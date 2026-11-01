import { test, beforeEach } from 'node:test';
import assert from 'node:assert/strict';
import { generateKeyPairSync, createSign } from 'node:crypto';
import worker from '../src/index.js';
import { resetJwksCache, signState, verifyState, verifyIdToken } from '../src/link.js';
import { pstDayKey } from '../src/names.js';

const sa = generateKeyPairSync('rsa', { modulusLength: 2048 });
const fb = generateKeyPairSync('rsa', { modulusLength: 2048 });
const other = generateKeyPairSync('rsa', { modulusLength: 2048 });
const env = {
  FIREBASE_DATABASE_URL: 'https://db.test', DISCORD_CLIENT_ID: '1565967052047388822',
  DISCORD_CLIENT_SECRET: 'dummy-client-secret', LINK_STATE_SECRET: 'dummy-state-secret',
  FIREBASE_SERVICE_ACCOUNT: JSON.stringify({ client_email: 'a@b', private_key: sa.privateKey.export({ type: 'pkcs8', format: 'pem' }) }),
};
const b64 = (o) => Buffer.from(JSON.stringify(o)).toString('base64url');
const now = () => Math.floor(Date.now() / 1000);
function idToken(claims = {}, { key = fb.privateKey, kid = 'k1' } = {}) {
  const t = now();
  const body = `${b64({ alg: 'RS256', kid, typ: 'JWT' })}.${b64({
    aud: 'word-multiplayer', iss: 'https://securetoken.google.com/word-multiplayer',
    sub: 'anonUid1', iat: t - 10, exp: t + 3600, auth_time: t - 10, ...claims })}`;
  return `${body}.${createSign('RSA-SHA256').update(body).sign(key).toString('base64url')}`;
}

let db, calls, discordUser;
beforeEach(() => {
  resetJwksCache();
  db = {}; calls = []; discordUser = { id: '111222333444555666', global_name: 'Starscapes', username: 'stars' };
  const jwk = { ...fb.publicKey.export({ format: 'jwk' }), kid: 'k1', alg: 'RS256', use: 'sig' };
  globalThis.fetch = async (url, init = {}) => {
    url = String(url); const m = init.method || 'GET'; calls.push({ url, m, init });
    const res = (b, s = 200, h = {}) => new Response(JSON.stringify(b), { status: s, headers: h });
    if (url.includes('oauth2.googleapis')) return res({ access_token: 't', expires_in: 3600 });
    if (url.includes('jwk/securetoken')) return res({ keys: [jwk] }, 200, { 'Cache-Control': 'max-age=100' });
    if (url === 'https://discord.com/api/oauth2/token') {
      const p = new URLSearchParams(init.body);
      return p.get('code') === 'good' ? res({ access_token: 'dtok' }) : res({ error: 'invalid_grant' }, 400);
    }
    if (url === 'https://discord.com/api/users/@me') return res(discordUser);
    const path = url.replace('https://db.test/', '').replace(/\.json.*$/, '');
    const etag = JSON.stringify(db[path] ?? null);
    if (m === 'GET') return res(db[path] ?? null, 200, { ETag: etag });
    if (m === 'PUT') {
      const im = init.headers?.['if-match'];
      if (im !== undefined && im !== etag) return res({}, 412);
      db[path] = JSON.parse(init.body); return res(db[path]);
    }
    if (m === 'DELETE') { delete db[path]; return res(null); }
  };
});

const post = (path, token) => worker.fetch(new Request(`https://w${path}`, {
  method: 'POST', headers: token ? { Authorization: `Bearer ${token}` } : {},
}), env, {});
const callback = (qs) => worker.fetch(new Request(`https://w/link/callback?${qs}`), env, {});
const goodState = (uid = 'anonUid1', exp = now() + 600) => signState({ uid, nonce: 'n', exp }, env.LINK_STATE_SECRET);
const loc = (r) => new URL(r.headers.get('Location'));

test('verifyIdToken checks signature, aud, iss, exp', async () => {
  assert.equal(await verifyIdToken(idToken(), env), 'anonUid1');
  assert.equal(await verifyIdToken(idToken({ aud: 'other' }), env), null);
  assert.equal(await verifyIdToken(idToken({ iss: 'https://securetoken.google.com/other' }), env), null);
  assert.equal(await verifyIdToken(idToken({ exp: now() - 1 }), env), null);
  assert.equal(await verifyIdToken(idToken({}, { key: other.privateKey }), env), null);
  assert.equal(await verifyIdToken(idToken({}, { kid: 'nope' }), env), null);
  assert.equal(await verifyIdToken('garbage', env), null);
});

test('state sign/verify rejects tamper and expiry', async () => {
  const s = await goodState();
  assert.equal((await verifyState(s, env.LINK_STATE_SECRET)).uid, 'anonUid1');
  assert.equal(await verifyState(s, 'wrong'), null);
  const [, sig] = s.split('.');
  assert.equal(await verifyState(`${b64({ uid: 'evil', nonce: 'n', exp: now() + 600 })}.${sig}`, env.LINK_STATE_SECRET), null);
  assert.equal(await verifyState(await goodState('anonUid1', now() - 1), env.LINK_STATE_SECRET), null);
});

test('/link/start returns Discord authorize URL with signed state', async () => {
  assert.equal((await post('/link/start')).status, 401);
  assert.equal((await post('/link/start', idToken({ exp: now() - 5 }))).status, 401);
  const r = await post('/link/start', idToken());
  assert.equal(r.status, 200);
  const u = new URL((await r.json()).url);
  assert.equal(u.origin + u.pathname, 'https://discord.com/oauth2/authorize');
  assert.equal(u.searchParams.get('client_id'), '1565967052047388822');
  assert.equal(u.searchParams.get('response_type'), 'code');
  assert.equal(u.searchParams.get('scope'), 'identify');
  assert.equal(u.searchParams.get('redirect_uri'), 'https://irodoku-discord.raadscapes.workers.dev/link/callback');
  const st = await verifyState(u.searchParams.get('state'), env.LINK_STATE_SECRET);
  assert.equal(st.uid, 'anonUid1');
  assert.ok(st.exp > now() + 590 && st.exp <= now() + 600);
});

test('/link/callback links, merges today pocket (better time), redirects', async () => {
  const day = pstDayKey();
  db[`irodoku_daily/${day}/pocket/anonUid1`] = { name: 'Tony', ms: 60000, at: 1 };
  db[`irodoku_daily/${day}/pocket/111222333444555666`] = { name: 'old', ms: 90000, at: 2, src: 'discord' };
  db[`irodoku_daily/${day}/pocket/someoneElse`] = { name: 'X', ms: 1, at: 1 };
  const r = await callback(`code=good&state=${await goodState()}`);
  assert.equal(r.status, 302);
  assert.equal(r.headers.get('Location'), 'irodoku://discord-linked?name=Starscapes');
  assert.equal(db['irodoku_links/android/anonUid1'].discordId, '111222333444555666');
  assert.equal(db['irodoku_links/android/anonUid1'].name, 'Starscapes');
  assert.equal(typeof db['irodoku_links/android/anonUid1'].linkedAt, 'number');
  assert.deepEqual(db['irodoku_links/discord/111222333444555666'], { uid: 'anonUid1' });
  assert.equal(db[`irodoku_daily/${day}/pocket/anonUid1`], undefined);
  assert.deepEqual(db[`irodoku_daily/${day}/pocket/111222333444555666`], { name: 'Starscapes', ms: 60000, at: 1 });
  assert.ok(db[`irodoku_daily/${day}/pocket/someoneElse`]);
  const tokenCall = calls.find((c) => c.url === 'https://discord.com/api/oauth2/token');
  assert.equal(new URLSearchParams(tokenCall.init.body).get('redirect_uri'), 'https://irodoku-discord.raadscapes.workers.dev/link/callback');
});

test('merge keeps existing Discord time when it is better', async () => {
  const day = pstDayKey();
  db[`irodoku_daily/${day}/pocket/anonUid1`] = { name: 'Tony', ms: 60000, at: 1 };
  db[`irodoku_daily/${day}/pocket/111222333444555666`] = { name: 'old', ms: 50000, at: 2, src: 'discord' };
  await callback(`code=good&state=${await goodState()}`);
  assert.equal(db[`irodoku_daily/${day}/pocket/111222333444555666`].ms, 50000);
  assert.equal(db[`irodoku_daily/${day}/pocket/111222333444555666`].name, 'Starscapes');
  assert.equal(db[`irodoku_daily/${day}/pocket/anonUid1`], undefined);
});

test('no anon entry today: nothing merged; yesterday untouched', async () => {
  const y = pstDayKey(Date.now() - 86400e3);
  db[`irodoku_daily/${y}/pocket/anonUid1`] = { name: 'Tony', ms: 60000, at: 1 };
  const r = await callback(`code=good&state=${await goodState()}`);
  assert.match(r.headers.get('Location'), /name=Starscapes/);
  assert.ok(db[`irodoku_daily/${y}/pocket/anonUid1`]);
  assert.equal(db[`irodoku_daily/${pstDayKey()}/pocket/111222333444555666`], undefined);
});

test('relinking a Discord account to a new device replaces the old android link', async () => {
  db['irodoku_links/android/oldUid'] = { discordId: '111222333444555666', name: 'S', linkedAt: 1 };
  db['irodoku_links/discord/111222333444555666'] = { uid: 'oldUid' };
  await callback(`code=good&state=${await goodState()}`);
  assert.equal(db['irodoku_links/android/oldUid'], undefined);
  assert.deepEqual(db['irodoku_links/discord/111222333444555666'], { uid: 'anonUid1' });
});

test('switching this device to another Discord account drops the old reverse link', async () => {
  db['irodoku_links/android/anonUid1'] = { discordId: '999', name: 'raadscapes', linkedAt: 1 };
  db['irodoku_links/discord/999'] = { uid: 'anonUid1' };
  await callback(`code=good&state=${await goodState()}`);
  assert.equal(db['irodoku_links/discord/999'], undefined);
});

test('callback errors redirect with error code', async () => {
  const code = async (qs) => loc(await callback(qs)).searchParams.get('error');
  assert.equal(await code('code=good&state=bad'), 'bad_state');
  assert.equal(await code(`code=good&state=${await goodState('anonUid1', now() - 1)}`), 'bad_state');
  assert.equal(await code(`state=${await goodState()}`), 'missing_code');
  assert.equal(await code(`code=bad&state=${await goodState()}`), 'exchange_failed');
  assert.equal(await code('error=access_denied'), 'denied');
  assert.equal(loc(await callback('state=x')).protocol, 'irodoku:');
  assert.equal(Object.keys(db).length, 0);
});

test('name falls back to username and is URL-encoded', async () => {
  discordUser = { id: '777777777777', global_name: null, username: 'raad scap' };
  const r = await callback(`code=good&state=${await goodState()}`);
  assert.equal(r.headers.get('Location'), 'irodoku://discord-linked?name=raad+scap');
});

test('/link/disconnect removes both records', async () => {
  db['irodoku_links/android/anonUid1'] = { discordId: '555555', name: 'S', linkedAt: 1 };
  db['irodoku_links/discord/555555'] = { uid: 'anonUid1' };
  assert.equal((await post('/link/disconnect')).status, 401);
  const r = await post('/link/disconnect', idToken());
  assert.deepEqual(await r.json(), { ok: true });
  assert.equal(db['irodoku_links/android/anonUid1'], undefined);
  assert.equal(db['irodoku_links/discord/555555'], undefined);
});
