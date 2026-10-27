"use client";

import Link from "next/link";
import { useEffect, useMemo, useState } from "react";

import { ago } from "@/lib/console";
import { statusInfo } from "@/lib/config";
import { useConsole } from "../ConsoleContext";
import { Empty, Icon, PageHeader } from "../ui";

const KINDS: Record<string, string> = { CAR: "Car", MOTORBIKE: "Motorbike", VAN: "Van", TRUCK: "Truck", AMBULANCE: "Ambulance" };
const PAGE = 100;

export default function VehiclesPage() {
  const { registry, store } = useConsole();
  const [q, setQ] = useState("");
  const [shown, setShown] = useState(PAGE);
  const [, setTick] = useState(0);
  useEffect(() => {
    const t = setInterval(() => setTick((x) => x + 1), 2000);
    return () => clearInterval(t);
  }, []);

  // Vehicles on the map first, most recently heard from first.
  const rows = useMemo(() => {
    const query = q.trim().toUpperCase();
    return [...registry.values()]
      .filter((v) => !query || v.license_plate.toUpperCase().includes(query))
      .map((v) => ({ v, live: store.get(v.id) }))
      .sort((a, b) => (b.live?.recordedAtMs ?? 0) - (a.live?.recordedAtMs ?? 0) || a.v.license_plate.localeCompare(b.v.license_plate));
    // store changes outside React; the tick above re-sorts every 2 s.
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [registry, store, q, store.list.length]);

  return (
    <>
      <PageHeader title="Vehicles" subtitle={`${registry.size.toLocaleString()} registered`}>
        <label className="flex h-10 min-w-0 flex-[0_1_300px] items-center gap-2 rounded-[10px] border border-line bg-input px-3">
          <Icon.Search />
          <span className="sr-only">Find a vehicle</span>
          <input value={q} onChange={(e) => (setQ(e.target.value), setShown(PAGE))} placeholder="Find by plate" className="min-w-0 grow bg-transparent text-[13px] outline-none placeholder:text-muted" />
        </label>
      </PageHeader>
      <div className="overflow-x-auto p-5">
        {rows.length === 0 ? (
          <Empty>No vehicles match.</Empty>
        ) : (
          <table className="w-full min-w-[640px] border-separate border-spacing-0 text-left text-[13px]">
            <thead className="text-[11px] uppercase tracking-wider text-muted">
              <tr>
                {["Plate", "Type", "Status", "Speed", "Last fix", ""].map((h) => (
                  <th key={h} className="border-b border-line px-3 py-2 font-semibold">
                    {h}
                  </th>
                ))}
              </tr>
            </thead>
            <tbody>
              {rows.slice(0, shown).map(({ v, live }) => (
                <tr key={v.id} className="hover:bg-hover">
                  <td className="border-b border-line px-3 py-2.5 font-mono font-semibold">{v.license_plate}</td>
                  <td className="border-b border-line px-3 py-2.5">{KINDS[v.kind] ?? v.kind}</td>
                  <td className="border-b border-line px-3 py-2.5">
                    {live ? (
                      <span className="inline-flex items-center gap-2">
                        <span className="size-2 rounded-full" style={{ background: `rgb(${statusInfo(live.status).rgb.join(",")})` }} />
                        {statusInfo(live.status).label}
                      </span>
                    ) : (
                      <span className="text-muted">Not in view</span>
                    )}
                  </td>
                  <td className="border-b border-line px-3 py-2.5 font-mono">{live ? `${Math.round(live.speedKmh)} km/h` : "—"}</td>
                  <td className="border-b border-line px-3 py-2.5 text-muted">{live ? ago(new Date(live.recordedAtMs).toISOString()) : "—"}</td>
                  <td className="border-b border-line px-3 py-2.5 text-right">
                    <Link href={`/vehicles/${v.id}`} className="font-semibold text-accent-fg">
                      Trip replay
                    </Link>
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
        )}
        {rows.length > shown && (
          <button type="button" onClick={() => setShown((s) => s + PAGE)} className="btn-secondary mt-4">
            Show {Math.min(PAGE, rows.length - shown)} more of {(rows.length - shown).toLocaleString()}
          </button>
        )}
      </div>
    </>
  );
}
