"""Escalado 30→50: cuentas preservadas, geometría local y límites explícitos."""
from collections import Counter
from datetime import datetime
import csv
import json

import pytest

from simulation import presentation as p
from simulation.actors import validate_publication
from simulation.clock import ClockSample
from simulation.scenario import ScenarioEngine
from rutautp_backend.simulation_control_store import ControlStore
from rutautp_backend.simulation_profile import SimulationProfile, lima_zone
from .conftest import GTFS_DIR
from .test_presentation import prepared


def test_fifty_profile_has_exact_independent_identities_and_three_or_four_per_bus():
    profile=SimulationProfile.load('pasajeros-50',GTFS_DIR)
    body=json.loads(profile.raw);validate_publication(profile)
    assert len(profile.principals)==50 and len(body['vehicles'])==15
    assert Counter(len(v['principals']) for v in body['vehicles'])=={3:10,4:5}
    assert len({v['routeId'] for v in body['vehicles']})==15
    assert profile.max_run_seconds==300


def test_fifty_motor_preserves_all_fifteen_vehicles_through_short_trial():
    profile=SimulationProfile.load('pasajeros-50',GTFS_DIR)
    model=ScenarioEngine.from_profile(profile,GTFS_DIR,'8e5dc699-60d4-4f58-8ced-638313365544')
    now=datetime(2026,10,28,12,tzinfo=lima_zone()).timestamp()
    first=model.advance(ClockSample(now,100))
    assert len(first.observations)==50 and len(first.vehicles)==15
    for elapsed in range(1,180):
        last=model.advance(ClockSample(now+elapsed,100+elapsed))
    assert len(last.vehicles)==15 and all(v.contributors>=2 for v in last.vehicles)


def test_extending_accounts_preserves_old_files_passwords_control_and_reader(prepared):
    files=['actors-credentials.json','reader.json','backend-environment.json','control/control.sqlite']
    before={name:(prepared/name).read_bytes() for name in files}
    old=p.private_read(prepared/'actors-credentials.json')
    result=p.prepare_profile(prepared,'pasajeros-50')
    assert result['accountsToImport']==20 and result['permissionRowsToImport']==60
    assert result['actorsStarted'] is False and result['networkStarted'] is False
    assert before=={name:(prepared/name).read_bytes() for name in files}
    profile,actors,reader,_=p.configuration(prepared,'pasajeros-50')
    assert len(actors.accounts)==50 and len(profile.principals)==50
    assert all(actors.accounts[key].password==value['password'] for key,value in old['accounts'].items())
    with (prepared/'EMQX-CUENTAS-ADICIONALES-50.csv').open() as stream:accounts=list(csv.DictReader(stream))
    assert {row['username'] for row in accounts}=={f'sim-{i:03d}' for i in range(31,51)}
    with (prepared/'EMQX-PERMISOS-ADICIONALES-50.csv').open() as stream:rules=list(csv.DictReader(stream))
    assert len(rules)==60 and not any(row['username'] in old['accounts'] for row in rules)
    assert all(row['access']=='deny' for row in rules if row['topic']=='#')
    assert not ControlStore(prepared/'control/control.sqlite').read()['enabled']
    assert len(p.configuration(prepared)[1].accounts)==30


def test_second_preparation_refuses_to_rotate_existing_extension(prepared):
    p.prepare_profile(prepared,'pasajeros-50')
    file,_=p.profile_files(prepared,'pasajeros-50');before=file.read_bytes()
    with pytest.raises(ValueError,match='sin sobrescribir'):p.prepare_profile(prepared,'pasajeros-50')
    assert file.read_bytes()==before


@pytest.mark.parametrize('seconds,calls',[(60,650),(180,1850),(300,3050)])
def test_fifty_budget_counts_fifty_identities(seconds,calls):
    assert p.required_calls(seconds,50,300)==calls


@pytest.mark.parametrize('seconds',[301,900])
def test_fifty_cannot_inherit_thirty_fifteen_minute_duration(seconds):
    with pytest.raises(ValueError):p.required_calls(seconds,50,300)


def test_unprepared_hundred_profile_is_still_rejected(prepared):
    with pytest.raises(ValueError):p.profile_files(prepared,'pasajeros-100')
    with pytest.raises(ValueError):p.required_calls(180,100)
