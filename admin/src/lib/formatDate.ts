// Every timestamp in this app is a moment in time recorded by the backend
// (which runs on PH-local time — see backend's `new Date()` usage). Pin
// every display to Asia/Manila explicitly instead of `toLocaleString()`'s
// default of the *viewer's* browser timezone, so an admin opening this
// site from outside PH sees the same time everyone else does.
const MANILA_TZ = 'Asia/Manila';

const dateFormatter = new Intl.DateTimeFormat('en-PH', {
  timeZone: MANILA_TZ,
  year: 'numeric',
  month: 'short',
  day: 'numeric',
});

const timeFormatter = new Intl.DateTimeFormat('en-PH', {
  timeZone: MANILA_TZ,
  hour: 'numeric',
  minute: '2-digit',
  hour12: true,
});

const dateTimeFormatter = new Intl.DateTimeFormat('en-PH', {
  timeZone: MANILA_TZ,
  year: 'numeric',
  month: 'short',
  day: 'numeric',
  hour: 'numeric',
  minute: '2-digit',
  hour12: true,
});

/** e.g. "Aug 14, 2026" */
export function formatManilaDate(iso: string): string {
  return dateFormatter.format(new Date(iso));
}

/** e.g. "3:45 PM" */
export function formatManilaTime(iso: string): string {
  return timeFormatter.format(new Date(iso));
}

/** e.g. "Aug 14, 2026, 3:45 PM" */
export function formatManilaDateTime(iso: string): string {
  return dateTimeFormatter.format(new Date(iso));
}

/** Whether `iso` falls on today's calendar date in Asia/Manila — used to
 * scope a "today's trips" view without a dedicated backend endpoint
 * (compares formatted date strings, so it's exact regardless of the
 * viewer's own timezone, same reasoning as every other formatter here). */
export function isManilaToday(iso: string): boolean {
  return dateFormatter.format(new Date(iso)) === dateFormatter.format(new Date());
}

const isoDayFormatter = new Intl.DateTimeFormat('en-CA', { timeZone: MANILA_TZ });

/** `date`'s own calendar date in Asia/Manila, as "YYYY-MM-DD" — what an
 * `<input type="date">` produces/expects, and the building block for the
 * range helpers below. */
export function manilaDateString(date: Date = new Date()): string {
  return isoDayFormatter.format(date);
}

/** Manila midnight for a given "YYYY-MM-DD" as a real UTC instant.
 * Asia/Manila's offset is fixed at +08:00 (no DST), so a plain ISO string
 * with that explicit offset is unambiguous regardless of the viewer's own
 * timezone — same technique as the backend's own date-range construction. */
export function manilaMidnight(isoDay: string): Date {
  return new Date(`${isoDay}T00:00:00+08:00`);
}

/** 0=Monday..6=Sunday for a "YYYY-MM-DD" — derived from the date's own
 * (year, month, day) via a UTC-midnight instant purely as a calendar
 * calculation, not a real moment in time, so it's correct regardless of
 * what that string means in Manila or any other zone. */
function isoDayOfWeekMondayFirst(isoDay: string): number {
  const sundayFirst = new Date(`${isoDay}T00:00:00Z`).getUTCDay();
  return (sundayFirst + 6) % 7;
}

/** [from, to) ISO instants for Trip History's Date filter, in Asia/Manila
 * — `to` is always "start of tomorrow" so every preset includes the whole
 * of today, not just up to the current moment. "Week" starts Monday. */
export function manilaDateRangeForPreset(preset: 'today' | 'week' | 'month'): { from: string; to: string } {
  const todayStr = manilaDateString();
  const todayMidnight = manilaMidnight(todayStr);
  const to = new Date(todayMidnight.getTime() + 24 * 60 * 60 * 1000).toISOString();

  if (preset === 'today') {
    return { from: todayMidnight.toISOString(), to };
  }
  if (preset === 'month') {
    const [year, month] = todayStr.split('-');
    return { from: manilaMidnight(`${year}-${month}-01`).toISOString(), to };
  }
  const daysSinceMonday = isoDayOfWeekMondayFirst(todayStr);
  const monday = new Date(todayMidnight.getTime() - daysSinceMonday * 24 * 60 * 60 * 1000);
  return { from: monday.toISOString(), to };
}

/** [from, to) ISO instants for a Custom Date Range picker's two
 * "YYYY-MM-DD" values — `to` is the day *after* [toDay] at Manila
 * midnight, so the end date picked is fully included. */
export function manilaDateRangeForCustom(fromDay: string, toDay: string): { from: string; to: string } {
  const from = manilaMidnight(fromDay).toISOString();
  const to = new Date(manilaMidnight(toDay).getTime() + 24 * 60 * 60 * 1000).toISOString();
  return { from, to };
}
