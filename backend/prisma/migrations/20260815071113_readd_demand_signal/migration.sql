-- CreateTable
CREATE TABLE "DemandSignal" (
    "id" TEXT NOT NULL,
    "commuterId" TEXT NOT NULL,
    "lat" DOUBLE PRECISION NOT NULL,
    "lng" DOUBLE PRECISION NOT NULL,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "DemandSignal_pkey" PRIMARY KEY ("id")
);

-- CreateIndex
CREATE INDEX "DemandSignal_createdAt_idx" ON "DemandSignal"("createdAt");
