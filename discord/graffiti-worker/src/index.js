// [Graffiti] — Discord Activity API (Cloudflare Worker "irodoku-graffiti").
// Separate Discord app from Pocket Daily Iro. Routes (behind URL mapping
// '/api' -> this worker; Discord's proxy strips '/api', so both forms work):
//   GET  /api/config          { client_id }  (public app id for the SDK)
//   POST /api/token           Discord OAuth code -> access_token
//   POST /api/firebase-token  Bearer <discord token> -> Firebase custom token
//                             (uid discord_<id>, claim name) + sanitized name
//   POST /api/result          Bearer <discord token>, {code} -> webhook post/edit
//                             derived from rooms/<code> in RTDB (see result.js)
import { leaderboardName } from '../../worker/src/names.js';
import { mintCustomToken } from './custom_token.js';
import { handleResult } from './result.js';

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

export const firebaseUid = (discordId) => `discord_${discordId}`;

async function handleFirebaseToken(req, env) {
  if (!env.FIREBASE_SERVICE_ACCOUNT) return json({ error: 'server_not_configured' }, 503);
  const user = await discordUser(req);
  if (!user || !/^\d{5,25}$/.test(String(user.id))) return json({ error: 'unauthorized' }, 401);
  const name = leaderboardName(user);
  const uid = firebaseUid(user.id);
  const token = await mintCustomToken(env.FIREBASE_SERVICE_ACCOUNT, uid, { name, discord: true });
  return json({ token, uid, name });
}

async function handleResultRoute(req, env) {
  if (!env.FIREBASE_SERVICE_ACCOUNT || !env.FIREBASE_DATABASE_URL || !env.DISCORD_WEBHOOK_URL) {
    return json({ error: 'server_not_configured' }, 503);
  }
  const user = await discordUser(req);
  if (!user || !/^\d{5,25}$/.test(String(user.id))) return json({ error: 'unauthorized' }, 401);
  const { code } = await readJson(req);
  const r = await handleResult(code, firebaseUid(user.id), env);
  return json(r.body, r.status);
}

export function normalizePath(p) {
  p = p.replace(/\/+$/, '').replace(/^\/\.proxy(?=\/|$)/, '');
  if (!p.startsWith('/api/') && p !== '/api') p = '/api' + p;
  return p;
}

export default {
  async fetch(req, env) {
    const url = new URL(req.url);
    const route = `${req.method} ${normalizePath(url.pathname)}`;
    try {
      switch (route) {
        case 'GET /api/config': return json({ client_id: env.DISCORD_CLIENT_ID || null });
        case 'POST /api/token': return await handleToken(req, env);
        case 'POST /api/firebase-token': return await handleFirebaseToken(req, env);
        case 'POST /api/result': return await handleResultRoute(req, env);
        case 'GET /api/health': return json({ ok: true });
        default: return json({ error: 'not_found' }, 404);
      }
    } catch (e) {
      console.error(e); return json({ error: 'internal' }, 500);
    }
  },
};
