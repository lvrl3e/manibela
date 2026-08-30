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

  // Semaphore rejects a leading "+" as an invalid number format (confirmed
  // by testing directly — 09XXXXXXXXX and 63XXXXXXXXXX both work, but
  // +63XXXXXXXXXX doesn't) even though the app's own numbers are always
  // +63XXXXXXXXXX via utils/phone's toE164. Stripped only for this one
  // API call, not anywhere the E.164 form actually matters (DB storage,
  // other integrations).
  const response = await fetch('https://semaphore.co/api/v4/priority', {
    method: 'POST',
    headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
    body: new URLSearchParams({
      apikey: apiKey,
      number: mobileNumber.replace(/^\+/, ''),
      message,
    }),
  });

  const body = await response.text();

  // Semaphore doesn't reliably reflect a failure in the HTTP status —
  // an invalid number comes back as a 200 with a Laravel-style
  // validation-error object instead of the array shape every real send
  // attempt returns (confirmed by testing directly: a missing/unapproved
  // sender name is a bare error array, an invalid number is a bare error
  // object). Treating a non-array 2xx body as a failure too, on top of
  // the ordinary non-2xx check, catches both without needing to guess
  // the exact shape of a genuine success.
  let parsed: unknown;
  try {
    parsed = JSON.parse(body);
  } catch {
    parsed = null;
  }

  if (!response.ok || !Array.isArray(parsed)) {
    throw new Error(`Semaphore SMS send failed (${response.status}): ${body}`);
  }
}
