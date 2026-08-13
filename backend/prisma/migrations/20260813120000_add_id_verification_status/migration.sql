-- CreateEnum
CREATE TYPE "IdVerificationStatus" AS ENUM ('PENDING', 'APPROVED', 'REJECTED');

-- AlterTable
ALTER TABLE "Commuter" ADD COLUMN "verificationStatus" "IdVerificationStatus";

-- Backfill: existing accounts that already submitted ID docs before this
-- column existed start in the review queue rather than silently invisible.
UPDATE "Commuter" SET "verificationStatus" = 'PENDING' WHERE "idFrontUrl" IS NOT NULL;

