"""S10: regresiones reveladas por el ensayo MQTT real; bases temporales."""
import pytest
from pathlib import Path
import uuid

from rutautp_backend.bridge import Bridge
from rutautp_backend.config import Config
from rutautp_backend.simulation_control_store import ControlBusy, ControlUnavailable
from rutautp_backend.simulation_models import SimulationActorRecord
from simulation.device_trial import console_events, app_process_id
from .conftest import GTFS_DIR
from .test_bridge import CapturingPublisher, payload_for
from .test_simulation_ingress import SESSION, SESSION_2, synthetic_topic
from .test_simulation_control import rig, profile
from .test_simulation_publisher import transport, connected, sample, observation


def populated_bridge(rig,feed,sample_route):
    publisher=CapturingPublisher()
    config=Config(gtfs_dir=GTFS_DIR,database_path='',health_file='',
        simulation_ingress_enabled=True,vehicle_position_schema_version=2)
    bridge=Bridge(config,feed,publisher,store=rig.history,simulation_control=rig.controller)
    bridge.control_publisher=rig.publisher
    bridge.tick(rig.clock.now)
    rig.controller.acknowledge(rig.publisher.messages[-1][0],rig.clock.now)
    run=rig.control.read()['runId']
    for principal,session in [('sim-001',SESSION),('sim-002',SESSION_2)]:
        rig.history.record_simulation_actor(SimulationActorRecord(run,principal,session,
            'scenario-bus-01',sample_route.route_id,rig.clock.now))
        assert bridge.handle_message(synthetic_topic(principal,session,run),
            payload_for(sample_route,session=session,now=rig.clock.now),rig.clock.now).accepted
    return bridge,publisher,run


def test_control_contention_rejects_current_message_without_rotating_vehicle_identity(rig,feed,sample_route,monkeypatch):
    bridge,publisher,run=populated_bridge(rig,feed,sample_route)
    before=bridge._simulation_aggregator
    initial_ids={v.vehicle_id for v in before.snapshot()}
    count=publisher.count
    with monkeypatch.context() as patch:
        def busy(): raise ControlBusy('another writer is committing')
        patch.setattr(rig.controller,'_read',busy)
        assert bridge._current_admission(rig.clock.now) is None
        result=bridge.handle_message(synthetic_topic('sim-001',SESSION,run),
            payload_for(sample_route,session=SESSION,now=rig.clock.now),rig.clock.now)
        assert not result.accepted and publisher.count==count
        assert bridge._simulation_aggregator is before
    assert bridge._current_admission(rig.clock.now) is not None
    assert bridge._simulation_aggregator is before
    assert {v.vehicle_id for v in before.snapshot()}==initial_ids


def test_control_error_still_drops_partition(rig,feed,sample_route,monkeypatch):
    bridge,_,_=populated_bridge(rig,feed,sample_route)
    def unavailable(): raise ControlUnavailable('storage unavailable')
    monkeypatch.setattr(rig.controller,'_read',unavailable)
    assert bridge._current_admission(rig.clock.now) is None
    assert bridge._simulation_aggregator is None


def test_disable_after_contention_cannot_restore_old_cache(rig,feed,sample_route,monkeypatch):
    bridge,publisher,run=populated_bridge(rig,feed,sample_route)
    with monkeypatch.context() as patch:
        def busy(): raise ControlBusy('writer')
        patch.setattr(rig.controller,'_read',busy)
        assert bridge._current_admission(rig.clock.now) is None
    rig.control.disable(rig.clock.now,'operator')
    assert bridge._current_admission(rig.clock.now) is None
    assert bridge._simulation_aggregator is None


def test_device_console_parser_ignores_noise_and_incomplete_tail(tmp_path):
    path=tmp_path/'console.log'
    path.write_text('normal log\n[S10] {"event":"map","counts":{"received":10}}\n'
        '[S10] {"event":\n[S10] []\n')
    assert console_events(path)==[{'event':'map','counts':{'received':10}}]
    assert console_events(tmp_path/'missing')==[]


def test_two_nominal_buses_at_same_route_point_can_fuse_and_result_is_visible(rig,feed,sample_route):
    bridge,_,run=populated_bridge(rig,feed,sample_route)
    original=bridge._simulation_aggregator.snapshot()[0].vehicle_id
    estimates=[]
    for principal in ['sim-003','sim-004']:
        session=str(uuid.uuid4())
        rig.history.record_simulation_actor(SimulationActorRecord(run,principal,session,
            'scenario-bus-02',sample_route.route_id,rig.clock.now))
        outcome=bridge.handle_message(synthetic_topic(principal,session,run),
            payload_for(sample_route,session=session,now=rig.clock.now),rig.clock.now)
        assert outcome.accepted
        estimates.append(outcome.vehicle_id)
    # Limitación del estimador espacial, sin modificar ruido o quorum para ocultarla.
    assert estimates==[original,original]
    assert bridge._simulation_aggregator.vehicle_count==1


def test_profiler_selects_exact_app_pid_without_attaching_to_other_processes():
    app={'executable':'file:///private/App/RutaUTP.app/RutaUTP','processIdentifier':42}
    assert app_process_id([{'executable':'other','processIdentifier':1},app])==42
    for processes in [[],[app,app],[{**app,'processIdentifier':True}],[{**app,'processIdentifier':-1}]]:
        with pytest.raises(RuntimeError):app_process_id(processes)


def test_busy_pause_discards_inflight_without_reconnecting_idle_channels(transport):
    first = connected(transport)
    idle = connected(transport, "sim-002")
    assert transport.publish(observation(), sample())
    transport.discard_pending_publications()
    assert first.closed and transport.channels["sim-001"].pending is None
    assert transport.channels["sim-001"].client is None
    assert transport.channels["sim-002"].client is idle and not idle.closed
    assert transport.ready("sim-002", sample())
    first.on_publish(first, None, 1, 0, None)
    assert transport.acknowledged == 0


def test_repeated_busy_pause_preserves_idle_backoff_and_expired_lease_cannot_publish(transport):
    idle = connected(transport)
    for _ in range(30): transport.discard_pending_publications()
    channel = transport.channels["sim-001"]
    assert channel.client is idle and channel.failures == 0
    assert not transport.ready("sim-001", sample(15))
    assert not transport.publish(observation(15), sample(15))
    transport.service(sample(15))
    assert idle.closed and not idle.messages
