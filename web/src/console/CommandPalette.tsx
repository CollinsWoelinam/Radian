"use client";

import { useRouter } from "next/navigation";
import { useEffect, useMemo, useRef, useState } from "react";

import { zoneKind } from "@/lib/geofences";
import { useConsole } from "./ConsoleContext";
import { Icon } from "./ui";

type Item = { id: string; group: string; label: string; hint?: string; mono?: boolean; run: () => void };

/** ⌘K: jump to a vehicle, job or zone, or run an action. */
export default function CommandPalette() {
  const { paletteOpen, setPaletteOpen } = useConsole();
  if (!paletteOpen) return null;
  return <Palette onClose={() => setPaletteOpen(false)} />;
}

function Palette({ onClose }: { onClose: () => void }) {
  const { registry, active, recent, zones, theme, setTheme, store } = useConsole();
  const router = useRouter();
  const [q, setQ] = useState("");
  const [cursor, setCursor] = useState(0);
  const input = useRef<HTMLInputElement>(null);

  useEffect(() => input.current?.focus(), []);

  const items = useMemo(() => {
    const go = (href: string) => () => {
      router.push(href);
      onClose();
    };
    const query = q.trim().toLowerCase().replace(/^#/, "");
    const all: Item[] = [
      { id: "new-job", group: "Actions", label: "New job", run: go("/jobs/new") },
      { id: "new-zone", group: "Actions", label: "Draw a zone", run: go("/zones?draw=1") },
      { id: "theme", group: "Actions", label: `Switch to ${theme === "dark" ? "light" : "dark"} theme`, run: () => (setTheme(theme === "dark" ? "light" : "dark"), onClose()) },
      ...[...active, ...recent].map((j) => ({
        id: `job-${j.id}`,
        group: "Jobs",
        label: `#${j.number} · ${j.pickup_address || "Pickup"}`,
        hint: j.vehicle?.license_plate,
        run: go(`/jobs/${j.id}`),
      })),
      ...[...registry.values()].map((v) => ({
        id: `veh-${v.id}`,
        group: "Vehicles",
        label: v.license_plate,
        hint: store.get(v.id) ? "on the map" : "out of view",
        mono: true,
        run: go(`/vehicles/${v.id}`),
      })),
      ...zones.map((z) => ({ id: `zone-${z.id}`, group: "Zones", label: z.name, hint: zoneKind(z.kind).label, run: go(`/zones?zone=${z.id}`) })),
    ];
    const hits = query ? all.filter((i) => `${i.label} ${i.hint ?? ""}`.toLowerCase().includes(query)) : all.filter((i) => i.group !== "Vehicles");
    return hits.slice(0, 40);
  }, [q, registry, active, recent, zones, theme, setTheme, store, router, onClose]);

  const pick = items[Math.min(cursor, items.length - 1)];

  return (
    <div className="fixed inset-0 z-[60] grid place-items-start bg-black/40 px-3 pt-[12vh]" onMouseDown={onClose}>
      <div role="dialog" aria-modal="true" aria-label="Search" className="panel mx-auto w-full max-w-xl overflow-hidden" onMouseDown={(e) => e.stopPropagation()}>
        <label className="flex items-center gap-3 border-b border-line px-4">
          <Icon.Search size={18} />
          <span className="sr-only">Search</span>
          <input
            ref={input}
            value={q}
            onChange={(e) => {
              setQ(e.target.value);
              setCursor(0);
            }}
            onKeyDown={(e) => {
              if (e.key === "ArrowDown") {
                e.preventDefault();
                setCursor((c) => Math.min(c + 1, items.length - 1));
              } else if (e.key === "ArrowUp") {
                e.preventDefault();
                setCursor((c) => Math.max(c - 1, 0));
              } else if (e.key === "Enter") {
                pick?.run();
              } else if (e.key === "Escape") {
                onClose();
              }
            }}
            placeholder="Search plates, jobs (#1042), zones, or type an action…"
            className="h-14 grow bg-transparent text-[15px] outline-none placeholder:text-muted"
            role="combobox"
            aria-expanded="true"
            aria-controls="palette-results"
            aria-activedescendant={pick ? `pal-${pick.id}` : undefined}
          />
          <kbd className="rounded-md border border-line px-1.5 py-0.5 font-mono text-[11px] text-muted">Esc</kbd>
        </label>
        <ul id="palette-results" role="listbox" className="max-h-[50vh] overflow-y-auto py-2">
          {items.length === 0 && <li className="px-4 py-6 text-[13px] text-muted">Nothing matches “{q}”.</li>}
          {items.map((it, i) => (
            <li key={it.id} id={`pal-${it.id}`} role="option" aria-selected={it === pick}>
              {(i === 0 || items[i - 1].group !== it.group) && <div className="px-4 pb-1 pt-2 text-[11px] font-semibold uppercase tracking-wider text-muted">{it.group}</div>}
              <button
                type="button"
                onMouseEnter={() => setCursor(i)}
                onClick={it.run}
                className={`flex w-full items-center gap-3 px-4 py-2 text-left text-[14px] ${it === pick ? "bg-hover" : ""}`}
              >
                <span className={`grow truncate ${it.mono ? "font-mono" : ""}`}>{it.label}</span>
                {it.hint && <span className="shrink-0 text-[12px] text-muted">{it.hint}</span>}
              </button>
            </li>
          ))}
        </ul>
      </div>
    </div>
  );
}
