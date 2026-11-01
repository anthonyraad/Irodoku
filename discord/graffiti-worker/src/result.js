// "<Winner> vandalized <Loser>" Discord posts for finished Graffiti matches.
// Winner/loser come from rooms/<code> in RTDB (never from the client).
// Dedupe: irodoku_graffiti_posts/<code>/<matchKey> claimed with ETag if-match.
// Streaks: irodoku_graffiti_streaks/<pairKey> = { winner, loser, count, messageId }.
import { rtdb } from '../../worker/src/firebase.js';

export const AVATAR_URL = 'https://cdn.discordapp.com/app-icons/1565967052047388822/3e3c1202310b13633f9ae599a7785b29.png?size=256';
const CODE_RE = /^[A-Z0-9]{5}$/;
const SAFE_KEY = /^[A-Za-z0-9_:-]{1,128}$/;

// App DisplayName rules (lib/models/daily_leaderboard.dart): 2–10 of [A-Za-z0-9 ._-].
export function roomName(raw) {
  const s = String(raw ?? '').trim().replace(/\s+/g, ' ');
  return s.length >= 2 && s.length <= 10 && /^[A-Za-z0-9 ._-]+$/.test(s) ? s : 'Player';
}
export const escapeMd = (s) => s.replace(/([\\*_~`|>])/g, '\\$1');
export const resultText = (w, l, count) =>
  `**${escapeMd(w)}** vandalized **${escapeMd(l)}**${count > 1 ? ` ${count}x` : ''}`;
export const pairKey = (a, b) => [a, b].sort().join('__');

async function sha(s) {
  const d = await crypto.subtle.digest('SHA-256', new TextEncoder().encode(s));
  return [...new Uint8Array(d)].slice(0, 8).map((b) => b.toString(16).padStart(2, '0')).join('');
}

/** Decided 2-player match from a room snapshot, or { skip: reason }. */
export async function decide(room, callerUid) {
  if (!room || typeof room !== 'object') return { skip: 'room_gone' };
  if (!String(room.app || '').startsWith('irodoku_graffiti')) return { skip: 'not_graffiti' };
  const players = Object.keys(room.players || {});
  if (!players.includes(callerUid)) return { skip: 'not_in_room' };
  if (room.gameState !== 'finished') return { skip: 'not_finished' };
  // Opponent left mid-match (app shows "Playing solo"; no rematch): not a real win.
  if (room.solo === true || players.length !== 2) return { skip: 'solo' };
  const winner = String(room.winner || '');
  if (!players.includes(winner)) return { skip: 'no_winner' }; // draw / defeat
  const loser = players.find((p) => p !== winner);
  if (!SAFE_KEY.test(winner) || !SAFE_KEY.test(loser)) return { skip: 'bad_uid' };
  const names = room.names || {};
  const matchKey = `${Number(room.createdAt) || 0}_${await sha(JSON.stringify(room.puzzle || []))}`;
  return { winner, loser, winnerName: roomName(names[winner]), loserName: roomName(names[loser]), matchKey };
}

async function readTagged(env, path) {
  const r = await rtdb(env, path, { headers: { 'X-Firebase-ETag': 'true' } });
  if (!r.ok) throw new Error(`rtdb ${r.status}`);
  return { etag: r.headers.get('ETag'), val: await r.json() };
}

const hookBody = (content) => ({
  content, username: 'Graffiti', avatar_url: AVATAR_URL, allowed_mentions: { parse: [] },
});

async function postNew(env, content) {
  const r = await fetch(`${env.DISCORD_WEBHOOK_URL}?wait=true`, {
    method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify(hookBody(content)),
  });
  if (!r.ok) throw new Error(`webhook ${r.status}`);
  return String((await r.json()).id || '');
}

async function editMsg(env, id, content) {
  const r = await fetch(`${env.DISCORD_WEBHOOK_URL}/messages/${id}`, {
    method: 'PATCH', headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ content, allowed_mentions: { parse: [] } }),
  });
  return r.ok;
}

/** Post/edit for a decided match. Idempotent per match. */
export async function announce(env, code, m) {
  const claimPath = `irodoku_graffiti_posts/${code}/${m.matchKey}`;
  const claim = await readTagged(env, claimPath);
  if (claim.val != null) return { posted: false, reason: 'duplicate' };
  const put = await rtdb(env, claimPath, { method: 'PUT', body: Date.now(), headers: { 'if-match': claim.etag } });
  if (!put.ok) return { posted: false, reason: 'duplicate' };
  try {
    const sPath = `irodoku_graffiti_streaks/${pairKey(m.winner, m.loser)}`;
    for (let attempt = 0; attempt < 3; attempt++) {
      const { etag, val } = await readTagged(env, sPath);
      const cont = val && val.winner === m.winner && val.messageId;
      const count = cont ? (Number(val.count) || 1) + 1 : 1;
      const content = resultText(m.winnerName, m.loserName, count);
      let messageId = cont ? String(val.messageId) : '';
      let edited = false;
      if (cont) edited = await editMsg(env, messageId, content);
      if (!edited) messageId = await postNew(env, content); // new streak, or old message gone
      const next = { winner: m.winner, loser: m.loser, count, messageId, at: Date.now() };
      const w = await rtdb(env, sPath, { method: 'PUT', body: next, headers: { 'if-match': etag } });
      if (w.ok) return { posted: true, count, edited };
      if (w.status !== 412) throw new Error(`rtdb ${w.status}`);
    }
    throw new Error('streak contention');
  } catch (e) {
    // Release the claim so a retry (other player's client) can post.
    await rtdb(env, claimPath, { method: 'DELETE' }).catch(() => {});
    throw e;
  }
}

export async function handleResult(code, callerUid, env) {
  if (!CODE_RE.test(String(code || ''))) return { status: 400, body: { error: 'bad_code' } };
  const room = await (await rtdb(env, `rooms/${code}`)).json();
  const m = await decide(room, callerUid);
  if (m.skip) return { status: 200, body: { posted: false, reason: m.skip } };
  return { status: 200, body: await announce(env, code, m) };
}
