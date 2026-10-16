package main

import (
	"testing"
	"time"

	pb "github.com/CollinsWoelinam/Radian/backend/gen/radian/telemetry/v1"
)

func fix(lat, lon float64, at time.Time, speed float32) *pb.LocationPoint {
	return &pb.LocationPoint{Latitude: lat, Longitude: lon, RecordedAtMs: at.UnixMilli(), SpeedKmh: &speed}
}

func drain(c *client) []*pb.FleetUpdate {
	var out []*pb.FleetUpdate
	for {
		select {
		case m := <-c.send:
			out = append(out, m.GetFleetUpdate())
		default:
			return out
		}
	}
}

// Viewport: central Accra.
var accra = &pb.BoundingBox{MinLon: -0.25, MinLat: 5.55, MaxLon: -0.15, MaxLat: 5.65}

func TestHubViewportLifecycle(t *testing.T) {
	now := time.Now()
	h := NewHub(2 * time.Minute)
	h.Apply("inside", fix(5.60, -0.20, now, 30))
	h.Apply("outside", fix(6.70, -1.60, now, 30)) // Kumasi
	h.Tick(now)                                   // clears initial dirty set

	c := newClient(nil)
	h.Register(c)
	h.Subscribe(c, accra)

	got := drain(c)
	if len(got) != 1 || !got[0].IsSnapshot || len(got[0].Deltas) != 1 || got[0].Deltas[0].VehicleId != "inside" {
		t.Fatalf("snapshot = %+v, want only 'inside'", got)
	}
	if s := got[0].Deltas[0].Status; s != pb.VehicleStatus_VEHICLE_STATUS_EN_ROUTE {
		t.Errorf("status = %v, want EN_ROUTE at 30 km/h", s)
	}

	// Move inside -> still inside; outside vehicle moves but stays out.
	h.Apply("inside", fix(5.61, -0.20, now.Add(time.Second), 0))
	h.Apply("outside", fix(6.71, -1.60, now.Add(time.Second), 30))
	h.Tick(now.Add(time.Second))
	got = drain(c)
	if len(got) != 1 || len(got[0].Deltas) != 1 || got[0].Deltas[0].Status != pb.VehicleStatus_VEHICLE_STATUS_IDLE {
		t.Fatalf("delta = %+v, want one IDLE update for 'inside'", got)
	}

	// Stale backfill must not rewind the live position.
	h.Apply("inside", fix(5.50, -0.10, now.Add(-time.Minute), 30))
	h.Tick(now.Add(2 * time.Second))
	if got = drain(c); len(got) != 0 {
		t.Fatalf("stale fix produced update: %+v", got)
	}

	// Drive out of the viewport -> removal.
	h.Apply("inside", fix(7.0, -0.20, now.Add(3*time.Second), 40))
	h.Tick(now.Add(3 * time.Second))
	got = drain(c)
	if len(got) != 1 || len(got[0].RemovedVehicleIds) != 1 || len(got[0].Deltas) != 0 {
		t.Fatalf("got %+v, want a single removal", got)
	}

	// Silence -> OFFLINE once the threshold passes (vehicle is back in view).
	h.Apply("inside", fix(5.60, -0.20, now.Add(4*time.Second), 0))
	h.Tick(now.Add(4 * time.Second))
	drain(c)
	h.Tick(now.Add(4*time.Second + 3*time.Minute))
	got = drain(c)
	if len(got) != 1 || got[0].Deltas[0].Status != pb.VehicleStatus_VEHICLE_STATUS_OFFLINE {
		t.Fatalf("got %+v, want OFFLINE transition", got)
	}
}

func TestHubSlowClientGetsSnapshot(t *testing.T) {
	now := time.Now()
	h := NewHub(2 * time.Minute)
	c := newClient(nil)
	h.Register(c)
	h.Subscribe(c, accra)
	drain(c)

	// Never drain: fill the queue, then overflow it.
	for i := range clientQueue + 2 {
		at := now.Add(time.Duration(i+1) * time.Second)
		h.Apply("v", fix(5.60+float64(i)*0.001, -0.20, at, 30))
		h.Tick(at)
	}
	if !c.needsSnapshot {
		t.Fatal("overflowed client should be flagged for a snapshot")
	}

	drain(c)
	at := now.Add(time.Minute)
	h.Apply("v", fix(5.62, -0.20, at, 30))
	h.Tick(at)
	got := drain(c)
	if len(got) != 1 || !got[0].IsSnapshot {
		t.Fatalf("got %+v, want a resync snapshot", got)
	}
}
