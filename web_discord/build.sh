#!/usr/bin/env bash
# Build the Discord Activity into $1 (default build/web/discord).
# Base href is chosen at runtime by web_discord/index.html, so the same files
# work under the Discord proxy root and under /Irodoku/discord/ on Pages.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"; cd "$ROOT"
OUT="${1:-build/web/discord}"
TMP=build/web_discord_tmp
flutter build web --release -t lib/main_discord.dart --dart-define=DISCORD=true \
  --no-web-resources-cdn -o "$TMP"
cp web_discord/index.html "$TMP/index.html"
cp web_discord/discord_bridge.js "$TMP/"
( cd web_discord && npm ci --no-audit --no-fund 2>/dev/null || npm install --no-audit --no-fund; npm run -s bundle-sdk )
cp web_discord/dist/discord-sdk.js "$TMP/"
rm -f "$TMP/flutter_service_worker.js"  # avoid SW caching surprises inside Discord
rm -rf "$OUT"; mkdir -p "$(dirname "$OUT")"; mv "$TMP" "$OUT"
echo "Discord build -> $OUT"
