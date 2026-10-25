"""Ocupación sintética: contrato, procedencia, histórico y migración temporal."""
from dataclasses import replace
import json
import sqlite3
from pathlib import Path
import pytest
from rutautp_backend.config import Config, ConfigError
from rutautp_backend.models import EstimatedVehicle
from rutautp_backend.persistence import ObservationStore, SCHEMA
from rutautp_backend.persistence_migrations import MIGRATIONS
from rutautp_backend.simulation_models import DataOrigin, SourceContext
from rutautp_backend.simulation_occupancy import scenario_occupancy, STATES
from rutautp_backend.simulation_reporting import history_reader, run_report
from .test_simulation_persistence import RUN, NOW, SOURCE, start_run
from .test_simulation_control import rig, profile
from .test_simulation_acceptance import populated_bridge
from .test_contract import swift_vehicle_wire_fields, VEHICLE_TRACKING_RECEPTION


def vehicle():
    return EstimatedVehicle(f'sim:{RUN}:bus', 'route', 'T', -8.1, -79, 5, 90, NOW, NOW)


def test_script_deterministic_varies_over_time_and_not_from_beacon_count():
    v=vehicle()
    values=[scenario_occupancy(SOURCE,v.vehicle_id,NOW+i*300) for i in range(6)]
    assert set(values)==set(STATES)
    assert values==[scenario_occupancy(SOURCE,v.vehicle_id,NOW+i*300) for i in range(6)]
    assert scenario_occupancy(SOURCE,v.vehicle_id,NOW)==scenario_occupancy(SOURCE,v.vehicle_id,NOW+.001)


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
