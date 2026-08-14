-- AlterTable
ALTER TABLE "Trip" DROP COLUMN "passengerCount";

-- AlterTable
ALTER TABLE "Commuter" ALTER COLUMN "isActive" SET DEFAULT false;
