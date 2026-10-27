"""S10: escalones autorizados, entorno aislado y contratos; todo offline."""
import json
import hashlib
import uuid
from dataclasses import replace
from datetime import datetime
from pathlib import Path
import pytest

from rutautp_backend.simulation_profile import PROFILE_SPECS, SimulationProfile, lima_zone
from rutautp_backend.simulation_control_store import ControlStore, ControlUnavailable, PublishBudgetExhausted
from simulation.actors import validate_publication
from simulation.clock import ClockSample
from simulation.geometry import load_trip_geometries
from simulation.scenario import ScenarioEngine
from simulation.publisher import load_credentials
from simulation.local_trial import (
    isolated_environment, local_acl, trial_host, private_json, trial_disk,
    probe_disable_delivery_seconds, disable_measurements,
)
from .conftest import GTFS_DIR
from .test_simulation_persistence import RUN


@pytest.mark.parametrize('name,actors,vehicles', [('ensayo-2',2,1),('ensayo-6',6,2),('pasajeros-30',30,10)])
def test_profiles_produce_exact_actor_counts_with_quorum_and_wire_contract(name,actors,vehicles,feed):
    profile=SimulationProfile.load(name,GTFS_DIR)
    geometries=load_trip_geometries(profile,GTFS_DIR,feed)
    engine=ScenarioEngine(profile,geometries,RUN,GTFS_DIR)
    now=datetime(2026,10,23,12,tzinfo=lima_zone()).timestamp()
    frame=engine.advance(ClockSample(now,100))
    assert len(frame.vehicles)==vehicles and len(frame.observations)==actors
    assert len(profile.principals)==actors
    assert all(v.contributors>=2 for v in frame.vehicles)
    assert len({o.session_id for o in frame.observations})==actors
    assert all(o.heading==-1 and o.speed==0 for o in frame.observations)
    assert all(len(o.payload())==11 for o in frame.observations)
    body=json.loads(profile.raw)
    assert body['limits']['maxObservationPublishCallsPerDay']==(10000 if name=='pasajeros-30' else 6000)
    assert body['limits']['maxRunDurationSeconds']<=PROFILE_SPECS[name][2]


@pytest.mark.parametrize('name', ['pasajeros-50','pasajeros-100','../pasajeros-30','arbitrary'])
def test_unprepared_profiles_never_expand_trial(name):
    with pytest.raises(ValueError): SimulationProfile.load(name,GTFS_DIR)


@pytest.mark.parametrize('name', ['ensayo-2','ensayo-6'])
def test_small_profile_credentials_require_exact_distinct_accounts(tmp_path,name):
    profile=SimulationProfile.load(name,GTFS_DIR)
    path=tmp_path/'accounts.json'
    body={'schemaVersion':1,'host':'127.0.0.1','port':1883,'tls':False,'caFile':None,
        'accounts':{p:{'username':p,'password':'unique-'+p} for p in profile.principals}}
    private_json(path,body)
    assert set(load_credentials(path,profile.principals).accounts)==profile.principals
    body['accounts']['phone']={'username':'phone','password':'unwanted'}
    path.write_text(json.dumps(body))
    with pytest.raises(ValueError): load_credentials(path,profile.principals)


def test_environment_does_not_inherit_active_database_or_broker(tmp_path,monkeypatch):
    for key in ['MQTT_HOST','MQTT_PASSWORD','BACKEND_DB_PATH','APNS_KEY_PATH']:
        monkeypatch.setenv(key,'do-not-inherit')
    env=isolated_environment(Path('/repo'),tmp_path,23567,'temporary')
    assert env['MQTT_HOST']=='127.0.0.1' and env['MQTT_PORT']=='23567'
    assert env['BACKEND_DB_PATH']==str(tmp_path/'history.sqlite')
    assert env['BACKEND_MIN_PUBLISH_PRINCIPALS']=='2'
    assert 'do-not-inherit' not in env.values() and 'APNS_KEY_PATH' not in env


def test_local_acl_has_no_writer_grant_for_reader_and_scopes_each_actor():
    text=local_acl(['sim-001','sim-002'])
    reader=text.split('user reader\n')[1].split('user sim-')[0]
    assert 'write' not in reader and 'rutautp/vehiculos/+/posicion' in reader
    actor=text.split('user sim-001\n')[1].split('user sim-002')[0]
    assert 'topic write rutautp/simulacion/+/observaciones/sim-001/+/posicion' in actor
    assert 'topic write rutautp/vehiculos' not in actor


def test_local_acl_grants_only_backend_the_two_existing_status_publications():
    text=local_acl(['sim-001','sim-002'])
    backend=text.split('user backend\n')[1].split('user reader\n')[0]
    assert {line for line in backend.splitlines() if line.startswith('topic write ')}=={
        'topic write rutautp/vehiculos/+/posicion', 'topic write rutautp/simulacion/estado',
        'topic write rutautp/cambios/estado', 'topic write rutautp/ocupacion/estado'}
    reader=text.split('user reader\n')[1].split('user sim-')[0]
    assert 'topic write ' not in reader
    for principal in ['sim-001','sim-002']:
        actor=text.split('user '+principal+'\n')[1].split('user ')[0]
        assert {line for line in actor.splitlines() if line.startswith('topic write ')}=={
            f'topic write rutautp/simulacion/+/observaciones/{principal}/+/posicion'}


@pytest.mark.parametrize('revision,enabled,seen', [
    (4,False,99.9),  # El OFF automático anterior no confirma el manual de revisión 5.
    (4,False,100.1), (6,False,100.1), (5,True,100.1),
    (5,False,99.9), (5,False,None), (5,False,float('nan')), (5,False,float('inf')),
])
def test_disable_probe_rejects_stale_or_unrelated_off_without_negative_latency(revision,enabled,seen):
    snapshot={'control':{'controlRevision':revision,'enabled':enabled},'controlSeenAtUptime':seen}
    assert probe_disable_delivery_seconds(snapshot,5,100) is None


@pytest.mark.parametrize('seen,expected', [(100,0),(100.25,.25)])
def test_disable_probe_confirms_exact_manual_revision_and_monotonic_delivery(seen,expected):
    snapshot={'control':{'controlRevision':5,'enabled':False},'controlSeenAtUptime':seen}
    assert probe_disable_delivery_seconds(snapshot,5,100)==expected


def test_automatic_off_does_not_turn_observer_diagnostic_into_manual_shutdown_latency():
    before={'requestedEnabled':False,'controlRevision':4,'reason':'producer:backend_or_puback_expired'}
    device={'cleanupUpperBoundSeconds':.1269}
    report=disable_measurements(before,5,device)
    assert report['controlWasEnabledBeforeDisable'] is False
    assert report['automaticDisableReason']=='producer:backend_or_puback_expired'
    assert report['disableRequestedRevision']==5
    assert report['iosCleanupTimingUsable'] is False and report['iosCleanupSeconds'] is None
    assert device=={'cleanupUpperBoundSeconds':.1269}  # Conservar diagnóstico original.


@pytest.mark.parametrize('requested_revision,usable', [(4,True),(5,False)])
def test_manual_shutdown_latency_requires_no_intervening_control_revision(requested_revision,usable):
    before={'requestedEnabled':True,'controlRevision':3,'reason':'running'}
    report=disable_measurements(before,requested_revision,{'cleanupUpperBoundSeconds':1.25})
    assert report['controlWasEnabledBeforeDisable'] is True
    assert report['automaticDisableReason'] is None
    assert report['controlChangedBeforeManualDisable'] is (not usable)
    assert report['iosCleanupTimingUsable'] is usable
    assert report['iosCleanupSeconds']==(1.25 if usable else None)


@pytest.mark.parametrize('diagnostic', [-.1,None,float('nan'),float('inf'),True])
def test_invalid_observer_diagnostic_never_becomes_a_shutdown_latency(diagnostic):
    before={'requestedEnabled':True,'controlRevision':3,'reason':'running'}
    report=disable_measurements(before,4,{'cleanupUpperBoundSeconds':diagnostic})
    assert report['iosCleanupTimingUsable'] is False and report['iosCleanupSeconds'] is None


@pytest.mark.parametrize('host', ['0.0.0.0','8.8.8.8','169.254.1.1','224.0.0.1','localhost','::1'])
def test_no_public_or_wildcard_trial_listener(host):
    with pytest.raises(ValueError): trial_host(host)


@pytest.mark.parametrize('host', ['127.0.0.1','10.0.0.1','172.16.1.1','192.168.18.87'])
def test_explicit_private_interface(host):
    assert trial_host(host)==host


def test_disk_measurement_counts_only_trial_history_and_reference(tmp_path):
    assert all(value==0 for value in trial_disk(tmp_path).values())
    (tmp_path/'history.sqlite').write_bytes(b'1234')
    (tmp_path/'reference.jsonl').write_bytes(b'12')
    (tmp_path/'passwords').write_bytes(b'not-measured')
    measured=trial_disk(tmp_path)
    assert measured['history.sqlite']==4 and measured['reference.jsonl']==2
    assert 'passwords' not in measured


# Cuota diaria del escenario v2: únicamente carpetas temporales y llamadas de reserva.
def quota_claimed_store(tmp_path, name='pasajeros-30', *, pinned_override=None):
    profile = SimulationProfile.load(name, GTFS_DIR)
    now = datetime(2026, 10, 26, 12, tzinfo=lima_zone()).timestamp()
    _, day, closes = profile.window(now)
    store = ControlStore.initialize(tmp_path/'control/control.sqlite', now)
    store.enable(pinned_override or profile.pinned(), now)
    run, owner, instance = (str(uuid.uuid4()) for _ in range(3))
    state = store.change('offline_test_claim', now, lambda state: state.update(
        runId=run, owner=owner, serviceDate=day, serviceEndsAt=closes, runStartedAt=now))
    store.claim_producer(run, state['revision'], owner, instance, now)
    return store, state, instance


def quota_reserve(store, state, instance, *, max_run=6000, max_day=10000):
    return store.reserve_publish(state['runId'], state['revision'], state['owner'], instance,
        state['serviceDate'], max_run=max_run, max_day=max_day)


@pytest.mark.parametrize('name,day_limit,version', [('ensayo-2',6000,1),('ensayo-6',6000,1),('pasajeros-30',10000,2)])
def test_version_two_daily_ceiling_is_per_profile_and_versioned(name,day_limit,version):
    import rutautp_backend.simulation_profile as module
    assert Path(module.__file__).resolve().parents[1] == Path(__file__).resolve().parents[1]
    profile = SimulationProfile.load(name, GTFS_DIR)
    validate_publication(profile)
    body = json.loads(profile.raw)
    assert body['scenarioVersion'] == version
    assert body['limits']['maxObservationPublishCallsPerDay'] == day_limit
    assert body['limits']['maxObservationPublishCallsPerRun'] == PROFILE_SPECS[name][3]
    assert body['limits']['maxRunDurationSeconds'] == PROFILE_SPECS[name][2]
    assert body['publication']['minimumIntervalSeconds'] == 5
    assert all(len(vehicle['principals']) >= 2 for vehicle in body['vehicles'])


@pytest.mark.parametrize('name,ceiling', [('ensayo-2',6000),('ensayo-6',6000),('pasajeros-30',10000)])
@pytest.mark.parametrize('violation', ['day_over','run_over','zero','boolean','fractional'])
def test_version_two_profile_and_actor_validator_reject_budget_boundaries(tmp_path,monkeypatch,name,ceiling,violation):
    import rutautp_backend.simulation_profile as module
    profile = SimulationProfile.load(name, GTFS_DIR)
    body = json.loads(profile.raw)
    key, value = {
        'day_over': ('maxObservationPublishCallsPerDay',ceiling+1),
        'run_over': ('maxObservationPublishCallsPerRun',PROFILE_SPECS[name][3]+1),
        'zero': ('maxObservationPublishCallsPerDay',0),
        'boolean': ('maxObservationPublishCallsPerDay',True),
        'fractional': ('maxObservationPublishCallsPerDay',1.5),
    }[violation]
    body['limits'][key] = value
    raw = json.dumps(body)
    (tmp_path/(name+'.json')).write_text(raw)
    monkeypatch.setattr(module,'PROFILE_DIRECTORY',tmp_path)
    with pytest.raises(ValueError): SimulationProfile.load(name,GTFS_DIR)
    with pytest.raises(ValueError): validate_publication(replace(profile,raw=raw))


@pytest.mark.parametrize('name,ceiling', [('ensayo-2',6000),('ensayo-6',6000),('pasajeros-30',10000)])
def test_version_two_store_accepts_exact_daily_ceiling(tmp_path,name,ceiling):
    store,state,instance = quota_claimed_store(tmp_path,name)
    assert quota_reserve(store,state,instance,max_run=PROFILE_SPECS[name][3],max_day=ceiling) == (1,1)


@pytest.mark.parametrize('name,ceiling', [('ensayo-2',6000),('ensayo-6',6000),('pasajeros-30',10000)])
@pytest.mark.parametrize('violation', ['day_over','run_over','boolean','zero'])
def test_version_two_store_rejects_invalid_limits_without_changing_ledger(tmp_path,name,ceiling,violation):
    store,state,instance = quota_claimed_store(tmp_path,name)
    limits = {'max_run':PROFILE_SPECS[name][3],'max_day':ceiling}
    key,value = {'day_over':('max_day',ceiling+1),'run_over':('max_run',6001),
                 'boolean':('max_day',True),'zero':('max_day',0)}[violation]
    limits[key] = value
    before = store.runtime()
    error = ControlUnavailable if violation == 'day_over' else ValueError
    with pytest.raises(error): quota_reserve(store,state,instance,**limits)
    assert store.runtime() == before


def test_version_two_second_run_3108_plus_6000_preserves_ledger_and_run_cap(tmp_path):
    store,state,instance = quota_claimed_store(tmp_path)
    old_run = str(uuid.uuid4())
    ledger = {'runs':{old_run:3108,state['runId']:5999},'days':{'2026-10-25':4815,state['serviceDate']:9107}}
    store.runtime(publishBudget=ledger)
    assert quota_reserve(store,state,instance) == (6000,9108)
    saved = ControlStore(store.path).runtime()['publishBudget']
    assert saved['runs'][old_run] == 3108 and saved['days']['2026-10-25'] == 4815
    with pytest.raises(PublishBudgetExhausted): quota_reserve(store,state,instance)
    assert ControlStore(store.path).runtime()['publishBudget'] == saved
    assert 3108 + 6000 == 9108 <= 10000


def test_version_two_daily_boundary_10000_is_inclusive_and_never_exceeded(tmp_path):
    store,state,instance = quota_claimed_store(tmp_path)
    store.runtime(publishBudget={'runs':{},'days':{state['serviceDate']:9999}})
    assert quota_reserve(store,state,instance) == (1,10000)
    saved = store.runtime()['publishBudget']
    with pytest.raises(PublishBudgetExhausted): quota_reserve(store,state,instance)
    assert store.runtime()['publishBudget'] == saved


def test_version_two_old_pinned_version_one_does_not_gain_daily_allowance(tmp_path):
    profile = SimulationProfile.load('pasajeros-30',GTFS_DIR)
    body = json.loads(profile.raw)
    body['scenarioVersion'] = 1
    body['limits']['maxObservationPublishCallsPerDay'] = 6000
    raw = json.dumps(body)
    pinned = {**profile.pinned(),'raw':raw,'sha256':hashlib.sha256(raw.encode()).hexdigest()}
    store,state,instance = quota_claimed_store(tmp_path,pinned_override=pinned)
    before = store.runtime()
    with pytest.raises(ControlUnavailable): quota_reserve(store,state,instance,max_day=10000)
    assert store.runtime() == before
    assert quota_reserve(store,state,instance,max_day=6000) == (1,1)


def test_version_two_lower_ceiling_does_not_reset_already_reserved_day(tmp_path):
    store,state,instance = quota_claimed_store(tmp_path)
    store.runtime(publishBudget={'runs':{},'days':{state['serviceDate']:7000}})
    before = store.runtime()['publishBudget']
    with pytest.raises(PublishBudgetExhausted): quota_reserve(store,state,instance,max_day=6000)
    assert store.runtime()['publishBudget'] == before


def test_version_two_version_change_and_new_generation_keep_prior_day_and_run_ledger(tmp_path):
    profile = SimulationProfile.load('pasajeros-30',GTFS_DIR)
    old_body = json.loads(profile.raw)
    old_body['scenarioVersion'] = 1
    old_body['limits']['maxObservationPublishCallsPerDay'] = 6000
    old_raw = json.dumps(old_body)
    old_pin = {**profile.pinned(),'raw':old_raw,'sha256':hashlib.sha256(old_raw.encode()).hexdigest()}
    store,old_state,old_instance = quota_claimed_store(tmp_path,pinned_override=old_pin)
    store.runtime(publishBudget={'runs':{old_state['runId']:3108},
        'days':{'2026-10-25':4815,old_state['serviceDate']:3108}})
    now = old_state['runStartedAt'] + 2
    store.disable(now-1,'offline_test_finish_old')
    store.enable(profile.pinned(),now)
    run,owner,instance = (str(uuid.uuid4()) for _ in range(3))
    state = store.change('offline_test_new_generation',now,lambda state: state.update(
        runId=run,owner=owner,serviceDate=old_state['serviceDate'],
        serviceEndsAt=old_state['serviceEndsAt'],runStartedAt=now))
    store.claim_producer(run,state['revision'],owner,instance,now)
    assert quota_reserve(store,state,instance) == (1,3109)
    saved = ControlStore(store.path).runtime()['publishBudget']
    assert saved['runs'][old_state['runId']] == 3108 and saved['runs'][run] == 1
    assert saved['days'] == {'2026-10-25':4815,old_state['serviceDate']:3109}
