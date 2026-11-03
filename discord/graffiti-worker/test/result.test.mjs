import { test } from 'node:test';
import assert from 'node:assert/strict';
import { generateKeyPairSync } from 'node:crypto';
import worker from '../src/index.js';
import { escapeMd, resultText, roomName, pairKey, sessionKey, AVATAR_URL } from '../src/result.js';

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
function room(code, winner, extra = {}, sc = [17, 8]) {
  const [w, l] = sc, loser = winner === ME ? OPP : ME;
  db[`rooms/${code}`] = {
    stats: { [winner]: { correct: w, mistakes: 1 }, [loser]: { correct: l } },
    app: 'irodoku_graffiti', gameState: 'finished', winner, createdAt: 1000, puzzle: [puzzleSeq++],
    players: { [ME]: true, [OPP]: true }, names: { [ME]: 'Star_scape', [OPP]: 'Sarah' }, ...extra,
  };
}
const result = async (code) => (await worker.fetch(new Request('https://w/result', {
  method: 'POST', headers: { Authorization: 'Bearer good-token-123' }, body: JSON.stringify({ code }),
}), env)).json();

test('helpers', () => {
  assert.equal(escapeMd('a_b*c'), 'a\\_b\\*c');
  assert.equal(resultText('A', 'B', 17, 8), '**A** vandalized **B** 17 - 8');
  assert.equal(resultText('a_b', 'c*d', '3', undefined), '**a\\_b** vandalized **c\\*d** 3 - 0');
  assert.equal(roomName('<@123>'), 'Player');
  assert.equal(pairKey('b', 'a'), 'a__b');
  assert.equal(sessionKey('ABCDE', 'b', 'a'), 'ABCDE__a__b');
});

test('session: lines appended across rematches incl. reversed winner; dedupe', async () => {
  reset();
  room('ABCDE', ME, {}, [17, 8]);
  assert.deepEqual(await result('ABCDE'), { posted: true, lines: 1, edited: false });
  assert.equal(hooks[0].content, '**Star\\_scape** vandalized **Sarah** 17 - 8');
  assert.equal(hooks[0].username, 'Graffiti');
  assert.equal(hooks[0].avatar_url, AVATAR_URL);
  assert.deepEqual(hooks[0].allowed_mentions, { parse: [] });
  assert.equal((await result('ABCDE')).reason, 'duplicate'); // retry / other client
  assert.equal(hooks.length, 1);
  room('ABCDE', ME, {}, [12, 11]);
  assert.deepEqual(await result('ABCDE'), { posted: true, lines: 2, edited: true });
  room('ABCDE', OPP, {}, [15, 9]);
  assert.deepEqual(await result('ABCDE'), { posted: true, lines: 3, edited: true });
  assert.deepEqual([hooks[2].op, hooks[2].id], ['edit', '1']);
  assert.equal(hooks[2].content, [
    '**Star\\_scape** vandalized **Sarah** 17 - 8',
    '**Star\\_scape** vandalized **Sarah** 12 - 11',
    '**Sarah** vandalized **Star\\_scape** 15 - 9'].join('\n'));
  assert.equal((await result('ABCDE')).reason, 'duplicate');
  assert.equal(hooks.length, 3);
  assert.equal(db[`irodoku_graffiti_sessions/ABCDE__${pairKey(ME, OPP)}`].lines.length, 3);
  // Legacy streak path no longer written.
  assert.ok(!('irodoku_graffiti_streaks' in db));
});

test('new message when room or pair changes; old session lines kept', async () => {
  reset();
  room('ABCDE', ME); await result('ABCDE');
  room('FGHJK', ME, {}, [10, 2]);
  assert.deepEqual(await result('FGHJK'), { posted: true, lines: 1, edited: false });
  assert.equal(hooks[1].op, 'post');
  const third = 'android_other';
  room('ABCDE', ME, { players: { [ME]: true, [third]: true }, names: { [ME]: 'Star_scape', [third]: 'Bob' },
    stats: { [ME]: { correct: 9 }, [third]: { correct: 4 } } });
  assert.deepEqual(await result('ABCDE'), { posted: true, lines: 1, edited: false });
  assert.equal(hooks[2].content, '**Star\\_scape** vandalized **Bob** 9 - 4');
  assert.equal(db[`irodoku_graffiti_sessions/ABCDE__${pairKey(ME, OPP)}`].lines.length, 1);
});

test('2000-char rollover starts a new message', async () => {
  reset();
  const k = `irodoku_graffiti_sessions/ABCDE__${pairKey(ME, OPP)}`;
  db[k] = { messageId: '77', lines: ['x'.repeat(1990)] };
  room('ABCDE', ME);
  assert.deepEqual(await result('ABCDE'), { posted: true, lines: 1, edited: false });
  assert.equal(hooks[0].op, 'post');
  assert.ok(hooks.every((h) => h.content.length <= 2000));
  assert.equal(db[k].messageId, '1');
});

test('edited message deleted -> posts new', async () => {
  reset(); room('LMNPQ', ME); await result('LMNPQ');
  deleted.add('1'); room('LMNPQ', ME);
  assert.deepEqual(await result('LMNPQ'), { posted: true, lines: 1, edited: false });
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
