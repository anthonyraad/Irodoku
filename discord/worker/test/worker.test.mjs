import { test } from 'node:test';
import assert from 'node:assert/strict';
import { generateKeyPairSync } from 'node:crypto';
import worker, { fmtTime } from '../src/index.js';
import { pstDayKey } from '../src/names.js';

const { privateKey } = generateKeyPairSync('rsa', { modulusLength: 2048 });
const env = {
  FIREBASE_DATABASE_URL: 'https://db.test', DISCORD_WEBHOOK_URL: 'https://hook.test/x',
  ACTIVITY_LINK: 'https://discord.com/activities/1',
  FIREBASE_SERVICE_ACCOUNT: JSON.stringify({ client_email: 'a@b', private_key: privateKey.export({ type: 'pkcs8', format: 'pem' }) }),
};

function mock() {
  const db = {}; const hooks = [];
  globalThis.fetch = async (url, init = {}) => {
    url = String(url); const m = init.method || 'GET';
    const res = (b, s = 200, h = {}) => new Response(JSON.stringify(b), { status: s, headers: h });
    if (url.includes('oauth2.googleapis')) return res({ access_token: 't', expires_in: 3600 });
    if (url.includes('users/@me')) return res({ id: '42', global_name: 'Tony' });
    if (url.startsWith('https://hook.test')) { hooks.push(JSON.parse(init.body)); return res({}, 204 === 0 ? 204 : 200); }
    const path = url.replace('https://db.test/', '').replace(/\.json.*$/, '');
    const etag = JSON.stringify(db[path] ?? null);
    if (m === 'GET') return res(db[path] ?? null, 200, { ETag: etag });
    if (m === 'PUT') {
      const im = init.headers?.['if-match'];
      if (im !== undefined && im !== etag) return res({}, 412);
      db[path] = JSON.parse(init.body); return res(db[path]);
    }
  };
  return { db, hooks };
}

async function score(ms) {
  const waits = [];
  const r = await worker.fetch(new Request('https://w/api/score', {
    method: 'POST', headers: { Authorization: 'Bearer abcdefghijkl' },
    body: JSON.stringify({ day: pstDayKey(), ms }),
  }), env, { waitUntil: (p) => waits.push(p) });
  await Promise.all(waits);
  return r.json();
}

test('fmtTime', () => {
  assert.equal(fmtTime(134000), '2:14');
  assert.equal(fmtTime(3725000), '1:02:05');
});

test('shoutout posts once on first completion only', async () => {
  const { db, hooks } = mock();
  db[`irodoku_daily_starts/${pstDayKey()}/pocket/42`] = Date.now() - 600e3;
  assert.equal((await score(200000)).committed, true);
  assert.equal(hooks.length, 1);
  assert.equal(hooks[0].content, "**Tony** finished today's Daily Iro in 3:20 — [Play Daily Iro](https://discord.com/activities/1)");
  assert.deepEqual(hooks[0].allowed_mentions, { parse: [] });
  assert.equal((await score(134000)).committed, true); // improvement
  await score(134000); // duplicate
  assert.equal(hooks.length, 1);
  assert.ok(db[`irodoku_daily_posts/${pstDayKey()}/42`]);
});

test('scheduled dispatches by cron', async () => {
  const { hooks } = mock();
  const run = async (cron) => { const w = []; await worker.scheduled({ cron }, env, { waitUntil: (p) => w.push(p) }); await Promise.all(w); };
  await run('0 16 * * *');
  assert.match(hooks[0].content, /^Daily Iro is now live! — \[Play Daily Iro\]\(https:\/\/discord.com\/activities\/1\)$/);
  assert.deepEqual(hooks[0].allowed_mentions, { parse: [] });
  globalThis.fetch = async (url, init) => { hooks.push({ nightly: String(url) }); return new Response('null'); };
  await run('0 8 * * *');
  assert.ok(hooks.some((h) => h.nightly === 'https://hook.test/x'));
});

test('zero/missing client time falls back to server elapsed', async () => {
  const { db } = mock();
  db[`irodoku_daily_starts/${pstDayKey()}/pocket/42`] = Date.now() - 90e3;
  const r = await score(0);
  assert.equal(r.ok, true);
  assert.ok(r.ms >= 90e3 && r.ms < 95e3, `ms=${r.ms}`);
  assert.equal(db[`irodoku_daily/${pstDayKey()}/pocket/42`].ms, r.ms);
  const r2 = await score(undefined);
  assert.equal(r2.ok, true);
});

test('client time beyond server window (slow auth) is saved and shown', async () => {
  const { db } = mock();
  db[`irodoku_daily_starts/${pstDayKey()}/pocket/42`] = Date.now() - 10e3;
  const r = await score(60e3);
  assert.equal(r.ok, true);
  assert.equal(db[`irodoku_daily/${pstDayKey()}/pocket/42`].src, 'discord');
});

test('missing start still saves the client time', async () => {
  const { db } = mock();
  const r = await score(70e3);
  assert.equal(r.ok, true);
  assert.equal(db[`irodoku_daily/${pstDayKey()}/pocket/42`].ms, 70e3);
  assert.equal((await score(1000)).error, 'bad_time');
});

test('start reports done when a score exists for today', async () => {
  const { db } = mock();
  const day = pstDayKey();
  db[`irodoku_daily/${day}/pocket/42`] = { name: 'Tony', ms: 131000 };
  const r = await (await worker.fetch(new Request('https://w/api/start', {
    method: 'POST', headers: { Authorization: 'Bearer abcdefghijkl' },
    body: JSON.stringify({ day }),
  }), env, {})).json();
  assert.deepEqual(r, { ok: true, done: true, ms: 131000 });
  assert.equal(db[`irodoku_daily_starts/${day}/pocket/42`], undefined);
});

test('routes accept proxy-stripped and /api path forms', async () => {
  mock();
  for (const p of ['/leaderboard', '/api/leaderboard', '/.proxy/api/leaderboard', '/health', '/api/health/']) {
    const r = await worker.fetch(new Request('https://w' + p + (p.includes('leader') ? '?day=2026-10-31' : '')), env, {});
    assert.equal(r.status, 200, p);
  }
});

// ---- Part B: interactions + single daily message ----
import { generateKeyPairSync as gkp, sign as edSign } from 'node:crypto';
import { dailyMessagePayload, dailyDescription, ANDROID_LINK, upsertDailyMessage, verifyDiscordRequest } from '../src/discord_bot.js';

const ed = gkp('ed25519');
const pubHex = ed.publicKey.export({ type: 'spki', format: 'der' }).subarray(-32).toString('hex');
const signed = (body, path = '/interactions') => {
  const ts = String(Math.floor(Date.now() / 1000));
  const sig = edSign(null, Buffer.from(ts + body), ed.privateKey).toString('hex');
  return new Request('https://w' + path, { method: 'POST', body,
    headers: { 'X-Signature-Ed25519': sig, 'X-Signature-Timestamp': ts } });
};

function botMock() {
  const m = mock(); const discord = [];
  const base = globalThis.fetch;
  let n = 0;
  globalThis.fetch = async (url, init = {}) => {
    url = String(url);
    if (url.startsWith('https://discord.com/api/v10/channels/')) {
      discord.push({ url, method: init.method, auth: init.headers?.Authorization, body: typeof init.body === 'string' ? JSON.parse(init.body) : init.body });
      return new Response(JSON.stringify({ id: 'm' + (++n) }), { status: 200 });
    }
    if (url.startsWith('https://db.test/') && init.method === 'DELETE') {
      delete m.db[url.replace('https://db.test/', '').replace(/\.json.*$/, '')]; return new Response('null');
    }
    if (url.includes('users/@me')) return new Response(JSON.stringify({ id: '42', global_name: 'Tony' }));
    const key = url.replace('https://db.test/', '').replace(/\.json.*$/, '');
    if (url.startsWith('https://db.test/') && (init.method || 'GET') === 'GET' && !(key in m.db)) {
      const kids = Object.fromEntries(Object.entries(m.db).filter(([k]) => k.startsWith(key + '/')).map(([k, v]) => [k.slice(key.length + 1), v]));
      if (Object.keys(kids).length) return new Response(JSON.stringify(kids));
    }
    return base(url, init);
  };
  return { ...m, discord };
}
const benv = { ...env, DISCORD_PUBLIC_KEY: pubHex, DISCORD_BOT_TOKEN: 'bt', DISCORD_CHANNEL_ID: '99' };

test('ed25519 verify', async () => {
  const req = signed('{"type":1}');
  assert.equal(await verifyDiscordRequest(pubHex, req.headers.get('X-Signature-Ed25519'), req.headers.get('X-Signature-Timestamp'), '{"type":1}'), true);
  assert.equal(await verifyDiscordRequest(pubHex, req.headers.get('X-Signature-Ed25519'), req.headers.get('X-Signature-Timestamp'), '{"type":2}'), false);
});

test('interactions: ping, entry point, play button, bad sig', async () => {
  botMock();
  const call = async (b, p) => { const w = []; const r = await worker.fetch(signed(JSON.stringify(b), p), benv, { waitUntil: (x) => w.push(x) }); await Promise.all(w); return r; };
  assert.deepEqual(await (await call({ type: 1 })).json(), { type: 1 });
  assert.deepEqual(await (await call({ type: 1 }, '/api/interactions')).json(), { type: 1 });
  assert.deepEqual(await (await call({ type: 2, data: { type: 4 } })).json(), { type: 12 });
  assert.deepEqual(await (await call({ type: 3, data: { custom_id: 'iro_play' } })).json(), { type: 12 });
  const bad = signed('{"type":1}'); 
  const r = await worker.fetch(new Request(bad.url, { method: 'POST', body: '{"type":2}', headers: bad.headers }), benv, {});
  assert.equal(r.status, 401);
});

test('daily message: created once, edited on finishes, no webhook shoutouts', async () => {
  const { db, hooks, discord } = botMock();
  const day = pstDayKey();
  const r1 = await upsertDailyMessage(benv, day);
  assert.equal(r1.created, 'm1');
  assert.equal(db[`irodoku_daily_msg/${day}`].id, 'm1');
  assert.equal(discord[0].method, 'POST'); assert.equal(discord[0].auth, 'Bot bt');
  assert.match(discord[0].body.embeds[0].description, /^Today's Iro is live!\n\n\[Download Irodoku on Android ↗\]\(https:\/\/play\.google\.com\/store\/apps\/details\?id=com\.irodoku\.irodoku\)$/);
  db[`irodoku_daily_starts/${day}/pocket/42`] = Date.now() - 600e3;
  const w = [];
  await worker.fetch(new Request('https://w/score', { method: 'POST', headers: { Authorization: 'Bearer abcdefghijkl' },
    body: JSON.stringify({ day, ms: 134000 }) }), benv, { waitUntil: (p) => w.push(p) });
  await Promise.all(w);
  const last = discord.at(-1);
  assert.equal(last.method, 'PATCH'); assert.match(last.url, /messages\/m1$/);
  assert.match(last.body.embeds[0].description, /1 player solved today[\s\S]*\*\*Tony\*\* — 2:14/);
  assert.ok(last.body.embeds[0].description.endsWith(`\n\n${ANDROID_LINK}`));
  assert.deepEqual(last.body.allowed_mentions, { parse: [] });
  assert.equal(last.body.components[0].components[0].custom_id, 'iro_play');
  assert.equal(last.body.components[0].components[0].label, 'Play now!');
  assert.equal(discord[0].body.components[0].components[0].label, 'Play now!');
  assert.equal(hooks.length, 0);
  assert.equal(discord.filter((d) => d.method === 'POST').length, 1);
});

test('daily payload title', () => {
  assert.equal(dailyMessagePayload('2026-10-31', []).embeds[0].title, 'Daily Iro — 10.31.26');
});

test('daily description: link survives 4096 limit, leaderboard truncated', () => {
  const rows = Array.from({ length: 40 }, (_, i) => ({ name: 'N'.repeat(200) + i, ms: 1000 * i }));
  const d = dailyMessagePayload('2026-10-31', rows).embeds[0].description;
  assert.ok(d.length <= 4096); assert.ok(d.endsWith(`\n\n${ANDROID_LINK}`));
  const big = dailyDescription('x'.repeat(5000));
  assert.ok(big.length <= 4096); assert.ok(big.endsWith(`\n\n${ANDROID_LINK}`));
});
