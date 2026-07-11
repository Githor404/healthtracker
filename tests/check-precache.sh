#!/usr/bin/env bash
# Verify every path in sw.js's PRECACHE list exists on disk. A 404 in
# cache.addAll rejects the whole SW install silently and disables offline —
# this makes that failure class loud at test time. (DECISIONS.md D6)
set -uo pipefail

DIR=$(cd "$(dirname "$0")/.." && pwd)
SW="$DIR/sw.js"
[ -f "$SW" ] || { echo "ERROR: sw.js not found" >&2; exit 2; }

# Pull the quoted entries out of the PRECACHE = [ ... ]; block.
paths=$(sed -n '/const PRECACHE = \[/,/\];/p' "$SW" | grep -oE "'[^']+'" | tr -d "'")
[ -n "$paths" ] || { echo "ERROR: could not parse PRECACHE from sw.js" >&2; exit 2; }

missing=0
while IFS= read -r p; do
  [ -z "$p" ] && continue
  rel="${p#./}"
  [ -z "$rel" ] && rel="index.html"          # './' navigation maps to index.html
  if [ -f "$DIR/$rel" ]; then
    echo "  ok    $p"
  else
    echo "  MISS  $p  ->  $DIR/$rel"
    missing=$((missing + 1))
  fi
done <<< "$paths"

echo "-----------------------------------------"
if [ "$missing" -eq 0 ]; then echo "PRECACHE: PASS"; exit 0; fi
echo "PRECACHE: FAIL ($missing missing)"; exit 1
