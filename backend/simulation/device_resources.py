"""CPU de RutaUTP desde contadores propios getrusage, sin abrir un dispositivo.

No reutiliza porcentajes de otro ensayo ni considera una traza vacía como cero.
Los límites del intervalo y los relojes son los del iPhone, nunca los del host.
"""
from __future__ import annotations

import math


def _time(value):
    if type(value) not in (int, float) or not math.isfinite(value) or value < 0:
        raise ValueError('reloj de recursos inválido')
    return value


def summarize_device_cpu(events: list[dict], expected_pid: int, *, after: float, before: float,
                         minimum_seconds: float = 29) -> dict:
    if type(expected_pid) is not int or expected_pid <= 0:
        raise ValueError('PID esperado inválido')
    for stamp in (after, before, minimum_seconds): _time(stamp)
    if before <= after or minimum_seconds < 1:
        raise ValueError('intervalo de recursos inválido')
    samples = []
    for event in events:
        if event.get('event') not in ('processResources', 'processResourceFailure'):
            continue
        uptime = _time(event.get('uptime'))
        if not after <= uptime <= before:
            continue
        if event['event'] == 'processResourceFailure':
            raise ValueError('getrusage falló dentro de la captura')
        wall = _time(event.get('wall'))
        counts = event.get('counts')
        fields = {'schemaVersion', 'processID', 'userMicroseconds', 'systemMicroseconds', 'logicalCPUs', 'active'}
        if not isinstance(counts, dict) or set(counts) != fields or any(type(v) is not int for v in counts.values()):
            raise ValueError('contrato de recursos inválido')
        if (counts['schemaVersion'] != 1 or counts['processID'] != expected_pid
                or min(counts['userMicroseconds'], counts['systemMicroseconds']) < 0
                or not 1 <= counts['logicalCPUs'] <= 256 or counts['active'] != 1):
            raise ValueError('proceso o estado de ejecución incompatible')
        samples.append({'uptime': uptime, 'wall': wall, **counts})
    if len(samples) < 2:
        raise ValueError('no hay muestras suficientes de CPU')
    elapsed = samples[-1]['uptime'] - samples[0]['uptime']
    if elapsed < minimum_seconds:
        raise ValueError('duración de CPU insuficiente')
    ratios = []
    for first, second in zip(samples, samples[1:]):
        delta = second['uptime'] - first['uptime']
        user = second['userMicroseconds'] - first['userMicroseconds']
        system = second['systemMicroseconds'] - first['systemMicroseconds']
        if (not 0 < delta <= 5 or user < 0 or system < 0
                or second['logicalCPUs'] != first['logicalCPUs']
                or abs((second['wall']-first['wall']) - delta) > 2):
            raise ValueError('reloj, contador o continuidad de CPU inválidos')
        ratio = (user + system) / 1_000_000 / delta * 100
        if ratio > first['logicalCPUs'] * 100 + 5:
            raise ValueError('CPU supera la capacidad declarada del proceso')
        ratios.append(ratio)
    first, last = samples[0], samples[-1]
    user = (last['userMicroseconds']-first['userMicroseconds'])/1_000_000
    system = (last['systemMicroseconds']-first['systemMicroseconds'])/1_000_000
    ordered = sorted(ratios)
    return {'complete': True, 'method': 'getrusage_RUSAGE_SELF_counter_deltas',
        'processPID': expected_pid, 'samples': len(samples), 'elapsedSeconds': elapsed,
        'userCPUSeconds': user, 'systemCPUSeconds': system, 'cpuSeconds': user+system,
        'cpuPctOneCore': (user+system)/elapsed*100,
        'intervalCpuPeakPctOneCore': max(ratios),
        'intervalCpuP95PctOneCore': ordered[math.ceil(.95*len(ordered))-1],
        'startDeviceUptime': first['uptime'], 'endDeviceUptime': last['uptime'],
        'allSamplesAppActive': True, 'energyMeasured': False, 'footprintMeasured': False,
        'meaning': 'all process threads; user+system CPU / device monotonic elapsed; '
                   'one core; diagnostic overhead included; not a stack profile'}
