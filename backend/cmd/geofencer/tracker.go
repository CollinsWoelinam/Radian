package main

import (
	"math"
	"time"

	pb "github.com/CollinsWoelinam/Radian/backend/gen/radian/telemetry/v1"
	"github.com/CollinsWoelinam/Radian/backend/internal/geo"
)

type Fence struct {
	ID   string
	Name string
	Kind pb.GeofenceKind
	Area geo.MultiPolygon

	// Alert rules set per zone by the dispatcher.
	AlertOnEnter bool
	AlertOnExit  bool
	Dwell        time.Duration // 0: no dwell alert

	minLat, minLon, maxLat, maxLon float64
}

func NewFence(id, name string, kind pb.GeofenceKind, area geo.MultiPolygon) *Fence {
	f := &Fence{ID: id, Name: name, Kind: kind, Area: area}
	f.minLat, f.minLon, f.maxLat, f.maxLon = area.Bounds()
	return f
}

type Fix struct {
	Lat, Lon  float64
	At        time.Time
	AccuracyM float64 // 0 = unknown
}

// Crossing is a confirmed boundary crossing, stamped with the first fix seen
// on the new side.
type Crossing struct {
	Fence     *Fence
	VehicleID string
	Entered   bool
	Fix       Fix
	// Baseline marks membership adopted on first sighting: it updates the
	// "who is inside" counts but is not an event and raises no alert.
	Baseline bool
	// Dwell marks a vehicle still inside after the zone's dwell limit.
	Dwell bool
}

// Alert reports whether the zone's rules flag this crossing.
func (c Crossing) Alert() bool {
	switch {
	case c.Baseline:
		return false
	case c.Dwell:
		return true
	case c.Entered:
		return c.Fence.AlertOnEnter
	default:
		return c.Fence.AlertOnExit
	}
}

// Tracker decides when a vehicle has really entered or left a zone.
//
// GPS noise near a boundary would otherwise produce a burst of enter/exit
// pairs, so a fix only counts when it is clearly on one side (farther from the
// boundary than its own accuracy) and a crossing needs Confirm such fixes in a
// row. Membership the first time a vehicle is seen near a fence is adopted
// silently, except in a zone that alerts on entry: being inside is the alert.
// A vehicle that stays inside longer than the zone's dwell limit gets one
// dwell event per visit.
type Tracker struct {
	Confirm      int
	MaxAccuracyM float64 // fixes worse than this are ignored
	MinMarginM   float64 // a fix closer than this to the boundary is ambiguous

	fences   map[string]*Fence
	vehicles map[string]*vehicleState
}

type vehicleState struct {
	lastAt  time.Time
	inside  map[string]bool // fence ID -> inside; absent = never observed
	pending map[string]*pending
	since   map[string]time.Time // fence ID -> inside since (for dwell)
	dwelt   map[string]bool      // dwell event already sent this visit
}

type pending struct {
	entered bool
	n       int
	first   Fix
}

func NewTracker() *Tracker {
	return &Tracker{
		Confirm:      2,
		MaxAccuracyM: 50,
		MinMarginM:   10,
		fences:       map[string]*Fence{},
		vehicles:     map[string]*vehicleState{},
	}
}

// SetFences replaces the zone set, forgetting state for removed zones.
func (t *Tracker) SetFences(fences []*Fence) {
	next := make(map[string]*Fence, len(fences))
	for _, f := range fences {
		next[f.ID] = f
	}
	for _, v := range t.vehicles {
		for id := range v.inside {
			if next[id] == nil {
				delete(v.inside, id)
				delete(v.pending, id)
				delete(v.since, id)
				delete(v.dwelt, id)
			}
		}
	}
	t.fences = next
}

// Restore seeds membership (e.g. from Redis after a restart).
func (t *Tracker) Restore(vehicleID, fenceID string) {
	t.state(vehicleID).inside[fenceID] = true
}

// Inside lists the zones a vehicle is currently in.
func (t *Tracker) Inside(vehicleID string) []string {
	var out []string
	if v := t.vehicles[vehicleID]; v != nil {
		for id, in := range v.inside {
			if in {
				out = append(out, id)
			}
		}
	}
	return out
}

func (t *Tracker) state(vehicleID string) *vehicleState {
	v := t.vehicles[vehicleID]
	if v == nil {
		v = &vehicleState{inside: map[string]bool{}, pending: map[string]*pending{}, since: map[string]time.Time{}, dwelt: map[string]bool{}}
		t.vehicles[vehicleID] = v
	}
	return v
}

// Observe feeds one fix and returns the crossings it confirms.
func (t *Tracker) Observe(vehicleID string, f Fix) []Crossing {
	if f.AccuracyM > t.MaxAccuracyM {
		return nil
	}
	v := t.state(vehicleID)
	if !f.At.After(v.lastAt) {
		return nil // late backfill: membership has moved on since
	}
	v.lastAt = f.At

	margin := math.Max(t.MinMarginM, f.AccuracyM)
	var out []Crossing
	for id, fence := range t.fences {
		side, clear := t.side(fence, f, margin)
		if !clear {
			continue // too close to the edge to tell; keep any pending count
		}
		was, known := v.inside[id]
		if !known {
			v.inside[id] = side
			if side {
				v.since[id] = f.At
				out = append(out, Crossing{Fence: fence, VehicleID: vehicleID, Entered: true, Fix: f, Baseline: !fence.AlertOnEnter})
			}
			continue
		}
		if side == was {
			delete(v.pending, id)
			if side {
				out = append(out, t.checkDwell(v, fence, vehicleID, f)...)
			}
			continue
		}
		p := v.pending[id]
		if p == nil || p.entered != side {
			p = &pending{entered: side, first: f}
			v.pending[id] = p
		}
		p.n++
		if p.n >= t.Confirm {
			v.inside[id] = side
			delete(v.pending, id)
			delete(v.dwelt, id)
			if side {
				v.since[id] = p.first.At
			} else {
				delete(v.since, id)
			}
			out = append(out, Crossing{Fence: fence, VehicleID: vehicleID, Entered: side, Fix: p.first})
		}
	}
	return out
}

// checkDwell emits one dwell crossing per visit once a vehicle has been inside
// longer than the zone allows. Membership restored after a restart counts
// from the first fix seen since.
func (t *Tracker) checkDwell(v *vehicleState, fence *Fence, vehicleID string, f Fix) []Crossing {
	since, ok := v.since[fence.ID]
	if !ok {
		v.since[fence.ID] = f.At
		return nil
	}
	if fence.Dwell <= 0 || v.dwelt[fence.ID] || f.At.Sub(since) < fence.Dwell {
		return nil
	}
	v.dwelt[fence.ID] = true
	return []Crossing{{Fence: fence, VehicleID: vehicleID, Entered: true, Dwell: true, Fix: f}}
}

// side reports whether the fix is inside the fence, and whether it is far
// enough from the boundary for that answer to be trusted.
func (t *Tracker) side(fence *Fence, f Fix, marginM float64) (inside, clear bool) {
	dLat := marginM / 111_320
	dLon := dLat / math.Max(math.Cos(f.Lat*math.Pi/180), 0.01)
	if f.Lat < fence.minLat-dLat || f.Lat > fence.maxLat+dLat || f.Lon < fence.minLon-dLon || f.Lon > fence.maxLon+dLon {
		return false, true // well outside the bounding box
	}
	inside = fence.Area.Contains(f.Lat, f.Lon)
	return inside, fence.Area.BoundaryDistanceM(f.Lat, f.Lon) > marginM
}
