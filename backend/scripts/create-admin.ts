import 'dotenv/config';
import bcrypt from 'bcryptjs';

import { prisma } from '../src/lib/prisma';

async function main() {
  const [fullName, rawEmail, password] = process.argv.slice(2);

  if (!fullName || !rawEmail || !password) {
    console.error('Usage: npm run create-admin -- "Full Name" "email@example.com" "Password123!"');
    process.exitCode = 1;
    return;
  }

  const email = rawEmail.trim().toLowerCase();
  if (!/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email)) {
    console.error(`"${rawEmail}" isn't a valid email address.`);
    process.exitCode = 1;
    return;
  }

  if (password.length < 8) {
    console.error('Password must be at least 8 characters.');
    process.exitCode = 1;
    return;
  }

  const existing = await prisma.admin.findUnique({ where: { email } });
  if (existing) {
    console.error(`An admin with ${email} already exists.`);
    process.exitCode = 1;
    return;
  }

  const passwordHash = await bcrypt.hash(password, 10);
  const admin = await prisma.admin.create({
    data: { fullName, email, passwordHash },
  });

  console.log('Admin account created:');
  console.log(`  fullName: ${admin.fullName}`);
  console.log(`  email:    ${admin.email}`);
}

main()
  .catch((err) => {
    console.error(err);
    process.exitCode = 1;
  })
  .finally(() => prisma.$disconnect());
