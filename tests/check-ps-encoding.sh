#!/usr/bin/env bash
# Every .ps1 gate script must be pure ASCII, or carry a byte-order mark.
#
# WHY. Windows PowerShell 5.1 reads a .ps1 with no BOM in the system codepage,
# not as UTF-8. So a literal non-ASCII character typed into a gate script does
# not reach PowerShell as the character that was typed. Measured, with the
# pattern's own codepoints printed:
#
#   'unresolved\s*<em dash>\s*resolve'   ->   226,8364,8221 where 8212 belongs
#
# which is the cp1252 reading of the UTF-8 bytes E2 80 94. jargon-gate carried
# exactly that inside a REGEX in its banned-phrase list, so that phrase could
# never match the page text and had never once been checked. It passed for as
# long as it existed, which is the worst way for a check to behave.
#
# In a comment the same mistake only garbles the output a gate exists to produce.
# In a string, a regex or a comparison it silently kills an assertion. This fails
# on both and SAYS WHICH, because that is the difference between cosmetic and
# dead.
#
# A BOM is accepted because it removes the cause: with one, PowerShell reads the
# file as UTF-8 and a literal em dash arrives as an em dash. Pure ASCII is the
# other way, and the way these gates are written: a regex escape (backslash-u
# 2014, backslash-u 00b7) or [char]0x2014 in a string -- ASCII source that
# produces the right character.
#
# Line terminators are NOT this check's business: CR is stripped before the scan,
# because check-eol.sh owns endings and two checks fighting over one property is
# how you get a failure nobody can act on.
set -uo pipefail

DIR=$(cd "$(dirname "$0")" && pwd)
cd "$DIR"

FAILED=0
CHECKED=0
WITH_BOM=0
LIVE_HITS=0
COMMENT_HITS=0

# A GLOB THAT MATCHES NOTHING MUST NOT PASS (D96). The floor sits well below the
# current count, so adding a gate never trips it, and well above zero, so a
# broken glob or a wrong working directory does.
FLOOR=15

for f in *.ps1; do
  [ -e "$f" ] || continue
  CHECKED=$((CHECKED + 1))

  # A BOM settles it: PowerShell then reads UTF-8 (or UTF-16) and non-ASCII is
  # safe, so nothing below applies.
  B=$(head -c 3 "$f" | od -An -tx1 | tr -d ' \n')
  case "$B" in
    efbbbf*|fffe*|feff*) WITH_BOM=$((WITH_BOM + 1)); continue ;;
  esac

  # No BOM: every byte must be printable ASCII, space or tab. In the C locale
  # [:print:] is 0x20-0x7E, so every byte >= 0x80 is caught, and so is a stray
  # control character.
  HITS=$(LC_ALL=C tr -d '\r' < "$f" | LC_ALL=C grep -n '[^[:print:][:blank:]]' || true)
  [ -n "$HITS" ] || continue

  FAILED=1
  # Classify each hit: a comment garbles output, a live line kills an assertion.
  # Naming which is the whole value -- "a quantity with no owner makes the reader
  # guess", and here the owner determines whether it is urgent.
  while IFS= read -r hit; do
    [ -n "$hit" ] || continue
    LN=${hit%%:*}
    TXT=${hit#*:}
    BODY=$(printf '%s' "$TXT" | sed -e 's/^[[:space:]]*//')
    case "$BODY" in
      '#'*) KIND=COMMENT; COMMENT_HITS=$((COMMENT_HITS + 1)) ;;
      *)    KIND=LIVE;    LIVE_HITS=$((LIVE_HITS + 1)) ;;
    esac
    SHOWN=$(printf '%s' "$BODY" | cut -c1-110)
    printf '  %s:%s  non-ASCII in a %s line\n' "$f" "$LN" "$KIND"
    printf '      %s\n' "$SHOWN"
  done <<EOF
$HITS
EOF
done

if [ "$CHECKED" -lt "$FLOOR" ]; then
  echo "ps-encoding: FAIL - only $CHECKED .ps1 file(s) found, floor is $FLOOR"
  echo "  A check that inspects nothing passes for free: wrong directory, or a broken glob."
  echo "GATE: FAIL"
  exit 1
fi

if [ "$FAILED" -ne 0 ]; then
  echo "ps-encoding: FAIL - $LIVE_HITS live line(s) and $COMMENT_HITS comment line(s) carry non-ASCII with no BOM"
  echo "  PowerShell 5.1 reads a BOM-less .ps1 in the system codepage, so these do not"
  echo "  arrive as the characters that were typed. In a COMMENT that garbles the output"
  echo "  a gate exists to produce. In a LIVE line it silently kills the assertion --"
  echo "  jargon-gate had a literal em dash in a regex and that phrase was never checked."
  echo "  Fix: a regex escape, or [char]0x2014 in a string. Both are ASCII source that"
  echo "  produces the right character. Adding a BOM also works."
  echo "GATE: FAIL"
  exit 1
fi

echo "ps-encoding: OK ($CHECKED .ps1 checked; $WITH_BOM with a BOM, $((CHECKED - WITH_BOM)) pure ASCII)"
echo "GATE: PASS"
exit 0
