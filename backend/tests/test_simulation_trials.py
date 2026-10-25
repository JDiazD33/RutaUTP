"""S10: escalones autorizados, entorno aislado y contratos; todo offline."""
import json
from datetime import datetime
from pathlib import Path
import pytest

from rutautp_backend.simulation_profile import PROFILE_SPECS, SimulationProfile, lima_zone
from simulation.clock import ClockSample
from simulation.geometry import load_trip_geometries
from simulation.scenario import ScenarioEngine
from simulation.publisher import load_credentials
from simulation.local_trial import isolated_environment, local_acl, trial_host, private_json, trial_disk
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
    assert body['limits']['maxObservationPublishCallsPerDay']==6000
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
