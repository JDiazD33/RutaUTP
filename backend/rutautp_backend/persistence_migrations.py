"""Migraciones aditivas del histórico; nunca se ejecutan al importar el módulo."""

from __future__ import annotations

import os
import logging
import shutil
import sqlite3
import time
import uuid
from pathlib import Path

STORE_SCHEMA_VERSION = 1
MIN_FREE_BYTES = 16 * 1024 * 1024
MIGRATION_NAME = "001_simulation_provenance.sql"
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
    destination = directory / f"{path.name}.schema-0-{time.time_ns()}-{uuid.uuid4().hex}.sqlite"
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


def _verify_current(connection: sqlite3.Connection) -> None:
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


def migrate_store(connection: sqlite3.Connection, path: Path, legacy_schema: str) -> Path | None:
    """Migra 0→1 una vez; versiones futuras/desconocidas fallan sin adoptar datos.

    La aplicación abrirá este método al desplegar/arrancar, nunca por importar.
    Una base existente requiere backup previo. No se ofrece downgrade destructivo.
    """
    version = connection.execute("PRAGMA user_version").fetchone()[0]
    if version == STORE_SCHEMA_VERSION:
        _verify_current(connection)
        record = connection.execute(
            "SELECT migration_name FROM store_schema_migrations WHERE version=?",
            (STORE_SCHEMA_VERSION,),
        ).fetchone()
        if record != (MIGRATION_NAME,):
            raise StoreMigrationError("versión sin registro de migración consistente")
        return None
    if version != 0:
        raise StoreMigrationError(f"versión de histórico no soportada: {version}")
    if connection.in_transaction:
        raise StoreMigrationError("no migrar con una transacción abierta")
    tables = {row[0] for row in connection.execute(
        "SELECT name FROM sqlite_master WHERE type='table' AND name NOT LIKE 'sqlite_%'"
    )}
    existing = bool(tables)
    if existing:
        if not set(LEGACY_COLUMNS) <= tables:
            raise StoreMigrationError("la base no tiene las tres tablas históricas esperadas")
        if tables & {"simulation_runs", "simulation_actors", "store_schema_migrations"}:
            raise StoreMigrationError("migración parcial o versión ausente; revisar la base")
        for table, required in LEGACY_COLUMNS.items():
            columns = _columns(connection, table)
            if not required <= columns or columns & {"data_origin", "simulation_run_id"}:
                raise StoreMigrationError(f"tabla histórica incompatible: {table}")
    sql = (Path(__file__).parent / "migrations" / MIGRATION_NAME).read_text(encoding="utf-8")
    backup = backup_database(connection, path) if existing else None
    if backup is not None:
        logger.info("backup previo a migración del histórico: %s", backup)
    try:
        connection.executescript("BEGIN IMMEDIATE;\n" + ("" if existing else legacy_schema) + sql)
        _verify_current(connection)
        connection.execute(
            "INSERT INTO store_schema_migrations VALUES (?, ?, ?, ?)",
            (STORE_SCHEMA_VERSION, MIGRATION_NAME, time.time(), str(backup) if backup else None),
        )
        connection.execute(f"PRAGMA user_version={STORE_SCHEMA_VERSION}")
        connection.commit()
    except (sqlite3.Error, StoreMigrationError):
        connection.rollback()
        raise
    return backup
