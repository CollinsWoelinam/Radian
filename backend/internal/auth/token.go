// Package auth issues and verifies signed tokens for the two kinds of
// clients. A device token binds a driver's phone to exactly one vehicle (the
// vehicle ID is never taken from a payload); a dispatcher token identifies a
// dashboard user.
package auth

import (
	"errors"
	"fmt"
	"time"

	"github.com/golang-jwt/jwt/v5"
)

const issuer = "radian"

const (
	AudienceDevice     = "device"
	AudienceDispatcher = "dispatcher"
)

type Tokens struct {
	secret []byte
}

func New(secret string) (*Tokens, error) {
	if len(secret) < 32 {
		return nil, errors.New("JWT secret must be at least 32 bytes")
	}
	return &Tokens{secret: []byte(secret)}, nil
}

// Issue returns a signed token for the given audience and subject.
func (t *Tokens) Issue(audience, subject string, ttl time.Duration) (string, error) {
	now := time.Now()
	claims := jwt.RegisteredClaims{
		Issuer:    issuer,
		Subject:   subject,
		Audience:  jwt.ClaimStrings{audience},
		IssuedAt:  jwt.NewNumericDate(now),
		ExpiresAt: jwt.NewNumericDate(now.Add(ttl)),
	}
	return jwt.NewWithClaims(jwt.SigningMethodHS256, claims).SignedString(t.secret)
}

// Verify validates a token for the given audience and returns its subject.
// A device token is rejected where a dispatcher token is required, and vice versa.
func (t *Tokens) Verify(audience, token string) (string, error) {
	var claims jwt.RegisteredClaims
	_, err := jwt.ParseWithClaims(token, &claims,
		func(*jwt.Token) (any, error) { return t.secret, nil },
		jwt.WithValidMethods([]string{jwt.SigningMethodHS256.Alg()}),
		jwt.WithIssuer(issuer),
		jwt.WithAudience(audience),
		jwt.WithExpirationRequired(),
	)
	if err != nil {
		return "", fmt.Errorf("invalid %s token: %w", audience, err)
	}
	if claims.Subject == "" {
		return "", fmt.Errorf("invalid %s token: missing subject", audience)
	}
	return claims.Subject, nil
}

// IssueDevice returns a device token whose subject is the vehicle ID.
func (t *Tokens) IssueDevice(vehicleID string, ttl time.Duration) (string, error) {
	return t.Issue(AudienceDevice, vehicleID, ttl)
}

// VerifyDevice returns the vehicle ID a device token was issued for.
func (t *Tokens) VerifyDevice(token string) (string, error) {
	return t.Verify(AudienceDevice, token)
}
