"""Ocupación sintética: contrato, procedencia, histórico y migración temporal."""
from dataclasses import replace
from datetime import datetime
import json
import sqlite3
from pathlib import Path
import pytest
from rutautp_backend.config import Config, ConfigError
from rutautp_backend.models import EstimatedVehicle
from rutautp_backend.persistence import ObservationStore, SCHEMA
from rutautp_backend.persistence_migrations import MIGRATIONS
from rutautp_backend.simulation_models import DataOrigin, SourceContext
from rutautp_backend.simulation_occupancy import demand_at, demand_label, scenario_occupancy, STATES
from rutautp_backend.simulation_profile import lima_zone
from rutautp_backend.simulation_reporting import history_reader, run_report
from .test_simulation_persistence import RUN, NOW, SOURCE, start_run
from .test_simulation_control import rig, profile
from .test_simulation_acceptance import populated_bridge
from .test_contract import swift_vehicle_wire_fields, VEHICLE_TRACKING_RECEPTION


def vehicle():
    return EstimatedVehicle(f'sim:{RUN}:bus', 'route', 'T', -8.1, -79, 5, 90, NOW, NOW)


def lima(hour,minute=0):
    return datetime(2026,10,21,hour,minute,tzinfo=lima_zone()).timestamp()


def mix(hour,minute=0,count=300):
    """Proporción de cada estado entre muchos micros sintéticos a esa hora."""
    states=[scenario_occupancy(SOURCE,f'sim:{RUN}:bus-{i:03d}',lima(hour,minute)) for i in range(count)]
    return {state:states.count(state)/count for state in STATES}


def test_script_deterministic_varies_over_time_and_not_from_beacon_count():
    v=vehicle()
    day=[scenario_occupancy(SOURCE,v.vehicle_id,lima(0)+i*300) for i in range(288)]
    assert day==[scenario_occupancy(SOURCE,v.vehicle_id,lima(0)+i*300) for i in range(288)]
    assert scenario_occupancy(SOURCE,v.vehicle_id,NOW)==scenario_occupancy(SOURCE,v.vehicle_id,NOW+.001)
    # De madrugada siempre vacío; en el pico del mediodía nunca vacío.
    assert day[0]=='empty' and 'empty' not in day[12*13:12*13+6]


def test_demand_curve_follows_lima_day_without_sudden_drops():
    # El desfase fijo UTC−5 del guion coincide con America/Lima.
    assert demand_at(lima(8))==demand_at(lima(13))==1.0
    assert demand_at(lima(6))<demand_at(lima(7))<demand_at(lima(8))
    assert demand_at(lima(10))<demand_at(lima(12))
    assert demand_at(lima(18))>demand_at(lima(19))>demand_at(lima(20))>demand_at(lima(21))>demand_at(lima(22))
    steps=[demand_at(lima(0)+i*300) for i in range(289)]
    assert all(0<=value<=1 for value in steps)
    assert max(abs(b-a) for a,b in zip(steps,steps[1:]))<=0.04
    assert (demand_label(lima(13)),demand_label(lima(10,30)),demand_label(lima(21,30)))==('alta','media','baja')
    with pytest.raises(ValueError): demand_at(float('nan'))


def test_mix_tracks_peaks_and_gradual_evening_decline():
    noon,valley=mix(13),mix(10,30)
    assert noon['full']>0.6 and noon['empty']==0
    assert valley['full']<0.15 and valley['space']>0.8
    evening=[mix(hour) for hour in (18,19,20,21,22)]
    full=[m['full'] for m in evening]
    assert full==sorted(full,reverse=True) and full[0]>full[1]>full[2]
    assert full[3]==full[4]==0
    assert evening[2]['empty']<evening[3]['empty']<evening[4]['empty']


def test_vehicle_never_jumps_between_empty_and_full():
    for i in range(100):
        day=[scenario_occupancy(SOURCE,f'sim:{RUN}:bus-{i:03d}',lima(0)+k*300) for k in range(289)]
        assert all({a,b}!={'empty','full'} for a,b in zip(day,day[1:]))


@pytest.mark.parametrize('source,identifier,stamp', [
    (SourceContext(DataOrigin.OBSERVED),'observed',NOW),
    (SOURCE,'sim:wrong:bus',NOW), (SOURCE,f'sim:{RUN}:bus',float('nan')),
    (SOURCE,f'sim:{RUN}:bus',-1)])
def test_script_rejects_invalid_provenance_and_time(source,identifier,stamp):
    with pytest.raises(ValueError): scenario_occupancy(source,identifier,stamp)


def test_wire_v3_matches_swift_and_preserves_timestamp():
    body=vehicle().to_vehicle_position_v3(SOURCE,3)
    _,v2=swift_vehicle_wire_fields()
    assert set(body)==v2|{'scenarioOccupancy','occupancyScriptVersion'}
    assert body['schemaVersion']==3 and body['occupancyScriptVersion']==1
    assert body['timestamp']==NOW and body['scenarioOccupancy'] in STATES
    text=VEHICLE_TRACKING_RECEPTION.read_text()
    assert 'case scenarioOccupancy, occupancyScriptVersion' in text


def test_occupancy_requires_explicit_ingress_and_defaults_off():
    assert not Config().simulation_occupancy_enabled
    with pytest.raises(ConfigError): Config(simulation_occupancy_enabled=True)
    with pytest.raises(ConfigError): Config(simulation_occupancy_enabled=1)


def test_bridge_persists_exact_occupancy_before_publication(rig,feed,sample_route):
    bridge,publisher,run=populated_bridge(rig,feed,sample_route)
    bridge.config=replace(bridge.config,simulation_occupancy_enabled=True)
    v=bridge._simulation_aggregator.snapshot()[0]
    v.timestamp += 5
    rig.clock.now += 5
    rig.clock.mono += 5
    assert bridge._publish_if_due(v,rig.clock.now,rig.clock.now,
        aggregator=bridge._simulation_aggregator,source=SourceContext(DataOrigin.SIMULATED,run),
        admission=rig.controller.admission(rig.clock.now))
    body=json.loads(publisher.messages[-1][1])
    assert body['schemaVersion']==3
    rows=rig.history.query('SELECT scenario_occupancy,occupancy_script_version FROM vehicle_positions ORDER BY id DESC LIMIT 1')
    assert rows==[(body['scenarioOccupancy'],1)]


@pytest.mark.parametrize('state,version,source', [
    ('full',None,SOURCE), (None,1,SOURCE), ('invalid',1,SOURCE),('full',True,SOURCE),
    ('full',1,SourceContext(DataOrigin.OBSERVED))])
def test_history_rejects_inconsistent_occupancy(tmp_path,state,version,source):
    store=ObservationStore(tmp_path/'history.sqlite',min_simulation_free_bytes=0)
    try:
        with pytest.raises(ValueError): store.record_vehicle(vehicle(),NOW,source=source,
            scenario_occupancy=state,occupancy_script_version=version)
    finally: store.close()


def test_schema1_read_only_then_migrates_with_backup(tmp_path):
    path=tmp_path/'old.sqlite'
    with sqlite3.connect(path) as db:
        db.executescript(SCHEMA+(Path(__file__).parents[1]/'rutautp_backend/migrations'/MIGRATIONS[1]).read_text())
        db.execute('INSERT INTO store_schema_migrations VALUES(1,?,?,NULL)',(MIGRATIONS[1],NOW))
        db.execute('PRAGMA user_version=1')
    before=path.read_bytes()
    with history_reader(path) as db: assert db.execute('PRAGMA user_version').fetchone()[0]==1
    assert path.read_bytes()==before
    store=ObservationStore(path,min_simulation_free_bytes=0)
    try:
        assert store.enabled and store.query('PRAGMA user_version')==[(2,)]
        with sqlite3.connect(store.migration_backup) as backup:
            assert backup.execute('PRAGMA user_version').fetchone()[0]==1
        start_run(store)
        store.record_vehicle(vehicle(),NOW,source=SOURCE,scenario_occupancy='full',occupancy_script_version=1)
        store.flush()
        assert run_report(path,RUN,NOW)['scenarioOccupancyStoredAttempts']=={'full':1}
        with pytest.raises(sqlite3.IntegrityError):
            store._connection.execute("UPDATE vehicle_positions SET scenario_occupancy=NULL")
    finally: store.close()
