-- CreateEnum
CREATE TYPE "PhotoAccessTargetType" AS ENUM ('COMMUTER', 'DRIVER');

-- CreateTable
CREATE TABLE "PhotoAccessLog" (
    "id" TEXT NOT NULL,
    "adminId" TEXT NOT NULL,
    "targetType" "PhotoAccessTargetType" NOT NULL,
    "targetId" TEXT NOT NULL,
    "viewedAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "PhotoAccessLog_pkey" PRIMARY KEY ("id")
);

-- CreateIndex
CREATE INDEX "PhotoAccessLog_targetType_targetId_viewedAt_idx" ON "PhotoAccessLog"("targetType", "targetId", "viewedAt");

-- CreateIndex
CREATE INDEX "PhotoAccessLog_adminId_viewedAt_idx" ON "PhotoAccessLog"("adminId", "viewedAt");
