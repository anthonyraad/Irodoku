// Discord Embedded App SDK bridge for Pocket Daily Iro.
// Loaded from index.html AFTER discord-sdk.js (local bundle; no CDN — CSP).
(function () {
  const CLIENT_ID = '1565967052047388822';
  let accessToken = null;
  let user = null;

  async function api(path, body) {
    const res = await fetch(path, {
      method: body === undefined ? 'GET' : 'POST',
      headers: Object.assign(
        { 'Content-Type': 'application/json' },
        accessToken ? { Authorization: 'Bearer ' + accessToken } : {}
      ),
      body: body === undefined ? undefined : JSON.stringify(body),
    });
    if (!res.ok) throw new Error(path + ' ' + res.status);
    return res.json();
  }

  const TOKEN_KEY = 'iro_discord_token_v1';
  // Fixed, minimal scope list: changing it makes Discord re-show the consent modal.
  const SCOPES = Object.freeze(['identify']);

  function safeStorage() {
    try { const s = window.localStorage; s.setItem('__iro_t', '1'); s.removeItem('__iro_t'); return s; }
    catch (_) { try { return window.sessionStorage; } catch (_) { return null; } }
  }

  // Try a cached access token first (authenticate() never shows UI); only fall
  // back to authorize() (prompt:'none') + /api/token exchange when it fails.
  async function authFlow(sdk, exchange, storage) {
    let cached = null;
    try { cached = storage && JSON.parse(storage.getItem(TOKEN_KEY) || 'null'); } catch (_) {}
    if (cached && cached.access_token && (!cached.exp || cached.exp > Date.now())) {
      try {
        const a = await sdk.commands.authenticate({ access_token: cached.access_token });
        if (a && a.user) return { access_token: cached.access_token, user: a.user };
      } catch (_) { /* expired/revoked: fall through */ }
    }
    try { storage && storage.removeItem(TOKEN_KEY); } catch (_) {}
    const { code } = await sdk.commands.authorize({
      client_id: CLIENT_ID, response_type: 'code', state: '', prompt: 'none', scope: SCOPES.slice(),
    });
    const tok = await exchange(code);
    const a = await sdk.commands.authenticate({ access_token: tok.access_token });
    if (a && a.user) {
      const exp = a.expires ? Date.parse(a.expires) : Date.now() + 6 * 864e5;
      try { storage && storage.setItem(TOKEN_KEY, JSON.stringify({ access_token: tok.access_token, exp: isNaN(exp) ? 0 : exp })); } catch (_) {}
    }
    return { access_token: tok.access_token, user: a && a.user };
  }

  async function init() {
    const Sdk = window.DiscordSDKBundle;
    const params = new URLSearchParams(location.search);
    if (!Sdk || !params.get('frame_id')) return null; // not inside Discord
    const sdk = new Sdk.DiscordSDK(CLIENT_ID);
    window.__iroDiscordSdk = sdk;
    await sdk.ready();
    const auth = await authFlow(sdk, (code) => api('/api/token', { code }), safeStorage());
    accessToken = auth.access_token;
    user = auth.user;
    if (!user) return null;
    return user.global_name || user.username;
  }

  window.__iroAuthFlow = authFlow; // exposed for tests
  window.IroDiscord = {
    init: () => init().catch((e) => { console.warn('[IroDiscord]', e); return null; }),
    startRun: (dayKey) => accessToken ? api('/api/start', { day: dayKey }).then((r) => (r ? JSON.stringify(r) : null)).catch(() => null) : Promise.resolve(null),
    submitScore: (dayKey, ms) => accessToken
      ? api('/api/score', { day: dayKey, ms }).then((r) => !!r.ok).catch(() => false)
      : Promise.resolve(false),
    leaderboard: (dayKey) => api('/api/leaderboard?day=' + encodeURIComponent(dayKey))
      .then((r) => JSON.stringify(r)).catch((e) => { console.warn('[IroDiscord] leaderboard', e); return null; }),
  };
})();
