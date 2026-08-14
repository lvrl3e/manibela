import { PrismaClient } from '@prisma/client';
const prisma = new PrismaClient();
const c = await prisma.complaint.findUnique({ where: { id: 'cmssob3gk0000uwcoq135rag4' } });
console.log(c);
await prisma.$disconnect();
