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