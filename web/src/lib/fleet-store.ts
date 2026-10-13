import { VehicleStatus, type FleetUpdate, type VehicleDelta } from "@/gen/radian/telemetry/v1/telemetry_pb";

/**
 * Live fleet state, kept outside React so 60 fps animation never triggers
 * re-renders. Each vehicle animates from where it is drawn now to its newest
 * fix over roughly one update interval, so motion stays continuous.
 */
export type Vehicle = {
  id: string;
  // What is drawn this frame.
  lon: number;
  lat: number;
  heading: number;
  // Current animation segment.
  fromLon: number;
  fromLat: number;
  fromHeading: number;
  toLon: number;
  toLat: number;
  toHeading: number;
  t0: number;
  dur: number;
  // Latest reported values.
  speedKmh: number;
  status: VehicleStatus;
  recordedAtMs: number;
  receivedAt: number;
};

const MIN_ANIM_MS = 300;
const MAX_ANIM_MS = 2500;
// Beyond this, teleport instead of sliding across the city (e.g. after a dead zone).
const SNAP_DISTANCE_DEG = 0.02;

export class FleetStore {
  private byId = new Map<string, Vehicle>();
  /** Stable array for deck.gl; replaced only when vehicles are added or removed. */
  list: Vehicle[] = [];
  private updatesInWindow = 0;
  private windowStart = performance.now();
  updatesPerSecond = 0;

  get(id: string): Vehicle | undefined {
    return this.byId.get(id);
  }

  apply(update: FleetUpdate, now: number) {
    let membershipChanged = false;

    if (update.isSnapshot) {
      const keep = new Set(update.deltas.map((d) => d.vehicleId));
      for (const id of this.byId.keys()) {
        if (!keep.has(id)) {
          this.byId.delete(id);
          membershipChanged = true;
        }
      }
    }
    for (const d of update.deltas) {
      if (this.upsert(d, now)) membershipChanged = true;
    }
    for (const id of update.removedVehicleIds) {
      if (this.byId.delete(id)) membershipChanged = true;
    }
    if (membershipChanged) this.list = [...this.byId.values()];

    this.updatesInWindow += update.deltas.length;
    if (now - this.windowStart >= 1000) {
      this.updatesPerSecond = (this.updatesInWindow * 1000) / (now - this.windowStart);
      this.updatesInWindow = 0;
      this.windowStart = now;
    }
  }

  private upsert(d: VehicleDelta, now: number): boolean {
    const v = this.byId.get(d.vehicleId);
    if (!v) {
      this.byId.set(d.vehicleId, {
        id: d.vehicleId,
        lon: d.longitude,
        lat: d.latitude,
        heading: d.headingDeg,
        fromLon: d.longitude,
        fromLat: d.latitude,
        fromHeading: d.headingDeg,
        toLon: d.longitude,
        toLat: d.latitude,
        toHeading: d.headingDeg,
        t0: now,
        dur: 1,
        speedKmh: d.speedKmh,
        status: d.status,
        recordedAtMs: Number(d.recordedAtMs),
        receivedAt: now,
      });
      return true;
    }

    const far =
      Math.abs(d.longitude - v.lon) > SNAP_DISTANCE_DEG || Math.abs(d.latitude - v.lat) > SNAP_DISTANCE_DEG;
    v.fromLon = far ? d.longitude : v.lon;
    v.fromLat = far ? d.latitude : v.lat;
    v.fromHeading = v.heading;
    v.toLon = d.longitude;
    v.toLat = d.latitude;
    v.toHeading = d.headingDeg;
    v.t0 = now;
    v.dur = clamp(now - v.receivedAt, MIN_ANIM_MS, MAX_ANIM_MS);
    v.speedKmh = d.speedKmh;
    v.status = d.status;
    v.recordedAtMs = Number(d.recordedAtMs);
    v.receivedAt = now;
    return false;
  }

  /** Move every vehicle to its interpolated position for this frame. */
  advance(now: number) {
    for (const v of this.list) {
      const t = clamp((now - v.t0) / v.dur, 0, 1);
      v.lon = v.fromLon + (v.toLon - v.fromLon) * t;
      v.lat = v.fromLat + (v.toLat - v.fromLat) * t;
      // Turn the short way round (350° -> 10° is +20°, not -340°).
      const dh = ((v.toHeading - v.fromHeading + 540) % 360) - 180;
      v.heading = (v.fromHeading + dh * t + 360) % 360;
    }
  }

  clear() {
    this.byId.clear();
    this.list = [];
  }
}

function clamp(x: number, lo: number, hi: number) {
  return Math.min(hi, Math.max(lo, x));
}
