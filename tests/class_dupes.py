#!/usr/bin/env python3
"""ONE CLASS, ONE RULE BLOCK -- with a manifest for the pairs that already exist.

WHAT HAPPENED, and it is D159's story told in CSS instead of JavaScript.
R159.1/A4 introduced a `.qrow` for the quick-add food row. `.qrow` was ALREADY
TAKEN -- the one-tap events row and a lab label row both use it -- and the new
rule came later in the cascade, so it silently restyled both.

    The one you styled was not the only one you styled.

AND IT CORRUPTED THE INSTRUMENT POINTED AT IT. The gate asserting "the sheet
lists at least three rows" counted `.qrow`, which now matched the foreign rows
too -- so a count of FOOD rows passed on elements from another surface. A name
collision does not only break what you wrote; it inflates whatever counts it.

It surfaced only because `flow-gate` tapped `document.querySelector('.qrow')`,
got a plain `<div>` with no handler, and clicking it did nothing at all. A silent
no-op took four rounds of diagnostics to name.

TWO EARLIER DRAFTS OF THIS CHECK WOULD HAVE MISSED IT, and both failures are
worth keeping here because they are the same mistake twice:

  1. "A newly EMITTED class must not already be styled." It passed, and it would
     have passed on the real bug: `.qrow` was not new to the markup at all --
     HEAD already emitted it. What was new was a second RULE.

  2. "No class may have two bare `^.name{` rules." This missed it too, because
     the stylesheet has MIXED INDENTATION: the pre-existing `.qrow{` is indented
     two spaces and the one I added sat at column zero. The extractor saw 89 of
     480 rules and reported a clean tree.

     > I wrote a detector for the bug I remembered rather than the bug I had,
     > twice -- and the second time the detector's own coverage was the defect.

So this parses the stylesheet by tracking BRACE DEPTH, which neither indentation
nor an at-rule can fool: only simple class selectors at depth 0 count, and rules
inside `@media` / `@supports` are excluded because a breakpoint override is the
one case where a second definition is the point.

THE MANIFEST. Nineteen classes already carry two top-level blocks, deliberately
-- a base rule and a modifier written apart. "No duplicates" is therefore not
clean on this tree, and a check that demanded it would have had to be negotiated
down until it passed, which is how a bar becomes decoration. They are named
instead, exactly as GATE_SCRIPTS names gates and D29 names write sites: a NEW
collision fails by name, and removing one of these fails too, so the manifest
cannot rot into a list of things that are no longer true.

Exit 0 PASS, 1 FAIL, 2 could not read the file.
"""
import io
import re
import sys
from collections import Counter

# Pairs that already carry two top-level blocks (measured 2026-10-09, with
# comments stripped -- the first count said 14 because 68 rules were hidden
# behind a comment sitting above them). Each is a base rule plus a modifier
# written elsewhere in the sheet, which is a different thing from a collision:
# both authors meant the same element.
#
# `.bgrp` is this slice's own and belongs here for the same reason: its base is
# shared with `.mgrp` in one rule and its accent edge is its own.
KNOWN_PAIRS = [
    'askbox', 'bgrp', 'daysel', 'delallback', 'delallkept', 'druglist',
    'drugtext', 'hrow', 'mcitebody', 'medmain', 'nightlows', 'nightshape',
    'obody', 'pmaltnone', 'pname', 'qnote', 'respcov', 'rvbox', 'sheetbody',
]

# A simple class selector, alone in its comma-separated part: `.name` and nothing
# else. `.a .b`, `.a>.b`, `.a:active`, `.a + .a` and `.a.b` are all different
# selectors doing a different job, and none of them is a second definition.
SIMPLE = re.compile(r'(?:^|,)\s*\.([a-z][a-z0-9-]*)\s*(?=,|$)')
MIN_RULES = 350          # 512 measured; far below it, to catch a rotted parser


def top_level_class_rules(css):
    """Every simple class selector at brace depth 0. Depth, not indentation."""
    depth, buf, top, nested = 0, [], [], []
    for ch in css:
        if ch == '{':
            sel = ''.join(buf).strip()
            buf = []
            (top if depth == 0 else nested).extend(SIMPLE.findall(sel))
            depth += 1
        elif ch == '}':
            depth = max(0, depth - 1)
            buf = []
        else:
            buf.append(ch)
    return top, nested


def read_css(path):
    text = io.open(path, encoding='utf-8', newline='').read()
    m = re.search(r'<style[^>]*>(.*?)</style>', text, re.S)
    css = m.group(1) if m else text
    # COMMENTS ARE STRIPPED FIRST, and this is the third coverage defect this one
    # check has had -- the one that let the real bug through. The selector buffer
    # is the text since the last `}`, so a `/* ... */` immediately above a rule
    # lands in front of the selector and `^\s*\.name$` no longer matches it. The
    # pre-existing `.qrow` rule has exactly such a comment above it, so the parser
    # never saw the half of the collision that was already there.
    return re.sub(r'/\*.*?\*/', ' ', css, flags=re.S)


def main():
    path = sys.argv[1] if len(sys.argv) > 1 else 'index.html'
    try:
        css = read_css(path)
    except OSError as e:
        print('class-dupes: could not read %s (%s)' % (path, e))
        return 2

    top, nested = top_level_class_rules(css)
    dupes = sorted(k for k, v in Counter(top).items() if v > 1)
    known = sorted(KNOWN_PAIRS)
    new = [d for d in dupes if d not in known]
    gone = [k for k in known if k not in dupes]
    failed = []

    if len(top) < MIN_RULES:
        failed.append('only %d top-level class rule(s) were parsed from %s -- the '
                      'parser has rotted, so finding no collisions proves nothing'
                      % (len(top), path))

    if new:
        failed.append('these class(es) have TWO top-level rule blocks and are NOT in '
                      'the manifest -- a second definition joins the first in the '
                      'cascade, and any gate counting the class counts every surface '
                      'that uses it: ' + ', '.join('.' + d for d in new))

    if gone:
        failed.append('the manifest names these as having two blocks and they no '
                      'longer do -- remove them from KNOWN_PAIRS in the same commit, '
                      'so the manifest cannot rot into a list of things that stopped '
                      'being true: ' + ', '.join('.' + g for g in gone))

    # ---- the planted control: duplicate a real rule, require a catch --------
    # A collision detector that cannot detect one reads exactly like a clean sheet.
    if top:
        victim = top[0]
        planted, _ = top_level_class_rules(css + '\n.%s{color:red}\n' % victim)
        caught = [k for k, v in Counter(planted).items()
                  if v > 1 and k not in known and k == victim]
        if not caught:
            failed.append('the parser did not catch a PLANTED second block for .%s '
                          '-- the clean result above cannot be trusted' % victim)

    if failed:
        for f in failed:
            print('class-dupes: FAIL - ' + f)
        return 1

    print('class-dupes: OK (%d top-level class rules, %d unique; %d known pair(s) '
          'in the manifest, no new collision; %d rule(s) inside at-rules excluded, '
          'where a breakpoint override is the point; planted duplicate found)'
          % (len(top), len(set(top)), len(known), len(nested)))
    return 0


if __name__ == '__main__':
    sys.exit(main())
