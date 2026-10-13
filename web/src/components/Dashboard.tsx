"use client";

import { useCallback, useEffect, useMemo, useRef, useState } from "react";
import type { MapRef } from "react-map-gl/maplibre";

import FleetMap from "./FleetMap";
import { FleetStore } from "@/lib/fleet-store";
import { FleetSocket, type ConnectionState, type Viewport } from "@/lib/fleet-socket";
import { fetchRegistry, type VehicleInfo } from "@/lib/registry";
import { FLEET_WS_URL, STATUSES, statusInfo, type StatusKey, type Theme } from "@/lib/config";

type Snapshot = {
  counts: Record<StatusKey, number>;
  total: number;
  updatesPerSecond: number;
};

const UI_REFRESH_MS = 500;

function initialTheme(): Theme {
  try {
    const saved = localStorage.getItem("radian:theme");
    if (saved === "dark" || saved === "light") return saved;
  } catch {}
  return window.matchMedia("(prefers-color-scheme: light)").matches ? "light" : "dark";
}

export default function Dashboard() {
  const store = useMemo(() => new FleetStore(), []);
  const mapRef = useRef<MapRef | null>(null);
  const socketRef = useRef<FleetSocket | null>(null);

  const [theme, setTheme] = useState<Theme>(initialTheme);
  const [conn, setConn] = useState<ConnectionState>("connecting");
  const [registry, setRegistry] = useState<Map<string, VehicleInfo>>(new Map());
  const [hidden, setHidden] = useState<Set<StatusKey>>(new Set());
  const [selectedId, setSelectedId] = useState<string | null>(null);
  const [follow, setFollow] = useState(false);
  const [query, setQuery] = useState("");
  const [fps, setFps] = useState(0);
  const [, setTick] = useState(0);
  const [snap, setSnap] = useState<Snapshot>({
    counts: { EN_ROUTE: 0, ON_JOB: 0, IDLE: 0, OFFLINE: 0 },
    total: 0,
    updatesPerSecond: 0,
  });

  useEffect(() => {
    document.documentElement.dataset.theme = theme;
    try {
      localStorage.setItem("radian:theme", theme);
    } catch {}
  }, [theme]);

  useEffect(() => {
    const socket = new FleetSocket(FLEET_WS_URL, (u) => store.apply(u, performance.now()), setConn);
    socketRef.current = socket;
    socket.connect();
    return () => socket.close();
  }, [store]);

  useEffect(() => {
    const ctrl = new AbortController();
    const load = () => fetchRegistry(ctrl.signal).then(setRegistry).catch(() => {});
    load();
    const id = setInterval(load, 30_000); // pick up newly registered vehicles
    return () => {
      ctrl.abort();
      clearInterval(id);
    };
  }, []);

  // React only sees the fleet at 2 Hz; the map animates independently.
  useEffect(() => {
    const id = setInterval(() => {
      const counts: Record<StatusKey, number> = { EN_ROUTE: 0, ON_JOB: 0, IDLE: 0, OFFLINE: 0 };
      for (const v of store.list) counts[statusInfo(v.status).key]++;
      setSnap({ counts, total: store.list.length, updatesPerSecond: store.updatesPerSecond });
      setTick((t) => t + 1);
    }, UI_REFRESH_MS);
    return () => clearInterval(id);
  }, [store]);

  const onViewportChange = useCallback((v: Viewport) => socketRef.current?.setViewport(v), []);
  const onUserPan = useCallback(() => setFollow(false), []);

  const select = useCallback(
    (id: string | null, fly = false) => {
      setSelectedId(id);
      if (!id) {
        setFollow(false);
        return;
      }
      const v = store.get(id);
      if (fly && v) mapRef.current?.flyTo({ center: [v.lon, v.lat], zoom: Math.max(mapRef.current.getZoom(), 14) });
    },
    [store],
  );

  const toggleStatus = (k: StatusKey) =>
    setHidden((prev) => {
      const next = new Set(prev);
      if (next.has(k)) next.delete(k);
      else next.add(k);
      return next;
    });

  const results = useMemo(() => {
    const q = query.trim().toUpperCase();
    if (!q) return [];
    return [...registry.values()].filter((r) => r.license_plate.toUpperCase().includes(q)).slice(0, 8);
  }, [query, registry]);

  const selected = selectedId ? store.get(selectedId) : undefined;
  const selectedInfo = selectedId ? registry.get(selectedId) : undefined;

  return (
    <div className="relative h-dvh w-full overflow-hidden bg-bg text-fg">
      <FleetMap
        store={store}
        theme={theme}
        hidden={hidden}
        selectedId={selectedId}
        follow={follow}
        onSelect={(id) => select(id)}
        onViewportChange={onViewportChange}
        onUserPan={onUserPan}
        onFrame={setFps}
        mapRef={mapRef}
      />

      {/* Fleet panel */}
      <aside className="panel absolute left-4 top-4 z-10 w-[min(320px,calc(100vw-2rem))] p-4">
        <header className="flex items-center justify-between">
          <div className="flex items-center gap-2">
            <Logo />
            <div>
              <h1 className="text-[15px] font-semibold leading-tight tracking-tight">Radian</h1>
              <p className="text-[11px] text-muted">Fleet control · Accra</p>
            </div>
          </div>
          <div className="flex items-center gap-2">
            <ConnectionPill state={conn} />
            <button
              className="icon-btn"
              aria-label={`Switch to ${theme === "dark" ? "light" : "dark"} map`}
              onClick={() => setTheme(theme === "dark" ? "light" : "dark")}
            >
              {theme === "dark" ? <SunIcon /> : <MoonIcon />}
            </button>
          </div>
        </header>

        <div className="mt-4 flex items-baseline justify-between">
          <span className="text-[11px] uppercase tracking-wider text-muted">Tracking</span>
          <span className="font-mono text-2xl font-semibold tabular-nums">{snap.total.toLocaleString()}</span>
        </div>

        <ul className="mt-3 grid grid-cols-2 gap-2">
          {STATUSES.map((s) => {
            const off = hidden.has(s.key);
            return (
              <li key={s.key}>
                <button
                  onClick={() => toggleStatus(s.key)}
                  aria-pressed={!off}
                  className={`status-chip w-full ${off ? "opacity-40" : ""}`}
                  title={off ? `Show ${s.label}` : `Hide ${s.label}`}
                >
                  <span className="size-2 shrink-0 rounded-full" style={{ background: `rgb(${s.rgb.join(",")})` }} />
                  <span className="truncate text-[12px] text-muted">{s.label}</span>
                  <span className="ml-auto font-mono text-[13px] tabular-nums">{snap.counts[s.key].toLocaleString()}</span>
                </button>
              </li>
            );
          })}
        </ul>

        <div className="relative mt-4">
          <input
            value={query}
            onChange={(e) => setQuery(e.target.value)}
            placeholder="Find vehicle by plate…"
            className="w-full rounded-lg border border-line bg-input px-3 py-2 text-[13px] outline-none placeholder:text-muted focus:border-accent"
            aria-label="Find vehicle by plate"
          />
          {results.length > 0 && (
            <ul className="mt-1 max-h-56 overflow-auto rounded-lg border border-line bg-input py-1">
              {results.map((r) => {
                const v = store.get(r.id);
                return (
                  <li key={r.id}>
                    <button
                      className="flex w-full items-center gap-2 px-3 py-1.5 text-left text-[13px] hover:bg-hover disabled:opacity-40"
                      disabled={!v}
                      onClick={() => {
                        select(r.id, true);
                        setQuery("");
                      }}
                    >
                      <span
                        className="size-2 rounded-full"
                        style={{ background: v ? `rgb(${statusInfo(v.status).rgb.join(",")})` : "transparent" }}
                      />
                      <span className="font-mono">{r.license_plate}</span>
                      <span className="ml-auto text-[11px] text-muted">{v ? kindLabel(r.kind) : "out of view"}</span>
                    </button>
                  </li>
                );
              })}
            </ul>
          )}
        </div>
      </aside>

      {/* Selected vehicle */}
      {selected && (
        <section className="panel absolute bottom-4 left-4 z-10 w-[min(320px,calc(100vw-2rem))] p-4" aria-live="polite">
          <div className="flex items-start justify-between gap-3">
            <div>
              <p className="font-mono text-lg font-semibold">{selectedInfo?.license_plate ?? "Unknown"}</p>
              <p className="text-[12px] text-muted">{kindLabel(selectedInfo?.kind)}</p>
            </div>
            <button className="icon-btn" aria-label="Close details" onClick={() => select(null)}>
              <CloseIcon />
            </button>
          </div>
          <dl className="mt-3 grid grid-cols-3 gap-2 text-[12px]">
            <Stat label="Status">
              <span className="inline-flex items-center gap-1.5">
                <span
                  className="size-2 rounded-full"
                  style={{ background: `rgb(${statusInfo(selected.status).rgb.join(",")})` }}
                />
                {statusInfo(selected.status).label}
              </span>
            </Stat>
            <Stat label="Speed">{Math.round(selected.speedKmh)} km/h</Stat>
            <Stat label="Heading">
              {Math.round(selected.toHeading)}° {compass(selected.toHeading)}
            </Stat>
            <Stat label="Last fix">{ago(selected.recordedAtMs)}</Stat>
            <Stat label="Position" wide>
              {selected.toLat.toFixed(5)}, {selected.toLon.toFixed(5)}
            </Stat>
          </dl>
          <button
            className={`mt-3 w-full rounded-lg border px-3 py-2 text-[13px] font-medium transition-colors ${
              follow ? "border-accent bg-accent text-white" : "border-line hover:bg-hover"
            }`}
            onClick={() => setFollow((f) => !f)}
            aria-pressed={follow}
          >
            {follow ? "Following" : "Follow vehicle"}
          </button>
        </section>
      )}

      {/* Pipeline telemetry */}
      <div className="panel absolute right-4 top-4 z-10 hidden px-3 py-2 font-mono text-[11px] text-muted sm:block">
        <span className="tabular-nums text-fg">{Math.round(snap.updatesPerSecond).toLocaleString()}</span> updates/s
        <span className="mx-2 opacity-40">|</span>
        <span className="tabular-nums text-fg">{Math.round(fps)}</span> fps
      </div>
    </div>
  );
}

function Stat({ label, children, wide }: { label: string; children: React.ReactNode; wide?: boolean }) {
  return (
    <div className={wide ? "col-span-2" : ""}>
      <dt className="text-[10px] uppercase tracking-wider text-muted">{label}</dt>
      <dd className="mt-0.5 tabular-nums">{children}</dd>
    </div>
  );
}

function ConnectionPill({ state }: { state: ConnectionState }) {
  const label = { connecting: "Connecting", live: "Live", reconnecting: "Reconnecting" }[state];
  const color = state === "live" ? "bg-emerald-500" : "bg-amber-500";
  return (
    <span className="inline-flex items-center gap-1.5 rounded-full border border-line px-2 py-0.5 text-[11px]" role="status">
      <span className={`relative flex size-2`}>
        {state === "live" && <span className={`absolute inline-flex size-full animate-ping rounded-full ${color} opacity-60`} />}
        <span className={`relative inline-flex size-2 rounded-full ${color}`} />
      </span>
      {label}
    </span>
  );
}

const KINDS: Record<string, string> = {
  CAR: "Car",
  MOTORBIKE: "Motorbike",
  VAN: "Van",
  TRUCK: "Truck",
  AMBULANCE: "Ambulance",
};
const kindLabel = (k?: string) => (k ? (KINDS[k] ?? k) : "—");

function compass(deg: number) {
  return ["N", "NE", "E", "SE", "S", "SW", "W", "NW"][Math.round(deg / 45) % 8];
}

function ago(ms: number) {
  const s = Math.max(0, Math.round((Date.now() - ms) / 1000));
  if (s < 60) return `${s}s ago`;
  if (s < 3600) return `${Math.floor(s / 60)}m ago`;
  return `${Math.floor(s / 3600)}h ago`;
}

function Logo() {
  return (
    <svg width="28" height="28" viewBox="0 0 28 28" aria-hidden>
      <rect width="28" height="28" rx="7" className="fill-accent" />
      <circle cx="14" cy="14" r="3" fill="#fff" />
      <path d="M14 5a9 9 0 0 1 9 9" stroke="#fff" strokeWidth="2" fill="none" strokeLinecap="round" />
      <path d="M14 9a5 5 0 0 1 5 5" stroke="#fff" strokeWidth="2" fill="none" strokeLinecap="round" opacity=".7" />
    </svg>
  );
}

const iconProps = { width: 16, height: 16, viewBox: "0 0 24 24", fill: "none", stroke: "currentColor", strokeWidth: 2, strokeLinecap: "round" as const, strokeLinejoin: "round" as const, "aria-hidden": true };

function SunIcon() {
  return (
    <svg {...iconProps}>
      <circle cx="12" cy="12" r="4" />
      <path d="M12 2v2M12 20v2M4.9 4.9l1.4 1.4M17.7 17.7l1.4 1.4M2 12h2M20 12h2M4.9 19.1l1.4-1.4M17.7 6.3l1.4-1.4" />
    </svg>
  );
}

function MoonIcon() {
  return (
    <svg {...iconProps}>
      <path d="M21 12.8A9 9 0 1 1 11.2 3a7 7 0 0 0 9.8 9.8z" />
    </svg>
  );
}

function CloseIcon() {
  return (
    <svg {...iconProps}>
      <path d="M18 6 6 18M6 6l12 12" />
    </svg>
  );
}
