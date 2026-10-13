package main

import (
	"sync"
	"time"

	"google.golang.org/protobuf/proto"

	pb "github.com/CollinsWoelinam/Radian/backend/gen/radian/telemetry/v1"
)

const (
	// Fraction of the viewport added on each side, so vehicles just off-screen
	// are already on the client when the user pans.
	viewportMargin = 0.2
	movingKmh      = 5
)

// Hub holds the latest state of every vehicle and fans coalesced deltas out to
// dashboard clients on a fixed tick. All client subscription state is guarded
// by mu as well, which keeps the tick a single consistent pass.
type Hub struct {
	offlineAfter time.Duration

	mu       sync.Mutex
	vehicles map[string]*pb.VehicleDelta
	dirty    map[string]struct{}
	// Status assigned by dispatch (e.g. ON_JOB); motion decides the rest.
	assigned map[string]pb.VehicleStatus
	clients  map[*client]struct{}
}

func NewHub(offlineAfter time.Duration) *Hub {
	return &Hub{
		offlineAfter: offlineAfter,
		vehicles:     make(map[string]*pb.VehicleDelta),
		dirty:        make(map[string]struct{}),
		assigned:     make(map[string]pb.VehicleStatus),
		clients:      make(map[*client]struct{}),
	}
}

// Apply records a fix if it is newer than what we have. Backfill from a
// device's offline buffer is usually older and only updates history.
func (h *Hub) Apply(vehicleID string, p *pb.LocationPoint) {
	h.mu.Lock()
	defer h.mu.Unlock()
	cur := h.vehicles[vehicleID]
	if cur != nil && p.RecordedAtMs <= cur.RecordedAtMs {
		return
	}
	d := &pb.VehicleDelta{
		VehicleId:    vehicleID,
		Latitude:     p.Latitude,
		Longitude:    p.Longitude,
		HeadingDeg:   p.GetHeadingDeg(),
		SpeedKmh:     p.GetSpeedKmh(),
		RecordedAtMs: p.RecordedAtMs,
	}
	// Keep the last heading while stopped; GPS bearing is noise at zero speed.
	if cur != nil && d.SpeedKmh < movingKmh {
		d.HeadingDeg = cur.HeadingDeg
	}
	d.Status = h.statusFor(vehicleID, d, time.Now())
	h.vehicles[vehicleID] = d
	h.dirty[vehicleID] = struct{}{}
}

// SetAssigned replaces the dispatch-assigned statuses (refreshed from the DB).
func (h *Hub) SetAssigned(assigned map[string]pb.VehicleStatus) {
	h.mu.Lock()
	defer h.mu.Unlock()
	h.assigned = assigned
}

func (h *Hub) statusFor(id string, d *pb.VehicleDelta, now time.Time) pb.VehicleStatus {
	if now.Sub(time.UnixMilli(d.RecordedAtMs)) > h.offlineAfter {
		return pb.VehicleStatus_VEHICLE_STATUS_OFFLINE
	}
	if s, ok := h.assigned[id]; ok {
		return s
	}
	if d.SpeedKmh >= movingKmh {
		return pb.VehicleStatus_VEHICLE_STATUS_EN_ROUTE
	}
	return pb.VehicleStatus_VEHICLE_STATUS_IDLE
}

func (h *Hub) Register(c *client) {
	h.mu.Lock()
	defer h.mu.Unlock()
	h.clients[c] = struct{}{}
}

func (h *Hub) Unregister(c *client) {
	h.mu.Lock()
	defer h.mu.Unlock()
	delete(h.clients, c)
}

// Subscribe sets a client's viewport and immediately sends it a snapshot of
// every vehicle inside it.
func (h *Hub) Subscribe(c *client, viewport *pb.BoundingBox) {
	h.mu.Lock()
	defer h.mu.Unlock()
	c.viewport = expand(viewport, viewportMargin)
	h.sendSnapshot(c, time.Now())
}

func (h *Hub) sendSnapshot(c *client, now time.Time) {
	c.has = make(map[string]struct{}, len(c.has))
	update := &pb.FleetUpdate{IsSnapshot: true, ServerTimeMs: now.UnixMilli()}
	for id, d := range h.vehicles {
		if contains(c.viewport, d) {
			update.Deltas = append(update.Deltas, d)
			c.has[id] = struct{}{}
		}
	}
	c.needsSnapshot = !c.enqueue(update)
}

// Tick refreshes derived statuses and sends each client the vehicles that
// changed inside its viewport since the last tick, at most one per vehicle.
func (h *Hub) Tick(now time.Time) {
	h.mu.Lock()
	defer h.mu.Unlock()

	for id, d := range h.vehicles {
		if s := h.statusFor(id, d, now); s != d.Status {
			// Copy so a delta already handed to a client writer is never mutated.
			d = proto.Clone(d).(*pb.VehicleDelta)
			d.Status = s
			h.vehicles[id] = d
			h.dirty[id] = struct{}{}
		}
	}

	if len(h.dirty) == 0 {
		return
	}
	for c := range h.clients {
		if c.viewport == nil {
			continue
		}
		if c.needsSnapshot {
			h.sendSnapshot(c, now)
			continue
		}
		update := &pb.FleetUpdate{ServerTimeMs: now.UnixMilli()}
		for id := range h.dirty {
			d := h.vehicles[id]
			_, had := c.has[id]
			switch in := contains(c.viewport, d); {
			case in:
				update.Deltas = append(update.Deltas, d)
				c.has[id] = struct{}{}
			case had:
				update.RemovedVehicleIds = append(update.RemovedVehicleIds, id)
				delete(c.has, id)
			}
		}
		if len(update.Deltas) > 0 || len(update.RemovedVehicleIds) > 0 {
			// A client too slow to drain its queue gets a fresh snapshot
			// instead of an ever-growing backlog of stale deltas.
			c.needsSnapshot = !c.enqueue(update)
		}
	}
	clear(h.dirty)
}

func (h *Hub) Stats() (vehicles, clients int) {
	h.mu.Lock()
	defer h.mu.Unlock()
	return len(h.vehicles), len(h.clients)
}

func expand(b *pb.BoundingBox, frac float64) *pb.BoundingBox {
	dLon := (b.MaxLon - b.MinLon) * frac
	dLat := (b.MaxLat - b.MinLat) * frac
	return &pb.BoundingBox{
		MinLon: max(b.MinLon-dLon, -180),
		MinLat: max(b.MinLat-dLat, -90),
		MaxLon: min(b.MaxLon+dLon, 180),
		MaxLat: min(b.MaxLat+dLat, 90),
	}
}

func contains(b *pb.BoundingBox, d *pb.VehicleDelta) bool {
	return d.Longitude >= b.MinLon && d.Longitude <= b.MaxLon &&
		d.Latitude >= b.MinLat && d.Latitude <= b.MaxLat
}
