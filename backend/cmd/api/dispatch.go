package main

import (
	"context"
	"errors"
	"fmt"
	"log/slog"
	"math"
	"slices"
	"time"

	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgxpool"

	pb "github.com/CollinsWoelinam/Radian/backend/gen/radian/telemetry/v1"
	"github.com/CollinsWoelinam/Radian/backend/internal/osrm"
)

// Dispatcher offers each job to the available vehicle that can reach the
// pickup soonest by road. An offer lasts offerTTL; a decline or timeout moves
// the job to the next-best vehicle. Jobs nobody can take are retried every
// retryEvery. Row locks (FOR UPDATE / SKIP LOCKED) make it safe to run several
// api instances.
type Dispatcher struct {
	log          *slog.Logger
	pool         *pgxpool.Pool
	notify       *Notifier
	osrm         *osrm.Client
	offerTTL     time.Duration
	retryEvery   time.Duration
	onlineWithin time.Duration
	maxRadiusM   float64
}

type Candidate struct {
	VehicleID    string  `json:"vehicle_id"`
	LicensePlate string  `json:"license_plate"`
	Kind         string  `json:"kind"`
	DriverName   string  `json:"driver_name"`
	Lat          float64 `json:"lat"`
	Lon          float64 `json:"lon"`
	StraightM    float64 `json:"straight_m"`
	EtaS         float64 `json:"eta_s"`
	RouteM       float64 `json:"route_m"`
	// "road" when ranked by OSRM drive time, "estimate" when OSRM was unavailable.
	EtaSource string `json:"eta_source"`
	Declined  bool   `json:"declined"`
}

// Without routing, assume ~25 km/h through the city and 30% detour over the crow-fly line.
const estimateSpeedMps, estimateDetour = 25.0 / 3.6, 1.3

// rank orders candidates by drive time. Vehicles OSRM can't route to are
// dropped; if the table call failed, ETAs fall back to a straight-line estimate.
func rank(cands []Candidate, table osrm.TableResult, tableErr error) []Candidate {
	out := make([]Candidate, 0, len(cands))
	for i, c := range cands {
		switch {
		case tableErr != nil || i >= len(table.DurationsS):
			c.EtaS = c.StraightM * estimateDetour / estimateSpeedMps
			c.RouteM = c.StraightM * estimateDetour
			c.EtaSource = "estimate"
		case table.DurationsS[i] < 0:
			continue // no road route (e.g. across water)
		default:
			c.EtaS, c.RouteM, c.EtaSource = table.DurationsS[i], table.DistancesM[i], "road"
		}
		out = append(out, c)
	}
	slices.SortStableFunc(out, func(a, b Candidate) int {
		// Vehicles that already declined go last; they're only offered on a manual pick.
		if a.Declined != b.Declined {
			if a.Declined {
				return 1
			}
			return -1
		}
		switch {
		case a.EtaS < b.EtaS:
			return -1
		case a.EtaS > b.EtaS:
			return 1
		}
		return 0
	})
	return out
}

// Candidates returns available vehicles near the job's pickup, best first.
// includeDeclined keeps vehicles that already turned this job down (for the
// dispatcher's manual pick list).
func (d *Dispatcher) Candidates(ctx context.Context, q pgx.Tx, jobID string, includeDeclined bool) ([]Candidate, error) {
	rows, err := q.Query(ctx, `
		SELECT v.id, v.license_plate, v.kind::text, COALESCE(dr.full_name, ''),
		       ST_Y(lp.location), ST_X(lp.location),
		       ST_Distance(lp.location::geography, j.pickup::geography),
		       v.id = ANY(j.declined_vehicle_ids)
		FROM jobs j
		JOIN vehicle_last_position lp ON ST_DWithin(lp.location::geography, j.pickup::geography, $2)
		JOIN vehicles v ON v.id = lp.vehicle_id
		JOIN vehicle_assignments va ON va.vehicle_id = v.id AND va.ended_at IS NULL
		JOIN drivers dr ON dr.id = va.driver_id
		WHERE j.id = $1
		  AND lp.recorded_at > now() - make_interval(secs => $3)
		  AND v.status <> 'ON_JOB'
		  AND ($4 OR NOT v.id = ANY(j.declined_vehicle_ids))
		  AND NOT EXISTS (
		      SELECT 1 FROM jobs o
		      WHERE o.id <> j.id
		        AND o.status IN ('OFFERED', 'ASSIGNED', 'EN_ROUTE_PICKUP', 'ON_SITE', 'EN_ROUTE_DROPOFF')
		        AND (o.assigned_vehicle_id = v.id OR o.offered_vehicle_id = v.id))
		ORDER BY lp.location <-> j.pickup
		LIMIT 10`,
		jobID, d.maxRadiusM, d.onlineWithin.Seconds(), includeDeclined)
	if err != nil {
		return nil, err
	}
	cands, err := pgx.CollectRows(rows, func(r pgx.CollectableRow) (Candidate, error) {
		var c Candidate
		err := r.Scan(&c.VehicleID, &c.LicensePlate, &c.Kind, &c.DriverName, &c.Lat, &c.Lon, &c.StraightM, &c.Declined)
		return c, err
	})
	if err != nil || len(cands) == 0 {
		return nil, err
	}

	var pickup osrm.Point
	if err := q.QueryRow(ctx, `SELECT ST_Y(pickup), ST_X(pickup) FROM jobs WHERE id = $1`, jobID).Scan(&pickup.Lat, &pickup.Lon); err != nil {
		return nil, err
	}
	sources := make([]osrm.Point, len(cands))
	for i, c := range cands {
		sources[i] = osrm.Point{Lat: c.Lat, Lon: c.Lon}
	}
	tctx, cancel := context.WithTimeout(ctx, 3*time.Second)
	defer cancel()
	table, terr := d.osrm.Table(tctx, sources, pickup)
	if terr != nil {
		d.log.Warn("osrm table failed; using straight-line estimates", "err", terr)
	}
	return rank(cands, table, terr), nil
}

var errNotDispatchable = errors.New("job is not waiting for a vehicle")

// Dispatch offers the job to the best available vehicle, or to vehicleID if
// given (a dispatcher's manual pick). Returns the vehicle offered, or "" if
// none is available right now.
func (d *Dispatcher) Dispatch(ctx context.Context, jobID, vehicleID string) (string, error) {
	tx, err := d.pool.Begin(ctx)
	if err != nil {
		return "", err
	}
	defer tx.Rollback(ctx)

	var status, prevOffered string
	err = tx.QueryRow(ctx, `
		SELECT status::text, COALESCE(offered_vehicle_id::text, '') FROM jobs
		WHERE id = $1 FOR UPDATE`, jobID).Scan(&status, &prevOffered)
	if errors.Is(err, pgx.ErrNoRows) {
		return "", errNotDispatchable
	}
	if err != nil {
		return "", err
	}
	if status != "PENDING" && !(status == "OFFERED" && vehicleID != "") {
		return "", errNotDispatchable
	}

	cands, err := d.Candidates(ctx, tx, jobID, vehicleID != "")
	if err != nil {
		return "", err
	}
	var pick *Candidate
	for i := range cands {
		if vehicleID == "" && !cands[i].Declined || cands[i].VehicleID == vehicleID {
			pick = &cands[i]
			break
		}
	}

	if pick == nil {
		if vehicleID != "" {
			return "", fmt.Errorf("vehicle %s is not available for this job", vehicleID)
		}
		// Record "no vehicle" once per dry spell, not on every retry.
		_, err = tx.Exec(ctx, `
			WITH upd AS (UPDATE jobs SET last_dispatch_at = now(), updated_at = now() WHERE id = $1)
			INSERT INTO job_events (job_id, kind)
			SELECT $1, 'no_vehicle'
			WHERE COALESCE((SELECT kind FROM job_events WHERE job_id = $1 ORDER BY at DESC, id DESC LIMIT 1), '') <> 'no_vehicle'`,
			jobID)
		if err != nil {
			return "", err
		}
		return "", tx.Commit(ctx)
	}

	var (
		offer      = pb.JobOffer{JobId: jobID, EtaSeconds: int32(math.Round(pick.EtaS))}
		pLat, pLon float64
		dLat, dLon *float64
		expires    time.Time
	)
	err = tx.QueryRow(ctx, `
		UPDATE jobs SET status = 'OFFERED', offered_vehicle_id = $2, offered_at = now(),
		       offer_expires_at = now() + make_interval(secs => $3), eta_seconds = $4,
		       last_dispatch_at = now(), updated_at = now()
		WHERE id = $1
		RETURNING number, ST_Y(pickup), ST_X(pickup), COALESCE(pickup_address, ''),
		          ST_Y(dropoff), ST_X(dropoff), dropoff_address, priority, COALESCE(notes, ''), offer_expires_at`,
		jobID, pick.VehicleID, d.offerTTL.Seconds(), offer.EtaSeconds,
	).Scan(&offer.Number, &pLat, &pLon, &offer.PickupAddress, &dLat, &dLon, &offer.DropoffAddress,
		&offer.Priority, &offer.Notes, &expires)
	if err != nil {
		return "", err
	}
	offer.Pickup = &pb.GeoPoint{Latitude: pLat, Longitude: pLon}
	if dLat != nil && dLon != nil {
		offer.Dropoff = &pb.GeoPoint{Latitude: *dLat, Longitude: *dLon}
	}
	offer.ExpiresAtMs = expires.UnixMilli()

	err = addEvent(ctx, tx, jobID, "offered", pick.VehicleID, map[string]any{
		"eta_s": offer.EtaSeconds, "route_m": math.Round(pick.RouteM), "eta_source": pick.EtaSource,
		"plate": pick.LicensePlate, "manual": vehicleID != "",
	})
	if err != nil {
		return "", err
	}
	if err := tx.Commit(ctx); err != nil {
		return "", err
	}

	if prevOffered != "" && prevOffered != pick.VehicleID {
		d.notify.Device(ctx, prevOffered, &pb.ServerMessage{Payload: &pb.ServerMessage_JobCancelled{
			JobCancelled: &pb.JobCancelled{JobId: jobID, Reason: "Reassigned by dispatch"},
		}})
	}
	d.notify.Device(ctx, pick.VehicleID, &pb.ServerMessage{Payload: &pb.ServerMessage_JobOffer{JobOffer: &offer}})
	d.notify.JobsChanged(ctx, jobID)
	d.log.Info("job offered", "job_id", jobID, "vehicle_id", pick.VehicleID, "eta_s", offer.EtaSeconds, "eta_source", pick.EtaSource)
	return pick.VehicleID, nil
}

func addEvent(ctx context.Context, tx pgx.Tx, jobID, kind, vehicleID string, detail map[string]any) error {
	if detail == nil {
		detail = map[string]any{}
	}
	var vid any
	if vehicleID != "" {
		vid = vehicleID
	}
	_, err := tx.Exec(ctx, `INSERT INTO job_events (job_id, kind, vehicle_id, detail) VALUES ($1, $2, $3, $4)`,
		jobID, kind, vid, detail)
	return err
}

// Run expires unanswered offers and retries jobs waiting for a vehicle.
func (d *Dispatcher) Run(ctx context.Context) {
	t := time.NewTicker(3 * time.Second)
	defer t.Stop()
	for {
		select {
		case <-ctx.Done():
			return
		case <-t.C:
			for _, id := range d.expireOffers(ctx) {
				d.dispatchLogged(ctx, id)
			}
			for _, id := range d.duePending(ctx) {
				d.dispatchLogged(ctx, id)
			}
		}
	}
}

func (d *Dispatcher) dispatchLogged(ctx context.Context, jobID string) {
	if _, err := d.Dispatch(ctx, jobID, ""); err != nil && !errors.Is(err, errNotDispatchable) && ctx.Err() == nil {
		d.log.Error("dispatch", "job_id", jobID, "err", err)
	}
}

// expireOffers returns lapsed offers to PENDING, counting them as declines.
func (d *Dispatcher) expireOffers(ctx context.Context) []string {
	tx, err := d.pool.Begin(ctx)
	if err != nil {
		return nil
	}
	defer tx.Rollback(ctx)
	rows, err := tx.Query(ctx, `
		SELECT id, offered_vehicle_id FROM jobs
		WHERE status = 'OFFERED' AND offer_expires_at < now()
		FOR UPDATE SKIP LOCKED`)
	if err != nil {
		return nil
	}
	type lapsed struct{ job, vehicle string }
	var expired []lapsed
	for rows.Next() {
		var l lapsed
		if rows.Scan(&l.job, &l.vehicle) == nil {
			expired = append(expired, l)
		}
	}
	rows.Close()
	var ids []string
	for _, l := range expired {
		_, err := tx.Exec(ctx, `
			UPDATE jobs SET status = 'PENDING', offered_vehicle_id = NULL, offered_at = NULL, offer_expires_at = NULL,
			       declined_vehicle_ids = array_append(declined_vehicle_ids, $2), last_dispatch_at = NULL, updated_at = now()
			WHERE id = $1`, l.job, l.vehicle)
		if err == nil {
			err = addEvent(ctx, tx, l.job, "offer_expired", l.vehicle, nil)
		}
		if err != nil {
			d.log.Error("expire offer", "job_id", l.job, "err", err)
			return nil
		}
		ids = append(ids, l.job)
	}
	if tx.Commit(ctx) != nil {
		return nil
	}
	for _, l := range expired {
		d.notify.Device(ctx, l.vehicle, &pb.ServerMessage{Payload: &pb.ServerMessage_JobCancelled{
			JobCancelled: &pb.JobCancelled{JobId: l.job, Reason: "Offer expired"},
		}})
	}
	return ids
}

// duePending lists jobs waiting for a vehicle whose last attempt is stale.
func (d *Dispatcher) duePending(ctx context.Context) []string {
	rows, err := d.pool.Query(ctx, `
		SELECT id FROM jobs
		WHERE status = 'PENDING'
		  AND (last_dispatch_at IS NULL OR last_dispatch_at < now() - make_interval(secs => $1))
		ORDER BY priority, created_at
		LIMIT 50`, d.retryEvery.Seconds())
	if err != nil {
		return nil
	}
	ids, _ := pgx.CollectRows(rows, pgx.RowTo[string])
	return ids
}

var (
	errNotYourJob  = errors.New("this job isn't offered or assigned to your vehicle")
	errBadProgress = errors.New("that step doesn't follow the job's current status")
)

// Accept assigns an offered job to the vehicle that was offered it.
func (d *Dispatcher) Accept(ctx context.Context, jobID, vehicleID string) error {
	tx, err := d.pool.Begin(ctx)
	if err != nil {
		return err
	}
	defer tx.Rollback(ctx)
	tag, err := tx.Exec(ctx, `
		UPDATE jobs SET status = 'EN_ROUTE_PICKUP', assigned_vehicle_id = $2, assigned_at = now(),
		       offered_vehicle_id = NULL, offered_at = NULL, offer_expires_at = NULL, updated_at = now()
		WHERE id = $1 AND status = 'OFFERED' AND offered_vehicle_id = $2 AND offer_expires_at > now()`,
		jobID, vehicleID)
	if err != nil {
		return err
	}
	if tag.RowsAffected() == 0 {
		return errNotYourJob
	}
	if _, err := tx.Exec(ctx, `UPDATE vehicles SET status = 'ON_JOB', updated_at = now() WHERE id = $1`, vehicleID); err != nil {
		return err
	}
	if err := addEvent(ctx, tx, jobID, "accepted", vehicleID, nil); err != nil {
		return err
	}
	if err := tx.Commit(ctx); err != nil {
		return err
	}
	d.notify.JobsChanged(ctx, jobID)
	return nil
}

// Decline passes the offer on to the next-best vehicle.
func (d *Dispatcher) Decline(ctx context.Context, jobID, vehicleID string) error {
	tx, err := d.pool.Begin(ctx)
	if err != nil {
		return err
	}
	defer tx.Rollback(ctx)
	tag, err := tx.Exec(ctx, `
		UPDATE jobs SET status = 'PENDING', offered_vehicle_id = NULL, offered_at = NULL, offer_expires_at = NULL,
		       declined_vehicle_ids = array_append(declined_vehicle_ids, $2), last_dispatch_at = NULL, updated_at = now()
		WHERE id = $1 AND status = 'OFFERED' AND offered_vehicle_id = $2`, jobID, vehicleID)
	if err != nil {
		return err
	}
	if tag.RowsAffected() == 0 {
		return errNotYourJob
	}
	if err := addEvent(ctx, tx, jobID, "declined", vehicleID, nil); err != nil {
		return err
	}
	if err := tx.Commit(ctx); err != nil {
		return err
	}
	d.dispatchLogged(ctx, jobID)
	d.notify.JobsChanged(ctx, jobID)
	return nil
}

// nextStatus lists the progress steps a driver may take from each status.
var nextStatus = map[string][]string{
	"EN_ROUTE_PICKUP":  {"ON_SITE"},
	"ON_SITE":          {"EN_ROUTE_DROPOFF", "COMPLETED"},
	"EN_ROUTE_DROPOFF": {"COMPLETED"},
}

// Progress moves an assigned job forward (arrived, picked up, completed).
func (d *Dispatcher) Progress(ctx context.Context, jobID, vehicleID, to string) error {
	tx, err := d.pool.Begin(ctx)
	if err != nil {
		return err
	}
	defer tx.Rollback(ctx)
	var from string
	var hasDropoff bool
	err = tx.QueryRow(ctx, `
		SELECT status::text, dropoff IS NOT NULL FROM jobs
		WHERE id = $1 AND assigned_vehicle_id = $2 FOR UPDATE`, jobID, vehicleID).Scan(&from, &hasDropoff)
	if errors.Is(err, pgx.ErrNoRows) {
		return errNotYourJob
	}
	if err != nil {
		return err
	}
	if !slices.Contains(nextStatus[from], to) || (to == "EN_ROUTE_DROPOFF" && !hasDropoff) {
		return errBadProgress
	}
	if _, err := tx.Exec(ctx, `
		UPDATE jobs SET status = $2::job_status, updated_at = now(),
		       completed_at = CASE WHEN $2 = 'COMPLETED' THEN now() ELSE completed_at END
		WHERE id = $1`, jobID, to); err != nil {
		return err
	}
	if to == "COMPLETED" {
		if _, err := tx.Exec(ctx, `UPDATE vehicles SET status = 'IDLE', updated_at = now() WHERE id = $1`, vehicleID); err != nil {
			return err
		}
	}
	if err := addEvent(ctx, tx, jobID, "status", vehicleID, map[string]any{"from": from, "to": to}); err != nil {
		return err
	}
	if err := tx.Commit(ctx); err != nil {
		return err
	}
	d.notify.JobsChanged(ctx, jobID)
	return nil
}

// Cancel stops a job at any stage before completion and frees its vehicle.
func (d *Dispatcher) Cancel(ctx context.Context, jobID, dispatcherID, reason string) error {
	tx, err := d.pool.Begin(ctx)
	if err != nil {
		return err
	}
	defer tx.Rollback(ctx)
	var assigned, offered *string
	err = tx.QueryRow(ctx, `
		UPDATE jobs j SET status = 'CANCELLED', updated_at = now(),
		       offered_vehicle_id = NULL, offered_at = NULL, offer_expires_at = NULL
		FROM (SELECT id, assigned_vehicle_id, offered_vehicle_id FROM jobs WHERE id = $1 FOR UPDATE) old
		WHERE j.id = old.id AND j.status NOT IN ('COMPLETED', 'CANCELLED')
		RETURNING old.assigned_vehicle_id::text, old.offered_vehicle_id::text`, jobID).Scan(&assigned, &offered)
	if errors.Is(err, pgx.ErrNoRows) {
		return errNotDispatchable
	}
	if err != nil {
		return err
	}
	if assigned != nil {
		if _, err := tx.Exec(ctx, `UPDATE vehicles SET status = 'IDLE', updated_at = now() WHERE id = $1`, *assigned); err != nil {
			return err
		}
	}
	if err := addEvent(ctx, tx, jobID, "cancelled", "", map[string]any{"by": dispatcherID, "reason": reason}); err != nil {
		return err
	}
	if err := tx.Commit(ctx); err != nil {
		return err
	}
	for _, v := range []*string{assigned, offered} {
		if v != nil {
			d.notify.Device(ctx, *v, &pb.ServerMessage{Payload: &pb.ServerMessage_JobCancelled{
				JobCancelled: &pb.JobCancelled{JobId: jobID, Reason: "Cancelled by dispatch"},
			}})
		}
	}
	d.notify.JobsChanged(ctx, jobID)
	return nil
}
