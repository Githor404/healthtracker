#!/usr/bin/env bash
# H28 / fork B -- ENGAGEMENT AS AN INPUT, NOT A VOCABULARY.
#
# WHY A WORD LIST COULD NOT DO THIS. anti-engagement-gate swept 191 visible
# strings and passed while the app shipped a feature called NUDGE whose own
# comment said, in capitals, "Readiness + offer key on ENGAGEMENT (days logged),
# never on what the readings SAY". The curriculum was deliberately gentle, so it
# would have passed the banned-word list even if it had rendered -- and it did not
# render, because the gate's fixture seeded three logged days against a floor of
# seven (fork C fixes that half).
#
# What the feature WAS, is engagement-keyed BY CONSTRUCTION, and no vocabulary ban
# can see construction. So this is the source-side half, ruled: nothing renders on
# a trigger derived from a count of how much the user has logged.
#
# THE DISTINCTION THIS CHECK TURNS ON, because it is easy to get wrong:
#
#   ENGAGEMENT  = how much the user has USED THE APP (distinct days with any log).
#                 Forbidden as a trigger for showing anything.
#   BEHAVIOUR   = something the user DID with their body. `fastStats().streak`
#                 counts CONFIRMED FASTS, not app visits, and is legitimate --
#                 anti-engagement-gate already requires it to carry its
#                 denominator, which is the assertion a ban cannot express.
#   SUFFICIENCY = a figure needs n days to be honest (TYPICAL_MIN_DAYS = 8, D95).
#                 Legitimate, and the opposite of a nudge: it SUPPRESSES output
#                 rather than producing it.
#
# WHAT THIS CHECK CANNOT DO, said plainly rather than implied. It cannot prove that
# a brand-new, differently-shaped engagement counter is absent. A shape heuristic
# was tried and rejected: scanning for functions that read day existence matched
# TWENTY functions, nearly all of which read day CONTENT, and a check built on that
# would have been noise wearing a verdict. What it does instead is pin the two
# things that ARE enumerable -- the retired symbols, and every day-count constant
# with its class -- so a new one has to be declared and classified by a human.
#
# Exit 0 PASS, 1 FAIL.
set -uo pipefail

DIR=$(cd "$(dirname "$0")/.." && pwd)
cd "$DIR"
APP="app.js"
IDX="index.html"
FAILED=0

say_fail() { echo "engagement: FAIL - $1"; FAILED=1; }

# ---- 1. THE RETIRED LAYER STAYS RETIRED ----------------------------------
# Names ASSEMBLED AT RUNTIME. A literal list here would make this file match its
# own ban -- the import-gate self-scan trap, which cost a slice once already.
N=$(printf '%s' 'n'; printf '%s' 'udge')
NU=$(printf '%s' 'N'; printf '%s' 'UDGE')
LD=$(printf '%s' 'logged'; printf '%s' 'Days')

BANNED="$N
$NU
$LD"

# PLANTED CONTROL: prove the matcher can fire before trusting it to pass.
CONTROL="  const x = ${LD}(); if (${NU}_MIN_DAYS) render${N^}();"
CONTROL_HITS=$(printf '%s\n' "$CONTROL" | grep -oiE "$N|$LD" | wc -l | tr -d ' ')
if [ "$CONTROL_HITS" -lt 3 ]; then
  say_fail "the CONTROL matched only $CONTROL_HITS of its 3 planted names -- the matcher is broken, so a clean scan below would mean nothing"
fi

# DECLARED EXEMPTIONS, each with a reason. Two lines in the shipped source name
# the retired thing on purpose, and both must keep doing so:
#
#   1. D157's principle statement -- the retired name IS the subject of the rule,
#      and a rule that cannot name what it forbids is not a rule.
#   2. normalizeSettings' explanation of what an old export's key does -- a reader
#      who finds the key absent needs to be told it is tolerated and dropped
#      rather than left to guess whether a restore would reject it.
#
# A blanket "anything in a comment is fine" pass was rejected: a ban that excuses
# comments can be defeated by writing the feature's trigger into one. So these are
# named, and a THIRD mention fails until someone declares it here.
EXEMPT="never a streak, a ${N} or a distance:D157's principle statement names what it forbids
IS DELIBERATELY ABSENT:normalizeSettings says the retired key is tolerated and dropped
REBUILD, so an old export:the same explanation, continued
TOLERATED AND DROPPED, never an error:the same explanation, continued
blob for carrying a retired key:the same explanation, continued"

exempt_filter() {
  local out="$1"
  while IFS= read -r e; do
    [ -n "$e" ] || continue
    out=$(printf '%s\n' "$out" | grep -vF "${e%%:*}" || true)
  done <<EOF2
$EXEMPT
EOF2
  printf '%s' "$out"
}

for f in "$APP" "$IDX"; do
  [ -f "$f" ] || { say_fail "$f is missing"; continue; }
  while IFS= read -r name; do
    # "judge", "budge", "smudge" and friends all contain the retired name as a
    # substring. A plain grep for it reported FIFTY-NINE hits that were mostly
    # `judge`, which is how a wrong grep nearly drove a wrong deletion.
    hits=$(grep -nE "(^|[^A-Za-z])${name}" "$f" 2>/dev/null \
           | grep -viE "judge|budge|smudge|grudge|fudge|nudged down" || true)
    hits=$(exempt_filter "$hits")
    hits=$(printf '%s' "$hits" | grep -E '[0-9]' || true)
    if [ -n "$hits" ]; then
      say_fail "$f still carries '${name}' (H28/A1 deleted that layer):"
      printf '%s\n' "$hits" | head -6 | sed 's/^/    /'
    fi
  done <<EOF
$BANNED
EOF
done

# THE EXEMPTIONS MUST STILL MATCH SOMETHING. A stale one is an allowance for a
# line that no longer exists, and it would silently excuse a future line that
# happens to contain the same words.
while IFS= read -r e; do
  [ -n "$e" ] || continue
  pat="${e%%:*}"
  if ! grep -qF "$pat" "$APP"; then
    say_fail "stale exemption -- nothing in $APP matches '$pat' any more"
  fi
done <<EOF3
$EXEMPT
EOF3

# ---- 2. EVERY DAY-COUNT CONSTANT IS DECLARED, WITH A CLASS ---------------
# The completeness half, and the only one available: a count of days is the shape
# an engagement trigger takes, so every such constant is enumerated FROM THE
# SOURCE and must appear below with a class. A new one fails BY NAME, and whoever
# adds it has to say what it is for. `engagement` is not an available class.
DECLARED="GLUCOSE_SC_DAYS=parameter:how many days the Shortcut recipe exports
PLATE_RECALL_DAYS=recall:how long a saved plate keeps offering itself; keyed on an ACTION, not on usage
TRASH_MAX_AGE_DAYS=retention:how long a deleted record is recoverable
TYPICAL_MIN_DAYS=sufficiency:a typical needs this many days to BE a typical (D95). SUPPRESSES output rather than producing it
WAKE_WINDOW_DAYS=window:the span D95 computes a wake time over"

FOUND=$(grep -oE "^const [A-Z][A-Z0-9_]*_DAYS" "$APP" | sed 's/^const //' | sort -u)
DECL_NAMES=$(printf '%s\n' "$DECLARED" | sed 's/=.*//' | sort -u)

if [ -z "$FOUND" ]; then
  say_fail "no *_DAYS constant found at all -- the extraction pattern has rotted, so this census is vacuous (D96)"
fi

UNDECLARED=$(comm -23 <(printf '%s\n' "$FOUND") <(printf '%s\n' "$DECL_NAMES") || true)
STALE=$(comm -13 <(printf '%s\n' "$FOUND") <(printf '%s\n' "$DECL_NAMES") || true)

if [ -n "$UNDECLARED" ]; then
  say_fail "day-count constant(s) not declared here:"
  printf '%s\n' "$UNDECLARED" | sed 's/^/    /'
  echo "    Add it above with a class. Available: parameter, recall, retention,"
  echo "    sufficiency, window. There is NO 'engagement' class: a count of how"
  echo "    much the user has logged must not decide whether something is shown."
fi
if [ -n "$STALE" ]; then
  say_fail "declared day-count constant(s) no longer in $APP (a stale allowance):"
  printf '%s\n' "$STALE" | sed 's/^/    /'
fi

# The class list is itself asserted, so 'engagement' cannot be quietly added as a
# sixth class to legalise the thing the ruling forbids.
if printf '%s\n' "$DECLARED" | grep -qiE "=engagement:"; then
  say_fail "an 'engagement' class appears in the declaration -- that is the one thing D157 forbids"
fi

# ---- 3. THE LEGITIMATE COUNTER IS STILL THE LEGITIMATE ONE ---------------
# fastStats().streak counts confirmed fasts, which is behaviour. If it ever stops
# existing, the sentence in this file's header stops being true, and a header that
# describes code that is gone is how a reader learns the wrong distinction.
if ! grep -q "streak: streak" "$APP"; then
  say_fail "fastStats() no longer reports a streak -- this check's BEHAVIOUR-vs-ENGAGEMENT example is stale"
fi

N_DECL=$(printf '%s\n' "$DECLARED" | grep -c .)
if [ "$FAILED" -ne 0 ]; then
  echo "GATE: FAIL"
  exit 1
fi
echo "engagement: OK (the retired layer is absent from app.js and index.html;"
echo "  $N_DECL day-count constants, each declared with a class, none of them engagement;"
echo "  the one legitimate streak counts behaviour, not visits)"
echo "GATE: PASS"
exit 0
