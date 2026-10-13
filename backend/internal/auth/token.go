// Package auth issues and verifies device tokens. A device token binds a
// WebSocket session to exactly one vehicle; the vehicle ID is never taken
// from the telemetry payload.
package auth

import (
	"errors"
	"fmt"
	"time"

	"github.com/golang-jwt/jwt/v5"
)

const issuer = "radian"

type Tokens struct {
	secret []byte
}

func New(secret string) (*Tokens, error) {
	if len(secret) < 32 {
		return nil, errors.New("JWT secret must be at least 32 bytes")
	}
	return &Tokens{secret: []byte(secret)}, nil
}

// IssueDevice returns a signed token whose subject is the vehicle ID.
func (t *Tokens) IssueDevice(vehicleID string, ttl time.Duration) (string, error) {
	now := time.Now()
	claims := jwt.RegisteredClaims{
		Issuer:    issuer,
		Subject:   vehicleID,
		Audience:  jwt.ClaimStrings{"device"},
		IssuedAt:  jwt.NewNumericDate(now),
		ExpiresAt: jwt.NewNumericDate(now.Add(ttl)),
	}
	return jwt.NewWithClaims(jwt.SigningMethodHS256, claims).SignedString(t.secret)
}

// VerifyDevice validates the token and returns the vehicle ID it was issued for.
func (t *Tokens) VerifyDevice(token string) (string, error) {
	var claims jwt.RegisteredClaims
	_, err := jwt.ParseWithClaims(token, &claims,
		func(*jwt.Token) (any, error) { return t.secret, nil },
		jwt.WithValidMethods([]string{jwt.SigningMethodHS256.Alg()}),
		jwt.WithIssuer(issuer),
		jwt.WithAudience("device"),
		jwt.WithExpirationRequired(),
	)
	if err != nil {
		return "", fmt.Errorf("invalid device token: %w", err)
	}
	if claims.Subject == "" {
		return "", errors.New("invalid device token: missing subject")
	}
	return claims.Subject, nil
}
