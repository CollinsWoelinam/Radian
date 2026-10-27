package main

import (
	"context"
	"net/http"
	"strconv"
	"time"

	"github.com/jackc/pgx/v5"

	"github.com/CollinsWoelinam/Radian/backend/internal/stream"
)

// onlineWithin is how recently a phone must have been heard from to count as
// online, the same window dispatch uses.
const onlineWithin = 2 * time.Minute

type overview struct {
	Online         int  `json:"online"`
	Vehicles       int  `json:"vehicles"`
	ActiveJobs     int  `json:"active_jobs"`
	WaitingJobs    int  `json:"waiting_jobs"`
	CompletedToday int  `json:"completed_today"`
	MedianPickupS  *int `json:"median_pickup_s"` // accepted → at pickup, last hour
	AlertsLastHour int  `json:"alerts_last_hour"`
}

// presence returns vehicle ID -> last heard from, per the ingest service.
func (a *app) presence(ctx context.Context) (map[string]time.Time, error) {
	raw, err := a.rdb.HGetAll(ctx, stream.PresenceKey).Result()
	if err != nil {
		return nil, err
	}
	out := make(map[string]time.Time, len(raw))
	for id, v := range raw {
		if ms, err := strconv.ParseInt(v, 10, 64); err == nil {
			out[id] = time.UnixMilli(ms)
		}
	}
	return out, nil
}

// GET /v1/overview: the numbers across the top of the live map.
func (a *app) handleOverview(w http.ResponseWriter, r *http.Request) {
	var o overview
	var median *float64
	err := a.pool.QueryRow(r.Context(), `
		WITH accepted AS (
			SELECT job_id, min(at) AS at FROM job_events WHERE kind = 'accepted' GROUP BY job_id
		), arrived AS (
			SELECT job_id, min(at) AS at FROM job_events
			WHERE kind = 'status' AND detail->>'to' = 'ON_SITE' AND at > now() - interval '1 hour'
			GROUP BY job_id
		)
		SELECT
			(SELECT count(*) FROM vehicles),
			(SELECT count(*) FROM jobs WHERE status IN ('ASSIGNED', 'EN_ROUTE_PICKUP', 'ON_SITE', 'EN_ROUTE_DROPOFF')),
			(SELECT count(*) FROM jobs WHERE status IN ('PENDING', 'OFFERED')),
			(SELECT count(*) FROM jobs WHERE status = 'COMPLETED' AND completed_at >= date_trunc('day', now())),
			(SELECT percentile_cont(0.5) WITHIN GROUP (ORDER BY extract(epoch FROM arrived.at - accepted.at))
			   FROM arrived JOIN accepted USING (job_id)),
			(SELECT count(*) FROM geofence_events WHERE alert AND occurred_at > now() - interval '1 hour')`,
	).Scan(&o.Vehicles, &o.ActiveJobs, &o.WaitingJobs, &o.CompletedToday, &median, &o.AlertsLastHour)
	if err != nil {
		a.internal(w, "overview", err)
		return
	}
	if median != nil {
		s := int(*median)
		o.MedianPickupS = &s
	}
	if seen, err := a.presence(r.Context()); err == nil {
		for _, t := range seen {
			if time.Since(t) < onlineWithin {
				o.Online++
			}
		}
	}
	writeJSON(w, http.StatusOK, o)
}

type attentionItem struct {
	Kind       string     `json:"kind"` // offer_expiring | no_driver | zone_alert | offline_on_job
	At         time.Time  `json:"at"`
	JobID      string     `json:"job_id,omitempty"`
	JobNumber  int64      `json:"job_number,omitempty"`
	Place      string     `json:"place,omitempty"`
	VehicleID  string     `json:"vehicle_id,omitempty"`
	Plate      string     `json:"license_plate,omitempty"`
	DriverName string     `json:"driver_name,omitempty"`
	ZoneName   string     `json:"zone_name,omitempty"`
	ZoneKind   string     `json:"zone_kind,omitempty"`
	Entered    bool       `json:"entered,omitempty"`
	Dwell      bool       `json:"dwell,omitempty"`
	ExpiresAt  *time.Time `json:"expires_at,omitempty"`
	Declines   int        `json:"declines,omitempty"`
}

// GET /v1/attention: what a dispatcher should look at now, most urgent first.
func (a *app) handleAttention(w http.ResponseWriter, r *http.Request) {
	ctx := r.Context()
	var items []attentionItem
	collect := func(sql string, scan func(pgx.CollectableRow) (attentionItem, error), args ...any) bool {
		rows, err := a.pool.Query(ctx, sql, args...)
		if err == nil {
			var got []attentionItem
			got, err = pgx.CollectRows(rows, scan)
			items = append(items, got...)
		}
		if err != nil {
			a.internal(w, "attention", err)
			return false
		}
		return true
	}

	// Offers waiting on a driver's answer.
	if !collect(`
		SELECT j.id, j.number, COALESCE(j.pickup_address, ''), v.id, v.license_plate, j.offer_expires_at, j.offered_at
		FROM jobs j JOIN vehicles v ON v.id = j.offered_vehicle_id
		WHERE j.status = 'OFFERED' ORDER BY j.offer_expires_at`,
		func(row pgx.CollectableRow) (attentionItem, error) {
			it := attentionItem{Kind: "offer_expiring"}
			err := row.Scan(&it.JobID, &it.JobNumber, &it.Place, &it.VehicleID, &it.Plate, &it.ExpiresAt, &it.At)
			return it, err
		}) {
		return
	}
	// Jobs nobody could be found for.
	if !collect(`
		SELECT id, number, COALESCE(pickup_address, ''), created_at, cardinality(declined_vehicle_ids)
		FROM jobs WHERE status = 'PENDING' AND created_at < now() - interval '30 seconds'
		ORDER BY priority, created_at LIMIT 10`,
		func(row pgx.CollectableRow) (attentionItem, error) {
			it := attentionItem{Kind: "no_driver"}
			err := row.Scan(&it.JobID, &it.JobNumber, &it.Place, &it.At, &it.Declines)
			return it, err
		}) {
		return
	}
	// Recent zone alerts.
	if !collect(`
		SELECT v.id, v.license_plate, g.name, g.kind::text, e.entered, e.dwell, e.occurred_at
		FROM geofence_events e JOIN geofences g ON g.id = e.geofence_id JOIN vehicles v ON v.id = e.vehicle_id
		WHERE e.alert AND e.occurred_at > now() - interval '15 minutes'
		ORDER BY e.occurred_at DESC LIMIT 5`,
		func(row pgx.CollectableRow) (attentionItem, error) {
			it := attentionItem{Kind: "zone_alert"}
			err := row.Scan(&it.VehicleID, &it.Plate, &it.ZoneName, &it.ZoneKind, &it.Entered, &it.Dwell, &it.At)
			return it, err
		}) {
		return
	}

	// Drivers on a job whose phone has gone quiet.
	seen, err := a.presence(ctx)
	if err == nil {
		rows, err := a.pool.Query(ctx, `
			SELECT j.id, j.number, v.id, v.license_plate, COALESCE(d.full_name, ''), lp.recorded_at
			FROM jobs j JOIN vehicles v ON v.id = j.assigned_vehicle_id
			LEFT JOIN vehicle_assignments va ON va.vehicle_id = v.id AND va.ended_at IS NULL
			LEFT JOIN drivers d ON d.id = va.driver_id
			LEFT JOIN vehicle_last_position lp ON lp.vehicle_id = v.id
			WHERE j.status IN ('ASSIGNED', 'EN_ROUTE_PICKUP', 'ON_SITE', 'EN_ROUTE_DROPOFF')`)
		if err == nil {
			for rows.Next() {
				var it attentionItem
				var lastFix *time.Time
				if rows.Scan(&it.JobID, &it.JobNumber, &it.VehicleID, &it.Plate, &it.DriverName, &lastFix) != nil {
					continue
				}
				last, ok := seen[it.VehicleID]
				if !ok && lastFix != nil {
					last, ok = *lastFix, true
				}
				if !ok || time.Since(last) > onlineWithin {
					it.Kind = "offline_on_job"
					it.At = last
					items = append(items, it)
				}
			}
			rows.Close()
		}
	}
	if items == nil {
		items = []attentionItem{}
	}
	writeJSON(w, http.StatusOK, items)
}
