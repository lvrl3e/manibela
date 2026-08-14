-- CreateTable
CREATE TABLE "TripBoarding" (
    "id" TEXT NOT NULL,
    "tripId" TEXT NOT NULL,
    "commuterId" TEXT NOT NULL,
    "boardedAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "TripBoarding_pkey" PRIMARY KEY ("id")
);

-- CreateIndex
CREATE INDEX "TripBoarding_tripId_idx" ON "TripBoarding"("tripId");

-- CreateIndex
CREATE INDEX "TripBoarding_commuterId_idx" ON "TripBoarding"("commuterId");

-- CreateIndex
CREATE UNIQUE INDEX "TripBoarding_tripId_commuterId_key" ON "TripBoarding"("tripId", "commuterId");
