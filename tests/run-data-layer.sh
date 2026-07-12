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
