package main

import (
	"errors"
	"testing"

	"github.com/CollinsWoelinam/Radian/backend/internal/osrm"
)

func ids(cs []Candidate) []string {
	out := make([]string, len(cs))
	for i, c := range cs {
		out[i] = c.VehicleID
	}
	return out
}

func TestRankByDriveTime(t *testing.T) {
	// Candidates arrive ordered by straight-line distance...
	cands := []Candidate{
		{VehicleID: "near-but-across-river", StraightM: 800},
		{VehicleID: "unroutable", StraightM: 900},
		{VehicleID: "farther-but-on-highway", StraightM: 2500},
		{VehicleID: "declined", StraightM: 100, Declined: true},
	}
	// ...but road drive time decides.
	table := osrm.TableResult{
		DurationsS: []float64{900, -1, 240, 60},
		DistancesM: []float64{6000, -1, 3100, 150},
	}
	got := rank(cands, table, nil)
	want := []string{"farther-but-on-highway", "near-but-across-river", "declined"}
	if len(got) != len(want) {
		t.Fatalf("got %v, want %v", ids(got), want)
	}
	for i := range want {
		if got[i].VehicleID != want[i] {
			t.Fatalf("got %v, want %v", ids(got), want)
		}
	}
	if got[0].EtaSource != "road" || got[0].RouteM != 3100 {
		t.Errorf("top candidate = %+v, want road ETA with 3100 m", got[0])
	}
}

func TestRankFallsBackToEstimate(t *testing.T) {
	cands := []Candidate{{VehicleID: "b", StraightM: 3000}, {VehicleID: "a", StraightM: 1000}}
	got := rank(cands, osrm.TableResult{}, errors.New("osrm down"))
	if ids(got)[0] != "a" || got[0].EtaSource != "estimate" {
		t.Fatalf("got %+v", got)
	}
	// 1 km straight, 30% detour at 25 km/h ≈ 187 s
	if got[0].EtaS < 180 || got[0].EtaS > 195 {
		t.Errorf("estimate ETA = %.0f s, want ~187 s", got[0].EtaS)
	}
}
