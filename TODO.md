# ManibelaApp — Future Work

Ideas and planned features not yet built. Not a bug tracker — just a
holding pen so they don't get lost between sessions.

## Re-enable strict SMS OTP failure (2026-08-30) — blocked on Semaphore

`utils/otp.ts`'s `issueOtp` currently swallows-and-logs a `sendSms`
failure instead of letting it throw (temporary, `channel: 'sms'` only —
`channel: 'email'`/Resend is untouched and still throws normally).
Needed because `SEMAPHORE_API_KEY` is configured on Render but every
real send fails until the "ManibelaApp" sender name is approved
(applied for 2026-08-30) — without the swallow, every sign-up/login OTP
request 500s outright instead of just failing to deliver the text.
Revert to a plain `await sendSms(...)` (no try/catch) the moment the
sender name is approved and a real send succeeds — otherwise a genuine
future SMS failure (bad number, no credits, Semaphore outage) goes
completely silent again, which is the exact failure mode this session
deliberately designed `sendSms` to avoid.

## Commuter resubmit after rejection (2026-08-30)

A commuter whose ID/selfie gets REJECTED currently hits a dead end —
`commuter_verification_status_screen.dart` just shows "Verification
Unsuccessful... contact support," no way to actually fix it and try
again in-app. Drivers already have this: `driver_license_number_screen.dart`
reopens the upload tiles whenever `licenseVerificationStatus` is
REJECTED, resubmitting through the same `POST /me/license-photo`
endpoint, no admin intervention needed to get a second attempt in
front of them. Commuters should get the equivalent — reopen the ID/
selfie capture flow (now the in-app camera, see
`InAppCameraCapture`) on a REJECTED account, resubmitting through
`POST /commuter/signup/:ticket/...`-equivalent endpoints for an
*existing* account (the current endpoints only exist for the
pre-account PendingCommuterSignup ticket flow, so this needs new
authenticated resubmit endpoints, not just a UI reopen — mirrors how
driver's resubmit works directly on the Driver row instead of a
pending-ticket row). Should re-run the automatic face-match (see
`backend/src/lib/faceMatch.ts`) on resubmit too, same as the original
signup — a clearer retake could auto-clear even if the first attempt
didn't.

Not needed for PENDING (still-waiting) accounts — that's normal
review latency, not a stuck state, and now resolves faster than
before thanks to auto-approval.