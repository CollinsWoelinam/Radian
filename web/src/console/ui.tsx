"use client";

import Link from "next/link";
import { useEffect, useState } from "react";
import { STATUS_META, type JobStatus } from "@/lib/jobs";
import { useConsole } from "./ConsoleContext";

const base = { fill: "none", stroke: "currentColor", strokeWidth: 2, strokeLinecap: "round" as const, strokeLinejoin: "round" as const, "aria-hidden": true };

/** The current time, refreshed every `ms`: for countdowns rendered from state. */
export function useNow(ms = 1000) {
  const [now, setNow] = useState(() => Date.now());
  useEffect(() => {
    const t = setInterval(() => setNow(Date.now()), ms);
    return () => clearInterval(t);
  }, [ms]);
  return now;
}

/** Stroke icons used across the console. */
export const Icon = {
  Map: (p: { size?: number }) => (
    <svg width={p.size ?? 20} height={p.size ?? 20} viewBox="0 0 24 24" {...base}>
      <path d="M9 4 3 6v14l6-2 6 2 6-2V4l-6 2-6-2z" />
      <path d="M9 4v14M15 6v14" />
    </svg>
  ),
  Jobs: (p: { size?: number }) => (
    <svg width={p.size ?? 20} height={p.size ?? 20} viewBox="0 0 24 24" {...base}>
      <rect x="3" y="4" width="18" height="16" rx="3" />
      <path d="M8 9h8M8 13h8M8 17h5" />
    </svg>
  ),
  Zone: (p: { size?: number }) => (
    <svg width={p.size ?? 20} height={p.size ?? 20} viewBox="0 0 24 24" {...base}>
      <path d="M4 7l6-3 10 4-2 11-12 1z" />
    </svg>
  ),
  Van: (p: { size?: number }) => (
    <svg width={p.size ?? 20} height={p.size ?? 20} viewBox="0 0 24 24" {...base}>
      <path d="M3 16V8h11l4 4h3v4" />
      <circle cx="7" cy="17" r="2" />
      <circle cx="17" cy="17" r="2" />
    </svg>
  ),
  Search: (p: { size?: number }) => (
    <svg width={p.size ?? 16} height={p.size ?? 16} viewBox="0 0 24 24" {...base}>
      <circle cx="11" cy="11" r="7" />
      <path d="m20 20-3.5-3.5" />
    </svg>
  ),
  Plus: (p: { size?: number }) => (
    <svg width={p.size ?? 16} height={p.size ?? 16} viewBox="0 0 24 24" {...base} strokeWidth={2.5}>
      <path d="M12 5v14M5 12h14" />
    </svg>
  ),
  Back: (p: { size?: number }) => (
    <svg width={p.size ?? 18} height={p.size ?? 18} viewBox="0 0 24 24" {...base}>
      <path d="M15 18l-6-6 6-6" />
    </svg>
  ),
  Close: (p: { size?: number }) => (
    <svg width={p.size ?? 16} height={p.size ?? 16} viewBox="0 0 24 24" {...base}>
      <path d="M18 6 6 18M6 6l12 12" />
    </svg>
  ),
  Sun: (p: { size?: number }) => (
    <svg width={p.size ?? 18} height={p.size ?? 18} viewBox="0 0 24 24" {...base}>
      <circle cx="12" cy="12" r="4" />
      <path d="M12 2v2M12 20v2M4.9 4.9l1.4 1.4M17.7 17.7l1.4 1.4M2 12h2M20 12h2M4.9 19.1l1.4-1.4M17.7 6.3l1.4-1.4" />
    </svg>
  ),
  Moon: (p: { size?: number }) => (
    <svg width={p.size ?? 18} height={p.size ?? 18} viewBox="0 0 24 24" {...base}>
      <path d="M21 12.8A9 9 0 1 1 11.2 3a7 7 0 0 0 9.8 9.8z" />
    </svg>
  ),
  Logout: (p: { size?: number }) => (
    <svg width={p.size ?? 18} height={p.size ?? 18} viewBox="0 0 24 24" {...base}>
      <path d="M9 21H5a2 2 0 0 1-2-2V5a2 2 0 0 1 2-2h4M16 17l5-5-5-5M21 12H9" />
    </svg>
  ),
  Play: (p: { size?: number }) => (
    <svg width={p.size ?? 18} height={p.size ?? 18} viewBox="0 0 24 24" fill="currentColor" aria-hidden>
      <path d="M8 5v14l11-7z" />
    </svg>
  ),
  Pause: (p: { size?: number }) => (
    <svg width={p.size ?? 18} height={p.size ?? 18} viewBox="0 0 24 24" fill="currentColor" aria-hidden>
      <rect x="6" y="5" width="4" height="14" rx="1" />
      <rect x="14" y="5" width="4" height="14" rx="1" />
    </svg>
  ),
  Trash: (p: { size?: number }) => (
    <svg width={p.size ?? 16} height={p.size ?? 16} viewBox="0 0 24 24" {...base}>
      <path d="M3 6h18M8 6V4h8v2M19 6l-1 14H6L5 6" />
    </svg>
  ),
  Alert: (p: { size?: number }) => (
    <svg width={p.size ?? 18} height={p.size ?? 18} viewBox="0 0 24 24" {...base} strokeWidth={2.2}>
      <path d="M12 9v4M12 17h.01" />
      <path d="M10.3 3.9 1.8 18a2 2 0 0 0 1.7 3h17a2 2 0 0 0 1.7-3L13.7 3.9a2 2 0 0 0-3.4 0z" />
    </svg>
  ),
};

/** Top bar of a console page: title, optional subtitle and actions. */
export function PageHeader({ title, subtitle, children, back }: { title: React.ReactNode; subtitle?: React.ReactNode; children?: React.ReactNode; back?: { href: string; label: string } }) {
  return (
    <header className="flex flex-wrap items-center gap-3 border-b border-line px-5 py-3.5">
      {back && (
        <Link href={back.href} className="icon-btn" aria-label={back.label}>
          <Icon.Back />
        </Link>
      )}
      <div className="mr-2 min-w-0">
        <h1 className="truncate text-[18px] font-semibold tracking-tight">{title}</h1>
        {subtitle && <div className="text-[12px] text-muted">{subtitle}</div>}
      </div>
      <span className="grow" />
      {children}
    </header>
  );
}

/** The ⌘K search field that opens the command palette. */
export function SearchButton({ wide }: { wide?: boolean }) {
  const { setPaletteOpen } = useConsole();
  return (
    <button
      type="button"
      onClick={() => setPaletteOpen(true)}
      className={`flex h-10 items-center gap-2.5 rounded-[10px] border border-line bg-input px-3 text-left text-[13px] text-muted hover:bg-hover ${wide ? "min-w-0 max-w-[440px] flex-[1_1_260px]" : ""}`}
    >
      <Icon.Search />
      <span className="grow truncate">Search plates, drivers, jobs, zones…</span>
      <kbd className="rounded-md border border-line px-1.5 py-0.5 font-mono text-[11px]">⌘K</kbd>
    </button>
  );
}

export function LivePill() {
  const { conn } = useConsole();
  const live = conn === "live";
  return (
    <span className="inline-flex h-8 items-center gap-2 rounded-full border border-line px-3 text-[12px]" role="status">
      <span className="relative flex size-2">
        {live && <span className="absolute inline-flex size-full animate-ping rounded-full bg-emerald-500 opacity-60" />}
        <span className={`relative inline-flex size-2 rounded-full ${live ? "bg-emerald-500" : "bg-amber-500"}`} />
      </span>
      {live ? "Live" : conn === "connecting" ? "Connecting" : "Reconnecting"}
    </span>
  );
}

const TONE_CLASS: Record<string, string> = {
  wait: "bg-amber-500/15 text-amber-700 dark:text-amber-300",
  offer: "bg-violet-500/15 text-violet-700 dark:text-violet-300",
  active: "bg-emerald-500/15 text-emerald-700 dark:text-emerald-300",
  done: "bg-slate-500/15 text-muted",
  off: "bg-slate-500/15 text-muted",
};

export function StatusBadge({ status }: { status: JobStatus }) {
  const meta = STATUS_META[status];
  return <span className={`inline-flex items-center rounded-full px-2.5 py-0.5 text-[11px] font-semibold ${TONE_CLASS[meta.tone]}`}>{meta.label}</span>;
}

export function UrgentBadge() {
  return <span className="inline-flex items-center rounded-full bg-red-500/15 px-2.5 py-0.5 text-[11px] font-semibold text-red-700 dark:text-red-300">Urgent</span>;
}

/** A small labelled number. */
export function Stat({ label, value, tone }: { label: string; value: React.ReactNode; tone?: "danger" | "good" }) {
  return (
    <div className="rounded-xl border border-line p-3">
      <dt className="text-[11px] uppercase tracking-wider text-muted">{label}</dt>
      <dd className={`mt-1 font-mono text-[20px] font-semibold ${tone === "danger" ? "text-red-500" : tone === "good" ? "text-emerald-500" : ""}`}>{value}</dd>
    </div>
  );
}

export function Empty({ children }: { children: React.ReactNode }) {
  return <p className="px-1 py-6 text-[13px] text-muted">{children}</p>;
}
