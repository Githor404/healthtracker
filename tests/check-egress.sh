#!/usr/bin/env bash
# EVERY HOST THIS APP CAN REACH, CENSUSED AND NAMED.
#
# [[D157]] binds the app to be "loyal to the user only: no ads, no data sale, no
# product steering". That was TRUE BY CONSTRUCTION -- no backend, no accounts, no
# telemetry -- and gated in exactly one place: import-gate proves nothing crosses
# the origin DURING AN IMPORT. Nothing watched the rest of the time.
#
# Loyalty true by construction becomes loyalty PROVEN. Three teeth, because a
# host census alone has an obvious hole:
#
#   1. THE HOST SET. Every host appearing in the shipped files must be declared
#      below with its classification and reason; every declared host must still
#      appear. A new host fails BY NAME. A declared host that has disappeared
#      fails as a STALE ALLOWANCE -- a census that cannot notice a removal is
#      half a census (D96).
#   2. THE FETCH CALL SITES, pinned by count. A host census only sees LITERAL
#      URLs, so `fetch(somethingNew)` would slip past it entirely. Pinning the
#      number of call sites is what closes that.
#   3. THE ABSENT APIS. XMLHttpRequest, WebSocket, sendBeacon, EventSource and
#      the notification/badge surfaces must all remain at zero -- those are the
#      ways egress (or a nudge) arrives without a literal URL.
#
# CLASSIFICATION MATTERS, and a naive census gets it wrong. `github.com` appears
# as an <a href> and inside the OpenFoodFacts User-Agent string; `dailymed` is a
# link the user taps; `console.x.ai` is prose in a comment. Calling those egress
# would be false, and a check that cries wolf is a check people stop reading. So
# the set is enforced and the classification is documented.
set -uo pipefail

DIR=$(cd "$(dirname "$0")/.." && pwd)
cd "$DIR"

FILES="app.js index.html sw.js manifest.json"
FAIL=0

# ---- THE DECLARED HOSTS -------------------------------------------------
# host|class|reason
# class: request = the app issues it; link = the user navigates there;
#        string  = it appears only in prose, a comment, or a header value.
DECLARED=$(cat <<'EOF'
world.openfoodfacts.org|request|product lookup on the scan path, cache-first, with the D14 etiquette User-Agent
api.x.ai|request|the BYOK provider base, on the USER'S OWN key, probe + chat/completions
api.fda.gov|request|the FDA drug label, on a tap only -- never on load
cdn.jsdelivr.net|request|the lazily loaded ZXing fallback, the one external dependency the brief allows
dailymed.nlm.nih.gov|link|"Search DailyMed yourself" and the label's own page -- the user navigates, the app does not request
github.com|link|the Source link in the About line, and the repo URL inside the OFF User-Agent string
console.x.ai|string|prose in a comment saying where a key comes from
EOF
)

DECL_HOSTS=$(printf '%s\n' "$DECLARED" | grep -v '^[[:space:]]*$' | cut -d'|' -f1 | sort -u)
N_DECL=$(printf '%s\n' "$DECL_HOSTS" | grep -c . || true)

# ---- 1. what is actually in the files -----------------------------------
FOUND=$(grep -ohoE "https?://[a-zA-Z0-9._~:/?#@!\$&'()*+,;=%-]+" $FILES 2>/dev/null \
  | sed -E 's#^https?://([^/"'"'"']+).*#\1#' \
  | sed -E 's#\.$##' \
  | sort -u | grep -v '^$' || true)
N_FOUND=$(printf '%s\n' "$FOUND" | grep -c . || true)

if [ "$N_FOUND" -lt 3 ]; then
  echo "egress: FAIL - only $N_FOUND host(s) found in $FILES"
  echo "  This app reaches OpenFoodFacts, an AI provider and the FDA; finding"
  echo "  fewer than three means the scan is broken, not that the app went quiet."
  echo "GATE: FAIL"; exit 1
fi

UNDECLARED=""
for h in $FOUND; do
  printf '%s\n' "$DECL_HOSTS" | grep -qxF "$h" || UNDECLARED="$UNDECLARED $h"
done
STALE=""
for h in $DECL_HOSTS; do
  printf '%s\n' "$FOUND" | grep -qxF "$h" || STALE="$STALE $h"
done

if [ -n "$UNDECLARED" ]; then
  FAIL=1
  echo "egress: UNDECLARED HOST(S):$UNDECLARED"
  for h in $UNDECLARED; do
    echo "  --- $h is reachable and has no entry. Where it appears:"
    grep -nE "https?://$(printf '%s' "$h" | sed 's/\./\\./g')" $FILES 2>/dev/null \
      | head -3 | sed 's/^/      /'
  done
  echo "  Declare it with its CLASS and its REASON, or remove it. An undeclared"
  echo "  host is the whole thing this check exists to refuse."
fi
if [ -n "$STALE" ]; then
  FAIL=1
  echo "egress: STALE ALLOWANCE(S):$STALE"
  echo "  Declared but no longer present. A permission nobody needs is a"
  echo "  permission nobody is watching."
fi

# ---- 2. the fetch call sites, pinned ------------------------------------
# app.js: the app's own calls. sw.js's are pass-through of the page's request
# (fetch(req)) and introduce no host of their own, so they are pinned separately.
PIN_APP=6
PIN_SW=5
N_APP=$(grep -cF 'fetch(' app.js || true)
N_SW=$(grep -cF 'fetch(' sw.js || true)
if [ "$N_APP" -ne "$PIN_APP" ]; then
  FAIL=1
  echo "egress: app.js has $N_APP fetch call site(s), pinned at $PIN_APP"
  grep -nF 'fetch(' app.js | sed 's/^/      /'
  echo "  A host census only sees LITERAL urls, so fetch(aVariable) would pass it."
  echo "  Re-pin deliberately, in the commit that adds or removes a call."
fi
if [ "$N_SW" -ne "$PIN_SW" ]; then
  FAIL=1
  echo "egress: sw.js has $N_SW fetch call site(s), pinned at $PIN_SW (all pass-through)"
  grep -nF 'fetch(' sw.js | sed 's/^/      /'
fi

# ---- 3. the absent APIs -------------------------------------------------
for api in XMLHttpRequest WebSocket sendBeacon EventSource "new Notification" PushManager setAppBadge; do
  n=$(grep -cF "$api" $FILES 2>/dev/null | awk -F: '{s+=$2} END {print s+0}')
  if [ "${n:-0}" -ne 0 ]; then
    FAIL=1
    echo "egress: $api appears $n time(s) -- an egress or notification path with no literal URL"
    grep -nF "$api" $FILES 2>/dev/null | head -3 | sed 's/^/      /'
  fi
done

if [ "$FAIL" -ne 0 ]; then
  echo "GATE: FAIL"; exit 1
fi

echo "egress: OK - $N_FOUND host(s) found, all $N_DECL declared with a reason"
printf '%s\n' "$DECLARED" | grep -v '^[[:space:]]*$' | while IFS='|' read -r h c r; do
  printf '  %-26s %-8s %s\n' "$h" "$c" "$r"
done
echo "  app.js $N_APP fetch sites (pinned), sw.js $N_SW pass-through (pinned);"
echo "  XMLHttpRequest / WebSocket / sendBeacon / EventSource / Notification / badge: none."
echo "GATE: PASS"
exit 0
