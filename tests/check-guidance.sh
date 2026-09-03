#!/usr/bin/env bash
# R6.1 ruling: the design's scale reference is the USER'S KNOWLEDGE, delivered
# through the confirm question -- not props in frame. User-facing photo help
# reduces to "one plate, all items visible" and nothing else.
#
# The browser suite covers the RENDERED surfaces (the draft + the prompt text).
# This is the static half: the photo pane in the shell, the shipped template
# constant, and the README -- prose the suite cannot load.
#
# Scoped deliberately. A repo-wide grep for "angle" would drown in ring geometry;
# this reads only the three places photo guidance could actually be written.
#
# On failure: delete the guidance. Do not narrow the term list to make it pass.
set -uo pipefail

DIR=$(cd "$(dirname "$0")/.." && pwd)
cd "$DIR"

TERMS='for scale|reference object|size reference|a coin|a fork|your hand|at an angle|straight down|overhead|in frame'

# ---- PLANTED CONTROL -------------------------------------------------------
# R6-vocab's lesson: a matcher that cannot match reads exactly like a clean pass.
# Prove the matcher can fail before trusting it to pass.
CONTROL='put a fork in frame for scale'
CONTROL_HITS=$(printf '%s\n' "$CONTROL" | grep -oiE "$TERMS" | wc -l | tr -d ' ')
if [ "$CONTROL_HITS" -ne 3 ]; then
  echo "guidance: FAIL - the CONTROL did not match ($CONTROL_HITS of 3 terms)."
  echo "  The matcher is broken, so a clean scan below would mean nothing."
  exit 1
fi

# ---- the three surfaces ----------------------------------------------------
PANE=$(sed -n '/id="pane-photo"/,/id="pane-manual"/p' index.html)
TMPL=$(sed -n '/^const AI_PROMPT_TEMPLATE/,/^const AI_PROMPT_SAMPLE/p' app.js)
[ -n "$PANE" ] || { echo "guidance: FAIL - the photo pane was not found in index.html"; exit 1; }
[ -n "$TMPL" ] || { echo "guidance: FAIL - AI_PROMPT_TEMPLATE was not found in app.js"; exit 1; }

FOUND=0
for pair in "photo pane (index.html)|$PANE" "AI_PROMPT_TEMPLATE (app.js)|$TMPL" "README.md|$(cat README.md)"; do
  WHERE=${pair%%|*}
  BODY=${pair#*|}
  HITS=$(printf '%s\n' "$BODY" | grep -inE "$TERMS")
  if [ -n "$HITS" ]; then
    echo "guidance: FAIL - reference-object guidance in $WHERE:"
    printf '    %s\n' "$HITS"
    FOUND=1
  fi
done

[ "$FOUND" -eq 0 ] || exit 1
echo "guidance: OK (control matched 3/3; no prop, framing or angle advice on the 3 photo surfaces)"
exit 0
