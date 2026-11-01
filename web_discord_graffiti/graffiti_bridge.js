// Discord Embedded App SDK bridge for the [Graffiti] Activity.
// Loaded from index.html AFTER discord-sdk.js (local bundle; no CDN — CSP).
//
// Inside Discord every request must go through the Activity's URL mappings,
// so before Firebase loads we rewrite:
//   *.firebaseio.com  -> /fb/<sub>    (RTDB websocket + long-poll)
//   *.googleapis.com  -> /gapi/<sub>  (identitytoolkit / securetoken auth)
// and record connection telemetry for the in-app debug overlay.
(function () {
  const params = new URLSearchParams(location.search);
  const inDiscord = !!(window.DiscordSDKBundle && params.get('frame_id'));
  const MAPPINGS = [
    { prefix: '/fb/{subdomain}', target: '{subdomain}.firebaseio.com' },
    { prefix: '/gapi/{subdomain}', target: '{subdomain}.googleapis.com' },
  ];

  // ---- network telemetry (read by the Dart overlay) ----
  const net = { ws: 'none', wsOpened: 0, wsErrors: 0, wsCloses: 0, lastClose: '', lastWsUrl: '', errors: [] };
  function note(e) { net.errors.push(String(e).slice(0, 160)); if (net.errors.length > 5) net.errors.shift(); }

  if (inDiscord) {
    try { window.DiscordSDKBundle.patchUrlMappings(MAPPINGS, { patchSrcAttributes: true }); }
    catch (e) { note('patchUrlMappings: ' + e); }
  }
  // Wrap (possibly already patched) WebSocket to observe Firebase sockets.
  const BaseWS = window.WebSocket;
  class ObservedWS extends BaseWS {
    constructor(url, protocols) {
      super(url, protocols);
      const u = String(this.url || url);
      if (!/firebaseio\.com|\/fb\//.test(u)) return;
      net.ws = 'connecting'; net.lastWsUrl = u.replace(/\?.*$/, '');
      this.addEventListener('open', () => { net.ws = 'open'; net.wsOpened++; });
      this.addEventListener('error', () => { net.ws = 'error'; net.wsErrors++; });
      this.addEventListener('close', (ev) => { net.ws = 'closed'; net.wsCloses++; net.lastClose = ev.code + (ev.reason ? ' ' + ev.reason : ''); });
    }
  }
  window.WebSocket = ObservedWS;

  function longPollCount() {
    try {
      return performance.getEntriesByType('resource').filter((r) => /\.lp\?/.test(r.name)).length;
    } catch (_) { return 0; }
  }

  // ---- Discord auth ----
  let accessToken = null;

  async function api(path, body) {
    const res = await fetch(path, {
      method: body === undefined ? 'GET' : 'POST',
      headers: Object.assign({ 'Content-Type': 'application/json' },
        accessToken ? { Authorization: 'Bearer ' + accessToken } : {}),
      body: body === undefined ? undefined : JSON.stringify(body),
    });
    if (!res.ok) throw new Error(path + ' ' + res.status);
    return res.json();
  }

  const TOKEN_KEY = 'iro_graffiti_discord_token_v1';
  const SCOPES = Object.freeze(['identify']);

  function safeStorage() {
    try { const s = window.localStorage; s.setItem('__iro_t', '1'); s.removeItem('__iro_t'); return s; }
    catch (_) { try { return window.sessionStorage; } catch (_) { return null; } }
  }

  async function authFlow(sdk, clientId, exchange, storage) {
    let cached = null;
    try { cached = storage && JSON.parse(storage.getItem(TOKEN_KEY) || 'null'); } catch (_) {}
    if (cached && cached.access_token && (!cached.exp || cached.exp > Date.now())) {
      try {
        const a = await sdk.commands.authenticate({ access_token: cached.access_token });
        if (a && a.user) return { access_token: cached.access_token, user: a.user };
      } catch (_) { /* expired/revoked */ }
    }
    try { storage && storage.removeItem(TOKEN_KEY); } catch (_) {}
    const { code } = await sdk.commands.authorize({
      client_id: clientId, response_type: 'code', state: '', prompt: 'none', scope: SCOPES.slice(),
    });
    const tok = await exchange(code);
    const a = await sdk.commands.authenticate({ access_token: tok.access_token });
    if (a && a.user) {
      const exp = a.expires ? Date.parse(a.expires) : Date.now() + 6 * 864e5;
      try { storage && storage.setItem(TOKEN_KEY, JSON.stringify({ access_token: tok.access_token, exp: isNaN(exp) ? 0 : exp })); } catch (_) {}
    }
    return { access_token: tok.access_token, user: a && a.user };
  }

  // Resolves to JSON {token, uid, name} (Firebase custom token) or null
  // outside Discord / on failure (the app then falls back to anonymous auth).
  async function init() {
    if (window.__iroFirebaseReady) await window.__iroFirebaseReady;
    if (!inDiscord) return null;
    const cfg = await api('/api/config');
    if (!cfg || !cfg.client_id) throw new Error('worker has no DISCORD_CLIENT_ID');
    const sdk = new window.DiscordSDKBundle.DiscordSDK(cfg.client_id);
    window.__iroDiscordSdk = sdk;
    await sdk.ready();
    const auth = await authFlow(sdk, cfg.client_id, (code) => api('/api/token', { code }), safeStorage());
    accessToken = auth.access_token;
    if (!auth.user) throw new Error('discord authenticate returned no user');
    const fb = await api('/api/firebase-token', {});
    return JSON.stringify(fb);
  }

  window.__iroGraffitiAuthFlow = authFlow; // exposed for tests
  window.IroGraffiti = {
    inDiscord: () => inDiscord,
    init: () => init().catch((e) => { note('init: ' + (e && e.message || e)); console.warn('[IroGraffiti]', e); return null; }),
    firebaseReady: () => (window.__iroFirebaseReady || Promise.resolve()).then(() => true, (e) => { note('firebase js: ' + e); return false; }),
    net: () => JSON.stringify(Object.assign({}, net, { longPolls: longPollCount(), inDiscord })),
    note,
  };
})();
