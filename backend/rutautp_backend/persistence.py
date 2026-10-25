"""Persistencia del histórico en SQLite.

Hasta ahora todo vivía en memoria: al reiniciar el backend se perdía la
evidencia. Sin histórico no se puede responder a las preguntas que importan
después de una prueba de campo:

- ¿cuántas observaciones se aceptaron y cuántas se descartaron, y por qué?
- ¿qué precisión tenía el GPS cuando se aceptó una observación?
- ¿a qué distancia del recorrido estaban las que se rechazaron?
- ¿por dónde pasó realmente cada vehículo estimado, para compararlo con la verdad?

Se usa `sqlite3` de la biblioteca estándar: no añade dependencias.

Tres decisiones que conviene conocer:

1. **Una transacción por segundo, no por mensaje.** Cada `commit` de SQLite
   fuerza un `fsync`. Hacerlo por mensaje limitaría el caudal y desgastaría el
   disco. El precio es que un corte abrupto pierde hasta un segundo de datos.
2. **Si falla el histórico observado, el puente sigue publicando.** La simulación
   exige almacenamiento: sus fallos se señalan con una excepción y quedan
   enclavados hasta reparar/reabrir el almacén. S03/S04 usarán esa señal para parar
   únicamente la alimentación sintética.
3. **El `sessionId` se guarda tal cual.** Es un UUID generado para cada abordaje
   que permite analizar cuántos viajes distintos aportaron a un mismo vehículo.
   Terminar la sesión local no borra el histórico de coordenadas y fechas.
   SQLite no tiene una columna de principal MQTT, pero el broker y el backend
   reciben esa cuenta asociada a la sesión y pueden correlacionar observaciones.
   No se garantiza anonimato. La retención se configura; `0` no borra filas.
"""

from __future__ import annotations

import json
import logging
import shutil
import sqlite3
import time
from dataclasses import dataclass
from pathlib import Path
from typing import Any, Iterator, Mapping, TextIO

from .models import EstimatedVehicle, Observation, RejectReason
from .persistence_migrations import MIN_FREE_BYTES, STORE_SCHEMA_VERSION, StoreMigrationError, migrate_store
from .simulation_models import (
    OBSERVED_SOURCE, UNKNOWN_SOURCE, TERMINAL_RUN_STATUSES, DataOrigin,
    SimulationActorRecord, SimulationRunRecord, SimulationRunStatus, SourceContext,
    canonical_uuid, finite_time,
)

logger = logging.getLogger(__name__)

# Longitud máxima del detalle de un rechazo. Evita que un mensaje manipulado de
# 10 MB acabe almacenado entero.
MAX_DETAIL_LENGTH = 200

SCHEMA = """
CREATE TABLE IF NOT EXISTS observations (
    id                 INTEGER PRIMARY KEY AUTOINCREMENT,
    at                 REAL NOT NULL,
    observed_at        REAL NOT NULL,
    session_id         TEXT NOT NULL,
    route_id           TEXT NOT NULL,
    linea              TEXT NOT NULL,
    lat                REAL NOT NULL,
    lon                REAL NOT NULL,
    speed              REAL NOT NULL,
    heading            REAL NOT NULL,
    accuracy           REAL NOT NULL,
    motion_activity    TEXT NOT NULL,
    distance_to_route_m REAL NOT NULL,
    heading_diff_deg   REAL NOT NULL,
    progress           REAL NOT NULL,
    vehicle_id         TEXT
);

CREATE INDEX IF NOT EXISTS idx_obs_observed_at ON observations(observed_at);
CREATE INDEX IF NOT EXISTS idx_obs_route ON observations(route_id);

CREATE TABLE IF NOT EXISTS rejections (
    id      INTEGER PRIMARY KEY AUTOINCREMENT,
    at      REAL NOT NULL,
    reason  TEXT NOT NULL,
    detail  TEXT NOT NULL DEFAULT ''
);

CREATE INDEX IF NOT EXISTS idx_rej_at ON rejections(at);
CREATE INDEX IF NOT EXISTS idx_rej_reason ON rejections(reason);

CREATE TABLE IF NOT EXISTS vehicle_positions (
    id           INTEGER PRIMARY KEY AUTOINCREMENT,
    at           REAL NOT NULL,
    observed_at  REAL NOT NULL,
    vehicle_id   TEXT NOT NULL,
    route_id     TEXT NOT NULL,
    linea        TEXT NOT NULL,
    lat          REAL NOT NULL,
    lon          REAL NOT NULL,
    speed        REAL NOT NULL,
    heading      REAL NOT NULL,
    sessions     INTEGER NOT NULL,
    samples      INTEGER NOT NULL
);

CREATE INDEX IF NOT EXISTS idx_veh_vehicle ON vehicle_positions(vehicle_id);
CREATE INDEX IF NOT EXISTS idx_veh_at ON vehicle_positions(at);
"""


@dataclass
class StoreCounts:
    """Filas almacenadas, para el resumen periódico."""

    observations: int = 0
    rejections: int = 0
    vehicle_positions: int = 0
    write_errors: int = 0

    def as_dict(self) -> dict[str, int]:
        return {
            "dbObservations": self.observations,
            "dbRejections": self.rejections,
            "dbVehiclePositions": self.vehicle_positions,
            "dbWriteErrors": self.write_errors,
        }


class SimulationPersistenceUnavailable(RuntimeError):
    """El consumidor debe pausar simulación; no autoriza cambiar el flujo observado."""


class ObservationStore:
    """Histórico del puente. Con `path=None` no hace nada (modo sin persistencia)."""

    def __init__(
        self,
        path: Path | None,
        retention_days: float = 0.0,
        *,
        min_simulation_free_bytes: int = MIN_FREE_BYTES,
        existing_only: bool = False,
    ) -> None:
        if type(min_simulation_free_bytes) is not int or min_simulation_free_bytes < 0:
            raise ValueError("el margen de disco debe ser un entero no negativo")
        self.path = path
        self.retention_days = retention_days
        self.counts = StoreCounts()

        self._connection: sqlite3.Connection | None = None
        self._pending = 0
        self._last_prune_at = 0.0
        self._min_simulation_free_bytes = min_simulation_free_bytes
        self._last_space_check = float("-inf")
        self._simulation_error: str | None = None
        self._pending_simulation_runs: set[str] = set()
        self._failed_simulation_runs: set[str] = set()
        self._created_simulation_runs: set[str] = set()
        self._active_simulation_runs: set[str] = set()
        self.migration_backup: Path | None = None
        self._existing_only = existing_only

        if path is None:
            logger.info("persistencia desactivada: el histórico no se guardará")
            return

        self._open(path)

    # ── Ciclo de vida ─────────────────────────────────────────────────────

    def _open(self, path: Path) -> None:
        try:
            if self._existing_only:
                # El productor comparte el histórico preparado por el backend;
                # un typo no debe crear/migrar otra base ni conceder un run.
                self._connection = sqlite3.connect(path.absolute().as_uri() + "?mode=rw", uri=True, timeout=1)
                if self._connection.execute("PRAGMA user_version").fetchone()[0] != STORE_SCHEMA_VERSION:
                    raise StoreMigrationError("el productor requiere el histórico ya migrado")
            else:
                path.parent.mkdir(parents=True, exist_ok=True)
                self._connection = sqlite3.connect(str(path))
            self._connection.execute("PRAGMA foreign_keys=ON")
            if not self._existing_only:
                self.migration_backup = migrate_store(self._connection, path, SCHEMA)

            # WAL permite leer mientras se escribe y aguanta mejor un corte.
            self._connection.execute("PRAGMA journal_mode=WAL")
            self._connection.execute("PRAGMA synchronous=NORMAL")
            logger.info("histórico en %s", path)
        except (sqlite3.Error, OSError, StoreMigrationError) as error:
            # No poder guardar el histórico no debe impedir el puente.
            #
            # Se atrapan también los errores del sistema de archivos, no solo
            # los de SQLite: una ruta cuyo directorio padre es un archivo, o un
            # disco de solo lectura, lanzan `OSError` y antes escapaban de aquí.
            # El resultado era que el puente **no arrancaba** por no poder
            # escribir el histórico, que es exactamente lo que esta garantía
            # promete evitar.
            logger.error("no se pudo abrir el histórico en %s: %s", path, error)
            if self._connection is not None:
                self._connection.close()
            self._connection = None
            self._simulation_error = str(error)

    @property
    def enabled(self) -> bool:
        return self._connection is not None

    def close(self) -> None:
        if self._connection is None:
            return

        try:
            self.flush()
            self._connection.close()
        except sqlite3.Error as error:
            logger.warning("error al cerrar el histórico: %s", error)
            self._fail_simulation(str(error))
        finally:
            self._connection = None

    # ── Escritura ─────────────────────────────────────────────────────────

    def record_observation(
        self,
        observation: Observation,
        vehicle_id: str,
        now: float,
        *,
        source: SourceContext = OBSERVED_SOURCE,
    ) -> None:
        self._check_accepted_source(source)
        if source.origin is DataOrigin.SIMULATED:
            self._check_actor_observation(source, observation)
        self._execute(
            """
            INSERT INTO observations (
                at, observed_at, session_id, route_id, linea, lat, lon,
                speed, heading, accuracy, motion_activity,
                distance_to_route_m, heading_diff_deg, progress, vehicle_id,
                data_origin, simulation_run_id
            ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            """,
            (
                now,
                observation.timestamp,
                observation.session_id,
                observation.route_id,
                observation.linea,
                observation.lat,
                observation.lon,
                observation.speed,
                observation.heading,
                observation.accuracy,
                observation.motion_activity,
                observation.distance_to_route_m,
                observation.heading_diff_deg,
                observation.progress,
                vehicle_id,
                source.origin.value,
                source.run_id,
            ),
            kind="observations",
            simulation_run_id=source.run_id,
        )

    def record_rejection(
        self,
        reason: RejectReason,
        detail: str,
        now: float,
        *,
        source: SourceContext = UNKNOWN_SOURCE,
    ) -> None:
        self._execute(
            "INSERT INTO rejections (at, reason, detail, data_origin, simulation_run_id) "
            "VALUES (?, ?, ?, ?, ?)",
            (now, reason.value, detail[:MAX_DETAIL_LENGTH], source.origin.value, source.run_id),
            kind="rejections",
            simulation_run_id=source.run_id,
            require_active_run=False,
        )

    def record_vehicle(
        self,
        vehicle: EstimatedVehicle,
        now: float,
        *,
        source: SourceContext = OBSERVED_SOURCE,
    ) -> None:
        self._check_accepted_source(source)
        self._execute(
            """
            INSERT INTO vehicle_positions (
                at, observed_at, vehicle_id, route_id, linea, lat, lon,
                speed, heading, sessions, samples, data_origin, simulation_run_id
            ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            """,
            (
                now,
                vehicle.timestamp,
                vehicle.vehicle_id,
                vehicle.route_id,
                vehicle.linea,
                vehicle.lat,
                vehicle.lon,
                vehicle.speed,
                vehicle.heading,
                len(vehicle.sessions),
                vehicle.sample_count,
                source.origin.value,
                source.run_id,
            ),
            kind="vehicle_positions",
            simulation_run_id=source.run_id,
        )

    def _execute(
        self, sql: str, params: tuple[Any, ...], kind: str | None = None,
        *, simulation_run_id: str | None = None, require_active_run: bool = True,
    ) -> bool:
        """Observados conservan tolerancia al fallo; sintéticos reciben una señal."""
        if simulation_run_id is not None:
            try:
                self.require_simulation_persistence()
            except SimulationPersistenceUnavailable as error:
                self._fail_simulation(str(error), simulation_run_id)
                raise
            if require_active_run:
                self._require_running_run(simulation_run_id)
        if self._connection is None:
            return False

        try:
            self._connection.execute(sql, params)

            if kind is not None:
                setattr(self.counts, kind, getattr(self.counts, kind) + 1)
            self._pending += 1
            if simulation_run_id is not None:
                self._pending_simulation_runs.add(simulation_run_id)
            return True
        except sqlite3.Error as error:
            self.counts.write_errors += 1
            self._fail_simulation(str(error), simulation_run_id)

            # Se avisa solo en el primer fallo de cada ráfaga: si el disco está
            # lleno, no interesa inundar el registro con una línea por mensaje.
            if self.counts.write_errors == 1:
                logger.error(
                    "no se pudo escribir en el histórico (%s); el puente "
                    "continúa sin persistencia",
                    error,
                )
            if simulation_run_id is not None:
                raise SimulationPersistenceUnavailable(self._simulation_error) from error
            return False

    # ── Mantenimiento ─────────────────────────────────────────────────────

    def flush(self) -> bool:
        """Confirma lo pendiente. Se llama desde el mantenimiento periódico."""
        if self._connection is None:
            return False
        if self._pending == 0:
            return True

        try:
            self._connection.commit()
            self._pending = 0
            self._pending_simulation_runs.clear()
            return True
        except sqlite3.Error as error:
            self.counts.write_errors += 1
            self._fail_simulation(str(error))
            logger.error("no se pudo confirmar el histórico: %s", error)
            return False

    def prune(self, now: float, interval_s: float = 3600.0) -> int:
        """Borra lo anterior a la retención. Devuelve las filas eliminadas."""
        if self._connection is None or self.retention_days <= 0:
            return 0

        if now - self._last_prune_at < interval_s:
            return 0

        self._last_prune_at = now
        cutoff = now - self.retention_days * 86_400.0

        borradas = 0

        try:
            for tabla in ("observations", "rejections", "vehicle_positions"):
                cursor = self._connection.execute(
                    f"DELETE FROM {tabla} WHERE at < ? AND data_origin != 'simulated'", (cutoff,)
                )
                borradas += cursor.rowcount or 0

            self._connection.commit()
            self._pending = 0
            self._pending_simulation_runs.clear()

            if borradas:
                logger.info(
                    "retención: %d fila(s) anteriores a %.0f días eliminadas",
                    borradas,
                    self.retention_days,
                )
        except sqlite3.Error as error:
            self.counts.write_errors += 1
            self._fail_simulation(str(error))
            logger.error("no se pudo aplicar la retención: %s", error)

        return borradas

    # ── Procedencia y persistencia obligatoria de simulación ─────────────

    def _fail_simulation(self, detail: str, run_id: str | None = None) -> None:
        self._failed_simulation_runs.update(self._pending_simulation_runs)
        self._failed_simulation_runs.update(self._active_simulation_runs)
        if run_id is not None:
            self._failed_simulation_runs.add(run_id)
        if self._simulation_error is None:
            self._simulation_error = detail[:MAX_DETAIL_LENGTH]
            logger.error("simulación sin histórico fiable; debe pausarse: %s", detail)

    def simulation_storage_status(self) -> dict[str, Any]:
        """Señal en memoria para S03/S04/S09; no equivale a un enable."""
        return {
            "available": self.enabled and self._simulation_error is None,
            "failure": self._simulation_error,
            "incompleteRunIds": sorted(self._failed_simulation_runs),
        }

    def require_simulation_persistence(self) -> None:
        if self._connection is None:
            raise SimulationPersistenceUnavailable("el histórico está deshabilitado")
        if self._simulation_error is not None:
            raise SimulationPersistenceUnavailable(self._simulation_error)
        monotonic = time.monotonic()
        if monotonic - self._last_space_check < 1:
            return
        try:
            if self.path is None or shutil.disk_usage(self.path.parent).free < self._min_simulation_free_bytes:
                raise OSError("sin el margen mínimo de disco para simulación")
        except OSError as error:
            self.counts.write_errors += 1
            self._fail_simulation(str(error))
            raise SimulationPersistenceUnavailable(self._simulation_error) from error
        self._last_space_check = monotonic

    def _simulation_rows(self, sql: str, params: tuple[Any, ...]) -> list[tuple]:
        self.require_simulation_persistence()
        assert self._connection is not None
        try:
            return self._connection.execute(sql, params).fetchall()
        except sqlite3.Error as error:
            self.counts.write_errors += 1
            self._fail_simulation(str(error))
            raise SimulationPersistenceUnavailable(self._simulation_error) from error

    @staticmethod
    def _check_accepted_source(source: SourceContext) -> None:
        if not isinstance(source, SourceContext) or source.origin not in (
            DataOrigin.OBSERVED, DataOrigin.SIMULATED,
        ):
            raise ValueError("una medición aceptada necesita procedencia conocida")

    def _run_state(self, run_id: str) -> tuple:
        canonical_uuid(run_id)
        rows = self._simulation_rows(
            "SELECT status, history_complete, created_at, started_at "
            "FROM simulation_runs WHERE run_id=?", (run_id,),
        )
        if not rows:
            raise ValueError("run no registrado")
        return rows[0]

    def _require_running_run(self, run_id: str) -> None:
        status, complete, _, _ = self._run_state(run_id)
        if status != SimulationRunStatus.RUNNING.value or not complete:
            raise ValueError("el run no está en ejecución con histórico completo")

    def _check_actor_observation(self, source: SourceContext, observation: Observation) -> None:
        if source.principal is None:
            raise ValueError("la observación sintética necesita principal")
        rows = self._simulation_rows(
            "SELECT principal, route_id, boarded_at, left_at FROM simulation_actors "
            "WHERE simulation_run_id=? AND session_id=?",
            (source.run_id, observation.session_id),
        )
        if not rows:
            raise ValueError("sesión sintética sin referencia de abordaje")
        principal, route, boarded, left = rows[0]
        if principal != source.principal or route != observation.route_id:
            raise ValueError("la observación no coincide con su actor/ruta")
        if observation.timestamp < boarded or (left is not None and observation.timestamp > left):
            raise ValueError("observación fuera del abordaje registrado")

    def require_simulation_observation(self, source: SourceContext, observation: Observation) -> None:
        """Preflight antes de mutar deducción/agrupación en la entrada S03."""
        if source.origin is not DataOrigin.SIMULATED or source.run_id is None:
            raise ValueError("se requiere contexto sintético")
        self._require_running_run(source.run_id)
        self._check_actor_observation(source, observation)

    def require_simulation_run(self, run_id: str) -> None:
        """Autorizar entrada requiere un run durable en ejecución y completo."""
        self._require_running_run(run_id)

    def create_simulation_run(self, record: SimulationRunRecord) -> None:
        self._execute(
            "INSERT INTO simulation_runs (run_id, scenario_id, scenario_version, seed, "
            "manifest_sha256, feed_hashes_json, created_at) VALUES (?, ?, ?, ?, ?, ?, ?)",
            (record.run_id, record.scenario_id, record.scenario_version, record.seed,
             record.manifest_sha256, json.dumps(dict(record.feed_sha256), sort_keys=True), record.created_at),
            simulation_run_id=record.run_id, require_active_run=False,
        )
        if not self.flush():
            raise SimulationPersistenceUnavailable(self._simulation_error)
        self._created_simulation_runs.add(record.run_id)

    def set_simulation_run_status(
        self, run_id: str, status: SimulationRunStatus, now: float,
        *, reason: str = "", totals: Mapping[str, int] | None = None,
    ) -> None:
        finite_time(now)
        if not isinstance(status, SimulationRunStatus):
            raise ValueError("estado de run no reconocido")
        self.require_simulation_persistence()
        if not self.flush():
            raise SimulationPersistenceUnavailable(self._simulation_error)
        previous, complete, created, started = self._run_state(run_id)
        if now < (started if started is not None else created):
            raise ValueError("el estado no puede retroceder la fecha del run")
        previous = SimulationRunStatus(previous)
        if status is previous:
            return
        if previous in TERMINAL_RUN_STATUSES:
            raise ValueError("un run terminado no se reactiva")
        allowed = {
            SimulationRunStatus.PREPARED: {SimulationRunStatus.RUNNING, SimulationRunStatus.DISABLED, SimulationRunStatus.FAILED},
            SimulationRunStatus.RUNNING: {SimulationRunStatus.PAUSED, *TERMINAL_RUN_STATUSES},
            SimulationRunStatus.PAUSED: {SimulationRunStatus.RUNNING, SimulationRunStatus.DISABLED, SimulationRunStatus.FAILED},
        }
        if status not in allowed[previous]:
            raise ValueError("transición de run no permitida")
        if status is SimulationRunStatus.COMPLETED and (
            run_id not in self._created_simulation_runs or not complete
            or run_id in self._failed_simulation_runs
        ):
            raise SimulationPersistenceUnavailable("no completar un run heredado o con pérdida de histórico")
        encoded_totals = None
        if totals is not None:
            if any(not isinstance(key, str) or type(value) is not int or value < 0 for key, value in totals.items()):
                raise ValueError("los totales deben ser contadores enteros no negativos")
            encoded_totals = json.dumps(dict(totals), sort_keys=True, allow_nan=False)
        self._execute(
            "UPDATE simulation_runs SET status=?, reason=?, started_at=COALESCE(started_at, ?), "
            "ended_at=?, totals_json=COALESCE(?, totals_json), history_complete=? WHERE run_id=?",
            (status.value, reason[:MAX_DETAIL_LENGTH], now if status is SimulationRunStatus.RUNNING else None,
             now if status in TERMINAL_RUN_STATUSES else None, encoded_totals,
             0 if status is SimulationRunStatus.FAILED else complete, run_id),
            simulation_run_id=run_id, require_active_run=False,
        )
        if not self.flush():
            raise SimulationPersistenceUnavailable(self._simulation_error)
        if status in (SimulationRunStatus.RUNNING, SimulationRunStatus.PAUSED):
            self._active_simulation_runs.add(run_id)
        elif status in TERMINAL_RUN_STATUSES:
            self._active_simulation_runs.discard(run_id)
            self._created_simulation_runs.discard(run_id)

    def record_simulation_actor(self, record: SimulationActorRecord) -> None:
        self._require_running_run(record.run_id)
        existing = self._simulation_rows(
            "SELECT principal, scenario_vehicle_id, route_id, boarded_at FROM simulation_actors "
            "WHERE simulation_run_id=? AND session_id=?", (record.run_id, record.session_id),
        )
        values = (record.principal, record.scenario_vehicle_id, record.route_id, record.boarded_at)
        if existing:
            if existing[0] != values:
                raise ValueError("la sesión ya pertenece a otro abordaje")
            return
        _, _, _, started = self._run_state(record.run_id)
        if started is None or record.boarded_at < started:
            raise ValueError("abordaje anterior al inicio del run")
        self._execute(
            "INSERT INTO simulation_actors (simulation_run_id, session_id, principal, "
            "scenario_vehicle_id, route_id, boarded_at) VALUES (?, ?, ?, ?, ?, ?)",
            (record.run_id, record.session_id, *values), simulation_run_id=record.run_id,
        )

    def end_simulation_actor(
        self, run_id: str, session_id: str, left_at: float, *, reason: str = "",
    ) -> None:
        canonical_uuid(run_id)
        canonical_uuid(session_id)
        finite_time(left_at)
        rows = self._simulation_rows(
            "SELECT boarded_at, left_at FROM simulation_actors WHERE simulation_run_id=? AND session_id=?",
            (run_id, session_id),
        )
        if not rows or left_at < rows[0][0]:
            raise ValueError("abordaje ausente o fecha de bajada anterior")
        if rows[0][1] is not None:
            return  # La primera bajada registrada no se reescribe al reintentar.
        self._execute(
            "UPDATE simulation_actors SET left_at=?, leave_reason=? "
            "WHERE simulation_run_id=? AND session_id=? AND left_at IS NULL",
            (left_at, reason[:MAX_DETAIL_LENGTH], run_id, session_id),
            simulation_run_id=run_id, require_active_run=False,
        )

    def purge_simulation_detail(self, run_id: str, before: float) -> int:
        """Purga explícita de detalle de UN run terminado; conserva su resumen."""
        finite_time(before)
        status, _, _, _ = self._run_state(run_id)
        if SimulationRunStatus(status) not in TERMINAL_RUN_STATUSES:
            raise ValueError("no purgar un run activo o pausado")
        if not self.flush():
            raise SimulationPersistenceUnavailable(self._simulation_error)
        assert self._connection is not None
        deleted = 0
        try:
            self._connection.execute("BEGIN IMMEDIATE")
            # Guardar un resumen antes de retirar detalle. Nunca sobrescribir
            # la primera fotografía con los conteos ya reducidos de otra purga.
            row = self._connection.execute('SELECT totals_json, detail_purged_before FROM simulation_runs '
                                           'WHERE run_id=?', (run_id,)).fetchone()
            totals = json.loads(row[0])
            if not isinstance(totals, dict):
                raise ValueError('resumen de run inválido')
            if 'beforeFirstRetention' not in totals:
                totals['beforeFirstRetention'] = {
                    table: self._connection.execute(f'SELECT COUNT(*) FROM {table} '
                        "WHERE data_origin='simulated' AND simulation_run_id=?", (run_id,)).fetchone()[0]
                    for table in ('observations', 'rejections', 'vehicle_positions', 'simulation_actors')}
                totals['beforeFirstRetention']['detailWasAlreadyPurged'] = row[1] is not None
            self._connection.execute('UPDATE simulation_runs SET totals_json=? WHERE run_id=?',
                (json.dumps(totals, allow_nan=False, sort_keys=True), run_id))
            for table in ("observations", "rejections", "vehicle_positions"):
                cursor = self._connection.execute(
                    f"DELETE FROM {table} WHERE data_origin='simulated' AND simulation_run_id=? AND at<?",
                    (run_id, before),
                )
                deleted += cursor.rowcount
            cursor = self._connection.execute(
                "DELETE FROM simulation_actors WHERE data_origin='simulated' "
                "AND simulation_run_id=? AND left_at<?", (run_id, before),
            )
            deleted += cursor.rowcount
            self._connection.execute(
                "UPDATE simulation_runs SET detail_purged_before=MAX(COALESCE(detail_purged_before, 0), ?) "
                "WHERE run_id=?", (before, run_id),
            )
            self._connection.commit()
        except (sqlite3.Error, ValueError, TypeError) as error:
            self._connection.rollback()
            self.counts.write_errors += 1
            self._fail_simulation(str(error), run_id)
            raise SimulationPersistenceUnavailable(self._simulation_error) from error
        return deleted

    def iter_export_rows(
        self, table: str, *, data_origin: DataOrigin | None = None, run_id: str | None = None,
    ) -> Iterator[dict[str, Any]]:
        """Exportación acotada en memoria; todas las columnas conservan procedencia."""
        tables = {
            "observations": ("simulation_run_id", "id"),
            "rejections": ("simulation_run_id", "id"),
            "vehicle_positions": ("simulation_run_id", "id"),
            "simulation_runs": ("run_id", "created_at, run_id"),
            "simulation_actors": ("simulation_run_id", "boarded_at, session_id"),
        }
        if table not in tables:
            raise ValueError("tabla de exportación no permitida")
        if data_origin is not None and not isinstance(data_origin, DataOrigin):
            raise ValueError("filtro de origen no reconocido")
        if run_id is not None:
            canonical_uuid(run_id)
            if data_origin not in (None, DataOrigin.SIMULATED):
                raise ValueError("un filtro de run solo corresponde a simulated")
            data_origin = DataOrigin.SIMULATED
        if not self.flush():
            raise RuntimeError("no se puede exportar un histórico sin confirmar")
        clauses, params = [], []
        if data_origin is not None:
            clauses.append("data_origin=?")
            params.append(data_origin.value)
        run_column, order = tables[table]
        if run_id is not None:
            clauses.append(f"{run_column}=?")
            params.append(run_id)
        where = " WHERE " + " AND ".join(clauses) if clauses else ""
        assert self._connection is not None
        cursor = self._connection.execute(f"SELECT * FROM {table}{where} ORDER BY {order}", params)
        columns = [item[0] for item in cursor.description]
        try:
            while batch := cursor.fetchmany(256):
                for row in batch:
                    result = dict(zip(columns, row))
                    if table == "simulation_runs" and result["run_id"] in self._failed_simulation_runs:
                        result["history_complete"] = 0
                    yield result
        finally:
            cursor.close()

    def export_jsonl(self, output: TextIO, table: str, **filters: Any) -> int:
        count = 0
        for row in self.iter_export_rows(table, **filters):
            output.write(json.dumps(row, ensure_ascii=False, allow_nan=False) + "\n")
            count += 1
        return count

    # ── Consulta (para pruebas y para el análisis posterior) ──────────────

    def query(self, sql: str, params: tuple[Any, ...] = ()) -> list[tuple]:
        """Ejecuta una consulta de lectura. Solo para inspección."""
        if self._connection is None:
            return []

        return self._connection.execute(sql, params).fetchall()


def default_database_path() -> Path:
    """Ruta por defecto: `backend/data/rutautp.sqlite`."""
    return Path(__file__).resolve().parents[1] / "data" / "rutautp.sqlite"


def open_store(
    path_setting: str,
    retention_days: float,
) -> ObservationStore:
    """Construye el almacén a partir de la configuración.

    Un valor vacío en la variable de entorno desactiva la persistencia; así se
    puede correr sin escribir nada en disco con `BACKEND_DB_PATH=`.
    """
    if not path_setting.strip():
        return ObservationStore(path=None, retention_days=retention_days)

    return ObservationStore(
        path=Path(path_setting).expanduser(),
        retention_days=retention_days,
    )
