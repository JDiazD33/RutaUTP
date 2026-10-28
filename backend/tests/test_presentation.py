"""Operación de presentación offline: SQLite temporal, sin broker ni iPhone."""
import csv
import hashlib
import json
from pathlib import Path
from types import SimpleNamespace
import time

import pytest

from simulation import presentation as p
from rutautp_backend.simulation_control_store import ControlStore


@pytest.fixture
def prepared(tmp_path):
    config=tmp_path/'backend.env';config.write_text('MQTT_HOST=broker.example\nMQTT_PORT=8883\nMQTT_TLS=1\nMQTT_USERNAME=backend\nMQTT_PASSWORD=test-only-$literal\nBACKEND_HEALTH_FILE=data/health.json\n')
    directory=tmp_path/'private'
    p.prepare(directory,config)
    return directory


def test_prepare_separates_roles_preserves_secret_permissions_and_never_enables(prepared):
    directory=prepared
    actors=p.private_read(directory/'actors-credentials.json');reader=p.private_read(directory/'reader.json')
    assert len(actors['accounts'])==30 and reader['username']=='presentation-reader'
    passwords=[a['password'] for a in actors['accounts'].values()]+[reader['password']]
    assert len(set(passwords))==31
    assert not ControlStore(directory/'control/control.sqlite').read()['enabled']
    assert p.private_read(directory/'backend-environment.json')['MQTT_PASSWORD']=='test-only-$literal'
    for file in directory.glob('*'):
        if file.is_file():assert file.stat().st_mode&0o077==0
    assert directory.stat().st_mode&0o077==0
    with (directory/'EMQX-PERMISOS-IMPORTAR.csv').open() as stream:rules=list(csv.DictReader(stream))
    assert len(rules)==93
    assert all(r['access']=='deny' for r in rules if r['topic']=='#')
    assert not [r for r in rules if r['username']=='backend']
    assert p.private_read(directory/'EMQX-PERMISOS-REVISAR.json')[-1]['username']=='backend'


def test_prepare_refuses_overwrite(prepared,tmp_path):
    before=(prepared/'actors-credentials.json').read_bytes()
    with pytest.raises(ValueError,match='ya existe'):p.prepare(prepared,tmp_path/'backend.env')
    assert (prepared/'actors-credentials.json').read_bytes()==before


@pytest.mark.parametrize('seconds,calls',[(60,390),(180,1110),(900,5430)])
def test_bounded_duration_reserves_conservative_publication_calls(seconds,calls):
    assert p.required_calls(seconds)==calls


@pytest.mark.parametrize('seconds',[True,0,59,901,180.0,'180'])
def test_unbounded_or_invalid_duration_rejected(seconds):
    with pytest.raises(ValueError):p.required_calls(seconds)


def test_foreign_endpoint_is_not_mixed_with_actor_credentials(prepared):
    reader=p.private_read(prepared/'reader.json');reader['host']='other.example'
    p.private_json(prepared/'reader.json',reader)
    with pytest.raises(ValueError,match='mismo broker'):p.configuration(prepared)


def test_private_read_rejects_world_readable_files_and_symlinks(tmp_path):
    path=tmp_path/'settings.json';path.write_text('{}');path.chmod(0o644)
    with pytest.raises(ValueError):p.private_read(path)
    path.chmod(0o600);link=tmp_path/'link';link.symlink_to(path)
    with pytest.raises(ValueError):p.private_read(link)


def ledger(workspace,name):
    path=workspace/'mds'/('evidencias-'+name)/'trial/control/control.sqlite'
    path.parent.mkdir(parents=True,mode=0o700)
    return ControlStore.initialize(path,1000)


def test_budget_sums_distinct_ledgers_and_deduplicates_exact_copies(tmp_path):
    first=ledger(tmp_path,'one');second=ledger(tmp_path,'two')
    # Un ledger inicial, sin consumo, también cuenta y sigue deshabilitado.
    result=p.aggregate_budget(tmp_path,first.path,'2026-10-27')
    assert result['used']==0 and len(result['controls'])==2 and not result['otherControlEnabled']
    copy=tmp_path/'mds/evidencias-copy/trial/control/control.sqlite';copy.parent.mkdir(parents=True)
    import shutil
    shutil.copy2(first.path,copy)
    result=p.aggregate_budget(tmp_path,second.path,'2026-10-27')
    assert len(result['controls'])==3 and sum(r['counted'] for r in result['controls'])==2


def set_budget(path,used):
    import sqlite3
    with sqlite3.connect(path) as db:
        value=json.loads(db.execute('SELECT snapshot FROM runtime').fetchone()[0])
        value['publishBudget']={'days':{'2026-10-27':used},'runs':{}}
        db.execute('UPDATE runtime SET snapshot=?',(json.dumps(value),))


def test_budget_keeps_previous_consumption_across_controls_and_copies(tmp_path):
    import shutil
    first=ledger(tmp_path,'one');second=ledger(tmp_path,'two')
    set_budget(first.path,4957);set_budget(second.path,743)
    copy=tmp_path/'mds/evidencias-copy/trial/control/control.sqlite';copy.parent.mkdir(parents=True)
    shutil.copy2(first.path,copy)
    assert p.aggregate_budget(tmp_path,first.path,'2026-10-27')['used']==5700


def test_divergent_copy_of_same_ledger_blocks_instead_of_resetting_budget(tmp_path):
    import shutil
    first=ledger(tmp_path,'one');set_budget(first.path,4957)
    copy=tmp_path/'mds/evidencias-copy/trial/control/control.sqlite';copy.parent.mkdir(parents=True)
    shutil.copy2(first.path,copy);set_budget(copy,100)
    with pytest.raises(ValueError,match='divergentes'):p.aggregate_budget(tmp_path,first.path,'2026-10-27')


def test_live_service_lock_prevents_duplicate_and_status_does_not_claim_ready(prepared):
    assert not p.service_state(prepared)['serviceRunning']
    with p.service_lock(prepared):
        assert p.service_state(prepared)['serviceRunning']
        with pytest.raises(BlockingIOError):
            with p.service_lock(prepared):pass
    assert not p.service_state(prepared)['serviceRunning']


def test_stop_of_idle_service_preserves_configuration(prepared):
    assert p.stop_service(prepared)=={'stopped':True,'wasRunning':False}
    assert (prepared/'actors-credentials.json').exists()
    assert not ControlStore(prepared/'control/control.sqlite').read()['enabled']


def test_stop_request_only_applies_to_current_owner(prepared):
    stop=p.ServiceStop(prepared,'current')
    assert not stop.is_set()
    p.private_json(prepared/'stop-request.json',{'owner':'old'})
    assert not stop.wait(0)
    p.private_json(prepared/'stop-request.json',{'owner':'current'})
    assert stop.wait(0)


def test_signal_stop_does_not_require_a_request_file(prepared):
    stop=p.ServiceStop(prepared,'current');stop.set()
    assert stop.is_set()


def test_no_accounts_or_processes_started_when_daily_budget_insufficient(prepared,monkeypatch):
    daytime(monkeypatch)
    monkeypatch.setattr(p,'aggregate_budget',lambda *_:{'used':9900,'otherControlEnabled':False})
    monkeypatch.setattr(p.subprocess,'Popen',lambda *_args,**_kwargs:pytest.fail('unexpected process'))
    with pytest.raises(ValueError,match='cuota insuficiente'):p.run_service(prepared,180)
    assert not ControlStore(prepared/'control/control.sqlite').read()['enabled']


def test_remote_enabled_control_never_starts_backend_or_changes_broker(prepared,monkeypatch):
    daytime(monkeypatch)
    actor_file=prepared/'actors-credentials.json';reader_file=prepared/'reader.json'
    p.private_json(prepared/'acl-verified.json',{'host':'broker.example','port':8883,
        'credentialsSHA256':hashlib.sha256(actor_file.read_bytes()).hexdigest(),
        'readerSHA256':hashlib.sha256(reader_file.read_bytes()).hexdigest()})
    monkeypatch.setattr(p,'aggregate_budget',lambda *_:{'used':0,'otherControlEnabled':False})
    monkeypatch.setattr(p,'read_heartbeat',lambda *_:None)
    monkeypatch.setattr(p.subprocess,'Popen',lambda *_args,**_kwargs:pytest.fail('backend would overwrite remote control'))
    closed=[]
    class Reader:
        def __init__(self,*_):pass
        def snapshot(self):return {'connected':True,'control':{'enabled':True,'controlRevision':9}}
        def close(self):closed.append(True)
    monkeypatch.setattr(p,'Reader',Reader)
    monkeypatch.setattr(p,'wait_for',lambda predicate,*_args,**_kwargs:predicate())
    result=p.run_service(prepared,60)
    assert result['state']=='fallo' and 'remoto ajeno' in result['reason']
    assert result['ownedProcessesStopped'] and closed==[True]
    assert not ControlStore(prepared/'control/control.sqlite').read()['enabled']


def daytime(monkeypatch):
    from datetime import datetime
    from rutautp_backend.simulation_profile import lima_zone
    fixed=datetime(2026,10,27,12,tzinfo=lima_zone()).timestamp()
    monkeypatch.setattr(p,'time',SimpleNamespace(time=lambda:fixed,
        monotonic=time.monotonic,sleep=lambda _:None))


@pytest.mark.parametrize("profile_name,expected_vehicles",[("pasajeros-30",10),("pasajeros-50",15)])
def test_complete_service_reads_stop_request_persists_off_and_closes_only_owned_children(prepared,monkeypatch,profile_name,expected_vehicles):
    if profile_name=="pasajeros-50":p.prepare_profile(prepared,profile_name)
    credential_file,proof_file=p.profile_files(prepared,profile_name)
    from datetime import datetime
    from rutautp_backend.simulation_profile import lima_zone
    clock=SimpleNamespace(now=1000.0)
    base=datetime(2026,10,27,12,tzinfo=lima_zone()).timestamp()
    def advance(seconds):clock.now+=seconds
    monkeypatch.setattr(p,'time',SimpleNamespace(time=lambda:base+clock.now,
        monotonic=lambda:clock.now,sleep=advance))
    control=SimpleNamespace(path=prepared/'control/control.sqlite',enabled=False,revision=1)
    control.read=lambda:{'enabled':control.enabled,'revision':control.revision}
    def enable(*_):control.enabled=True;control.revision+=1;return {'runId':None,'revision':control.revision}
    def disable(*_):control.enabled=False;control.revision+=1;return control.read()
    control.enable=enable;control.disable=disable
    monkeypatch.setattr(p,'ControlStore',lambda *_:control)
    monkeypatch.setattr(p,'aggregate_budget',lambda *_:{'used':6884,'otherControlEnabled':False})
    p.private_json(proof_file,{'host':'broker.example','port':8883,
        'credentialsSHA256':hashlib.sha256(credential_file.read_bytes()).hexdigest(),
        'readerSHA256':hashlib.sha256((prepared/'reader.json').read_bytes()).hexdigest()})
    children=[]
    class Child:
        def __init__(self,args,**_):self.args=args;self.pid=100+len(children);self.done=False;children.append(self)
        def poll(self):return 0 if self.done else None
        def terminate(self):self.done=True
        def kill(self):self.done=True
        def wait(self,timeout):return 0
    monkeypatch.setattr(p.subprocess,'Popen',Child)
    monkeypatch.setattr(p,'read_heartbeat',lambda path: {'connected':True,'at':base+clock.now} if children else None)
    monkeypatch.setattr(p,'status',lambda *_:{'requestedEnabled':control.enabled,'controlRevision':control.revision,
        'backend':{'fresh':True},'mqtt':{'lastAckedRevision':control.revision},'runOwner':'owner','reason':'running',
        'runId':'run',
        'producer':{'status':'running' if control.enabled else 'stopped'}})
    class Reader:
        def __init__(self,*_):pass
        def snapshot(self):return {'connected':True,'control':{'enabled':control.enabled,'controlRevision':control.revision},
            'currentVehicles':expected_vehicles if control.enabled else 0,'occupancy':{'empty':2,'space':5,'full':3}}
        def close(self):pass
    monkeypatch.setattr(p,'Reader',Reader)
    original=p.ServiceStop
    def stop_factory(directory,owner):
        result=original(directory,owner)
        class Event:
            def is_set(self):return False
            def set(self):pass
            def wait(self,seconds):
                advance(seconds)
                if clock.now>=1002:p.private_json(prepared/'stop-request.json',{'owner':owner})
        result.event=Event();return result
    monkeypatch.setattr(p,'ServiceStop',stop_factory)
    result=p.run_service(prepared,180,profile_name)
    assert result['state']=='detenido' and result['reason']=='presentation_operator_stop'
    assert result['readyObserved'] and result['offDeliveryConfirmed']
    assert result['runId']=='run'
    assert result['expectedVehicles']==expected_vehicles and result['profile']==profile_name
    assert str(credential_file) in children[-1].args and profile_name in children[-1].args
    assert result['dayUsedBefore']==6884 and not control.enabled
    assert result['ownedProcessesStopped'] and len(children)==3 and all(c.done for c in children)
    assert result['probe']['currentVehicles']==0 and result['remainingSeconds']==0
    assert p.private_read(prepared/'status.json')['state']=='detenido'


@pytest.mark.parametrize('body,valid',[
    ({'enabled':False,'controlRevision':4,'runId':'run'},True),
    ({'enabled':False,'controlRevision':5,'runId':'run'},True),
    ({'enabled':False,'controlRevision':3,'runId':'run'},False),
    ({'enabled':False,'controlRevision':4,'runId':'other'},False),
    ({'enabled':True,'controlRevision':4,'runId':'run'},False),
    ({},False),
])
def test_shutdown_receipt_requires_current_revoked_run(body,valid):
    assert p.received_current_off({'control':body},{'revision':4,'runId':'run'}) is valid


@pytest.mark.parametrize('remote,conflict',[
    ({'enabled':True,'controlRevision':3,'runId':'run'},False),
    ({'enabled':True,'controlRevision':3,'runId':'other'},True),
    ({'enabled':True,'controlRevision':4,'runId':'run'},True),
    ({'enabled':False,'controlRevision':5,'runId':'run'},True),
    ({'enabled':False,'controlRevision':4,'runId':'run'},False),
    (None,False),
])
def test_restart_reconciles_only_own_older_retained_control(remote,conflict):
    assert p.remote_control_conflicts(remote,{'enabled':False,'revision':4,'runId':'run'}) is conflict
