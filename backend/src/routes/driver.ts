import { Router } from 'express';
import bcrypt from 'bcryptjs';
import { z } from 'zod';

import { prisma } from '../lib/prisma';
import { toE164 } from '../utils/phone';
import { isValidPlateNumber, normalizePlateNumber } from '../utils/plate';
import { toTitleCase } from '../utils/text';
import { generateDriverId } from '../utils/driverId';
import { generateQrToken } from '../utils/qrToken';
import { signAuthToken } from '../utils/jwt';
import { issueOtp, verifyOtp } from '../utils/otp';
import { formatDateOnly } from '../utils/date';
import { requireAuth } from '../middleware/auth';
import { uploadPhoto, uploadLicensePhotos, deleteUploadedPhoto, uploadBufferToCloudinary } from '../middleware/upload';
import { notifyDriver, notifyAdmin, notifyCommuter } from '../utils/notify';
import { authLimiter } from '../middleware/rateLimit';
import { compareFaces, fetchImageBuffer, FACE_MATCH_AUTO_CLEAR_SCORE } from '../lib/faceMatch';

const router = Router();

// Unauthenticated + brute-forceable — see middleware/rateLimit.ts.
router.use(
  ['/signup', '/login', '/forgot-password', '/verify-otp', '/reset-password'],
  authLimiter,
);

function toPublicDriver(driver: {
  id: string;
  driverId: string;
  fullName: string;
  mobileNumber: string;
  plateNumber: string;
  dateOfBirth: Date | null;
  photoUrl: string | null;
  licenseNumber: string | null;
  licenseVerificationStatus: string | null;
}) {
  return {
    id: driver.id,
    driverId: driver.driverId,
    fullName: driver.fullName,
    mobileNumber: driver.mobileNumber,
    plateNumber: driver.plateNumber,
    dateOfBirth: driver.dateOfBirth ? formatDateOnly(driver.dateOfBirth) : null,
    photoUrl: driver.photoUrl,
    // Only ever set by an admin, alongside licenseVerificationStatus —
    // see PATCH /admin/drivers/:id/license-number. Shown to the driver
    // themselves once approved (see driver_license_number_screen.dart),
    // not just the bare "Verified" status.
    licenseNumber: driver.licenseNumber,
    licenseVerificationStatus: driver.licenseVerificationStatus,
  };
}

function toPublicTrip(trip: {
  id: string;
  driverId: string;
  route: string | null;
  status: string;
  currentLat: number | null;
  currentLng: number | null;
  startedAt: Date;
  endedAt: Date | null;
  isShortTrip: boolean;
  flagReason: string | null;
  driverExplanation: string | null;
  explanationSubmittedAt: Date | null;
  reviewStatus: string;
  reviewedAt: Date | null;
  adminReviewNote: string | null;
}) {
  return {
    id: trip.id,
    driverId: trip.driverId,
    route: trip.route,
    status: trip.status,
    currentLat: trip.currentLat,
    currentLng: trip.currentLng,
    startedAt: trip.startedAt,
    endedAt: trip.endedAt,
    isShortTrip: trip.isShortTrip,
    flagReason: trip.flagReason,
    driverExplanation: trip.driverExplanation,
    explanationSubmittedAt: trip.explanationSubmittedAt,
    reviewStatus: trip.reviewStatus,
    reviewedAt: trip.reviewedAt,
    // reviewedBy (an admin id) is deliberately left out — the driver has
    // no use for it and no visibility into the admin table.
    adminReviewNote: trip.adminReviewNote,
  };
}

// Two escalating tiers, both duration-based. Distance would sharpen this
// (a short trip that still covered real distance is probably genuine),
// but this app doesn't track a trip's traveled distance anywhere yet —
// only a live currentLat/currentLng snapshot, not a path — so duration
// is the only honest signal available. Server-side and fixed, not
// client-supplied, so neither the Flutter app nor any other caller can
// influence it.
//
// - Under 60s: almost certainly an accidental/test tap of Start Trip
//   immediately followed by End Trip, not a real completed run.
// - Under 5 minutes (but at least 60s): still far too short for a real
//   Pasig–Quiapo run even in light traffic — less likely a mis-tap, more
//   likely a genuinely aborted trip (breakdown, no passengers, gaming
//   the system), which is arguably the more useful signal for admin
//   review. Both tiers reuse the same isShortTrip/flagReason/review/
//   explanation pipeline — only the wording differs, so admins and
//   drivers can tell the two apart from the Flag Reason text alone.
const IMMEDIATE_TAP_THRESHOLD_MS = 60_000; // 1 minute
const BRIEF_TRIP_THRESHOLD_MS = 5 * 60_000; // 5 minutes

function computeShortTripFlag(startedAt: Date, endedAt: Date): { isShortTrip: boolean; flagReason: string | null } {
  const durationMs = endedAt.getTime() - startedAt.getTime();
  if (durationMs >= BRIEF_TRIP_THRESHOLD_MS) {
    return { isShortTrip: false, flagReason: null };
  }
  const totalSeconds = Math.max(0, Math.round(durationMs / 1000));
  const minutes = Math.floor(totalSeconds / 60);
  const seconds = totalSeconds % 60;
  if (durationMs < IMMEDIATE_TAP_THRESHOLD_MS) {
    return {
      isShortTrip: true,
      flagReason: `Trip lasted ${minutes}m ${seconds}s, below the 60-second minimum.`,
    };
  }
  return {
    isShortTrip: true,
    flagReason: `Trip lasted ${minutes}m ${seconds}s — unusually brief for a completed Pasig–Quiapo run.`,
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
  fullName: z.string().trim().min(1).transform(toTitleCase),
  mobileNumber: z.string().trim().min(1),
  password: z.string().min(8),
  plateNumber: z
    .string()
    .trim()
    .min(1)
    .transform((value) => normalizePlateNumber(value))
    .refine(isValidPlateNumber, {
      message: 'Plate number must be 3 letters followed by 3 or 4 numbers (e.g. ABC123 or ABC1234).',
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
        qrToken: await generateQrToken(),
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

    if (!driver.isActive) {
      res.status(403).json({ error: 'This account has been deactivated. Contact your operator for help.' });
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

    // Expiry isn't re-checked here — that's only meant to bound the OTP
    // screen itself, not how long someone takes on the password fields
    // after (see verifyOtp's checkExpiry doc comment).
    const ok = await verifyOtp(mobileNumber, 'PASSWORD_RESET', body.code, { checkExpiry: false });
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

// dateOfBirth deliberately isn't editable here — only an admin can set it
// now, via PATCH /admin/drivers/:id/date-of-birth (see that endpoint's
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

router.patch('/me', requireAuth('driver'), async (req, res, next) => {
  try {
    const body = updateProfileSchema.parse(req.body);

    const driver = await prisma.driver.update({
      where: { id: req.auth!.sub },
      data: {
        fullName: body.fullName,
        photoUrl: body.photoUrl,
      },
    });

    res.json({ driver: toPublicDriver(driver) });
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

router.post('/me/phone/send-otp', requireAuth('driver'), async (req, res, next) => {
  try {
    const body = sendPhoneChangeOtpSchema.parse(req.body);
    const mobileNumber = toE164(body.mobileNumber);

    const existing = await prisma.driver.findUnique({ where: { mobileNumber } });
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

router.post('/me/phone/verify', requireAuth('driver'), async (req, res, next) => {
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
    const existing = await prisma.driver.findUnique({ where: { mobileNumber } });
    if (existing && existing.id !== req.auth!.sub) {
      res.status(409).json({ error: 'This mobile number is already registered to another account.' });
      return;
    }

    const driver = await prisma.driver.update({
      where: { id: req.auth!.sub },
      data: { mobileNumber },
    });

    res.json({ driver: toPublicDriver(driver) });
  } catch (err) {
    next(err);
  }
});

// multipart/form-data, field name "photo" — a plain URL/JSON field can't
// carry binary image data, hence the separate endpoint (and separate
// content type) from PATCH /me above.
router.post('/me/photo', requireAuth('driver'), (req, res, next) => {
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
      const existing = await prisma.driver.findUnique({ where: { id: req.auth!.sub } });
      if (!existing) {
        res.status(404).json({ error: 'Account not found.' });
        return;
      }

      const photoUrl = await uploadBufferToCloudinary(req.file.buffer, 'profile-photos');
      const driver = await prisma.driver.update({
        where: { id: existing.id },
        data: { photoUrl },
      });

      // Only after the DB update succeeds — never leave the record
      // pointing at a file that got deleted out from under it.
      deleteUploadedPhoto(existing.photoUrl);

      res.json({ driver: toPublicDriver(driver) });
    } catch (err2) {
      next(err2);
    }
  });
});

// Driver-submitted license photo + selfie — Settings -> License Number
// -> upload or take photo -> submit (see TODO.md re: no OCR/auto-detect
// on the license number itself). Reuses the same uploadLicensePhotos
// middleware the (now-removed) admin-side upload used — all three files
// are required here, unlike that old endpoint where either license side
// alone was accepted. A high enough faceMatchScore (selfie vs. license
// front, same mechanism/threshold as commuter signup — see
// lib/faceMatch.ts) auto-clears straight to APPROVED, letting the
// driver start trips immediately with no admin involved; otherwise this
// sets PENDING same as before, for an admin to review manually.
router.post('/me/license-photo', requireAuth('driver'), (req, res, next) => {
  uploadLicensePhotos(req, res, async (err) => {
    if (err) {
      res.status(400).json({ error: err instanceof Error ? err.message : 'Upload failed.' });
      return;
    }

    try {
      const files = req.files as
        | { licenseFront?: Express.Multer.File[]; licenseBack?: Express.Multer.File[]; selfie?: Express.Multer.File[] }
        | undefined;
      const front = files?.licenseFront?.[0];
      const back = files?.licenseBack?.[0];
      const selfie = files?.selfie?.[0];
      if (!front || !back || !selfie) {
        res.status(400).json({ error: 'Please provide the front and back of your license, and a selfie.' });
        return;
      }

      const existing = await prisma.driver.findUnique({ where: { id: req.auth!.sub } });
      if (!existing) {
        res.status(404).json({ error: 'Account not found.' });
        return;
      }

      const [licenseFrontUrl, licenseBackUrl, selfieUrl] = await Promise.all([
        uploadBufferToCloudinary(front.buffer, 'license-photos', { sensitive: true }),
        uploadBufferToCloudinary(back.buffer, 'license-photos', { sensitive: true }),
        uploadBufferToCloudinary(selfie.buffer, 'selfies', { sensitive: true }),
      ]);

      // Never blocks submission — any failure (no face found, model
      // error, fetch failure) just degrades to a null score, which
      // falls back to the same PENDING/manual-review path as before.
      let faceMatchScore: number | null = null;
      try {
        const [selfieBuffer, licenseBuffer] = await Promise.all([
          fetchImageBuffer(selfieUrl),
          fetchImageBuffer(licenseFrontUrl),
        ]);
        faceMatchScore = await compareFaces(selfieBuffer, licenseBuffer);
      } catch {
        faceMatchScore = null;
      }
      const autoCleared = faceMatchScore !== null && faceMatchScore >= FACE_MATCH_AUTO_CLEAR_SCORE;

      const driver = await prisma.driver.update({
        where: { id: existing.id },
        data: {
          licenseFrontUrl,
          licenseBackUrl,
          selfieUrl,
          faceMatchScore,
          licenseVerificationStatus: autoCleared ? 'APPROVED' : 'PENDING',
        },
      });

      deleteUploadedPhoto(existing.licenseFrontUrl);
      deleteUploadedPhoto(existing.licenseBackUrl);
      deleteUploadedPhoto(existing.selfieUrl);

      if (!autoCleared) {
        await notifyAdmin({
          title: 'Driver license submitted',
          message: `${driver.fullName} (${driver.driverId}) submitted license photos for review.`,
          type: 'LICENSE_SUBMITTED',
          referenceId: driver.id,
        });
      }

      res.json({ driver: toPublicDriver(driver) });
    } catch (err2) {
      next(err2);
    }
  });
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
// TRIPS — start/end + periodic location pings while active. This is what
// actually persists a trip server-side; DriverActiveTrip on the Flutter
// side still owns the in-app GPS-following UI, but now also calls these
// so the admin live map (and passenger boarding counts below) reflect
// something real instead of only existing on the driver's own device.
// ---------------------------------------------------------------------------

const startTripSchema = z.object({ route: z.string().trim().min(1).nullable().optional() });

router.post('/trips/start', requireAuth('driver'), async (req, res, next) => {
  try {
    const body = startTripSchema.parse(req.body);

    // Real enforcement, not just a UI gate — the app already blocks
    // reaching this screen when unverified (see driver_dashboard_screen's
    // _handleStartTrip), but this is what actually stops it if that's
    // ever bypassed.
    const driver = await prisma.driver.findUnique({ where: { id: req.auth!.sub } });
    if (driver?.licenseVerificationStatus !== 'APPROVED') {
      res.status(403).json({
        error: 'Your license must be verified before you can start a trip.',
        code: 'LICENSE_NOT_VERIFIED',
      });
      return;
    }

    const existingActive = await prisma.trip.findFirst({
      where: { driverId: req.auth!.sub, status: 'ACTIVE' },
    });
    if (existingActive) {
      res.json({ trip: toPublicTrip(existingActive) });
      return;
    }

    // No "Trip Started" notification — the driver just tapped the button
    // that caused this, so they already know; a notification for it would
    // just be an echo. "Trip Completed" (below, in /trips/:id/end) stays,
    // since it doubles as a record that the trip was actually recorded.
    const trip = await prisma.trip.create({
      data: { driverId: req.auth!.sub, route: body.route ?? null },
    });

    res.status(201).json({ trip: toPublicTrip(trip) });
  } catch (err) {
    next(err);
  }
});

router.get('/trips/active', requireAuth('driver'), async (req, res, next) => {
  try {
    const trip = await prisma.trip.findFirst({
      where: { driverId: req.auth!.sub, status: 'ACTIVE' },
    });
    res.json({ trip: trip ? toPublicTrip(trip) : null });
  } catch (err) {
    next(err);
  }
});

const tripLocationSchema = z.object({
  lat: z.number().min(-90).max(90),
  lng: z.number().min(-180).max(180),
});

router.patch('/trips/:id/location', requireAuth('driver'), async (req, res, next) => {
  try {
    const id: string = Array.isArray(req.params.id) ? req.params.id[0] : req.params.id;
    const body = tripLocationSchema.parse(req.body);

    const trip = await prisma.trip.findUnique({ where: { id } });
    if (!trip || trip.driverId !== req.auth!.sub) {
      res.status(404).json({ error: 'Trip not found.' });
      return;
    }
    if (trip.status !== 'ACTIVE') {
      res.status(400).json({ error: 'This trip has already ended.' });
      return;
    }

    const updated = await prisma.trip.update({
      where: { id },
      data: { currentLat: body.lat, currentLng: body.lng, locationUpdatedAt: new Date() },
    });

    res.json({ trip: toPublicTrip(updated) });
  } catch (err) {
    next(err);
  }
});

router.post('/trips/:id/end', requireAuth('driver'), async (req, res, next) => {
  try {
    const id: string = Array.isArray(req.params.id) ? req.params.id[0] : req.params.id;

    const trip = await prisma.trip.findUnique({ where: { id } });
    if (!trip || trip.driverId !== req.auth!.sub) {
      res.status(404).json({ error: 'Trip not found.' });
      return;
    }
    if (trip.status !== 'ACTIVE') {
      res.json({ trip: toPublicTrip(trip) });
      return;
    }

    const endedAt = new Date();
    const { isShortTrip, flagReason } = computeShortTripFlag(trip.startedAt, endedAt);

    const updated = await prisma.trip.update({
      where: { id },
      data: { status: 'COMPLETED', endedAt, isShortTrip, flagReason },
    });

    // A commuter still marked onboard when the *driver* ends the trip
    // (as opposed to tapping their own "Para Po"/End Trip — see POST
    // /api/commuter/alight) would otherwise stay stuck with alightedAt
    // still null forever: their own active-trip check already stops
    // showing them as riding once trip.status flips off ACTIVE, but the
    // boarding record itself never closes, and they're never told the
    // trip actually ended. Close every open boarding out here too, same
    // as a real alight, and let each of them know.
    const openBoardings = await prisma.tripBoarding.findMany({
      where: { tripId: id, alightedAt: null },
      select: { commuterId: true },
    });
    if (openBoardings.length > 0) {
      await prisma.tripBoarding.updateMany({
        where: { tripId: id, alightedAt: null },
        data: { alightedAt: endedAt },
      });
      await Promise.all(
        openBoardings.map((b) =>
          notifyCommuter({
            recipientId: b.commuterId,
            title: 'Trip Completed',
            message: 'Your trip has ended. Thanks for riding with ManibelaApp!',
            type: 'TRIP_COMPLETED',
            referenceId: updated.id,
          }),
        ),
      );
    }

    await notifyDriver({
      recipientId: req.auth!.sub,
      title: 'Trip Completed',
      message: updated.route ? `${updated.route} has ended.` : 'Your trip has ended.',
      type: 'TRIP_COMPLETED',
      referenceId: updated.id,
    });

    if (isShortTrip) {
      const routeLabel = updated.route ?? 'your trip';
      await notifyDriver({
        recipientId: req.auth!.sub,
        title: 'Short Trip Flagged',
        message: `${routeLabel} was flagged as unusually short (${flagReason}). Tap to explain what happened.`,
        type: 'TRIP_SHORT_FLAGGED',
        referenceId: updated.id,
      });

      // Admins otherwise only find out once a driver bothers to submit an
      // explanation (see PATCH /trips/:id/explanation) — this way a
      // flagged trip that never gets explained still surfaces for review.
      const driver = await prisma.driver.findUnique({ where: { id: req.auth!.sub } });
      await notifyAdmin({
        title: 'Short trip flagged',
        message: `${driver?.fullName ?? 'A driver'} (${driver?.plateNumber ?? '—'})'s trip on ${routeLabel} was flagged as unusually short — needs review.`,
        type: 'TRIP_SHORT_FLAGGED',
        referenceId: updated.driverId,
      });
    }

    res.json({ trip: toPublicTrip(updated) });
  } catch (err) {
    next(err);
  }
});

// The two fixed routes this fleet services — see DRIVER_ROUTES's doc
// comment in admin.ts for why this is hardcoded rather than a `SELECT
// DISTINCT route` per driver.
const DRIVER_ROUTES = [
  'Pasig – Quiapo (Shaw Blvd)',
  'Quiapo – Pasig (Shaw Blvd)',
  'Pasig – Quiapo (Sta. Mesa)',
  'Quiapo – Pasig (Sta. Mesa)',
] as const;

// Completed trips only — the app's own Trip History screen has nothing to
// show for a still-ACTIVE trip (that's what the dashboard/in-progress
// screen are for). Backs DriverHistoryScreen's paginated list — "Load 20
// initially, Load More for 20 more" is just this driver tapping through
// increasing `page` values with `limit` fixed at 20, same page/limit
// pagination the admin site's equivalent view uses (as `page`/`pageSize`
// there — named differently only because that's this app's existing
// per-platform convention, see GET /admin/trips).
const tripHistoryQuerySchema = z.object({
  page: z.coerce.number().int().min(1).default(1),
  limit: z.coerce.number().int().min(1).max(100).default(20),
  dateFrom: z.coerce.date().optional(),
  dateTo: z.coerce.date().optional(),
  route: z.enum(DRIVER_ROUTES).optional(),
  flag: z.enum(['all', 'normal', 'short']).default('all'),
});

router.get('/trips', requireAuth('driver'), async (req, res, next) => {
  try {
    const query = tripHistoryQuerySchema.parse(req.query);

    const where = {
      driverId: req.auth!.sub,
      status: 'COMPLETED' as const,
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
        skip: (query.page - 1) * query.limit,
        take: query.limit,
      }),
      prisma.trip.count({ where }),
    ]);

    const totalPages = Math.max(1, Math.ceil(totalTrips / query.limit));

    res.json({
      trips: trips.map(toPublicTrip),
      currentPage: query.page,
      pageSize: query.limit,
      totalTrips,
      totalPages,
      hasNextPage: query.page < totalPages,
      routes: DRIVER_ROUTES,
    });
  } catch (err) {
    next(err);
  }
});

// Single-trip lookup, scoped to the calling driver — backs
// DriverTripDetailsScreen/DriverTripExplanationScreen's own polling (an
// admin can review this exact trip while the driver is sitting on one of
// those screens) and the notifications screen's "open the trip this
// notification points at" navigation. Replaces the old pattern of
// re-syncing this driver's *entire* trip history just to refresh or look
// up one trip by id — the whole reason Trip History is paginated now is
// that a full sync doesn't scale, so nothing else should do one either.
router.get('/trips/:id', requireAuth('driver'), async (req, res, next) => {
  try {
    const id: string = Array.isArray(req.params.id) ? req.params.id[0] : req.params.id;
    const trip = await prisma.trip.findUnique({ where: { id } });
    if (!trip || trip.driverId !== req.auth!.sub) {
      res.status(404).json({ error: 'Trip not found.' });
      return;
    }
    res.json({ trip: toPublicTrip(trip) });
  } catch (err) {
    next(err);
  }
});

const submitExplanationSchema = z.object({
  explanation: z.string().trim().min(1, 'Explanation cannot be empty.').max(1000),
});

// A driver explaining why one of their own trips came in under the
// short-trip threshold. Resubmittable (each call overwrites the previous
// explanation + explanationSubmittedAt) so a driver can correct/expand
// it, but only for a trip that (a) is actually theirs — checked below,
// same as /trips/:id/end and /trips/:id/location, (b) was actually
// flagged, and (c) hasn't been reviewed yet — once an admin has acted on
// it, the explanation that call was based on is locked, so the app's own
// "Update Explanation" button being disabled can't be bypassed by calling
// this directly. Nothing here is writable by the driver besides the
// explanation text itself (isShortTrip, flagReason, reviewStatus,
// reviewedAt, adminReviewNote all stay admin/backend-only, see PATCH
// /api/admin/trips/:id/review).
router.patch('/trips/:id/explanation', requireAuth('driver'), async (req, res, next) => {
  try {
    const id: string = Array.isArray(req.params.id) ? req.params.id[0] : req.params.id;
    const body = submitExplanationSchema.parse(req.body);

    const trip = await prisma.trip.findUnique({ where: { id } });
    if (!trip || trip.driverId !== req.auth!.sub) {
      res.status(404).json({ error: 'Trip not found.' });
      return;
    }
    if (!trip.isShortTrip) {
      res.status(400).json({ error: 'This trip was not flagged, so there is nothing to explain.' });
      return;
    }
    if (trip.reviewStatus !== 'PENDING') {
      res.status(400).json({ error: 'This trip has already been reviewed and can no longer be explained.' });
      return;
    }

    const updated = await prisma.trip.update({
      where: { id },
      data: { driverExplanation: body.explanation, explanationSubmittedAt: new Date() },
    });

    // Lets admins know there's something to review without having to poll
    // every driver's Trip History for one — mirrors the other ADMIN
    // notifications in this app (see e.g. "New severe complaint filed" in
    // commuter.ts). The driver record is only needed for this message; no
    // need to require it earlier since a missing driver here would mean
    // req.auth's own token no longer resolves, which requireAuth already
    // guards against.
    const driver = await prisma.driver.findUnique({ where: { id: req.auth!.sub } });
    await notifyAdmin({
      title: 'Driver explanation submitted',
      message: `${driver?.fullName ?? 'A driver'} (${driver?.plateNumber ?? '—'}) explained their short trip on ${updated.route ?? 'an unnamed route'} — needs review.`,
      type: 'TRIP_EXPLANATION_SUBMITTED',
      referenceId: req.auth!.sub,
    });

    res.json({ trip: toPublicTrip(updated) });
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
// below will actually recognize. It's assigned once at account creation
// and never changes — permanent for the life of the account, no
// self-serve rotation.

router.get('/me/qr-token', requireAuth('driver'), async (req, res, next) => {
  try {
    const driver = await prisma.driver.findUnique({ where: { id: req.auth!.sub } });
    if (!driver) {
      res.status(404).json({ error: 'Account not found.' });
      return;
    }

    // Every driver gets a qrToken at creation now, but this covers
    // accounts created before that was true (nothing to backfill).
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

// Public on purpose — a commuter scanning a driver's QR isn't authenticated
// as anyone. Deliberately a narrower shape than toPublicDriver (which also
// carries mobileNumber/dateOfBirth for the driver's own authenticated
// /me-style views) — only what's safe to show a commuter before/while
// boarding: name, driverId, plate, profile photo, and the driver's live
// average rating (see Rating's doc comment in schema.prisma) — never the
// mobile number or date of birth.
router.get('/verify-qr/:token', async (req, res, next) => {
  try {
    const driver = await prisma.driver.findUnique({ where: { qrToken: req.params.token } });
    if (!driver) {
      res.status(404).json({ error: 'This QR code is not recognized.' });
      return;
    }

    const ratingInfo = await prisma.rating.aggregate({
      where: { driverId: driver.id },
      _avg: { stars: true },
      _count: { stars: true },
    });

    res.json({
      driver: {
        id: driver.id,
        driverId: driver.driverId,
        fullName: driver.fullName,
        plateNumber: driver.plateNumber,
        photoUrl: driver.photoUrl,
        averageRating: ratingInfo._avg.stars,
        ratingCount: ratingInfo._count.stars,
      },
    });
  } catch (err) {
    next(err);
  }
});

// ---------------------------------------------------------------------------
// DEMAND SIGNALS — the driver-side read of the same raw pings admin's
// Passenger Live Map uses (see GET /admin/demand-signals and
// DemandSignal's doc comment in schema.prisma). Clustered into grid cells
// client-side, same as the admin website's copy of that logic, so a
// driver sees the same "where passengers are waiting" clusters admin does
// from the same underlying data.
// ---------------------------------------------------------------------------

// Same window and reasoning as GET /admin/demand-signals — kept in sync
// deliberately so admin and driver never disagree on what counts as "still
// live."
const DEMAND_SIGNAL_WINDOW_MS = 15 * 60 * 1000;

const driverDemandSignalsQuerySchema = z.object({
  // The route this driver is currently running — when given, only pings
  // from commuters who picked the same route are returned, so a driver
  // running Pasig -> Quiapo doesn't get shown someone waiting for the
  // opposite direction. Omitted (e.g. before a route is chosen on the
  // dashboard) means "show everything."
  route: z.string().trim().min(1).optional(),
});

router.get('/demand-signals', requireAuth('driver'), async (req, res, next) => {
  try {
    const query = driverDemandSignalsQuerySchema.parse(req.query);
    const since = new Date(Date.now() - DEMAND_SIGNAL_WINDOW_MS);
    const signals = await prisma.demandSignal.findMany({
      // fulfilledAt: null — a commuter who's already boarded no longer
      // needs a pickup, so their signal stops showing here (see
      // fulfilledAt's doc comment in schema.prisma) even though it's kept
      // in the table.
      where: {
        createdAt: { gte: since },
        fulfilledAt: null,
        ...(query.route ? { route: query.route } : {}),
      },
      orderBy: { createdAt: 'desc' },
      select: { id: true, lat: true, lng: true, createdAt: true, partySize: true },
    });
    res.json({ signals });
  } catch (err) {
    next(err);
  }
});

// ---------------------------------------------------------------------------
// DAILY OPERATIONS LOG — backs the Daily Operations / Weekly / Monthly
// Analytics screens (see DriverDailyLog's doc comment in schema.prisma).
// The app already has a local (SharedPreferences) version of this; these
// endpoints let it sync instead of being the sole source of truth.
// ---------------------------------------------------------------------------

// Local getters deliberately, not UTC — this server is assumed to run in
// PH time (see this file's other "today" comments), so the local
// calendar day IS the PH calendar day. Built via Date.UTC (not
// `new Date(y, m, d)`) so this round-trips losslessly through
// DriverDailyLog.date, a `@db.Date` column: Prisma extracts a Date
// object's UTC calendar components when writing one, and a plain local-
// midnight Date is one UTC day *earlier* than intended for any positive
// UTC offset (PH is UTC+8) — the exact class of bug `dateOnly` in
// utils/date.ts already exists to avoid for dateOfBirth. Confirmed live:
// this used to store "today's" log under yesterday's date every time.
function todayDateOnly(): Date {
  const now = new Date();
  return new Date(Date.UTC(now.getFullYear(), now.getMonth(), now.getDate()));
}

function toPublicDailyLog(log: {
  id: string;
  date: Date;
  startOdo: number;
  endOdo: number;
  earnings: number;
  fuelExpense: number;
  otherExpenses: number;
}) {
  return {
    id: log.id,
    date: formatDateOnly(log.date),
    startOdo: log.startOdo,
    endOdo: log.endOdo,
    earnings: log.earnings,
    fuelExpense: log.fuelExpense,
    otherExpenses: log.otherExpenses,
  };
}

const dailyLogSchema = z.object({
  startOdo: z.number().min(0),
  endOdo: z.number().min(0),
  earnings: z.number().min(0),
  fuelExpense: z.number().min(0).default(0),
  otherExpenses: z.number().min(0).default(0),
});

// Always writes to *today's* row (server-side "today" — this machine runs
// in PH time, matching the app's audience) — a driver can revise it as
// many times as they like before the day is over, never picks a date.
router.put('/daily-log', requireAuth('driver'), async (req, res, next) => {
  try {
    const body = dailyLogSchema.parse(req.body);
    if (body.endOdo < body.startOdo) {
      res.status(400).json({ error: 'End odometer must be at least the start odometer.' });
      return;
    }

    const date = todayDateOnly();
    const log = await prisma.driverDailyLog.upsert({
      where: { driverId_date: { driverId: req.auth!.sub, date } },
      update: body,
      create: { driverId: req.auth!.sub, date, ...body },
    });

    res.json({ dailyLog: toPublicDailyLog(log) });
  } catch (err) {
    next(err);
  }
});

const dailyLogQuerySchema = z.object({
  days: z.coerce.number().int().min(1).max(366).default(31),
});

router.get('/daily-log', requireAuth('driver'), async (req, res, next) => {
  try {
    const query = dailyLogQuerySchema.parse(req.query);
    // UTC-constructed from local calendar components, same reasoning as
    // todayDateOnly() above — filters a `@db.Date` column, so a plain
    // local-midnight Date would cut the window off one day too early.
    const localToday = new Date();
    const since = new Date(
      Date.UTC(localToday.getFullYear(), localToday.getMonth(), localToday.getDate() - query.days),
    );

    const logs = await prisma.driverDailyLog.findMany({
      where: { driverId: req.auth!.sub, date: { gte: since } },
      orderBy: { date: 'desc' },
    });

    res.json({ dailyLogs: logs.map(toPublicDailyLog) });
  } catch (err) {
    next(err);
  }
});

router.get('/today-stats', requireAuth('driver'), async (req, res, next) => {
  try {
    const startOfToday = new Date();
    startOfToday.setHours(0, 0, 0, 0);

    const [tripsToday, todayLog] = await Promise.all([
      prisma.trip.count({ where: { driverId: req.auth!.sub, startedAt: { gte: startOfToday } } }),
      prisma.driverDailyLog.findUnique({
        where: { driverId_date: { driverId: req.auth!.sub, date: todayDateOnly() } },
      }),
    ]);

    res.json({
      tripsToday,
      earningsToday: todayLog?.earnings ?? null,
    });
  } catch (err) {
    next(err);
  }
});

// ---------------------------------------------------------------------------
// NOTIFICATIONS — server-triggered async events (see Notification's doc
// comment in schema.prisma), merged client-side with each app's own local
// notifications.
// ---------------------------------------------------------------------------

const notificationsQuerySchema = z.object({
  page: z.coerce.number().int().min(1).default(1),
  pageSize: z.coerce.number().int().min(1).max(100).default(50),
});

router.get('/notifications', requireAuth('driver'), async (req, res, next) => {
  try {
    const query = notificationsQuerySchema.parse(req.query);
    const where = { recipientId: req.auth!.sub };
    const [notifications, totalNotifications] = await Promise.all([
      prisma.driverNotification.findMany({
        where,
        orderBy: { createdAt: 'desc' },
        skip: (query.page - 1) * query.pageSize,
        take: query.pageSize,
      }),
      prisma.driverNotification.count({ where }),
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

router.post('/notifications/mark-read', requireAuth('driver'), async (req, res, next) => {
  try {
    await prisma.driverNotification.updateMany({
      where: { recipientId: req.auth!.sub, isRead: false },
      data: { isRead: true },
    });
    res.json({ message: 'Marked read.' });
  } catch (err) {
    next(err);
  }
});

// "Clear All" — a real delete, not a soft-dismiss; there's no undo, same
// as the commuter app's own DELETE /notifications. Only ever clears this
// driver's own notifications (recipientId scoped), never anyone else's.
router.delete('/notifications', requireAuth('driver'), async (req, res, next) => {
  try {
    await prisma.driverNotification.deleteMany({ where: { recipientId: req.auth!.sub } });
    res.json({ message: 'Notifications cleared.' });
  } catch (err) {
    next(err);
  }
});

export default router;
