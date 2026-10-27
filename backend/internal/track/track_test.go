package track

import (
	"testing"
	"time"
)

var t0 = time.Date(2026, 10, 27, 8, 0, 0, 0, time.UTC)

// drive makes n fixes 2 s apart moving north at kmh, starting at lat.
func drive(start time.Time, lat float64, n int, kmh float64) []Point {
	var pts []Point
	step := kmh / 3.6 * 2 / 111_320 // degrees of latitude per 2 s
	for i := 0; i < n; i++ {
		pts = append(pts, Point{At: start.Add(time.Duration(2*i) * time.Second), Lat: lat + float64(i)*step, Lon: -0.2, SpeedKmh: kmh, AccuracyM: 5})
	}
	return pts
}

func TestSummarizeCountsDrivingNotJitter(t *testing.T) {
	pts := drive(t0, 5.6, 31, 36) // 60 s at 36 km/h = 600 m
	// Then parked for a minute with 15 m of GPS jitter.
	last := pts[len(pts)-1]
	for i := 1; i <= 30; i++ {
		lat := last.Lat
		if i%2 == 1 {
			lat += 0.00013
		}
		pts = append(pts, Point{At: last.At.Add(time.Duration(2*i) * time.Second), Lat: lat, Lon: -0.2, SpeedKmh: 0, AccuracyM: 12})
	}
	s := Summarize(pts)
	if s.DistanceM < 580 || s.DistanceM > 620 {
		t.Fatalf("distance %.0f m, want ~600", s.DistanceM)
	}
	if s.DrivingS < 58 || s.DrivingS > 62 {
		t.Fatalf("driving %d s, want ~60", s.DrivingS)
	}
	if s.TopSpeedKmh != 36 {
		t.Fatalf("top speed %.0f, want 36", s.TopSpeedKmh)
	}
}

func TestSummarizeIgnoresInaccurateAndImpossibleFixes(t *testing.T) {
	pts := drive(t0, 5.6, 10, 30)
	pts[5].AccuracyM = 300 // coarse network fix
	pts[5].SpeedKmh = 140
	pts = append(pts, Point{At: pts[9].At.Add(2 * time.Second), Lat: 6.6, Lon: -0.2, SpeedKmh: -1, AccuracyM: 5}) // 110 km in 2 s
	s := Summarize(pts)
	if s.TopSpeedKmh != 30 {
		t.Fatalf("top speed %.0f, want 30", s.TopSpeedKmh)
	}
	if s.DistanceM > 200 {
		t.Fatalf("distance %.0f m, the teleport should not count", s.DistanceM)
	}
}

func TestEventsSpeedingStopsAndGaps(t *testing.T) {
	pts := drive(t0, 5.6, 5, 40)
	pts = append(pts, drive(pts[4].At.Add(2*time.Second), 5.61, 10, 95)...) // 20 s at 95
	end := pts[len(pts)-1].At
	for i := 1; i <= 200; i++ { // 400 s parked
		pts = append(pts, Point{At: end.Add(time.Duration(2*i) * time.Second), Lat: 5.62, Lon: -0.2, SpeedKmh: 0, AccuracyM: 6})
	}
	end = pts[len(pts)-1].At
	pts = append(pts, drive(end.Add(10*time.Minute), 5.62, 5, 30)...) // phone silent 10 min

	ev := Events(pts, 80, 2*time.Minute)
	kinds := map[string]Event{}
	for _, e := range ev {
		kinds[e.Kind] = e
	}
	if e, ok := kinds["speeding"]; !ok || e.MaxSpeedKmh != 95 || e.DurationS < 18 {
		t.Fatalf("speeding event = %+v", e)
	}
	if e, ok := kinds["stop"]; !ok || e.DurationS < 390 {
		t.Fatalf("stop event = %+v", e)
	}
	if e, ok := kinds["no_signal"]; !ok || e.DurationS != 600 {
		t.Fatalf("no_signal event = %+v", e)
	}
	if len(ev) != 3 {
		t.Fatalf("want 3 events, got %+v", ev)
	}
}

func TestEventsIgnoresShortBursts(t *testing.T) {
	pts := drive(t0, 5.6, 5, 40)
	pts = append(pts, drive(pts[4].At.Add(2*time.Second), 5.61, 3, 90)...) // 4 s over the limit
	pts = append(pts, drive(pts[7].At.Add(2*time.Second), 5.61, 5, 40)...)
	if ev := Events(pts, 80, 2*time.Minute); len(ev) != 0 {
		t.Fatalf("a 4 s burst should not count, got %+v", ev)
	}
}

func TestDownsampleKeepsEnds(t *testing.T) {
	pts := drive(t0, 5.6, 1000, 30)
	d := Downsample(pts, 100)
	if len(d) != 100 || d[0] != pts[0] || d[99] != pts[999] {
		t.Fatalf("downsample len=%d first/last kept=%v/%v", len(d), d[0] == pts[0], d[99] == pts[999])
	}
	if got := Downsample(pts[:10], 100); len(got) != 10 {
		t.Fatalf("short input should be returned as is")
	}
}
