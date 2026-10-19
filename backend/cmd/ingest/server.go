package main

import (
	"context"
	"encoding/json"
	"errors"
	"log/slog"
	"net/http"
	"strings"
	"sync"
	"sync/atomic"
	"time"

	"github.com/coder/websocket"
	"github.com/redis/go-redis/v9"
	"google.golang.org/protobuf/proto"

	pb "github.com/CollinsWoelinam/Radian/backend/gen/radian/telemetry/v1"
	"github.com/CollinsWoelinam/Radian/backend/internal/auth"
	"github.com/CollinsWoelinam/Radian/backend/internal/stream"
	"github.com/CollinsWoelinam/Radian/backend/internal/telemetry"
)

const (
	maxMessageBytes = 512 << 10 // one batch of ~5k points
	maxBatchPoints  = 2000
	// Clients send a heartbeat or batch at least every 30s; allow for jitter.
	readIdleTimeout = 90 * time.Second
	writeTimeout    = 10 * time.Second
)

type Server struct {
	log       *slog.Logger
	rdb       *redis.Client
	tokens    *auth.Tokens
	limits    telemetry.Limits
	streamMax int64
	tracking  *pb.TrackingConfig

	mu       sync.Mutex
	sessions map[string]*session // by vehicle ID

	stats struct {
		connections    atomic.Int64
		batches        atomic.Int64
		pointsAccepted atomic.Int64
		pointsRejected atomic.Int64
		queueErrors    atomic.Int64
	}
}

type session struct {
	vehicleID string
	conn      *websocket.Conn
	seenAt    time.Time // last presence write, to throttle Redis writes
}

// markSeen records that the phone is online, at most every 10 s.
func (s *Server) markSeen(ctx context.Context, sess *session) {
	now := time.Now()
	if now.Sub(sess.seenAt) < 10*time.Second {
		return
	}
	sess.seenAt = now
	if err := s.rdb.HSet(ctx, stream.PresenceKey, sess.vehicleID, now.UnixMilli()).Err(); err != nil {
		s.log.Warn("presence", "err", err)
	}
}

func (s *Server) handleWS(w http.ResponseWriter, r *http.Request) {
	vehicleID, err := s.tokens.VerifyDevice(bearerToken(r))
	if err != nil {
		http.Error(w, "unauthorized", http.StatusUnauthorized)
		return
	}

	conn, err := websocket.Accept(w, r, &websocket.AcceptOptions{
		// Native mobile clients send no Origin header; browsers never connect here.
		InsecureSkipVerify: true,
	})
	if err != nil {
		s.log.Warn("websocket accept", "err", err)
		return
	}
	conn.SetReadLimit(maxMessageBytes)

	sess := &session{vehicleID: vehicleID, conn: conn}
	s.register(sess)
	defer s.unregister(sess)

	log := s.log.With("vehicle_id", vehicleID)
	log.Info("device connected", "remote", r.RemoteAddr)

	ctx := r.Context()
	if err := s.send(ctx, sess, &pb.ServerMessage{Payload: &pb.ServerMessage_Config{Config: s.tracking}}); err != nil {
		return
	}

	for {
		readCtx, cancel := context.WithTimeout(ctx, readIdleTimeout)
		typ, data, err := conn.Read(readCtx)
		cancel()
		if err != nil {
			if status := websocket.CloseStatus(err); status != websocket.StatusNormalClosure && status != websocket.StatusGoingAway {
				log.Info("device disconnected", "err", err)
			}
			return
		}
		if typ != websocket.MessageBinary {
			conn.Close(websocket.StatusUnsupportedData, "expected protobuf binary frames")
			return
		}

		var msg pb.ClientMessage
		if err := proto.Unmarshal(data, &msg); err != nil {
			conn.Close(websocket.StatusInvalidFramePayloadData, "malformed message")
			return
		}
		s.markSeen(ctx, sess)

		switch p := msg.Payload.(type) {
		case *pb.ClientMessage_Batch:
			if err := s.handleBatch(ctx, sess, p.Batch); err != nil {
				log.Warn("batch rejected", "err", err)
				conn.Close(websocket.StatusPolicyViolation, err.Error())
				return
			}
		case *pb.ClientMessage_Heartbeat:
			// Receiving anything resets the idle timeout; nothing else to do.
		case *pb.ClientMessage_JobStatus:
			// Dispatch flow lands in a later step.
			log.Info("job status update", "job_id", p.JobStatus.GetJobId(), "status", p.JobStatus.GetStatus().String())
		}
	}
}

var errBatchTooLarge = errors.New("batch exceeds point limit")

func (s *Server) handleBatch(ctx context.Context, sess *session, batch *pb.TelemetryBatch) error {
	if len(batch.Points) > maxBatchPoints {
		return errBatchTooLarge
	}
	s.stats.batches.Add(1)

	res := telemetry.Sanitize(batch.Points, time.Now(), s.limits)
	s.stats.pointsRejected.Add(int64(res.Rejected))
	if res.Rejected > 0 {
		s.log.Info("points rejected", "vehicle_id", sess.vehicleID, "count", res.Rejected, "reasons", res.Reasons)
	}

	if len(res.Accepted) > 0 {
		clean, err := proto.Marshal(&pb.TelemetryBatch{Points: res.Accepted, IsBackfill: batch.IsBackfill})
		if err != nil {
			return err
		}
		err = s.rdb.XAdd(ctx, &redis.XAddArgs{
			Stream: stream.Telemetry,
			MaxLen: s.streamMax,
			Approx: true,
			Values: map[string]any{
				stream.FieldVehicleID:  sess.vehicleID,
				stream.FieldBatch:      clean,
				stream.FieldReceivedMs: time.Now().UnixMilli(),
			},
		}).Err()
		if err != nil {
			// No ack: the device keeps the points buffered and resends them.
			s.stats.queueErrors.Add(1)
			s.log.Error("queue batch", "vehicle_id", sess.vehicleID, "err", err)
			return nil
		}
		s.stats.pointsAccepted.Add(int64(len(res.Accepted)))
	}

	// Rejected points are acked too: resending an invalid fix never helps.
	return s.send(ctx, sess, &pb.ServerMessage{Payload: &pb.ServerMessage_Ack{Ack: &pb.BatchAck{AckedSeq: res.MaxSeq}}})
}

func (s *Server) send(ctx context.Context, sess *session, msg *pb.ServerMessage) error {
	data, err := proto.Marshal(msg)
	if err != nil {
		return err
	}
	ctx, cancel := context.WithTimeout(ctx, writeTimeout)
	defer cancel()
	return sess.conn.Write(ctx, websocket.MessageBinary, data)
}

// register replaces any existing session for the vehicle: a reconnecting
// device often arrives before the server notices the old socket is dead.
func (s *Server) register(sess *session) {
	s.mu.Lock()
	old := s.sessions[sess.vehicleID]
	s.sessions[sess.vehicleID] = sess
	s.mu.Unlock()
	s.stats.connections.Add(1)
	if old != nil {
		old.conn.Close(websocket.StatusPolicyViolation, "superseded by a newer connection")
	}
}

func (s *Server) unregister(sess *session) {
	s.mu.Lock()
	if s.sessions[sess.vehicleID] == sess {
		delete(s.sessions, sess.vehicleID)
	}
	s.mu.Unlock()
	s.stats.connections.Add(-1)
	sess.conn.CloseNow()
}

func (s *Server) closeAll() {
	s.mu.Lock()
	defer s.mu.Unlock()
	for _, sess := range s.sessions {
		sess.conn.Close(websocket.StatusGoingAway, "server shutting down")
	}
}

func (s *Server) handleMetrics(w http.ResponseWriter, _ *http.Request) {
	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(map[string]int64{
		"connections":     s.stats.connections.Load(),
		"batches":         s.stats.batches.Load(),
		"points_accepted": s.stats.pointsAccepted.Load(),
		"points_rejected": s.stats.pointsRejected.Load(),
		"queue_errors":    s.stats.queueErrors.Load(),
	})
}

// forwardDispatch relays job offers and cancellations published by the api
// service to the vehicle's phone, if it's connected to this instance. Phones
// also poll for their current job, so a missed message only delays it.
func (s *Server) forwardDispatch(ctx context.Context) {
	ps := s.rdb.PSubscribe(ctx, stream.DevicePattern)
	go func() {
		<-ctx.Done()
		ps.Close()
	}()
	for m := range ps.Channel() {
		vehicleID := strings.TrimPrefix(m.Channel, stream.DeviceChannel(""))
		s.mu.Lock()
		sess := s.sessions[vehicleID]
		s.mu.Unlock()
		if sess == nil {
			continue
		}
		wctx, cancel := context.WithTimeout(ctx, writeTimeout)
		err := sess.conn.Write(wctx, websocket.MessageBinary, []byte(m.Payload))
		cancel()
		if err != nil {
			s.log.Warn("forward dispatch message", "vehicle_id", vehicleID, "err", err)
		} else {
			s.log.Info("dispatch message delivered", "vehicle_id", vehicleID)
		}
	}
}

func bearerToken(r *http.Request) string {
	if h := r.Header.Get("Authorization"); strings.HasPrefix(h, "Bearer ") {
		return strings.TrimPrefix(h, "Bearer ")
	}
	// Some mobile WebSocket clients can't set headers on the upgrade request.
	return r.URL.Query().Get("token")
}
