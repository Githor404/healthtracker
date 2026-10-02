#!/usr/bin/env bash
# THE LINE-ENDING CENSUS -- every tracked file against what .gitattributes says.
#
# Endings have cost time three times across this repo and its sibling, and each
# time the symptom wore a different costume: a 26,260-line diff on a 136-line
# change; `sed -i` flattening a file nobody meant to rewrite; and a file reading
# CLEAN while disagreeing with its own blob, because git's stat cache compares
# size and mtime and never looks at the content. The common cause is that nothing
# in the repository SAID what the endings should be -- `core.autocrlf` arrives
# from the machine's system gitconfig, so the answer depended on who cloned it.
#
# .gitattributes says it now. This holds the tree to that, so the declaration
# cannot quietly stop being true.
#
# TWO SIDES, SCOPED DIFFERENTLY ON PURPOSE:
#
#   THE BLOB (`i/`) is the repository's business and is asserted everywhere. A
#   file git treats as text must be stored LF. This is the half that produces the
#   catastrophic diffs: a blob that disagrees with the filter rewrites every line
#   of the file on the next commit that touches it.
#
#   THE WORKING TREE (`w/`) is the machine's business, and is asserted ONLY where
#   `eol` is explicitly declared. Asserting it elsewhere would fail on Linux and
#   pass on Windows for the same commit -- a check that reports the operating
#   system rather than the tree.
#
# AN UNDECLARED FILE IS A FAILURE, not a pass. Same rule the gate runner applies
# to an unwired check: if the `* text=auto` default is ever removed, every file
# goes "unspecified", and a census with nothing to compare against would go green
# over precisely the condition it exists to catch.
#
# THE INSTRUMENT IS `git ls-files --eol`, which git ships for exactly this and
# which reports the index ending, the worktree ending, the declared attributes
# AND git's own binary verdict in one call. Two earlier versions built that by
# hand and both were worse: four perl spawns per file took most of a minute, four
# seds per file took thirty-five seconds, and the sed version ALSO lost an
# assertion -- `git grep -I` silently skips binary files, so a NUL-bearing shard
# wrongly declared `text` was invisible to the one check that cared about it. The
# defect pass on this very script caught that.
#
# The lone-CR probe still needs `git grep`, because git's eol vocabulary knows
# only LF and CRLF and a bare CR is neither.
#
# Exit 0 PASS, 1 FAIL. Prints `GATE: PASS` / `GATE: FAIL` like every other check.
set -u
cd "$(dirname "$0")/.." || exit 1
AWK="$(dirname "$0")/check-eol.awk"

if [ ! -f .gitattributes ]; then
  echo "check-eol: no .gitattributes -- nothing declares how this tree is stored,"
  echo "  so every ending in it is whatever the cloning machine's core.autocrlf said."
  echo "GATE: FAIL"
  exit 1
fi
if [ ! -f "$AWK" ]; then
  echo "check-eol: $AWK is missing, so the census has no matcher and cannot report."
  echo "  Recover: git checkout -- tests/check-eol.awk"
  echo "GATE: FAIL"
  exit 1
fi

CR=$(printf '\r')

# Both greps exit 1 when nothing matches, which is the healthy case, not an error.
{
  git ls-files --eol                                        | sed 's/^/E /'
  { git grep -I -c -e "${CR}\$" -- . 2>/dev/null || true; } | sed 's/^/W /'
  { git grep -I -c -e "${CR}"   -- . 2>/dev/null || true; } | sed 's/^/C /'
} | awk -F'\t' -f "$AWK"
exit $?
