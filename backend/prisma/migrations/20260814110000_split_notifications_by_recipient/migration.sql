-- CreateTable
CREATE TABLE "DriverNotification" (
    "id" TEXT NOT NULL,
    "recipientId" TEXT NOT NULL,
    "title" TEXT NOT NULL,
    "message" TEXT NOT NULL,
    "isRead" BOOLEAN NOT NULL DEFAULT false,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "type" TEXT,
    "referenceId" TEXT,

    CONSTRAINT "DriverNotification_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "CommuterNotification" (
    "id" TEXT NOT NULL,
    "recipientId" TEXT NOT NULL,
    "title" TEXT NOT NULL,
    "message" TEXT NOT NULL,
    "isRead" BOOLEAN NOT NULL DEFAULT false,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "type" TEXT,
    "referenceId" TEXT,

    CONSTRAINT "CommuterNotification_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "AdminNotification" (
    "id" TEXT NOT NULL,
    "title" TEXT NOT NULL,
    "message" TEXT NOT NULL,
    "isRead" BOOLEAN NOT NULL DEFAULT false,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "type" TEXT,
    "referenceId" TEXT,

    CONSTRAINT "AdminNotification_pkey" PRIMARY KEY ("id")
);

-- CreateIndex
CREATE INDEX "DriverNotification_recipientId_isRead_idx" ON "DriverNotification"("recipientId", "isRead");

-- CreateIndex
CREATE INDEX "CommuterNotification_recipientId_isRead_idx" ON "CommuterNotification"("recipientId", "isRead");

-- CreateIndex
CREATE INDEX "AdminNotification_isRead_idx" ON "AdminNotification"("isRead");

-- Migrate existing rows out of the old polymorphic table before dropping it.
INSERT INTO "DriverNotification" ("id", "recipientId", "title", "message", "isRead", "createdAt", "type", "referenceId")
SELECT "id", "recipientId", "title", "message", "isRead", "createdAt", "type", "referenceId"
FROM "Notification"
WHERE "recipientType" = 'DRIVER' AND "recipientId" IS NOT NULL;

INSERT INTO "CommuterNotification" ("id", "recipientId", "title", "message", "isRead", "createdAt", "type", "referenceId")
SELECT "id", "recipientId", "title", "message", "isRead", "createdAt", "type", "referenceId"
FROM "Notification"
WHERE "recipientType" = 'COMMUTER' AND "recipientId" IS NOT NULL;

INSERT INTO "AdminNotification" ("id", "title", "message", "isRead", "createdAt", "type", "referenceId")
SELECT "id", "title", "message", "isRead", "createdAt", "type", "referenceId"
FROM "Notification"
WHERE "recipientType" = 'ADMIN';

-- DropTable
DROP TABLE "Notification";

-- DropEnum
DROP TYPE "NotificationRecipientType";
