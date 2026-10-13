// Command seed creates demo drivers, each assigned to a vehicle, so the driver
// app has something to log in with. Safe to rerun.
package main

import (
	"context"
	"fmt"
	"log/slog"
	"os"

	"github.com/jackc/pgx/v5/pgxpool"
	"golang.org/x/crypto/bcrypt"

	"github.com/CollinsWoelinam/Radian/backend/internal/config"
)

const demoPassword = "radian-demo"

var demo = []struct{ name, phone, plate, kind string }{
	{"Kwame Mensah", "0240000001", "GR 1024-26", "VAN"},
	{"Ama Owusu", "0240000002", "GT 3317-25", "MOTORBIKE"},
	{"Kofi Boateng", "0240000003", "GE 7781-24", "AMBULANCE"},
}

func main() {
	ctx := context.Background()
	pool, err := pgxpool.New(ctx, config.String("DATABASE_URL", "postgres://radian:radian@localhost:5433/radian?sslmode=disable"))
	if err != nil {
		slog.Error("postgres connect", "err", err)
		os.Exit(1)
	}
	defer pool.Close()

	hash, err := bcrypt.GenerateFromPassword([]byte(demoPassword), bcrypt.DefaultCost)
	if err != nil {
		slog.Error("hash password", "err", err)
		os.Exit(1)
	}

	for _, d := range demo {
		tx, err := pool.Begin(ctx)
		if err != nil {
			slog.Error("begin", "err", err)
			os.Exit(1)
		}
		var driverID, vehicleID string
		err = tx.QueryRow(ctx, `
			INSERT INTO drivers (full_name, phone, password_hash) VALUES ($1, $2, $3)
			ON CONFLICT (phone) DO UPDATE SET full_name = EXCLUDED.full_name, password_hash = EXCLUDED.password_hash
			RETURNING id`, d.name, d.phone, hash).Scan(&driverID)
		if err == nil {
			err = tx.QueryRow(ctx, `
				INSERT INTO vehicles (license_plate, kind) VALUES ($1, $2)
				ON CONFLICT (license_plate) DO UPDATE SET kind = EXCLUDED.kind
				RETURNING id`, d.plate, d.kind).Scan(&vehicleID)
		}
		if err == nil {
			// End any other active assignment for either side, then assign.
			_, err = tx.Exec(ctx, `
				UPDATE vehicle_assignments SET ended_at = NOW()
				WHERE ended_at IS NULL AND (driver_id = $1 OR vehicle_id = $2)
				  AND NOT (driver_id = $1 AND vehicle_id = $2)`, driverID, vehicleID)
		}
		if err == nil {
			_, err = tx.Exec(ctx, `
				INSERT INTO vehicle_assignments (driver_id, vehicle_id)
				SELECT $1, $2 WHERE NOT EXISTS (
					SELECT 1 FROM vehicle_assignments WHERE driver_id = $1 AND vehicle_id = $2 AND ended_at IS NULL)`,
				driverID, vehicleID)
		}
		if err == nil {
			err = tx.Commit(ctx)
		}
		if err != nil {
			tx.Rollback(ctx)
			slog.Error("seed driver", "phone", d.phone, "err", err)
			os.Exit(1)
		}
		fmt.Printf("%-14s phone %s  vehicle %-11s (%s)\n", d.name, d.phone, d.plate, d.kind)
	}
	fmt.Printf("\nPassword for all demo drivers: %s\n", demoPassword)
}
