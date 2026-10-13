"use client";

import dynamic from "next/dynamic";

// MapLibre and deck.gl need WebGL and window; render them only in the browser.
const Dashboard = dynamic(() => import("./Dashboard"), {
  ssr: false,
  loading: () => (
    <div className="grid h-dvh place-items-center bg-bg text-[13px] text-muted">Loading fleet map…</div>
  ),
});

export default function DashboardLoader() {
  return <Dashboard />;
}
