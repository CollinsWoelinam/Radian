"use client";

import Link from "next/link";
import { useMemo, useState } from "react";

import { ago, clock } from "@/lib/console";
import { STATUS_META, type Job, type JobStatus } from "@/lib/jobs";
import { useConsole } from "../ConsoleContext";
import { Empty, Icon, PageHeader, SearchButton, StatusBadge, UrgentBadge, useNow } from "../ui";

const COLUMNS: { title: string; statuses: JobStatus[]; dot: string }[] = [
  { title: "Finding driver", statuses: ["PENDING"], dot: "bg-amber-500" },
  { title: "Offered", statuses: ["OFFERED"], dot: "bg-violet-500" },
  { title: "To pickup", statuses: ["ASSIGNED", "EN_ROUTE_PICKUP"], dot: "bg-blue-500" },
  { title: "At pickup · to drop-off", statuses: ["ON_SITE", "EN_ROUTE_DROPOFF"], dot: "bg-purple-500" },
  { title: "Done today", statuses: ["COMPLETED"], dot: "bg-emerald-500" },
];

export default function JobsPage() {
  const { active, recent } = useConsole();
  const [view, setView] = useState<"board" | "list">("board");
  const [urgentOnly, setUrgentOnly] = useState(false);
  const [q, setQ] = useState("");
  const now = useNow(); // offer countdowns

  const startOfDay = new Date(now);
  startOfDay.setHours(0, 0, 0, 0);
  const jobs = useMemo(() => {
    const query = q.trim().toLowerCase().replace(/^#/, "");
    return [...active, ...recent].filter(
      (j) =>
        (!urgentOnly || j.priority <= 2) &&
        (!query || `${j.number} ${j.pickup_address} ${j.dropoff_address ?? ""} ${j.vehicle?.license_plate ?? ""} ${j.vehicle?.driver_name ?? ""}`.toLowerCase().includes(query)),
    );
  }, [active, recent, urgentOnly, q]);
  const doneToday = recent.filter((j) => j.status === "COMPLETED" && j.completed_at && Date.parse(j.completed_at) >= startOfDay.getTime()).length;

  return (
    <>
      <PageHeader title="Jobs" subtitle={`${active.length} active · ${doneToday} completed today`}>
        <div role="tablist" aria-label="View" className="flex gap-0.5 rounded-[10px] bg-sunken p-[3px]">
          {(["board", "list"] as const).map((v) => (
            <button key={v} type="button" role="tab" aria-selected={view === v} onClick={() => setView(v)} className={`h-8 rounded-lg px-3.5 text-[13px] font-semibold capitalize ${view === v ? "bg-surface shadow-sm" : "text-muted"}`}>
              {v}
            </button>
          ))}
        </div>
        <SearchButton />
        <Link href="/jobs/new" className="btn-primary inline-flex h-10 items-center gap-2 rounded-[10px] px-4 text-[14px]">
          <Icon.Plus /> New job
        </Link>
      </PageHeader>

      <div className="flex flex-wrap items-center gap-2 px-5 pt-3.5">
        <button type="button" aria-pressed={urgentOnly} onClick={() => setUrgentOnly((u) => !u)} className={`h-8 rounded-full border px-3 text-[12px] font-semibold ${urgentOnly ? "border-red-500 bg-red-500/10 text-red-600 dark:text-red-400" : "border-line hover:bg-hover"}`}>
          Urgent only
        </button>
        <label className="flex h-8 min-w-0 flex-[0_1_280px] items-center gap-2 rounded-full border border-line px-3">
          <Icon.Search size={14} />
          <span className="sr-only">Filter jobs</span>
          <input value={q} onChange={(e) => setQ(e.target.value)} placeholder="Filter by number, place, plate or driver" className="min-w-0 grow bg-transparent text-[12px] outline-none placeholder:text-muted" />
        </label>
      </div>

      {view === "board" ? (
        <div className="grow overflow-x-auto px-5 pb-5 pt-3.5">
          <div className="grid min-w-[1180px] grid-cols-5 gap-3.5">
            {COLUMNS.map((col) => {
              const list = jobs.filter((j) => col.statuses.includes(j.status) && (j.status !== "COMPLETED" || (j.completed_at && Date.parse(j.completed_at) >= startOfDay.getTime())));
              return (
                <section key={col.title} aria-label={col.title} className="flex flex-col gap-2.5 self-start rounded-2xl bg-sunken p-3">
                  <h2 className="flex items-center gap-2 px-1 pt-1 text-[13px] font-semibold">
                    <span className={`size-2 rounded-full ${col.dot}`} />
                    {col.title}
                    <span className="ml-auto font-mono text-muted">{list.length}</span>
                  </h2>
                  {list.length === 0 && <p className="px-1 pb-2 text-[12px] text-muted">None</p>}
                  {list.map((j) => (
                    <JobCard key={j.id} job={j} now={now} />
                  ))}
                </section>
              );
            })}
          </div>
        </div>
      ) : (
        <div className="grow overflow-x-auto px-5 pb-5 pt-3.5">
          {jobs.length === 0 ? (
            <Empty>No jobs match.</Empty>
          ) : (
            <table className="w-full min-w-[820px] border-separate border-spacing-0 text-left text-[13px]">
              <thead className="text-[11px] uppercase tracking-wider text-muted">
                <tr>
                  {["Job", "Status", "Pickup", "Drop-off", "Driver", "Created"].map((h) => (
                    <th key={h} className="border-b border-line px-3 py-2 font-semibold">
                      {h}
                    </th>
                  ))}
                </tr>
              </thead>
              <tbody>
                {jobs.map((j) => (
                  <tr key={j.id} className="hover:bg-hover">
                    <td className="border-b border-line px-3 py-2.5">
                      <Link href={`/jobs/${j.id}`} className="font-mono font-semibold text-accent-fg">
                        #{j.number}
                      </Link>
                      {j.priority <= 2 && <span className="ml-2"><UrgentBadge /></span>}
                    </td>
                    <td className="border-b border-line px-3 py-2.5"><StatusBadge status={j.status} /></td>
                    <td className="max-w-[220px] truncate border-b border-line px-3 py-2.5">{j.pickup_address || "—"}</td>
                    <td className="max-w-[220px] truncate border-b border-line px-3 py-2.5 text-muted">{j.dropoff_address || "—"}</td>
                    <td className="border-b border-line px-3 py-2.5">{j.vehicle ? <><span className="font-mono">{j.vehicle.license_plate}</span> <span className="text-muted">· {j.vehicle.driver_name}</span></> : <span className="text-muted">—</span>}</td>
                    <td className="border-b border-line px-3 py-2.5 font-mono text-muted">{clock(j.created_at)}</td>
                  </tr>
                ))}
              </tbody>
            </table>
          )}
        </div>
      )}
    </>
  );
}

function JobCard({ job: j, now }: { job: Job; now: number }) {
  const left = j.offer_expires_at ? Math.max(0, Math.round((Date.parse(j.offer_expires_at) - now) / 1000)) : null;
  return (
    <Link href={`/jobs/${j.id}`} className={`flex flex-col gap-1.5 rounded-xl border bg-surface p-3 hover:border-accent ${j.status === "OFFERED" ? "border-violet-400/60" : "border-line"} ${j.status === "COMPLETED" ? "opacity-85" : ""}`}>
      <div className="flex items-center justify-between gap-2">
        <span className="font-mono text-[13px] font-semibold">#{j.number}</span>
        {j.priority <= 2 ? <UrgentBadge /> : <span className="text-[11px] text-muted">{STATUS_META[j.status].label}</span>}
      </div>
      <div className="text-[14px] font-semibold leading-snug">{j.pickup_address || "Pickup"}</div>
      {j.dropoff_address && <div className="truncate text-[12px] text-muted">→ {j.dropoff_address}</div>}
      <div className="flex items-center gap-2 text-[12px]">
        {j.vehicle ? (
          <span className="truncate">
            <span className="font-mono">{j.vehicle.license_plate}</span> <span className="text-muted">· {j.vehicle.driver_name}</span>
          </span>
        ) : (
          <span className="text-amber-600 dark:text-amber-400">Waiting {ago(j.created_at).replace(" ago", "")}</span>
        )}
        <span className="ml-auto shrink-0 font-mono">
          {j.status === "OFFERED" && left != null ? <span className="text-violet-600 dark:text-violet-300">0:{String(left).padStart(2, "0")}</span> : j.status === "COMPLETED" && j.completed_at ? <span className="text-muted">{clock(j.completed_at)}</span> : j.eta_seconds != null ? <span className="text-accent-fg">{Math.max(1, Math.round(j.eta_seconds / 60))} min</span> : null}
        </span>
      </div>
      {j.status === "OFFERED" && left != null && (
        <span className="h-1 overflow-hidden rounded bg-violet-500/15">
          <span className="block h-full bg-violet-500" style={{ width: `${(left / 30) * 100}%` }} />
        </span>
      )}
    </Link>
  );
}
