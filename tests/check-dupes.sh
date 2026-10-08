#!/usr/bin/env bash
# NO TOP-LEVEL DEFINITION TWICE. Closing a trap that cost a diagnosis in H30.
#
# WHAT HAPPENED. A patch script spliced a new `identityNormalisePrompt` and a new
# `identityNormaliseParse` into app.js by cutting from the prompt's opening line to
# "the next closing brace" -- which was the PROMPT's brace, not the parse's. So the
# ORIGINAL `identityNormaliseParse` survived BELOW the new one.
#
# In JavaScript a later `function` declaration SILENTLY REPLACES an earlier one.
# Both definitions parsed. Nothing warned. The app ran the old array-returning
# version while every new caller expected `{names, per100}`, and the failure
# surfaced three layers away as "Cannot read properties of undefined (reading
# 'length')".
#
#   > The one you read was not the one that ran.
#
# That is the whole class, and it is invisible to every other gate here: the file
# is valid, the suite boots, and only a caller that happens to use the NEW contract
# fails. A duplicate that happens to be behaviourally identical would never fail at
# all -- it would just sit there waiting for one of the two to be edited.
#
# A DUPLICATE `const` OR `let` IS DIFFERENT, AND IS CHECKED ANYWAY. At top level
# those are a SyntaxError, so they break loudly and immediately -- they cannot hide.
# They are still reported, because the cost of checking is nothing and the day this
# file is wrapped in a module or an IIFE the scoping rules change under it.
#
# TOP LEVEL ONLY, by column zero. A nested helper or an object method may share a
# name with something else by design; two definitions in the SAME scope cannot.
#
# Exit 0 PASS, 1 FAIL.
set -uo pipefail

DIR=$(cd "$(dirname "$0")/.." && pwd)
cd "$DIR"
FILES="app.js sw.js"
FAILED=0

say_fail() { echo "dupes: FAIL - $1"; FAILED=1; }

# ---- the extractors, used for both the control and the real scan ---------
fn_names() { grep -oE '^function [A-Za-z0-9_$]+' "$1" 2>/dev/null | sed 's/^function //'; }
var_names() { grep -oE '^(const|let) [A-Za-z0-9_$]+' "$1" 2>/dev/null | awk '{print $2}'; }

# ---- PLANTED CONTROL: prove the matcher can fire -------------------------
# A matcher that cannot match reads exactly like a clean file. The control is a
# throwaway with a duplicate of each kind, and both must be found before the real
# scan below is trusted.
CTRL=$(mktemp 2>/dev/null || echo "./.dupes-control.tmp")
cat > "$CTRL" <<'CONTROL'
const PLANTED_TWICE = 1;
function plantedFn(a) { return a; }
const OTHER = 2;
function plantedFn(a, b) { return b; }
const PLANTED_TWICE = 3;
CONTROL
CTRL_FN=$(fn_names "$CTRL" | sort | uniq -d | tr -d ' ')
CTRL_VAR=$(var_names "$CTRL" | sort | uniq -d | tr -d ' ')
rm -f "$CTRL"
if [ "$CTRL_FN" != "plantedFn" ]; then
  say_fail "the CONTROL did not find its planted duplicate function (got '$CTRL_FN') -- the matcher is broken, so a clean scan below would mean nothing"
fi
if [ "$CTRL_VAR" != "PLANTED_TWICE" ]; then
  say_fail "the CONTROL did not find its planted duplicate const (got '$CTRL_VAR')"
fi

# ---- the real scan -------------------------------------------------------
TOTAL_FN=0
TOTAL_VAR=0
for f in $FILES; do
  [ -f "$f" ] || { say_fail "$f is missing"; continue; }
  nfn=$(fn_names "$f" | grep -c . || true)
  nvar=$(var_names "$f" | grep -c . || true)
  TOTAL_FN=$((TOTAL_FN + nfn))
  TOTAL_VAR=$((TOTAL_VAR + nvar))

  dfn=$(fn_names "$f" | sort | uniq -d)
  if [ -n "$dfn" ]; then
    say_fail "$f defines these top-level function(s) TWICE -- the later one silently wins:"
    printf '%s\n' "$dfn" | while IFS= read -r n; do
      [ -n "$n" ] || continue
      echo "    $n  (lines: $(grep -nE "^function ${n}\\b" "$f" | cut -d: -f1 | tr '\n' ' '))"
    done
    echo "    Both parse and nothing warns. Delete the stale one; do not rename it."
  fi

  dvar=$(var_names "$f" | sort | uniq -d)
  if [ -n "$dvar" ]; then
    say_fail "$f declares these top-level const/let TWICE (a SyntaxError -- the file will not run):"
    printf '%s\n' "$dvar" | while IFS= read -r n; do
      [ -n "$n" ] || continue
      echo "    $n  (lines: $(grep -nE "^(const|let) ${n}\\b" "$f" | cut -d: -f1 | tr '\n' ' '))"
    done
  fi
done

# ---- a floor, so a rotted pattern cannot pass vacuously (D96) ------------
# app.js carried 927 top-level functions and 321 const/let when this was written.
# The floors are deliberately far below those: they exist to catch an extractor
# that has stopped matching, not to pin a count that changes every slice.
if [ "$TOTAL_FN" -lt 400 ]; then
  say_fail "only $TOTAL_FN top-level function(s) were found across $FILES -- the extractor has rotted, so finding no duplicates proves nothing"
fi
if [ "$TOTAL_VAR" -lt 150 ]; then
  say_fail "only $TOTAL_VAR top-level const/let were found -- same rot, other extractor"
fi

if [ "$FAILED" -ne 0 ]; then
  echo "GATE: FAIL"
  exit 1
fi
echo "dupes: OK ($TOTAL_FN top-level functions, $TOTAL_VAR const/let across $FILES;"
echo "  no name defined twice, and the planted control proves the matcher fires)"
echo "GATE: PASS"
exit 0
