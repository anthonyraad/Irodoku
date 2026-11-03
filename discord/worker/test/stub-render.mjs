// Node can't load the Workers wasm/ttf imports; stub render.js for unit tests.
import { registerHooks } from 'node:module';
registerHooks({
  load(url, ctx, next) {
    if (url.endsWith('/src/render.js')) return { format: 'module', shortCircuit: true,
      source: 'export const leaderboardEmbed = (day, rows) => ({ title: day, description: `${rows.length} rows`, rows: rows.length }); export const renderPng = async () => { throw new Error("stub"); };' };
    return next(url, ctx);
  },
});
