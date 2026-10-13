// Package config reads service settings from environment variables.
package config

import (
	"log/slog"
	"os"
	"strconv"
	"time"
)

func String(key, def string) string {
	if v, ok := os.LookupEnv(key); ok && v != "" {
		return v
	}
	return def
}

func Int(key string, def int) int {
	v := String(key, "")
	if v == "" {
		return def
	}
	n, err := strconv.Atoi(v)
	if err != nil {
		slog.Warn("invalid int env var, using default", "key", key, "value", v, "default", def)
		return def
	}
	return n
}

func Float(key string, def float64) float64 {
	v := String(key, "")
	if v == "" {
		return def
	}
	f, err := strconv.ParseFloat(v, 64)
	if err != nil {
		slog.Warn("invalid float env var, using default", "key", key, "value", v, "default", def)
		return def
	}
	return f
}

func Duration(key string, def time.Duration) time.Duration {
	v := String(key, "")
	if v == "" {
		return def
	}
	d, err := time.ParseDuration(v)
	if err != nil {
		slog.Warn("invalid duration env var, using default", "key", key, "value", v, "default", def)
		return def
	}
	return d
}
