#!/usr/bin/env bash
# ZXing sourcing drift gate (DECISIONS.md D15). The ZXING constant in app.js is
# the SINGLE source of truth for version / url / SRI hash. SRI-pinned + SW-cached
# means a version bump that forgets the hash is a SILENT "scanner won't load" no
# headless test catches -- the same failure class as the SW-version integer that
# went stale for six slices (D6 amendment). This fails loudly on drift.
#
#   bash tests/check-zxing.sh          verify: consistency (offline) + SRI-vs-file (online)
#   bash tests/check-zxing.sh --fix    fetch the pinned file, recompute SRI, stamp app.js
#
# Offline: consistency still runs; the SRI-vs-file check WARNs and passes (run
# online before shipping a bump). Online: a stale hash FAILS the gate.
set -uo pipefail

DIR=$(cd "$(dirname "$0")/.." && pwd)
cd "$DIR"

val() { grep -oE "$1: '[^']*'" app.js | head -1 | sed -E "s/.*'([^']*)'.*/\1/"; }
VERSION=$(val version)
URL=$(val url)
SRI=$(val integrity)
HOST=$(printf '%s' "$URL" | sed -E 's#https?://([^/]+)/.*#\1#')

fail() { echo "check-zxing: FAIL - $1"; exit 1; }
[ -n "$VERSION" ] || fail "no ZXING.version in app.js"
[ -n "$URL" ]     || fail "no ZXING.url in app.js"
[ -n "$SRI" ]     || fail "no ZXING.integrity in app.js"

# Consistency (offline): the url pins the version, and sw.js runtime-caches this
# exact host (so the SW keeps caching ZXing across version bumps).
case "$URL" in
  *"@zxing/library@$VERSION/"*) : ;;
  *) fail "ZXING.url does not pin version $VERSION" ;;
esac
grep -qF "ZXING_HOST = '$HOST'" sw.js || fail "sw.js runtime cache does not reference host $HOST"
echo "check-zxing: consistency OK (version $VERSION, host $HOST)"

# SRI-vs-file (network). --fix stamps the computed hash; plain run fails on drift.
TMP="$DIR/tests/.zxing.tmp"
if ! curl -fsSL --max-time 25 "$URL" -o "$TMP" 2>/dev/null; then
  rm -f "$TMP"
  echo "check-zxing: WARN - offline; SRI hash NOT verified against the file (run online before shipping a bump)"
  exit 0
fi
COMPUTED="sha384-$(python -c "import hashlib,base64,sys;print(base64.b64encode(hashlib.sha384(open(sys.argv[1],'rb').read()).digest()).decode())" "$TMP")"
rm -f "$TMP"

if [ "${1:-}" = "--fix" ]; then
  esc=$(printf '%s' "$COMPUTED" | sed -e 's/[&#]/\\&/g')
  sed -i -E "s#(integrity: ')[^']*(')#\\1${esc}\\2#" app.js
  echo "check-zxing: integrity stamped -> $COMPUTED"
  exit 0
fi

if [ "$COMPUTED" = "$SRI" ]; then
  echo "check-zxing: OK - SRI matches the pinned file ($COMPUTED)"
  exit 0
fi
echo "check-zxing: FAIL - SRI hash STALE vs the file at $URL"
echo "  app.js:   $SRI"
echo "  computed: $COMPUTED"
echo "  fix:      bash tests/check-zxing.sh --fix"
exit 1
