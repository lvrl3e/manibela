-- No fare/payment feature in this app — TripBoarding's separate
-- regular/student/senior rider counts and computed fare collapse into a
-- single headcount. Existing rows are summed into that headcount rather
-- than losing the data outright.

-- AlterTable: add the new column first, backfill it, then drop the old
-- ones — in that order so no existing data is lost in between.
ALTER TABLE "TripBoarding" ADD COLUMN "riders" INTEGER;

UPDATE "TripBoarding"
SET "riders" = COALESCE("regularRiders", 0) + COALESCE("studentRiders", 0) + COALESCE("seniorRiders", 0)
WHERE "regularRiders" IS NOT NULL OR "studentRiders" IS NOT NULL OR "seniorRiders" IS NOT NULL;

ALTER TABLE "TripBoarding" DROP COLUMN "fare";
ALTER TABLE "TripBoarding" DROP COLUMN "regularRiders";
ALTER TABLE "TripBoarding" DROP COLUMN "studentRiders";
ALTER TABLE "TripBoarding" DROP COLUMN "seniorRiders";

-- AlterTable: DemandSignal gets a party-size field so a map cluster can
-- sum real headcount instead of just counting distinct accounts pinging.
ALTER TABLE "DemandSignal" ADD COLUMN "partySize" INTEGER;
