import { ApiClient } from "./api";
import type { Job, LatLon } from "./jobs";

export type Overview = {
  online: number;
  vehicles: number;
  active_jobs: number;
  waiting_jobs: number;
  completed_today: number;
  median_pickup_s: number | null;
  alerts_last_hour: number;
};

export type AttentionItem = {
  kind: "offer_expiring" | "no_driver" | "zone_alert" | "offline_on_job";
  at: string;
  job_id?: string;
  job_number?: number;
  place?: string;
  vehicle_id?: string;
  license_plate?: string;
  driver_name?: string;
  zone_name?: string;
  zone_kind?: string;
  entered?: boolean;
  dwell?: boolean;
  expires_at?: string;
  declines?: number;
};

export type VehicleDetail = {
  id: string;
  license_plate: string;
  kind: string;
  status: string;
  driver_name?: string;
  driver_phone?: string;
  online: boolean;
  last_seen?: string;
  position?: LatLon & { speed_kmh?: number; heading_deg?: number; accuracy_m?: number; battery_pct?: number; recorded_at: string };
  shift_started_at?: string;
  job?: Job;
};

export type TrackEvent = {
  kind: "speeding" | "stop" | "no_signal" | "job" | "zone";
  at: string;
  duration_s?: number;
  lat?: number;
  lon?: number;
  max_speed_kmh?: number;
  job_number?: number;
  job_event?: string;
  zone_name?: string;
  zone_kind?: string;
  entered?: boolean;
  dwell?: boolean;
  alert?: boolean;
};

export type Track = {
  from: string;
  to: string;
  summary: { distance_m: number; driving_s: number; top_speed_kmh: number };
  jobs_completed: number;
  /** [unix ms, lat, lon, speed km/h or -1] */
  points: [number, number, number, number][];
  events: TrackEvent[];
};

export const SPEED_LIMIT_KMH = 80;

export class ConsoleApi extends ApiClient {
  overview() {
    return this.req<Overview>(`/v1/overview`);
  }
  attention() {
    return this.req<AttentionItem[]>(`/v1/attention`);
  }
  vehicle(id: string) {
    return this.req<VehicleDetail>(`/v1/vehicles/${id}`);
  }
  track(id: string, from?: Date, to?: Date) {
    const q = new URLSearchParams();
    if (from) q.set("from", from.toISOString());
    if (to) q.set("to", to.toISOString());
    return this.req<Track>(`/v1/vehicles/${id}/track${q.size ? `?${q}` : ""}`);
  }
}

export function duration(s: number) {
  if (s < 60) return `${Math.round(s)}s`;
  const m = Math.round(s / 60);
  if (m < 60) return `${m} min`;
  return `${Math.floor(m / 60)}h ${String(m % 60).padStart(2, "0")}m`;
}

export function distance(m: number) {
  return m >= 1000 ? `${(m / 1000).toFixed(1)} km` : `${Math.round(m)} m`;
}

export function clock(iso: string | number) {
  return new Date(iso).toLocaleTimeString([], { hour: "2-digit", minute: "2-digit", hour12: false });
}

export function ago(iso: string) {
  const s = Math.max(0, Math.round((Date.now() - Date.parse(iso)) / 1000));
  if (s < 60) return `${s}s ago`;
  if (s < 3600) return `${Math.floor(s / 60)} min ago`;
  if (s < 86400) return `${Math.floor(s / 3600)}h ago`;
  return new Date(iso).toLocaleDateString();
}
