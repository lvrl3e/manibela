-- CreateEnum
CREATE TYPE "OtpPurpose" AS ENUM ('PASSWORD_RESET');

-- CreateTable
CREATE TABLE "Commuter" (
    "id" TEXT NOT NULL,
    "commuterId" TEXT NOT NULL,
    "fullName" TEXT NOT NULL,
    "mobileNumber" TEXT NOT NULL,
    "passwordHash" TEXT NOT NULL,
    "dateOfBirth" TIMESTAMP(3),
    "photoUrl" TEXT,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMP(3) NOT NULL,

    CONSTRAINT "Commuter_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "Driver" (
    "id" TEXT NOT NULL,
    "driverId" TEXT NOT NULL,
    "fullName" TEXT NOT NULL,
    "mobileNumber" TEXT NOT NULL,
    "passwordHash" TEXT NOT NULL,
    "plateNumber" TEXT NOT NULL,
    "photoUrl" TEXT,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMP(3) NOT NULL,

    CONSTRAINT "Driver_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "OtpCode" (
    "id" TEXT NOT NULL,
    "mobileNumber" TEXT NOT NULL,
    "code" TEXT NOT NULL,
    "purpose" "OtpPurpose" NOT NULL,
    "consumed" BOOLEAN NOT NULL DEFAULT false,
    "expiresAt" TIMESTAMP(3) NOT NULL,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "OtpCode_pkey" PRIMARY KEY ("id")
);

-- CreateIndex
CREATE UNIQUE INDEX "Commuter_commuterId_key" ON "Commuter"("commuterId");

-- CreateIndex
CREATE UNIQUE INDEX "Commuter_mobileNumber_key" ON "Commuter"("mobileNumber");

-- CreateIndex
CREATE UNIQUE INDEX "Driver_driverId_key" ON "Driver"("driverId");

-- CreateIndex
CREATE UNIQUE INDEX "Driver_mobileNumber_key" ON "Driver"("mobileNumber");

-- CreateIndex
CREATE INDEX "OtpCode_mobileNumber_purpose_idx" ON "OtpCode"("mobileNumber", "purpose");
