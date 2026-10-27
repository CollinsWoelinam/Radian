"use client";

import Link from "next/link";
import { useRouter, useSearchParams } from "next/navigation";
import { useCallback, useEffect, useRef, useState } from "react";
import type { MapRef } from "react-map-gl/maplibre";

import { ago } from "@/lib/console";
import { ZONE_KINDS, defaultRules, severity, verb, zoneKind, type AlertRules, type Zone, type ZoneKind } from "@/lib/geofences";
import { useConsole } from "../ConsoleContext";
import { FleetMap, noJobs, useZoneOverlay } from "../maps";
import { Empty, Icon, PageHeader } from "../ui";

const DWELL_OPTIONS = [null, 120, 300, 600, 900, 1800, 3600];
const dwellLabel = (s: number | null) => (s == null ? "Off" : s < 3600 ? `${s / 60} min` : `${s / 3600} h`);

function formatArea(km2: number) {
  if (km2 >= 10) return `${Math.round(km2).toLocaleString()} km²`;
  if (km2 >= 1) return `${km2.toFixed(1)} km²`;
  return `${Math.round(km2 * 100)} ha`;
}

export default function ZonesPage() {
  const { store, theme, setViewport, zones, setZones, refreshZones, zonesApi, zoneEvents, setZoneEvents } = useConsole();
  const router = useRouter();
  const params = useSearchParams();
  const mapRef = useRef<MapRef | null>(null);
  const selectedId = params.get("zone");
  const drawing = params.get("draw") === "1";
  const [outline, setOutline] = useState<[number, number][]>([]);
  const [closed, setClosed] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const selected = zones.find((z) => z.id === selectedId) ?? null;
  const zoneOverlay = useZoneOverlay({ highlightId: selectedId, draft: drawing ? outline : null, draftClosed: closed });
  const jobOverlay = useRef(noJobs);

  const go = useCallback((q: string) => router.replace(`/zones${q}`), [router]);

  const fit = useCallback((z: Zone) => {
    const pts = z.area.flat(2);
    const lons = pts.map((p) => p[0]);
    const lats = pts.map((p) => p[1]);
    mapRef.current?.fitBounds(
      [
        [Math.min(...lons), Math.min(...lats)],
        [Math.max(...lons), Math.max(...lats)],
      ],
      { padding: 60, maxZoom: 16, duration: 700 },
    );
  }, []);

  // Fly to a zone picked from the palette or the list.
  const lastFit = useRef<string | null>(null);
  useEffect(() => {
    if (selected && lastFit.current !== selected.id) {
      const t = setTimeout(() => fit(selected), 300);
      lastFit.current = selected.id;
      return () => clearTimeout(t);
    }
  }, [selected, fit]);

  const startDraw = () => {
    setOutline([]);
    setClosed(false);
    setError(null);
    go("?draw=1");
  };

  return (
    <>
      <PageHeader title="Zones" subtitle="Depots, service areas and restricted areas, with the alerts they raise">
        {!drawing && (
          <button type="button" onClick={startDraw} className="btn-primary inline-flex h-10 items-center gap-2 rounded-[10px] px-4 text-[14px]">
            <Icon.Plus /> Draw zone
          </button>
        )}
      </PageHeader>
      <div className="flex grow flex-wrap">
        <section aria-label="Zone list" className="flex max-w-full flex-[1_1_300px] flex-col gap-1.5 border-r border-line bg-surface p-4">
          {zones.length === 0 && <Empty>No zones yet. Draw one to get alerts when vehicles enter or leave it.</Empty>}
          <ul className="flex flex-col gap-1.5">
            {zones.map((z) => {
              const k = zoneKind(z.kind);
              const on = z.id === selectedId;
              return (
                <li key={z.id}>
                  <button
                    type="button"
                    aria-current={on ? "true" : undefined}
                    onClick={() => go(on ? "" : `?zone=${z.id}`)}
                    className={`flex w-full items-center gap-3 rounded-xl border p-3 text-left ${on ? "border-current bg-hover" : "border-transparent hover:bg-hover"}`}
                    style={on ? { color: `rgb(${k.rgb.join(",")})` } : undefined}
                  >
                    <span className="size-3 shrink-0 rounded-[3px]" style={{ background: `rgb(${k.rgb.join(",")})` }} />
                    <span className="min-w-0 grow text-fg">
                      <span className="block truncate text-[14px] font-semibold">{z.name}</span>
                      <span className="text-[12px] text-muted">
                        {k.label} · {formatArea(z.area_km2)}
                      </span>
                    </span>
                    <span className="text-right text-fg" title="Vehicles inside now">
                      <span className="block font-mono text-[15px] font-semibold">{z.vehicles_inside.toLocaleString()}</span>
                      <span className="block text-[10px] text-muted">inside</span>
                    </span>
                  </button>
                </li>
              );
            })}
          </ul>
        </section>

        <section aria-label="Zone map" className="relative min-h-[520px] min-w-0 flex-[999_1_420px] overflow-hidden">
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
            onMapClick={() => {}}
            zoneOverlay={zoneOverlay}
            drawing={drawing}
            onDrawPoint={(p) => setOutline((o) => [...o, p])}
            onCloseDraft={() => setClosed(true)}
          />
          {drawing && !closed && (
            <div className="panel pointer-events-none absolute left-1/2 top-4 z-10 -translate-x-1/2 px-4 py-2.5 text-[13px] font-semibold">
              {outline.length < 3 ? `Click to add corners · ${outline.length} of at least 3` : "Click the first corner to close the outline"}
            </div>
          )}
        </section>

        <aside aria-label={drawing ? "New zone" : "Zone details"} className="flex max-w-full flex-[1_1_330px] flex-col gap-4 border-l border-line bg-surface p-5">
          {drawing ? (
            <DrawForm
              corners={outline.length}
              closed={closed}
              error={error}
              onUndo={() => (closed ? setClosed(false) : setOutline((o) => o.slice(0, -1)))}
              onClose={() => setClosed(true)}
              onCancel={() => go("")}
              onSave={async (name, kind, rules) => {
                setError(null);
                try {
                  const z = await zonesApi.create({ name, kind, polygon: outline, rules });
                  setZones((prev) => [...prev.filter((x) => x.id !== z.id), z]);
                  refreshZones();
                  go(`?zone=${z.id}`);
                } catch (e) {
                  setError(e instanceof Error ? e.message : "Couldn't save the zone.");
                }
              }}
            />
          ) : selected ? (
            <ZoneDetail
              key={selected.id}
              zone={selected}
              events={zoneEvents.filter((e) => e.geofence_id === selected.id).slice(0, 12)}
              onRules={async (rules) => {
                const z = await zonesApi.setRules(selected.id, rules);
                setZones((prev) => prev.map((x) => (x.id === z.id ? z : x)));
              }}
              onDelete={async () => {
                await zonesApi.remove(selected.id);
                setZones((prev) => prev.filter((x) => x.id !== selected.id));
                setZoneEvents((prev) => prev.filter((e) => e.geofence_id !== selected.id));
                go("");
              }}
            />
          ) : (
            <>
              <h2 className="text-[15px] font-semibold">Recent activity</h2>
              {zoneEvents.length === 0 && <Empty>No crossings yet.</Empty>}
              <ol className="flex flex-col gap-2.5">
                {zoneEvents.slice(0, 30).map((e) => {
                  const sev = severity(e);
                  return (
                    <li key={e.id} className="flex gap-2.5 text-[13px]">
                      <span className={`mt-1.5 size-2 shrink-0 rounded-full ${sev === "critical" ? "bg-red-500" : sev === "warning" ? "bg-amber-500" : "bg-slate-400"}`} />
                      <span className="min-w-0 grow">
                        <Link href={`/vehicles/${e.vehicle_id}`} className="font-mono font-semibold">
                          {e.license_plate}
                        </Link>{" "}
                        {verb(e)} {e.geofence_name}
                      </span>
                      <span className="shrink-0 text-[12px] text-muted">{ago(e.occurred_at)}</span>
                    </li>
                  );
                })}
              </ol>
            </>
          )}
        </aside>
      </div>
    </>
  );
}

function Toggle({ label, checked, onChange }: { label: string; checked: boolean; onChange: (v: boolean) => void }) {
  return (
    <div className="flex items-center gap-3 px-3.5 py-3">
      <span className="grow text-[14px]">{label}</span>
      <button type="button" role="switch" aria-checked={checked} aria-label={label} onClick={() => onChange(!checked)} className={`relative h-[26px] w-11 shrink-0 rounded-full transition-colors ${checked ? "bg-accent" : "bg-slate-400/50"}`}>
        <span className={`absolute top-[3px] size-5 rounded-full bg-white shadow transition-all ${checked ? "left-[21px]" : "left-[3px]"}`} />
      </button>
    </div>
  );
}

function RulesEditor({ rules, onChange }: { rules: AlertRules; onChange: (r: AlertRules) => void }) {
  return (
    <div>
      <h3 className="mb-2 text-[12px] font-semibold uppercase tracking-wider text-muted">Alert me when</h3>
      <div className="divide-y divide-line overflow-hidden rounded-xl border border-line">
        <Toggle label="A vehicle enters" checked={rules.alert_on_enter} onChange={(v) => onChange({ ...rules, alert_on_enter: v })} />
        <Toggle label="A vehicle leaves" checked={rules.alert_on_exit} onChange={(v) => onChange({ ...rules, alert_on_exit: v })} />
        <label className="flex items-center gap-3 px-3.5 py-3">
          <span className="grow text-[14px]">It stays longer than</span>
          <select
            value={rules.dwell_alert_s ?? ""}
            onChange={(e) => onChange({ ...rules, dwell_alert_s: e.target.value ? Number(e.target.value) : null })}
            className="field h-9 w-28 rounded-lg font-mono"
          >
            {DWELL_OPTIONS.map((s) => (
              <option key={s ?? "off"} value={s ?? ""}>
                {dwellLabel(s)}
              </option>
            ))}
          </select>
        </label>
      </div>
    </div>
  );
}

function ZoneDetail({ zone, events, onRules, onDelete }: { zone: Zone; events: import("@/lib/geofences").ZoneEvent[]; onRules: (r: AlertRules) => Promise<void>; onDelete: () => Promise<void> }) {
  const k = zoneKind(zone.kind);
  const [rules, setRules] = useState<AlertRules>({ alert_on_enter: zone.alert_on_enter, alert_on_exit: zone.alert_on_exit, dwell_alert_s: zone.dwell_alert_s });
  const [saving, setSaving] = useState<"idle" | "saving" | "saved" | "error">("idle");
  const [confirm, setConfirm] = useState(false);
  const corners = Math.max(0, (zone.area[0]?.[0]?.length ?? 1) - 1);

  const change = async (r: AlertRules) => {
    setRules(r);
    setSaving("saving");
    try {
      await onRules(r);
      setSaving("saved");
    } catch {
      setSaving("error");
    }
  };

  return (
    <>
      <div>
        <div className="flex items-center gap-2">
          <span className="size-3 rounded-[3px]" style={{ background: `rgb(${k.rgb.join(",")})` }} />
          <h2 className="text-[18px] font-semibold">{zone.name}</h2>
        </div>
        <p className="mt-0.5 text-[13px] text-muted">
          {k.label} · {formatArea(zone.area_km2)} · {corners} corners
        </p>
      </div>
      <dl className="grid grid-cols-2 gap-2.5">
        <div className="rounded-xl border border-line p-3">
          <dt className="text-[11px] uppercase tracking-wider text-muted">Inside now</dt>
          <dd className="mt-1 font-mono text-[20px] font-semibold">{zone.vehicles_inside.toLocaleString()}</dd>
        </div>
        <div className="rounded-xl border border-line p-3">
          <dt className="text-[11px] uppercase tracking-wider text-muted">Crossings</dt>
          <dd className="mt-1 font-mono text-[20px] font-semibold">{events.length}</dd>
        </div>
      </dl>
      <RulesEditor rules={rules} onChange={change} />
      <p className="-mt-2 text-[12px] text-muted" aria-live="polite">
        {saving === "saving" ? "Saving…" : saving === "saved" ? "Saved. Applies to new crossings within a few seconds." : saving === "error" ? "Couldn't save. Try again." : "Alerts show as a toast and in Needs attention."}
      </p>
      <div>
        <h3 className="mb-2 text-[12px] font-semibold uppercase tracking-wider text-muted">Recent crossings</h3>
        {events.length === 0 ? (
          <p className="text-[13px] text-muted">None yet.</p>
        ) : (
          <ol className="flex flex-col gap-2.5 text-[13px]">
            {events.map((e) => (
              <li key={e.id} className="flex gap-2.5">
                <span className={`mt-1.5 size-2 shrink-0 rounded-full ${e.alert ? (zone.kind === "RESTRICTED" ? "bg-red-500" : "bg-amber-500") : "bg-slate-400"}`} />
                <span className="grow">
                  <Link href={`/vehicles/${e.vehicle_id}`} className="font-mono font-semibold">
                    {e.license_plate}
                  </Link>{" "}
                  {verb(e)}
                </span>
                <span className="text-[12px] text-muted">{ago(e.occurred_at)}</span>
              </li>
            ))}
          </ol>
        )}
      </div>
      <span className="grow" />
      {confirm ? (
        <div className="flex items-center gap-2">
          <span className="grow text-[13px]">Delete this zone and its history?</span>
          <button type="button" className="btn-danger h-9 rounded-lg" onClick={() => onDelete()}>
            Delete
          </button>
          <button type="button" className="btn-secondary h-9 rounded-lg" onClick={() => setConfirm(false)}>
            Keep
          </button>
        </div>
      ) : (
        <button type="button" onClick={() => setConfirm(true)} className="inline-flex items-center gap-2 self-start text-[13px] font-semibold text-red-600 dark:text-red-400">
          <Icon.Trash /> Delete zone
        </button>
      )}
    </>
  );
}

function DrawForm({ corners, closed, error, onUndo, onClose, onCancel, onSave }: { corners: number; closed: boolean; error: string | null; onUndo: () => void; onClose: () => void; onCancel: () => void; onSave: (name: string, kind: ZoneKind, rules: AlertRules) => Promise<void> }) {
  const [name, setName] = useState("");
  const [kind, setKind] = useState<ZoneKind>("DEPOT");
  const [rules, setRules] = useState<AlertRules>(defaultRules("DEPOT"));
  const [busy, setBusy] = useState(false);
  return (
    <form
      className="flex flex-col gap-4"
      onSubmit={async (e) => {
        e.preventDefault();
        setBusy(true);
        await onSave(name.trim(), kind, rules);
        setBusy(false);
      }}
    >
      <div className="flex items-center justify-between">
        <h2 className="text-[18px] font-semibold">New zone</h2>
        <button type="button" onClick={onCancel} className="text-[13px] text-muted hover:text-fg">
          Cancel
        </button>
      </div>
      <div className="rounded-xl border border-line bg-sunken p-3 text-[13px]" aria-live="polite">
        {closed ? (
          <p>
            <b className="text-emerald-600 dark:text-emerald-400">Outline complete</b> · {corners} corners
          </p>
        ) : (
          <p>
            <b>Click the map to add corners.</b> <span className="text-muted">{corners < 3 ? `${corners} of at least 3.` : "Click the first corner, or Finish."}</span>
          </p>
        )}
        <div className="mt-2 flex gap-2">
          <button type="button" className="btn-secondary" disabled={corners === 0} onClick={onUndo}>
            {closed ? "Reopen" : "Undo corner"}
          </button>
          {!closed && (
            <button type="button" className="btn-secondary" disabled={corners < 3} onClick={onClose}>
              Finish outline
            </button>
          )}
        </div>
      </div>
      <label className="flex flex-col gap-1.5 text-[12px] font-semibold uppercase tracking-wider text-muted">
        Name
        <input className="field h-11 rounded-xl text-[14px] normal-case tracking-normal text-fg" value={name} onChange={(e) => setName(e.target.value)} placeholder="e.g. Tema Harbour Depot" maxLength={100} />
      </label>
      <div role="radiogroup" aria-labelledby="kind-label">
        <span id="kind-label" className="mb-1.5 block text-[12px] font-semibold uppercase tracking-wider text-muted">
          Type
        </span>
        <div className="flex flex-col gap-1.5">
          {ZONE_KINDS.map((k) => (
            <button
              type="button"
              role="radio"
              aria-checked={kind === k.value}
              key={k.value}
              onClick={() => {
                setKind(k.value);
                setRules(defaultRules(k.value));
              }}
              className={`flex items-center gap-2.5 rounded-xl border px-3 py-2 text-left ${kind === k.value ? "border-accent bg-accent/10" : "border-line hover:bg-hover"}`}
            >
              <span className="size-3 rounded-[3px]" style={{ background: `rgb(${k.rgb.join(",")})` }} />
              <span>
                <span className="block text-[13px] font-semibold">{k.label}</span>
                <span className="block text-[12px] text-muted">{k.hint}</span>
              </span>
            </button>
          ))}
        </div>
      </div>
      <RulesEditor rules={rules} onChange={setRules} />
      {error && <p className="rounded-lg bg-red-500/10 px-3 py-2 text-[13px] text-red-600 dark:text-red-400">{error}</p>}
      <button type="submit" disabled={busy || !closed || !name.trim()} className="btn-primary h-11 rounded-xl text-[14px]">
        {busy ? "Saving…" : "Save zone"}
      </button>
    </form>
  );
}
