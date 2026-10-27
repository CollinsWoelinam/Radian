"use client";

import dynamic from "next/dynamic";
import { useEffect, useRef } from "react";

import type { JobOverlay, ZoneOverlay } from "@/components/FleetMap";
import type { Zone } from "@/lib/geofences";
import { useConsole } from "./ConsoleContext";

// MapLibre and deck.gl need WebGL and window: load them in the browser only.
export const FleetMap = dynamic(() => import("@/components/FleetMap"), {
  ssr: false,
  loading: () => <div className="absolute inset-0 grid place-items-center bg-sunken text-[13px] text-muted">Loading map…</div>,
});

export const ReplayMap = dynamic(() => import("@/components/ReplayMap"), {
  ssr: false,
  loading: () => <div className="absolute inset-0 grid place-items-center bg-sunken text-[13px] text-muted">Loading map…</div>,
});

export const noJobs: JobOverlay = { jobs: [], selectedJob: null, draft: null, picking: false };

/** A zone overlay kept in step with the console's zones and live alerts. */
export function useZoneOverlay(opts: { zones?: Zone[]; highlightId?: string | null; draft?: [number, number][] | null; draftClosed?: boolean } = {}) {
  const { zones, mapAlerts } = useConsole();
  const ref = useRef<ZoneOverlay>({ zones: [], highlightId: null, draft: null, draftClosed: false, alerts: [] });
  const shown = opts.zones ?? zones;
  useEffect(() => {
    ref.current = {
      zones: shown,
      highlightId: opts.highlightId ?? null,
      draft: opts.draft ?? null,
      draftClosed: opts.draftClosed ?? false,
      // Read each frame, so new alerts pulse without a re-render.
      get alerts() {
        return mapAlerts.current;
      },
    };
  }, [shown, opts.highlightId, opts.draft, opts.draftClosed, mapAlerts]);
  return ref;
}
