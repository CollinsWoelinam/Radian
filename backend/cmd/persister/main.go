// Command persister drains the telemetry stream into TimescaleDB/PostGIS in
// bulk. Entries are acked only after the database commit, so a crash between
// read and write replays the batch instead of losing it.
package main

import (
	"context"
	"errors"
	"log/slog"
	"os"
	"os/signal"
	"strings"
	"syscall"
	"time"

	"github.com/jackc/pgx/v5/pgxpool"
	"github.com/redis/go-redis/v9"

	"github.com/CollinsWoelinam/Radian/backend/internal/config"
	"github.com/CollinsWoelinam/Radian/backend/internal/stream"
)

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

	hostname, _ := os.Hostname()
	p := &Persister{
		log:           log,
		rdb:           rdb,
		store:         &Store{pool: pool},
		consumer:      config.String("PERSISTER_CONSUMER", hostname),
		flushInterval: config.Duration("PERSISTER_FLUSH_INTERVAL", 2*time.Second),
		maxRows:       config.Int("PERSISTER_MAX_ROWS", 20_000),
	}

	if err := p.ensureGroup(ctx); err != nil {
		log.Error("create consumer group", "err", err)
		os.Exit(1)
	}

	log.Info("persister started", "consumer", p.consumer, "flush_interval", p.flushInterval.String())
	if err := p.Run(ctx); err != nil && !errors.Is(err, context.Canceled) {
		log.Error("persister stopped", "err", err)
		os.Exit(1)
	}
}

func (p *Persister) ensureGroup(ctx context.Context) error {
	err := p.rdb.XGroupCreateMkStream(ctx, stream.Telemetry, stream.PersisterGroup, "0").Err()
	if err != nil && !strings.Contains(err.Error(), "BUSYGROUP") {
		return err
	}
	return nil
}
