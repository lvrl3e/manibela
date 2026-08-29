/**
 * Sends a real SMS to a PH mobile number via Semaphore
 * (https://semaphore.co) — chosen over Twilio for being roughly 20x
 * cheaper per SMS to Philippine numbers. Hits the `priority` (expedited)
 * endpoint rather than the standard `messages` one specifically because
 * this is used for OTP codes that expire in minutes; a code delivered
 * late is useless.
 *
 * No-ops (does nothing beyond issueOtp's own console.log) when
 * SEMAPHORE_API_KEY isn't set at all — that's "not set up yet", not a
 * failure, and every OTP flow needs to keep working exactly as it does
 * today (console-only) until a real Semaphore account/credits exist.
 * Once a key IS configured, though, any failure to actually send (bad
 * key, no credits, network error, non-2xx response) throws instead of
 * swallowing it — at that point an OTP the user never receives is a
 * real failure the caller needs to know about, not something to paper
 * over silently.
 */
export async function sendSms(mobileNumber: string, message: string): Promise<void> {
  const apiKey = process.env.SEMAPHORE_API_KEY;
  if (!apiKey) return;

  const response = await fetch('https://semaphore.co/api/v4/priority', {
    method: 'POST',
    headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
    body: new URLSearchParams({
      apikey: apiKey,
      number: mobileNumber,
      message,
    }),
  });

  if (!response.ok) {
    const body = await response.text().catch(() => '');
    throw new Error(`Semaphore SMS send failed (${response.status}): ${body}`);
  }
}
