#!/usr/bin/env bash
# Is the deployed shell the shell in this working tree? Byte for byte.
#
# WHY THIS EXISTS. Deploy verification was done by hand, by grepping the served
# app.js for feature strings. Three times in one session the pattern was wrong --
# `class=\"tback\"` when the code emits `class="btn tback"`, `class=\"txaxis\"`
# written with shell-escaped quotes that grep took literally -- and each time the
# output read exactly like a broken deploy. Twice I was one step from reporting a
# defect that did not exist.
#
# The cause was the same every time: a pattern RECONSTRUCTED FROM MEMORY. So
# there are no patterns here. Comparing the whole artifact subsumes every pattern
# anyone could type: if the served bytes equal the local bytes, every class name,
# every function and every string is present by construction.
#
# NOTHING IS HAND-TYPED:
#   - the file list comes from check-sw-hash.sh, which already owns it
#   - the URL comes from the git remote
#   - the version and shell hash are extracted from the files, not quoted here
#   - the shell hash is RECOMPUTED from the served bytes with check-sw-hash's own
#     algorithm, which catches a stale sw.js served alongside fresh assets
#
# NOT PART OF THE SUITE, deliberately, which is why it is not called check-*.sh:
# the suite must run offline (offline-gate) and BEFORE a push. This runs after
# one. Prints `GATE: PASS` / `GATE: FAIL` like any other check.
#
# "Cannot confirm" prints FAIL, not PASS. For a deploy check that polarity is the
# whole point: silence from the network is not evidence of a good deploy.
set -uo pipefail

DIR=$(cd "$(dirname "$0")/.." && pwd)
cd "$DIR"

ATTEMPTS=${ATTEMPTS:-8}
PAUSE=${PAUSE:-25}

# ---- the URL, from the remote --------------------------------------------
REMOTE=$(git remote get-url origin 2>/dev/null || true)
if [ -z "$REMOTE" ]; then
  echo "verify-deploy: no 'origin' remote, so the deployed URL cannot be derived"
  echo "GATE: FAIL"; exit 1
fi
# git@github.com:Owner/Repo.git  or  https://github.com/Owner/Repo(.git)
# The suffix is stripped FIRST. An optional (\.git)? after a greedy group never
# matches, because the greedy group has already eaten it -- that bug derived
# the URL as `.../healthtracker.git`, and this check reported FAIL with the
# derived URL printed, which is how it was found in a single run.
REMOTE_BARE=${REMOTE%.git}
OWNER=$(printf '%s' "$REMOTE_BARE" | sed -E 's#^.*[:/]([^/]+)/[^/]+$#\1#')
REPO=$(printf '%s' "$REMOTE_BARE" | sed -E 's#^.*/##')
OWNER_LC=$(printf '%s' "$OWNER" | tr 'A-Z' 'a-z')
BASE="https://${OWNER_LC}.github.io/${REPO}"
echo "verify-deploy: $BASE  (derived from $REMOTE)"

# ---- the file list, from the check that already owns it -------------------
TEXT=$(grep -E '^TEXT=' tests/check-sw-hash.sh | head -1 | sed -E 's/^TEXT="(.*)"$/\1/')
BIN=$(grep -E '^BIN=' tests/check-sw-hash.sh | head -1 | sed -E 's/^BIN="(.*)"$/\1/')
if [ -z "$TEXT" ] || [ -z "$BIN" ]; then
  echo "verify-deploy: could not read the shell file list out of tests/check-sw-hash.sh"
  echo "  That list is the single source of truth for what the shell IS; this check"
  echo "  will not invent a second copy of it."
  echo "GATE: FAIL"; exit 1
fi
# sw.js is excluded from the shell HASH (its own bytes change when it changes)
# but it is still part of what gets deployed, so it is compared like the rest.
ALL="$TEXT $BIN sw.js"
N_FILES=$(printf '%s\n' $ALL | grep -c .)
echo "verify-deploy: $N_FILES files  ($(printf '%s' "$TEXT" | wc -w) text, $(printf '%s' "$BIN" | wc -w) binary, + sw.js)"

for f in $ALL; do
  [ -f "$f" ] || { echo "verify-deploy: local $f is missing"; echo "GATE: FAIL"; exit 1; }
done

# ---- what the local tree says it is (extracted, never quoted) -------------
LOCAL_V=$(grep -oE "APP_VERSION[[:space:]]*=[[:space:]]*'[^']*'" app.js | head -1 | sed -E "s/.*'([^']*)'.*/\1/")
LOCAL_H=$(grep -oE "SHELL_HASH[[:space:]]*=[[:space:]]*'[^']*'" sw.js | head -1 | sed -E "s/.*'([^']*)'.*/\1/")
if [ -z "$LOCAL_V" ] || [ -z "$LOCAL_H" ]; then
  echo "verify-deploy: could not extract APP_VERSION / SHELL_HASH from the local tree"
  echo "GATE: FAIL"; exit 1
fi
echo "verify-deploy: local v$LOCAL_V  shell $LOCAL_H"

TMP=$(mktemp -d 2>/dev/null || mktemp -d -t vd)
trap 'rm -rf "$TMP"' EXIT

fetch_all() {   # -> 0 if every file came back non-empty
  local ok=0 f
  for f in $ALL; do
    mkdir -p "$TMP/served/$(dirname "$f")"
    if ! curl -fsS --max-time 30 "$BASE/$f?cb=$RANDOM$RANDOM" -o "$TMP/served/$f" 2>/dev/null; then
      ok=1
    elif [ ! -s "$TMP/served/$f" ]; then
      ok=1
    fi
  done
  return $ok
}

# A text file's CR is a checkout artifact, not a difference: the blob is LF and
# that is what Pages serves. Binaries are compared raw.
hash_text() { LC_ALL=C tr -d '\r' < "$1" | sha256sum | cut -d' ' -f1; }
hash_raw()  { sha256sum < "$1" | cut -d' ' -f1; }

MISMATCH=""
SERVED_V=""
SERVED_H=""
for i in $(seq 1 "$ATTEMPTS"); do
  MISMATCH=""
  if ! fetch_all; then
    echo "  attempt $i: could not fetch every file"
    [ "$i" -lt "$ATTEMPTS" ] && sleep "$PAUSE"
    MISMATCH="unreachable"
    continue
  fi
  for f in $TEXT sw.js; do
    [ "$(hash_text "$f")" = "$(hash_text "$TMP/served/$f")" ] || MISMATCH="$MISMATCH $f"
  done
  for f in $BIN; do
    [ "$(hash_raw "$f")" = "$(hash_raw "$TMP/served/$f")" ] || MISMATCH="$MISMATCH $f"
  done
  SERVED_V=$(grep -oE "APP_VERSION[[:space:]]*=[[:space:]]*'[^']*'" "$TMP/served/app.js" | head -1 | sed -E "s/.*'([^']*)'.*/\1/")
  SERVED_H=$(grep -oE "SHELL_HASH[[:space:]]*=[[:space:]]*'[^']*'" "$TMP/served/sw.js" | head -1 | sed -E "s/.*'([^']*)'.*/\1/")
  if [ -z "$MISMATCH" ]; then
    echo "  attempt $i: served v${SERVED_V:-?} shell ${SERVED_H:-?} -- all $N_FILES files identical"
    break
  fi
  echo "  attempt $i: served v${SERVED_V:-?} shell ${SERVED_H:-?} -- differs:$MISMATCH"
  [ "$i" -lt "$ATTEMPTS" ] && sleep "$PAUSE"
done

if [ "$MISMATCH" = "unreachable" ]; then
  echo "verify-deploy: FAIL - could not reach $BASE after $ATTEMPTS attempts"
  echo "  Not evidence of a good deploy. A verification that cannot see its subject"
  echo "  reports FAIL, because 'cannot confirm' must never read as 'confirmed'."
  echo "GATE: FAIL"; exit 1
fi
if [ -n "$MISMATCH" ]; then
  echo "verify-deploy: FAIL - the deployed shell differs from this tree:$MISMATCH"
  echo "  local  v$LOCAL_V  shell $LOCAL_H"
  echo "  served v${SERVED_V:-?}  shell ${SERVED_H:-?}"
  echo "  If the versions match but bytes differ, the push landed and Pages is still"
  echo "  propagating, or a file outside the shell list changed. If the versions"
  echo "  differ, the deploy has not arrived yet."
  echo "GATE: FAIL"; exit 1
fi

# ---- the served sw.js must describe the served shell ---------------------
# check-sw-hash.sh's own algorithm, over the SERVED bytes. This is the one thing
# byte-equality does not cover by itself: a correct sw.js and correct assets can
# still be served from two different deploys.
(
  cd "$TMP/served" || exit 1
  H1=$(cat $TEXT | LC_ALL=C tr -d '\r' | sha256sum | cut -d' ' -f1)
  H2=$(sha256sum $BIN | sha256sum | cut -d' ' -f1)
  printf '%s%s' "$H1" "$H2" | sha256sum | cut -c1-12
) > "$TMP/recomputed" 2>/dev/null
RECOMP=$(cat "$TMP/recomputed" 2>/dev/null)
if [ -z "$RECOMP" ]; then
  echo "verify-deploy: FAIL - could not recompute the shell hash from the served bytes"
  echo "GATE: FAIL"; exit 1
fi
if [ "$RECOMP" != "$SERVED_H" ]; then
  echo "verify-deploy: FAIL - the served sw.js does not describe the served shell"
  echo "  served SHELL_HASH : $SERVED_H"
  echo "  recomputed        : $RECOMP"
  echo "  The service worker would cache under a name that does not match what it"
  echo "  cached, which is the stale-shell trap D6's content-derived name exists to"
  echo "  prevent. Byte-equality alone cannot see this."
  echo "GATE: FAIL"; exit 1
fi

echo "verify-deploy: OK - v$SERVED_V, shell $SERVED_H, $N_FILES files byte-identical to this tree,"
echo "  and the served sw.js's SHELL_HASH recomputes from the served bytes."
echo "  No hand-typed patterns: file list from check-sw-hash.sh, URL from the git remote,"
echo "  version and hash extracted from the files themselves."
echo "GATE: PASS"
exit 0
