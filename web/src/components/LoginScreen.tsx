"use client";

import { useState } from "react";
import { RadianMark, Wordmark } from "./Brand";
import { login, type DispatcherSession } from "@/lib/auth";

export default function LoginScreen({ onSignedIn }: { onSignedIn: (s: DispatcherSession) => void }) {
  const [email, setEmail] = useState("");
  const [password, setPassword] = useState("");
  const [error, setError] = useState<string | null>(null);
  const [busy, setBusy] = useState(false);

  return (
    <main className="grid min-h-dvh bg-bg text-fg md:grid-cols-[minmax(0,1.1fr)_minmax(0,1fr)]">
      {/* Brand panel: always Night Ink, like the driver app's splash. */}
      <section className="relative flex min-h-64 flex-col justify-between overflow-hidden bg-ink px-6 py-8 text-[#f3f6fa] md:min-h-dvh md:px-12 md:py-12">
        <svg className="pointer-events-none absolute inset-0 size-full" aria-hidden>
          {[140, 250, 360, 470, 580, 690].map((r, i) => (
            <circle key={r} cx="22%" cy="62%" r={r} fill="none" stroke="#4F8BFF" strokeOpacity={0.12 - i * 0.016} />
          ))}
        </svg>
        <p className="relative font-mono text-[12px] uppercase tracking-[0.3em] text-[#9aa6b8]">Dispatch</p>
        <div className="relative flex flex-col items-start gap-4">
          <RadianMark size={120} color="#4F8BFF" ground="#0B1220" />
          <Wordmark className="text-6xl leading-none md:text-7xl" />
          <p className="max-w-sm text-[15px] leading-relaxed text-[#9aa6b8]">Live fleet telemetry &amp; dispatch. See every vehicle, send the nearest driver.</p>
        </div>
        <p className="relative hidden font-mono text-[12px] text-[#9aa6b8] md:block">Accra · 5.6037° N, 0.1870° W</p>
      </section>

      <section className="grid place-items-center px-4 py-10">
        <form
          className="w-full max-w-sm space-y-5"
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
            <h1 className="text-2xl font-semibold tracking-tight">Sign in to Radian</h1>
            <p className="mt-1 text-[13px] text-muted">Manage your fleet, jobs and zones.</p>
          </div>
          <label className="block">
            <span className="mb-1.5 block text-[12px] font-medium text-muted">Email</span>
            <input className="field py-2.5" type="email" autoComplete="username" required value={email} onChange={(e) => setEmail(e.target.value)} />
          </label>
          <label className="block">
            <span className="mb-1.5 block text-[12px] font-medium text-muted">Password</span>
            <input className="field py-2.5" type="password" autoComplete="current-password" required value={password} onChange={(e) => setPassword(e.target.value)} />
          </label>
          {error && <p className="text-[12px] text-red-500" role="alert">{error}</p>}
          <button className="btn-primary w-full py-3 text-[14px]" disabled={busy}>
            {busy ? "Signing in…" : "Sign in"}
          </button>
          <p className="text-center font-mono text-[11px] text-muted">Demo: dispatch@radian.dev · radian-demo</p>
        </form>
      </section>
    </main>
  );
}
