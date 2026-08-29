/**
 * Automated ID + face verification via Didit (https://didit.me) —
 * standalone server-to-server endpoints, not their hosted-redirect
 * product, so none of this app's own capture screens change: we submit
 * images we already have, Didit just scores them.
 *
 * Every function here no-ops (returns null) when DIDIT_API_KEY isn't
 * set — "not configured yet", not a failure, so both verification flows
 * keep working exactly as they did before this integration existed
 * (stays PENDING, an admin reviews manually) until a real key is added.
 * A real failure once a key IS configured (bad key, Didit outage,
 * network error) is caught by runAutoVerification below and treated the
 * same as "inconclusive" — unlike the SMS/email integrations, a failed
 * Didit call is never something to surface as an error to the end user;
 * it's a supplement to human review, not a required step, so it always
 * degrades to "an admin will look at this instead."
 */

const DIDIT_BASE_URL = 'https://verification.didit.me/v3';

/**
 * Pulls an already-uploaded Cloudinary photo back down into a Buffer —
 * needed because the commuter signup flow uploads ID/selfie photos in
 * their own earlier requests (POST /signup/:ticket/id-photos and
 * .../selfie), so by the time POST /signup runs and can call Didit, only
 * the resulting URLs are on hand, not the original multipart buffers
 * (unlike the driver license flow, where all three files arrive in one
 * request and are already in memory).
 */
export async function fetchImageBuffer(url: string): Promise<Buffer> {
  const response = await fetch(url);
  if (!response.ok) {
    throw new Error(`Could not fetch ${url} (${response.status})`);
  }
  const arrayBuffer = await response.arrayBuffer();
  return Buffer.from(arrayBuffer);
}

type DiditCheckResult = { passed: boolean; detail: string } | null;

async function callDidit(path: string, form: FormData): Promise<any> {
  const apiKey = process.env.DIDIT_API_KEY;
  if (!apiKey) return null;

  const response = await fetch(`${DIDIT_BASE_URL}${path}`, {
    method: 'POST',
    headers: { 'x-api-key': apiKey },
    body: form,
  });

  if (!response.ok) {
    throw new Error(`Didit ${path} failed (${response.status})`);
  }

  return response.json();
}

/** Checks the ID/license document itself is genuine and legible. */
async function verifyIdDocument(front: Buffer, back: Buffer): Promise<DiditCheckResult> {
  const form = new FormData();
  form.append('front', new Blob([new Uint8Array(front)]), 'front.jpg');
  form.append('back', new Blob([new Uint8Array(back)]), 'back.jpg');

  const result = await callDidit('/id-verification/', form);
  if (result === null) return null;

  return {
    passed: result.status === 'Approved' || result.status === 'approved',
    detail: result.status ?? 'unknown status',
  };
}

/** Checks the selfie is a live capture, not a photo-of-a-photo/screen. */
async function checkLiveness(selfie: Buffer): Promise<DiditCheckResult> {
  const form = new FormData();
  form.append('selfie', new Blob([new Uint8Array(selfie)]), 'selfie.jpg');

  const result = await callDidit('/liveness/', form);
  if (result === null) return null;

  return {
    passed: result.status === 'Approved' || result.status === 'approved' || result.liveness === true,
    detail: result.status ?? (result.liveness ? 'live' : 'not live'),
  };
}

/** Checks the selfie is the same person as the ID/license photo. */
async function matchFaces(selfie: Buffer, idPhoto: Buffer): Promise<DiditCheckResult> {
  const form = new FormData();
  form.append('selfie', new Blob([new Uint8Array(selfie)]), 'selfie.jpg');
  form.append('reference', new Blob([new Uint8Array(idPhoto)]), 'reference.jpg');

  const result = await callDidit('/face-match/', form);
  if (result === null) return null;

  return {
    passed: result.status === 'Approved' || result.status === 'approved' || result.match === true,
    detail: result.status ?? `match score ${result.score ?? 'unknown'}`,
  };
}

export type AutoVerificationResult = {
  approved: boolean;
  note: string;
};

/**
 * Runs all three Didit checks against a document (ID or license) front/
 * back and a selfie, and decides whether that's enough to auto-approve.
 * Only a clean pass on all three does — anything inconclusive, not
 * configured, or actually failed leaves it for an admin, same as before
 * this integration existed. Never throws: a Didit outage or bad key
 * degrades to "inconclusive", not a broken signup/submission.
 */
export async function runAutoVerification(
  documentFront: Buffer,
  documentBack: Buffer,
  selfie: Buffer,
): Promise<AutoVerificationResult> {
  try {
    const [idResult, livenessResult, faceMatchResult] = await Promise.all([
      verifyIdDocument(documentFront, documentBack),
      checkLiveness(selfie),
      matchFaces(selfie, documentFront),
    ]);

    if (idResult === null || livenessResult === null || faceMatchResult === null) {
      return { approved: false, note: 'Didit not configured — awaiting manual review.' };
    }

    const notes = [
      `ID document: ${idResult.passed ? 'valid' : `failed (${idResult.detail})`}`,
      `Liveness: ${livenessResult.passed ? 'passed' : `failed (${livenessResult.detail})`}`,
      `Face match: ${faceMatchResult.passed ? 'confirmed' : `inconclusive (${faceMatchResult.detail})`}`,
    ];

    const approved = idResult.passed && livenessResult.passed && faceMatchResult.passed;
    return { approved, note: notes.join('; ') };
  } catch (err) {
    const message = err instanceof Error ? err.message : 'unknown error';
    return { approved: false, note: `Didit check failed (${message}) — awaiting manual review.` };
  }
}
