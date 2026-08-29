/**
 * Sends a real SMS to a PH mobile number via Semaphore
 * (https://semaphore.co) — chosen over Twilio for being roughly 20x
 * cheaper per SMS to Philippine numbers. Hits the `priority` (expedited)
 * endpoint rather than the standard `messages` one specifically because
 * this is used for OTP codes that expire in minutes; a code delivered
 * late is useless.
 *
 * Throws on any failure (bad key, no credits, network error, non-2xx
 * response) rather than swallowing it — an OTP the user never receives
 * is a real failure the caller needs to know about, not something to
 * paper over silently.
 */
export async function sendSms(mobileNumber: string, message: string): Promise<void> {
  const apiKey = process.env.SEMAPHORE_API_KEY;

  const response = await fetch('https://semaphore.co/api/v4/priority', {
    method: 'POST',
    headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
    body: new URLSearchParams({
      apikey: apiKey ?? '',
      number: mobileNumber,
      message,
    }),
  });

  if (!response.ok) {
    const body = await response.text().catch(() => '');
    throw new Error(`Semaphore SMS send failed (${response.status}): ${body}`);
  }
}
