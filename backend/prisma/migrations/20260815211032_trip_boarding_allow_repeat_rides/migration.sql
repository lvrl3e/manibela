-- DropIndex (the old unique constraint made a second ride on the same
-- driver Trip impossible to log — see TripBoarding's doc comment)
DROP INDEX "TripBoarding_tripId_commuterId_key";

-- CreateIndex — partial unique index: at most one *open* boarding
-- (alightedAt IS NULL) per (tripId, commuterId), so a re-scan/re-confirm
-- mid-ride still can't duplicate, but a genuinely new ride (boarded again
-- after already being alighted) is free to create its own row.
CREATE UNIQUE INDEX "TripBoarding_tripId_commuterId_open_key" ON "TripBoarding"("tripId", "commuterId") WHERE "alightedAt" IS NULL;
