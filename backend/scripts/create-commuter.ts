import 'dotenv/config';
import bcrypt from 'bcryptjs';

import { prisma } from '../src/lib/prisma';
import { toE164 } from '../src/utils/phone';
import { toTitleCase } from '../src/utils/text';

/** Mirrors commuter.ts's own (unexported) generateCommuterId — kept as a
 * small local copy here rather than exporting that one just for this
 * one-off script to import. */
async function generateCommuterId(): Promise<string> {
  let next = (await prisma.commuter.count()) + 1;
  for (;;) {
    const candidate = `CM-${next.toString().padStart(5, '0')}`;
    const exists = await prisma.commuter.findUnique({ where: { commuterId: candidate } });
    if (!exists) return candidate;
    next++;
  }
}

async function main() {
  const [rawFullName, rawMobileNumber, password] = process.argv.slice(2);

  if (!rawFullName || !rawMobileNumber || !password) {
    console.error('Usage: npm run create-commuter -- "Full Name" "09XXXXXXXXX" "Password123!"');
    process.exitCode = 1;
    return;
  }

  const fullName = toTitleCase(rawFullName);
  const mobileNumber = toE164(rawMobileNumber);

  const existing = await prisma.commuter.findUnique({ where: { mobileNumber } });
  if (existing) {
    console.error(`A commuter with ${mobileNumber} already exists (${existing.commuterId}).`);
    process.exitCode = 1;
    return;
  }

  const passwordHash = await bcrypt.hash(password, 10);
  // Skips the normal KYC flow entirely (no ID/selfie on file) — an
  // admin/test-created account is trusted by construction, same
  // reasoning as create-driver.ts having no license-verification step
  // of its own either.
  const commuter = await prisma.commuter.create({
    data: {
      commuterId: await generateCommuterId(),
      fullName,
      mobileNumber,
      passwordHash,
      phoneVerifiedAt: new Date(),
      verificationStatus: 'APPROVED',
      isActive: true,
    },
  });

  console.log('Commuter account created:');
  console.log(`  commuterId:   ${commuter.commuterId}`);
  console.log(`  fullName:     ${commuter.fullName}`);
  console.log(`  mobileNumber: ${commuter.mobileNumber}`);
  console.log(`  status:       ${commuter.verificationStatus} / active`);
}

main()
  .catch((err) => {
    console.error(err);
    process.exitCode = 1;
  })
  .finally(() => prisma.$disconnect());
