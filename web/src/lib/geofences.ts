import { ApiClient } from "./api";
import type { LatLon } from "./jobs";
import { GeofenceKind, type GeofenceEvent as GeofenceEventMsg } from "@/gen/radian/telemetry/v1/telemetry_pb";

export type ZoneKind = "DEPOT" | "SERVICE_AREA" | "RESTRICTED";

/** [lon, lat] rings, GeoJSON MultiPolygon order. */
export type MultiPolygon = [number, number][][][];

export type Zone = {
  id: string;
  name: string;
  kind: ZoneKind;
  area: MultiPolygon;
  area_km2: number;
  vehicles_inside: number;
  created_at: string;
};

export type ZoneEvent = {
  id: number;
  geofence_id: string;
  geofence_name: string;
  kind: ZoneKind;
  vehicle_id: string;
  license_plate: string;
  entered: boolean;
  occurred_at: string;
  position?: LatLon;
};

type RGB = [number, number, number];

export const ZONE_KINDS: { value: ZoneKind; label: string; hint: string; rgb: RGB }[] = [
  { value: "DEPOT", label: "Depot", hint: "Arrivals and departures are logged.", rgb: [59, 130, 246] },
  { value: "SERVICE_AREA", label: "Service area", hint: "Alerts when a vehicle leaves it.", rgb: [16, 185, 129] },
  { value: "RESTRICTED", label: "Restricted", hint: "Alerts when a vehicle enters it.", rgb: [239, 68, 68] },
];

export const zoneKind = (k: ZoneKind) => ZONE_KINDS.find((z) => z.value === k) ?? ZONE_KINDS[0];

export type Severity = "critical" | "warning" | "info";

/** Which crossings deserve a dispatcher's attention right now. */
export function severity(kind: ZoneKind, entered: boolean): Severity {
  if (kind === "RESTRICTED" && entered) return "critical";
  if (kind === "SERVICE_AREA" && !entered) return "warning";
  return "info";
}

export function describe(e: Pick<ZoneEvent, "license_plate" | "entered" | "geofence_name">) {
  return `${e.license_plate || "A vehicle"} ${e.entered ? "entered" : "left"} ${e.geofence_name}`;
}

const KIND_FROM_PROTO: Record<number, ZoneKind> = {
  [GeofenceKind.DEPOT]: "DEPOT",
  [GeofenceKind.SERVICE_AREA]: "SERVICE_AREA",
  [GeofenceKind.RESTRICTED]: "RESTRICTED",
};

/** Converts a live push into the same shape the REST feed returns. */
export function fromMessage(m: GeofenceEventMsg): ZoneEvent {
  return {
    id: Number(m.id),
    geofence_id: m.geofenceId,
    geofence_name: m.geofenceName,
    kind: KIND_FROM_PROTO[m.kind] ?? "DEPOT",
    vehicle_id: m.vehicleId,
    license_plate: m.licensePlate,
    entered: m.entered,
    occurred_at: new Date(Number(m.occurredAtMs)).toISOString(),
    position: m.position ? { lat: m.position.latitude, lon: m.position.longitude } : undefined,
  };
}

export type NewZone = { name: string; kind: ZoneKind; polygon: [number, number][] };

export class GeofencesApi extends ApiClient {
  list() {
    return this.req<Zone[]>(`/v1/geofences`);
  }
  create(z: NewZone) {
    return this.req<Zone>(`/v1/geofences`, { method: "POST", body: JSON.stringify(z) });
  }
  remove(id: string) {
    return this.req<void>(`/v1/geofences/${id}`, { method: "DELETE" });
  }
  events(limit = 50) {
    return this.req<ZoneEvent[]>(`/v1/geofence-events?limit=${limit}`);
  }
}
