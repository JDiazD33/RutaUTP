"""S06: reloj inyectado, SQLite temporal, conexiones capturadas. Sin MQTT."""

from dataclasses import replace
from datetime import datetime
import io
import json
import sqlite3
from types import SimpleNamespace

import pytest

from rutautp_backend.bridge import Bridge
from rutautp_backend.models import OBSERVATION_FIELDS
from rutautp_backend.persistence import ObservationStore, SimulationPersistenceUnavailable
from rutautp_backend.simulation_admin import status
from rutautp_backend.simulation_control_store import ControlBusy, ControlStore, ControlUnavailable
from rutautp_backend.simulation_profile import lima_zone
from simulation.actors import ActorRunner, LocalAuthority, ProducerLock, new_instance_id
from simulation.clock import ClockSample
from simulation.__main__ import main
from simulation.scenario import ScenarioEngine
from .conftest import GTFS_DIR
from .test_bridge import CapturingPublisher
from .test_simulation_control import profile, rig, tick
from .test_simulation_geometry import profile_s05, geometries_s05
from .test_simulation_publisher import credentials_file


class Transport:
    def __init__(self, principals, run_id):
        self.channels = {p: None for p in principals}
        self.run_id = run_id
        self.messages = []
        self.discarded = []
        self.pending = set()
        self.revoked = self.closed = False
        self.online = True
        self.ready_principals = set(principals)
        self.deliver = None
    def ready(self, principal, sample):
        return self.online and not self.closed and principal in self.ready_principals
    def service(self, sample): pass
    def ensure_connections(self, active, sample): pass
    def publish(self, observation, sample):
        self.messages.append((observation, sample))
        if self.deliver: self.deliver(observation, sample)
        return True
    def discard(self, principal): self.discarded.append(principal)
    def discard_pending_publications(self):
        for principal in sorted(self.pending): self.discard(principal)
        self.pending.clear()
    def counts(self):
        return {"connections": 30 if self.online and not self.closed else 0,
                "readyActors": 30 if self.online and not self.closed else 0, "inflight": 0, "publishAcks": 0}
    def close(self): self.closed = True


def runner_for(rig, geometries, *, history=None, reference=None):
    body = tick(rig, ack=True)
    state = rig.control.read()
    engine = ScenarioEngine(rig.controller._profile, geometries, body["runId"], GTFS_DIR)
    authority = LocalAuthority(rig.control, engine.profile, body["runId"], body["controlRevision"],
                               state["owner"], GTFS_DIR, monotonic_clock=lambda: rig.clock.mono)
    transport = Transport(engine.profile.principals, body["runId"])
    clock = SimpleNamespace(read=lambda: ClockSample(rig.clock.now, rig.clock.mono))
    runner = ActorRunner(engine, rig.control, history or rig.history, transport, authority,
                         new_instance_id(), ProducerLock(rig.control), reference=reference, clock=clock)
    rig.runner = runner
    return runner


@pytest.fixture
def producer(rig, geometries_s05):
    runner = runner_for(rig, geometries_s05)
    yield SimpleNamespace(rig=rig, runner=runner, transport=runner.transport)
    runner.stop(ClockSample(rig.clock.now, rig.clock.mono))


def advance(producer, seconds=0):
    producer.rig.clock.advance(seconds)
    tick(producer.rig, ack=True)
    return producer.runner.step(ClockSample(producer.rig.clock.now, producer.rig.clock.mono))


def test_sessions_committed_before_first_observation_and_reference_is_separate(producer):
    output = io.StringIO()
    producer.runner.reference = output
    assert advance(producer)
    assert producer.rig.history.query("SELECT COUNT(*) FROM simulation_actors") == [(30,)]
    assert not producer.transport.messages
    assert advance(producer, .1)
    assert len(producer.transport.messages) == 1
    assert set(producer.transport.messages[0][0].payload()) == set(OBSERVATION_FIELDS)
    records = [json.loads(line) for line in output.getvalue().splitlines()]
    assert len(records) == 3  # cabecera y dos frames; no publica la verdad nominal
    assert producer.rig.history.query("SELECT COUNT(*) FROM observations") == [(0,)]


def test_central_monotonic_phases_jitter_and_no_actor_exceeds_cadence(producer):
    assert advance(producer)
    phases = sorted(producer.runner.next_due.values())
    assert phases[0] > 100 and phases[-1] < 105.25
    for _ in range(300): assert advance(producer, .1)
    grouped = {}
    for observation, stamp in producer.transport.messages:
        grouped.setdefault(observation.principal, []).append(stamp.monotonic)
        assert observation.timestamp == stamp.unix
    assert len(grouped) == 30
    assert all(b - a > 5 for times in grouped.values() for a, b in zip(times, times[1:]))
    assert producer.runner.calls == len(producer.transport.messages) < 180


def test_offline_ticks_drop_samples_without_backlog_or_budget_use(producer):
    producer.transport.online = False
    for _ in range(100): assert advance(producer, .1)
    assert producer.runner.calls == 0 and not producer.transport.messages
    producer.transport.online = True
    assert advance(producer, .1)
    assert len(producer.transport.messages) <= 1
    for _ in range(52): assert advance(producer, .1)
    counts = {}
    for obs, _ in producer.transport.messages: counts[obs.principal] = counts.get(obs.principal, 0) + 1
    assert max(counts.values()) <= 2 and producer.runner.calls <= 31


def test_durable_budget_reserved_before_publish_even_if_mqtt_fails(producer, monkeypatch):
    def failed(observation, sample):
        budget = producer.rig.control.runtime()["publishBudget"]
        assert budget["runs"][producer.runner.engine.run_id] == 1
        return False
    monkeypatch.setattr(producer.transport, "publish", failed)
    assert advance(producer)
    assert advance(producer, .1)
    assert producer.runner.calls == 1


def test_budget_exhaustion_stops_all_and_persists_disable(producer):
    producer.runner.manifest["limits"]["maxObservationPublishCallsPerRun"] = 2
    assert advance(producer)
    for _ in range(10):
        if not advance(producer, .1): break
    assert producer.runner.stopped and producer.runner.calls == 2
    assert len(producer.transport.messages) == 2 and producer.transport.closed
    assert producer.rig.control.read()["enabled"] is False
    assert producer.rig.control.runtime()["publishBudget"]["runs"][producer.runner.engine.run_id] == 2


def test_disabled_control_closes_only_actors_and_keeps_history(producer):
    assert advance(producer)
    producer.rig.control.disable(producer.rig.clock.now, "operator")
    assert not producer.runner.step(ClockSample(producer.rig.clock.now, producer.rig.clock.mono))
    assert producer.transport.closed and not producer.transport.messages
    assert producer.rig.history.query("SELECT COUNT(*) FROM simulation_actors WHERE left_at IS NOT NULL") == [(30,)]
    saved = status(producer.rig.control, producer.rig.clock.now)
    assert saved["producer"]["status"] == "stopped" and saved["clientsApplied"] == "unknown"


def test_busy_authority_emits_nothing_and_keeps_idle_connections_then_honors_disable(producer, monkeypatch):
    assert advance(producer)
    producer.transport.pending = {"sim-001"}
    with monkeypatch.context() as patch:
        def busy(_): raise ControlBusy("writer committing")
        patch.setattr(producer.runner.authority, "current", busy)
        for _ in range(20):
            assert producer.runner.step(ClockSample(producer.rig.clock.now, producer.rig.clock.mono))
        assert not producer.transport.messages
        assert producer.transport.discarded == ["sim-001"]
        assert producer.runner.calls == 0 and not producer.transport.closed
    producer.rig.control.disable(producer.rig.clock.now, "operator")
    assert not producer.runner.step(ClockSample(producer.rig.clock.now, producer.rig.clock.mono))
    assert producer.transport.closed and not producer.transport.messages


def test_disable_between_reservation_and_publish_consumes_budget_without_emitting(producer, monkeypatch):
    assert advance(producer)
    reserve = producer.rig.control.reserve_publish
    def revoke(*args, **kwargs):
        result = reserve(*args, **kwargs)
        producer.rig.control.disable(producer.rig.clock.now, "race")
        return result
    monkeypatch.setattr(producer.rig.control, "reserve_publish", revoke)
    assert not advance(producer, .1)
    assert producer.runner.calls == 1 and not producer.transport.messages and producer.transport.closed


@pytest.mark.parametrize("fault", ["sleep", "civil_backwards", "civil_forward"])
def test_clock_discontinuities_stop_without_replay_or_reuse(producer, fault):
    assert advance(producer)
    producer.rig.clock.advance(16 if fault == "sleep" else 1, wall=None if fault == "sleep" else (-1 if fault == "civil_backwards" else 10))
    assert not producer.runner.step(ClockSample(producer.rig.clock.now, producer.rig.clock.mono))
    assert producer.transport.closed and not producer.transport.messages
    assert not producer.rig.control.read()["enabled"]


def test_expired_backend_ack_stops_before_next_publish(producer):
    assert advance(producer)
    producer.rig.clock.advance(15)
    assert not producer.runner.step(ClockSample(producer.rig.clock.now, producer.rig.clock.mono))
    assert producer.transport.closed and not producer.transport.messages


def test_storage_failure_during_boarding_emits_nothing_and_revokes(producer, monkeypatch):
    def fail(*args): raise SimulationPersistenceUnavailable("disk full")
    monkeypatch.setattr(producer.rig.history, "record_simulation_actor", fail)
    assert not advance(producer)
    assert not producer.transport.messages and producer.transport.closed
    assert not producer.rig.control.read()["enabled"]
    tick(producer.rig, ack=True)
    assert producer.rig.history.query("SELECT status, history_complete FROM simulation_runs") == [("failed", 0)]


def test_duplicate_instance_lock_and_replaced_lock_stop(producer):
    with pytest.raises(ControlUnavailable): ProducerLock(producer.rig.control)
    assert advance(producer)
    producer.runner.lock.path.unlink()
    producer.runner.lock.path.write_text("")
    assert not advance(producer, .1)
    assert producer.transport.closed and not producer.transport.messages


def test_crashed_producer_cannot_resume_same_run(producer, geometries_s05):
    assert advance(producer)
    old = producer.runner
    old.transport.close()
    old.lock.close()  # muerte sin parada administrativa
    replacement = runner_for(producer.rig, geometries_s05)
    try:
        assert replacement.engine.session_namespace != old.engine.session_namespace
        assert not replacement.step(ClockSample(producer.rig.clock.now, producer.rig.clock.mono))
        assert not replacement.transport.messages
        assert not producer.rig.control.read()["enabled"]
        tick(producer.rig, ack=True)
        assert producer.rig.history.query("SELECT status, history_complete FROM simulation_runs") == [("failed", 0)]
    finally:
        replacement.lock.close()


def test_close_of_service_is_exact_and_has_no_outside_observation(rig, geometries_s05):
    rig.clock.now = datetime(2026, 10, 21, 22, 29, 59, tzinfo=lima_zone()).timestamp()
    runner = runner_for(rig, geometries_s05)
    try:
        assert runner.step(ClockSample(rig.clock.now, rig.clock.mono))
        rig.clock.advance(1)
        assert not runner.step(ClockSample(rig.clock.now, rig.clock.mono))
        assert runner.transport.closed and not runner.transport.messages
    finally: runner.stop(ClockSample(rig.clock.now, rig.clock.mono))


def test_same_history_shared_with_backend_without_migrating_or_granting_run(rig, geometries_s05, config, feed):
    writer = ObservationStore(rig.history.path, existing_only=True, min_simulation_free_bytes=0)
    runner = runner_for(rig, geometries_s05, history=writer)
    publisher = CapturingPublisher()
    cfg = replace(config, simulation_ingress_enabled=True, vehicle_position_schema_version=2, min_publish_principals=2)
    bridge = Bridge(cfg, feed, publisher, store=rig.history, admission_provider=rig.controller.admission)
    outcomes = []
    def deliver(observation, sample):
        topic = f"rutautp/simulacion/{runner.engine.run_id}/observaciones/{observation.principal}/{observation.session_id}/posicion"
        outcomes.append(bridge.handle_message(topic, json.dumps(observation.payload()), sample.unix))
    runner.transport.deliver = deliver
    p = SimpleNamespace(rig=rig, runner=runner, transport=runner.transport)
    try:
        assert advance(p)
        for _ in range(61): assert advance(p, .1)
        assert outcomes and all(outcome.accepted for outcome in outcomes)
        assert publisher.count > 0 and all(body["dataOrigin"] == "simulated" for body in publisher.payloads())
        assert writer.migration_backup is None
        assert rig.history.query("SELECT COUNT(*) FROM simulation_actors")[0][0] >= 30
    finally:
        runner.stop(ClockSample(rig.clock.now, rig.clock.mono))
        writer.close()


def test_existing_only_open_does_not_create_or_migrate(tmp_path):
    missing = tmp_path / "missing/fake.sqlite"
    store = ObservationStore(missing, existing_only=True)
    assert not store.enabled and not missing.exists() and not missing.parent.exists()
    legacy = tmp_path / "old.sqlite"
    sqlite3.connect(legacy).close()
    before = legacy.read_bytes()
    store = ObservationStore(legacy, existing_only=True)
    assert not store.enabled and legacy.read_bytes() == before


def test_daily_budget_survives_new_run_and_new_controlstore_object(producer, geometries_s05):
    assert advance(producer)
    assert advance(producer, .1)
    old = producer.runner
    assert old.calls == 1
    old.stop(ClockSample(producer.rig.clock.now, producer.rig.clock.mono))
    producer.rig.control.enable(old.engine.profile.pinned(), producer.rig.clock.now)
    new = runner_for(producer.rig, geometries_s05)
    p = SimpleNamespace(rig=producer.rig, runner=new, transport=new.transport)
    new.manifest["limits"]["maxObservationPublishCallsPerDay"] = 1
    try:
        assert advance(p)
        assert not advance(p, .1)
        assert not new.transport.messages
        saved = ControlStore(producer.rig.control.path).runtime()
        assert saved["publishBudget"]["days"][producer.rig.control.read()["serviceDate"]] == 1
    finally: new.stop(ClockSample(producer.rig.clock.now, producer.rig.clock.mono))


def test_status_freshness_revocation_and_backend_tick_preserves_producer_status(producer):
    assert advance(producer)
    assert status(producer.rig.control, producer.rig.clock.now)["producer"]["status"] == "running"
    producer.rig.clock.advance(5)
    tick(producer.rig, ack=True)
    assert status(producer.rig.control, producer.rig.clock.now)["producer"]["status"] == "running"
    producer.rig.control.disable(producer.rig.clock.now, "operator")
    assert status(producer.rig.control, producer.rig.clock.now)["producer"]["status"] == "revocation_pending"
    assert status(producer.rig.control, producer.rig.clock.now + 15)["producer"]["status"] == "unknown"


def test_cli_check_is_offline_and_does_not_open_history_or_create_lock(rig, tmp_path, capsys):
    credentials = credentials_file(tmp_path)
    nonexistent = tmp_path / "must-not-exist.sqlite"
    code = main(["--control-db", str(rig.control.path), "--history-db", str(nonexistent),
                 "--credentials-file", str(credentials), "--gtfs-dir", str(GTFS_DIR), "check"])
    output = json.loads(capsys.readouterr().out)
    assert code == 0 and output["networkStarted"] is False and not nonexistent.exists()
    assert not rig.control.path.with_suffix(".sqlite.producer-lock").exists()


@pytest.mark.parametrize("budget", [{"runs": [], "days": {}}, {"runs": {}, "days": {"2026-10-21": -1}},
                                   {"runs": {}, "days": {"2026-10-21": True}}])
def test_corrupt_budget_fails_closed_before_publish(producer, budget):
    assert advance(producer)
    producer.rig.control.runtime(publishBudget=budget)
    assert not advance(producer, .1)
    assert not producer.transport.messages and producer.transport.closed


def test_suspension_while_reserving_budget_does_not_publish_old_frame(producer, monkeypatch):
    assert advance(producer)
    reserve = producer.rig.control.reserve_publish
    def delayed(*args, **kwargs):
        result = reserve(*args, **kwargs)
        producer.rig.clock.advance(16)
        return result
    monkeypatch.setattr(producer.rig.control, "reserve_publish", delayed)
    assert not advance(producer, .1)
    assert producer.runner.calls == 1 and not producer.transport.messages
