"""CLI local del operador. Sin HTTP/MQTT; histórico explícito para reportes/purga.

Usar una ruta explícita privada o BACKEND_SIMULATION_CONTROL_PATH. init crea
solo estado deshabilitado; enable arma el perfil, no arranca actores.
"""

from __future__ import annotations

import argparse
from datetime import datetime
import json
import os
from pathlib import Path
import sqlite3
import sys
import time

from .config import DEFAULT_GTFS_DIR
from .simulation_control_store import ControlStore, ControlUnavailable
from .simulation_profile import SimulationProfile, PROFILE_SPECS, lima_zone
from .health import fresh_timestamp, read_heartbeat, simulation_health


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description="Control privado de simulación RutaUTP")
    parser.add_argument("--control-db", default=os.environ.get("BACKEND_SIMULATION_CONTROL_PATH", ""))
    parser.add_argument("--gtfs-dir", type=Path, default=Path(os.environ.get("GTFS_DIR") or DEFAULT_GTFS_DIR))
    parser.add_argument('--history-db', type=Path, help='histórico explícito; status/report nunca lo migran')
    parser.add_argument('--health-file', help='latido explícito del mismo backend; no hay ruta implícita')
    commands = parser.add_subparsers(dest="command", required=True)
    commands.add_parser("init", help="crear estado privado deshabilitado; nunca sobrescribe")
    commands.add_parser("status", help="leer orden, revisión aplicada y estado de entrega")
    enable = commands.add_parser("enable", help="armar el perfil dentro de su horario")
    enable.add_argument("--profile", required=True, choices=tuple(PROFILE_SPECS))
    for command in ("disable", "recover-disabled"):
        disable = commands.add_parser(command, help="revocar; recuperación siempre deshabilitada")
        disable.add_argument("--reason", required=True)
    report = commands.add_parser('report', help='resumen JSON o comparación referencia/estimación de solo lectura')
    report.add_argument('--run-id', required=True)
    report.add_argument('--format', choices=['json', 'comparison-jsonl', 'comparison-csv'], default='json')
    for command in ('retention-plan', 'purge-detail'):
        retention = commands.add_parser(command, help='retención seleccionada; nunca purga resúmenes/control')
        retention.add_argument('--run-id', required=True)
        retention.add_argument('--detail-days', type=float, required=True)
        retention.add_argument('--summary-days', type=float, required=True)
        if command == 'purge-detail':
            retention.add_argument('--apply', action='store_true', required=True)
    return parser


def status(store: ControlStore, now: float) -> dict:
    state, runtime = store.snapshot()
    seen = runtime.get("backendSeenAt")
    fresh = fresh_timestamp(seen, now)
    producer = runtime.get("producer", {})
    producer = dict(producer) if isinstance(producer, dict) else {}
    producer_seen = producer.get("seenAt")
    producer_fresh = fresh_timestamp(producer_seen, now)
    same_run = producer.get("runId") == state["runId"]
    producer.update(fresh=producer_fresh, matchesCurrentRun=same_run)
    if not producer_fresh or not same_run:
        producer["status"] = "unknown"
    elif producer.get("status") == "running" and (not state["enabled"]
            or producer.get("controlRevision") != state["revision"]):
        producer["status"] = "revocation_pending"
    manifest = json.loads(state['profile']['raw']) if state['profile'] else {}
    if not isinstance(manifest, dict) or not isinstance(manifest.get('limits', {}), dict):
        raise ControlUnavailable('perfil fijado inválido para métricas')
    limits = manifest.get('limits', {})
    budget = runtime.get('publishBudget', {'runs': {}, 'days': {}})
    day = datetime.fromtimestamp(now, lima_zone()).date().isoformat()
    valid_budget = isinstance(budget, dict) and set(budget) == {'runs', 'days'} and all(
        isinstance(budget[key], dict) and all(type(n) is int and n >= 0 for n in budget[key].values())
        for key in ('runs', 'days'))
    run_calls = budget['runs'].get(state['runId'], 0) if valid_budget else None
    day_calls = budget['days'].get(day, 0) if valid_budget else None
    def count(key):
        value = producer.get(key)
        return value if producer_fresh and same_run and type(value) is int and value >= 0 else None
    return {
        "controlAvailable": True, "requestedEnabled": state["enabled"],
        "controlRevision": state["revision"], "profile": state["profile"]["name"] if state["profile"] else None,
        "runId": state["runId"], "runOwner": state["owner"],
        "reason": state["reason"], "updatedAt": state["updatedAt"],
        "backend": {"fresh": fresh, "instance": runtime.get("backendInstance"),
                    "appliedRevision": runtime.get("appliedRevision"), "seenAt": seen,
                    'matchesRunOwner': state['owner'] is not None and runtime.get('backendInstance') == state['owner']},
        "mqtt": {"lastEnqueuedRevision": runtime.get("lastEnqueuedRevision"),
                 "lastEnqueuedAt": runtime.get("lastEnqueuedAt"),
                 "lastAckedRevision": runtime.get("lastAckedRevision"),
                 "lastAckedAt": runtime.get("lastAckedAt")},
        "producer": producer,
        'counts': {'expectedActors': limits.get('maxConcurrentActors'),
                   'nominalVehicles': limits.get('nominalVehicleCount'),
                   'mqttConnections': count('connections'), 'activePassengers': count('actors'),
                   'readyActors': count('readyActors'), 'inflight': count('inflight'),
                   'observationPubacks': count('publishAcks'),
                   'estimatedVehicles': None, 'positionsReceivedByApp': None, 'markersRendered': None,
                   'markerLimit': None},
        'budget': {'available': valid_budget, 'serviceDate': day,
                   'reservedPublishCallsRun': run_calls, 'reservedPublishCallsDay': day_calls,
                   'maxPublishCallsRun': limits.get('maxObservationPublishCallsPerRun'),
                   'maxPublishCallsDay': limits.get('maxObservationPublishCallsPerDay'),
                   'maxRunSeconds': limits.get('maxRunDurationSeconds'),
                   'runStartedAt': state['runStartedAt'], 'serviceEndsAt': state['serviceEndsAt']},
        "clientsApplied": "unknown",
    }


def status_with_health(store: ControlStore, now: float, heartbeat: dict | None) -> dict:
    result = status(store, now)
    result['simulationHealth'] = simulation_health(heartbeat, now)
    snapshot = heartbeat.get('simulation') if isinstance(heartbeat, dict) else None
    snapshot_backend = snapshot.get('backend') if isinstance(snapshot, dict) else None
    matches = (isinstance(snapshot, dict) and fresh_timestamp(heartbeat.get('at'), now)
        and snapshot.get('runId') == result['runId']
        and snapshot.get('controlRevision') == result['controlRevision']
        and snapshot.get('runOwner') == result['runOwner']
        and isinstance(snapshot_backend, dict)
        and snapshot_backend.get('instance') == result['backend']['instance'])
    result['heartbeatMatchesControl'] = matches
    if matches:
        value = heartbeat.get('simulationVehicles')
        if type(value) is int and value >= 0:
            result['counts']['estimatedVehicles'] = value
        result['metrics'] = {'byOrigin': heartbeat.get('byOrigin', {}), 'byRun': heartbeat.get('byRun', {}),
            'evictedRunScopes': heartbeat.get('evictedRunScopes', 0), 'scope': 'current_backend_process'}
        result['persistence'] = heartbeat.get('persistence')
        result['simulationStorage'] = heartbeat.get('simulationStorage')
    return result


def main(argv: list[str] | None = None) -> int:
    parser = build_parser()
    args = parser.parse_args(argv)
    if args.command in ('report', 'retention-plan', 'purge-detail') and args.history_db is None:
        parser.error('--history-db es obligatorio para esta operación')
    if args.command not in ('report', 'retention-plan') and not args.control_db.strip():
        parser.error("define --control-db o BACKEND_SIMULATION_CONTROL_PATH; no se crea una ruta implícita")
    now = time.time()
    store = ControlStore(args.control_db)
    try:
        if args.command == 'report':
            from .simulation_reporting import run_report, export_comparison
            if args.format == 'json':
                print(json.dumps(run_report(args.history_db, args.run_id, now), ensure_ascii=False, allow_nan=False, indent=2))
            else:
                export_comparison(args.history_db, args.run_id, sys.stdout,
                    format='csv' if args.format == 'comparison-csv' else 'jsonl')
            return 0
        if args.command in ('retention-plan', 'purge-detail'):
            from .simulation_reporting import retention_plan
            plan = retention_plan(args.history_db, args.run_id, now, args.detail_days, args.summary_days)
            if args.command == 'purge-detail':
                if not plan['eligibleForDetailPurge']:
                    raise ValueError('run no elegible para la retención seleccionada')
                # No purgar mientras esa generación siga en el control activo.
                state = store.read()
                if state['enabled'] and state['runId'] == args.run_id:
                    raise ValueError('el run sigue autorizado en control')
                from .persistence import ObservationStore
                history = ObservationStore(args.history_db, existing_only=True)
                try:
                    plan['deletedRows'] = history.purge_simulation_detail(args.run_id, plan['detailBefore'])
                finally:
                    history.close()
            print(json.dumps(plan, ensure_ascii=False, allow_nan=False, indent=2))
            return 0
        if args.command == "init":
            store = ControlStore.initialize(args.control_db, now)
        elif args.command == "enable":
            store.enable(SimulationProfile.load(args.profile, args.gtfs_dir).pinned(), now)
        elif args.command in ("disable", "recover-disabled"):
            store.disable(now, args.reason, recover=args.command == "recover-disabled")
        result = status_with_health(store, now, read_heartbeat(args.health_file)) if args.health_file else status(store, now)
        print(json.dumps(result, ensure_ascii=False, allow_nan=False, indent=2))
        return 0
    except (ControlUnavailable, OSError, ValueError, TypeError, KeyError, sqlite3.Error, RuntimeError) as error:
        # No imprimir contenido de bases ni credenciales del entorno.
        unavailable = {'historyAvailable': False} if args.command in ('report', 'retention-plan') else {
            'controlAvailable': False, 'requestedEnabled': None}
        print(json.dumps({**unavailable,
                          'operation': args.command,
                          "error": str(error) if isinstance(error, ControlUnavailable) else type(error).__name__},
                         ensure_ascii=False), file=sys.stderr)
        return 2


if __name__ == "__main__":
    raise SystemExit(main())
