"use client";

import Link from "next/link";
import { useParams } from "next/navigation";
import { useCallback, useEffect, useRef, useState } from "react";
import type { MapRef } from "react-map-gl/maplibre";

import type { JobOverlay } from "@/components/FleetMap";
import { ApiError } from "@/lib/auth";
import { clock, distance } from "@/lib/console";
import { STATUS_META, type Candidate, type JobDetail, type JobEvent } from "@/lib/jobs";
import { useConsole } from "../ConsoleContext";
import { FleetMap, useZoneOverlay } from "../maps";
import { Empty, PageHeader, StatusBadge, UrgentBadge, useNow } from "../ui";

const STEPS = ["OFFERED", "ASSIGNED", "ON_SITE", "EN_ROUTE_DROPOFF", "COMPLETED"] as const;
const stepIndex = (s: string) => ({ PENDING: 0, OFFERED: 1, ASSIGNED: 2, EN_ROUTE_PICKUP: 2, ON_SITE: 3, EN_ROUTE_DROPOFF: 4, COMPLETED: 5, CANCELLED: 0 })[s] ?? 0;
const mins = (s: number) => (s < 60 ? "<1 min" : `${Math.round(s / 60)} min`);

export default function DispatchPage() {
  const { id } = useParams<{ id: string }>();
  const { store, theme, setViewport, jobsApi, jobsVersion, refreshJobs } = useConsole();
  const mapRef = useRef<MapRef | null>(null);
  const [job, setJob] = useState<JobDetail | null>(null);
  const [missing, setMissing] = useState(false);
  const [cands, setCands] = useState<Candidate[]>([]);
  const [error, setError] = useState<string | null>(null);
  const [cancelling, setCancelling] = useState(false);
  const [reason, setReason] = useState("");
  const now = useNow();
  const jobOverlay = useRef<JobOverlay>({ jobs: [], selectedJob: null, draft: null, picking: false });
  const zoneOverlay = useZoneOverlay();
  const fitted = useRef(false);

  const load = useCallback(async () => {
    try {
      setJob(await jobsApi.get(id));
    } catch (e) {
      if (e instanceof ApiError && e.status === 404) setMissing(true);
    }
  }, [jobsApi, id]);

  useEffect(() => {
    const first = setTimeout(load, 0);
    const t = setInterval(load, 5000); // live route and ETA
    return () => {
      clearTimeout(first);
      clearInterval(t);
    };
  }, [load, jobsVersion]);

  const open = job && (job.status === "PENDING" || job.status === "OFFERED");
  useEffect(() => {
    if (!open) return;
    let live = true;
    const get = () => jobsApi.candidates(id).then((c) => live && setCands(c)).catch(() => {});
    get();
    const t = setInterval(get, 5000);
    return () => {
      live = false;
      clearInterval(t);
    };
  }, [open, jobsApi, id, jobsVersion]);

  useEffect(() => {
    jobOverlay.current = { jobs: [], selectedJob: job, draft: null, picking: false };
    // Frame the route once, when it first arrives.
    if (job && !fitted.current && mapRef.current) {
      const pts: [number, number][] = [[job.pickup.lon, job.pickup.lat]];
      if (job.dropoff) pts.push([job.dropoff.lon, job.dropoff.lat]);
      if (job.vehicle?.position) pts.push([job.vehicle.position.lon, job.vehicle.position.lat]);
      job.route.forEach((l) => pts.push(...l.coordinates));
      const lons = pts.map((p) => p[0]);
      const lats = pts.map((p) => p[1]);
      mapRef.current.fitBounds(
        [
          [Math.min(...lons), Math.min(...lats)],
          [Math.max(...lons), Math.max(...lats)],
        ],
        { padding: 70, maxZoom: 15, duration: 600 },
      );
      fitted.current = true;
    }
  }, [job]);

  const run = async (f: () => Promise<unknown>) => {
    setError(null);
    try {
      await f();
      await Promise.all([load(), refreshJobs()]);
    } catch (e) {
      setError(e instanceof Error ? e.message : "Something went wrong.");
    }
  };

  if (missing) {
    return (
      <>
        <PageHeader title="Job not found" back={{ href: "/jobs", label: "Back to jobs" }} />
        <div className="p-6">
          <Empty>This job doesn&apos;t exist, or was removed.</Empty>
        </div>
      </>
    );
  }

  const left = job?.offer_expires_at ? Math.max(0, Math.round((Date.parse(job.offer_expires_at) - now) / 1000)) : null;
  const finished = job && (job.status === "COMPLETED" || job.status === "CANCELLED");
  const toPickup = job?.route.find((l) => l.kind === "to_pickup");
  const toDropoff = job?.route.find((l) => l.kind === "to_dropoff");

  return (
    <>
      <PageHeader
        title={
          <span className="flex items-center gap-2.5">
            <Link href="/jobs" className="text-[13px] font-normal text-muted hover:text-fg">
              Jobs
            </Link>
            <span className="text-muted">/</span>
            <span className="font-mono">#{job?.number ?? "…"}</span>
            {job && job.priority <= 2 && <UrgentBadge />}
            {job && <StatusBadge status={job.status} />}
          </span>
        }
      >
        {job && !finished && !cancelling && (
          <button type="button" onClick={() => setCancelling(true)} className="h-9 rounded-[10px] border border-red-500/40 px-3.5 text-[13px] font-semibold text-red-600 hover:bg-red-500/10 dark:text-red-400">
            Cancel job
          </button>
        )}
        {cancelling && job && (
          <form
            className="flex flex-wrap items-center gap-2"
            onSubmit={(e) => {
              e.preventDefault();
              run(() => jobsApi.cancel(job.id, reason.trim() || "Cancelled by dispatcher")).then(() => setCancelling(false));
            }}
          >
            <label className="sr-only" htmlFor="reason">
              Reason
            </label>
            <input id="reason" autoFocus value={reason} onChange={(e) => setReason(e.target.value)} placeholder="Reason (optional)" className="field h-9 w-56 rounded-[10px]" />
            <button className="h-9 rounded-[10px] bg-red-600 px-3.5 text-[13px] font-semibold text-white">Cancel job</button>
            <button type="button" className="h-9 rounded-[10px] px-3 text-[13px] text-muted hover:bg-hover" onClick={() => setCancelling(false)}>
              Keep
            </button>
          </form>
        )}
      </PageHeader>

      <div className="flex grow flex-wrap">
        <section aria-label="Job details" className="flex max-w-full flex-[1_1_300px] flex-col gap-4 border-r border-line p-5">
          {job ? (
            <>
              <ol className="flex gap-1" aria-label={`Progress: ${STATUS_META[job.status].label}`}>
                {STEPS.map((s, i) => (
                  <li key={s} className={`h-1 flex-1 rounded ${job.status === "CANCELLED" ? "bg-slate-500/30" : i < stepIndex(job.status) ? "bg-accent" : "bg-sunken"}`} />
                ))}
              </ol>
              <Stop color="pickup" label="Pickup" place={job.pickup_address || "Pickup"} at={job.pickup} />
              {job.dropoff && <Stop color="dropoff" label="Drop-off" place={job.dropoff_address || "Drop-off"} at={job.dropoff} />}
              {job.notes && <p className="rounded-xl border border-line bg-sunken p-3 text-[13px] leading-relaxed">{job.notes}</p>}
              <div>
                <h2 className="mb-2.5 text-[12px] font-semibold uppercase tracking-wider text-muted">Timeline</h2>
                <ol className="flex flex-col gap-2.5 text-[13px]">
                  {job.events.map((e, i) => (
                    <li key={i} className="grid grid-cols-[46px_minmax(0,1fr)] gap-2">
                      <span className="font-mono text-muted">{clock(e.at)}</span>
                      <span className={e.kind === "offer_expired" || e.kind === "declined" ? "text-amber-600 dark:text-amber-400" : e.kind === "cancelled" ? "text-red-600 dark:text-red-400" : ""}>{describeEvent(e)}</span>
                    </li>
                  ))}
                </ol>
              </div>
            </>
          ) : (
            <p className="text-[13px] text-muted">Loading…</p>
          )}
        </section>

        <section aria-label="Route" className="relative min-h-[520px] min-w-0 flex-[999_1_420px] overflow-hidden">
          <FleetMap
            store={store}
            theme={theme}
            hidden={new Set()}
            selectedId={null}
            follow={false}
            onSelect={() => {}}
            onViewportChange={setViewport}
            onUserPan={() => {}}
            onFrame={() => {}}
            mapRef={mapRef}
            jobOverlay={jobOverlay}
            onSelectJob={() => {}}
            onMapClick={() => {}}
            zoneOverlay={zoneOverlay}
            drawing={false}
            onDrawPoint={() => {}}
            onCloseDraft={() => {}}
          />
          {(toPickup || toDropoff) && (
            <div className="panel absolute bottom-4 left-4 z-10 flex flex-wrap gap-6 px-4 py-3">
              {toPickup && (
                <div>
                  <div className="text-[11px] text-muted">To pickup</div>
                  <div className="font-mono text-[17px] font-semibold text-blue-500">
                    {mins(toPickup.duration_s)} · {distance(toPickup.distance_m)}
                  </div>
                </div>
              )}
              {toDropoff && (
                <div>
                  <div className="text-[11px] text-muted">{toPickup ? "Then to drop-off" : "To drop-off"}</div>
                  <div className="font-mono text-[17px] font-semibold text-purple-500">
                    {mins(toDropoff.duration_s)} · {distance(toDropoff.distance_m)}
                  </div>
                </div>
              )}
            </div>
          )}
        </section>

        <aside aria-label="Driver" className="flex max-w-full flex-[1_1_340px] flex-col gap-3.5 border-l border-line bg-sunken p-5">
          {job?.status === "OFFERED" && job.vehicle && left != null && (
            <div className="flex items-center gap-3.5 rounded-[14px] border border-violet-500/40 bg-violet-500/[0.08] p-3.5">
              <svg width="52" height="52" viewBox="0 0 52 52" role="img" aria-label={`${left} seconds left`}>
                <circle cx="26" cy="26" r="22" fill="none" stroke="currentColor" strokeOpacity="0.15" strokeWidth="5" />
                <circle cx="26" cy="26" r="22" fill="none" stroke="#8B5CF6" strokeWidth="5" strokeLinecap="round" strokeDasharray="138.2" strokeDashoffset={138.2 * (1 - left / 30)} transform="rotate(-90 26 26)" />
                <text x="26" y="31" textAnchor="middle" className="fill-fg font-mono text-[14px] font-semibold">
                  {left}
                </text>
              </svg>
              <div>
                <div className="text-[13px] font-semibold">
                  Waiting for <span className="font-mono">{job.vehicle.license_plate}</span>
                </div>
                <div className="text-[12px] text-muted">{job.vehicle.driver_name} · the offer lapses in {left} s</div>
              </div>
            </div>
          )}

          {job && job.vehicle && job.status !== "OFFERED" && !finished && (
            <div className="rounded-[14px] border border-line bg-surface p-3.5">
              <div className="flex items-baseline justify-between">
                <span className="font-mono text-[15px] font-semibold">{job.vehicle.license_plate}</span>
                <Link href={`/vehicles/${job.vehicle.id}`} className="text-[12px] font-semibold text-accent-fg">
                  Vehicle
                </Link>
              </div>
              <div className="text-[13px] text-muted">{job.vehicle.driver_name}</div>
              {job.eta_seconds != null && <div className="mt-2 text-[13px]">Pickup ETA when accepted: {mins(job.eta_seconds)}</div>}
            </div>
          )}

          {open && (
            <>
              <div className="flex items-baseline justify-between">
                <h2 className="text-[15px] font-semibold">Nearest by drive time</h2>
                <span className="text-[12px] text-muted">road routes</span>
              </div>
              {cands.length === 0 ? (
                <Empty>No available drivers within 30 km. The job keeps retrying every 15 s.</Empty>
              ) : (
                <ol className="flex flex-col gap-2">
                  {cands.slice(0, 8).map((c) => {
                    const offered = job?.status === "OFFERED" && job.vehicle?.id === c.vehicle_id;
                    const max = Math.max(...cands.map((x) => x.eta_s), 1);
                    return (
                      <li key={c.vehicle_id} className={`grid grid-cols-[minmax(0,1fr)_auto] items-center gap-x-3 gap-y-1.5 rounded-xl border p-3 ${offered ? "border-accent bg-accent/[0.06]" : "border-line bg-surface"} ${c.declined ? "opacity-55" : ""}`}>
                        <span className="truncate">
                          <span className="font-mono text-[14px] font-semibold">{c.license_plate}</span> <span className="text-[12px] text-muted">· {c.driver_name}</span>
                        </span>
                        {offered ? (
                          <span className="text-[12px] font-semibold text-violet-600 dark:text-violet-300">Offered</span>
                        ) : c.declined ? (
                          <span className="text-[12px] text-amber-600 dark:text-amber-400">Declined</span>
                        ) : (
                          <button type="button" onClick={() => run(() => jobsApi.offer(id, c.vehicle_id))} className="btn-primary h-8 rounded-lg px-3 text-[12px]">
                            Offer
                          </button>
                        )}
                        <span className="h-1.5 overflow-hidden rounded bg-line">
                          <span className="block h-full bg-blue-500" style={{ width: `${Math.max(6, (c.eta_s / max) * 100)}%` }} />
                        </span>
                        <span className="font-mono text-[13px]" title={c.eta_source === "estimate" ? "Straight-line estimate" : "Road drive time"}>
                          {mins(c.eta_s)}
                          {c.eta_source === "estimate" ? "*" : ""}
                        </span>
                      </li>
                    );
                  })}
                </ol>
              )}
              <p className="text-[12px] leading-relaxed text-muted">If nobody accepts within 30 s, the next driver is offered automatically.</p>
            </>
          )}
          {finished && job && (
            <p className="rounded-xl border border-line bg-surface p-3.5 text-[13px]">
              {job.status === "COMPLETED" ? `Completed at ${job.completed_at ? clock(job.completed_at) : "—"}` : "This job was cancelled."}
            </p>
          )}
          {error && <p className="rounded-lg bg-red-500/10 px-3 py-2 text-[13px] text-red-600 dark:text-red-400">{error}</p>}
        </aside>
      </div>
    </>
  );
}

function Stop({ color, label, place, at }: { color: "pickup" | "dropoff"; label: string; place: string; at: { lat: number; lon: number } }) {
  return (
    <div className="flex gap-3">
      {color === "pickup" ? (
        <span className="mt-1 size-3 shrink-0 rounded-full bg-emerald-500 ring-4 ring-emerald-500/20" />
      ) : (
        <span className="mt-1 size-3 shrink-0 rounded-full border-[3px] border-purple-500" />
      )}
      <div>
        <div className="text-[11px] uppercase tracking-wider text-muted">{label}</div>
        <div className="text-[15px] font-semibold">{place}</div>
        <div className="font-mono text-[12px] text-muted">
          {at.lat.toFixed(4)}, {at.lon.toFixed(4)}
        </div>
      </div>
    </div>
  );
}

function describeEvent(e: JobEvent): string {
  const plate = e.license_plate ?? "driver";
  switch (e.kind) {
    case "created":
      return "Job created";
    case "offered": {
      const eta = typeof e.detail.eta_s === "number" ? ` · ${mins(e.detail.eta_s)} away` : "";
      return `Offered to ${plate}${eta}${e.detail.manual ? " by dispatcher" : ""}`;
    }
    case "accepted":
      return `${plate} accepted`;
    case "declined":
      return `${plate} declined`;
    case "offer_expired":
      return `${plate} didn't answer in 30 s`;
    case "no_vehicle":
      return "No driver available yet";
    case "cancelled":
      return `Cancelled${e.detail.reason ? `: ${e.detail.reason}` : ""}`;
    case "status": {
      const to = e.detail.to as keyof typeof STATUS_META;
      return `${plate}: ${STATUS_META[to]?.label ?? to}`;
    }
    default:
      return e.kind;
  }
}
