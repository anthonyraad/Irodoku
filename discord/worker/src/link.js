// Android "Sync Discord": link a Firebase (anonymous) app uid to a Discord
// account via standard OAuth2 (identify). The Worker owns irodoku_links/*
// (clients can only read their own android record).
//   POST /link/start       (Firebase ID token) -> { url } Discord authorize URL
//   GET  /link/callback    Discord redirect -> 302 irodoku://discord-linked?...
//   POST /link/disconnect  (Firebase ID token) -> removes both link records
// Discord players' Pocket leaderboard key is the raw Discord user id (same key
// the Activity's /api/score writes), see discordKey().
import { rtdb } from './firebase.js';
import { leaderboardName, pstDayKey } from './names.js';

export const LINK_CALLBACK = 'https://irodoku-discord.raadscapes.workers.dev/link/callback';
export const DEFAULT_CLIENT_ID = '1565967052047388822';
const DEFAULT_PROJECT = 'word-multiplayer';
const JWKS_URL = 'https://www.googleapis.com/service_accounts/v1/jwk/securetoken@system.gserviceaccount.com';
const STATE_TTL_S = 600;
const enc = new TextEncoder();

/** Pocket leaderboard key for a Discord player (matches the Activity). */
export const discordKey = (discordId) => String(discordId);

const json = (body, status = 200) => new Response(JSON.stringify(body), {
  status, headers: { 'Content-Type': 'application/json', 'Cache-Control': 'no-store' },
});
const redirect = (loc) => new Response(null, { status: 302, headers: { Location: loc, 'Cache-Control': 'no-store' } });
const appUrl = (params) => `irodoku://discord-linked?${new URLSearchParams(params)}`;

const b64url = (bytes) => btoa(String.fromCharCode(...new Uint8Array(bytes)))
  .replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/, '');
function b64urlDecode(s) {
  const b = atob(s.replace(/-/g, '+').replace(/_/g, '/') + '==='.slice((s.length + 3) % 4));
  const out = new Uint8Array(b.length);
  for (let i = 0; i < b.length; i++) out[i] = b.charCodeAt(i);
  return out;
}
const decodeJson = (s) => JSON.parse(new TextDecoder().decode(b64urlDecode(s)));

// ---- Firebase ID token (securetoken) verification ----
let jwksCache = null; // { keys, exp }
async function jwks(force = false) {
  const now = Date.now();
  if (!force && jwksCache && jwksCache.exp > now) return jwksCache.keys;
  const r = await fetch(JWKS_URL);
  if (!r.ok) throw new Error(`jwks ${r.status}`);
  const { keys } = await r.json();
  const maxAge = Number(/max-age=(\d+)/.exec(r.headers.get('Cache-Control') || '')?.[1] || 3600);
  jwksCache = { keys: keys || [], exp: now + maxAge * 1000 };
  return jwksCache.keys;
}
export function resetJwksCache() { jwksCache = null; }

/** Returns the Firebase uid for a valid ID token, else null. */
export async function verifyIdToken(token, env, nowS = Math.floor(Date.now() / 1000)) {
  try {
    if (typeof token !== 'string') return null;
    const parts = token.split('.');
    if (parts.length !== 3) return null;
    const header = decodeJson(parts[0]);
    const p = decodeJson(parts[1]);
    if (header.alg !== 'RS256' || !header.kid) return null;
    const project = env.FIREBASE_PROJECT_ID || DEFAULT_PROJECT;
    if (p.aud !== project || p.iss !== `https://securetoken.google.com/${project}`) return null;
    if (typeof p.sub !== 'string' || !p.sub || p.sub.length > 128) return null;
    if (!(p.exp > nowS) || !(p.iat <= nowS + 300) || (p.auth_time != null && p.auth_time > nowS + 300)) return null;
    let jwk = (await jwks()).find((k) => k.kid === header.kid);
    if (!jwk) jwk = (await jwks(true)).find((k) => k.kid === header.kid);
    if (!jwk) return null;
    const key = await crypto.subtle.importKey('jwk', { kty: jwk.kty, n: jwk.n, e: jwk.e, alg: 'RS256', ext: true },
      { name: 'RSASSA-PKCS1-v1_5', hash: 'SHA-256' }, false, ['verify']);
    const ok = await crypto.subtle.verify('RSASSA-PKCS1-v1_5', key, b64urlDecode(parts[2]),
      enc.encode(`${parts[0]}.${parts[1]}`));
    return ok ? p.sub : null;
  } catch { return null; }
}

async function idTokenUid(req, env) {
  const auth = req.headers.get('Authorization') || '';
  let token = auth.startsWith('Bearer ') ? auth.slice(7).trim() : '';
  if (!token) { try { token = (await req.clone().json())?.idToken || ''; } catch { /* no body */ } }
  return verifyIdToken(token, env);
}

// ---- signed OAuth state ----
async function hmacKey(secret) {
  return crypto.subtle.importKey('raw', enc.encode(secret), { name: 'HMAC', hash: 'SHA-256' }, false, ['sign', 'verify']);
}
export async function signState(payload, secret) {
  const body = b64url(enc.encode(JSON.stringify(payload)));
  const sig = await crypto.subtle.sign('HMAC', await hmacKey(secret), enc.encode(body));
  return `${body}.${b64url(sig)}`;
}
export async function verifyState(state, secret, nowS = Math.floor(Date.now() / 1000)) {
  try {
    const [body, sig, extra] = String(state || '').split('.');
    if (!body || !sig || extra !== undefined) return null;
    const ok = await crypto.subtle.verify('HMAC', await hmacKey(secret), b64urlDecode(sig), enc.encode(body));
    if (!ok) return null;
    const p = decodeJson(body);
    if (typeof p.uid !== 'string' || !p.uid || !(p.exp > nowS)) return null;
    return p;
  } catch { return null; }
}

// ---- routes ----
export async function handleLinkStart(req, env) {
  if (!env.LINK_STATE_SECRET) return json({ error: 'server_not_configured' }, 503);
  const uid = await idTokenUid(req, env);
  if (!uid) return json({ error: 'unauthorized' }, 401);
  const nonce = b64url(crypto.getRandomValues(new Uint8Array(16)));
  const state = await signState({ uid, nonce, exp: Math.floor(Date.now() / 1000) + STATE_TTL_S }, env.LINK_STATE_SECRET);
  const q = new URLSearchParams({
    client_id: env.DISCORD_CLIENT_ID || DEFAULT_CLIENT_ID, response_type: 'code', scope: 'identify',
    redirect_uri: LINK_CALLBACK, state,
  });
  return json({ url: `https://discord.com/oauth2/authorize?${q}` });
}

async function dbOk(res) {
  if (!res.ok) throw Object.assign(new Error(`rtdb ${res.status}`), { code: 'db_error' });
  return res.json();
}

/** Move today's anon Pocket entry onto the Discord key, keeping the better time. */
export async function mergeTodayPocket(env, uid, discordId, name, day = pstDayKey()) {
  const from = `irodoku_daily/${day}/pocket/${uid}`;
  const anon = await dbOk(await rtdb(env, from));
  if (!anon || !Number.isFinite(Number(anon.ms))) return { merged: false };
  const to = `irodoku_daily/${day}/pocket/${discordKey(discordId)}`;
  for (let attempt = 0; attempt < 3; attempt++) {
    const cur = await rtdb(env, to, { headers: { 'X-Firebase-ETag': 'true' } });
    const existing = await dbOk(cur);
    const keepExisting = existing && Number.isFinite(Number(existing.ms)) && Number(existing.ms) <= Number(anon.ms);
    const best = keepExisting ? existing : anon;
    const entry = { ...best, name };
    const put = await rtdb(env, to, { method: 'PUT', body: entry, headers: { 'if-match': cur.headers.get('ETag') } });
    if (put.ok) {
      await dbOk(await rtdb(env, from, { method: 'DELETE' }));
      return { merged: true, ms: Number(entry.ms) };
    }
    if (put.status !== 412) throw Object.assign(new Error(`rtdb ${put.status}`), { code: 'db_error' });
  }
  throw Object.assign(new Error('rtdb contention'), { code: 'db_error' });
}

export async function handleLinkCallback(url, env) {
  const fail = (code) => redirect(appUrl({ error: code }));
  try {
    if (url.searchParams.get('error')) return fail('denied');
    if (!env.LINK_STATE_SECRET || !env.DISCORD_CLIENT_SECRET || !env.FIREBASE_SERVICE_ACCOUNT || !env.FIREBASE_DATABASE_URL) {
      return fail('server_not_configured');
    }
    const st = await verifyState(url.searchParams.get('state'), env.LINK_STATE_SECRET);
    if (!st) return fail('bad_state');
    const code = url.searchParams.get('code');
    if (!code) return fail('missing_code');
    const tr = await fetch('https://discord.com/api/oauth2/token', {
      method: 'POST',
      headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
      body: new URLSearchParams({
        client_id: env.DISCORD_CLIENT_ID || DEFAULT_CLIENT_ID, client_secret: env.DISCORD_CLIENT_SECRET,
        grant_type: 'authorization_code', code, redirect_uri: LINK_CALLBACK,
      }),
    });
    const tok = await tr.json().catch(() => ({}));
    if (!tr.ok || !tok.access_token) return fail('exchange_failed');
    const ur = await fetch('https://discord.com/api/users/@me', { headers: { Authorization: `Bearer ${tok.access_token}` } });
    const user = ur.ok ? await ur.json().catch(() => null) : null;
    if (!user?.id || !/^\d{5,25}$/.test(String(user.id))) return fail('user_failed');
    const discordId = String(user.id);
    // Leaderboard-safe version of global_name || username (app DisplayName rules).
    const name = leaderboardName(user);
    const { uid } = st;

    // Replace any previous links on either side.
    const prevDiscord = await dbOk(await rtdb(env, `irodoku_links/discord/${discordId}`));
    if (prevDiscord?.uid && prevDiscord.uid !== uid) {
      await dbOk(await rtdb(env, `irodoku_links/android/${prevDiscord.uid}`, { method: 'DELETE' }));
    }
    const prevAndroid = await dbOk(await rtdb(env, `irodoku_links/android/${uid}`));
    if (prevAndroid?.discordId && String(prevAndroid.discordId) !== discordId) {
      await dbOk(await rtdb(env, `irodoku_links/discord/${prevAndroid.discordId}`, { method: 'DELETE' }));
    }
    await dbOk(await rtdb(env, `irodoku_links/android/${uid}`, {
      method: 'PUT', body: { discordId, name, linkedAt: Date.now() },
    }));
    await dbOk(await rtdb(env, `irodoku_links/discord/${discordId}`, { method: 'PUT', body: { uid } }));
    try { await mergeTodayPocket(env, uid, discordId, name); } catch (e) { console.error('link merge', e); }
    return redirect(appUrl({ name }));
  } catch (e) {
    console.error('link callback', e);
    return fail(e?.code || 'internal');
  }
}

export async function handleLinkDisconnect(req, env) {
  const uid = await idTokenUid(req, env);
  if (!uid) return json({ error: 'unauthorized' }, 401);
  const cur = await dbOk(await rtdb(env, `irodoku_links/android/${uid}`));
  if (cur?.discordId) {
    const back = await dbOk(await rtdb(env, `irodoku_links/discord/${cur.discordId}`));
    if (!back || back.uid === uid) {
      await dbOk(await rtdb(env, `irodoku_links/discord/${cur.discordId}`, { method: 'DELETE' }));
    }
  }
  await dbOk(await rtdb(env, `irodoku_links/android/${uid}`, { method: 'DELETE' }));
  return json({ ok: true });
}
