#!/usr/bin/env bash
# R320 -- EVERY WAIT IS A WAIT ON A CONDITION, AND NOTHING TAPS OR MEASURES BEFORE ONE.
# stackadd-gate was written after the R283 sweep and still tapped without waiting for the
# screen it tapped: green alone, red in the suite. This reads every *-gate.ps1 and fails,
# by file and line, on a Start-Sleep outside a polling loop, on input sent with no Wait*
# before it, and on a measurement after a viewport or colour-scheme change with no Wait*
# between. tests/gate_waits.py holds the rules and runs a planted control first.
#
# Exit 0 PASS, 1 FAIL.
set -uo pipefail
DIR=$(cd "$(dirname "$0")" && pwd)
python -I "$DIR/gate_waits.py"
