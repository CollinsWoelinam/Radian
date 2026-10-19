"use client";

import { useEffect, useRef } from "react";
import { Map, NavigationControl, useControl, type MapRef } from "react-map-gl/maplibre";
import { MapboxOverlay } from "@deck.gl/mapbox";
import { setWorkerUrl } from "maplibre-gl";
import { IconLayer, PathLayer, PolygonLayer, ScatterplotLayer, TextLayer } from "@deck.gl/layers";
import type { PickingInfo } from "@deck.gl/core";
import "maplibre-gl/dist/maplibre-gl.css";

import type { FleetStore, Vehicle } from "@/lib/fleet-store";
import { VehicleStatus } from "@/gen/radian/telemetry/v1/telemetry_pb";
import type { Viewport } from "@/lib/fleet-socket";
import { INITIAL_VIEW, MAP_STYLES, statusInfo, type StatusKey, type Theme } from "@/lib/config";
import { STATUS_META, type Job, type JobDetail, type LatLon, type RouteLeg } from "@/lib/jobs";
import { zoneKind, type Severity, type Zone } from "@/lib/geofences";

/** Job-related things to draw over the fleet; read every frame. */
export type JobOverlay = {
  jobs: Job[];
  selectedJob: JobDetail | null;
  draft: { pickup?: LatLon; dropoff?: LatLon } | null;
  picking: boolean;
};

/** Zones and zone drawing; read every frame. */
export type ZoneOverlay = {
  zones: Zone[];
  highlightId: string | null;
  /** Outline being drawn, [lon, lat]; null when not drawing. */
  draft: [number, number][] | null;
  /** The outline is complete; clicks no longer add corners. */
  draftClosed: boolean;
  /** Recent alerts to pulse on the map; `t` is performance.now() when received. */
  alerts: { at: LatLon; t: number; severity: Severity }[];
};

type RGB = [number, number, number];
type ZonePart = { zone: Zone; rings: [number, number][][] };
type ZoneLabel = { zone: Zone; at: [number, number] };
type ZoneData = { zones: Zone[]; parts: ZonePart[]; labels: ZoneLabel[] };
const PULSE_MS = 2400;
const SEVERITY_RGB: Record<Severity, RGB> = { critical: [239, 68, 68], warning: [245, 158, 11], info: [59, 130, 246] };

/** Deck data for the zones; rebuilt only when the zone list changes. */
function zoneData(zones: Zone[], cache: ZoneData | null): ZoneData {
  if (cache?.zones === zones) return cache;
  const parts = zones.flatMap((zone) => zone.area.map((rings) => ({ zone, rings })));
  const labels = zones.map((zone) => {
    const outer = zone.area[0]?.[0] ?? [];
    const lons = outer.map((p) => p[0]);
    const lats = outer.map((p) => p[1]);
    return { zone, at: [(Math.min(...lons) + Math.max(...lons)) / 2, (Math.min(...lats) + Math.max(...lats)) / 2] as [number, number] };
  });
  return { zones, parts, labels };
}
const TONE_RGB: Record<string, RGB> = {
  wait: [245, 158, 11],
  offer: [139, 92, 246],
  active: [16, 185, 129],
  done: [120, 128, 140],
  off: [120, 128, 140],
};
const jobRgb = (j: Job): RGB => TONE_RGB[STATUS_META[j.status].tone];
const LEG_RGB: Record<RouteLeg["kind"], RGB> = { to_pickup: [59, 130, 246], to_dropoff: [168, 85, 247] };
type Pin = { id: string; at: LatLon; rgb: RGB; kind: "pickup" | "dropoff" };

const ICON_MAPPING = {
  arrow: { x: 0, y: 0, width: 64, height: 64, mask: true },
  dot: { x: 64, y: 0, width: 64, height: 64, mask: true },
};
const MOVING_KMH = 5;

type Props = {
  store: FleetStore;
  theme: Theme;
  hidden: Set<StatusKey>;
  selectedId: string | null;
  follow: boolean;
  onSelect: (id: string | null) => void;
  onViewportChange: (v: Viewport) => void;
  onUserPan: () => void;
  onFrame: (fps: number) => void;
  mapRef: React.RefObject<MapRef | null>;
  jobOverlay: React.RefObject<JobOverlay>;
  onSelectJob: (id: string | null) => void;
  onMapClick: (at: LatLon) => void;
  zoneOverlay: React.RefObject<ZoneOverlay>;
  /** Drawing a zone: clicks add corners; clicking the first corner closes it. */
  drawing: boolean;
  onDrawPoint: (p: [number, number]) => void;
  onCloseDraft: () => void;
};

// MapLibre resolves its worker relative to its own bundle, which breaks once
// Turbopack relocates it; serve the worker from /public instead.
setWorkerUrl(new URL("/maplibre/maplibre-gl-worker.mjs", window.location.origin).href);

function DeckOverlay({ onReady }: { onReady: (o: MapboxOverlay) => void }) {
  // Own canvas above the map: survives React's dev double-mount, and markers
  // always draw over basemap labels.
  const overlay = useControl(() => new MapboxOverlay({ interleaved: false }));
  useEffect(() => {
    onReady(overlay);
  }, [overlay, onReady]);
  return null;
}

export default function FleetMap(props: Props) {
  const { store, theme, mapRef, onViewportChange, onUserPan } = props;
  const overlayRef = useRef<MapboxOverlay | null>(null);
  // The render loop reads the latest props without restarting.
  const live = useRef(props);
  useEffect(() => {
    live.current = props;
  });

  useEffect(() => {
    let raf = 0;
    let frames = 0;
    let fpsStart = performance.now();
    let zoneCache: ZoneData | null = null;

    const loop = (now: number) => {
      raf = requestAnimationFrame(loop);
      const overlay = overlayRef.current;
      if (!overlay) return;
      const { hidden, selectedId, follow, onSelect, onFrame, theme: mapTheme, jobOverlay, onSelectJob, onMapClick } =
        live.current;
      const { zoneOverlay, drawing, onDrawPoint, onCloseDraft } = live.current;
      const jo = jobOverlay.current;
      const zo = zoneOverlay.current;
      zoneCache = zoneData(zo.zones, zoneCache);
      const { parts, labels } = zoneCache;
      const draft = zo.draft ?? [];
      const pulses = zo.alerts.filter((a) => now - a.t < PULSE_MS);
      const ring: [number, number, number] = mapTheme === "dark" ? [255, 255, 255] : [15, 23, 42];

      store.advance(now);
      const selected = selectedId ? store.get(selectedId) : undefined;
      if (selected && follow) {
        mapRef.current?.getMap().setCenter([selected.lon, selected.lat]);
      }

      const isHidden = (v: Vehicle) => hidden.has(statusInfo(v.status).key);
      const isOffline = (v: Vehicle) => v.status === VehicleStatus.OFFLINE;
      const icon = (v: Vehicle) => (v.speedKmh >= MOVING_KMH && !isOffline(v) ? "arrow" : "dot");
      // Sized in meters so markers shrink with the city when zoomed out,
      // clamped so they stay visible and never balloon.
      const size = (v: Vehicle, halo: number) => {
        if (isHidden(v)) return 0;
        if (isOffline(v)) return 55 + halo * 15;
        return (icon(v) === "arrow" ? 140 : 80) + halo * 30;
      };
      const common = {
        data: store.list,
        iconAtlas: "/vehicle-atlas.svg",
        iconMapping: ICON_MAPPING,
        billboard: false, // lie flat so headings stay true when the map rotates
        sizeUnits: "meters" as const,
        getPosition: (v: Vehicle) => [v.lon, v.lat] as [number, number],
        getAngle: (v: Vehicle) => -v.heading,
        getIcon: icon,
        updateTriggers: { getPosition: now, getAngle: now, getIcon: now, getColor: now, getSize: now },
      };

      // Job pins: every open job's pickup; the selected job also shows its drop-off.
      const sel = jo.selectedJob;
      const pins: Pin[] = jo.jobs
        .filter((j) => j.id !== sel?.id)
        .map((j) => ({ id: j.id, at: j.pickup, rgb: jobRgb(j), kind: "pickup" }));
      if (sel) {
        pins.push({ id: sel.id, at: sel.pickup, rgb: jobRgb(sel), kind: "pickup" });
        if (sel.dropoff) pins.push({ id: sel.id, at: sel.dropoff, rgb: jobRgb(sel), kind: "dropoff" });
      }
      const currentLeg = sel?.route[0];
      const legsBottomUp = sel ? [...sel.route].reverse() : [];
      const jobVehicle = sel?.vehicle ? store.get(sel.vehicle.id) : undefined;
      const draftPins: Pin[] = [];
      if (jo.draft?.pickup) draftPins.push({ id: "draft-p", at: jo.draft.pickup, rgb: [34, 197, 94], kind: "pickup" });
      if (jo.draft?.dropoff) draftPins.push({ id: "draft-d", at: jo.draft.dropoff, rgb: [239, 68, 68], kind: "dropoff" });

      overlay.setProps({
        layers: [
          new PolygonLayer<ZonePart>({
            id: "zones",
            data: parts,
            getPolygon: (z) => z.rings,
            filled: true,
            stroked: true,
            getFillColor: (z) => [...zoneKind(z.zone.kind).rgb, z.zone.id === zo.highlightId ? 70 : z.zone.kind === "SERVICE_AREA" ? 14 : 38],
            getLineColor: (z) => [...zoneKind(z.zone.kind).rgb, z.zone.id === zo.highlightId ? 255 : 190],
            getLineWidth: (z) => (z.zone.id === zo.highlightId ? 3 : z.zone.kind === "SERVICE_AREA" ? 1.5 : 2),
            lineWidthUnits: "pixels",
            updateTriggers: { getFillColor: zo.highlightId, getLineColor: zo.highlightId, getLineWidth: zo.highlightId },
          }),
          new TextLayer<ZoneLabel>({
            id: "zone-labels",
            data: labels,
            getPosition: (l) => l.at,
            getText: (l) => l.zone.name,
            getSize: 11,
            getColor: (l) => [...zoneKind(l.zone.kind).rgb, 255],
            fontFamily: 'system-ui, -apple-system, "Segoe UI", Roboto, sans-serif',
            fontWeight: 600,
            background: true,
            getBackgroundColor: mapTheme === "dark" ? [11, 15, 20, 200] : [255, 255, 255, 220],
            backgroundPadding: [5, 2],
            updateTriggers: { getBackgroundColor: mapTheme },
          }),
          new PolygonLayer<[number, number][]>({
            id: "zone-draft-fill",
            data: draft.length >= 3 ? [draft] : [],
            getPolygon: (d) => d,
            filled: true,
            stroked: false,
            getFillColor: [59, 130, 246, zo.draftClosed ? 60 : 30],
            updateTriggers: { getFillColor: zo.draftClosed },
          }),
          new PathLayer<[number, number][]>({
            id: "zone-draft-edge",
            data: draft.length >= 2 ? [zo.draftClosed ? [...draft, draft[0]] : draft] : [],
            getPath: (d) => d,
            getColor: [59, 130, 246, 255],
            getWidth: 2,
            widthUnits: "pixels",
          }),
          new ScatterplotLayer<[number, number]>({
            id: "zone-draft-corners",
            data: draft,
            getPosition: (d) => d,
            radiusUnits: "pixels",
            // The first corner is bigger: clicking it closes the outline.
            getRadius: (d) => (d === draft[0] && draft.length >= 3 && !zo.draftClosed ? 8 : 5),
            stroked: true,
            getFillColor: [255, 255, 255, 255],
            getLineColor: [59, 130, 246, 255],
            lineWidthUnits: "pixels",
            getLineWidth: 2,
            updateTriggers: { getRadius: [draft.length, zo.draftClosed] },
          }),
          // Legs come current-first from the API; draw upcoming ones underneath,
          // faded, so the leg the driver is on now is never hidden by a later one.
          new PathLayer<RouteLeg>({
            id: "job-route-casing",
            data: legsBottomUp,
            getPath: (l) => l.coordinates,
            getColor: (l) => [255, 255, 255, l === currentLeg ? 210 : 90],
            getWidth: (l) => (l === currentLeg ? 10 : 7),
            widthUnits: "pixels",
            capRounded: true,
            jointRounded: true,
          }),
          new PathLayer<RouteLeg>({
            id: "job-route",
            data: legsBottomUp,
            getPath: (l) => l.coordinates,
            getColor: (l) => [...LEG_RGB[l.kind], l === currentLeg ? 240 : 120],
            getWidth: (l) => (l === currentLeg ? 6 : 4),
            widthUnits: "pixels",
            capRounded: true,
            jointRounded: true,
          }),
          // Dark halo underneath keeps markers legible on any basemap.
          new IconLayer<Vehicle>({
            ...common,
            id: "vehicle-halo",
            sizeMinPixels: 0,
            sizeMaxPixels: 30,
            getColor: (v) => [0, 0, 0, isOffline(v) ? 50 : 120],
            getSize: (v) => size(v, 1),
          }),
          new IconLayer<Vehicle>({
            ...common,
            id: "vehicles",
            pickable: true,
            sizeMinPixels: 4,
            sizeMaxPixels: 24,
            getColor: (v) => [...statusInfo(v.status).rgb, isOffline(v) ? 150 : 255],
            getSize: (v) => size(v, 0),
          }),
          new ScatterplotLayer<Vehicle>({
            id: "selection",
            data: selected ? [selected] : [],
            getPosition: (v) => [v.lon, v.lat],
            radiusUnits: "pixels",
            getRadius: 19,
            stroked: true,
            filled: true,
            getFillColor: [...ring, 30],
            getLineColor: [...ring, 230],
            lineWidthUnits: "pixels",
            getLineWidth: 2,
            updateTriggers: { getPosition: now },
          }),
          new ScatterplotLayer<Vehicle>({
            id: "job-vehicle",
            data: jobVehicle ? [jobVehicle] : [],
            getPosition: (v) => [v.lon, v.lat],
            radiusUnits: "pixels",
            getRadius: 16,
            stroked: true,
            filled: true,
            getFillColor: [245, 158, 11, 45],
            getLineColor: [245, 158, 11, 255],
            lineWidthUnits: "pixels",
            getLineWidth: 3,
            updateTriggers: { getPosition: now },
          }),
          new ScatterplotLayer<Pin>({
            id: "job-pins",
            data: [...pins, ...draftPins],
            pickable: true,
            getPosition: (p) => [p.at.lon, p.at.lat],
            radiusUnits: "pixels",
            getRadius: (p) => (p.id === sel?.id || p.id.startsWith("draft") ? 10 : 7),
            stroked: true,
            getFillColor: (p) => (p.kind === "dropoff" ? [255, 255, 255, 255] : [...p.rgb, 255]),
            getLineColor: (p) => (p.kind === "dropoff" ? [...p.rgb, 255] : [255, 255, 255, 255]),
            lineWidthUnits: "pixels",
            getLineWidth: (p) => (p.kind === "dropoff" ? 4 : 2),
            updateTriggers: { getRadius: sel?.id, getFillColor: pins.length, getLineColor: pins.length },
          }),
          // Expanding rings where an alert just fired.
          new ScatterplotLayer<ZoneOverlay["alerts"][number]>({
            id: "alert-pulses",
            data: pulses,
            getPosition: (a) => [a.at.lon, a.at.lat],
            radiusUnits: "pixels",
            getRadius: (a) => 10 + (((now - a.t) % 1200) / 1200) * 40,
            stroked: true,
            filled: false,
            getLineColor: (a) => [...SEVERITY_RGB[a.severity], 255 * (1 - ((now - a.t) % 1200) / 1200)],
            lineWidthUnits: "pixels",
            getLineWidth: 3,
            updateTriggers: { getRadius: now, getLineColor: now },
          }),
        ],
        onClick: (info: PickingInfo) => {
          if (drawing) {
            if (zo.draftClosed || !info.coordinate) return;
            // Clicking near the first corner closes the outline.
            const first = draft[0];
            const p = first && mapRef.current?.project(first);
            if (p && draft.length >= 3 && Math.hypot(p.x - info.x, p.y - info.y) < 12) onCloseDraft();
            else onDrawPoint([info.coordinate[0], info.coordinate[1]]);
            return;
          }
          // While placing a job, every click sets a location, even on top of
          // a moving vehicle or another job's pin.
          if (jo.picking && info.coordinate) {
            onMapClick({ lon: info.coordinate[0], lat: info.coordinate[1] });
          } else if (info.layer?.id === "job-pins" && info.object && !(info.object as Pin).id.startsWith("draft")) {
            onSelectJob((info.object as Pin).id);
          } else if (info.layer?.id === "vehicles" && info.object) {
            onSelect((info.object as Vehicle).id);
          } else {
            onSelect(null);
          }
        },
        getCursor: ({ isHovering }) => (jo.picking || drawing ? "crosshair" : isHovering ? "pointer" : "grab"),
      });

      frames++;
      if (now - fpsStart >= 1000) {
        onFrame((frames * 1000) / (now - fpsStart));
        frames = 0;
        fpsStart = now;
      }
    };
    raf = requestAnimationFrame(loop);
    return () => cancelAnimationFrame(raf);
  }, [store, mapRef]);

  const emitViewport = () => {
    const b = mapRef.current?.getBounds();
    if (b) onViewportChange({ minLon: b.getWest(), minLat: b.getSouth(), maxLon: b.getEast(), maxLat: b.getNorth() });
  };

  return (
    <Map
      ref={mapRef}
      initialViewState={INITIAL_VIEW}
      mapStyle={MAP_STYLES[theme]}
      style={{ position: "absolute", inset: 0 }}
      attributionControl={{ compact: true }}
      onLoad={emitViewport}
      onMoveEnd={emitViewport}
      onDragStart={onUserPan}
      doubleClickZoom={!props.drawing}
    >
      <NavigationControl position="bottom-right" visualizePitch />
      <DeckOverlay onReady={(o) => (overlayRef.current = o)} />
    </Map>
  );
}
