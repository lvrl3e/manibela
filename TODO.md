# Manibela App — Future Work

Ideas and planned features not yet built. Not a bug tracker — just a
holding pen so they don't get lost between sessions.

Nothing outstanding right now.

---

Shipped:
- Trip History discoverability (2026-08-20): `/jeepney-monitoring/history`
  was only reachable indirectly (Dashboard Quick Actions, or a Fleet row's
  "View Trips"). Added a "Trip History" button next to "Open Full-Screen
  Map" on Jeepney Monitoring (`admin/src/pages/JeepneyMonitoringPage.tsx`)
  instead of a sidebar nav item.
- Short-trip flagging threshold (2026-08-19): `computeShortTripFlag` in
  `backend/src/routes/driver.ts` now flags two tiers instead of one —
  under 60s (likely an accidental Start+End tap) and 60s–5min (too short
  for a real Pasig–Quiapo run, more likely a genuinely aborted trip) —
  both reusing the existing `isShortTrip`/`flagReason`/review/explanation
  pipeline, distinguished only by the `flagReason` wording.
