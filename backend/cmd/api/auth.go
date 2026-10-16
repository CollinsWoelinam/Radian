package main

import (
	"encoding/json"
	"errors"
	"net/http"
	"strings"
	"sync"
	"time"

	"github.com/jackc/pgx/v5"
	"golang.org/x/crypto/bcrypt"
)

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
		a.log.Warn("driver login rate limited", "phone_suffix", phoneSuffix(req.Phone))
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
		a.log.Info("driver login failed", "reason", "unknown_phone", "phone_suffix", phoneSuffix(req.Phone))
		writeError(w, http.StatusUnauthorized, "invalid_credentials", "Phone number or password is incorrect.")
		return
	}
	if err != nil {
		a.log.Error("login query", "err", err)
		writeError(w, http.StatusInternalServerError, "internal", "Something went wrong. Try again.")
		return
	}
	if bcrypt.CompareHashAndPassword([]byte(passwordHash), []byte(req.Password)) != nil {
		a.log.Info("driver login failed", "reason", "bad_password", "driver_id", resp.Driver.ID)
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

type refreshResponse struct {
	Token     string    `json:"token"`
	ExpiresAt time.Time `json:"expires_at"`
}

// handleDeviceRefresh swaps a still-valid device token for a fresh one, so a
// driver on a long run of shifts is never signed out mid-shift. It refuses
// once the vehicle no longer has an active assignment.
func (a *app) handleDeviceRefresh(w http.ResponseWriter, r *http.Request) {
	token, ok := strings.CutPrefix(r.Header.Get("Authorization"), "Bearer ")
	if !ok {
		writeError(w, http.StatusUnauthorized, "invalid_token", "Sign in again.")
		return
	}
	vehicleID, err := a.tokens.VerifyDevice(token)
	if err != nil {
		writeError(w, http.StatusUnauthorized, "invalid_token", "Sign in again.")
		return
	}
	var assigned bool
	err = a.pool.QueryRow(r.Context(),
		`SELECT EXISTS (SELECT 1 FROM vehicle_assignments WHERE vehicle_id = $1 AND ended_at IS NULL)`,
		vehicleID).Scan(&assigned)
	if err != nil {
		a.log.Error("refresh query", "err", err)
		writeError(w, http.StatusInternalServerError, "internal", "Something went wrong. Try again.")
		return
	}
	if !assigned {
		writeError(w, http.StatusUnauthorized, "no_vehicle", "You are no longer assigned to this vehicle. Sign in again.")
		return
	}
	resp := refreshResponse{ExpiresAt: time.Now().Add(a.tokenTTL).UTC()}
	if resp.Token, err = a.tokens.IssueDevice(vehicleID, a.tokenTTL); err != nil {
		a.log.Error("issue token", "err", err)
		writeError(w, http.StatusInternalServerError, "internal", "Something went wrong. Try again.")
		return
	}
	a.log.Info("device token refreshed", "vehicle_id", vehicleID)
	writeJSON(w, http.StatusOK, resp)
}

// phoneSuffix logs only the last 3 digits, enough to correlate attempts
// without writing full phone numbers to logs.
func phoneSuffix(p string) string {
	if len(p) <= 3 {
		return p
	}
	return "…" + p[len(p)-3:]
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

const dispatcherTokenTTL = 12 * time.Hour

type dispatcherLoginRequest struct {
	Email    string `json:"email"`
	Password string `json:"password"`
}

type dispatcherLoginResponse struct {
	Token      string    `json:"token"`
	ExpiresAt  time.Time `json:"expires_at"`
	Dispatcher struct {
		ID       string `json:"id"`
		FullName string `json:"full_name"`
		Email    string `json:"email"`
	} `json:"dispatcher"`
}

func (a *app) handleDispatcherLogin(w http.ResponseWriter, r *http.Request) {
	var req dispatcherLoginRequest
	if err := json.NewDecoder(http.MaxBytesReader(w, r.Body, 4<<10)).Decode(&req); err != nil {
		writeError(w, http.StatusBadRequest, "invalid_request", "Expected JSON with email and password.")
		return
	}
	req.Email = strings.ToLower(strings.TrimSpace(req.Email))
	if req.Email == "" || req.Password == "" {
		writeError(w, http.StatusBadRequest, "invalid_request", "Email and password are required.")
		return
	}
	if !a.limiter.allow("dispatcher:" + req.Email) {
		a.log.Warn("dispatcher login rate limited")
		writeError(w, http.StatusTooManyRequests, "rate_limited", "Too many attempts. Try again in a minute.")
		return
	}

	var (
		resp dispatcherLoginResponse
		hash string
	)
	err := a.pool.QueryRow(r.Context(),
		`SELECT id, full_name, email, password_hash FROM dispatchers WHERE email = $1`, req.Email,
	).Scan(&resp.Dispatcher.ID, &resp.Dispatcher.FullName, &resp.Dispatcher.Email, &hash)
	if errors.Is(err, pgx.ErrNoRows) {
		bcrypt.CompareHashAndPassword(dummyHash, []byte(req.Password))
		a.log.Info("dispatcher login failed", "reason", "unknown_email")
		writeError(w, http.StatusUnauthorized, "invalid_credentials", "Email or password is incorrect.")
		return
	}
	if err != nil {
		a.log.Error("dispatcher login query", "err", err)
		writeError(w, http.StatusInternalServerError, "internal", "Something went wrong. Try again.")
		return
	}
	if bcrypt.CompareHashAndPassword([]byte(hash), []byte(req.Password)) != nil {
		a.log.Info("dispatcher login failed", "reason", "bad_password", "dispatcher_id", resp.Dispatcher.ID)
		writeError(w, http.StatusUnauthorized, "invalid_credentials", "Email or password is incorrect.")
		return
	}
	resp.ExpiresAt = time.Now().Add(dispatcherTokenTTL).UTC()
	if resp.Token, err = a.tokens.Issue("dispatcher", resp.Dispatcher.ID, dispatcherTokenTTL); err != nil {
		writeError(w, http.StatusInternalServerError, "internal", "Something went wrong. Try again.")
		return
	}
	a.limiter.reset("dispatcher:" + req.Email)
	a.log.Info("dispatcher login", "dispatcher_id", resp.Dispatcher.ID)
	writeJSON(w, http.StatusOK, resp)
}
