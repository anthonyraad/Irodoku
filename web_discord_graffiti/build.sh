#!/usr/bin/env bash
# Build the [Graffiti] Discord Activity into $1 (default build/web/discord-graffiti).
# Base href is chosen at runtime by index.html (Discord proxy root or
# /Irodoku/discord-graffiti/ on Pages). Reuses web_discord's SDK bundle.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"; cd "$ROOT"
OUT="${1:-build/web/discord-graffiti}"
TMP=build/web_discord_graffiti_tmp
flutter build web --release -t lib/main_discord_graffiti.dart \
  --no-web-resources-cdn -o "$TMP"
BUILD_ID="$(git rev-parse --short HEAD 2>/dev/null || date +%s)"

# Firebase JS SDK version FlutterFire expects (firebase_core_web's pin).
PUB="${PUB_CACHE:-$HOME/.pub-cache}"
CW_VER="$(awk '/^  firebase_core_web:/{f=1} f&&/version:/{gsub(/"/,"",$2);print $2;exit}' pubspec.lock)"
VER_FILE="$PUB/hosted/pub.dev/firebase_core_web-$CW_VER/lib/src/firebase_sdk_version.dart"
[ -f "$VER_FILE" ] || VER_FILE="$(find "$PUB" "$HOME/.pub-cache" "$(dirname "$(command -v flutter)")/../.pub-cache" -path "*firebase_core_web-$CW_VER/lib/src/firebase_sdk_version.dart" 2>/dev/null | head -1)"
FBJS="$(sed -n "s/.*supportedFirebaseJsSdkVersion = '\(.*\)';/\1/p" "$VER_FILE" 2>/dev/null || true)"
[ -n "$FBJS" ] || { echo "cannot resolve Firebase JS SDK version" >&2; exit 1; }
mkdir -p "$TMP/firebasejs/$FBJS"
for n in app auth database; do
  curl -fsSL "https://www.gstatic.com/firebasejs/$FBJS/firebase-$n.js" -o "$TMP/firebasejs/$FBJS/firebase-$n.js"
done
# Component bundles import firebase-app.js by absolute gstatic URL: make it local.
sed -i "s#https://www.gstatic.com/firebasejs/$FBJS/firebase-app.js#./firebase-app.js#g" "$TMP/firebasejs/$FBJS/"*.js
if grep -l "www.gstatic.com" "$TMP/firebasejs/$FBJS/"*.js >/dev/null; then
  echo "warning: gstatic references remain in firebasejs" >&2
fi

sed -e "s/__BUILD__/$BUILD_ID/g" -e "s/__FBJS__/$FBJS/g" web_discord_graffiti/index.html > "$TMP/index.html"
python3 - "$TMP/flutter_bootstrap.js" "$BUILD_ID" <<'PY'
import re,sys
p,v=sys.argv[1],sys.argv[2];s=open(p).read()
s=s.replace('"mainJsPath":"main.dart.js"','"mainJsPath":"main.dart.js?v=%s"'%v)
s=re.sub(r'_flutter\.loader\.load\(\{.*?\}\);\s*$','_flutter.loader.load({});\n',s,flags=re.S)
open(p,'w').write(s)
PY
cp web_discord_graffiti/graffiti_bridge.js "$TMP/"
( cd web_discord && { npm ci --no-audit --no-fund 2>/dev/null || npm install --no-audit --no-fund; } && npm run -s bundle-sdk )
cp web_discord/dist/discord-sdk.js "$TMP/"
rm -f "$TMP/flutter_service_worker.js"
rm -rf "$OUT"; mkdir -p "$(dirname "$OUT")"; mv "$TMP" "$OUT"
echo "Graffiti Discord build -> $OUT (Firebase JS $FBJS)"
