#!/usr/bin/env bash
# FULL-SUITE RUNNER -- presence AND a verdict, or fail, by name.
#
# WHY THIS EXISTS. Four times now this project has found the same failure shape:
# a check that silently stops checking while everything still reports green.
#
#   1. Date-pinned gates rotting at midnight            -> D50 (one clock)
#   2. A storage gate green while the row printed 3.5   -> D52 (display is a gate surface)
#   3. A gate script QUARANTINED by antivirus           -> D53 (the presence census)
#   4. A gate script PRESENT but DENIED EXECUTION       -> this runner
#
# The census closed #3 by checking that every gate script EXISTS. #4 walked
# straight past it: `bm-slider-gate.ps1` sat byte-identical to its commit and
# simply would not launch ("Access is denied", one second), because it is the one
# gate that injects synthetic input and the AV's proactive-defence module fires on
# that. Presence was necessary and not sufficient.
#
# So the bar is now PRESENCE + VERDICT. Every gate must PRINT one -- a `GATE: PASS`
# or `GATE: FAIL` line -- and a gate that prints neither fails the suite BY NAME,
# exactly as a missing file does. There is no third outcome called "silence".
#
# The silent skip did not live in any committed script; it lived in how the gates
# were INVOKED, one at a time, by hand, with a `grep GATE:` that printed nothing
# and moved on. That is what this file replaces.
#
# A GATE THIS FILE NEVER CALLS is the same failure one level up (D75). Until
# 2026-09-17 this runner did not execute check-precache.sh or check-guidance.sh,
# while GATES.md counted both as gates, so a green run said nothing about either.
# Every tests/check-*.sh must now be WIRED -- run here, or run inside the harness
# and seen to be called there -- and an unwired one fails the suite by name.
#
# HOW THE COUNT IS ARRIVED AT. "N of N" is the number of verdict lines this file
# prints, and nothing else:
#     1  data-layer harness            (run-data-layer.sh)
#   + the checks in STATIC_CHECKS      (run here)
#   + every *-gate.ps1                 (pinned by the census in run-data-layer.sh)
# The checks in IN_HARNESS are preconditions inside the harness: a failure there
# fails the harness line, and they are not counted a second time. The `counted:`
# line prints this sum on every run, so the number never travels without its
# method -- and the suite fails if the verdicts do not add up to it.
#
# Usage:  bash tests/run-all-gates.sh
#         GATE_TIMEOUT=900 bash tests/run-all-gates.sh    # per-gate seconds
set -uo pipefail

DIR=$(cd "$(dirname "$0")" && pwd)
GATE_TIMEOUT=${GATE_TIMEOUT:-600}

# A hung gate produces no verdict AND never exits -- it would hang this runner
# forever, which is the silent skip with the volume turned all the way down. Every
# gate therefore runs on a leash, and a timeout is a FAILURE, not a pause.
have_timeout=1
command -v timeout >/dev/null 2>&1 || have_timeout=0

echo "==================================================================="
echo " HealthTracker full gate suite -- presence + verdict, or fail"
echo "==================================================================="

FAILED=""
PASSED=""

leashed() {
  if [ "$have_timeout" -eq 1 ]; then timeout "$GATE_TIMEOUT" "$@"; else "$@"; fi
}

# One classification for every gate this file judges directly (the table in
# tests/README.md). Appends to FAILED / PASSED.
judge() {  # judge <name> <rc> <output>
  local name=$1 rc=$2 out=$3 verdict
  verdict=$(printf '%s\n' "$out" | grep -oE 'GATE: (PASS|FAIL)' | tail -1)

  if [ "$rc" -eq 124 ]; then
    # Timed out: no verdict will ever arrive.
    printf '  %-26s FAIL - HUNG, no verdict within %ss\n' "$name" "$GATE_TIMEOUT"
    FAILED="$FAILED ${name}(hung)"
  elif [ -z "$verdict" ]; then
    # PRESENT BUT SPEECHLESS -- the #4 shape. The file exists and the census is
    # satisfied; it simply never reported. That is a failure, never silence.
    printf '  %-26s FAIL - PRODUCED NO VERDICT (rc=%s)\n' "$name" "$rc"
    printf '%s\n' "$out" | grep -viE '^\s*$' | tail -3 | sed 's/^/      /'
    case "$name" in *.ps1)
      echo "      If this reads 'Access is denied' with the file intact, suspect the"
      echo "      ANTIVIRUS proactive-defence module, not the script (tests/README.md)." ;;
    esac
    FAILED="$FAILED ${name}(no-verdict)"
  elif [ "$verdict" != "GATE: PASS" ]; then
    printf '  %-26s FAIL\n' "$name"
    case "$name" in
      *.ps1) printf '%s\n' "$out" | grep -E '\->\s*False|FAIL' | tail -4 | sed 's/^/      /' ;;
      # A static check's output is short and its evidence is not on the FAIL
      # line (the missing path, the offending sentence), so show the output.
      *)     printf '%s\n' "$out" | grep -vE '^\s*(ok\s.*)?$|^GATE:' | tail -6 | sed 's/^/      /' ;;
    esac
    FAILED="$FAILED $name"
  elif [ "$rc" -ne 0 ]; then
    # Said PASS but exited non-zero: the two disagree, so neither is trusted.
    printf '  %-26s FAIL - verdict PASS but exit %s (they must agree)\n' "$name" "$rc"
    FAILED="$FAILED ${name}(rc-mismatch)"
  else
    printf '  %-26s PASS\n' "$name"
    PASSED="$PASSED $name"
  fi
}

# ---- 1. the data-layer harness (carries the gate-script presence census) ----
DL_OUT=$(bash "$DIR/run-data-layer.sh" 2>&1)
DL_RC=$?
DL_VERDICT=$(printf '%s\n' "$DL_OUT" | grep -oE 'GATE: (PASS|FAIL)' | tail -1)
printf '%s\n' "$DL_OUT" | grep -E 'gate-script census|assertions:|SUMMARY' || true
if [ -z "$DL_VERDICT" ]; then
  echo "  data-layer          : FAIL - produced NO VERDICT (rc=$DL_RC)"
  printf '%s\n' "$DL_OUT" | tail -5 | sed 's/^/      /'
  FAILED="$FAILED data-layer(no-verdict)"
elif [ "$DL_VERDICT" != "GATE: PASS" ] || [ "$DL_RC" -ne 0 ]; then
  echo "  data-layer          : FAIL ($DL_VERDICT, rc=$DL_RC)"
  FAILED="$FAILED data-layer"
else
  echo "  data-layer          : PASS"
  PASSED="$PASSED data-layer"
fi

# ---- 2. static checks: wired, then run, then judged like any gate ----------
# Two manifests, pinned like the gate-script census, so a new check has to be
# placed deliberately. IN_HARNESS entries are NOT run here -- run-data-layer.sh
# runs them as preconditions -- and this block only confirms it still calls them.
STATIC_CHECKS="check-guidance.sh
check-precache.sh"
IN_HARNESS="check-sw-hash.sh
check-version.sh
check-writesites.sh
check-zxing.sh"

for c in $IN_HARNESS; do
  if [ ! -f "$DIR/$c" ]; then
    printf '  %-26s FAIL - missing (the harness runs it)\n' "$c"
    FAILED="$FAILED ${c}(missing)"
  elif ! grep -vE '^\s*#' "$DIR/run-data-layer.sh" | grep -qF "bash \"\$DIR/$c\""; then
    printf '  %-26s FAIL - listed IN_HARNESS, but run-data-layer.sh never calls it\n' "$c"
    FAILED="$FAILED ${c}(not-called)"
  fi
done

for f in "$DIR"/check-*.sh; do
  [ -e "$f" ] || continue
  c=$(basename "$f")
  if ! printf '%s\n' $STATIC_CHECKS $IN_HARNESS | grep -qxF "$c"; then
    printf '  %-26s FAIL - UNWIRED: nothing runs it, so a green suite says nothing about it\n' "$c"
    echo "      Add it to STATIC_CHECKS here, or call it from run-data-layer.sh and add it to IN_HARNESS."
    FAILED="$FAILED ${c}(unwired)"
  fi
done

N_STATIC=0
for c in $STATIC_CHECKS; do
  N_STATIC=$((N_STATIC + 1))
  if [ ! -f "$DIR/$c" ]; then
    printf '  %-26s FAIL - missing\n' "$c"; FAILED="$FAILED ${c}(missing)"; continue
  fi
  OUT=$(leashed bash "$DIR/$c" 2>&1); RC=$?
  judge "$c" "$RC" "$OUT"
done

# ---- 3. every CDP gate, each of which must speak ---------------------------
N_CDP=0
for g in "$DIR"/*-gate.ps1; do
  name=$(basename "$g")
  N_CDP=$((N_CDP + 1))
  if [ ! -f "$g" ]; then
    echo "  ${name}: FAIL - missing"; FAILED="$FAILED ${name}(missing)"; continue
  fi
  OUT=$(leashed powershell.exe -NoProfile -ExecutionPolicy Bypass -File "$g" 2>&1); RC=$?
  judge "$name" "$RC" "$OUT"
done

NP=$(printf '%s\n' $PASSED | grep -c .)
NF=$(printf '%s\n' $FAILED | grep -c .)
TOTAL=$((1 + N_STATIC + N_CDP))
NH=$(printf '%s\n' $IN_HARNESS | grep -c .)
echo "-------------------------------------------------------------------"
echo "passed: $NP   failed: $NF"
echo "counted: 1 harness + $N_STATIC static + $N_CDP CDP = $TOTAL verdicts" \
     "($NH more checks run inside the harness and are part of its verdict)"
if [ -z "$FAILED" ] && [ "$NP" -ne "$TOTAL" ]; then
  # Every judged gate lands in PASSED or FAILED, so this cannot happen unless the
  # counting and the running have drifted apart -- which is what the line is for.
  FAILED=" count-mismatch(passed $NP, counted $TOTAL)"
fi
if [ -n "$FAILED" ]; then
  echo "FAILED:$FAILED"
  echo "SUITE: FAIL"
  exit 1
fi
echo "SUITE: PASS ($NP of $TOTAL produced a verdict, and every verdict was PASS)"
exit 0
