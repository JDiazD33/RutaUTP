"""S09: exportación, referencia y retención en SQLite temporal, sin MQTT."""

from dataclasses import replace
import io
import json
import sqlite3

import pytest

from rutautp_backend.simulation_admin import main
from rutautp_backend.simulation_models import SimulationActorRecord, SimulationRunStatus
from rutautp_backend.simulation_reporting import history_reader, run_report, export_comparison, retention_plan
from rutautp_backend.persistence import ObservationStore
from .test_simulation_persistence import (store, start_run, observation, vehicle, RUN, OTHER_RUN,
    NOW, SOURCE, SESSION, run_record)


@pytest.fixture
def recorded(store):
    start_run(store)
    store.record_observation(observation(), 'estimated-a', NOW, source=SOURCE)
    store.record_vehicle(vehicle(), NOW, source=SOURCE)
    store.flush()
    return store


def test_report_does_not_create_or_migrate_missing_or_legacy_history(tmp_path):
    path = tmp_path/'missing.sqlite'
    with pytest.raises(FileNotFoundError): run_report(path, RUN, NOW)
    assert not path.exists()
    with sqlite3.connect(path) as db: db.execute('CREATE TABLE legacy (id INTEGER)')
    before = path.read_bytes()
    with pytest.raises(ValueError): run_report(path, RUN, NOW)
    assert path.read_bytes() == before


def test_reader_forbids_writes(recorded):
    with history_reader(recorded.path) as db:
        with pytest.raises(sqlite3.OperationalError): db.execute('DELETE FROM observations')
    assert recorded.query('SELECT COUNT(*) FROM observations') == [(1,)]


def test_report_keeps_reference_estimate_and_delivery_meanings_separate(recorded):
    report = run_report(recorded.path, RUN, NOW)
    assert report['stored']['observations']['rows'] == 1
    assert report['stored']['vehicle_positions']['rows'] == 1
    assert report['actors']['principals'] == 1 and report['actors']['nominalVehiclesSeen'] == 1
    assert report['estimatedIdsSeen'] == 1
    assert report['markersRendered'] is None and report['positionsReceivedByApp'] is None
    assert report['positionRowsMeaning'] == 'stored_attempts_not_broker_or_client_ack'
    assert report['historyComplete'] and report['detailComplete']


def test_report_detects_historical_splits_and_merges_without_claiming_accuracy(recorded):
    recorded.record_observation(observation(), 'estimated-b', NOW+1, source=SOURCE)
    other_session = '1c3c55e3-1d29-4f87-a874-eb7fe06da361'
    recorded.record_simulation_actor(SimulationActorRecord(RUN, 'sim-002', other_session,
        'scenario-bus-02', observation().route_id, NOW-1))
    from rutautp_backend.simulation_models import SourceContext, DataOrigin
    recorded.record_observation(replace(observation(), session_id=other_session), 'estimated-b', NOW+2,
        source=SourceContext(DataOrigin.SIMULATED, RUN, 'sim-002'))
    recorded.flush()
    comparison = run_report(recorded.path, RUN, NOW+2)['comparison']
    assert comparison['nominalWithMultipleEstimatedIds'] == 1
    assert comparison['estimatedIdsWithMultipleNominals'] == 1
    assert comparison['meaning'] == 'historical_associations_not_simultaneous_accuracy'


def test_export_jsonl_and_csv_keep_run_and_origin(recorded):
    for format in ('jsonl', 'csv'):
        output = io.StringIO()
        assert export_comparison(recorded.path, RUN, output, format=format) == 1
        assert RUN in output.getvalue() and 'simulated' in output.getvalue()
        assert 'scenario-bus-01' in output.getvalue() and 'estimated-a' in output.getvalue()


def test_export_does_not_mix_another_run_or_observed(recorded):
    recorded.record_observation(observation(), 'observed-id', NOW)
    start_run(recorded, OTHER_RUN)
    recorded.flush()
    output = io.StringIO(); export_comparison(recorded.path, RUN, output)
    assert 'observed-id' not in output.getvalue() and OTHER_RUN not in output.getvalue()
    assert run_report(recorded.path, OTHER_RUN, NOW)['stored']['observations']['rows'] == 0


def test_report_rejects_noncanonical_or_missing_run(recorded):
    with pytest.raises(ValueError): run_report(recorded.path, 'not-a-run', NOW)
    with pytest.raises(ValueError): run_report(recorded.path, OTHER_RUN, NOW)


@pytest.mark.parametrize('detail,summary', [(0,30), (-1,30), (7,6), (float('nan'),30), (7,float('inf')), (True,30)])
def test_retention_requires_explicit_valid_horizons(recorded, detail, summary):
    with pytest.raises(ValueError): retention_plan(recorded.path, RUN, NOW, detail, summary)


def test_retention_plan_keeps_running_run_and_old_summary(recorded):
    plan = retention_plan(recorded.path, RUN, NOW+40*86400, 7, 30)
    assert not plan['eligibleForDetailPurge']
    assert not plan['automaticDeletion'] and not plan['summaryDeletionImplemented']


def test_retention_preserves_original_totals_summary_and_observed(recorded):
    recorded.record_observation(observation(), 'observed', NOW)
    recorded.record_observation(observation(), 'legacy', NOW)
    recorded.flush()
    with sqlite3.connect(recorded.path) as db:
        db.execute("UPDATE observations SET data_origin='legacy_unknown' WHERE vehicle_id='legacy'")
    recorded.end_simulation_actor(RUN, SESSION, NOW+1, reason='test')
    recorded.set_simulation_run_status(RUN, SimulationRunStatus.DISABLED, NOW+2)
    plan = retention_plan(recorded.path, RUN, NOW+40*86400, 7, 30)
    assert plan['eligibleForDetailPurge'] and plan['summaryRetentionElapsed']
    recorded.purge_simulation_detail(RUN, plan['detailBefore'])
    first = run_report(recorded.path, RUN, NOW+40*86400)
    assert not first['detailComplete']
    assert first['run']['savedTotals']['beforeFirstRetention']['observations'] == 1
    assert recorded.query("SELECT vehicle_id FROM observations WHERE data_origin='observed'") == [('observed',)]
    assert recorded.query("SELECT vehicle_id FROM observations WHERE data_origin='legacy_unknown'") == [('legacy',)]
    recorded.purge_simulation_detail(RUN, plan['detailBefore']+1)
    assert run_report(recorded.path, RUN, NOW+40*86400)['run']['savedTotals'] == first['run']['savedTotals']
    assert recorded.query('SELECT COUNT(*) FROM simulation_runs') == [(1,)]


def test_csv_formula_like_reference_id_is_escaped(recorded):
    with sqlite3.connect(recorded.path) as db:
        db.execute("UPDATE simulation_actors SET scenario_vehicle_id='=1+1' WHERE simulation_run_id=?", (RUN,))
    output = io.StringIO(); export_comparison(recorded.path, RUN, output, format='csv')
    assert "'=1+1" in output.getvalue()


def test_report_association_requires_matching_boarding_time(recorded):
    with sqlite3.connect(recorded.path) as db:
        db.execute('UPDATE simulation_actors SET boarded_at=? WHERE simulation_run_id=?', (NOW+1, RUN))
    report = run_report(recorded.path, RUN, NOW+2)
    assert report['comparison']['unmappedObservations'] == 1
    output = io.StringIO(); assert export_comparison(recorded.path, RUN, output) == 0


def test_incomplete_history_is_reported_not_success(recorded):
    recorded.set_simulation_run_status(RUN, SimulationRunStatus.FAILED, NOW+1)
    assert not run_report(recorded.path, RUN, NOW+1)['historyComplete']


def test_report_cli_only_reads_and_needs_no_control_database(recorded, capsys):
    assert main(['--history-db', str(recorded.path), 'report', '--run-id', RUN]) == 0
    assert json.loads(capsys.readouterr().out)['run']['run_id'] == RUN


def test_purge_cli_requires_apply_and_explicit_history(tmp_path):
    with pytest.raises(SystemExit):
        main(['--control-db', str(tmp_path/'missing'), '--history-db', str(tmp_path/'history'),
              'purge-detail', '--run-id', RUN, '--detail-days', '7', '--summary-days', '30'])
    assert list(tmp_path.iterdir()) == []


def test_explicit_purge_cli_only_removes_selected_synthetic_detail(recorded, tmp_path, monkeypatch, capsys):
    from rutautp_backend.simulation_control_store import ControlStore
    from rutautp_backend import simulation_admin
    recorded.record_observation(observation(), 'observed', NOW)
    recorded.end_simulation_actor(RUN, SESSION, NOW+1)
    recorded.set_simulation_run_status(RUN, SimulationRunStatus.DISABLED, NOW+2)
    control = ControlStore.initialize(tmp_path/'private/control.sqlite', NOW+3)
    monkeypatch.setattr(simulation_admin.time, 'time', lambda: NOW+40*86400)
    assert main(['--control-db', str(control.path), '--history-db', str(recorded.path), 'purge-detail',
        '--run-id', RUN, '--detail-days', '7', '--summary-days', '30', '--apply']) == 0
    result = json.loads(capsys.readouterr().out)
    assert result['deletedRows'] == 3
    assert recorded.query('SELECT vehicle_id FROM observations') == [('observed',)]
    assert run_report(recorded.path, RUN, NOW+40*86400)['run']['savedTotals']['beforeFirstRetention']['observations'] == 1
