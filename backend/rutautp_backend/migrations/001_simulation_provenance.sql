-- Esquema 0: las tres tablas históricas sin versión. Esquema 1: S02.
-- El ejecutor abre UNA transacción y fija user_version solo al confirmar.
CREATE TABLE simulation_runs (
    run_id TEXT PRIMARY KEY NOT NULL,
    data_origin TEXT NOT NULL DEFAULT 'simulated' CHECK (data_origin = 'simulated'),
    scenario_id TEXT NOT NULL,
    scenario_version INTEGER NOT NULL CHECK (scenario_version >= 1),
    seed INTEGER NOT NULL CHECK (seed >= 0),
    manifest_sha256 TEXT NOT NULL,
    feed_hashes_json TEXT NOT NULL,
    created_at REAL NOT NULL,
    started_at REAL,
    ended_at REAL,
    status TEXT NOT NULL DEFAULT 'prepared'
        CHECK (status IN ('prepared', 'running', 'paused', 'completed', 'disabled', 'failed')),
    reason TEXT NOT NULL DEFAULT '',
    totals_json TEXT NOT NULL DEFAULT '{}',
    history_complete INTEGER NOT NULL DEFAULT 1 CHECK (history_complete IN (0, 1)),
    detail_purged_before REAL,
    CHECK (started_at IS NULL OR started_at >= created_at),
    CHECK (ended_at IS NULL OR ended_at >= COALESCE(started_at, created_at))
);

CREATE TABLE simulation_actors (
    simulation_run_id TEXT NOT NULL REFERENCES simulation_runs(run_id),
    data_origin TEXT NOT NULL DEFAULT 'simulated' CHECK (data_origin = 'simulated'),
    session_id TEXT NOT NULL,
    principal TEXT NOT NULL,
    scenario_vehicle_id TEXT NOT NULL,
    route_id TEXT NOT NULL,
    boarded_at REAL NOT NULL,
    left_at REAL,
    leave_reason TEXT NOT NULL DEFAULT '',
    PRIMARY KEY (simulation_run_id, session_id),
    CHECK (left_at IS NULL OR left_at >= boarded_at)
);

ALTER TABLE observations ADD COLUMN data_origin TEXT NOT NULL DEFAULT 'legacy_unknown'
    CHECK (data_origin IN ('legacy_unknown', 'observed', 'simulated'));
ALTER TABLE observations ADD COLUMN simulation_run_id TEXT DEFAULT NULL
    REFERENCES simulation_runs(run_id)
    CHECK ((data_origin = 'simulated' AND simulation_run_id IS NOT NULL)
        OR (data_origin != 'simulated' AND simulation_run_id IS NULL));

ALTER TABLE vehicle_positions ADD COLUMN data_origin TEXT NOT NULL DEFAULT 'legacy_unknown'
    CHECK (data_origin IN ('legacy_unknown', 'observed', 'simulated'));
ALTER TABLE vehicle_positions ADD COLUMN simulation_run_id TEXT DEFAULT NULL
    REFERENCES simulation_runs(run_id)
    CHECK ((data_origin = 'simulated' AND simulation_run_id IS NOT NULL)
        OR (data_origin != 'simulated' AND simulation_run_id IS NULL));

ALTER TABLE rejections ADD COLUMN data_origin TEXT NOT NULL DEFAULT 'legacy_unknown'
    CHECK (data_origin IN ('legacy_unknown', 'unknown', 'observed', 'simulated'));
ALTER TABLE rejections ADD COLUMN simulation_run_id TEXT DEFAULT NULL
    REFERENCES simulation_runs(run_id)
    CHECK ((data_origin = 'simulated' AND simulation_run_id IS NOT NULL)
        OR (data_origin != 'simulated' AND simulation_run_id IS NULL));

CREATE INDEX idx_obs_origin_run_at ON observations(data_origin, simulation_run_id, at);
CREATE INDEX idx_veh_origin_run_at ON vehicle_positions(data_origin, simulation_run_id, at);
CREATE INDEX idx_rej_origin_run_at ON rejections(data_origin, simulation_run_id, at);
CREATE INDEX idx_runs_origin_created ON simulation_runs(data_origin, created_at);
CREATE INDEX idx_actors_origin_run_at ON simulation_actors(data_origin, simulation_run_id, boarded_at);
CREATE INDEX idx_actors_run_principal ON simulation_actors(simulation_run_id, principal);
CREATE INDEX idx_actors_run_left ON simulation_actors(simulation_run_id, left_at);

CREATE TABLE store_schema_migrations (
    version INTEGER PRIMARY KEY,
    migration_name TEXT NOT NULL,
    applied_at REAL NOT NULL,
    backup_path TEXT
);
