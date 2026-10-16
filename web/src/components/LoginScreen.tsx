"use client";

import { useState } from "react";
import { login, type DispatcherSession } from "@/lib/auth";

export default function LoginScreen({ onSignedIn }: { onSignedIn: (s: DispatcherSession) => void }) {
  const [email, setEmail] = useState("");
  const [password, setPassword] = useState("");
  const [error, setError] = useState<string | null>(null);
  const [busy, setBusy] = useState(false);

  return (
    <main className="grid min-h-dvh place-items-center bg-bg px-4 text-fg">
      <form
        className="panel w-full max-w-sm space-y-4 p-6"
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
        <div className="flex items-center gap-3">
          <svg width="40" height="40" viewBox="0 0 28 28" aria-hidden>
            <rect width="28" height="28" rx="7" className="fill-accent" />
            <circle cx="14" cy="14" r="3" fill="#fff" />
            <path d="M14 5a9 9 0 0 1 9 9" stroke="#fff" strokeWidth="2" fill="none" strokeLinecap="round" />
            <path d="M14 9a5 5 0 0 1 5 5" stroke="#fff" strokeWidth="2" fill="none" strokeLinecap="round" opacity=".7" />
          </svg>
          <div>
            <h1 className="text-lg font-semibold">Radian dispatch</h1>
            <p className="text-[12px] text-muted">Sign in to manage your fleet.</p>
          </div>
        </div>
        <label className="block">
          <span className="mb-1 block text-[12px] text-muted">Email</span>
          <input className="field" type="email" autoComplete="username" required value={email} onChange={(e) => setEmail(e.target.value)} />
        </label>
        <label className="block">
          <span className="mb-1 block text-[12px] text-muted">Password</span>
          <input className="field" type="password" autoComplete="current-password" required value={password} onChange={(e) => setPassword(e.target.value)} />
        </label>
        {error && <p className="text-[12px] text-red-500" role="alert">{error}</p>}
        <button className="btn-primary w-full py-2.5" disabled={busy}>
          {busy ? "Signing in…" : "Sign in"}
        </button>
        <p className="text-center text-[11px] text-muted">Demo: dispatch@radian.dev · radian-demo</p>
      </form>
    </main>
  );
}
