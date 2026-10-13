"""Registro privado MQTT, preferencias persistidas y proveedor APNs HTTP/2.

No publica tokens en snapshots ni los escribe en logs. La identidad la impone
la ACL del broker, nunca un campo del JSON. El worker no bloquea la red MQTT.
"""
from __future__ import annotations

import json
import logging
import math
import re
import sqlite3
import threading
import time
import uuid
from datetime import datetime
from pathlib import Path
from zoneinfo import ZoneInfo, ZoneInfoNotFoundError

from .config import ConfigError
from .push_config import PushConfig

REGISTER_TOPIC = "rutautp/notificaciones/+/registro"
LEASE_SECONDS = 30 * 86400
logger = logging.getLogger(__name__)


def permits(settings: dict, now: float) -> bool:
    if not settings["enabled"] or now < (settings["pauseUntil"] or 0):
        return False
    local = datetime.fromtimestamp(now, ZoneInfo(settings["timeZone"]))
    # Swift Calendar: domingo=1; Python datetime: lunes=0.
    if (local.weekday() + 1) % 7 + 1 in settings["mutedDays"]:
        return False
    if not settings["quietHours"]:
        return True
    minute = local.hour * 60 + local.minute
    start, end = settings["quietStart"], settings["quietEnd"]
    if start == end:
        return False
    return not (start <= minute < end if start < end else minute >= start or minute < end)


class APNsProvider:
    def __init__(self, config: PushConfig):
        try:
            import httpx
            import jwt
            from cryptography.hazmat.primitives.serialization import load_pem_private_key
            from cryptography.hazmat.primitives.asymmetric.ec import EllipticCurvePrivateKey, SECP256R1
            key = load_pem_private_key(Path(config.key_path).read_bytes(), password=None)
            if not isinstance(key, EllipticCurvePrivateKey) or not isinstance(key.curve, SECP256R1):
                raise ValueError("clave incompatible")
        except (ImportError, OSError, ValueError, TypeError) as error:
            # No incluir la clave, token o texto de una excepcion HTTP en logs.
            raise ConfigError("APNs necesita requirements-push.txt y una clave Apple P-256 valida") from None
        self.config = config
        self.httpx = httpx
        self.jwt = jwt
        self.key = key
        self.client = httpx.Client(http2=True, timeout=5.0, trust_env=False)
        self.authorization = ""
        self.issued_at = 0

    def send(self, token: str, event: dict, settings: dict) -> str:
        now = time.time()
        if not self.authorization or not 0 <= now - self.issued_at < 3000:
            self.issued_at = int(now)
            self.authorization = self.jwt.encode(
                {"iss": self.config.team_id, "iat": self.issued_at}, self.key,
                algorithm="ES256", headers={"kid": self.config.key_id},
            )
        # Textos del mismo catalogo que la app; no nombres de lugares inventados.
        texts = PUSH_TEXTS[settings["language"]]
        payload = {
            "aps": {"alert": {"title": texts[0], "body": texts[1].format(event["routeName"])},
                    "thread-id": "rutautp.cambios"},
            "rutaUTP": {"schemaVersion": 1, "kind": "routeChange", "eventID": event["id"],
                        "routeID": event["routeId"], "expiresAt": event["expiresAt"]},
        }
        if settings["sound"]:
            payload["aps"]["sound"] = "default"
        host = "api.sandbox.push.apple.com" if self.config.environment == "development" else "api.push.apple.com"
        headers = {"authorization": "bearer " + self.authorization, "apns-topic": self.config.topic,
                   "apns-push-type": "alert", "apns-priority": "10",
                   "apns-expiration": str(int(event["expiresAt"])),
                   "apns-collapse-id": event["id"], "apns-id": event["deliveryID"]}
        try:
            response = self.client.post(f"https://{host}/3/device/{token}", headers=headers, json=payload)
        except self.httpx.HTTPError:
            # Resultado incierto: Apple puede haberlo aceptado. No reenviar y
            # producir un duplicado tras un timeout o un reinicio del servidor.
            return "uncertain"
        if response.http_version != "HTTP/2":
            return "provider_error"
        if response.status_code == 200:
            return "accepted"
        reason = ""
        try:
            reason = response.json().get("reason", "")
        except (ValueError, AttributeError):
            pass
        if response.status_code == 410 or reason in ("BadDeviceToken", "DeviceTokenNotForTopic", "Unregistered"):
            return "invalid_token"
        if response.status_code in (429, 500, 503):
            return "retry"
        return "provider_error"

    def close(self):
        self.client.close()


PUSH_TEXTS = {
    "es": ("Cambio reportado por la comunidad", "Dos o más usuarios reportan un cambio en {}. Abre RutaUTP para consultar el estado actual."),
    "en": ("Community route report", "Two or more users report a change on {}. Open RutaUTP to check the current status."),
    "fr": ("Changement signalé par la communauté", "Au moins deux utilisateurs signalent un changement sur {}. Ouvrez RutaUTP pour consulter l’état actuel."),
    "pt-BR": ("Mudança relatada pela comunidade", "Dois ou mais usuários relatam uma mudança na {}. Abra o RutaUTP para consultar a situação atual."),
    "de": ("Routenänderung aus der Community", "Mindestens zwei Nutzer melden eine Änderung auf {}. Öffne RutaUTP, um den aktuellen Stand zu prüfen."),
    "zh-Hans": ("社区报告的线路变化", "至少两名用户报告 {} 有变化。打开 RutaUTP 查看当前情况。"),
}


class PushService:
    def __init__(self, config: PushConfig, feed):
        self.config = config
        self.feed = feed
        self.provider = APNsProvider(config) if config.enabled else None
        path = Path(config.database_path)
        path.parent.mkdir(parents=True, exist_ok=True)
        self.db = sqlite3.connect(str(path), check_same_thread=False, timeout=5)
        # SQLite conserva tokens: desplegar /data y sus copias con acceso privado.
        path.chmod(0o600)
        self.db.execute("PRAGMA journal_mode=WAL")
        self.db.executescript("""
            CREATE TABLE IF NOT EXISTS devices (
              principal TEXT, device TEXT, revision INTEGER, body TEXT, added TEXT,
              lease REAL, PRIMARY KEY(principal, device));
            CREATE TABLE IF NOT EXISTS deliveries (
              principal TEXT, device TEXT, event TEXT, body TEXT, state TEXT,
              due REAL, attempts INTEGER, expires REAL,
              PRIMARY KEY(principal, device, event));
            UPDATE deliveries SET state='uncertain' WHERE state='sending';
            UPDATE deliveries SET state='skipped' WHERE state='pending';
        """)
        self.db.commit()
        self.lock = threading.RLock()
        self.stop_event = threading.Event()
        self.wake = threading.Event()
        self.thread = None
        self.last_cleanup = 0.0
        self.provider_failed = False
        self.seen_events = set()
        self.last_observe = 0.0

    @property
    def ready(self):
        return self.provider is not None and not self.provider_failed

    def start(self):
        if self.provider:
            self.thread = threading.Thread(target=self._run, name="rutautp-apns", daemon=True)
            self.thread.start()

    def register(self, topic: str, payload, now: float):
        match = re.fullmatch(r"rutautp/notificaciones/([^/+#\x00]{1,128})/registro", topic)
        if not match or len(payload) > 32768:
            return None
        principal = match[1]
        receipt = None
        try:
            body = json.loads(payload)
            request = str(uuid.UUID(body["requestID"]))
            device = str(uuid.UUID(body["deviceID"]))
            revision = body["revision"]
            receipt = {"requestID": body["requestID"], "revision": revision, "accepted": False,
                       "providerReady": self.ready, "code": "invalid", "leaseUntil": 0}
            if (request.lower() != body["requestID"].lower() or device.lower() != body["deviceID"].lower()
                or type(revision) is not int or not 1 <= revision <= 9007199254740991
                or type(body.get("schemaVersion")) is not int or body["schemaVersion"] != 1
                or type(body["timestamp"]) not in (int, float) or not math.isfinite(body["timestamp"])
                or not -10 <= now - body["timestamp"] <= 120
                or any(type(body[k]) is not bool for k in ("enabled", "quietHours", "sound"))
                or body["language"] not in PUSH_TEXTS
                or body["environment"] not in ("development", "production")
                or any(type(body[k]) is not int or not 0 <= body[k] < 1440 for k in ("quietStart", "quietEnd"))):
                return principal, receipt
            zone = body["timeZone"]
            if not isinstance(zone, str) or len(zone) > 128:
                return principal, receipt
            ZoneInfo(zone)
            pause = body["pauseUntil"]
            if pause is not None and (type(pause) not in (int, float) or not math.isfinite(pause) or not 0 <= pause < 4102444800):
                return principal, receipt
            days, routes = body["mutedDays"], body["routes"]
            if (not isinstance(days, list) or len(days) > 7 or any(type(d) is not int or not 1 <= d <= 7 for d in days)
                or not isinstance(routes, list) or len(routes) > 100
                or any(not isinstance(r, str) or len(r) > 128 or self.feed.get(r) is None for r in routes)):
                return principal, receipt
            token = body.get("token", "")
            if not isinstance(token, str) or (token and (not re.fullmatch(r"[0-9a-f]{2,2048}", token) or len(token) % 2 != 0)) or (body["enabled"] and not token):
                return principal, receipt
            if body["environment"] != self.config.environment and self.config.enabled:
                receipt["code"] = "environment"
                return principal, receipt
            # Unicamente se persisten campos del contrato, nunca campos arbitrarios.
            fields = ("enabled", "quietHours", "sound", "language", "environment", "quietStart",
                      "quietEnd", "timeZone", "pauseUntil", "mutedDays", "routes", "token")
            clean = {k: body.get(k, "") for k in fields}
            with self.lock:
                previous = self.db.execute("SELECT revision,body,added FROM devices WHERE principal=? AND device=?", (principal, device)).fetchone()
                if previous and revision < previous[0]:
                    receipt["code"] = "stale"
                    return principal, receipt
                old = json.loads(previous[1]) if previous else {}
                if previous and revision == previous[0] and old != clean:
                    receipt["code"] = "stale"
                    return principal, receipt
                if not previous and (self.db.execute("SELECT COUNT(*) FROM devices WHERE principal=?", (principal,)).fetchone()[0] >= 8
                                     or self.db.execute("SELECT COUNT(*) FROM devices").fetchone()[0] >= 10000):
                    receipt["code"] = "busy"
                    return principal, receipt
                added_before = json.loads(previous[2]) if previous and old.get("enabled") and clean["enabled"] else {}
                added = {r: added_before.get(r, now) for r in set(routes)}
                # Un token nuevo no recibe sucesos que preceden a su registro.
                if token != old.get("token"):
                    added = {r: now for r in set(routes)}
                lease = now + LEASE_SECONDS
                self.db.execute("INSERT OR REPLACE INTO devices VALUES (?,?,?,?,?,?)",
                                (principal, device, revision, json.dumps(clean), json.dumps(added), lease))
                # Invalida tareas anteriores de esta instalacion. Los eventos
                # omitidos no se acumulan para cuando se reactive o cambie horario.
                if old != clean:
                    self.db.execute("UPDATE deliveries SET state='skipped' WHERE principal=? AND device=? AND state='pending'",
                                    (principal, device))
                self.db.commit()
            receipt.update(accepted=True, code="saved", leaseUntil=lease)
            return principal, receipt
        except (ValueError, TypeError, KeyError, AttributeError, UnicodeDecodeError, RecursionError, ZoneInfoNotFoundError):
            return (principal, receipt) if receipt else None

    def observe(self, alerts: list, now: float):
        if now - self.last_observe < 5:
            return
        self.last_observe = now
        with self.lock:
            if now - self.last_cleanup >= 60:
                self.db.execute("DELETE FROM devices WHERE lease<=?", (now,))
                self.db.execute("DELETE FROM deliveries WHERE expires<?", (now - 86400,))
                self.db.commit()
                self.last_cleanup = now
        if not self.ready:
            return
        ids = {a["id"] for a in alerts}
        fresh = [a for a in alerts if a["id"] not in self.seen_events]
        self.seen_events = ids
        with self.lock:
            # Si se pierde el quorum o desaparece el reporte, cancelar su cola.
            for row in self.db.execute("SELECT DISTINCT event FROM deliveries WHERE state='pending'").fetchall():
                if row[0] not in ids:
                    self.db.execute("UPDATE deliveries SET state='skipped' WHERE event=? AND state='pending'", row)
            devices = self.db.execute("SELECT principal,device,body,added,lease FROM devices WHERE lease>?", (now,)).fetchall()
            for principal, device, raw, added_raw, lease in devices:
                settings, added = json.loads(raw), json.loads(added_raw)
                if settings["environment"] != self.config.environment:
                    continue
                for alert in fresh:
                    if alert["routeId"] not in added or alert["confirmedAt"] < added[alert["routeId"]]:
                        continue
                    event = {"id": alert["id"], "routeId": alert["routeId"], "expiresAt": alert["expiresAt"],
                             "routeName": (self.feed.get(alert["routeId"]).linea + " " + self.feed.get(alert["routeId"]).variante).strip()[:120],
                             "deliveryID": str(uuid.uuid4())}
                    state = "pending" if permits(settings, now) and permits(settings, alert["confirmedAt"]) and settings["token"] else "skipped"
                    self.db.execute("INSERT OR IGNORE INTO deliveries VALUES (?,?,?,?,?,?,?,?)",
                                    (principal, device, alert["id"], json.dumps(event), state, now, 0, alert["expiresAt"]))
            self.db.commit()
        self.wake.set()

    def _run(self):
        while not self.stop_event.is_set():
            try:
                while not self.stop_event.is_set() and self.ready and self._send_one():
                    pass
            except Exception:
                # No volcar excepciones que puedan contener URLs con tokens.
                self.provider_failed = True
                logger.error("APNs detenido por un error interno; revisar configuracion y reiniciar")
            self.wake.wait(1)
            self.wake.clear()

    def _send_one(self):
        now = time.time()
        with self.lock:
            row = self.db.execute("SELECT principal,device,event,body,attempts,expires FROM deliveries WHERE state='pending' AND due<=? ORDER BY due LIMIT 1", (now,)).fetchone()
            if not row:
                return False
            principal, device, event_id, raw, attempts, expires = row
            key = (principal, device, event_id)
            registration = self.db.execute("SELECT body,lease FROM devices WHERE principal=? AND device=?", (principal, device)).fetchone()
            settings = json.loads(registration[0]) if registration else None
            if (expires <= now or not registration or registration[1] <= now or not permits(settings, now)
                or event_id is None or json.loads(raw)["routeId"] not in settings["routes"] or not settings["token"]):
                self.db.execute("UPDATE deliveries SET state='skipped' WHERE principal=? AND device=? AND event=?", key)
                self.db.commit()
                return True
            self.db.execute("UPDATE deliveries SET state='sending',attempts=attempts+1 WHERE principal=? AND device=? AND event=?", key)
            self.db.commit()
        result = self.provider.send(settings["token"], json.loads(raw), settings)
        with self.lock:
            # Solo se reintentan rechazos explicitos temporales de Apple.
            retry = result == "retry" and attempts < 3 and expires > time.time() + 30
            self.db.execute("UPDATE deliveries SET state=?,due=? WHERE principal=? AND device=? AND event=?",
                            ("pending" if retry else result, time.time() + 30 * 2 ** attempts, *key))
            if result == "invalid_token":
                current = self.db.execute("SELECT body FROM devices WHERE principal=? AND device=?", (principal, device)).fetchone()
                if current:
                    updated = json.loads(current[0])
                    if updated["token"] == settings["token"]:
                        updated["enabled"] = False
                        updated["token"] = ""
                        self.db.execute("UPDATE devices SET body=? WHERE principal=? AND device=?", (json.dumps(updated), principal, device))
            if result == "provider_error":
                self.provider_failed = True
                logger.error("APNs rechazo la configuracion del proveedor; envio detenido")
            self.db.commit()
        return True

    def close(self):
        self.stop_event.set()
        self.wake.set()
        if self.thread:
            self.thread.join(timeout=10)
        # El cliente HTTP y SQLite nunca se cierran mientras el worker los usa.
        if not self.thread or not self.thread.is_alive():
            if self.provider:
                self.provider.close()
            self.db.close()
