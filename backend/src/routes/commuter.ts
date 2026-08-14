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
import {
  uploadPhoto,
  uploadIdPhotos,
  uploadSelfie,
  uploadComplaintAttachment,
  deleteUploadedPhoto,
} from '../middleware/upload';
import { normalizePlateNumber } from '../utils/plate';
import { toTitleCase } from '../utils/text';
import { notifyDriver, notifyCommuter, notifyAdmin } from '../utils/notify';

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
  fullName: z.string().trim().min(1).transform(toTitleCase),
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

// ---------------------------------------------------------------------------
// ID + FACE VERIFICATION (unauthenticated — no account exists yet at this
// point in the flow, so the unguessable ticket itself is what gates these,
// same as /signup below). Both just persist the uploaded photos onto the
// pending signup row; neither runs any actual verification against them —
// see the TODO on the face-verification screen for the still-mocked
// face-match step.
// ---------------------------------------------------------------------------

router.post('/signup/:ticket/id-photos', (req, res, next) => {
  uploadIdPhotos(req, res, async (err) => {
    if (err) {
      res.status(400).json({ error: err instanceof Error ? err.message : 'Upload failed.' });
      return;
    }

    try {
      const pending = await prisma.pendingCommuterSignup.findUnique({
        where: { ticket: req.params.ticket },
      });
      if (!pending || pending.expiresAt < new Date()) {
        res.status(400).json({
          error: 'Your verification has expired. Please start sign-up again from the beginning.',
        });
        return;
      }

      const files = req.files as { front?: Express.Multer.File[]; back?: Express.Multer.File[] } | undefined;
      const front = files?.front?.[0];
      const back = files?.back?.[0];
      if (!front || !back) {
        res.status(400).json({ error: 'Both the front and back of your ID are required.' });
        return;
      }

      const idType = typeof req.body.idType === 'string' ? req.body.idType.trim() : '';
      if (!idType) {
        res.status(400).json({ error: 'ID type is required.' });
        return;
      }

      const idFrontUrl = `/uploads/id-photos/${front.filename}`;
      const idBackUrl = `/uploads/id-photos/${back.filename}`;

      await prisma.pendingCommuterSignup.update({
        where: { id: pending.id },
        data: { idType, idFrontUrl, idBackUrl },
      });

      // Only after the DB update succeeds, and only the previous pair —
      // never leave the record pointing at files that got deleted out
      // from under it. Covers a retry re-uploading over an earlier pick.
      deleteUploadedPhoto(pending.idFrontUrl);
      deleteUploadedPhoto(pending.idBackUrl);

      res.json({ message: 'ID photos uploaded.' });
    } catch (err2) {
      next(err2);
    }
  });
});

router.post('/signup/:ticket/selfie', (req, res, next) => {
  uploadSelfie(req, res, async (err) => {
    if (err) {
      res.status(400).json({ error: err instanceof Error ? err.message : 'Upload failed.' });
      return;
    }
    if (!req.file) {
      res.status(400).json({ error: 'No selfie was uploaded.' });
      return;
    }

    try {
      const pending = await prisma.pendingCommuterSignup.findUnique({
        where: { ticket: req.params.ticket },
      });
      if (!pending || pending.expiresAt < new Date()) {
        res.status(400).json({
          error: 'Your verification has expired. Please start sign-up again from the beginning.',
        });
        return;
      }

      const selfieUrl = `/uploads/selfies/${req.file.filename}`;

      await prisma.pendingCommuterSignup.update({
        where: { id: pending.id },
        data: { selfieUrl },
      });

      deleteUploadedPhoto(pending.selfieUrl);

      res.json({ message: 'Selfie uploaded.' });
    } catch (err2) {
      next(err2);
    }
  });
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
        idType: pending.idType,
        idFrontUrl: pending.idFrontUrl,
        idBackUrl: pending.idBackUrl,
        selfieUrl: pending.selfieUrl,
        // Submitting docs is what puts an account in the admin review
        // queue — no docs yet (null) is a different state from "waiting
        // on a human," which is why this isn't just "always PENDING".
        verificationStatus: pending.idFrontUrl ? 'PENDING' : null,
      },
    });

    await prisma.pendingCommuterSignup.delete({ where: { id: pending.id } });

    if (commuter.verificationStatus === 'PENDING') {
      await notifyAdmin({
        title: 'New ID verification submitted',
        message: `${commuter.fullName} (${commuter.commuterId}) is waiting for review.`,
        type: 'ID_VERIFICATION_SUBMITTED',
        referenceId: commuter.id,
      });
    }

    // No token here — a brand-new account is never APPROVED yet (that
    // can only happen after an admin reviews it, which can't have
    // happened in the moments since this row was just created), so
    // handing out a session here would let a fresh sign-up skip the
    // exact gate /login enforces. The app sends them to the
    // verification-status screen instead, the same place a blocked
    // /login attempt does.
    res.status(201).json({
      commuter: toPublicCommuter(commuter),
      verificationStatus: commuter.verificationStatus,
    });
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

    // Correct credentials, but no session is issued until an admin has
    // approved the ID/selfie submitted at sign-up — the app shows the
    // verification-status screen instead of logging them in. No token
    // means no way into anything else the API protects, so this is a
    // real gate, not just a client-side redirect. Checked before isActive
    // below: isActive only means something once an account is APPROVED
    // (see its doc comment in schema.prisma), so a still-pending account
    // must get "awaiting verification," never a misleading "deactivated."
    if (commuter.verificationStatus !== 'APPROVED') {
      res.status(403).json({
        error: 'Your account is awaiting identity verification.',
        verificationStatus: commuter.verificationStatus,
      });
      return;
    }

    if (!commuter.isActive) {
      res.status(403).json({ error: 'This account has been deactivated.' });
      return;
    }

    const token = signAuthToken({ sub: commuter.id, role: 'commuter' });
    res.json({ token, commuter: toPublicCommuter(commuter) });
  } catch (err) {
    next(err);
  }
});

const verificationStatusQuerySchema = z.object({
  mobileNumber: z.string().trim().min(1),
});

// Public on purpose — lets the app poll for a status change (approved /
// rejected) without needing the account's password on hand, which is
// what a full login re-check would require. Returns only the review
// state, nothing else about the account.
router.get('/verification-status', async (req, res, next) => {
  try {
    const query = verificationStatusQuerySchema.parse(req.query);
    const mobileNumber = toE164(query.mobileNumber);

    const commuter = await prisma.commuter.findUnique({ where: { mobileNumber } });
    if (!commuter) {
      res.status(404).json({ error: 'This number is not registered.' });
      return;
    }

    res.json({
      verificationStatus: commuter.verificationStatus,
      isActive: commuter.isActive,
    });
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
  fullName: z
    .string()
    .trim()
    .min(1)
    .optional()
    .transform((value) => (value === undefined ? undefined : toTitleCase(value))),
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

      const photoUrl = `/uploads/profile-photos/${req.file.filename}`;
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

const deleteAccountSchema = z.object({
  password: z.string().min(1),
});

// Permanently erases the account — a real delete, not the isActive
// soft-disable admins use. Requires the current password as confirmation
// since this can't be undone. Trips/complaints/demand signals this
// commuter is referenced from aren't cascaded (they're plain string refs,
// not relations — see schema.prisma) and just display "Unknown commuter"
// afterward, same as any other missing-reference case in the admin UI.
router.delete('/me', requireAuth('commuter'), async (req, res, next) => {
  try {
    const body = deleteAccountSchema.parse(req.body);

    const commuter = await prisma.commuter.findUnique({ where: { id: req.auth!.sub } });
    if (!commuter) {
      res.status(404).json({ error: 'Account not found.' });
      return;
    }

    const valid = await bcrypt.compare(body.password, commuter.passwordHash);
    if (!valid) {
      res.status(400).json({ error: 'Incorrect password.' });
      return;
    }

    await prisma.commuter.delete({ where: { id: commuter.id } });

    res.json({ message: 'Account deleted.' });
  } catch (err) {
    next(err);
  }
});

// ---------------------------------------------------------------------------
// DEMAND SIGNALS — "request a ride here". A point-in-time location, not a
// standing request that gets matched to a driver (there's no dispatch
// system) — read by the admin dashboard as a live/recent heatmap.
// ---------------------------------------------------------------------------

const demandSignalSchema = z.object({
  lat: z.number().min(-90).max(90),
  lng: z.number().min(-180).max(180),
});

router.post('/demand-signals', requireAuth('commuter'), async (req, res, next) => {
  try {
    const body = demandSignalSchema.parse(req.body);
    const signal = await prisma.demandSignal.create({
      data: { commuterId: req.auth!.sub, lat: body.lat, lng: body.lng },
    });
    res.status(201).json({ demandSignal: { id: signal.id, lat: signal.lat, lng: signal.lng, createdAt: signal.createdAt } });
  } catch (err) {
    next(err);
  }
});

// ---------------------------------------------------------------------------
// BOARDING — a commuter scanning a driver's QR code while logged in. This
// is the real "I'm on this jeepney" signal (see TripBoarding's doc comment
// in schema.prisma); GET /api/driver/verify-qr/:token stays public/anonymous
// for just previewing who a QR belongs to before deciding to ride.
// ---------------------------------------------------------------------------

const boardSchema = z.object({
  qrToken: z.string().trim().min(1),
});

router.post('/board', requireAuth('commuter'), async (req, res, next) => {
  try {
    const body = boardSchema.parse(req.body);

    const driver = await prisma.driver.findUnique({ where: { qrToken: body.qrToken } });
    if (!driver) {
      res.status(404).json({ error: 'This QR code is not recognized.' });
      return;
    }

    const trip = await prisma.trip.findFirst({ where: { driverId: driver.id, status: 'ACTIVE' } });
    if (!trip) {
      res.status(409).json({ error: "This driver doesn't have an active trip right now." });
      return;
    }

    // Upsert, not create — scanning the same driver's QR again mid-ride
    // (re-confirming, accidental double-scan) shouldn't error or duplicate.
    // Resets alightedAt too: re-scanning after tapping Para Po (e.g. a
    // quick stop, or an accidental tap) is a fresh boarding signal.
    await prisma.tripBoarding.upsert({
      where: { tripId_commuterId: { tripId: trip.id, commuterId: req.auth!.sub } },
      update: { alightedAt: null },
      create: { tripId: trip.id, commuterId: req.auth!.sub },
    });

    res.json({ boarded: true, tripId: trip.id });
  } catch (err) {
    next(err);
  }
});

// Tapping "Para Po" in the booking flow — the app's existing "I'm about to
// get off" signal. Marks this commuter's current boarding(s) as alighted
// so they drop off the admin's "Currently On Board" list right away,
// instead of only when the whole trip ends. No trip id is required from
// the client — a commuter can only realistically be on one active trip's
// boarding list at a time, so this just clears whichever one(s) match.
router.post('/alight', requireAuth('commuter'), async (req, res, next) => {
  try {
    const activeTripIds = (await prisma.trip.findMany({ where: { status: 'ACTIVE' }, select: { id: true } })).map(
      (t) => t.id,
    );
    const openBoardings = await prisma.tripBoarding.findMany({
      where: { commuterId: req.auth!.sub, tripId: { in: activeTripIds }, alightedAt: null },
      select: { tripId: true },
    });
    const updated = await prisma.tripBoarding.updateMany({
      where: { commuterId: req.auth!.sub, tripId: { in: activeTripIds }, alightedAt: null },
      data: { alightedAt: new Date() },
    });

    // Only when this call actually closed out a boarding — a stray/repeat
    // "Para Po" tap with nothing open shouldn't notify.
    if (updated.count > 0) {
      await notifyCommuter({
        recipientId: req.auth!.sub,
        title: 'Trip Completed',
        message: 'Your trip has ended. Thanks for riding with ManibelApp!',
        type: 'TRIP_COMPLETED',
        referenceId: openBoardings[0]?.tripId,
      });
    }

    res.json({ alighted: true });
  } catch (err) {
    next(err);
  }
});

// ---------------------------------------------------------------------------
// TRIP HISTORY — the commuter's own real boardings (see TripBoarding's doc
// comment in schema.prisma), joined with the trip/driver they rode with.
// Backs CommuterHistoryScreen, which used to be SharedPreferences-only.
// Fare/rider-count breakdown stays purely client-side — see FareBreakdown
// on the Flutter side; there's nothing honestly trackable about it
// server-side (same reasoning as DriverDailyLog's earnings: cash, no
// payment system), so this only syncs *which trip, which driver, when*.
// ---------------------------------------------------------------------------

const tripHistoryQuerySchema = z.object({
  days: z.coerce.number().int().min(1).max(366).default(90),
  page: z.coerce.number().int().min(1).default(1),
  pageSize: z.coerce.number().int().min(1).max(100).default(100),
});

router.get('/trips', requireAuth('commuter'), async (req, res, next) => {
  try {
    const query = tripHistoryQuerySchema.parse(req.query);
    const since = new Date();
    since.setDate(since.getDate() - query.days);
    const where = { commuterId: req.auth!.sub, boardedAt: { gte: since } };

    const [boardings, totalTrips] = await Promise.all([
      prisma.tripBoarding.findMany({
        where,
        orderBy: { boardedAt: 'desc' },
        skip: (query.page - 1) * query.pageSize,
        take: query.pageSize,
      }),
      prisma.tripBoarding.count({ where }),
    ]);
    const totalPages = Math.max(1, Math.ceil(totalTrips / query.pageSize));
    if (boardings.length === 0) {
      res.json({ trips: [], currentPage: query.page, pageSize: query.pageSize, totalTrips, totalPages, hasNextPage: false });
      return;
    }

    const tripIds = boardings.map((b) => b.tripId);
    const trips = await prisma.trip.findMany({ where: { id: { in: tripIds } } });
    const tripsById = new Map(trips.map((t) => [t.id, t]));

    const driverIds = [...new Set(trips.map((t) => t.driverId))];
    const drivers = await prisma.driver.findMany({ where: { id: { in: driverIds } } });
    const driversById = new Map(drivers.map((d) => [d.id, d]));

    const [ratingAgg, myRatings, myComplaints] = await Promise.all([
      prisma.rating.groupBy({ by: ['driverId'], where: { driverId: { in: driverIds } }, _avg: { stars: true }, _count: { stars: true } }),
      prisma.rating.findMany({ where: { tripId: { in: tripIds }, commuterId: req.auth!.sub }, select: { tripId: true } }),
      prisma.complaint.findMany({ where: { tripId: { in: tripIds }, complainantId: req.auth!.sub }, select: { tripId: true } }),
    ]);
    const ratingByDriver = new Map(ratingAgg.map((r) => [r.driverId, { avg: r._avg.stars, count: r._count.stars }]));
    const ratedTripIds = new Set(myRatings.map((r) => r.tripId));
    const reportedTripIds = new Set(myComplaints.map((c) => c.tripId).filter((id): id is string => id !== null));

    const result = boardings
      .map((b) => {
        const trip = tripsById.get(b.tripId);
        if (!trip) return null;
        const driver = driversById.get(trip.driverId);
        const ratingInfo = ratingByDriver.get(trip.driverId);
        return {
          tripId: trip.id,
          driverId: trip.driverId,
          driverName: driver?.fullName ?? 'Unknown driver',
          plateNumber: driver?.plateNumber ?? '—',
          route: trip.route,
          boardedAt: b.boardedAt,
          alightedAt: b.alightedAt,
          driverAverageRating: ratingInfo?.avg ?? null,
          driverRatingCount: ratingInfo?.count ?? 0,
          alreadyRated: ratedTripIds.has(trip.id),
          alreadyReported: reportedTripIds.has(trip.id),
        };
      })
      .filter((entry): entry is NonNullable<typeof entry> => entry !== null);

    res.json({
      trips: result,
      currentPage: query.page,
      pageSize: query.pageSize,
      totalTrips,
      totalPages,
      hasNextPage: query.page < totalPages,
    });
  } catch (err) {
    next(err);
  }
});

// ---------------------------------------------------------------------------
// RATINGS — a commuter rating the driver of one specific trip they actually
// boarded (see Rating's doc comment in schema.prisma). One per trip.
// ---------------------------------------------------------------------------

const ratingSchema = z.object({
  stars: z.number().int().min(1).max(5),
  comment: z.string().trim().max(500).optional(),
});

router.post('/trips/:tripId/rating', requireAuth('commuter'), async (req, res, next) => {
  try {
    const tripId: string = Array.isArray(req.params.tripId) ? req.params.tripId[0] : req.params.tripId;
    const body = ratingSchema.parse(req.body);

    const boarding = await prisma.tripBoarding.findUnique({
      where: { tripId_commuterId: { tripId, commuterId: req.auth!.sub } },
    });
    if (!boarding) {
      res.status(404).json({ error: "You didn't board this trip." });
      return;
    }

    const existing = await prisma.rating.findUnique({
      where: { tripId_commuterId: { tripId, commuterId: req.auth!.sub } },
    });
    if (existing) {
      res.status(409).json({ error: "You've already rated this trip." });
      return;
    }

    const trip = await prisma.trip.findUnique({ where: { id: tripId } });
    if (!trip) {
      res.status(404).json({ error: 'Trip not found.' });
      return;
    }

    const rating = await prisma.rating.create({
      data: {
        tripId,
        driverId: trip.driverId,
        commuterId: req.auth!.sub,
        stars: body.stars,
        comment: body.comment ?? null,
      },
    });

    res.status(201).json({ rating: { id: rating.id, stars: rating.stars, comment: rating.comment, createdAt: rating.createdAt } });
  } catch (err) {
    next(err);
  }
});

// ---------------------------------------------------------------------------
// COMPLAINTS — filed against a driver by plate number, since there's no
// per-trip passenger manifest to pick a driver from (see Trip's doc
// comment in schema.prisma). multipart/form-data so an optional photo can
// ride along with it, same reasoning as the photo-upload endpoints above.
// [tripId] is optional — set when filed from Trip History (where the
// commuter picked one particular ride), left out from the general "File a
// Complaint" flow (where they only know the driver's plate).
// ---------------------------------------------------------------------------

const COMPLAINT_TYPES = ['Reckless Driving', 'Overcharging', 'Rude Behavior', 'Route Deviation', 'Other'] as const;

const complaintSchema = z.object({
  plateNumber: z.string().trim().min(1),
  tripId: z.string().trim().min(1).optional(),
  complaintType: z.enum(COMPLAINT_TYPES),
  description: z.string().trim().min(1).max(2000),
});

router.post('/complaints', requireAuth('commuter'), (req, res, next) => {
  uploadComplaintAttachment(req, res, async (err) => {
    if (err) {
      res.status(400).json({ error: err instanceof Error ? err.message : 'Upload failed.' });
      return;
    }

    try {
      const body = complaintSchema.parse(req.body);
      const plateNumber = normalizePlateNumber(body.plateNumber);

      const driver = await prisma.driver.findFirst({ where: { plateNumber } });
      if (!driver) {
        res.status(404).json({ error: `No driver found with plate number ${plateNumber}.` });
        return;
      }

      const complaint = await prisma.complaint.create({
        data: {
          complainantId: req.auth!.sub,
          driverId: driver.id,
          tripId: body.tripId ?? null,
          complaintType: body.complaintType,
          description: body.description,
          attachmentUrl: req.file ? `/uploads/complaint-attachments/${req.file.filename}` : null,
        },
      });

      await notifyDriver({
        recipientId: driver.id,
        title: 'A complaint was filed against you',
        message: `${body.complaintType} — plate ${plateNumber}.`,
      });

      await notifyAdmin({
        title: 'New complaint filed',
        message: `${body.complaintType} against ${plateNumber} — needs review.`,
        type: 'COMPLAINT_FILED',
        referenceId: complaint.id,
      });

      res.status(201).json({ complaint: { id: complaint.id, status: complaint.status, createdAt: complaint.createdAt } });
    } catch (err2) {
      next(err2);
    }
  });
});

// ---------------------------------------------------------------------------
// NOTIFICATIONS — server-triggered async events (see Notification's doc
// comment in schema.prisma). Kept separate from each app's own local,
// client-generated notifications (trip completed, etc.) — the app merges
// both feeds together.
// ---------------------------------------------------------------------------

const notificationsQuerySchema = z.object({
  page: z.coerce.number().int().min(1).default(1),
  pageSize: z.coerce.number().int().min(1).max(100).default(50),
});

router.get('/notifications', requireAuth('commuter'), async (req, res, next) => {
  try {
    const query = notificationsQuerySchema.parse(req.query);
    const where = { recipientId: req.auth!.sub };
    const [notifications, totalNotifications] = await Promise.all([
      prisma.commuterNotification.findMany({
        where,
        orderBy: { createdAt: 'desc' },
        skip: (query.page - 1) * query.pageSize,
        take: query.pageSize,
      }),
      prisma.commuterNotification.count({ where }),
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

router.post('/notifications/mark-read', requireAuth('commuter'), async (req, res, next) => {
  try {
    await prisma.commuterNotification.updateMany({
      where: { recipientId: req.auth!.sub, isRead: false },
      data: { isRead: true },
    });
    res.json({ message: 'Marked read.' });
  } catch (err) {
    next(err);
  }
});

export default router;
