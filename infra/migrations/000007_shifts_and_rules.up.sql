-- Driver shifts: started and ended by the driver app; summaries are computed
-- from telemetry and job events when a shift closes.
CREATE TABLE shifts (
    id             UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    vehicle_id     UUID NOT NULL REFERENCES vehicles(id) ON DELETE CASCADE,
    driver_id      UUID REFERENCES drivers(id) ON DELETE SET NULL,
    started_at     TIMESTAMPTZ NOT NULL,
    ended_at       TIMESTAMPTZ,
    distance_m     DOUBLE PRECISION,
    driving_s      INT,
    jobs_completed INT,
    CHECK (ended_at IS NULL OR ended_at >= started_at)
);
CREATE UNIQUE INDEX uq_shifts_open_vehicle ON shifts(vehicle_id) WHERE ended_at IS NULL;
CREATE INDEX idx_shifts_vehicle ON shifts(vehicle_id, started_at DESC);

-- Per-zone alert rules, replacing alerts implied by the zone's kind.
ALTER TABLE geofences
    ADD COLUMN alert_on_enter BOOLEAN NOT NULL DEFAULT FALSE,
    ADD COLUMN alert_on_exit  BOOLEAN NOT NULL DEFAULT FALSE,
    ADD COLUMN dwell_alert_s  INT CHECK (dwell_alert_s IS NULL OR dwell_alert_s BETWEEN 30 AND 86400);
UPDATE geofences SET alert_on_enter = TRUE WHERE kind = 'RESTRICTED';
UPDATE geofences SET alert_on_exit = TRUE WHERE kind = 'SERVICE_AREA';

-- A dwell event marks a vehicle that stayed inside longer than the zone allows.
-- alert records whether the zone's rules flagged the event when it happened.
ALTER TABLE geofence_events
    ADD COLUMN dwell BOOLEAN NOT NULL DEFAULT FALSE,
    ADD COLUMN alert BOOLEAN NOT NULL DEFAULT FALSE;
UPDATE geofence_events e SET alert = (g.kind = 'RESTRICTED' AND e.entered) OR (g.kind = 'SERVICE_AREA' AND NOT e.entered)
FROM geofences g WHERE g.id = e.geofence_id;
DROP INDEX IF EXISTS uq_geofence_events_crossing;
CREATE UNIQUE INDEX uq_geofence_events_crossing ON geofence_events(geofence_id, vehicle_id, occurred_at, entered, dwell);
CREATE INDEX idx_geofence_events_alerts ON geofence_events(occurred_at DESC) WHERE alert;
