"""S02: migración, aislamiento y fallos. Solo bases temporales; sin MQTT.

Preparadas para ejecución autorizada. Importar/compilar el archivo no las ejecuta.
"""

from __future__ import annotations

import io
import json
import sqlite3
from pathlib import Path
from types import SimpleNamespace

import pytest

from rutautp_backend import persistence_migrations
from rutautp_backend.models import EstimatedVehicle, Observation, RejectReason
from rutautp_backend.persistence import SCHEMA, ObservationStore, SimulationPersistenceUnavailable
from rutautp_backend.simulation_models import (
    DataOrigin, SimulationActorRecord, SimulationRunRecord, SimulationRunStatus, SourceContext,
)

NOW = 1_700_000_000.0
RUN = "5bdb08e8-e971-4a9e-a18e-47f359841321"
OTHER_RUN = "f238fb5a-d352-43df-87f5-50782a3af451"
SESSION = "c58e47f5-7a2b-44d3-b657-e794b54c19ae"
SOURCE = SourceContext(DataOrigin.SIMULATED, RUN, "sim-001")


def observation() -> Observation:
    return Observation(
        session_id=SESSION, route_id="17350695", linea="C-01", lat=-8.11, lon=-79.006,
        speed=8.0, heading=170.0, accuracy=8.0, motion_activity="automotive",
        timestamp=NOW, distance_to_route_m=3.5, heading_diff_deg=4.2, progress=0.51,
    )


def vehicle() -> EstimatedVehicle:
    return EstimatedVehicle(
        vehicle_id="sim:vehicle-1", route_id="17350695", linea="C-01", lat=-8.11,
        lon=-79.006, speed=8.0, heading=170.0, timestamp=NOW, last_seen=NOW,
    )


def run_record(run_id: str = RUN) -> SimulationRunRecord:
    return SimulationRunRecord(
        run_id=run_id, scenario_id="pasajeros-30", scenario_version=1, seed=20261021,
        manifest_sha256="a" * 64,
        feed_sha256={name: "b" * 64 for name in (
            "routes.txt", "trips.txt", "shapes.txt", "stops.txt", "stop_times.txt",
        )}, created_at=NOW - 10,
    )


def start_run(store: ObservationStore, run_id: str = RUN) -> None:
    store.create_simulation_run(run_record(run_id))
    store.set_simulation_run_status(run_id, SimulationRunStatus.RUNNING, NOW - 5)
    store.record_simulation_actor(SimulationActorRecord(
        run_id, "sim-001", SESSION, "scenario-bus-01", "17350695", NOW - 1,
    ))


@pytest.fixture
def store(tmp_path: Path):
    instance = ObservationStore(tmp_path / "history.sqlite", min_simulation_free_bytes=0)
    yield instance
    instance.close()


@pytest.fixture
def legacy(tmp_path: Path):
    """Mantiene WAL abierto para que el backup deba incorporar sus commits."""
    path = tmp_path / "legacy.sqlite"
    connection = sqlite3.connect(path)
    connection.execute("PRAGMA journal_mode=WAL")
    connection.executescript(SCHEMA)
    connection.execute(
        "INSERT INTO observations (at, observed_at, session_id, route_id, linea, lat, lon, "
        "speed, heading, accuracy, motion_activity, distance_to_route_m, heading_diff_deg, "
        "progress, vehicle_id) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)",
        (NOW - 100, NOW - 101, "old-session", "old-route", "old-line", -8, -79,
         1, -1, 8, "stationary", 2, 0, 0.5, "old-vehicle"),
    )
    connection.execute("INSERT INTO rejections(at, reason, detail) VALUES (?, ?, ?)",
                       (NOW - 100, "duplicate", "legacy detail"))
    connection.execute(
        "INSERT INTO vehicle_positions (at, observed_at, vehicle_id, route_id, linea, "
        "lat, lon, speed, heading, sessions, samples) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)",
        (NOW - 100, NOW - 101, "old-vehicle", "old-route", "old-line", -8, -79, 1, -1, 2, 3),
    )
    connection.commit()
    original = {name: connection.execute(f"SELECT * FROM {name}").fetchall()
                for name in ("observations", "rejections", "vehicle_positions")}
    yield path, connection, original
    connection.close()


def test_migration_preserves_every_legacy_value_and_wal_backup(legacy):
    path, _, original = legacy
    migrated = ObservationStore(path)
    try:
        assert migrated.enabled
        assert migrated.query("PRAGMA user_version") == [(2,)]
        assert migrated.migration_backup is not None
        with sqlite3.connect(migrated.migration_backup) as backup:
            assert backup.execute("PRAGMA user_version").fetchone() == (0,)
            for table, rows in original.items():
                assert backup.execute(f"SELECT * FROM {table}").fetchall() == rows
        for table, rows in original.items():
            result = migrated.query(f"SELECT * FROM {table}")
            added = 4 if table == "vehicle_positions" else 2
            assert [row[:-added] for row in result] == rows
            assert all(row[len(row)-added:len(row)-added+2] == ("legacy_unknown", None) for row in result)
    finally:
        migrated.close()


def test_reopen_is_idempotent_and_preserves_foreign_keys(legacy):
    path, _, _ = legacy
    first = ObservationStore(path)
    backup = first.migration_backup
    first.close()
    second = ObservationStore(path)
    try:
        assert second.enabled and second.migration_backup is None
        assert second.query("PRAGMA foreign_keys") == [(1,)]
        assert second.query("SELECT COUNT(*) FROM store_schema_migrations") == [(2,)]
        assert len(list((path.parent / "backups").glob("*.sqlite"))) == 1
        assert backup.is_file()
    finally:
        second.close()


def test_failed_migration_rolls_back_schema_and_values(legacy, monkeypatch):
    path, _, original = legacy

    def reject(_):
        raise persistence_migrations.StoreMigrationError("injected verification failure")

    monkeypatch.setattr(persistence_migrations, "_verify_current", reject)
    failed = ObservationStore(path)
    assert not failed.enabled
    with sqlite3.connect(path) as connection:
        assert connection.execute("PRAGMA user_version").fetchone() == (0,)
        for table, rows in original.items():
            assert connection.execute(f"SELECT * FROM {table}").fetchall() == rows
        assert not connection.execute(
            "SELECT name FROM sqlite_master WHERE name='simulation_runs'"
        ).fetchall()
    assert list((path.parent / "backups").glob("*.sqlite"))


def test_future_schema_is_not_downgraded(tmp_path):
    path = tmp_path / "future.sqlite"
    with sqlite3.connect(path) as connection:
        connection.execute("PRAGMA user_version=99")
    assert not ObservationStore(path).enabled
    with sqlite3.connect(path) as connection:
        assert connection.execute("PRAGMA user_version").fetchone() == (99,)


def test_version_without_migration_record_is_not_adopted(tmp_path):
    path = tmp_path / "incomplete.sqlite"
    initial = ObservationStore(path)
    initial.close()
    with sqlite3.connect(path) as connection:
        connection.execute("DELETE FROM store_schema_migrations")
    assert not ObservationStore(path).enabled


def test_new_records_keep_distinct_origins_and_ground_truth(store):
    start_run(store)
    store.record_observation(observation(), "observed-1", NOW)
    store.record_observation(observation(), "sim-vehicle-1", NOW, source=SOURCE)
    store.record_vehicle(vehicle(), NOW, source=SOURCE)
    store.record_rejection(RejectReason.DUPLICATE, "unknown", NOW)
    store.record_rejection(RejectReason.DUPLICATE, "known", NOW, source=SOURCE)
    store.flush()
    assert store.query("SELECT data_origin, simulation_run_id FROM observations ORDER BY id") == [
        ("observed", None), ("simulated", RUN),
    ]
    assert store.query("SELECT data_origin FROM rejections ORDER BY id") == [("unknown",), ("simulated",)]
    assert store.query("SELECT scenario_vehicle_id FROM simulation_actors") == [("scenario-bus-01",)]
    assert store.query("SELECT data_origin, simulation_run_id FROM vehicle_positions") == [("simulated", RUN)]


def test_actor_reference_is_idempotent_but_cannot_be_reassigned(store):
    start_run(store)
    store.record_simulation_actor(SimulationActorRecord(
        RUN, "sim-001", SESSION, "scenario-bus-01", "17350695", NOW - 1,
    ))
    assert store.query("SELECT COUNT(*) FROM simulation_actors") == [(1,)]
    with pytest.raises(ValueError):
        store.record_observation(observation(), "v", NOW, source=SourceContext(DataOrigin.SIMULATED, RUN, "sim-002"))
    store.end_simulation_actor(RUN, SESSION, NOW - 0.5)
    with pytest.raises(ValueError):
        store.record_observation(observation(), "v", NOW, source=SOURCE)


def test_readonly_write_pauses_simulation_and_observed_call_still_does_not_raise(store):
    start_run(store)
    store.flush()
    store._connection.execute("PRAGMA query_only=ON")
    with pytest.raises(SimulationPersistenceUnavailable):
        store.record_observation(observation(), "v", NOW, source=SOURCE)
    store.record_observation(observation(), "observed", NOW)
    status = store.simulation_storage_status()
    assert not status["available"] and RUN in status["incompleteRunIds"]
    assert store.counts.write_errors == 2


def test_disk_preflight_only_blocks_synthetic_writes(store, monkeypatch):
    start_run(store)
    store.flush()
    store._min_simulation_free_bytes = 1
    store._last_space_check = float("-inf")
    monkeypatch.setattr("rutautp_backend.persistence.shutil.disk_usage", lambda _: SimpleNamespace(free=0))
    with pytest.raises(SimulationPersistenceUnavailable):
        store.record_observation(observation(), "v", NOW, source=SOURCE)
    store.record_observation(observation(), "observed", NOW)
    assert store.flush()
    assert store.query("SELECT data_origin FROM observations") == [("observed",)]


def test_commit_failure_cannot_complete_run(store):
    start_run(store)
    store.record_observation(observation(), "v", NOW, source=SOURCE)
    real = store._connection

    class CommitFailure:
        def commit(self):
            raise sqlite3.OperationalError("injected commit failure")

    store._connection = CommitFailure()
    try:
        assert not store.flush()
        assert RUN in store.simulation_storage_status()["incompleteRunIds"]
        with pytest.raises(SimulationPersistenceUnavailable):
            store.set_simulation_run_status(RUN, SimulationRunStatus.COMPLETED, NOW + 1)
    finally:
        store._connection = real


def test_interrupted_run_cannot_be_reported_complete_after_reopen(tmp_path):
    path = tmp_path / "interrupted.sqlite"
    first = ObservationStore(path)
    start_run(first)
    first.close()
    second = ObservationStore(path)
    try:
        with pytest.raises(SimulationPersistenceUnavailable):
            second.set_simulation_run_status(RUN, SimulationRunStatus.COMPLETED, NOW + 1)
        second.set_simulation_run_status(RUN, SimulationRunStatus.FAILED, NOW + 1, reason="restart")
        assert second.query("SELECT status, history_complete FROM simulation_runs") == [("failed", 0)]
    finally:
        second.close()


def test_disabled_storage_refuses_simulation():
    disabled = ObservationStore(None)
    with pytest.raises(SimulationPersistenceUnavailable):
        disabled.create_simulation_run(run_record())
    disabled.record_observation(observation(), "v", NOW)
    assert disabled.counts.observations == 0


def test_export_keeps_provenance_and_filters_run(store):
    start_run(store)
    store.record_observation(observation(), "observed", NOW)
    store.record_observation(observation(), "simulated", NOW, source=SOURCE)
    output = io.StringIO()
    assert store.export_jsonl(output, "observations", run_id=RUN) == 1
    row = json.loads(output.getvalue())
    assert row["data_origin"] == "simulated" and row["simulation_run_id"] == RUN
    assert row["session_id"] == SESSION and row["route_id"] == "17350695"
    assert row["accuracy"] == 8 and row["vehicle_id"] == "simulated"
    with pytest.raises(ValueError):
        list(store.iter_export_rows("observations; DROP TABLE observations"))


def test_purge_targets_one_run_and_preserves_legacy_observed_and_other_run(legacy):
    path, _, _ = legacy
    instance = ObservationStore(path)
    try:
        start_run(instance)
        instance.record_observation(observation(), "sim-a", NOW, source=SOURCE)
        instance.record_observation(observation(), "observed", NOW)
        instance.end_simulation_actor(RUN, SESSION, NOW + 1)
        instance.set_simulation_run_status(RUN, SimulationRunStatus.COMPLETED, NOW + 2)
        start_run(instance, OTHER_RUN)
        instance.record_observation(observation(), "sim-b", NOW,
                                    source=SourceContext(DataOrigin.SIMULATED, OTHER_RUN, "sim-001"))
        assert instance.purge_simulation_detail(RUN, NOW + 3) == 2
        assert instance.query("SELECT data_origin FROM observations ORDER BY id") == [
            ("legacy_unknown",), ("observed",), ("simulated",),
        ]
        assert instance.query("SELECT COUNT(*) FROM simulation_runs") == [(2,)]
        assert instance.query("SELECT detail_purged_before FROM simulation_runs WHERE run_id=?", (RUN,)) == [(NOW + 3,)]
        with pytest.raises(ValueError):
            instance.purge_simulation_detail(OTHER_RUN, NOW + 3)
    finally:
        instance.close()


def test_general_retention_does_not_apply_to_synthetic_detail(tmp_path):
    instance = ObservationStore(tmp_path / "retention.sqlite", retention_days=1)
    try:
        start_run(instance)
        instance.record_observation(observation(), "sim", NOW, source=SOURCE)
        instance.record_observation(observation(), "observed", NOW)
        assert instance.prune(NOW + 5 * 86400) == 1
        assert instance.query("SELECT data_origin FROM observations") == [("simulated",)]
    finally:
        instance.close()
