#!/usr/bin/env bash
# Builds the Discord Activity web app into discord/server/public.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
flutter pub get
flutter build web --release -t lib/main_discord.dart --dart-define=DISCORD=true \
  --base-href=/ --no-web-resources-cdn -o build/web_discord
# Swap in the Discord index (no Google sign-in meta, loads SDK + bridge).
sed 's#\$FLUTTER_BASE_HREF#/#' web_discord/index.html > build/web_discord/index.html
cp web_discord/discord_bridge.js build/web_discord/
( cd discord/server && npm install --no-audit --no-fund && npx esbuild sdk-entry.js \
    --bundle --minify --format=iife --outfile=../../build/web_discord/discord-sdk.js )
rm -rf discord/server/public && cp -r build/web_discord discord/server/public
echo "Built -> discord/server/public"
