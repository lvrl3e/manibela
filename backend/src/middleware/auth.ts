import type { NextFunction, Request, Response } from 'express';
import { prisma } from '../lib/prisma';
import { verifyAuthToken, type AuthRole } from '../utils/jwt';

/** Requires a valid Bearer token; optionally restricts it to one role.
 *
 * Driver/commuter/admin tokens are also checked against that account's
 * current `isActive` on every request (an extra DB lookup, but these are
 * the only roles that can be soft-disabled — see PATCH
 * /drivers/:id/status, /commuters/:id/status, and /admins/:id/status). A
 * JWT is stateless and valid for JWT_EXPIRES_IN (7 days by default)
 * regardless of what happens to the account after it's issued, so without
 * this a deactivation would do nothing until that token happened to
 * expire — the account keeps working normally. `code: 'ACCOUNT_DEACTIVATED'`
 * on the 401 is what the Flutter apps key off of to force an immediate
 * logout instead of treating it like any other auth failure (see
 * ApiClient.onAccountDeactivated); the admin site's own ApiClient checks
 * for the same code. */
export function requireAuth(role?: AuthRole) {
  return async (req: Request, res: Response, next: NextFunction) => {
    const header = req.headers.authorization;
    const token = header?.startsWith('Bearer ') ? header.slice(7) : undefined;

    if (!token) {
      res.status(401).json({ error: 'Missing bearer token.' });
      return;
    }

    try {
      const payload = verifyAuthToken(token);
      if (role && payload.role !== role) {
        res.status(403).json({ error: 'Not allowed for this account type.' });
        return;
      }

      if (payload.role === 'driver' || payload.role === 'commuter' || payload.role === 'admin') {
        const account =
          payload.role === 'driver'
            ? await prisma.driver.findUnique({ where: { id: payload.sub }, select: { isActive: true } })
            : payload.role === 'commuter'
              ? await prisma.commuter.findUnique({ where: { id: payload.sub }, select: { isActive: true } })
              : await prisma.admin.findUnique({ where: { id: payload.sub }, select: { isActive: true } });
        if (!account || !account.isActive) {
          res.status(401).json({ error: 'This account has been deactivated.', code: 'ACCOUNT_DEACTIVATED' });
          return;
        }
      }

      req.auth = payload;
      next();
    } catch {
      res.status(401).json({ error: 'Invalid or expired token.' });
    }
  };
}

/** Chains after `requireAuth('admin')` — restricts to the single Main
 * Admin account (see AdminRole's doc comment in schema.prisma). Looked up
 * fresh from the database on every call rather than trusted from the JWT
 * (which only ever carries the account *type*, the generic 'admin' —
 * never this business-level role), same reasoning as requireAuth's own
 * isActive check above: a stateless token shouldn't go on carrying
 * elevated privilege after it's been taken away. Every admin-account-
 * management endpoint that creates, changes the role of, deactivates, or
 * resets the password of an admin account must use this — see
 * ADMIN ACCOUNTS in routes/admin.ts. */
export function requireMainAdmin() {
  return async (req: Request, res: Response, next: NextFunction) => {
    const admin = await prisma.admin.findUnique({ where: { id: req.auth!.sub }, select: { role: true } });
    if (!admin || admin.role !== 'MAIN_ADMIN') {
      res.status(403).json({ error: 'Only the Main Admin can perform this action.' });
      return;
    }
    next();
  };
}
