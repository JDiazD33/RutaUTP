"""S03: entrada real del puente, SQLite temporal y publicador capturado.

Sin sockets, broker, base activa ni proceso generador. Ejecutar solo con permiso.
"""

from dataclasses import replace
import json
import sqlite3
from types import SimpleNamespace

import pytest

from rutautp_backend.bridge import Bridge
from rutautp_backend.config import Config, ConfigError
from rutautp_backend.models import RejectReason
from rutautp_backend.persistence import ObservationStore
from rutautp_backend.simulation_ingress import (
    SimulationAdmission, SIMULATION_OBSERVATIONS_TOPIC, parse_observation_topic,
)
from rutautp_backend.simulation_models import (
    DataOrigin, SimulationActorRecord, SimulationRunStatus,
)

from .test_bridge import CapturingPublisher, payload_for, topic_for
from .test_simulation_persistence import NOW, RUN, OTHER_RUN, SESSION, run_record

SESSION_2 = "a91de44b-b901-4300-a59a-e95656c139f0"
PRINCIPALS = frozenset({"sim-001", "sim-002", "sim-003"})


def admission(run=RUN, revision=1, **changes):
    return SimulationAdmission(**{
        "run_id": run, "control_revision": revision, "principals": PRINCIPALS,
        "issued_at": NOW - 1, "valid_until": NOW + 14, "service_ends_at": NOW + 900,
        **changes,
    })


def synthetic_topic(principal="sim-001", session=SESSION, run=RUN):
    return f"rutautp/simulacion/{run}/observaciones/{principal}/{session}/posicion"


def register(store, run, route):
    store.create_simulation_run(run_record(run))
    store.set_simulation_run_status(run, SimulationRunStatus.RUNNING, NOW - 5)
    for principal, session in (("sim-001", SESSION), ("sim-002", SESSION_2)):
        store.record_simulation_actor(SimulationActorRecord(
            run, principal, session, "nominal-bus-01", route.route_id, NOW - 1,
        ))
    assert store.flush()


@pytest.fixture
def rig(tmp_path, config, feed, sample_route):
    store = ObservationStore(tmp_path / "s03.sqlite", min_simulation_free_bytes=0)
    register(store, RUN, sample_route)
    publisher = CapturingPublisher()
    control = SimpleNamespace(current=admission())
    cfg = replace(config, min_publish_principals=2, vehicle_position_schema_version=2,
                  simulation_ingress_enabled=True)
    bridge = Bridge(cfg, feed, publisher, store=store, admission_provider=lambda _: control.current)
    yield SimpleNamespace(store=store, bridge=bridge, publisher=publisher, control=control)
    store.close()


def send(rig, route, principal="sim-001", session=SESSION, run=RUN, now=NOW, **payload):
    return rig.bridge.handle_message(
        synthetic_topic(principal, session, run),
        payload_for(route, session=session, now=now, **payload), now,
    )


def test_two_synthetic_principals_publish_separately_from_observed(rig, sample_route):
    observed = rig.bridge.handle_message(
        topic_for("observed"), payload_for(sample_route, session="observed"), NOW,
    )
    first = send(rig, sample_route)
    assert observed.accepted and first.accepted
    assert not observed.published and not first.published
    assert observed.vehicle_id != first.vehicle_id
    second = send(rig, sample_route, "sim-002", SESSION_2)
    assert second.vehicle_id == first.vehicle_id and second.published
    body = rig.publisher.last()
    assert body["schemaVersion"] == 2 and body["dataOrigin"] == "simulated"
    assert body["simulationRunId"] == RUN and body["controlRevision"] == 1
    assert body["vehicleId"].startswith(f"sim:{RUN}:")
    assert body["timestamp"] == NOW
    assert len(body) == 12
    assert rig.bridge._vehicle_counts() == {
        "vehicles": 2, "routes": 2, "observedVehicles": 1, "simulationVehicles": 1,
    }
    assert rig.store.query("SELECT data_origin, simulation_run_id FROM observations ORDER BY id") == [
        ("observed", None), ("simulated", RUN), ("simulated", RUN),
    ]


def test_rotating_sessions_under_one_synthetic_principal_cannot_reach_quorum(rig, sample_route):
    extra_session = "33ea8b06-42d7-4ea6-b4bc-76eae27abc9d"
    rig.store.record_simulation_actor(SimulationActorRecord(
        RUN, "sim-001", extra_session, "nominal-bus-01", sample_route.route_id, NOW - 1,
    ))
    assert send(rig, sample_route).accepted
    assert send(rig, sample_route, session=extra_session).accepted
    assert rig.publisher.count == 0


def test_shared_session_and_timestamp_do_not_share_dedupe_or_continuity(rig, sample_route):
    normal = rig.bridge.handle_message(
        topic_for(SESSION), payload_for(sample_route, session=SESSION, progress=0.1), NOW,
    )
    assert normal.accepted
    assert send(rig, sample_route, progress=0.8).accepted
    duplicate = send(rig, sample_route, progress=0.8)
    assert duplicate.reason is RejectReason.DUPLICATE


def test_new_run_has_new_group_dedupe_and_continuity(rig, sample_route):
    first = send(rig, sample_route, progress=0.1)
    register(rig.store, OTHER_RUN, sample_route)
    rig.control.current = admission(OTHER_RUN, 2)
    second = send(rig, sample_route, run=OTHER_RUN, progress=0.8)
    assert first.accepted and second.accepted
    assert second.vehicle_id.startswith(f"sim:{OTHER_RUN}:")
    assert second.vehicle_id != first.vehicle_id
    assert rig.bridge._simulation_aggregator.vehicle_count == 1
    assert send(rig, sample_route).reason is RejectReason.SOURCE_NOT_AUTHORIZED


def test_global_capacity_is_shared_across_origins(rig, sample_route, feed):
    cfg = replace(rig.bridge.config, max_messages_per_minute=2,
                  max_messages_per_minute_global=2)
    rig.bridge = Bridge(cfg, feed, rig.publisher, store=rig.store,
                        admission_provider=lambda _: rig.control.current)
    assert send(rig, sample_route).accepted
    assert rig.bridge.handle_message(topic_for(), payload_for(sample_route), NOW).accepted
    third = send(rig, sample_route, "sim-002", SESSION_2)
    assert third.reason is RejectReason.GLOBAL_RATE_LIMITED
    assert rig.publisher.count == 0


def test_principal_capacity_survives_a_run_change(rig, sample_route, feed):
    cfg = replace(rig.bridge.config, max_messages_per_minute=1)
    rig.bridge = Bridge(cfg, feed, rig.publisher, store=rig.store,
                        admission_provider=lambda _: rig.control.current)
    assert send(rig, sample_route).accepted
    register(rig.store, OTHER_RUN, sample_route)
    rig.control.current = admission(OTHER_RUN, 2)
    assert send(rig, sample_route, run=OTHER_RUN).reason is RejectReason.RATE_LIMITED


@pytest.mark.parametrize("principal", ["sim-001", "sim-099", "SIM-001", "sim-malformado"])
def test_synthetic_identity_on_normal_branch_is_rejected(rig, sample_route, principal):
    outcome = rig.bridge.handle_message(
        topic_for(SESSION, principal), payload_for(sample_route, session=SESSION), NOW,
    )
    assert outcome.reason is RejectReason.SOURCE_NOT_AUTHORIZED
    assert rig.bridge.aggregator.vehicle_count == 0


@pytest.mark.parametrize("principal,session,run", [
    ("sim-099", SESSION, RUN), ("sim-001", SESSION, OTHER_RUN),
    ("sim-002", SESSION, RUN), ("sim-003", SESSION_2, RUN),
])
def test_requires_whitelist_and_registered_actor_binding(rig, sample_route, principal, session, run):
    assert send(rig, sample_route, principal, session, run).reason is RejectReason.SOURCE_NOT_AUTHORIZED
    assert rig.publisher.count == 0


def test_route_mismatch_does_not_poison_dedupe(rig, sample_route, feed):
    other = next(route for route in feed.routes.values()
                 if route.route_id != sample_route.route_id and len(route.shape) >= 2)
    assert send(rig, other).reason is RejectReason.SOURCE_NOT_AUTHORIZED
    assert send(rig, sample_route).accepted


def test_payload_cannot_declare_its_origin_or_vehicle_id(rig, sample_route):
    outcome = rig.bridge.handle_message(
        topic_for(), payload_for(sample_route, dataOrigin="simulated", runId=RUN,
                                 vehicleId="forged"), NOW,
    )
    assert outcome.accepted and not outcome.vehicle_id.startswith("sim:")
    assert rig.store.query("SELECT data_origin, simulation_run_id FROM observations") == [("observed", None)]


@pytest.mark.parametrize("mode", ["disabled", "missing", "expired", "future", "throws", "bad_type"])
def test_missing_valid_control_closes_only_synthetic_branch(rig, sample_route, mode):
    assert send(rig, sample_route).accepted
    if mode == "disabled":
        rig.control.current = None
    elif mode == "missing":
        rig.bridge.admission_provider = None
    elif mode == "expired":
        rig.control.current = admission(issued_at=NOW - 15, valid_until=NOW)
    elif mode == "future":
        rig.control.current = admission(issued_at=NOW + 1, valid_until=NOW + 15)
    elif mode == "throws":
        def broken(_):
            raise RuntimeError("controller offline")
        rig.bridge.admission_provider = broken
    else:
        rig.control.current = {"enabled": True, "runId": RUN}
    outcome = send(rig, sample_route, "sim-002", SESSION_2)
    assert outcome.reason is RejectReason.SOURCE_NOT_AUTHORIZED
    assert rig.bridge._simulation_aggregator is None
    assert rig.bridge.handle_message(topic_for(), payload_for(sample_route), NOW).accepted


def test_tick_drops_synthetic_state_when_lease_expires(rig, sample_route):
    assert send(rig, sample_route).accepted
    rig.bridge.handle_message(topic_for(), payload_for(sample_route), NOW)
    rig.bridge.tick(NOW + 14)
    assert rig.bridge._simulation_aggregator is None
    assert rig.bridge.aggregator.vehicle_count == 1


def test_regressive_revision_cannot_reopen_an_old_run(rig, sample_route):
    assert send(rig, sample_route).accepted
    register(rig.store, OTHER_RUN, sample_route)
    rig.control.current = admission(OTHER_RUN, 2)
    assert send(rig, sample_route, run=OTHER_RUN).accepted
    rig.control.current = admission(RUN, 1)
    assert send(rig, sample_route).reason is RejectReason.SOURCE_NOT_AUTHORIZED


@pytest.mark.parametrize("registered", [False, True])
def test_admission_requires_running_durable_run_even_for_malformed_input(rig, sample_route, registered):
    if registered:
        rig.store.set_simulation_run_status(RUN, SimulationRunStatus.PAUSED, NOW)
    else:
        rig.control.current = admission(OTHER_RUN, 2)
    topic = synthetic_topic(run=RUN if registered else OTHER_RUN)
    result = rig.bridge.handle_message(topic, "{bad-json", NOW)
    assert result.reason is RejectReason.SOURCE_NOT_AUTHORIZED
    assert rig.bridge._simulation_aggregator is None
    assert rig.store.simulation_storage_status()["available"]


def test_whitelist_change_requires_a_new_revision(rig, sample_route):
    assert send(rig, sample_route).accepted
    rig.control.current = admission(principals={"sim-001", "sim-002"})
    assert send(rig, sample_route, "sim-002", SESSION_2).reason is RejectReason.SOURCE_NOT_AUTHORIZED
    assert rig.bridge._simulation_aggregator is None


def test_sqlite_is_durable_before_transport_handoff(rig, sample_route):
    seen = []
    def publisher(topic, raw):
        with sqlite3.connect(rig.store.path) as reader:
            seen.append(reader.execute("SELECT COUNT(*) FROM observations WHERE data_origin='simulated'").fetchone()[0])
            assert reader.execute("SELECT COUNT(*) FROM vehicle_positions WHERE data_origin='simulated'").fetchone() == (1,)
        return True
    rig.bridge.publisher = publisher
    send(rig, sample_route)
    assert send(rig, sample_route, "sim-002", SESSION_2).published
    assert seen == [2]


def test_write_failure_drops_partition_and_stops_synthetic_publish(rig, sample_route):
    assert send(rig, sample_route).accepted
    rig.store._connection.execute("PRAGMA query_only=ON")
    failed = send(rig, sample_route, "sim-002", SESSION_2)
    assert failed.reason is RejectReason.SIMULATION_UNAVAILABLE
    assert rig.publisher.count == 0 and rig.bridge._simulation_aggregator is None
    assert not rig.store.simulation_storage_status()["available"]
    assert rig.bridge.handle_message(topic_for(), payload_for(sample_route), NOW).accepted


def test_commit_failure_blocks_transport(rig, sample_route, monkeypatch):
    assert send(rig, sample_route).accepted
    def broken_commit():
        rig.store._fail_simulation("injected commit failure")
        return False
    monkeypatch.setattr(rig.store, "flush", broken_commit)
    assert send(rig, sample_route, "sim-002", SESSION_2).reason is RejectReason.SIMULATION_UNAVAILABLE
    assert rig.publisher.count == 0 and rig.bridge._simulation_aggregator is None


def test_expiry_during_commit_blocks_transport(rig, sample_route, monkeypatch):
    assert send(rig, sample_route).accepted
    original_flush = rig.store.flush
    def expire_during_flush():
        rig.control.current = None
        return original_flush()
    monkeypatch.setattr(rig.store, "flush", expire_during_flush)
    assert not send(rig, sample_route, "sim-002", SESSION_2).published
    assert rig.publisher.count == 0 and rig.bridge._simulation_aggregator is None


def test_retained_observations_are_rejected(rig, sample_route):
    for topic in (synthetic_topic(), topic_for(SESSION)):
        outcome = rig.bridge.handle_message(topic, payload_for(sample_route, session=SESSION), NOW, retained=True)
        assert outcome.reason is RejectReason.SOURCE_NOT_AUTHORIZED
    assert rig.publisher.count == 0


def test_observed_v2_and_legacy_default(config, feed, sample_route):
    for version in (1, 2):
        publisher = CapturingPublisher()
        bridge = Bridge(replace(config, vehicle_position_schema_version=version), feed, publisher)
        assert bridge.handle_message(topic_for(), payload_for(sample_route), NOW).published
        body = publisher.last()
        assert len(body) == (8 if version == 1 else 12)
        if version == 2:
            assert body["dataOrigin"] == "observed"
            assert body["simulationRunId"] is None and body["controlRevision"] is None


@pytest.mark.parametrize("changes", [
    {"control_revision": True}, {"control_revision": 0}, {"principals": {"device-001"}},
    {"valid_until": NOW + 20}, {"service_ends_at": NOW}, {"issued_at": float("nan")},
    {"run_id": "invalid"},
])
def test_invalid_admission_is_rejected(changes):
    with pytest.raises(ValueError):
        admission(**changes)


@pytest.mark.parametrize("topic", [
    synthetic_topic().replace(RUN, "bad-run"), synthetic_topic().replace(SESSION, "bad-session"),
    synthetic_topic().replace("sim-001", "device-001"), synthetic_topic() + "/extra",
    "rutautp/observaciones/+/s/posicion", "rutautp/observaciones/device-001/ /posicion",
])
def test_parser_rejects_noncanonical_topics(topic):
    assert parse_observation_topic(topic) is None


def test_configuration_is_closed_by_default_and_requires_v2_with_quorum(config):
    assert not config.simulation_ingress_enabled
    for changes in ({"simulation_ingress_enabled": True},
                    {"simulation_ingress_enabled": True, "vehicle_position_schema_version": 2},
                    {"vehicle_position_schema_version": True}):
        with pytest.raises(ConfigError):
            replace(config, **changes)
    cfg = Config.from_env({"BACKEND_SIMULATION_INGRESS_ENABLED": "1",
                           "BACKEND_VEHICLE_POSITION_SCHEMA_VERSION": "2"})
    assert cfg.simulation_ingress_enabled and cfg.min_publish_principals == 2


def test_synthetic_subscription_is_explicit_and_opt_in(rig, config, feed):
    for bridge, expected in ((Bridge(config, feed), False), (rig.bridge, True)):
        subscriptions = []
        client = SimpleNamespace(subscribe=lambda topic, qos: subscriptions.append(topic))
        bridge._on_connect(client, None, None, 0)
        assert (SIMULATION_OBSERVATIONS_TOPIC in subscriptions) is expected
