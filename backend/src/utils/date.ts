import { z } from 'zod';

/**
 * A calendar date with no time-of-day or timezone component (birthdays,
 * not instants), serialized on the wire as a plain "YYYY-MM-DD" string.
 *
 * `z.coerce.date()` / `new Date(isoString)` is NOT safe for this: an ISO
 * string with a time component but no explicit UTC offset (which is what
 * Dart's `DateTime.toIso8601String()` produces for a local `DateTime`) is
 * parsed as *local time in whatever timezone the parsing machine happens
 * to be in* per the JS Date spec — so the same string can silently land
 * on a different calendar date depending on where the backend runs.
 * Constructing via `Date.UTC(year, month, day)` from parsed components
 * sidesteps that entirely: the same three integers always produce the
 * same instant, everywhere.
 */
export const dateOnly = z
  .string()
  .regex(/^\d{4}-\d{2}-\d{2}$/, 'Must be in YYYY-MM-DD format')
  .transform((value) => {
    const [year, month, day] = value.split('-').map(Number);
    return new Date(Date.UTC(year, month - 1, day));
  });

/** Commuters must be at least this old to self-register — see the
 * Terms & Conditions' eligibility clause (legal_text.dart /
 * admin/public/terms-and-conditions.html) and the age-confirmation
 * checkbox on the mobile app's ID-verification step. Enforced here (not
 * just client-side in CommuterSignUpScreen's own `_minAge`) since a
 * direct API call skips whatever the app validates before sending. */
export const MIN_COMMUTER_SIGNUP_AGE = 18;

/** Age in whole years as of `asOf` (defaults to now) — birthday-aware,
 * not just a year subtraction, same logic as the mobile app's own
 * `_calculateAge` in CommuterSignUpScreen. */
export function calculateAge(dateOfBirth: Date, asOf: Date = new Date()): number {
  let age = asOf.getUTCFullYear() - dateOfBirth.getUTCFullYear();
  const hasHadBirthdayThisYear =
    asOf.getUTCMonth() > dateOfBirth.getUTCMonth() ||
    (asOf.getUTCMonth() === dateOfBirth.getUTCMonth() && asOf.getUTCDate() >= dateOfBirth.getUTCDate());
  if (!hasHadBirthdayThisYear) age--;
  return age;
}

/**
 * Formats a `Date` read back from a `@db.Date` column as "YYYY-MM-DD" —
 * never a full timestamp. Uses UTC getters since Prisma always
 * constructs these as UTC midnight for a DATE column; UTC getters read
 * that back exactly, regardless of the server's local timezone.
 */
export function formatDateOnly(date: Date): string {
  const year = date.getUTCFullYear().toString().padStart(4, '0');
  const month = (date.getUTCMonth() + 1).toString().padStart(2, '0');
  const day = date.getUTCDate().toString().padStart(2, '0');
  return `${year}-${month}-${day}`;
}

const manilaTimeFormatter = new Intl.DateTimeFormat('en-PH', {
  timeZone: 'Asia/Manila',
  hour: 'numeric',
  minute: '2-digit',
  hour12: true,
});

/** e.g. "7:25 AM" — for notification message text, pinned to PH-local
 * time regardless of where the backend process happens to run (mirrors
 * the admin site's own formatManilaTime in lib/formatDate.ts). */
export function formatManilaTime(date: Date): string {
  return manilaTimeFormatter.format(date);
}

const manilaDayKeyFormatter = new Intl.DateTimeFormat('en-CA', { timeZone: 'Asia/Manila' });

/** "2026-08-15" — the Asia/Manila calendar day a real instant falls on,
 * via Intl rather than fixed-offset arithmetic on `.toISOString()` (which
 * is always UTC) — mirrors the admin frontend's own manilaDateString in
 * lib/formatDate.ts. Use this whenever bucketing timestamps by day for a
 * PH-facing chart/report; GET /admin/trends used to bucket by UTC day,
 * which misplaced a signup from the early hours of a Manila day into the
 * previous day's bar regardless of the server's own local timezone. */
export function manilaDayKey(date: Date): string {
  return manilaDayKeyFormatter.format(date);
}

/** Manila midnight for a given Manila calendar day ("2026-08-15") as a
 * real UTC instant — the "+08:00" offset makes the string unambiguous
 * regardless of the parsing machine's own timezone (Manila has no DST,
 * so this fixed offset is always correct). Mirrors the admin frontend's
 * own manilaMidnight in lib/formatDate.ts. */
export function manilaMidnight(isoDay: string): Date {
  return new Date(`${isoDay}T00:00:00+08:00`);
}
