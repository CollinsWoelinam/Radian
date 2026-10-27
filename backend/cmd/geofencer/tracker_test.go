package main

import (
	"testing"
	"time"

	pb "github.com/CollinsWoelinam/Radian/backend/gen/radian/telemetry/v1"
	"github.com/CollinsWoelinam/Radian/backend/internal/geo"
)

// ~1.1 km square: lon -0.20..-0.19, lat 5.60..5.61.
var depot = NewFence("depot", "Depot", pb.GeofenceKind_GEOFENCE_KIND_DEPOT, geo.MultiPolygon{{
	{{-0.20, 5.60}, {-0.19, 5.60}, {-0.19, 5.61}, {-0.20, 5.61}},
}})

var restricted = func() *Fence {
	f := NewFence("airport", "Airport", pb.GeofenceKind_GEOFENCE_KIND_RESTRICTED, depot.Area)
	f.AlertOnEnter = true
	return f
}()

var t0 = time.Date(2026, 10, 19, 12, 0, 0, 0, time.UTC)

const (
	outLon  = -0.185   // ~550 m east of the fence
	inLon   = -0.195   // middle
	edgeLon = -0.19003 // ~3 m inside the east edge
)

func fix(sec int, lon float64) Fix {
	return Fix{Lat: 5.605, Lon: lon, At: t0.Add(time.Duration(sec) * time.Second), AccuracyM: 5}
}

func feed(tr *Tracker, fixes ...Fix) []Crossing {
	var all []Crossing
	for _, f := range fixes {
		all = append(all, tr.Observe("v1", f)...)
	}
	return all
}

func newTracker(f ...*Fence) *Tracker {
	tr := NewTracker()
	tr.SetFences(f)
	return tr
}

func TestEnterNeedsConfirmation(t *testing.T) {
	tr := newTracker(depot)
	if c := feed(tr, fix(0, outLon), fix(1, inLon)); len(c) != 0 {
		t.Fatalf("one inside fix should not confirm, got %v", c)
	}
	c := feed(tr, fix(2, inLon))
	if len(c) != 1 || !c[0].Entered || c[0].Fence.ID != "depot" {
		t.Fatalf("want one enter, got %+v", c)
	}
	if !c[0].Fix.At.Equal(t0.Add(time.Second)) {
		t.Fatalf("crossing should be stamped with the first inside fix, got %v", c[0].Fix.At)
	}
	c = feed(tr, fix(3, outLon), fix(4, outLon))
	if len(c) != 1 || c[0].Entered {
		t.Fatalf("want one exit, got %+v", c)
	}
}

func TestFirstSightingIsSilentExceptRestricted(t *testing.T) {
	tr := newTracker(depot)
	if c := feed(tr, fix(0, inLon)); len(c) != 1 || !c[0].Baseline {
		t.Fatalf("first sighting inside a depot should be a silent baseline, got %+v", c)
	}
	if got := tr.Inside("v1"); len(got) != 1 {
		t.Fatalf("membership not adopted: %v", got)
	}

	tr = newTracker(restricted)
	c := feed(tr, fix(0, inLon))
	if len(c) != 1 || !c[0].Entered || c[0].Baseline {
		t.Fatalf("first sighting inside a restricted zone should alert, got %+v", c)
	}
	if c := feed(newTracker(depot), fix(0, outLon)); len(c) != 0 {
		t.Fatalf("first sighting outside should be silent, got %+v", c)
	}
}

func TestEdgeJitterDoesNotFlap(t *testing.T) {
	tr := newTracker(depot)
	feed(tr, fix(0, inLon))
	// Hovering on the boundary, within GPS accuracy of it.
	var c []Crossing
	for i := 1; i < 30; i++ {
		lon := edgeLon
		if i%2 == 0 {
			lon = -0.18997 // ~3 m outside
		}
		c = append(c, feed(tr, fix(i, lon))...)
	}
	if len(c) != 0 {
		t.Fatalf("boundary jitter produced %d crossings", len(c))
	}
}

func TestAlternatingSidesResetConfirmation(t *testing.T) {
	tr := newTracker(depot)
	feed(tr, fix(0, outLon))
	if c := feed(tr, fix(1, inLon), fix(2, outLon), fix(3, inLon), fix(4, outLon)); len(c) != 0 {
		t.Fatalf("no side held for 2 fixes, got %v", c)
	}
}

func TestIgnoresInaccurateAndLateFixes(t *testing.T) {
	tr := newTracker(depot)
	feed(tr, fix(10, outLon))
	bad := fix(11, inLon)
	bad.AccuracyM = 200
	late := fix(5, inLon)
	if c := feed(tr, bad, bad, late, late); len(c) != 0 {
		t.Fatalf("inaccurate/late fixes caused crossings: %v", c)
	}
}

func TestRemovedFenceIsForgotten(t *testing.T) {
	tr := newTracker(depot)
	feed(tr, fix(0, inLon))
	tr.SetFences(nil)
	if got := tr.Inside("v1"); len(got) != 0 {
		t.Fatalf("still inside a deleted fence: %v", got)
	}
}

func TestDwellAlertsOncePerVisit(t *testing.T) {
	f := NewFence("rank", "Taxi rank", pb.GeofenceKind_GEOFENCE_KIND_DEPOT, depot.Area)
	f.Dwell = 2 * time.Minute
	tr := newTracker(f)
	feed(tr, fix(0, outLon), fix(1, inLon), fix(2, inLon)) // entered at t=1
	if c := feed(tr, fix(100, inLon)); len(c) != 0 {
		t.Fatalf("too early for dwell: %+v", c)
	}
	c := feed(tr, fix(121, inLon))
	if len(c) != 1 || !c[0].Dwell || !c[0].Alert() {
		t.Fatalf("want one dwell alert, got %+v", c)
	}
	if c := feed(tr, fix(300, inLon)); len(c) != 0 {
		t.Fatalf("dwell must fire once per visit, got %+v", c)
	}
	// Leave and come back: a new visit can alert again.
	feed(tr, fix(301, outLon), fix(302, outLon), fix(303, inLon), fix(304, inLon))
	if c := feed(tr, fix(430, inLon)); len(c) != 1 || !c[0].Dwell {
		t.Fatalf("second visit should alert again, got %+v", c)
	}
}

func TestAlertFollowsZoneRules(t *testing.T) {
	quiet := NewFence("q", "Quiet depot", pb.GeofenceKind_GEOFENCE_KIND_DEPOT, depot.Area)
	tr := newTracker(quiet)
	feed(tr, fix(0, outLon))
	c := feed(tr, fix(1, inLon), fix(2, inLon))
	if len(c) != 1 || c[0].Alert() {
		t.Fatalf("depot without rules should log but not alert: %+v", c)
	}
	quiet.AlertOnExit = true
	c = feed(tr, fix(3, outLon), fix(4, outLon))
	if len(c) != 1 || !c[0].Alert() {
		t.Fatalf("exit should alert once the rule is on: %+v", c)
	}
}
