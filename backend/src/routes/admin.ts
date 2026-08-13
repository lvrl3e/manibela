import { randomBytes } from 'node:crypto';
import { Router } from 'express';
import bcrypt from 'bcryptjs';
import { z } from 'zod';

import { prisma } from '../lib/prisma';
import { toE164 } from '../utils/phone';
import { isValidPlateNumber, normalizePlateNumber } from '../utils/plate';
import { generateDriverId } from '../utils/driverId';
import { generateQrToken } from '../utils/qrToken';
import { signAuthToken } from '../utils/jwt';
import { formatDateOnly } from '../utils/date';
import { requireAuth } from '../middleware/auth';

const router = Router();

const RESET_TOKEN_TTL_MINUTES = 30;

function toPublicAdmin(admin: { id: string; email: string; fullName: string }) {
  return { id: admin.id, email: admin.email, fullName: admin.fullName };
}

function normalizeEmail(email: string): string {
  return email.trim().toLowerCase();
}

// ---------------------------------------------------------------------------
// LOGIN
// ---------------------------------------------------------------------------
// No self-registration — admin accounts are created via the create-admin
// CLI script (mirrors scripts/create-driver.ts), not through the API.

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

    const valid = await bcrypt.compare(body.password, admin.passwordHash);
    if (!valid) {
      res.status(401).json({ error: 'Incorrect password.' });
      return;
    }

    const token = signAuthToken({ sub: admin.id, role: 'admin' });
    res.json({ token, admin: toPublicAdmin(admin) });
  } catch (err) {
    next(err);
  }
});

// ---------------------------------------------------------------------------
// FORGOT PASSWORD — email a single-use reset link/token, then redeem it.
// Deliberately separate from OtpCode/OtpPurpose (those are PH-mobile-number
// SMS codes); this is an email-addressed link, matching how admin accounts
// authenticate differently from commuter/driver. No email provider is
// wired up yet, so — same as OTP codes today — the token is logged to the
// server console instead of actually being emailed.
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

    // Invalidate any earlier unconsumed tokens so only the latest works —
    // mirrors issueOtp's behavior for the same reason.
    await prisma.adminPasswordReset.updateMany({
      where: { adminId: admin.id, consumed: false },
      data: { consumed: true },
    });

    const token = randomBytes(24).toString('base64url');
    await prisma.adminPasswordReset.create({
      data: {
        adminId: admin.id,
        token,
        expiresAt: new Date(Date.now() + RESET_TOKEN_TTL_MINUTES * 60_000),
      },
    });

    console.log(`[ADMIN PASSWORD RESET] token for ${email}: ${token}`);
    res.json({ message: 'A password reset link has been sent.' });
  } catch (err) {
    next(err);
  }
});

const resetPasswordSchema = z.object({
  token: z.string().min(1),
  newPassword: z.string().min(8),
});

router.post('/reset-password', async (req, res, next) => {
  try {
    const body = resetPasswordSchema.parse(req.body);

    const reset = await prisma.adminPasswordReset.findUnique({ where: { token: body.token } });
    if (!reset || reset.consumed || reset.expiresAt < new Date()) {
      res.status(400).json({ error: 'Invalid or expired reset link.' });
      return;
    }

    const passwordHash = await bcrypt.hash(body.newPassword, 10);
    await prisma.admin.update({ where: { id: reset.adminId }, data: { passwordHash } });
    await prisma.adminPasswordReset.update({ where: { id: reset.id }, data: { consumed: true } });

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

const updateProfileSchema = z.object({ fullName: z.string().trim().min(1) });

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
    // UTC throughout (cutoff and bucketing both) so day boundaries are
    // unambiguous regardless of the server's local timezone — the same
    // class of bug fixed for dateOfBirth elsewhere in this codebase.
    const today = new Date();
    const todayUtcMidnight = Date.UTC(today.getUTCFullYear(), today.getUTCMonth(), today.getUTCDate());
    const since = new Date(todayUtcMidnight - (days - 1) * 24 * 60 * 60 * 1000);

    const [drivers, commuters] = await Promise.all([
      prisma.driver.findMany({ where: { createdAt: { gte: since } }, select: { createdAt: true } }),
      prisma.commuter.findMany({ where: { createdAt: { gte: since } }, select: { createdAt: true } }),
    ]);

    const dayKey = (d: Date) => d.toISOString().slice(0, 10);

    const driverCounts = new Map<string, number>();
    for (const d of drivers) driverCounts.set(dayKey(d.createdAt), (driverCounts.get(dayKey(d.createdAt)) ?? 0) + 1);

    const commuterCounts = new Map<string, number>();
    for (const c of commuters) {
      commuterCounts.set(dayKey(c.createdAt), (commuterCounts.get(dayKey(c.createdAt)) ?? 0) + 1);
    }

    const series: { date: string; drivers: number; commuters: number }[] = [];
    for (let i = 0; i < days; i++) {
      const date = new Date(since.getTime() + i * 24 * 60 * 60 * 1000);
      const key = dayKey(date);
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

router.get('/drivers', requireAuth('admin'), async (_req, res, next) => {
  try {
    const drivers = await prisma.driver.findMany({ orderBy: { createdAt: 'desc' } });
    res.json({
      drivers: drivers.map((driver) => ({
        id: driver.id,
        driverId: driver.driverId,
        fullName: driver.fullName,
        mobileNumber: driver.mobileNumber,
        plateNumber: driver.plateNumber,
        dateOfBirth: driver.dateOfBirth ? formatDateOnly(driver.dateOfBirth) : null,
        photoUrl: driver.photoUrl,
        createdAt: driver.createdAt,
      })),
    });
  } catch (err) {
    next(err);
  }
});

// The real, operator-gated version of what POST /api/driver/signup's own
// comment calls out as still missing — drivers don't self-register, an
// admin creates the account on their behalf.
const createDriverSchema = z.object({
  fullName: z.string().trim().min(1),
  mobileNumber: z.string().trim().min(1),
  password: z.string().min(8),
  plateNumber: z
    .string()
    .trim()
    .min(1)
    .transform((value) => normalizePlateNumber(value))
    .refine(isValidPlateNumber, {
      message: 'Plate number must be 3 letters followed by 3 numbers (e.g. ABC123).',
    }),
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
        dateOfBirth: null,
        photoUrl: null,
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
});

router.get('/commuters', requireAuth('admin'), async (req, res, next) => {
  try {
    const query = commutersQuerySchema.parse(req.query);
    const commuters = await prisma.commuter.findMany({
      where: query.status ? { verificationStatus: query.status.toUpperCase() as 'PENDING' | 'APPROVED' | 'REJECTED' } : undefined,
      orderBy: { createdAt: 'desc' },
    });
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
        createdAt: commuter.createdAt,
      })),
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
        createdAt: commuter.createdAt,
      },
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

    const commuter = await prisma.commuter.update({
      where: { id },
      data: { verificationStatus: body.status },
    });

    res.json({
      commuter: {
        id: commuter.id,
        commuterId: commuter.commuterId,
        verificationStatus: commuter.verificationStatus,
      },
    });
  } catch (err) {
    next(err);
  }
});

export default router;
