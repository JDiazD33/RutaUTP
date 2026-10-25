-- Guion del backend, exclusivamente para posiciones sintéticas. No son votos.
ALTER TABLE vehicle_positions ADD COLUMN occupancy_script_version INTEGER DEFAULT NULL
    CHECK (occupancy_script_version IS NULL OR
        (data_origin = 'simulated' AND occupancy_script_version = 1));
ALTER TABLE vehicle_positions ADD COLUMN scenario_occupancy TEXT DEFAULT NULL
    CHECK ((scenario_occupancy IS NULL AND occupancy_script_version IS NULL) OR
        (scenario_occupancy IS NOT NULL AND occupancy_script_version IS NOT NULL
         AND data_origin = 'simulated' AND occupancy_script_version = 1
         AND scenario_occupancy IN ('empty', 'space', 'full')));
