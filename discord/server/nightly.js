// Nightly: after PST (UTC-8) midnight, post yesterday's Pocket top-10 as a PNG.
// Run via cron at 08:00 UTC (= 00:00 UTC-8), e.g. `0 8 * * *  node nightly.js`.
// Env: DISCORD_WEBHOOK_URL, FIREBASE_SERVICE_ACCOUNT, FIREBASE_DATABASE_URL.
// `node nightly.js --dry-run [day]` writes leaderboard.png without posting.
import { writeFileSync } from 'node:fs';
import { createCanvas } from '@napi-rs/canvas';
import { pstDayKey, topPocket } from './firebase.js';

const fmt = (ms) => { const s = Math.floor(ms / 1000); return `${Math.floor(s / 60)}:${String(s % 60).padStart(2, '0')}`; };

export function render(day, rows) {
  const W = 640, H = 120 + Math.max(rows.length, 1) * 44;
  const c = createCanvas(W, H); const g = c.getContext('2d');
  g.fillStyle = '#16131f'; g.fillRect(0, 0, W, H);
  const colors = ['#ff5a5f', '#ffb400', '#ffe14d', '#3ddc97', '#3aa0ff', '#a970ff'];
  colors.forEach((col, i) => { g.fillStyle = col; g.fillRect(i * (W / 6), 0, W / 6, 8); });
  g.fillStyle = '#fff'; g.font = 'bold 30px sans-serif';
  g.fillText(`Pocket Daily Iro — ${day}`, 28, 60);
  g.font = '24px sans-serif';
  if (!rows.length) { g.fillStyle = '#aaa'; g.fillText('No times yesterday.', 28, 110); }
  rows.forEach((r, i) => {
    const y = 110 + i * 44;
    g.fillStyle = i < 3 ? colors[i] : '#ccc'; g.fillText(`${i + 1}.`, 28, y);
    g.fillStyle = '#fff'; g.fillText(String(r.name).slice(0, 24), 80, y);
    g.textAlign = 'right'; g.fillText(fmt(r.ms), W - 28, y); g.textAlign = 'left';
  });
  return c.toBuffer('image/png');
}

async function main() {
  const dry = process.argv.includes('--dry-run');
  const argDay = process.argv.find((a) => /^\d{4}-\d{2}-\d{2}$/.test(a));
  const day = argDay || pstDayKey(new Date(Date.now() - 86400e3));
  const rows = dry && !process.env.FIREBASE_SERVICE_ACCOUNT
    ? [{ name: 'Sample', ms: 61234 }, { name: 'Another', ms: 75000 }]
    : await topPocket(day, 10);
  const png = render(day, rows);
  if (dry) { writeFileSync('leaderboard.png', png); console.log('wrote leaderboard.png'); return; }
  const url = process.env.DISCORD_WEBHOOK_URL;
  if (!url) throw new Error('DISCORD_WEBHOOK_URL not set');
  const form = new FormData();
  form.append('payload_json', JSON.stringify({ content: `🏆 Pocket Daily Iro results for ${day}` }));
  form.append('files[0]', new Blob([png], { type: 'image/png' }), `pocket-${day}.png`);
  const r = await fetch(url, { method: 'POST', body: form });
  if (!r.ok) throw new Error(`webhook ${r.status}: ${await r.text()}`);
  console.log('posted', day, rows.length);
}
main().catch((e) => { console.error(e); process.exit(1); });
