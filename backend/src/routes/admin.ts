import { Router } from 'express';
import bcrypt from 'bcryptjs';
import { z } from 'zod';

import { prisma } from '../lib/prisma';
import { toE164, phoneSearchVariant } from '../utils/phone';
import { isValidPlateNumber, normalizePlateNumber } from '../utils/plate';
import { toTitleCase } from '../utils/text';
import { generateDriverId } from '../utils/driverId';
import { generateQrToken } from '../utils/qrToken';
import { signAuthToken } from '../utils/jwt';
import {
  dateOnly,
  formatDateOnly,
  formatManilaTime,
  manilaDayKey,
  manilaMidnight,
  calculateAge,
  MIN_ADULT_AGE,
} from '../utils/date';
import { requireAuth, requireMainAdmin } from '../middleware/auth';
import { notifyDriver, notifyCommuter } from '../utils/notify';
import { issueOtp, verifyOtp } from '../utils/otp';
import { authLimiter } from '../middleware/rateLimit';

const router = Router();

// Unauthenticated + brute-forceable — see middleware/rateLimit.ts.
router.use(['/login', '/forgot-password', '/verify-otp', '/reset-password'], authLimiter);

function toPublicAdmin(admin: {
  id: string;
  email: string;
  fullName: string;
  role: string;
  isActive: boolean;
  createdAt: Date;
  lastLoginAt: Date | null;
}) {
  return {
    id: admin.id,
    email: admin.email,
    fullName: admin.fullName,
    role: admin.role,
    isActive: admin.isActive,
    createdAt: admin.createdAt,
    lastLoginAt: admin.lastLoginAt,
  };
}

function normalizeEmail(email: string): string {
  return email.trim().toLowerCase();
}

// ---------------------------------------------------------------------------
// LOGIN
// ---------------------------------------------------------------------------
// No self-registration — the first (Main) admin account is created via
// the create-admin CLI script (mirrors scripts/create-driver.ts); every
// admin after that is created by the Main Admin from Settings ->
// Admin Accounts (see POST /admins further below), not through this route.

const loginSchema = z.object({
  email: z.string().trim().email(),
  password: z.string().min(1),
});

router.post('/login', async (req, res, next) => {
  try {
    const body = loginSchema.parse(req.body);
    const email = normalizeEmail(body.email);

    const admin = await prisma.admin.findUnique({ where: { email } });
    if (!admin) {
      res.status(404).json({ error: 'No admin account found for that email.' });
      return;
    }

    if (!admin.isActive) {
      res.status(401).json({ error: 'This account has been deactivated.', code: 'ACCOUNT_DEACTIVATED' });
      return;
    }

    const valid = await bcrypt.compare(body.password, admin.passwordHash);
    if (!valid) {
      res.status(401).json({ error: 'Incorrect password.' });
      return;
    }

    const updated = await prisma.admin.update({ where: { id: admin.id }, data: { lastLoginAt: new Date() } });

    const token = signAuthToken({ sub: admin.id, role: 'admin' });
    res.json({ token, admin: toPublicAdmin(updated) });
  } catch (err) {
    next(err);
  }
});

// ---------------------------------------------------------------------------
// FORGOT PASSWORD — same OTP-code pattern as commuter/driver (see
// utils/otp.ts), just keyed by email instead of a PH mobile number since
// that's how admin accounts authenticate. No email provider is wired up
// yet, so — same as SMS OTPs today — the code is logged to the server
// console instead of actually being sent.
// ---------------------------------------------------------------------------

const forgotPasswordSchema = z.object({ email: z.string().trim().email() });

router.post('/forgot-password', async (req, res, next) => {
  try {
    const body = forgotPasswordSchema.parse(req.body);
    const email = normalizeEmail(body.email);

    const admin = await prisma.admin.findUnique({ where: { email } });
    if (!admin) {
      res.status(404).json({ error: 'No admin account found for that email.' });
      return;
    }

    await issueOtp(email, 'PASSWORD_RESET');
    res.json({ message: 'A verification code has been sent.' });
  } catch (err) {
    next(err);
  }
});

const verifyOtpSchema = z.object({
  email: z.string().trim().email(),
  code: z.string().length(6),
});

router.post('/verify-otp', async (req, res, next) => {
  try {
    const body = verifyOtpSchema.parse(req.body);
    const email = normalizeEmail(body.email);

    // Doesn't consume the code — this is just early feedback ("yes, that's
    // right") before the app moves on to reset-password, which is the
    // call that actually spends it.
    const ok = await verifyOtp(email, 'PASSWORD_RESET', body.code, { consume: false });
    if (!ok) {
      res.status(400).json({ error: 'Invalid or expired code.' });
      return;
    }

    res.json({ verified: true });
  } catch (err) {
    next(err);
  }
});

const resetPasswordSchema = z.object({
  email: z.string().trim().email(),
  code: z.string().length(6),
  newPassword: z.string().min(8),
});

router.post('/reset-password', async (req, res, next) => {
  try {
    const body = resetPasswordSchema.parse(req.body);
    const email = normalizeEmail(body.email);

    const ok = await verifyOtp(email, 'PASSWORD_RESET', body.code);
    if (!ok) {
      res.status(400).json({ error: 'Invalid or expired code.' });
      return;
    }

    const admin = await prisma.admin.findUnique({ where: { email } });
    if (!admin) {
      res.status(404).json({ error: 'No admin account found for that email.' });
      return;
    }

    const passwordHash = await bcrypt.hash(body.newPassword, 10);
    await prisma.admin.update({ where: { id: admin.id }, data: { passwordHash } });

    res.json({ message: 'Password reset successfully.' });
  } catch (err) {
    next(err);
  }
});

// ---------------------------------------------------------------------------
// SELF
// ---------------------------------------------------------------------------

router.get('/me', requireAuth('admin'), async (req, res, next) => {
  try {
    const admin = await prisma.admin.findUnique({ where: { id: req.auth!.sub } });
    if (!admin) {
      res.status(404).json({ error: 'Account not found.' });
      return;
    }
    res.json({ admin: toPublicAdmin(admin) });
  } catch (err) {
    next(err);
  }
});

const updateProfileSchema = z.object({ fullName: z.string().trim().min(1).transform(toTitleCase) });

router.patch('/me', requireAuth('admin'), async (req, res, next) => {
  try {
    const body = updateProfileSchema.parse(req.body);
    const admin = await prisma.admin.update({
      where: { id: req.auth!.sub },
      data: { fullName: body.fullName },
    });
    res.json({ admin: toPublicAdmin(admin) });
  } catch (err) {
    next(err);
  }
});

const changePasswordSchema = z.object({
  currentPassword: z.string().min(1),
  newPassword: z.string().min(8),
});

router.patch('/me/password', requireAuth('admin'), async (req, res, next) => {
  try {
    const body = changePasswordSchema.parse(req.body);

    const admin = await prisma.admin.findUnique({ where: { id: req.auth!.sub } });
    if (!admin) {
      res.status(404).json({ error: 'Account not found.' });
      return;
    }

    const valid = await bcrypt.compare(body.currentPassword, admin.passwordHash);
    if (!valid) {
      res.status(400).json({ error: 'Current password is incorrect.' });
      return;
    }

    const passwordHash = await bcrypt.hash(body.newPassword, 10);
    await prisma.admin.update({ where: { id: admin.id }, data: { passwordHash } });

    res.json({ message: 'Password updated.' });
  } catch (err) {
    next(err);
  }
});

// ---------------------------------------------------------------------------
// DASHBOARD STATS
// ---------------------------------------------------------------------------

/** Percent change from [previous] to [current], rounded to 1 decimal.
 * Null when [previous] is 0 — "up from zero" isn't a meaningful percent,
 * so the frontend shows the raw count instead of a bogus/infinite rate. */
function percentChange(current: number, previous: number): number | null {
  if (previous === 0) return null;
  return Math.round(((current - previous) / previous) * 1000) / 10;
}

router.get('/stats', requireAuth('admin'), async (_req, res, next) => {
  try {
    const now = Date.now();
    const sevenDaysAgo = new Date(now - 7 * 24 * 60 * 60 * 1000);
    const fourteenDaysAgo = new Date(now - 14 * 24 * 60 * 60 * 1000);

    const [
      totalDrivers,
      totalCommuters,
      commutersWithIdSubmitted,
      pendingVerifications,
      approvedVerifications,
      rejectedVerifications,
      newCommutersThisWeek,
      newDriversThisWeek,
      commutersPriorWeek,
      driversPriorWeek,
      activeTrips,
      openComplaints,
    ] = await Promise.all([
      prisma.driver.count(),
      prisma.commuter.count(),
      prisma.commuter.count({ where: { idFrontUrl: { not: null } } }),
      prisma.commuter.count({ where: { verificationStatus: 'PENDING' } }),
      prisma.commuter.count({ where: { verificationStatus: 'APPROVED' } }),
      prisma.commuter.count({ where: { verificationStatus: 'REJECTED' } }),
      prisma.commuter.count({ where: { createdAt: { gte: sevenDaysAgo } } }),
      prisma.driver.count({ where: { createdAt: { gte: sevenDaysAgo } } }),
      prisma.commuter.count({ where: { createdAt: { gte: fourteenDaysAgo, lt: sevenDaysAgo } } }),
      prisma.driver.count({ where: { createdAt: { gte: fourteenDaysAgo, lt: sevenDaysAgo } } }),
      // Fleet oversight — the operational counts the dashboard was missing
      // entirely (it only ever covered account growth + ID verification).
      // Deliberately no flagged-trips count here — kept dashboard-only to
      // active trips + open complaints per explicit request.
      prisma.trip.count({ where: { status: 'ACTIVE' } }),
      prisma.complaint.count({ where: { status: { in: ['PENDING', 'INVESTIGATING'] } } }),
    ]);

    res.json({
      totalDrivers,
      totalCommuters,
      commutersWithIdSubmitted,
      pendingVerifications,
      approvedVerifications,
      rejectedVerifications,
      newCommutersThisWeek,
      newDriversThisWeek,
      commutersChangePercent: percentChange(newCommutersThisWeek, commutersPriorWeek),
      driversChangePercent: percentChange(newDriversThisWeek, driversPriorWeek),
      // Growth of the overall base, not the weekly signup pace above — the
      // total as of 7 days ago is just today's total minus this week's
      // new signups (no deletions to account for).
      totalDriversChangePercent: percentChange(totalDrivers, totalDrivers - newDriversThisWeek),
      totalCommutersChangePercent: percentChange(totalCommuters, totalCommuters - newCommutersThisWeek),
      activeTrips,
      openComplaints,
    });
  } catch (err) {
    next(err);
  }
});

// ---------------------------------------------------------------------------
// RECENT ACTIVITY — the most recent driver + commuter registrations,
// merged into one feed. Just the two existing tables re-sorted together;
// no new storage, since "activity" here is exactly "an account was
// created" (there's no Trip/action log to draw from yet).
// ---------------------------------------------------------------------------

router.get('/activity', requireAuth('admin'), async (req, res, next) => {
  try {
    const limit = Math.min(Number(req.query.limit) || 10, 50);

    const [drivers, commuters] = await Promise.all([
      prisma.driver.findMany({
        orderBy: { createdAt: 'desc' },
        take: limit,
        select: { id: true, driverId: true, fullName: true, photoUrl: true, createdAt: true },
      }),
      prisma.commuter.findMany({
        orderBy: { createdAt: 'desc' },
        take: limit,
        select: { id: true, commuterId: true, fullName: true, photoUrl: true, createdAt: true },
      }),
    ]);

    const activity = [
      ...drivers.map((d) => ({
        type: 'driver' as const,
        id: d.id,
        identifier: d.driverId,
        fullName: d.fullName,
        photoUrl: d.photoUrl,
        createdAt: d.createdAt,
      })),
      ...commuters.map((c) => ({
        type: 'commuter' as const,
        id: c.id,
        identifier: c.commuterId,
        fullName: c.fullName,
        photoUrl: c.photoUrl,
        createdAt: c.createdAt,
      })),
    ]
      .sort((a, b) => b.createdAt.getTime() - a.createdAt.getTime())
      .slice(0, limit);

    res.json({ activity });
  } catch (err) {
    next(err);
  }
});

// ---------------------------------------------------------------------------
// TRENDS — daily registration counts for the dashboard chart. Computed
// in JS from the two tables rather than a raw SQL GROUP BY, since the
// volumes here are small (an admin tool, not analytics-at-scale) and this
// keeps it portable/readable without a raw query.
// ---------------------------------------------------------------------------

router.get('/trends', requireAuth('admin'), async (req, res, next) => {
  try {
    const days = Math.min(Math.max(Number(req.query.days) || 14, 1), 90);
    // Bucketed by Asia/Manila calendar day, not UTC (see manilaDayKey) —
    // previously used `.toISOString().slice(0, 10)`, which put a signup
    // from the early hours of a Manila day into the previous day's bar.
    const since = manilaMidnight(manilaDayKey(new Date(Date.now() - (days - 1) * 24 * 60 * 60 * 1000)));

    const [drivers, commuters] = await Promise.all([
      prisma.driver.findMany({ where: { createdAt: { gte: since } }, select: { createdAt: true } }),
      prisma.commuter.findMany({ where: { createdAt: { gte: since } }, select: { createdAt: true } }),
    ]);

    const driverCounts = new Map<string, number>();
    for (const d of drivers) driverCounts.set(manilaDayKey(d.createdAt), (driverCounts.get(manilaDayKey(d.createdAt)) ?? 0) + 1);

    const commuterCounts = new Map<string, number>();
    for (const c of commuters) {
      commuterCounts.set(manilaDayKey(c.createdAt), (commuterCounts.get(manilaDayKey(c.createdAt)) ?? 0) + 1);
    }

    const series: { date: string; drivers: number; commuters: number }[] = [];
    for (let i = 0; i < days; i++) {
      const date = new Date(since.getTime() + i * 24 * 60 * 60 * 1000);
      const key = manilaDayKey(date);
      series.push({ date: key, drivers: driverCounts.get(key) ?? 0, commuters: commuterCounts.get(key) ?? 0 });
    }

    res.json({ series });
  } catch (err) {
    next(err);
  }
});

// ---------------------------------------------------------------------------
// DRIVERS
// ---------------------------------------------------------------------------

const driversQuerySchema = z.object({
  accountStatus: z.enum(['active', 'inactive']).optional(),
  search: z.string().trim().min(1).optional(),
  page: z.coerce.number().int().min(1).default(1),
  pageSize: z.coerce.number().int().min(1).max(100).default(25),
});

router.get('/drivers', requireAuth('admin'), async (req, res, next) => {
  try {
    const query = driversQuerySchema.parse(req.query);
    const where = {
      ...(query.accountStatus ? { isActive: query.accountStatus === 'active' } : {}),
      ...(query.search
        ? {
            OR: [
              { fullName: { contains: query.search, mode: 'insensitive' as const } },
              { mobileNumber: { contains: query.search, mode: 'insensitive' as const } },
              ...(phoneSearchVariant(query.search)
                ? [{ mobileNumber: { contains: phoneSearchVariant(query.search)!, mode: 'insensitive' as const } }]
                : []),
              { plateNumber: { contains: query.search, mode: 'insensitive' as const } },
              { driverId: { contains: query.search, mode: 'insensitive' as const } },
            ],
          }
        : {}),
    };

    const [drivers, totalDrivers] = await Promise.all([
      prisma.driver.findMany({
        where,
        orderBy: { createdAt: 'desc' },
        skip: (query.page - 1) * query.pageSize,
        take: query.pageSize,
      }),
      prisma.driver.count({ where }),
    ]);
    const totalPages = Math.max(1, Math.ceil(totalDrivers / query.pageSize));

    res.json({
      drivers: drivers.map((driver) => ({
        id: driver.id,
        driverId: driver.driverId,
        fullName: driver.fullName,
        mobileNumber: driver.mobileNumber,
        plateNumber: driver.plateNumber,
        dateOfBirth: driver.dateOfBirth ? formatDateOnly(driver.dateOfBirth) : null,
        photoUrl: driver.photoUrl,
        isActive: driver.isActive,
        createdAt: driver.createdAt,
      })),
      currentPage: query.page,
      pageSize: query.pageSize,
      totalDrivers,
      totalPages,
      hasNextPage: query.page < totalPages,
    });
  } catch (err) {
    next(err);
  }
});

// One row per jeepney (=driver — this app assigns exactly one plate per
// driver, see Driver.plateNumber) for Jeepney Monitoring's live fleet
// table and full-screen map — every registered driver, not just today's
// active ones; the page's own search box and Online/Offline filter are
// what narrow the view, and View Location/View Trips already degrade
// gracefully (disabled link, "no trips yet" empty state) for a driver
// with no activity at all. Never one row per trip — a driver ending one
// trip and starting another still resolves to the same driverId, so
// it's still the same row; the client just sees its route/currentTripStart
// change. Registered before /drivers/:id below so "jeepneys" doesn't get
// swallowed as a driver id by that route's wildcard param (it wouldn't
// collide anyway, different path segment, but kept alongside it for
// clarity).
router.get('/jeepneys', requireAuth('admin'), async (_req, res, next) => {
  try {
    const drivers = await prisma.driver.findMany({ orderBy: { fullName: 'asc' } });
    const driverIds = drivers.map((d) => d.id);

    // Two queries, each `distinct: ['driverId']` — one row per driver,
    // not one row per trip. Used to load *every* trip these drivers had
    // ever run (unbounded — the whole fleet's entire trip history) just
    // to pick two things per driver in JS; `distinct` + `orderBy` lets
    // Postgres do that same "pick the newest match per driver" directly,
    // so this stays cheap regardless of how many trips pile up over time.
    const [activeTrips, lastLocatedTrips] = await Promise.all([
      prisma.trip.findMany({
        where: { driverId: { in: driverIds }, status: 'ACTIVE' },
        orderBy: { startedAt: 'desc' },
        distinct: ['driverId'],
      }),
      // A trip can end with no ping at all (e.g. one ended within a
      // second of starting), so "most recently located" isn't always the
      // same trip as "most recently active" — queried separately.
      prisma.trip.findMany({
        where: { driverId: { in: driverIds }, currentLat: { not: null } },
        orderBy: { startedAt: 'desc' },
        distinct: ['driverId'],
      }),
    ]);

    const activeByDriver = new Map(activeTrips.map((t) => [t.driverId, t]));
    const lastLocatedByDriver = new Map(lastLocatedTrips.map((t) => [t.driverId, t]));

    res.json({
      jeepneys: drivers.map((d) => {
        const active = activeByDriver.get(d.id);
        const located = lastLocatedByDriver.get(d.id);
        return {
          driverId: d.id,
          driverName: d.fullName,
          plateNumber: d.plateNumber,
          isOnline: !!active,
          route: active?.route ?? null,
          currentTripStart: active?.startedAt ?? null,
          lastLat: located?.currentLat ?? null,
          lastLng: located?.currentLng ?? null,
          lastLocationUpdatedAt: located?.locationUpdatedAt ?? null,
        };
      }),
    });
  } catch (err) {
    next(err);
  }
});

router.get('/drivers/:id', requireAuth('admin'), async (req, res, next) => {
  try {
    const id: string = Array.isArray(req.params.id) ? req.params.id[0] : req.params.id;
    const driver = await prisma.driver.findUnique({ where: { id } });
    if (!driver) {
      res.status(404).json({ error: 'Driver not found.' });
      return;
    }

    const [reportCount, ratingInfo] = await Promise.all([
      prisma.complaint.count({ where: { driverId: id } }),
      prisma.rating.aggregate({ where: { driverId: id }, _avg: { stars: true }, _count: { stars: true } }),
    ]);

    res.json({
      driver: {
        id: driver.id,
        driverId: driver.driverId,
        fullName: driver.fullName,
        mobileNumber: driver.mobileNumber,
        plateNumber: driver.plateNumber,
        dateOfBirth: driver.dateOfBirth ? formatDateOnly(driver.dateOfBirth) : null,
        photoUrl: driver.photoUrl,
        licenseFrontUrl: driver.licenseFrontUrl,
        licenseBackUrl: driver.licenseBackUrl,
        licenseNumber: driver.licenseNumber,
        licenseVerificationStatus: driver.licenseVerificationStatus,
        qrToken: driver.qrToken,
        isActive: driver.isActive,
        reportCount,
        averageRating: ratingInfo._avg.stars,
        ratingCount: ratingInfo._count.stars,
        createdAt: driver.createdAt,
      },
    });
  } catch (err) {
    next(err);
  }
});

// Two things happen through this one endpoint, distinguished by whether
// [status] is sent:
//  - Plain correction (no [status]) — an admin editing the number on file
//    directly (e.g. fixing a typo from Add Driver), same as
//    PlateNumberField/DateOfBirthField's own inline edit. Doesn't touch
//    licenseVerificationStatus and doesn't require a submitted photo.
//  - Review (with [status]) — the admin types in the license number
//    themselves after looking at a submitted photo (no OCR/auto-detect;
//    see TODO.md for why that was considered and dropped). Requires
//    licenseNumber when approving; rejecting doesn't need one. Requires a
//    submitted photo, since there's nothing to review otherwise.
const driverLicenseNumberSchema = z.object({
  status: z.enum(['APPROVED', 'REJECTED']).optional(),
  licenseNumber: z.string().trim().min(1).optional(),
});

router.patch('/drivers/:id/license-number', requireAuth('admin'), async (req, res, next) => {
  try {
    const id: string = Array.isArray(req.params.id) ? req.params.id[0] : req.params.id;
    const body = driverLicenseNumberSchema.parse(req.body);

    const driver = await prisma.driver.findUnique({ where: { id } });
    if (!driver) {
      res.status(404).json({ error: 'Driver not found.' });
      return;
    }

    if (!body.status) {
      // Plain correction — see this endpoint's own doc comment above.
      if (!body.licenseNumber) {
        res.status(400).json({ error: 'License number is required.' });
        return;
      }
      const updated = await prisma.driver.update({
        where: { id },
        data: { licenseNumber: body.licenseNumber },
      });
      res.json({
        driver: {
          id: updated.id,
          licenseNumber: updated.licenseNumber,
          licenseVerificationStatus: updated.licenseVerificationStatus,
        },
      });
      return;
    }

    if (!driver.licenseFrontUrl) {
      res.status(400).json({ error: 'This driver has not submitted a license photo yet.' });
      return;
    }
    if (body.status === 'APPROVED' && !body.licenseNumber) {
      res.status(400).json({ error: 'License number is required to approve.' });
      return;
    }

    const updated = await prisma.driver.update({
      where: { id },
      data: {
        licenseVerificationStatus: body.status,
        licenseNumber: body.status === 'APPROVED' ? body.licenseNumber : driver.licenseNumber,
      },
    });

    await notifyDriver({
      recipientId: id,
      title: body.status === 'APPROVED' ? 'License verified' : 'License submission rejected',
      message:
        body.status === 'APPROVED'
          ? 'Your submitted license photo has been verified.'
          : 'Your submitted license photo was rejected. Please submit a clearer photo from Settings.',
      type: body.status === 'APPROVED' ? 'LICENSE_APPROVED' : 'LICENSE_REJECTED',
    });

    res.json({
      driver: {
        id: updated.id,
        licenseNumber: updated.licenseNumber,
        licenseVerificationStatus: updated.licenseVerificationStatus,
      },
    });
  } catch (err) {
    next(err);
  }
});

// The two fixed routes this fleet services — same constant as
// kDriverRoutes in the driver app's driver_start_trip_screen.dart, and
// the same reasoning as the Route filter added to Jeepney Monitoring:
// fixed and hardcoded rather than a `SELECT DISTINCT route` per driver,
// so the filter's option list costs nothing to render even once a driver
// has hundreds of thousands of trips on record.
const DRIVER_ROUTES = ['Pasig – Quiapo', 'Quiapo – Pasig'] as const;

const driverTripsQuerySchema = z.object({
  page: z.coerce.number().int().min(1).default(1),
  pageSize: z.coerce.number().int().min(1).max(100).default(25),
  dateFrom: z.coerce.date().optional(),
  dateTo: z.coerce.date().optional(),
  route: z.enum(DRIVER_ROUTES).optional(),
  flag: z.enum(['all', 'normal', 'short']).default('all'),
});

// Paginated Trip History for one driver — backs the Trip History table
// inside the admin site's Driver Detail Panel. Deliberately a separate
// endpoint from GET /drivers/:id above (which used to embed the first 30
// trips inline): that endpoint gets polled every few seconds just to keep
// the driver's basic info/status current, and refetching a whole page of
// trips on every one of those ticks — plus losing whatever page/filter
// the admin had open — would be wasteful and janky. This is fetched (and
// re-polled) independently, keyed by its own page/filter state.
router.get('/drivers/:id/trips', requireAuth('admin'), async (req, res, next) => {
  try {
    const id: string = Array.isArray(req.params.id) ? req.params.id[0] : req.params.id;
    const query = driverTripsQuerySchema.parse(req.query);

    const where = {
      driverId: id,
      ...(query.dateFrom || query.dateTo
        ? { startedAt: { ...(query.dateFrom ? { gte: query.dateFrom } : {}), ...(query.dateTo ? { lt: query.dateTo } : {}) } }
        : {}),
      ...(query.route ? { route: query.route } : {}),
      ...(query.flag === 'short' ? { isShortTrip: true } : query.flag === 'normal' ? { isShortTrip: false } : {}),
    };

    const [trips, totalTrips] = await Promise.all([
      prisma.trip.findMany({
        where,
        orderBy: { startedAt: 'desc' },
        skip: (query.page - 1) * query.pageSize,
        take: query.pageSize,
      }),
      prisma.trip.count({ where }),
    ]);
    // Only ever non-empty for flagged trips that have already been
    // reviewed — the admin review panel shown from this table needs the
    // reviewer's name, not just their id.
    const reviewersById = await loadAdminsById(trips.map((t) => t.reviewedBy));

    const totalPages = Math.max(1, Math.ceil(totalTrips / query.pageSize));

    res.json({
      trips: trips.map((t) => ({
        id: t.id,
        route: t.route,
        status: t.status,
        startedAt: t.startedAt,
        endedAt: t.endedAt,
        isShortTrip: t.isShortTrip,
        flagReason: t.flagReason,
        driverExplanation: t.driverExplanation,
        explanationSubmittedAt: t.explanationSubmittedAt,
        reviewStatus: t.reviewStatus,
        reviewedAt: t.reviewedAt,
        reviewedByName: t.reviewedBy ? reviewersById.get(t.reviewedBy)?.fullName ?? null : null,
        adminReviewNote: t.adminReviewNote,
      })),
      currentPage: query.page,
      pageSize: query.pageSize,
      totalTrips,
      totalPages,
      hasNextPage: query.page < totalPages,
      routes: DRIVER_ROUTES,
    });
  } catch (err) {
    next(err);
  }
});

const setStatusSchema = z.object({ isActive: z.boolean() });

router.patch('/drivers/:id/status', requireAuth('admin'), async (req, res, next) => {
  try {
    const id: string = Array.isArray(req.params.id) ? req.params.id[0] : req.params.id;
    const body = setStatusSchema.parse(req.body);

    const driver = await prisma.driver.update({ where: { id }, data: { isActive: body.isActive } });

    // No notification on deactivation — requireAuth now force-logs them out
    // on their very next request (see auth.ts), so they're gone before a
    // deactivation notification could ever reach them. Reactivation is the
    // one that's actually worth telling them about, since nothing else in
    // the app would otherwise let them know they can log back in.
    if (driver.isActive) {
      await notifyDriver({
        recipientId: driver.id,
        title: 'Your account has been reactivated',
        message: 'You can now continue using the app.',
      });
    }

    res.json({ driver: { id: driver.id, isActive: driver.isActive } });
  } catch (err) {
    next(err);
  }
});

const setPlateNumberSchema = z.object({
  plateNumber: z
    .string()
    .trim()
    .min(1)
    .transform((value) => normalizePlateNumber(value))
    .refine(isValidPlateNumber, {
      message: 'Plate number must be 3 letters followed by 3 or 4 numbers (e.g. ABC123 or ABC1234).',
    }),
});

router.patch('/drivers/:id/plate-number', requireAuth('admin'), async (req, res, next) => {
  try {
    const id: string = Array.isArray(req.params.id) ? req.params.id[0] : req.params.id;
    const body = setPlateNumberSchema.parse(req.body);

    const driver = await prisma.driver.update({ where: { id }, data: { plateNumber: body.plateNumber } });

    await notifyDriver({
      recipientId: driver.id,
      title: 'Your plate number was updated',
      message: `Your registered plate number is now ${driver.plateNumber}.`,
      type: 'PLATE_NUMBER_UPDATED',
    });

    res.json({ driver: { id: driver.id, plateNumber: driver.plateNumber } });
  } catch (err) {
    next(err);
  }
});

// Optional for a driver (unlike a commuter's, which is required at
// signup) — an admin may not have this on hand yet. But when a date IS
// given, it still has to clear MIN_ADULT_AGE, whether at creation
// (createDriverSchema below) or a later correction here, same reasoning
// as setCommuterDateOfBirthSchema further down.
const driverDateOfBirth = dateOnly.nullable().refine(
  (value) => value === null || calculateAge(value) >= MIN_ADULT_AGE,
  { message: `Drivers must be at least ${MIN_ADULT_AGE} years old.` },
);

// Date of birth is no longer editable by the driver themselves (see
// PATCH /driver/me) — only an admin can set/correct it now, same
// verified-by-a-human reasoning as plate number and license number.
const setDateOfBirthSchema = z.object({ dateOfBirth: driverDateOfBirth });

router.patch('/drivers/:id/date-of-birth', requireAuth('admin'), async (req, res, next) => {
  try {
    const id: string = Array.isArray(req.params.id) ? req.params.id[0] : req.params.id;
    const body = setDateOfBirthSchema.parse(req.body);

    const driver = await prisma.driver.update({ where: { id }, data: { dateOfBirth: body.dateOfBirth } });

    res.json({
      driver: {
        id: driver.id,
        dateOfBirth: driver.dateOfBirth ? formatDateOnly(driver.dateOfBirth) : null,
      },
    });
  } catch (err) {
    next(err);
  }
});

// The real, operator-gated version of what POST /api/driver/signup's own
// comment calls out as still missing — drivers don't self-register, an
// admin creates the account on their behalf.
// toE164 (utils/phone.ts) never throws — it just mangles whatever it's
// given into *some* +63-prefixed string, so without this check a garbage
// mobileNumber (e.g. "abc") would silently become "+63" and still create
// an account. Mirrors the PH-format check every self-serve signup/login
// screen already does client-side before ever reaching this shape of
// request.
const phMobileNumberRegex = /^(?:\+63\d{10}|09\d{9})$/;

const createDriverSchema = z.object({
  fullName: z.string().trim().min(1).transform(toTitleCase),
  mobileNumber: z
    .string()
    .trim()
    .transform((value) => value.replace(/[\s-]/g, ''))
    .refine((value) => phMobileNumberRegex.test(value), {
      message: 'Enter a valid PH mobile number (e.g. 09171234567 or +639171234567).',
    }),
  password: z.string().min(8),
  plateNumber: z
    .string()
    .trim()
    .min(1)
    .transform((value) => normalizePlateNumber(value))
    .refine(isValidPlateNumber, {
      message: 'Plate number must be 3 letters followed by 3 or 4 numbers (e.g. ABC123 or ABC1234).',
    }),
  // Required — an admin records this on file at creation. Doesn't set
  // licenseVerificationStatus by itself, though: the driver still has to
  // submit a license photo (Settings -> License Number) and get that
  // reviewed and approved before they can start a trip (see POST
  // /driver/trips/start's own check). This is just the number on record,
  // not proof of it.
  licenseNumber: z.string().trim().min(1),
  // Optional — an admin may not have this on hand at creation time; can
  // always be added/corrected later via PATCH /drivers/:id/date-of-birth.
  // Still enforces MIN_ADULT_AGE when a date is given — see
  // driverDateOfBirth's own doc comment.
  dateOfBirth: driverDateOfBirth.optional(),
});

router.post('/drivers', requireAuth('admin'), async (req, res, next) => {
  try {
    const body = createDriverSchema.parse(req.body);
    const mobileNumber = toE164(body.mobileNumber);

    const existing = await prisma.driver.findUnique({ where: { mobileNumber } });
    if (existing) {
      res.status(409).json({ error: 'This number is already registered.' });
      return;
    }

    const passwordHash = await bcrypt.hash(body.password, 10);
    const driver = await prisma.driver.create({
      data: {
        driverId: await generateDriverId(),
        fullName: body.fullName,
        mobileNumber,
        passwordHash,
        plateNumber: body.plateNumber,
        licenseNumber: body.licenseNumber,
        dateOfBirth: body.dateOfBirth ?? null,
        qrToken: await generateQrToken(),
      },
    });

    res.status(201).json({
      driver: {
        id: driver.id,
        driverId: driver.driverId,
        fullName: driver.fullName,
        mobileNumber: driver.mobileNumber,
        plateNumber: driver.plateNumber,
        licenseNumber: driver.licenseNumber,
        dateOfBirth: driver.dateOfBirth ? formatDateOnly(driver.dateOfBirth) : null,
        photoUrl: null,
        isActive: driver.isActive,
        createdAt: driver.createdAt,
      },
    });
  } catch (err) {
    next(err);
  }
});

// ---------------------------------------------------------------------------
// COMMUTERS
// ---------------------------------------------------------------------------
// The list view deliberately omits the ID/selfie photo URLs — those are
// only pulled in the single-commuter detail endpoint below, for KYC
// review, rather than loaded for every row in the table.

const commutersQuerySchema = z.object({
  status: z.enum(['pending', 'approved', 'rejected']).optional(),
  // 'all'/'active'/'inactive' — separate from `status` (verification
  // status) since CommutersPage and IdVerificationPage filter on two
  // different, independent things. Named accountStatus to avoid the clash.
  accountStatus: z.enum(['active', 'inactive']).optional(),
  // IdVerificationPage's "All" tab means "every commuter who's actually
  // submitted something to review," not literally every commuter —
  // idSubmitted isn't expressible via `status` alone since a submission's
  // verificationStatus can be any of the three values.
  submittedOnly: z.coerce.boolean().optional(),
  search: z.string().trim().min(1).optional(),
  page: z.coerce.number().int().min(1).default(1),
  pageSize: z.coerce.number().int().min(1).max(100).default(25),
});

router.get('/commuters', requireAuth('admin'), async (req, res, next) => {
  try {
    const query = commutersQuerySchema.parse(req.query);
    const where = {
      ...(query.status ? { verificationStatus: query.status.toUpperCase() as 'PENDING' | 'APPROVED' | 'REJECTED' } : {}),
      ...(query.accountStatus ? { isActive: query.accountStatus === 'active' } : {}),
      ...(query.submittedOnly ? { idFrontUrl: { not: null } } : {}),
      ...(query.search
        ? {
            OR: [
              { fullName: { contains: query.search, mode: 'insensitive' as const } },
              { mobileNumber: { contains: query.search, mode: 'insensitive' as const } },
              ...(phoneSearchVariant(query.search)
                ? [{ mobileNumber: { contains: phoneSearchVariant(query.search)!, mode: 'insensitive' as const } }]
                : []),
              { commuterId: { contains: query.search, mode: 'insensitive' as const } },
            ],
          }
        : {}),
    };

    const [commuters, totalCommuters] = await Promise.all([
      prisma.commuter.findMany({
        where,
        orderBy: { createdAt: 'desc' },
        skip: (query.page - 1) * query.pageSize,
        take: query.pageSize,
      }),
      prisma.commuter.count({ where }),
    ]);
    const totalPages = Math.max(1, Math.ceil(totalCommuters / query.pageSize));

    res.json({
      commuters: commuters.map((commuter) => ({
        id: commuter.id,
        commuterId: commuter.commuterId,
        fullName: commuter.fullName,
        mobileNumber: commuter.mobileNumber,
        dateOfBirth: commuter.dateOfBirth ? formatDateOnly(commuter.dateOfBirth) : null,
        photoUrl: commuter.photoUrl,
        phoneVerified: commuter.phoneVerifiedAt != null,
        idSubmitted: commuter.idFrontUrl != null,
        verificationStatus: commuter.verificationStatus,
        isActive: commuter.isActive,
        createdAt: commuter.createdAt,
      })),
      currentPage: query.page,
      pageSize: query.pageSize,
      totalCommuters,
      totalPages,
      hasNextPage: query.page < totalPages,
    });
  } catch (err) {
    next(err);
  }
});

router.patch('/commuters/:id/status', requireAuth('admin'), async (req, res, next) => {
  try {
    const id: string = Array.isArray(req.params.id) ? req.params.id[0] : req.params.id;
    const body = setStatusSchema.parse(req.body);

    const commuter = await prisma.commuter.update({ where: { id }, data: { isActive: body.isActive } });

    // No notification on deactivation — requireAuth now force-logs them out
    // on their very next request (see auth.ts), so they're gone before a
    // deactivation notification could ever reach them. Reactivation is the
    // one that's actually worth telling them about, since nothing else in
    // the app would otherwise let them know they can log back in.
    if (commuter.isActive) {
      await notifyCommuter({
        recipientId: commuter.id,
        title: 'Your account has been reactivated',
        message: 'You can now continue using the app.',
      });
    }

    res.json({ commuter: { id: commuter.id, isActive: commuter.isActive } });
  } catch (err) {
    next(err);
  }
});

// Own schema rather than reusing driverDateOfBirth — a commuter's date
// of birth is required (unlike a driver's, which stays optional even
// here), and this message says "commuter" rather than "driver". Still
// enforces the same MIN_ADULT_AGE, so an admin setting/correcting the
// date can't bypass the signup-time check in
// POST /api/commuter/verify-signup-otp.
const setCommuterDateOfBirthSchema = z.object({
  dateOfBirth: dateOnly.nullable().refine((value) => value === null || calculateAge(value) >= MIN_ADULT_AGE, {
    message: `Commuters must be at least ${MIN_ADULT_AGE} years old.`,
  }),
});

// Date of birth is no longer editable by the commuter themselves (see
// PATCH /commuter/me) — only an admin can set/correct it now, same
// verified-by-a-human reasoning as a driver's plate/license number.
router.patch('/commuters/:id/date-of-birth', requireAuth('admin'), async (req, res, next) => {
  try {
    const id: string = Array.isArray(req.params.id) ? req.params.id[0] : req.params.id;
    const body = setCommuterDateOfBirthSchema.parse(req.body);

    const commuter = await prisma.commuter.update({ where: { id }, data: { dateOfBirth: body.dateOfBirth } });

    res.json({
      commuter: {
        id: commuter.id,
        dateOfBirth: commuter.dateOfBirth ? formatDateOnly(commuter.dateOfBirth) : null,
      },
    });
  } catch (err) {
    next(err);
  }
});

router.get('/commuters/:id', requireAuth('admin'), async (req, res, next) => {
  try {
    // Express 5's route-literal param typing infers `id` (unlike other
    // param names used elsewhere in this codebase, e.g. :ticket/:token)
    // as `string | string[]` — narrow it explicitly rather than fight
    // the inference.
    const id: string = Array.isArray(req.params.id) ? req.params.id[0] : req.params.id;
    const commuter = await prisma.commuter.findUnique({ where: { id } });
    if (!commuter) {
      res.status(404).json({ error: 'Commuter not found.' });
      return;
    }

    const totalSignals = await prisma.demandSignal.count({ where: { commuterId: id } });

    res.json({
      commuter: {
        id: commuter.id,
        commuterId: commuter.commuterId,
        fullName: commuter.fullName,
        mobileNumber: commuter.mobileNumber,
        dateOfBirth: commuter.dateOfBirth ? formatDateOnly(commuter.dateOfBirth) : null,
        photoUrl: commuter.photoUrl,
        phoneVerified: commuter.phoneVerifiedAt != null,
        idType: commuter.idType,
        idFrontUrl: commuter.idFrontUrl,
        idBackUrl: commuter.idBackUrl,
        selfieUrl: commuter.selfieUrl,
        verificationStatus: commuter.verificationStatus,
        isActive: commuter.isActive,
        totalSignals,
        createdAt: commuter.createdAt,
      },
    });
  } catch (err) {
    next(err);
  }
});

const commuterRideHistoryQuerySchema = z.object({
  page: z.coerce.number().int().min(1).default(1),
  pageSize: z.coerce.number().int().min(1).max(100).default(25),
});

// Paginated ride history for one commuter — backs the Commuter Detail
// Panel's own ride-history table, split out from GET /commuters/:id above
// the same way GET /drivers/:id/trips is split from GET /drivers/:id (see
// that route's doc comment for why: a fixed take: 30 with no paging used
// to run here, cutting the list off with no way to see older rides and no
// warning that it was even truncated).
router.get('/commuters/:id/trips', requireAuth('admin'), async (req, res, next) => {
  try {
    const id: string = Array.isArray(req.params.id) ? req.params.id[0] : req.params.id;
    const query = commuterRideHistoryQuerySchema.parse(req.query);
    const where = { commuterId: id };

    const [boardings, totalRides] = await Promise.all([
      prisma.tripBoarding.findMany({
        where,
        orderBy: { boardedAt: 'desc' },
        skip: (query.page - 1) * query.pageSize,
        take: query.pageSize,
      }),
      prisma.tripBoarding.count({ where }),
    ]);
    // Batch-joined against Trip/Driver the same way every other
    // cross-model list in this file is, since those are plain string
    // refs, not Prisma relations.
    const tripIds = [...new Set(boardings.map((b) => b.tripId))];
    const trips = await prisma.trip.findMany({ where: { id: { in: tripIds } } });
    const tripsById = new Map(trips.map((t) => [t.id, t]));
    const driversById = await loadDriversById(trips.map((t) => t.driverId));
    const totalPages = Math.max(1, Math.ceil(totalRides / query.pageSize));

    res.json({
      rideHistory: boardings.map((b) => {
        const trip = tripsById.get(b.tripId);
        const driver = trip ? driversById.get(trip.driverId) : undefined;
        return {
          id: b.id,
          driverName: driver?.fullName ?? 'Unknown driver',
          plateNumber: driver?.plateNumber ?? '—',
          route: trip?.route ?? null,
          boardedAt: b.boardedAt,
          alightedAt: b.alightedAt,
        };
      }),
      currentPage: query.page,
      pageSize: query.pageSize,
      totalRides,
      totalPages,
      hasNextPage: query.page < totalPages,
    });
  } catch (err) {
    next(err);
  }
});

const verifySchema = z.object({ status: z.enum(['APPROVED', 'REJECTED']) });

router.post('/commuters/:id/verify', requireAuth('admin'), async (req, res, next) => {
  try {
    const id: string = Array.isArray(req.params.id) ? req.params.id[0] : req.params.id;
    const body = verifySchema.parse(req.body);

    const existing = await prisma.commuter.findUnique({ where: { id } });
    if (!existing) {
      res.status(404).json({ error: 'Commuter not found.' });
      return;
    }
    if (!existing.idFrontUrl) {
      res.status(400).json({ error: 'This commuter has not submitted ID documents yet.' });
      return;
    }

    // Approval is what actually activates the account — a commuter can't
    // log in at all until this flips isActive to true (see the isActive
    // doc comment in schema.prisma). Rejecting explicitly keeps it false
    // rather than relying on the default, in case this is a re-review.
    const commuter = await prisma.commuter.update({
      where: { id },
      data: { verificationStatus: body.status, isActive: body.status === 'APPROVED' },
    });

    res.json({
      commuter: {
        id: commuter.id,
        commuterId: commuter.commuterId,
        verificationStatus: commuter.verificationStatus,
        isActive: commuter.isActive,
      },
    });
  } catch (err) {
    next(err);
  }
});

// ---------------------------------------------------------------------------
// DRIVER STATS — for the Drivers list page.
// ---------------------------------------------------------------------------

router.get('/driver-stats', requireAuth('admin'), async (_req, res, next) => {
  try {
    const now = Date.now();
    const startOfThisMonth = new Date(now);
    startOfThisMonth.setDate(1);
    startOfThisMonth.setHours(0, 0, 0, 0);
    const startOfLastMonth = new Date(startOfThisMonth);
    startOfLastMonth.setMonth(startOfLastMonth.getMonth() - 1);

    const [totalDrivers, activeDrivers, inactiveDrivers, newThisMonth, newLastMonth] = await Promise.all([
      prisma.driver.count(),
      prisma.driver.count({ where: { isActive: true } }),
      prisma.driver.count({ where: { isActive: false } }),
      prisma.driver.count({ where: { createdAt: { gte: startOfThisMonth } } }),
      prisma.driver.count({ where: { createdAt: { gte: startOfLastMonth, lt: startOfThisMonth } } }),
    ]);

    res.json({
      totalDrivers,
      activeDrivers,
      inactiveDrivers,
      totalDriversChangePercent: percentChange(newThisMonth, newLastMonth),
    });
  } catch (err) {
    next(err);
  }
});

// ---------------------------------------------------------------------------
// COMMUTER / PASSENGER STATS — shared by the Commuters page and the
// Passenger Monitoring page (each just shows a different subset of it).
// ---------------------------------------------------------------------------

router.get('/commuter-stats', requireAuth('admin'), async (_req, res, next) => {
  try {
    const now = Date.now();
    const startOfThisMonth = new Date(now);
    startOfThisMonth.setDate(1);
    startOfThisMonth.setHours(0, 0, 0, 0);
    const startOfLastMonth = new Date(startOfThisMonth);
    startOfLastMonth.setMonth(startOfLastMonth.getMonth() - 1);

    const activeTripIds = (await prisma.trip.findMany({ where: { status: 'ACTIVE' }, select: { id: true } })).map(
      (t) => t.id,
    );
    const startOfToday = new Date(now);
    startOfToday.setHours(0, 0, 0, 0);

    const [
      totalCommuters,
      activeCommuters,
      inactiveCommuters,
      currentlyOnBoard,
      demandSignalsToday,
      newThisMonth,
      newLastMonth,
    ] = await Promise.all([
      prisma.commuter.count(),
      prisma.commuter.count({ where: { isActive: true } }),
      prisma.commuter.count({ where: { isActive: false } }),
      prisma.tripBoarding.count({ where: { tripId: { in: activeTripIds }, alightedAt: null } }),
      prisma.demandSignal.count({ where: { createdAt: { gte: startOfToday } } }),
      prisma.commuter.count({ where: { createdAt: { gte: startOfThisMonth } } }),
      prisma.commuter.count({ where: { createdAt: { gte: startOfLastMonth, lt: startOfThisMonth } } }),
    ]);

    res.json({
      totalCommuters,
      activeCommuters,
      inactiveCommuters,
      currentlyOnBoard,
      demandSignalsToday,
      totalCommutersChangePercent: percentChange(newThisMonth, newLastMonth),
    });
  } catch (err) {
    next(err);
  }
});

// ---------------------------------------------------------------------------
// DEMAND SIGNALS — raw pings for the Passenger Live Map's heatmap. Returns
// individual rows (not pre-clustered — the map component buckets them into
// grid cells client-side, same as the driver app's own copy of that logic)
// but never commuterId (see DemandSignal's doc comment in schema.prisma) —
// only ever what's needed to place a dot on a map.
// ---------------------------------------------------------------------------

// Signals older than this are no longer "live demand" — jeepneys on these
// routes pass frequently enough that a ping this old is more likely someone
// who gave up and left (or got picked up outside the app) than someone
// still standing there; showing it anyway just sends a driver somewhere
// with no one to find.
const DEMAND_SIGNAL_WINDOW_MS = 15 * 60 * 1000;

router.get('/demand-signals', requireAuth('admin'), async (_req, res, next) => {
  try {
    const since = new Date(Date.now() - DEMAND_SIGNAL_WINDOW_MS);
    const signals = await prisma.demandSignal.findMany({
      // fulfilledAt: null — a commuter who's already boarded no longer
      // needs a pickup, so their signal stops showing here (see
      // fulfilledAt's doc comment in schema.prisma) even though it's kept
      // in the table.
      where: { createdAt: { gte: since }, fulfilledAt: null },
      orderBy: { createdAt: 'desc' },
      select: { id: true, lat: true, lng: true, createdAt: true, partySize: true },
    });
    res.json({ signals });
  } catch (err) {
    next(err);
  }
});

// ---------------------------------------------------------------------------
// JEEPNEY / TRIP MONITORING
// ---------------------------------------------------------------------------

router.get('/jeepney-stats', requireAuth('admin'), async (_req, res, next) => {
  try {
    const now = new Date();
    const startOfToday = new Date(now);
    startOfToday.setHours(0, 0, 0, 0);
    const startOfYesterday = new Date(startOfToday);
    startOfYesterday.setDate(startOfYesterday.getDate() - 1);

    const [registeredJeepneys, online, tripsToday, tripsYesterday] = await Promise.all([
      prisma.driver.count(),
      prisma.trip.count({ where: { status: 'ACTIVE' } }),
      prisma.trip.count({ where: { startedAt: { gte: startOfToday } } }),
      prisma.trip.count({ where: { startedAt: { gte: startOfYesterday, lt: startOfToday } } }),
    ]);
    // Reconciles with GET /jeepneys, which now lists every registered
    // driver (see that route's doc comment) — Offline is simply
    // everyone not currently online.
    const offline = Math.max(0, registeredJeepneys - online);

    res.json({
      registeredJeepneys,
      online,
      offline,
      // Trips started today vs yesterday — a real, honest proxy for
      // "more/fewer jeepneys running today," not a literal snapshot
      // comparison (which would need historical online/offline logging
      // this app doesn't do).
      onlineChangePercent: percentChange(tripsToday, tripsYesterday),
    });
  } catch (err) {
    next(err);
  }
});

/** Batch-loads {id -> driver} for a list of trips — Trip only stores a
 * plain driverId (see schema.prisma), so list/map views join it in here
 * rather than a Prisma relation. */
async function loadDriversById(driverIds: string[]) {
  const unique = [...new Set(driverIds)];
  const drivers = await prisma.driver.findMany({ where: { id: { in: unique } } });
  return new Map(drivers.map((d) => [d.id, d]));
}

router.get('/trips/active', requireAuth('admin'), async (_req, res, next) => {
  try {
    const trips = await prisma.trip.findMany({ where: { status: 'ACTIVE' }, orderBy: { startedAt: 'desc' } });
    const driversById = await loadDriversById(trips.map((t) => t.driverId));

    res.json({
      trips: trips.map((t) => {
        const driver = driversById.get(t.driverId);
        return {
          id: t.id,
          driverId: t.driverId,
          driverName: driver?.fullName ?? 'Unknown driver',
          plateNumber: driver?.plateNumber ?? '—',
          route: t.route,
          currentLat: t.currentLat,
          currentLng: t.currentLng,
          startedAt: t.startedAt,
        };
      }),
    });
  } catch (err) {
    next(err);
  }
});

const tripsQuerySchema = z.object({
  status: z.enum(['active', 'completed']).optional(),
  page: z.coerce.number().int().min(1).default(1),
  pageSize: z.coerce.number().int().min(1).max(100).default(25),
});

// Paginated — this is what the Trip History page reads (see the admin
// site's TripHistoryPage.tsx). Jeepney Monitoring's own live view reads
// GET /trips/active above instead, which needs no pagination since the
// number of trips actually in progress right now is naturally small.
router.get('/trips', requireAuth('admin'), async (req, res, next) => {
  try {
    const query = tripsQuerySchema.parse(req.query);
    const where = query.status ? { status: query.status.toUpperCase() as 'ACTIVE' | 'COMPLETED' } : undefined;

    const [trips, total] = await Promise.all([
      prisma.trip.findMany({
        where,
        orderBy: { startedAt: 'desc' },
        skip: (query.page - 1) * query.pageSize,
        take: query.pageSize,
      }),
      prisma.trip.count({ where }),
    ]);
    const driversById = await loadDriversById(trips.map((t) => t.driverId));
    // Only ever non-empty for flagged trips that have already been
    // reviewed — needed so a flagged row's card here can show who
    // reviewed it without a second round trip.
    const reviewersById = await loadAdminsById(trips.map((t) => t.reviewedBy));

    res.json({
      trips: trips.map((t) => {
        const driver = driversById.get(t.driverId);
        return {
          id: t.id,
          driverName: driver?.fullName ?? 'Unknown driver',
          plateNumber: driver?.plateNumber ?? '—',
          route: t.route,
          status: t.status,
          startedAt: t.startedAt,
          endedAt: t.endedAt,
          isShortTrip: t.isShortTrip,
          flagReason: t.flagReason,
          driverExplanation: t.driverExplanation,
          explanationSubmittedAt: t.explanationSubmittedAt,
          reviewStatus: t.reviewStatus,
          reviewedAt: t.reviewedAt,
          reviewedByName: t.reviewedBy ? reviewersById.get(t.reviewedBy)?.fullName ?? null : null,
          adminReviewNote: t.adminReviewNote,
        };
      }),
      total,
      page: query.page,
      pageSize: query.pageSize,
    });
  } catch (err) {
    next(err);
  }
});

// Trip records are never hard-deleted from the admin site — a bad trip
// (most commonly a driver's accidental Start Trip immediately followed
// by End Trip) gets flagged instead, same permanent-record principle as
// an auto-detected short trip: the driver still gets a chance to explain
// it, and an admin reviews and marks it Valid/Invalid rather than making
// it disappear with no trail. This reuses that exact pipeline — an
// admin-initiated flag sets the same isShortTrip/flagReason a backend
// auto-detection would, so every downstream piece (driver's Explain
// screen, admin's review panel, notifications) already just works.
router.patch('/trips/:id/flag', requireAuth('admin'), async (req, res, next) => {
  try {
    const id: string = Array.isArray(req.params.id) ? req.params.id[0] : req.params.id;
    const trip = await prisma.trip.findUnique({ where: { id } });
    if (!trip) {
      res.status(404).json({ error: 'Trip not found.' });
      return;
    }
    if (trip.status !== 'COMPLETED') {
      // A still-ACTIVE trip's isShortTrip/flagReason gets unconditionally
      // recomputed from duration when it ends (see /trips/:id/end) — flagging
      // it now would just get silently overwritten (or erased entirely) the
      // moment the driver ends it, so only completed trips are flaggable.
      res.status(400).json({ error: 'Only completed trips can be flagged for review.' });
      return;
    }
    if (trip.isShortTrip) {
      res.status(400).json({ error: 'This trip is already flagged.' });
      return;
    }

    const updated = await prisma.trip.update({
      where: { id },
      data: { isShortTrip: true, flagReason: 'Flagged by admin for review.' },
    });

    await notifyDriver({
      recipientId: updated.driverId,
      title: 'Trip Flagged for Review',
      message: `${updated.route ?? 'Your trip'} was flagged by an admin for review. Tap to explain what happened.`,
      type: 'TRIP_SHORT_FLAGGED',
      referenceId: updated.id,
    });

    res.json({ trip: { id: updated.id, isShortTrip: updated.isShortTrip, flagReason: updated.flagReason } });
  } catch (err) {
    next(err);
  }
});

// Undoes an admin-initiated flag — deliberately narrower than "clear any
// flag": only reverses one this same endpoint set (matched by the exact
// [flagReason] it writes), and only before a review has happened. A
// backend-auto-detected short trip carries real duration signal that
// shouldn't be erasable from the admin UI, and once reviewStatus has moved
// past PENDING the flag is part of the permanent review trail (see this
// route file's Trip records are never hard-deleted comment above) — this
// is purely an "I clicked Flag by mistake" undo, not a way to un-review
// something.
router.delete('/trips/:id/flag', requireAuth('admin'), async (req, res, next) => {
  try {
    const id: string = Array.isArray(req.params.id) ? req.params.id[0] : req.params.id;
    const trip = await prisma.trip.findUnique({ where: { id } });
    if (!trip) {
      res.status(404).json({ error: 'Trip not found.' });
      return;
    }
    if (!trip.isShortTrip) {
      res.status(400).json({ error: 'This trip is not flagged.' });
      return;
    }
    if (trip.flagReason !== 'Flagged by admin for review.') {
      res.status(400).json({ error: 'Only an admin-initiated flag can be undone — this trip was flagged automatically.' });
      return;
    }
    if (trip.reviewStatus !== 'PENDING') {
      res.status(400).json({ error: 'This flag has already been reviewed and is part of the trip record.' });
      return;
    }

    const updated = await prisma.trip.update({
      where: { id },
      data: { isShortTrip: false, flagReason: null, driverExplanation: null, explanationSubmittedAt: null },
    });

    await notifyDriver({
      recipientId: updated.driverId,
      title: 'Trip Flag Removed',
      message: `${updated.route ?? 'Your trip'} is no longer flagged for review — no action needed.`,
      type: 'TRIP_SHORT_FLAGGED',
      referenceId: updated.id,
    });

    res.json({ trip: { id: updated.id, isShortTrip: updated.isShortTrip, flagReason: updated.flagReason } });
  } catch (err) {
    next(err);
  }
});

/** Batch-loads {id -> admin} for a list of reviewer ids — same pattern as
 * loadDriversById above (Trip.reviewedBy is a plain string, not a Prisma
 * relation). */
async function loadAdminsById(adminIds: (string | null)[]) {
  const unique = [...new Set(adminIds.filter((id): id is string => id !== null))];
  if (unique.length === 0) return new Map<string, { id: string; fullName: string }>();
  const admins = await prisma.admin.findMany({ where: { id: { in: unique } } });
  return new Map(admins.map((a) => [a.id, a]));
}

const reviewTripSchema = z
  .object({
    status: z.enum(['REVIEWED', 'VALID', 'INVALID']),
    note: z.string().trim().max(1000).optional(),
  })
  .refine((data) => data.status !== 'INVALID' || (data.note && data.note.length > 0), {
    message: 'A note is required when marking a trip invalid.',
    path: ['note'],
  });

// The admin verdict on a flagged trip — REVIEWED is a neutral "looked at,
// no verdict yet" state, VALID/INVALID are the two actual verdicts (see
// TripReviewStatus's doc comment in schema.prisma). Never touches
// isShortTrip/flagReason/driverExplanation — this only ever writes the
// review trail, and only for a trip that was actually flagged, so a
// stray call against an unflagged trip's id can't fabricate a review.
router.patch('/trips/:id/review', requireAuth('admin'), async (req, res, next) => {
  try {
    const id: string = Array.isArray(req.params.id) ? req.params.id[0] : req.params.id;
    const body = reviewTripSchema.parse(req.body);

    const trip = await prisma.trip.findUnique({ where: { id } });
    if (!trip || !trip.isShortTrip) {
      res.status(404).json({ error: 'Flagged trip not found.' });
      return;
    }

    const updated = await prisma.trip.update({
      where: { id },
      data: {
        reviewStatus: body.status,
        reviewedAt: new Date(),
        reviewedBy: req.auth!.sub,
        adminReviewNote: body.note && body.note.length > 0 ? body.note : null,
      },
    });

    // Lets the driver know without them having to go check Trip History —
    // same general pattern as every other server-triggered notification
    // in this app (see notify's doc comment).
    const resultLabel = body.status === 'VALID' ? 'Valid' : body.status === 'INVALID' ? 'Invalid' : 'Reviewed';
    await notifyDriver({
      recipientId: updated.driverId,
      title: 'Short Trip Reviewed',
      message: `Your short trip on ${updated.route ?? 'your route'} at ${formatManilaTime(updated.startedAt)} was reviewed.\nResult: ${resultLabel}\nAdmin Note: ${updated.adminReviewNote ?? 'None'}`,
      type: 'TRIP_REVIEWED',
      referenceId: updated.id,
    });

    res.json({
      trip: {
        id: updated.id,
        reviewStatus: updated.reviewStatus,
        reviewedAt: updated.reviewedAt,
        adminReviewNote: updated.adminReviewNote,
      },
    });
  } catch (err) {
    next(err);
  }
});

router.get('/onboard-passengers', requireAuth('admin'), async (_req, res, next) => {
  try {
    const activeTrips = await prisma.trip.findMany({ where: { status: 'ACTIVE' } });
    const activeTripIds = activeTrips.map((t) => t.id);
    const tripsById = new Map(activeTrips.map((t) => [t.id, t]));
    const driversById = await loadDriversById(activeTrips.map((t) => t.driverId));

    const boardings = await prisma.tripBoarding.findMany({
      where: { tripId: { in: activeTripIds }, alightedAt: null },
      orderBy: { boardedAt: 'desc' },
    });
    const commuterIds = [...new Set(boardings.map((b) => b.commuterId))];
    const commuters = await prisma.commuter.findMany({ where: { id: { in: commuterIds } } });
    const commutersById = new Map(commuters.map((c) => [c.id, c]));

    res.json({
      passengers: boardings.map((b) => {
        const trip = tripsById.get(b.tripId);
        const driver = trip ? driversById.get(trip.driverId) : undefined;
        const commuter = commutersById.get(b.commuterId);
        return {
          id: b.id,
          tripId: b.tripId,
          commuterName: commuter?.fullName ?? 'Unknown commuter',
          mobileNumber: commuter?.mobileNumber ?? null,
          driverName: driver?.fullName ?? 'Unknown driver',
          plateNumber: driver?.plateNumber ?? '—',
          route: trip?.route ?? null,
          boardedAt: b.boardedAt,
        };
      }),
    });
  } catch (err) {
    next(err);
  }
});

// ---------------------------------------------------------------------------
// INCIDENT REPORTS (complaints)
// ---------------------------------------------------------------------------

router.get('/complaint-stats', requireAuth('admin'), async (_req, res, next) => {
  try {
    const now = Date.now();
    const startOfThisMonth = new Date(now);
    startOfThisMonth.setDate(1);
    startOfThisMonth.setHours(0, 0, 0, 0);
    const startOfLastMonth = new Date(startOfThisMonth);
    startOfLastMonth.setMonth(startOfLastMonth.getMonth() - 1);

    const [total, pending, investigating, resolved, rejected, newThisMonth, newLastMonth] = await Promise.all([
      prisma.complaint.count(),
      prisma.complaint.count({ where: { status: 'PENDING' } }),
      prisma.complaint.count({ where: { status: 'INVESTIGATING' } }),
      prisma.complaint.count({ where: { status: 'RESOLVED' } }),
      prisma.complaint.count({ where: { status: 'REJECTED' } }),
      prisma.complaint.count({ where: { createdAt: { gte: startOfThisMonth } } }),
      prisma.complaint.count({ where: { createdAt: { gte: startOfLastMonth, lt: startOfThisMonth } } }),
    ]);

    res.json({
      totalComplaints: total,
      pending,
      investigating,
      resolved,
      rejected,
      totalComplaintsChangePercent: percentChange(newThisMonth, newLastMonth),
    });
  } catch (err) {
    next(err);
  }
});

// Must match COMPLAINT_TYPES in commuter.ts (what a commuter's complaintType
// is actually validated/restricted to at submission) — same reasoning as
// DRIVER_ROUTES being kept in sync across files rather than shared, since
// each file's copy is read-only and small.
const COMPLAINT_TYPES = ['Reckless Driving', 'Overcharging', 'Rude Behavior', 'Route Deviation', 'Other'] as const;

const complaintsQuerySchema = z.object({
  status: z.enum(['pending', 'investigating', 'resolved', 'rejected']).optional(),
  type: z.enum(COMPLAINT_TYPES).optional(),
  search: z.string().trim().min(1).optional(),
  page: z.coerce.number().int().min(1).default(1),
  pageSize: z.coerce.number().int().min(1).max(100).default(25),
});

router.get('/complaints', requireAuth('admin'), async (req, res, next) => {
  try {
    const query = complaintsQuerySchema.parse(req.query);

    // Complaint has no Prisma relation to Driver/Commuter (see the manual
    // findMany-by-id lookups below) — a name/plate search has to resolve
    // matching ids first, then OR them in alongside the fields Complaint
    // does carry directly (complaintType).
    let searchOr: Record<string, unknown>[] | undefined;
    if (query.search) {
      const [matchingDrivers, matchingCommuters] = await Promise.all([
        prisma.driver.findMany({
          where: {
            OR: [
              { fullName: { contains: query.search, mode: 'insensitive' } },
              { plateNumber: { contains: query.search, mode: 'insensitive' } },
            ],
          },
          select: { id: true },
        }),
        prisma.commuter.findMany({
          where: { fullName: { contains: query.search, mode: 'insensitive' } },
          select: { id: true },
        }),
      ]);
      searchOr = [
        { complaintType: { contains: query.search, mode: 'insensitive' as const } },
        { driverId: { in: matchingDrivers.map((d) => d.id) } },
        { complainantId: { in: matchingCommuters.map((c) => c.id) } },
      ];
    }

    const where = {
      ...(query.status ? { status: query.status.toUpperCase() as 'PENDING' | 'INVESTIGATING' | 'RESOLVED' | 'REJECTED' } : {}),
      ...(query.type ? { complaintType: query.type } : {}),
      ...(searchOr ? { OR: searchOr } : {}),
    };

    const [complaints, totalComplaints] = await Promise.all([
      prisma.complaint.findMany({
        where,
        orderBy: { createdAt: 'desc' },
        skip: (query.page - 1) * query.pageSize,
        take: query.pageSize,
      }),
      prisma.complaint.count({ where }),
    ]);

    const commuterIds = [...new Set(complaints.map((c) => c.complainantId))];
    const driverIds = [...new Set(complaints.map((c) => c.driverId))];
    const [commuters, drivers] = await Promise.all([
      prisma.commuter.findMany({ where: { id: { in: commuterIds } } }),
      prisma.driver.findMany({ where: { id: { in: driverIds } } }),
    ]);
    const commutersById = new Map(commuters.map((c) => [c.id, c]));
    const driversById = new Map(drivers.map((d) => [d.id, d]));
    const totalPages = Math.max(1, Math.ceil(totalComplaints / query.pageSize));

    res.json({
      complaints: complaints.map((c) => ({
        id: c.id,
        complainantName: commutersById.get(c.complainantId)?.fullName ?? 'Unknown commuter',
        driverName: driversById.get(c.driverId)?.fullName ?? 'Unknown driver',
        plateNumber: driversById.get(c.driverId)?.plateNumber ?? '—',
        complaintType: c.complaintType,
        status: c.status,
        createdAt: c.createdAt,
      })),
      currentPage: query.page,
      pageSize: query.pageSize,
      totalComplaints,
      totalPages,
      hasNextPage: query.page < totalPages,
    });
  } catch (err) {
    next(err);
  }
});

router.get('/complaints/:id', requireAuth('admin'), async (req, res, next) => {
  try {
    const id: string = Array.isArray(req.params.id) ? req.params.id[0] : req.params.id;
    const complaint = await prisma.complaint.findUnique({ where: { id } });
    if (!complaint) {
      res.status(404).json({ error: 'Complaint not found.' });
      return;
    }

    const [commuter, driver] = await Promise.all([
      prisma.commuter.findUnique({ where: { id: complaint.complainantId } }),
      prisma.driver.findUnique({ where: { id: complaint.driverId } }),
    ]);

    res.json({
      complaint: {
        id: complaint.id,
        complainantName: commuter?.fullName ?? 'Unknown commuter',
        complainantMobileNumber: commuter?.mobileNumber ?? null,
        driverName: driver?.fullName ?? 'Unknown driver',
        plateNumber: driver?.plateNumber ?? '—',
        complaintType: complaint.complaintType,
        description: complaint.description,
        attachmentUrl: complaint.attachmentUrl,
        status: complaint.status,
        createdAt: complaint.createdAt,
      },
    });
  } catch (err) {
    next(err);
  }
});

const complaintStatusSchema = z.object({
  status: z.enum(['INVESTIGATING', 'RESOLVED', 'REJECTED']),
});

router.patch('/complaints/:id/status', requireAuth('admin'), async (req, res, next) => {
  try {
    const id: string = Array.isArray(req.params.id) ? req.params.id[0] : req.params.id;
    const body = complaintStatusSchema.parse(req.body);

    const complaint = await prisma.complaint.update({ where: { id }, data: { status: body.status } });

    const complaintStatusTitle: Record<typeof body.status, string> = {
      INVESTIGATING: 'Your complaint is being investigated',
      RESOLVED: 'Your complaint was resolved',
      REJECTED: 'Your complaint was rejected',
    };
    await notifyCommuter({
      recipientId: complaint.complainantId,
      title: complaintStatusTitle[body.status],
      message: `${complaint.complaintType} — status updated to ${body.status.toLowerCase()}.`,
    });

    res.json({ complaint: { id: complaint.id, status: complaint.status } });
  } catch (err) {
    next(err);
  }
});

// ---------------------------------------------------------------------------
// ADMIN ACCOUNTS — Settings -> Admin Accounts (see AdminRole's doc comment
// in schema.prisma). Viewing the roster is open to any admin (it's just
// read-only context for a regular ADMIN); every mutation here — create,
// change role, deactivate/reactivate, reset password — is Main-Admin-only
// (requireMainAdmin, checked fresh from the database on every call, never
// trusted from the JWT) and additionally guards the Main Admin account
// itself against being retargeted by any of them.
// ---------------------------------------------------------------------------

router.get('/admins', requireAuth('admin'), async (_req, res, next) => {
  try {
    const admins = await prisma.admin.findMany({ orderBy: { createdAt: 'asc' } });
    res.json({ admins: admins.map(toPublicAdmin) });
  } catch (err) {
    next(err);
  }
});

const createAdminSchema = z.object({
  fullName: z.string().trim().min(1).transform(toTitleCase),
  email: z.string().trim().email(),
  password: z.string().min(8),
});

router.post('/admins', requireAuth('admin'), requireMainAdmin(), async (req, res, next) => {
  try {
    const body = createAdminSchema.parse(req.body);
    const email = normalizeEmail(body.email);

    const existing = await prisma.admin.findUnique({ where: { email } });
    if (existing) {
      res.status(409).json({ error: 'An admin with that email already exists.' });
      return;
    }

    // Always a regular ADMIN — the Main Admin role is a singleton
    // (enforced by a partial unique index, see this model's migration)
    // assigned only once, by scripts/create-admin.ts's own bootstrap
    // logic. There is no "create another Main Admin" path.
    const passwordHash = await bcrypt.hash(body.password, 10);
    const admin = await prisma.admin.create({
      data: { fullName: body.fullName, email, passwordHash, role: 'ADMIN' },
    });

    res.status(201).json({ admin: toPublicAdmin(admin) });
  } catch (err) {
    next(err);
  }
});

const changeRoleSchema = z.object({
  // 'MAIN_ADMIN' is deliberately not an accepted value here — promoting a
  // second account would collide with the singleton Main Admin the moment
  // it happened, and there's no accompanying "demote the current one"
  // step for this endpoint to also perform.
  role: z.literal('ADMIN'),
});

router.patch('/admins/:id/role', requireAuth('admin'), requireMainAdmin(), async (req, res, next) => {
  try {
    const id: string = Array.isArray(req.params.id) ? req.params.id[0] : req.params.id;
    const body = changeRoleSchema.parse(req.body);

    const target = await prisma.admin.findUnique({ where: { id } });
    if (!target) {
      res.status(404).json({ error: 'Admin not found.' });
      return;
    }
    if (target.role === 'MAIN_ADMIN') {
      res.status(400).json({ error: "The Main Admin's role can't be changed." });
      return;
    }

    const updated = await prisma.admin.update({ where: { id }, data: { role: body.role } });
    res.json({ admin: toPublicAdmin(updated) });
  } catch (err) {
    next(err);
  }
});

const setAdminStatusSchema = z.object({ isActive: z.boolean() });

router.patch('/admins/:id/status', requireAuth('admin'), requireMainAdmin(), async (req, res, next) => {
  try {
    const id: string = Array.isArray(req.params.id) ? req.params.id[0] : req.params.id;
    const body = setAdminStatusSchema.parse(req.body);

    const target = await prisma.admin.findUnique({ where: { id } });
    if (!target) {
      res.status(404).json({ error: 'Admin not found.' });
      return;
    }
    if (target.role === 'MAIN_ADMIN') {
      res.status(400).json({ error: 'The Main Admin account can never be deactivated.' });
      return;
    }

    const updated = await prisma.admin.update({ where: { id }, data: { isActive: body.isActive } });
    res.json({ admin: toPublicAdmin(updated) });
  } catch (err) {
    next(err);
  }
});

const resetAdminPasswordSchema = z.object({ newPassword: z.string().min(8) });

router.post('/admins/:id/reset-password', requireAuth('admin'), requireMainAdmin(), async (req, res, next) => {
  try {
    const id: string = Array.isArray(req.params.id) ? req.params.id[0] : req.params.id;
    const body = resetAdminPasswordSchema.parse(req.body);

    if (id === req.auth!.sub) {
      res.status(400).json({ error: 'Use Change Password in Settings to update your own password.' });
      return;
    }

    const target = await prisma.admin.findUnique({ where: { id } });
    if (!target) {
      res.status(404).json({ error: 'Admin not found.' });
      return;
    }

    const passwordHash = await bcrypt.hash(body.newPassword, 10);
    await prisma.admin.update({ where: { id }, data: { passwordHash } });

    res.json({ message: `Password reset for ${target.fullName}.` });
  } catch (err) {
    next(err);
  }
});

// ---------------------------------------------------------------------------
// NOTIFICATIONS — server-triggered async events (see Notification's doc
// comment in schema.prisma). Admin notifications broadcast to the whole
// team (recipientId is null), not one specific admin.
// ---------------------------------------------------------------------------

const notificationsQuerySchema = z.object({
  page: z.coerce.number().int().min(1).default(1),
  pageSize: z.coerce.number().int().min(1).max(100).default(50),
});

router.get('/notifications', requireAuth('admin'), async (req, res, next) => {
  try {
    const query = notificationsQuerySchema.parse(req.query);
    const [notifications, totalNotifications] = await Promise.all([
      prisma.adminNotification.findMany({
        orderBy: { createdAt: 'desc' },
        skip: (query.page - 1) * query.pageSize,
        take: query.pageSize,
      }),
      prisma.adminNotification.count(),
    ]);
    const totalPages = Math.max(1, Math.ceil(totalNotifications / query.pageSize));
    res.json({
      notifications,
      currentPage: query.page,
      pageSize: query.pageSize,
      totalNotifications,
      totalPages,
      hasNextPage: query.page < totalPages,
    });
  } catch (err) {
    next(err);
  }
});

router.post('/notifications/mark-read', requireAuth('admin'), async (req, res, next) => {
  try {
    await prisma.adminNotification.updateMany({
      where: { isRead: false },
      data: { isRead: true },
    });
    res.json({ message: 'Marked read.' });
  } catch (err) {
    next(err);
  }
});

// ---------------------------------------------------------------------------
// OPERATIONS REPORT — aggregates driver daily logs (see DriverDailyLog's
// doc comment in schema.prisma) across all drivers for a date range. Trip
// counts come from the real Trip table instead, since those are honestly
// trackable independent of whether a driver bothered to log their day.
// ---------------------------------------------------------------------------

const operationsReportQuerySchema = z.object({
  days: z.coerce.number().int().min(1).max(366).default(30),
});

router.get('/operations-report', requireAuth('admin'), async (req, res, next) => {
  try {
    const query = operationsReportQuerySchema.parse(req.query);
    // This server is assumed to run in PH time, so local-midnight is the
    // correct real instant for the trip.startedAt (DateTime) cutoff below.
    const since = new Date();
    since.setDate(since.getDate() - query.days);
    since.setHours(0, 0, 0, 0);
    // DriverDailyLog.date is a `@db.Date` column, not a DateTime — Prisma
    // extracts a Date object's *UTC* calendar components when writing/
    // filtering one, and `since` above (local midnight) is one UTC day
    // earlier than intended for any positive UTC offset (PH is UTC+8).
    // Rebuilt via Date.UTC from the same local calendar components so the
    // comparison lands on the right calendar date — see todayDateOnly()'s
    // doc comment in driver.ts for the full reasoning.
    const sinceDateOnly = new Date(Date.UTC(since.getFullYear(), since.getMonth(), since.getDate()));

    const [logs, totalTrips] = await Promise.all([
      prisma.driverDailyLog.findMany({ where: { date: { gte: sinceDateOnly } }, orderBy: { date: 'asc' } }),
      prisma.trip.count({ where: { startedAt: { gte: since } } }),
    ]);

    const totals = logs.reduce(
      (acc, l) => {
        acc.earnings += l.earnings;
        acc.fuelExpense += l.fuelExpense;
        acc.otherExpenses += l.otherExpenses;
        return acc;
      },
      { earnings: 0, fuelExpense: 0, otherExpenses: 0 },
    );

    const seriesByDate = new Map<string, { earnings: number; fuelExpense: number; otherExpenses: number }>();
    for (const l of logs) {
      const key = formatDateOnly(l.date);
      const bucket = seriesByDate.get(key) ?? { earnings: 0, fuelExpense: 0, otherExpenses: 0 };
      bucket.earnings += l.earnings;
      bucket.fuelExpense += l.fuelExpense;
      bucket.otherExpenses += l.otherExpenses;
      seriesByDate.set(key, bucket);
    }
    const series = [...seriesByDate.entries()].map(([date, v]) => ({
      date,
      earnings: v.earnings,
      expenses: v.fuelExpense + v.otherExpenses,
      netIncome: v.earnings - v.fuelExpense - v.otherExpenses,
    }));

    const byDriver = new Map<
      string,
      { earnings: number; fuelExpense: number; otherExpenses: number; daysLogged: number }
    >();
    for (const l of logs) {
      const bucket = byDriver.get(l.driverId) ?? { earnings: 0, fuelExpense: 0, otherExpenses: 0, daysLogged: 0 };
      bucket.earnings += l.earnings;
      bucket.fuelExpense += l.fuelExpense;
      bucket.otherExpenses += l.otherExpenses;
      bucket.daysLogged += 1;
      byDriver.set(l.driverId, bucket);
    }
    const driversById = await loadDriversById([...byDriver.keys()]);
    const perDriver = [...byDriver.entries()]
      .map(([driverId, v]) => {
        const driver = driversById.get(driverId);
        return {
          driverId,
          driverName: driver?.fullName ?? 'Unknown driver',
          plateNumber: driver?.plateNumber ?? '—',
          earnings: v.earnings,
          fuelExpense: v.fuelExpense,
          otherExpenses: v.otherExpenses,
          netIncome: v.earnings - v.fuelExpense - v.otherExpenses,
          daysLogged: v.daysLogged,
        };
      })
      .sort((a, b) => b.netIncome - a.netIncome);

    res.json({
      totalEarnings: totals.earnings,
      totalFuelExpense: totals.fuelExpense,
      totalOtherExpenses: totals.otherExpenses,
      netIncome: totals.earnings - totals.fuelExpense - totals.otherExpenses,
      totalTrips,
      daysWithLogs: seriesByDate.size,
      series,
      perDriver,
    });
  } catch (err) {
    next(err);
  }
});

/** "YYYY-MM-DD" from a Date's own *local* calendar components — distinct
 * from formatDateOnly (UTC getters, for @db.Date columns like
 * DriverDailyLog.date). This app's server is assumed to run in PH time
 * (same assumption GET /operations-report above already makes for its
 * `since` cutoff), so a real DateTime instant's local getters already are
 * its correct Manila calendar date. */
function localDateKey(d: Date): string {
  const year = d.getFullYear().toString().padStart(4, '0');
  const month = (d.getMonth() + 1).toString().padStart(2, '0');
  const day = d.getDate().toString().padStart(2, '0');
  return `${year}-${month}-${day}`;
}

/** Same "YYYY-MM-DD" shape as formatDateOnly (UTC getters) but built from
 * a Date's *local* components — the bridge between localDateKey's world
 * and formatDateOnly's, so a DriverDailyLog day and a Trip.startedAt day
 * that represent the same real calendar date always produce the same map
 * key regardless of which column type they came from. */
function localDateToUtcDateOnlyKey(d: Date): string {
  return formatDateOnly(new Date(Date.UTC(d.getFullYear(), d.getMonth(), d.getDate())));
}

// Full-detail pull backing the Operations Report's XLSX export (Summary +
// Daily Breakdown + By Driver sheets — see ReportsPage.tsx) — distinct from
// GET /operations-report above (which only feeds the live dashboard/chart
// and must keep behaving exactly as it does today): this one additionally
// zero-fills every calendar day in the period (the chart only plots days
// that actually have a log) and breaks trips down per day/per driver,
// neither of which the dashboard needs.
router.get('/operations-report/export', requireAuth('admin'), async (req, res, next) => {
  try {
    const query = operationsReportQuerySchema.parse(req.query);
    // Identical `since` cutoff to GET /operations-report above (same
    // `days` off-by-one and all) — the export's totals need to match
    // what's already on screen exactly, not a redefinition of what "last
    // 30 days" means.
    const since = new Date();
    since.setDate(since.getDate() - query.days);
    since.setHours(0, 0, 0, 0);
    const sinceDateOnly = new Date(Date.UTC(since.getFullYear(), since.getMonth(), since.getDate()));
    const today = new Date();
    today.setHours(0, 0, 0, 0);

    const [logs, trips] = await Promise.all([
      prisma.driverDailyLog.findMany({ where: { date: { gte: sinceDateOnly } }, orderBy: { date: 'asc' } }),
      prisma.trip.findMany({ where: { startedAt: { gte: since } }, select: { driverId: true, startedAt: true } }),
    ]);

    type DayBucket = { earnings: number; fuelExpense: number; otherExpenses: number; trips: number };
    const dailyByDate = new Map<string, DayBucket>();
    for (const d = new Date(since); d <= today; d.setDate(d.getDate() + 1)) {
      dailyByDate.set(localDateToUtcDateOnlyKey(d), { earnings: 0, fuelExpense: 0, otherExpenses: 0, trips: 0 });
    }

    const loggedDates = new Set<string>();
    const totals = { earnings: 0, fuelExpense: 0, otherExpenses: 0 };
    for (const l of logs) {
      const key = formatDateOnly(l.date);
      loggedDates.add(key);
      totals.earnings += l.earnings;
      totals.fuelExpense += l.fuelExpense;
      totals.otherExpenses += l.otherExpenses;
      const bucket = dailyByDate.get(key);
      if (bucket) {
        bucket.earnings += l.earnings;
        bucket.fuelExpense += l.fuelExpense;
        bucket.otherExpenses += l.otherExpenses;
      }
    }
    for (const t of trips) {
      const bucket = dailyByDate.get(localDateToUtcDateOnlyKey(t.startedAt));
      if (bucket) bucket.trips += 1;
    }

    const tripsByDriver = new Map<string, number>();
    for (const t of trips) {
      tripsByDriver.set(t.driverId, (tripsByDriver.get(t.driverId) ?? 0) + 1);
    }

    const byDriver = new Map<
      string,
      { earnings: number; fuelExpense: number; otherExpenses: number; daysLogged: number }
    >();
    for (const l of logs) {
      const bucket = byDriver.get(l.driverId) ?? { earnings: 0, fuelExpense: 0, otherExpenses: 0, daysLogged: 0 };
      bucket.earnings += l.earnings;
      bucket.fuelExpense += l.fuelExpense;
      bucket.otherExpenses += l.otherExpenses;
      bucket.daysLogged += 1;
      byDriver.set(l.driverId, bucket);
    }
    const driversById = await loadDriversById([...byDriver.keys()]);
    const perDriver = [...byDriver.entries()]
      .map(([driverId, v]) => {
        const driver = driversById.get(driverId);
        return {
          driverId,
          driverName: driver?.fullName ?? 'Unknown driver',
          plateNumber: driver?.plateNumber ?? '—',
          earnings: v.earnings,
          fuelExpense: v.fuelExpense,
          otherExpenses: v.otherExpenses,
          netIncome: v.earnings - v.fuelExpense - v.otherExpenses,
          trips: tripsByDriver.get(driverId) ?? 0,
          daysLogged: v.daysLogged,
        };
      })
      .sort((a, b) => b.netIncome - a.netIncome);

    const daily = [...dailyByDate.entries()]
      .sort(([a], [b]) => (a < b ? -1 : a > b ? 1 : 0))
      .map(([date, v]) => ({
        date,
        earnings: v.earnings,
        fuelExpense: v.fuelExpense,
        otherExpenses: v.otherExpenses,
        totalExpenses: v.fuelExpense + v.otherExpenses,
        netIncome: v.earnings - v.fuelExpense - v.otherExpenses,
        trips: v.trips,
      }));

    res.json({
      reportPeriodLabel: `Last ${query.days} Days`,
      summary: {
        totalEarnings: totals.earnings,
        totalFuelExpense: totals.fuelExpense,
        totalOtherExpenses: totals.otherExpenses,
        totalExpenses: totals.fuelExpense + totals.otherExpenses,
        netIncome: totals.earnings - totals.fuelExpense - totals.otherExpenses,
        totalTrips: trips.length,
        daysWithLogs: loggedDates.size,
      },
      daily,
      perDriver,
    });
  } catch (err) {
    next(err);
  }
});

// ---------------------------------------------------------------------------
// EXPORTS — full-dataset pulls for the Reports page's export buttons (one
// per dataset: Drivers, Commuters, Trips, Incident Reports — see
// ReportsPage.tsx). Distinct from the paginated list endpoints above: an
// export needs the whole matching set in one response, not one page of it.
// Still bounded (EXPORT_ROW_CAP) rather than truly unbounded, so a dataset
// that's grown huge degrades to "capped export" instead of a multi-minute
// query.
// ---------------------------------------------------------------------------

const EXPORT_ROW_CAP = 5000;

// Shared by every export below — an explicit From/To (Reports page's
// "Also export" date filter) narrows to that window; omitting both keeps
// each export's existing default (full roster for Drivers/Commuters, the
// `days` preset for Trips/Complaints). `dateTo` is exclusive, same
// "day-after, midnight" convention as the admin site's other custom date
// range pickers (see manilaDateRangeForCustom).
const exportDateRangeQuerySchema = z.object({
  dateFrom: z.coerce.date().optional(),
  dateTo: z.coerce.date().optional(),
});

function exportDateWhere(query: { dateFrom?: Date; dateTo?: Date }): { gte?: Date; lt?: Date } | undefined {
  if (!query.dateFrom && !query.dateTo) return undefined;
  return { ...(query.dateFrom ? { gte: query.dateFrom } : {}), ...(query.dateTo ? { lt: query.dateTo } : {}) };
}

router.get('/export/drivers', requireAuth('admin'), async (req, res, next) => {
  try {
    const query = exportDateRangeQuerySchema.parse(req.query);
    const createdAt = exportDateWhere(query);
    const where = createdAt ? { createdAt } : {};

    const [drivers, totalDrivers, activeDrivers, inactiveDrivers] = await Promise.all([
      prisma.driver.findMany({ where, orderBy: { createdAt: 'desc' }, take: EXPORT_ROW_CAP }),
      prisma.driver.count({ where }),
      prisma.driver.count({ where: { ...where, isActive: true } }),
      prisma.driver.count({ where: { ...where, isActive: false } }),
    ]);

    const driverIds = drivers.map((d) => d.id);
    // All-time trip figures (not scoped to the roster's own join-date
    // filter above) — same "total trips this driver has ever run" figure
    // the Driver Detail Panel already shows, not something specific to
    // whatever window narrowed who's *in* this export.
    const [tripCounts, mostRecentTrips] = await Promise.all([
      prisma.trip.groupBy({ by: ['driverId', 'status'], where: { driverId: { in: driverIds } }, _count: { _all: true } }),
      prisma.trip.findMany({
        where: { driverId: { in: driverIds } },
        orderBy: { startedAt: 'desc' },
        distinct: ['driverId'],
        select: { driverId: true, route: true },
      }),
    ]);
    const totalTripsByDriver = new Map<string, number>();
    const completedTripsByDriver = new Map<string, number>();
    for (const row of tripCounts) {
      totalTripsByDriver.set(row.driverId, (totalTripsByDriver.get(row.driverId) ?? 0) + row._count._all);
      if (row.status === 'COMPLETED') completedTripsByDriver.set(row.driverId, row._count._all);
    }
    const latestRouteByDriver = new Map(mostRecentTrips.map((t) => [t.driverId, t.route]));

    res.json({
      // Aggregates, not just the row dump below — same "processed, not
      // raw" shape as the Operations Report CSV's own Summary section
      // (see ReportsPage.tsx's handleDatasetExport, which prints this as
      // a Summary block ahead of the per-row data). Computed via count()
      // against the whole table, not derived from `rows`, so it's still
      // accurate even when `rows` itself is capped (see `truncated`).
      summary: { totalDrivers, activeDrivers, inactiveDrivers },
      rows: drivers.map((d) => ({
        driverId: d.driverId,
        fullName: d.fullName,
        mobileNumber: d.mobileNumber,
        plateNumber: d.plateNumber,
        // A driver picks a route per trip, not a fixed assignment (see
        // Trip's own doc comment) — this is their most recently run one,
        // the closest real thing to a "current route" a roster export can
        // show. Null for a driver who's never started a trip.
        route: latestRouteByDriver.get(d.id) ?? null,
        // Drivers have no ID-verification flow like a commuter's KYC
        // (see Driver's doc comment in schema.prisma) — the closest real
        // equivalent is whether an admin has uploaded their license
        // photos yet (see the Driver Detail Panel's License Photos
        // section), so that's what this reflects.
        licenseVerified: Boolean(d.licenseFrontUrl && d.licenseBackUrl),
        dateOfBirth: d.dateOfBirth ? formatDateOnly(d.dateOfBirth) : null,
        isActive: d.isActive,
        createdAt: d.createdAt,
        totalTrips: totalTripsByDriver.get(d.id) ?? 0,
        completedTrips: completedTripsByDriver.get(d.id) ?? 0,
      })),
      truncated: drivers.length === EXPORT_ROW_CAP,
    });
  } catch (err) {
    next(err);
  }
});

router.get('/export/commuters', requireAuth('admin'), async (req, res, next) => {
  try {
    const query = exportDateRangeQuerySchema.parse(req.query);
    const createdAt = exportDateWhere(query);
    const where = createdAt ? { createdAt } : {};

    const [commuters, totalCommuters, activeCommuters, inactiveCommuters, phoneVerified, pendingVerification, approvedVerification, rejectedVerification] =
      await Promise.all([
        prisma.commuter.findMany({ where, orderBy: { createdAt: 'desc' }, take: EXPORT_ROW_CAP }),
        prisma.commuter.count({ where }),
        prisma.commuter.count({ where: { ...where, isActive: true } }),
        prisma.commuter.count({ where: { ...where, isActive: false } }),
        prisma.commuter.count({ where: { ...where, phoneVerifiedAt: { not: null } } }),
        prisma.commuter.count({ where: { ...where, verificationStatus: 'PENDING' } }),
        prisma.commuter.count({ where: { ...where, verificationStatus: 'APPROVED' } }),
        prisma.commuter.count({ where: { ...where, verificationStatus: 'REJECTED' } }),
      ]);

    // All-time ride count (not scoped to the roster's own join-date filter
    // above) — same reasoning as the driver export's totalTrips.
    const commuterIds = commuters.map((c) => c.id);
    const tripCounts = await prisma.tripBoarding.groupBy({
      by: ['commuterId'],
      where: { commuterId: { in: commuterIds } },
      _count: { _all: true },
    });
    const totalTripsByCommuter = new Map(tripCounts.map((row) => [row.commuterId, row._count._all]));

    res.json({
      summary: {
        totalCommuters,
        activeCommuters,
        inactiveCommuters,
        phoneVerified,
        pendingVerification,
        approvedVerification,
        rejectedVerification,
      },
      rows: commuters.map((c) => ({
        commuterId: c.commuterId,
        fullName: c.fullName,
        mobileNumber: c.mobileNumber,
        dateOfBirth: c.dateOfBirth ? formatDateOnly(c.dateOfBirth) : null,
        phoneVerified: c.phoneVerifiedAt != null,
        verificationStatus: c.verificationStatus,
        isActive: c.isActive,
        createdAt: c.createdAt,
        totalTrips: totalTripsByCommuter.get(c.id) ?? 0,
      })),
      truncated: commuters.length === EXPORT_ROW_CAP,
    });
  } catch (err) {
    next(err);
  }
});

const exportRangeQuerySchema = z.object({
  days: z.coerce.number().int().min(1).max(366).default(30),
  dateFrom: z.coerce.date().optional(),
  dateTo: z.coerce.date().optional(),
});

router.get('/export/trips', requireAuth('admin'), async (req, res, next) => {
  try {
    const query = exportRangeQuerySchema.parse(req.query);
    let startedAt = exportDateWhere(query);
    if (!startedAt) {
      const since = new Date();
      since.setDate(since.getDate() - query.days);
      since.setHours(0, 0, 0, 0);
      startedAt = { gte: since };
    }
    const where = { startedAt };

    const [trips, totalTrips, completedTrips, activeTrips, shortTripsFlagged, reviewPending, reviewValid, reviewInvalid] =
      await Promise.all([
        prisma.trip.findMany({ where, orderBy: { startedAt: 'desc' }, take: EXPORT_ROW_CAP }),
        prisma.trip.count({ where }),
        prisma.trip.count({ where: { ...where, status: 'COMPLETED' } }),
        prisma.trip.count({ where: { ...where, status: 'ACTIVE' } }),
        prisma.trip.count({ where: { ...where, isShortTrip: true } }),
        // Review-outcome counts are scoped to flagged trips only — every
        // trip defaults to reviewStatus PENDING regardless of whether it
        // was ever flagged, so counting PENDING across *all* trips would
        // just be "trips nobody needed to review," not a useful figure.
        prisma.trip.count({ where: { ...where, isShortTrip: true, reviewStatus: 'PENDING' } }),
        prisma.trip.count({ where: { ...where, isShortTrip: true, reviewStatus: 'VALID' } }),
        prisma.trip.count({ where: { ...where, isShortTrip: true, reviewStatus: 'INVALID' } }),
      ]);
    const driversById = await loadDriversById(trips.map((t) => t.driverId));

    res.json({
      summary: {
        totalTrips,
        completedTrips,
        activeTrips,
        shortTripsFlagged,
        reviewPending,
        reviewValid,
        reviewInvalid,
      },
      rows: trips.map((t) => {
        const driver = driversById.get(t.driverId);
        return {
          driverName: driver?.fullName ?? 'Unknown driver',
          plateNumber: driver?.plateNumber ?? '—',
          route: t.route,
          status: t.status,
          startedAt: t.startedAt,
          endedAt: t.endedAt,
          isShortTrip: t.isShortTrip,
          reviewStatus: t.reviewStatus,
        };
      }),
      truncated: trips.length === EXPORT_ROW_CAP,
    });
  } catch (err) {
    next(err);
  }
});

router.get('/export/complaints', requireAuth('admin'), async (req, res, next) => {
  try {
    const query = exportRangeQuerySchema.parse(req.query);
    let createdAt = exportDateWhere(query);
    if (!createdAt) {
      const since = new Date();
      since.setDate(since.getDate() - query.days);
      since.setHours(0, 0, 0, 0);
      createdAt = { gte: since };
    }
    const where = { createdAt };

    const [complaints, totalComplaints, pending, investigating, resolved, rejected] = await Promise.all([
      prisma.complaint.findMany({ where, orderBy: { createdAt: 'desc' }, take: EXPORT_ROW_CAP }),
      prisma.complaint.count({ where }),
      prisma.complaint.count({ where: { ...where, status: 'PENDING' } }),
      prisma.complaint.count({ where: { ...where, status: 'INVESTIGATING' } }),
      prisma.complaint.count({ where: { ...where, status: 'RESOLVED' } }),
      prisma.complaint.count({ where: { ...where, status: 'REJECTED' } }),
    ]);
    const commuterIds = [...new Set(complaints.map((c) => c.complainantId))];
    const driverIds = [...new Set(complaints.map((c) => c.driverId))];
    const tripIds = [...new Set(complaints.map((c) => c.tripId).filter((id): id is string => id != null))];
    const [commuters, drivers, trips] = await Promise.all([
      prisma.commuter.findMany({ where: { id: { in: commuterIds } } }),
      prisma.driver.findMany({ where: { id: { in: driverIds } } }),
      // Only complaints filed from Trip History carry a tripId (see
      // Complaint.tripId's own doc comment) — the general "File a
      // Complaint" flow only has a plate number, so this is empty for
      // those and `route` below just falls back to null.
      prisma.trip.findMany({ where: { id: { in: tripIds } }, select: { id: true, route: true } }),
    ]);
    const commutersById = new Map(commuters.map((c) => [c.id, c]));
    const driversById = new Map(drivers.map((d) => [d.id, d]));
    const routeByTripId = new Map(trips.map((t) => [t.id, t.route]));

    res.json({
      summary: { totalComplaints, pending, investigating, resolved, rejected },
      rows: complaints.map((c) => {
        // No dedicated resolution note/resolvedAt field on Complaint (see
        // its doc comment in schema.prisma) — nothing else updates a
        // complaint after creation except its own status, so updatedAt
        // *is* honestly "when this was last resolved" once it's actually
        // sitting in one of the two terminal states.
        const isTerminal = c.status === 'RESOLVED' || c.status === 'REJECTED';
        return {
          id: c.id,
          complainantName: commutersById.get(c.complainantId)?.fullName ?? 'Unknown commuter',
          driverName: driversById.get(c.driverId)?.fullName ?? 'Unknown driver',
          plateNumber: driversById.get(c.driverId)?.plateNumber ?? '—',
          route: c.tripId ? (routeByTripId.get(c.tripId) ?? null) : null,
          complaintType: c.complaintType,
          description: c.description,
          status: c.status,
          resolution: isTerminal ? c.status : null,
          resolvedAt: isTerminal ? c.updatedAt : null,
          createdAt: c.createdAt,
        };
      }),
      truncated: complaints.length === EXPORT_ROW_CAP,
    });
  } catch (err) {
    next(err);
  }
});

export default router;
