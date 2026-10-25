"""Transporte MQTT S06. Importar/configurar no abre conexiones.

Un bucle externo atiende los sockets; un único trabajador abre TCP/TLS de uno
en uno. Cada intento crea un cliente limpio: Paho no conserva QoS 1 entre
conexiones. No se toca su cola privada ni se usa loop_start/loop_forever.
"""

from __future__ import annotations

from concurrent.futures import ThreadPoolExecutor
from dataclasses import dataclass, field
import hashlib
import json
import os
from pathlib import Path
import select
import ssl
import stat
from typing import Callable
import uuid

from rutautp_backend.simulation_ingress import SIMULATION_CONTROL_TOPIC
from rutautp_backend.simulation_models import canonical_uuid
from .clock import ClockSample
from .scenario import ActorObservation

CONTROL_KEYS = frozenset({"schemaVersion", "enabled", "runId", "controlRevision", "issuedAt",
                          "validUntil", "serviceEndsAt", "timeZone"})


def strict_json(raw: str | bytes):
    def pairs(items):
        result = {}
        for key, value in items:
            if key in result:
                raise ValueError("clave repetida")
            result[key] = value
        return result
    def invalid(_):
        raise ValueError("número JSON no finito")
    return json.loads(raw, object_pairs_hook=pairs, parse_constant=invalid)


@dataclass(frozen=True)
class Account:
    username: str
    password: str = field(repr=False)


@dataclass(frozen=True)
class BrokerSettings:
    host: str
    port: int
    tls: bool
    ca_file: str | None
    accounts: dict[str, Account] = field(repr=False)


def load_credentials(path: Path, principals: frozenset[str]) -> BrokerSettings:
    """Solo fichero regular privado del usuario; sin fallback a cuentas app/backend."""
    descriptor = os.open(path, os.O_RDONLY | getattr(os, "O_NOFOLLOW", 0))
    try:
        info = os.fstat(descriptor)
        if (not stat.S_ISREG(info.st_mode) or info.st_uid != os.getuid()
                or info.st_mode & 0o077 or info.st_size > 65536):
            raise ValueError("credenciales requieren fichero privado de hasta 64 KiB")
        with os.fdopen(descriptor, "rb", closefd=False) as source:
            body = strict_json(source.read(65537))
    finally:
        os.close(descriptor)
    if (not isinstance(body, dict) or set(body) != {"schemaVersion", "host", "port", "tls", "caFile", "accounts"}
            or type(body["schemaVersion"]) is not int or body["schemaVersion"] != 1
            or not isinstance(body["host"], str) or not body["host"].strip() or len(body["host"]) > 253
            or type(body["port"]) is not int or not 1 <= body["port"] <= 65535
            or type(body["tls"]) is not bool
            or body["caFile"] is not None and not isinstance(body["caFile"], str)
            or not isinstance(body["accounts"], dict) or set(body["accounts"]) != principals):
        raise ValueError('configuración de credenciales inválida; se requieren las cuentas exactas del perfil')
    accounts = {}
    for principal, entry in body["accounts"].items():
        if (not isinstance(entry, dict) or set(entry) != {"username", "password"}
                or entry["username"] != principal or not isinstance(entry["password"], str)
                or not entry["password"] or len(entry["password"]) > 4096):
            raise ValueError("cada cuenta debe autenticar exclusivamente su principal sim-NNN")
        accounts[principal] = Account(principal, entry["password"])
    if len({account.password for account in accounts.values()}) != len(accounts):
        raise ValueError('las cuentas del perfil requieren secretos distintos')
    return BrokerSettings(body["host"], body["port"], body["tls"], body["caFile"], accounts)


def parse_control(raw: bytes, now: float) -> dict:
    if len(raw) > 4096:
        raise ValueError("control demasiado grande")
    body = strict_json(raw)
    if (not isinstance(body, dict) or set(body) != CONTROL_KEYS
            or type(body["schemaVersion"]) is not int or body["schemaVersion"] != 1
            or type(body["enabled"]) is not bool or type(body["controlRevision"]) is not int
            or not 0 <= body["controlRevision"] <= 2**53 - 1
            or body["timeZone"] != "America/Lima"):
        raise ValueError("contrato de control inválido")
    for key in ("issuedAt", "validUntil", "serviceEndsAt"):
        value = body[key]
        if type(value) not in (int, float) or not 0 <= value < float("inf"):
            raise ValueError("fecha de control inválida")
    if body["runId"] is not None:
        canonical_uuid(body["runId"])
    if body["issuedAt"] > now:
        raise ValueError("control futuro")
    if body["enabled"]:
        if (body["runId"] is None or body["controlRevision"] == 0
                or not body["issuedAt"] < body["validUntil"] <= body["serviceEndsAt"]
                or body["validUntil"] - body["issuedAt"] > 15):
            raise ValueError("lease inválido")
    elif body["validUntil"] != body["issuedAt"]:
        raise ValueError("tombstone inválido")
    if body["controlRevision"] == 0 and body["runId"] is not None:
        raise ValueError("revisión inicial inválida")
    return body


def close_client(client) -> None:
    """Descarta también un PUBLISH parcial pendiente; nunca drena al apagar."""
    if client is None:
        return
    try:
        sock = client.socket()
        if sock is not None:
            sock.close()
    except (OSError, ValueError):
        pass
    try:
        client.disconnect()
    except (OSError, ValueError):
        pass


def paho_factory(settings: BrokerSettings) -> Callable:
    import paho.mqtt.client as mqtt
    context = ssl.create_default_context(cafile=settings.ca_file) if settings.tls else None
    def create(principal: str, client_id: str):
        client = mqtt.Client(callback_api_version=mqtt.CallbackAPIVersion.VERSION2,
                             client_id=client_id, clean_session=True, protocol=mqtt.MQTTv311,
                             reconnect_on_failure=False)
        client.username_pw_set(settings.accounts[principal].username, settings.accounts[principal].password)
        client.max_queued_messages_set(1)
        client.max_inflight_messages_set(1)
        client.connect_timeout = 2
        if context is not None:
            client.tls_set_context(context)
        return client
    return create


class SerialDialer:
    """Como máximo un connect en curso y ninguno en cola."""
    def __init__(self, settings: BrokerSettings):
        self.settings = settings
        self.executor = ThreadPoolExecutor(max_workers=1, thread_name_prefix="simulation-connect")
        self.future = None
        self.closed = False

    @property
    def busy(self):
        return self.future is not None and not self.future.done()

    def submit(self, client):
        if self.closed or self.busy:
            raise RuntimeError("conector ocupado/cerrado")
        def connect():
            try:
                return client.connect(self.settings.host, self.settings.port, keepalive=15)
            except Exception:
                close_client(client)
                raise
            finally:
                if self.closed:
                    close_client(client)
        self.future = self.executor.submit(connect)
        return self.future

    def close(self):
        self.closed = True
        self.executor.shutdown(wait=False, cancel_futures=True)


@dataclass
class Channel:
    principal: str
    retry_at: float
    client: object = None
    dialing: object = None
    connecting_at: float | None = None
    connected: bool = False
    subscribed: bool = False
    subscription_mid: int | None = None
    lease: dict | None = None
    pending: tuple[int, float, float] | None = None  # MID, monotónico, timestamp
    failures: int = 0
    attempts: int = 0


class MqttTransport:
    def __init__(self, principals: frozenset[str], run_id: str, revision: int,
                 settings: BrokerSettings, instance_id: str, *, client_factory=None, dialer=None):
        canonical_uuid(run_id)
        canonical_uuid(instance_id)
        if set(settings.accounts) != principals:
            raise ValueError("credenciales/perfil no coinciden")
        self.run_id, self.revision, self.instance_id = run_id, revision, instance_id
        self.create = client_factory or paho_factory(settings)
        self.dialer = dialer or SerialDialer(settings)
        self.channels = {p: Channel(p, 0) for p in sorted(principals)}
        self.sample = ClockSample(0, 0)
        self.revoked = False
        self.closed = False
        self.acknowledged = 0

    def _current(self, channel, client):
        return not self.closed and channel.client is client

    def _callbacks(self, channel: Channel, client):
        def on_connect(active, userdata, flags, reason, properties):
            if not self._current(channel, active):
                return
            if reason != 0:
                self.discard(channel.principal)
                return
            channel.connected = True
            result, mid = active.subscribe(SIMULATION_CONTROL_TOPIC, qos=1)
            if result != 0:
                self.discard(channel.principal)
            else:
                channel.subscription_mid = mid
        def on_subscribe(active, userdata, mid, reasons, properties):
            if self._current(channel, active) and mid == channel.subscription_mid:
                if reasons and all(reason == 1 for reason in reasons):
                    channel.subscribed = True
                else:
                    self.discard(channel.principal)
        def on_message(active, userdata, message):
            if not self._current(channel, active) or message.topic != SIMULATION_CONTROL_TOPIC:
                return
            try:
                body = parse_control(message.payload, self.sample.unix)
                if body["controlRevision"] < self.revision:
                    return
                if (body["controlRevision"] != self.revision or not body["enabled"]
                        or body["runId"] != self.run_id):
                    self.revoked = True
                    return
                previous = channel.lease
                if previous and body["issuedAt"] < previous["issuedAt"]:
                    return
                if previous and body["issuedAt"] == previous["issuedAt"] and body != previous:
                    raise ValueError("lease contradictorio")
                channel.lease = body
            except (ValueError, TypeError, UnicodeError):
                self.discard(channel.principal)
        def on_disconnect(active, userdata, flags, reason, properties):
            if self._current(channel, active):
                self.discard(channel.principal)
        def on_publish(active, userdata, mid, reason, properties):
            if self._current(channel, active) and channel.pending and channel.pending[0] == mid:
                channel.pending = None
                channel.failures = 0
                self.acknowledged += 1
        client.on_connect, client.on_subscribe, client.on_message = on_connect, on_subscribe, on_message
        client.on_disconnect, client.on_publish = on_disconnect, on_publish

    def discard(self, principal: str):
        channel = self.channels[principal]
        client, future = channel.client, channel.dialing
        channel.client = channel.dialing = None
        channel.connected = channel.subscribed = False
        channel.lease = channel.pending = channel.connecting_at = None
        channel.subscription_mid = None
        base = min(60, 2 ** min(channel.failures, 6))
        noise = int.from_bytes(hashlib.sha256(
            f"{self.run_id}:{principal}:{channel.failures}".encode()).digest()[:8], "big") / 2**64
        delay = base + noise * min(.25, 60 - base)
        channel.failures += 1
        channel.retry_at = self.sample.monotonic + delay
        # No tocar un cliente mientras connect trabaja sobre él. Al finalizar,
        # el callback solo cierra su socket; nunca acepta callbacks/publica.
        if future is not None and not future.done():
            future.add_done_callback(lambda _: close_client(client))
        else:
            close_client(client)

    def ready(self, principal: str, sample: ClockSample) -> bool:
        channel = self.channels[principal]
        lease = channel.lease
        return bool(not self.closed and not self.revoked and channel.connected and channel.subscribed
                    and channel.pending is None and lease and lease["issuedAt"] <= sample.unix
                    < min(lease["validUntil"], lease["serviceEndsAt"]))

    def discard_pending_publications(self):
        """Corta observaciones pendientes; conserva conexiones sin datos en cola.

        Una lectura local ocupada impide publicar ese tick. Desconectar también
        clientes ociosos acumularía backoff en toda la flota por cada contención.
        El siguiente tick debe validar autoridad y lease antes de servir sockets.
        """
        for channel in self.channels.values():
            if channel.pending is not None:
                self.discard(channel.principal)

    def service(self, sample: ClockSample):
        """Sin espera: lee primero; comprueba caducidad antes de escribir sockets."""
        self.sample = sample
        if self.closed:
            return
        for channel in self.channels.values():
            if channel.dialing is not None and channel.dialing.done():
                future, channel.dialing = channel.dialing, None
                try:
                    if future.result() != 0:
                        self.discard(channel.principal)
                except Exception:
                    self.discard(channel.principal)
            expired = channel.pending and (sample.monotonic - channel.pending[1] >= 10
                                            or sample.unix - channel.pending[2] >= 10)
            lease_expired = channel.lease and sample.unix >= min(channel.lease["validUntil"], channel.lease["serviceEndsAt"])
            timeout = channel.connecting_at is not None and not channel.subscribed and sample.monotonic - channel.connecting_at >= 10
            if channel.client is not None and (expired or lease_expired or timeout):
                self.discard(channel.principal)
        sockets = {}
        for channel in self.channels.values():
            if channel.client is not None and channel.dialing is None:
                sock = channel.client.socket()
                if sock is not None:
                    sockets[sock] = channel
        try:
            readable, _, _ = select.select(list(sockets), [], [], 0) if sockets else ([], [], [])
            readable = set(readable) | {sock for sock in sockets if isinstance(sock, ssl.SSLSocket) and sock.pending()}
            for sock in readable:
                channel = sockets[sock]
                if channel.client is not None and channel.client.loop_read() != 0:
                    self.discard(channel.principal)
            if self.revoked:
                self.close()
                return
            for channel in self.channels.values():
                client = channel.client
                if client is not None and channel.dialing is None:
                    if client.loop_misc() != 0:
                        self.discard(channel.principal)
                    elif self._current(channel, client) and client.want_write() and client.loop_write() != 0:
                        self.discard(channel.principal)
        except (OSError, ValueError):
            # Socket sustituido/cerrado durante callback: descartar, no reintentar
            # el paquete del cliente que acaba de fallar.
            for channel in self.channels.values():
                if channel.client is not None and channel.dialing is None:
                    self.discard(channel.principal)

    def ensure_connections(self, active: set[str], sample: ClockSample):
        self.sample = sample
        if self.closed or self.revoked or self.dialer.busy:
            return
        candidates = [c for p, c in self.channels.items() if p in active and c.client is None
                      and sample.monotonic >= c.retry_at]
        if not candidates:
            return
        channel = min(candidates, key=lambda c: (c.attempts, c.retry_at, c.principal))
        channel.attempts += 1
        client_id = f"s{uuid.uuid4().hex[:15]}{channel.principal[-3:]}"  # 19 ASCII, nuevo por intento
        client = self.create(channel.principal, client_id)
        channel.client, channel.connecting_at = client, sample.monotonic
        self._callbacks(channel, client)
        try:
            channel.dialing = self.dialer.submit(client)
        except Exception:
            self.discard(channel.principal)

    def publish(self, observation: ActorObservation, sample: ClockSample) -> bool:
        if (observation.principal not in self.channels or not self.ready(observation.principal, sample)
                or not 0 <= sample.unix - observation.timestamp < 10):
            return False
        canonical_uuid(observation.session_id)
        channel = self.channels[observation.principal]
        topic = f"rutautp/simulacion/{self.run_id}/observaciones/{observation.principal}/{observation.session_id}/posicion"
        raw = json.dumps(observation.payload(), allow_nan=False, separators=(",", ":"))
        try:
            info = channel.client.publish(topic, raw, qos=1, retain=False)
            if info.rc != 0:
                self.discard(observation.principal)
                return False
            channel.pending = (info.mid, sample.monotonic, observation.timestamp)
            return True
        except (OSError, ValueError):
            self.discard(observation.principal)
            return False

    def counts(self) -> dict:
        return {"connections": sum(c.connected for c in self.channels.values()),
                "readyActors": sum(self.ready(p, self.sample) for p in self.channels),
                "inflight": sum(c.pending is not None for c in self.channels.values()),
                "publishAcks": self.acknowledged}

    def close(self):
        if self.closed:
            return
        self.closed = True
        for principal in self.channels:
            self.discard(principal)
        self.dialer.close()
