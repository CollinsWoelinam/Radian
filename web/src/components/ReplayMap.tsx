"use client";

import { useEffect, useMemo, useRef } from "react";
import { Map, NavigationControl, useControl, type MapRef } from "react-map-gl/maplibre";
import { MapboxOverlay } from "@deck.gl/mapbox";
import { setWorkerUrl } from "maplibre-gl";
import { PathLayer, ScatterplotLayer } from "@deck.gl/layers";
import "maplibre-gl/dist/maplibre-gl.css";

import { INITIAL_VIEW, MAP_STYLES, type Theme } from "@/lib/config";
import { SPEED_LIMIT_KMH, type TrackEvent } from "@/lib/console";

setWorkerUrl(new URL("/maplibre/maplibre-gl-worker.mjs", window.location.origin).href);

type Pt = [number, number, number, number]; // [ms, lat, lon, speed]
type Seg = { path: [number, number][]; fast: boolean; played: boolean };

function Overlay({ layers }: { layers: unknown[] }) {
  const overlay = useControl(() => new MapboxOverlay({ interleaved: false }));
  useEffect(() => {
    overlay.setProps({ layers: layers as never });
  }, [overlay, layers]);
  return null;
}

/** A vehicle's route for one time window, with a playhead at `cursor`. */
export default function ReplayMap({ points, cursor, events, theme }: { points: Pt[]; cursor: number; events: TrackEvent[]; theme: Theme }) {
  const mapRef = useRef<MapRef | null>(null);

  // Split the route into runs at or under, and over, the speed limit. A gap of
  // more than two minutes without a fix breaks the line instead of drawing a
  // straight jump across the map.
  const runs = useMemo(() => {
    const out: { from: number; to: number; fast: boolean }[] = [];
    for (let i = 1; i < points.length; i++) {
      if (points[i][0] - points[i - 1][0] > 120_000) continue;
      const fast = points[i][3] > SPEED_LIMIT_KMH;
      const last = out[out.length - 1];
      if (last && last.fast === fast && last.to === i - 1) last.to = i;
      else out.push({ from: i - 1, to: i, fast });
    }
    return out;
  }, [points]);

  const layers = useMemo(() => {
    const segs: Seg[] = [];
    for (const r of runs) {
      const cut = Math.min(Math.max(cursor, r.from), r.to);
      const path = (a: number, b: number) => points.slice(a, b + 1).map((p) => [p[2], p[1]] as [number, number]);
      if (cut > r.from) segs.push({ path: path(r.from, cut), fast: r.fast, played: true });
      if (cut < r.to) segs.push({ path: path(cut, r.to), fast: r.fast, played: false });
    }
    const here = points[Math.min(cursor, points.length - 1)];
    const marks = events.filter((e) => e.lat != null && e.lon != null && (e.kind === "stop" || e.kind === "speeding" || (e.kind === "zone" && e.alert)));
    return [
      new PathLayer<Seg>({
        id: "route-casing",
        data: segs,
        getPath: (s) => s.path,
        getColor: theme === "dark" ? [14, 22, 38, 255] : [255, 255, 255, 255],
        getWidth: 9,
        widthUnits: "pixels",
        capRounded: true,
        jointRounded: true,
      }),
      new PathLayer<Seg>({
        id: "route",
        data: segs,
        getPath: (s) => s.path,
        getColor: (s) => (s.fast ? [239, 68, 68, s.played ? 255 : 110] : [79, 139, 255, s.played ? 255 : 90]),
        getWidth: (s) => (s.played ? 5 : 4),
        widthUnits: "pixels",
        capRounded: true,
        jointRounded: true,
      }),
      new ScatterplotLayer<TrackEvent>({
        id: "marks",
        data: marks,
        getPosition: (e) => [e.lon!, e.lat!],
        radiusUnits: "pixels",
        getRadius: 6,
        stroked: true,
        getFillColor: theme === "dark" ? [14, 22, 38, 255] : [255, 255, 255, 255],
        getLineColor: (e) => (e.kind === "speeding" || e.kind === "zone" ? [239, 68, 68, 255] : [154, 166, 184, 255]),
        lineWidthUnits: "pixels",
        getLineWidth: 2.5,
      }),
      new ScatterplotLayer<Pt>({
        id: "here",
        data: here ? [here] : [],
        getPosition: (p) => [p[2], p[1]],
        radiusUnits: "pixels",
        getRadius: 9,
        stroked: true,
        getFillColor: [245, 158, 11, 255],
        getLineColor: theme === "dark" ? [14, 22, 38, 255] : [255, 255, 255, 255],
        lineWidthUnits: "pixels",
        getLineWidth: 3,
      }),
      new ScatterplotLayer<Pt>({
        id: "here-halo",
        data: here ? [here] : [],
        getPosition: (p) => [p[2], p[1]],
        radiusUnits: "pixels",
        getRadius: 20,
        getFillColor: [245, 158, 11, 50],
      }),
    ];
  }, [runs, points, cursor, events, theme]);

  // Frame the whole route when a new window loads.
  useEffect(() => {
    const map = mapRef.current;
    if (!map || points.length < 2) return;
    const lons = points.map((p) => p[2]);
    const lats = points.map((p) => p[1]);
    map.fitBounds(
      [
        [Math.min(...lons), Math.min(...lats)],
        [Math.max(...lons), Math.max(...lats)],
      ],
      { padding: 60, maxZoom: 16, duration: 600 },
    );
  }, [points]);

  return (
    <Map ref={mapRef} initialViewState={INITIAL_VIEW} mapStyle={MAP_STYLES[theme]} style={{ position: "absolute", inset: 0 }} attributionControl={{ compact: true }}>
      <NavigationControl position="bottom-right" />
      <Overlay layers={layers} />
    </Map>
  );
}
