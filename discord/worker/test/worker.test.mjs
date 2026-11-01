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

test('client time beyond server window is rejected', async () => {
  const { db } = mock();
  db[`irodoku_daily_starts/${pstDayKey()}/pocket/42`] = Date.now() - 10e3;
  assert.equal((await score(60e3)).error, 'time_exceeds_window');
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
