package main

import (
	"context"
	"log/slog"
	"math"
	"math/rand/v2"
	"net/http"
	"sync"
	"time"

	"github.com/coder/websocket"
	"google.golang.org/protobuf/proto"

	pb "github.com/CollinsWoelinam/Radian/backend/gen/radian/telemetry/v1"
	"github.com/CollinsWoelinam/Radian/backend/internal/geo"
	"github.com/CollinsWoelinam/Radian/backend/internal/osrm"
)

// Greater Accra, roughly Kasoa to Tema.
const (
	minLat, maxLat = 5.53, 5.72
	minLon, maxLon = -0.32, -0.02

	maxBackfillBatch = 500
)

type vehicle struct {
	id, token, url string
	interval       time.Duration
	dropout        float64
	st             *stats
	log            *slog.Logger

	// Kinematics: drive along path ([lon, lat] points) at around cruiseKmh.
	lat, lon, heading, speedKmh float64
	path                        [][2]float64
	pathIdx                     int
	cruiseKmh                   float64
	pausedUntil                 time.Time
	battery                     float64

	// Dispatch (see driver.go). Only the run loop touches offer/job.
	api        string
	routing    *osrm.Client
	acceptRate float64
	offers     chan *pb.JobOffer
	cancels    chan string
	offer      *pb.JobOffer
	decideAt   time.Time
	job        *simJob

	// Client-side buffer, mirroring the app's SQLite ring buffer.
	mu       sync.Mutex
	seq      int64
	buffer   []*pb.LocationPoint
	lastSent *pb.LocationPoint
	// Highest seq written on the current connection; reset on reconnect so
	// everything unacked is resent.
	wroteSeq int64

	offlineUntil time.Time
}

type vehicleOpts struct {
	url, api   string
	routing    *osrm.Client
	interval   time.Duration
	dropout    float64
	acceptRate float64
}

func newVehicle(ctx context.Context, id, token string, o vehicleOpts, st *stats, log *slog.Logger) *vehicle {
	v := &vehicle{
		id: id, token: token, url: o.url, interval: o.interval, dropout: o.dropout, st: st,
		log:        log.With("vehicle_id", id),
		battery:    40 + rand.Float64()*60,
		api:        o.api,
		routing:    o.routing,
		acceptRate: o.acceptRate,
		offers:     make(chan *pb.JobOffer, 4),
		cancels:    make(chan string, 4),
	}
	v.lat, v.lon = randomLandPoint()
	v.roam(ctx, time.Now(), 0)
	return v
}

// coastLat approximates the Gulf of Guinea shoreline across Greater Accra
// (piecewise linear, west to east), so random destinations stay on land.
func coastLat(lon float64) float64 {
	pts := [][2]float64{{-0.32, 5.50}, {-0.21, 5.535}, {-0.14, 5.555}, {-0.06, 5.595}, {-0.02, 5.625}}
	for i := 1; i < len(pts); i++ {
		if lon <= pts[i][0] {
			a, b := pts[i-1], pts[i]
			return a[1] + (lon-a[0])/(b[0]-a[0])*(b[1]-a[1])
		}
	}
	return pts[len(pts)-1][1]
}

func randomLandPoint() (lat, lon float64) {
	for {
		lat = minLat + rand.Float64()*(maxLat-minLat)
		lon = minLon + rand.Float64()*(maxLon-minLon)
		if lat > coastLat(lon)+0.012 {
			return lat, lon
		}
	}
}

// step advances the vehicle by dt and returns a noisy GPS fix.
func (v *vehicle) step(ctx context.Context, dt time.Duration, now time.Time) *pb.LocationPoint {
	switch {
	case now.Before(v.pausedUntil):
		v.speedKmh = 0
	case v.pathIdx >= len(v.path):
		v.speedKmh = 0
		v.arrive(ctx, now) // also resumes after a dwell at the pickup
	default:
		// Ease toward cruise speed with some traffic noise.
		v.speedKmh += (v.cruiseKmh-v.speedKmh)*0.3 + rand.NormFloat64()*3
		v.speedKmh = math.Max(0, math.Min(v.speedKmh, 90))
		if v.advance(v.speedKmh / 3.6 * dt.Seconds()) {
			v.arrive(ctx, now)
		}
	}
	v.battery = math.Max(5, v.battery-0.002)

	// GPS noise: a few meters of jitter, occasionally a bad fix.
	accuracy := 3 + rand.Float64()*9
	if rand.Float64() < 0.02 {
		accuracy = 60 + rand.Float64()*100 // the server should reject these
	}
	jLat, jLon := geo.Destination(v.lat, v.lon, rand.Float64()*360, rand.NormFloat64()*accuracy/2)

	speed := float32(v.speedKmh)
	heading := float32(v.heading)
	acc := float32(accuracy)
	battery := int32(v.battery)
	return &pb.LocationPoint{
		Latitude:     jLat,
		Longitude:    jLon,
		RecordedAtMs: now.UnixMilli(),
		SpeedKmh:     &speed,
		HeadingDeg:   &heading,
		AccuracyM:    &acc,
		BatteryPct:   &battery,
	}
}

// shouldSend is the on-device stationary filter from the design doc.
func shouldSend(p, last *pb.LocationPoint) bool {
	if last == nil {
		return true
	}
	d := geo.DistanceM(last.Latitude, last.Longitude, p.Latitude, p.Longitude)
	// Still emit a fix every 30s while parked so the dashboard knows we're alive.
	stale := p.RecordedAtMs-last.RecordedAtMs > 30_000
	return !(d < 10 && p.GetSpeedKmh() < 3.6) || stale
}

func (v *vehicle) run(ctx context.Context) {
	ticker := time.NewTicker(v.interval)
	defer ticker.Stop()

	var conn *websocket.Conn
	backoff := time.Second
	nextDial := time.Time{}

	for {
		select {
		case <-ctx.Done():
			if conn != nil {
				conn.Close(websocket.StatusNormalClosure, "simulator stopping")
			}
			return
		case now := <-ticker.C:
			v.handleDispatch(ctx, now)
			v.record(ctx, now)

			if conn == nil && now.Before(v.offlineUntil) {
				continue
			}
			if conn != nil && rand.Float64() < v.dropout {
				// Drive into a dead zone: drop the socket, keep buffering.
				v.offlineUntil = now.Add(time.Duration(20+rand.IntN(60)) * time.Second)
				v.st.deadZones.Add(1)
				conn.CloseNow()
				conn = nil
				continue
			}

			if conn == nil {
				if now.Before(nextDial) {
					continue
				}
				c, err := v.dial(ctx)
				if err != nil {
					v.log.Debug("dial failed", "err", err)
					nextDial = now.Add(backoff)
					backoff = min(backoff*2, 30*time.Second)
					continue
				}
				conn, backoff = c, time.Second
				v.mu.Lock()
				v.wroteSeq = 0
				v.mu.Unlock()
				v.st.reconnects.Add(1)
				go v.readAcks(ctx, conn)
			}

			if err := v.flush(ctx, conn); err != nil {
				conn.CloseNow()
				conn = nil
			}
		}
	}
}

// record takes a GPS fix and buffers it if it passes the stationary filter.
func (v *vehicle) record(ctx context.Context, now time.Time) {
	p := v.step(ctx, v.interval, now)
	v.mu.Lock()
	defer v.mu.Unlock()
	if !shouldSend(p, v.lastSent) {
		v.st.filtered.Add(1)
		return
	}
	v.seq++
	p.Seq = v.seq
	v.lastSent = p
	v.buffer = append(v.buffer, p)
}

// flush sends buffered points not yet written on this connection. A backlog
// from a dead zone goes out as backfill.
func (v *vehicle) flush(ctx context.Context, conn *websocket.Conn) error {
	v.mu.Lock()
	var points []*pb.LocationPoint
	for _, p := range v.buffer {
		if p.Seq > v.wroteSeq {
			points = append(points, p)
		}
	}
	v.mu.Unlock()

	for len(points) > 0 {
		n := min(len(points), maxBackfillBatch)
		chunk := points[:n]
		points = points[n:]
		msg := &pb.ClientMessage{Payload: &pb.ClientMessage_Batch{Batch: &pb.TelemetryBatch{
			Points:     chunk,
			IsBackfill: len(chunk) > 1,
		}}}
		data, err := proto.Marshal(msg)
		if err != nil {
			return err
		}
		wctx, cancel := context.WithTimeout(ctx, 5*time.Second)
		err = conn.Write(wctx, websocket.MessageBinary, data)
		cancel()
		if err != nil {
			return err
		}
		v.st.sent.Add(int64(len(chunk)))
		v.mu.Lock()
		v.wroteSeq = chunk[len(chunk)-1].Seq
		v.mu.Unlock()
	}
	return nil
}

func (v *vehicle) readAcks(ctx context.Context, conn *websocket.Conn) {
	for {
		_, data, err := conn.Read(ctx)
		if err != nil {
			return
		}
		var msg pb.ServerMessage
		if proto.Unmarshal(data, &msg) != nil {
			continue
		}
		v.onServerMessage(&msg)
		if ack := msg.GetAck(); ack != nil {
			v.mu.Lock()
			i := 0
			for i < len(v.buffer) && v.buffer[i].Seq <= ack.AckedSeq {
				i++
			}
			v.st.acked.Add(int64(i))
			v.buffer = v.buffer[i:]
			v.mu.Unlock()
		}
	}
}

func (v *vehicle) dial(ctx context.Context) (*websocket.Conn, error) {
	dctx, cancel := context.WithTimeout(ctx, 5*time.Second)
	defer cancel()
	conn, _, err := websocket.Dial(dctx, v.url, &websocket.DialOptions{
		HTTPHeader: http.Header{"Authorization": {"Bearer " + v.token}},
	})
	return conn, err
}
