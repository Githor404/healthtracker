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

# ---- 2. every CDP gate, each of which must speak ---------------------------
for g in "$DIR"/*-gate.ps1; do
  name=$(basename "$g")
  if [ ! -f "$g" ]; then
    echo "  ${name}: FAIL - missing"; FAILED="$FAILED ${name}(missing)"; continue
  fi
  if [ "$have_timeout" -eq 1 ]; then
    OUT=$(timeout "$GATE_TIMEOUT" powershell.exe -NoProfile -ExecutionPolicy Bypass -File "$g" 2>&1); RC=$?
  else
    OUT=$(powershell.exe -NoProfile -ExecutionPolicy Bypass -File "$g" 2>&1); RC=$?
  fi
  VERDICT=$(printf '%s\n' "$OUT" | grep -oE 'GATE: (PASS|FAIL)' | tail -1)

  if [ "$RC" -eq 124 ]; then
    # Timed out: no verdict will ever arrive.
    printf '  %-26s FAIL - HUNG, no verdict within %ss\n' "$name" "$GATE_TIMEOUT"
    FAILED="$FAILED ${name}(hung)"
  elif [ -z "$VERDICT" ]; then
    # PRESENT BUT SPEECHLESS -- the #4 shape. The file exists and the census is
    # satisfied; it simply never reported. That is a failure, never silence.
    printf '  %-26s FAIL - PRODUCED NO VERDICT (rc=%s)\n' "$name" "$RC"
    printf '%s\n' "$OUT" | grep -viE '^\s*$' | tail -3 | sed 's/^/      /'
    echo "      If this reads 'Access is denied' with the file intact, suspect the"
    echo "      ANTIVIRUS proactive-defence module, not the script (tests/README.md)."
    FAILED="$FAILED ${name}(no-verdict)"
  elif [ "$VERDICT" != "GATE: PASS" ]; then
    printf '  %-26s FAIL\n' "$name"
    printf '%s\n' "$OUT" | grep -E '\->\s*False|FAIL' | tail -4 | sed 's/^/      /'
    FAILED="$FAILED $name"
  elif [ "$RC" -ne 0 ]; then
    # Said PASS but exited non-zero: the two disagree, so neither is trusted.
    printf '  %-26s FAIL - verdict PASS but exit %s (they must agree)\n' "$name" "$RC"
    FAILED="$FAILED ${name}(rc-mismatch)"
  else
    printf '  %-26s PASS\n' "$name"
    PASSED="$PASSED $name"
  fi
done

NP=$(printf '%s\n' $PASSED | grep -c .)
NF=$(printf '%s\n' $FAILED | grep -c .)
echo "-------------------------------------------------------------------"
echo "passed: $NP   failed: $NF"
if [ -n "$FAILED" ]; then
  echo "FAILED:$FAILED"
  echo "SUITE: FAIL"
  exit 1
fi
echo "SUITE: PASS ($NP of $NP produced a verdict, and every verdict was PASS)"
exit 0
