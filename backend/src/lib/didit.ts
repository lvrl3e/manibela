import { createHmac, timingSafeEqual } from 'node:crypto';

/**
 * Automated ID + face verification via Didit's Workflow product
 * (https://didit.me) — a hosted verification session, not the
 * standalone server-to-server API this originally used. The standalone
 * API turned out to have no free tier at all (a minimum $50 prepaid
 * balance is required before any call succeeds, confirmed directly by
 * Didit support); the free 500-checks/month tier only applies to
 * Workflows, where the user is sent to a Didit-hosted page to capture
 * their own ID/selfie, and Didit calls [POST /api/webhooks/didit] back
 * with the result — see that route for how a session's outcome actually
 * gets applied.
 *
 * Every function here no-ops (returns null) when DIDIT_API_KEY or
 * DIDIT_WORKFLOW_ID isn't set — "not configured yet", not a failure —
 * so signup/license submission keep working exactly as they did before
 * this integration existed (stays PENDING, an admin reviews manually)
 * until both are set up.
 */

const DIDIT_BASE_URL = 'https://verification.didit.me/v3';

export type CreatedSession = {
  sessionId: string;
  url: string;
};

/**
 * Creates a hosted verification session for [vendorData] — the id this
 * app will later use to find its way back to the right row when the
 * webhook reports a decision (a PendingCommuterSignup ticket for
 * commuter signup, or a Driver's own id for license verification).
 * Returns null if Didit isn't configured yet; throws on a genuine API
 * failure (bad key, bad workflow id, Didit outage) — callers decide how
 * to surface that (there's no "PENDING, review later" fallback for a
 * session that never got created at all, unlike a webhook that never
 * arrives).
 */
export async function createVerificationSession(vendorData: string): Promise<CreatedSession | null> {
  const apiKey = process.env.DIDIT_API_KEY;
  const workflowId = process.env.DIDIT_WORKFLOW_ID;
  if (!apiKey || !workflowId) return null;

  const response = await fetch(`${DIDIT_BASE_URL}/session/`, {
    method: 'POST',
    headers: {
      'x-api-key': apiKey,
      'Content-Type': 'application/json',
    },
    body: JSON.stringify({ workflow_id: workflowId, vendor_data: vendorData }),
  });

  if (!response.ok) {
    const body = await response.text().catch(() => '');
    throw new Error(`Didit session creation failed (${response.status}): ${body}`);
  }

  const result = (await response.json()) as { session_id: string; url: string };
  return { sessionId: result.session_id, url: result.url };
}

/**
 * Verifies a webhook actually came from Didit — HMAC-SHA256 over the
 * raw request body (must be the exact bytes Didit sent, before any
 * JSON.parse, since re-serializing can reorder keys/whitespace and
 * change the signature), using the shared secret from the webhook
 * destination configured in Didit's console. Also rejects anything
 * outside a 5-minute timestamp window, so a captured request can't be
 * replayed indefinitely.
 */
export function verifyWebhookSignature(rawBody: string, signatureHeader: string | undefined, timestampHeader: string | undefined): boolean {
  const secret = process.env.DIDIT_WEBHOOK_SECRET;
  if (!secret || !signatureHeader || !timestampHeader) return false;

  const timestampSeconds = Number(timestampHeader);
  if (!Number.isFinite(timestampSeconds)) return false;
  const ageMs = Date.now() - timestampSeconds * 1000;
  if (Math.abs(ageMs) > 5 * 60 * 1000) return false;

  const expected = createHmac('sha256', secret).update(rawBody).digest('hex');
  const expectedBuffer = Buffer.from(expected, 'hex');
  const actualBuffer = Buffer.from(signatureHeader, 'hex');
  if (expectedBuffer.length !== actualBuffer.length) return false;

  return timingSafeEqual(expectedBuffer, actualBuffer);
}

/** Didit's per-session decision, boiled down to what this app acts on. */
export type SessionOutcome = {
  vendorData: string;
  approved: boolean;
  note: string;
};

/**
 * Parses a verified webhook payload into the shape the rest of the app
 * cares about. Only a clean overall "Approved" status auto-approves —
 * anything else (declined, in review, needs a human per Didit's own
 * classification) leaves it for an admin, same as before this
 * integration existed.
 */
export function parseWebhookPayload(payload: any): SessionOutcome | null {
  const vendorData = payload?.vendor_data;
  if (typeof vendorData !== 'string' || !vendorData) return null;

  const status: string = payload?.status ?? payload?.decision?.status ?? 'unknown';
  const approved = status === 'Approved' || status === 'approved';

  return {
    vendorData,
    approved,
    note: `Didit workflow status: ${status}`,
  };
}
