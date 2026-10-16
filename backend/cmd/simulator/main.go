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
	"github.com/CollinsWoelinam/Radian/backend/internal/osrm"
)

type stats struct {
	sent, acked, filtered, deadZones, reconnects atomic.Int64
	accepted, declined, completed                atomic.Int64
}

func main() {
	n := flag.Int("n", 50, "number of vehicles")
	interval := flag.Duration("interval", 2*time.Second, "GPS fix interval per vehicle")
	url := flag.String("url", "ws://localhost:8081/v1/telemetry/ws", "ingest WebSocket URL")
	dropout := flag.Float64("dropout", 0.003, "per-tick probability a vehicle enters a dead zone")
	apiURL := flag.String("api", "http://localhost:8080", "api base URL for accepting jobs (empty: ignore dispatch)")
	osrmURL := flag.String("osrm", config.String("OSRM_URL", "http://localhost:5001"), "OSRM URL for road routes (empty: straight lines)")
	acceptRate := flag.Float64("accept", 0.85, "probability a simulated driver accepts an offer")
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

	opts := vehicleOpts{url: *url, api: *apiURL, interval: *interval, dropout: *dropout, acceptRate: *acceptRate}
	if *osrmURL != "" {
		opts.routing = osrm.New(*osrmURL)
	}

	var st stats
	var wg sync.WaitGroup
	for i, id := range ids {
		token, err := tokens.IssueDevice(id, 24*time.Hour)
		if err != nil {
			log.Error("issue token", "err", err)
			os.Exit(1)
		}
		v := newVehicle(ctx, id, token, opts, &st, log)
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
				"reconnects", st.reconnects.Load(),
				"jobs_accepted", st.accepted.Load(), "jobs_declined", st.declined.Load(), "jobs_completed", st.completed.Load())
		}
	}
}

// seedVehicles upserts SIM-#### vehicles, each with a simulated driver on an
// active assignment (so dispatch can offer them jobs). Reruns reuse the IDs.
// Simulated drivers get an unusable password hash: nobody can sign in as them.
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
		_, err = pool.Exec(ctx, `
			WITH d AS (
				INSERT INTO drivers (full_name, phone, password_hash) VALUES ($1, $2, '!')
				ON CONFLICT (phone) DO UPDATE SET full_name = EXCLUDED.full_name
				RETURNING id)
			INSERT INTO vehicle_assignments (driver_id, vehicle_id)
			SELECT d.id, $3 FROM d
			WHERE NOT EXISTS (SELECT 1 FROM vehicle_assignments WHERE vehicle_id = $3 AND ended_at IS NULL)
			  AND NOT EXISTS (SELECT 1 FROM vehicle_assignments va WHERE va.driver_id = d.id AND va.ended_at IS NULL)`,
			fmt.Sprintf("Sim Driver %d", i), fmt.Sprintf("+999%07d", i), id)
		if err != nil {
			return nil, err
		}
		ids = append(ids, id)
	}
	return ids, nil
}
