-- Partial index for "most recently started trip with a real location ping,
-- per driver" (GET /admin/jeepneys, distinct-on-driverId query) — narrower
-- and cheaper than a full [driverId, startedAt] index since most trips
-- never rack up more rows here than jeepneys actually being tracked live.
-- Prisma's schema DSL has no partial-index syntax, so this exists only in
-- SQL — see the note on the Trip model in schema.prisma.
CREATE INDEX "Trip_driverId_startedAt_located_idx" ON "Trip"("driverId", "startedAt" DESC) WHERE "currentLat" IS NOT NULL;

-- Widen TripBoarding's commuterId index to also cover boardedAt, for GET
-- /admin/commuters/:id/trips's paginated ride history.
DROP INDEX "TripBoarding_commuterId_idx";
CREATE INDEX "TripBoarding_commuterId_boardedAt_idx" ON "TripBoarding"("commuterId", "boardedAt");

-- Widen Complaint's status index to also cover createdAt, for GET
-- /admin/complaints's paginated "optionally filtered by status, newest
-- first" query; add a bare createdAt index for its unfiltered case.
DROP INDEX "Complaint_status_idx";
CREATE INDEX "Complaint_status_createdAt_idx" ON "Complaint"("status", "createdAt");
CREATE INDEX "Complaint_createdAt_idx" ON "Complaint"("createdAt");

-- New indexes for each notification table's paginated "this
-- recipient's/all notifications, newest first" GET.
CREATE INDEX "DriverNotification_recipientId_createdAt_idx" ON "DriverNotification"("recipientId", "createdAt");
CREATE INDEX "CommuterNotification_recipientId_createdAt_idx" ON "CommuterNotification"("recipientId", "createdAt");
CREATE INDEX "AdminNotification_createdAt_idx" ON "AdminNotification"("createdAt");
