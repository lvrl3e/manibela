# Tech Stack & Deployment

## Tech stack

### Mobile app (`lib/`)
Flutter/Dart, targeting Android as the primary release platform (the project
scaffold also includes iOS/Windows/macOS/Linux/web, but the release pipeline
only ships Android).

Key packages: `flutter_map` (OpenStreetMap tiles), `geolocator`,
`mobile_scanner` (QR codes), `google_mlkit_face_detection` + `camera`,
`flutter_secure_storage`, `qr_flutter`, `http`.

### Backend (`backend/`)
Node.js 20, Express 5, TypeScript, Prisma ORM 6.19 → PostgreSQL.

- `jsonwebtoken` + `bcryptjs` — auth
- `zod` — request validation
- `multer` + Cloudinary — photo uploads
- `@tensorflow/tfjs-node` + `@vladmandic/face-api` — local, on-device
  face-match (no paid vendor API)
- `express-rate-limit`

### Admin dashboard (`admin/`)
React 19, TypeScript, Vite 8, Tailwind CSS 4, React Router 7,
`leaflet`/`react-leaflet` (OpenStreetMap), `exceljs` (exports).

### Landing page (`landing/`)
A single static `index.html` — no framework, no build step.

### Database
PostgreSQL on **Neon** (serverless Postgres).

### Maps / routing
- Mapbox — tiles + custom map style (paid, kept as-is)
- OSRM's free public demo server — turn-by-turn routing/ETA, isolated in
  `backend/src/lib/routingService.ts` with a haversine fallback if it's
  ever unavailable. No paid routing API.

## Deployment Stack

| Piece | Where | Notes |
|---|---|---|
| Admin dashboard | **Vercel** | `admin/vercel.json` (SPA rewrite). Auto-deploys on push to `main`. |
| Mobile app | GitHub Releases (`latest`), not the Play Store | Built by `.github/workflows/build-apk.yml` on every push to `main`; signed with the `ANDROID_KEYSTORE_BASE64`/`ANDROID_KEYSTORE_PASSWORD`/`ANDROID_KEY_PASSWORD`/`ANDROID_KEY_ALIAS` repo secrets. |
| Backend API (`api.manibelaapp.com`) | **Render** | No `render.yaml` in the repo — configured via Render's own dashboard/GitHub integration, not repo config. |
| Landing page | **Vercel** | Same platform as the admin dashboard, separate project. |
| Database | Neon | Managed Postgres; `DATABASE_URL` in `backend/.env`. |

### Git remotes

- `origin` — `github.com/mcm876/ManibelApp` (primary)
- `deploy` — `github.com/lvrl3e/manibela` (mirror)
- `admin-website-mirror` — `github.com/lvrl3e/ManibelApp-Admin-Website`

Every push goes to both `origin` and `deploy`.
