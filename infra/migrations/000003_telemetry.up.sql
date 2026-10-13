-- Raw GPS history. Hypertable partitioned by the device's recorded time,
-- never server arrival time, so late offline batches land in the right chunk.
CREATE TABLE vehicle_telemetry (
    vehicle_id  UUID NOT NULL REFERENCES vehicles(id) ON DELETE CASCADE,
    recorded_at TIMESTAMPTZ NOT NULL,
    seq         BIGINT NOT NULL,                 -- per-device monotonic counter
    location    GEOMETRY(Point, 4326) NOT NULL,  -- WGS 84 (lon, lat)
    speed_kmh   REAL,
    heading_deg REAL CHECK (heading_deg IS NULL OR (heading_deg >= 0 AND heading_deg < 360)),
    accuracy_m  REAL,                            -- horizontal accuracy radius
    altitude_m  REAL,
    battery_pct SMALLINT CHECK (battery_pct IS NULL OR battery_pct BETWEEN 0 AND 100),
    received_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    -- Idempotency: retried offline batches are dropped via ON CONFLICT DO NOTHING
    PRIMARY KEY (vehicle_id, recorded_at)
);

SELECT create_hypertable('vehicle_telemetry', by_range('recorded_at', INTERVAL '1 day'));

CREATE INDEX idx_telemetry_location ON vehicle_telemetry USING GIST (location);

ALTER TABLE vehicle_telemetry SET (
    timescaledb.compress,
    timescaledb.compress_segmentby = 'vehicle_id',
    timescaledb.compress_orderby   = 'recorded_at DESC'
);
SELECT add_compression_policy('vehicle_telemetry', INTERVAL '7 days');
SELECT add_retention_policy('vehicle_telemetry', INTERVAL '180 days');

-- Latest known fix per vehicle. Durable fallback for Redis GEO.
CREATE TABLE vehicle_last_position (
    vehicle_id  UUID PRIMARY KEY REFERENCES vehicles(id) ON DELETE CASCADE,
    recorded_at TIMESTAMPTZ NOT NULL,
    location    GEOMETRY(Point, 4326) NOT NULL,
    speed_kmh   REAL,
    heading_deg REAL,
    accuracy_m  REAL,
    battery_pct SMALLINT,
    updated_at  TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_last_position_location ON vehicle_last_position USING GIST (location);
