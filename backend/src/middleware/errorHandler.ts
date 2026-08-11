import type { NextFunction, Request, Response } from 'express';
import { ZodError } from 'zod';

export function errorHandler(
  err: unknown,
  _req: Request,
  res: Response,
  _next: NextFunction,
) {
  if (err instanceof ZodError) {
    res.status(400).json({ error: 'Validation failed.', details: err.issues });
    return;
  }

  console.error(err);
  res.status(500).json({ error: 'Something went wrong.' });
}
