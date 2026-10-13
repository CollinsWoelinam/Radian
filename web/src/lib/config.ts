import { VehicleStatus } from "@/gen/radian/telemetry/v1/telemetry_pb";

export const BROADCAST_URL = process.env.NEXT_PUBLIC_BROADCAST_URL ?? "http://localhost:8082";
export const FLEET_WS_URL = BROADCAST_URL.replace(/^http/, "ws") + "/v1/fleet/ws";

export const MAP_STYLES = {
  dark: "https://tiles.openfreemap.org/styles/dark",
  light: "https://tiles.openfreemap.org/styles/positron",
} as const;

export type Theme = keyof typeof MAP_STYLES;

// Greater Accra
export const INITIAL_VIEW = { longitude: -0.19, latitude: 5.6, zoom: 11.3 };

export type StatusKey = "EN_ROUTE" | "ON_JOB" | "IDLE" | "OFFLINE";

export const STATUSES: { key: StatusKey; value: VehicleStatus; label: string; rgb: [number, number, number] }[] = [
  { key: "EN_ROUTE", value: VehicleStatus.EN_ROUTE, label: "En route", rgb: [59, 130, 246] },
  { key: "ON_JOB", value: VehicleStatus.ON_JOB, label: "On job", rgb: [245, 158, 11] },
  { key: "IDLE", value: VehicleStatus.IDLE, label: "Idle", rgb: [34, 197, 94] },
  { key: "OFFLINE", value: VehicleStatus.OFFLINE, label: "Offline", rgb: [120, 128, 140] },
];

export const statusInfo = (s: VehicleStatus) => STATUSES.find((x) => x.value === s) ?? STATUSES[3];
