"use client";

import { useRouter } from "next/navigation";
import { useEffect, useRef, useState } from "react";
import type { MapRef } from "react-map-gl/maplibre";

import type { JobOverlay } from "@/components/FleetMap";
import { PRIORITIES, type LatLon } from "@/lib/jobs";
import { useConsole } from "../ConsoleContext";
import { FleetMap, useZoneOverlay } from "../maps";
import { PageHeader } from "../ui";

const fmt = (p: LatLon) => `${p.lat.toFixed(5)}, ${p.lon.toFixed(5)}`;

export default function NewJobPage() {
  const { store, theme, setViewport, jobsApi, refreshJobs } = useConsole();
  const router = useRouter();
  const mapRef = useRef<MapRef | null>(null);
  const [pickup, setPickup] = useState<LatLon | null>(null);
  const [dropoff, setDropoff] = useState<LatLon | null | undefined>(undefined); // null = skipped
  const [pickupAddress, setPickupAddress] = useState("");
  const [dropoffAddress, setDropoffAddress] = useState("");
  const [priority, setPriority] = useState(3);
  const [notes, setNotes] = useState("");
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const jobOverlay = useRef<JobOverlay>({ jobs: [], selectedJob: null, draft: null, picking: true });
  const zoneOverlay = useZoneOverlay();

  const picking = !pickup || dropoff === undefined;
  useEffect(() => {
    jobOverlay.current = { jobs: [], selectedJob: null, draft: { pickup: pickup ?? undefined, dropoff: dropoff ?? undefined }, picking };
  }, [pickup, dropoff, picking]);

  const step = !pickup ? 1 : dropoff === undefined ? 2 : 3;

  return (
    <>
      <PageHeader title="New job" subtitle="Click the map to place the pickup, then the drop-off" back={{ href: "/jobs", label: "Back to jobs" }} />
      <div className="flex grow flex-wrap">
        <section aria-label="Pick locations" className="relative min-h-[520px] min-w-0 flex-[999_1_560px] overflow-hidden">
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
            onMapClick={(at) => {
              if (!pickup) setPickup(at);
              else if (dropoff === undefined) setDropoff(at);
            }}
            zoneOverlay={zoneOverlay}
            drawing={false}
            onDrawPoint={() => {}}
            onCloseDraft={() => {}}
          />
          {picking && (
            <div className="panel pointer-events-none absolute left-1/2 top-4 z-10 -translate-x-1/2 px-4 py-2.5 text-[13px] font-semibold">
              {step === 1 ? "Click the pickup point" : "Click the drop-off, or skip it"}
            </div>
          )}
        </section>

        <aside className="flex max-w-full flex-[1_1_360px] flex-col gap-4 border-l border-line bg-surface p-5">
          <ol className="flex flex-col gap-2.5">
            <StepRow n={1} title="Pickup" done={!!pickup} active={step === 1} detail={pickup ? fmt(pickup) : "Click the map"} onReset={pickup ? () => (setPickup(null), setDropoff(undefined)) : undefined} />
            <StepRow
              n={2}
              title="Drop-off (optional)"
              done={!!dropoff}
              active={step === 2}
              detail={dropoff ? fmt(dropoff) : dropoff === null ? "None" : "Click the map"}
              onReset={dropoff !== undefined ? () => setDropoff(undefined) : undefined}
              action={step === 2 ? { label: "Skip", run: () => setDropoff(null) } : undefined}
            />
          </ol>

          <form
            className={`flex flex-col gap-3.5 ${step < 3 ? "pointer-events-none opacity-50" : ""}`}
            onSubmit={async (e) => {
              e.preventDefault();
              if (!pickup) return;
              setBusy(true);
              setError(null);
              try {
                const job = await jobsApi.create({ pickup, dropoff: dropoff ?? undefined, pickup_address: pickupAddress, dropoff_address: dropoffAddress, priority, notes });
                await refreshJobs();
                router.push(`/jobs/${job.id}`);
              } catch (err) {
                setError(err instanceof Error ? err.message : "Couldn't create the job.");
                setBusy(false);
              }
            }}
          >
            <label className="flex flex-col gap-1.5 text-[12px] font-semibold uppercase tracking-wider text-muted">
              Pickup address
              <input className="field h-11 rounded-xl text-[14px] normal-case tracking-normal text-fg" value={pickupAddress} onChange={(e) => setPickupAddress(e.target.value)} placeholder="e.g. Makola Market, gate 2" />
            </label>
            {dropoff && (
              <label className="flex flex-col gap-1.5 text-[12px] font-semibold uppercase tracking-wider text-muted">
                Drop-off address
                <input className="field h-11 rounded-xl text-[14px] normal-case tracking-normal text-fg" value={dropoffAddress} onChange={(e) => setDropoffAddress(e.target.value)} placeholder="e.g. Korle Bu, A&E entrance" />
              </label>
            )}
            <div role="group" aria-labelledby="prio">
              <span id="prio" className="mb-1.5 block text-[12px] font-semibold uppercase tracking-wider text-muted">
                Priority
              </span>
              <div className="flex gap-1.5">
                {PRIORITIES.map((p) => (
                  <button
                    type="button"
                    key={p.value}
                    aria-pressed={priority === p.value}
                    onClick={() => setPriority(p.value)}
                    className={`h-10 flex-1 rounded-[10px] border text-[13px] font-semibold ${priority === p.value ? (p.value === 1 ? "border-red-500 bg-red-500/10 text-red-600 dark:text-red-400" : "border-accent bg-accent/10 text-accent-fg") : "border-line text-muted hover:bg-hover"}`}
                  >
                    {p.label}
                  </button>
                ))}
              </div>
            </div>
            <label className="flex flex-col gap-1.5 text-[12px] font-semibold uppercase tracking-wider text-muted">
              Notes for the driver
              <textarea className="field min-h-20 rounded-xl text-[14px] normal-case tracking-normal text-fg" value={notes} onChange={(e) => setNotes(e.target.value)} placeholder="Access details, contact, what to bring…" />
            </label>
            {error && <p className="rounded-lg bg-red-500/10 px-3 py-2 text-[13px] text-red-600 dark:text-red-400">{error}</p>}
            <button type="submit" disabled={busy || step < 3} className="btn-primary h-12 rounded-xl text-[15px]">
              {busy ? "Dispatching…" : "Create & dispatch"}
            </button>
            <p className="text-[12px] text-muted">The nearest available driver by road drive time gets the offer. If they don&apos;t accept within 30 s, it goes to the next one.</p>
          </form>
        </aside>
      </div>
    </>
  );
}

function StepRow({ n, title, detail, done, active, onReset, action }: { n: number; title: string; detail: string; done: boolean; active: boolean; onReset?: () => void; action?: { label: string; run: () => void } }) {
  return (
    <li className={`flex items-center gap-3 rounded-xl border p-3 ${active ? "border-accent bg-accent/5" : "border-line"}`}>
      <span className={`grid size-7 shrink-0 place-items-center rounded-full text-[12px] font-semibold ${done ? "bg-emerald-500 text-white" : active ? "bg-accent text-white" : "bg-sunken text-muted"}`}>{done ? "✓" : n}</span>
      <span className="min-w-0 grow">
        <span className="block text-[14px] font-semibold">{title}</span>
        <span className="block truncate font-mono text-[12px] text-muted">{detail}</span>
      </span>
      {action && (
        <button type="button" className="text-[13px] font-semibold text-accent-fg" onClick={action.run}>
          {action.label}
        </button>
      )}
      {onReset && (
        <button type="button" className="text-[12px] text-muted hover:text-fg" onClick={onReset}>
          Change
        </button>
      )}
    </li>
  );
}
