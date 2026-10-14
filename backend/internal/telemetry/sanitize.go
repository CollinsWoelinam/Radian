// Package telemetry validates incoming GPS points before they are queued.
package telemetry

import (
	"math"
	"slices"
	"time"

	pb "github.com/CollinsWoelinam/Radian/backend/gen/radian/telemetry/v1"
)

type Limits struct {
	MaxAccuracyM  float64       // drop fixes with a worse horizontal accuracy
	MaxFutureSkew time.Duration // tolerate device clocks running slightly ahead
	MaxAge        time.Duration // oldest backfill accepted (matches DB retention)
}

func DefaultLimits() Limits {
	return Limits{
		MaxAccuracyM:  50,
		MaxFutureSkew: 2 * time.Minute,
		MaxAge:        180 * 24 * time.Hour,
	}
}

type Result struct {
	Accepted []*pb.LocationPoint // sorted by recorded_at
	Rejected int
	MaxSeq   int64          // highest seq seen, accepted or not
	Reasons  map[string]int // rejection counts by reason, nil if none
}

// Sanitize drops invalid points and orders the rest by device GPS time, so
// out-of-order delivery from offline buffers never reaches storage unsorted.
func Sanitize(points []*pb.LocationPoint, now time.Time, lim Limits) Result {
	res := Result{Accepted: make([]*pb.LocationPoint, 0, len(points))}
	nowMs := now.UnixMilli()
	minMs := now.Add(-lim.MaxAge).UnixMilli()
	maxMs := now.Add(lim.MaxFutureSkew).UnixMilli()

	for _, p := range points {
		res.MaxSeq = max(res.MaxSeq, p.GetSeq())
		if reason := invalid(p, minMs, maxMs, lim.MaxAccuracyM); reason != "" {
			res.Rejected++
			if res.Reasons == nil {
				res.Reasons = make(map[string]int)
			}
			res.Reasons[reason]++
			continue
		}
		// Clamp small forward skew so "now" stays the upper bound downstream.
		if p.RecordedAtMs > nowMs {
			p.RecordedAtMs = nowMs
		}
		if p.HeadingDeg != nil && *p.HeadingDeg >= 360 {
			h := float32(math.Mod(float64(*p.HeadingDeg), 360))
			p.HeadingDeg = &h
		}
		res.Accepted = append(res.Accepted, p)
	}

	slices.SortStableFunc(res.Accepted, func(a, b *pb.LocationPoint) int {
		switch {
		case a.RecordedAtMs < b.RecordedAtMs:
			return -1
		case a.RecordedAtMs > b.RecordedAtMs:
			return 1
		}
		return 0
	})
	return res
}

// invalid returns why a point is rejected, or "" if it is acceptable.
func invalid(p *pb.LocationPoint, minMs, maxMs int64, maxAccuracy float64) string {
	lat, lon := p.GetLatitude(), p.GetLongitude()
	switch {
	case math.IsNaN(lat) || math.IsNaN(lon):
		return "nan_coordinates"
	case lat < -90 || lat > 90 || lon < -180 || lon > 180:
		return "out_of_range"
	case lat == 0 && lon == 0: // "Null Island": an uninitialised fix
		return "null_island"
	case p.RecordedAtMs < minMs:
		return "too_old"
	case p.RecordedAtMs > maxMs:
		return "in_future"
	case p.AccuracyM != nil && float64(*p.AccuracyM) > maxAccuracy:
		return "inaccurate"
	case p.SpeedKmh != nil && (*p.SpeedKmh < 0 || *p.SpeedKmh > 400):
		return "bad_speed"
	case p.HeadingDeg != nil && *p.HeadingDeg < 0:
		return "bad_heading"
	case p.BatteryPct != nil && (*p.BatteryPct < 0 || *p.BatteryPct > 100):
		return "bad_battery"
	}
	return ""
}
