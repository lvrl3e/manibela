-- AlterTable
ALTER TABLE "Commuter" ADD COLUMN "idType" TEXT,
ADD COLUMN "idFrontUrl" TEXT,
ADD COLUMN "idBackUrl" TEXT,
ADD COLUMN "selfieUrl" TEXT;

-- AlterTable
ALTER TABLE "PendingCommuterSignup" ADD COLUMN "idType" TEXT,
ADD COLUMN "idFrontUrl" TEXT,
ADD COLUMN "idBackUrl" TEXT,
ADD COLUMN "selfieUrl" TEXT;
