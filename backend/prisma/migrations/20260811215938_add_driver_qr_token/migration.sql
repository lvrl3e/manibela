-- AlterTable
ALTER TABLE "Driver" ADD COLUMN "qrToken" TEXT;

-- CreateIndex
CREATE UNIQUE INDEX "Driver_qrToken_key" ON "Driver"("qrToken");
