"""Planificador central S06: autoridad, referencia durable, cadencia y presupuesto."""

from __future__ import annotations

import fcntl
import hashlib
import json
import os
from pathlib import Path
import stat
from typing import TextIO
import uuid

from rutautp_backend.persistence import ObservationStore, SimulationPersistenceUnavailable
from rutautp_backend.simulation_control_store import ControlBusy, ControlStore, ControlUnavailable
from rutautp_backend.simulation_profile import SimulationProfile, PROFILE_SPECS
from .clock import ClockDiscontinuity, ClockGuard, ClockSample, RealtimeClock
from .publisher import MqttTransport
from .scenario import ScenarioEngine, ScenarioFrame


class ProducerStopped(RuntimeError):
    pass


class ProducerLock:
    """Una instancia por base de control (más estricto que una por run)."""
    def __init__(self, control: ControlStore):
        control.read()  # verifica rutas/propietario/revisión antes de crear el lock
        self.path = control.path.with_suffix(control.path.suffix + ".producer-lock")
        self.fd = os.open(self.path, os.O_RDWR | os.O_CREAT | getattr(os, "O_NOFOLLOW", 0), 0o600)
        try:
            held = os.fstat(self.fd)
            if not stat.S_ISREG(held.st_mode) or held.st_uid != os.getuid() or held.st_mode & 0o077:
                raise ControlUnavailable("lock de productor no privado")
            fcntl.flock(self.fd, fcntl.LOCK_EX | fcntl.LOCK_NB)
        except (OSError, ControlUnavailable) as error:
            os.close(self.fd)
            self.fd = None
            raise ControlUnavailable("ya hay un productor o su lock no está disponible") from error

    def check(self):
        if self.fd is None:
            raise ProducerStopped("producer_lock_closed")
        held, current = os.fstat(self.fd), self.path.lstat()
        if (held.st_dev, held.st_ino) != (current.st_dev, current.st_ino):
            raise ProducerStopped("producer_lock_replaced")

    def close(self):
        if self.fd is not None:
            os.close(self.fd)
            self.fd = None
        # Nunca unlink: otro proceso podría estar esperando sobre el mismo inode.


class LocalAuthority:
    def __init__(self, control: ControlStore, profile: SimulationProfile, run_id: str,
                 revision: int, owner: str, gtfs_dir: Path):
        self.control, self.profile = control, profile
        self.run_id, self.revision, self.owner, self.gtfs_dir = run_id, revision, owner, gtfs_dir

    def current(self, sample: ClockSample) -> dict:
        state = self.control.read()
        if (not state["enabled"] or state["runId"] != self.run_id or state["revision"] != self.revision
                or state["owner"] != self.owner or state["profile"] != self.profile.pinned()):
            raise ProducerStopped("control_revoked_or_changed")
        inside, day, closes = self.profile.window(sample.unix)
        if (not inside or state["serviceDate"] != day or state["serviceEndsAt"] != closes
                or state["runStartedAt"] is None or not state["runStartedAt"] <= sample.unix
                < state["runStartedAt"] + self.profile.max_run_seconds):
            raise ProducerStopped("outside_service_or_run_duration")
        if self.profile.signatures(self.gtfs_dir) != self.profile.verified_signatures:
            raise ProducerStopped("profile_or_feed_changed")
        runtime = self.control.runtime()
        if (runtime.get("backendInstance") != self.owner or runtime.get("appliedRevision") != self.revision
                or runtime.get("lastAckedRevision") != self.revision):
            raise ProducerStopped("backend_or_control_not_applied")
        for field in ("backendSeenAt", "lastAckedAt"):
            stamp = runtime.get(field)
            if type(stamp) not in (int, float) or not 0 <= sample.unix - stamp < 15:
                raise ProducerStopped("backend_or_puback_expired")
        return state


def validate_publication(profile: SimulationProfile):
    manifest = json.loads(profile.raw)
    publication = manifest["publication"]
    expected = {"qos": 1, "retained": False, "minimumIntervalSeconds": 5,
                "positiveJitterMaxSeconds": .25, "phaseWindowSeconds": 5,
                "maxQueuedMessagesPerActor": 1, "maxInflightMessagesPerActor": 1,
                "maxMessageAgeSeconds": 10, "reconnectBackoffSeconds": {"min": 1, "max": 60}}
    if (profile.name not in PROFILE_SPECS or publication != expected
            or len(profile.principals) != PROFILE_SPECS[profile.name][0]):
        raise ValueError('contrato de publicación no coincide con el perfil preparado')
    for key in ("maxObservationPublishCallsPerRun", "maxObservationPublishCallsPerDay"):
        maximum = PROFILE_SPECS[profile.name][3] if key.endswith('PerRun') else 6000
        if type(manifest["limits"][key]) is not int or not 1 <= manifest["limits"][key] <= maximum:
            raise ValueError("presupuesto inicial inválido")


class ActorRunner:
    def __init__(self, engine: ScenarioEngine, control: ControlStore, history: ObservationStore,
                 transport: MqttTransport, authority: LocalAuthority, instance_id: str,
                 lock: ProducerLock, *, reference: TextIO | None = None, clock=None):
        validate_publication(engine.profile)
        if engine.run_id != authority.run_id or engine.run_id != transport.run_id:
            raise ValueError("run del motor/control/transporte no coincide")
        self.engine, self.control, self.history = engine, control, history
        self.manifest = json.loads(engine.profile.raw)
        self.transport, self.authority, self.instance_id, self.lock = transport, authority, instance_id, lock
        self.reference = reference
        self.clock = clock
        self.guard = ClockGuard()
        self.next_due: dict[str, float] = {}
        self.sessions: dict[str, str] = {}
        self.calls = 0
        self.day_calls = 0
        self.active_actors = 0
        self.stopped = False
        self.reason = "not_started"
        self._claimed = False
        self._reference_header = False
        self._last_status = float("-inf")
        self._last_sample = None

    def _events(self, frame: ScenarioFrame):
        for event in frame.events:
            if event.kind == "board":
                self.history.record_simulation_actor(event.boarding_record(self.engine.run_id))
            elif event.kind == "leave":
                self.history.end_simulation_actor(self.engine.run_id, event.session_id, event.at, reason=event.reason)
        if not self.history.flush():
            raise SimulationPersistenceUnavailable("no se confirmaron los abordajes/cierres")

    def _reference(self, frame: ScenarioFrame):
        if self.reference is not None:
            self.engine.write_reference(self.reference, frame, include_header=not self._reference_header)
            self.reference.flush()
            self._reference_header = True

    def _status(self, sample: ClockSample, *, force=False):
        if not force and sample.monotonic - self._last_status < 5:
            return
        self.control.runtime(producer={"status": "stopped" if self.stopped else "running",
            "instance": self.instance_id, "runId": self.engine.run_id, "controlRevision": self.authority.revision,
            "seenAt": sample.unix, "reason": self.reason, "actors": self.active_actors,
            "nominalVehicles": len(self.manifest["vehicles"]),
            "reservedPublishCallsRun": self.calls, "reservedPublishCallsDay": self.day_calls,
            **self.transport.counts()})
        self._last_status = sample.monotonic

    def _jitter(self, principal: str, turn: float) -> float:
        raw = hashlib.sha256(f"{self.engine.profile.seed}:{principal}:{turn:.9f}".encode()).digest()
        return .000001 + int.from_bytes(raw[:8], "big") / (2**64) * (.25 - .000001)

    def step(self, sample: ClockSample) -> bool:
        """Un tick; nunca recorre plazos atrasados ni almacena muestras para después."""
        if self.stopped:
            return False
        self._last_sample = sample
        try:
            self.guard.elapsed(sample)
            self.lock.check()
            state = self.authority.current(sample)
            self.history.require_simulation_run(self.engine.run_id)
            if not self._claimed:
                self.control.claim_producer(self.engine.run_id, self.authority.revision,
                    self.authority.owner, self.instance_id, sample.unix)
                self._claimed = True
                for index, principal in enumerate(sorted(self.engine.profile.principals)):
                    self.next_due[principal] = sample.monotonic + index * 5 / len(self.engine.profile.principals) + self._jitter(principal, 0)
            self.transport.service(sample)
            if self.transport.revoked:
                raise ProducerStopped("mqtt_control_revoked")
            frame = self.engine.advance(sample)
            self._events(frame)  # commit antes de dar al broker un sessionId nuevo
            self._reference(frame)
            if frame.state != "running":
                raise ProducerStopped(frame.reason or frame.state)
            active = {observation.principal for observation in frame.observations}
            self.active_actors = len(active)
            for principal in set(self.sessions) - active:
                self.transport.discard(principal)
                del self.sessions[principal]
            for observation in frame.observations:
                principal = observation.principal
                previous = self.sessions.get(principal)
                if previous is not None and previous != observation.session_id:
                    self.transport.discard(principal)
                self.sessions[principal] = observation.session_id
                if sample.monotonic < self.next_due[principal]:
                    continue
                # La cadencia se mide entre intentos, también si faltó conexión,
                # ACK o control. Jamás publicar una ráfaga al volver la red.
                self.next_due[principal] = sample.monotonic + 5 + self._jitter(principal, sample.monotonic)
                if not self.transport.ready(principal, sample):
                    continue
                state = self.authority.current(sample)
                limits = self.manifest["limits"]
                self.calls, self.day_calls = self.control.reserve_publish(
                    self.engine.run_id, self.authority.revision, self.authority.owner, self.instance_id,
                    state["serviceDate"], max_run=limits["maxObservationPublishCallsPerRun"],
                    max_day=limits["maxObservationPublishCallsPerDay"])
                fresh = self.clock.read() if self.clock is not None else sample
                self._last_sample = fresh
                self.guard.elapsed(fresh)
                self.lock.check()
                self.authority.current(fresh)  # disable durante reserva: consumirla, no emitir
                if not 0 <= fresh.unix - observation.timestamp < 10:
                    raise ProducerStopped("observation_expired_during_storage")
                self.next_due[principal] = fresh.monotonic + 5 + self._jitter(principal, fresh.monotonic)
                self.transport.publish(observation, fresh)
            self.transport.ensure_connections(active, sample)
            self.reason = "active"
            self._status(sample)
            return True
        except ControlBusy:
            # No servir sockets ni publicar sin verificar el permiso. Descartar
            # observaciones pendientes sin penalizar conexiones que están ociosas.
            self.transport.discard_pending_publications()
            return True
        except (ProducerStopped, ClockDiscontinuity, ControlUnavailable,
                SimulationPersistenceUnavailable, OSError, ValueError, TypeError, KeyError) as error:
            reason = str(error) if isinstance(error, (ProducerStopped, ClockDiscontinuity)) else type(error).__name__
            self.stop(self._last_sample, reason)
            return False

    def stop(self, sample: ClockSample, reason: str = "operator_stop"):
        if self.stopped:
            return
        self.stopped, self.reason, self.active_actors = True, reason, 0
        self.transport.close()  # primero cortar sockets/colas, después guardar
        frame = self.engine.stop(sample, reason, paused=reason != "operator_stop")
        incomplete = isinstance(reason, str) and reason == "SimulationPersistenceUnavailable"
        try:
            self._events(frame)
            self._reference(frame)
        except (SimulationPersistenceUnavailable, OSError, ValueError):
            self.reason += ":history_or_reference_incomplete"
            incomplete = True
        try:
            # Evita reiniciar el mismo run tras señal, suspensión o presupuesto.
            self.control.disable(sample.unix, "producer_history_incomplete" if incomplete else "producer:" + self.reason[:240],
                                 expected_revision=self.authority.revision)
        except ControlUnavailable:
            pass  # faltando control se corta localmente; los leases caducan
        try:
            self._status(sample, force=True)
        except ControlUnavailable:
            pass
        finally:
            self.lock.close()

    def run(self, stop_event, *, clock=None):
        clock = clock or self.clock or RealtimeClock()
        self.clock = clock
        try:
            while not stop_event.is_set():
                if not self.step(clock.read()):
                    break
                stop_event.wait(.1)
        finally:
            self.stop(clock.read(), "operator_stop")


def new_instance_id() -> str:
    return str(uuid.uuid4())
