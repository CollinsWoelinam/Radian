package main

import (
	"context"
	"time"

	"github.com/coder/websocket"
	"google.golang.org/protobuf/proto"

	pb "github.com/CollinsWoelinam/Radian/backend/gen/radian/telemetry/v1"
)

const clientQueue = 4

// client is one dashboard connection. viewport, has and needsSnapshot are
// owned by the Hub and only touched under Hub.mu.
type client struct {
	conn *websocket.Conn
	send chan *pb.FleetUpdate

	viewport      *pb.BoundingBox
	has           map[string]struct{}
	needsSnapshot bool
}

func newClient(conn *websocket.Conn) *client {
	return &client{conn: conn, send: make(chan *pb.FleetUpdate, clientQueue)}
}

// enqueue never blocks the hub; it reports false when the client is behind.
func (c *client) enqueue(u *pb.FleetUpdate) bool {
	select {
	case c.send <- u:
		return true
	default:
		return false
	}
}

func (c *client) writeLoop(ctx context.Context) error {
	for {
		select {
		case <-ctx.Done():
			return ctx.Err()
		case u := <-c.send:
			data, err := proto.Marshal(&pb.DashboardServerMessage{
				Payload: &pb.DashboardServerMessage_FleetUpdate{FleetUpdate: u},
			})
			if err != nil {
				return err
			}
			wctx, cancel := context.WithTimeout(ctx, 5*time.Second)
			err = c.conn.Write(wctx, websocket.MessageBinary, data)
			cancel()
			if err != nil {
				return err
			}
		}
	}
}
