import { prisma } from '../lib/prisma';
import { deleteUploadedPhoto } from '../middleware/upload';

/**
 * Data-minimization cleanup for KYC photos (ID/license/selfie) — flagged
 * during the Cloudinary security review as a policy gap: these were kept
 * indefinitely with no auto-delete after any period, which sits poorly
 * against the PH Data Privacy Act's data-minimization principle once a
 * commuter/driver record is genuinely closed rather than mid-review.
 *
 * Deliberately deletes only the photo fields, never the account row
 * itself — Trip/Rating/Complaint history still needs the row to exist.
 * Never touches anything still PENDING review: only a definite closure
 * (REJECTED, or deactivated after having been APPROVED) starts the
 * retention clock, and only once it's been closed for RETENTION_DAYS —
 * an admin correcting a mistaken rejection/deactivation naturally resets
 * that clock too, since doing so touches updatedAt.
 *
 * Same plain-setInterval approach as jobs/driverLogReminders.ts — nothing
 * here needs a real cron library, and re-running this on every interval
 * (or across a restart) is safe: once a photo's URL is null, that row
 * simply stops matching the query.
 */

const CHECK_INTERVAL_MS = 24 * 60 * 60 * 1000; // once a day is plenty

// 90 days past closure — a policy choice, not a legal minimum (the Data
// Privacy Act doesn't set a fixed number, just "no longer than necessary
// for the stated purpose"). Long enough that an admin has real time to
// notice and reverse a mistaken rejection/deactivation before the photos
// are gone for good; short enough that a genuinely closed account isn't
// carrying sensitive ID photos indefinitely for no operational purpose.
const RETENTION_DAYS = 90;

function retentionCutoff(): Date {
  return new Date(Date.now() - RETENTION_DAYS * 24 * 60 * 60 * 1000);
}

async function cleanupCommuterPhotos() {
  const cutoff = retentionCutoff();
  const candidates = await prisma.commuter.findMany({
    where: {
      updatedAt: { lt: cutoff },
      OR: [{ verificationStatus: 'REJECTED' }, { isActive: false, verificationStatus: 'APPROVED' }],
      AND: { OR: [{ idFrontUrl: { not: null } }, { idBackUrl: { not: null } }, { selfieUrl: { not: null } }] },
    },
    select: { id: true, idFrontUrl: true, idBackUrl: true, selfieUrl: true },
  });

  for (const c of candidates) {
    await Promise.all([deleteUploadedPhoto(c.idFrontUrl), deleteUploadedPhoto(c.idBackUrl), deleteUploadedPhoto(c.selfieUrl)]);
    await prisma.commuter.update({
      where: { id: c.id },
      data: { idFrontUrl: null, idBackUrl: null, selfieUrl: null },
    });
  }
  return candidates.length;
}

async function cleanupDriverPhotos() {
  const cutoff = retentionCutoff();
  const candidates = await prisma.driver.findMany({
    where: {
      updatedAt: { lt: cutoff },
      OR: [{ licenseVerificationStatus: 'REJECTED' }, { isActive: false }],
      AND: {
        OR: [{ licenseFrontUrl: { not: null } }, { licenseBackUrl: { not: null } }, { selfieUrl: { not: null } }],
      },
    },
    select: { id: true, licenseFrontUrl: true, licenseBackUrl: true, selfieUrl: true },
  });

  for (const d of candidates) {
    await Promise.all([
      deleteUploadedPhoto(d.licenseFrontUrl),
      deleteUploadedPhoto(d.licenseBackUrl),
      deleteUploadedPhoto(d.selfieUrl),
    ]);
    await prisma.driver.update({
      where: { id: d.id },
      data: { licenseFrontUrl: null, licenseBackUrl: null, selfieUrl: null },
    });
  }
  return candidates.length;
}

/** Abandoned sign-up tickets (never redeemed before their 30-minute TTL)
 * can still be carrying an uploaded ID/selfie from before the user gave
 * up — nothing else ever cleans these rows up. Deleted outright, ticket
 * and all: an expired ticket is already unusable (see POST /signup and
 * friends, which reject any expiresAt in the past), so there's no reason
 * to keep it or its photos around at all once expired. */
async function cleanupExpiredPendingSignups() {
  const expired = await prisma.pendingCommuterSignup.findMany({
    where: { expiresAt: { lt: new Date() } },
    select: { id: true, idFrontUrl: true, idBackUrl: true, selfieUrl: true },
  });

  for (const p of expired) {
    await Promise.all([deleteUploadedPhoto(p.idFrontUrl), deleteUploadedPhoto(p.idBackUrl), deleteUploadedPhoto(p.selfieUrl)]);
  }
  if (expired.length > 0) {
    await prisma.pendingCommuterSignup.deleteMany({ where: { id: { in: expired.map((p) => p.id) } } });
  }
  return expired.length;
}

async function runCleanup() {
  for (const [name, task] of Object.entries({
    cleanupCommuterPhotos,
    cleanupDriverPhotos,
    cleanupExpiredPendingSignups,
  })) {
    try {
      const count = await task();
      if (count > 0) console.log(`kycPhotoRetention: ${name} cleaned up ${count} row(s)`);
    } catch (err) {
      console.error(`kycPhotoRetention: ${name} failed:`, err);
    }
  }
}

let started = false;

/** Starts the daily retention sweep — call once at server startup (see
 * index.ts). Idempotent; a second call is a no-op. */
export function startKycPhotoRetentionJob() {
  if (started) return;
  started = true;
  void runCleanup();
  setInterval(() => void runCleanup(), CHECK_INTERVAL_MS);
}
