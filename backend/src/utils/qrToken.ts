import { randomBytes } from 'node:crypto';
import { prisma } from '../lib/prisma';

/**
 * Random opaque token for a driver's QR code. Generated once, at account
 * creation — permanent for the life of the account, never rotated. Losing
 * it (a leaked photo, etc.) would need a real support process to reissue,
 * not a self-serve button.
 */
export async function generateQrToken(): Promise<string> {
  for (;;) {
    const candidate = randomBytes(24).toString('base64url');
    const exists = await prisma.driver.findUnique({ where: { qrToken: candidate } });
    if (!exists) return candidate;
  }
}
