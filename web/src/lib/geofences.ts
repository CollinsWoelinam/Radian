import { ApiClient } from "./api";
import type { LatLon } from "./jobs";
import { GeofenceKind, type GeofenceEvent as GeofenceEventMsg } from "@/gen/radian/telemetry/v1/telemetry_pb";

export type ZoneKind = "DEPOT" | "SERVICE_AREA" | "RESTRICTED";

/** [lon, lat] rings, GeoJSON MultiPolygon order. */
export type MultiPolygon = [number, number][][][];

export type AlertRules = {
  alert_on_enter: boolean;
  alert_on_exit: boolean;
  /** Alert when a vehicle stays inside this long; null = off. */
  dwell_alert_s: number | null;
};

export type Zone = AlertRules & {
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
  dwell: boolean;
  /** The zone's rules flagged this event. */
  alert: boolean;
  occurred_at: string;
  position?: LatLon;
};

type RGB = [number, number, number];

export const ZONE_KINDS: { value: ZoneKind; label: string; hint: string; rgb: RGB }[] = [
  { value: "DEPOT", label: "Depot", hint: "Logs arrivals and departures.", rgb: [59, 130, 246] },
  { value: "SERVICE_AREA", label: "Service area", hint: "Alerts when a vehicle leaves it.", rgb: [16, 185, 129] },
  { value: "RESTRICTED", label: "Restricted", hint: "Alerts when a vehicle enters it.", rgb: [239, 68, 68] },
];

/** What each kind of zone alerts on unless the dispatcher changes it. */
export const defaultRules = (k: ZoneKind): AlertRules => ({ alert_on_enter: k === "RESTRICTED", alert_on_exit: k === "SERVICE_AREA", dwell_alert_s: null });

export const zoneKind = (k: ZoneKind) => ZONE_KINDS.find((z) => z.value === k) ?? ZONE_KINDS[0];

export type Severity = "critical" | "warning" | "info";

/** How loudly to show a crossing: the zone's rules decide whether it alerts. */
export function severity(e: Pick<ZoneEvent, "kind" | "alert">): Severity {
  if (!e.alert) return "info";
  return e.kind === "RESTRICTED" ? "critical" : "warning";
}

export function verb(e: Pick<ZoneEvent, "entered" | "dwell">) {
  return e.dwell ? "is still in" : e.entered ? "entered" : "left";
}

export function describe(e: Pick<ZoneEvent, "license_plate" | "entered" | "dwell" | "geofence_name">) {
  return `${e.license_plate || "A vehicle"} ${verb(e)} ${e.geofence_name}`;
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
    dwell: m.dwell,
    alert: m.alert,
    occurred_at: new Date(Number(m.occurredAtMs)).toISOString(),
    position: m.position ? { lat: m.position.latitude, lon: m.position.longitude } : undefined,
  };
}

export type NewZone = { name: string; kind: ZoneKind; polygon: [number, number][]; rules?: AlertRules };

export class GeofencesApi extends ApiClient {
  list() {
    return this.req<Zone[]>(`/v1/geofences`);
  }
  create(z: NewZone) {
    return this.req<Zone>(`/v1/geofences`, { method: "POST", body: JSON.stringify(z) });
  }
  setRules(id: string, rules: AlertRules) {
    return this.req<Zone>(`/v1/geofences/${id}/rules`, { method: "PUT", body: JSON.stringify(rules) });
  }
  remove(id: string) {
    return this.req<void>(`/v1/geofences/${id}`, { method: "DELETE" });
  }
  events(limit = 50) {
    return this.req<ZoneEvent[]>(`/v1/geofence-events?limit=${limit}`);
  }
}
