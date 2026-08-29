ALTER TABLE "PendingCommuterSignup" ADD COLUMN "diditSessionId" TEXT;
ALTER TABLE "PendingCommuterSignup" ADD COLUMN "diditDecision" TEXT;
ALTER TABLE "Commuter" ADD COLUMN "diditSessionId" TEXT;
ALTER TABLE "Driver" ADD COLUMN "diditSessionId" TEXT;
