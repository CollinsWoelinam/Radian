"use client";

import Link from "next/link";
import { usePathname, useRouter } from "next/navigation";
import { useCallback, useState } from "react";

import LoginScreen from "@/components/LoginScreen";
import { RadianMark } from "@/components/Brand";
import { clearSession, loadSession, type DispatcherSession } from "@/lib/auth";
import { describe } from "@/lib/geofences";
import CommandPalette from "./CommandPalette";
import { ConsoleProvider, useConsole } from "./ConsoleContext";
import { Icon } from "./ui";

/** Signs the dispatcher in, then shows the console around the current page. */
export default function Console({ children }: { children: React.ReactNode }) {
  const [session, setSession] = useState<DispatcherSession | null>(loadSession);
  const signOut = useCallback(() => {
    clearSession();
    setSession(null);
  }, []);
  if (!session) return <LoginScreen onSignedIn={setSession} />;
  return (
    <ConsoleProvider session={session} onSignOut={signOut}>
      <div className="flex min-h-dvh flex-wrap bg-bg text-fg sm:flex-nowrap">
        <NavRail />
        <main className="flex min-h-dvh min-w-0 flex-[999_1_640px] flex-col">{children}</main>
      </div>
      <Toasts />
      <CommandPalette />
    </ConsoleProvider>
  );
}

const NAV = [
  { href: "/", label: "Live map", icon: Icon.Map, match: (p: string) => p === "/" },
  { href: "/jobs", label: "Jobs", icon: Icon.Jobs, match: (p: string) => p.startsWith("/jobs") },
  { href: "/zones", label: "Zones", icon: Icon.Zone, match: (p: string) => p.startsWith("/zones") },
  { href: "/vehicles", label: "Vehicles", icon: Icon.Van, match: (p: string) => p.startsWith("/vehicles") },
];

function NavRail() {
  const path = usePathname();
  const { theme, setTheme, session, signOut } = useConsole();
  const initials = session.dispatcher.full_name
    .split(/\s+/)
    .map((w) => w[0])
    .join("")
    .slice(0, 2)
    .toUpperCase();
  return (
    <nav
      aria-label="Main"
      className="flex w-full shrink-0 items-center gap-1.5 border-b border-line bg-sunken px-3 py-2 sm:sticky sm:top-0 sm:h-dvh sm:w-[72px] sm:flex-col sm:border-b-0 sm:border-r sm:px-0 sm:py-[18px]"
    >
      <Link href="/" aria-label="Radian home" className="mr-2 sm:mb-3.5 sm:mr-0">
        <RadianMark size={36} ground="var(--sunken)" />
      </Link>
      {NAV.map(({ href, label, icon: I, match }) => {
        const on = match(path);
        return (
          <Link
            key={href}
            href={href}
            aria-label={label}
            title={label}
            aria-current={on ? "page" : undefined}
            className={`grid size-11 place-items-center rounded-xl transition-colors ${on ? "bg-rail-active text-fg" : "text-muted hover:bg-hover hover:text-fg"}`}
          >
            <I />
          </Link>
        );
      })}
      <span className="grow" />
      <button
        type="button"
        className="grid size-11 place-items-center rounded-xl text-muted hover:bg-hover hover:text-fg"
        aria-label={`Switch to ${theme === "dark" ? "light" : "dark"} theme`}
        title={`Switch to ${theme === "dark" ? "light" : "dark"} theme`}
        onClick={() => setTheme(theme === "dark" ? "light" : "dark")}
      >
        {theme === "dark" ? <Icon.Sun /> : <Icon.Moon />}
      </button>
      <button
        type="button"
        className="grid size-11 place-items-center rounded-xl text-muted hover:bg-hover hover:text-fg"
        aria-label={`Sign out ${session.dispatcher.full_name}`}
        title={`Sign out ${session.dispatcher.full_name}`}
        onClick={signOut}
      >
        <Icon.Logout />
      </button>
      <span className="ml-1 grid size-9 place-items-center rounded-full bg-accent text-[13px] font-semibold text-white sm:ml-0 sm:mt-1" title={session.dispatcher.full_name}>
        {initials}
      </span>
    </nav>
  );
}

function Toasts() {
  const { toasts, dismissToast, store } = useConsole();
  const router = useRouter();
  return (
    <ol className="pointer-events-none fixed inset-x-2 top-2 z-50 flex flex-col items-center gap-2 sm:top-4" aria-live="assertive">
      {toasts.map((t) => (
        <li key={t.key} className="pointer-events-auto w-full max-w-md">
          <button
            type="button"
            className={`panel flex w-full items-start gap-3 p-3 text-left ${t.severity === "critical" ? "ring-1 ring-red-500/60" : "ring-1 ring-amber-500/60"}`}
            onClick={() => {
              dismissToast(t.key);
              if (store.get(t.event.vehicle_id)) router.push(`/?vehicle=${t.event.vehicle_id}`);
              else router.push(`/vehicles/${t.event.vehicle_id}`);
            }}
          >
            <span className={`grid size-9 shrink-0 place-items-center rounded-[10px] ${t.severity === "critical" ? "bg-red-500/15 text-red-500" : "bg-amber-500/15 text-amber-500"}`}>
              <Icon.Alert />
            </span>
            <span className="min-w-0 flex-1 text-[13px]">
              <b>{describe(t.event)}</b>
              <span className="block text-[12px] text-muted">Click to show the vehicle</span>
            </span>
          </button>
        </li>
      ))}
    </ol>
  );
}
