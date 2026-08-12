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
