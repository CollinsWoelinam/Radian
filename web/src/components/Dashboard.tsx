"use client";

import { useCallback, useEffect, useMemo, useRef, useState } from "react";
import type { MapRef } from "react-map-gl/maplibre";

import FleetMap, { type JobOverlay } from "./FleetMap";
import JobsPanel, { type PanelMode } from "./JobsPanel";
import LoginScreen from "./LoginScreen";
import { clearSession, loadSession, type DispatcherSession } from "@/lib/auth";
import { JobsApi, type Job, type JobDetail, type LatLon } from "@/lib/jobs";
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

type Draft = { pickup?: LatLon; dropoff?: LatLon | null };

/** Signs the dispatcher in, then shows the live dashboard. */
export default function Dashboard() {
  const [session, setSession] = useState<DispatcherSession | null>(loadSession);
  const signOut = useCallback(() => {
    clearSession();
    setSession(null);
  }, []);
  if (!session) return <LoginScreen onSignedIn={setSession} />;
  return <FleetDashboard session={session} onSignOut={signOut} />;
}

function FleetDashboard({ session, onSignOut }: { session: DispatcherSession; onSignOut: () => void }) {
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
  const api = useMemo(() => new JobsApi(session.token, onSignOut), [session.token, onSignOut]);
  const [active, setActive] = useState<Job[]>([]);
  const [recent, setRecent] = useState<Job[]>([]);
  const [panel, setPanel] = useState<PanelMode>("list");
  const [selectedJobId, setSelectedJobId] = useState<string | null>(null);
  const [selectedJob, setSelectedJob] = useState<JobDetail | null>(null);
  const [draft, setDraft] = useState<Draft | null>(null);
  const [jobError, setJobError] = useState<string | null>(null);
  const [jobsOpen, setJobsOpen] = useState(false); // small screens
  const jobOverlay = useRef<JobOverlay>({ jobs: [], selectedJob: null, draft: null, picking: false });
  const selectedJobRef = useRef<string | null>(null);
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

  // --- Jobs -------------------------------------------------------------------
  const refreshJobs = useCallback(async () => {
    try {
      const [a, r] = await Promise.all([api.list("active"), api.list("recent")]);
      setActive(a);
      setRecent(r);
    } catch {}
  }, [api]);

  const refreshSelected = useCallback(async () => {
    const id = selectedJobRef.current;
    if (!id) return;
    try {
      const d = await api.get(id);
      if (selectedJobRef.current === id) setSelectedJob(d);
    } catch {}
  }, [api]);

  useEffect(() => {
    const first = setTimeout(refreshJobs, 0);
    const t = setInterval(refreshJobs, 15_000); // safety net; pushes usually arrive first
    return () => {
      clearTimeout(first);
      clearInterval(t);
    };
  }, [refreshJobs]);

  useEffect(() => {
    selectedJobRef.current = selectedJobId;
    if (!selectedJobId) return;
    const first = setTimeout(refreshSelected, 0);
    const t = setInterval(refreshSelected, 5_000); // keeps the live route and ETA fresh
    return () => {
      clearTimeout(first);
      clearInterval(t);
    };
  }, [selectedJobId, refreshSelected]);

  // Only show detail that belongs to the current selection (a stale fetch may linger).
  const shownJob = selectedJob && selectedJob.id === selectedJobId ? selectedJob : null;

  useEffect(() => {
    const picking = panel === "create" && (!draft?.pickup || draft.dropoff === undefined);
    jobOverlay.current = { jobs: active, selectedJob: shownJob, draft: draft && { pickup: draft.pickup, dropoff: draft.dropoff ?? undefined }, picking };
  }, [active, shownJob, draft, panel]);

  // Job-change pushes arrive in bursts (offer, accept, status); refetch once per burst.
  const jobsTimer = useRef<ReturnType<typeof setTimeout> | null>(null);
  const onJobsChanged = useCallback(() => {
    if (jobsTimer.current) clearTimeout(jobsTimer.current);
    jobsTimer.current = setTimeout(() => {
      refreshJobs();
      refreshSelected();
    }, 250);
  }, [refreshJobs, refreshSelected]);

  useEffect(() => {
    const url = `${FLEET_WS_URL}?token=${encodeURIComponent(session.token)}`;
    const socket = new FleetSocket(url, (u) => store.apply(u, performance.now()), setConn, onJobsChanged);
    socketRef.current = socket;
    socket.connect();
    return () => socket.close();
  }, [store, session.token, onJobsChanged]);

  useEffect(() => {
    const ctrl = new AbortController();
    const load = () => fetchRegistry(session.token, ctrl.signal).then(setRegistry).catch(() => {});
    load();
    const id = setInterval(load, 30_000); // pick up newly registered vehicles
    return () => {
      ctrl.abort();
      clearInterval(id);
    };
  }, [session.token]);

  const flyTo = useCallback((at: LatLon, zoom = 14.5) => {
    mapRef.current?.flyTo({ center: [at.lon, at.lat], zoom: Math.max(mapRef.current.getZoom(), zoom) });
  }, []);

  const selectJob = useCallback(
    (id: string | null) => {
      setJobError(null);
      setSelectedJobId(id);
      setPanel(id ? "detail" : "list");
      const j = id ? [...active, ...recent].find((x) => x.id === id) : undefined;
      if (j) flyTo(j.pickup, 13.5);
    },
    [active, recent, flyTo],
  );

  const run = useCallback(async (f: () => Promise<unknown>) => {
    setJobError(null);
    try {
      await f();
    } catch (e) {
      setJobError(e instanceof Error ? e.message : "Something went wrong.");
    }
  }, []);

  const onMapClick = useCallback(
    (at: LatLon) => {
      if (panel !== "create") return;
      setDraft((d) => (!d?.pickup ? { pickup: at } : d.dropoff === undefined ? { ...d, dropoff: at } : d));
    },
    [panel],
  );

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
        jobOverlay={jobOverlay}
        onSelectJob={selectJob}
        onMapClick={onMapClick}
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
            <button className="icon-btn" aria-label={`Sign out ${session.dispatcher.full_name}`} title={`Sign out ${session.dispatcher.full_name}`} onClick={onSignOut}>
              <LogoutIcon />
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
        <p className="mt-3 font-mono text-[11px] text-muted">
          <span className="tabular-nums text-fg">{Math.round(snap.updatesPerSecond).toLocaleString()}</span> updates/s
          <span className="mx-2 opacity-40">|</span>
          <span className="tabular-nums text-fg">{Math.round(fps)}</span> fps
        </p>
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

      {/* Jobs: right-hand panel on wide screens, a toggled sheet on phones */}
      <button
        className="panel absolute bottom-4 left-1/2 z-20 -translate-x-1/2 px-4 py-2 text-[13px] font-semibold sm:hidden"
        onClick={() => setJobsOpen((o) => !o)}
        aria-expanded={jobsOpen}
      >
        {jobsOpen ? "Hide jobs" : `Jobs (${active.length})`}
      </button>
      <section
        className={`panel absolute z-10 flex-col overflow-hidden ${jobsOpen ? "flex" : "hidden"} inset-x-2 bottom-16 max-h-[60dvh] sm:inset-x-auto sm:bottom-auto sm:right-4 sm:top-4 sm:flex sm:max-h-[calc(100dvh-7rem)] sm:w-[360px]`}
        aria-label="Jobs"
      >
        <JobsPanel
          mode={panel}
          active={active}
          recent={recent}
          selected={shownJob}
          draft={draft}
          error={jobError}
          onNewJob={() => {
            setSelectedJobId(null);
            setDraft({});
            setPanel("create");
            setJobsOpen(true);
          }}
          onCancelDraft={() => {
            setDraft(null);
            setPanel("list");
          }}
          onSkipDropoff={() => setDraft((d) => ({ ...d, dropoff: null }))}
          onCreate={(fields) =>
            run(async () => {
              if (!draft?.pickup) return;
              const job = await api.create({ ...fields, pickup: draft.pickup, dropoff: draft.dropoff ?? undefined });
              setDraft(null);
              await refreshJobs();
              setSelectedJobId(job.id);
              setPanel("detail");
            })
          }
          onSelect={selectJob}
          onCancelJob={(id, reason) => run(() => api.cancel(id, reason).then(refreshJobs).then(refreshSelected))}
          loadCandidates={async (id) => {
            try {
              return await api.candidates(id);
            } catch (e) {
              setJobError(e instanceof Error ? e.message : "Couldn't load drivers.");
              return [];
            }
          }}
          onOffer={(jobId, vehicleId) => run(() => api.offer(jobId, vehicleId).then(refreshSelected).then(refreshJobs))}
          onFocus={(at) => flyTo(at)}
        />
      </section>
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

function LogoutIcon() {
  return (
    <svg {...iconProps}>
      <path d="M9 21H5a2 2 0 0 1-2-2V5a2 2 0 0 1 2-2h4M16 17l5-5-5-5M21 12H9" />
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
