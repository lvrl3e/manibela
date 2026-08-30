# ManibelaApp — Future Work

Ideas and planned features not yet built. Not a bug tracker — just a
holding pen so they don't get lost between sessions.

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