#!/usr/bin/env bash
# D131 -- THE ALLOWLIST CENSUS.
#
# Every record normaliser in app.js is an ALLOWLIST REBUILD. A property written
# onto a stored record but never declared in that record's normaliser is DELETED
# the first time the record is restored, imported or migrated -- silently, and far
# from the change that caused it.
#
# It has hit repeatedly, most recently `it.ref`: D121 wrote it, D129 declared it
# eight versions later, and the warning against it was already written INSIDE THE
# FUNCTION THAT WAS MISSED. A rule in a comment is a rule nobody runs.
#
# Both sides of the census are derived from the source -- the allowlist from each
# normaliser's own body, the writes from the assignments in the file. No field
# name is kept by hand anywhere in this check.
#
# Exit 0 OK, 1 FAIL, 2 could not run.
set -uo pipefail
DIR=$(cd "$(dirname "$0")" && pwd)

PY=""
for c in python3 python py; do
  if command -v "$c" >/dev/null 2>&1; then PY="$c"; break; fi
done

if [ -z "$PY" ]; then
  # Silence is the one outcome a check may never produce: say it could not run
  # rather than letting an absent interpreter read as a clean sheet.
  echo "allowlist: COULD NOT RUN - no python interpreter found"
  echo "GATE: FAIL"
  echo "  This check is not optional: without it, a field written to a record and"
  echo "  missing from its normaliser ships silently and is lost at the next restore."
  exit 2
fi

"$PY" "$DIR/allowlist_census.py"
rc=$?
if [ "$rc" -ne 0 ] && [ "$rc" -ne 1 ]; then
  echo "allowlist: COULD NOT RUN - the census exited $rc"
  echo "GATE: FAIL"
  exit 2
fi
exit $rc
