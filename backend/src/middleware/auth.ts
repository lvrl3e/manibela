import type { NextFunction, Request, Response } from 'express';
import { verifyAuthToken, type AuthRole } from '../utils/jwt';

/** Requires a valid Bearer token; optionally restricts it to one role. */
export function requireAuth(role?: AuthRole) {
  return (req: Request, res: Response, next: NextFunction) => {
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
      req.auth = payload;
      next();
    } catch {
      res.status(401).json({ error: 'Invalid or expired token.' });
    }
  };
}
