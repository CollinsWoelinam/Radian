"use client";

import Link from "next/link";
import { useRouter, useSearchParams } from "next/navigation";
import { useCallback, useEffect, useRef, useState } from "react";
import type { MapRef } from "react-map-gl/maplibre";

import type { JobOverlay } from "@/components/FleetMap";
import { ago, duration, type AttentionItem, type VehicleDetail } from "@/lib/console";
import { STATUSES, statusInfo, type StatusKey } from "@/lib/config";
import { useConsole } from "../ConsoleContext";
import { FleetMap, useZoneOverlay } from "../maps";
import { Icon, LivePill, PageHeader, SearchButton, useNow } from "../ui";

const KINDS: Record<string, string> = { CAR: "Car", MOTORBIKE: "Motorbike", VAN: "Van", TRUCK: "Truck", AMBULANCE: "Ambulance" };

export default function LivePage() {
  const { store, theme, setViewport, active, registry, overview, attention, consoleApi } = useConsole();
  const router = useRouter();
  const params = useSearchParams();
  const mapRef = useRef<MapRef | null>(null);
  const [hidden, setHidden] = useState<Set<StatusKey>>(new Set());
  const [selectedId, setSelectedId] = useState<string | null>(null);
  const [follow, setFollow] = useState(false);
  const [detail, setDetail] = useState<VehicleDetail | null>(null);
  const [, setTick] = useState(0);
  const jobOverlay = useRef<JobOverlay>({ jobs: [], selectedJob: null, draft: null, picking: false });
  const zoneOverlay = useZoneOverlay();

  useEffect(() => {
    jobOverlay.current = { jobs: active, selectedJob: null, draft: null, picking: false };
  }, [active]);

  // React redraws the panels at 2 Hz; the map animates on its own.
  useEffect(() => {
    const id = setInterval(() => setTick((t) => t + 1), 500);
    return () => clearInterval(id);
  }, []);

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

  // ?vehicle=<id> (from an alert or the palette) selects and flies to it.
  const wanted = params.get("vehicle");
  useEffect(() => {
    if (!wanted) return;
    const t = setTimeout(() => select(wanted, true), 300);
    return () => clearTimeout(t);
  }, [wanted, select]);

  useEffect(() => {
    if (!selectedId) return;
    let live = true;
    const load = () => consoleApi.vehicle(selectedId).then((d) => live && setDetail(d)).catch(() => {});
    load();
    const t = setInterval(load, 15_000);
    return () => {
      live = false;
      clearInterval(t);
    };
  }, [selectedId, consoleApi]);

  const counts: Record<StatusKey, number> = { EN_ROUTE: 0, ON_JOB: 0, IDLE: 0, OFFLINE: 0 };
  for (const v of store.list) counts[statusInfo(v.status).key]++;
  const total = store.list.length;
  const selected = selectedId ? store.get(selectedId) : undefined;
  const info = selectedId ? registry.get(selectedId) : undefined;
  const shownDetail = detail && detail.id === selectedId ? detail : null;

  return (
    <>
      <PageHeader title="Live operations" subtitle="Greater Accra · updated live">
        <SearchButton wide />
        <LivePill />
        <Link href="/jobs/new" className="btn-primary inline-flex h-10 items-center gap-2 rounded-[10px] px-4 text-[14px]">
          <Icon.Plus /> New job
        </Link>
      </PageHeader>

      <div className="flex grow flex-wrap">
        <section aria-label="Live map" className="relative min-h-[560px] min-w-0 flex-[999_1_560px] overflow-hidden">
          <FleetMap
            store={store}
            theme={theme}
            hidden={hidden}
            selectedId={selectedId}
            follow={follow}
            onSelect={(id) => select(id)}
            onViewportChange={setViewport}
            onUserPan={() => setFollow(false)}
            onFrame={() => {}}
            mapRef={mapRef}
            jobOverlay={jobOverlay}
            onSelectJob={(id) => id && router.push(`/jobs/${id}`)}
            onMapClick={() => {}}
            zoneOverlay={zoneOverlay}
            drawing={false}
            onDrawPoint={() => {}}
            onCloseDraft={() => {}}
          />

          <div className="pointer-events-none absolute inset-x-4 top-4 z-10 grid grid-cols-2 gap-2.5 sm:grid-cols-[repeat(4,minmax(0,160px))]">
            <Kpi label="Online" value={overview ? overview.online.toLocaleString() : "—"} note={overview ? `of ${overview.vehicles.toLocaleString()} vehicles` : ""} />
            <Kpi label="Active jobs" value={overview ? String(overview.active_jobs) : "—"} note={overview ? `${overview.waiting_jobs} waiting for a driver` : ""} />
            <Kpi label="Pickup time" value={overview?.median_pickup_s != null ? duration(overview.median_pickup_s) : "—"} note="median, last hour" />
            <Kpi label="Alerts" value={overview ? String(overview.alerts_last_hour) : "—"} note="zone alerts, last hour" tone={overview && overview.alerts_last_hour > 0 ? "warn" : undefined} />
          </div>

          {selected && (
            <div className="panel absolute right-4 top-4 z-10 w-[min(280px,calc(100%-2rem))] p-3.5 sm:top-auto sm:bottom-16">
              <div className="flex items-start justify-between gap-2">
                <div>
                  <p className="font-mono text-[16px] font-semibold">{info?.license_plate ?? "Unknown"}</p>
                  <p className="text-[12px] text-muted">
                    {shownDetail?.driver_name ? `${shownDetail.driver_name} · ` : ""}
                    {KINDS[info?.kind ?? ""] ?? info?.kind ?? ""}
                  </p>
                </div>
                <span className="flex items-center gap-1.5 text-[12px]">
                  <span className="size-2 rounded-full" style={{ background: `rgb(${statusInfo(selected.status).rgb.join(",")})` }} />
                  {statusInfo(selected.status).label}
                </span>
              </div>
              <dl className="mt-3 grid grid-cols-3 gap-2 text-[11px] text-muted">
                <div>
                  <dt>Speed</dt>
                  <dd className="font-mono text-[14px] text-fg">{Math.round(selected.speedKmh)} km/h</dd>
                </div>
                <div>
                  <dt>Battery</dt>
                  <dd className="font-mono text-[14px] text-fg">{shownDetail?.position?.battery_pct != null ? `${shownDetail.position.battery_pct}%` : "—"}</dd>
                </div>
                <div>
                  <dt>Last fix</dt>
                  <dd className="font-mono text-[14px] text-fg">{ago(new Date(selected.recordedAtMs).toISOString()).replace(" ago", "")}</dd>
                </div>
              </dl>
              {shownDetail?.job && (
                <Link href={`/jobs/${shownDetail.job.id}`} className="mt-3 block rounded-lg bg-sunken px-3 py-2 text-[12px] hover:bg-hover">
                  On job <span className="font-mono">#{shownDetail.job.number}</span> · {shownDetail.job.pickup_address || "pickup"}
                </Link>
              )}
              <div className="mt-3 grid grid-cols-2 gap-2">
                <button type="button" onClick={() => setFollow((f) => !f)} aria-pressed={follow} className={`h-9 rounded-[9px] text-[12px] font-semibold ${follow ? "bg-accent text-white" : "border border-line hover:bg-hover"}`}>
                  {follow ? "Following" : "Follow"}
                </button>
                <Link href={`/vehicles/${selected.id}`} className="grid h-9 place-items-center rounded-[9px] bg-sunken text-[12px] font-semibold hover:bg-hover">
                  Trip replay
                </Link>
              </div>
              <button type="button" className="icon-btn absolute right-2 top-2 sm:hidden" aria-label="Close" onClick={() => select(null)}>
                <Icon.Close />
              </button>
            </div>
          )}

          <div className="absolute bottom-4 left-4 z-10 flex flex-wrap gap-1.5">
            {STATUSES.map((s) => {
              const off = hidden.has(s.key);
              return (
                <button
                  key={s.key}
                  type="button"
                  aria-pressed={!off}
                  title={off ? `Show ${s.label}` : `Hide ${s.label}`}
                  onClick={() =>
                    setHidden((prev) => {
                      const next = new Set(prev);
                      if (next.has(s.key)) next.delete(s.key);
                      else next.add(s.key);
                      return next;
                    })
                  }
                  className={`panel inline-flex h-8 items-center gap-1.5 !rounded-full px-3 text-[12px] ${off ? "opacity-45" : ""}`}
                >
                  <span className="size-2 rounded-full" style={{ background: `rgb(${s.rgb.join(",")})` }} />
                  {s.label} <span className="font-mono tabular-nums">{counts[s.key].toLocaleString()}</span>
                </button>
              );
            })}
          </div>
        </section>

        <aside aria-label="Needs attention" className="flex max-w-full flex-[1_1_340px] flex-col gap-3.5 border-l border-line bg-sunken p-4 sm:max-h-[calc(100dvh-69px)] sm:overflow-y-auto">
          <div className="flex items-baseline justify-between">
            <h2 className="text-[15px] font-semibold">Needs attention</h2>
            <span className="font-mono text-[12px] text-muted">{attention.length}</span>
          </div>
          {attention.length === 0 && <p className="rounded-xl border border-dashed border-line px-3 py-4 text-[13px] text-muted">All clear. Offers waiting on drivers, unassigned jobs, zone alerts and drivers who go offline mid-job show up here.</p>}
          {attention.map((a, i) => (
            <AttentionCard key={`${a.kind}-${a.job_id ?? a.vehicle_id}-${a.at}-${i}`} item={a} />
          ))}

          <div className="mt-1.5">
            <h2 className="mb-2.5 text-[15px] font-semibold">Fleet right now</h2>
            <div className="flex h-2.5 gap-0.5 overflow-hidden rounded-full" role="img" aria-label={STATUSES.map((s) => `${counts[s.key]} ${s.label}`).join(", ")}>
              {STATUSES.map((s) => (
                <span key={s.key} style={{ flex: counts[s.key], background: `rgb(${s.rgb.join(",")})` }} />
              ))}
            </div>
            <div className="mt-2 flex justify-between text-[12px] text-muted">
              <span>{total.toLocaleString()} in view</span>
              <span>{total ? Math.round(((counts.EN_ROUTE + counts.ON_JOB) / total) * 100) : 0}% moving or on a job</span>
            </div>
          </div>
        </aside>
      </div>
    </>
  );
}

function Kpi({ label, value, note, tone }: { label: string; value: string; note: string; tone?: "warn" }) {
  return (
    <div className="pointer-events-auto rounded-2xl border border-line bg-surface px-3.5 py-3 shadow-[var(--shadow)]">
      <div className="text-[11px] uppercase tracking-wider text-muted">{label}</div>
      <div className={`mt-1 font-mono text-[22px] font-semibold ${tone === "warn" ? "text-amber-500" : ""}`}>{value}</div>
      <div className="truncate text-[12px] text-muted">{note}</div>
    </div>
  );
}

function AttentionCard({ item: a }: { item: AttentionItem }) {
  const now = useNow();

  const tone = {
    offer_expiring: "border-amber-500/40 bg-amber-500/[0.07]",
    zone_alert: "border-red-500/40 bg-red-500/[0.07]",
    no_driver: "border-line",
    offline_on_job: "border-line",
  }[a.kind];
  let title: React.ReactNode, meta: React.ReactNode, body: React.ReactNode, link: { href: string; label: string };
  switch (a.kind) {
    case "offer_expiring": {
      const left = a.expires_at ? Math.max(0, Math.round((Date.parse(a.expires_at) - now) / 1000)) : 0;
      title = <>Offer waiting · <span className="font-mono">#{a.job_number}</span></>;
      meta = <span className="font-mono text-amber-600 dark:text-amber-400">0:{String(left).padStart(2, "0")}</span>;
      body = <>{a.place || "Pickup"}. <span className="font-mono">{a.license_plate}</span> hasn&apos;t answered yet.</>;
      link = { href: `/jobs/${a.job_id}`, label: "Pick another driver" };
      break;
    }
    case "no_driver":
      title = <>No driver found · <span className="font-mono">#{a.job_number}</span></>;
      meta = ago(a.at);
      body = <>{a.place || "Pickup"}. Retrying every 15 s{a.declines ? `, ${a.declines} declined` : ""}.</>;
      link = { href: `/jobs/${a.job_id}`, label: "Open job" };
      break;
    case "zone_alert":
      title = a.dwell ? `Stayed too long in ${a.zone_name}` : a.entered ? `Entered ${a.zone_name}` : `Left ${a.zone_name}`;
      meta = ago(a.at);
      body = <><span className="font-mono">{a.license_plate}</span> · {a.zone_kind === "RESTRICTED" ? "restricted zone" : a.zone_kind === "SERVICE_AREA" ? "service area" : "depot"}</>;
      link = { href: `/?vehicle=${a.vehicle_id}`, label: "Show on map" };
      break;
    default:
      title = "Driver offline on a job";
      meta = a.at && !a.at.startsWith("0001") ? ago(a.at) : "";
      body = <>{a.driver_name || "Driver"} · <span className="font-mono">{a.license_plate}</span> · job <span className="font-mono">#{a.job_number}</span>.</>;
      link = { href: `/jobs/${a.job_id}`, label: "Open job" };
  }
  return (
    <div className={`flex flex-col gap-2 rounded-[14px] border px-3.5 py-3 ${tone}`}>
      <div className="flex justify-between gap-2 text-[13px] font-semibold">
        <span>{title}</span>
        <span className="shrink-0 text-[12px] font-normal text-muted">{meta}</span>
      </div>
      <span className="text-[12px] text-muted">{body}</span>
      <Link href={link.href} className="text-[12px] font-semibold text-accent-fg">
        {link.label}
      </Link>
    </div>
  );
}
