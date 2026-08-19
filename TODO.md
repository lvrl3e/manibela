# Manibela App — Future Work

Ideas and planned features not yet built. Not a bug tracker — just a
holding pen so they don't get lost between sessions.

Nothing outstanding right now — the short-trip flagging threshold
(flagged 2026-08-19) shipped the same day: `computeShortTripFlag` in
`backend/src/routes/driver.ts` now flags two tiers instead of one —
under 60s (likely an accidental Start+End tap) and 60s–5min (too short
for a real Pasig–Quiapo run, more likely a genuinely aborted trip) —
both reusing the existing `isShortTrip`/`flagReason`/review/explanation
pipeline, distinguished only by the `flagReason` wording.
