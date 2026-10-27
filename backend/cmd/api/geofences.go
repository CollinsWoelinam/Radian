package main

import (
	"encoding/json"
	"errors"
	"net/http"
	"strconv"
	"strings"
	"time"

	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgconn"
	"github.com/redis/go-redis/v9"

	"github.com/CollinsWoelinam/Radian/backend/internal/geo"
	"github.com/CollinsWoelinam/Radian/backend/internal/stream"
)

var geofenceKinds = map[string]bool{"DEPOT": true, "SERVICE_AREA": true, "RESTRICTED": true}

type Geofence struct {
	ID             string           `json:"id"`
	Name           string           `json:"name"`
	Kind           string           `json:"kind"`
	Area           geo.MultiPolygon `json:"area"` // GeoJSON MultiPolygon coordinates
	AreaKm2        float64          `json:"area_km2"`
	VehiclesInside int64            `json:"vehicles_inside"`
	CreatedAt      time.Time        `json:"created_at"`
	AlertRules
}

// AlertRules decide which crossings of a zone raise an alert.
type AlertRules struct {
	AlertOnEnter bool `json:"alert_on_enter"`
	AlertOnExit  bool `json:"alert_on_exit"`
	DwellAlertS  *int `json:"dwell_alert_s"` // alert after this long inside; null = off
}

// defaultRules match what each kind of zone is for.
func defaultRules(kind string) AlertRules {
	return AlertRules{AlertOnEnter: kind == "RESTRICTED", AlertOnExit: kind == "SERVICE_AREA"}
}

func validDwell(s *int) bool { return s == nil || (*s >= 30 && *s <= 86400) }

const geofenceSelect = `
	SELECT id, name, kind::text, ST_AsGeoJSON(area, 6)::json -> 'coordinates',
	       ST_Area(area::geography) / 1e6, created_at, alert_on_enter, alert_on_exit, dwell_alert_s
	FROM geofences`

func (a *app) scanGeofences(r *http.Request, rows pgx.Rows) ([]Geofence, error) {
	out, err := pgx.CollectRows(rows, func(row pgx.CollectableRow) (Geofence, error) {
		var g Geofence
		err := row.Scan(&g.ID, &g.Name, &g.Kind, &g.Area, &g.AreaKm2, &g.CreatedAt, &g.AlertOnEnter, &g.AlertOnExit, &g.DwellAlertS)
		return g, err
	})
	if err != nil {
		return nil, err
	}
	// Live membership is kept by the geofencer; counting is best effort.
	pipe := a.rdb.Pipeline()
	counts := make([]*redis.IntCmd, len(out))
	for i, g := range out {
		counts[i] = pipe.SCard(r.Context(), stream.InsideKey(g.ID))
	}
	if _, err := pipe.Exec(r.Context()); err == nil {
		for i := range out {
			out[i].VehiclesInside = counts[i].Val()
		}
	}
	return out, nil
}

// GET /v1/geofences
func (a *app) handleListGeofences(w http.ResponseWriter, r *http.Request) {
	rows, err := a.pool.Query(r.Context(), geofenceSelect+` ORDER BY kind, name`)
	if err != nil {
		a.internal(w, "list geofences", err)
		return
	}
	fences, err := a.scanGeofences(r, rows)
	if err != nil {
		a.internal(w, "scan geofences", err)
		return
	}
	writeJSON(w, http.StatusOK, fences)
}

type createGeofenceRequest struct {
	Name    string       `json:"name"`
	Kind    string       `json:"kind"`
	Polygon [][2]float64 `json:"polygon"` // [lon, lat] vertices, open or closed
	Rules   *AlertRules  `json:"rules"`   // omitted: the kind's defaults
}

// POST /v1/geofences draws a zone from a single outline.
func (a *app) handleCreateGeofence(w http.ResponseWriter, r *http.Request) {
	var req createGeofenceRequest
	if err := json.NewDecoder(http.MaxBytesReader(w, r.Body, 64<<10)).Decode(&req); err != nil {
		writeError(w, http.StatusBadRequest, "invalid_request", "Expected a JSON zone.")
		return
	}
	req.Name = strings.TrimSpace(req.Name)
	ring := closeRing(req.Polygon)
	switch {
	case req.Name == "" || len(req.Name) > 100:
		writeError(w, http.StatusBadRequest, "invalid_name", "Give the zone a name (up to 100 characters).")
		return
	case !geofenceKinds[req.Kind]:
		writeError(w, http.StatusBadRequest, "invalid_kind", "Choose depot, service area or restricted.")
		return
	case len(ring) < 4 || len(ring) > 501:
		writeError(w, http.StatusBadRequest, "invalid_polygon", "A zone needs between 3 and 500 corners.")
		return
	}
	rules := defaultRules(req.Kind)
	if req.Rules != nil {
		rules = *req.Rules
	}
	if !validDwell(rules.DwellAlertS) {
		writeError(w, http.StatusBadRequest, "invalid_dwell", "The time limit must be between 30 seconds and 24 hours.")
		return
	}
	for _, p := range ring {
		if p[0] < -180 || p[0] > 180 || p[1] < -90 || p[1] > 90 {
			writeError(w, http.StatusBadRequest, "invalid_polygon", "A corner is outside the map.")
			return
		}
	}
	shape, _ := json.Marshal(map[string]any{"type": "Polygon", "coordinates": [][][2]float64{ring}})

	var valid bool
	var reason string
	if err := a.pool.QueryRow(r.Context(),
		`SELECT ST_IsValid(g), ST_IsValidReason(g) FROM ST_SetSRID(ST_GeomFromGeoJSON($1), 4326) g`, shape,
	).Scan(&valid, &reason); err != nil {
		writeError(w, http.StatusBadRequest, "invalid_polygon", "That outline isn't a valid shape.")
		return
	}
	if !valid {
		a.log.Info("rejected geofence", "reason", reason)
		writeError(w, http.StatusBadRequest, "invalid_polygon", "The zone's edges cross each other. Redraw it without crossing lines.")
		return
	}

	rows, err := a.pool.Query(r.Context(), `
		WITH g AS (
			INSERT INTO geofences (name, kind, area, created_by, alert_on_enter, alert_on_exit, dwell_alert_s)
			VALUES ($1, $2, ST_Multi(ST_SetSRID(ST_GeomFromGeoJSON($3), 4326)), $4, $5, $6, $7)
			RETURNING *
		)
		SELECT id, name, kind::text, ST_AsGeoJSON(area, 6)::json -> 'coordinates',
		       ST_Area(area::geography) / 1e6, created_at, alert_on_enter, alert_on_exit, dwell_alert_s FROM g`,
		req.Name, req.Kind, shape, subject(r), rules.AlertOnEnter, rules.AlertOnExit, rules.DwellAlertS)
	if err != nil {
		a.internal(w, "insert geofence", err)
		return
	}
	fences, err := a.scanGeofences(r, rows)
	if err != nil {
		a.internal(w, "insert geofence", err)
		return
	}
	a.dispatch.notify.GeofencesChanged(r.Context())
	writeJSON(w, http.StatusCreated, fences[0])
}

func closeRing(pts [][2]float64) [][2]float64 {
	if len(pts) > 0 && pts[0] != pts[len(pts)-1] {
		pts = append(pts, pts[0])
	}
	return pts
}

// PUT /v1/geofences/{id}/rules replaces a zone's alert rules.
func (a *app) handleUpdateGeofenceRules(w http.ResponseWriter, r *http.Request) {
	var rules AlertRules
	if err := json.NewDecoder(http.MaxBytesReader(w, r.Body, 4<<10)).Decode(&rules); err != nil {
		writeError(w, http.StatusBadRequest, "invalid_request", "Expected the zone's alert rules.")
		return
	}
	if !validDwell(rules.DwellAlertS) {
		writeError(w, http.StatusBadRequest, "invalid_dwell", "The time limit must be between 30 seconds and 24 hours.")
		return
	}
	rows, err := a.pool.Query(r.Context(), `
		WITH g AS (
			UPDATE geofences SET alert_on_enter = $2, alert_on_exit = $3, dwell_alert_s = $4
			WHERE id = $1 RETURNING *
		)
		SELECT id, name, kind::text, ST_AsGeoJSON(area, 6)::json -> 'coordinates',
		       ST_Area(area::geography) / 1e6, created_at, alert_on_enter, alert_on_exit, dwell_alert_s FROM g`,
		r.PathValue("id"), rules.AlertOnEnter, rules.AlertOnExit, rules.DwellAlertS)
	if err != nil {
		a.internal(w, "update geofence rules", err)
		return
	}
	fences, err := a.scanGeofences(r, rows)
	if err != nil {
		a.internal(w, "update geofence rules", err)
		return
	}
	if len(fences) == 0 {
		writeError(w, http.StatusNotFound, "not_found", "Zone not found.")
		return
	}
	a.dispatch.notify.GeofencesChanged(r.Context())
	writeJSON(w, http.StatusOK, fences[0])
}

// DELETE /v1/geofences/{id}
func (a *app) handleDeleteGeofence(w http.ResponseWriter, r *http.Request) {
	tag, err := a.pool.Exec(r.Context(), `DELETE FROM geofences WHERE id = $1`, r.PathValue("id"))
	var pgErr *pgconn.PgError
	if errors.As(err, &pgErr) && pgErr.Code == "22P02" { // not a UUID
		tag, err = pgconn.CommandTag{}, nil
	}
	if err != nil {
		a.internal(w, "delete geofence", err)
		return
	}
	if tag.RowsAffected() == 0 {
		writeError(w, http.StatusNotFound, "not_found", "Zone not found.")
		return
	}
	a.rdb.Del(r.Context(), stream.InsideKey(r.PathValue("id")))
	a.dispatch.notify.GeofencesChanged(r.Context())
	w.WriteHeader(http.StatusNoContent)
}

type geofenceEvent struct {
	ID           int64     `json:"id"`
	GeofenceID   string    `json:"geofence_id"`
	GeofenceName string    `json:"geofence_name"`
	Kind         string    `json:"kind"`
	VehicleID    string    `json:"vehicle_id"`
	LicensePlate string    `json:"license_plate"`
	Entered      bool      `json:"entered"`
	Dwell        bool      `json:"dwell"`
	Alert        bool      `json:"alert"`
	OccurredAt   time.Time `json:"occurred_at"`
	Position     *geoPoint `json:"position,omitempty"`
}

// GET /v1/geofence-events?limit=50: the newest crossings, for the alert feed.
func (a *app) handleGeofenceEvents(w http.ResponseWriter, r *http.Request) {
	limit, _ := strconv.Atoi(r.URL.Query().Get("limit"))
	if limit <= 0 || limit > 200 {
		limit = 50
	}
	rows, err := a.pool.Query(r.Context(), `
		SELECT e.id, g.id, g.name, g.kind::text, v.id, v.license_plate, e.entered, e.dwell, e.alert, e.occurred_at,
		       ST_Y(e.location), ST_X(e.location)
		FROM geofence_events e
		JOIN geofences g ON g.id = e.geofence_id
		JOIN vehicles v ON v.id = e.vehicle_id
		ORDER BY e.occurred_at DESC, e.id DESC
		LIMIT $1`, limit)
	if err != nil {
		a.internal(w, "geofence events", err)
		return
	}
	events, err := pgx.CollectRows(rows, func(row pgx.CollectableRow) (geofenceEvent, error) {
		var (
			e        geofenceEvent
			lat, lon *float64
		)
		err := row.Scan(&e.ID, &e.GeofenceID, &e.GeofenceName, &e.Kind, &e.VehicleID, &e.LicensePlate,
			&e.Entered, &e.Dwell, &e.Alert, &e.OccurredAt, &lat, &lon)
		if lat != nil && lon != nil {
			e.Position = &geoPoint{Lat: *lat, Lon: *lon}
		}
		return e, err
	})
	if err != nil {
		a.internal(w, "scan geofence events", err)
		return
	}
	writeJSON(w, http.StatusOK, events)
}
