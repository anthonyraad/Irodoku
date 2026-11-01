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
BUILD_ID="$(git rev-parse --short HEAD 2>/dev/null || date +%s)"
sed "s/__BUILD__/$BUILD_ID/g" web_discord/index.html > "$TMP/index.html"
# No service worker; version main.dart.js so caches can't serve an old build.
python3 - "$TMP/flutter_bootstrap.js" "$BUILD_ID" <<'PY'
import re,sys
p,v=sys.argv[1],sys.argv[2];s=open(p).read()
s=s.replace('"mainJsPath":"main.dart.js"','"mainJsPath":"main.dart.js?v=%s"'%v)
s=re.sub(r'_flutter\.loader\.load\(\{.*?\}\);\s*$','_flutter.loader.load({});\n',s,flags=re.S)
open(p,'w').write(s)
PY
cp web_discord/discord_bridge.js "$TMP/"
( cd web_discord && npm ci --no-audit --no-fund 2>/dev/null || npm install --no-audit --no-fund; npm run -s bundle-sdk )
cp web_discord/dist/discord-sdk.js "$TMP/"
rm -f "$TMP/flutter_service_worker.js"  # avoid SW caching surprises inside Discord
rm -rf "$OUT"; mkdir -p "$(dirname "$OUT")"; mv "$TMP" "$OUT"
echo "Discord build -> $OUT"
