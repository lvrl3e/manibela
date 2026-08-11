import 'dotenv/config';
import express from 'express';
import cors from 'cors';

import healthRouter from './routes/health';
import commuterRouter from './routes/commuter';
import driverRouter from './routes/driver';
import { errorHandler } from './middleware/errorHandler';

const app = express();

app.use(cors());
app.use(express.json());

app.get('/', (_req, res) => {
  res.json({ name: 'ManibelApp backend', health: '/api/health' });
});

app.use('/api/health', healthRouter);
app.use('/api/commuter', commuterRouter);
app.use('/api/driver', driverRouter);

app.use(errorHandler);

const PORT = Number(process.env.PORT ?? 4000);
app.listen(PORT, () => {
  console.log(`ManibelApp backend listening on http://localhost:${PORT}`);
});
