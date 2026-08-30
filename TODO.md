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