#!/usr/bin/env bash
# The SW cache name is content-derived (DECISIONS.md D6). This computes the hash
# of the precached shell (everything EXCEPT sw.js) and verifies sw.js's
# SHELL_HASH matches. If the shell changed but SHELL_HASH did not, the deployed
# SW would never update and the cache would go stale — the trap that froze the
# first-deploy shell. `--fix` writes the current hash into sw.js.
#
# Line endings are normalized for text so the hash is platform-stable; binaries
# (PNG) are hashed raw. sw.js's own edits are self-detecting (its bytes change),
# so it is excluded from the hash.
set -uo pipefail

DIR=$(cd "$(dirname "$0")/.." && pwd)
cd "$DIR"

TEXT="index.html app.js manifest.json icons/icon.svg"
BIN="icons/icon-192.png icons/icon-512.png icons/apple-touch-icon.png"

for f in $TEXT $BIN; do
  [ -f "$f" ] || { echo "sw-hash: missing shell file $f" >&2; exit 2; }
done

H1=$(cat $TEXT | tr -d '\r' | sha256sum | cut -d' ' -f1)
H2=$(sha256sum $BIN | sha256sum | cut -d' ' -f1)
HASH=$(printf '%s%s' "$H1" "$H2" | sha256sum | cut -c1-12)

CUR=$(grep -oE "SHELL_HASH = '[^']*'" sw.js | head -1 | sed -E "s/.*'([^']*)'.*/\1/")

if [ "${1:-}" = "--fix" ]; then
  sed -i -E "s/(const SHELL_HASH = ')[^']*(')/\\1${HASH}\\2/" sw.js
  echo "sw-hash: SHELL_HASH set to $HASH"
  exit 0
fi

if [ "$HASH" = "$CUR" ]; then echo "sw-hash: OK ($HASH)"; exit 0; fi
echo "sw-hash: STALE - shell changed but sw.js SHELL_HASH was not updated"
echo "  shell hash: $HASH"
echo "  sw.js hash: $CUR"
echo "  fix:        bash tests/check-sw-hash.sh --fix"
exit 1
