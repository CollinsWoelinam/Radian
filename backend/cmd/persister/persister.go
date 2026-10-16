package main

import (
	"context"
	"log/slog"
	"time"

	"github.com/redis/go-redis/v9"
	"google.golang.org/protobuf/proto"

	pb "github.com/CollinsWoelinam/Radian/backend/gen/radian/telemetry/v1"
	"github.com/CollinsWoelinam/Radian/backend/internal/stream"
)

type Persister struct {
	log           *slog.Logger
	rdb           *redis.Client
	store         *Store
	consumer      string
	flushInterval time.Duration
	maxRows       int
}

type pending struct {
	ids  []string
	rows []Row
	// When the oldest buffered entry arrived; bounds end-to-end write latency.
	since time.Time
}

func (p *Persister) Run(ctx context.Context) error {
	var buf pending

	// "0" first replays entries this consumer read but never acked (a crash
	// mid-flush); ">" then reads new entries.
	cursor := "0"

	for {
		if ctx.Err() != nil {
			p.flush(context.Background(), &buf) // best effort on shutdown
			return ctx.Err()
		}

		block := p.flushInterval
		if len(buf.ids) > 0 {
			block = max(time.Until(buf.since.Add(p.flushInterval)), time.Millisecond)
		}

		res, err := p.rdb.XReadGroup(ctx, &redis.XReadGroupArgs{
			Group:    stream.PersisterGroup,
			Consumer: p.consumer,
			Streams:  []string{stream.Telemetry, cursor},
			Count:    1000,
			Block:    block,
		}).Result()
		if err != nil && err != redis.Nil {
			if ctx.Err() != nil {
				continue
			}
			p.log.Error("xreadgroup", "err", err)
			time.Sleep(time.Second)
			continue
		}

		var n int
		for _, s := range res {
			for _, msg := range s.Messages {
				n++
				p.decode(msg, &buf)
				if cursor != ">" {
					// Replaying the pending list: advance past what we've read.
					cursor = msg.ID
				}
			}
		}
		if cursor != ">" && n == 0 {
			cursor = ">"
		}

		due := len(buf.ids) > 0 && time.Since(buf.since) >= p.flushInterval
		if due || len(buf.rows) >= p.maxRows {
			p.flush(ctx, &buf)
		}
	}
}

func (p *Persister) decode(msg redis.XMessage, buf *pending) {
	if len(buf.ids) == 0 {
		buf.since = time.Now()
	}
	buf.ids = append(buf.ids, msg.ID)

	vehicleID, _ := msg.Values[stream.FieldVehicleID].(string)
	raw, _ := msg.Values[stream.FieldBatch].(string)
	var batch pb.TelemetryBatch
	if vehicleID == "" || proto.Unmarshal([]byte(raw), &batch) != nil {
		// Poison entry: keep its ID so it gets acked and never blocks the stream.
		p.log.Warn("dropping undecodable stream entry", "id", msg.ID)
		return
	}
	for _, pt := range batch.Points {
		buf.rows = append(buf.rows, rowFromPoint(vehicleID, pt))
	}
}

// trim drops stream entries that every persister has stored: everything
// older than the oldest still-pending entry (or than lastAcked if none is
// pending). Broadcast only reads new entries, so it doesn't need them.
// Without this the stream sits at its MAXLEN cap and Redis restarts slowly.
func (p *Persister) trim(ctx context.Context, lastAcked string) {
	minID := lastAcked
	if sum, err := p.rdb.XPending(ctx, stream.Telemetry, stream.PersisterGroup).Result(); err == nil && sum.Count > 0 {
		minID = sum.Lower
	}
	if err := p.rdb.XTrimMinIDApprox(ctx, stream.Telemetry, minID, 0).Err(); err != nil {
		p.log.Warn("trim stream", "err", err)
	}
}

// flush retries until the batch commits (or shutdown): unacked entries would
// otherwise be re-read only after a restart.
func (p *Persister) flush(ctx context.Context, buf *pending) {
	if len(buf.ids) == 0 {
		return
	}
	for attempt := 0; ; attempt++ {
		start := time.Now()
		inserted, err := p.store.Write(ctx, buf.rows)
		if err == nil {
			if err := p.rdb.XAck(ctx, stream.Telemetry, stream.PersisterGroup, buf.ids...).Err(); err != nil {
				// Rows are committed; a replay is harmless thanks to ON CONFLICT DO NOTHING.
				p.log.Error("xack", "err", err)
			}
			p.log.Info("flushed",
				"entries", len(buf.ids),
				"rows", len(buf.rows),
				"inserted", inserted,
				"duplicates", int64(len(buf.rows))-inserted,
				"took_ms", time.Since(start).Milliseconds(),
			)
			p.trim(ctx, buf.ids[len(buf.ids)-1])
			*buf = pending{}
			return
		}
		p.log.Error("write batch", "err", err, "attempt", attempt, "rows", len(buf.rows))
		select {
		case <-ctx.Done():
			return
		case <-time.After(min(time.Duration(attempt+1)*time.Second, 15*time.Second)):
		}
	}
}
