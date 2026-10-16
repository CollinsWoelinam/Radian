package main

import (
	"context"
	"encoding/json"
	"errors"
	"math"
	"net/http"
	"strings"
	"time"

	"github.com/jackc/pgx/v5"

	"github.com/CollinsWoelinam/Radian/backend/internal/osrm"
)

type geoPoint struct {
	Lat float64 `json:"lat"`
	Lon float64 `json:"lon"`
}

type jobVehicle struct {
	ID           string    `json:"id"`
	LicensePlate string    `json:"license_plate"`
	Kind         string    `json:"kind"`
	DriverName   string    `json:"driver_name"`
	Position     *geoPoint `json:"position,omitempty"`
}

type Job struct {
	ID             string      `json:"id"`
	Number         int64       `json:"number"`
	Status         string      `json:"status"`
	Priority       int         `json:"priority"`
	Pickup         geoPoint    `json:"pickup"`
	PickupAddress  string      `json:"pickup_address"`
	Dropoff        *geoPoint   `json:"dropoff,omitempty"`
	DropoffAddress string      `json:"dropoff_address,omitempty"`
	Notes          string      `json:"notes,omitempty"`
	EtaSeconds     *int        `json:"eta_seconds,omitempty"`
	Vehicle        *jobVehicle `json:"vehicle,omitempty"` // assigned, or currently offered
	OfferExpiresAt *time.Time  `json:"offer_expires_at,omitempty"`
	Declines       int         `json:"declines"`
	CreatedAt      time.Time   `json:"created_at"`
	AssignedAt     *time.Time  `json:"assigned_at,omitempty"`
	CompletedAt    *time.Time  `json:"completed_at,omitempty"`
	UpdatedAt      time.Time   `json:"updated_at"`
}

const jobSelect = `
	SELECT j.id, j.number, j.status::text, j.priority,
	       ST_Y(j.pickup), ST_X(j.pickup), COALESCE(j.pickup_address, ''),
	       ST_Y(j.dropoff), ST_X(j.dropoff), COALESCE(j.dropoff_address, ''), COALESCE(j.notes, ''),
	       j.eta_seconds, j.offer_expires_at, cardinality(j.declined_vehicle_ids),
	       j.created_at, j.assigned_at, j.completed_at, j.updated_at,
	       v.id, v.license_plate, v.kind::text, COALESCE(dr.full_name, ''),
	       ST_Y(lp.location), ST_X(lp.location)
	FROM jobs j
	LEFT JOIN vehicles v ON v.id = COALESCE(j.assigned_vehicle_id, j.offered_vehicle_id)
	LEFT JOIN vehicle_assignments va ON va.vehicle_id = v.id AND va.ended_at IS NULL
	LEFT JOIN drivers dr ON dr.id = va.driver_id
	LEFT JOIN vehicle_last_position lp ON lp.vehicle_id = v.id`

func scanJob(row pgx.Row) (Job, error) {
	var (
		j                  Job
		dLat, dLon         *float64
		vID, vPlate, vKind *string
		vDriver            *string
		vLat, vLon         *float64
	)
	err := row.Scan(&j.ID, &j.Number, &j.Status, &j.Priority,
		&j.Pickup.Lat, &j.Pickup.Lon, &j.PickupAddress,
		&dLat, &dLon, &j.DropoffAddress, &j.Notes,
		&j.EtaSeconds, &j.OfferExpiresAt, &j.Declines,
		&j.CreatedAt, &j.AssignedAt, &j.CompletedAt, &j.UpdatedAt,
		&vID, &vPlate, &vKind, &vDriver, &vLat, &vLon)
	if err != nil {
		return j, err
	}
	if dLat != nil && dLon != nil {
		j.Dropoff = &geoPoint{Lat: *dLat, Lon: *dLon}
	}
	if vID != nil {
		j.Vehicle = &jobVehicle{ID: *vID, LicensePlate: *vPlate, Kind: *vKind, DriverName: *vDriver}
		if vLat != nil && vLon != nil {
			j.Vehicle.Position = &geoPoint{Lat: *vLat, Lon: *vLon}
		}
	}
	return j, nil
}

// GET /v1/jobs?scope=active|recent
func (a *app) handleListJobs(w http.ResponseWriter, r *http.Request) {
	where := `WHERE j.status NOT IN ('COMPLETED', 'CANCELLED')`
	order := `ORDER BY j.priority, j.created_at`
	if r.URL.Query().Get("scope") == "recent" {
		where = `WHERE j.status IN ('COMPLETED', 'CANCELLED') AND j.updated_at > now() - interval '24 hours'`
		order = `ORDER BY j.updated_at DESC`
	}
	rows, err := a.pool.Query(r.Context(), jobSelect+" "+where+" "+order+" LIMIT 200")
	if err != nil {
		a.internal(w, "list jobs", err)
		return
	}
	defer rows.Close()
	jobs := []Job{}
	for rows.Next() {
		j, err := scanJob(rows)
		if err != nil {
			a.internal(w, "scan job", err)
			return
		}
		jobs = append(jobs, j)
	}
	writeJSON(w, http.StatusOK, jobs)
}

type createJobRequest struct {
	Pickup         *geoPoint `json:"pickup"`
	PickupAddress  string    `json:"pickup_address"`
	Dropoff        *geoPoint `json:"dropoff"`
	DropoffAddress string    `json:"dropoff_address"`
	Priority       int       `json:"priority"`
	Notes          string    `json:"notes"`
}

func validPoint(p *geoPoint) bool {
	return p != nil && p.Lat >= -90 && p.Lat <= 90 && p.Lon >= -180 && p.Lon <= 180 && !(p.Lat == 0 && p.Lon == 0)
}

// POST /v1/jobs creates a job and immediately tries to dispatch it.
func (a *app) handleCreateJob(w http.ResponseWriter, r *http.Request) {
	var req createJobRequest
	if err := json.NewDecoder(http.MaxBytesReader(w, r.Body, 16<<10)).Decode(&req); err != nil {
		writeError(w, http.StatusBadRequest, "invalid_request", "Expected a JSON job.")
		return
	}
	switch {
	case !validPoint(req.Pickup):
		writeError(w, http.StatusBadRequest, "invalid_pickup", "Choose a pickup point on the map.")
		return
	case req.Dropoff != nil && !validPoint(req.Dropoff):
		writeError(w, http.StatusBadRequest, "invalid_dropoff", "The drop-off point is invalid.")
		return
	case len(req.Notes) > 1000 || len(req.PickupAddress) > 300 || len(req.DropoffAddress) > 300:
		writeError(w, http.StatusBadRequest, "too_long", "Addresses or notes are too long.")
		return
	}
	if req.Priority < 1 || req.Priority > 5 {
		req.Priority = 3
	}

	tx, err := a.pool.Begin(r.Context())
	if err != nil {
		a.internal(w, "begin", err)
		return
	}
	defer tx.Rollback(r.Context())
	var dropoff any
	if req.Dropoff != nil {
		dropoff = []float64{req.Dropoff.Lon, req.Dropoff.Lat}
	}
	var id string
	err = tx.QueryRow(r.Context(), `
		INSERT INTO jobs (pickup, pickup_address, dropoff, dropoff_address, priority, notes, created_by)
		VALUES (ST_SetSRID(ST_MakePoint($1, $2), 4326), NULLIF($3, ''),
		        CASE WHEN $4::float8[] IS NULL THEN NULL ELSE ST_SetSRID(ST_MakePoint(($4::float8[])[1], ($4::float8[])[2]), 4326) END,
		        NULLIF($5, ''), $6, NULLIF($7, ''), $8)
		RETURNING id`,
		req.Pickup.Lon, req.Pickup.Lat, strings.TrimSpace(req.PickupAddress), dropoff,
		strings.TrimSpace(req.DropoffAddress), req.Priority, strings.TrimSpace(req.Notes), subject(r),
	).Scan(&id)
	if err != nil {
		a.internal(w, "insert job", err)
		return
	}
	if err := addEvent(r.Context(), tx, id, "created", "", map[string]any{"by": subject(r)}); err != nil {
		a.internal(w, "job event", err)
		return
	}
	if err := tx.Commit(r.Context()); err != nil {
		a.internal(w, "commit", err)
		return
	}

	a.dispatch.dispatchLogged(r.Context(), id)
	a.dispatch.notify.JobsChanged(r.Context(), id)
	j, err := scanJob(a.pool.QueryRow(r.Context(), jobSelect+" WHERE j.id = $1", id))
	if err != nil {
		a.internal(w, "reload job", err)
		return
	}
	writeJSON(w, http.StatusCreated, j)
}

type jobEvent struct {
	Kind      string         `json:"kind"`
	VehicleID *string        `json:"vehicle_id,omitempty"`
	Plate     *string        `json:"license_plate,omitempty"`
	Detail    map[string]any `json:"detail"`
	At        time.Time      `json:"at"`
}

type routeLeg struct {
	Kind        string       `json:"kind"` // to_pickup | to_dropoff
	DurationS   float64      `json:"duration_s"`
	DistanceM   float64      `json:"distance_m"`
	Coordinates [][2]float64 `json:"coordinates"`
}

type jobDetail struct {
	Job
	Events []jobEvent `json:"events"`
	Route  []routeLeg `json:"route"`
}

// GET /v1/jobs/{id}: the job, its timeline, and the live route for its current stage.
func (a *app) handleGetJob(w http.ResponseWriter, r *http.Request) {
	j, err := scanJob(a.pool.QueryRow(r.Context(), jobSelect+" WHERE j.id = $1", r.PathValue("id")))
	if errors.Is(err, pgx.ErrNoRows) {
		writeError(w, http.StatusNotFound, "not_found", "Job not found.")
		return
	}
	if err != nil {
		a.internal(w, "get job", err)
		return
	}
	rows, err := a.pool.Query(r.Context(), `
		SELECT e.kind, e.vehicle_id::text, v.license_plate, e.detail, e.at
		FROM job_events e LEFT JOIN vehicles v ON v.id = e.vehicle_id
		WHERE e.job_id = $1 ORDER BY e.at, e.id`, j.ID)
	if err != nil {
		a.internal(w, "job events", err)
		return
	}
	events, err := pgx.CollectRows(rows, func(row pgx.CollectableRow) (jobEvent, error) {
		var e jobEvent
		err := row.Scan(&e.Kind, &e.VehicleID, &e.Plate, &e.Detail, &e.At)
		return e, err
	})
	if err != nil {
		a.internal(w, "scan events", err)
		return
	}
	writeJSON(w, http.StatusOK, jobDetail{Job: j, Events: events, Route: a.routeFor(r.Context(), j)})
}

// routeFor returns the road route still ahead for the job's current stage.
// Routing is best effort: without OSRM the dashboard just shows the pins.
func (a *app) routeFor(ctx context.Context, j Job) []routeLeg {
	ctx, cancel := context.WithTimeout(ctx, 3*time.Second)
	defer cancel()
	pt := func(g geoPoint) osrm.Point { return osrm.Point{Lat: g.Lat, Lon: g.Lon} }
	leg := func(kind string, from, to geoPoint) *routeLeg {
		r, err := a.dispatch.osrm.Route(ctx, pt(from), pt(to))
		if err != nil {
			return nil
		}
		return &routeLeg{Kind: kind, DurationS: math.Round(r.DurationS), DistanceM: math.Round(r.DistanceM), Coordinates: r.Coordinates}
	}
	var legs []routeLeg
	add := func(l *routeLeg) {
		if l != nil {
			legs = append(legs, *l)
		}
	}
	var vehiclePos *geoPoint
	if j.Vehicle != nil {
		vehiclePos = j.Vehicle.Position
	}
	switch j.Status {
	case "OFFERED", "ASSIGNED", "EN_ROUTE_PICKUP":
		if vehiclePos != nil {
			add(leg("to_pickup", *vehiclePos, j.Pickup))
		}
		if j.Dropoff != nil {
			add(leg("to_dropoff", j.Pickup, *j.Dropoff))
		}
	case "ON_SITE", "EN_ROUTE_DROPOFF":
		if j.Dropoff != nil && vehiclePos != nil {
			add(leg("to_dropoff", *vehiclePos, *j.Dropoff))
		}
	case "PENDING":
		if j.Dropoff != nil {
			add(leg("to_dropoff", j.Pickup, *j.Dropoff))
		}
	}
	return legs
}

// GET /v1/jobs/{id}/candidates: available vehicles ranked by drive time.
func (a *app) handleJobCandidates(w http.ResponseWriter, r *http.Request) {
	tx, err := a.pool.Begin(r.Context())
	if err != nil {
		a.internal(w, "begin", err)
		return
	}
	defer tx.Rollback(r.Context())
	cands, err := a.dispatch.Candidates(r.Context(), tx, r.PathValue("id"), true)
	if err != nil {
		a.internal(w, "candidates", err)
		return
	}
	if cands == nil {
		cands = []Candidate{}
	}
	writeJSON(w, http.StatusOK, cands)
}

// POST /v1/jobs/{id}/offer {"vehicle_id": "..."}: the dispatcher picks the vehicle.
func (a *app) handleOfferJob(w http.ResponseWriter, r *http.Request) {
	var req struct {
		VehicleID string `json:"vehicle_id"`
	}
	if err := json.NewDecoder(http.MaxBytesReader(w, r.Body, 1<<10)).Decode(&req); err != nil || req.VehicleID == "" {
		writeError(w, http.StatusBadRequest, "invalid_request", "Choose a vehicle.")
		return
	}
	_, err := a.dispatch.Dispatch(r.Context(), r.PathValue("id"), req.VehicleID)
	switch {
	case errors.Is(err, errNotDispatchable):
		writeError(w, http.StatusConflict, "not_dispatchable", "This job already has a driver or is closed.")
	case err != nil:
		writeError(w, http.StatusConflict, "unavailable", "That vehicle can't take this job right now.")
	default:
		w.WriteHeader(http.StatusNoContent)
	}
}

// POST /v1/jobs/{id}/cancel {"reason": "..."}
func (a *app) handleCancelJob(w http.ResponseWriter, r *http.Request) {
	var req struct {
		Reason string `json:"reason"`
	}
	json.NewDecoder(http.MaxBytesReader(w, r.Body, 2<<10)).Decode(&req)
	err := a.dispatch.Cancel(r.Context(), r.PathValue("id"), subject(r), strings.TrimSpace(req.Reason))
	switch {
	case errors.Is(err, errNotDispatchable):
		writeError(w, http.StatusConflict, "closed", "This job is already finished.")
	case err != nil:
		a.internal(w, "cancel job", err)
	default:
		w.WriteHeader(http.StatusNoContent)
	}
}

// --- Driver ----------------------------------------------------------------

// GET /v1/driver/job: the live offer for this vehicle, or the job it's working on.
func (a *app) handleDriverCurrentJob(w http.ResponseWriter, r *http.Request) {
	j, err := scanJob(a.pool.QueryRow(r.Context(), jobSelect+`
		WHERE (j.status = 'OFFERED' AND j.offered_vehicle_id = $1 AND j.offer_expires_at > now())
		   OR (j.assigned_vehicle_id = $1 AND j.status IN ('ASSIGNED', 'EN_ROUTE_PICKUP', 'ON_SITE', 'EN_ROUTE_DROPOFF'))
		ORDER BY j.created_at DESC LIMIT 1`, subject(r)))
	if errors.Is(err, pgx.ErrNoRows) {
		w.WriteHeader(http.StatusNoContent)
		return
	}
	if err != nil {
		a.internal(w, "driver job", err)
		return
	}
	writeJSON(w, http.StatusOK, j)
}

func (a *app) handleDriverAccept(w http.ResponseWriter, r *http.Request) {
	a.driverAction(w, a.dispatch.Accept(r.Context(), r.PathValue("id"), subject(r)), "This offer has expired or was given to another driver.")
}

func (a *app) handleDriverDecline(w http.ResponseWriter, r *http.Request) {
	a.driverAction(w, a.dispatch.Decline(r.Context(), r.PathValue("id"), subject(r)), "This offer is no longer open.")
}

// POST /v1/driver/jobs/{id}/status {"status": "ON_SITE" | "EN_ROUTE_DROPOFF" | "COMPLETED"}
func (a *app) handleDriverStatus(w http.ResponseWriter, r *http.Request) {
	var req struct {
		Status string `json:"status"`
	}
	if err := json.NewDecoder(http.MaxBytesReader(w, r.Body, 1<<10)).Decode(&req); err != nil {
		writeError(w, http.StatusBadRequest, "invalid_request", "Expected a status.")
		return
	}
	err := a.dispatch.Progress(r.Context(), r.PathValue("id"), subject(r), req.Status)
	if errors.Is(err, errBadProgress) {
		writeError(w, http.StatusConflict, "bad_step", "That step doesn't apply to this job right now.")
		return
	}
	a.driverAction(w, err, "This job is no longer assigned to you.")
}

func (a *app) driverAction(w http.ResponseWriter, err error, gone string) {
	switch {
	case errors.Is(err, errNotYourJob):
		writeError(w, http.StatusConflict, "gone", gone)
	case err != nil:
		a.internal(w, "driver action", err)
	default:
		w.WriteHeader(http.StatusNoContent)
	}
}

func (a *app) internal(w http.ResponseWriter, what string, err error) {
	a.log.Error(what, "err", err)
	writeError(w, http.StatusInternalServerError, "internal", "Something went wrong. Try again.")
}
