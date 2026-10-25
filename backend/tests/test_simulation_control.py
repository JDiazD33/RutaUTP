"""S04: control/CLI/puente con reloj inyectado y SQLite temporal, sin MQTT."""

from datetime import datetime
import json
import os
from pathlib import Path
import sqlite3
from types import SimpleNamespace

import pytest

from rutautp_backend.bridge import Bridge
from rutautp_backend.config import Config
from rutautp_backend.simulation_admin import main, status
from rutautp_backend.simulation_control import SimulationController
from rutautp_backend.simulation_control_store import ControlStore, ControlUnavailable
from rutautp_backend.simulation_profile import lima_zone, SimulationProfile
from rutautp_backend.simulation_models import SimulationActorRecord
from rutautp_backend.persistence import ObservationStore
from .conftest import GTFS_DIR
from .test_bridge import CapturingPublisher, payload_for, topic_for
from .test_simulation_ingress import SESSION, SESSION_2, synthetic_topic

LIMA = lima_zone()


class Clock:
    def __init__(self, hour=12, minute=0, second=0):
        self.now = datetime(2026, 10, 21, hour, minute, second, tzinfo=LIMA).timestamp()
        self.mono = 100.0

    def advance(self, seconds, *, wall=None):
        self.now += seconds if wall is None else wall
        self.mono += seconds


class ControlPublisher:
    def __init__(self):
        self.messages = []

    def __call__(self, topic, raw):
        mid = len(self.messages) + 1
        self.messages.append((mid, topic, json.loads(raw)))
        return mid


@pytest.fixture(scope="session")
def profile():
    return SimulationProfile.load("pasajeros-30", GTFS_DIR)


@pytest.fixture
def rig(tmp_path, profile):
    clock = Clock()
    control = ControlStore.initialize(tmp_path / "control/control.sqlite", clock.now)
    history = ObservationStore(tmp_path / "history.sqlite", min_simulation_free_bytes=0)
    control.enable(profile.pinned(), clock.now)
    controller = SimulationController(control, history, GTFS_DIR, monotonic_clock=lambda: clock.mono)
    publisher = ControlPublisher()
    item = SimpleNamespace(clock=clock, control=control, history=history,
                           controller=controller, publisher=publisher)
    yield item
    item.controller.close(clock.now)
    history.close()


def tick(rig, ack=False):
    body = rig.controller.tick(rig.clock.now, rig.publisher)
    if ack and rig.publisher.messages:
        rig.controller.acknowledge(rig.publisher.messages[-1][0], rig.clock.now)
    return body


def crash(controller):
    # Libera solo el descriptor del proceso muerto, sin hacer shutdown limpio.
    os.close(controller._owner_fd)
    controller._closed = True


def restart(rig):
    crash(rig.controller)
    rig.controller = SimulationController(rig.control, rig.history, GTFS_DIR,
                                          monotonic_clock=lambda: rig.clock.mono)


def test_initialization_is_disabled_private_and_never_overwrites(tmp_path):
    path = tmp_path / "private/control.sqlite"
    store = ControlStore.initialize(path, 100)
    before = path.read_bytes()
    assert store.read()["enabled"] is False
    assert status(store, 100)["producer"]["status"] == "unknown"
    assert path.read_bytes() == before
    assert path.stat().st_mode & 0o777 == 0o600
    assert path.parent.stat().st_mode & 0o777 == 0o700
    with pytest.raises(ControlUnavailable):
        ControlStore.initialize(path, 101)
    assert path.read_bytes() == before


def test_missing_state_is_not_created_by_status(tmp_path):
    path = tmp_path / "missing/control.sqlite"
    with pytest.raises(ControlUnavailable):
        ControlStore(path).read()
    assert not path.exists() and not path.parent.exists()


def test_enable_creates_durable_generation_and_requires_puback(rig):
    body = tick(rig)
    assert body["enabled"] and len(body) == 8
    assert body["validUntil"] == rig.clock.now + 15
    assert body["controlRevision"] == 3
    assert rig.history.query("SELECT status FROM simulation_runs") == [("running",)]
    assert rig.controller.admission(rig.clock.now) is None
    saved = status(rig.control, rig.clock.now)
    assert saved["backend"]["appliedRevision"] == body["controlRevision"]
    assert saved["mqtt"]["lastEnqueuedRevision"] == body["controlRevision"]
    assert saved["mqtt"]["lastAckedRevision"] is None
    rig.controller.acknowledge(999, rig.clock.now)
    assert rig.controller.admission(rig.clock.now) is None
    rig.controller.acknowledge(rig.publisher.messages[-1][0], rig.clock.now)
    assert rig.controller.admission(rig.clock.now).run_id == body["runId"]


def test_heartbeat_renews_same_revision_every_five_seconds(rig):
    first = tick(rig, ack=True)
    rig.clock.advance(4)
    tick(rig)
    assert len(rig.publisher.messages) == 1
    rig.clock.advance(1)
    second = tick(rig, ack=True)
    assert len(rig.publisher.messages) == 2
    assert first["controlRevision"] == second["controlRevision"]
    assert second["validUntil"] == rig.clock.now + 15
    assert rig.controller.admission(rig.clock.now).valid_until == second["validUntil"]


def test_disable_is_persistent_and_does_not_delete_history(rig):
    body = tick(rig, ack=True)
    rig.control.disable(rig.clock.now, "operator")
    assert rig.controller.admission(rig.clock.now) is None
    off = tick(rig, ack=True)
    assert not off["enabled"] and off["validUntil"] == off["issuedAt"]
    assert off["runId"] == body["runId"]
    assert off["controlRevision"] > body["controlRevision"]
    restart(rig)
    assert not tick(rig)["enabled"]
    assert rig.history.query("SELECT COUNT(*) FROM simulation_runs") == [(1,)]
    assert rig.control.read()["enabled"] is False


def test_restart_never_reuses_running_generation(rig):
    first = tick(rig, ack=True)
    restart(rig)
    second = tick(rig)
    assert second["runId"] != first["runId"]
    assert second["controlRevision"] > first["controlRevision"]
    assert rig.controller.admission(rig.clock.now) is None
    assert rig.history.query("SELECT status FROM simulation_runs ORDER BY rowid") == [("failed",), ("running",)]


def test_enable_before_opening_waits_then_starts_at_seven(rig):
    rig.clock.now = datetime(2026, 10, 21, 6, 59, 55, tzinfo=LIMA).timestamp()
    off = tick(rig)
    assert not off["enabled"] and rig.control.read()["enabled"]
    assert rig.history.query("SELECT COUNT(*) FROM simulation_runs") == [(0,)]
    rig.clock.advance(5)
    on = tick(rig, ack=True)
    assert on["enabled"] and rig.controller.admission(rig.clock.now)


def test_closing_boundary_revokes_without_exceeding_service_end(rig):
    rig.clock.now = datetime(2026, 10, 21, 22, 29, 55, tzinfo=LIMA).timestamp()
    body = tick(rig, ack=True)
    assert body["validUntil"] == body["serviceEndsAt"] == rig.clock.now + 5
    rig.clock.advance(5)
    off = tick(rig, ack=True)
    assert not off["enabled"] and rig.controller.admission(rig.clock.now) is None
    assert rig.control.read()["enabled"] and rig.control.read()["owner"] is None
    assert rig.history.query("SELECT status FROM simulation_runs") == [("disabled",)]
    revision = rig.control.read()["revision"]
    rig.clock.advance(1)
    tick(rig)
    assert rig.control.read()["revision"] == revision


def test_run_duration_is_bounded_without_automatic_restart(rig):
    tick(rig, ack=True)
    # Reloj inyectado en pasos inferiores al detector de suspensión; no sleep.
    for _ in range(90):
        rig.clock.advance(10)
        tick(rig, ack=True)
    assert rig.control.read()["enabled"] is False
    assert rig.control.read()["reason"] == "max_run_duration"
    assert rig.history.query("SELECT COUNT(*) FROM simulation_runs") == [(1,)]


def test_missing_puback_disarms_after_fifteen_seconds(rig):
    tick(rig)
    rig.clock.advance(15)
    off = tick(rig)
    assert not off["enabled"]
    assert rig.control.read()["reason"] == "control_ack_timeout"
    assert rig.controller.admission(rig.clock.now) is None


def test_lost_renewal_expires_and_does_not_accumulate_messages(rig):
    tick(rig, ack=True)
    rig.clock.advance(5)
    tick(rig)  # sin acuse de esta renovación
    rig.clock.advance(5)
    tick(rig)
    assert len(rig.publisher.messages) == 2
    rig.clock.advance(5)
    off = tick(rig)
    assert not off["enabled"]
    assert rig.control.read()["reason"] == "control_lease_expired"
    assert len(rig.publisher.messages) == 3  # añade revocación, no otro lease


@pytest.mark.parametrize("wall,elapsed", [(31, 1), (-20, 1), (20, 20)])
def test_civil_clock_jump_or_suspension_persistently_pauses(rig, wall, elapsed):
    tick(rig, ack=True)
    rig.clock.advance(elapsed, wall=wall)
    tick(rig)
    assert not rig.control.read()["enabled"]
    assert rig.control.read()["reason"] == "civil_clock_jump_or_suspension"
    assert rig.controller.admission(rig.clock.now) is None


def test_second_backend_controller_is_rejected(rig):
    with pytest.raises(ControlUnavailable, match="controlador"):
        SimulationController(rig.control, rig.history, GTFS_DIR)


def test_old_database_restore_cannot_reenable_and_recovery_only_disables(rig, tmp_path):
    backup = tmp_path / "old-control.sqlite"
    with sqlite3.connect(rig.control.path) as source, sqlite3.connect(backup) as target:
        source.backup(target)
    tick(rig, ack=True)
    rig.control.disable(rig.clock.now, "operator")
    high = rig.control.read()["revision"]
    with sqlite3.connect(backup) as source, sqlite3.connect(rig.control.path) as target:
        source.backup(target)
    with pytest.raises(ControlUnavailable, match="revisión"):
        rig.control.read()
    assert tick(rig) is None and rig.controller.error
    assert rig.controller.admission(rig.clock.now) is None
    recovered = rig.control.disable(rig.clock.now, "reviewed_restore", recover=True)
    assert not recovered["enabled"] and recovered["revision"] > high
    assert tick(rig) is None  # un controlador fallido requiere reinicio


def test_missing_anchor_stays_closed_without_recreating_it(rig):
    tick(rig, ack=True)
    rig.control.anchor.unlink()
    assert tick(rig) is None
    assert rig.controller.admission(rig.clock.now) is None
    assert not rig.control.anchor.exists()


def test_unknown_schema_is_rejected_without_downgrade(rig):
    with sqlite3.connect(rig.control.path) as db:
        db.execute("PRAGMA user_version=2")
    with pytest.raises(ControlUnavailable, match="versión"):
        rig.control.read()
    with sqlite3.connect(rig.control.path) as db:
        assert db.execute("PRAGMA user_version").fetchone() == (2,)


def test_incomplete_anchor_commit_requires_explicit_disabled_recovery(rig, monkeypatch):
    original = rig.control._write_anchor
    def fail_anchor(*_):
        raise OSError("injected anchor write failure")
    monkeypatch.setattr(rig.control, "_write_anchor", fail_anchor)
    with pytest.raises(ControlUnavailable):
        rig.control.disable(rig.clock.now, "operator")
    with pytest.raises(ControlUnavailable, match="revisión"):
        rig.control.read()
    assert tick(rig) is None
    monkeypatch.setattr(rig.control, "_write_anchor", original)
    assert rig.control.disable(rig.clock.now, "reviewed", recover=True)["enabled"] is False


def test_profile_change_during_admission_is_durably_revoked(rig, monkeypatch):
    tick(rig, ack=True)
    monkeypatch.setattr(SimulationProfile, "signatures", lambda *_: ("changed",))
    assert rig.controller.admission(rig.clock.now) is None
    assert not rig.control.read()["enabled"]
    assert tick(rig)["enabled"] is False


def test_wrong_feed_is_rejected_before_enabling(tmp_path):
    from rutautp_backend.simulation_models import FEED_HASH_FILES
    for name in FEED_HASH_FILES:
        (tmp_path / name).write_text("wrong-feed")
    with pytest.raises(ValueError, match="feed no coincide"):
        SimulationProfile.load("pasajeros-30", tmp_path)


def test_replaced_backend_lock_closes_previous_controller(rig):
    tick(rig, ack=True)
    rig.control.owner_lock.unlink()
    rig.control.owner_lock.touch(mode=0o600)
    assert tick(rig) is None
    assert rig.controller.admission(rig.clock.now) is None


def test_history_write_failure_does_not_prevent_disable_publication(rig):
    tick(rig, ack=True)
    rig.history._connection.execute("PRAGMA query_only=ON")
    rig.control.disable(rig.clock.now, "operator")
    off = tick(rig)
    assert off["enabled"] is False
    assert rig.controller.admission(rig.clock.now) is None
    assert rig.publisher.messages[-1][2]["enabled"] is False


def test_publisher_exception_leaves_no_permission_and_can_retry(rig):
    def broken(*_):
        raise RuntimeError("injected transport failure")
    rig.controller.tick(rig.clock.now, broken)
    assert rig.controller.error is None and rig.controller.admission(rig.clock.now) is None
    rig.clock.advance(5)
    tick(rig, ack=True)
    assert rig.controller.admission(rig.clock.now)


def test_reconnect_discards_old_lease_and_requires_fresh_ack(rig):
    tick(rig, ack=True)
    rig.controller.disconnected()
    assert rig.controller.admission(rig.clock.now) is None
    tick(rig)
    assert rig.controller.admission(rig.clock.now) is None
    rig.controller.acknowledge(rig.publisher.messages[-1][0], rig.clock.now)
    assert rig.controller.admission(rig.clock.now)


def test_stale_puback_cannot_revive_disabled_generation(rig):
    tick(rig)
    mid = rig.publisher.messages[-1][0]
    rig.control.disable(rig.clock.now, "operator")
    rig.controller.acknowledge(mid, rig.clock.now)
    assert rig.controller.admission(rig.clock.now) is None


def test_cli_init_enable_status_disable_only_changes_control(tmp_path, profile, monkeypatch, capsys):
    path = tmp_path / "cli/control.sqlite"
    monkeypatch.setattr("rutautp_backend.simulation_admin.time.time", lambda: Clock().now)
    prefix = ["--control-db", str(path), "--gtfs-dir", str(GTFS_DIR)]
    assert main([*prefix, "init"]) == 0
    assert json.loads(capsys.readouterr().out)["requestedEnabled"] is False
    assert main([*prefix, "enable", "--profile", "pasajeros-30"]) == 0
    result = json.loads(capsys.readouterr().out)
    assert result["requestedEnabled"] is True and result["runId"] is None
    assert result["backend"]["appliedRevision"] is None
    assert result["producer"]["status"] == "unknown"
    assert main([*prefix, "disable", "--reason", "operator"]) == 0
    assert json.loads(capsys.readouterr().out)["requestedEnabled"] is False
    assert main([*prefix, "status"]) == 0
    assert json.loads(capsys.readouterr().out)["mqtt"]["lastAckedRevision"] is None
    with sqlite3.connect(path) as db:
        assert [r[0] for r in db.execute("SELECT action FROM audit ORDER BY revision")] == ["init", "enable", "disable"]


def test_control_transport_uses_retained_only_for_control(config, feed):
    calls = []
    connected = [False]
    client = SimpleNamespace(is_connected=lambda: connected[0],
        publish=lambda *a, **kw: (calls.append((a, kw)) or SimpleNamespace(rc=0, mid=7)))
    bridge = Bridge(config, feed)
    control_publish = bridge._client_control_publisher(client)
    assert control_publish("rutautp/simulacion/estado", "{}") is None
    connected[0] = True
    assert control_publish("rutautp/vehiculos/x/posicion", "{}") is None
    assert control_publish("rutautp/simulacion/estado", "{}") == 7
    assert calls[-1][1] == {"qos": 1, "retain": True}
    bridge._client_publisher(client)("rutautp/vehiculos/x/posicion", "{}")
    assert calls[-1][1] == {"qos": 1, "retain": False}


def test_bridge_applies_admin_disable_before_tick_without_affecting_observed(rig, feed, sample_route):
    publisher = CapturingPublisher()
    config = Config(gtfs_dir=GTFS_DIR, database_path="", health_file="",
                    simulation_ingress_enabled=True, vehicle_position_schema_version=2)
    bridge = Bridge(config, feed, publisher, store=rig.history, simulation_control=rig.controller)
    bridge.control_publisher = rig.publisher
    bridge.tick(rig.clock.now)
    rig.controller.acknowledge(rig.publisher.messages[-1][0], rig.clock.now)
    run_id = rig.control.read()["runId"]
    for principal, session in (("sim-001", SESSION), ("sim-002", SESSION_2)):
        rig.history.record_simulation_actor(SimulationActorRecord(
            run_id, principal, session, "scenario-bus-01", sample_route.route_id, rig.clock.now,
        ))
        result = bridge.handle_message(synthetic_topic(principal, session, run_id),
            payload_for(sample_route, session=session, now=rig.clock.now), rig.clock.now)
        assert result.accepted
    assert publisher.count == 1
    rig.control.disable(rig.clock.now, "operator")
    rejected = bridge.handle_message(synthetic_topic(run=run_id),
        payload_for(sample_route, session=SESSION, now=rig.clock.now + 1), rig.clock.now + 1)
    assert not rejected.accepted and publisher.count == 1
    for index in range(2):
        session = f"observed-{index}"
        normal = bridge.handle_message(topic_for(session, f"device-{index}"),
            payload_for(sample_route, session=session, now=rig.clock.now + 1), rig.clock.now + 1)
        assert normal.accepted
    assert publisher.last()["dataOrigin"] == "observed"
    assert bridge._simulation_aggregator is None


def test_missing_control_database_keeps_bridge_and_observed_working(config, feed, sample_route, tmp_path):
    cfg = Config(**{**config.__dict__, "simulation_ingress_enabled": True,
                    "vehicle_position_schema_version": 2, "min_publish_principals": 2,
                    "simulation_control_path": str(tmp_path / "not-created/control.sqlite")})
    bridge = Bridge(cfg, feed)
    assert bridge.simulation_control is None
    assert bridge.handle_message(topic_for(), payload_for(sample_route), 1_700_000_000).accepted
    assert not (tmp_path / "not-created").exists()
