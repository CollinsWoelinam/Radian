package main

import (
	"context"
	"errors"
	"net/http"
	"slices"
	"time"

	"github.com/jackc/pgx/v5"

	"github.com/CollinsWoelinam/Radian/backend/internal/track"
)

type vehiclePosition struct {
	geoPoint
	SpeedKmh   *float64  `json:"speed_kmh,omitempty"`
	HeadingDeg *float64  `json:"heading_deg,omitempty"`
	AccuracyM  *float64  `json:"accuracy_m,omitempty"`
	BatteryPct *int      `json:"battery_pct,omitempty"`
	RecordedAt time.Time `json:"recorded_at"`
}

type vehicleDetail struct {
	ID           string           `json:"id"`
	LicensePlate string           `json:"license_plate"`
	Kind         string           `json:"kind"`
	Status       string           `json:"status"`
	DriverName   string           `json:"driver_name,omitempty"`
	DriverPhone  string           `json:"driver_phone,omitempty"`
	Online       bool             `json:"online"`
	LastSeen     *time.Time       `json:"last_seen,omitempty"`
	Position     *vehiclePosition `json:"position,omitempty"`
	ShiftStarted *time.Time       `json:"shift_started_at,omitempty"`
	Job          *Job             `json:"job,omitempty"`
}

// GET /v1/vehicles/{id}: who drives it, where it is, its shift and current job.
func (a *app) handleVehicle(w http.ResponseWriter, r *http.Request) {
	ctx := r.Context()
	var (
		v                        vehicleDetail
		lat, lon, speed, heading *float64
		acc                      *float64
		battery                  *int
		fixAt                    *time.Time
	)
	err := a.pool.QueryRow(ctx, `
		SELECT v.id, v.license_plate, v.kind::text, v.status::text, COALESCE(d.full_name, ''), COALESCE(d.phone, ''),
		       ST_Y(lp.location), ST_X(lp.location), lp.speed_kmh, lp.heading_deg, lp.accuracy_m, lp.battery_pct, lp.recorded_at,
		       (SELECT started_at FROM shifts s WHERE s.vehicle_id = v.id AND s.ended_at IS NULL)
		FROM vehicles v
		LEFT JOIN vehicle_assignments va ON va.vehicle_id = v.id AND va.ended_at IS NULL
		LEFT JOIN drivers d ON d.id = va.driver_id
		LEFT JOIN vehicle_last_position lp ON lp.vehicle_id = v.id
		WHERE v.id = $1`, r.PathValue("id"),
	).Scan(&v.ID, &v.LicensePlate, &v.Kind, &v.Status, &v.DriverName, &v.DriverPhone,
		&lat, &lon, &speed, &heading, &acc, &battery, &fixAt, &v.ShiftStarted)
	if errors.Is(err, pgx.ErrNoRows) || isInvalidUUID(err) {
		writeError(w, http.StatusNotFound, "not_found", "Vehicle not found.")
		return
	}
	if err != nil {
		a.internal(w, "vehicle", err)
		return
	}
	if lat != nil && lon != nil && fixAt != nil {
		v.Position = &vehiclePosition{geoPoint: geoPoint{Lat: *lat, Lon: *lon}, SpeedKmh: speed, HeadingDeg: heading, AccuracyM: acc, BatteryPct: battery, RecordedAt: *fixAt}
		v.LastSeen = fixAt
	}
	if seen, err := a.presence(ctx); err == nil {
		if t, ok := seen[v.ID]; ok {
			v.LastSeen = &t
		}
	}
	v.Online = v.LastSeen != nil && time.Since(*v.LastSeen) < onlineWithin
	j, err := scanJob(a.pool.QueryRow(ctx, jobSelect+`
		WHERE j.assigned_vehicle_id = $1 AND j.status IN ('ASSIGNED', 'EN_ROUTE_PICKUP', 'ON_SITE', 'EN_ROUTE_DROPOFF')
		LIMIT 1`, v.ID))
	if err == nil {
		v.Job = &j
	}
	writeJSON(w, http.StatusOK, v)
}

// trackEvent is one line in a vehicle's day: from its movements, its jobs or
// its zones.
type trackEvent struct {
	Kind        string    `json:"kind"` // speeding | stop | no_signal | job | zone
	At          time.Time `json:"at"`
	DurationS   int       `json:"duration_s,omitempty"`
	Lat         float64   `json:"lat,omitempty"`
	Lon         float64   `json:"lon,omitempty"`
	MaxSpeedKmh float64   `json:"max_speed_kmh,omitempty"`
	JobNumber   int64     `json:"job_number,omitempty"`
	JobEvent    string    `json:"job_event,omitempty"` // accepted | ON_SITE | EN_ROUTE_DROPOFF | COMPLETED ...
	ZoneName    string    `json:"zone_name,omitempty"`
	ZoneKind    string    `json:"zone_kind,omitempty"`
	Entered     bool      `json:"entered,omitempty"`
	Dwell       bool      `json:"dwell,omitempty"`
	Alert       bool      `json:"alert,omitempty"`
}

type trackResponse struct {
	From          time.Time     `json:"from"`
	To            time.Time     `json:"to"`
	Summary       track.Summary `json:"summary"`
	JobsCompleted int           `json:"jobs_completed"`
	// [unix ms, lat, lon, speed km/h or -1], downsampled for drawing.
	Points [][4]float64 `json:"points"`
	Events []trackEvent `json:"events"`
}

const speedLimitKmh = 80

// loadTrack reads a vehicle's fixes in [from, to] and everything notable.
func (a *app) loadTrack(ctx context.Context, vehicleID string, from, to time.Time, maxPoints int) (trackResponse, error) {
	resp := trackResponse{From: from, To: to, Points: [][4]float64{}, Events: []trackEvent{}}
	rows, err := a.pool.Query(ctx, `
		SELECT recorded_at, ST_Y(location), ST_X(location), COALESCE(speed_kmh, -1), COALESCE(accuracy_m, -1)
		FROM vehicle_telemetry
		WHERE vehicle_id = $1 AND recorded_at BETWEEN $2 AND $3
		ORDER BY recorded_at LIMIT 100000`, vehicleID, from, to)
	if err != nil {
		return resp, err
	}
	pts, err := pgx.CollectRows(rows, func(row pgx.CollectableRow) (track.Point, error) {
		var p track.Point
		err := row.Scan(&p.At, &p.Lat, &p.Lon, &p.SpeedKmh, &p.AccuracyM)
		return p, err
	})
	if err != nil {
		return resp, err
	}
	resp.Summary = track.Summarize(pts)
	for _, p := range track.Downsample(pts, maxPoints) {
		resp.Points = append(resp.Points, [4]float64{float64(p.At.UnixMilli()), p.Lat, p.Lon, p.SpeedKmh})
	}
	for _, e := range track.Events(pts, speedLimitKmh, 2*time.Minute) {
		resp.Events = append(resp.Events, trackEvent{Kind: e.Kind, At: e.At, DurationS: e.DurationS, Lat: e.Lat, Lon: e.Lon, MaxSpeedKmh: e.MaxSpeedKmh})
	}

	rows, err = a.pool.Query(ctx, `
		SELECT e.at, j.number, CASE WHEN e.kind = 'status' THEN e.detail->>'to' ELSE e.kind END
		FROM job_events e JOIN jobs j ON j.id = e.job_id
		WHERE e.vehicle_id = $1 AND e.at BETWEEN $2 AND $3 AND e.kind IN ('accepted', 'status')
		ORDER BY e.at`, vehicleID, from, to)
	if err != nil {
		return resp, err
	}
	jobEvents, err := pgx.CollectRows(rows, func(row pgx.CollectableRow) (trackEvent, error) {
		e := trackEvent{Kind: "job"}
		err := row.Scan(&e.At, &e.JobNumber, &e.JobEvent)
		return e, err
	})
	if err != nil {
		return resp, err
	}
	for _, e := range jobEvents {
		if e.JobEvent == "COMPLETED" {
			resp.JobsCompleted++
		}
	}
	resp.Events = append(resp.Events, jobEvents...)

	rows, err = a.pool.Query(ctx, `
		SELECT e.occurred_at, g.name, g.kind::text, e.entered, e.dwell, e.alert, ST_Y(e.location), ST_X(e.location)
		FROM geofence_events e JOIN geofences g ON g.id = e.geofence_id
		WHERE e.vehicle_id = $1 AND e.occurred_at BETWEEN $2 AND $3
		ORDER BY e.occurred_at LIMIT 200`, vehicleID, from, to)
	if err != nil {
		return resp, err
	}
	zoneEvents, err := pgx.CollectRows(rows, func(row pgx.CollectableRow) (trackEvent, error) {
		e := trackEvent{Kind: "zone"}
		var lat, lon *float64
		err := row.Scan(&e.At, &e.ZoneName, &e.ZoneKind, &e.Entered, &e.Dwell, &e.Alert, &lat, &lon)
		if lat != nil && lon != nil {
			e.Lat, e.Lon = *lat, *lon
		}
		return e, err
	})
	if err != nil {
		return resp, err
	}
	resp.Events = append(resp.Events, zoneEvents...)
	slices.SortFunc(resp.Events, func(x, y trackEvent) int { return y.At.Compare(x.At) })
	return resp, nil
}

// window reads ?from= and ?to= (RFC 3339). By default: the vehicle's open
// shift, else the last 12 hours.
func (a *app) window(r *http.Request, vehicleID string) (time.Time, time.Time, bool) {
	to := time.Now()
	from := to.Add(-12 * time.Hour)
	q := r.URL.Query()
	if s := q.Get("to"); s != "" {
		t, err := time.Parse(time.RFC3339, s)
		if err != nil {
			return from, to, false
		}
		to = t
	}
	if s := q.Get("from"); s != "" {
		t, err := time.Parse(time.RFC3339, s)
		if err != nil {
			return from, to, false
		}
		from = t
	} else {
		var started time.Time
		if a.pool.QueryRow(r.Context(), `SELECT started_at FROM shifts WHERE vehicle_id = $1 AND ended_at IS NULL`, vehicleID).Scan(&started) == nil {
			from = started
		}
	}
	return from, to, !to.Before(from) && to.Sub(from) <= 7*24*time.Hour
}

// GET /v1/vehicles/{id}/track?from=&to=: the route, its summary and events.
func (a *app) handleVehicleTrack(w http.ResponseWriter, r *http.Request) {
	id := r.PathValue("id")
	from, to, ok := a.window(r, id)
	if !ok {
		writeError(w, http.StatusBadRequest, "invalid_window", "Pick a time range of up to 7 days.")
		return
	}
	resp, err := a.loadTrack(r.Context(), id, from, to, 3000)
	if isInvalidUUID(err) {
		writeError(w, http.StatusNotFound, "not_found", "Vehicle not found.")
		return
	}
	if err != nil {
		a.internal(w, "vehicle track", err)
		return
	}
	writeJSON(w, http.StatusOK, resp)
}
