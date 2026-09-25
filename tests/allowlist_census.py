"""D131 -- THE ALLOWLIST CENSUS.

THE TRAP THIS EXISTS FOR. Every record normaliser in app.js is an ALLOWLIST
REBUILD: it returns a fresh object carrying only the properties it names. So a
property written onto a stored record but never declared in that record's
normaliser is DELETED the first time the record is restored, imported or
migrated -- silently, far from the change that caused it.

It has happened repeatedly. Most recently `it.ref` (D121 wrote it, D129 declared
it eight versions later), and the warning against it was written INSIDE THE VERY
FUNCTION that was missed:

    "a half-declared field is the trap itself: a record edited by any future path
     would round-trip as edited-value-without-edit-history the first time it was
     exported."

A rule in a comment is a rule nobody runs.

HOW THE CENSUS IS DERIVED. Both sides come from the code, never from a kept list:

  the ALLOWLIST -- the properties a normaliser actually emits, read out of its own
  body (`out.x = ...`, the keys of its returned literal, and the constant arrays
  it spreads through `out[k]`).

  the WRITES -- every property assigned directly onto a stored record, found by
  scanning assignments across the file.

WHAT IS *NOT* A STORED RECORD, ALSO DERIVED. A photo DRAFT is transient: it lives
in PHOTO_DRAFT, is never persisted, and never passes a normaliser. So a function
whose body references PHOTO_DRAFT is writing a draft, and its assignments are not
censused. That exclusion is read from the function's own body -- it is not a list
of blessed field names.

The one thing kept by hand here is the table of record KINDS and which normaliser
owns each, which is structural: four records, four normalisers. No field name
appears in this file.
"""
import re
import sys
import os

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SRC = open(os.path.join(ROOT, 'app.js'), encoding='utf-8', newline='').read()
LINES = SRC.split('\n')

FUNC_RE = re.compile(r'^(?:async\s+)?function\s+([A-Za-z_]\w*)\s*\(')


def functions():
    """name -> (start_line, body). Top-level declarations only, which is every
    normaliser and every writer in this file."""
    starts = []
    for i, ln in enumerate(LINES):
        m = FUNC_RE.match(ln)
        if m:
            starts.append((i, m.group(1)))
    out = {}
    for n, (i, name) in enumerate(starts):
        end = starts[n + 1][0] if n + 1 < len(starts) else len(LINES)
        out[name] = (i + 1, '\n'.join(LINES[i:end]))
    return out


FUNCS = functions()


def const_array(name):
    """The string entries of a top-level `const NAME = [...]`, so a normaliser
    that spreads a constant through out[k] is read correctly."""
    m = re.search(r'const\s+' + re.escape(name) + r'\s*=\s*\[(.*?)\]', SRC, re.S)
    if not m:
        return []
    return re.findall(r"'([^']+)'", m.group(1))


def allowlist(fn, anchor=None):
    """Every property this normaliser emits, read from its own body."""
    if fn not in FUNCS:
        return None
    body = FUNCS[fn][1]
    keys = set(re.findall(r'\bout\.([A-Za-z_]\w*)\s*=(?!=)', body))
    keys |= set(re.findall(r'\brec\.([A-Za-z_]\w*)\s*=(?!=)', body))
    # Keys of the object literal the normaliser builds. `anchor` lets a kind say
    # where ITS literal is assembled when that is not `const out = {` -- the day's
    # record is built inline inside normalizeState. Structural, never field names.
    pats = [r'(?:const\s+out\s*=|return)\s*\{(.*?)\n\s*\};?']
    if anchor:
        pats = [anchor + r'\s*\{(.*?)\n\s*\};']
    for pat in pats:
        for lit in re.findall(pat, body, re.S):
            keys |= set(re.findall(r'^\s*([A-Za-z_]\w*)\s*:', lit, re.M))
    # a constant array spread through out[k] -- e.g. MACRO_KEYS.forEach(k => out[k] = ...)
    for arr in re.findall(r'([A-Z_]{2,})\.forEach\(', body):
        if re.search(r'out\[[A-Za-z_]\w*\]\s*=', body):
            keys |= set(const_array(arr))
    return keys


# kind -> (normaliser, variable names, a pattern that identifies a function
# operating on the STORED record of that kind)
KINDS = [
    ('item', 'normalizeItem', ('it', 'item'), r'\.items\[', None),
    ('med', 'normalizeMed', ('med',), r'APP_STATE\.meds|getMed\(', None),
    ('plate', 'normalizePlate', ('pl', 'plate'), r'APP_STATE\.plates|getPlate\(', None),
    ('day', 'normalizeState', ('day',), r'\.days\[|curDay\(|dayForWrite\(', r's\.days\[d\]\s*='),
]

leaks = []
checked = 0
for kind, norm, varnames, scope, anchor in KINDS:
    allow = allowlist(norm, anchor)
    if allow is None:
        leaks.append('%s: normaliser %s not found -- the census cannot see this record kind'
                     % (kind, norm))
        continue
    if not allow:
        leaks.append('%s: %s emitted no properties -- the census read nothing, which is '
                     'not the same as there being nothing' % (kind, norm))
        continue
    for fname, (start, body) in FUNCS.items():
        if fname.startswith('normalize'):
            continue                       # a normaliser rebuilding its own output
        if 'PHOTO_DRAFT' in body:
            continue                       # a draft is transient and never normalised
        if not re.search(scope, body):
            continue                       # this function does not touch a stored record
        # The variable holding a stored record is DERIVED, not assumed to be called
        # `it`. A defect pass found the blind spot: a census that scans only the
        # conventional names sees only the conventional writes, and the next leak
        # will be through a local called something else.
        #
        # A name bound FROM the store (`const x = day.items[i]`) holds the stored
        # record itself, so writing to it bypasses the normaliser. A name bound to a
        # copy that is then passed THROUGH a normaliser is the safe pattern and is
        # deliberately not scanned -- there the normaliser still decides.
        local = set(varnames)
        for m in re.finditer(r'(?:const|let|var)\s+([A-Za-z_]\w*)\s*=\s*[^;\n]*?(?:' + scope + ')', body):
            if m.group(1):
                local.add(m.group(1))
        for var in sorted(local):
            for m in re.finditer(r'\b' + re.escape(var) + r'\.([A-Za-z_]\w*)\s*=(?!=)', body):
                prop = m.group(1)
                checked += 1
                if prop not in allow:
                    line = start + body[:m.start()].count('\n')
                    leaks.append('%s.%s written at app.js:%d in %s() but NOT declared in %s()'
                                 % (kind, prop, line, fname, norm))

print('allowlist census: %d direct writes checked across %d record kinds' % (checked, len(KINDS)))
for kind, norm, _v, _s, anch in KINDS:
    a = allowlist(norm, anch)
    print('  %-6s %-16s declares %d properties' % (kind, norm + '()', len(a) if a else 0))

if leaks:
    print('allowlist: a property is written to a stored record and dropped by its normaliser')
    for l in sorted(set(leaks)):
        print('    ' + l)
    print('  Such a field survives in memory and VANISHES on the first restore, import')
    print('  or migration. Declare it in the normaliser, in the same commit that writes it.')
    print('GATE: FAIL')
    sys.exit(1)

print('allowlist: every property written to a stored record is declared')
print('GATE: PASS')
sys.exit(0)
