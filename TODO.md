# ManibelApp — Future Work

Ideas and planned features not yet built. Not a bug tracker — just a
holding pen so they don't get lost between sessions.

## Older-driver accessibility (from 2026-08-21 design audit)

Most jeepney drivers are older; the app's visual language currently assumes
young, sharp-eyed users. Grep found 103 occurrences of sub-12px text across
28 of ~37 screens — this is a systemic habit, not a one-off.

- **Font-size floor app-wide.** Raise the minimum to 12px everywhere, 14px+
  for body text. Highest priority: `driver_daily_operations_screen.dart` —
  the odometer/earnings/fuel-expense values a driver types and re-checks
  render at 12px today, same size as their labels. This is the one screen
  where a misread digit costs the driver money; its numbers should be the
  largest, boldest text on the page.
- **Form input contrast.** Daily Ops' empty-field hints use
  `Colors.grey.shade400` on a light field — low contrast, hard to read
  outdoors/in glare. Darken hint text and give filled vs. empty fields a
  more visible difference (not just text color).
- **Empty-state CTAs.** Weekly/Monthly Analytics ("No data yet — Log your
  Daily Operations to see analytics here") point at a screen with no
  button to get there — add a direct "Log Today's Trip" CTA instead of
  making the driver hunt through the menu.
- **Accessibility escape hatch.** No explicit `MediaQuery`/`TextScaler`
  handling anywhere in the app. Verify fixed-height containers (Daily
  Ops' summary table, the driver dashboard's stat cards) don't
  clip/overflow when a driver has the OS system font size turned up —
  and if OS-level scaling alone isn't reliable enough across these
  screens, add an in-app text-size control as a fallback.

---

Tried and reverted:
- 3-tier header system (2026-08-21): differentiated Weekly/Monthly
  Analytics (quiet pale-yellow tint) and Daily Operations (neutral) from
  the full yellow gradient kept on Start Trip/dashboards. Shipped, then
  reverted the same day — user called it "too inconsistent." All three
  screens are back to the identical full yellow gradient banner. Don't
  re-attempt this without discussing the inconsistency concern first.

Shipped:
- Logout loading screen, mobile app (2026-08-21): both driver and
  commuter logout previously either navigated to login instantly with the
  sign-out I/O happening invisibly in the background (driver), or awaited
  it with the dashboard frozen and no feedback (commuter). Added
  `lib/core/widgets/signing_out_screen.dart` — a shared, self-contained
  "Signing you out..." screen (branded, spinner, held a minimum 500ms so
  it never flashes) — matching the same pattern already used for the
  admin website's auth loading screens. Wired into both
  `driver_dashboard_screen.dart` and `commuter_dashboard_screen.dart`'s
  `_handleLogout`, unifying the two previously-inconsistent flows.
- Dashboard Start Trip FAB redesign (2026-08-21): the round yellow FAB on
  `driver_dashboard_screen.dart` was an 82px circle with icon-over-text at
  8px — the smallest text of any CTA in the app, on its single most
  important tap. First tried just enlarging the circle (92px, 12px text);
  user asked for a more substantial change ("change it entirely"). Picked
  from a 3-way mockup (bigger circle / full-width docked bar / floating
  pill) — landed on the floating pill: icon + "Start Trip"/"View Trip"
  label side-by-side at 16px in a rounded-pill `Material`, same position
  and active-trip color logic (yellow primary / blue when a trip is
  live) as before, just no longer circle-constrained.
  (An earlier attempt applied a similar redesign to the *confirm* button
  on `driver_start_trip_screen.dart` instead — wrong screen; that button
  was reverted back to its original 52px/12px-text design per user
  request and is unaffected by this change.)
- `onPrimary`/`primary` text contrast (2026-08-21): `AppColors.onPrimary`
  (`lib/core/constants/app_colors.dart`) was `0xFF92600A`, ~2.8:1 against
  the yellow `primary` background — failing WCAG AA's 4.5:1 floor for
  normal text, which every name/label/button sitting directly on a yellow
  surface uses. Darkened to `0xFF623D00` (~5.0:1), still a warm on-brand
  amber rather than flat black.
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
