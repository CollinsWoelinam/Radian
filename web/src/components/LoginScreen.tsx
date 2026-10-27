"use client";

import { useEffect, useState } from "react";
import { RadianMark, Wordmark } from "./Brand";
import { login, type DispatcherSession } from "@/lib/auth";

export default function LoginScreen({ onSignedIn }: { onSignedIn: (s: DispatcherSession) => void }) {
  const [email, setEmail] = useState("");
  const [password, setPassword] = useState("");
  const [error, setError] = useState<string | null>(null);
  const [busy, setBusy] = useState(false);

  // Signed out, follow the saved or system theme (the console has a toggle).
  useEffect(() => {
    let theme = window.matchMedia("(prefers-color-scheme: light)").matches ? "light" : "dark";
    try {
      theme = localStorage.getItem("radian:theme") ?? theme;
    } catch {}
    document.documentElement.dataset.theme = theme;
  }, []);

  return (
    <main className="flex min-h-dvh flex-wrap bg-bg text-fg">
      {/* Brand panel: always Night Ink, like the driver app. */}
      <section className="relative flex min-h-[420px] flex-[1_1_520px] flex-col justify-between overflow-hidden bg-ink p-8 text-[#f3f6fa] md:p-12">
        <svg className="pointer-events-none absolute inset-0 size-full" viewBox="0 0 800 900" preserveAspectRatio="xMidYMid slice" aria-hidden>
          {[150, 270, 390, 510, 630].map((r, i) => (
            <circle key={r} cx="170" cy="620" r={r} fill="none" stroke="#4F8BFF" strokeOpacity={0.13 - i * 0.02} />
          ))}
          <path d="M170 620 L800 620 A630 630 0 0 0 510.4 90.1 Z" fill="#4F8BFF" fillOpacity="0.06" />
          <circle cx="510.4" cy="90.1" r="28" fill="#F59E0B" fillOpacity="0.15" />
          <circle cx="510.4" cy="90.1" r="12" fill="#F59E0B" />
        </svg>
        <div className="relative flex items-center gap-3">
          <RadianMark size={40} color="#4F8BFF" ground="#0B1220" />
          <Wordmark className="text-[26px]" />
        </div>
        <div className="relative max-w-[460px] py-10">
          <h1 className="text-[34px] font-semibold leading-[1.08] tracking-[-0.03em] md:text-[44px]">Every vehicle, live. The nearest driver, every time.</h1>
          <p className="mt-4 text-[16px] leading-relaxed text-[#9aa6b8]">Real-time telemetry, dispatch by road drive time, and zone alerts for your fleet.</p>
        </div>
        <p className="relative font-mono text-[12px] text-[#9aa6b8]">Accra · 5.6037° N, 0.1870° W</p>
      </section>

      <section className="flex flex-[1_1_420px] items-center justify-center px-6 py-10">
        <form
          className="flex w-full max-w-[380px] flex-col gap-[18px]"
          onSubmit={async (e) => {
            e.preventDefault();
            setBusy(true);
            setError(null);
            try {
              onSignedIn(await login(email, password));
            } catch (err) {
              setError(err instanceof Error ? err.message : "Sign-in failed.");
            } finally {
              setBusy(false);
            }
          }}
        >
          <div>
            <h2 className="text-[28px] font-semibold tracking-[-0.02em]">Welcome back</h2>
            <p className="mt-1.5 text-[14px] text-muted">Sign in to the dispatch console.</p>
          </div>
          <label className="flex flex-col gap-1.5 text-[13px] font-medium">
            Work email
            <input className="field h-[46px] rounded-xl text-[15px]" type="email" autoComplete="username" required value={email} onChange={(e) => setEmail(e.target.value)} />
          </label>
          <label className="flex flex-col gap-1.5 text-[13px] font-medium">
            Password
            <input className="field h-[46px] rounded-xl text-[15px]" type="password" autoComplete="current-password" required value={password} onChange={(e) => setPassword(e.target.value)} />
          </label>
          {error && (
            <p className="rounded-lg bg-red-500/10 px-3 py-2 text-[13px] text-red-600 dark:text-red-400" role="alert">
              {error}
            </p>
          )}
          <button className="btn-primary h-12 rounded-xl text-[15px]" disabled={busy}>
            {busy ? "Signing in…" : "Sign in"}
          </button>
          <p className="text-center text-[12px] text-muted">
            Drivers sign in on the Radian Driver app.
            <br />
            <span className="font-mono">Demo: dispatch@radian.dev · radian-demo</span>
          </p>
        </form>
      </section>
    </main>
  );
}
