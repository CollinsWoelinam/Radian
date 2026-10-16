"use client";

import { useEffect, useRef } from "react";
import { Map, NavigationControl, useControl, type MapRef } from "react-map-gl/maplibre";
import { MapboxOverlay } from "@deck.gl/mapbox";
import { setWorkerUrl } from "maplibre-gl";
import { IconLayer, PathLayer, ScatterplotLayer } from "@deck.gl/layers";
import type { PickingInfo } from "@deck.gl/core";
import "maplibre-gl/dist/maplibre-gl.css";

import type { FleetStore, Vehicle } from "@/lib/fleet-store";
import { VehicleStatus } from "@/gen/radian/telemetry/v1/telemetry_pb";
import type { Viewport } from "@/lib/fleet-socket";
import { INITIAL_VIEW, MAP_STYLES, statusInfo, type StatusKey, type Theme } from "@/lib/config";
import { STATUS_META, type Job, type JobDetail, type LatLon, type RouteLeg } from "@/lib/jobs";

/** Job-related things to draw over the fleet; read every frame. */
export type JobOverlay = {
  jobs: Job[];
  selectedJob: JobDetail | null;
  draft: { pickup?: LatLon; dropoff?: LatLon } | null;
  picking: boolean;
};

type RGB = [number, number, number];
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

    const loop = (now: number) => {
      raf = requestAnimationFrame(loop);
      const overlay = overlayRef.current;
      if (!overlay) return;
      const { hidden, selectedId, follow, onSelect, onFrame, theme: mapTheme, jobOverlay, onSelectJob, onMapClick } =
        live.current;
      const jo = jobOverlay.current;
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
        ],
        onClick: (info: PickingInfo) => {
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
        getCursor: ({ isHovering }) => (jo.picking ? "crosshair" : isHovering ? "pointer" : "grab"),
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
    >
      <NavigationControl position="bottom-right" visualizePitch />
      <DeckOverlay onReady={(o) => (overlayRef.current = o)} />
    </Map>
  );
}
