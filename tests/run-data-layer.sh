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
GATE_SCRIPTS="backup-gate.ps1
bpchart-gate.ps1
bm-slider-gate.ps1
capture-gate.ps1
capture-outcome-gate.ps1
anti-engagement-gate.ps1
chart-gate.ps1
import-gate.ps1
chip-layout-gate.ps1
close-gate.ps1
cold-start-gate.ps1
dayclose-gate.ps1
perf-gate.ps1
collapse-gate.ps1
delete-all-gate.ps1
correction-gate.ps1
corpus-cache-gate.ps1
corpus-gate.ps1
dayroll-gate.ps1
drinkfree-gate.ps1
elite-gate.ps1
entry-gate.ps1
fdc-gate.ps1
flow-gate.ps1
font-floor-gate.ps1
forms-gate.ps1
identity-search-gate.ps1
jargon-gate.ps1
lab-form-gate.ps1
landing-gate.ps1
lookup-gate.ps1
myfood-gate.ps1
night-gate.ps1
noauto-gate.ps1
offline-gate.ps1
onedoor-gate.ps1
overlay-gate.ps1
page-overflow-gate.ps1
parity-gate.ps1
panel-gate.ps1
potential-gate.ps1
precedence-gate.ps1
photo-lead-gate.ps1
rank-gate.ps1
resolve-gate.ps1
response-gate.ps1
review-gate.ps1
ring-size-gate.ps1
searchmine-gate.ps1
sensor-gate.ps1
served-gate.ps1
stackcheck-gate.ps1
stacktotals-gate.ps1
update-gate.ps1
weekly-gate.ps1"
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
# R221/5: the same lean flags every gate's browser now starts with (background
# services off; nothing that changes rendering).
OUT=$("$BROWSER" --headless --disable-gpu --no-sandbox --allow-file-access-from-files \
  --disable-extensions --disable-background-networking --disable-component-update \
  --disable-sync --disable-default-apps --mute-audio \
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
# B3: 2664 -> 2673, delta +9. Whole-number calories: the helper and its coercion,
# the by-key form that rounds kcal and leaves grams alone, and then the PROPERTY on
# the rendered day rather than on the helper -- a fixture whose group total is a
# real fraction (350.81), the header reading 351, no decimal in any calorie figure
# anywhere on the day, and the ring centre agreeing. Plus the half a display change
# could quietly break: the store and the export keep every digit.
# R168: 2673 -> 2701, delta +28. The daily stack's contract and its one write:
# schema v13 with a structural-passthrough migrator, the stack shipping empty and
# surviving an allowlist-rebuild normaliser, the item contract field by field
# (including that the bioactive TAG rides on a FOOD item, which is ruling D-C),
# the IU table that REFUSES what it has no factor for, and then ruling D-D end to
# end: every enabled row ticked on open, one confirm writing only the ticked ones,
# the unticked ones absent from BOTH stores, one timestamp across the lot, no
# `_auto`, D120 asserted in both directions, and an all-unticked confirm refused
# rather than succeeding emptily.
# R168/2: 2701 -> 2718, delta +17. The confirm sheet asserted on the RENDERED
# surface (the B3 lesson: three correct helper assertions passed while the screen
# still showed a decimal) -- all ticked on open, the button stating its own count,
# unticking visibly dimming the row, and an empty stack drawing nothing. Plus the
# app's FIRST cited intake figure: flagged above the figure and not at or under
# it, absent for a nutrient with no cited limit, carrying org + source +
# POPULATION, containing no instruction or verdict, offering the reading instead,
# rendering beside its item, and VANISHING when the citation is stripped -- each
# with a control so none of them can pass on an empty string.
# COMBOS: 2718 -> 2746, delta +28. Schema v14 and its passthrough migrator; the
# combo and part contracts; the third provenance as ALL-THREE-OR-NOTHING with the
# retrieval date shown; refAtGrams scaling linearly and DROPPING a ref with no
# basis; then the ruling itself -- one tap writing N separate items at one
# timestamp, the coffee carrying its caffeine and the dairy its own fat, neither
# inheriting the other's provenance, and NO composite record anywhere (asserted by
# absence, so Fork 3's intersection has nothing to apply to); the stepper
# multiplying every part with no grams on the plan; and the frequency list
# collapsing occasions into one row that survives the combo being deleted.
# +1 on the re-run: the undeclared-micro assertion split in two once measurement
# showed the mechanism was PRESERVATION and not dropping -- the key survives, and
# a second assertion carries the reason nothing renders it.
# COMBOS/2: 2747 -> 2758, delta +11. The surface, and the silent no-op it closes:
# a combo row has no `item` (the point of it) and quickPlan's `!row.item` guard
# returned null there, so quickStepHTML rendered nothing and TAPPING A COMBO DID
# NOTHING AT ALL -- the shape that took four rounds of diagnostics to name when
# `.qrow` did it. Now: the row is pickable, the stepper reads as a MULTIPLIER with
# no grams box, 2x shows every part at its own doubled portion, a published part
# shows org + source + retrieval date WITH the values, a part whose matched row
# differs says which row it matched, the write goes through logCombo rather than a
# second copy, the multiplier reaches the ref, and the pick clears afterwards.
# +1: an H31-wire PRECONDITION naming the cause. The block failed four assertions
# at once inside the full suite while passing three times standalone, and all four
# compared a string to the template -- so the log showed four mismatches and not
# the reason, which was that the capture made no request and the body was ''.
# COMBOS/3: 2759 -> 2779, delta +20. "Save as combo" from items already logged:
# the parts take their portions AND their provenance from the items (a frozen ref
# on one, a published citation on the other), the meal is deliberately NOT copied
# because B1 ruled the clock decides, the standing supplement is refused as a
# part, and an empty or unnamed selection is refused by name. Then the editor,
# which is the same object: rename, delete, and adjust-a-portion moving the
# macros, the micros AND the ref together -- buildRepeatItem's old trap was
# moving the match and leaving the macros behind -- with a no-basis part refused
# rather than treated as 100 g, and deletion leaving the logged items alone.
# Finally the surface: off by default, stating what it will save before the tap,
# ticks appearing only while selecting and not outliving the save.
# ONE DOOR / 2: 2796 -> 2830, delta +34 (33 new, and one /1 pin MOVED rather than
# added: it asserted "+ New combo" was absent while it had nothing to open). The
# typeahead as a pure function over an index built in the harness -- with the
# matcher's own zero rows for a half-typed word as the control, a finished word
# answered by the matcher byte for byte, and a row that misses the half-typed
# word ranked beneath rather than dropped. Ruling (a) in its one function: the
# row's macros as the item's OWN numbers at the typed grams, cited, eyeballed,
# micros left in ref.v, an absent macro left off, a row with no energy refused,
# and the whole item surviving the normaliser. Then the builder: a matched part
# owed an amount rather than given one, a typed part bringing no caffeine, the
# total saying "from 1 of 2 parts" for both figures, a save with NOTHING logged
# first, and the saved combo logging at 2x with the cited caffeine doubled.
# v0.85.0: 2830 -> 2871, delta +41.
# R187, +8 on ONE DOOR/2: the ranking found by LOOKING at it -- a row holding the
# typed word as a whole token leads (milk before milkfish, egg before eggplant) and
# the top row does not change when the word is finished; and the draft -- kept
# across the back link and a closed sheet, said on the root, ended only by Save or
# Start over. Two /2 pins MOVED rather than added: 'going back ABANDONS the draft'
# (ruled against), and a ranking case whose two rows each answered one word and so
# proved nothing about the rule it named.
# R186, +33: every wear time cited, with the 15-day caveat beside its number;
# `device` surviving the normaliser and never given to a record without one; the
# countdown at pinned times -- Day 1, Day 3, Day 10, grace with hours, past, the
# 15-day type as the control, no 'of N' for an untyped entry, no hours for an
# untimed one, a newer change resetting it; the first tap asking and writing
# nothing; the same arm deduped, the other arm correcting through editRecord, a
# tap outside the window writing (the control); and the user's own edit keeping
# 'no type was recorded' as '' because undefined does not survive JSON.
# R189 (the source fix only): +3. A searched item's source is `corpus`, with a word,
# through the normaliser; and in a combo the matched and typed parts keep their own.
# R189, v0.86.0: 2874 -> 2909, delta +35. The decision as a pure function over a
# refuse table built in the harness -- wings corrected, a meat-only row never, a
# breast and a banana and an egg offered and not applied, 'boneless' in the
# identification, the user's own earlier answer winning both ways, no figure on a
# corpus with no table; the stored form dropped entire without its source; then
# the real plate path -- 120 g served, 74.4 g edible, half eaten is 37.2 g and
# 111.6 cal, the day total moving by that and not by 360, the remainder measured
# against the edible part, the meal event the response reader takes holding eaten
# grams; the afterwards control (all, a quarter, typed grams, capped, undoable);
# 'it was boneless' putting the bone back while the half stays a half, remembered,
# and undone back to no memory; and Search writing through the same plate, its
# undo taking the plate with it, a banana and an egg by weight counted whole.
# R195, v0.87.0: 2909 -> 2906, delta -3, and it is a DROP ON PURPOSE. The day's
# 'Save as combo' selection panel is removed (ruled: one door), and its six
# assertions with it -- all six passed on the build reported from the device as a
# dead end, because they asserted the bar and the mode and never that a tick was
# anywhere a person could reach. Three replace them: the day offers no such link
# and draws no panel or ticks, the mode's functions are gone rather than hidden,
# and the one door is still there.
# R192, v0.88.0: +6. The one-tap Red light preset: 15 before anything is logged,
# one event through addSignal at quick provenance, an unknown type refused, Undo,
# and the minutes remembered from the log rather than stored.
# R189/2, v0.89.0: +13. "Ate:" on any item with a weight, by ATTACHING a plate when
# it is first reduced: offering it writes nothing, "all" on an untouched item makes
# no plate, a half moves the grams, the macros AND the label micros, the plate is an
# entry plate at the item's own time and offset, undo leaves no plate behind, and an
# item with no weight is refused. And the entry plate: removing a searched food
# takes its plate (v0.86.0 offered it back as leftovers), undo restores both, and a
# photographed plate still stands -- the control.
# E-LITE and R197, v0.91.0: 2925 -> 2963, delta +38. The rule as a pure function --
# the threshold either side, in both units, a hole or a unit change inside the
# hour claiming nothing, a plateau as one rise -- and the defect its own first run
# found, pinned: a rise starts where the climb starts and peaks at its real peak.
# Then a day of three climbs: the 4 h window to the minute either side, the eaten
# basis (a served plate explains nothing), the ruled order of what is offered for
# a sudden drop, a sensor's first day, logged and assumed sleep, waking; steps
# known, unknown, and never confused; steps from an Apple Health file, for
# glucose's days only and one source; the answer stored as a timeline record,
# replaced, undone, dismissed, refused where there is no rise; the mark on the
# chart; and a surface with no probability, likelihood, score or cause in it.
# Two R189/2 pins moved for R197/3: a weighed serving reads "weighed 200 g".
# R198 / R199, v0.92.0: 2963 -> 2995, delta +32, and two pins MOVED. The search
# ranking on a fixture: plural and singular through matchFold and nothing wider,
# with the control that an index built without the fold keeps them apart; coffee
# before Coffee cake, Milk before Milk shake before Crackers-milk before milkfish,
# Egg before Egg substitute before Eggplant, and "Frozen yogurts" not headed
# yogurt; the same order half-typed and finished. What was logged before leads,
# but not past a row answering more of the words. Combo editing: opened in the
# builder, an untouched part saved back exactly, an amount scaling calories,
# label micros and cited values together, a part with no amount refused a
# resize, in-place save under the same id, THE PAST LOG BYTE-IDENTICAL, the next
# log at the new amount, delete and both undos. "Ate:" at save: one mechanism,
# one Undo for the item and its plate, nothing extra for "all", refused without
# a weight; and an entry plate with nothing eaten from it is never offered.
# MOVED: two ONE-DOOR/2 pins compared the typeahead's rows to the matcher's byte
# for byte. The typeahead's rows now carry their own ranking facts, so the bytes
# differ by design; what the pins protected -- the same rows at the same score --
# is asserted directly.
# R200, v0.93.0: 2995 -> 3007, delta +12. A trade name read off the name, and
# its control (BBQ, DHA, ARA, NFS, USDA are not brands); generic before branded,
# with a brand that is asked for still found; the earlier part of a name, and the
# tie it leaves between the two sardine rows said as a tie; one list for two
# spellings, whole and half-typed; the table's size; the control that the
# identity matcher still reads the word as written; and R198's four orders
# unmoved.
# R202 / R203 / R204, v0.94.0: 3007 -> 3043, delta +36, with about twenty cases
# REWRITTEN TO ASSERT THE OPPOSITE of what they held. The old cases said: an
# enabled supplement is injected at boot, at day creation and on a paste; it is
# flagged, non-deletable, non-editable and refused as a combo part. Each now
# says: boot, day creation, a paste and a simulated midnight write NOTHING; the
# setting became one stack item; the old entry is ordinary, marked, timeless,
# deletable with Undo, and still counted on its day. S1-S7 (the setting's own
# behaviour) are replaced by the stack editor's: add, convert-or-refuse, edit in
# place, a food as a food-database part at typed grams, enable, remove with
# Undo, the tap logging N and N-1, and ONE Undo for the whole confirm. New: the
# day's groups (the reported day reads 3 items at 23:02; a supplement group of
# its own; the split at more than three hours with the exactly-three-hours
# control; a range on a long group). Every schema pin moved 14 -> 15 and the
# forward guard 15 -> 16; the migration-chain census gained its step.
# R207 / R208, v0.95.0: 3043 -> 3068, delta +25. A logged dose carries what it
# counts toward, and an unmapped one carries nothing; the day's doses summed by
# nutrient; NO calories and no day item; the stack as a third provenance in the
# panel's rollup, with the control that the labelled figure is unmoved; the
# panel's own line. The ruled scenarios: vitamin D 40 food + 75 stack flagged at
# 115 on the total; magnesium 400 food + 300 stack NOT flagged; stack magnesium
# 400 flagged at 350, supplemental only. The flag's sentence: what was summed,
# the source, the scope, no borrowed line, no instruction. A day item logged as
# a supplement counts as supplemental. Scope is a field: a limit without one, or
# without a citation, flags nothing. The record boundary keeps the map on a dose
# only. The editor suggests and never sets, with controls for a name that holds
# no nutrient and a word that merely contains one.
# R213, v0.96.0: 3068 -> 3102, delta +34. KINDS: three, supplement the default,
# a stored "dose" reads as one; each row leads with its word; medication distinct
# on the dose record; a food keeps its calories; the render-only relabel of
# earlier entries and its controls (a dose typed into the form, ordinary food);
# rendering changes no record. THE NOTE: collapsed in the markup, labelled, the
# sentence inside; my amount first on an item's; one in the editor, on the Log
# sheet and in the panel. THE BACKUP: the file's name, "none yet", "Last
# backup", no urging, the key removed by delete-everything, the restore boundary
# accepting it. MY FOODS: ships empty; per serving stored per 100 g; absent not
# zero; five refusals; found by name; a part in the combo part's shape with no
# citation; saved in the stack, logged, IN THE DAY'S TOTALS, "from label"; as a
# combo part; listed first where a food is searched; remove with Undo changing
# nothing already saved; the boundary.
# R215, v0.97.0: 3102 -> 3132, delta +30. THE D113 AUTO-CLOSE: three cases
# REVERSED in place, same fixture, opposite outcome (still open past 24h with a
# pattern; no inferred night written; the API gone) -- net 0. NEW: the one-tap
# section in + Log and no drink kinds; the sensor line read-only; a stated
# bedtime, last night's when later than now, with Undo; My usual offered from
# eight nights and NOT before it has come; taken, stored as accepted; the wake
# read through the night's own record and never an inferred one; a second start
# refused; practice start and end with Undo; the ring read-only; the regimen
# line and its checklist in + Log; Your drinks from the log, last size, kept out
# of Your top, one tap adding its calories, Undo, the empty block; the old
# badge label; the night summary naming both; adjusted normalised, said,
# round-tripped; corpus kept only with a citation.
# R221, v0.98.0: 3132 -> 3142, delta +10 (the tenth: the category orders WITHIN a tier of words answered). WATER: two taps are two entries and the
# day is the old figure plus them; deleting one takes 0.5 off; its Undo; clear
# day takes the entries and its Undo puts them back; water is an event in litres.
# DRINKS FIRST: the stable partition; no categories, no reorder; both hashes, and
# a stored corpus without them is not current. (One run of this re-pin hung at
# the 35 s chain timeout and passed whole on the next -- the intermittent D110
# names, recorded here so a second sighting is countable.)
# R223, v0.99.0: 3142 -> 3146, delta +4. The big sleep button: Going to sleep,
# leading the pane and the only sleep control; Woke - end sleep with the hours;
# the ring detail without close. The taps are entry-gate's.
# R225, v0.100.0: 3146 -> 3158, delta +12 (the twelfth: carbs all equal is said as such). The review on a hand-computed curve:
# iAUC 90 inside the response; similar median/range/n at the floor; by carbs
# 30-50 g, n 3; below the floor said with n; not clean both ways, not compared;
# a gap -> not judged with the reason; the expected box; no verdict words;
# Spearman incl. ties; nothing stored.
# R227.1, v0.101.0 (schema v16): 3158 -> 3167, delta +9. The export carries the
# streams exactly, with provenance, in one compact line; export -> wipe -> restore
# byte-identical, and a byte-identical re-export; a v15 file leaves the device's
# glucose alone; the boundary rebuilds a hostile stream; v15->v16 is the version
# only; the file name says v16. (34 earlier cases moved 15 -> 16 / 16 -> 17, and
# H19's 'export carries no glucose' was reversed by ruling -- same count.)
# R229, v0.102.0: 3167 -> 3178, delta +11 (ten sitting cases + cancel-before-send, the app bug D110's hang exposed). The sitting: three dinner items and a
# snack 15 min later are one; any id resolves to it; carbs summed; clean only by
# food outside it; a coffee alone is a sitting of one; one block on the lead
# group; the link; R228's no-glucose-yet with last import and why?; stops at;
# nothing before glucose began.
# 3178 -> 3200 (v0.103.0, R226 + R230): +22 -- rewards ship off; the no-drinks
# mark is an explicit zero, once, distinct from missing in the export; a drink
# on a marked day asks; Keep is stored; the mark deletes; 4 of 7 with unmarked
# days counted; the month out of the days so far; the run with and without
# today; counts off/on/off with every mark kept; the fasted span 800 min with its
# words; the arc on both days; the stop ends the eating window; a repeated stop
# is one fast; "from last food" without a stop; E-lite offers food last after a
# stop; its context names the stop, and drops it once food follows.
# 3200 -> 3203 (R232, same release): the mark is ALCOHOL only -- sparkling water
# (source 0 g) asks nothing; a drink no source speaks for is asked once and the
# answer is remembered and exported; white wine (source > 0) asks.
# 3203 -> 3221 (v0.104.0, R233.1 + R234 + R237): +18 -- the precedence rule case
# by case (row beats estimate; the user's set and typed values win; an empty form
# takes the row; the row at the item's grams; estimate alone; nothing); a v16
# file restored is recomputed and each change keeps what it was; a repeat counts
# the same; a v17 round trip is byte-identical (which found normalizeRef turning a
# null distance into 0); boot recomputes and keeps the v16 blob first; adjusted
# untouched; a correction suggests at the new grams; provisional counting; the
# day's not-counted line; confirm; nothing-to-suggest stays uncounted.
# +1 (same release): a correction made on a plate is learned (C1/C3).
# 3222 -> 3231 (v0.105.0, R242/A): +9 -- the one rescale (halves, keeps the
# original, three no-basis policies) and every path calling it with no copy of
# its own; "Save this meal as a combo" prefills two parts, writes nothing, and
# never replaces an open draft; its button is on the meal block; "Daily stack";
# the update notice one line until tapped.
# 3231 -> 3252 (v0.106.0, R242/B): +21 -- USDA FoodData Central: a survey food and
# a packaged one parse into rows under their own namespace and the corpus slots;
# "less than" and %DV zeros are dropped, a stated 0 kept; no kcal / wrong type /
# no id / no name is not offered; the citation names source, kind, id, published
# and retrieved dates; the freeze, the restore boundary and the precedence rule
# take the row unchanged; no key says so with no button; a wrong key is refused;
# the key is on the device only, masked, in neither log nor export; the offer is a
# button until tapped; "None of these fits" and the estimate come before the rows;
# kinds and macros on every row; refusals named; Remove key; a memory proposal
# never carries an FDC id into the shipped file; corrections keep the namespace
# and take the numbers from the earlier item's ref; the ruled constants.
# 3252 -> 3263 (v0.107.0, C + R254): +11 -- Search offers foods logged before with no
# database row (newest first, one per name, at most three; matched items, stack
# entries and the user's own foods are not repeated there; drinks only in Log a
# drink); Your foods lead; a picked food opens at its serving and logs the
# user's numbers; one tap logs an earlier unmatched food again as last time.
# R254: an amount edited first is the amount logged, re-expressed; a food with
# no numbers is never re-logged by its row -- it opens the picker, carrying its
# grams; only "Log without nutrition" saves it with none; the past is untouched;
# a database row logged before is not taken for a my-food (suite run 1).
# 3263 -> 3278 (v0.108.0, R246 Part 1): +15 -- the stack's untick-then-confirm
# sheet is replaced (four of its cases go): collapsed to one line with Took all;
# rows unchecked until taken; one tap = taken now at the usual dose, linked to its
# stack item; an edited dose and time are stated by the user and survive the
# restore boundary, a vitamin re-expressed and another unit counting toward
# nothing; a food's amount is its grams; the export says taken / not taken; uncheck
# with Undo; Took all then uncheck one -> N-1; an old sheet's dose matched by name;
# an item never taken still reads "not taken" (found by stackcheck-gate).
# 3278 -> 3296 (v0.109.0, R255): +18 -- each stack item's added_on and the rule
# that set it (created / logged / auto / unknown), backfilled once and on restore;
# an item added today reads "not in stack yet" yesterday, on the sheet and in the
# backup; a removed item kept with removed_on.
# 3296 -> 3310 (v0.109.0, R256): +14 -- every switch of a stack item's include
# box with its time (off 09:00 / on 15:30 the same day both kept); a day ended off
# reads "switched off", a partial day shows its times; the backup lists the events.
# 3310 -> 3320 (v0.110.0, R251.2): +10 -- blood pressure as one chart: pairing at
# true times, the readout, gaps not joined, 135/85 labelled with both editions
# cited, no verdict, the nearest reading picked, fewer than three in words.
# 3320 -> 3344 (v0.111.0, R265.1 + R262): +24 -- fasting by one 12 h rule (12 h
# exactly is a fast, 11 h 59 m is not; from a Stopped eating; green/orange on the
# ring; nothing asked, D22's question retired), and the weekly review: Monday
# weeks, the pairwise probability with n 5 a side and its words, the meal and
# fasting numbers on a fixture, three rings with sleep hidden, nothing stored,
# the optional notice. Retired cases (pending, resolve, figure-and-ground) were
# rewritten in place, not dropped.
# 3344 -> 3357 (v0.111.0, R269): +13 -- a zero nobody measured is not counted and
# ends a fast (a row or a label that says 0 does not); no fast of 48 h or more
# (47 h is one, 48 h and 60 h are unlogged gaps); the not-counted past is
# suggested from the user's own later choice at its own grams, on restore and on
# boot, once, keeping what it was. R181-eatring repointed in place (the 78 h gap
# draws nothing now).
# 3357 -> 3369 (v0.111.0, R271): +12 -- R269's suggestion is a reading, never
# stored: boot, a save for another reason, the export and a restore all keep the
# wines exactly as logged, while the screen counts them provisionally and says
# which entry the suggestion came from; a user's confirm stores that one. A scanned
# label that prints 0 kcal is a known 0 ("Diet drink A": counted, a fast kept); a
# label with no energy figure is not (control), and the flag round-trips.
EXPECTED_ASSERTIONS=3393
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
