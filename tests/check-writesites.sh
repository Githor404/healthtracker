#!/usr/bin/env bash
# D29 write-site census. The creation-path sweep asserts that every write site is
# either STAMPED with the device tz offset or DELIBERATELY EXEMPT -- but a
# behavioral test can only check the sites it knows about. This is the static half:
# it enumerates every record-write into a persisted store and fails if the set
# drifts from the pinned manifest, so a NEW write site cannot silently join
# unstamped. Same idiom as check-sw-hash / the legacy strip check.
#
# On failure: add the new site to the manifest below AND to the D29 sweep in
# DECISIONS.md, classified stamped or exempt-with-a-reason. Never just re-pin.
set -uo pipefail

DIR=$(cd "$(dirname "$0")/.." && pwd)
cd "$DIR"

# ---- STORE COVERAGE (D83) -----------------------------------------------------
# The write pattern used to be ONE hand-written regex covering the stores someone
# remembered. R33 added `plates` and nobody added it here, so a new plate write site
# would have joined unstamped and passed -- not a defect on the day, a defect the
# NEXT plate-writing slice would have created. That is fixed by CATEGORY, not by
# adding one alternation: the store list is read from emptyState() in app.js, and
# every store must be classified below. A store the app gains fails this check until
# someone decides whether it holds records.
#
# RECORD stores, each with the pattern(s) that find a record being created in it:
STORE_PATTERNS="days|\.items\.push\(
priceLog|\.entries\.push\(
plates|plates\[[^]]+\][[:space:]]*=[^=]
meds|meds\[[^]]+\][[:space:]]*=[^=]
meds|\.fills\.push\(
timeline|timeline\[[^]]+\][^;]*\.push\(
fastLog|fastLog\[[^]]+\][[:space:]]*=[^=]
regimens|\.log\[[^]]+\]\[[^]]+\][[:space:]]*=[^=]
scans|scans\.push\("
# NOT record stores, with the reason:
#   version, current -- scalars about the blob, not records;
#   settings         -- configuration and templates (goals, presets, units), which
#                       describe how to record, not what happened;
#   labels           -- H5 label DOCUMENTS fetched from openFDA. They are not
#                       records of anything the user did: each carries the source's
#                       own dates and the retrieval date, and a device offset on one
#                       would describe nothing (D29's purpose is when a record was
#                       made, here that is the source's business).
NOT_RECORD_STORES="version current settings labels"
# Stores that live OUTSIDE APP_STATE, so emptyState() cannot list them:
#   scans -- the local scan list (H4, D77 §1), in its own localStorage key.
OUTSIDE_STATE="scans"

# Top-level keys of emptyState(): the object literal it returns, with every nested
# {...} removed first so a nested key (regimens.log) is not mistaken for a store.
ES_BODY=$(sed -n '/^function emptyState()/,/^}/p' app.js | tr -d '\n' | sed -E 's/^[^{]*\{[^{]*\{//; s/\}[^}]*\}[^}]*$//')
while printf '%s' "$ES_BODY" | grep -q '{[^{}]*}'; do ES_BODY=$(printf '%s' "$ES_BODY" | sed -E 's/\{[^{}]*\}//g'); done
STATE_STORES=$(printf '%s' "$ES_BODY" | grep -oE '[A-Za-z_]+[[:space:]]*:' | tr -d ': ' | sort -u)
[ -n "$STATE_STORES" ] || { echo "writesites: FAIL - could not read the store list from emptyState()"; exit 1; }
PATTERN_STORES=$(printf '%s\n' "$STORE_PATTERNS" | cut -d'|' -f1 | sort -u)

UNCLASSIFIED=""
for st in $STATE_STORES; do
  if ! printf '%s\n' $PATTERN_STORES $NOT_RECORD_STORES | grep -qxF "$st"; then UNCLASSIFIED="$UNCLASSIFIED $st"; fi
done
STALE=""
for st in $PATTERN_STORES; do
  if ! printf '%s\n' $STATE_STORES $OUTSIDE_STATE | grep -qxF "$st"; then STALE="$STALE $st"; fi
done
if [ -n "$UNCLASSIFIED" ] || [ -n "$STALE" ]; then
  echo "writesites: FAIL - the store list and the census disagree"
  [ -n "$UNCLASSIFIED" ] && echo "  UNCLASSIFIED store(s) in emptyState():$UNCLASSIFIED -- add a record pattern, or list it as not a record store, with the reason"
  [ -n "$STALE" ] && echo "  pattern(s) for store(s) the app no longer has:$STALE"
  exit 1
fi

WRITE_RE="($(printf '%s\n' "$STORE_PATTERNS" | cut -d'|' -f2- | paste -sd'|' -))"

# Enclosing function for each match. grep does the matching (its ERE is the one
# the pattern is written for); awk only maps a line number to the `function NAME(`
# that most recently preceded it at column 0.
MATCHES=$(grep -nE "$WRITE_RE" app.js | cut -d: -f1)
[ -n "$MATCHES" ] || { echo "writesites: FAIL - no write sites matched at all (pattern broken?)"; exit 1; }

FOUND=$(printf '%s\n' "$MATCHES" | awk '
  NR == FNR { want[$1] = 1; next }
  /^function [A-Za-z0-9_]+\(/ { fn = $0; sub(/^function /, "", fn); sub(/\(.*/, "", fn) }
  (FNR in want) { print (fn == "" ? "(top-level)" : fn) }
' - app.js | sort -u)

# ---- the pinned manifest (D29) --------------------------------------------
# STAMPED  : writes a record that carries the device offset.
# EXEMPT   : writes something that is not a stamped record -- reason in D29.
#
# R25/D61: `photoAddItem` is EXEMPT. It pushes into PHOTO_DRAFT.items -- a DRAFT
# held in memory and never persisted -- so it creates no record and there is
# nothing to stamp. `photoSave` is the creation site for that path and it is
# already registered and stamped. Recorded because it exposes a real limit of the
# detector: it matches the SHAPE `.items.push(`, not the STORE, so any array named
# `items` reads as a record store. That over-match is the safe direction (it asks
# rather than assumes) and the manifest is where the answer goes.
#
# R33/D69: `photoSave` LEFT this manifest, and its departure is the evidence the
# slice worked. It no longer writes items at all -- it confirms a plate (a fact that
# contributes nothing to any total) and delegates to `consumeFromPlate`, which is
# now the stamped creation site for that path. A census that had merely gained a
# name would say less than one that also lost the one it replaced.
#
# D83: `photoSave` is BACK, for a different write. It creates the PLATE
# (APP_STATE.plates[id] =), which the census could not see until `plates` was
# classified. It is STAMPED: plateFromDraft sets tzo. R33's point above stands --
# photoSave writes no items -- and the census now also sees the plate it does write.
#
# H4/D82: three new sites. `createMedFromDraft` (meds[id] =) and `addMedFill`
# (fills.push) are STAMPED -- the medication and each fill carry the device offset.
# `logScan` (scans.push) is EXEMPT: the scan list is a date-only local log, outside
# APP_STATE and never exported, and D77 ruled its fields; a time zone on it would be
# a field nobody asked for, on a record nothing computes over.
#
# H4.1/D89: `removeMed` is EXEMPT, and it is the first site here that writes without
# creating. Its UNDO closure puts a snapshot back (`meds[id] = snapshot`), so the
# record and its stamp are the ones that already existed. Stamping it on the way back
# would REWRITE history: the medication would claim to have been created at the
# moment someone undid a mistake. The detector matches the shape of the write, not
# its intent, which is exactly why the manifest carries the reason.
MANIFEST=$(cat <<'EOF'
addManualEntry
addMedFill
createMedFromDraft
logScan
photoSave
removeMed
addPriceEntry
addSignal
applySupplementToToday
focusAdherence
ingestItems
logPreset
logRegimenEntry
logScanItem
maybeInjectSupplement
consumeFromPlate
photoAddItem
priceComparison
resolveFast
setFulfillment
EOF
)

EXPECTED=$(printf '%s\n' "$MANIFEST" | sort -u)

if [ "$FOUND" = "$EXPECTED" ]; then
  echo "writesites: OK ($(printf '%s\n' "$FOUND" | grep -c .) sites, manifest matches; stores classified: $(printf '%s\n' $STATE_STORES | paste -sd' ' -))"
  exit 0
fi

echo "writesites: FAIL - the record-write census drifted from the D29 manifest"
NEW=$(comm -23 <(printf '%s\n' "$FOUND") <(printf '%s\n' "$EXPECTED"))
GONE=$(comm -13 <(printf '%s\n' "$FOUND") <(printf '%s\n' "$EXPECTED"))
[ -n "$NEW" ]  && { echo "  UNREGISTERED write site(s) -- classify stamped or exempt in D29:"; printf '    + %s\n' $NEW; }
[ -n "$GONE" ] && { echo "  manifest lists site(s) that no longer exist:";                     printf '    - %s\n' $GONE; }
exit 1
