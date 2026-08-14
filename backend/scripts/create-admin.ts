import 'dotenv/config';
import bcrypt from 'bcryptjs';

import { prisma } from '../src/lib/prisma';
import { toTitleCase } from '../src/utils/text';

async function main() {
  const [rawFullName, rawEmail, password] = process.argv.slice(2);

  if (!rawFullName || !rawEmail || !password) {
    console.error('Usage: npm run create-admin -- "Full Name" "email@example.com" "Password123!"');
    process.exitCode = 1;
    return;
  }

  const fullName = toTitleCase(rawFullName);
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

  // The very first admin ever created becomes the Main Admin (see
  // AdminRole's doc comment in schema.prisma) — there's no other bootstrap
  // path, since admin accounts can't self-register. Every admin created
  // afterwards, from here or from the Main Admin's own Settings ->
  // Admin Accounts UI, is a regular ADMIN.
  const adminCount = await prisma.admin.count();
  const role = adminCount === 0 ? 'MAIN_ADMIN' : 'ADMIN';

  const passwordHash = await bcrypt.hash(password, 10);
  const admin = await prisma.admin.create({
    data: { fullName, email, passwordHash, role },
  });

  console.log('Admin account created:');
  console.log(`  fullName: ${admin.fullName}`);
  console.log(`  email:    ${admin.email}`);
  console.log(`  role:     ${admin.role}`);
}

main()
  .catch((err) => {
    console.error(err);
    process.exitCode = 1;
  })
  .finally(() => prisma.$disconnect());
