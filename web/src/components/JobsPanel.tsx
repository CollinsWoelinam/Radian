"use client";

import { useEffect, useState } from "react";
import {
  PRIORITIES,
  STATUS_META,
  priorityLabel,
  type Candidate,
  type Job,
  type JobDetail,
  type JobEvent,
  type LatLon,
  type NewJob,
} from "@/lib/jobs";

export type PanelMode = "list" | "create" | "detail";

type Props = {
  mode: PanelMode;
  active: Job[];
  recent: Job[];
  selected: JobDetail | null;
  draft: { pickup?: LatLon; dropoff?: LatLon | null } | null;
  error: string | null;
  onNewJob: () => void;
  onCancelDraft: () => void;
  onSkipDropoff: () => void;
  onCreate: (job: Omit<NewJob, "pickup" | "dropoff">) => Promise<void>;
  onSelect: (id: string | null) => void;
  onCancelJob: (id: string, reason: string) => Promise<void>;
  loadCandidates: (id: string) => Promise<Candidate[]>;
  onOffer: (jobId: string, vehicleId: string) => Promise<void>;
  onFocus: (at: LatLon) => void;
};

const TONE_CLASS: Record<string, string> = {
  wait: "bg-amber-500/15 text-amber-600 dark:text-amber-400 ring-amber-500/30",
  offer: "bg-violet-500/15 text-violet-600 ring-violet-500/30",
  active: "bg-emerald-500/15 text-emerald-600 ring-emerald-500/30",
  done: "bg-slate-500/15 text-muted ring-slate-500/30",
  off: "bg-slate-500/15 text-muted ring-slate-500/30",
};

export function StatusBadge({ status }: { status: Job["status"] }) {
  const meta = STATUS_META[status];
  return (
    <span className={`inline-flex items-center rounded-full px-2 py-0.5 text-[11px] font-medium ring-1 ${TONE_CLASS[meta.tone]}`}>
      {meta.label}
    </span>
  );
}

export default function JobsPanel(p: Props) {
  const [tab, setTab] = useState<"active" | "recent">("active");

  return (
    <div className="flex max-h-full min-h-0 flex-col">
      {p.mode === "list" && (
        <>
          <header className="flex items-center justify-between gap-2 border-b border-line px-4 py-3">
            <div className="flex gap-1 rounded-lg bg-input p-0.5" role="tablist">
              {(["active", "recent"] as const).map((t) => (
                <button
                  key={t}
                  role="tab"
                  aria-selected={tab === t}
                  onClick={() => setTab(t)}
                  className={`rounded-md px-2.5 py-1 text-[12px] font-medium ${tab === t ? "bg-panel shadow-sm" : "text-muted"}`}
                >
                  {t === "active" ? `Active (${p.active.length})` : "Recent"}
                </button>
              ))}
            </div>
            <button onClick={p.onNewJob} className="btn-primary">
              + New job
            </button>
          </header>
          <JobList jobs={tab === "active" ? p.active : p.recent} onSelect={p.onSelect} empty={tab === "active" ? "No open jobs. Create one to dispatch the nearest driver." : "Nothing finished in the last 24 hours."} />
        </>
      )}

      {p.mode === "create" && <CreateJob {...p} />}

      {/* Keyed so the candidate list and cancel prompt reset when the job or its stage changes. */}
      {p.mode === "detail" && p.selected && <JobDetailView key={`${p.selected.id}:${p.selected.status}`} job={p.selected} {...p} />}
      {p.error && <p className="mx-4 mb-3 rounded-lg bg-red-500/10 px-3 py-2 text-[12px] text-red-600 dark:text-red-400">{p.error}</p>}
    </div>
  );
}

function JobList({ jobs, onSelect, empty }: { jobs: Job[]; onSelect: (id: string) => void; empty: string }) {
  if (jobs.length === 0) return <p className="px-4 py-6 text-[13px] text-muted">{empty}</p>;
  return (
    <ul className="min-h-0 overflow-y-auto py-1">
      {jobs.map((j) => (
        <li key={j.id}>
          <button onClick={() => onSelect(j.id)} className="w-full px-4 py-2.5 text-left hover:bg-hover">
            <div className="flex items-center justify-between gap-2">
              <span className="font-mono text-[13px] font-semibold">#{j.number}</span>
              <StatusBadge status={j.status} />
            </div>
            <p className="mt-0.5 truncate text-[13px]">{j.pickup_address || coords(j.pickup)}</p>
            <p className="mt-0.5 truncate text-[11px] text-muted">
              {j.priority <= 2 && <span className="mr-1 font-semibold text-red-500">URGENT ·</span>}
              {j.vehicle ? `${j.vehicle.license_plate} · ${j.vehicle.driver_name}` : `Waiting ${since(j.created_at)}`}
              {j.eta_seconds != null && j.status !== "COMPLETED" && ` · ETA ${mins(j.eta_seconds)}`}
            </p>
          </button>
        </li>
      ))}
    </ul>
  );
}

function CreateJob(p: Props) {
  const [pickupAddress, setPickupAddress] = useState("");
  const [dropoffAddress, setDropoffAddress] = useState("");
  const [priority, setPriority] = useState(3);
  const [notes, setNotes] = useState("");
  const [busy, setBusy] = useState(false);
  const d = p.draft;
  const step = !d?.pickup ? "pickup" : d.dropoff === undefined ? "dropoff" : "details";

  return (
    <div className="flex min-h-0 flex-col">
      <header className="flex items-center justify-between border-b border-line px-4 py-3">
        <h2 className="text-[14px] font-semibold">New job</h2>
        <button onClick={p.onCancelDraft} className="text-[12px] text-muted hover:text-fg">
          Cancel
        </button>
      </header>
      <div className="space-y-3 overflow-y-auto px-4 py-3">
        <Step n={1} done={!!d?.pickup} active={step === "pickup"} title="Pickup" hint="Click the map where the driver should go.">
          {d?.pickup && <p className="font-mono text-[11px] text-muted">{coords(d.pickup)}</p>}
        </Step>
        <Step
          n={2}
          done={!!d?.dropoff}
          active={step === "dropoff"}
          title="Drop-off (optional)"
          hint="Click the destination, or skip if there isn't one."
        >
          {step === "dropoff" && (
            <button onClick={p.onSkipDropoff} className="mt-1 text-[12px] font-medium text-accent-fg">
              Skip drop-off
            </button>
          )}
          {d?.dropoff && <p className="font-mono text-[11px] text-muted">{coords(d.dropoff)}</p>}
        </Step>

        {step === "details" && (
          <form
            className="space-y-3"
            onSubmit={async (e) => {
              e.preventDefault();
              setBusy(true);
              try {
                await p.onCreate({ pickup_address: pickupAddress, dropoff_address: dropoffAddress, priority, notes });
              } finally {
                setBusy(false);
              }
            }}
          >
            <Field label="Pickup address">
              <input className="field" value={pickupAddress} onChange={(e) => setPickupAddress(e.target.value)} placeholder="e.g. Makola Market, gate 2" autoFocus />
            </Field>
            {d?.dropoff && (
              <Field label="Drop-off address">
                <input className="field" value={dropoffAddress} onChange={(e) => setDropoffAddress(e.target.value)} placeholder="e.g. Korle Bu, A&E entrance" />
              </Field>
            )}
            <div role="group" aria-labelledby="priority-label">
              <span id="priority-label" className="mb-1 block text-[11px] font-semibold uppercase tracking-wider text-muted">
                Priority
              </span>
              <div className="flex gap-1.5">
                {PRIORITIES.map((pr) => (
                  <button
                    type="button"
                    key={pr.value}
                    onClick={() => setPriority(pr.value)}
                    aria-pressed={priority === pr.value}
                    className={`flex-1 rounded-lg border px-2 py-1.5 text-[12px] font-medium ${priority === pr.value ? (pr.value === 1 ? "border-red-500 bg-red-500/10 text-red-600" : "border-accent bg-accent/10 text-accent-fg") : "border-line text-muted hover:bg-hover"}`}
                  >
                    {pr.label}
                  </button>
                ))}
              </div>
            </div>
            <Field label="Notes for the driver">
              <textarea className="field min-h-16" value={notes} onChange={(e) => setNotes(e.target.value)} placeholder="Access details, contact, what to bring…" />
            </Field>
            <button type="submit" disabled={busy} className="btn-primary w-full py-2.5">
              {busy ? "Dispatching…" : "Create & dispatch"}
            </button>
            <p className="text-[11px] text-muted">The nearest available driver by drive time gets the offer. If they don&apos;t accept within 30 s, it goes to the next one.</p>
          </form>
        )}
      </div>
    </div>
  );
}

function JobDetailView({ job, onSelect, onCancelJob, loadCandidates, onOffer, onFocus }: Props & { job: JobDetail }) {
  const [candidates, setCandidates] = useState<Candidate[] | null>(null);
  const [confirmCancel, setConfirmCancel] = useState(false);
  const [now, setNow] = useState(() => Date.now());
  useEffect(() => {
    const t = setInterval(() => setNow(Date.now()), 1000);
    return () => clearInterval(t);
  }, []);

  const open = job.status !== "COMPLETED" && job.status !== "CANCELLED";
  const offerLeft = job.offer_expires_at ? Math.max(0, Math.round((new Date(job.offer_expires_at).getTime() - now) / 1000)) : 0;
  const ahead = job.route.find((l) => l.kind === (["ON_SITE", "EN_ROUTE_DROPOFF"].includes(job.status) ? "to_dropoff" : "to_pickup"));

  return (
    <div className="flex min-h-0 flex-col">
      <header className="flex items-center gap-2 border-b border-line px-4 py-3">
        <button onClick={() => onSelect(null)} className="icon-btn" aria-label="Back to jobs">
          ←
        </button>
        <h2 className="font-mono text-[15px] font-semibold">#{job.number}</h2>
        <StatusBadge status={job.status} />
        <span className={`ml-auto text-[11px] font-semibold ${job.priority <= 2 ? "text-red-500" : "text-muted"}`}>{priorityLabel(job.priority)}</span>
      </header>

      <div className="space-y-4 overflow-y-auto px-4 py-3 text-[13px]">
        <section className="space-y-2">
          <Place dot="bg-emerald-500" label="Pickup" text={job.pickup_address || coords(job.pickup)} onClick={() => onFocus(job.pickup)} />
          {job.dropoff && <Place dot="bg-violet-500" label="Drop-off" text={job.dropoff_address || coords(job.dropoff)} onClick={() => onFocus(job.dropoff!)} />}
          {job.notes && <p className="rounded-lg bg-input px-3 py-2 text-[12px]">{job.notes}</p>}
        </section>

        {job.vehicle ? (
          <section className="rounded-xl border border-line p-3">
            <div className="flex items-center justify-between">
              <div>
                <p className="font-mono font-semibold">{job.vehicle.license_plate}</p>
                <p className="text-[12px] text-muted">{job.vehicle.driver_name}</p>
              </div>
              {job.vehicle.position && (
                <button onClick={() => onFocus(job.vehicle!.position!)} className="text-[12px] font-medium text-accent-fg">
                  Show
                </button>
              )}
            </div>
            {job.status === "OFFERED" && (
              <p className="mt-2 text-[12px] text-violet-600">
                Waiting for the driver to accept · {offerLeft}s left
              </p>
            )}
            {ahead && open && (
              <p className="mt-2 text-[12px]">
                <span className="font-semibold">{mins(ahead.duration_s)}</span> to {ahead.kind === "to_pickup" ? "pickup" : "drop-off"} ·{" "}
                {(ahead.distance_m / 1000).toFixed(1)} km by road
              </p>
            )}
          </section>
        ) : (
          open && <p className="rounded-xl border border-dashed border-line p-3 text-[12px] text-muted">No driver yet. Retrying every 15 s as drivers become free.</p>
        )}

        {open && (
          <section className="flex gap-2">
            {["PENDING", "OFFERED"].includes(job.status) && (
              <button className="btn-secondary flex-1" onClick={async () => setCandidates(await loadCandidates(job.id))}>
                Choose driver
              </button>
            )}
            {confirmCancel ? (
              <button
                className="btn-danger flex-1"
                onClick={async () => {
                  await onCancelJob(job.id, "Cancelled from dashboard");
                  setConfirmCancel(false);
                }}
              >
                Confirm cancel
              </button>
            ) : (
              <button className="btn-secondary flex-1" onClick={() => setConfirmCancel(true)}>
                Cancel job
              </button>
            )}
          </section>
        )}

        {candidates && (
          <section>
            <h3 className="mb-1 text-[11px] font-semibold uppercase tracking-wider text-muted">Nearest drivers by road</h3>
            {candidates.length === 0 ? (
              <p className="text-[12px] text-muted">No available drivers within 30 km.</p>
            ) : (
              <ul className="divide-y divide-line rounded-xl border border-line">
                {candidates.map((c) => (
                  <li key={c.vehicle_id} className="flex items-center gap-2 px-3 py-2">
                    <div className="min-w-0 flex-1">
                      <p className="font-mono text-[12px] font-semibold">{c.license_plate}</p>
                      <p className="truncate text-[11px] text-muted">
                        {c.driver_name}
                        {c.declined && " · declined earlier"}
                      </p>
                    </div>
                    <span className="text-[12px] tabular-nums">
                      {mins(c.eta_s)}
                      <span className="text-muted"> · {(c.route_m / 1000).toFixed(1)} km</span>
                    </span>
                    <button className="btn-primary px-2 py-1 text-[11px]" onClick={() => onOffer(job.id, c.vehicle_id)}>
                      Offer
                    </button>
                  </li>
                ))}
              </ul>
            )}
          </section>
        )}

        <section>
          <h3 className="mb-2 text-[11px] font-semibold uppercase tracking-wider text-muted">Timeline</h3>
          <ol className="space-y-2 border-l border-line pl-3">
            {job.events.map((e, i) => (
              <li key={i} className="relative text-[12px]">
                <span className="absolute -left-[17px] top-1.5 size-2 rounded-full bg-line ring-2 ring-panel" />
                <span className="text-muted tabular-nums">{clock(e.at)}</span> {describe(e)}
              </li>
            ))}
          </ol>
        </section>
      </div>
    </div>
  );
}

function Step({ n, done, active, title, hint, children }: { n: number; done: boolean; active: boolean; title: string; hint: string; children?: React.ReactNode }) {
  return (
    <div className={`flex gap-3 rounded-xl border p-3 ${active ? "border-accent bg-accent/5" : "border-line"}`}>
      <span className={`grid size-6 shrink-0 place-items-center rounded-full text-[12px] font-semibold ${done ? "bg-emerald-500 text-white" : active ? "bg-accent text-white" : "bg-input text-muted"}`}>
        {done ? "✓" : n}
      </span>
      <div>
        <p className="text-[13px] font-medium">{title}</p>
        {active && <p className="text-[12px] text-muted">{hint}</p>}
        {children}
      </div>
    </div>
  );
}

/** Labels a single input; don't wrap buttons in it (a <label> names its first labelable child). */
function Field({ label, children }: { label: string; children: React.ReactNode }) {
  return (
    <label className="block">
      <span className="mb-1 block text-[11px] font-semibold uppercase tracking-wider text-muted">{label}</span>
      {children}
    </label>
  );
}

function Place({ dot, label, text, onClick }: { dot: string; label: string; text: string; onClick: () => void }) {
  return (
    <button onClick={onClick} className="flex w-full items-start gap-2 text-left">
      <span className={`mt-1.5 size-2.5 shrink-0 rounded-full ${dot}`} />
      <span>
        <span className="block text-[11px] text-muted">{label}</span>
        <span className="block">{text}</span>
      </span>
    </button>
  );
}

function describe(e: JobEvent): string {
  const plate = e.license_plate ?? "driver";
  switch (e.kind) {
    case "created":
      return "Job created";
    case "offered": {
      const eta = typeof e.detail.eta_s === "number" ? ` (${mins(e.detail.eta_s)} away)` : "";
      return `Offered to ${plate}${eta}${e.detail.manual ? " by dispatcher" : ""}`;
    }
    case "accepted":
      return `${plate} accepted`;
    case "declined":
      return `${plate} declined`;
    case "offer_expired":
      return `${plate} didn't respond in time`;
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

const coords = (p: LatLon) => `${p.lat.toFixed(5)}, ${p.lon.toFixed(5)}`;
const mins = (s: number) => (s < 60 ? "<1 min" : `${Math.round(s / 60)} min`);
const clock = (iso: string) => new Date(iso).toLocaleTimeString([], { hour: "2-digit", minute: "2-digit" });
function since(iso: string) {
  const s = Math.round((Date.now() - new Date(iso).getTime()) / 1000);
  return s < 60 ? `${s}s` : `${Math.round(s / 60)} min`;
}
