-- Widen the driverId+status index to also cover startedAt (the sort/
-- range-filter column every Trip History query uses), and add driverId-
-- scoped indexes for route/isShortTrip filtering, so a single driver's
-- Trip History stays index-served even at hundreds of thousands of rows.
DROP INDEX "Trip_driverId_status_idx";

CREATE INDEX "Trip_driverId_status_startedAt_idx" ON "Trip"("driverId", "status", "startedAt");
CREATE INDEX "Trip_driverId_route_idx" ON "Trip"("driverId", "route");
CREATE INDEX "Trip_driverId_isShortTrip_idx" ON "Trip"("driverId", "isShortTrip");
