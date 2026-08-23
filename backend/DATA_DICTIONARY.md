# ManibelApp Data Dictionary

Field-by-field reference for every table in the ManibelApp database
(PostgreSQL via Prisma). Companion to [`DATABASE_SCHEMA.md`](DATABASE_SCHEMA.md),
which explains the *why* behind the design — this file is the exhaustive
*what*: every column, its type, its constraints, and a one-line
description. Current as of 2026-08-18; source of truth is
[`prisma/schema.prisma`](prisma/schema.prisma).

**Legend:** PK = Primary Key · FK* = references another table's id, but
as a plain column, not a DB-enforced foreign key (see `DATABASE_SCHEMA.md`)
· U = Unique · N = Nullable · Default = value when not supplied.

---

## Commuter
Rider account. Table name: `Commuter`.

| Field | Type | Constraints | Description |
|---|---|---|---|
| `id` | String (cuid) | PK | Internal row id |
| `commuterId` | String | U, NOT NULL | Human-readable display id, e.g. `CM-00001` |
| `fullName` | String | NOT NULL | |
| `mobileNumber` | String | U, NOT NULL | E.164 format, `+63XXXXXXXXXX` |
| `passwordHash` | String | NOT NULL | bcrypt hash, never plaintext |
| `dateOfBirth` | Date | N | Collected at signup itself; **admin-only to edit** afterward — `PATCH /commuter/me` doesn't accept it, only `PATCH /admin/commuters/:id/date-of-birth` |
| `photoUrl` | String | N | Relative path, e.g. `/uploads/profile-photos/xyz.png` |
| `phoneVerifiedAt` | DateTime | N | Set once signup OTP is verified |
| `idType` | String | N | Government ID type submitted at signup |
| `idFrontUrl` | String | N | |
| `idBackUrl` | String | N | |
| `selfieUrl` | String | N | |
| `verificationStatus` | Enum `IdVerificationStatus` | N, default: none | `PENDING` \| `APPROVED` \| `REJECTED`; null = nothing submitted yet |
| `isActive` | Boolean | NOT NULL, default `false` | Login gate; flipped true on admin approval |
| `createdAt` | DateTime | NOT NULL, default: now | |
| `updatedAt` | DateTime | NOT NULL, auto-updated | |

## Driver
Jeepney driver account, admin-created. Table name: `Driver`.

| Field | Type | Constraints | Description |
|---|---|---|---|
| `id` | String (cuid) | PK | |
| `driverId` | String | U, NOT NULL | e.g. `DR-00001` |
| `fullName` | String | NOT NULL | |
| `mobileNumber` | String | U, NOT NULL | E.164 format |
| `passwordHash` | String | NOT NULL | |
| `plateNumber` | String | NOT NULL | |
| `dateOfBirth` | Date | N | Optional at Add Driver; **admin-only to edit** afterward, same as `Commuter.dateOfBirth` |
| `photoUrl` | String | N | |
| `licenseFrontUrl` | String | N | Submitted by the **driver themselves** (Settings → License Number), both sides required together — no admin-side upload exists |
| `licenseBackUrl` | String | N | |
| `licenseNumber` | String | N | Always admin-entered — recorded directly (Add Driver / a correction) or typed in while reviewing a photo. Never OCR'd |
| `licenseVerificationStatus` | Enum `IdVerificationStatus` | N, default: none | null → `PENDING` (photos submitted) → `APPROVED`/`REJECTED` (admin review). **Gates `POST /driver/trips/start`** |
| `qrToken` | String | U, N | Permanent token encoded into the driver's QR code |
| `isActive` | Boolean | NOT NULL, default `true` | Soft-disable flag |
| `createdAt` | DateTime | NOT NULL, default: now | |
| `updatedAt` | DateTime | NOT NULL, auto-updated | |

## Admin
Dashboard operator/staff account. Table name: `Admin`.

| Field | Type | Constraints | Description |
|---|---|---|---|
| `id` | String (cuid) | PK | |
| `email` | String | U, NOT NULL | Login identifier |
| `passwordHash` | String | NOT NULL | |
| `fullName` | String | NOT NULL | |
| `role` | Enum `AdminRole` | NOT NULL, default `ADMIN` | `MAIN_ADMIN` \| `ADMIN` — exactly one `MAIN_ADMIN` row enforced by a partial unique index |
| `isActive` | Boolean | NOT NULL, default `true` | Main Admin can never be deactivated (app-enforced) |
| `lastLoginAt` | DateTime | N | Null until first login |
| `createdAt` | DateTime | NOT NULL, default: now | |
| `updatedAt` | DateTime | NOT NULL, auto-updated | |

## PendingCommuterSignup
Staging row for an in-progress commuter signup. Table name: `PendingCommuterSignup`.

| Field | Type | Constraints | Description |
|---|---|---|---|
| `id` | String (cuid) | PK | |
| `ticket` | String | U, NOT NULL | Opaque token identifying this signup-in-progress |
| `fullName` | String | NOT NULL | |
| `mobileNumber` | String | NOT NULL | Not yet unique-constrained (no Commuter row exists yet) |
| `passwordHash` | String | NOT NULL | Hashed before staging, never plaintext |
| `dateOfBirth` | Date | N | Collected on the signup form itself; copied to `Commuter.dateOfBirth` on redemption |
| `idType` | String | N | |
| `idFrontUrl` | String | N | |
| `idBackUrl` | String | N | |
| `selfieUrl` | String | N | |
| `expiresAt` | DateTime | NOT NULL | |
| `createdAt` | DateTime | NOT NULL, default: now | |

## Trip
One jeepney run, start to end. Table name: `Trip`.

| Field | Type | Constraints | Description |
|---|---|---|---|
| `id` | String (cuid) | PK | |
| `driverId` | String | FK* → Driver.id, NOT NULL | |
| `route` | String | N | e.g. `Pasig – Quiapo` |
| `status` | Enum `TripStatus` | NOT NULL, default `ACTIVE` | `ACTIVE` \| `COMPLETED` |
| `currentLat` | Float | N | Overwritten on each location ping, not history |
| `currentLng` | Float | N | |
| `locationUpdatedAt` | DateTime | N | Timestamp of the last location ping |
| `startedAt` | DateTime | NOT NULL, default: now | |
| `endedAt` | DateTime | N | |
| `isShortTrip` | Boolean | NOT NULL, default `false` | Auto-flagged if duration < 5 min (two tiers: < 60s and 60s–5 min, see `flagReason`); also settable manually by an admin |
| `flagReason` | String | N | Backend-generated explanation — wording distinguishes the < 60s tier from the 60s–5 min tier |
| `driverExplanation` | String | N | Driver's own account of a flagged trip |
| `explanationSubmittedAt` | DateTime | N | |
| `reviewStatus` | Enum `TripReviewStatus` | NOT NULL, default `PENDING` | `PENDING` \| `REVIEWED` \| `VALID` \| `INVALID` |
| `reviewedAt` | DateTime | N | |
| `reviewedBy` | String | FK* → Admin.id, N | |
| `adminReviewNote` | String | N | Required by the API when `reviewStatus` = `INVALID` |

## TripBoarding
One ride segment: a commuter's board→alight on one Trip. Table name: `TripBoarding`.

| Field | Type | Constraints | Description |
|---|---|---|---|
| `id` | String (cuid) | PK | |
| `tripId` | String | FK* → Trip.id, NOT NULL | |
| `commuterId` | String | FK* → Commuter.id, NOT NULL | U (partial, raw SQL) with `tripId` where `alightedAt IS NULL` — at most one open ride per commuter per trip |
| `boardedAt` | DateTime | NOT NULL, default: now | |
| `alightedAt` | DateTime | N | Null = still riding |
| `riders` | Int | N | Party size at boarding |

## DemandSignal
Anonymous "I want a ride here" ping. Table name: `DemandSignal`.

| Field | Type | Constraints | Description |
|---|---|---|---|
| `id` | String (cuid) | PK | |
| `commuterId` | String | FK* → Commuter.id, NOT NULL | Never exposed in any API response — signals are read as clusters only |
| `lat` | Float | NOT NULL | |
| `lng` | Float | NOT NULL | |
| `createdAt` | DateTime | NOT NULL, default: now | |
| `route` | String | N | |
| `partySize` | Int | N | How many people this ping is requesting a ride for; null treated as 1 |
| `fulfilledAt` | DateTime | N | Set on boarding or explicit cancel; null = still waiting |

## Complaint
Commuter-filed complaint against a driver. Table name: `Complaint`.

| Field | Type | Constraints | Description |
|---|---|---|---|
| `id` | String (cuid) | PK | |
| `complainantId` | String | FK* → Commuter.id, NOT NULL | |
| `driverId` | String | FK* → Driver.id, NOT NULL | Resolved from a plate number at submission time |
| `tripId` | String | FK* → Trip.id, N | Set only when filed from a specific Trip History entry |
| `complaintType` | String | NOT NULL | e.g. `Reckless Driving`, `Overcharging` |
| `description` | String | NOT NULL | |
| `attachmentUrl` | String | N | Optional photo/file evidence |
| `status` | Enum `ComplaintStatus` | NOT NULL, default `PENDING` | `PENDING` \| `INVESTIGATING` \| `RESOLVED` \| `REJECTED` |
| `createdAt` | DateTime | NOT NULL, default: now | |
| `updatedAt` | DateTime | NOT NULL, auto-updated | |

## Rating
A commuter's 1–5 star rating for one ride. Table name: `Rating`.

| Field | Type | Constraints | Description |
|---|---|---|---|
| `id` | String (cuid) | PK | |
| `tripId` | String | FK* → Trip.id, NOT NULL | U together with `commuterId` — one rating per commuter per trip |
| `driverId` | String | FK* → Driver.id, NOT NULL | |
| `commuterId` | String | FK* → Commuter.id, NOT NULL | |
| `stars` | Int | NOT NULL | 1–5, app-validated |
| `comment` | String | N | Optional freeform note |
| `createdAt` | DateTime | NOT NULL, default: now | |

## OtpCode
One-time codes for signup/reset/phone-change verification. Table name: `OtpCode`.

| Field | Type | Constraints | Description |
|---|---|---|---|
| `id` | String (cuid) | PK | |
| `mobileNumber` | String | NOT NULL | Or an admin's email for `PASSWORD_RESET` |
| `code` | String | NOT NULL | 6-digit code |
| `purpose` | Enum `OtpPurpose` | NOT NULL | `PASSWORD_RESET` \| `SIGNUP_VERIFICATION` \| `PHONE_CHANGE` |
| `consumed` | Boolean | NOT NULL, default `false` | Single-use |
| `expiresAt` | DateTime | NOT NULL | 5-minute TTL from issue |
| `createdAt` | DateTime | NOT NULL, default: now | |

## DriverNotification / CommuterNotification
Server-triggered notifications, one table per recipient type (identical shape). Table names: `DriverNotification`, `CommuterNotification`.

| Field | Type | Constraints | Description |
|---|---|---|---|
| `id` | String (cuid) | PK | |
| `recipientId` | String | FK* → Driver.id or Commuter.id, NOT NULL | |
| `title` | String | NOT NULL | |
| `message` | String | NOT NULL | |
| `isRead` | Boolean | NOT NULL, default `false` | |
| `createdAt` | DateTime | NOT NULL, default: now | |
| `type` | String | N | e.g. `TRIP_SHORT_FLAGGED`, `TRIP_REVIEWED` |
| `referenceId` | String | FK* → Trip.id, N | Lets the client navigate on tap |

## AdminNotification
Team-wide notifications (no per-recipient targeting). Table name: `AdminNotification`.

| Field | Type | Constraints | Description |
|---|---|---|---|
| `id` | String (cuid) | PK | |
| `title` | String | NOT NULL | |
| `message` | String | NOT NULL | |
| `isRead` | Boolean | NOT NULL, default `false` | Single shared flag for the whole admin team |
| `createdAt` | DateTime | NOT NULL, default: now | |
| `type` | String | N | |
| `referenceId` | String | FK* → Driver.id, N | Navigates to that driver's detail panel |

## DriverDailyLog
Driver's once-a-day self-reported operations summary. Table name: `DriverDailyLog`.

| Field | Type | Constraints | Description |
|---|---|---|---|
| `id` | String (cuid) | PK | |
| `driverId` | String | FK* → Driver.id, NOT NULL | U together with `date` — one row per driver per day, upserted |
| `date` | Date | NOT NULL | |
| `startOdo` | Float | NOT NULL | Starting odometer reading |
| `endOdo` | Float | NOT NULL | Ending odometer reading |
| `earnings` | Float | NOT NULL | Cash fares collected |
| `fuelExpense` | Float | NOT NULL, default `0` | |
| `otherExpenses` | Float | NOT NULL, default `0` | |
| `createdAt` | DateTime | NOT NULL, default: now | |
| `updatedAt` | DateTime | NOT NULL, auto-updated | |

---

## Enumerated types

| Enum | Values | Used by |
|---|---|---|
| `IdVerificationStatus` | `PENDING`, `APPROVED`, `REJECTED` | `Commuter.verificationStatus`, `Driver.licenseVerificationStatus` |
| `TripStatus` | `ACTIVE`, `COMPLETED` | `Trip.status` |
| `TripReviewStatus` | `PENDING`, `REVIEWED`, `VALID`, `INVALID` | `Trip.reviewStatus` |
| `ComplaintStatus` | `PENDING`, `INVESTIGATING`, `RESOLVED`, `REJECTED` | `Complaint.status` |
| `AdminRole` | `MAIN_ADMIN`, `ADMIN` | `Admin.role` |
| `OtpPurpose` | `PASSWORD_RESET`, `SIGNUP_VERIFICATION`, `PHONE_CHANGE` | `OtpCode.purpose` |
