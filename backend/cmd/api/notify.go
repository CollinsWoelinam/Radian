package main

import (
	"context"
	"log/slog"

	"github.com/redis/go-redis/v9"
	"google.golang.org/protobuf/proto"

	pb "github.com/CollinsWoelinam/Radian/backend/gen/radian/telemetry/v1"
	"github.com/CollinsWoelinam/Radian/backend/internal/stream"
)

// Notifier pushes dispatch events over Redis Pub/Sub: to a driver's phone via
// the ingest service (which holds the device WebSockets) and to dashboards via
// the broadcast service. Delivery is best effort; phones and dashboards also
// fetch current state over REST, so a missed message only delays an update.
type Notifier struct {
	rdb *redis.Client
	log *slog.Logger
}

func (n *Notifier) Device(ctx context.Context, vehicleID string, msg *pb.ServerMessage) {
	n.publish(ctx, stream.DeviceChannel(vehicleID), msg)
}

func (n *Notifier) JobsChanged(ctx context.Context, jobIDs ...string) {
	n.publish(ctx, stream.JobsChannel, &pb.JobsChanged{JobIds: jobIDs})
}

// GeofencesChanged tells dashboards and the geofencer to reload zones.
func (n *Notifier) GeofencesChanged(ctx context.Context) {
	n.publish(ctx, stream.GeofenceChannel, &pb.DashboardServerMessage{
		Payload: &pb.DashboardServerMessage_GeofencesChanged{GeofencesChanged: &pb.GeofencesChanged{}},
	})
}

func (n *Notifier) publish(ctx context.Context, channel string, msg proto.Message) {
	data, err := proto.Marshal(msg)
	if err == nil {
		err = n.rdb.Publish(ctx, channel, data).Err()
	}
	if err != nil {
		n.log.Warn("publish", "channel", channel, "err", err)
	}
}
