// Command api serves Radian's REST endpoints. For now that is driver login,
// which exchanges phone + password for a device token bound to the vehicle the
// driver is currently assigned to. Dispatch endpoints land here next.
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
	"strings"
	"sync"
	"syscall"
	"time"

	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgxpool"
	"golang.org/x/crypto/bcrypt"

	"github.com/CollinsWoelinam/Radian/backend/internal/auth"
	"github.com/CollinsWoelinam/Radian/backend/internal/config"
)

type app struct {
	log      *slog.Logger
	pool     *pgxpool.Pool
	tokens   *auth.Tokens
	tokenTTL time.Duration
	limiter  *loginLimiter
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

	a := &app{
		log:      log,
		pool:     pool,
		tokens:   tokens,
		tokenTTL: config.Duration("DEVICE_TOKEN_TTL", 7*24*time.Hour),
		limiter:  newLoginLimiter(10, time.Minute),
	}

	mux := http.NewServeMux()
	mux.HandleFunc("POST /v1/auth/driver/login", a.handleDriverLogin)
	mux.HandleFunc("GET /healthz", func(w http.ResponseWriter, _ *http.Request) { w.Write([]byte("ok")) })

	addr := config.String("API_ADDR", ":8080")
	srv := &http.Server{
		Addr:              addr,
		Handler:           mux,
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

type loginRequest struct {
	Phone    string `json:"phone"`
	Password string `json:"password"`
}

type loginResponse struct {
	Token     string    `json:"token"`
	ExpiresAt time.Time `json:"expires_at"`
	Driver    struct {
		ID       string `json:"id"`
		FullName string `json:"full_name"`
	} `json:"driver"`
	Vehicle struct {
		ID           string `json:"id"`
		LicensePlate string `json:"license_plate"`
		Kind         string `json:"kind"`
	} `json:"vehicle"`
}

// A valid hash to compare against when the phone is unknown, so response
// time doesn't reveal which phone numbers are registered.
var dummyHash, _ = bcrypt.GenerateFromPassword([]byte("radian-timing-equalizer"), bcrypt.DefaultCost)

func (a *app) handleDriverLogin(w http.ResponseWriter, r *http.Request) {
	var req loginRequest
	if err := json.NewDecoder(http.MaxBytesReader(w, r.Body, 4<<10)).Decode(&req); err != nil {
		writeError(w, http.StatusBadRequest, "invalid_request", "Expected JSON with phone and password.")
		return
	}
	req.Phone = normalizePhone(req.Phone)
	if req.Phone == "" || req.Password == "" {
		writeError(w, http.StatusBadRequest, "invalid_request", "Phone and password are required.")
		return
	}
	if !a.limiter.allow(req.Phone) {
		writeError(w, http.StatusTooManyRequests, "rate_limited", "Too many attempts. Try again in a minute.")
		return
	}

	var (
		resp         loginResponse
		passwordHash string
		vehicleID    *string
		plate, kind  *string
	)
	err := a.pool.QueryRow(r.Context(), `
		SELECT d.id, d.full_name, d.password_hash, v.id, v.license_plate, v.kind::text
		FROM drivers d
		LEFT JOIN vehicle_assignments va ON va.driver_id = d.id AND va.ended_at IS NULL
		LEFT JOIN vehicles v ON v.id = va.vehicle_id
		WHERE d.phone = $1`, req.Phone,
	).Scan(&resp.Driver.ID, &resp.Driver.FullName, &passwordHash, &vehicleID, &plate, &kind)
	if errors.Is(err, pgx.ErrNoRows) {
		bcrypt.CompareHashAndPassword(dummyHash, []byte(req.Password))
		writeError(w, http.StatusUnauthorized, "invalid_credentials", "Phone number or password is incorrect.")
		return
	}
	if err != nil {
		a.log.Error("login query", "err", err)
		writeError(w, http.StatusInternalServerError, "internal", "Something went wrong. Try again.")
		return
	}
	if bcrypt.CompareHashAndPassword([]byte(passwordHash), []byte(req.Password)) != nil {
		writeError(w, http.StatusUnauthorized, "invalid_credentials", "Phone number or password is incorrect.")
		return
	}
	if vehicleID == nil {
		writeError(w, http.StatusConflict, "no_vehicle", "You are not assigned to a vehicle. Ask your dispatcher.")
		return
	}

	resp.Vehicle.ID, resp.Vehicle.LicensePlate, resp.Vehicle.Kind = *vehicleID, *plate, *kind
	resp.ExpiresAt = time.Now().Add(a.tokenTTL).UTC()
	resp.Token, err = a.tokens.IssueDevice(*vehicleID, a.tokenTTL)
	if err != nil {
		a.log.Error("issue token", "err", err)
		writeError(w, http.StatusInternalServerError, "internal", "Something went wrong. Try again.")
		return
	}
	a.limiter.reset(req.Phone)
	a.log.Info("driver login", "driver_id", resp.Driver.ID, "vehicle_id", resp.Vehicle.ID)
	writeJSON(w, http.StatusOK, resp)
}

// normalizePhone keeps digits and a leading +, so "024 000 0001" and
// "0240000001" match the same driver.
func normalizePhone(p string) string {
	var b strings.Builder
	for i, c := range strings.TrimSpace(p) {
		if (c >= '0' && c <= '9') || (c == '+' && i == 0) {
			b.WriteRune(c)
		}
	}
	return b.String()
}

func writeJSON(w http.ResponseWriter, status int, v any) {
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(status)
	json.NewEncoder(w).Encode(v)
}

func writeError(w http.ResponseWriter, status int, code, message string) {
	writeJSON(w, status, map[string]string{"error": code, "message": message})
}

// loginLimiter allows n attempts per phone per window. In-memory is enough
// for a single api instance; move it to Redis when scaling out.
type loginLimiter struct {
	n      int
	window time.Duration
	mu     sync.Mutex
	hits   map[string][]time.Time
}

func newLoginLimiter(n int, window time.Duration) *loginLimiter {
	return &loginLimiter{n: n, window: window, hits: make(map[string][]time.Time)}
}

func (l *loginLimiter) allow(key string) bool {
	l.mu.Lock()
	defer l.mu.Unlock()
	now := time.Now()
	recent := l.hits[key][:0]
	for _, t := range l.hits[key] {
		if now.Sub(t) < l.window {
			recent = append(recent, t)
		}
	}
	if len(recent) >= l.n {
		l.hits[key] = recent
		return false
	}
	l.hits[key] = append(recent, now)
	return true
}

func (l *loginLimiter) reset(key string) {
	l.mu.Lock()
	defer l.mu.Unlock()
	delete(l.hits, key)
}
