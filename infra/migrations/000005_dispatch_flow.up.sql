-- Offer stage: the job has been offered to one vehicle and awaits accept/decline.
ALTER TYPE job_status ADD VALUE IF NOT EXISTS 'OFFERED' AFTER 'PENDING';

CREATE TABLE dispatchers (
    id            UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    email         VARCHAR(255) UNIQUE NOT NULL,
    full_name     VARCHAR(100) NOT NULL,
    password_hash TEXT NOT NULL,
    created_at    TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

ALTER TABLE jobs
    ADD COLUMN number               BIGSERIAL,          -- human-friendly "#1042"
    ADD COLUMN created_by           UUID REFERENCES dispatchers(id) ON DELETE SET NULL,
    ADD COLUMN offered_vehicle_id   UUID REFERENCES vehicles(id) ON DELETE SET NULL,
    ADD COLUMN offered_at           TIMESTAMPTZ,
    ADD COLUMN offer_expires_at     TIMESTAMPTZ,
    ADD COLUMN declined_vehicle_ids UUID[] NOT NULL DEFAULT '{}',
    ADD COLUMN last_dispatch_at     TIMESTAMPTZ,
    ADD COLUMN updated_at           TIMESTAMPTZ NOT NULL DEFAULT NOW();

CREATE UNIQUE INDEX uq_jobs_number ON jobs(number);

-- A vehicle works one job at a time.
CREATE UNIQUE INDEX uq_jobs_active_vehicle ON jobs(assigned_vehicle_id)
    WHERE status IN ('ASSIGNED', 'EN_ROUTE_PICKUP', 'ON_SITE', 'EN_ROUTE_DROPOFF');

-- Audit trail shown as the job timeline on the dashboard.
CREATE TABLE job_events (
    id         BIGSERIAL PRIMARY KEY,
    job_id     UUID NOT NULL REFERENCES jobs(id) ON DELETE CASCADE,
    kind       VARCHAR(40) NOT NULL,   -- created, offered, accepted, declined, offer_expired, status, cancelled, no_vehicle
    vehicle_id UUID REFERENCES vehicles(id) ON DELETE SET NULL,
    detail     JSONB NOT NULL DEFAULT '{}',
    at         TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_job_events_job ON job_events(job_id, at);
