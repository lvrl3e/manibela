import 'dotenv/config';
import bcrypt from 'bcryptjs';

import { prisma } from '../src/lib/prisma';
import { toE164 } from '../src/utils/phone';
import { isValidPlateNumber, normalizePlateNumber } from '../src/utils/plate';
import { generateDriverId } from '../src/utils/driverId';
import { generateQrToken } from '../src/utils/qrToken';

async function main() {
  const [fullName, rawMobileNumber, password, rawPlateNumber] = process.argv.slice(2);

  if (!fullName || !rawMobileNumber || !password || !rawPlateNumber) {
    console.error(
      'Usage: npm run create-driver -- "Full Name" "09XXXXXXXXX" "Password123!" "ABC123"',
    );
    process.exitCode = 1;
    return;
  }

  const plateNumber = normalizePlateNumber(rawPlateNumber);
  if (!isValidPlateNumber(plateNumber)) {
    console.error(
      `"${rawPlateNumber}" isn't a valid plate — expected 3 letters followed by 3 numbers (e.g. ABC123).`,
    );
    process.exitCode = 1;
    return;
  }

  const mobileNumber = toE164(rawMobileNumber);

  const existing = await prisma.driver.findUnique({ where: { mobileNumber } });
  if (existing) {
    console.error(`A driver with ${mobileNumber} already exists (${existing.driverId}).`);
    process.exitCode = 1;
    return;
  }

  const passwordHash = await bcrypt.hash(password, 10);
  const driver = await prisma.driver.create({
    data: {
      driverId: await generateDriverId(),
      fullName,
      mobileNumber,
      passwordHash,
      plateNumber,
      qrToken: await generateQrToken(),
    },
  });

  console.log('Driver account created:');
  console.log(`  driverId:     ${driver.driverId}`);
  console.log(`  fullName:     ${driver.fullName}`);
  console.log(`  mobileNumber: ${driver.mobileNumber}`);
  console.log(`  plateNumber:  ${driver.plateNumber}`);
}

main()
  .catch((err) => {
    console.error(err);
    process.exitCode = 1;
  })
  .finally(() => prisma.$disconnect());
