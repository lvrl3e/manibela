-- CreateEnum
CREATE TYPE "NotificationRecipientType" AS ENUM ('COMMUTER', 'DRIVER', 'ADMIN');

-- CreateTable
CREATE TABLE "Notification" (
    "id" TEXT NOT NULL,
    "recipientType" "NotificationRecipientType" NOT NULL,
    "recipientId" TEXT,
    "title" TEXT NOT NULL,
    "message" TEXT NOT NULL,
    "isRead" BOOLEAN NOT NULL DEFAULT false,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "Notification_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "DriverDailyLog" (
    "id" TEXT NOT NULL,
    "driverId" TEXT NOT NULL,
    "date" DATE NOT NULL,
    "startOdo" DOUBLE PRECISION NOT NULL,
    "endOdo" DOUBLE PRECISION NOT NULL,
    "earnings" DOUBLE PRECISION NOT NULL,
    "fuelExpense" DOUBLE PRECISION NOT NULL DEFAULT 0,
    "otherExpenses" DOUBLE PRECISION NOT NULL DEFAULT 0,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMP(3) NOT NULL,

    CONSTRAINT "DriverDailyLog_pkey" PRIMARY KEY ("id")
);

-- CreateIndex
CREATE INDEX "Notification_recipientType_recipientId_isRead_idx" ON "Notification"("recipientType", "recipientId", "isRead");

-- CreateIndex
CREATE INDEX "DriverDailyLog_driverId_date_idx" ON "DriverDailyLog"("driverId", "date");

-- CreateIndex
CREATE UNIQUE INDEX "DriverDailyLog_driverId_date_key" ON "DriverDailyLog"("driverId", "date");
