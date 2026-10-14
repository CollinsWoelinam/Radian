// Command simulator drives a fake fleet around Accra against the ingest
// service. Each vehicle behaves like the driver app: it filters stationary
// noise, buffers points until acked, drops into network dead zones, and
// uploads its backlog as a backfill batch on reconnect.
package main

import (
	"context"
	"flag"
	"fmt"
	"log/slog"
	"math/rand/v2"
	"os"
	"os/signal"
	"sync"
	"sync/atomic"
	"syscall"
	"time"

	"github.com/jackc/pgx/v5/pgxpool"

	"github.com/CollinsWoelinam/Radian/backend/internal/auth"
	"github.com/CollinsWoelinam/Radian/backend/internal/config"
)

type stats struct {
	sent, acked, filtered, deadZones, reconnects atomic.Int64
}

func main() {
	n := flag.Int("n", 50, "number of vehicles")
	interval := flag.Duration("interval", 2*time.Second, "GPS fix interval per vehicle")
	url := flag.String("url", "ws://localhost:8081/v1/telemetry/ws", "ingest WebSocket URL")
	dropout := flag.Float64("dropout", 0.003, "per-tick probability a vehicle enters a dead zone")
	flag.Parse()

	log := slog.New(slog.NewTextHandler(os.Stdout, nil))
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
	ids, err := seedVehicles(ctx, pool, *n)
	pool.Close()
	if err != nil {
		log.Error("seed vehicles", "err", err)
		os.Exit(1)
	}
	log.Info("seeded vehicles", "count", len(ids))

	var st stats
	var wg sync.WaitGroup
	for i, id := range ids {
		token, err := tokens.IssueDevice(id, 24*time.Hour)
		if err != nil {
			log.Error("issue token", "err", err)
			os.Exit(1)
		}
		v := newVehicle(id, token, *url, *interval, *dropout, &st, log)
		wg.Add(1)
		go func() {
			defer wg.Done()
			// Stagger startup so connections don't arrive as one thundering herd.
			select {
			case <-time.After(time.Duration(i) * *interval / time.Duration(len(ids))):
			case <-ctx.Done():
				return
			}
			v.run(ctx)
		}()
	}

	ticker := time.NewTicker(10 * time.Second)
	defer ticker.Stop()
	for {
		select {
		case <-ctx.Done():
			wg.Wait()
			return
		case <-ticker.C:
			log.Info("stats",
				"sent", st.sent.Load(), "acked", st.acked.Load(),
				"filtered", st.filtered.Load(), "dead_zones", st.deadZones.Load(),
				"reconnects", st.reconnects.Load())
		}
	}
}

// seedVehicles upserts SIM-#### vehicles so reruns reuse the same IDs.
func seedVehicles(ctx context.Context, pool *pgxpool.Pool, n int) ([]string, error) {
	kinds := []string{"CAR", "CAR", "MOTORBIKE", "VAN", "TRUCK", "AMBULANCE"}
	ids := make([]string, 0, n)
	for i := 1; i <= n; i++ {
		var id string
		err := pool.QueryRow(ctx, `
			INSERT INTO vehicles (license_plate, kind, status)
			VALUES ($1, $2, 'IDLE')
			ON CONFLICT (license_plate) DO UPDATE SET updated_at = NOW()
			RETURNING id`,
			fmt.Sprintf("SIM-%04d", i), kinds[rand.IntN(len(kinds))],
		).Scan(&id)
		if err != nil {
			return nil, err
		}
		ids = append(ids, id)
	}
	return ids, nil
}
