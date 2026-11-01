import { test } from 'node:test';
import assert from 'node:assert/strict';
import { generateKeyPairSync } from 'node:crypto';
import worker from '../src/index.js';
import { escapeMd, resultText, roomName, pairKey, AVATAR_URL } from '../src/result.js';

const { privateKey } = generateKeyPairSync('rsa', { modulusLength: 2048 });
const env = {
  FIREBASE_DATABASE_URL: 'https://db.test', DISCORD_WEBHOOK_URL: 'https://hook.test/w',
  FIREBASE_SERVICE_ACCOUNT: JSON.stringify({ client_email: 'a@b', private_key: privateKey.export({ type: 'pkcs8', format: 'pem' }) }),
};
const ME = 'discord_100000000001', OPP = 'android_uid_xyz';
let db, hooks, nextId, deleted;
function reset() { db = {}; hooks = []; nextId = 1; deleted = new Set(); }
globalThis.fetch = async (url, init = {}) => {
  url = String(url); const m = init.method || 'GET';
  const res = (b, s = 200, h = {}) => new Response(JSON.stringify(b), { status: s, headers: h });
  if (url.includes('oauth2.googleapis')) return res({ access_token: 't', expires_in: 3600 });
  if (url.endsWith('/users/@me')) return res({ id: '100000000001', global_name: 'Me' });
  if (url.startsWith('https://hook.test/w')) {
    const body = JSON.parse(init.body);
    if (m === 'POST') { assert.ok(url.endsWith('?wait=true')); const id = String(nextId++); hooks.push({ op: 'post', id, ...body }); return res({ id }); }
    const id = url.split('/messages/')[1];
    if (deleted.has(id)) return res({}, 404);
    hooks.push({ op: 'edit', id, ...body }); return res({ id });
  }
  const path = url.replace('https://db.test/', '').replace(/\.json.*$/, '');
  const etag = JSON.stringify(db[path] ?? null);
  if (m === 'GET') return res(db[path] ?? null, 200, { ETag: etag });
  if (m === 'DELETE') { delete db[path]; return res(null); }
  if (m === 'PUT') {
    const im = init.headers?.['if-match'];
    if (im !== undefined && im !== etag) return res({}, 412);
    db[path] = JSON.parse(init.body); return res(db[path]);
  }
};

let puzzleSeq = 0;
function room(code, winner, extra = {}) {
  db[`rooms/${code}`] = {
    app: 'irodoku_graffiti', gameState: 'finished', winner, createdAt: 1000, puzzle: [puzzleSeq++],
    players: { [ME]: true, [OPP]: true }, names: { [ME]: 'Star_scape', [OPP]: 'Sarah' }, ...extra,
  };
}
const result = async (code) => (await worker.fetch(new Request('https://w/result', {
  method: 'POST', headers: { Authorization: 'Bearer good-token-123' }, body: JSON.stringify({ code }),
}), env)).json();

test('helpers', () => {
  assert.equal(escapeMd('a_b*c'), 'a\\_b\\*c');
  assert.equal(resultText('A', 'B', 1), '**A** vandalized **B**');
  assert.equal(resultText('A', 'B', 3), '**A** vandalized **B** 3x');
  assert.equal(roomName('<@123>'), 'Player');
  assert.equal(pairKey('b', 'a'), 'a__b');
});

test('post, increment edit, dedupe, streak break', async () => {
  reset();
  room('ABCDE', ME);
  assert.deepEqual(await result('ABCDE'), { posted: true, count: 1, edited: false });
  assert.equal(hooks[0].content, '**Star\\_scape** vandalized **Sarah**');
  assert.equal(hooks[0].username, 'Graffiti');
  assert.equal(hooks[0].avatar_url, AVATAR_URL);
  assert.deepEqual(hooks[0].allowed_mentions, { parse: [] });
  // Same match again (other client / retry): no new post.
  assert.equal((await result('ABCDE')).reason, 'duplicate');
  assert.equal(hooks.length, 1);
  // Rematch (new puzzle) in same room, same winner: edit to 2x.
  room('ABCDE', ME);
  assert.deepEqual(await result('ABCDE'), { posted: true, count: 2, edited: true });
  assert.deepEqual([hooks[1].op, hooks[1].id, hooks[1].content], ['edit', '1', '**Star\\_scape** vandalized **Sarah** 2x']);
  // Different room, same pair, same winner: 3x.
  room('FGHJK', ME);
  assert.equal((await result('FGHJK')).count, 3);
  assert.equal(hooks[2].content.endsWith(' 3x'), true);
  // Opponent wins: streak breaks, new message.
  room('FGHJK', OPP);
  assert.deepEqual(await result('FGHJK'), { posted: true, count: 1, edited: false });
  assert.equal(hooks[3].op, 'post');
  assert.equal(hooks[3].content, '**Sarah** vandalized **Star\\_scape**');
  // Then I win again: new message, count 1.
  room('FGHJK', ME);
  assert.deepEqual(await result('FGHJK'), { posted: true, count: 1, edited: false });
});

test('edited message deleted -> posts new with count', async () => {
  reset(); room('LMNPQ', ME); await result('LMNPQ');
  deleted.add('1'); room('LMNPQ', ME);
  assert.deepEqual(await result('LMNPQ'), { posted: true, count: 2, edited: false });
  assert.equal(hooks.at(-1).op, 'post');
});

test('skips draws, solo, unfinished, gone rooms, non-members', async () => {
  reset();
  room('AAAAA', 'draw'); assert.equal((await result('AAAAA')).reason, 'no_winner');
  room('AAAAA', ME, { solo: true }); assert.equal((await result('AAAAA')).reason, 'solo');
  room('AAAAA', ME, { players: { [ME]: true } }); assert.equal((await result('AAAAA')).reason, 'solo');
  room('AAAAA', null, { gameState: 'playing' }); assert.equal((await result('AAAAA')).reason, 'not_finished');
  room('AAAAA', OPP, { players: { x: true, [OPP]: true } }); assert.equal((await result('AAAAA')).reason, 'not_in_room');
  assert.equal((await result('ZZZZZ')).reason, 'room_gone');
  assert.equal(hooks.length, 0);
  const r = await worker.fetch(new Request('https://w/result', { method: 'POST', headers: { Authorization: 'Bearer good-token-123' }, body: '{"code":"../x"}' }), env);
  assert.equal(r.status, 400);
});
