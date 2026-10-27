package main

import (
	"encoding/json"
	"errors"
	"net/http"
	"strconv"
	"time"

	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgconn"

	"github.com/CollinsWoelinam/Radian/backend/internal/track"
)

func isInvalidUUID(err error) bool {
	var pgErr *pgconn.PgError
	return errors.As(err, &pgErr) && pgErr.Code == "22P02"
}

type shift struct {
	ID            string     `json:"id"`
	StartedAt     time.Time  `json:"started_at"`
	EndedAt       *time.Time `json:"ended_at,omitempty"`
	DistanceM     *float64   `json:"distance_m,omitempty"`
	DrivingS      *int       `json:"driving_s,omitempty"`
	JobsCompleted *int       `json:"jobs_completed,omitempty"`
}

type shiftJob struct {
	Number         int64     `json:"number"`
	PickupAddress  string    `json:"pickup_address"`
	DropoffAddress string    `json:"dropoff_address,omitempty"`
	CompletedAt    time.Time `json:"completed_at"`
}

type shiftDetail struct {
	shift
	Summary track.Summary `json:"summary"`
	Points  [][4]float64  `json:"points"` // [unix ms, lat, lon, speed]
	Jobs    []shiftJob    `json:"jobs"`
}

const shiftColumns = `id, started_at, ended_at, distance_m, driving_s, jobs_completed`

func scanShift(row pgx.Row) (shift, error) {
	var s shift
	err := row.Scan(&s.ID, &s.StartedAt, &s.EndedAt, &s.DistanceM, &s.DrivingS, &s.JobsCompleted)
	return s, err
}

type shiftTimes struct {
	StartedAt *time.Time `json:"started_at"`
	EndedAt   *time.Time `json:"ended_at"`
}

func readShiftTimes(w http.ResponseWriter, r *http.Request) (shiftTimes, bool) {
	var t shiftTimes
	if r.ContentLength != 0 {
		if err := json.NewDecoder(http.MaxBytesReader(w, r.Body, 4<<10)).Decode(&t); err != nil {
			writeError(w, http.StatusBadRequest, "invalid_request", "Expected shift times.")
			return t, false
		}
	}
	now := time.Now()
	for _, p := range []*time.Time{t.StartedAt, t.EndedAt} {
		if p != nil && (p.After(now.Add(5*time.Minute)) || p.Before(now.Add(-7*24*time.Hour))) {
			writeError(w, http.StatusBadRequest, "invalid_time", "Shift times must be within the last week.")
			return t, false
		}
	}
	return t, true
}

// POST /v1/driver/shifts/start: opens a shift (idempotent: an open shift is returned as is).
func (a *app) handleShiftStart(w http.ResponseWriter, r *http.Request) {
	t, ok := readShiftTimes(w, r)
	if !ok {
		return
	}
	started := time.Now()
	if t.StartedAt != nil {
		started = *t.StartedAt
	}
	s, err := scanShift(a.pool.QueryRow(r.Context(), `
		WITH ins AS (
			INSERT INTO shifts (vehicle_id, driver_id, started_at)
			SELECT $1, (SELECT driver_id FROM vehicle_assignments WHERE vehicle_id = $1 AND ended_at IS NULL), $2
			WHERE NOT EXISTS (SELECT 1 FROM shifts WHERE vehicle_id = $1 AND ended_at IS NULL)
			RETURNING `+shiftColumns+`
		)
		SELECT `+shiftColumns+` FROM ins
		UNION ALL
		SELECT `+shiftColumns+` FROM shifts WHERE vehicle_id = $1 AND ended_at IS NULL
		LIMIT 1`, subject(r), started))
	if err != nil {
		a.internal(w, "start shift", err)
		return
	}
	writeJSON(w, http.StatusOK, s)
}

// POST /v1/driver/shifts/end: closes the open shift and stores its summary.
// A shift whose start never reached the server (no signal) is created from
// the started_at the app sends.
func (a *app) handleShiftEnd(w http.ResponseWriter, r *http.Request) {
	t, ok := readShiftTimes(w, r)
	if !ok {
		return
	}
	ctx := r.Context()
	vehicleID := subject(r)
	ended := time.Now()
	if t.EndedAt != nil {
		ended = *t.EndedAt
	}
	var id string
	var started time.Time
	err := a.pool.QueryRow(ctx, `SELECT id, started_at FROM shifts WHERE vehicle_id = $1 AND ended_at IS NULL`, vehicleID).Scan(&id, &started)
	if errors.Is(err, pgx.ErrNoRows) {
		if t.StartedAt == nil {
			writeError(w, http.StatusConflict, "no_shift", "There is no shift to end.")
			return
		}
		started = *t.StartedAt
		err = a.pool.QueryRow(ctx, `
			INSERT INTO shifts (vehicle_id, driver_id, started_at)
			VALUES ($1, (SELECT driver_id FROM vehicle_assignments WHERE vehicle_id = $1 AND ended_at IS NULL), $2)
			RETURNING id`, vehicleID, started).Scan(&id)
	}
	if err != nil {
		a.internal(w, "end shift", err)
		return
	}
	if ended.Before(started) {
		ended = started
	}
	tr, err := a.loadTrack(ctx, vehicleID, started, ended, 400)
	if err != nil {
		a.internal(w, "shift track", err)
		return
	}
	if _, err := a.pool.Exec(ctx, `
		UPDATE shifts SET ended_at = $2, distance_m = $3, driving_s = $4, jobs_completed = $5 WHERE id = $1`,
		id, ended, tr.Summary.DistanceM, tr.Summary.DrivingS, tr.JobsCompleted); err != nil {
		a.internal(w, "close shift", err)
		return
	}
	a.writeShiftDetail(w, r, id)
}

// GET /v1/driver/shifts?limit=20: this vehicle's recent shifts.
func (a *app) handleShifts(w http.ResponseWriter, r *http.Request) {
	limit, _ := strconv.Atoi(r.URL.Query().Get("limit"))
	if limit <= 0 || limit > 100 {
		limit = 20
	}
	rows, err := a.pool.Query(r.Context(), `SELECT `+shiftColumns+` FROM shifts WHERE vehicle_id = $1 ORDER BY started_at DESC LIMIT $2`, subject(r), limit)
	if err != nil {
		a.internal(w, "shifts", err)
		return
	}
	list, err := pgx.CollectRows(rows, func(row pgx.CollectableRow) (shift, error) { return scanShift(row) })
	if err != nil {
		a.internal(w, "shifts", err)
		return
	}
	if list == nil {
		list = []shift{}
	}
	writeJSON(w, http.StatusOK, list)
}

// GET /v1/driver/shifts/{id}: one shift with its route and jobs.
func (a *app) handleShift(w http.ResponseWriter, r *http.Request) {
	a.writeShiftDetail(w, r, r.PathValue("id"))
}

func (a *app) writeShiftDetail(w http.ResponseWriter, r *http.Request, id string) {
	ctx := r.Context()
	vehicleID := subject(r)
	s, err := scanShift(a.pool.QueryRow(ctx, `SELECT `+shiftColumns+` FROM shifts WHERE id = $1 AND vehicle_id = $2`, id, vehicleID))
	if errors.Is(err, pgx.ErrNoRows) || isInvalidUUID(err) {
		writeError(w, http.StatusNotFound, "not_found", "Shift not found.")
		return
	}
	if err != nil {
		a.internal(w, "shift", err)
		return
	}
	end := time.Now()
	if s.EndedAt != nil {
		end = *s.EndedAt
	}
	tr, err := a.loadTrack(ctx, vehicleID, s.StartedAt, end, 400)
	if err != nil {
		a.internal(w, "shift track", err)
		return
	}
	rows, err := a.pool.Query(ctx, `
		SELECT number, COALESCE(pickup_address, ''), COALESCE(dropoff_address, ''), completed_at
		FROM jobs WHERE assigned_vehicle_id = $1 AND status = 'COMPLETED' AND completed_at BETWEEN $2 AND $3
		ORDER BY completed_at DESC`, vehicleID, s.StartedAt, end)
	if err != nil {
		a.internal(w, "shift jobs", err)
		return
	}
	jobs, err := pgx.CollectRows(rows, func(row pgx.CollectableRow) (shiftJob, error) {
		var j shiftJob
		err := row.Scan(&j.Number, &j.PickupAddress, &j.DropoffAddress, &j.CompletedAt)
		return j, err
	})
	if err != nil {
		a.internal(w, "shift jobs", err)
		return
	}
	if jobs == nil {
		jobs = []shiftJob{}
	}
	writeJSON(w, http.StatusOK, shiftDetail{shift: s, Summary: tr.Summary, Points: tr.Points, Jobs: jobs})
}
