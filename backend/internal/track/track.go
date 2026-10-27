// Package track turns a vehicle's stored fixes into what a dispatcher reads:
// how far and how long it drove, its top speed, and the moments worth a look
// (speeding, long stops, time without location).
package track

import (
	"math"
	"time"

	"github.com/CollinsWoelinam/Radian/backend/internal/geo"
)

// Point is one stored fix. SpeedKmh and AccuracyM are negative when unknown.
type Point struct {
	At        time.Time
	Lat, Lon  float64
	SpeedKmh  float64
	AccuracyM float64
}

const (
	movingKmh      = 5.0
	maxPlausible   = 250.0
	maxAccuracyM   = 50.0
	maxDrivingGap  = 2 * time.Minute
	stopMinimum    = 5 * time.Minute
	speedingMinDur = 10 * time.Second
)

// Summary of a stretch of driving.
type Summary struct {
	DistanceM   float64 `json:"distance_m"`
	DrivingS    int     `json:"driving_s"`
	TopSpeedKmh float64 `json:"top_speed_kmh"`
}

func usable(p Point) bool { return p.AccuracyM < 0 || p.AccuracyM <= maxAccuracyM }

// Summarize adds up distance and driving time, ignoring the GPS jitter of a
// parked phone: a leg only counts when the vehicle was moving or the jump is
// larger than the two fixes' accuracy.
func Summarize(pts []Point) Summary {
	var s Summary
	var prev *Point
	for i := range pts {
		p := pts[i]
		if !usable(p) {
			continue
		}
		if p.SpeedKmh >= 0 && p.SpeedKmh <= maxPlausible {
			s.TopSpeedKmh = math.Max(s.TopSpeedKmh, p.SpeedKmh)
		}
		if prev != nil {
			dt := p.At.Sub(prev.At)
			d := geo.DistanceM(prev.Lat, prev.Lon, p.Lat, p.Lon)
			if dt > 0 && d/dt.Seconds()*3.6 <= maxPlausible {
				moving := p.SpeedKmh >= movingKmh || prev.SpeedKmh >= movingKmh
				noise := math.Max(prev.AccuracyM, 0) + math.Max(p.AccuracyM, 0)
				if moving || (p.SpeedKmh < 0 && d > noise) {
					s.DistanceM += d
					if dt <= maxDrivingGap {
						s.DrivingS += int(dt.Seconds())
					}
				}
			}
		}
		prev = &pts[i]
	}
	s.DistanceM = math.Round(s.DistanceM)
	s.TopSpeedKmh = math.Round(s.TopSpeedKmh)
	return s
}

// Event is something notable on the track.
type Event struct {
	Kind      string    `json:"kind"` // speeding | stop | no_signal
	At        time.Time `json:"at"`
	DurationS int       `json:"duration_s"`
	Lat       float64   `json:"lat"`
	Lon       float64   `json:"lon"`
	// Speeding: the highest speed reached.
	MaxSpeedKmh float64 `json:"max_speed_kmh,omitempty"`
}

// Events finds speeding over limitKmh, stops of five minutes or more, and gaps
// longer than gap with no fixes at all.
func Events(pts []Point, limitKmh float64, gap time.Duration) []Event {
	var out []Event
	var speeding, stop *Event
	closeSpeeding := func(end time.Time) {
		if speeding != nil {
			speeding.DurationS = int(end.Sub(speeding.At).Seconds())
			if end.Sub(speeding.At) >= speedingMinDur {
				out = append(out, *speeding)
			}
			speeding = nil
		}
	}
	closeStop := func(end time.Time) {
		if stop != nil {
			if end.Sub(stop.At) >= stopMinimum {
				stop.DurationS = int(end.Sub(stop.At).Seconds())
				out = append(out, *stop)
			}
			stop = nil
		}
	}
	for i, p := range pts {
		if i > 0 && p.At.Sub(pts[i-1].At) > gap {
			prev := pts[i-1]
			closeSpeeding(prev.At)
			closeStop(prev.At)
			out = append(out, Event{Kind: "no_signal", At: prev.At, DurationS: int(p.At.Sub(prev.At).Seconds()), Lat: prev.Lat, Lon: prev.Lon})
		}
		if !usable(p) || p.SpeedKmh < 0 {
			continue
		}
		if p.SpeedKmh > limitKmh && p.SpeedKmh <= maxPlausible {
			if speeding == nil {
				speeding = &Event{Kind: "speeding", At: p.At, Lat: p.Lat, Lon: p.Lon}
			}
			speeding.MaxSpeedKmh = math.Max(speeding.MaxSpeedKmh, math.Round(p.SpeedKmh))
		} else {
			closeSpeeding(p.At)
		}
		if p.SpeedKmh < movingKmh {
			if stop == nil {
				stop = &Event{Kind: "stop", At: p.At, Lat: p.Lat, Lon: p.Lon}
			}
		} else {
			closeStop(p.At)
		}
	}
	if n := len(pts); n > 0 {
		closeSpeeding(pts[n-1].At)
		closeStop(pts[n-1].At)
	}
	return out
}

// Downsample keeps at most max points, evenly spaced, always keeping the last.
func Downsample(pts []Point, max int) []Point {
	if max <= 0 || len(pts) <= max {
		return pts
	}
	step := float64(len(pts)-1) / float64(max-1)
	out := make([]Point, 0, max)
	for i := 0; i < max; i++ {
		out = append(out, pts[int(math.Round(float64(i)*step))])
	}
	return out
}
