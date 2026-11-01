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
