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
// without touching code; the localhost default keeps `npm run dev`
// working exactly as before.
const allowedOrigins = (process.env.CORS_ORIGINS ?? 'http://localhost:5173')
  .split(',')
  .map((origin) => origin.trim())
  .filter(Boolean);

app.use(
  cors({
    origin(origin, callback) {
      if (!origin || allowedOrigins.includes(origin)) {
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
