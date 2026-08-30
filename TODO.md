# ManibelaApp — Future Work

Ideas and planned features not yet built. Not a bug tracker — just a
holding pen so they don't get lost between sessions.

## Connect admin/landing to Vercel's GitHub auto-deploy (2026-08-30)

Both are currently deployed by hand (`vercel --prod` from `admin/` /
`landing/`), the one inconsistent piece in an otherwise fully-automated
pipeline — Render auto-deploys the backend on push, GitHub Actions
auto-builds the APK on push, but these two need someone to remember a
manual step, or they silently drift behind what's actually on `main`.
Fix: in each Vercel project, Settings → Git → connect to
`lvrl3e/manibela` (the same repo Render/Actions already watch) — free,
no plan change, standard Vercel workflow. Once connected, `git push
deploy main` alone deploys both, same as the backend/APK already work.

## Face-match consent copy + liveness detection (2026-08-30)

Two gaps from a face-match production-readiness review (see
`backend/src/lib/faceMatch.ts` for the matching logic itself, already
live).

- **Consent copy.** `lib/core/constants/legal_text.dart` already
  discloses that government ID/license/selfie photos are collected as
  sensitive personal information under RA 10173 with explicit consent
  — good, existing groundwork. It doesn't yet mention that an
  *automated* system compares the selfie against the ID photo (as
  opposed to purely human review, which is what it described before
  face-match existed). Add a sentence disclosing the automated
  comparison, with manual admin review as the fallback for anything it
  can't confidently clear.
- **Liveness detection.** The face-match step compares two static
  photos — nothing currently stops someone holding up a printed photo
  or another phone/screen during the live selfie capture
  (`InAppCameraCapture`) and having it read as a match. Addressable
  with an on-device liveness challenge (e.g. a blink or turn-your-head
  prompt via Google ML Kit's face landmark/expression detection) before
  the selfie is accepted — real work, not a config toggle, but closes
  the one spoofing gap that matters most here.

## KYC photo retention + access audit trail (2026-08-30)

Two policy gaps flagged during a Cloudinary security review (which also
fixed the real issue — ID/license/selfie photos now upload as
Cloudinary's `authenticated` type instead of plain public URLs, see
`uploadBufferToCloudinary`'s `sensitive` option). Neither blocks
anything today; both are worth a decision before real user volume:

- **Retention.** ID/license/selfie photos are kept indefinitely once
  submitted — no auto-delete after any period. Under the PH Data
  Privacy Act's data-minimization principle, worth deciding on an
  actual policy (e.g. delete on account closure, or after N years of
  inactivity) instead of keeping them forever by default.
- **Access audit trail.** No log exists of which admin viewed which
  ID/selfie/license photo and when. Not required, but a common ask if
  ManibelaApp ever needs to demonstrate accountability over who
  accessed sensitive data.

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