package main

import (
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"math/rand/v2"
	"net/http"
	"time"

	pb "github.com/CollinsWoelinam/Radian/backend/gen/radian/telemetry/v1"
	"github.com/CollinsWoelinam/Radian/backend/internal/geo"
	"github.com/CollinsWoelinam/Radian/backend/internal/osrm"
)

// Driver behaviour for simulated vehicles: follow real roads (via OSRM) and
// handle dispatch the way a person would: think for a few seconds, usually
// accept, drive to the pickup, wait, drive to the drop-off, complete.

type jobPhase int

const (
	toPickup jobPhase = iota
	atPickup
	toDropoff
)

type simJob struct {
	id      string
	number  int64
	phase   jobPhase
	pickup  [2]float64 // lat, lon
	dropoff *[2]float64
}

// followRoute plans a road route to (lat, lon); without OSRM it drives straight.
func (v *vehicle) followRoute(ctx context.Context, lat, lon float64) {
	v.path, v.pathIdx = nil, 0
	if v.routing != nil {
		rctx, cancel := context.WithTimeout(ctx, 3*time.Second)
		r, err := v.routing.Route(rctx, osrm.Point{Lat: v.lat, Lon: v.lon}, osrm.Point{Lat: lat, Lon: lon})
		cancel()
		if err == nil && len(r.Coordinates) > 1 {
			v.path = r.Coordinates
			return
		}
	}
	v.path = [][2]float64{{v.lon, v.lat}, {lon, lat}}
}

// advance moves up to distM metres along the planned path. Returns true on arrival.
func (v *vehicle) advance(distM float64) bool {
	for distM > 0 && v.pathIdx < len(v.path) {
		next := v.path[v.pathIdx]
		d := geo.DistanceM(v.lat, v.lon, next[1], next[0])
		if d > 0.5 {
			v.heading = geo.BearingDeg(v.lat, v.lon, next[1], next[0])
		}
		if d <= distM {
			v.lat, v.lon = next[1], next[0]
			v.pathIdx++
			distM -= d
			continue
		}
		v.lat, v.lon = geo.Destination(v.lat, v.lon, v.heading, distM)
		distM = 0
	}
	return v.pathIdx >= len(v.path)
}

// roam heads to a random spot after a short stop, like a driver between jobs.
func (v *vehicle) roam(ctx context.Context, now time.Time, dwell time.Duration) {
	v.pausedUntil = now.Add(dwell)
	lat, lon := randomLandPoint()
	v.cruiseKmh = 20 + rand.Float64()*35
	v.followRoute(ctx, lat, lon)
}

// handleDispatch processes offers and cancellations; called every tick.
func (v *vehicle) handleDispatch(ctx context.Context, now time.Time) {
	for drained := false; !drained; {
		select {
		case o := <-v.offers:
			if v.job == nil {
				v.offer = o
				v.decideAt = now.Add(time.Duration(2+rand.IntN(5)) * time.Second) // a moment to read it
			}
		case id := <-v.cancels:
			if v.offer != nil && v.offer.JobId == id {
				v.offer = nil
			}
			if v.job != nil && v.job.id == id {
				v.log.Info("job cancelled by dispatch", "job", v.job.number)
				v.job = nil
				v.roam(ctx, now, 5*time.Second)
			}
		default:
			drained = true
		}
	}

	if v.offer == nil || now.Before(v.decideAt) {
		return
	}
	o := v.offer
	v.offer = nil
	if rand.Float64() >= v.acceptRate {
		v.st.declined.Add(1)
		v.post(ctx, "/v1/driver/jobs/"+o.JobId+"/decline", nil)
		return
	}
	if !v.post(ctx, "/v1/driver/jobs/"+o.JobId+"/accept", nil) {
		return // expired or reassigned meanwhile
	}
	v.st.accepted.Add(1)
	j := &simJob{id: o.JobId, number: o.Number, pickup: [2]float64{o.Pickup.Latitude, o.Pickup.Longitude}}
	if o.Dropoff != nil {
		j.dropoff = &[2]float64{o.Dropoff.Latitude, o.Dropoff.Longitude}
	}
	v.job = j
	v.pausedUntil = time.Time{}
	v.cruiseKmh = 35 + rand.Float64()*20 // on a job: a bit more purposeful
	v.followRoute(ctx, j.pickup[0], j.pickup[1])
	v.log.Info("accepted job", "job", o.Number, "eta_s", o.EtaSeconds)
}

// arrive runs when the vehicle reaches the end of its path.
func (v *vehicle) arrive(ctx context.Context, now time.Time) {
	j := v.job
	if j == nil {
		v.roam(ctx, now, time.Duration(10+rand.IntN(40))*time.Second)
		return
	}
	switch j.phase {
	case toPickup:
		v.post(ctx, "/v1/driver/jobs/"+j.id+"/status", map[string]string{"status": "ON_SITE"})
		j.phase = atPickup
		v.pausedUntil = now.Add(time.Duration(10+rand.IntN(15)) * time.Second) // loading / patient handover
		v.path, v.pathIdx = nil, 0
	case atPickup:
		if j.dropoff != nil {
			v.post(ctx, "/v1/driver/jobs/"+j.id+"/status", map[string]string{"status": "EN_ROUTE_DROPOFF"})
			j.phase = toDropoff
			v.followRoute(ctx, j.dropoff[0], j.dropoff[1])
			return
		}
		v.complete(ctx, now)
	case toDropoff:
		v.complete(ctx, now)
	}
}

func (v *vehicle) complete(ctx context.Context, now time.Time) {
	v.post(ctx, "/v1/driver/jobs/"+v.job.id+"/status", map[string]string{"status": "COMPLETED"})
	v.st.completed.Add(1)
	v.log.Info("completed job", "job", v.job.number)
	v.job = nil
	v.roam(ctx, now, time.Duration(10+rand.IntN(20))*time.Second)
}

// post calls the api as this vehicle's driver; true on 2xx.
func (v *vehicle) post(ctx context.Context, path string, body any) bool {
	if v.api == "" {
		return false
	}
	var buf bytes.Buffer
	if body != nil {
		json.NewEncoder(&buf).Encode(body)
	}
	rctx, cancel := context.WithTimeout(ctx, 5*time.Second)
	defer cancel()
	req, err := http.NewRequestWithContext(rctx, http.MethodPost, v.api+path, &buf)
	if err != nil {
		return false
	}
	req.Header.Set("Authorization", "Bearer "+v.token)
	req.Header.Set("Content-Type", "application/json")
	res, err := http.DefaultClient.Do(req)
	if err != nil {
		v.log.Warn("api call failed", "path", path, "err", err)
		return false
	}
	res.Body.Close()
	if res.StatusCode >= 300 {
		v.log.Debug("api call rejected", "path", path, "status", fmt.Sprint(res.StatusCode))
		return false
	}
	return true
}

// onServerMessage routes dispatch messages from the read goroutine to the
// vehicle's run loop.
func (v *vehicle) onServerMessage(msg *pb.ServerMessage) {
	switch p := msg.Payload.(type) {
	case *pb.ServerMessage_JobOffer:
		select {
		case v.offers <- p.JobOffer:
		default:
		}
	case *pb.ServerMessage_JobCancelled:
		select {
		case v.cancels <- p.JobCancelled.JobId:
		default:
		}
	}
}
