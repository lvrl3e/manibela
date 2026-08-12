-- AlterTable
-- dateOfBirth is a calendar date, not an instant — storing it as
-- TIMESTAMP(3) meant every read/write went through a timezone-sensitive
-- conversion that could shift the day near a UTC boundary. DATE has no
-- time-of-day/timezone component at all, so that entire class of bug is
-- no longer possible at the storage layer.
ALTER TABLE "Commuter" ALTER COLUMN "dateOfBirth" TYPE DATE USING "dateOfBirth"::date;
ALTER TABLE "Driver" ALTER COLUMN "dateOfBirth" TYPE DATE USING "dateOfBirth"::date;
