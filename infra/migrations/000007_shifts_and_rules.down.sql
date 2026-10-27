DROP INDEX IF EXISTS idx_geofence_events_alerts;
DROP INDEX IF EXISTS uq_geofence_events_crossing;
ALTER TABLE geofence_events DROP COLUMN IF EXISTS alert, DROP COLUMN IF EXISTS dwell;
CREATE UNIQUE INDEX uq_geofence_events_crossing ON geofence_events(geofence_id, vehicle_id, occurred_at, entered);
ALTER TABLE geofences DROP COLUMN IF EXISTS dwell_alert_s, DROP COLUMN IF EXISTS alert_on_exit, DROP COLUMN IF EXISTS alert_on_enter;
DROP TABLE IF EXISTS shifts;
