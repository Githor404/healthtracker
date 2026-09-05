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

# R21/D45 Fork G: the SW must let the BYOK vision call through untouched. A
# cross-origin POST is not cacheable BY DEFAULT, and "by default" is not "never",
# so the bypass is asserted rather than assumed.
if ! grep -q "req.method !== 'GET') return" "$DIR/../sw.js"; then
  echo "SW BYPASS: FAIL - the non-GET early return is gone; the vision POST could be intercepted"; exit 1
fi
if ! grep -q "url.origin !== self.location.origin) return" "$DIR/../sw.js"; then
  echo "SW BYPASS: FAIL - the cross-origin passthrough is gone"; exit 1
fi
if ! grep -q "Fork G" "$DIR/../sw.js"; then
  echo "SW BYPASS: FAIL - the bypass is no longer named as deliberate (D45 Fork G)"; exit 1
fi
echo "sw bypass: the BYOK call passes through uncached (non-GET + cross-origin)"

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

# Write-site census (D29): every record-write must be a REGISTERED site, classified
# stamped-with-the-tz-offset or exempt-with-a-reason. A new write site fails here
# rather than silently joining unstamped.
if ! bash "$DIR/check-writesites.sh"; then
  echo "WRITESITES CHECK: FAIL"
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

# --virtual-time-budget: the D30 cases load the SHIPPED index.html into an iframe,
# so the dump must wait for that async load rather than snapshotting mid-flight.
OUT=$("$BROWSER" --headless --disable-gpu --no-sandbox --allow-file-access-from-files \
  --virtual-time-budget=20000 --dump-dom "$URL" 2>/dev/null \
  | grep -oE '<p class="(r|s)">[^<]*</p>' | sed -E 's/<[^>]+>//g')

echo "$OUT"
echo "-----------------------------------------"

# ASSERTION-COUNT DISCIPLINE (ruled after the v0.11.0 masked-exception defect).
# A synchronous throw used to abort the suite while still printing a green-looking
# SUMMARY with a silently reduced count -- ~40 D35 assertions never ran and nobody
# noticed. The harness now records such a throw as a failure, and this pin is the
# second line of defence: the EXECUTED count must match the pinned number, so any
# silent drop fails the gate rather than passing quietly.
#
# Bump EXPECTED_ASSERTIONS deliberately, in the same commit that adds or removes
# cases, and state the delta in the gate report.
#
# AUTHORED is a static lower-bound cross-check only: it counts source LINES
# containing a res( call, so multi-line calls and helper reuse make it an
# approximation, not an equality. The PIN is the enforcing mechanism.
EXPECTED_ASSERTIONS=1173
TOTAL=$(printf '%s\n' "$OUT" | grep -oE 'SUMMARY [0-9]+/[0-9]+' | head -1 | sed -E 's#.*/##')
AUTHORED=$(grep -cE '(^|[^A-Za-z_.])res\(' "$HTML")
echo "assertions: executed ${TOTAL:-0} · pinned $EXPECTED_ASSERTIONS · authored-lines(static lower bound) $AUTHORED"
if [ -z "$TOTAL" ]; then
  echo "ASSERTION COUNT: FAIL - no SUMMARY line (the suite did not finish)"
  echo "GATE: FAIL"
  exit 1
fi
if [ "$TOTAL" -ne "$EXPECTED_ASSERTIONS" ]; then
  echo "ASSERTION COUNT: FAIL - executed $TOTAL, pinned $EXPECTED_ASSERTIONS (delta $((TOTAL - EXPECTED_ASSERTIONS)))"
  echo "  A DROP means cases stopped running - find out why before re-pinning."
  echo "  A RISE means cases were added - re-pin deliberately in the same commit."
  echo "GATE: FAIL"
  exit 1
fi
if printf '%s\n' "$OUT" | grep -q 'ALL PASS'; then
  echo "GATE: PASS"
  exit 0
fi
echo "GATE: FAIL"
exit 1
