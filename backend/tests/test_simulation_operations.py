"""S09: métricas, salud y supervisor; reloj inyectado y control temporal, sin red."""

from copy import deepcopy
import json
import uuid

import pytest

from rutautp_backend.bridge import Bridge
from rutautp_backend.health import fresh_timestamp, simulation_health, read_heartbeat
from rutautp_backend.metrics import Metrics
from rutautp_backend.models import RejectReason
from rutautp_backend.simulation_admin import status, status_with_health
from rutautp_backend.simulation_models import DataOrigin, SourceContext, OBSERVED_SOURCE
from rutautp_backend.simulation_supervisor import supervise, main
from .test_simulation_control import rig, profile, tick
from .test_simulation_ingress import rig as ingress_rig, send, SESSION_2
from .test_bridge import payload_for, topic_for
from .test_simulation_persistence import NOW, RUN


def heartbeat(rig):
    value = status(rig.control, rig.clock.now)
    return {'at': rig.clock.now, 'connected': True, 'simulationStorage': {'available': True},
            'simulation': value, 'simulationVehicles': 7, 'byOrigin': {'simulated': {'accepted': 4}},
            'byRun': {value['runId']: {'accepted': 4}}, 'persistence': {'dbWriteErrors': 0}}


def ready(rig):
    tick(rig, ack=True)
    state = rig.control.read()
    rig.control.runtime(producer={'runId': state['runId'], 'controlRevision': state['revision'],
        'status': 'running', 'seenAt': rig.clock.now, 'actors': 24, 'connections': 25,
        'readyActors': 23, 'inflight': 2, 'publishAcks': 21})
    return heartbeat(rig)


def test_metrics_separate_origins_and_runs_without_changing_global_contract():
    metrics = Metrics(); run = str(uuid.uuid4()); source = SourceContext(DataOrigin.SIMULATED, run)
    for context in (source, OBSERVED_SOURCE):
        metrics.record_received(); metrics.record_accepted(context, at=100)
        metrics.record_created(context); metrics.record_publish_attempt(context)
        metrics.record_published(context)
    metrics.record_received(); metrics.record_rejected(RejectReason.DUPLICATE, source)
    metrics.record_publish_attempt(source); metrics.record_publish_failed(source)
    scopes = metrics.provenance_snapshot()
    assert metrics.snapshot()['received'] == 3 and metrics.snapshot()['accepted'] == 2
    assert scopes['byOrigin']['observed']['accepted'] == 1
    assert scopes['byRun'][run]['received'] == 2
    assert scopes['byRun'][run]['reasons'] == {'duplicate': 1}
    assert scopes['byRun'][run]['publishFailures'] == 1
    assert scopes['byRun'][run]['enqueuedPositions'] == 1


def test_metrics_run_memory_bounded_origin_totals_preserved():
    metrics = Metrics()
    for _ in range(40):
        metrics.record_accepted(SourceContext(DataOrigin.SIMULATED, str(uuid.uuid4())))
    snapshot = metrics.provenance_snapshot()
    assert len(snapshot['byRun']) == 32 and snapshot['evictedRunScopes'] == 8
    assert snapshot['byOrigin']['simulated']['accepted'] == 40
    snapshot['byOrigin']['simulated']['accepted'] = 0
    assert metrics.provenance_snapshot()['byOrigin']['simulated']['accepted'] == 40


@pytest.mark.parametrize('stamp', [None, True, False, '100', float('nan'), float('inf'), -float('inf'), 10**400, 101, 85])
def test_freshness_rejects_invalid_future_or_expired(stamp):
    assert not fresh_timestamp(stamp, 100)


def test_status_uses_persisted_daily_budget_and_separate_counts(rig):
    ready(rig); state = rig.control.read()
    rig.control.runtime(publishBudget={'runs': {state['runId']: 20}, 'days': {state['serviceDate']: 40}})
    current = status(rig.control, rig.clock.now)
    assert current['budget']['reservedPublishCallsRun'] == 20
    assert current['budget']['reservedPublishCallsDay'] == 40
    assert current['budget']['maxRunSeconds'] == 900
    assert current['budget']['maxPublishCallsDay'] == 6000
    assert current['counts']['expectedActors'] == 30
    assert current['counts']['nominalVehicles'] == 10
    assert current['counts']['mqttConnections'] == 25
    assert current['counts']['activePassengers'] == 24
    assert current['counts']['estimatedVehicles'] is None
    assert current['counts']['markersRendered'] is None


def test_stale_producer_counts_are_unknown_not_zero(rig):
    ready(rig)
    current = status(rig.control, rig.clock.now+15)
    assert current['producer']['status'] == 'unknown'
    assert current['counts']['mqttConnections'] is None
    assert current['counts']['activePassengers'] is None


def test_status_health_does_not_borrow_another_generation(rig):
    health = ready(rig)
    current = status_with_health(rig.control, rig.clock.now, health)
    assert current['counts']['estimatedVehicles'] == 7
    health['simulation']['runId'] = str(uuid.uuid4())
    assert status_with_health(rig.control, rig.clock.now, health)['counts']['estimatedVehicles'] is None


@pytest.mark.parametrize('backend', [None, [], 'bad'])
def test_malformed_health_backend_is_not_trusted(rig, backend):
    health = ready(rig); health['simulation']['backend'] = backend
    assert not status_with_health(rig.control, rig.clock.now, health)['heartbeatMatchesControl']


def test_health_records_storage_failure_even_with_recent_backend(feed, config, tmp_path):
    from dataclasses import replace
    bridge = Bridge(replace(config, health_file=str(tmp_path/'health.json')), feed)
    bridge.tick(100, connected=True)
    saved = read_heartbeat(str(tmp_path/'health.json'))
    assert saved['persistence']['dbWriteErrors'] == 0
    assert not saved['simulationStorage']['available']  # histórico intencionadamente deshabilitado
    assert saved['app']['positionsReceived'] is None
    assert simulation_health(saved, 100)['reason'] == 'simulation_history_unavailable'


def test_bridge_heartbeat_records_verified_origin_run_and_estimates(ingress_rig, sample_route, tmp_path):
    from dataclasses import replace
    bridge = ingress_rig.bridge
    bridge.config = replace(bridge.config, health_file=str(tmp_path/'scoped-health.json'))
    assert bridge.handle_message(topic_for('observed'), payload_for(sample_route, session='observed'), NOW).accepted
    assert send(ingress_rig, sample_route).accepted
    assert send(ingress_rig, sample_route, 'sim-002', SESSION_2).published
    bridge.tick(NOW, connected=True)
    saved = read_heartbeat(bridge.config.health_file)
    assert saved['byOrigin']['observed']['accepted'] == 1
    assert saved['byRun'][RUN]['accepted'] == 2
    assert saved['byRun'][RUN]['enqueuedPositions'] == 1
    assert saved['observedVehicles'] == 1 and saved['simulationVehicles'] == 1
    assert saved['simulationStorage']['available']
    assert saved['app']['markersRendered'] is None


def test_supervisor_check_is_read_only_and_unknown_app_telemetry_stays_unknown(rig):
    health = ready(rig); before = rig.control.read()
    result = supervise(rig.control, health, rig.clock.now)
    assert result['supervision']['healthy']
    assert result['supervision']['action'] == 'none'
    assert not result['supervision']['appCleanupConfirmed']
    assert result['counts']['markersRendered'] is None
    assert rig.control.read() == before


@pytest.mark.parametrize('kind', ['missing', 'disconnected', 'storage', 'control', 'generation', 'revision', 'ack'])
def test_supervisor_identifies_failures_and_only_explicit_guard_revokes(rig, kind):
    health = ready(rig); state = rig.control.read()
    if kind == 'missing': health = None
    elif kind == 'disconnected': health['connected'] = False
    elif kind == 'storage': health['simulationStorage']['available'] = False
    elif kind == 'control': health['simulationControlError'] = 'unavailable'
    elif kind == 'generation': health['simulation']['runId'] = str(uuid.uuid4())
    elif kind == 'revision': rig.control.runtime(appliedRevision=state['revision']-1)
    else: rig.control.runtime(lastAckedRevision=state['revision']-1)
    checked = supervise(rig.control, health, rig.clock.now)
    assert not checked['supervision']['healthy'] and rig.control.read()['enabled']
    guarded = supervise(rig.control, health, rig.clock.now, revoke=True)
    assert guarded['supervision']['action'] == 'disable_saved'
    assert not rig.control.read()['enabled']
    assert not guarded['supervision']['backendAppliedDisable']


def test_supervisor_does_not_repeat_disable_or_announce_stopped(rig):
    ready(rig); rig.control.disable(rig.clock.now, 'operator')
    revision = rig.control.read()['revision']
    result = supervise(rig.control, None, rig.clock.now, revoke=True)
    assert result['supervision']['issues'] == ['producer_revocation_pending']
    assert not result['supervision']['producerStoppedConfirmed']
    assert result['supervision']['action'] == 'none'
    assert rig.control.read()['revision'] == revision


def test_supervisor_cas_does_not_revoke_a_new_generation(rig, monkeypatch):
    ready(rig); original = rig.control.disable
    def concurrent(now, reason, **kwargs):
        original(now, 'another_operator')
        return original(now, reason, **kwargs)
    monkeypatch.setattr(rig.control, 'disable', concurrent)
    result = supervise(rig.control, None, rig.clock.now, revoke=True)
    assert result['supervision']['action'] == 'generation_changed_no_action'
    assert rig.control.read()['reason'] == 'another_operator'


def test_invalid_budget_is_exposed_and_guard_can_revoke(rig):
    health = ready(rig)
    rig.control.runtime(publishBudget={'runs': {}, 'days': {'2026-10-21': True}})
    assert not status(rig.control, rig.clock.now)['budget']['available']
    result = supervise(rig.control, health, rig.clock.now, revoke=True)
    assert 'publish_budget_unavailable' in result['supervision']['issues']
    assert not rig.control.read()['enabled']


@pytest.mark.parametrize('kind', ['duration', 'service', 'budget', 'producer'])
def test_supervisor_deadlines_budget_and_producer_freshness(rig, kind):
    health = ready(rig); state = rig.control.read(); now = rig.clock.now
    if kind == 'duration': now += 900
    elif kind == 'service': now = state['serviceEndsAt']
    elif kind == 'producer': now += 16
    else: rig.control.runtime(publishBudget={'runs': {state['runId']: 6000}, 'days': {state['serviceDate']: 6000}})
    result = supervise(rig.control, health, now)
    expected = {'duration': 'max_run_duration', 'service': 'service_closed',
        'budget': 'publish_budget_exhausted_day', 'producer': 'producer_missing_stopped_or_stale'}[kind]
    assert expected in result['supervision']['issues']


def test_supervisor_missing_control_never_creates_state(tmp_path, capsys):
    missing = tmp_path/'missing/control.sqlite'
    assert main(['--control-db', str(missing), '--health-file', str(tmp_path/'health.json'), 'check']) == 2
    assert not missing.parent.exists()
    assert 'control_unavailable' in capsys.readouterr().out
