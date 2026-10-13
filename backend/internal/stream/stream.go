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
