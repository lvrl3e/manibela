-- AlterTable
ALTER TABLE "Complaint" ADD COLUMN     "tripId" TEXT;

-- CreateIndex
CREATE INDEX "Complaint_tripId_idx" ON "Complaint"("tripId");

-- CreateTable
CREATE TABLE "Rating" (
    "id" TEXT NOT NULL,
    "tripId" TEXT NOT NULL,
    "driverId" TEXT NOT NULL,
    "commuterId" TEXT NOT NULL,
    "stars" INTEGER NOT NULL,
    "comment" TEXT,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "Rating_pkey" PRIMARY KEY ("id")
);

-- CreateIndex
CREATE INDEX "Rating_driverId_idx" ON "Rating"("driverId");

-- CreateIndex
CREATE UNIQUE INDEX "Rating_tripId_commuterId_key" ON "Rating"("tripId", "commuterId");
