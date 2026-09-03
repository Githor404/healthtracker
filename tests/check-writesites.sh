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

# Writes into the five persisted record stores: day.items, timeline[date],
# priceLog[bc].entries, fastLog[start], regimens.log[date][entryId].
WRITE_RE='(\.items\.push\(|\.entries\.push\(|timeline\[[^]]+\][^;]*\.push\(|fastLog\[[^]]+\][[:space:]]*=[^=]|\.log\[[^]]+\]\[[^]]+\][[:space:]]*=[^=])'

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
MANIFEST=$(cat <<'EOF'
addManualEntry
addPriceEntry
addSignal
applySupplementToToday
focusAdherence
ingestItems
logPreset
logRegimenEntry
logScanItem
maybeInjectSupplement
photoSave
priceComparison
resolveFast
setFulfillment
EOF
)

EXPECTED=$(printf '%s\n' "$MANIFEST" | sort -u)

if [ "$FOUND" = "$EXPECTED" ]; then
  echo "writesites: OK ($(printf '%s\n' "$FOUND" | grep -c .) sites, manifest matches)"
  exit 0
fi

echo "writesites: FAIL - the record-write census drifted from the D29 manifest"
NEW=$(comm -23 <(printf '%s\n' "$FOUND") <(printf '%s\n' "$EXPECTED"))
GONE=$(comm -13 <(printf '%s\n' "$FOUND") <(printf '%s\n' "$EXPECTED"))
[ -n "$NEW" ]  && { echo "  UNREGISTERED write site(s) -- classify stamped or exempt in D29:"; printf '    + %s\n' $NEW; }
[ -n "$GONE" ] && { echo "  manifest lists site(s) that no longer exist:";                     printf '    - %s\n' $GONE; }
exit 1
