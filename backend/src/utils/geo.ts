/** Haversine distance in meters — the two points are always close enough
 * (city-scale) that Earth's curvature beyond a spherical approximation
 * doesn't matter here. Extracted from commuter.ts's own nearby-jeepneys
 * endpoint (its original, only caller) so driver.ts's route-to-passenger
 * endpoint can share the exact same math instead of a second copy. */
export function distanceMeters(lat1: number, lng1: number, lat2: number, lng2: number): number {
  const R = 6371000;
  const toRad = (deg: number) => (deg * Math.PI) / 180;
  const dLat = toRad(lat2 - lat1);
  const dLng = toRad(lng2 - lng1);
  const a = Math.sin(dLat / 2) ** 2 + Math.cos(toRad(lat1)) * Math.cos(toRad(lat2)) * Math.sin(dLng / 2) ** 2;
  return 2 * R * Math.asin(Math.sqrt(a));
}

// Rough city-jeepney travel speed for an ETA estimate — used as the
// fallback whenever real routing (see lib/routingService.ts) isn't
// available, so distance-over-assumed-speed stays consistent everywhere
// it's needed instead of each caller picking its own number.
const ASSUMED_SPEED_KMH = 15;

/** Straight-line-distance-over-assumed-speed ETA, in whole minutes,
 * never less than 1 — the fallback used whenever real routing isn't
 * available. */
export function estimateEtaMinutes(distanceMetersValue: number): number {
  return Math.max(1, Math.round((distanceMetersValue / 1000 / ASSUMED_SPEED_KMH) * 60));
}
