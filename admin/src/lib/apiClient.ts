// Defaults to localhost for `npm run dev`; set VITE_API_BASE_URL in a
// `.env.production` (or the deploy environment) to point a production
// build at the real backend.
const BASE_URL = import.meta.env.VITE_API_BASE_URL ?? 'http://localhost:4000';

/** Thrown for any non-2xx response; `message` is the backend's own
 * `{ "error": "..." }` text when available. Mirrors ApiException on the
 * Flutter side so both clients handle the same backend the same way. */
export class ApiError extends Error {
  status: number;
  /** The backend's optional machine-readable `code` (e.g.
   * 'ACCOUNT_DEACTIVATED') — see decode()'s own handling of that one. */
  code?: string;
  constructor(message: string, status: number, code?: string) {
    super(message);
    this.name = 'ApiError';
    this.status = status;
    this.code = code;
  }
}

/** Set once by AuthProvider — lets any request, anywhere, force an
 * immediate logout the moment the backend reports this admin's own
 * session has been deactivated mid-use (e.g. the Main Admin deactivated
 * them from another tab), the same "code" the Flutter apps' own
 * ApiClient.onAccountDeactivated reacts to. A JWT is otherwise stateless
 * and would keep working normally until it expired on its own. */
let deactivationHandler: (() => void) | null = null;

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
    const errorBody = body && typeof body === 'object' ? (body as { error?: unknown; code?: unknown }) : undefined;
    const message = typeof errorBody?.error === 'string' ? errorBody.error : 'Something went wrong.';
    const code = typeof errorBody?.code === 'string' ? errorBody.code : undefined;
    if (code === 'ACCOUNT_DEACTIVATED') deactivationHandler?.();
    throw new ApiError(message, response.status, code);
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

  /** Like [post], but for endpoints that take one or more files —
   * [files] maps each multipart field name to the File to send for it.
   * multipart/form-data is the only way to send binary files, so this
   * can't ride along as JSON the way [post]/[patch] do. Mirrors the
   * Flutter client's own ApiClient.uploadFiles for the same reason. */
  uploadFiles: async <T>(path: string, files: Record<string, File>): Promise<T> => {
    const formData = new FormData();
    for (const [field, file] of Object.entries(files)) formData.append(field, file);

    let response: Response;
    try {
      response = await fetch(`${BASE_URL}${path}`, {
        method: 'POST',
        headers: authHeaders(),
        body: formData,
      });
    } catch {
      throw new ApiError("Couldn't reach the server. Check your connection and that the backend is running.", 0);
    }
    return decode(response) as Promise<T>;
  },

  /** Resolves a relative path the backend returned (e.g. a `photoUrl`
   * like `/uploads/profile-photos/xyz.jpg`) into a URL an `<img>` can
   * load, using the same base URL as every other request. */
  resolveUrl: (path: string | null): string | null => {
    if (!path) return null;
    if (path.startsWith('http://') || path.startsWith('https://')) return path;
    return `${BASE_URL}${path}`;
  },

  /** Registers the one handler `decode()` calls on an ACCOUNT_DEACTIVATED
   * response — called once by AuthProvider. */
  onAccountDeactivated: (handler: () => void): void => {
    deactivationHandler = handler;
  },
};
