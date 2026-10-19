-- Geofence alerts: who drew a zone, where each crossing happened, and fast
-- lookups for the dashboard's alert feed and "vehicles inside" counts.
ALTER TABLE geofences
    ADD COLUMN created_by UUID REFERENCES dispatchers(id) ON DELETE SET NULL;

ALTER TABLE geofence_events
    ADD COLUMN location GEOMETRY(Point, 4326);

CREATE INDEX idx_geofence_events_recent ON geofence_events(occurred_at DESC);
CREATE INDEX idx_geofence_events_fence_vehicle ON geofence_events(geofence_id, vehicle_id, occurred_at DESC);

-- Makes a replayed crossing (stream redelivery after a crash) a no-op.
CREATE UNIQUE INDEX uq_geofence_events_crossing ON geofence_events(geofence_id, vehicle_id, occurred_at, entered);
