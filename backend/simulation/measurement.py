"""Captura explícita de procesos Mac/Linux. No inicia app, broker ni actores.

CPU de intervalos a partir del contador acumulado de ps, normalizada a un núcleo;
RSS no es memoria física exclusiva ni una medida de energía. Sin argumentos/secretos.
"""

from __future__ import annotations

import argparse
from dataclasses import asdict, dataclass
import json
import math
import os
from pathlib import Path
import platform
import subprocess
import time


def cpu_seconds(text: str) -> float:
    """[d-]hh:mm:ss o mm:ss.fracción, según ps del host."""
    days = 0
    if '-' in text:
        raw_days, text = text.split('-', 1)
        if not raw_days.isdigit(): raise ValueError('tiempo CPU inválido')
        days = int(raw_days)
    parts = text.split(':')
    if len(parts) not in (2, 3) or any(not p.isdigit() for p in parts[:-1]):
        raise ValueError('tiempo CPU inválido')
    seconds = float(parts[-1])
    if not math.isfinite(seconds) or not 0 <= seconds < 60:
        raise ValueError('segundos CPU inválidos')
    minutes = int(parts[-2])
    if len(parts) == 3 and minutes >= 60:
        raise ValueError('minutos CPU inválidos')
    hours = int(parts[0]) if len(parts) == 3 else 0
    return days*86400+hours*3600+minutes*60+seconds


@dataclass(frozen=True)
class ProcessSample:
    pid: int
    started: str
    cpuSeconds: float
    rssBytes: int
    at: float
    uptime: float


def parse_ps(raw: str, pid: int, at: float, uptime: float) -> ProcessSample:
    lines = [line for line in raw.splitlines() if line.strip()]
    if len(lines) != 1:
        raise ValueError('proceso ausente o resultado ambiguo')
    fields = lines[0].split(None, 3)
    if len(fields) != 4 or not fields[0].isdigit() or int(fields[0]) != pid or not fields[2].isdigit():
        raise ValueError('resultado ps inválido')
    for value in (at, uptime):
        if type(value) not in (int, float) or not math.isfinite(value) or value < 0:
            raise ValueError('reloj de captura inválido')
    return ProcessSample(pid, fields[3], cpu_seconds(fields[1]), int(fields[2])*1024, at, uptime)


def read_process(pid: int) -> ProcessSample:
    if type(pid) is not int or pid <= 0:
        raise ValueError('PID positivo requerido')
    # No leer command/args: las contraseñas de otro proceso no entran en el log.
    result = subprocess.run(['/bin/ps', '-p', str(pid), '-o', 'pid=,time=,rss=,lstart='],
        capture_output=True, text=True, timeout=5, env={**os.environ, 'LC_ALL': 'C'})
    if result.returncode:
        raise ValueError('proceso no disponible')
    return parse_ps(result.stdout, pid, time.time(), time.monotonic())


def summarize(samples: list[ProcessSample]) -> dict:
    if not samples:
        return {'samples': 0, 'cpuPctOneCore': None, 'rssPeakBytes': None}
    first = samples[0]; ratios = []; total_cpu = total_time = 0.0
    for previous, current in zip(samples, samples[1:]):
        if (current.pid, current.started) != (first.pid, first.started):
            raise ValueError('identidad del proceso cambió')
        elapsed = current.uptime-previous.uptime
        cpu = current.cpuSeconds-previous.cpuSeconds
        if elapsed <= 0 or cpu < 0:
            raise ValueError('reloj o contador CPU retrocedió')
        total_time += elapsed; total_cpu += cpu; ratios.append(cpu/elapsed*100)
    ordered = sorted(ratios)
    return {'samples': len(samples), 'elapsedSeconds': total_time, 'cpuSeconds': total_cpu,
        'cpuPctOneCore': total_cpu/total_time*100 if total_time else None,
        'intervalCpuPeakPctOneCore': max(ratios) if ratios else None,
        'intervalCpuP95PctOneCore': ordered[math.ceil(len(ordered)*.95)-1] if ordered else None,
        'rssPeakBytes': max(s.rssBytes for s in samples),
        'meaning': 'ps_counter_deltas_one_core; rss_snapshot; interval_peak_not_instantaneous'}


def capture(targets: dict[str, int], output: Path, duration: float, interval: float = 1,
            *, reader=read_process, monotonic=time.monotonic, wait=time.sleep) -> dict:
    if (not targets or len(targets) > 4 or len(set(targets.values())) != len(targets)
            or any(type(p) is not int or p <= 0 for p in targets.values())
            or any(not label.isidentifier() for label in targets)):
        raise ValueError('entre uno y cuatro procesos distintos con etiquetas simples')
    for value, low, high in ((duration, 1, 900), (interval, .5, 5)):
        if type(value) not in (int, float) or not math.isfinite(value) or not low <= value <= high:
            raise ValueError('duración/intervalo fuera de rango')
    samples = {label: [] for label in targets}
    descriptor = os.open(output, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
    report = {'complete': False, 'failure': None, 'targets': {}, 'timeZone': 'America/Lima',
        'system': platform.system(), 'logicalCPUs': os.cpu_count(), 'cpuNormalization': 'one_core',
        'iPhoneMeasured': False, 'networkMeasured': False, 'energyMeasured': False}
    with os.fdopen(descriptor, 'w', encoding='utf-8') as stream:
        stream.write(json.dumps({'kind': 'capture', 'durationSeconds': duration,
            'intervalSeconds': interval, 'pids': targets, **report})+'\n')
        deadline = monotonic()+duration
        try:
            while True:
                for label, pid in targets.items():
                    sample = reader(pid)
                    if samples[label]:
                        # Fallar antes de escribir un nuevo PID/reinicio bajo la misma etiqueta.
                        summarize([samples[label][-1], sample])
                    samples[label].append(sample)
                    stream.write(json.dumps({'kind': 'sample', 'label': label, **asdict(sample)}, allow_nan=False)+'\n')
                stream.flush()
                remaining = deadline-monotonic()
                if remaining <= 0:
                    break
                wait(min(interval, remaining))
            report['complete'] = all(len(s) >= 2 for s in samples.values())
        except (OSError, ValueError, subprocess.SubprocessError) as error:
            report['failure'] = type(error).__name__
        report['targets'] = {label: summarize(rows) for label, rows in samples.items()}
        stream.write(json.dumps({'kind': 'summary', **report}, allow_nan=False)+'\n')
        stream.flush()
    return report


def main(argv=None) -> int:
    parser = argparse.ArgumentParser(description='Captura explícita CPU/RSS de procesos ya identificados')
    parser.add_argument('--pid', action='append', required=True, help='etiqueta=PID; nunca busca procesos por nombre')
    parser.add_argument('--output', required=True, type=Path, help='JSONL nuevo, no sobrescribe')
    parser.add_argument('--seconds', required=True, type=float)
    parser.add_argument('--interval', type=float, default=1)
    args = parser.parse_args(argv)
    try:
        targets = {}
        for item in args.pid:
            label, pid = item.split('=', 1)
            if label in targets: raise ValueError('etiqueta repetida')
            targets[label] = int(pid)
        result = capture(targets, args.output, args.seconds, args.interval)
        print(json.dumps(result, allow_nan=False))
        return 0 if result['complete'] else 2
    except (OSError, ValueError):
        print(json.dumps({'complete': False, 'failure': 'invalid_or_unavailable_capture'}))
        return 2


if __name__ == '__main__':
    raise SystemExit(main())
