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
2. **Si la escritura falla, el puente sigue publicando.** Un disco lleno no debe
   tumbar el mapa. Los fallos se registran y se cuentan, pero nunca interrumpen.
3. **El `sessionId` se guarda tal cual.** Es un UUID anónimo que se genera en cada
   abordaje y muere al bajar del vehículo; no identifica a nadie y es lo que
   permite analizar cuántos viajes distintos aportaron a un mismo vehículo.
"""

from __future__ import annotations

import logging
import sqlite3
from dataclasses import dataclass
from pathlib import Path
from typing import Any

from .models import EstimatedVehicle, Observation, RejectReason

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


class ObservationStore:
    """Histórico del puente. Con `path=None` no hace nada (modo sin persistencia)."""

    def __init__(
        self,
        path: Path | None,
        retention_days: float = 0.0,
    ) -> None:
        self.path = path
        self.retention_days = retention_days
        self.counts = StoreCounts()

        self._connection: sqlite3.Connection | None = None
        self._pending = 0
        self._last_prune_at = 0.0

        if path is None:
            logger.info("persistencia desactivada: el histórico no se guardará")
            return

        self._open(path)

    # ── Ciclo de vida ─────────────────────────────────────────────────────

    def _open(self, path: Path) -> None:
        try:
            path.parent.mkdir(parents=True, exist_ok=True)

            self._connection = sqlite3.connect(str(path))

            # WAL permite leer mientras se escribe y aguanta mejor un corte.
            self._connection.execute("PRAGMA journal_mode=WAL")
            self._connection.execute("PRAGMA synchronous=NORMAL")
            self._connection.executescript(SCHEMA)
            self._connection.commit()

            logger.info("histórico en %s", path)
        except (sqlite3.Error, OSError) as error:
            # No poder guardar el histórico no debe impedir el puente.
            #
            # Se atrapan también los errores del sistema de archivos, no solo
            # los de SQLite: una ruta cuyo directorio padre es un archivo, o un
            # disco de solo lectura, lanzan `OSError` y antes escapaban de aquí.
            # El resultado era que el puente **no arrancaba** por no poder
            # escribir el histórico, que es exactamente lo que esta garantía
            # promete evitar.
            logger.error("no se pudo abrir el histórico en %s: %s", path, error)
            self._connection = None

    @property
    def enabled(self) -> bool:
        return self._connection is not None

    def close(self) -> None:
        if self._connection is None:
            return

        try:
            self._connection.commit()
            self._connection.close()
        except sqlite3.Error as error:
            logger.warning("error al cerrar el histórico: %s", error)
        finally:
            self._connection = None

    # ── Escritura ─────────────────────────────────────────────────────────

    def record_observation(
        self,
        observation: Observation,
        vehicle_id: str,
        now: float,
    ) -> None:
        self._execute(
            """
            INSERT INTO observations (
                at, observed_at, session_id, route_id, linea, lat, lon,
                speed, heading, accuracy, motion_activity,
                distance_to_route_m, heading_diff_deg, progress, vehicle_id
            ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
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
            ),
            kind="observations",
        )

    def record_rejection(
        self,
        reason: RejectReason,
        detail: str,
        now: float,
    ) -> None:
        self._execute(
            "INSERT INTO rejections (at, reason, detail) VALUES (?, ?, ?)",
            (now, reason.value, detail[:MAX_DETAIL_LENGTH]),
            kind="rejections",
        )

    def record_vehicle(
        self,
        vehicle: EstimatedVehicle,
        now: float,
    ) -> None:
        self._execute(
            """
            INSERT INTO vehicle_positions (
                at, observed_at, vehicle_id, route_id, linea, lat, lon,
                speed, heading, sessions, samples
            ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
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
            ),
            kind="vehicle_positions",
        )

    def _execute(self, sql: str, params: tuple[Any, ...], kind: str) -> None:
        """Ejecuta una inserción sin dejar que un fallo tumbe el puente."""
        if self._connection is None:
            return

        try:
            self._connection.execute(sql, params)

            setattr(self.counts, kind, getattr(self.counts, kind) + 1)
            self._pending += 1
        except sqlite3.Error as error:
            self.counts.write_errors += 1

            # Se avisa solo en el primer fallo de cada ráfaga: si el disco está
            # lleno, no interesa inundar el registro con una línea por mensaje.
            if self.counts.write_errors == 1:
                logger.error(
                    "no se pudo escribir en el histórico (%s); el puente "
                    "continúa sin persistencia",
                    error,
                )

    # ── Mantenimiento ─────────────────────────────────────────────────────

    def flush(self) -> None:
        """Confirma lo pendiente. Se llama desde el mantenimiento periódico."""
        if self._connection is None or self._pending == 0:
            return

        try:
            self._connection.commit()
            self._pending = 0
        except sqlite3.Error as error:
            self.counts.write_errors += 1
            logger.error("no se pudo confirmar el histórico: %s", error)

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
                    f"DELETE FROM {tabla} WHERE at < ?", (cutoff,)
                )
                borradas += cursor.rowcount or 0

            self._connection.commit()

            if borradas:
                logger.info(
                    "retención: %d fila(s) anteriores a %.0f días eliminadas",
                    borradas,
                    self.retention_days,
                )
        except sqlite3.Error as error:
            self.counts.write_errors += 1
            logger.error("no se pudo aplicar la retención: %s", error)

        return borradas

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
