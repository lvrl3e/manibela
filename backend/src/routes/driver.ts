import { randomBytes } from 'node:crypto';
import { Router } from 'express';
import bcrypt from 'bcryptjs';
import { z } from 'zod';

import { prisma } from '../lib/prisma';
import { toE164 } from '../utils/phone';
import { isValidPlateNumber, normalizePlateNumber } from '../utils/plate';
import { generateDriverId } from '../utils/driverId';
import { signAuthToken } from '../utils/jwt';
import { issueOtp, verifyOtp } from '../utils/otp';
import { requireAuth } from '../middleware/auth';

const router = Router();

async function generateQrToken(): Promise<string> {
  for (;;) {
    const candidate = randomBytes(24).toString('base64url');
    const exists = await prisma.driver.findUnique({ where: { qrToken: candidate } });
    if (!exists) return candidate;
  }
}

function toPublicDriver(driver: {
  id: string;
  driverId: string;
  fullName: string;
  mobileNumber: string;
  plateNumber: string;
  photoUrl: string | null;
}) {
  return {
    id: driver.id,
    driverId: driver.driverId,
    fullName: driver.fullName,
    mobileNumber: driver.mobileNumber,
    plateNumber: driver.plateNumber,
    photoUrl: driver.photoUrl,
  };
}

// ---------------------------------------------------------------------------
// SIGN UP
// ---------------------------------------------------------------------------
// Drivers don't self-register in the app — an operator/admin creates their
// account (see DriverSession's doc comment on the Flutter side). There's no
// operator role/auth in this schema yet, so this endpoint is left open for
// now (used by prisma/seed.ts and manual testing); gate it behind an
// operator role before this ever goes further than local dev.

const signupSchema = z.object({
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

router.post('/signup', async (req, res, next) => {
  try {
    const body = signupSchema.parse(req.body);
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
      },
    });

    const token = signAuthToken({ sub: driver.id, role: 'driver' });
    res.status(201).json({ token, driver: toPublicDriver(driver) });
  } catch (err) {
    next(err);
  }
});

// ---------------------------------------------------------------------------
// LOGIN
// ---------------------------------------------------------------------------

const loginSchema = z.object({
  mobileNumber: z.string().trim().min(1),
  password: z.string().min(1),
});

router.post('/login', async (req, res, next) => {
  try {
    const body = loginSchema.parse(req.body);
    const mobileNumber = toE164(body.mobileNumber);

    const driver = await prisma.driver.findUnique({ where: { mobileNumber } });
    if (!driver) {
      res.status(404).json({
        error: "This number isn't registered. Contact your operator to get a driver account.",
      });
      return;
    }

    const valid = await bcrypt.compare(body.password, driver.passwordHash);
    if (!valid) {
      res.status(401).json({ error: 'Incorrect password.' });
      return;
    }

    const token = signAuthToken({ sub: driver.id, role: 'driver' });
    res.json({ token, driver: toPublicDriver(driver) });
  } catch (err) {
    next(err);
  }
});

// ---------------------------------------------------------------------------
// FORGOT PASSWORD — request + verify OTP, then reset
// ---------------------------------------------------------------------------

const mobileOnlySchema = z.object({ mobileNumber: z.string().trim().min(1) });

router.post('/forgot-password', async (req, res, next) => {
  try {
    const body = mobileOnlySchema.parse(req.body);
    const mobileNumber = toE164(body.mobileNumber);

    const driver = await prisma.driver.findUnique({ where: { mobileNumber } });
    if (!driver) {
      res.status(404).json({ error: 'This number is not registered.' });
      return;
    }

    await issueOtp(mobileNumber, 'PASSWORD_RESET');
    res.json({ message: 'A verification code has been sent.' });
  } catch (err) {
    next(err);
  }
});

const verifyOtpSchema = z.object({
  mobileNumber: z.string().trim().min(1),
  code: z.string().length(6),
});

router.post('/verify-otp', async (req, res, next) => {
  try {
    const body = verifyOtpSchema.parse(req.body);
    const mobileNumber = toE164(body.mobileNumber);

    const ok = await verifyOtp(mobileNumber, 'PASSWORD_RESET', body.code);
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
  mobileNumber: z.string().trim().min(1),
  code: z.string().length(6),
  newPassword: z.string().min(8),
});

router.post('/reset-password', async (req, res, next) => {
  try {
    const body = resetPasswordSchema.parse(req.body);
    const mobileNumber = toE164(body.mobileNumber);

    const ok = await verifyOtp(mobileNumber, 'PASSWORD_RESET', body.code);
    if (!ok) {
      res.status(400).json({ error: 'Invalid or expired code.' });
      return;
    }

    const driver = await prisma.driver.findUnique({ where: { mobileNumber } });
    if (!driver) {
      res.status(404).json({ error: 'This number is not registered.' });
      return;
    }

    const passwordHash = await bcrypt.hash(body.newPassword, 10);
    await prisma.driver.update({ where: { id: driver.id }, data: { passwordHash } });

    res.json({ message: 'Password reset successfully.' });
  } catch (err) {
    next(err);
  }
});

// ---------------------------------------------------------------------------
// PROFILE (authenticated)
// ---------------------------------------------------------------------------

router.get('/me', requireAuth('driver'), async (req, res, next) => {
  try {
    const driver = await prisma.driver.findUnique({ where: { id: req.auth!.sub } });
    if (!driver) {
      res.status(404).json({ error: 'Account not found.' });
      return;
    }
    res.json({ driver: toPublicDriver(driver) });
  } catch (err) {
    next(err);
  }
});

const updateProfileSchema = z.object({
  fullName: z.string().trim().min(1).optional(),
  mobileNumber: z.string().trim().min(1).optional(),
  photoUrl: z.string().trim().min(1).nullable().optional(),
});

router.patch('/me', requireAuth('driver'), async (req, res, next) => {
  try {
    const body = updateProfileSchema.parse(req.body);

    const driver = await prisma.driver.update({
      where: { id: req.auth!.sub },
      data: {
        fullName: body.fullName,
        mobileNumber: body.mobileNumber ? toE164(body.mobileNumber) : undefined,
        photoUrl: body.photoUrl,
      },
    });

    res.json({ driver: toPublicDriver(driver) });
  } catch (err) {
    next(err);
  }
});

const changePasswordSchema = z.object({
  currentPassword: z.string().min(1),
  newPassword: z.string().min(8),
});

router.patch('/me/password', requireAuth('driver'), async (req, res, next) => {
  try {
    const body = changePasswordSchema.parse(req.body);

    const driver = await prisma.driver.findUnique({ where: { id: req.auth!.sub } });
    if (!driver) {
      res.status(404).json({ error: 'Account not found.' });
      return;
    }

    const valid = await bcrypt.compare(body.currentPassword, driver.passwordHash);
    if (!valid) {
      res.status(400).json({ error: 'Current password is incorrect.' });
      return;
    }

    const passwordHash = await bcrypt.hash(body.newPassword, 10);
    await prisma.driver.update({ where: { id: driver.id }, data: { passwordHash } });

    res.json({ message: 'Password updated.' });
  } catch (err) {
    next(err);
  }
});

// ---------------------------------------------------------------------------
// QR CODE
// ---------------------------------------------------------------------------
// The QR a driver shows encodes this opaque token, not their driverId
// directly — anyone can forge a QR that *contains* a plausible-looking
// "DR-00001", but only the backend can hand out a token that verify-qr
// below will actually recognize. Rotating it invalidates any
// previously-issued QR code (e.g. if a photo of it leaked).

router.get('/me/qr-token', requireAuth('driver'), async (req, res, next) => {
  try {
    const driver = await prisma.driver.findUnique({ where: { id: req.auth!.sub } });
    if (!driver) {
      res.status(404).json({ error: 'Account not found.' });
      return;
    }

    let { qrToken } = driver;
    if (!qrToken) {
      qrToken = await generateQrToken();
      await prisma.driver.update({ where: { id: driver.id }, data: { qrToken } });
    }

    res.json({ qrToken });
  } catch (err) {
    next(err);
  }
});

router.post('/me/qr-token/rotate', requireAuth('driver'), async (req, res, next) => {
  try {
    const qrToken = await generateQrToken();
    await prisma.driver.update({ where: { id: req.auth!.sub }, data: { qrToken } });
    res.json({ qrToken });
  } catch (err) {
    next(err);
  }
});

// Public on purpose — a commuter scanning a driver's QR isn't authenticated
// as anyone. Only exposes what's already shown on the driver's own QR
// screen (name, driverId, plate), never the mobile number or anything else.
router.get('/verify-qr/:token', async (req, res, next) => {
  try {
    const driver = await prisma.driver.findUnique({ where: { qrToken: req.params.token } });
    if (!driver) {
      res.status(404).json({ error: 'This QR code is not recognized.' });
      return;
    }
    res.json({ driver: toPublicDriver(driver) });
  } catch (err) {
    next(err);
  }
});

export default router;
