package stream

// InsideKey is a Redis set of the vehicle IDs currently inside a geofence,
// maintained by the geofencer. The api counts it for the dashboard.
func InsideKey(geofenceID string) string { return "geofence:inside:" + geofenceID }
