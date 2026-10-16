import { API_URL } from "./config";

export type DispatcherSession = {
  token: string;
  expiresAt: string;
  dispatcher: { id: string; full_name: string; email: string };
};

const KEY = "radian:dispatcher";

export class ApiError extends Error {
  constructor(
    public status: number,
    message: string,
  ) {
    super(message);
  }
}

export function loadSession(): DispatcherSession | null {
  try {
    const raw = localStorage.getItem(KEY);
    if (!raw) return null;
    const s = JSON.parse(raw) as DispatcherSession;
    return new Date(s.expiresAt).getTime() > Date.now() ? s : null;
  } catch {
    return null;
  }
}

export function clearSession() {
  try {
    localStorage.removeItem(KEY);
  } catch {}
}

export async function login(email: string, password: string): Promise<DispatcherSession> {
  let res: Response;
  try {
    res = await fetch(`${API_URL}/v1/auth/dispatcher/login`, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ email, password }),
    });
  } catch {
    throw new ApiError(0, "Can't reach the Radian API. Check that it's running.");
  }
  const body = await res.json().catch(() => ({}));
  if (!res.ok) throw new ApiError(res.status, body.message ?? `Sign-in failed (${res.status}).`);
  const session: DispatcherSession = { token: body.token, expiresAt: body.expires_at, dispatcher: body.dispatcher };
  try {
    localStorage.setItem(KEY, JSON.stringify(session));
  } catch {}
  return session;
}
