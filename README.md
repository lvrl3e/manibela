# ManibelApp

A jeepney commuter & driver app for the Pasig–Quiapo route (Metro Manila),
plus the admin website that oversees it. Commuters find and board nearby
jeepneys via GPS proximity (with QR-scan as a fallback), drivers run their
shift and log trips, and admins verify IDs, review flagged trips, and
handle complaints.

## What's in this repo

| Folder | What it is | Stack |
|---|---|---|
| `lib/` (+ `android/`, `ios/`, `windows/`, etc.) | The commuter & driver mobile app | Flutter/Dart |
| `admin/` | The admin website | React 19 + TypeScript, Vite, Tailwind CSS 4 |
| `backend/` | The shared REST API both of the above talk to | Node.js + Express 5 + TypeScript, PostgreSQL via Prisma |

Maps everywhere are OpenStreetMap (`flutter_map` / `react-leaflet`) — no
Google Maps API in use.

## Getting started

See **[COMMANDS.md](COMMANDS.md)** for first-time setup and every
day-to-day command (running each part, database migrations, creating
driver/admin accounts, typechecking).

## Database reference

- **[backend/DATABASE_SCHEMA.md](backend/DATABASE_SCHEMA.md)** — what each
  table is for and the design reasoning behind it (start here).
- **[backend/DATA_DICTIONARY.md](backend/DATA_DICTIONARY.md)** — exhaustive
  field-by-field reference: every column, type, and constraint.

Source of truth for the actual schema is
[`backend/prisma/schema.prisma`](backend/prisma/schema.prisma); the two
docs above are companions to it, not a replacement.

## Status

Pre-release. OTP delivery and ID/face verification are currently
manual/mocked by design (admin reviews everything by hand) rather than
backed by a real SMS or face-match provider.
