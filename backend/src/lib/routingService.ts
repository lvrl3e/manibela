/**
 * Real driving-route distance/duration via OSRM's free, keyless public
 * demo server — no paid Mapbox Directions API, no API key. Confirmed
 * working for Metro Manila directly (returns real street-following
 * distance/duration, not a straight line).
 *
 * OSRM's own usage policy says the public demo server isn't meant for
 * high-volume production traffic — acceptable for now given real usage
 * is still near zero, but this is the one file to change (self-host
 * OSRM, or swap providers entirely) if that ever needs to change. Every
 * caller already treats a `null` return as "fall back to the straight-
 * line estimate" (see utils/geo.ts), so a slow/unavailable public demo
 * server degrades the feature instead of breaking it.
 */

const OSRM_BASE_URL = 'https://router.project-osrm.org';

// The public demo server is shared infrastructure — a hung request
// should never leave a poll loop (or a driver's tap) waiting indefinitely
// for it.
const REQUEST_TIMEOUT_MS = 5000;

export interface RouteResult {
  distanceMeters: number;
  durationSeconds: number;
}

/** Real road-network distance/duration between two points, or `null` on
 * any failure (network error, timeout, non-200, no route found, or an
 * unexpected response shape) — never throws. */
export async function getRoute(
  from: { lat: number; lng: number },
  to: { lat: number; lng: number },
): Promise<RouteResult | null> {
  const url =
    `${OSRM_BASE_URL}/route/v1/driving/${from.lng},${from.lat};${to.lng},${to.lat}` +
    '?overview=false';

  try {
    const controller = new AbortController();
    const timeout = setTimeout(() => controller.abort(), REQUEST_TIMEOUT_MS);
    let response: Response;
    try {
      response = await fetch(url, { signal: controller.signal });
    } finally {
      clearTimeout(timeout);
    }
    if (!response.ok) return null;

    const data = (await response.json()) as {
      code?: string;
      routes?: { distance?: number; duration?: number }[];
    };
    if (data.code !== 'Ok' || !data.routes?.length) return null;

    const { distance, duration } = data.routes[0];
    if (typeof distance !== 'number' || typeof duration !== 'number') return null;

    return { distanceMeters: distance, durationSeconds: duration };
  } catch {
    return null;
  }
}
