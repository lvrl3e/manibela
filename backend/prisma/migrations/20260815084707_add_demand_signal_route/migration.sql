-- AlterTable
ALTER TABLE "DemandSignal" ADD COLUMN "route" TEXT;

-- CreateIndex
CREATE INDEX "DemandSignal_commuterId_fulfilledAt_idx" ON "DemandSignal"("commuterId", "fulfilledAt");
