// Bot-side Discord features: interaction signature verification and the
// single per-day status message in the daily channel (Wordle-style).
import { rtdb } from './firebase.js';

const API = 'https://discord.com/api/v10';
const hexBytes = (h) => new Uint8Array((h.match(/../g) || []).map((b) => parseInt(b, 16)));

/** Verify Discord's Ed25519 request signature (X-Signature-Ed25519 / -Timestamp). */
export async function verifyDiscordRequest(publicKeyHex, signatureHex, timestamp, body) {
  if (!publicKeyHex || !signatureHex || !timestamp) return false;
  try {
    const key = await crypto.subtle.importKey('raw', hexBytes(publicKeyHex), { name: 'Ed25519' }, false, ['verify']);
    return await crypto.subtle.verify('Ed25519', key, hexBytes(signatureHex),
      new TextEncoder().encode(timestamp + body));
  } catch { return false; }
}

export const botEnabled = (env) => Boolean(env.DISCORD_BOT_TOKEN && env.DISCORD_CHANNEL_ID);

export async function botApi(env, method, path, body) {
  const init = { method, headers: { Authorization: `Bot ${env.DISCORD_BOT_TOKEN}` } };
  if (body instanceof FormData) init.body = body;
  else if (body !== undefined) {
    init.headers['Content-Type'] = 'application/json';
    init.body = JSON.stringify(body);
  }
  return fetch(API + path, init);
}

const fmt = (ms) => {
  const t = Math.floor(ms / 1000), h = Math.floor(t / 3600), m = Math.floor((t % 3600) / 60), s = t % 60;
  const ss = String(s).padStart(2, '0');
  return h ? `${h}:${String(m).padStart(2, '0')}:${ss}` : `${m}:${ss}`;
};
const esc = (s) => String(s).replace(/([\\*_~`|>#\[\]()])/g, '\\$1');

export const PLAY_BUTTON = { type: 1, components: [{ type: 2, style: 1, label: 'Play now!', custom_id: 'iro_play' }] };

export const ANDROID_LINK = '[Get Irodoku on Android ↗](https://play.google.com/store/apps/details?id=com.irodoku.irodoku)';
export const DESC_LIMIT = 4096; // Discord embed description max

/** Shared by the initial POST and every PATCH: body + blank line + Android link,
 * truncating the leaderboard body (never the link) to fit Discord's limit. */
export function dailyDescription(body, limit = DESC_LIMIT) {
  const tail = `\n\n${ANDROID_LINK}`;
  const max = limit - tail.length;
  if (body.length > max) {
    const cut = body.slice(0, max - 1);
    const nl = cut.lastIndexOf('\n');
    body = (nl > 0 ? cut.slice(0, nl) : cut) + '…';
  }
  return body + tail;
}

export function dailyMessagePayload(day, rows) {
  const n = rows.length;
  const lines = rows.slice(0, 30).map((r, i) => `${i + 1}. **${esc(r.name)}** — ${fmt(r.ms)}`);
  if (n > 30) lines.push(`…and ${n - 30} more`);
  const body = n ? `${n} player${n === 1 ? '' : 's'} solved today\n\n` + lines.join('\n') : "Today's Iro is live!";
  return {
    allowed_mentions: { parse: [] },
    embeds: [{
      title: `Daily Iro — ${dispDay(day)}`, color: 0x7c5cff,
      description: dailyDescription(body),
    }],
    components: [PLAY_BUTTON],
  };
}

async function finishers(env, day) {
  const res = await rtdb(env, `irodoku_daily/${day}/pocket`);
  if (!res.ok) throw new Error(`rtdb ${res.status}`);
  return Object.values((await res.json()) || {})
    .filter((v) => v && Number.isFinite(Number(v.ms)))
    .map((v) => ({ name: String(v.name || 'Player'), ms: Number(v.ms) }))
    .sort((a, b) => a.ms - b.ms);
}

/** Create today's message if missing, else edit it with the current finishers. */
export async function upsertDailyMessage(env, day) {
  if (!botEnabled(env)) return { skipped: true };
  const path = `irodoku_daily_msg/${day}`;
  const cur = await rtdb(env, path, { headers: { 'X-Firebase-ETag': 'true' } });
  if (!cur.ok) throw new Error(`rtdb ${cur.status}`);
  const rec = await cur.json();
  const ch = env.DISCORD_CHANNEL_ID;
  if (rec && rec.id) {
    const payload = dailyMessagePayload(day, await finishers(env, day));
    const r = await botApi(env, 'PATCH', `/channels/${ch}/messages/${rec.id}`, payload);
    if (r.ok) return { edited: rec.id };
    if (r.status !== 404) throw new Error(`discord edit ${r.status}`);
    await rtdb(env, path, { method: 'DELETE' }); // message was deleted: recreate below
  } else if (rec && rec.pending && Date.now() - rec.pending < 30e3) {
    return { pending: true }; // another request is creating it
  }
  // Claim creation so concurrent launches don't post twice.
  const guard = rec && rec.id ? {} : { 'if-match': cur.headers.get('ETag') };
  const claim = await rtdb(env, path, { method: 'PUT', body: { pending: Date.now() }, headers: guard });
  if (!claim.ok) return { pending: true };
  const payload = dailyMessagePayload(day, await finishers(env, day));
  const r = await botApi(env, 'POST', `/channels/${ch}/messages`, payload);
  if (!r.ok) { await rtdb(env, path, { method: 'DELETE' }); throw new Error(`discord post ${r.status}`); }
  const msg = await r.json();
  await rtdb(env, path, { method: 'PUT', body: { id: msg.id, at: Date.now() } });
  return { created: msg.id };
}

/** '2026-10-31' -> '10.31.26' for display. */
export function dispDay(day) {
  const m = /^(\d{4})-(\d{2})-(\d{2})$/.exec(String(day));
  return m ? `${m[2]}.${m[3]}.${m[1].slice(2)}` : String(day);
}
