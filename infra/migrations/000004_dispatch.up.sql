CREATE TYPE geofence_kind AS ENUM ('DEPOT', 'SERVICE_AREA', 'RESTRICTED');

CREATE TABLE geofences (
    id         UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    name       VARCHAR(100) NOT NULL,
    kind       geofence_kind NOT NULL,
    area       GEOMETRY(MultiPolygon, 4326) NOT NULL CHECK (ST_IsValid(area)),
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_geofences_area ON geofences USING GIST (area);

CREATE TYPE job_status AS ENUM (
    'PENDING', 'ASSIGNED', 'EN_ROUTE_PICKUP', 'ON_SITE', 'EN_ROUTE_DROPOFF', 'COMPLETED', 'CANCELLED'
);

CREATE TABLE jobs (
    id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    status              job_status NOT NULL DEFAULT 'PENDING',
    priority            SMALLINT NOT NULL DEFAULT 3 CHECK (priority BETWEEN 1 AND 5), -- 1 = most urgent
    pickup              GEOMETRY(Point, 4326) NOT NULL,
    pickup_address      TEXT,
    dropoff             GEOMETRY(Point, 4326),
    dropoff_address     TEXT,
    notes               TEXT,
    assigned_vehicle_id UUID REFERENCES vehicles(id) ON DELETE SET NULL,
    eta_seconds         INT,
    created_at          TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    assigned_at         TIMESTAMPTZ,
    completed_at        TIMESTAMPTZ
);

CREATE INDEX idx_jobs_open ON jobs(status, priority, created_at)
    WHERE status NOT IN ('COMPLETED', 'CANCELLED');
CREATE INDEX idx_jobs_pickup ON jobs USING GIST (pickup);

-- Enter/exit events, detected by the persister when a fix crosses a fence boundary.
CREATE TABLE geofence_events (
    id          BIGSERIAL PRIMARY KEY,
    geofence_id UUID NOT NULL REFERENCES geofences(id) ON DELETE CASCADE,
    vehicle_id  UUID NOT NULL REFERENCES vehicles(id) ON DELETE CASCADE,
    entered     BOOLEAN NOT NULL,  -- true = enter, false = exit
    occurred_at TIMESTAMPTZ NOT NULL
);

CREATE INDEX idx_geofence_events_vehicle ON geofence_events(vehicle_id, occurred_at DESC);
