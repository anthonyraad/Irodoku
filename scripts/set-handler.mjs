#!/usr/bin/env node
// Switch the Activity's Entry Point command handler.
//   DISCORD_BOT_TOKEN=... node scripts/set-handler.mjs          -> handler 1 (APP_HANDLER: our /interactions)
//   DISCORD_BOT_TOKEN=... node scripts/set-handler.mjs --revert -> handler 2 (DISCORD_LAUNCH_ACTIVITY)
const APP_ID = process.env.DISCORD_APP_ID || '1565967052047388822';
const token = process.env.DISCORD_BOT_TOKEN;
if (!token) { console.error('DISCORD_BOT_TOKEN is required'); process.exit(1); }
const handler = process.argv.includes('--revert') ? 2 : 1;
const api = (path, init = {}) => fetch(`https://discord.com/api/v10${path}`, {
  ...init, headers: { Authorization: `Bot ${token}`, 'Content-Type': 'application/json', ...(init.headers || {}) },
});
const list = await api(`/applications/${APP_ID}/commands`);
if (!list.ok) { console.error('list failed', list.status, await list.text()); process.exit(1); }
const entry = (await list.json()).find((c) => c.type === 4);
if (!entry) { console.error('no PRIMARY_ENTRY_POINT (type 4) command found'); process.exit(1); }
const r = await api(`/applications/${APP_ID}/commands/${entry.id}`, { method: 'PATCH', body: JSON.stringify({ handler }) });
if (!r.ok) { console.error('patch failed', r.status, await r.text()); process.exit(1); }
console.log(`entry point ${entry.id} (${entry.name}) handler -> ${(await r.json()).handler}`);
