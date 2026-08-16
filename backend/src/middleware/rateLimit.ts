import rateLimit, { ipKeyGenerator } from 'express-rate-limit';

/** Broad safety net over every /api route — generous enough that normal
 * app usage (polling, live maps, etc.) never comes close to it. */
export const apiLimiter = rateLimit({
  windowMs: 15 * 60 * 1000,
  limit: 600,
  standardHeaders: true,
  legacyHeaders: false,
});

/** Tighter limit for unauthenticated, brute-forceable endpoints — login,
 * signup, and OTP request/verify. Keyed by IP + request body's
 * mobileNumber (when present) so one IP can't lock out every account on
 * the device, but repeated attempts against a single number still get
 * throttled. */
export const authLimiter = rateLimit({
  windowMs: 15 * 60 * 1000,
  limit: 20,
  standardHeaders: true,
  legacyHeaders: false,
  keyGenerator: (req) => {
    const mobileNumber = (req.body as { mobileNumber?: unknown } | undefined)?.mobileNumber;
    const ip = ipKeyGenerator(req.ip ?? 'unknown');
    return typeof mobileNumber === 'string' ? `${ip}:${mobileNumber}` : ip;
  },
});
