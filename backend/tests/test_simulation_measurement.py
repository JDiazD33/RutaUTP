"""S10: contadores y reloj inyectados; ninguna captura de procesos reales."""
from dataclasses import replace
import json
import pytest

from simulation.measurement import ProcessSample, cpu_seconds, parse_ps, summarize, capture


@pytest.mark.parametrize('raw,expected', [('00:01.25', 1.25), ('61:02', 3662),
    ('01:02:03', 3723), ('2-03:04:05.5', 183845.5)])
def test_cpu_time_formats(raw, expected):
    assert cpu_seconds(raw) == expected


@pytest.mark.parametrize('raw', ['', '1', '-1:00', '1:nan', '1:inf', '1:60', '1:60:00', 'x-01:00'])
def test_invalid_cpu_time(raw):
    with pytest.raises(ValueError): cpu_seconds(raw)


def sample(cpu=0, uptime=0, rss=1024, **changes):
    return replace(ProcessSample(42, 'Thu Oct 22 10:00:00 2026', cpu, rss, 1000+uptime, uptime), **changes)


def test_ps_converts_kib_without_reading_command_arguments():
    result = parse_ps(' 42 00:01.25 2048 Thu Oct 22 10:00:00 2026\n', 42, 1000, 10)
    assert result.cpuSeconds == 1.25 and result.rssBytes == 2097152
    assert result.started == 'Thu Oct 22 10:00:00 2026'


@pytest.mark.parametrize('raw,pid', [('',42), ('42 00:01 2 date\n42 00:02 2 date',42),
    ('41 00:01 2 date',42), ('42 00:01 -2 date',42)])
def test_ambiguous_or_absent_ps(raw,pid):
    with pytest.raises(ValueError): parse_ps(raw,pid,1000,10)


def test_summary_weights_cpu_by_elapsed_time_instead_of_averaging_percentages():
    result = summarize([sample(), sample(1,1,2048), sample(2,10,4096)])
    assert result['cpuPctOneCore'] == pytest.approx(20)
    assert result['intervalCpuPeakPctOneCore'] == 100
    assert result['intervalCpuP95PctOneCore'] == 100
    assert result['rssPeakBytes'] == 4096


@pytest.mark.parametrize('next_sample', [sample(1,1,pid=43), sample(1,1,started='new'),
    sample(1,0), sample(-1,1)])
def test_pid_reuse_and_counter_rollback_fail(next_sample):
    with pytest.raises(ValueError): summarize([sample(),next_sample])


class Clock:
    now = 0
    def wait(self, seconds): self.now += seconds
    def read(self, pid): return sample(self.now/2,self.now,pid=pid)


def test_capture_writes_raw_samples_and_summary_without_overwrite(tmp_path):
    clock=Clock(); path=tmp_path/'resources.jsonl'
    result=capture({'backend':42},path,2,reader=clock.read,monotonic=lambda:clock.now,wait=clock.wait)
    assert result['complete'] and result['targets']['backend']['cpuPctOneCore'] == 50
    assert path.stat().st_mode & 0o777 == 0o600
    rows=[json.loads(line) for line in path.read_text().splitlines()]
    assert rows[0]['kind']=='capture' and rows[-1]['kind']=='summary'
    assert len([r for r in rows if r['kind']=='sample'])==3
    original=path.read_bytes()
    with pytest.raises(FileExistsError):
        capture({'backend':42},path,2,reader=clock.read,monotonic=lambda:clock.now,wait=clock.wait)
    assert path.read_bytes()==original


def test_capture_failure_retains_previous_samples_and_marks_incomplete(tmp_path):
    clock=Clock()
    def reader(pid):
        if clock.now: raise ValueError('process ended')
        return clock.read(pid)
    result=capture({'backend':42},tmp_path/'resources.jsonl',2,reader=reader,
        monotonic=lambda:clock.now,wait=clock.wait)
    assert not result['complete'] and result['failure']=='ValueError'
    assert result['targets']['backend']['samples']==1


@pytest.mark.parametrize('targets,duration,interval', [({},1,1), ({'a':True},1,1),
    ({'a':42,'b':42},1,1), ({'bad label':42},1,1), ({'a':42},float('nan'),1),
    ({'a':42},901,1), ({'a':42},1,.1)])
def test_invalid_capture_does_not_create_file(tmp_path,targets,duration,interval):
    path=tmp_path/'resources.jsonl'
    with pytest.raises(ValueError): capture(targets,path,duration,interval)
    assert not path.exists()
