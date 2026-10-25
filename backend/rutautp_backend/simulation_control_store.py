"""Estado administrativo independiente del histórico y sin efectos al importar.

SQLite + referencia externa de revisión. No reparar ni recrear automáticamente
un estado ausente/corrupto: eso podría habilitar un run restaurado.
"""

from __future__ import annotations

from contextlib import contextmanager
import fcntl
import hashlib
import json
import math
import os
from pathlib import Path
import sqlite3
import stat
import tempfile
import time
from typing import Callable
import uuid

from .simulation_models import canonical_uuid, finite_time

MAX_REVISION = 2**53 - 1
STATE_KEYS = frozenset({"revision", "enabled", "profile", "runId", "owner", "serviceDate",
                        "serviceEndsAt", "runStartedAt", "reason", "updatedAt"})
SCHEMA = """
CREATE TABLE control (id INTEGER PRIMARY KEY CHECK(id=1), database_id TEXT NOT NULL, snapshot TEXT NOT NULL);
CREATE TABLE audit (revision INTEGER PRIMARY KEY, at REAL NOT NULL, action TEXT NOT NULL, snapshot TEXT NOT NULL);
CREATE TABLE runtime (id INTEGER PRIMARY KEY CHECK(id=1), snapshot TEXT NOT NULL);
PRAGMA user_version=1;
"""


class ControlUnavailable(RuntimeError):
    pass


class ControlBusy(ControlUnavailable):
    pass


class PublishBudgetExhausted(ControlUnavailable):
    pass


class ProducerGenerationUsed(ControlUnavailable):
    pass


def _encode(value) -> str:
    return json.dumps(value, ensure_ascii=False, allow_nan=False, sort_keys=True, separators=(",", ":"))


def _private(path: Path, directory: bool = False) -> None:
    info = path.lstat()
    expected = stat.S_ISDIR if directory else stat.S_ISREG
    if not expected(info.st_mode) or info.st_uid != os.getuid() or info.st_mode & 0o077:
        raise ControlUnavailable(f"se requiere ruta privada del usuario de servicio: {path.name}")


def _validate(state: dict) -> None:
    if not isinstance(state, dict) or set(state) != STATE_KEYS:
        raise ControlUnavailable("estado administrativo incompleto")
    if type(state["revision"]) is not int or not 1 <= state["revision"] <= MAX_REVISION:
        raise ControlUnavailable("revisión inválida")
    if type(state["enabled"]) is not bool or not isinstance(state["reason"], str) or len(state["reason"]) > 256:
        raise ControlUnavailable("estado/motivo inválido")
    finite_time(state["updatedAt"])
    finite_time(state["serviceEndsAt"])
    if state["runStartedAt"] is not None:
        finite_time(state["runStartedAt"])
    for field in ("runId", "owner"):
        if state[field] is not None:
            canonical_uuid(state[field])
    if state["serviceDate"] is not None:
        from datetime import date
        if date.fromisoformat(state["serviceDate"]).isoformat() != state["serviceDate"]:
            raise ControlUnavailable("fecha de servicio inválida")
    if state["owner"] is not None and (not state["enabled"] or state["runId"] is None
                                       or state["serviceDate"] is None or state["runStartedAt"] is None):
        raise ControlUnavailable("propiedad del run inconsistente")
    profile = state["profile"]
    if profile is not None:
        if (not isinstance(profile, dict) or set(profile) != {"name", "path", "sha256", "raw"}
                or not all(isinstance(v, str) for v in profile.values())
                or len(profile["raw"].encode()) > 64 * 1024
                or hashlib.sha256(profile["raw"].encode()).hexdigest() != profile["sha256"]):
            raise ControlUnavailable("perfil fijado inválido")
    if state["enabled"] and profile is None:
        raise ControlUnavailable("enable sin perfil")


def _audit_snapshot(state: dict) -> dict:
    return {**state, "profile": ({k: v for k, v in state["profile"].items() if k != "raw"}
                                if state["profile"] is not None else None)}


class ControlStore:
    def __init__(self, path: str | Path, *, lock_timeout: float = .05,
                 lock_clock: Callable[[], float] = time.monotonic,
                 lock_sleep: Callable[[float], None] = time.sleep) -> None:
        if type(lock_timeout) not in (int, float) or not math.isfinite(lock_timeout) or not 0 <= lock_timeout <= .1:
            raise ValueError("espera de control entre 0 y 100 ms")
        self.path = Path(path).absolute()
        self.anchor = self.path.with_suffix(self.path.suffix + ".revision")
        self.lock = self.path.with_suffix(self.path.suffix + ".lock")
        self.owner_lock = self.path.with_suffix(self.path.suffix + ".backend-lock")
        self.lock_timeout = lock_timeout
        self._lock_clock, self._lock_sleep = lock_clock, lock_sleep
        self._lock_retries = self._lock_timeouts = 0

    def lock_statistics(self) -> dict:
        return {"retryAttempts": self._lock_retries, "timeouts": self._lock_timeouts,
                "waitBudgetSeconds": self.lock_timeout, "readersUseSharedLock": True}

    def _acquire(self, descriptor: int, write: bool) -> None:
        # Lectores compatibles; el escritor sigue excluyendo lectura y escritura
        # hasta confirmar SQLite y la referencia externa de revisión.
        operation = fcntl.LOCK_EX if write else fcntl.LOCK_SH
        deadline = self._lock_clock() + self.lock_timeout
        while True:
            try:
                fcntl.flock(descriptor, operation | fcntl.LOCK_NB)
                return
            except BlockingIOError:
                remaining = deadline - self._lock_clock()
                if remaining <= 0:
                    self._lock_timeouts += 1
                    raise
                self._lock_retries += 1
                self._lock_sleep(min(.001, remaining))

    @classmethod
    def initialize(cls, path: str | Path, now: float) -> "ControlStore":
        finite_time(now)
        store = cls(path)
        store.path.parent.mkdir(mode=0o700, parents=True, exist_ok=True)
        _private(store.path.parent, directory=True)
        targets = (store.path, store.anchor, store.lock, store.owner_lock)
        if any(p.exists() or p.is_symlink() for p in targets):
            raise ControlUnavailable("init no sobrescribe estado ni archivos existentes")
        # Si se interrumpe init, la carpeta parcial queda cerrada para revisión.
        for target in (store.lock, store.owner_lock, store.path):
            os.close(os.open(target, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600))
        database_id = str(uuid.uuid4())
        state = {"revision": 1, "enabled": False, "profile": None, "runId": None,
                 "owner": None, "serviceDate": None, "serviceEndsAt": 0,
                 "runStartedAt": None, "reason": "initialized", "updatedAt": now}
        with sqlite3.connect(store.path) as db:
            db.executescript("BEGIN IMMEDIATE;" + SCHEMA)
            db.execute("INSERT INTO control VALUES (1, ?, ?)", (database_id, _encode(state)))
            db.execute("INSERT INTO audit VALUES (1, ?, 'init', ?)", (now, _encode(_audit_snapshot(state))))
            db.execute("INSERT INTO runtime VALUES (1, '{}')")
        store._write_anchor(database_id, 1)
        return store

    def _write_anchor(self, database_id: str, revision: int) -> None:
        descriptor, temporary = tempfile.mkstemp(prefix=".revision-", dir=self.path.parent)
        try:
            with os.fdopen(descriptor, "w") as stream:
                stream.write(_encode({"databaseId": database_id, "revision": revision}) + "\n")
                stream.flush()
                os.fsync(stream.fileno())
            os.replace(temporary, self.anchor)
            directory = os.open(self.path.parent, os.O_RDONLY)
            try:
                os.fsync(directory)
            finally:
                os.close(directory)
        finally:
            if os.path.exists(temporary):
                os.unlink(temporary)

    @contextmanager
    def _connection(self, write: bool = False):
        descriptor = None
        db = None
        try:
            _private(self.path.parent, directory=True)
            for path in (self.path, self.anchor, self.lock, self.owner_lock):
                _private(path)
            descriptor = os.open(self.lock, os.O_RDWR | getattr(os, "O_NOFOLLOW", 0))
            self._acquire(descriptor, write)
            mode = "rw" if write else "ro"
            db = sqlite3.connect(self.path.as_uri() + f"?mode={mode}", uri=True, timeout=1)
            db.row_factory = sqlite3.Row
            if db.execute("PRAGMA user_version").fetchone()[0] != 1:
                raise ControlUnavailable("versión de control desconocida")
            if write:
                db.execute("PRAGMA synchronous=FULL")
                db.execute("BEGIN IMMEDIATE")
            yield db
        except BlockingIOError as error:
            raise ControlBusy("control ocupado; reintentar") from error
        except (OSError, sqlite3.Error, ValueError, TypeError, KeyError) as error:
            raise ControlUnavailable(f"control no disponible: {type(error).__name__}") from error
        finally:
            if db is not None:
                db.close()  # rollback si una mutación no llegó a commit
            if descriptor is not None:
                os.close(descriptor)

    def _read(self, db: sqlite3.Connection, *, allow_mismatch: bool = False) -> tuple[str, dict, int]:
        row = db.execute("SELECT database_id, snapshot FROM control WHERE id=1").fetchone()
        if row is None:
            raise ControlUnavailable("falta el estado de control")
        database_id = canonical_uuid(row["database_id"])
        state = json.loads(row["snapshot"])
        _validate(state)
        anchor = json.loads(self.anchor.read_text())
        if (not isinstance(anchor, dict) or set(anchor) != {"databaseId", "revision"}
                or anchor["databaseId"] != database_id or type(anchor["revision"]) is not int
                or not 1 <= anchor["revision"] <= MAX_REVISION):
            raise ControlUnavailable("referencia de revisión inválida")
        audit = db.execute("SELECT revision, snapshot FROM audit ORDER BY revision DESC LIMIT 1").fetchone()
        if audit is None or audit["revision"] != state["revision"] or json.loads(audit["snapshot"]) != _audit_snapshot(state):
            raise ControlUnavailable("estado/auditoría inconsistentes")
        if not allow_mismatch and anchor["revision"] != state["revision"]:
            raise ControlUnavailable("revisión restaurada o commit incompleto; requiere recover-disabled")
        return database_id, state, anchor["revision"]

    def read(self) -> dict:
        with self._connection() as db:
            return self._read(db)[1]

    def snapshot(self) -> tuple[dict, dict]:
        """Orden y runtime de una misma transacción de lectura; nunca los repara."""
        with self._connection() as db:
            db.execute('BEGIN')
            state = self._read(db)[1]
            row = db.execute('SELECT snapshot FROM runtime WHERE id=1').fetchone()
            runtime = json.loads(row[0]) if row else None
            if not isinstance(runtime, dict):
                raise ControlUnavailable('estado del backend inválido')
            return state, runtime

    def change(self, action: str, now: float, mutate: Callable[[dict], None], *,
               expected_revision: int | None = None, recover: bool = False) -> dict | None:
        finite_time(now)
        with self._connection(write=True) as db:
            database_id, state, anchor = self._read(db, allow_mismatch=recover)
            if expected_revision is not None and state["revision"] != expected_revision:
                return None
            revision = max(state["revision"], anchor) + 1
            if revision > MAX_REVISION:
                raise ControlUnavailable("revisión agotada")
            mutate(state)
            state.update(revision=revision, updatedAt=now)
            _validate(state)
            db.execute("UPDATE control SET snapshot=? WHERE id=1", (_encode(state),))
            db.execute("INSERT INTO audit VALUES (?, ?, ?, ?)",
                       (revision, now, action, _encode(_audit_snapshot(state))))
            db.commit()
            # Una caída entre ambos commits no se repara habilitando: la
            # desigualdad de revisiones cierra hasta recuperación explícita.
            self._write_anchor(database_id, revision)
            return state

    def enable(self, profile: dict, now: float) -> dict:
        def mutate(state):
            state.update(enabled=True, profile=profile, owner=None, reason="operator_enable")
        return self.change("enable", now, mutate)

    def disable(self, now: float, reason: str = "operator", *, recover: bool = False,
                expected_revision: int | None = None) -> dict | None:
        if not isinstance(reason, str) or not reason.strip() or len(reason) > 256:
            raise ValueError("motivo requerido, máximo 256 caracteres")
        return self.change("recover-disabled" if recover else "disable", now,
                           lambda state: state.update(enabled=False, owner=None, reason=reason),
                           expected_revision=expected_revision, recover=recover)

    def runtime(self, **updates) -> dict:
        with self._connection(write=bool(updates)) as db:
            self._read(db)
            row = db.execute("SELECT snapshot FROM runtime WHERE id=1").fetchone()
            if row is None:
                raise ControlUnavailable("falta el estado del backend")
            current = json.loads(row[0])
            if not isinstance(current, dict):
                raise ControlUnavailable("estado del backend inválido")
            if updates:
                current.update(updates)
                db.execute("UPDATE runtime SET snapshot=? WHERE id=1", (_encode(current),))
                db.commit()
            return current

    def producer_transaction(self, run_id: str, revision: int, owner: str,
                             mutate: Callable[[dict, dict], None]) -> dict:
        """CAS privado del productor: intención y contadores en un mismo commit.

        No modifica revisión/orden ni publica control. El presupuesto cuenta
        reservas previas a llamadas publish, incluidas las que fallen después.
        """
        canonical_uuid(run_id)
        canonical_uuid(owner)
        with self._connection(write=True) as db:
            state = self._read(db)[1]
            if (not state["enabled"] or state["runId"] != run_id
                    or state["revision"] != revision or state["owner"] != owner):
                raise ControlUnavailable("run del productor revocado")
            row = db.execute("SELECT snapshot FROM runtime WHERE id=1").fetchone()
            current = json.loads(row[0]) if row else None
            if not isinstance(current, dict):
                raise ControlUnavailable("runtime inválido")
            mutate(current, state)
            db.execute("UPDATE runtime SET snapshot=? WHERE id=1", (_encode(current),))
            db.commit()
            return current

    def claim_producer(self, run_id: str, revision: int, owner: str, instance: str, now: float) -> None:
        canonical_uuid(instance)
        finite_time(now)
        def claim(runtime, state):
            claims = runtime.setdefault("producerClaims", {})
            if not isinstance(claims, dict):
                raise ControlUnavailable("registro de productores inválido")
            if run_id in claims:
                raise ProducerGenerationUsed("run ya utilizado por un productor; requiere nueva generación")
            claims[run_id] = {"instance": instance, "at": now, "serviceDate": state["serviceDate"]}
        self.producer_transaction(run_id, revision, owner, claim)

    def reserve_publish(self, run_id: str, revision: int, owner: str, instance: str,
                        service_date: str, *, max_run: int, max_day: int) -> tuple[int, int]:
        if any(type(limit) is not int or not 1 <= limit <= 6000 for limit in (max_run, max_day)):
            raise ValueError("presupuesto inicial entre 1 y 6000")
        counts = []
        def reserve(runtime, state):
            claims = runtime.get("producerClaims", {})
            if not isinstance(claims, dict):
                raise ControlUnavailable("registro de productores inválido")
            claim = claims.get(run_id, {})
            if (not isinstance(claim, dict) or claim.get("instance") != instance or state["serviceDate"] != service_date
                    or claim.get("serviceDate") != service_date):
                raise ControlUnavailable("productor o fecha del presupuesto no coinciden")
            budget = runtime.setdefault("publishBudget", {"runs": {}, "days": {}})
            if not isinstance(budget, dict) or set(budget) != {"runs", "days"}:
                raise ControlUnavailable("presupuesto inválido")
            if any(not isinstance(budget[k], dict) for k in ("runs", "days")):
                raise ControlUnavailable("contadores inválidos")
            run_count, day_count = budget["runs"].get(run_id, 0), budget["days"].get(service_date, 0)
            if any(type(count) is not int or count < 0 for count in (run_count, day_count)):
                raise ControlUnavailable("contadores inválidos")
            if run_count > day_count:
                raise ControlUnavailable("presupuesto diario inconsistente")
            if run_count >= max_run or day_count >= max_day:
                raise PublishBudgetExhausted("presupuesto de publicaciones agotado")
            budget["runs"][run_id], budget["days"][service_date] = run_count + 1, day_count + 1
            counts.extend((run_count + 1, day_count + 1))
        self.producer_transaction(run_id, revision, owner, reserve)
        return tuple(counts)

    def acquire_backend(self) -> int:
        self.read()
        descriptor = os.open(self.owner_lock, os.O_RDWR | getattr(os, "O_NOFOLLOW", 0))
        try:
            fcntl.flock(descriptor, fcntl.LOCK_EX | fcntl.LOCK_NB)
        except OSError as error:
            os.close(descriptor)
            raise ControlUnavailable("ya hay un controlador del backend") from error
        return descriptor
