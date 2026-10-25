"""Control privado S04: horario, generaciones, revisión durable y lease MQTT.

No arranca actores. El permiso del backend requiere PUBACK del estado vigente;
el acuse del broker no demuestra recepción o retirada en todos los teléfonos.
"""

from __future__ import annotations

import json
import logging
import os
from pathlib import Path
import time
from typing import Callable
import uuid

from .persistence import ObservationStore, SimulationPersistenceUnavailable
from .simulation_control_store import ControlBusy, ControlStore, ControlUnavailable
from .simulation_ingress import SIMULATION_CONTROL_TOPIC, SimulationAdmission
from .simulation_models import SimulationRunRecord, SimulationRunStatus, finite_time
from .simulation_profile import SimulationProfile

logger = logging.getLogger(__name__)
ControlPublisher = Callable[[str, str], int | None]


class SimulationController:
    def __init__(self, control: ControlStore, history: ObservationStore, gtfs_dir: Path,
                 *, monotonic_clock: Callable[[], float] = time.monotonic) -> None:
        self.control, self.history, self.gtfs_dir = control, history, Path(gtfs_dir)
        self._owner_fd = control.acquire_backend()
        self.instance_id = str(uuid.uuid4())
        self.monotonic = monotonic_clock
        self.error: str | None = None
        self._highest_revision = 0
        self._profile: SimulationProfile | None = None
        self._profile_revision = 0
        self._signatures: tuple | None = None
        self._clock_sample: tuple[float, float] | None = None
        self._lease: dict | None = None
        self._pending: dict[int, tuple[dict, float]] = {}
        self._last_attempt: tuple[int, float] | None = None
        self._last_runtime_at = float("-inf")
        self._applied_revision = 0
        self._last_closed_run: str | None = None
        self._awaiting_ack_since: float | None = None
        self._closed = False

    def _read(self) -> dict:
        held = os.fstat(self._owner_fd)
        current = self.control.owner_lock.stat()
        if (held.st_dev, held.st_ino) != (current.st_dev, current.st_ino):
            raise ControlUnavailable("se reemplazó el lock del controlador")
        state = self.control.read()
        if state["revision"] < self._highest_revision:
            raise ControlUnavailable("revisión regresiva durante la ejecución")
        self._highest_revision = state["revision"]
        return state

    def _clock_ok(self, now: float) -> bool:
        finite_time(now)
        mono = self.monotonic()
        finite_time(mono)
        previous = self._clock_sample
        self._clock_sample = (now, mono)
        if previous is None:
            return True
        wall_delta, mono_delta = now - previous[0], mono - previous[1]
        return mono_delta >= 0 and mono_delta <= 15 and abs(wall_delta - mono_delta) <= 2

    def _finish_run(self, run_id: str | None, now: float, reason: str, *, failed: bool = False) -> None:
        if run_id is None or run_id == self._last_closed_run:
            return
        try:
            self.history.require_simulation_persistence()
            rows = self.history.query(
                "SELECT status, created_at, started_at FROM simulation_runs WHERE run_id=?", (run_id,),
            )
            if rows and rows[0][0] not in ("completed", "disabled", "failed"):
                self.history.set_simulation_run_status(
                    run_id, SimulationRunStatus.FAILED if failed else SimulationRunStatus.DISABLED,
                    max(now, rows[0][2] or rows[0][1]), reason=reason,
                )
            self._last_closed_run = run_id
        except (SimulationPersistenceUnavailable, ValueError):
            # El control separado ya revocó. Un histórico roto no impide apagar.
            logger.error("run revocado; pendiente registrar su cierre en el histórico")

    def _disable(self, state: dict, now: float, reason: str) -> dict:
        updated = self.control.disable(now, reason, expected_revision=state["revision"])
        if updated is None:
            return self._read()
        self._lease = None
        self._awaiting_ack_since = None
        self._finish_run(state["runId"], now, reason,
                         failed=reason in ("profile_or_history_unavailable", "civil_clock_jump_or_suspension"))
        return updated

    def _load_profile(self, state: dict) -> SimulationProfile:
        pinned = state["profile"]
        if (self._profile is None or self._profile.sha256 != pinned["sha256"]
                or state["reason"] == "operator_enable" and state["revision"] != self._profile_revision):
            profile = SimulationProfile.load(pinned["name"], self.gtfs_dir)
            if profile.pinned() != pinned:
                raise ValueError("el perfil fijado cambió; requiere enable explícito")
            self._profile = profile
            self._profile_revision = state["revision"]
            self._signatures = profile.verified_signatures
        if self._profile.signatures(self.gtfs_dir) != self._signatures:
            raise ValueError("el manifiesto/feed cambió durante el run")
        return self._profile

    def _synchronize(self, state: dict, now: float) -> dict:
        if not state["enabled"]:
            self._lease = None
            self._awaiting_ack_since = None
            self._finish_run(state["runId"], now, state["reason"], failed=state["reason"] in (
                "producer_history_incomplete", "producer:ProducerGenerationUsed",
                "producer:civil_clock_jump_or_suspension"))
            return state
        profile = self._load_profile(state)
        in_service, service_date, closes = profile.window(now)
        if not in_service:
            self._lease = None
            self._awaiting_ack_since = None
            if state["owner"] is not None:
                updated = self.control.change("service-close", now,
                    lambda s: s.update(owner=None, reason="outside_service"),
                    expected_revision=state["revision"])
                if updated is not None:
                    self._finish_run(state["runId"], now, "service_closed")
                    return updated
            return state
        if state["owner"] != self.instance_id or state["serviceDate"] != service_date:
            self._finish_run(state["runId"], now, "backend_restart_or_new_generation", failed=True)
            run_id = str(uuid.uuid4())
            updated = self.control.change("new-run", now,
                lambda s: s.update(runId=run_id, owner=self.instance_id, serviceDate=service_date,
                                   serviceEndsAt=closes, runStartedAt=now, reason="running"),
                expected_revision=state["revision"])
            if updated is None:
                return self._read()
            # Dos bases no comparten transacción. Nada se autoriza/publica
            # habilitado hasta confirmar referencia e inicio en el histórico.
            self.history.create_simulation_run(SimulationRunRecord(
                run_id, profile.name, profile.version, profile.seed, profile.sha256,
                profile.feed_hashes, now,
            ))
            self.history.set_simulation_run_status(run_id, SimulationRunStatus.RUNNING, now)
            self._lease = None
            self._pending.clear()
            self._awaiting_ack_since = self.monotonic()
            state = updated
        self.history.require_simulation_run(state["runId"])
        if now >= state["runStartedAt"] + profile.max_run_seconds:
            return self._disable(state, now, "max_run_duration")
        if self._awaiting_ack_since is not None and self.monotonic() - self._awaiting_ack_since >= 15:
            return self._disable(state, now, "control_ack_timeout")
        if self._lease is not None and now >= self._lease["validUntil"]:
            return self._disable(state, now, "control_lease_expired")
        return state

    def _payload(self, state: dict, now: float) -> dict:
        active = (state["enabled"] and state["owner"] == self.instance_id
                  and self._profile is not None and self._profile.window(now)[0])
        valid_until = now
        if active:
            valid_until = min(now + 15, state["serviceEndsAt"],
                              state["runStartedAt"] + self._profile.max_run_seconds)
            active = valid_until > now
        return {"schemaVersion": 1, "enabled": bool(active), "runId": state["runId"],
                "controlRevision": state["revision"], "issuedAt": now,
                "validUntil": valid_until if active else now,
                "serviceEndsAt": state["serviceEndsAt"], "timeZone": "America/Lima"}

    def _publish(self, state: dict, now: float, publisher: ControlPublisher | None) -> dict:
        payload = self._payload(state, now)
        mono = self.monotonic()
        due = (self._last_attempt is None or self._last_attempt[0] != state["revision"]
               or mono - self._last_attempt[1] >= 5)
        if publisher is None or not due:
            return payload
        # Una renovación pendiente por revisión: no acumular leases al perder
        # PUBACK. Cambiar revisión permite enviar la revocación inmediatamente.
        if any(body["controlRevision"] == state["revision"] for body, _ in self._pending.values()):
            return payload
        self._last_attempt = (state["revision"], mono)
        # No mezclar un snapshot antiguo con una orden recién guardada.
        if self._read()["revision"] != state["revision"]:
            self._lease = None
            return payload
        try:
            mid = publisher(SIMULATION_CONTROL_TOPIC, json.dumps(payload, allow_nan=False))
        except Exception:
            logger.error("no se pudo encolar el estado de simulación")
            return payload
        if type(mid) is int and mid > 0:
            self._pending = {mid: (payload, mono)}
            self.control.runtime(lastEnqueuedRevision=state["revision"], lastEnqueuedAt=now)
        return payload

    def tick(self, now: float, publisher: ControlPublisher | None = None) -> dict | None:
        if self._closed or self.error is not None:
            return None
        try:
            state = self._read()
            if not self._clock_ok(now) and state["enabled"]:
                state = self._disable(state, now, "civil_clock_jump_or_suspension")
            try:
                state = self._synchronize(state, now)
            except (SimulationPersistenceUnavailable, ValueError, OSError, KeyError, TypeError):
                # Puede haber fallado después de guardar new-run en la otra DB.
                state = self._disable(self._read(), now, "profile_or_history_unavailable")
            mono = self.monotonic()
            if mono - self._last_runtime_at >= 5 or state["revision"] != self._applied_revision:
                self.control.runtime(backendInstance=self.instance_id, backendSeenAt=now,
                                     appliedRevision=state["revision"])
                self._last_runtime_at = mono
                self._applied_revision = state["revision"]
            return self._publish(state, now, publisher)
        except ControlBusy:
            return None
        except (ControlUnavailable, ValueError, OSError) as error:
            self._lease = None
            self.error = f"control_unavailable:{type(error).__name__}"
            logger.error("control sintético cerrado; requiere revisar estado y reiniciar controlador")
            return None

    def acknowledge(self, mid: int, now: float) -> None:
        pending = self._pending.pop(mid, None)
        if pending is None or self._closed or self.error is not None:
            return
        body, sent_mono = pending
        try:
            state = self._read()
            if body["controlRevision"] != state["revision"]:
                return
            self.control.runtime(lastAckedRevision=body["controlRevision"], lastAckedAt=now)
            if (body["enabled"] and state["enabled"] and state["owner"] == self.instance_id
                    and body["issuedAt"] <= now < body["validUntil"]
                    and 0 <= self.monotonic() - sent_mono < 15):
                self._lease = body
                self._awaiting_ack_since = None
        except ControlBusy:
            return
        except (ControlUnavailable, ValueError, OSError):
            self._lease = None
            self.error = "control_unavailable_on_ack"

    def admission(self, now: float) -> SimulationAdmission | None:
        if self._closed or self.error is not None or self._lease is None:
            return None
        state = None
        started = self.monotonic()
        try:
            state = self._read()
            if not self._clock_ok(now):
                self._disable(state, now, "civil_clock_jump_or_suspension")
                return None
            body = self._lease
            profile = self._load_profile(state) if state["enabled"] else None
            # La espera de un escritor y la lectura no amplían el lease.
            elapsed = self.monotonic() - started
            if elapsed < 0:
                return None
            evaluated_at = now + elapsed
            if (profile is None or not profile.window(evaluated_at)[0] or state["owner"] != self.instance_id
                    or state["runId"] != body["runId"] or state["revision"] != body["controlRevision"]
                    or not body["issuedAt"] <= evaluated_at < body["validUntil"]):
                return None
            return SimulationAdmission(body["runId"], body["controlRevision"], profile.principals,
                                       body["issuedAt"], body["validUntil"], body["serviceEndsAt"])
        except ControlBusy:
            # El llamador sigue sin permiso para aceptar/publicar. Distinguir
            # contención breve de una revocación evita destruir la partición
            # y cambiar IDs cada vez que el productor actualiza su estado.
            raise
        except ControlUnavailable:
            self._lease = None
            self.error = "control_unavailable_on_admission"
            return None
        except (ValueError, OSError, KeyError, TypeError):
            self._lease = None
            try:
                if state is not None and state["enabled"]:
                    self._disable(state, now, "profile_or_history_unavailable")
                else:
                    self.error = "control_unavailable_on_admission"
            except (ControlUnavailable, ValueError, OSError):
                self.error = "control_unavailable_on_admission"
            return None

    def disconnected(self) -> None:
        self._lease = None
        self._pending.clear()
        self._last_attempt = None
        self._awaiting_ack_since = self.monotonic()

    def close(self, now: float, publisher: ControlPublisher | None = None) -> None:
        if self._closed:
            return
        try:
            state = self._read()
            if state["owner"] == self.instance_id:
                updated = self.control.change("backend-stop", now,
                    lambda s: s.update(owner=None, reason="backend_stopped"),
                    expected_revision=state["revision"])
                if updated is not None:
                    self._lease = None
                    self._finish_run(state["runId"], now, "backend_stopped")
                    self._publish(updated, now, publisher)
        except (ControlUnavailable, ValueError, OSError):
            logger.error("no se confirmó revocación al cerrar; caducará el lease")
        finally:
            self._lease = None
            self._closed = True
            os.close(self._owner_fd)
