-- CreateEnum
CREATE TYPE "TripReviewStatus" AS ENUM ('PENDING', 'REVIEWED', 'VALID', 'INVALID');

-- AlterTable
ALTER TABLE "Trip" ADD COLUMN     "isShortTrip" BOOLEAN NOT NULL DEFAULT false,
ADD COLUMN     "flagReason" TEXT,
ADD COLUMN     "driverExplanation" TEXT,
ADD COLUMN     "explanationSubmittedAt" TIMESTAMP(3),
ADD COLUMN     "reviewStatus" "TripReviewStatus" NOT NULL DEFAULT 'PENDING',
ADD COLUMN     "reviewedAt" TIMESTAMP(3),
ADD COLUMN     "reviewedBy" TEXT,
ADD COLUMN     "adminReviewNote" TEXT;

-- CreateIndex
CREATE INDEX "Trip_isShortTrip_reviewStatus_idx" ON "Trip"("isShortTrip", "reviewStatus");
