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

	// Kinematics
	lat, lon, heading, speedKmh float64
	targetLat, targetLon        float64
	cruiseKmh                   float64
	pausedUntil                 time.Time
	battery                     float64

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

func newVehicle(id, token, url string, interval time.Duration, dropout float64, st *stats, log *slog.Logger) *vehicle {
	v := &vehicle{
		id: id, token: token, url: url, interval: interval, dropout: dropout, st: st,
		log:     log.With("vehicle_id", id),
		lat:     minLat + rand.Float64()*(maxLat-minLat),
		lon:     minLon + rand.Float64()*(maxLon-minLon),
		battery: 40 + rand.Float64()*60,
	}
	v.pickTarget()
	return v
}

func (v *vehicle) pickTarget() {
	v.targetLat = minLat + rand.Float64()*(maxLat-minLat)
	v.targetLon = minLon + rand.Float64()*(maxLon-minLon)
	v.cruiseKmh = 20 + rand.Float64()*45
}

// step advances the vehicle by dt and returns a noisy GPS fix.
func (v *vehicle) step(dt time.Duration, now time.Time) *pb.LocationPoint {
	if now.Before(v.pausedUntil) {
		v.speedKmh = 0
	} else {
		dist := geo.DistanceM(v.lat, v.lon, v.targetLat, v.targetLon)
		if dist < 50 {
			// Arrived: dwell like a delivery stop, then head somewhere new.
			v.pausedUntil = now.Add(time.Duration(10+rand.IntN(50)) * time.Second)
			v.pickTarget()
			v.speedKmh = 0
		} else {
			// Ease toward cruise speed with some traffic noise.
			v.speedKmh += (v.cruiseKmh-v.speedKmh)*0.3 + rand.NormFloat64()*3
			v.speedKmh = math.Max(0, math.Min(v.speedKmh, 90))
			want := geo.BearingDeg(v.lat, v.lon, v.targetLat, v.targetLon)
			// Wobble the heading so tracks aren't perfectly straight lines.
			v.heading = math.Mod(want+rand.NormFloat64()*8+360, 360)
			move := math.Min(v.speedKmh/3.6*dt.Seconds(), dist)
			v.lat, v.lon = geo.Destination(v.lat, v.lon, v.heading, move)
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
			v.record(now)

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
func (v *vehicle) record(now time.Time) {
	p := v.step(v.interval, now)
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
