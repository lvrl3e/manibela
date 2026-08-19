import path from 'node:path';
import 'dotenv/config';
import express from 'express';
import cors from 'cors';

import healthRouter from './routes/health';
import commuterRouter from './routes/commuter';
import driverRouter from './routes/driver';
import adminRouter from './routes/admin';
import { errorHandler } from './middleware/errorHandler';
import { apiLimiter } from './middleware/rateLimit';
import { startDriverLogReminderJobs } from './jobs/driverLogReminders';

const app = express();

// The Flutter app calls this API directly (no browser, no Origin header),
// so CORS only ever applies to browser clients — the admin website.
// CORS_ORIGINS lets a real deployment add its production admin domain
// without touching code.
const allowedOrigins = (process.env.CORS_ORIGINS ?? '')
  .split(',')
  .map((origin) => origin.trim())
  .filter(Boolean);

// Any localhost port, always allowed (in every environment, not just
// dev) — `npm run dev` for the admin site can land on 5173, 5174, 5175...
// depending on what else is already running on the machine, and an
// Origin header of "localhost" can only ever come from a browser on the
// same machine anyway, so there's nothing for a remote attacker to spoof
// here. Keeps local dev working with zero config regardless of which
// port Vite happens to pick.
const localhostOriginPattern = /^https?:\/\/(localhost|127\.0\.0\.1):\d+$/;

app.use(
  cors({
    origin(origin, callback) {
      if (!origin || allowedOrigins.includes(origin) || localhostOriginPattern.test(origin)) {
        callback(null, true);
      } else {
        callback(new Error(`Origin not allowed: ${origin}`));
      }
    },
  }),
);
app.use(express.json());
app.use('/api', apiLimiter);

// Uploaded profile photos — served as plain static files under /uploads,
// matching the relative photoUrl paths stored in the database (see
// middleware/upload.ts). The client prepends its own configured API base
// URL to these, the same way it does for every other request, so this
// never hardcodes what host the server thinks it's reachable at.
app.use('/uploads', express.static(path.join(__dirname, '..', 'uploads')));

app.get('/', (_req, res) => {
  res.json({ name: 'ManibelApp backend', health: '/api/health' });
});

app.use('/api/health', healthRouter);
app.use('/api/commuter', commuterRouter);
app.use('/api/driver', driverRouter);
app.use('/api/admin', adminRouter);

app.use(errorHandler);

const PORT = Number(process.env.PORT ?? 4000);
app.listen(PORT, () => {
  console.log(`ManibelApp backend listening on http://localhost:${PORT}`);
});

startDriverLogReminderJobs();
