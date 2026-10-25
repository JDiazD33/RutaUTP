"""Supervisor local S09: check/watch solo leen; guard puede revocar con CAS.

No arranca procesos, no habilita, no abre MQTT y nunca mata un PID. No se instala
como tarea programada. El operador elige explícitamente cuándo ejecutarlo.
"""

from __future__ import annotations

import argparse
import json
import time

from .health import fresh_timestamp, read_heartbeat
from .simulation_admin import status_with_health
from .simulation_control_store import ControlStore, ControlUnavailable


def inspect(control: ControlStore, heartbeat: dict | None, now: float) -> dict:
    result = status_with_health(control, now, heartbeat)
    issues = []
    enabled = result['requestedEnabled']
    if enabled:
        if not result['simulationHealth']['healthy']:
            issues.append(result['simulationHealth']['reason'])
        if not result['backend']['fresh']:
            issues.append('backend_status_stale')
        if result['runOwner'] is not None:
            if not result['backend']['matchesRunOwner'] or not result['heartbeatMatchesControl']:
                issues.append('backend_generation_unconfirmed')
            if result['backend']['appliedRevision'] != result['controlRevision']:
                issues.append('control_revision_not_applied')
            mqtt = result['mqtt']
            if mqtt['lastAckedRevision'] != result['controlRevision'] or not fresh_timestamp(mqtt['lastAckedAt'], now):
                issues.append('control_puback_missing_or_stale')
            started = result['budget']['runStartedAt']
            if now-started >= 15 and result['producer'].get('status') != 'running':
                issues.append('producer_missing_stopped_or_stale')
            if now < started:
                issues.append('clock_before_run_start')
            duration = result['budget']['maxRunSeconds']
            if duration is not None and now >= started+duration:
                issues.append('max_run_duration')
            if now >= result['budget']['serviceEndsAt']:
                issues.append('service_closed')
        budget = result['budget']
        if not budget['available']:
            issues.append('publish_budget_unavailable')
        else:
            for suffix in ('Run', 'Day'):
                if suffix == 'Run' and result['runOwner'] is None:
                    continue
                count, maximum = budget['reservedPublishCalls'+suffix], budget['maxPublishCalls'+suffix]
                if maximum is not None and count >= maximum:
                    issues.append('publish_budget_exhausted_'+suffix.lower())
    elif result['producer'].get('status') == 'revocation_pending':
        issues.append('producer_revocation_pending')
    result['supervision'] = {'healthy': not issues, 'issues': issues,
        'producerStoppedConfirmed': result['producer'].get('status') == 'stopped',
        'appCleanupConfirmed': False, 'action': 'none', 'checkedAt': now}
    return result


def supervise(control: ControlStore, heartbeat: dict | None, now: float, *, revoke: bool = False) -> dict:
    result = inspect(control, heartbeat, now)
    supervision = result['supervision']
    if revoke and result['requestedEnabled'] and supervision['issues']:
        changed = control.disable(now, 'supervisor:'+supervision['issues'][0],
                                  expected_revision=result['controlRevision'])
        supervision['action'] = 'disable_saved' if changed is not None else 'generation_changed_no_action'
        supervision['savedRevision'] = changed['revision'] if changed else None
        # Un commit no confirma ni la publicación retained ni la limpieza iOS.
        supervision['backendAppliedDisable'] = False
    return result


def main(argv=None) -> int:
    parser = argparse.ArgumentParser(description='Supervisión privada de simulación, sin arranque automático')
    parser.add_argument('--control-db', required=True)
    parser.add_argument('--health-file', required=True)
    parser.add_argument('--interval', type=float, default=5)
    parser.add_argument('command', choices=['check', 'watch', 'guard'],
        help='check/watch solo leen; guard revoca ante fallos, nunca vuelve a habilitar')
    args = parser.parse_args(argv)
    if not 1 <= args.interval <= 5:
        parser.error('intervalo entre 1 y 5 segundos')
    control = ControlStore(args.control_db)
    try:
        while True:
            result = supervise(control, read_heartbeat(args.health_file), time.time(), revoke=args.command == 'guard')
            print(json.dumps(result, ensure_ascii=False, allow_nan=False), flush=True)
            if args.command != 'watch':
                return 0 if result['supervision']['healthy'] else 2
            time.sleep(args.interval)
    except KeyboardInterrupt:
        return 0
    except (ControlUnavailable, OSError, ValueError, TypeError, KeyError):
        print(json.dumps({'supervision': {'healthy': False, 'action': 'none',
            'issues': ['control_unavailable_leases_must_expire'], 'appCleanupConfirmed': False}}))
        return 2


if __name__ == '__main__':
    raise SystemExit(main())
