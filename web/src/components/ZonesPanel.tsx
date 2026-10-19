"use client";

import { useState } from "react";
import {
  ZONE_KINDS,
  severity,
  zoneKind,
  type Zone,
  type ZoneEvent,
  type ZoneKind,
} from "@/lib/geofences";

export type ZoneMode = "list" | "draw";

type Props = {
  mode: ZoneMode;
  zones: Zone[];
  events: ZoneEvent[];
  highlightId: string | null;
  corners: number;
  closed: boolean;
  error: string | null;
  onNew: () => void;
  onCancel: () => void;
  onUndo: () => void;
  onClose: () => void;
  onSave: (name: string, kind: ZoneKind) => Promise<void>;
  onDelete: (z: Zone) => Promise<void>;
  onFocusZone: (z: Zone) => void;
  onFocusEvent: (e: ZoneEvent) => void;
};

const SEVERITY_DOT = {
  critical: "bg-red-500",
  warning: "bg-amber-500",
  info: "bg-slate-400",
};

export default function ZonesPanel(p: Props) {
  const [tab, setTab] = useState<"zones" | "alerts">("zones");
  const alerts = p.events.filter(
    (e) => severity(e.kind, e.entered) !== "info",
  ).length;

  if (p.mode === "draw") return <DrawZone {...p} />;
  return (
    <div className="flex max-h-full min-h-0 flex-col">
      <header className="flex items-center justify-between gap-2 border-b border-line px-4 py-3">
        <div className="flex gap-1 rounded-lg bg-input p-0.5" role="tablist">
          {(["zones", "alerts"] as const).map((t) => (
            <button
              key={t}
              role="tab"
              aria-selected={tab === t}
              onClick={() => setTab(t)}
              className={`rounded-md px-2.5 py-1 text-[12px] font-medium ${tab === t ? "bg-panel shadow-sm" : "text-muted"}`}
            >
              {t === "zones"
                ? `Zones (${p.zones.length})`
                : `Activity${alerts ? ` (${alerts})` : ""}`}
            </button>
          ))}
        </div>
        <button onClick={p.onNew} className="btn-primary">
          + New zone
        </button>
      </header>
      {tab === "zones" ? (
        <ZoneList {...p} />
      ) : (
        <EventFeed events={p.events} onFocus={p.onFocusEvent} />
      )}
      {p.error && (
        <p className="mx-4 mb-3 rounded-lg bg-red-500/10 px-3 py-2 text-[12px] text-red-600 dark:text-red-400">
          {p.error}
        </p>
      )}
    </div>
  );
}

function ZoneList(p: Props) {
  const [confirming, setConfirming] = useState<string | null>(null);
  if (p.zones.length === 0)
    return (
      <p className="px-4 py-6 text-[13px] text-muted">
        No zones yet. Draw depots, service areas and restricted areas to get
        alerts.
      </p>
    );
  return (
    <ul className="min-h-0 overflow-y-auto py-1">
      {p.zones.map((z) => {
        const k = zoneKind(z.kind);
        return (
          <li
            key={z.id}
            className={`group flex items-center gap-2 pr-2 ${z.id === p.highlightId ? "bg-hover" : ""}`}
          >
            <button
              onClick={() => p.onFocusZone(z)}
              className="flex min-w-0 flex-1 items-center gap-3 px-4 py-2.5 text-left hover:bg-hover"
            >
              <span
                className="size-3 shrink-0 rounded-sm ring-2"
                style={{
                  background: `rgb(${k.rgb.join(",")} / 0.35)`,
                  ["--tw-ring-color" as string]: `rgb(${k.rgb.join(",")})`,
                }}
              />
              <span className="min-w-0 flex-1">
                <span className="block truncate text-[13px] font-medium">
                  {z.name}
                </span>
                <span className="block text-[11px] text-muted">
                  {k.label} · {formatArea(z.area_km2)}
                </span>
              </span>
              <span className="text-right" title="Vehicles inside now">
                <span className="block font-mono text-[13px] tabular-nums">
                  {z.vehicles_inside.toLocaleString()}
                </span>
                <span className="block text-[10px] text-muted">inside</span>
              </span>
            </button>
            {confirming === z.id ? (
              <span className="flex gap-1">
                <button
                  className="rounded-md bg-red-500 px-2 py-1 text-[11px] font-semibold text-white"
                  onClick={() =>
                    p.onDelete(z).finally(() => setConfirming(null))
                  }
                >
                  Delete
                </button>
                <button
                  className="rounded-md px-2 py-1 text-[11px] text-muted hover:bg-hover"
                  onClick={() => setConfirming(null)}
                >
                  Keep
                </button>
              </span>
            ) : (
              <button
                className="icon-btn opacity-60 hover:opacity-100 focus:opacity-100"
                aria-label={`Delete ${z.name}`}
                title="Delete zone"
                onClick={() => setConfirming(z.id)}
              >
                <TrashIcon />
              </button>
            )}
          </li>
        );
      })}
    </ul>
  );
}

function EventFeed({
  events,
  onFocus,
}: {
  events: ZoneEvent[];
  onFocus: (e: ZoneEvent) => void;
}) {
  if (events.length === 0)
    return (
      <p className="px-4 py-6 text-[13px] text-muted">
        No zone crossings yet. They appear here as vehicles enter and leave
        zones.
      </p>
    );
  return (
    <ul className="min-h-0 overflow-y-auto py-1" aria-live="polite">
      {events.map((e) => {
        const sev = severity(e.kind, e.entered);
        return (
          <li key={e.id}>
            <button
              onClick={() => onFocus(e)}
              className="flex w-full items-start gap-3 px-4 py-2 text-left hover:bg-hover"
            >
              <span
                className={`mt-1.5 size-2 shrink-0 rounded-full ${SEVERITY_DOT[sev]}`}
                aria-label={sev}
              />
              <span className="min-w-0 flex-1">
                <span
                  className={`block text-[13px] ${sev === "info" ? "" : "font-medium"}`}
                >
                  <span className="font-mono">{e.license_plate}</span>{" "}
                  {e.entered ? "entered" : "left"} {e.geofence_name}
                </span>
                <span className="block text-[11px] text-muted">
                  {zoneKind(e.kind).label} · {timeAgo(e.occurred_at)}
                </span>
              </span>
            </button>
          </li>
        );
      })}
    </ul>
  );
}

function DrawZone(p: Props) {
  const [name, setName] = useState("");
  const [kind, setKind] = useState<ZoneKind>("DEPOT");
  const [busy, setBusy] = useState(false);
  const canClose = p.corners >= 3 && !p.closed;

  return (
    <div className="flex min-h-0 flex-col">
      <header className="flex items-center justify-between border-b border-line px-4 py-3">
        <h2 className="text-[14px] font-semibold">New zone</h2>
        <button
          onClick={p.onCancel}
          className="text-[12px] text-muted hover:text-fg"
        >
          Cancel
        </button>
      </header>
      <form
        className="space-y-3 overflow-y-auto px-4 py-3"
        onSubmit={async (e) => {
          e.preventDefault();
          setBusy(true);
          try {
            await p.onSave(name, kind);
          } finally {
            setBusy(false);
          }
        }}
      >
        <div
          className="rounded-lg border border-line bg-input px-3 py-2.5 text-[12px]"
          aria-live="polite"
        >
          {p.closed ? (
            <p>
              <span className="font-semibold text-emerald-600 dark:text-emerald-400">
                Outline complete
              </span>{" "}
              · {p.corners} corners
            </p>
          ) : (
            <p>
              <span className="font-semibold">
                Click the map to add corners.
              </span>{" "}
              <span className="text-muted">
                {p.corners < 3
                  ? `${p.corners} of at least 3 placed.`
                  : "Click the first corner, or Finish, to close the outline."}
              </span>
            </p>
          )}
          <div className="mt-2 flex gap-2">
            <button
              type="button"
              className="btn-secondary"
              disabled={p.corners === 0}
              onClick={p.onUndo}
            >
              {p.closed ? "Reopen" : "Undo corner"}
            </button>
            {!p.closed && (
              <button
                type="button"
                className="btn-secondary"
                disabled={!canClose}
                onClick={p.onClose}
              >
                Finish outline
              </button>
            )}
          </div>
        </div>

        <label className="block">
          <span className="mb-1 block text-[11px] font-semibold uppercase tracking-wider text-muted">
            Name
          </span>
          <input
            className="field"
            value={name}
            onChange={(e) => setName(e.target.value)}
            placeholder="e.g. Tema Harbour Depot"
            maxLength={100}
          />
        </label>

        <div role="radiogroup" aria-labelledby="zone-kind-label">
          <span
            id="zone-kind-label"
            className="mb-1 block text-[11px] font-semibold uppercase tracking-wider text-muted"
          >
            Type
          </span>
          <div className="space-y-1.5">
            {ZONE_KINDS.map((k) => (
              <button
                type="button"
                role="radio"
                aria-checked={kind === k.value}
                key={k.value}
                onClick={() => setKind(k.value)}
                className={`flex w-full items-center gap-2.5 rounded-lg border px-3 py-2 text-left ${kind === k.value ? "border-accent bg-accent/10" : "border-line hover:bg-hover"}`}
              >
                <span
                  className="size-3 shrink-0 rounded-sm"
                  style={{ background: `rgb(${k.rgb.join(",")})` }}
                />
                <span>
                  <span className="block text-[13px] font-medium">
                    {k.label}
                  </span>
                  <span className="block text-[11px] text-muted">{k.hint}</span>
                </span>
              </button>
            ))}
          </div>
        </div>

        <button
          type="submit"
          disabled={busy || !p.closed || !name.trim()}
          className="btn-primary w-full py-2.5"
        >
          {busy ? "Saving…" : "Save zone"}
        </button>
        {!p.closed && (
          <p className="text-[11px] text-muted">Close the outline to save.</p>
        )}
        {p.error && (
          <p className="rounded-lg bg-red-500/10 px-3 py-2 text-[12px] text-red-600 dark:text-red-400">
            {p.error}
          </p>
        )}
      </form>
    </div>
  );
}

function formatArea(km2: number) {
  if (km2 >= 10) return `${Math.round(km2).toLocaleString()} km²`;
  if (km2 >= 1) return `${km2.toFixed(1)} km²`;
  return `${Math.round(km2 * 100)} ha`;
}

export function timeAgo(iso: string) {
  const s = Math.max(0, Math.round((Date.now() - Date.parse(iso)) / 1000));
  if (s < 60) return `${s}s ago`;
  if (s < 3600) return `${Math.floor(s / 60)}m ago`;
  if (s < 86400) return `${Math.floor(s / 3600)}h ago`;
  return new Date(iso).toLocaleDateString();
}

function TrashIcon() {
  return (
    <svg
      width="15"
      height="15"
      viewBox="0 0 24 24"
      fill="none"
      stroke="currentColor"
      strokeWidth="2"
      strokeLinecap="round"
      strokeLinejoin="round"
      aria-hidden
    >
      <path d="M3 6h18M8 6V4h8v2M19 6l-1 14H6L5 6" />
    </svg>
  );
}
