"use client";

import Link from "next/link";
import { useParams } from "next/navigation";
import { useEffect, useMemo, useRef, useState } from "react";

import { ago, clock, distance, duration, SPEED_LIMIT_KMH, type Track, type TrackEvent, type VehicleDetail } from "@/lib/console";
import { STATUS_META } from "@/lib/jobs";
import { useConsole } from "../ConsoleContext";
import { ReplayMap } from "../maps";
import { Empty, Icon, PageHeader, Stat } from "../ui";

type Window = "shift" | "today" | "12h" | "yesterday";
const WINDOWS: { id: Window; label: string }[] = [
  { id: "shift", label: "This shift" },
  { id: "today", label: "Today" },
  { id: "12h", label: "Last 12 h" },
  { id: "yesterday", label: "Yesterday" },
];
const SPEEDS = [1, 8, 32, 128];
const KINDS: Record<string, string> = { CAR: "Car", MOTORBIKE: "Motorbike", VAN: "Van", TRUCK: "Truck", AMBULANCE: "Ambulance" };

function range(w: Window): [Date?, Date?] {
  const now = new Date();
  const midnight = new Date(now);
  midnight.setHours(0, 0, 0, 0);
  switch (w) {
    case "today":
      return [midnight, now];
    case "12h":
      return [new Date(now.getTime() - 12 * 3600_000), now];
    case "yesterday":
      return [new Date(midnight.getTime() - 86400_000), midnight];
    default:
      return [undefined, undefined]; // the server picks the open shift, else 12 h
  }
}

export default function VehiclePage() {
  const { id } = useParams<{ id: string }>();
  const { consoleApi, theme } = useConsole();
  const [vehicle, setVehicle] = useState<VehicleDetail | null>(null);
  const [missing, setMissing] = useState(false);
  const [win, setWin] = useState<Window>("shift");
  const [track, setTrack] = useState<Track | null>(null);
  const [loading, setLoading] = useState(true);
  const [cursor, setCursor] = useState(0);
  const [playing, setPlaying] = useState(false);
  const [speed, setSpeed] = useState(32);

  useEffect(() => {
    let live = true;
    const load = () =>
      consoleApi
        .vehicle(id)
        .then((v) => live && setVehicle(v))
        .catch((e) => live && e?.status === 404 && setMissing(true));
    load();
    const t = setInterval(load, 15_000);
    return () => {
      live = false;
      clearInterval(t);
    };
  }, [consoleApi, id]);

  useEffect(() => {
    let live = true;
    const [from, to] = range(win);
    const t = setTimeout(() => {
      setLoading(true);
      consoleApi
        .track(id, from, to)
        .then((tr) => {
          if (!live) return;
          setTrack(tr);
          setCursor(Math.max(0, tr.points.length - 1));
          setPlaying(false);
        })
        .catch(() => live && setTrack(null))
        .finally(() => live && setLoading(false));
    }, 0);
    return () => {
      live = false;
      clearTimeout(t);
    };
  }, [consoleApi, id, win]);

  // Playback: advance through the track at `speed`× real time.
  const raf = useRef(0);
  useEffect(() => {
    if (!playing || !track || track.points.length < 2) return;
    const pts = track.points;
    let last = performance.now();
    let t = pts[Math.min(cursor, pts.length - 1)][0];
    let i = cursor;
    const step = (now: number) => {
      t += (now - last) * speed;
      last = now;
      while (i < pts.length - 1 && pts[i + 1][0] <= t) i++;
      setCursor(i);
      if (i >= pts.length - 1) {
        setPlaying(false);
        return;
      }
      raf.current = requestAnimationFrame(step);
    };
    raf.current = requestAnimationFrame(step);
    return () => cancelAnimationFrame(raf.current);
    // The cursor is read once when playback starts.
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [playing, speed, track]);

  const here = track?.points[Math.min(cursor, (track?.points.length ?? 1) - 1)];

  if (missing) {
    return (
      <>
        <PageHeader title="Vehicle not found" back={{ href: "/vehicles", label: "Back to vehicles" }} />
        <div className="p-6">
          <Empty>This vehicle doesn&apos;t exist.</Empty>
        </div>
      </>
    );
  }

  return (
    <>
      <PageHeader
        back={{ href: "/vehicles", label: "Back to vehicles" }}
        title={<span className="font-mono">{vehicle?.license_plate ?? "…"}</span>}
        subtitle={vehicle ? `${KINDS[vehicle.kind] ?? vehicle.kind}${vehicle.driver_name ? ` · ${vehicle.driver_name}` : ""}${vehicle.shift_started_at ? ` · on shift since ${clock(vehicle.shift_started_at)}` : ""}` : ""}
      >
        {vehicle && (
          <span className="inline-flex items-center gap-2 rounded-full border border-line px-3 py-1 text-[12px]">
            <span className={`size-2 rounded-full ${vehicle.online ? "bg-emerald-500" : "bg-slate-400"}`} />
            {vehicle.online ? "Online" : vehicle.last_seen ? `Last seen ${ago(vehicle.last_seen)}` : "Never seen"}
          </span>
        )}
        {vehicle?.job && (
          <Link href={`/jobs/${vehicle.job.id}`} className="rounded-full bg-amber-500 px-3 py-1 text-[12px] font-semibold text-[#1f1300]">
            On job #{vehicle.job.number}
          </Link>
        )}
        <div role="tablist" aria-label="Time range" className="flex flex-wrap gap-0.5 rounded-[10px] bg-sunken p-[3px]">
          {WINDOWS.map((w) => (
            <button key={w.id} type="button" role="tab" aria-selected={win === w.id} onClick={() => setWin(w.id)} className={`h-8 rounded-lg px-3 text-[13px] font-semibold ${win === w.id ? "bg-surface shadow-sm" : "text-muted"}`}>
              {w.label}
            </button>
          ))}
        </div>
      </PageHeader>

      <div className="flex grow flex-wrap">
        <div className="flex min-w-0 flex-[999_1_560px] flex-col">
          <section aria-label="Route replay" className="relative min-h-[440px] grow overflow-hidden">
            {track && <ReplayMap points={track.points} cursor={cursor} events={track.events} theme={theme} />}
            {!loading && track && track.points.length === 0 && (
              <div className="absolute inset-0 z-10 grid place-items-center bg-sunken/80 text-[14px] text-muted">No location data in this time range.</div>
            )}
            {loading && <div className="absolute inset-0 grid place-items-center text-[13px] text-muted">Loading route…</div>}
            {here && (
              <div className="panel absolute right-4 top-4 z-10 min-w-[170px] px-3.5 py-3">
                <div className="font-mono text-[20px] font-semibold">{new Date(here[0]).toLocaleTimeString([], { hour12: false })}</div>
                <div className="text-[12px] text-muted">{here[3] >= 0 ? `${Math.round(here[3])} km/h` : "speed unknown"}</div>
              </div>
            )}
            <div className="absolute left-4 top-4 z-10 flex flex-wrap gap-2 text-[12px]">
              <span className="panel inline-flex h-8 items-center gap-2 !rounded-full px-3">
                <span className="h-1 w-4 rounded bg-[#4f8bff]" /> Within limit
              </span>
              <span className="panel inline-flex h-8 items-center gap-2 !rounded-full px-3">
                <span className="h-1 w-4 rounded bg-red-500" /> Over {SPEED_LIMIT_KMH} km/h
              </span>
            </div>
          </section>

          {track && track.points.length > 1 && (
            <section aria-label="Playback" className="flex flex-col gap-3 border-t border-line bg-sunken px-5 pb-4 pt-3.5">
              <div className="flex flex-wrap items-center gap-3">
                <button type="button" aria-label={playing ? "Pause" : "Play"} onClick={() => (cursor >= track.points.length - 1 ? (setCursor(0), setPlaying(true)) : setPlaying((p) => !p))} className="grid size-11 place-items-center rounded-full bg-accent text-white">
                  {playing ? <Icon.Pause /> : <Icon.Play />}
                </button>
                <div role="group" aria-label="Playback speed" className="flex gap-1">
                  {SPEEDS.map((s) => (
                    <button key={s} type="button" aria-pressed={speed === s} onClick={() => setSpeed(s)} className={`h-8 rounded-lg border px-2.5 font-mono text-[12px] ${speed === s ? "border-accent bg-accent/10" : "border-line text-muted"}`}>
                      {s}×
                    </button>
                  ))}
                </div>
                <span className="grow" />
                <span className="font-mono text-[12px] text-muted">
                  {clock(track.points[0][0])} → {clock(track.points[track.points.length - 1][0])}
                </span>
              </div>
              <SpeedChart points={track.points} cursor={cursor} onSeek={(i) => (setPlaying(false), setCursor(i))} />
            </section>
          )}
        </div>

        <aside aria-label="Trip details" className="flex max-w-full flex-[1_1_320px] flex-col gap-5 border-l border-line p-5">
          {track ? (
            <dl className="grid grid-cols-2 gap-2.5">
              <Stat label="Distance" value={distance(track.summary.distance_m)} />
              <Stat label="Driving" value={duration(track.summary.driving_s)} />
              <Stat label="Jobs done" value={track.jobs_completed} />
              <Stat label="Top speed" value={`${track.summary.top_speed_kmh} km/h`} tone={track.summary.top_speed_kmh > SPEED_LIMIT_KMH ? "danger" : undefined} />
            </dl>
          ) : (
            !loading && <Empty>Couldn&apos;t load this vehicle&apos;s route.</Empty>
          )}
          <div>
            <h2 className="mb-2.5 text-[15px] font-semibold">Events</h2>
            {track && track.events.length === 0 && <p className="text-[13px] text-muted">Nothing notable in this time range.</p>}
            <ol className="flex flex-col gap-3 text-[13px]">
              {track?.events.slice(0, 40).map((e, i) => (
                <li key={i} className="grid grid-cols-[46px_minmax(0,1fr)] gap-2">
                  <span className="font-mono text-muted">{clock(e.at)}</span>
                  <EventText e={e} />
                </li>
              ))}
            </ol>
          </div>
          {vehicle?.position && (
            <div>
              <h2 className="mb-2.5 text-[15px] font-semibold">Phone</h2>
              <ul className="flex flex-col gap-2 text-[13px]">
                <li className="flex justify-between">
                  <span className="text-muted">Battery</span>
                  <span className="font-mono">{vehicle.position.battery_pct != null ? `${vehicle.position.battery_pct}%` : "—"}</span>
                </li>
                <li className="flex justify-between">
                  <span className="text-muted">GPS accuracy</span>
                  <span className="font-mono">{vehicle.position.accuracy_m != null ? `±${Math.round(vehicle.position.accuracy_m)} m` : "—"}</span>
                </li>
                <li className="flex justify-between">
                  <span className="text-muted">Last fix</span>
                  <span>{ago(vehicle.position.recorded_at)}</span>
                </li>
                {vehicle.driver_phone && (
                  <li className="flex justify-between">
                    <span className="text-muted">Driver</span>
                    <a href={`tel:${vehicle.driver_phone}`} className="font-mono text-accent-fg">
                      {vehicle.driver_phone}
                    </a>
                  </li>
                )}
              </ul>
            </div>
          )}
        </aside>
      </div>
    </>
  );
}

function EventText({ e }: { e: TrackEvent }) {
  switch (e.kind) {
    case "speeding":
      return <span className="text-red-600 dark:text-red-400">{e.max_speed_kmh} km/h for {duration(e.duration_s ?? 0)}</span>;
    case "stop":
      return <span>Stopped {duration(e.duration_s ?? 0)}</span>;
    case "no_signal":
      return <span className="text-muted">No location for {duration(e.duration_s ?? 0)}</span>;
    case "job": {
      const step = e.job_event === "accepted" ? "Accepted" : (STATUS_META[e.job_event as keyof typeof STATUS_META]?.label ?? e.job_event);
      return (
        <span>
          {step} · job <span className="font-mono">#{e.job_number}</span>
        </span>
      );
    }
    case "zone":
      return (
        <span className={e.alert ? "text-amber-600 dark:text-amber-400" : ""}>
          {e.dwell ? "Stayed too long in" : e.entered ? "Entered" : "Left"} {e.zone_name}
        </span>
      );
  }
}

/** Speed over the window; click or drag to move the playhead. */
function SpeedChart({ points, cursor, onSeek }: { points: [number, number, number, number][]; cursor: number; onSeek: (i: number) => void }) {
  const W = 1000;
  const H = 110;
  const t0 = points[0][0];
  const t1 = points[points.length - 1][0] || t0 + 1;
  const max = Math.max(SPEED_LIMIT_KMH + 20, ...points.map((p) => p[3]));
  const x = (t: number) => ((t - t0) / (t1 - t0 || 1)) * W;
  const y = (v: number) => H - (Math.max(0, v) / max) * (H - 8);
  const line = useMemo(() => points.map((p, i) => `${i ? "L" : "M"}${x(p[0]).toFixed(1)} ${y(p[3]).toFixed(1)}`).join(" "), [points]); // eslint-disable-line react-hooks/exhaustive-deps
  const seek = (clientX: number, el: SVGSVGElement) => {
    const r = el.getBoundingClientRect();
    const t = t0 + ((clientX - r.left) / r.width) * (t1 - t0);
    let i = 0;
    while (i < points.length - 1 && points[i + 1][0] <= t) i++;
    onSeek(i);
  };
  const cx = x(points[Math.min(cursor, points.length - 1)][0]);
  return (
    <svg
      viewBox={`0 0 ${W} ${H}`}
      preserveAspectRatio="none"
      className="h-[110px] w-full cursor-pointer touch-none"
      role="slider"
      aria-label="Playback position"
      aria-valuemin={0}
      aria-valuemax={points.length - 1}
      aria-valuenow={cursor}
      tabIndex={0}
      onKeyDown={(e) => {
        if (e.key === "ArrowRight") onSeek(Math.min(points.length - 1, cursor + Math.ceil(points.length / 100)));
        if (e.key === "ArrowLeft") onSeek(Math.max(0, cursor - Math.ceil(points.length / 100)));
      }}
      onPointerDown={(e) => {
        e.currentTarget.setPointerCapture(e.pointerId);
        seek(e.clientX, e.currentTarget);
      }}
      onPointerMove={(e) => e.buttons && seek(e.clientX, e.currentTarget)}
    >
      <line x1="0" x2={W} y1={y(SPEED_LIMIT_KMH)} y2={y(SPEED_LIMIT_KMH)} stroke="#ef4444" strokeOpacity="0.5" strokeDasharray="4 4" vectorEffect="non-scaling-stroke" />
      <path d={`${line} L${W} ${H} L0 ${H} Z`} fill="#4f8bff" fillOpacity="0.15" />
      <path d={line} fill="none" stroke="#4f8bff" strokeWidth="1.5" vectorEffect="non-scaling-stroke" />
      <line x1={cx} x2={cx} y1="0" y2={H} stroke="#f59e0b" strokeWidth="2" vectorEffect="non-scaling-stroke" />
    </svg>
  );
}
