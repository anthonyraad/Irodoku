// Pocket Daily Iro — Discord Activity API (Cloudflare Worker).
// Routes (behind Discord URL mapping '/api' -> this worker):
//   POST /api/token  POST /api/start  POST /api/score  GET /api/leaderboard
// Cron '0 8 * * *': post yesterday's Pocket top-10 to DISCORD_WEBHOOK_URL.
// Cron '0 16 * * *' (8 AM PST): 'Daily Iro is now live' post.
import { dbConfigured, rtdb, topPocket, writeBest } from './firebase.js';
import { leaderboardName, pstDayKey } from './names.js';
import { leaderboardEmbed, renderPng } from './render.js';
import { botApi, botEnabled, upsertDailyMessage, verifyDiscordRequest } from './discord_bot.js';

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

function bg(ctx, p, label) {
  p = Promise.resolve(p).catch((e) => console.error(label, e));
  if (ctx?.waitUntil) ctx.waitUntil(p);
  return p;
}

async function handleStart(req, env, ctx) {
  const user = await discordUser(req);
  if (!user) return json({ error: 'unauthorized' }, 401);
  const { day } = await readJson(req);
  if (day === pstDayKey() && dbConfigured(env)) bg(ctx, upsertDailyMessage(env, day), 'daily msg');
  if (!validDay(day)) return json({ error: 'bad_day' }, 400);
  if (!dbConfigured(env)) return json({ error: 'db_not_configured' }, 503);
  // Already finished today: no new run, the client shows the leaderboard.
  const done = await (await rtdb(env, `irodoku_daily/${day}/pocket/${user.id}`)).json();
  if (done && typeof done.ms === 'number') return json({ ok: true, done: true, ms: done.ms });
  const path = startPath(day, user.id);
  const prior = await (await rtdb(env, path)).json();
  if (typeof prior === 'number') return json({ ok: true, start: prior });
  const start = Date.now();
  await rtdb(env, path, { method: 'PUT', body: start });
  return json({ ok: true, start });
}

const DEFAULT_ACTIVITY_LINK = 'https://discord.com/activities/1565967052047388822';
const activityLink = (env) => env.ACTIVITY_LINK || DEFAULT_ACTIVITY_LINK;

export function fmtTime(ms) {
  const t = Math.floor(ms / 1000), h = Math.floor(t / 3600), m = Math.floor((t % 3600) / 60), s = t % 60;
  const ss = String(s).padStart(2, '0');
  return h ? `${h}:${String(m).padStart(2, '0')}:${ss}` : `${m}:${ss}`;
}

async function postWebhook(env, payload) {
  if (!env.DISCORD_WEBHOOK_URL) throw new Error('DISCORD_WEBHOOK_URL not set');
  const r = await fetch(env.DISCORD_WEBHOOK_URL, {
    method: 'POST', headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ allowed_mentions: { parse: [] }, ...payload }),
  });
  if (!r.ok) throw new Error(`webhook ${r.status}`);
}

/** Post a no-spoiler finish shoutout once per player per day (Firebase-guarded). */
export async function finishShoutout(env, day, uid, name, ms) {
  const path = `irodoku_daily_posts/${day}/${uid}`;
  const cur = await rtdb(env, path, { headers: { 'X-Firebase-ETag': 'true' } });
  if (!cur.ok) throw new Error(`rtdb ${cur.status}`);
  if ((await cur.json()) != null) return { posted: false };
  // Claim atomically: fails with 412 if another request claimed first.
  const claim = await rtdb(env, path, { method: 'PUT', body: Date.now(), headers: { 'if-match': cur.headers.get('ETag') } });
  if (!claim.ok) return { posted: false };
  await postWebhook(env, {
    content: `**${name}** finished today's Daily Iro in ${fmtTime(ms)} — [Play Daily Iro](${activityLink(env)})`,
  });
  return { posted: true };
}

export async function livePost(env) {
  await postWebhook(env, {
    content: `Daily Iro is now live! — [Play Daily Iro](${activityLink(env)})`,
    embeds: [{
      title: `Daily Iro — ${pstDayKey()}`, url: activityLink(env), color: 0x7c5cff,
      description: "Today's puzzle is ready. Finish it to get on the Pocket leaderboard!",
    }],
  });
  return { posted: true };
}

async function handleScore(req, env, ctx) {
  const user = await discordUser(req);
  if (!user) return json({ error: 'unauthorized' }, 401);
  const body = await readJson(req);
  const { day } = body;
  let { ms } = body;
  if (!validDay(day)) return json({ error: 'bad_day' }, 400);
  if (ms != null && (!Number.isInteger(ms) || ms < 0 || ms > MAX_MS)) return json({ error: 'bad_time' }, 400);
  if (!dbConfigured(env)) return json({ error: 'db_not_configured' }, 503);
  const start = await (await rtdb(env, startPath(day, user.id))).json();
  if (typeof start !== 'number') return json({ error: 'no_start' }, 409);
  const serverMs = Date.now() - start;
  if (ms != null && ms > serverMs + SLACK_MS) return json({ error: 'time_exceeds_window' }, 422);
  // A missing/implausibly small client time means the on-screen clock never
  // ran; fall back to the server-recorded window (start -> now).
  if (ms == null || ms < MIN_MS) ms = serverMs;
  if (ms < MIN_MS || ms > MAX_MS) return json({ error: 'bad_time' }, 400);
  const result = await writeBest(env, `irodoku_daily/${day}/pocket/${user.id}`,
    { name: leaderboardName(user), ms, at: Date.now(), src: 'discord' });
  // First completion of the day always commits; the Firebase flag dedupes.
  if (day === pstDayKey() && botEnabled(env)) {
    // Bot mode: the single daily message replaces per-finish shoutouts.
    if (result.committed) bg(ctx, upsertDailyMessage(env, day), 'daily msg');
  } else if (result.committed && day === pstDayKey()) {
    const p = finishShoutout(env, day, user.id, leaderboardName(user), ms).catch((e) => console.error('shoutout', e));
    if (ctx?.waitUntil) ctx.waitUntil(p);
  }
  return json({ ok: true, ms, ...result });
}

async function handleInteractions(req, env, ctx) {
  const body = await req.text();
  const ok = await verifyDiscordRequest(env.DISCORD_PUBLIC_KEY, req.headers.get('X-Signature-Ed25519'),
    req.headers.get('X-Signature-Timestamp'), body);
  if (!ok) return new Response('invalid request signature', { status: 401 });
  let i; try { i = JSON.parse(body); } catch { return json({ error: 'bad_json' }, 400); }
  if (i.type === 1) return json({ type: 1 });
  const launch = (i.type === 2 && i.data?.type === 4) || (i.type === 3 && i.data?.custom_id === 'iro_play');
  if (launch) {
    if (dbConfigured(env)) bg(ctx, upsertDailyMessage(env, pstDayKey()), 'daily msg');
    return json({ type: 12 });
  }
  return json({ type: 4, data: { content: 'Unknown command.', flags: 64 } });
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
  let r;
  if (botEnabled(env)) {
    r = await botApi(env, 'POST', `/channels/${env.DISCORD_CHANNEL_ID}/messages`, form);
  } else {
    if (!env.DISCORD_WEBHOOK_URL) throw new Error('DISCORD_WEBHOOK_URL not set');
    r = await fetch(env.DISCORD_WEBHOOK_URL, { method: 'POST', body: form });
  }
  if (!r.ok) throw new Error(`nightly post ${r.status}`);
  return { day, posted: rows.length };
}

// Discord's URL-mapping proxy strips the matched prefix: the client's
// /api/leaderboard (or /.proxy/api/leaderboard) arrives here as /leaderboard.
// Accept both forms so direct curl and proxied requests route the same.
export function normalizePath(p) {
  p = p.replace(/\/+$/, '').replace(/^\/\.proxy(?=\/|$)/, '');
  if (!p.startsWith('/api/') && p !== '/api') p = '/api' + p;
  return p;
}

export default {
  async fetch(req, env, ctx) {
    const url = new URL(req.url);
    const route = `${req.method} ${normalizePath(url.pathname)}`;
    try {
      switch (route) {
        case 'POST /api/token': return await handleToken(req, env);
        case 'POST /api/start': return await handleStart(req, env, ctx);
        case 'POST /api/score': return await handleScore(req, env, ctx);
        case 'GET /api/leaderboard': return await handleLeaderboard(url, env);
        case 'POST /api/interactions': return await handleInteractions(req, env, ctx);
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
  async scheduled(event, env, ctx) {
    const job = event?.cron === '0 16 * * *'
      ? (botEnabled(env) ? upsertDailyMessage(env, pstDayKey()) : livePost(env))
      : nightly(env);
    ctx.waitUntil(job);
  },
};
