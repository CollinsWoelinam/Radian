import { BROADCAST_URL } from "./config";

export type VehicleInfo = { id: string; license_plate: string; kind: string };

export async function fetchRegistry(token: string, signal?: AbortSignal): Promise<Map<string, VehicleInfo>> {
  const res = await fetch(`${BROADCAST_URL}/v1/vehicles`, { signal, headers: { Authorization: `Bearer ${token}` } });
  if (!res.ok) throw new Error(`registry: HTTP ${res.status}`);
  const rows: VehicleInfo[] = await res.json();
  return new Map(rows.map((r) => [r.id, r]));
}
