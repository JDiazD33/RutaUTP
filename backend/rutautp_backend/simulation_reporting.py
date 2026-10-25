"""S09: consultas/exportación del histórico existente, exclusivamente de lectura.

Nunca construye ObservationStore, migra, crea una base ni alimenta el agrupador.
La relación actor→vehículo nominal es referencia; vehicle_id es la estimación.
"""

from __future__ import annotations

from contextlib import contextmanager
import csv
import json
from pathlib import Path
import sqlite3
from typing import TextIO

from .persistence_migrations import STORE_SCHEMA_VERSION, MIGRATION_NAME
from .simulation_models import canonical_uuid, finite_time


@contextmanager
def history_reader(path: str | Path):
    target = Path(path).expanduser().resolve(strict=True)
    db = sqlite3.connect(target.as_uri() + '?mode=ro', uri=True, timeout=2)
    db.row_factory = sqlite3.Row
    try:
        db.execute('PRAGMA query_only=ON')
        db.execute('BEGIN')
        if db.execute('PRAGMA user_version').fetchone()[0] != STORE_SCHEMA_VERSION:
            raise ValueError('versión de histórico incompatible; no se migra al consultar')
        row = db.execute('SELECT migration_name FROM store_schema_migrations WHERE version=?',
                         (STORE_SCHEMA_VERSION,)).fetchone()
        if row is None or row[0] != MIGRATION_NAME:
            raise ValueError('histórico sin migración consistente')
        yield db
    finally:
        db.close()


def comparison_rows(db: sqlite3.Connection, run_id: str):
    """Streaming por pareja, sin confundir IDs vistos a lo largo del run con simultáneos."""
    canonical_uuid(run_id)
    cursor = db.execute('''SELECT a.scenario_vehicle_id AS nominalVehicleId,
        o.vehicle_id AS estimatedVehicleId, o.route_id AS routeId,
        COUNT(*) AS observations, COUNT(DISTINCT a.principal) AS principals,
        MIN(o.observed_at) AS firstSampleAt, MAX(o.observed_at) AS lastSampleAt
        FROM observations o JOIN simulation_actors a
          ON a.simulation_run_id=o.simulation_run_id AND a.session_id=o.session_id
          AND a.route_id=o.route_id AND a.data_origin='simulated'
          AND o.observed_at>=a.boarded_at AND (a.left_at IS NULL OR o.observed_at<=a.left_at)
        WHERE o.data_origin='simulated' AND o.simulation_run_id=?
        GROUP BY a.scenario_vehicle_id, o.vehicle_id, o.route_id
        ORDER BY a.scenario_vehicle_id, o.vehicle_id, o.route_id''', (run_id,))
    try:
        for row in cursor:
            yield dict(row)
    finally:
        cursor.close()


def _summary(db: sqlite3.Connection, run_id: str, now: float) -> dict:
    canonical_uuid(run_id); finite_time(now)
    record = db.execute("SELECT * FROM simulation_runs WHERE run_id=? AND data_origin='simulated'",
                        (run_id,)).fetchone()
    if record is None:
        raise ValueError('run no encontrado')
    run = dict(record)
    run['feedHashes'] = json.loads(run.pop('feed_hashes_json'))
    run['savedTotals'] = json.loads(run.pop('totals_json'))
    counts = {}
    for table in ('observations', 'rejections', 'vehicle_positions'):
        counts[table] = dict(db.execute(f'''SELECT COUNT(*) AS rows, MAX(at) AS lastStoredAt
            FROM {table} WHERE data_origin='simulated' AND simulation_run_id=?''', (run_id,)).fetchone())
    actors = db.execute('''SELECT COUNT(*) AS sessions, COUNT(DISTINCT principal) AS principals,
        COUNT(DISTINCT scenario_vehicle_id) AS nominalVehiclesSeen,
        SUM(CASE WHEN boarded_at<=? AND (left_at IS NULL OR left_at>?) THEN 1 ELSE 0 END) AS openSessionsAt
        FROM simulation_actors WHERE data_origin='simulated' AND simulation_run_id=?''',
        (now, now, run_id)).fetchone()
    estimates = db.execute('''SELECT COUNT(DISTINCT vehicle_id) FROM observations
        WHERE data_origin='simulated' AND simulation_run_id=?''', (run_id,)).fetchone()[0]
    # Agregación en SQL; memoria constante aun si hay muchos IDs históricos.
    comparisons = '''SELECT a.scenario_vehicle_id AS nominal, o.vehicle_id AS estimated
        FROM observations o JOIN simulation_actors a ON a.simulation_run_id=o.simulation_run_id
        AND a.session_id=o.session_id AND a.route_id=o.route_id AND a.data_origin='simulated'
        AND o.observed_at>=a.boarded_at AND (a.left_at IS NULL OR o.observed_at<=a.left_at)
        WHERE o.data_origin='simulated' AND o.simulation_run_id=? AND o.vehicle_id IS NOT NULL'''
    split = db.execute(f'SELECT COUNT(*) FROM (SELECT nominal FROM ({comparisons}) GROUP BY nominal '
                       'HAVING COUNT(DISTINCT estimated)>1)', (run_id,)).fetchone()[0]
    merge = db.execute(f'SELECT COUNT(*) FROM (SELECT estimated FROM ({comparisons}) GROUP BY estimated '
                       'HAVING COUNT(DISTINCT nominal)>1)', (run_id,)).fetchone()[0]
    unmapped = db.execute('''SELECT COUNT(*) FROM observations o WHERE o.data_origin='simulated'
        AND o.simulation_run_id=? AND NOT EXISTS (SELECT 1 FROM simulation_actors a
        WHERE a.simulation_run_id=o.simulation_run_id AND a.session_id=o.session_id
        AND a.data_origin='simulated' AND a.route_id=o.route_id AND o.observed_at>=a.boarded_at
        AND (a.left_at IS NULL OR o.observed_at<=a.left_at))''', (run_id,)).fetchone()[0]
    reasons = dict(db.execute("SELECT reason, COUNT(*) FROM rejections WHERE data_origin='simulated' "
        'AND simulation_run_id=? GROUP BY reason ORDER BY reason', (run_id,)).fetchall())
    return {'schemaVersion': 1, 'generatedAt': now, 'run': run, 'stored': counts,
        'actors': dict(actors), 'estimatedIdsSeen': estimates,
        'comparison': {'nominalWithMultipleEstimatedIds': split, 'estimatedIdsWithMultipleNominals': merge,
            'unmappedObservations': unmapped, 'meaning': 'historical_associations_not_simultaneous_accuracy',
            'coverage': 'partial_after_retention' if run['detail_purged_before'] is not None
                else 'stored_accepted_observations_only'},
        'rejectionReasons': reasons, 'historyComplete': bool(run['history_complete']),
        'detailComplete': run['detail_purged_before'] is None,
        'mqttConnections': None, 'positionsReceivedByApp': None, 'markersRendered': None,
        'markerLimit': 8, 'positionRowsMeaning': 'stored_attempts_not_broker_or_client_ack',
        'referenceMeaning': 'durable_boarding_records_joined_by_run_session_route_and_time'}


def run_report(path: str | Path, run_id: str, now: float) -> dict:
    with history_reader(path) as db:
        return _summary(db, run_id, now)


def export_comparison(path: str | Path, run_id: str, output: TextIO, *, format: str = 'jsonl') -> int:
    if format not in ('jsonl', 'csv'):
        raise ValueError('formato de comparación no admitido')
    with history_reader(path) as db:
        canonical_uuid(run_id)
        if db.execute('SELECT 1 FROM simulation_runs WHERE run_id=?', (run_id,)).fetchone() is None:
            raise ValueError('run no encontrado')
        names = ['dataOrigin', 'simulationRunId', 'nominalVehicleId', 'estimatedVehicleId',
                 'routeId', 'observations', 'principals', 'firstSampleAt', 'lastSampleAt']
        writer = csv.DictWriter(output, fieldnames=names) if format == 'csv' else None
        if writer:
            writer.writeheader()
        count = 0
        for row in comparison_rows(db, run_id):
            row = {'dataOrigin': 'simulated', 'simulationRunId': run_id, **row}
            if writer:
                # IDs de GTFS son datos: evitar fórmulas al abrir el CSV en una hoja.
                writer.writerow({k: "'"+v if isinstance(v, str) and v.startswith(('=', '+', '-', '@', '\t', '\r')) else v
                                 for k, v in row.items()})
            else:
                output.write(json.dumps(row, ensure_ascii=False, allow_nan=False)+'\n')
            count += 1
        return count


def retention_plan(path: str | Path, run_id: str, now: float, detail_days: float,
                   summary_days: float) -> dict:
    finite_time(now)
    for days in (detail_days, summary_days):
        if type(days) not in (int, float) or not 0 < days <= 3650:
            raise ValueError('retención positiva y acotada, sin default automático')
    if summary_days < detail_days:
        raise ValueError('el resumen debe durar al menos tanto como el detalle')
    with history_reader(path) as db:
        report = _summary(db, run_id, now)
        run = report['run']
        ended = run['ended_at']
        terminal = run['status'] in ('disabled', 'failed', 'completed')
        cutoff = now-detail_days*86400
        eligible = terminal and ended is not None and ended < cutoff
        return {'runId': run_id, 'dataOrigin': 'simulated', 'detailDays': detail_days,
            'summaryDays': summary_days, 'detailBefore': max(0, cutoff),
            'eligibleForDetailPurge': eligible,
            'summaryRetentionElapsed': terminal and ended is not None and ended < now-summary_days*86400,
            'automaticDeletion': False, 'summaryDeletionImplemented': False,
            'meaning': 'explicit_detail_purge_only; summaries_and_control_ledger_preserved'}
