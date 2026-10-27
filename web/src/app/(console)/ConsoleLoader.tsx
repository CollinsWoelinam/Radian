"use client";

import { useSyncExternalStore } from "react";
import Console from "@/console/Console";

const noop = () => () => {};

// The console keeps its session in localStorage and draws WebGL maps, so it
// renders in the browser only; the server sends this placeholder.
export default function ConsoleLoader({ children }: { children: React.ReactNode }) {
  const inBrowser = useSyncExternalStore(
    noop,
    () => true,
    () => false,
  );
  if (!inBrowser) return <div className="grid h-dvh place-items-center bg-bg text-[13px] text-muted">Loading…</div>;
  return <Console>{children}</Console>;
}
