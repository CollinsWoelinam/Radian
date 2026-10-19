// Command geofencer watches the telemetry stream for vehicles entering and
// leaving zones. It reads in its own consumer group, so it never slows the
// persister, records each confirmed crossing in geofence_events, keeps the
// current membership in Redis, and pushes the event to dashboards through the
// broadcast service.
package main

import (
	"context"
	"encoding/json"
	"errors"
	"log/slog"
	"os"
	"os/signal"
	"strings"
	"syscall"
	"time"

	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgconn"
	"github.com/jackc/pgx/v5/pgxpool"
	"github.com/redis/go-redis/v9"
	"google.golang.org/protobuf/proto"

	pb "github.com/CollinsWoelinam/Radian/backend/gen/radian/telemetry/v1"
	"github.com/CollinsWoelinam/Radian/backend/internal/config"
	"github.com/CollinsWoelinam/Radian/backend/internal/geo"
	"github.com/CollinsWoelinam/Radian/backend/internal/stream"
)

type service struct {
	log      *slog.Logger
	pool     *pgxpool.Pool
	rdb      *redis.Client
	consumer string
	tracker  *Tracker
	plates   map[string]string
	reload   chan struct{}
}

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
	s := &service{
		log:      log,
		pool:     pool,
		rdb:      rdb,
		consumer: config.String("GEOFENCER_CONSUMER", hostname),
		tracker:  NewTracker(),
		plates:   map[string]string{},
		reload:   make(chan struct{}, 1),
	}
	s.tracker.Confirm = config.Int("GEOFENCE_CONFIRM_FIXES", 2)
	s.tracker.MaxAccuracyM = config.Float("GEOFENCE_MAX_ACCURACY_M", 50)

	// Only live crossings matter: a fresh group starts at the stream's end.
	err = rdb.XGroupCreateMkStream(ctx, stream.Telemetry, stream.GeofenceGroup, "$").Err()
	if err != nil && !strings.Contains(err.Error(), "BUSYGROUP") {
		log.Error("create consumer group", "err", err)
		os.Exit(1)
	}
	if err := s.loadFences(ctx, true); err != nil {
		log.Error("load geofences", "err", err)
		os.Exit(1)
	}

	go s.watchChanges(ctx)
	log.Info("geofencer started", "consumer", s.consumer, "fences", len(s.tracker.fences))
	s.run(ctx)
}

// watchChanges asks the main loop to reload zones when the api changes them,
// and once a minute as a safety net for a missed notice.
func (s *service) watchChanges(ctx context.Context) {
	ps := s.rdb.Subscribe(ctx, stream.GeofenceChannel)
	defer ps.Close()
	tick := time.NewTicker(time.Minute)
	defer tick.Stop()
	poke := func() {
		select {
		case s.reload <- struct{}{}:
		default:
		}
	}
	for {
		select {
		case <-ctx.Done():
			return
		case <-tick.C:
			poke()
		case m := <-ps.Channel():
			var msg pb.DashboardServerMessage
			if proto.Unmarshal([]byte(m.Payload), &msg) == nil && msg.GetGeofencesChanged() != nil {
				poke()
			}
		}
	}
}

func (s *service) loadFences(ctx context.Context, restore bool) error {
	rows, err := s.pool.Query(ctx, `SELECT id, name, kind::text, ST_AsGeoJSON(area) FROM geofences`)
	if err != nil {
		return err
	}
	defer rows.Close()
	var fences []*Fence
	for rows.Next() {
		var id, name, kind, geojson string
		if err := rows.Scan(&id, &name, &kind, &geojson); err != nil {
			return err
		}
		var g struct {
			Coordinates geo.MultiPolygon `json:"coordinates"`
		}
		if err := json.Unmarshal([]byte(geojson), &g); err != nil {
			s.log.Warn("skipping unreadable geofence", "id", id, "err", err)
			continue
		}
		fences = append(fences, NewFence(id, name, kindFromDB(kind), g.Coordinates))
	}
	if err := rows.Err(); err != nil {
		return err
	}
	s.tracker.SetFences(fences)
	if restore {
		for _, f := range fences {
			ids, err := s.rdb.SMembers(ctx, stream.InsideKey(f.ID)).Result()
			if err != nil {
				return err
			}
			for _, v := range ids {
				s.tracker.Restore(v, f.ID)
			}
		}
	}
	return nil
}

func kindFromDB(k string) pb.GeofenceKind {
	if v, ok := pb.GeofenceKind_value["GEOFENCE_KIND_"+k]; ok {
		return pb.GeofenceKind(v)
	}
	return pb.GeofenceKind_GEOFENCE_KIND_UNSPECIFIED
}

func (s *service) run(ctx context.Context) {
	cursor := "0" // replay our unacked entries first, then new ones
	for ctx.Err() == nil {
		select {
		case <-s.reload:
			if err := s.loadFences(ctx, false); err != nil && ctx.Err() == nil {
				s.log.Warn("reload geofences", "err", err)
			}
		default:
		}

		res, err := s.rdb.XReadGroup(ctx, &redis.XReadGroupArgs{
			Group:    stream.GeofenceGroup,
			Consumer: s.consumer,
			Streams:  []string{stream.Telemetry, cursor},
			Count:    500,
			Block:    time.Second,
		}).Result()
		if err != nil && err != redis.Nil {
			if ctx.Err() == nil {
				s.log.Error("xreadgroup", "err", err)
				time.Sleep(time.Second)
			}
			continue
		}

		var ids []string
		var crossings []Crossing
		for _, st := range res {
			for _, msg := range st.Messages {
				ids = append(ids, msg.ID)
				if cursor != ">" {
					cursor = msg.ID
				}
				crossings = append(crossings, s.observe(msg)...)
			}
		}
		if cursor != ">" && len(ids) == 0 {
			cursor = ">"
		}
		if len(ids) == 0 {
			continue
		}
		s.commit(ctx, crossings)
		if err := s.rdb.XAck(ctx, stream.Telemetry, stream.GeofenceGroup, ids...).Err(); err != nil {
			s.log.Error("xack", "err", err) // replays are harmless: crossings are unique
		}
	}
}

func (s *service) observe(msg redis.XMessage) []Crossing {
	vehicleID, _ := msg.Values[stream.FieldVehicleID].(string)
	raw, _ := msg.Values[stream.FieldBatch].(string)
	var batch pb.TelemetryBatch
	if vehicleID == "" || proto.Unmarshal([]byte(raw), &batch) != nil {
		return nil
	}
	var out []Crossing
	for _, p := range batch.Points {
		f := Fix{Lat: p.Latitude, Lon: p.Longitude, At: time.UnixMilli(p.RecordedAtMs)}
		if p.AccuracyM != nil {
			f.AccuracyM = float64(*p.AccuracyM)
		}
		out = append(out, s.tracker.Observe(vehicleID, f)...)
	}
	return out
}

// commit stores crossings, updates membership and notifies dashboards. It
// retries until the database accepts them (or shutdown), like the persister.
func (s *service) commit(ctx context.Context, crossings []Crossing) {
	for _, c := range crossings {
		var id int64
		for attempt := 0; !c.Baseline; attempt++ {
			err := s.pool.QueryRow(ctx, `
				INSERT INTO geofence_events (geofence_id, vehicle_id, entered, occurred_at, location)
				VALUES ($1, $2, $3, $4, ST_SetSRID(ST_MakePoint($5, $6), 4326))
				ON CONFLICT DO NOTHING
				RETURNING id`,
				c.Fence.ID, c.VehicleID, c.Entered, c.Fix.At, c.Fix.Lon, c.Fix.Lat).Scan(&id)
			if err == nil || errors.Is(err, pgx.ErrNoRows) {
				break // stored, or a replay of one already stored
			}
			if pgErr, ok := errors.AsType[*pgconn.PgError](err); ok && pgErr.Code == "23503" {
				id = 0 // the zone (or vehicle) was deleted meanwhile
				break
			}
			s.log.Error("insert geofence event", "err", err, "attempt", attempt)
			select {
			case <-ctx.Done():
				return
			case <-time.After(min(time.Duration(attempt+1)*time.Second, 15*time.Second)):
			}
		}

		key := stream.InsideKey(c.Fence.ID)
		var err error
		if c.Entered {
			err = s.rdb.SAdd(ctx, key, c.VehicleID).Err()
		} else {
			err = s.rdb.SRem(ctx, key, c.VehicleID).Err()
		}
		if err != nil {
			s.log.Warn("update membership", "err", err)
		}
		if id == 0 {
			continue
		}
		s.log.Info("geofence crossing", "fence", c.Fence.Name, "vehicle", c.VehicleID, "entered", c.Entered)
		s.publish(ctx, &pb.GeofenceEvent{
			Id:           id,
			GeofenceId:   c.Fence.ID,
			GeofenceName: c.Fence.Name,
			Kind:         c.Fence.Kind,
			VehicleId:    c.VehicleID,
			LicensePlate: s.plate(ctx, c.VehicleID),
			Entered:      c.Entered,
			OccurredAtMs: c.Fix.At.UnixMilli(),
			Position:     &pb.GeoPoint{Latitude: c.Fix.Lat, Longitude: c.Fix.Lon},
		})
	}
}

func (s *service) plate(ctx context.Context, vehicleID string) string {
	if p, ok := s.plates[vehicleID]; ok {
		return p
	}
	var p string
	if err := s.pool.QueryRow(ctx, `SELECT license_plate FROM vehicles WHERE id = $1`, vehicleID).Scan(&p); err != nil {
		return ""
	}
	s.plates[vehicleID] = p
	return p
}

func (s *service) publish(ctx context.Context, e *pb.GeofenceEvent) {
	data, err := proto.Marshal(&pb.DashboardServerMessage{Payload: &pb.DashboardServerMessage_GeofenceEvent{GeofenceEvent: e}})
	if err == nil {
		err = s.rdb.Publish(ctx, stream.GeofenceChannel, data).Err()
	}
	if err != nil {
		s.log.Warn("publish geofence event", "err", err)
	}
}
