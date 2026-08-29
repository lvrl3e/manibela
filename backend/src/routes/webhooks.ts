import { Router } from 'express';
import { prisma } from '../lib/prisma';
import { verifyWebhookSignature, parseWebhookPayload } from '../lib/didit';
import { notifyAdmin } from '../utils/notify';

const router = Router();

// Didit calls this when a hosted verification session finishes — not our
// own app, so there's no requireAuth here; the HMAC signature is what
// proves a request actually came from Didit instead. Mounted with
// express.raw() ahead of the global express.json() (see index.ts) so
// req.body is the exact bytes Didit sent, which the signature is
// computed over — re-parsing to JSON first and re-serializing could
// reorder keys/whitespace and make a genuine webhook fail verification.
router.post('/didit', async (req, res, next) => {
  try {
    const rawBody = (req.body as Buffer).toString('utf8');
    const signature = req.header('x-signature');
    const timestamp = req.header('x-timestamp');

    if (!verifyWebhookSignature(rawBody, signature, timestamp)) {
      res.status(401).json({ error: 'Invalid signature.' });
      return;
    }

    const payload = JSON.parse(rawBody);
    const outcome = parseWebhookPayload(payload);
    if (!outcome) {
      // A verified-but-unrecognized payload shape — ack anyway so Didit
      // doesn't retry forever on something we'll never be able to parse.
      res.json({ received: true });
      return;
    }

    // vendor_data is whatever we set at session creation: a
    // PendingCommuterSignup's own ticket for commuter signup, or a
    // Driver's id for license verification (see POST
    // .../verification-session in each route file) — try commuter first,
    // then driver.
    const pending = await prisma.pendingCommuterSignup.findUnique({
      where: { ticket: outcome.vendorData },
    });
    if (pending) {
      await prisma.pendingCommuterSignup.update({
        where: { id: pending.id },
        data: { diditDecision: outcome.approved ? 'approved' : 'inconclusive' },
      });
      res.json({ received: true });
      return;
    }

    const driver = await prisma.driver.findUnique({ where: { id: outcome.vendorData } });
    if (driver) {
      const updated = await prisma.driver.update({
        where: { id: driver.id },
        data: {
          licenseVerificationStatus: outcome.approved ? 'APPROVED' : 'PENDING',
          autoVerificationNote: outcome.note,
        },
      });

      // Only notify when this still needs a human — an auto-approval
      // needs no admin action, so paging one for it would just be noise.
      if (!outcome.approved) {
        await notifyAdmin({
          title: 'Driver license submitted',
          message: `${updated.fullName} (${updated.driverId}) is waiting for review.`,
          type: 'LICENSE_SUBMITTED',
          referenceId: updated.id,
        });
      }
      res.json({ received: true });
      return;
    }

    // Unrecognized vendor_data (e.g. an expired/deleted signup ticket) —
    // a safe no-op rather than an error, so Didit's retry logic doesn't
    // loop forever on a session that'll never resolve to anything.
    res.json({ received: true });
  } catch (err) {
    next(err);
  }
});

export default router;
