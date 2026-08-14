import { prisma } from '../lib/prisma';
import { notifyDriver } from '../utils/notify';

/**
 * Three lightweight, time-based reminders for the Daily Operations /
 * Weekly / Monthly Analytics screens — plain setInterval, not a real cron
 * library, since every check here is just "does the current server clock
 * fall in a window" and this backend already assumes it runs in PH time
 * (see todayDateOnly() in driver.ts). Checked every 10 minutes; each
 * individual notification is guarded against re-sending by checking for
 * one already created today, so re-running this check repeatedly (or
 * across a server restart) never double-sends.
 */

const CHECK_INTERVAL_MS = 10 * 60 * 1000;

// Evening window for "log today's operations" — deliberately NOT pinned
// to a single instant like 11:00 PM, which would leave almost no time to
// actually read the notification and act on it before the day rolls
// over. Opens a few hours earlier instead and stays open for an hour, so
// the periodic 10-minute check always catches it at least once per
// driver per day.
const DAILY_REMINDER_START_HOUR = 20; // 8:00 PM
const DAILY_REMINDER_END_HOUR = 21; // 9:00 PM

// Two different "today", for two different column types — mixing them up
// is exactly the bug this pair of helpers exists to prevent (confirmed
// live: PUT /daily-log used to store every entry under yesterday's date
// before todayDateOnly() in driver.ts got the same fix).
//
// - DriverDailyLog.date is a `@db.Date` column: Prisma extracts a Date
//   object's *UTC* calendar components when writing/filtering one, so a
//   plain local-midnight Date lands one day early for any positive UTC
//   offset (PH is UTC+8). todayDateOnlyUtc() rebuilds local calendar
//   components via Date.UTC so the round-trip is lossless.
// - Trip.startedAt / DriverNotification.createdAt are real DateTime
//   columns (an instant, not a calendar date) — for those, local
//   midnight IS the correct instant, exactly as long as this process's
//   own clock is PH time. startOfLocalDay() is that instant.
function todayDateOnlyUtc(): Date {
  const now = new Date();
  return new Date(Date.UTC(now.getFullYear(), now.getMonth(), now.getDate()));
}

function startOfLocalDay(): Date {
  const now = new Date();
  return new Date(now.getFullYear(), now.getMonth(), now.getDate());
}

/** Reminds a driver to log today's operations — only if they actually
 * drove today (a reminder makes no sense for someone who never went
 * online), haven't already logged today, and haven't already been
 * reminded today. */
async function sendDailyLogReminders() {
  const now = new Date();
  if (now.getHours() < DAILY_REMINDER_START_HOUR || now.getHours() >= DAILY_REMINDER_END_HOUR) return;

  const todayDate = todayDateOnlyUtc();
  const todayInstant = startOfLocalDay();

  const activeTripDrivers = await prisma.trip.findMany({
    where: { startedAt: { gte: todayInstant } },
    select: { driverId: true },
    distinct: ['driverId'],
  });
  if (activeTripDrivers.length === 0) return;
  const driverIds = activeTripDrivers.map((t) => t.driverId);

  const [drivers, loggedToday, remindedToday] = await Promise.all([
    prisma.driver.findMany({ where: { id: { in: driverIds }, isActive: true }, select: { id: true } }),
    prisma.driverDailyLog.findMany({ where: { driverId: { in: driverIds }, date: todayDate }, select: { driverId: true } }),
    prisma.driverNotification.findMany({
      where: { recipientId: { in: driverIds }, type: 'DAILY_LOG_REMINDER', createdAt: { gte: todayInstant } },
      select: { recipientId: true },
    }),
  ]);
  const loggedIds = new Set(loggedToday.map((l) => l.driverId));
  const remindedIds = new Set(remindedToday.map((n) => n.recipientId));

  for (const driver of drivers) {
    if (loggedIds.has(driver.id) || remindedIds.has(driver.id)) continue;
    await notifyDriver({
      recipientId: driver.id,
      title: "Don't forget to log today's operations",
      message: "There's still time to log today's earnings, expenses, and odometer readings before the day ends.",
      type: 'DAILY_LOG_REMINDER',
    });
  }
}

/** Once a week (Monday), lets a driver know their weekly report has
 * fresh data — only drivers who actually logged something in the past 7
 * days, so an inactive driver doesn't get pinged about an empty report. */
async function sendWeeklyReportNotifications() {
  const now = new Date();
  if (now.getDay() !== 1) return; // 1 = Monday

  const todayDate = todayDateOnlyUtc();
  const todayInstant = startOfLocalDay();
  const weekAgo = new Date(todayDate.getTime() - 7 * 24 * 60 * 60 * 1000);

  const [loggedThisWeek, remindedToday] = await Promise.all([
    prisma.driverDailyLog.findMany({
      where: { date: { gte: weekAgo, lt: todayDate } },
      select: { driverId: true },
      distinct: ['driverId'],
    }),
    prisma.driverNotification.findMany({
      where: { type: 'WEEKLY_REPORT_AVAILABLE', createdAt: { gte: todayInstant } },
      select: { recipientId: true },
    }),
  ]);
  if (loggedThisWeek.length === 0) return;
  const remindedIds = new Set(remindedToday.map((n) => n.recipientId));

  const drivers = await prisma.driver.findMany({
    where: { id: { in: loggedThisWeek.map((l) => l.driverId) }, isActive: true },
    select: { id: true },
  });

  for (const driver of drivers) {
    if (remindedIds.has(driver.id)) continue;
    await notifyDriver({
      recipientId: driver.id,
      title: 'Your weekly report is available',
      message: 'Your earnings and expenses for the past 7 days are ready to view in Weekly Analytics.',
      type: 'WEEKLY_REPORT_AVAILABLE',
    });
  }
}

/** On the 1st of each month, lets a driver know last month's report is
 * ready — only drivers who logged something last month. */
async function sendMonthlyReportNotifications() {
  const now = new Date();
  if (now.getDate() !== 1) return;

  const todayDate = todayDateOnlyUtc();
  const todayInstant = startOfLocalDay();
  const startOfLastMonth = new Date(Date.UTC(todayDate.getUTCFullYear(), todayDate.getUTCMonth() - 1, 1));

  const [loggedLastMonth, remindedToday] = await Promise.all([
    prisma.driverDailyLog.findMany({
      where: { date: { gte: startOfLastMonth, lt: todayDate } },
      select: { driverId: true },
      distinct: ['driverId'],
    }),
    prisma.driverNotification.findMany({
      where: { type: 'MONTHLY_REPORT_AVAILABLE', createdAt: { gte: todayInstant } },
      select: { recipientId: true },
    }),
  ]);
  if (loggedLastMonth.length === 0) return;
  const remindedIds = new Set(remindedToday.map((n) => n.recipientId));

  const drivers = await prisma.driver.findMany({
    where: { id: { in: loggedLastMonth.map((l) => l.driverId) }, isActive: true },
    select: { id: true },
  });

  const monthLabel = startOfLastMonth.toLocaleDateString('en-PH', { month: 'long', year: 'numeric', timeZone: 'UTC' });
  for (const driver of drivers) {
    if (remindedIds.has(driver.id)) continue;
    await notifyDriver({
      recipientId: driver.id,
      title: 'Your monthly report is available',
      message: `Your earnings and expenses for ${monthLabel} are ready to view in Monthly Analytics.`,
      type: 'MONTHLY_REPORT_AVAILABLE',
    });
  }
}

async function runChecks() {
  // Each check runs independently — one failing (a transient DB hiccup,
  // say) shouldn't stop the others from still getting a chance to run.
  for (const check of [sendDailyLogReminders, sendWeeklyReportNotifications, sendMonthlyReportNotifications]) {
    try {
      await check();
    } catch (err) {
      console.error(`driverLogReminders: ${check.name} failed:`, err);
    }
  }
}

let started = false;

/** Starts the periodic checks — call once at server startup (see
 * index.ts). Idempotent; a second call is a no-op. */
export function startDriverLogReminderJobs() {
  if (started) return;
  started = true;
  void runChecks();
  setInterval(() => void runChecks(), CHECK_INTERVAL_MS);
}
