"""CPU iOS: muestras inyectadas y consola temporal, sin app ni Instruments."""
import json
from types import SimpleNamespace
import pytest
from simulation.device_resources import summarize_device_cpu
from simulation.device_trial import DeviceObserver
from simulation.local_trial import run_trial


def row(t=0, *, cpu=None, system=0, **changes):
    counts={'schemaVersion':1,'processID':42,'userMicroseconds':int((t/4 if cpu is None else cpu)*1e6),
        'systemMicroseconds':system,'logicalCPUs':6,'active':1,**changes}
    return {'event':'processResources','uptime':100+t,'wall':1000+t,'counts':counts}


def summary(rows, **changes):
    return summarize_device_cpu(rows,42,after=100,before=140,**changes)


def test_weights_totals_not_interval_percentages_and_reports_units():
    rows=[row(i,cpu=.5 if i else 0) for i in range(31)]
    value=summary(rows)
    assert value['cpuPctOneCore']==pytest.approx(.5/30*100)
    assert value['intervalCpuPeakPctOneCore']==50
    assert value['samples']==31 and value['elapsedSeconds']==30
    assert value['method']=='getrusage_RUSAGE_SELF_counter_deltas'


def test_real_zero_is_valid_only_with_sufficient_continuous_samples():
    assert summary([row(i,cpu=0) for i in range(31)])['cpuPctOneCore']==0
    for rows in ([],[row()], [row(),row(1)]):
        with pytest.raises(ValueError): summary(rows)


@pytest.mark.parametrize('changes',[
    {'processID':43},{'processID':True},{'schemaVersion':2},{'active':0},
    {'userMicroseconds':-1},{'systemMicroseconds':-1},{'logicalCPUs':0},
    {'logicalCPUs':257},{'extra':0},{'userMicroseconds':1.5}])
def test_invalid_or_other_process_sample_fails(changes):
    rows=[row(i) for i in range(31)];rows[15]=row(15,**changes)
    with pytest.raises(ValueError):summary(rows)


@pytest.mark.parametrize('mutation', ['counter','wall','uptime','gap','cpuCapacity','cores','failure'])
def test_regressions_gaps_background_and_failures_never_become_low_cpu(mutation):
    rows=[row(i) for i in range(31)]
    if mutation=='counter': rows[15]['counts']['userMicroseconds']=0
    elif mutation=='wall': rows[15]['wall']+=20
    elif mutation=='uptime':rows[15]['uptime']=rows[14]['uptime']
    elif mutation=='gap':rows=rows[:10]+rows[20:]
    elif mutation=='cpuCapacity': rows[15]['counts']['userMicroseconds']+=100_000_000
    elif mutation=='cores':rows[15]['counts']['logicalCPUs']=3
    elif mutation=='failure':rows[15]['event']='processResourceFailure'
    with pytest.raises(ValueError):summary(rows)


def test_bounds_use_only_device_uptime_and_exclude_bootstrap():
    rows=[row(i) for i in range(41)]
    rows[0]=row(0,processID=99)
    result=summarize_device_cpu(rows,42,after=110,before=140)
    assert result['startDeviceUptime']==110 and result['elapsedSeconds']==30
    assert result['cpuPctOneCore']==25


@pytest.mark.parametrize('pid,after,before,minimum',[(True,100,140,29),(0,100,140,29),
    (42,float('nan'),140,29),(42,100,100,29),(42,100,140,0)])
def test_invalid_capture_arguments(pid,after,before,minimum):
    with pytest.raises(ValueError):
        summarize_device_cpu([row(i) for i in range(31)],pid,after=after,before=before,minimum_seconds=minimum)


def console(path, events):
    path.write_text(''.join('[S10] '+json.dumps(e)+'\n' for e in events))


def test_observer_default_does_not_start_competing_instruments(monkeypatch,tmp_path):
    observer=DeviceObserver('phone','bundle');observer.output=tmp_path
    console(tmp_path/'device-console.log',[{'event':'map','counts':{'received':10},'uptime':100}])
    monkeypatch.setattr(observer,'_wait',lambda *_:None)
    monkeypatch.setattr('simulation.device_trial.remote_process_id',lambda *_:42)
    def forbidden(*_):raise AssertionError('no Instruments automático')
    monkeypatch.setattr(observer,'_spawn',forbidden)
    observer.capture_started()
    assert observer.pid==42 and observer.cpu_start==100 and observer.profiler is None


def test_optional_profiler_uses_single_all_process_session(monkeypatch,tmp_path):
    observer=DeviceObserver('phone','bundle',instruments=True);observer.output=tmp_path
    console(tmp_path/'device-console.log',[{'event':'map','counts':{'received':10},'uptime':100}])
    monkeypatch.setattr(observer,'_wait',lambda *_:None)
    monkeypatch.setattr('simulation.device_trial.remote_process_id',lambda *_:42)
    calls=[]
    monkeypatch.setattr(observer,'_spawn',lambda args,name:calls.append(args) or object())
    observer.capture_started()
    assert len(calls)==1 and '--all-processes' in calls[0] and '--attach' not in calls[0]


@pytest.mark.parametrize('has_samples',[False,True])
def test_control_only_diagnostic_does_not_call_retirement_a_cleanup_measurement(tmp_path,has_samples):
    observer=DeviceObserver('phone','bundle');observer.output=tmp_path;observer.pid=42
    observer.cpu_start=100;observer.cpu_end=130
    events=[{'event':'map','counts':{'received':0,'fleet':0}},
            {'event':'control','counts':{'enabled':0}}]
    if has_samples:events += [row(i) for i in range(31)]
    console(tmp_path/'device-console.log',events)
    result=observer.finished(0,require_positions=False)
    assert result['cpu']['complete'] is has_samples
    assert result['cleanupUpperBoundSeconds'] is None and not result['retiredConfirmed']
    assert result['traceSavedIsNotCPUValidation'] and not result['traceCaptured']


def test_diagnostic_requires_device_and_never_creates_output_without_it(tmp_path):
    path=tmp_path/'new'
    with pytest.raises(ValueError,match='requiere observador'):
        run_trial(path,'pasajeros-30',35,control_only=True)
    assert not path.exists()


def test_reconnection_check_requires_new_subscription_and_disabled_control(tmp_path,monkeypatch):
    observer=DeviceObserver('phone','bundle');observer.output=tmp_path
    path=tmp_path/'device-console.log';console(path,[])
    def disconnect():console(path,[{'event':'disconnection','counts':{'accepted':0}}])
    def reconnect():console(path,[{'event':'disconnection','counts':{'accepted':0}},
        {'event':'connection','counts':{'accepted':1}},
        {'event':'subscription','counts':{'control':1}},
        {'event':'control','counts':{'enabled':0}}])
    def immediate(predicate,*_):assert predicate()
    monkeypatch.setattr(observer,'_wait',immediate)
    result=observer.check_reconnection(disconnect,reconnect)
    assert result['complete'] and result['cpuIntervalEndedBeforeFault']


def test_reconnection_fault_is_not_available_on_active_trial(tmp_path):
    with pytest.raises(ValueError,match='requiere control-only'):
        run_trial(tmp_path/'new','pasajeros-30',35,check_reconnect=True)
    assert not (tmp_path/'new').exists()
