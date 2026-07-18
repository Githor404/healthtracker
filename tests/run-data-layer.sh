#!/usr/bin/env bash
# Re-runnable Phase 0 data-layer gate. Drives headless Chrome/Edge against
# tests/data-layer.test.html (which loads the real ../app.js), extracts the
# per-assertion results, and exits non-zero unless every check passes.
# No Node, no build step — just a browser.
set -uo pipefail

DIR=$(cd "$(dirname "$0")" && pwd)
HTML="$DIR/data-layer.test.html"

# Phase R (D5/D7): the legacy path must be fully stripped from app.js. Match code
# (the migrator/constant identifiers and quoted 'uha-log-v1' string usage) — a
# doc comment mentioning the removed key in backticks is fine.
STRIP_RE="migrateLegacy|LEGACY_KEY|['\"]uha-log-v1['\"]"
if grep -nE "$STRIP_RE" "$DIR/../app.js" >/dev/null 2>&1; then
  echo "STRIP CHECK: FAIL — legacy code remains in app.js:"
  grep -nE "$STRIP_RE" "$DIR/../app.js"
  exit 1
fi
echo "strip check: app.js is legacy-free"

# SW cache name must track the shell (D6): fail if sw.js SHELL_HASH is stale, so
# a shell change can never ship without the SW seeing it.
if ! bash "$DIR/check-sw-hash.sh" >/dev/null 2>&1; then
  bash "$DIR/check-sw-hash.sh"
  echo "SW-HASH CHECK: FAIL"
  exit 1
fi
echo "sw-hash check: sw.js cache name tracks the shell"

# ZXing sourcing drift (D15): the ZXING single-SoT constant's SRI hash must match
# the pinned CDN file (online), and version/host stay consistent (offline). A
# stale hash is a silent "scanner won't load" -- same class as the SW-hash trap.
if ! bash "$DIR/check-zxing.sh"; then
  echo "ZXING CHECK: FAIL"
  exit 1
fi

# APP_VERSION drift (D6 force-and-notify): APP_VERSION must carry a changelog line
# and bump whenever the shell changes, so an update can't ship without a notice.
if ! bash "$DIR/check-version.sh"; then
  echo "VERSION CHECK: FAIL"
  exit 1
fi

# Convert the POSIX path to a file:// URL Chrome understands on Windows.
if command -v cygpath >/dev/null 2>&1; then
  URL="file:///$(cygpath -m "$HTML")"
else
  URL="file:///$(printf '%s' "$HTML" | sed -E 's#^/([a-zA-Z])/#\U\1:/#')"
fi

BROWSER=""
for c in \
  "/c/Program Files/Google/Chrome/Application/chrome.exe" \
  "/c/Program Files (x86)/Google/Chrome/Application/chrome.exe" \
  "/c/Program Files (x86)/Microsoft/Edge/Application/msedge.exe" \
  "/c/Program Files/Microsoft/Edge/Application/msedge.exe"; do
  if [ -x "$c" ]; then BROWSER="$c"; break; fi
done
if [ -z "$BROWSER" ]; then echo "ERROR: no headless Chrome/Edge found" >&2; exit 2; fi

OUT=$("$BROWSER" --headless --disable-gpu --no-sandbox --allow-file-access-from-files \
  --dump-dom "$URL" 2>/dev/null \
  | grep -oE '<p class="(r|s)">[^<]*</p>' | sed -E 's/<[^>]+>//g')

echo "$OUT"
echo "-----------------------------------------"
if printf '%s\n' "$OUT" | grep -q 'ALL PASS'; then
  echo "GATE: PASS"
  exit 0
fi
echo "GATE: FAIL"
exit 1
