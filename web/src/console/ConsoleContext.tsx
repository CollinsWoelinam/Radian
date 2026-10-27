"use client";

import { createContext, useCallback, useContext, useEffect, useMemo, useRef, useState } from "react";

import type { DispatcherSession } from "@/lib/auth";
import { ConsoleApi, type AttentionItem, type Overview } from "@/lib/console";
import { FLEET_WS_URL, type Theme } from "@/lib/config";
import { FleetSocket, type ConnectionState, type Viewport } from "@/lib/fleet-socket";
import { FleetStore } from "@/lib/fleet-store";
import { GeofencesApi, fromMessage, severity, type Severity, type Zone, type ZoneEvent } from "@/lib/geofences";
import { JobsApi, type Job, type LatLon } from "@/lib/jobs";
import { fetchRegistry, type VehicleInfo } from "@/lib/registry";

export type Toast = { key: number; event: ZoneEvent; severity: Severity };
/** A recent alert to pulse on the map; `t` is performance.now() when received. */
export type MapAlert = { at: LatLon; t: number; severity: Severity };

type ConsoleState = {
  session: DispatcherSession;
  signOut: () => void;
  theme: Theme;
  setTheme: (t: Theme) => void;
  jobsApi: JobsApi;
  zonesApi: GeofencesApi;
  consoleApi: ConsoleApi;
  /** Live fleet, updated outside React; read it during render or every frame. */
  store: FleetStore;
  conn: ConnectionState;
  setViewport: (v: Viewport) => void;
  registry: Map<string, VehicleInfo>;
  active: Job[];
  recent: Job[];
  refreshJobs: () => Promise<void>;
  /** Bumped on every job change push, so open pages can refetch details. */
  jobsVersion: number;
  zones: Zone[];
  setZones: React.Dispatch<React.SetStateAction<Zone[]>>;
  refreshZones: () => Promise<void>;
  zoneEvents: ZoneEvent[];
  setZoneEvents: React.Dispatch<React.SetStateAction<ZoneEvent[]>>;
  overview: Overview | null;
  attention: AttentionItem[];
  toasts: Toast[];
  dismissToast: (key: number) => void;
  mapAlerts: React.RefObject<MapAlert[]>;
  paletteOpen: boolean;
  setPaletteOpen: (open: boolean) => void;
};

const Ctx = createContext<ConsoleState | null>(null);

export function useConsole() {
  const c = useContext(Ctx);
  if (!c) throw new Error("useConsole outside ConsoleProvider");
  return c;
}

const TOAST_MS = 8000;
const MAX_TOASTS = 3;

function initialTheme(): Theme {
  try {
    const saved = localStorage.getItem("radian:theme");
    if (saved === "dark" || saved === "light") return saved;
  } catch {}
  return window.matchMedia("(prefers-color-scheme: light)").matches ? "light" : "dark";
}

/** Newest first, de-duplicated (a live push may also arrive in a fetch). */
export function mergeEvents(a: ZoneEvent[], b: ZoneEvent[]) {
  const seen = new Set<number>();
  return [...a, ...b]
    .filter((e) => (seen.has(e.id) ? false : (seen.add(e.id), true)))
    .sort((x, y) => Date.parse(y.occurred_at) - Date.parse(x.occurred_at) || y.id - x.id)
    .slice(0, 200);
}

export function ConsoleProvider({
  session,
  onSignOut,
  children,
}: {
  session: DispatcherSession;
  onSignOut: () => void;
  children: React.ReactNode;
}) {
  const store = useMemo(() => new FleetStore(), []);
  const jobsApi = useMemo(() => new JobsApi(session.token, onSignOut), [session.token, onSignOut]);
  const zonesApi = useMemo(() => new GeofencesApi(session.token, onSignOut), [session.token, onSignOut]);
  const consoleApi = useMemo(() => new ConsoleApi(session.token, onSignOut), [session.token, onSignOut]);

  const [theme, setThemeState] = useState<Theme>(initialTheme);
  const [conn, setConn] = useState<ConnectionState>("connecting");
  const [registry, setRegistry] = useState<Map<string, VehicleInfo>>(new Map());
  const [active, setActive] = useState<Job[]>([]);
  const [recent, setRecent] = useState<Job[]>([]);
  const [jobsVersion, setJobsVersion] = useState(0);
  const [zones, setZones] = useState<Zone[]>([]);
  const [zoneEvents, setZoneEvents] = useState<ZoneEvent[]>([]);
  const [overview, setOverview] = useState<Overview | null>(null);
  const [attention, setAttention] = useState<AttentionItem[]>([]);
  const [toasts, setToasts] = useState<Toast[]>([]);
  const [paletteOpen, setPaletteOpen] = useState(false);
  const mapAlerts = useRef<MapAlert[]>([]);
  const socketRef = useRef<FleetSocket | null>(null);

  useEffect(() => {
    document.documentElement.dataset.theme = theme;
    try {
      localStorage.setItem("radian:theme", theme);
    } catch {}
  }, [theme]);

  const refreshJobs = useCallback(async () => {
    try {
      const [a, r] = await Promise.all([jobsApi.list("active"), jobsApi.list("recent")]);
      setActive(a);
      setRecent(r);
    } catch {}
  }, [jobsApi]);

  const refreshZones = useCallback(async () => {
    try {
      setZones(await zonesApi.list());
    } catch {}
  }, [zonesApi]);

  const refreshOps = useCallback(async () => {
    try {
      const [o, a] = await Promise.all([consoleApi.overview(), consoleApi.attention()]);
      setOverview(o);
      setAttention(a);
    } catch {}
  }, [consoleApi]);

  // Initial loads, then slow polls as a safety net: pushes usually arrive first.
  useEffect(() => {
    const first = setTimeout(async () => {
      refreshJobs();
      refreshZones();
      refreshOps();
      try {
        const evs = await zonesApi.events(100);
        setZoneEvents((live) => mergeEvents(live, evs));
      } catch {}
    }, 0);
    const jobsTimer = setInterval(refreshJobs, 15_000);
    const zonesTimer = setInterval(refreshZones, 30_000);
    const opsTimer = setInterval(refreshOps, 10_000);
    return () => {
      clearTimeout(first);
      clearInterval(jobsTimer);
      clearInterval(zonesTimer);
      clearInterval(opsTimer);
    };
  }, [refreshJobs, refreshZones, refreshOps, zonesApi]);

  useEffect(() => {
    const ctrl = new AbortController();
    const load = () => fetchRegistry(session.token, ctrl.signal).then(setRegistry).catch(() => {});
    load();
    const id = setInterval(load, 30_000);
    return () => {
      ctrl.abort();
      clearInterval(id);
    };
  }, [session.token]);

  // Bursts of pushes (offer, accept, status) refetch once.
  const burst = useRef<ReturnType<typeof setTimeout> | null>(null);
  const onJobsChanged = useCallback(() => {
    if (burst.current) clearTimeout(burst.current);
    burst.current = setTimeout(() => {
      refreshJobs();
      refreshOps();
      setJobsVersion((v) => v + 1);
    }, 250);
  }, [refreshJobs, refreshOps]);

  const toastKey = useRef(0);
  const zoneBurst = useRef<ReturnType<typeof setTimeout> | null>(null);
  const onGeofenceEvent = useCallback(
    (e: ZoneEvent) => {
      setZoneEvents((prev) => mergeEvents([e], prev));
      if (zoneBurst.current) clearTimeout(zoneBurst.current);
      zoneBurst.current = setTimeout(() => {
        refreshZones();
        refreshOps();
      }, 1000);
      const sev = severity(e);
      if (sev === "info") return;
      if (e.position) {
        const recentAlerts = mapAlerts.current.filter((a) => performance.now() - a.t < 5000);
        mapAlerts.current = [...recentAlerts, { at: e.position, t: performance.now(), severity: sev }];
      }
      const key = ++toastKey.current;
      setToasts((t) => [...t, { key, event: e, severity: sev }].slice(-MAX_TOASTS));
      setTimeout(() => setToasts((t) => t.filter((x) => x.key !== key)), TOAST_MS);
    },
    [refreshZones, refreshOps],
  );

  useEffect(() => {
    const url = `${FLEET_WS_URL}?token=${encodeURIComponent(session.token)}`;
    const socket = new FleetSocket(url, (u) => store.apply(u, performance.now()), setConn, {
      onJobsChanged,
      onGeofenceEvent: (m) => onGeofenceEvent(fromMessage(m)),
      onGeofencesChanged: refreshZones,
    });
    socketRef.current = socket;
    socket.connect();
    return () => socket.close();
  }, [store, session.token, onJobsChanged, onGeofenceEvent, refreshZones]);

  // ⌘K / Ctrl+K opens the command palette from anywhere.
  useEffect(() => {
    const onKey = (e: KeyboardEvent) => {
      if ((e.metaKey || e.ctrlKey) && e.key.toLowerCase() === "k") {
        e.preventDefault();
        setPaletteOpen((o) => !o);
      }
    };
    window.addEventListener("keydown", onKey);
    return () => window.removeEventListener("keydown", onKey);
  }, []);

  const value: ConsoleState = {
    session,
    signOut: onSignOut,
    theme,
    setTheme: setThemeState,
    jobsApi,
    zonesApi,
    consoleApi,
    store,
    conn,
    setViewport: useCallback((v: Viewport) => socketRef.current?.setViewport(v), []),
    registry,
    active,
    recent,
    refreshJobs,
    jobsVersion,
    zones,
    setZones,
    refreshZones,
    zoneEvents,
    setZoneEvents,
    overview,
    attention,
    toasts,
    dismissToast: useCallback((key: number) => setToasts((t) => t.filter((x) => x.key !== key)), []),
    mapAlerts,
    paletteOpen,
    setPaletteOpen,
  };
  return <Ctx.Provider value={value}>{children}</Ctx.Provider>;
}
