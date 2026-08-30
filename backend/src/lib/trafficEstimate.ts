/**
 * A time-of-day traffic estimate — not real sensor/congestion data (no
 * free source of that exists; Google/Mapbox charge for live traffic and
 * OSM-based routing has no real-time feed at all), just typical Metro
 * Manila weekday rush-hour patterns. Confirmed with the user as the
 * intended tradeoff for keeping this feature entirely free — clearly an
 * estimate, shown as one, never presented as measured.
 *
 * Assumes the server clock is PH time, same assumption
 * jobs/driverLogReminders.ts already makes elsewhere in this codebase.
 */
export type TrafficCondition = 'Light' | 'Moderate' | 'Heavy';

export function estimateTrafficCondition(date: Date = new Date()): TrafficCondition {
  const day = date.getDay(); // 0 = Sunday, 6 = Saturday
  const hour = date.getHours();
  const isWeekday = day >= 1 && day <= 5;

  if (!isWeekday) return 'Light';
  if ((hour >= 7 && hour < 9) || (hour >= 17 && hour < 20)) return 'Heavy';
  if ((hour >= 11 && hour < 13) || (hour >= 9 && hour < 17)) return 'Moderate';
  return 'Light';
}
