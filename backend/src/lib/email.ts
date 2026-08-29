/**
 * Sends a real email via Resend (https://resend.com) — a free tier
 * (3,000/month, 100/day) that's already far more than admin's own
 * password-reset volume will ever need, with a single REST call, no
 * SMTP setup.
 *
 * Same graceful-degradation shape as sendSms (lib/sms.ts): no-ops when
 * RESEND_API_KEY isn't set at all (not set up yet, not a failure — keeps
 * today's console-only behavior working), but throws on any failure once
 * a key IS configured (bad key, unverified sending domain, network
 * error, non-2xx response) — an OTP the admin never receives is a real
 * failure the caller needs to know about, not something to paper over.
 *
 * `from` is configurable via RESEND_FROM_EMAIL because Resend's sandbox
 * address (onboarding@resend.dev) only delivers to the account owner's
 * own verified email — sending to any other admin's real inbox needs a
 * verified sending domain set up in the Resend dashboard first.
 */
export async function sendEmail(to: string, subject: string, html: string): Promise<void> {
  const apiKey = process.env.RESEND_API_KEY;
  if (!apiKey) return;

  const from = process.env.RESEND_FROM_EMAIL || 'ManibelApp <onboarding@resend.dev>';

  const response = await fetch('https://api.resend.com/emails', {
    method: 'POST',
    headers: {
      Authorization: `Bearer ${apiKey}`,
      'Content-Type': 'application/json',
    },
    body: JSON.stringify({ from, to: [to], subject, html }),
  });

  if (!response.ok) {
    const body = await response.text().catch(() => '');
    throw new Error(`Resend email send failed (${response.status}): ${body}`);
  }
}
