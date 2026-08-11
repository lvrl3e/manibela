import { PrismaClient } from '@prisma/client';

// Single shared instance — ts-node-dev's respawn-on-change would otherwise
// pile up new PrismaClients (and DB connections) across reloads.
export const prisma = new PrismaClient();
