// Command api serves Radian's REST endpoints: driver and dispatcher sign-in,
// the jobs and geofences APIs for the dashboard, the driver's job actions, and the dispatch
// engine that offers each job to the nearest available vehicle by drive time.
package main

import (
	"context"
	"errors"
	"log/slog"
	"net"
	"net/http"
	"os"
	"os/signal"
	"slices"
	"strings"
	"syscall"
	"time"

	"github.com/jackc/pgx/v5/pgxpool"
	"github.com/redis/go-redis/v9"

	"github.com/CollinsWoelinam/Radian/backend/internal/auth"
	"github.com/CollinsWoelinam/Radian/backend/internal/config"
	"github.com/CollinsWoelinam/Radian/backend/internal/osrm"
)

type app struct {
	log            *slog.Logger
	pool           *pgxpool.Pool
	tokens         *auth.Tokens
	tokenTTL       time.Duration
	limiter        *loginLimiter
	dispatch       *Dispatcher
	rdb            *redis.Client
	allowedOrigins []string
}

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

	a := &app{
		log:      log,
		pool:     pool,
		tokens:   tokens,
		tokenTTL: config.Duration("DEVICE_TOKEN_TTL", 7*24*time.Hour),
		limiter:  newLoginLimiter(10, time.Minute),
		rdb:      rdb,
		dispatch: &Dispatcher{
			log:          log,
			pool:         pool,
			notify:       &Notifier{rdb: rdb, log: log},
			osrm:         osrm.New(config.String("OSRM_URL", "http://localhost:5001")),
			offerTTL:     config.Duration("DISPATCH_OFFER_TTL", 30*time.Second),
			retryEvery:   config.Duration("DISPATCH_RETRY_EVERY", 15*time.Second),
			onlineWithin: config.Duration("DISPATCH_ONLINE_WITHIN", 2*time.Minute),
			maxRadiusM:   config.Float("DISPATCH_MAX_RADIUS_M", 30_000),
		},
		allowedOrigins: strings.Split(config.String("API_ALLOWED_ORIGINS", "http://localhost:3000"), ","),
	}
	go a.dispatch.Run(ctx)

	mux := http.NewServeMux()
	// Sign-in
	mux.HandleFunc("POST /v1/auth/driver/login", a.handleDriverLogin)
	mux.HandleFunc("POST /v1/auth/device/refresh", a.handleDeviceRefresh)
	mux.HandleFunc("POST /v1/auth/dispatcher/login", a.handleDispatcherLogin)
	// Dashboard (dispatcher token)
	mux.Handle("GET /v1/jobs", a.dispatcherOnly(a.handleListJobs))
	mux.Handle("POST /v1/jobs", a.dispatcherOnly(a.handleCreateJob))
	mux.Handle("GET /v1/jobs/{id}", a.dispatcherOnly(a.handleGetJob))
	mux.Handle("GET /v1/jobs/{id}/candidates", a.dispatcherOnly(a.handleJobCandidates))
	mux.Handle("POST /v1/jobs/{id}/offer", a.dispatcherOnly(a.handleOfferJob))
	mux.Handle("POST /v1/jobs/{id}/cancel", a.dispatcherOnly(a.handleCancelJob))
	mux.Handle("GET /v1/geofences", a.dispatcherOnly(a.handleListGeofences))
	mux.Handle("POST /v1/geofences", a.dispatcherOnly(a.handleCreateGeofence))
	mux.Handle("DELETE /v1/geofences/{id}", a.dispatcherOnly(a.handleDeleteGeofence))
	mux.Handle("GET /v1/geofence-events", a.dispatcherOnly(a.handleGeofenceEvents))
	// Driver app (device token)
	mux.Handle("GET /v1/driver/job", a.deviceOnly(a.handleDriverCurrentJob))
	mux.Handle("POST /v1/driver/jobs/{id}/accept", a.deviceOnly(a.handleDriverAccept))
	mux.Handle("POST /v1/driver/jobs/{id}/decline", a.deviceOnly(a.handleDriverDecline))
	mux.Handle("POST /v1/driver/jobs/{id}/status", a.deviceOnly(a.handleDriverStatus))
	mux.HandleFunc("GET /healthz", func(w http.ResponseWriter, _ *http.Request) { w.Write([]byte("ok")) })

	addr := config.String("API_ADDR", ":8080")
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

	log.Info("api listening", "addr", addr)
	if err := srv.ListenAndServe(); err != nil && !errors.Is(err, http.ErrServerClosed) {
		log.Error("listen", "err", err)
		os.Exit(1)
	}
}

type ctxKey int

const subjectKey ctxKey = 0

// subject returns the dispatcher or vehicle ID the request was authenticated as.
func subject(r *http.Request) string {
	s, _ := r.Context().Value(subjectKey).(string)
	return s
}

func (a *app) requireAudience(audience string, next http.HandlerFunc) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		token, ok := strings.CutPrefix(r.Header.Get("Authorization"), "Bearer ")
		if !ok {
			writeError(w, http.StatusUnauthorized, "unauthorized", "Sign in to continue.")
			return
		}
		sub, err := a.tokens.Verify(audience, token)
		if err != nil {
			writeError(w, http.StatusUnauthorized, "unauthorized", "Your session has expired. Sign in again.")
			return
		}
		next(w, r.WithContext(context.WithValue(r.Context(), subjectKey, sub)))
	})
}

func (a *app) dispatcherOnly(next http.HandlerFunc) http.Handler {
	return a.requireAudience(auth.AudienceDispatcher, next)
}

func (a *app) deviceOnly(next http.HandlerFunc) http.Handler {
	return a.requireAudience(auth.AudienceDevice, next)
}

// cors lets the dashboard (a different origin in development) call the API
// with a bearer token. Native apps send no Origin and are unaffected.
func (a *app) cors(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if origin := r.Header.Get("Origin"); origin != "" && slices.Contains(a.allowedOrigins, origin) {
			h := w.Header()
			h.Set("Access-Control-Allow-Origin", origin)
			h.Set("Vary", "Origin")
			h.Set("Access-Control-Allow-Headers", "Authorization, Content-Type")
			h.Set("Access-Control-Allow-Methods", "GET, POST, DELETE, OPTIONS")
			h.Set("Access-Control-Max-Age", "600")
		}
		if r.Method == http.MethodOptions {
			w.WriteHeader(http.StatusNoContent)
			return
		}
		next.ServeHTTP(w, r)
	})
}
