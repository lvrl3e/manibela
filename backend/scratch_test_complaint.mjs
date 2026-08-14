import { PrismaClient } from '@prisma/client';
import jwt from 'jsonwebtoken';
import 'dotenv/config';

const prisma = new PrismaClient();

const commuter = await prisma.commuter.create({
  data: {
    commuterId: 'QA-9999',
    fullName: 'QA Complaint Tester',
    mobileNumber: '+639170009999',
    passwordHash: 'x',
    isActive: true,
    phoneVerifiedAt: new Date(),
  },
});

const token = jwt.sign({ sub: commuter.id, role: 'commuter' }, process.env.JWT_SECRET, { expiresIn: '1h' });
console.log('COMMUTER_ID=' + commuter.id);
console.log('TOKEN=' + token);

await prisma.$disconnect();
