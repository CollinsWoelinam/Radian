// Command broadcast tails the telemetry stream and pushes coalesced, viewport-
// filtered fleet updates to dashboard clients over WebSocket. Every instance
// reads the whole stream (no consumer group), so instances scale horizontally.
package main

import (
	"context"
	"encoding/json"
	"errors"
	"log/slog"
	"net"
	"net/http"
	"os"
	"os/signal"
	"strconv"
	"strings"
	"syscall"
	"time"

	"github.com/coder/websocket"
	"github.com/jackc/pgx/v5/pgxpool"
	"github.com/redis/go-redis/v9"
	"google.golang.org/protobuf/proto"

	pb "github.com/CollinsWoelinam/Radian/backend/gen/radian/telemetry/v1"
	"github.com/CollinsWoelinam/Radian/backend/internal/auth"
	"github.com/CollinsWoelinam/Radian/backend/internal/config"
	"github.com/CollinsWoelinam/Radian/backend/internal/stream"
)

type app struct {
	tokens         *auth.Tokens
	log            *slog.Logger
	rdb            *redis.Client
	pool           *pgxpool.Pool
	hub            *Hub
	allowedOrigins []string
}

func main() {
	log := slog.New(slog.NewJSONHandler(os.Stdout, nil))
	slog.SetDefault(log)

	ctx, stop := signal.NotifyContext(context.Background(), os.Interrupt, syscall.SIGTERM)
	defer stop()

	pool, err := pgxpool.New(ctx, config.String("DATABASE_URL", "postgres://radian:radian@localhost:5434/radian?sslmode=disable"))
	if err != nil {
		log.Error("postgres connect", "err", err)
		os.Exit(1)
	}
	defer pool.Close()

	ropts, err := redis.ParseURL(config.String("REDIS_URL", "redis://localhost:6380/0"))
	if err != nil {
		log.Error("parse REDIS_URL", "err", err)
		os.Exit(1)
	}
	rdb := redis.NewClient(ropts)
	defer rdb.Close()

	tokens, err := auth.New(config.String("JWT_SECRET", ""))
	if err != nil {
		log.Error("auth setup", "err", err)
		os.Exit(1)
	}

	a := &app{
		tokens:         tokens,
		log:            log,
		rdb:            rdb,
		pool:           pool,
		hub:            NewHub(config.Duration("BROADCAST_OFFLINE_AFTER", 2*time.Minute)),
		allowedOrigins: strings.Split(config.String("BROADCAST_ALLOWED_ORIGINS", "localhost:3000"), ","),
	}

	// Note the stream position *before* loading the snapshot so nothing that
	// lands in between is missed (replays are harmless: Apply ignores old fixes).
	cursor, err := a.streamTail(ctx)
	if err != nil {
		log.Error("read stream tail", "err", err)
		os.Exit(1)
	}
	if err := a.loadSnapshot(ctx); err != nil {
		log.Error("load snapshot", "err", err)
		os.Exit(1)
	}
	if err := a.refreshAssigned(ctx); err != nil {
		log.Error("load vehicle statuses", "err", err)
		os.Exit(1)
	}
	n, _ := a.hub.Stats()
	log.Info("snapshot loaded", "vehicles", n)

	go a.tailStream(ctx, cursor)
	go a.forwardJobs(ctx)
	go a.every(ctx, config.Duration("BROADCAST_TICK", time.Second), a.hub.Tick)
	go a.every(ctx, 10*time.Second, func(time.Time) {
		if err := a.refreshAssigned(ctx); err != nil && ctx.Err() == nil {
			log.Warn("refresh vehicle statuses", "err", err)
		}
		if err := a.refreshPresence(ctx); err != nil && ctx.Err() == nil {
			log.Warn("refresh presence", "err", err)
		}
	})

	mux := http.NewServeMux()
	mux.HandleFunc("GET /v1/fleet/ws", a.handleWS)
	mux.HandleFunc("GET /v1/vehicles", a.requireDispatcher(a.handleVehicles))
	mux.HandleFunc("GET /healthz", func(w http.ResponseWriter, _ *http.Request) { w.Write([]byte("ok")) })
	mux.HandleFunc("GET /metrics", func(w http.ResponseWriter, _ *http.Request) {
		v, c := a.hub.Stats()
		w.Header().Set("Content-Type", "application/json")
		json.NewEncoder(w).Encode(map[string]int{"vehicles": v, "clients": c})
	})

	addr := config.String("BROADCAST_ADDR", ":8082")
	srv := &http.Server{
		Addr:              addr,
		Handler:           a.cors(mux),
		ReadHeaderTimeout: 10 * time.Second,
		BaseContext:       func(net.Listener) context.Context { return ctx },
	}
	go func() {
		<-ctx.Done()
		sctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
		defer cancel()
		srv.Shutdown(sctx)
	}()

	log.Info("broadcast listening", "addr", addr)
	if err := srv.ListenAndServe(); err != nil && !errors.Is(err, http.ErrServerClosed) {
		log.Error("listen", "err", err)
		os.Exit(1)
	}
}

func (a *app) handleWS(w http.ResponseWriter, r *http.Request) {
	// Browsers can't set headers on a WebSocket upgrade, so the token rides in the query.
	if _, err := a.tokens.Verify(auth.AudienceDispatcher, r.URL.Query().Get("token")); err != nil {
		http.Error(w, "unauthorized", http.StatusUnauthorized)
		return
	}
	conn, err := websocket.Accept(w, r, &websocket.AcceptOptions{OriginPatterns: a.allowedOrigins})
	if err != nil {
		return
	}
	conn.SetReadLimit(4 << 10)

	c := newClient(conn)
	a.hub.Register(c)
	defer a.hub.Unregister(c)

	ctx, cancel := context.WithCancel(r.Context())
	defer cancel()
	go func() {
		if err := c.writeLoop(ctx); err != nil {
			cancel()
		}
		conn.CloseNow()
	}()

	for {
		_, data, err := conn.Read(ctx)
		if err != nil {
			return
		}
		var msg pb.DashboardClientMessage
		if proto.Unmarshal(data, &msg) != nil {
			conn.Close(websocket.StatusInvalidFramePayloadData, "malformed message")
			return
		}
		if sub := msg.GetSubscribe(); sub != nil && validBBox(sub.Viewport) {
			a.hub.Subscribe(c, sub.Viewport)
		}
	}
}

type vehicleInfo struct {
	ID           string `json:"id"`
	LicensePlate string `json:"license_plate"`
	Kind         string `json:"kind"`
}

// handleVehicles serves the registry the dashboard joins live deltas against.
// It moves to the api service once that exists.
func (a *app) handleVehicles(w http.ResponseWriter, r *http.Request) {
	rows, err := a.pool.Query(r.Context(), `SELECT id, license_plate, kind FROM vehicles ORDER BY license_plate`)
	if err != nil {
		http.Error(w, "query failed", http.StatusInternalServerError)
		return
	}
	defer rows.Close()
	out := []vehicleInfo{}
	for rows.Next() {
		var v vehicleInfo
		if err := rows.Scan(&v.ID, &v.LicensePlate, &v.Kind); err != nil {
			http.Error(w, "scan failed", http.StatusInternalServerError)
			return
		}
		out = append(out, v)
	}
	w.Header().Set("Content-Type", "application/json")
	w.Header().Set("Cache-Control", "max-age=30")
	json.NewEncoder(w).Encode(out)
}

func (a *app) requireDispatcher(next http.HandlerFunc) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		token, _ := strings.CutPrefix(r.Header.Get("Authorization"), "Bearer ")
		if _, err := a.tokens.Verify(auth.AudienceDispatcher, token); err != nil {
			http.Error(w, "unauthorized", http.StatusUnauthorized)
			return
		}
		next(w, r)
	}
}

// forwardJobs relays JobsChanged notices from the api service to dashboards.
func (a *app) forwardJobs(ctx context.Context) {
	ps := a.rdb.Subscribe(ctx, stream.JobsChannel)
	go func() {
		<-ctx.Done()
		ps.Close()
	}()
	for m := range ps.Channel() {
		var jc pb.JobsChanged
		if proto.Unmarshal([]byte(m.Payload), &jc) != nil {
			continue
		}
		// Job changes often flip a vehicle to/from ON_JOB; refresh now rather
		// than waiting for the periodic poll.
		if err := a.refreshAssigned(ctx); err != nil && ctx.Err() == nil {
			a.log.Warn("refresh vehicle statuses", "err", err)
		}
		a.hub.Notify(&pb.DashboardServerMessage{Payload: &pb.DashboardServerMessage_JobsChanged{JobsChanged: &jc}})
	}
}

func (a *app) cors(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if origin := r.Header.Get("Origin"); origin != "" {
			host := strings.TrimPrefix(strings.TrimPrefix(origin, "https://"), "http://")
			for _, allowed := range a.allowedOrigins {
				if host == allowed {
					w.Header().Set("Access-Control-Allow-Origin", origin)
					w.Header().Set("Vary", "Origin")
					w.Header().Set("Access-Control-Allow-Headers", "Authorization")
				}
			}
		}
		if r.Method == http.MethodOptions {
			w.WriteHeader(http.StatusNoContent)
			return
		}
		next.ServeHTTP(w, r)
	})
}

func (a *app) streamTail(ctx context.Context) (string, error) {
	msgs, err := a.rdb.XRevRangeN(ctx, stream.Telemetry, "+", "-", 1).Result()
	if err != nil {
		return "", err
	}
	if len(msgs) == 0 {
		return "0", nil
	}
	return msgs[0].ID, nil
}

func (a *app) loadSnapshot(ctx context.Context) error {
	rows, err := a.pool.Query(ctx, `
		SELECT vehicle_id, ST_Y(location), ST_X(location),
		       COALESCE(heading_deg, 0), COALESCE(speed_kmh, 0), recorded_at
		FROM vehicle_last_position`)
	if err != nil {
		return err
	}
	defer rows.Close()
	for rows.Next() {
		var (
			id             string
			lat, lon       float64
			heading, speed float32
			recordedAt     time.Time
		)
		if err := rows.Scan(&id, &lat, &lon, &heading, &speed, &recordedAt); err != nil {
			return err
		}
		a.hub.Apply(id, &pb.LocationPoint{
			Latitude: lat, Longitude: lon, RecordedAtMs: recordedAt.UnixMilli(),
			HeadingDeg: &heading, SpeedKmh: &speed,
		})
	}
	return rows.Err()
}

func (a *app) refreshAssigned(ctx context.Context) error {
	rows, err := a.pool.Query(ctx, `SELECT id FROM vehicles WHERE status = 'ON_JOB'`)
	if err != nil {
		return err
	}
	defer rows.Close()
	assigned := map[string]pb.VehicleStatus{}
	for rows.Next() {
		var id string
		if err := rows.Scan(&id); err != nil {
			return err
		}
		assigned[id] = pb.VehicleStatus_VEHICLE_STATUS_ON_JOB
	}
	if err := rows.Err(); err != nil {
		return err
	}
	a.hub.SetAssigned(assigned)
	return nil
}

func (a *app) refreshPresence(ctx context.Context) error {
	raw, err := a.rdb.HGetAll(ctx, stream.PresenceKey).Result()
	if err != nil {
		return err
	}
	p := make(map[string]int64, len(raw))
	for id, v := range raw {
		if ms, err := strconv.ParseInt(v, 10, 64); err == nil {
			p[id] = ms
		}
	}
	a.hub.SetPresence(p)
	return nil
}

func (a *app) tailStream(ctx context.Context, cursor string) {
	for ctx.Err() == nil {
		res, err := a.rdb.XRead(ctx, &redis.XReadArgs{
			Streams: []string{stream.Telemetry, cursor},
			Count:   2000,
			Block:   time.Second,
		}).Result()
		if err != nil {
			if err != redis.Nil && ctx.Err() == nil {
				a.log.Error("xread", "err", err)
				time.Sleep(time.Second)
			}
			continue
		}
		for _, s := range res {
			for _, msg := range s.Messages {
				cursor = msg.ID
				vehicleID, _ := msg.Values[stream.FieldVehicleID].(string)
				raw, _ := msg.Values[stream.FieldBatch].(string)
				var batch pb.TelemetryBatch
				if vehicleID == "" || proto.Unmarshal([]byte(raw), &batch) != nil || len(batch.Points) == 0 {
					continue
				}
				// Points are time-sorted by ingest; only the newest matters live.
				a.hub.Apply(vehicleID, batch.Points[len(batch.Points)-1])
			}
		}
	}
}

func (a *app) every(ctx context.Context, d time.Duration, f func(time.Time)) {
	t := time.NewTicker(d)
	defer t.Stop()
	for {
		select {
		case <-ctx.Done():
			return
		case now := <-t.C:
			f(now)
		}
	}
}

func validBBox(b *pb.BoundingBox) bool {
	return b != nil && b.MinLon < b.MaxLon && b.MinLat < b.MaxLat &&
		b.MinLat >= -90 && b.MaxLat <= 90 && b.MinLon >= -180 && b.MaxLon <= 180
}
