CREATE TYPE vehicle_kind AS ENUM ('CAR', 'MOTORBIKE', 'VAN', 'TRUCK', 'AMBULANCE');
CREATE TYPE vehicle_status AS ENUM ('OFFLINE', 'IDLE', 'EN_ROUTE', 'ON_JOB');

CREATE TABLE vehicles (
    id            UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    license_plate VARCHAR(20) UNIQUE NOT NULL,
    kind          vehicle_kind NOT NULL DEFAULT 'CAR',
    status        vehicle_status NOT NULL DEFAULT 'OFFLINE',
    created_at    TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at    TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE drivers (
    id            UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    full_name     VARCHAR(100) NOT NULL,
    phone         VARCHAR(20) UNIQUE NOT NULL,
    password_hash TEXT NOT NULL,
    created_at    TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- A driver drives one vehicle at a time; vehicles change hands across shifts.
CREATE TABLE vehicle_assignments (
    id         BIGSERIAL PRIMARY KEY,
    driver_id  UUID NOT NULL REFERENCES drivers(id) ON DELETE CASCADE,
    vehicle_id UUID NOT NULL REFERENCES vehicles(id) ON DELETE CASCADE,
    started_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    ended_at   TIMESTAMPTZ,
    CHECK (ended_at IS NULL OR ended_at > started_at)
);

CREATE UNIQUE INDEX uq_assignment_active_driver  ON vehicle_assignments(driver_id)  WHERE ended_at IS NULL;
CREATE UNIQUE INDEX uq_assignment_active_vehicle ON vehicle_assignments(vehicle_id) WHERE ended_at IS NULL;
