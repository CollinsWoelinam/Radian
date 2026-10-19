import { API_URL } from "./config";
import { ApiError } from "./auth";

/** Thin authenticated client for the Radian API. A 401 calls onUnauthorized. */
export class ApiClient {
  constructor(
    private token: string,
    private onUnauthorized: () => void,
  ) {}

  protected async req<T>(path: string, init?: RequestInit): Promise<T> {
    let res: Response;
    try {
      res = await fetch(`${API_URL}${path}`, {
        ...init,
        headers: { Authorization: `Bearer ${this.token}`, "Content-Type": "application/json", ...init?.headers },
      });
    } catch {
      throw new ApiError(0, "Can't reach the Radian API.");
    }
    if (res.status === 401) {
      this.onUnauthorized();
      throw new ApiError(401, "Your session has expired.");
    }
    if (res.status === 204) return undefined as T;
    const body = await res.json().catch(() => ({}));
    if (!res.ok) throw new ApiError(res.status, body.message ?? `Request failed (${res.status}).`);
    return body as T;
  }
}
