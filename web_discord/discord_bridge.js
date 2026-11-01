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

  async function init() {
    const Sdk = window.DiscordSDKBundle;
    const params = new URLSearchParams(location.search);
    if (!Sdk || !params.get('frame_id')) return null; // not inside Discord
    const sdk = new Sdk.DiscordSDK(CLIENT_ID);
    window.__iroDiscordSdk = sdk;
    await sdk.ready();
    const { code } = await sdk.commands.authorize({
      client_id: CLIENT_ID,
      response_type: 'code',
      state: '',
      prompt: 'none',
      scope: ['identify'],
    });
    const tok = await api('/api/token', { code });
    accessToken = tok.access_token;
    const auth = await sdk.commands.authenticate({ access_token: accessToken });
    user = auth && auth.user;
    if (!user) return null;
    return user.global_name || user.username;
  }

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
