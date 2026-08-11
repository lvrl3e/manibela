import { prisma } from '../lib/prisma';

/**
 * Next sequential DR-00001, DR-00002, ... id. Starts from the current
 * driver count (fast path, no collision in the common case) and walks
 * forward if that's already taken — covers gaps left by deleted drivers
 * without needing to parse/max every existing id.
 */
export async function generateDriverId(): Promise<string> {
  let next = (await prisma.driver.count()) + 1;
  for (;;) {
    const candidate = `DR-${next.toString().padStart(5, '0')}`;
    const exists = await prisma.driver.findUnique({ where: { driverId: candidate } });
    if (!exists) return candidate;
    next++;
  }
}
