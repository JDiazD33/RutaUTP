"""Migraciones aditivas del histórico; nunca se ejecutan al importar el módulo."""

from __future__ import annotations

import os
import logging
import shutil
import sqlite3
import time
import uuid
from pathlib import Path

STORE_SCHEMA_VERSION = 2
MIN_FREE_BYTES = 16 * 1024 * 1024
MIGRATION_NAME = "002_scenario_occupancy.sql"
MIGRATIONS = {1: "001_simulation_provenance.sql", 2: MIGRATION_NAME}
logger = logging.getLogger(__name__)
LEGACY_COLUMNS = {
    "observations": {
        "id", "at", "observed_at", "session_id", "route_id", "linea", "lat", "lon",
        "speed", "heading", "accuracy", "motion_activity", "distance_to_route_m",
        "heading_diff_deg", "progress", "vehicle_id",
    },
    "rejections": {"id", "at", "reason", "detail"},
    "vehicle_positions": {
        "id", "at", "observed_at", "vehicle_id", "route_id", "linea", "lat", "lon",
        "speed", "heading", "sessions", "samples",
    },
}


class StoreMigrationError(RuntimeError):
    pass


def backup_database(connection: sqlite3.Connection, path: Path) -> Path:
    """Snapshot consistente mediante SQLite, incluido lo confirmado en WAL."""
    if connection.in_transaction:
        raise StoreMigrationError("confirmar pendientes antes de crear el backup")
    estimated_bytes = (
        connection.execute("PRAGMA page_count").fetchone()[0]
        * connection.execute("PRAGMA page_size").fetchone()[0]
    )
    if shutil.disk_usage(path.parent).free < estimated_bytes + MIN_FREE_BYTES:
        raise StoreMigrationError("espacio insuficiente para backup y migración")
    directory = path.parent / "backups"
    directory.mkdir(mode=0o700, exist_ok=True)
    version = connection.execute("PRAGMA user_version").fetchone()[0]
    destination = directory / f"{path.name}.schema-{version}-{time.time_ns()}-{uuid.uuid4().hex}.sqlite"
    descriptor = os.open(destination, os.O_CREAT | os.O_EXCL | os.O_WRONLY, 0o600)
    os.close(descriptor)
    target = None
    try:
        target = sqlite3.connect(str(destination))
        connection.backup(target)
        if target.execute("PRAGMA quick_check").fetchall() != [("ok",)]:
            raise StoreMigrationError("el backup no supera quick_check")
        return destination
    except (sqlite3.Error, OSError, StoreMigrationError):
        if target is not None:
            target.close()
            target = None
        destination.unlink(missing_ok=True)
        raise
    finally:
        if target is not None:
            target.close()


def _columns(connection: sqlite3.Connection, table: str) -> set[str]:
    # Solo se llama con nombres constantes de este módulo.
    return {row[1] for row in connection.execute(f"PRAGMA table_info({table})")}


def _verify_v1(connection: sqlite3.Connection) -> None:
    for table, columns in LEGACY_COLUMNS.items():
        if not (columns | {"data_origin", "simulation_run_id"}) <= _columns(connection, table):
            raise StoreMigrationError(f"esquema incompleto: {table}")
    required = {
        "simulation_runs": {"run_id", "data_origin", "scenario_id", "scenario_version", "seed",
                            "manifest_sha256", "feed_hashes_json", "created_at", "started_at",
                            "ended_at", "status", "reason", "totals_json", "history_complete", "detail_purged_before"},
        "simulation_actors": {"simulation_run_id", "data_origin", "session_id", "principal",
                              "scenario_vehicle_id", "route_id", "boarded_at", "left_at", "leave_reason"},
        "store_schema_migrations": {"version", "migration_name", "applied_at", "backup_path"},
    }
    for table, columns in required.items():
        if not columns <= _columns(connection, table):
            raise StoreMigrationError(f"esquema incompleto: {table}")


def _verify_current(connection: sqlite3.Connection) -> None:
    _verify_v1(connection)
    if not {"scenario_occupancy", "occupancy_script_version"} <= _columns(connection, "vehicle_positions"):
        raise StoreMigrationError("esquema incompleto: ocupación de escenario")


def verify_migration_records(connection: sqlite3.Connection, version: int) -> None:
    for number in range(1, version + 1):
        row = connection.execute(
            "SELECT migration_name FROM store_schema_migrations WHERE version=?", (number,)
        ).fetchone()
        if row is None or row[0] != MIGRATIONS[number]:
            raise StoreMigrationError("versión sin registro de migración consistente")


def migrate_store(connection: sqlite3.Connection, path: Path, legacy_schema: str) -> Path | None:
    """Migraciones 0→1→2 aditivas, transaccionales y con backup de bases existentes."""
    version = connection.execute("PRAGMA user_version").fetchone()[0]
    if version not in (0, 1, 2):
        raise StoreMigrationError(f"versión de histórico no soportada: {version}")
    if connection.in_transaction:
        raise StoreMigrationError("no migrar con una transacción abierta")
    tables = {row[0] for row in connection.execute(
        "SELECT name FROM sqlite_master WHERE type='table' AND name NOT LIKE 'sqlite_%'"
    )}
    existing = bool(tables)
    if version:
        _verify_current(connection) if version == 2 else _verify_v1(connection)
        verify_migration_records(connection, version)
        if version == 1 and {"scenario_occupancy", "occupancy_script_version"} & _columns(connection, "vehicle_positions"):
            raise StoreMigrationError("migración de ocupación parcial")
        if version == STORE_SCHEMA_VERSION:
            return None
    elif existing:
        if not set(LEGACY_COLUMNS) <= tables:
            raise StoreMigrationError("la base no tiene las tres tablas históricas esperadas")
        if tables & {"simulation_runs", "simulation_actors", "store_schema_migrations"}:
            raise StoreMigrationError("migración parcial o versión ausente; revisar la base")
        for table, required in LEGACY_COLUMNS.items():
            columns = _columns(connection, table)
            if not required <= columns or columns & {"data_origin", "simulation_run_id", "scenario_occupancy", "occupancy_script_version"}:
                raise StoreMigrationError(f"tabla histórica incompatible: {table}")
    scripts = [(number, (Path(__file__).parent / "migrations" / MIGRATIONS[number]).read_text(encoding="utf-8"))
               for number in range(version + 1, STORE_SCHEMA_VERSION + 1)]
    backup = backup_database(connection, path) if existing else None
    if backup is not None:
        logger.info("backup previo a migración del histórico: %s", backup)
    try:
        connection.executescript("BEGIN IMMEDIATE;\n" + ("" if existing else legacy_schema)
                                 + "\n".join(sql for _, sql in scripts))
        _verify_current(connection)
        for number, _ in scripts:
            connection.execute("INSERT INTO store_schema_migrations VALUES (?, ?, ?, ?)",
                (number, MIGRATIONS[number], time.time(), str(backup) if backup else None))
        connection.execute(f"PRAGMA user_version={STORE_SCHEMA_VERSION}")
        connection.commit()
    except (sqlite3.Error, StoreMigrationError):
        connection.rollback()
        raise
    return backup
