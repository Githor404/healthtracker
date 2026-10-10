#!/usr/bin/env bash
# Re-runnable Phase 0 data-layer gate. Drives headless Chrome/Edge against
# tests/data-layer.test.html (which loads the real ../app.js), extracts the
# per-assertion results, and exits non-zero unless every check passes.
# No Node, no build step — just a browser.
set -uo pipefail

# EVERY EXIT PATH SPEAKS. run-all-gates reads only `GATE: (PASS|FAIL)` and
# scores anything else as PRODUCED NO VERDICT -- so a precondition that
# exited 1 with its own wording turned a real failure into apparent silence.
# "It failed" and "it never reported" send a reader to different places.
speak_fail() { echo "GATE: FAIL"; exit 1; }

DIR=$(cd "$(dirname "$0")" && pwd)
HTML="$DIR/data-layer.test.html"

# GATE-SCRIPT CENSUS -- a precondition, recorded 2026-09-06 after a real loss.
#
# The CDP gates are PowerShell driving headless Chrome with synthetic input
# injection, and that profile matches automation-malware heuristics: Kaspersky
# quarantined bm-slider-gate.ps1 as PDM:Trojan.Win32.Bazon.a mid-session. A
# quarantined gate DOES NOT RUN AND DOES NOT SAY SO -- which is this project's
# recurring failure shape, a check that silently stops checking while everything
# still reports green. The assertion-count pin catches that inside the harness;
# nothing caught it at the SCRIPT level until this.
#
# Pinned as a MANIFEST, not a bare count, for the same reason SE-disclose names
# the leaked phrase rather than reporting a mismatch: "expected 8, found 7"
# starts a hunt, naming the file ends it. A manifest also catches a RENAME, which
# a count cannot see at all.
#
# Adding a gate: add its name here, in the same commit -- deliberately, exactly
# as EXPECTED_ASSERTIONS is re-pinned.
GATE_SCRIPTS="bm-slider-gate.ps1
capture-gate.ps1
capture-outcome-gate.ps1
anti-engagement-gate.ps1
chart-gate.ps1
import-gate.ps1
chip-layout-gate.ps1
collapse-gate.ps1
delete-all-gate.ps1
correction-gate.ps1
corpus-gate.ps1
dayroll-gate.ps1
flow-gate.ps1
font-floor-gate.ps1
identity-search-gate.ps1
jargon-gate.ps1
lab-form-gate.ps1
landing-gate.ps1
night-gate.ps1
offline-gate.ps1
overlay-gate.ps1
page-overflow-gate.ps1
parity-gate.ps1
panel-gate.ps1
potential-gate.ps1
photo-lead-gate.ps1
resolve-gate.ps1
response-gate.ps1
ring-size-gate.ps1
update-gate.ps1"
# DERIVED, not hand-maintained. This was a literal, read by nothing but two
# echo strings -- the real bar is the manifest above versus the files on disk
# (GS_MISSING / GS_EXTRA). Setting it to 21 with 22 gates present changed
# nothing and printed "22 of 21 present, manifest matches", a
# self-contradicting sentence that still passed. A number that looks like a
# bar and enforces nothing is worse than no number: it invites the next
# reader to trust it. Derived from the manifest, and now checked.
EXPECTED_GATE_SCRIPTS=$(printf '%s\n' "$GATE_SCRIPTS" | grep -c .)

GS_MISSING=""
for g in $GATE_SCRIPTS; do [ -f "$DIR/$g" ] || GS_MISSING="$GS_MISSING $g"; done
GS_FOUND=$(ls "$DIR"/*-gate.ps1 2>/dev/null | wc -l | tr -d ' ')
GS_EXTRA=$(ls "$DIR"/*-gate.ps1 2>/dev/null | xargs -n1 basename 2>/dev/null   | grep -vxF "$GATE_SCRIPTS" | tr '
' ' ')

if [ -n "$GS_MISSING" ]; then
  echo "GATE-SCRIPT CENSUS: FAIL -$GS_MISSING missing (expected $EXPECTED_GATE_SCRIPTS, found $GS_FOUND)"
  echo "  A gate script that is absent does not run and does not report."
  echo "  SUSPECT ANTIVIRUS QUARANTINE FIRST: Kaspersky has flagged these as"
  echo "  PDM:Trojan.Win32.Bazon.a -- a behavioural false positive on the CDP profile."
  echo "  Recover (every gate script is committed):"
  for g in $GS_MISSING; do echo "    git checkout -- tests/$g"; done
  echo "  Then confirm the scoped AV exclusion for tests/ is in place on this machine."
  speak_fail
fi
if [ -n "$GS_EXTRA" ]; then
  echo "GATE-SCRIPT CENSUS: FAIL - unpinned gate script(s): $GS_EXTRA"
  echo "  A new gate must join the manifest deliberately, in the same commit that adds it,"
  echo "  so the bar can never move without someone choosing to move it."
  speak_fail
fi
if [ "$GS_FOUND" -ne "$EXPECTED_GATE_SCRIPTS" ]; then
  echo "GATE-SCRIPT CENSUS: FAIL - $GS_FOUND file(s) on disk against $EXPECTED_GATE_SCRIPTS in the manifest"
  echo "  GS_MISSING and GS_EXTRA should have caught this; if they did not, the"
  echo "  census itself is broken and no count below can be trusted."
  speak_fail
fi
echo "gate-script census: $GS_FOUND of $EXPECTED_GATE_SCRIPTS present, manifest matches"

# Phase R (D5/D7): the legacy path must be fully stripped from app.js. Match code
# (the migrator/constant identifiers and quoted 'uha-log-v1' string usage) — a
# doc comment mentioning the removed key in backticks is fine.
STRIP_RE="migrateLegacy|LEGACY_KEY|['\"]uha-log-v1['\"]"
if grep -nE "$STRIP_RE" "$DIR/../app.js" >/dev/null 2>&1; then
  echo "STRIP CHECK: FAIL — legacy code remains in app.js:"
  grep -nE "$STRIP_RE" "$DIR/../app.js"
  speak_fail
fi
echo "strip check: app.js is legacy-free"

# R21/D45 Fork G: the SW must let the BYOK vision call through untouched. A
# cross-origin POST is not cacheable BY DEFAULT, and "by default" is not "never",
# so the bypass is asserted rather than assumed.
if ! grep -q "req.method !== 'GET') return" "$DIR/../sw.js"; then
  echo "SW BYPASS: FAIL - the non-GET early return is gone; the vision POST could be intercepted"; speak_fail
fi
if ! grep -q "url.origin !== self.location.origin) return" "$DIR/../sw.js"; then
  echo "SW BYPASS: FAIL - the cross-origin passthrough is gone"; speak_fail
fi
if ! grep -q "Fork G" "$DIR/../sw.js"; then
  echo "SW BYPASS: FAIL - the bypass is no longer named as deliberate (D45 Fork G)"; speak_fail
fi
echo "sw bypass: the BYOK call passes through uncached (non-GET + cross-origin)"

# SW cache name must track the shell (D6): fail if sw.js SHELL_HASH is stale, so
# a shell change can never ship without the SW seeing it.
if ! bash "$DIR/check-sw-hash.sh" >/dev/null 2>&1; then
  bash "$DIR/check-sw-hash.sh"
  echo "SW-HASH CHECK: FAIL"
  speak_fail
fi
echo "sw-hash check: sw.js cache name tracks the shell"

# ZXing sourcing drift (D15): the ZXING single-SoT constant's SRI hash must match
# the pinned CDN file (online), and version/host stay consistent (offline). A
# stale hash is a silent "scanner won't load" -- same class as the SW-hash trap.
if ! bash "$DIR/check-zxing.sh"; then
  echo "ZXING CHECK: FAIL"
  speak_fail
fi

# APP_VERSION drift (D6 force-and-notify): APP_VERSION must carry a changelog line
# and bump whenever the shell changes, so an update can't ship without a notice.
if ! bash "$DIR/check-version.sh"; then
  echo "VERSION CHECK: FAIL"
  speak_fail
fi

# Write-site census (D29): every record-write must be a REGISTERED site, classified
# stamped-with-the-tz-offset or exempt-with-a-reason. A new write site fails here
# rather than silently joining unstamped.
if ! bash "$DIR/check-writesites.sh"; then
  echo "WRITESITES CHECK: FAIL"
  exit 1
fi

# Convert the POSIX path to a file:// URL Chrome understands on Windows.
if command -v cygpath >/dev/null 2>&1; then
  URL="file:///$(cygpath -m "$HTML")"
else
  URL="file:///$(printf '%s' "$HTML" | sed -E 's#^/([a-zA-Z])/#\U\1:/#')"
fi

BROWSER=""
for c in \
  "/c/Program Files/Google/Chrome/Application/chrome.exe" \
  "/c/Program Files (x86)/Google/Chrome/Application/chrome.exe" \
  "/c/Program Files (x86)/Microsoft/Edge/Application/msedge.exe" \
  "/c/Program Files/Microsoft/Edge/Application/msedge.exe"; do
  if [ -x "$c" ]; then BROWSER="$c"; break; fi
done
if [ -z "$BROWSER" ]; then echo "ERROR: no headless Chrome/Edge found" >&2; exit 2; fi

# --virtual-time-budget: the D30 cases load the SHIPPED index.html into an iframe,
# so the dump must wait for that async load rather than snapshotting mid-flight.
OUT=$("$BROWSER" --headless --disable-gpu --no-sandbox --allow-file-access-from-files \
  --virtual-time-budget=45000 --dump-dom "$URL" 2>/dev/null \
  | grep -oE '<p class="(r|s)">[^<]*</p>' | sed -E 's/<[^>]+>//g')

echo "$OUT"
echo "-----------------------------------------"

# ASSERTION-COUNT DISCIPLINE (ruled after the v0.11.0 masked-exception defect).
# A synchronous throw used to abort the suite while still printing a green-looking
# SUMMARY with a silently reduced count -- ~40 D35 assertions never ran and nobody
# noticed. The harness now records such a throw as a failure, and this pin is the
# second line of defence: the EXECUTED count must match the pinned number, so any
# silent drop fails the gate rather than passing quietly.
#
# Bump EXPECTED_ASSERTIONS deliberately, in the same commit that adds or removes
# cases, and state the delta in the gate report.
#
# AUTHORED is a static lower-bound cross-check only: it counts source LINES
# containing a res( call, so multi-line calls and helper reuse make it an
# approximation, not an equality. The PIN is the enforcing mechanism.
# H31: 2631 -> 2638, delta +7 -- the correction hint ON THE WIRE (the body is the
# template plus the hint; it names both words; it says they are hints; the
# appended slice IS the hint; and that slice carries no corpus id and no macros),
# plus the explicit statement that a user with no corrections has an empty hint,
# which is what makes R21-parity's existing assertion hold unchanged.
# R159.1/A3: 2638 -> 2642, delta +4. Two assertions named a surface BY CLASS
# (`.goalcov`) that this slice renamed to `.dfigcov`; one failed loudly and one
# -- its control -- went on PASSING while measuring nothing, because no element
# carries a `goalcov` any more and `indexOf < 0` had become unfalsifiable. The
# re-point adds the positional claim the words had always made and no assertion
# had ever tested (the sentence renders ABOVE the goal cells) plus a planted
# reversal to prove that test can fail: +2. And R33-badge, re-pinned to the
# ruling that moved the leftovers list into the quick-add sheet, now pins three
# claims where it pinned one -- the day asks quietly, the day does not carry the
# list, the sheet does: +2. Plus one locator: the order test needed a fixture that
# CONFIGURES a goal, because this one boots with none and `above` needs both ends
# present -- the plant proved the test could fail and nothing proved it could
# pass, which is the defect this re-point exists to close, one level up: +1.
# R159.1/A4: 2643 -> 2644, delta +1 net. D130-row pinned three claims about the
# five-badge row the ruling removes. The claim that it NAMED five things goes with
# the row (-1); the other two were never about those words -- targets-not-a-menu
# and no-streak-no-distance -- and now bind the replacement. Added: the five words
# are ABSENT from the rendered day, and the replacement is PRESENT (+2), so "the
# badges are gone" cannot be satisfied by a blank screen.
# B1: 2644 -> 2661, delta +17. The meal tag, measured before the rule was written
# (37 of 54 clock-comparable items in the real log carried a tag the clock
# contradicts) and then pinned at every creation path: the pure rule and its three
# edges (a choice wins, a non-meal is not a choice, no clock means `snack`), the
# reported defect reproduced on a clock pinned at 10:51 (draft, day record, and the
# one header the day draws), the model's guess kept beside the derived tag and said
# on the draft, scan / manual / preset each with a control proving the assertion is
# about the DEFAULT and not about overriding a choice, and the leftover -- the case
# the plate's tag got most wrong -- with its past-day control.
# B2: 2661 -> 2664, delta +3. The now-hand's inner end, pinned where the fix put
# it: CAL_RING_STROKE against the stroke-width the SHIPPED stylesheet actually
# paints (one number, two files, and only a test can keep them equal), the hand
# stopping at the calorie arc's outer edge, and that this is strictly further out
# than the `rim * RING_CENTER_R` bound it replaced. The collision itself is the
# ring gate's, swept over all 1440 minutes.
EXPECTED_ASSERTIONS=2664
TOTAL=$(printf '%s\n' "$OUT" | grep -oE 'SUMMARY [0-9]+/[0-9]+' | head -1 | sed -E 's#.*/##')
AUTHORED=$(grep -cE '(^|[^A-Za-z_.])res\(' "$HTML")
echo "assertions: executed ${TOTAL:-0} · pinned $EXPECTED_ASSERTIONS · authored-lines(static lower bound) $AUTHORED"
if [ -z "$TOTAL" ]; then
  echo "ASSERTION COUNT: FAIL - no SUMMARY line (the suite did not finish)"
  echo "GATE: FAIL"
  exit 1
fi
if [ "$TOTAL" -ne "$EXPECTED_ASSERTIONS" ]; then
  echo "ASSERTION COUNT: FAIL - executed $TOTAL, pinned $EXPECTED_ASSERTIONS (delta $((TOTAL - EXPECTED_ASSERTIONS)))"
  echo "  A DROP means cases stopped running - find out why before re-pinning."
  echo "  A RISE means cases were added - re-pin deliberately in the same commit."
  echo "GATE: FAIL"
  exit 1
fi
if printf '%s\n' "$OUT" | grep -q 'ALL PASS'; then
  echo "GATE: PASS"
  exit 0
fi
echo "GATE: FAIL"
exit 1
