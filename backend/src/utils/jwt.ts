import jwt, { type SignOptions } from 'jsonwebtoken';

function requiredEnv(name: string): string {
  const value = process.env[name];
  if (!value) throw new Error(`${name} is not set — check backend/.env`);
  return value;
}

const JWT_SECRET = requiredEnv('JWT_SECRET');
const JWT_EXPIRES_IN = (process.env.JWT_EXPIRES_IN ?? '7d') as SignOptions['expiresIn'];

export type AuthRole = 'commuter' | 'driver';

export interface AuthTokenPayload {
  sub: string;
  role: AuthRole;
}

export function signAuthToken(payload: AuthTokenPayload): string {
  return jwt.sign(payload, JWT_SECRET, { expiresIn: JWT_EXPIRES_IN });
}

export function verifyAuthToken(token: string): AuthTokenPayload {
  return jwt.verify(token, JWT_SECRET) as AuthTokenPayload;
}
