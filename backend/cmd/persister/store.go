package main

import (
	"context"
	"time"

	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgxpool"

	pb "github.com/CollinsWoelinam/Radian/backend/gen/radian/telemetry/v1"
)

type Row struct {
	VehicleID  string
	RecordedAt time.Time
	Seq        int64
	Lat, Lon   float64
	SpeedKmh   *float32
	HeadingDeg *float32
	AccuracyM  *float32
	AltitudeM  *float32
	BatteryPct *int16
}

func rowFromPoint(vehicleID string, p *pb.LocationPoint) Row {
	r := Row{
		VehicleID:  vehicleID,
		RecordedAt: time.UnixMilli(p.RecordedAtMs).UTC(),
		Seq:        p.Seq,
		Lat:        p.Latitude,
		Lon:        p.Longitude,
		SpeedKmh:   p.SpeedKmh,
		HeadingDeg: p.HeadingDeg,
		AccuracyM:  p.AccuracyM,
		AltitudeM:  p.AltitudeM,
	}
	if p.BatteryPct != nil {
		b := int16(*p.BatteryPct)
		r.BatteryPct = &b
	}
	return r
}

type Store struct {
	pool *pgxpool.Pool
}

var stagingColumns = []string{
	"vehicle_id", "recorded_at", "seq", "lat", "lon",
	"speed_kmh", "heading_deg", "accuracy_m", "altitude_m", "battery_pct",
}

// Write COPYs rows into a temp staging table, then moves them into the
// hypertable with ON CONFLICT DO NOTHING so resent points are dropped. Rows
// for unknown vehicles are skipped by the join rather than failing the batch.
// Returns the number of newly inserted telemetry rows.
func (s *Store) Write(ctx context.Context, rows []Row) (int64, error) {
	if len(rows) == 0 {
		return 0, nil
	}
	tx, err := s.pool.Begin(ctx)
	if err != nil {
		return 0, err
	}
	defer tx.Rollback(ctx)

	_, err = tx.Exec(ctx, `
		CREATE TEMP TABLE telemetry_staging (
			vehicle_id  UUID,
			recorded_at TIMESTAMPTZ,
			seq         BIGINT,
			lat         DOUBLE PRECISION,
			lon         DOUBLE PRECISION,
			speed_kmh   REAL,
			heading_deg REAL,
			accuracy_m  REAL,
			altitude_m  REAL,
			battery_pct SMALLINT
		) ON COMMIT DROP`)
	if err != nil {
		return 0, err
	}

	_, err = tx.CopyFrom(ctx, pgx.Identifier{"telemetry_staging"}, stagingColumns,
		pgx.CopyFromSlice(len(rows), func(i int) ([]any, error) {
			r := rows[i]
			return []any{
				r.VehicleID, r.RecordedAt, r.Seq, r.Lat, r.Lon,
				r.SpeedKmh, r.HeadingDeg, r.AccuracyM, r.AltitudeM, r.BatteryPct,
			}, nil
		}))
	if err != nil {
		return 0, err
	}

	tag, err := tx.Exec(ctx, `
		INSERT INTO vehicle_telemetry
			(vehicle_id, recorded_at, seq, location, speed_kmh, heading_deg, accuracy_m, altitude_m, battery_pct)
		SELECT s.vehicle_id, s.recorded_at, s.seq,
		       ST_SetSRID(ST_MakePoint(s.lon, s.lat), 4326),
		       s.speed_kmh, s.heading_deg, s.accuracy_m, s.altitude_m, s.battery_pct
		FROM telemetry_staging s
		JOIN vehicles v ON v.id = s.vehicle_id
		ON CONFLICT DO NOTHING`)
	if err != nil {
		return 0, err
	}

	// Only move last_position forward: a late backfill must not rewind it.
	_, err = tx.Exec(ctx, `
		INSERT INTO vehicle_last_position
			(vehicle_id, recorded_at, location, speed_kmh, heading_deg, accuracy_m, battery_pct, updated_at)
		SELECT DISTINCT ON (s.vehicle_id)
		       s.vehicle_id, s.recorded_at, ST_SetSRID(ST_MakePoint(s.lon, s.lat), 4326),
		       s.speed_kmh, s.heading_deg, s.accuracy_m, s.battery_pct, NOW()
		FROM telemetry_staging s
		JOIN vehicles v ON v.id = s.vehicle_id
		ORDER BY s.vehicle_id, s.recorded_at DESC
		ON CONFLICT (vehicle_id) DO UPDATE SET
			recorded_at = EXCLUDED.recorded_at,
			location    = EXCLUDED.location,
			speed_kmh   = EXCLUDED.speed_kmh,
			heading_deg = EXCLUDED.heading_deg,
			accuracy_m  = EXCLUDED.accuracy_m,
			battery_pct = EXCLUDED.battery_pct,
			updated_at  = EXCLUDED.updated_at
		WHERE vehicle_last_position.recorded_at < EXCLUDED.recorded_at`)
	if err != nil {
		return 0, err
	}

	if err := tx.Commit(ctx); err != nil {
		return 0, err
	}
	return tag.RowsAffected(), nil
}
