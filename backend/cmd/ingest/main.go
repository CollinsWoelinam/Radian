// Command ingest accepts telemetry from driver devices over WebSocket and
// appends it to a Redis Stream for the persister and broadcast services.
package main

import (
	"context"
	"errors"
	"log/slog"
	"net"
	"net/http"
	"os"
	"os/signal"
	"syscall"
	"time"

	"github.com/redis/go-redis/v9"

	pb "github.com/CollinsWoelinam/Radian/backend/gen/radian/telemetry/v1"
	"github.com/CollinsWoelinam/Radian/backend/internal/auth"
	"github.com/CollinsWoelinam/Radian/backend/internal/config"
	"github.com/CollinsWoelinam/Radian/backend/internal/telemetry"
)

func main() {
	log := slog.New(slog.NewJSONHandler(os.Stdout, nil))
	slog.SetDefault(log)

	ctx, stop := signal.NotifyContext(context.Background(), os.Interrupt, syscall.SIGTERM)
	defer stop()

	tokens, err := auth.New(config.String("JWT_SECRET", ""))
	if err != nil {
		log.Error("auth setup", "err", err)
		os.Exit(1)
	}

	ropts, err := redis.ParseURL(config.String("REDIS_URL", "redis://localhost:6380/0"))
	if err != nil {
		log.Error("parse REDIS_URL", "err", err)
		os.Exit(1)
	}
	rdb := redis.NewClient(ropts)
	defer rdb.Close()
	if err := rdb.Ping(ctx).Err(); err != nil {
		log.Error("redis ping", "err", err)
		os.Exit(1)
	}

	limits := telemetry.DefaultLimits()
	limits.MaxAccuracyM = config.Float("INGEST_MAX_ACCURACY_M", limits.MaxAccuracyM)

	srv := &Server{
		log:       log,
		rdb:       rdb,
		tokens:    tokens,
		limits:    limits,
		streamMax: int64(config.Int("TELEMETRY_STREAM_MAXLEN", 1_000_000)),
		tracking: &pb.TrackingConfig{
			MovingIntervalMs:   int32(config.Int("TRACKING_MOVING_INTERVAL_MS", 2000)),
			DistanceFilterM:    int32(config.Int("TRACKING_DISTANCE_FILTER_M", 10)),
			MaxAccuracyM:       float32(limits.MaxAccuracyM),
			StationarySpeedKmh: float32(config.Float("TRACKING_STATIONARY_SPEED_KMH", 5)),
		},
		sessions: make(map[string]*session),
	}

	mux := http.NewServeMux()
	mux.HandleFunc("GET /v1/telemetry/ws", srv.handleWS)
	mux.HandleFunc("GET /healthz", func(w http.ResponseWriter, r *http.Request) {
		if err := rdb.Ping(r.Context()).Err(); err != nil {
			http.Error(w, "redis unavailable", http.StatusServiceUnavailable)
			return
		}
		w.Write([]byte("ok"))
	})
	mux.HandleFunc("GET /metrics", srv.handleMetrics)

	addr := config.String("INGEST_ADDR", ":8081")
	httpSrv := &http.Server{
		Addr:              addr,
		Handler:           mux,
		ReadHeaderTimeout: 10 * time.Second,
		BaseContext:       func(_ net.Listener) context.Context { return ctx },
	}

	go func() {
		<-ctx.Done()
		shutdownCtx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
		defer cancel()
		srv.closeAll()
		httpSrv.Shutdown(shutdownCtx)
	}()

	log.Info("ingest listening", "addr", addr)
	if err := httpSrv.ListenAndServe(); err != nil && !errors.Is(err, http.ErrServerClosed) {
		log.Error("listen", "err", err)
		os.Exit(1)
	}
}
