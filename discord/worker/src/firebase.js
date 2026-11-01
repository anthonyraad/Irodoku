// Firebase RTDB over REST, authorized with a Google OAuth access token minted
// from the service account (RS256 JWT signed via WebCrypto). Chosen over the
// legacy "database secret", which Google has deprecated and can't be scoped.
let cached = null; // { token, exp }

const b64url = (buf) => btoa(String.fromCharCode(...new Uint8Array(buf)))
  .replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/, '');
const b64urlStr = (s) => b64url(new TextEncoder().encode(s));

function pemToDer(pem) {
  const b = atob(pem.replace(/-----[^-]+-----/g, '').replace(/\s+/g, ''));
  const out = new Uint8Array(b.length);
  for (let i = 0; i < b.length; i++) out[i] = b.charCodeAt(i);
  return out.buffer;
}

export function parseServiceAccount(raw) {
  if (!raw) return null;
  const json = raw.trim().startsWith('{') ? raw : atob(raw.trim());
  const sa = JSON.parse(json);
  if (!sa.client_email || !sa.private_key) throw new Error('bad service account');
  return sa;
}

async function accessToken(env) {
  const now = Math.floor(Date.now() / 1000);
  if (cached && cached.exp - 60 > now) return cached.token;
  const sa = parseServiceAccount(env.FIREBASE_SERVICE_ACCOUNT);
  if (!sa) throw new Error('FIREBASE_SERVICE_ACCOUNT not set');
  const header = b64urlStr(JSON.stringify({ alg: 'RS256', typ: 'JWT' }));
  const claims = b64urlStr(JSON.stringify({
    iss: sa.client_email,
    scope: 'https://www.googleapis.com/auth/firebase.database https://www.googleapis.com/auth/userinfo.email',
    aud: 'https://oauth2.googleapis.com/token',
    iat: now,
    exp: now + 3600,
  }));
  const key = await crypto.subtle.importKey('pkcs8', pemToDer(sa.private_key),
    { name: 'RSASSA-PKCS1-v1_5', hash: 'SHA-256' }, false, ['sign']);
  const sig = await crypto.subtle.sign('RSASSA-PKCS1-v1_5', key,
    new TextEncoder().encode(`${header}.${claims}`));
  const res = await fetch('https://oauth2.googleapis.com/token', {
    method: 'POST',
    headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
    body: new URLSearchParams({
      grant_type: 'urn:ietf:params:oauth:grant-type:jwt-bearer',
      assertion: `${header}.${claims}.${b64url(sig)}`,
    }),
  });
  const data = await res.json();
  if (!res.ok || !data.access_token) throw new Error('google token failed');
  cached = { token: data.access_token, exp: now + (data.expires_in || 3600) };
  return cached.token;
}

export function dbConfigured(env) {
  return Boolean(env.FIREBASE_DATABASE_URL && env.FIREBASE_SERVICE_ACCOUNT);
}

export async function rtdb(env, path, { method = 'GET', body, query = '', headers = {} } = {}) {
  const url = `${env.FIREBASE_DATABASE_URL.replace(/\/$/, '')}/${path}.json${query}`;
  const res = await fetch(url, {
    method,
    headers: { Authorization: `Bearer ${await accessToken(env)}`, 'Content-Type': 'application/json', ...headers },
    body: body === undefined ? undefined : JSON.stringify(body),
  });
  return res;
}

export async function topPocket(env, day, n = 10) {
  // Whole branch + local sort (as the app does); avoids needing .indexOn.
  const res = await rtdb(env, `irodoku_daily/${day}/pocket`);
  if (!res.ok) throw new Error(`rtdb ${res.status}`);
  const val = (await res.json()) || {};
  return Object.values(val)
    .filter((v) => v && Number.isFinite(Number(v.ms)))
    .map((v) => ({ name: String(v.name || 'Player'), ms: Number(v.ms) }))
    .sort((a, b) => a.ms - b.ms)
    .slice(0, n);
}

/** Keep-the-best write with ETag optimistic concurrency (REST "transaction"). */
export async function writeBest(env, path, entry) {
  for (let attempt = 0; attempt < 3; attempt++) {
    const cur = await rtdb(env, path, { headers: { 'X-Firebase-ETag': 'true' } });
    if (!cur.ok) throw new Error(`rtdb ${cur.status}`);
    const etag = cur.headers.get('ETag');
    const existing = await cur.json();
    if (existing && Number(existing.ms) <= entry.ms) return { committed: false, best: Number(existing.ms) };
    const put = await rtdb(env, path, { method: 'PUT', body: entry, headers: { 'if-match': etag } });
    if (put.ok) return { committed: true, best: entry.ms };
    if (put.status !== 412) throw new Error(`rtdb ${put.status}`);
  }
  throw new Error('rtdb contention');
}
