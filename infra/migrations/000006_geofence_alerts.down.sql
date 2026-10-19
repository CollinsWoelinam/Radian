DROP INDEX IF EXISTS uq_geofence_events_crossing;
DROP INDEX IF EXISTS idx_geofence_events_fence_vehicle;
DROP INDEX IF EXISTS idx_geofence_events_recent;
ALTER TABLE geofence_events DROP COLUMN IF EXISTS location;
ALTER TABLE geofences DROP COLUMN IF EXISTS created_by;
