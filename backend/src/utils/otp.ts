import type { OtpPurpose } from '@prisma/client';
import { prisma } from '../lib/prisma';

const OTP_TTL_MINUTES = 5;

function generateCode(): string {
  return Math.floor(100000 + Math.random() * 900000).toString();
}

/**
 * Issues a fresh OTP for [mobileNumber], invalidating any earlier
 * unconsumed codes for the same number+purpose so only the latest one
 * verifies.
 *
 * There's no SMS provider wired up yet, so the code is logged to the
 * server console instead of actually being texted — swap this out for a
 * real SMS gateway (Semaphore, Twilio, etc.) once one is available.
 */
export async function issueOtp(
  mobileNumber: string,
  purpose: OtpPurpose,
): Promise<string> {
  await prisma.otpCode.updateMany({
    where: { mobileNumber, purpose, consumed: false },
    data: { consumed: true },
  });

  const code = generateCode();
  await prisma.otpCode.create({
    data: {
      mobileNumber,
      purpose,
      code,
      expiresAt: new Date(Date.now() + OTP_TTL_MINUTES * 60_000),
    },
  });

  console.log(`[OTP] ${purpose} code for ${mobileNumber}: ${code}`);
  return code;
}

export async function verifyOtp(
  mobileNumber: string,
  purpose: OtpPurpose,
  code: string,
): Promise<boolean> {
  const match = await prisma.otpCode.findFirst({
    where: {
      mobileNumber,
      purpose,
      code,
      consumed: false,
      expiresAt: { gt: new Date() },
    },
    orderBy: { createdAt: 'desc' },
  });

  if (!match) return false;

  await prisma.otpCode.update({
    where: { id: match.id },
    data: { consumed: true },
  });

  return true;
}
