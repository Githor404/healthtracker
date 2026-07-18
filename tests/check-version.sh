#!/usr/bin/env bash
# APP_VERSION drift gate (DECISIONS.md D6 force-and-notify amendment). APP_VERSION
# is load-bearing: it must carry a VERSION_LOG changelog line and MOVE whenever the
# shell changes -- so a shipped update can't silently show no notice, and a bump
# can't ship without a changelog. Same spirit as check-sw-hash.
#
# Drift is measured against the LAST COMMIT (the last release), not a stamped
# baseline -- so iterating within a release is friction-free, and a commit that
# changes the shell without bumping APP_VERSION fails. No --fix / no baseline file.
set -uo pipefail

DIR=$(cd "$(dirname "$0")/.." && pwd)
cd "$DIR"
SHELL_FILES="index.html app.js manifest.json icons"

extract_appv() { grep -oE "APP_VERSION[[:space:]]*=[[:space:]]*'[^']*'" | head -1 | sed -E "s/.*'([^']*)'.*/\1/"; }
APPV=$(extract_appv < app.js)
LOGV=$(grep -oE "v: '[0-9]+\.[0-9]+\.[0-9]+'" app.js | sed -E "s/.*'([^']*)'.*/\1/")

fail() { echo "check-version: FAIL - $1"; exit 1; }
[ -n "$APPV" ] || fail "no APP_VERSION in app.js"
[ -n "$LOGV" ] || fail "no VERSION_LOG entries in app.js"

# Changelog discipline: APP_VERSION must have a VERSION_LOG line and be the newest.
echo "$LOGV" | grep -qx "$APPV" || fail "APP_VERSION $APPV has no VERSION_LOG changelog entry"
NEWEST=$(printf '%s\n' "$LOGV" | sort -V | tail -1)
[ "$APPV" = "$NEWEST" ] || fail "APP_VERSION $APPV is not the newest VERSION_LOG entry (newest: $NEWEST)"

# Drift: if the shell changed since the last commit, APP_VERSION must have bumped.
if git rev-parse HEAD >/dev/null 2>&1; then
  if ! git diff --quiet HEAD -- $SHELL_FILES 2>/dev/null; then
    PREV=$(git show HEAD:app.js 2>/dev/null | extract_appv)
    if [ -n "$PREV" ] && [ "$PREV" = "$APPV" ]; then
      fail "shell changed since last commit but APP_VERSION did not bump (still $APPV) - bump it + add a VERSION_LOG line"
    fi
    echo "check-version: OK ($APPV; shell changed since last commit, APP_VERSION bumped $PREV -> $APPV)"
    exit 0
  fi
fi
echo "check-version: OK ($APPV, changelog present; shell unchanged since last commit)"
exit 0
