#!/usr/bin/env bash
# APP_VERSION drift gate (DECISIONS.md D6 force-and-notify amendment). APP_VERSION
# is load-bearing: it must carry a VERSION_LOG changelog line and MOVE whenever the
# shell changes -- so a shipped update can't silently show no notice, and a bump
# can't ship without a changelog. Same spirit as check-sw-hash.
#
# Drift is measured against the LAST COMMIT (the last release), not a stamped
# baseline -- so iterating within a release is friction-free, and a commit that
# changes the shell without bumping APP_VERSION fails. No --fix / no baseline file.
#
# BOTH DIRECTIONS ARE GATED (D6 converse amendment, 2026-09-06):
#   shell changed + APP_VERSION did not move  -> FAIL (an update with no notice)
#   APP_VERSION moved + shell otherwise same  -> FAIL (a notice with no update)
# The second is the one that needed thought. Bumping APP_VERSION EDITS app.js,
# which is itself a shell file, so "the shell changed" is trivially true on every
# bump and a plain diff can never catch a hollow one. So the shell is fingerprinted
# with its version metadata STRIPPED -- the APP_VERSION assignment and the
# VERSION_LOG entry lines removed -- and compared against HEAD. Same fingerprint
# with a moved version means the version was the only thing that changed, which
# under force-and-notify ships a changelog line announcing work no user can see.
set -uo pipefail

DIR=$(cd "$(dirname "$0")/.." && pwd)
cd "$DIR"
SHELL_FILES="index.html app.js manifest.json icons"
SHELL_TEXT="index.html app.js manifest.json icons/icon.svg"
SHELL_BIN="icons/icon-192.png icons/icon-512.png icons/apple-touch-icon.png"

# Version metadata, removed so the REST of the shell can be compared. Matches the
# APP_VERSION assignment and VERSION_LOG entry lines only -- references such as
# `'HealthTracker/' + APP_VERSION` are not assignments and are deliberately kept.
#
# The entry pattern deliberately keys on `{ v: 'X.Y.Z'` ALONE, not on what follows.
# It once required `, note:` and that was a latent silent-skip: adding the `d:`
# release-date field between them would have stopped the line matching, the two
# fingerprints would then differ on any changelog edit, and since the converse arm
# fires only when they are EQUAL it would have quietly stopped catching hollow
# bumps. A gate must not depend on the shape of a field it is not checking.
strip_vmeta() {
  sed -E \
    -e "/APP_VERSION[[:space:]]*=[[:space:]]*'[^']*'/d" \
    -e "/^[[:space:]]*\{[[:space:]]*v:[[:space:]]*'[0-9]+\.[0-9]+\.[0-9]+'/d"
}
# Line endings normalized like check-sw-hash, so the fingerprint is platform-stable.
subst_hash_work() {
  for f in $SHELL_TEXT; do
    if [ "$f" = app.js ]; then strip_vmeta < "$f"; else cat "$f"; fi
  done | tr -d '\r' | sha256sum | cut -d' ' -f1
}
subst_hash_head() {
  for f in $SHELL_TEXT; do
    if [ "$f" = app.js ]; then git show "HEAD:$f" | strip_vmeta; else git show "HEAD:$f"; fi
  done | tr -d '\r' | sha256sum | cut -d' ' -f1
}

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

# Release date lives INSIDE the entry (D6 converse amendment) so it cannot drift
# from the version it describes -- but it can still be omitted, so require it on
# the entry being shipped. Older entries predating the convention stay bare and
# render as the version alone; only the newest is gated.
APPV_LINE=$(grep -F "{ v: '$APPV'," app.js | head -1)
[ -n "$APPV_LINE" ] || fail "no VERSION_LOG line found for APP_VERSION $APPV"
APPV_DATE=$(printf '%s' "$APPV_LINE" | grep -oE "d: '[0-9]{4}-[0-9]{2}-[0-9]{2}'" | head -1 | cut -d"'" -f2)
[ -n "$APPV_DATE" ] || fail "VERSION_LOG entry for $APPV has no release date - add d: 'YYYY-MM-DD' to it (it is what Settings shows)"
TODAY=$(date +%F)
if [ "$APPV_DATE" ">" "$TODAY" ]; then
  fail "VERSION_LOG release date for $APPV is in the future ($APPV_DATE > $TODAY) - likely a typo"
fi

# Drift: if the shell changed since the last commit, APP_VERSION must have bumped.
if git rev-parse HEAD >/dev/null 2>&1; then
  if ! git diff --quiet HEAD -- $SHELL_FILES 2>/dev/null; then
    PREV=$(git show HEAD:app.js 2>/dev/null | extract_appv)
    if [ -n "$PREV" ] && [ "$PREV" = "$APPV" ]; then
      fail "shell changed since last commit but APP_VERSION did not bump (still $APPV) - bump it + add a VERSION_LOG line"
    fi
    # Converse arm: the version moved, but did anything a user could SEE move with it?
    if [ -n "$PREV" ] && [ "$PREV" != "$APPV" ] \
       && [ "$(subst_hash_work)" = "$(subst_hash_head)" ] \
       && git diff --quiet HEAD -- $SHELL_BIN 2>/dev/null; then
      echo "check-version: FAIL - APP_VERSION bumped $PREV -> $APPV but the shell is"
      echo "  otherwise UNCHANGED: stripped of the version line and the VERSION_LOG"
      echo "  entries, the shell fingerprint is identical to HEAD. Under force-and-notify"
      echo "  (D6) this ships a changelog line to every device announcing a change that"
      echo "  did not happen. Infrastructure work (gates, harness, docs) is not a release."
      echo "  fix: ship a real shell change with the bump, or hold the version."
      exit 1
    fi
    echo "check-version: OK ($APPV; shell changed since last commit, APP_VERSION bumped $PREV -> $APPV)"
    exit 0
  fi
fi
echo "check-version: OK ($APPV, changelog present; shell unchanged since last commit)"
exit 0
