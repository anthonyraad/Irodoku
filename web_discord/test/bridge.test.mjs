import test from 'node:test'; import assert from 'node:assert';
import fs from 'node:fs'; import vm from 'node:vm';
const src = fs.readFileSync(new URL('../discord_bridge.js', import.meta.url), 'utf8');
function load() { const w = {}; vm.runInNewContext(src, { window: w, location: { search: '' }, URLSearchParams, Date, JSON }); return w.__iroAuthFlow; }
function mem() { const m = new Map(); return { getItem: k => m.has(k) ? m.get(k) : null, setItem: (k, v) => m.set(k, String(v)), removeItem: k => m.delete(k) }; }
function sdk(valid) { const calls = []; return { calls, commands: {
  authorize: async (a) => { calls.push(['authorize', a]); return { code: 'c' }; },
  authenticate: async ({ access_token }) => { calls.push(['authenticate', access_token]); if (!valid.has(access_token)) throw new Error('bad'); return { user: { id: '1' }, expires: new Date(Date.now() + 1e9).toISOString() }; } } }; }
test('first launch authorizes with prompt none + identify only, then caches', async () => {
  const flow = load(), st = mem(), s = sdk(new Set(['T1']));
  const r = await flow(s, async () => ({ access_token: 'T1' }), st);
  assert.equal(r.access_token, 'T1');
  const a = s.calls.find(c => c[0] === 'authorize')[1];
  assert.equal(a.prompt, 'none'); assert.deepEqual([...a.scope], ['identify']);
  const s2 = sdk(new Set(['T1']));
  await flow(s2, async () => { throw new Error('no exchange'); }, st);
  assert.ok(!s2.calls.some(c => c[0] === 'authorize'), 'second launch must not authorize');
});
test('invalid cached token falls back to authorize', async () => {
  const flow = load(), st = mem(); st.setItem('iro_discord_token_v1', JSON.stringify({ access_token: 'OLD', exp: 0 }));
  const s = sdk(new Set(['NEW']));
  const r = await flow(s, async () => ({ access_token: 'NEW' }), st);
  assert.equal(r.access_token, 'NEW'); assert.ok(s.calls.some(c => c[0] === 'authorize'));
});
