// Pocket Daily Iro — Discord Activity API (Cloudflare Worker).
// Routes (behind Discord URL mapping '/api' -> this worker):
//   POST /api/token  POST /api/start  POST /api/score  GET /api/leaderboard
// Cron '0 8 * * *': post yesterday's Pocket top-10 to DISCORD_WEBHOOK_URL.
import { dbConfigured, rtdb, topPocket, writeBest } from './firebase.js';
import { leaderboardName, pstDayKey } from './names.js';
import { leaderboardEmbed, renderPng } from './render.js';

const MIN_MS = 5000;
const MAX_MS = 24 * 3600e3;
const SLACK_MS = 3000;
const DAY_RE = /^\d{4}-\d{2}-\d{2}$/;

const json = (body, status = 200) => new Response(JSON.stringify(body), {
  status, headers: { 'Content-Type': 'application/json', 'Cache-Control': 'no-store' },
});

async function readJson(req) { try { return await req.json(); } catch { return {}; } }

async function discordUser(req) {
  const auth = req.headers.get('Authorization') || '';
  if (!auth.startsWith('Bearer ') || auth.length < 15) return null;
  const r = await fetch('https://discord.com/api/v10/users/@me', { headers: { Authorization: auth } });
  return r.ok ? r.json() : null;
}

function validDay(day, now = Date.now()) {
  return typeof day === 'string' && DAY_RE.test(day)
    && (day === pstDayKey(now) || day === pstDayKey(now - 86400e3));
}

const startPath = (day, uid) => `irodoku_daily_starts/${day}/pocket/${uid}`;

async function handleToken(req, env) {
  if (!env.DISCORD_CLIENT_ID || !env.DISCORD_CLIENT_SECRET) return json({ error: 'server_not_configured' }, 503);
  const { code } = await readJson(req);
  if (typeof code !== 'string' || !code) return json({ error: 'missing_code' }, 400);
  const r = await fetch('https://discord.com/api/v10/oauth2/token', {
    method: 'POST',
    headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
    body: new URLSearchParams({
      client_id: env.DISCORD_CLIENT_ID, client_secret: env.DISCORD_CLIENT_SECRET,
      grant_type: 'authorization_code', code,
    }),
  });
  const data = await r.json().catch(() => ({}));
  if (!r.ok || !data.access_token) return json({ error: 'exchange_failed' }, 401);
  return json({ access_token: data.access_token });
}

async function handleStart(req, env) {
  const user = await discordUser(req);
  if (!user) return json({ error: 'unauthorized' }, 401);
  const { day } = await readJson(req);
  if (!validDay(day)) return json({ error: 'bad_day' }, 400);
  if (!dbConfigured(env)) return json({ error: 'db_not_configured' }, 503);
  const path = startPath(day, user.id);
  const prior = await (await rtdb(env, path)).json();
  if (typeof prior === 'number') return json({ ok: true, start: prior });
  const start = Date.now();
  await rtdb(env, path, { method: 'PUT', body: start });
  return json({ ok: true, start });
}

async function handleScore(req, env) {
  const user = await discordUser(req);
  if (!user) return json({ error: 'unauthorized' }, 401);
  const { day, ms } = await readJson(req);
  if (!validDay(day)) return json({ error: 'bad_day' }, 400);
  if (!Number.isInteger(ms) || ms < MIN_MS || ms > MAX_MS) return json({ error: 'bad_time' }, 400);
  if (!dbConfigured(env)) return json({ error: 'db_not_configured' }, 503);
  const start = await (await rtdb(env, startPath(day, user.id))).json();
  if (typeof start !== 'number') return json({ error: 'no_start' }, 409);
  if (ms > Date.now() - start + SLACK_MS) return json({ error: 'time_exceeds_window' }, 422);
  const result = await writeBest(env, `irodoku_daily/${day}/pocket/${user.id}`,
    { name: leaderboardName(user), ms, at: Date.now(), src: 'discord' });
  return json({ ok: true, ...result });
}

async function handleLeaderboard(url, env) {
  const day = url.searchParams.get('day') || pstDayKey();
  if (!DAY_RE.test(day)) return json({ error: 'bad_day' }, 400);
  if (!dbConfigured(env)) return json({ day, top: [] });
  try { return json({ day, top: await topPocket(env, day, 10) }); }
  catch { return json({ error: 'db_unavailable' }, 503); }
}

export async function nightly(env, { day = pstDayKey(Date.now() - 86400e3), rows, post = true } = {}) {
  rows ??= await topPocket(env, day, 10);
  const content = `Pocket Daily Iro results for ${day}`;
  const form = new FormData();
  let png = null;
  if ((env.NIGHTLY_FORMAT || 'embed') === 'png') {
    try { png = await renderPng(day, rows); } catch (e) { console.error('png failed, using embed', e); }
  }
  if (png) {
    if (!post) return { day, bytes: png.length, png };
    form.append('payload_json', JSON.stringify({ content }));
    form.append('files[0]', new Blob([png], { type: 'image/png' }), `pocket-${day}.png`);
  } else {
    const embed = leaderboardEmbed(day, rows);
    if (!post) return { day, embed };
    form.append('payload_json', JSON.stringify({ content, embeds: [embed] }));
  }
  if (!env.DISCORD_WEBHOOK_URL) throw new Error('DISCORD_WEBHOOK_URL not set');
  const r = await fetch(env.DISCORD_WEBHOOK_URL, { method: 'POST', body: form });
  if (!r.ok) throw new Error(`webhook ${r.status}`);
  return { day, posted: rows.length };
}

export default {
  async fetch(req, env) {
    const url = new URL(req.url);
    const route = `${req.method} ${url.pathname.replace(/\/+$/, '')}`;
    try {
      switch (route) {
        case 'POST /api/token': return await handleToken(req, env);
        case 'POST /api/start': return await handleStart(req, env);
        case 'POST /api/score': return await handleScore(req, env);
        case 'GET /api/leaderboard': return await handleLeaderboard(url, env);
        case 'GET /api/health': return json({ ok: true });
        case 'GET /api/nightly-preview': {
          env = { ...env, NIGHTLY_FORMAT: url.searchParams.get('format') || 'png' };
          // Dev-only dry run (no webhook post). Disabled unless DEV_PREVIEW=1.
          if (env.DEV_PREVIEW !== '1') return json({ error: 'not_found' }, 404);
          const sample = [{ name: 'iro_fan', ms: 52000 }, { name: 'Anthony', ms: 61000 }, { name: 'Player', ms: 70000 }];
          const out = await nightly(env, { day: url.searchParams.get('day') || '2026-10-30', rows: sample, post: false });
          return out.png ? new Response(out.png, { headers: { 'Content-Type': 'image/png' } }) : json(out);
        }
        default: return json({ error: 'not_found' }, 404);
      }
    } catch (e) {
      console.error(e); return json({ error: 'internal' }, 500);
    }
  },
  async scheduled(_event, env, ctx) {
    ctx.waitUntil(nightly(env));
  },
};
