package geo

import (
	"math"
	"testing"
)

// A ~1.1 km square near Accra with a ~220 m hole in the middle.
var square = MultiPolygon{{
	{{-0.20, 5.60}, {-0.19, 5.60}, {-0.19, 5.61}, {-0.20, 5.61}, {-0.20, 5.60}},
	{{-0.196, 5.604}, {-0.194, 5.604}, {-0.194, 5.606}, {-0.196, 5.606}, {-0.196, 5.604}},
}}

func TestContains(t *testing.T) {
	cases := []struct {
		name     string
		lat, lon float64
		want     bool
	}{
		{"inside", 5.602, -0.198, true},
		{"in the hole", 5.605, -0.195, false},
		{"outside east", 5.605, -0.185, false},
		{"outside south", 5.595, -0.195, false},
	}
	for _, c := range cases {
		if got := square.Contains(c.lat, c.lon); got != c.want {
			t.Errorf("%s: Contains = %v, want %v", c.name, got, c.want)
		}
	}
}

func TestContainsSecondPolygon(t *testing.T) {
	m := append(MultiPolygon{}, square...)
	m = append(m, Polygon{{{0.0, 5.0}, {0.01, 5.0}, {0.01, 5.01}, {0.0, 5.01}}}) // open ring
	if !m.Contains(5.005, 0.005) {
		t.Fatal("point in second polygon not contained")
	}
}

func TestBoundaryDistance(t *testing.T) {
	// 0.001° of latitude north of the south edge is ~110.6 m.
	d := square.BoundaryDistanceM(5.601, -0.198)
	if math.Abs(d-110.6) > 1 {
		t.Fatalf("distance to south edge = %.1f m, want ~110.6", d)
	}
	// Just outside the east edge: ~0.0005° of longitude ≈ 55 m at 5.6°N.
	d = square.BoundaryDistanceM(5.605, -0.1895)
	if math.Abs(d-55.4) > 1 {
		t.Fatalf("distance to east edge = %.1f m, want ~55.4", d)
	}
}
