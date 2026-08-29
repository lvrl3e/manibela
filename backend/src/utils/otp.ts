import type { OtpPurpose } from '@prisma/client';
import { prisma } from '../lib/prisma';
import { sendSms } from '../lib/sms';
import { sendEmail } from '../lib/email';

const OTP_TTL_MINUTES = 5;

function generateCode(): string {
  return Math.floor(100000 + Math.random() * 900000).toString();
}

/**
 * Issues a fresh OTP for [identifier], invalidating any earlier
 * unconsumed codes for the same identifier+purpose so only the latest
 * one verifies.
 *
 * `channel` picks how the code actually reaches the user — this same
 * function is called with a real PH mobile number for every commuter/
 * driver purpose (channel: 'sms', the default, via Semaphore) and with
 * an email address for admin's password reset (channel: 'email', via
 * Resend), so it can't always mean "text this".
 */
export async function issueOtp(
  identifier: string,
  purpose: OtpPurpose,
  { channel = 'sms' }: { channel?: 'sms' | 'email' } = {},
): Promise<string> {
  await prisma.otpCode.updateMany({
    where: { mobileNumber: identifier, purpose, consumed: false },
    data: { consumed: true },
  });

  const code = generateCode();
  await prisma.otpCode.create({
    data: {
      mobileNumber: identifier,
      purpose,
      code,
      expiresAt: new Date(Date.now() + OTP_TTL_MINUTES * 60_000),
    },
  });

  console.log(`[OTP] ${purpose} code for ${identifier}: ${code}`);

  if (channel === 'sms') {
    await sendSms(identifier, `Your ManibelaApp verification code is ${code}. It expires in ${OTP_TTL_MINUTES} minutes.`);
  } else {
    await sendEmail(
      identifier,
      'Your ManibelaApp verification code',
      `<p>Your verification code is <strong>${code}</strong>. It expires in ${OTP_TTL_MINUTES} minutes.</p>`,
    );
  }

  return code;
}

/**
 * Checks [code] for [mobileNumber]/[purpose]. By default this *spends*
 * the code (marks it consumed, so it can't verify again) — pass
 * `consume: false` for an early "is this even right?" check (e.g. an OTP
 * screen's own Verify button) that a later call, like reset-password,
 * still needs to actually spend. Without that distinction, an earlier
 * peek would burn the code and the real, final check would always fail
 * with "invalid or expired" even though the user typed it correctly.
 *
 * `checkExpiry: false` drops the TTL check entirely (the match still has
 * to be an unconsumed code for this number/purpose — just not a
 * time-bounded one). Expiry is meant to bound how long a code sits
 * unused on the OTP screen, not how long someone takes filling in a new
 * password afterward — a call like reset-password, made *after* the
 * code already passed the OTP screen's own (expiry-checked) verify,
 * should pass this flag so a slow typist isn't punished with an
 * "expired" error nowhere near an OTP field to fix it. The code is still
 * single-use and gets invalidated the moment a new one is issued for the
 * same number (see issueOtp), so this doesn't leave it valid forever.
 */
export async function verifyOtp(
  mobileNumber: string,
  purpose: OtpPurpose,
  code: string,
  { consume = true, checkExpiry = true }: { consume?: boolean; checkExpiry?: boolean } = {},
): Promise<boolean> {
  const match = await prisma.otpCode.findFirst({
    where: {
      mobileNumber,
      purpose,
      code,
      consumed: false,
      ...(checkExpiry ? { expiresAt: { gt: new Date() } } : {}),
    },
    orderBy: { createdAt: 'desc' },
  });

  if (!match) return false;

  if (consume) {
    await prisma.otpCode.update({
      where: { id: match.id },
      data: { consumed: true },
    });
  }

  return true;
}
