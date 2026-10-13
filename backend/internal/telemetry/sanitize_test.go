package telemetry

import (
	"testing"
	"time"

	pb "github.com/CollinsWoelinam/Radian/backend/gen/radian/telemetry/v1"
)

func f32(v float32) *float32 { return &v }

func TestSanitize(t *testing.T) {
	now := time.UnixMilli(1_782_830_400_000)
	ms := now.UnixMilli()
	lim := DefaultLimits()

	points := []*pb.LocationPoint{
		{Seq: 3, Latitude: 5.6037, Longitude: -0.1870, RecordedAtMs: ms - 1000},
		{Seq: 1, Latitude: 5.6000, Longitude: -0.1800, RecordedAtMs: ms - 5000},                         // out of order
		{Seq: 2, Latitude: 0, Longitude: 0, RecordedAtMs: ms - 3000},                                    // null island
		{Seq: 4, Latitude: 5.6, Longitude: -0.18, RecordedAtMs: ms, AccuracyM: f32(120)},                // too inaccurate
		{Seq: 5, Latitude: 95, Longitude: -0.18, RecordedAtMs: ms},                                      // bad latitude
		{Seq: 6, Latitude: 5.6, Longitude: -0.18, RecordedAtMs: ms + int64(time.Hour/time.Millisecond)}, // far future
		{Seq: 7, Latitude: 5.61, Longitude: -0.18, RecordedAtMs: ms + 30_000},                           // small skew, clamped
	}

	res := Sanitize(points, now, lim)

	if res.MaxSeq != 7 {
		t.Errorf("MaxSeq = %d, want 7", res.MaxSeq)
	}
	if res.Rejected != 4 {
		t.Errorf("Rejected = %d, want 4", res.Rejected)
	}
	gotSeqs := []int64{}
	for _, p := range res.Accepted {
		gotSeqs = append(gotSeqs, p.Seq)
	}
	want := []int64{1, 3, 7}
	if len(gotSeqs) != len(want) {
		t.Fatalf("accepted seqs = %v, want %v", gotSeqs, want)
	}
	for i := range want {
		if gotSeqs[i] != want[i] {
			t.Fatalf("accepted seqs = %v, want %v (sorted by recorded_at)", gotSeqs, want)
		}
	}
	if last := res.Accepted[2]; last.RecordedAtMs != ms {
		t.Errorf("future skew not clamped: got %d, want %d", last.RecordedAtMs, ms)
	}
}
