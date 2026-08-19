# Manibela App — Future Work

Ideas and planned features not yet built. Not a bug tracker — just a
holding pen so they don't get lost between sessions.

- **Reconsider the short-trip flagging threshold.** Currently
  `SHORT_TRIP_THRESHOLD_MS = 60_000` in `backend/src/routes/driver.ts`
  (any trip under 60s gets flagged for review). A real Pasig–Quiapo run
  never finishes in under a minute even in the best case, so 60s only
  ever catches an accidental Start+End tap — it won't catch a driver who
  started a real trip and bailed a few minutes in (breakdown, no
  passengers, gaming the system), which is arguably the more useful
  signal for admin review. Consider raising to ~3-5 minutes if the intent
  is to catch genuinely-aborted trips rather than just mis-taps. Flagged
  2026-08-19; not yet decided or implemented.
