-- AlterEnum
ALTER TYPE "OtpPurpose" ADD VALUE 'SIGNUP_VERIFICATION';

-- AlterTable
ALTER TABLE "Commuter" ADD COLUMN "phoneVerifiedAt" TIMESTAMP(3);
