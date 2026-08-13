const BASE_URL = 'http://localhost:4000';

/** Thrown for any non-2xx response; `message` is the backend's own
 * `{ "error": "..." }` text when available. Mirrors ApiException on the
 * Flutter side so both clients handle the same backend the same way. */
export class ApiError extends Error {
  status: number;
  constructor(message: string, status: number) {
    super(message);
    this.name = 'ApiError';
    this.status = status;
  }
}

async function decode(response: Response): Promise<unknown> {
  const text = await response.text();
  let body: unknown = undefined;
  if (text) {
    try {
      body = JSON.parse(text);
    } catch {
      // Non-JSON body — fall through with body left undefined.
    }
  }

  if (!response.ok) {
    const message =
      (body && typeof body === 'object' && 'error' in body && typeof (body as { error: unknown }).error === 'string'
        ? (body as { error: string }).error
        : undefined) ?? 'Something went wrong.';
    throw new ApiError(message, response.status);
  }

  return body ?? {};
}

function authHeaders(): Record<string, string> {
  const token = localStorage.getItem('adminToken') ?? sessionStorage.getItem('adminToken');
  return token ? { Authorization: `Bearer ${token}` } : {};
}

async function request<T>(method: string, path: string, body?: unknown): Promise<T> {
  let response: Response;
  try {
    response = await fetch(`${BASE_URL}${path}`, {
      method,
      headers: {
        'Content-Type': 'application/json',
        ...authHeaders(),
      },
      body: body !== undefined ? JSON.stringify(body) : undefined,
    });
  } catch {
    throw new ApiError("Couldn't reach the server. Check your connection and that the backend is running.", 0);
  }
  return decode(response) as Promise<T>;
}

export const apiClient = {
  get: <T>(path: string) => request<T>('GET', path),
  post: <T>(path: string, body?: unknown) => request<T>('POST', path, body),
  patch: <T>(path: string, body?: unknown) => request<T>('PATCH', path, body),

  /** Resolves a relative path the backend returned (e.g. a `photoUrl`
   * like `/uploads/profile-photos/xyz.jpg`) into a URL an `<img>` can
   * load, using the same base URL as every other request. */
  resolveUrl: (path: string | null): string | null => {
    if (!path) return null;
    if (path.startsWith('http://') || path.startsWith('https://')) return path;
    return `${BASE_URL}${path}`;
  },
};
