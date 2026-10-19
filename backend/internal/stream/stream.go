// Package stream defines the Redis Streams layout shared by the ingest,
// persister and broadcast services.
package stream

const (
	// Telemetry holds one entry per accepted TelemetryBatch.
	Telemetry = "telemetry:raw"

	// PersisterGroup is the consumer group that writes telemetry to Postgres.
	PersisterGroup = "persister"

	FieldVehicleID  = "v" // vehicle UUID
	FieldBatch      = "b" // protobuf-encoded TelemetryBatch
	FieldReceivedMs = "r" // server receive time, Unix ms
)

// Pub/Sub channels for dispatch.
const (
	// DevicePattern matches every per-vehicle channel; the ingest service
	// subscribes to it and forwards messages to the connected phone.
	DevicePattern = "dispatch:device:*"
	// JobsChannel carries JobsChanged notices for dashboards.
	JobsChannel = "dispatch:jobs"
)

// DeviceChannel carries ServerMessages for one vehicle's phone.
func DeviceChannel(vehicleID string) string { return "dispatch:device:" + vehicleID }

// PresenceKey is a hash of vehicle ID -> last time (Unix ms) its phone was
// heard from (any message, including heartbeats). Being online is separate
// from having a good GPS fix: a phone indoors may send heartbeats but no
// usable positions.
const PresenceKey = "fleet:presence"
