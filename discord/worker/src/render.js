// Leaderboard image: hand-built SVG -> PNG via resvg-wasm with the bundled
// Balatro font (no system fonts in Workers). Small canvas keeps CPU low.
import { initWasm, Resvg } from '@resvg/resvg-wasm';
import resvgWasm from '@resvg/resvg-wasm/index_bg.wasm';
import font from './font.ttf';

let ready = null;
const esc = (s) => String(s).replace(/[&<>"']/g, (c) => `&#${c.charCodeAt(0)};`);
export const fmtMs = (ms) => { const s = Math.floor(ms / 1000); return `${Math.floor(s / 60)}:${String(s % 60).padStart(2, '0')}`; };
const COLORS = ['#ff5a5f', '#ffb400', '#ffe14d', '#3ddc97', '#3aa0ff', '#a970ff'];

export function leaderboardSvg(day, rows) {
  const W = 600, H = 110 + Math.max(rows.length, 1) * 40;
  const bars = COLORS.map((c, i) => `<rect x="${i * 100}" y="0" width="100" height="8" fill="${c}"/>`).join('');
  const body = rows.length
    ? rows.map((r, i) => {
      const y = 104 + i * 40;
      return `<text x="28" y="${y}" fill="${i < 3 ? COLORS[i] : '#cccccc'}">${i + 1}.</text>`
        + `<text x="80" y="${y}" fill="#ffffff">${esc(r.name)}</text>`
        + `<text x="${W - 28}" y="${y}" fill="#ffffff" text-anchor="end">${fmtMs(r.ms)}</text>`;
    }).join('')
    : '<text x="28" y="104" fill="#aaaaaa">No times yesterday.</text>';
  return `<svg xmlns="http://www.w3.org/2000/svg" width="${W}" height="${H}" font-family="Balatro" font-size="24">`
    + `<rect width="100%" height="100%" fill="#16131f"/>${bars}`
    + `<text x="28" y="56" font-size="30" fill="#ffffff">Daily Iro  ${esc(day)}</text>${body}</svg>`;
}

export async function renderPng(day, rows) {
  ready ??= initWasm(resvgWasm);
  await ready;
  const r = new Resvg(leaderboardSvg(day, rows), {
    font: { fontBuffers: [new Uint8Array(font)], loadSystemFonts: false, defaultFontFamily: 'Balatro' },
  });
  return r.render().asPng();
}

export function leaderboardEmbed(day, rows) {
  const lines = rows.length
    ? rows.map((r, i) => `\`${String(i + 1).padStart(2)}.\` **${r.name}** — ${fmtMs(r.ms)}`).join('\n')
    : 'No times yesterday.';
  return { title: `Daily Iro — ${day}`, description: lines, color: 0xa970ff };
}
