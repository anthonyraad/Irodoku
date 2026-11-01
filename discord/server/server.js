// Pocket Daily Iro — Discord Activity backend + static host.
import express from 'express';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { getDb, pstDayKey, topPocket } from './firebase.js';

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const app = express();
app.use(express.json({ limit: '8kb' }));

const MIN_MS = 5000;
const MAX_MS = 24 * 3600e3;
const SLACK_MS = 3000; // network/clock slack on the start→finish window

// In-memory run starts: `${userId}:${day}` -> first start epoch ms.
// Single instance is fine for phase 1; mirrored to RTDB when configured.
const starts = new Map();

async function discordUser(req) {
  const auth = req.get('authorization') || '';
  const token = auth.startsWith('Bearer ') ? auth.slice(7) : null;
  if (!token) return null;
  const r = await fetch('https://discord.com/api/users/@me', { headers: { Authorization: `Bearer ${token}` } });
  if (!r.ok) return null;
  return r.json();
}

app.post('/api/token', async (req, res) => {
  const { DISCORD_CLIENT_ID, DISCORD_CLIENT_SECRET } = process.env;
  if (!DISCORD_CLIENT_ID || !DISCORD_CLIENT_SECRET) {
    return res.status(503).json({ error: 'server_not_configured' });
  }
  const code = req.body && req.body.code;
  if (typeof code !== 'string' || !code) return res.status(400).json({ error: 'missing_code' });
  const r = await fetch('https://discord.com/api/oauth2/token', {
    method: 'POST',
    headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
    body: new URLSearchParams({
      client_id: DISCORD_CLIENT_ID,
      client_secret: DISCORD_CLIENT_SECRET,
      grant_type: 'authorization_code',
      code,
    }),
  });
  const data = await r.json().catch(() => ({}));
  if (!r.ok || !data.access_token) return res.status(401).json({ error: 'exchange_failed' });
  res.json({ access_token: data.access_token });
});

function validDay(day) {
  if (typeof day !== 'string' || !/^\d{4}-\d{2}-\d{2}$/.test(day)) return false;
  const today = pstDayKey();
  const yesterday = pstDayKey(new Date(Date.now() - 86400e3));
  return day === today || day === yesterday; // allow a run that crossed midnight
}

app.post('/api/start', async (req, res) => {
  const user = await discordUser(req);
  if (!user) return res.status(401).json({ error: 'unauthorized' });
  const day = req.body && req.body.day;
  if (!validDay(day)) return res.status(400).json({ error: 'bad_day' });
  const key = `${user.id}:${day}`;
  let start = starts.get(key);
  if (!start) {
    const db = getDb();
    const ref = db && db.ref(`irodoku_daily_starts/${day}/pocket/${user.id}`);
    const prior = ref ? (await ref.get()).val() : null;
    start = typeof prior === 'number' ? prior : Date.now();
    starts.set(key, start);
    if (ref && prior == null) await ref.set(start);
  }
  res.json({ ok: true, start });
});

app.post('/api/score', async (req, res) => {
  const user = await discordUser(req);
  if (!user) return res.status(401).json({ error: 'unauthorized' });
  const { day, ms } = req.body || {};
  if (!validDay(day)) return res.status(400).json({ error: 'bad_day' });
  if (!Number.isInteger(ms) || ms < MIN_MS || ms > MAX_MS) return res.status(400).json({ error: 'bad_time' });
  let start = starts.get(`${user.id}:${day}`);
  if (!start && getDb()) {
    const v = (await getDb().ref(`irodoku_daily_starts/${day}/pocket/${user.id}`).get()).val();
    if (typeof v === 'number') start = v;
  }
  if (!start) return res.status(409).json({ error: 'no_start' });
  if (ms > Date.now() - start + SLACK_MS) return res.status(422).json({ error: 'time_exceeds_window' });
  const db = getDb();
  if (!db) return res.status(503).json({ error: 'db_not_configured' });
  const name = String(user.global_name || user.username || 'Player').slice(0, 24);
  const ref = db.ref(`irodoku_daily/${day}/pocket/${user.id}`);
  const result = await ref.transaction((cur) => {
    if (cur && typeof cur.ms === 'number' && cur.ms <= ms) return undefined; // keep best
    return { name, ms, at: Date.now(), src: 'discord' };
  });
  res.json({ ok: true, committed: result.committed });
});

app.get('/api/leaderboard', async (req, res) => {
  const day = typeof req.query.day === 'string' ? req.query.day : pstDayKey();
  if (!/^\d{4}-\d{2}-\d{2}$/.test(day)) return res.status(400).json({ error: 'bad_day' });
  try { res.json({ day, top: await topPocket(day, 10) }); }
  catch { res.status(503).json({ error: 'db_unavailable' }); }
});

app.get('/healthz', (_req, res) => res.send('ok'));
app.use(express.static(path.join(__dirname, 'public'), { index: 'index.html' }));
app.get('*', (_req, res) => res.sendFile(path.join(__dirname, 'public', 'index.html')));

const port = Number(process.env.PORT) || 8080;
app.listen(port, () => console.log(`Pocket Daily Iro on :${port}`));
