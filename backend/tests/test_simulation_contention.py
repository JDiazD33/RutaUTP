"""Contención real de flock sobre SQLite temporal; ningún broker ni base activa."""
import fcntl

import pytest

from rutautp_backend.simulation_control_store import ControlBusy, ControlStore
from .test_simulation_control import rig, profile, tick
from .test_simulation_acceptance import populated_bridge
from .test_bridge import payload_for
from .test_simulation_ingress import SESSION, synthetic_topic
from .conftest import GTFS_DIR
from simulation.actors import LocalAuthority, ProducerStopped
from simulation.clock import ClockSample


def test_readers_coexist_but_writer_cannot_overtake_snapshot(tmp_path):
    first = ControlStore.initialize(tmp_path/'control/state.sqlite', 1000)
    other = ControlStore(first.path, lock_timeout=0)
    with first._connection():
        assert other.read()['revision'] == 1
        with pytest.raises(ControlBusy): other.disable(1001, 'operator')
        assert first.read()['enabled'] is False
    assert other.disable(1001, 'operator')['revision'] == 2
    assert first.read()['revision'] == 2


def test_writer_keeps_readers_out_with_bounded_wait_and_no_stale_fallback(tmp_path):
    writer = ControlStore.initialize(tmp_path/'control/state.sqlite', 1000)
    seconds = [0.0]
    def sleep(delay): seconds[0] += delay
    reader = ControlStore(writer.path, lock_clock=lambda: seconds[0], lock_sleep=sleep)
    with writer._connection(write=True):
        with pytest.raises(ControlBusy): reader.read()
    assert seconds[0] == pytest.approx(.05)
    assert reader.lock_statistics()['timeouts'] == 1
    assert reader.lock_statistics()['retryAttempts'] > 0
    assert reader.read()['revision'] == 1


def test_transient_busy_reads_committed_disable_after_retry(tmp_path, monkeypatch):
    store = ControlStore.initialize(tmp_path/'control/state.sqlite', 1000)
    real_flock = fcntl.flock
    failed = [False]
    def once(descriptor, operation):
        if operation & fcntl.LOCK_SH and not failed[0]:
            failed[0] = True
            raise BlockingIOError('writer committing')
        return real_flock(descriptor, operation)
    reader = ControlStore(store.path, lock_sleep=lambda _: store.disable(1001, 'operator'))
    monkeypatch.setattr(fcntl, 'flock', once)
    state = reader.read()
    assert state['enabled'] is False and state['revision'] == 2
    assert reader.lock_statistics()['retryAttempts'] == 1
    assert reader.lock_statistics()['timeouts'] == 0


@pytest.mark.parametrize('value', [-1, .101, float('inf'), float('nan'), True, '0.05'])
def test_wait_policy_cannot_be_unbounded_or_invalid(tmp_path, value):
    with pytest.raises(ValueError): ControlStore(tmp_path/'unused', lock_timeout=value)


def test_authority_wait_never_extends_existing_lease(rig, monkeypatch):
    tick(rig, ack=True)
    rig.clock.advance(14.99)
    original = rig.controller._load_profile
    def after_wait(state):
        rig.clock.advance(.02)
        return original(state)
    monkeypatch.setattr(rig.controller, '_load_profile', after_wait)
    assert rig.controller.admission(rig.clock.now) is None


@pytest.mark.parametrize('ack_offset,accepted', [(.02, True), (.06, False)])
def test_producer_evaluates_ack_after_read_wait_and_still_rejects_actual_future(rig, monkeypatch, ack_offset, accepted):
    tick(rig, ack=True)
    state = rig.control.read()
    elapsed = [100.0]
    authority = LocalAuthority(rig.control, rig.controller._profile, state['runId'],
        state['revision'], state['owner'], GTFS_DIR, monotonic_clock=lambda: elapsed[0])
    runtime = rig.control.runtime
    def committed_during_read():
        result = runtime()
        result['backendSeenAt'] = result['lastAckedAt'] = rig.clock.now + ack_offset
        elapsed[0] += .03
        return result
    monkeypatch.setattr(rig.control, 'runtime', committed_during_read)
    sample = ClockSample(rig.clock.now, rig.clock.mono)
    if accepted: assert authority.current(sample)['runId'] == state['runId']
    else:
        with pytest.raises(ProducerStopped): authority.current(sample)


def test_busy_rejection_count_is_distinct_from_invalid_principal(rig, feed, sample_route, monkeypatch):
    bridge, _, run = populated_bridge(rig, feed, sample_route)
    with monkeypatch.context() as patch:
        def busy(): raise ControlBusy('writer committing')
        patch.setattr(rig.controller, '_read', busy)
        result = bridge.handle_message(synthetic_topic('sim-001', SESSION, run),
            payload_for(sample_route, session=SESSION, now=rig.clock.now), rig.clock.now)
        assert not result.accepted and result.detail == 'simulation_control_busy'
    assert bridge.metrics.snapshot()['simulationControlBusyRejections'] == 1
    assert bridge._current_admission(rig.clock.now) is not None
    bridge.handle_message(synthetic_topic('sim-099', SESSION, run),
        payload_for(sample_route, session=SESSION, now=rig.clock.now), rig.clock.now)
    assert bridge.metrics.snapshot()['simulationControlBusyRejections'] == 1
