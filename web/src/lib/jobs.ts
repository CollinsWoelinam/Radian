import { ApiClient } from "./api";

export type LatLon = { lat: number; lon: number };

export type JobStatus =
  | "PENDING"
  | "OFFERED"
  | "ASSIGNED"
  | "EN_ROUTE_PICKUP"
  | "ON_SITE"
  | "EN_ROUTE_DROPOFF"
  | "COMPLETED"
  | "CANCELLED";

export type Job = {
  id: string;
  number: number;
  status: JobStatus;
  priority: number;
  pickup: LatLon;
  pickup_address: string;
  dropoff?: LatLon;
  dropoff_address?: string;
  notes?: string;
  eta_seconds?: number;
  vehicle?: { id: string; license_plate: string; kind: string; driver_name: string; position?: LatLon };
  offer_expires_at?: string;
  declines: number;
  created_at: string;
  assigned_at?: string;
  completed_at?: string;
  updated_at: string;
};

export type JobEvent = {
  kind: string;
  vehicle_id?: string;
  license_plate?: string;
  detail: Record<string, unknown>;
  at: string;
};

export type RouteLeg = {
  kind: "to_pickup" | "to_dropoff";
  duration_s: number;
  distance_m: number;
  coordinates: [number, number][];
};

export type JobDetail = Job & { events: JobEvent[]; route: RouteLeg[] };

export type Candidate = {
  vehicle_id: string;
  license_plate: string;
  kind: string;
  driver_name: string;
  eta_s: number;
  route_m: number;
  eta_source: "road" | "estimate";
  declined: boolean;
};

export type NewJob = {
  pickup: LatLon;
  pickup_address: string;
  dropoff?: LatLon;
  dropoff_address?: string;
  priority: number;
  notes?: string;
};

/** Client for the jobs API. */
export class JobsApi extends ApiClient {
  list(scope: "active" | "recent") {
    return this.req<Job[]>(`/v1/jobs?scope=${scope}`);
  }
  get(id: string) {
    return this.req<JobDetail>(`/v1/jobs/${id}`);
  }
  create(job: NewJob) {
    return this.req<Job>(`/v1/jobs`, { method: "POST", body: JSON.stringify(job) });
  }
  cancel(id: string, reason: string) {
    return this.req<void>(`/v1/jobs/${id}/cancel`, { method: "POST", body: JSON.stringify({ reason }) });
  }
  candidates(id: string) {
    return this.req<Candidate[]>(`/v1/jobs/${id}/candidates`);
  }
  offer(id: string, vehicleId: string) {
    return this.req<void>(`/v1/jobs/${id}/offer`, { method: "POST", body: JSON.stringify({ vehicle_id: vehicleId }) });
  }
}

export const STATUS_META: Record<JobStatus, { label: string; tone: "wait" | "offer" | "active" | "done" | "off" }> = {
  PENDING: { label: "Finding driver", tone: "wait" },
  OFFERED: { label: "Offered", tone: "offer" },
  ASSIGNED: { label: "Assigned", tone: "active" },
  EN_ROUTE_PICKUP: { label: "To pickup", tone: "active" },
  ON_SITE: { label: "At pickup", tone: "active" },
  EN_ROUTE_DROPOFF: { label: "To drop-off", tone: "active" },
  COMPLETED: { label: "Completed", tone: "done" },
  CANCELLED: { label: "Cancelled", tone: "off" },
};

export const PRIORITIES = [
  { value: 1, label: "Urgent" },
  { value: 3, label: "Normal" },
  { value: 5, label: "Low" },
];

export const priorityLabel = (p: number) => (p <= 2 ? "Urgent" : p >= 4 ? "Low" : "Normal");
