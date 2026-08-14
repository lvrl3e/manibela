# ManibelApp — Command Reference

All backend commands are run from the `backend/` folder. Admin website
commands are run from the `admin/` folder. All Flutter commands are run
from the project root. PowerShell in VS Code is assumed; swap `curl.exe`
quoting if you're on bash instead.

## First-time setup

```powershell
cd backend
npm install
npx prisma generate
docker compose up -d          # starts local Postgres (see backend/docker-compose.yml)
npx prisma migrate deploy     # applies all migrations
```

No demo driver gets created automatically — use `npm run create-driver` (below)
to make your own. `npm run seed` still exists if you ever want a quick
throwaway demo account, but it's optional.

```powershell
cd ..
flutter pub get
```

```powershell
cd admin
npm install
```

No admin account exists by default either — use `npm run create-admin` "Full Name" "email@example.com" "Password123!"
(below, run from `backend/`) to make one before you can sign in.

## Running things day-to-day

```powershell
cd backend
npm run dev                   # backend on http://localhost:4000, auto-restarts on save
```

```powershell
flutter run -d windows        # or -d chrome, or a device id from `flutter devices`
```

```powershell
cd admin
npm run dev                   # admin website on http://localhost:5173
```

## Database

```powershell
npx prisma studio             # browsable DB GUI at http://localhost:5555
docker compose up -d          # start Postgres if it's not already running
docker compose down           # stop Postgres (data persists in its volume)
```

Schema changes: edit `backend/prisma/schema.prisma`, then either:

```powershell
npx prisma migrate dev --name some_change   # interactive # interactive — only works in a real terminal
```

or, if that's non-interactive-blocked (e.g. run through an agent), write the
migration SQL by hand under `backend/prisma/migrations/<timestamp>_name/migration.sql`,
then:

```powershell
npx prisma migrate deploy
npx prisma generate
```

## Creating accounts

Drivers don't self-register in the app — create their accounts manually:

```powershell
cd backend
npm run create-driver -- "Full Name" "09XXXXXXXXX" "Password123!" "ABC123"
```

Plate number must be exactly 3 letters + 3 numbers (standard PH format,
no dash/space needed — `abc-123` or `abc 123` get auto-normalized to
`ABC123` too).    # CAN BE 4 DIGITS

Commuters self-register from the app's Sign Up screen — no manual step needed.

Admins don't self-register either — there's no sign-up UI at all, only this:

```powershell
cd backend
npm run create-admin -- "Full Name" "email@example.com" "Password123!"
```

## Backend checks

```powershell
npx tsc --noEmit               # typecheck
curl.exe http://localhost:4000/api/health
```

## Admin website checks

```powershell
cd admin
npm run build                  # typecheck (tsc -b) + production build
```

## Flutter checks

```powershell
flutter analyze                # static analysis / lint
flutter pub get                # after editing pubspec.yaml
flutter devices                # list run targets (Windows, Chrome, connected phone, etc.)
```

## Notes

- Android **emulator** needs the backend base URL set to `10.0.2.2` instead
  of `localhost` (see `lib/core/services/api_client.dart`).
- A physical Android device over USB needs `adb reverse tcp:4000 tcp:4000`
  once per debugging session for `localhost` to reach your machine.
- `POST /api/driver/signup` is still open/unauthenticated on purpose, for
  local dev and the `create-driver` script — the real, admin-gated way to
  create a driver account is now the admin website's Drivers page (or
  `POST /api/admin/drivers`), not this endpoint.
- No email provider is wired up yet, same as SMS for OTP — the admin
  forgot-password reset link is logged to the backend console
  (`[ADMIN PASSWORD RESET] ...`) instead of actually being emailed.
