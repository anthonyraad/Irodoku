import { test } from 'node:test';
import assert from 'node:assert/strict';
import { generateKeyPairSync, createVerify } from 'node:crypto';
import worker, { normalizePath, firebaseUid } from '../src/index.js';

const { privateKey, publicKey } = generateKeyPairSync('rsa', { modulusLength: 2048 });
const SA = JSON.stringify({ client_email: 'sa@proj.iam.gserviceaccount.com', private_key: privateKey.export({ type: 'pkcs8', format: 'pem' }) });
const env = { DISCORD_CLIENT_ID: '123', DISCORD_CLIENT_SECRET: 's', FIREBASE_SERVICE_ACCOUNT: SA };

let me = { id: '987654321098', global_name: 'Tøny 🎨 Raad!!', username: 'tony' };
globalThis.fetch = async (url, init = {}) => {
  url = String(url);
  const res = (b, s = 200) => new Response(JSON.stringify(b), { status: s });
  if (url.endsWith('/users/@me')) return init.headers.Authorization === 'Bearer good-token-123' ? res(me) : res({}, 401);
  if (url.endsWith('/oauth2/token')) {
    const p = new URLSearchParams(init.body);
    return p.get('code') === 'ok' && p.get('client_secret') === 's' ? res({ access_token: 'AT' }) : res({}, 400);
  }
  throw new Error('unexpected fetch ' + url);
};

const call = (path, { method = 'GET', body, auth } = {}, e = env) => worker.fetch(new Request('https://w' + path, {
  method, headers: auth ? { Authorization: 'Bearer ' + auth } : {}, body: body && JSON.stringify(body),
}), e);

const b64 = (s) => JSON.parse(Buffer.from(s, 'base64url').toString());

test('normalizePath accepts stripped and /.proxy forms', () => {
  assert.equal(normalizePath('/token'), '/api/token');
  assert.equal(normalizePath('/api/firebase-token/'), '/api/firebase-token');
  assert.equal(normalizePath('/.proxy/api/config'), '/api/config');
});

test('config exposes client id', async () => {
  assert.deepEqual(await (await call('/config')).json(), { client_id: '123' });
});

test('token exchange', async () => {
  assert.deepEqual(await (await call('/token', { method: 'POST', body: { code: 'ok' } })).json(), { access_token: 'AT' });
  assert.equal((await call('/token', { method: 'POST', body: { code: 'bad' } })).status, 401);
  assert.equal((await call('/token', { method: 'POST', body: {} })).status, 400);
  assert.equal((await call('/token', { method: 'POST', body: { code: 'ok' } }, {})).status, 503);
});

test('firebase-token mints a verifiable custom token', async () => {
  const r = await call('/firebase-token', { method: 'POST', auth: 'good-token-123' });
  assert.equal(r.status, 200);
  const { token, uid, name } = await r.json();
  assert.equal(uid, 'discord_987654321098');
  assert.equal(name, 'Tny  Raad'.replace(/\s+/g, ' ').slice(0, 10).trim());
  const [h, p, s] = token.split('.');
  assert.deepEqual(b64(h), { alg: 'RS256', typ: 'JWT' });
  const claims = b64(p);
  assert.equal(claims.uid, uid);
  assert.equal(claims.iss, 'sa@proj.iam.gserviceaccount.com');
  assert.equal(claims.sub, claims.iss);
  assert.equal(claims.aud, 'https://identitytoolkit.googleapis.com/google.identity.identitytoolkit.v1.IdentityToolkit');
  assert.equal(claims.exp - claims.iat, 3600);
  assert.deepEqual(claims.claims, { name, discord: true });
  const v = createVerify('RSA-SHA256'); v.update(`${h}.${p}`);
  assert.ok(v.verify(publicKey, Buffer.from(s, 'base64url')));
});

test('firebase-token name falls back to Player', async () => {
  me = { id: '111111111111', global_name: '🎨🎨', username: 'x' };
  const { name } = await (await call('/firebase-token', { method: 'POST', auth: 'good-token-123' })).json();
  assert.equal(name, 'Player');
});

test('firebase-token rejects bad auth / unconfigured', async () => {
  assert.equal((await call('/firebase-token', { method: 'POST', auth: 'nope-nope-nope' })).status, 401);
  assert.equal((await call('/firebase-token', { method: 'POST' })).status, 401);
  assert.equal((await call('/firebase-token', { method: 'POST', auth: 'good-token-123' }, {})).status, 503);
  assert.equal(firebaseUid('5'), 'discord_5');
});
