"""Fases con reloj y CoreDevice capturados. Sin red, dispositivo ni GTFS."""
import json
from pathlib import Path
import subprocess
from types import SimpleNamespace

import pytest

from simulation.device_faults import (ActiveFaultError, ActiveFaultObserver,
    empty_map, full_map, background_cleared, foreground_recovered, network_recovered_disabled)
from simulation.local_trial import run_trial, main


def event(kind, **counts):
    return {'event':kind,'counts':counts,'uptime':100,'wall':1000}


def fleet(size=10):
    return event('map',received=size,fleet=size,occupancyEmpty=0,
        occupancySpace=size,occupancyFull=0)


def lifecycle(stage,state):
    return event('providerLifecycle',processID=7,providerInstance=1,stage=stage,
        applicationState=state)


class Harness:
    def __init__(self,tmp_path):
        self.now = 1000.0
        self.path = tmp_path/'device-console.log'
        self.events = [event('control',enabled=1,revision=3),fleet()]
        self.events += [{'event':'processResources','uptime':100+i,'wall':1000+i,
            'counts':{'schemaVersion':1,'processID':7,'logicalCPUs':6,'active':1,
                'userMicroseconds':10000*i,'systemMicroseconds':0}} for i in range(36)]
        self.commands = []
        self.cut = None
        self.pid = 7
        self.fail_operation = None
        self.background = True
        self.bad_foreground = False
        self.resurrect = False
        self.changed_on_activate = False
        self.activation_response_pid = None
        self.extra_instance = False
        self.stale_stopped = False
        self.status_after_reconnect = None
        self.write()
        self.observer = ActiveFaultObserver('phone','bundle',runner=self.run,
            monotonic=lambda:self.now,sleep=self.sleep,notifier=self.notify)
        self.observer.output = tmp_path
        self.observer.pid = 7
        self.observer.cpu_start = 100
        self.observer.cpu_end = 135
        self.observer.activation_environment = {'DEVICECTL_CHILD_MQTT_PASSWORD':'never-log-this-secret'}
        self.observer.begin_active_run(self.now)

    def write(self):
        self.path.write_text(''.join('[S10] '+json.dumps(e)+'\n' for e in self.events))

    def append(self,*events):
        self.events.extend(events)
        self.write()

    def sleep(self,seconds):
        self.now += seconds

    def notify(self,raw,**_):
        assert json.loads(raw)['phase']=='background_iphone_request'
        if self.background:self.append(lifecycle(10,2),fleet(0))

    def run(self,args,*,capture_output,timeout,env):
        operation = 'pid_check' if 'info' in args else (
            'activate' if 'launch' in args else ('suspend' if 'suspend' in args else 'resume'))
        self.commands.append({'operation':operation,'args':args,'timeout':timeout,'env':env})
        if self.fail_operation==operation:
            self.fail_operation=None
            raise subprocess.TimeoutExpired(args,timeout)
        if operation=='activate':
            if self.changed_on_activate:self.pid=8
            self.append(lifecycle(11,1),lifecycle(9,0))
            if self.bad_foreground:self.append(fleet())
            self.append(event('control',enabled=1,revision=3),fleet())
        result = {'processIdentifier':self.pid,'secret':'never-log-this-secret'}
        if operation=='activate' and self.activation_response_pid is not None:
            result['processIdentifier']=self.activation_response_pid
        if operation=='pid_check':
            result={'runningProcesses':[{'processIdentifier':self.pid,
                'executable':'/private/containers/RutaUTP.app/RutaUTP'}]}
            if self.extra_instance:
                result['runningProcesses'].append({'processIdentifier':9,
                    'executable':'/private/other/RutaUTP.app/RutaUTP'})
        Path(args[args.index('--json-output')+1]).write_text(json.dumps({
            'info':{'outcome':'success','environment':{'secret':'never-log-this-secret'}},'result':result}))
        return SimpleNamespace(returncode=0)

    def status(self):
        stopped = self.cut is not None and self.now-self.cut>=15
        current = {'requestedEnabled':not stopped,'controlRevision':4 if stopped else 3,
            'runId':'run','producerProcessExited':stopped,
            'reason':'producer:backend_or_puback_expired' if stopped else 'running',
            'producer':{'status':'stopped' if stopped else 'running'}}
        if self.cut is not None and self.now-self.cut>=30:
            if self.stale_stopped:current['producer']['status']='unknown'
            if self.status_after_reconnect:current.update(self.status_after_reconnect)
        return current

    def disconnect(self):
        self.cut=self.now
        self.append(event('disconnection',accepted=0),fleet(0))

    def reconnect(self):
        self.append(event('connection',accepted=1),event('subscription',control=1))
        if self.resurrect:self.append(fleet())
        self.append(event('control',enabled=0,revision=4))


def test_complete_fault_sequence_preserves_cpu_and_scopes_os_commands(tmp_path):
    h=Harness(tmp_path)
    result=h.observer.check_active_faults(h.disconnect,h.reconnect,h.status)
    assert result['complete'] and h.observer.cpu_end==135
    assert result['suspension']['suspendedHoldSeconds']>=25
    assert result['suspension']['pidUnchanged']
    assert not h.observer.suspended and h.observer.resume_confirmed
    assert result['network']['controlPersistentlyDisabled']
    assert result['network']['producerStopped'] and not result['network']['fleetResurrected']
    assert h.now<=1300
    activation=next(c for c in h.commands if c['operation']=='activate')
    assert '--activate' in activation['args'] and '--terminate-existing' not in activation['args']
    bundle_index=activation['args'].index('bundle')
    assert all(activation['args'].index(option)<bundle_index
        for option in ['--device','--timeout','--json-output','--activate'])
    assert activation['env']['DEVICECTL_CHILD_MQTT_PASSWORD']=='never-log-this-secret'
    assert all('never-log-this-secret' not in arg for c in h.commands for arg in c['args'])
    logs=(tmp_path/'device-faults.jsonl').read_text()
    assert 'never-log-this-secret' not in logs
    assert not list(tmp_path.glob('s10-fault-*.json'))


def test_suspend_timeout_still_attempts_resume_of_verified_owned_pid(tmp_path):
    h=Harness(tmp_path);h.fail_operation='suspend'
    with pytest.raises(ActiveFaultError,match='device_suspend_failed'):
        h.observer.check_active_faults(h.disconnect,h.reconnect,h.status)
    assert [c['operation'] for c in h.commands].count('resume')==1
    assert not h.observer.suspended and h.observer.resume_confirmed
    assert h.cut is None


def test_stopped_heartbeat_can_expire_after_verified_exit(tmp_path):
    h=Harness(tmp_path);h.stale_stopped=True
    result=h.observer.check_active_faults(h.disconnect,h.reconnect,h.status)
    assert result['network']['producerProcessExited']
    assert result['network']['producerStatusAfterRecovery']=='unknown'


@pytest.mark.parametrize('changed',[
    {'producerProcessExited':False}, {'requestedEnabled':True}, {'runId':'other'},
    {'controlRevision':3}, {'producer':{'status':'running'}},
])
def test_recovery_requires_same_disabled_run_and_confirmed_process_exit(tmp_path,changed):
    h=Harness(tmp_path);h.status_after_reconnect=changed
    with pytest.raises(ActiveFaultError,match='control_or_producer_not_stopped_after_recovery'):
        h.observer.check_active_faults(h.disconnect,h.reconnect,h.status)


def test_pid_change_blocks_suspend_instead_of_touching_another_process(tmp_path):
    h=Harness(tmp_path);h.pid=8
    with pytest.raises(ActiveFaultError,match='own_pid_changed_before_suspend'):
        h.observer.check_active_faults(h.disconnect,h.reconnect,h.status)
    assert not any(c['operation']=='suspend' for c in h.commands)


def test_changed_pid_after_activate_is_not_reported_as_process_resume(tmp_path):
    h=Harness(tmp_path);h.changed_on_activate=True;h.activation_response_pid=7
    with pytest.raises(ActiveFaultError,match='own_pid_changed_after_activate'):
        h.observer.check_active_faults(h.disconnect,h.reconnect,h.status)
    assert not h.observer.suspended


def test_activation_response_cannot_silently_report_another_pid(tmp_path):
    h=Harness(tmp_path);h.activation_response_pid=8
    with pytest.raises(ActiveFaultError,match='own_pid_changed_activation_response'):
        h.observer.check_active_faults(h.disconnect,h.reconnect,h.status)
    assert not h.observer.suspended


def test_second_instance_is_not_hidden_by_an_old_pid_filter(tmp_path):
    h=Harness(tmp_path);h.extra_instance=True
    with pytest.raises(ActiveFaultError,match='own_pid_not_confirmed_before_suspend'):
        h.observer.check_active_faults(h.disconnect,h.reconnect,h.status)
    assert not any(c['operation']=='suspend' for c in h.commands)
    assert '--search' in h.commands[0]['args'] and '--filter' not in h.commands[0]['args']


def test_background_notification_without_empty_map_does_not_pass():
    assert not background_cleared([lifecycle(10,2),fleet()],7)
    assert not background_cleared([fleet(0)],7)
    assert not background_cleared([lifecycle(10,0),fleet(0)],7)
    assert background_cleared([lifecycle(10,2),fleet(0)],7)


def test_background_timeout_uses_global_deadline_and_never_suspends(tmp_path):
    h=Harness(tmp_path);h.background=False;h.now=1279
    with pytest.raises(ActiveFaultError,match='phase_condition_timeout'):
        h.observer.check_active_faults(h.disconnect,h.reconnect,h.status)
    assert h.now<=1280 and not h.commands


def test_phase_hold_cannot_overrun_global_cleanup_reserve(tmp_path):
    h=Harness(tmp_path);h.now=1270
    with pytest.raises(ActiveFaultError,match='insufficient_time_for_phase'):
        h.observer._hold(25)
    assert h.now==1270


def test_cpu_boundary_must_exist_before_faults(tmp_path):
    h=Harness(tmp_path);h.observer.cpu_end=None
    with pytest.raises(ActiveFaultError,match='baseline_cpu_not_frozen'):
        h.observer.check_active_faults(h.disconnect,h.reconnect,h.status)
    assert not h.commands and h.cut is None


def test_invalid_baseline_cpu_stops_before_any_fault(tmp_path):
    h=Harness(tmp_path)
    h.events=[e for e in h.events if e['event']!='processResources'];h.write()
    with pytest.raises(ActiveFaultError,match='baseline_cpu_not_valid'):
        h.observer.check_active_faults(h.disconnect,h.reconnect,h.status)
    assert not h.commands and h.cut is None


def test_fleet_before_fresh_foreground_control_is_rejected(tmp_path):
    h=Harness(tmp_path);h.bad_foreground=True
    with pytest.raises(ActiveFaultError,match='fleet_before_foreground_control'):
        h.observer.check_active_faults(h.disconnect,h.reconnect,h.status)
    assert not h.observer.suspended and h.cut is None


def test_foreground_recovery_requires_both_lifecycle_stages_and_active_state():
    control=event('control',enabled=1,revision=3)
    assert not foreground_recovered([lifecycle(11,1),control,fleet()],7,3)
    assert not foreground_recovered([lifecycle(11,1),lifecycle(9,1),control,fleet()],7,3)
    with pytest.raises(ActiveFaultError,match='fleet_before_foreground_control'):
        foreground_recovered([lifecycle(9,0),control,fleet()],7,3)
    assert foreground_recovered([lifecycle(11,1),lifecycle(9,0),control,fleet()],7,3)


def test_fleet_resurrection_after_network_cut_is_rejected(tmp_path):
    h=Harness(tmp_path);h.resurrect=True
    with pytest.raises(ActiveFaultError,match='fleet_resurrected_after_broker_cut'):
        h.observer.check_active_faults(h.disconnect,h.reconnect,h.status)
    assert not h.observer.suspended


def test_only_ordered_new_connection_subscription_and_off_confirms_recovery():
    off=event('control',enabled=0,revision=4)
    connection=event('connection',accepted=1)
    subscription=event('subscription',control=1)
    assert not network_recovered_disabled([off],4)
    assert not network_recovered_disabled([subscription,connection,off],4)
    assert not network_recovered_disabled([connection,subscription,event('control',enabled=0,revision=3)],4)
    assert network_recovered_disabled([connection,subscription,off],4)


def test_occupancy_and_live_fleet_are_both_required():
    assert full_map(fleet()) and empty_map(fleet(0))
    broken=fleet();broken['counts']['occupancyFull']=1
    assert not full_map(broken)
    broken=fleet(0);broken['counts']['occupancyFull']=1
    assert not empty_map(broken)


def test_no_forced_suspend_does_not_claim_an_os_suspension(tmp_path):
    h=Harness(tmp_path)
    h.observer._wait(lambda:background_cleared([lifecycle(10,2),fleet(0)],7),1)
    assert not h.observer.resume_confirmed and h.observer.active_faults is None


@pytest.mark.parametrize('kwargs', [
    {'observer':None}, {'name':'ensayo-6'}, {'seconds':870},
    {'control_only':True}, {'check_reconnect':True}, {'scenario_occupancy':False},
])
def test_fault_mode_is_exclusive_and_rejects_invalid_request_before_gtfs_or_processes(tmp_path,kwargs):
    request={'output':tmp_path/'trial','name':'pasajeros-30','seconds':35,
        'observer':object(),'check_active_faults':True,'scenario_occupancy':True,
        'gtfs_dir':tmp_path/'does-not-exist',**kwargs}
    with pytest.raises(ValueError,match='modo exclusivo'):
        run_trial(**request)
    assert not (tmp_path/'trial').exists()


@pytest.mark.parametrize('change', ['no_device','wrong_profile','wrong_seconds','control_only',
    'check_reconnect','no_occupancy','instruments','loopback'])
def test_cli_invalid_fault_combinations_fail_without_device_or_network(tmp_path,change):
    args=['--profile','pasajeros-30','--output',str(tmp_path/'trial'),'--seconds','35',
        '--listen-host','192.168.18.87','--device','captured-only',
        '--check-active-faults','--scenario-occupancy']
    if change=='no_device':
        at=args.index('--device');del args[at:at+2]
    elif change=='wrong_profile':args[args.index('--profile')+1]='ensayo-6'
    elif change=='wrong_seconds':args[args.index('--seconds')+1]='870'
    elif change=='control_only':args.append('--control-only')
    elif change=='check_reconnect':args.append('--check-reconnect')
    elif change=='no_occupancy':args.remove('--scenario-occupancy')
    elif change=='instruments':args.append('--instruments')
    elif change=='loopback':args[args.index('--listen-host')+1]='127.0.0.1'
    assert main([*args,'run'])==2
    assert not (tmp_path/'trial').exists()


@pytest.mark.parametrize('fault_failure',[False,True])
def test_trial_mode_separates_baseline_from_expected_auto_off_and_always_cleans(
        tmp_path,monkeypatch,fault_failure):
    import simulation.local_trial as trial
    clock=SimpleNamespace(now=1000.0)
    children=[];captures=[]
    control=SimpleNamespace(enabled=False,revision=1,producer='running',path=tmp_path/'trial/control/control.sqlite')
    def enable(*_):control.enabled=True;control.revision=3
    def disable(*_):
        control.enabled=False;control.revision+=1;clock.now+=.2
        return {'revision':control.revision}
    control.enable=enable;control.disable=disable
    control.read=lambda:{'enabled':control.enabled,'revision':control.revision}
    def status(*_):
        return {'requestedEnabled':control.enabled,'controlRevision':control.revision,
            'runId':'run','runOwner':'owner' if control.enabled else None,
            'reason':'running' if control.enabled else 'producer:backend_or_puback_expired',
            'backend':{'fresh':True,'appliedRevision':control.revision},
            'mqtt':{'lastAckedRevision':control.revision},
            'counts':{'mqttConnections':30 if control.enabled else 0},
            'producer':{'status':control.producer}}
    class Child:
        def __init__(self,args,**_):
            self.args=args;self.pid=200+len(children);self.done=False;children.append(self)
        def poll(self):return 0 if self.done else None
        def terminate(self):self.done=True
        def kill(self):self.done=True
        def wait(self,timeout):self.done=True;return 0
    class Socket:
        def __enter__(self):return self
        def __exit__(self,*_):pass
        def bind(self,*_):pass
        def getsockname(self):return ('127.0.0.1',1884)
    class Probe:
        def __init__(self,*_):pass
        def close(self):pass
        def snapshot(self):return {'connected':True,'receivedPositions':10,'invalidPositions':0,
            'control':{'enabled':control.enabled,'controlRevision':control.revision},
            'controlSeenAtUptime':clock.now}
    class Observer:
        suspended=False;active_faults=None
        def __init__(self):self.prepared=0;self.cpu_end=None;self.closed=False
        def started(self,*_):pass
        def begin_active_run(self,started):self.deadline=started+300
        def capture_started(self):pass
        def remaining(self):return self.deadline-20-clock.now
        def prepare_disable(self):self.prepared+=1;self.cpu_end=135
        def check_active_faults(self,disconnect,reconnect,get_status):
            assert self.prepared==1 and self.cpu_end==135
            assert len(captures)==1 and captures[0]['seconds']==35
            assert get_status()['requestedEnabled']
            disconnect();reconnect();clock.now+=60
            control.enabled=False;control.revision=4;control.producer='stopped'
            next(c for c in children if c.args[-1]=='run').done=True
            self.active_faults={'complete':not fault_failure,'cpuIntervalEndedBeforeFault':True}
            if fault_failure:raise ActiveFaultError('captured_fault_failure')
            return self.active_faults
        def finished(self,requested,*,require_positions):
            assert require_positions is False and self.prepared==1 and self.cpu_end==135
            return {'cpu':{'complete':True},'cleanupUpperBoundSeconds':None}
        def resume_for_cleanup(self):self.suspended=False
        def close(self):self.closed=True
    def capture(targets,path,seconds):
        captures.append({'targets':targets,'seconds':seconds})
        clock.now+=seconds
        return {'complete':True,'targets':{}}
    fake_profile=SimpleNamespace(max_run_seconds=900,principals={f'sim-{i:03}' for i in range(1,31)},
        window=lambda _:(True,'2026-10-27',2000),pinned=lambda:{'name':'pasajeros-30'})
    monkeypatch.setattr(trial,'SimulationProfile',SimpleNamespace(load=lambda *_:fake_profile))
    monkeypatch.setattr(trial,'ControlStore',SimpleNamespace(initialize=lambda *_:control))
    monkeypatch.setattr(trial,'time',SimpleNamespace(time=lambda:clock.now,monotonic=lambda:clock.now,sleep=lambda _:None))
    monkeypatch.setattr(trial,'socket',SimpleNamespace(socket=Socket,create_connection=lambda *_args,**_kw:Socket()))
    monkeypatch.setattr(trial,'subprocess',SimpleNamespace(Popen=Child,
        run=lambda *_args,**_kw:SimpleNamespace(returncode=0),STDOUT=subprocess.STDOUT,
        SubprocessError=subprocess.SubprocessError,TimeoutExpired=subprocess.TimeoutExpired))
    monkeypatch.setattr(trial.shutil,'which',lambda name:'/fake/'+name)
    monkeypatch.setattr(trial,'Probe',Probe)
    monkeypatch.setattr(trial,'verify_local_acl',lambda *_:[{'denied':True}])
    monkeypatch.setattr(trial,'read_heartbeat',lambda *_:{'connected':True})
    monkeypatch.setattr(trial,'status',status)
    monkeypatch.setattr(trial,'capture',capture)
    monkeypatch.setattr(trial,'run_report',lambda *_:{'historyComplete':True,'stored':{'observations':{'rows':10}}})
    monkeypatch.setattr(trial,'export_comparison',lambda *_args,**_kw:None)
    observer=Observer()
    result=trial.run_trial(tmp_path/'trial','pasajeros-30',35,observer=observer,
        check_active_faults=True,scenario_occupancy=True)
    assert result['complete'] is (not fault_failure)
    assert result['ownedProcessesStopped'] and result['suspendedProcessResumedOrNeverSuspended']
    assert observer.closed and observer.prepared==1
    assert result['mode']=='active_fleet_faults' and not result['captureEndedEarly']
    assert result['iosCleanupSeconds'] is None and not result['iosCleanupTimingUsable']
    assert len(captures)==1 and captures[0]['targets']['broker']==children[0].pid
    assert len(children)==4 and all(child.poll() is not None for child in children)
    assert not (tmp_path/'trial/passwords').exists()
    assert not (tmp_path/'trial/actors-credentials.json').exists()
    assert not result['globalDeadlineExceeded']
    if fault_failure:
        assert result['failureReason']=='captured_fault_failure'
    else:
        assert result['functionalComplete'] and not result['controlWasEnabledBeforeDisable']
