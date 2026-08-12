import { randomBytes } from 'node:crypto';
import { Router } from 'express';
import bcrypt from 'bcryptjs';
import { z } from 'zod';

import { prisma } from '../lib/prisma';
import { toE164 } from '../utils/phone';
import { signAuthToken } from '../utils/jwt';
import { issueOtp, verifyOtp } from '../utils/otp';
import { dateOnly, formatDateOnly } from '../utils/date';
import { requireAuth } from '../middleware/auth';
import { uploadPhoto, deleteUploadedPhoto } from '../middleware/upload';

const router = Router();

const PENDING_SIGNUP_TTL_MINUTES = 30;

/**
 * Next sequential CM-00001, CM-00002, ... id — mirrors generateDriverId
 * (see /utils/driverId.ts). Starts from the current commuter count (fast
 * path, no collision in the common case) and walks forward if that's
 * already taken — covers gaps left by deleted commuters without needing
 * to parse/max every existing id.
 */
async function generateCommuterId(): Promise<string> {
  let next = (await prisma.commuter.count()) + 1;
  for (;;) {
    const candidate = `CM-${next.toString().padStart(5, '0')}`;
    const exists = await prisma.commuter.findUnique({ where: { commuterId: candidate } });
    if (!exists) return candidate;
    next++;
  }
}

function toPublicCommuter(commuter: {
  id: string;
  commuterId: string;
  fullName: string;
  mobileNumber: string;
  dateOfBirth: Date | null;
  photoUrl: string | null;
  phoneVerifiedAt: Date | null;
}) {
  return {
    id: commuter.id,
    commuterId: commuter.commuterId,
    fullName: commuter.fullName,
    mobileNumber: commuter.mobileNumber,
    dateOfBirth: commuter.dateOfBirth ? formatDateOnly(commuter.dateOfBirth) : null,
    photoUrl: commuter.photoUrl,
    phoneVerified: commuter.phoneVerifiedAt != null,
  };
}

// ---------------------------------------------------------------------------
// SIGN UP
// ---------------------------------------------------------------------------
// No Commuter row exists until the entire sign-up flow — phone
// verification AND the ID/face verification steps after it — actually
// finishes. The sequence:
//   1. send-signup-otp   — request a code against a number (no account yet)
//   2. verify-signup-otp — check the code, stash the (now-hashed) signup
//                          details as a PendingCommuterSignup, hand back a
//                          ticket. Still no account yet — the app carries
//                          this ticket through the ID/face verification
//                          screens.
//   3. signup            — redeem the ticket to actually create the
//                          account, once the app reaches the end of that
//                          flow. This is the only place a Commuter row
//                          gets created.
// Abandoning the flow at any point before step 3 leaves nothing behind —
// the phone number stays available and no password ever gets stored.

const sendSignupOtpSchema = z.object({ mobileNumber: z.string().trim().min(1) });

router.post('/send-signup-otp', async (req, res, next) => {
  try {
    const body = sendSignupOtpSchema.parse(req.body);
    const mobileNumber = toE164(body.mobileNumber);

    const existing = await prisma.commuter.findUnique({ where: { mobileNumber } });
    if (existing) {
      res.status(409).json({ error: 'This mobile number is already registered. Please log in instead.' });
      return;
    }

    await issueOtp(mobileNumber, 'SIGNUP_VERIFICATION');
    res.json({ message: 'A verification code has been sent.' });
  } catch (err) {
    next(err);
  }
});

async function generateSignupTicket(): Promise<string> {
  for (;;) {
    const candidate = randomBytes(24).toString('base64url');
    const exists = await prisma.pendingCommuterSignup.findUnique({ where: { ticket: candidate } });
    if (!exists) return candidate;
  }
}

const verifySignupOtpSchema = z.object({
  fullName: z.string().trim().min(1),
  mobileNumber: z.string().trim().min(1),
  password: z.string().min(8),
  code: z.string().length(6),
});

router.post('/verify-signup-otp', async (req, res, next) => {
  try {
    const body = verifySignupOtpSchema.parse(req.body);
    const mobileNumber = toE164(body.mobileNumber);

    const existing = await prisma.commuter.findUnique({ where: { mobileNumber } });
    if (existing) {
      res.status(409).json({ error: 'This number is already registered.' });
      return;
    }

    const ok = await verifyOtp(mobileNumber, 'SIGNUP_VERIFICATION', body.code);
    if (!ok) {
      res.status(400).json({ error: 'Invalid or expired code.' });
      return;
    }

    const passwordHash = await bcrypt.hash(body.password, 10);
    const pending = await prisma.pendingCommuterSignup.create({
      data: {
        ticket: await generateSignupTicket(),
        fullName: body.fullName,
        mobileNumber,
        passwordHash,
        expiresAt: new Date(Date.now() + PENDING_SIGNUP_TTL_MINUTES * 60_000),
      },
    });

    res.json({ ticket: pending.ticket });
  } catch (err) {
    next(err);
  }
});

const signupSchema = z.object({ ticket: z.string().min(1) });

router.post('/signup', async (req, res, next) => {
  try {
    const body = signupSchema.parse(req.body);

    const pending = await prisma.pendingCommuterSignup.findUnique({
      where: { ticket: body.ticket },
    });
    if (!pending || pending.expiresAt < new Date()) {
      res.status(400).json({
        error: 'Your verification has expired. Please start sign-up again from the beginning.',
      });
      return;
    }

    // Re-checked here in case someone else registered this number while
    // this ticket's owner was still working through ID/face verification.
    const existing = await prisma.commuter.findUnique({
      where: { mobileNumber: pending.mobileNumber },
    });
    if (existing) {
      res.status(409).json({ error: 'This number is already registered.' });
      return;
    }

    const commuter = await prisma.commuter.create({
      data: {
        commuterId: await generateCommuterId(),
        fullName: pending.fullName,
        mobileNumber: pending.mobileNumber,
        passwordHash: pending.passwordHash,
        phoneVerifiedAt: new Date(),
      },
    });

    await prisma.pendingCommuterSignup.delete({ where: { id: pending.id } });

    const token = signAuthToken({ sub: commuter.id, role: 'commuter' });
    res.status(201).json({ token, commuter: toPublicCommuter(commuter) });
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

    const commuter = await prisma.commuter.findUnique({ where: { mobileNumber } });
    if (!commuter) {
      res.status(404).json({ error: 'This number is not registered. Please sign up first.' });
      return;
    }

    const valid = await bcrypt.compare(body.password, commuter.passwordHash);
    if (!valid) {
      res.status(401).json({ error: 'Incorrect password.' });
      return;
    }

    const token = signAuthToken({ sub: commuter.id, role: 'commuter' });
    res.json({ token, commuter: toPublicCommuter(commuter) });
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

    const commuter = await prisma.commuter.findUnique({ where: { mobileNumber } });
    if (!commuter) {
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

    // Doesn't consume the code — this is just early feedback ("yes, that's
    // right") before the app moves on to reset-password, which is the
    // call that actually spends it.
    const ok = await verifyOtp(mobileNumber, 'PASSWORD_RESET', body.code, { consume: false });
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

    // Re-checking the code here (rather than trusting a prior /verify-otp
    // call) keeps this endpoint safe to call on its own.
    const ok = await verifyOtp(mobileNumber, 'PASSWORD_RESET', body.code);
    if (!ok) {
      res.status(400).json({ error: 'Invalid or expired code.' });
      return;
    }

    const commuter = await prisma.commuter.findUnique({ where: { mobileNumber } });
    if (!commuter) {
      res.status(404).json({ error: 'This number is not registered.' });
      return;
    }

    const passwordHash = await bcrypt.hash(body.newPassword, 10);
    await prisma.commuter.update({ where: { id: commuter.id }, data: { passwordHash } });

    res.json({ message: 'Password reset successfully.' });
  } catch (err) {
    next(err);
  }
});

// ---------------------------------------------------------------------------
// PROFILE (authenticated)
// ---------------------------------------------------------------------------

router.get('/me', requireAuth('commuter'), async (req, res, next) => {
  try {
    const commuter = await prisma.commuter.findUnique({ where: { id: req.auth!.sub } });
    if (!commuter) {
      res.status(404).json({ error: 'Account not found.' });
      return;
    }
    res.json({ commuter: toPublicCommuter(commuter) });
  } catch (err) {
    next(err);
  }
});

const updateProfileSchema = z.object({
  fullName: z.string().trim().min(1).optional(),
  dateOfBirth: dateOnly.nullable().optional(),
  photoUrl: z.string().trim().min(1).nullable().optional(),
});

router.patch('/me', requireAuth('commuter'), async (req, res, next) => {
  try {
    const body = updateProfileSchema.parse(req.body);

    const commuter = await prisma.commuter.update({
      where: { id: req.auth!.sub },
      data: {
        fullName: body.fullName,
        dateOfBirth: body.dateOfBirth,
        photoUrl: body.photoUrl,
      },
    });

    res.json({ commuter: toPublicCommuter(commuter) });
  } catch (err) {
    next(err);
  }
});

// ---------------------------------------------------------------------------
// CHANGE MOBILE NUMBER (authenticated) — OTP-gated so a number can't be
// swapped onto an account without proving the caller actually controls it.
// send-otp texts the code to the NEW number (not the account's current
// one — there's nothing to prove about a number already on file); verify
// checks it and, only then, actually moves the account onto it.
// ---------------------------------------------------------------------------

const sendPhoneChangeOtpSchema = z.object({ mobileNumber: z.string().trim().min(1) });

router.post('/me/phone/send-otp', requireAuth('commuter'), async (req, res, next) => {
  try {
    const body = sendPhoneChangeOtpSchema.parse(req.body);
    const mobileNumber = toE164(body.mobileNumber);

    const existing = await prisma.commuter.findUnique({ where: { mobileNumber } });
    if (existing && existing.id !== req.auth!.sub) {
      res.status(409).json({ error: 'This mobile number is already registered to another account.' });
      return;
    }

    await issueOtp(mobileNumber, 'PHONE_CHANGE');
    res.json({ message: 'A verification code has been sent.' });
  } catch (err) {
    next(err);
  }
});

const verifyPhoneChangeOtpSchema = z.object({
  mobileNumber: z.string().trim().min(1),
  code: z.string().length(6),
});

router.post('/me/phone/verify', requireAuth('commuter'), async (req, res, next) => {
  try {
    const body = verifyPhoneChangeOtpSchema.parse(req.body);
    const mobileNumber = toE164(body.mobileNumber);

    const ok = await verifyOtp(mobileNumber, 'PHONE_CHANGE', body.code);
    if (!ok) {
      res.status(400).json({ error: 'Invalid or expired code.' });
      return;
    }

    // Re-checked here (not just at send-otp time) in case someone else
    // claimed this number during the window the code was outstanding.
    const existing = await prisma.commuter.findUnique({ where: { mobileNumber } });
    if (existing && existing.id !== req.auth!.sub) {
      res.status(409).json({ error: 'This mobile number is already registered to another account.' });
      return;
    }

    const commuter = await prisma.commuter.update({
      where: { id: req.auth!.sub },
      data: { mobileNumber },
    });

    res.json({ commuter: toPublicCommuter(commuter) });
  } catch (err) {
    next(err);
  }
});

// multipart/form-data, field name "photo" — a plain URL/JSON field
// can't carry binary image data, hence the separate endpoint (and
// separate content type) from PATCH /me above.
router.post('/me/photo', requireAuth('commuter'), (req, res, next) => {
  uploadPhoto(req, res, async (err) => {
    if (err) {
      res.status(400).json({ error: err instanceof Error ? err.message : 'Upload failed.' });
      return;
    }
    if (!req.file) {
      res.status(400).json({ error: 'No photo was uploaded.' });
      return;
    }

    try {
      const existing = await prisma.commuter.findUnique({ where: { id: req.auth!.sub } });
      if (!existing) {
        res.status(404).json({ error: 'Account not found.' });
        return;
      }

      const photoUrl = `/uploads/${req.file.filename}`;
      const commuter = await prisma.commuter.update({
        where: { id: existing.id },
        data: { photoUrl },
      });

      // Only after the DB update succeeds — never leave the record
      // pointing at a file that got deleted out from under it.
      deleteUploadedPhoto(existing.photoUrl);

      res.json({ commuter: toPublicCommuter(commuter) });
    } catch (err2) {
      next(err2);
    }
  });
});

const changePasswordSchema = z.object({
  currentPassword: z.string().min(1),
  newPassword: z.string().min(8),
});

router.patch('/me/password', requireAuth('commuter'), async (req, res, next) => {
  try {
    const body = changePasswordSchema.parse(req.body);

    const commuter = await prisma.commuter.findUnique({ where: { id: req.auth!.sub } });
    if (!commuter) {
      res.status(404).json({ error: 'Account not found.' });
      return;
    }

    const valid = await bcrypt.compare(body.currentPassword, commuter.passwordHash);
    if (!valid) {
      res.status(400).json({ error: 'Current password is incorrect.' });
      return;
    }

    const passwordHash = await bcrypt.hash(body.newPassword, 10);
    await prisma.commuter.update({ where: { id: commuter.id }, data: { passwordHash } });

    res.json({ message: 'Password updated.' });
  } catch (err) {
    next(err);
  }
});

export default router;
