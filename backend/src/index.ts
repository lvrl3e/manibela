import 'dotenv/config';
import express from 'express';
import cors from 'cors';

import healthRouter from './routes/health';
import commuterRouter from './routes/commuter';
import driverRouter from './routes/driver';
import adminRouter from './routes/admin';
import webhooksRouter from './routes/webhooks';
import { errorHandler } from './middleware/errorHandler';
import { apiLimiter } from './middleware/rateLimit';
import { startDriverLogReminderJobs } from './jobs/driverLogReminders';

const app = express();

// Render (and any real deployment) puts the app behind a reverse proxy —
// without this, Express ignores X-Forwarded-For entirely, so req.ip
// resolves to the proxy's own address for every request. That breaks
// express-rate-limit two ways: it refuses to trust the header (the
// ERR_ERL_UNEXPECTED_X_FORWARDED_FOR error), and if it didn't, every
// user behind the proxy would share one rate-limit bucket. `1` trusts
// exactly one hop — Render's own proxy — not arbitrary chained values a
// client could spoof further back.
app.set('trust proxy', 1);

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
// Mounted ahead of the global express.json() below, and only for this
// one path — Didit's webhook signature is computed over the exact raw
// bytes of the request body, so this route needs the untouched Buffer,
// not the already-parsed-and-reserialized object express.json() would
// otherwise hand it (see routes/webhooks.ts). Consuming the request
// stream here also means express.json() effectively no-ops for this
// specific path when it runs next.
app.use('/api/webhooks', express.raw({ type: 'application/json' }));

app.use(express.json());
app.use('/api', apiLimiter);

app.get('/', (_req, res) => {
  res.json({ name: 'ManibelaApp backend', health: '/api/health' });
});

app.use('/api/health', healthRouter);
app.use('/api/commuter', commuterRouter);
app.use('/api/driver', driverRouter);
app.use('/api/admin', adminRouter);
app.use('/api/webhooks', webhooksRouter);

app.use(errorHandler);

const PORT = Number(process.env.PORT ?? 4000);
app.listen(PORT, () => {
  console.log(`ManibelaApp backend listening on http://localhost:${PORT}`);
});

startDriverLogReminderJobs();
