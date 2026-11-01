# Pocket Daily Iro — Discord Activity

* **Client**: `lib/main_discord.dart` (Pocket 6×6 Daily only), `web_discord/` (index, SDK bridge, local SDK bundle).
  Built by `web_discord/build.sh` into `build/web/discord`, deployed with the main Pages site at
  `https://anthonyraad.github.io/Irodoku/discord/`. Base href is chosen at runtime (`/` under the
  Discord proxy, `/Irodoku/discord/` on Pages).
* **API + nightly**: `discord/worker` (Cloudflare Worker). Firebase RTDB via REST with a Google OAuth
  token minted from the service account (RS256 JWT, WebCrypto). Start times live in RTDB
  (`irodoku_daily_starts`), so no KV/D1.

## Discord URL Mappings (Developer Portal → Activities → URL Mappings)
| Prefix | Target |
|---|---|
| `/api` | `irodoku-discord.<account-subdomain>.workers.dev` |
| `/` | `anthonyraad.github.io/Irodoku/discord` |

## Worker
```
cd discord/worker && npm install
npx wrangler login
npx wrangler secret put DISCORD_CLIENT_SECRET
npx wrangler secret put DISCORD_WEBHOOK_URL
npx wrangler secret put FIREBASE_SERVICE_ACCOUNT   # paste the JSON (or base64)
# set FIREBASE_DATABASE_URL in wrangler.toml [vars]
npx wrangler deploy
```
Local: `npx wrangler dev` (`.dev.vars` with `DEV_PREVIEW=1` enables `GET /api/nightly-preview?format=png|embed`).
Cron test: `curl "localhost:8787/cdn-cgi/local/scheduled?cron=0+8+*+*+*"`.

`NIGHTLY_FORMAT=embed` (default) fits Workers Free's 10 ms CPU cap; `png` (resvg-wasm, ~9 ms warm /
~45 ms cold) is better on Workers Paid and falls back to embed on error.

## Android "Sync Discord" (account link)
Routes on the same Worker (called directly by the Android app, not via the Activity proxy):
`POST /link/start` (Firebase ID token → Discord authorize URL with HMAC-signed state),
`GET /link/callback` (OAuth redirect; writes `irodoku_links/android/{uid}` = `{discordId,name,linkedAt}` and
`irodoku_links/discord/{discordId}` = `{uid}`, merges today's Pocket entry from the anon uid onto the
Discord key keeping the better time, then 302 → `irodoku://discord-linked?name=…|error=…`),
`POST /link/disconnect` (Firebase ID token; removes both records).
The Discord player's Pocket key is the raw Discord user id (same key the Activity writes).

Setup: Developer Portal → OAuth2 → Redirects: `https://irodoku-discord.raadscapes.workers.dev/link/callback`;
`npx wrangler secret put LINK_STATE_SECRET` (random, e.g. `openssl rand -base64 32`). Rules: see
`firebase/irodoku_daily.rules.md` (`irodoku_links` + linked Pocket writes).
