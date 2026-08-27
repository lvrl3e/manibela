import { randomBytes } from 'node:crypto';
import { Router } from 'express';
import bcrypt from 'bcryptjs';
import { z } from 'zod';

import { prisma } from '../lib/prisma';
import { toE164 } from '../utils/phone';
import { signAuthToken } from '../utils/jwt';
import { issueOtp, verifyOtp } from '../utils/otp';
import { dateOnly, formatDateOnly, calculateAge, MIN_ADULT_AGE } from '../utils/date';
import { requireAuth } from '../middleware/auth';
import {
  uploadPhoto,
  uploadIdPhotos,
  uploadSelfie,
  uploadComplaintAttachment,
  deleteUploadedPhoto,
  uploadBufferToCloudinary,
} from '../middleware/upload';
import { normalizePlateNumber } from '../utils/plate';
import { toTitleCase } from '../utils/text';
import { notifyDriver, notifyCommuter, notifyAdmin } from '../utils/notify';
import { authLimiter } from '../middleware/rateLimit';

const router = Router();

// Unauthenticated + brute-forceable — see middleware/rateLimit.ts.
router.use(
  [
    '/send-signup-otp',
    '/verify-signup-otp',
    '/signup',
    '/login',
    '/forgot-password',
    '/verify-otp',
    '/reset-password',
  ],
  authLimiter,
);

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
  // .refine() here, not just CommuterSignUpScreen's own client-side
  // check, so a direct API call can't create an under-18 account by
  // skipping whatever the app validates before sending.
  dateOfBirth: dateOnly.refine((value) => calculateAge(value) >= MIN_ADULT_AGE, {
    message: `You must be at least ${MIN_ADULT_AGE} years old to create a commuter account.`,
  }),
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
        dateOfBirth: body.dateOfBirth,
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

      const [idFrontUrl, idBackUrl] = await Promise.all([
        uploadBufferToCloudinary(front.buffer, 'id-photos'),
        uploadBufferToCloudinary(back.buffer, 'id-photos'),
      ]);

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

      const selfieUrl = await uploadBufferToCloudinary(req.file.buffer, 'selfies');

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
        dateOfBirth: pending.dateOfBirth,
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

    // A forgotten-password reset never has the old password to compare
    // client-side (that's the whole point of going through OTP instead),
    // so it has to be caught here.
    const isSamePassword = await bcrypt.compare(body.newPassword, commuter.passwordHash);
    if (isSamePassword) {
      res.status(400).json({ error: 'New password must be different from your current password.' });
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

// dateOfBirth deliberately isn't editable here — only an admin can set it
// now, via PATCH /admin/commuters/:id/date-of-birth (see that endpoint's
// doc comment for why).
const updateProfileSchema = z.object({
  fullName: z
    .string()
    .trim()
    .min(1)
    .optional()
    .transform((value) => (value === undefined ? undefined : toTitleCase(value))),
  photoUrl: z.string().trim().min(1).nullable().optional(),
});

router.patch('/me', requireAuth('commuter'), async (req, res, next) => {
  try {
    const body = updateProfileSchema.parse(req.body);

    const commuter = await prisma.commuter.update({
      where: { id: req.auth!.sub },
      data: {
        fullName: body.fullName,
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

      const photoUrl = await uploadBufferToCloudinary(req.file.buffer, 'profile-photos');
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
// since this can't be undone. Cascades through every table that
// references this commuter first (see below) — Trip itself is the one
// exception, since a Trip belongs to the driver and may carry other
// commuters' boardings too.
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

    // Complaint/Rating/TripBoarding/CommuterNotification/DemandSignal have
    // no real Prisma @relation to Commuter (plain string id columns, no
    // DB-enforced cascade) — a bare `commuter.delete` left every one of
    // these behind, still visible on the admin website (trip history,
    // ratings, complaints) even though the account itself was gone from
    // the app. Walk every table that references this commuter's id first.
    const complaints = await prisma.complaint.findMany({
      where: { complainantId: commuter.id },
      select: { id: true, attachmentUrl: true },
    });
    const complaintIds = complaints.map((c) => c.id);

    await prisma.$transaction([
      prisma.complaint.deleteMany({ where: { complainantId: commuter.id } }),
      prisma.rating.deleteMany({ where: { commuterId: commuter.id } }),
      prisma.tripBoarding.deleteMany({ where: { commuterId: commuter.id } }),
      prisma.demandSignal.deleteMany({ where: { commuterId: commuter.id } }),
      prisma.commuterNotification.deleteMany({ where: { recipientId: commuter.id } }),
      // referenceId covers both an ID-verification notification (points at
      // the commuter's own id) and a complaint-filed notification (points
      // at the complaint's id) — see notifyAdmin call sites in this file.
      prisma.adminNotification.deleteMany({ where: { referenceId: { in: [commuter.id, ...complaintIds] } } }),
      prisma.commuter.delete({ where: { id: commuter.id } }),
    ]);

    // Uploaded files aren't part of the DB transaction — best-effort
    // cleanup after it commits, same as every other delete in this app.
    deleteUploadedPhoto(commuter.photoUrl);
    deleteUploadedPhoto(commuter.idFrontUrl);
    deleteUploadedPhoto(commuter.idBackUrl);
    deleteUploadedPhoto(commuter.selfieUrl);
    for (const complaint of complaints) deleteUploadedPhoto(complaint.attachmentUrl);

    res.json({ message: 'Account deleted.' });
  } catch (err) {
    next(err);
  }
});

// ---------------------------------------------------------------------------
// NEARBY JEEPNEYS — "find a jeepney near me" before a commuter has a
// driver's QR code in front of them. Sourced entirely from real data
// drivers already produce: an ACTIVE trip's currentLat/currentLng, kept
// fresh by the driver app's own location pings (see PATCH
// /api/driver/trips/:id/location). Nothing is simulated — a trip whose
// driver stopped pinging (app closed, forgot to end trip) ages out via
// the staleness cutoff below rather than showing a stale position forever.
// ---------------------------------------------------------------------------

const nearbyJeepneysQuerySchema = z.object({
  lat: z.coerce.number().min(-90).max(90),
  lng: z.coerce.number().min(-180).max(180),
  route: z.string().trim().min(1).optional(),
});

// A driver who hasn't pinged in this long is treated as effectively
// offline for "nearby" purposes, even if they never formally ended the
// trip — same reasoning as Jeepney Monitoring's admin map (see
// JeepneyLiveMapPage's own "today" filter), just a much tighter window
// since this is meant to be genuinely live, not "sometime today".
const NEARBY_STALENESS_MS = 5 * 60 * 1000;

// How far out a commuter can see a jeepney on the map/list — deliberately
// much wider than BOARD_PROXIMITY_METERS below (boarding needs the commuter
// actually at the jeepney; just watching it approach doesn't).
const NEARBY_RADIUS_METERS = 20000;

// Rough city-jeepney travel speed for an ETA estimate — this app has no
// real routing/traffic data, so straight-line distance over an assumed
// average speed is the best available approximation, clearly presented
// as an estimate (see etaMinutes below) rather than implying precision
// the data doesn't support.
const ASSUMED_SPEED_KMH = 15;

// Haversine distance in meters — the two points are always close enough
// (city-scale) that Earth's curvature beyond a spherical approximation
// doesn't matter here.
function distanceMeters(lat1: number, lng1: number, lat2: number, lng2: number): number {
  const R = 6371000;
  const toRad = (deg: number) => (deg * Math.PI) / 180;
  const dLat = toRad(lat2 - lat1);
  const dLng = toRad(lng2 - lng1);
  const a =
    Math.sin(dLat / 2) ** 2 + Math.cos(toRad(lat1)) * Math.cos(toRad(lat2)) * Math.sin(dLng / 2) ** 2;
  return 2 * R * Math.asin(Math.sqrt(a));
}

router.get('/nearby-jeepneys', requireAuth('commuter'), async (req, res, next) => {
  try {
    const query = nearbyJeepneysQuerySchema.parse(req.query);
    const since = new Date(Date.now() - NEARBY_STALENESS_MS);

    const trips = await prisma.trip.findMany({
      where: {
        status: 'ACTIVE',
        currentLat: { not: null },
        currentLng: { not: null },
        locationUpdatedAt: { gte: since },
        ...(query.route ? { route: query.route } : {}),
      },
    });
    if (trips.length === 0) {
      res.json({ jeepneys: [] });
      return;
    }

    const driverIds = [...new Set(trips.map((t) => t.driverId))];
    const [drivers, ratingAgg] = await Promise.all([
      prisma.driver.findMany({ where: { id: { in: driverIds } } }),
      prisma.rating.groupBy({ by: ['driverId'], where: { driverId: { in: driverIds } }, _avg: { stars: true }, _count: { stars: true } }),
    ]);
    const driversById = new Map(drivers.map((d) => [d.id, d]));
    const ratingByDriver = new Map(ratingAgg.map((r) => [r.driverId, { avg: r._avg.stars, count: r._count.stars }]));

    const jeepneys = trips
      .map((trip) => {
        const driver = driversById.get(trip.driverId);
        if (!driver || !driver.isActive) return null;
        const distance = distanceMeters(query.lat, query.lng, trip.currentLat!, trip.currentLng!);
        if (distance > NEARBY_RADIUS_METERS) return null;
        const ratingInfo = ratingByDriver.get(trip.driverId);
        return {
          tripId: trip.id,
          driverName: driver.fullName,
          plateNumber: driver.plateNumber,
          photoUrl: driver.photoUrl,
          route: trip.route,
          lat: trip.currentLat,
          lng: trip.currentLng,
          distanceMeters: Math.round(distance),
          etaMinutes: Math.max(1, Math.round((distance / 1000 / ASSUMED_SPEED_KMH) * 60)),
          averageRating: ratingInfo?.avg ?? null,
          ratingCount: ratingInfo?.count ?? 0,
        };
      })
      .filter((j): j is NonNullable<typeof j> => j !== null)
      .sort((a, b) => a.distanceMeters - b.distanceMeters);

    res.json({ jeepneys });
  } catch (err) {
    next(err);
  }
});

// Whether this commuter is already mid-trip — an open TripBoarding
// (alightedAt still null) on a Trip that's still ACTIVE. Lets the app
// resume the live boarding-status view on launch instead of only ever
// reaching it by walking through the booking flow in that same session
// (e.g. after a force-close, or a trip boarded on another device).
router.get('/active-trip', requireAuth('commuter'), async (req, res, next) => {
  try {
    const boarding = await prisma.tripBoarding.findFirst({
      where: { commuterId: req.auth!.sub, alightedAt: null },
      orderBy: { boardedAt: 'desc' },
    });
    if (!boarding) {
      res.json({ activeTrip: null });
      return;
    }

    const trip = await prisma.trip.findUnique({ where: { id: boarding.tripId } });
    if (!trip || trip.status !== 'ACTIVE') {
      res.json({ activeTrip: null });
      return;
    }

    const driver = await prisma.driver.findUnique({ where: { id: trip.driverId } });
    if (!driver) {
      res.json({ activeTrip: null });
      return;
    }

    const ratingInfo = await prisma.rating.aggregate({
      where: { driverId: driver.id },
      _avg: { stars: true },
      _count: { stars: true },
    });

    res.json({
      activeTrip: {
        tripId: trip.id,
        route: trip.route,
        driverName: driver.fullName,
        plateNumber: driver.plateNumber,
        photoUrl: driver.photoUrl,
        averageRating: ratingInfo._avg.stars,
        ratingCount: ratingInfo._count.stars,
        riders: boarding.riders ?? 1,
        boardedAt: boarding.boardedAt,
        // The jeepney's live position — same currentLat/currentLng the
        // driver's own location pings keep fresh (see PATCH
        // /api/driver/trips/:id/location) — lets the boarding-status
        // screen show the jeepney actually moving, not just a static pin.
        lat: trip.currentLat,
        lng: trip.currentLng,
      },
    });
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

// A commuter this far from the jeepney's own last-known position isn't
// actually standing at it — reject the boarding rather than trust a QR
// scan or proximity tap alone, since either could be attempted from well
// outside boarding range (a screenshotted/shared QR code, a stale
// "nearby" list, etc.). Deliberately tighter than NEARBY_RADIUS_METERS
// above, which only gates *seeing* a jeepney in the list — this gates
// actually boarding it.
const BOARD_PROXIMITY_METERS = 20;

const boardSchema = z
  .object({
    qrToken: z.string().trim().min(1).optional(),
    /// Set instead of qrToken when boarding is triggered by proximity match
    /// rather than a scan — the app already has this from GET
    /// /nearby-jeepneys, so there's no code to decode.
    tripId: z.string().trim().min(1).optional(),
    // The commuter's own current position, checked against the jeepney's
    // last-known location below — see BOARD_PROXIMITY_METERS.
    lat: z.coerce.number().min(-90).max(90),
    lng: z.coerce.number().min(-180).max(180),
    riders: z.number().int().min(1).default(1),
  })
  .refine((data) => !!data.qrToken || !!data.tripId, {
    message: 'Either a QR token or a trip id is required.',
    path: ['qrToken'],
  });

router.post('/board', requireAuth('commuter'), async (req, res, next) => {
  try {
    const body = boardSchema.parse(req.body);

    // Two ways in: a QR scan (deterministic — resolves to exactly one
    // driver) or a proximity match (no code to scan, so the client sends
    // the tripId it already has from GET /nearby-jeepneys instead). Both
    // end at the same place: one specific ACTIVE trip to board.
    let trip;
    if (body.qrToken) {
      const driver = await prisma.driver.findUnique({ where: { qrToken: body.qrToken } });
      if (!driver) {
        res.status(404).json({ error: 'This QR code is not recognized.' });
        return;
      }
      trip = await prisma.trip.findFirst({ where: { driverId: driver.id, status: 'ACTIVE' } });
    } else {
      trip = await prisma.trip.findFirst({ where: { id: body.tripId, status: 'ACTIVE' } });
    }
    if (!trip) {
      res.status(409).json({ error: "This driver doesn't have an active trip right now." });
      return;
    }

    // Only enforceable once the driver has actually pinged a location —
    // fails open (lets the boarding through) rather than blocking every
    // boarding on a trip that hasn't gotten its first location update yet.
    if (trip.currentLat != null && trip.currentLng != null) {
      const distance = distanceMeters(body.lat, body.lng, trip.currentLat, trip.currentLng);
      if (distance > BOARD_PROXIMITY_METERS) {
        res.status(409).json({ error: "You're too far from this jeepney to board. Get closer and try again." });
        return;
      }
    }

    // Reuse an *open* boarding on this trip if one exists — scanning the
    // same driver's QR again mid-ride (re-confirming, accidental
    // double-scan) shouldn't duplicate. But once a boarding's been
    // alighted, this driver's Trip is still ACTIVE (a shift commonly
    // spans a whole day, not one ride), so a genuinely new ride on it —
    // rode out this morning, riding back this evening — gets its own row
    // instead of overwriting/losing the earlier one (see TripBoarding's
    // doc comment in schema.prisma).
    const openBoarding = await prisma.tripBoarding.findFirst({
      where: { tripId: trip.id, commuterId: req.auth!.sub, alightedAt: null },
    });

    let boarding;
    if (openBoarding) {
      boarding = await prisma.tripBoarding.update({
        where: { id: openBoarding.id },
        data: { riders: body.riders },
      });
    } else {
      boarding = await prisma.tripBoarding.create({
        data: {
          tripId: trip.id,
          commuterId: req.auth!.sub,
          riders: body.riders,
        },
      });
    }

    // This commuter's need is fulfilled the moment they board — any of
    // their still-outstanding demand signals should stop showing up as
    // "waiting" on admin/driver maps (see fulfilledAt's doc comment in
    // schema.prisma). Left in the table either way, so the day's
    // demandSignalsToday total in commuter-stats is unaffected.
    await prisma.demandSignal.updateMany({
      where: { commuterId: req.auth!.sub, fulfilledAt: null },
      data: { fulfilledAt: new Date() },
    });

    // boardingId (TripBoarding.id) is the real per-ride identity — tripId
    // alone is ambiguous once a commuter rides the same driver's Trip more
    // than once in a day (out and back), see TripBoarding's doc comment
    // in schema.prisma. The client's Trip History needs this to key its
    // own local cache by so a second ride on the same Trip gets its own
    // entry instead of overwriting the first.
    res.json({ boarded: true, tripId: trip.id, boardingId: boarding.id });
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
// DEMAND SIGNALS — a commuter tapping "Request a ride here" from the live
// map. Anonymous by design (see DemandSignal's doc comment in
// schema.prisma): commuterId is stored so a repeat/duplicate ping could
// theoretically be de-duped later, but no GET endpoint (admin or driver)
// ever returns it — both only ever return grid-cell clusters.
// ---------------------------------------------------------------------------

const demandSignalSchema = z.object({
  lat: z.number().min(-90).max(90),
  lng: z.number().min(-180).max(180),
  route: z.string().trim().min(1).optional(),
  // How many people this commuter is requesting a ride for — a cluster's
  // displayed passenger count sums this instead of counting rows, so a
  // group of 4 booked from one account reads as 4 waiting, not 1.
  partySize: z.number().int().min(1).default(1),
});

router.post('/demand-signals', requireAuth('commuter'), async (req, res, next) => {
  try {
    const body = demandSignalSchema.parse(req.body);

    // At most one *outstanding* (unfulfilled) signal per commuter — the
    // booking flow re-sends this every 10 minutes while still looking
    // (see jeepney_booking_flow_screen.dart) to keep a genuinely-waiting
    // commuter visible past the staleness window; refreshing the existing
    // row in place (rather than creating another) keeps a cluster's count
    // meaning "party sizes of N distinct people," not "N pings from
    // however-many people."
    // Self-healing: if more than one unfulfilled row somehow already
    // exists for this commuter (e.g. a duplicate created before this
    // dedup logic existed), every send here collapses back down to one —
    // the newest is refreshed, any older ones are cleaned up.
    const existing = await prisma.demandSignal.findMany({
      where: { commuterId: req.auth!.sub, fulfilledAt: null },
      orderBy: { createdAt: 'desc' },
    });

    if (existing.length > 0) {
      const [keep, ...duplicates] = existing;
      await prisma.$transaction([
        prisma.demandSignal.update({
          where: { id: keep.id },
          data: {
            lat: body.lat,
            lng: body.lng,
            route: body.route ?? keep.route,
            partySize: body.partySize,
            createdAt: new Date(),
          },
        }),
        ...(duplicates.length > 0
          ? [prisma.demandSignal.deleteMany({ where: { id: { in: duplicates.map((d) => d.id) } } })]
          : []),
      ]);
    } else {
      await prisma.demandSignal.create({
        data: {
          commuterId: req.auth!.sub,
          lat: body.lat,
          lng: body.lng,
          route: body.route,
          partySize: body.partySize,
        },
      });
    }

    res.status(201).json({ message: 'Signal sent.' });
  } catch (err) {
    next(err);
  }
});

// Called when a commuter stops looking without boarding — backed out of
// the booking flow, or left it another way (see _stopDemandSignalKeepAlive
// in jeepney_booking_flow_screen.dart). Without this, their last-sent
// signal would just sit there showing as "still waiting" on admin/driver
// maps for up to DEMAND_SIGNAL_WINDOW_MS after they've actually given up.
// A no-op if they already boarded (see fulfilledAt's doc comment in
// schema.prisma) — nothing outstanding left to cancel in that case.
router.post('/demand-signals/cancel', requireAuth('commuter'), async (req, res, next) => {
  try {
    await prisma.demandSignal.updateMany({
      where: { commuterId: req.auth!.sub, fulfilledAt: null },
      data: { fulfilledAt: new Date() },
    });
    res.json({ message: 'Signal cancelled.' });
  } catch (err) {
    next(err);
  }
});

// ---------------------------------------------------------------------------
// TRIP HISTORY — the commuter's own real boardings (see TripBoarding's doc
// comment in schema.prisma), joined with the trip/driver they rode with.
// Backs CommuterHistoryScreen, which used to be SharedPreferences-only.
// There's no fare/payment feature in this app — riders is a headcount
// only, same reasoning as DriverDailyLog's own earnings staying
// self-reported cash with no payment system behind it.
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
      prisma.rating.findMany({ where: { tripId: { in: tripIds }, commuterId: req.auth!.sub }, select: { tripId: true, stars: true } }),
      prisma.complaint.findMany({ where: { tripId: { in: tripIds }, complainantId: req.auth!.sub }, select: { tripId: true } }),
    ]);
    const ratingByDriver = new Map(ratingAgg.map((r) => [r.driverId, { avg: r._avg.stars, count: r._count.stars }]));
    // The commuter's own star rating for a trip, keyed by tripId — distinct
    // from ratingByDriver's aggregate above. Lets Trip History redraw the
    // exact stars given rather than just a boolean "already rated" (see
    // [alreadyRated] below, still needed for the disabled/no-op check).
    const myRatingByTripId = new Map(myRatings.map((r) => [r.tripId, r.stars]));
    const ratedTripIds = new Set(myRatings.map((r) => r.tripId));
    const reportedTripIds = new Set(myComplaints.map((c) => c.tripId).filter((id): id is string => id !== null));

    const result = boardings
      .map((b) => {
        const trip = tripsById.get(b.tripId);
        if (!trip) return null;
        const driver = driversById.get(trip.driverId);
        const ratingInfo = ratingByDriver.get(trip.driverId);
        return {
          // The real per-ride identity — see boardingId's doc comment on
          // POST /board above. tripId alone can't tell two rides on the
          // same driver's Trip apart.
          boardingId: b.id,
          tripId: trip.id,
          driverId: trip.driverId,
          driverName: driver?.fullName ?? 'Unknown driver',
          plateNumber: driver?.plateNumber ?? '—',
          photoUrl: driver?.photoUrl ?? null,
          route: trip.route,
          boardedAt: b.boardedAt,
          alightedAt: b.alightedAt,
          // Null on boardings from before this column existed (see
          // TripBoarding's doc comment) — the client falls back to
          // whatever it has cached locally in that case.
          riders: b.riders,
          driverAverageRating: ratingInfo?.avg ?? null,
          driverRatingCount: ratingInfo?.count ?? 0,
          alreadyRated: ratedTripIds.has(trip.id),
          alreadyReported: reportedTripIds.has(trip.id),
          myRating: myRatingByTripId.get(trip.id) ?? null,
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

    // Rides this trip more than once now creates more than one row (see
    // TripBoarding's doc comment) — any one of them is proof enough that
    // this commuter actually rode with this driver on this trip.
    const boarding = await prisma.tripBoarding.findFirst({
      where: { tripId, commuterId: req.auth!.sub },
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

    // Also pushed locally the instant this succeeds, for zero-latency
    // feedback (see RATING_SUBMITTED in jeepney_booking_flow_screen.dart /
    // commuter_history_screen.dart) — matching type+referenceId here lets
    // the notifications feed de-dup the two into one entry once this
    // server copy syncs in, rather than showing both forever.
    await notifyCommuter({
      recipientId: req.auth!.sub,
      title: 'Thank You For Rating!',
      message: 'Thank you! Your rating helps improve our service.',
      type: 'RATING_SUBMITTED',
      referenceId: tripId,
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

      const attachmentUrl = req.file
        ? await uploadBufferToCloudinary(req.file.buffer, 'complaint-attachments')
        : null;
      const complaint = await prisma.complaint.create({
        data: {
          complainantId: req.auth!.sub,
          driverId: driver.id,
          tripId: body.tripId ?? null,
          complaintType: body.complaintType,
          description: body.description,
          attachmentUrl,
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

      // Also pushed locally for the filer the instant this succeeds (see
      // "Report Received" in jeepney_booking_flow_screen.dart /
      // commuter_history_screen.dart) — same type+referenceId as above so
      // the notifications feed de-dups the local and server copies into
      // one entry.
      await notifyCommuter({
        recipientId: req.auth!.sub,
        title: 'Report Received',
        message: `Your report about ${driver.fullName} has been received. Thank you for helping us improve.`,
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

// "Clear All" — a real delete, not a soft-dismiss; there's no undo, same
// as the rest of this app's delete actions. Only ever clears this
// commuter's own notifications (recipientId scoped), never anyone else's.
router.delete('/notifications', requireAuth('commuter'), async (req, res, next) => {
  try {
    await prisma.commuterNotification.deleteMany({ where: { recipientId: req.auth!.sub } });
    res.json({ message: 'Notifications cleared.' });
  } catch (err) {
    next(err);
  }
});

export default router;
