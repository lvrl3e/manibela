import 'dotenv/config';
import bcrypt from 'bcryptjs';
import { prisma } from '../src/lib/prisma';

// Seeds one demo driver account so there's something real to log into
// without having to run create-driver.ts by hand first.
async function main() {
  const mobileNumber = '+639171234567';

  const existing = await prisma.driver.findUnique({ where: { mobileNumber } });
  if (existing) {
    console.log('Demo driver already seeded, skipping.');
    return;
  }

  const passwordHash = await bcrypt.hash('Driver@123', 10);
  await prisma.driver.create({
    data: {
      driverId: 'DR-00001',
      fullName: 'Juan Dela Cruz',
      mobileNumber,
      passwordHash,
      plateNumber: 'NGP123',
    },
  });

  console.log(`Seeded demo driver ${mobileNumber} / Driver@123`);
}

main()
  .catch((err) => {
    console.error(err);
    process.exitCode = 1;
  })
  .finally(() => prisma.$disconnect());
