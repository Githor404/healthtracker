#!/usr/bin/env bash
# The corpus slot list is APPEND-ONLY FOREVER (D114), so it is the one artifact
# in this repo that must never drift silently. This check asserts:
#
#   1. slots.json parses and its own counts add up to its own list
#   2. the list is APPEND-ONLY against what is committed -- a slot may be ADDED,
#      never removed, renumbered, or have its unit or key changed under it, and
#      no source number may be RETARGETED at a different slot
#   3. slot numbers are unique and every slot has a unit
#   4. every JUDGED entry carries a stated reason
#   5. the source maps point only at slots that exist
#   6. THE SPEC AND THE SHIPPED ASSETS AGREE -- corpus/dist/<ns>.json declares
#      the same slot list in the same ORDER, `cols` equals its length, and the
#      .bin is exactly rows x cols x 4 bytes
#
# LEGS 2 AND 6 WERE PROMISED BY THIS FILE'S OWN HEADER AND NEVER IMPLEMENTED.
# From the day it was written until H24 the body's second check was the unique-
# numbers test, which is leg 3 -- so the file described an append-only guarantee
# it did not provide. Found while adding the first new slot since the corpus
# shipped, which is the exact moment the guarantee was first exercised.
#
# LEG 6 IS THE ONE WITH TEETH, and it is the trap H24 walked past. A slot is a
# COLUMN INDEX: adding fructose (212) inserted a column at index 5 and shifted
# every later slot by one. Regenerating slots.json without re-running encode.py
# leaves a 47-slot spec describing a 46-column binary, and then every nutrient
# after index 5 is read one column off -- silently, and into plausible numbers,
# because these quantities all live in the same range. Nothing checked this.
#
# It deliberately does NOT re-derive from the sources: the source archives are
# ~19 MB and are not committed (corpus/README.md says where to get them). A full
# re-derivation is `python corpus/derive_slots.py --src <dir> --check`, which is
# the stronger check and the one to run when the sources are to hand. This one
# runs everywhere, every time, and catches the failure that actually threatens a
# permanent artifact: an edit nobody meant to make.
set -uo pipefail
DIR=$(cd "$(dirname "$0")" && pwd)
REPO=$(cd "$DIR/.." && pwd)
SLOTS="$REPO/corpus/slots.json"

if [ ! -f "$SLOTS" ]; then
  echo "SLOTS CHECK: FAIL - corpus/slots.json is missing"
  echo "GATE: FAIL"; exit 1
fi

# The committed baseline for the append-only leg. A comparison needs something to
# compare to, and the only honest "previous" is what is in HEAD.
BASE=""
BASE_WHY="no git"
if git -C "$REPO" rev-parse --git-dir >/dev/null 2>&1; then
  BASE="$DIR/.slots-head.tmp"
  if git -C "$REPO" show HEAD:corpus/slots.json > "$BASE" 2>/dev/null; then
    BASE_WHY=""
  else
    rm -f "$BASE"; BASE=""; BASE_WHY="not in HEAD (new file)"
  fi
fi

python - "$SLOTS" "$REPO" "$BASE" "$BASE_WHY" <<'PY'
import json, io, os, struct, sys

path, repo, base_path, base_why = sys.argv[1], sys.argv[2], sys.argv[3], sys.argv[4]
try:
    d = json.load(io.open(path, encoding='utf-8'))
except Exception as e:
    print('SLOTS CHECK: FAIL - slots.json does not parse: %s' % e)
    print('GATE: FAIL'); sys.exit(1)

slots = d.get('slots') or []
counts = d.get('counts') or {}
bad = []

# 1. the counts must describe the list, or the artifact is lying about itself
derived = sum(1 for s in slots if s.get('origin') == 'derived')
judged = sum(1 for s in slots if s.get('origin') == 'judged')
if derived != counts.get('derived'):
    bad.append('derived count %s != %d in the list' % (counts.get('derived'), derived))
if judged != counts.get('judged_additions'):
    bad.append('judged count %s != %d in the list' % (counts.get('judged_additions'), judged))
if len(slots) != counts.get('total'):
    bad.append('total %s != %d slots' % (counts.get('total'), len(slots)))
if len(d.get('merges') or []) != counts.get('judged_merges'):
    bad.append('merge count disagrees with the merge list')


# 2. APPEND-ONLY, against the committed baseline.
#
#    What may change: slots may be ADDED, and anything purely descriptive on an
#    existing slot (its `why`, its measured percentages) may be restated.
#    What may NOT: a slot disappearing, its unit or key changing under it, or a
#    source number being pointed at a DIFFERENT slot. The last is the quiet one:
#    every device that already resolved an item holds that source id, so
#    retargeting it reassigns stored data to another nutrient.
def appendonly(old, new):
    out = []
    old_by = {}
    for s in (old.get('slots') or []):
        old_by[s.get('slot')] = s
    new_by = {}
    for s in (new.get('slots') or []):
        new_by[s.get('slot')] = s
    for n, o in sorted(old_by.items(), key=lambda kv: (kv[0] is None, kv[0])):
        v = new_by.get(n)
        if v is None:
            out.append('slot %s was REMOVED -- the list is append-only forever' % n)
            continue
        for field in ('unit', 'key'):
            a, b = o.get(field), v.get(field)
            if a is not None and a != b:
                out.append('slot %s had its %s changed from %r to %r under it'
                           % (n, field, a, b))
    for name in ('fdc_number_to_slot', 'cnf_id_to_slot'):
        om, nm = (old.get(name) or {}), (new.get(name) or {})
        for k, v in sorted(om.items()):
            if k not in nm:
                out.append('%s no longer maps source number %s' % (name, k))
            elif nm[k] != v:
                out.append('%s RETARGETED source number %s from slot %s to slot %s'
                           % (name, k, v, nm[k]))
    old_m = {}
    for m in (old.get('merges') or []):
        old_m[m.get('from_cnf')] = m.get('slot')
    new_m = {}
    for m in (new.get('merges') or []):
        new_m[m.get('from_cnf')] = m.get('slot')
    for k, v in sorted(old_m.items(), key=lambda kv: (kv[0] is None, kv[0])):
        if k not in new_m:
            out.append('the merge of CNF %s into slot %s is gone' % (k, v))
        elif new_m[k] != v:
            out.append('CNF %s now merges into slot %s, not %s' % (k, new_m[k], v))
    return out


# PLANTED CONTROLS. A comparator that cannot find a violation reads exactly like
# a clean history, so three are planted -- one per kind -- and all three must be
# caught before the real comparison below means anything (D96).
def _clone(x):
    return json.loads(json.dumps(x))

ctl = _clone(d)
if ctl['slots']:
    ctl['slots'] = ctl['slots'][1:]
    ctl['slots'] = ctl['slots']
if not any('REMOVED' in f for f in appendonly(d, ctl)):
    bad.append('CONTROL: a removed slot was not detected -- the append-only comparator'
               ' is broken, so finding no drift below would prove nothing')

ctl = _clone(d)
if ctl['slots']:
    ctl['slots'][0]['unit'] = 'furlong'
if not any('changed from' in f for f in appendonly(d, ctl)):
    bad.append('CONTROL: a changed unit was not detected')

ctl = _clone(d)
_k = sorted(ctl.get('cnf_id_to_slot') or {})
if _k:
    ctl['cnf_id_to_slot'][_k[0]] = -999
if not any('RETARGETED' in f for f in appendonly(d, ctl)):
    bad.append('CONTROL: a retargeted source number was not detected')

APPEND_LINE = 'append-only: NOT CHECKED (%s)' % base_why
if base_path:
    try:
        base = json.load(io.open(base_path, encoding='utf-8'))
    except Exception as e:
        bad.append('the committed baseline does not parse: %s' % e)
    else:
        found = appendonly(base, d)
        bad.extend(found)
        APPEND_LINE = ('append-only: %d committed slot(s) all still present, unchanged,'
                       ' and no source number retargeted' % len(base.get('slots') or []))

# 3. slot numbers are unique and every slot has a unit -- a slot without a unit
#    cannot hold a value that means anything
seen = set()
for s in slots:
    n = s.get('slot')
    if n in seen:
        bad.append('slot %s appears twice' % n)
    seen.add(n)
    if not s.get('unit'):
        bad.append('slot %s has no unit' % n)

# 4. every JUDGED entry states WHY it was judged. An unexplained hand-ruled
#    entry is a curated list wearing a derivation's clothes.
for s in slots:
    if s.get('origin') == 'judged' and not str(s.get('why') or '').strip():
        bad.append('judged slot %s has no stated reason' % s.get('slot'))
for m in (d.get('merges') or []):
    if not str(m.get('why') or '').strip():
        bad.append('merge %s -> %s has no stated reason' % (m.get('from_cnf'), m.get('slot')))

# 5. the source maps may not point at a slot that does not exist
for name in ('fdc_number_to_slot', 'cnf_id_to_slot'):
    for k, v in (d.get(name) or {}).items():
        if v not in seen:
            bad.append('%s maps %s to slot %s, which is not in the list' % (name, k, v))

# 6. THE SPEC AND THE SHIPPED ASSETS AGREE. A slot is a column index, so a spec
#    that has moved on from the binary does not fail -- it reads every later
#    nutrient one column off, into a plausible number.
spec_order = [s.get('slot') for s in slots]


def agrees(ns, spec_order, meta, size):
    """Findings for one namespace. Takes the meta and the .bin size as arguments
    rather than reading them, so the planted control below can feed it a mutant."""
    out = []
    got = list(meta.get('slots') or [])
    if got != spec_order:
        where = 'length %d vs %d' % (len(got), len(spec_order))
        for i in range(min(len(got), len(spec_order))):
            if got[i] != spec_order[i]:
                where = 'first difference at column %d: asset has slot %s, spec has %s' % (
                    i, got[i], spec_order[i])
                break
        out.append('corpus/dist/%s.json declares a DIFFERENT slot list from slots.json'
                   ' (%s) -- re-run corpus/encode.py, or every nutrient past that column'
                   ' is read off by one' % (ns, where))
        return out
    cols = meta.get('cols')
    rows = len(meta.get('index') or [])
    if cols != len(spec_order):
        out.append('corpus/dist/%s.json declares cols=%s but the slot list is %d long'
                   % (ns, cols, len(spec_order)))
        return out
    want = rows * cols * 4
    if size != want:
        out.append('corpus/dist/%s.bin is %d bytes, not rows x cols x 4 = %d x %d x 4 = %d'
                   % (ns, size, rows, cols, want))
    return out


asset_line = []
metas = {}
for ns in ('fdc', 'cnf'):
    mj = os.path.join(repo, 'corpus', 'dist', ns + '.json')
    mb = os.path.join(repo, 'corpus', 'dist', ns + '.bin')
    if not os.path.exists(mj) or not os.path.exists(mb):
        bad.append('corpus/dist/%s.{json,bin} is missing -- the shipped asset cannot be'
                   ' checked against the spec' % ns)
        continue
    try:
        meta = json.load(io.open(mj, encoding='utf-8'))
    except Exception as e:
        bad.append('corpus/dist/%s.json does not parse: %s' % (ns, e))
        continue
    found = agrees(ns, spec_order, meta, os.path.getsize(mb))
    bad.extend(found)
    if not found:
        metas[ns] = meta
        asset_line.append('%s %dx%d' % (ns, len(meta.get('index') or []), meta.get('cols')))

# PLANTED CONTROLS for leg 6, through the SAME function the real check used. The
# first is the H24 failure exactly: a spec that gained a slot against a binary
# that did not. The second is the stale-binary half of the same mistake.
if metas:
    _ns = sorted(metas)[0]
    _m = metas[_ns]
    _stale = _clone(_m)
    _stale['slots'] = [s for s in _stale['slots'] if s != 212] or _stale['slots'][1:]
    _stale['cols'] = len(_stale['slots'])
    if not agrees(_ns, spec_order, _stale, os.path.getsize(
            os.path.join(repo, 'corpus', 'dist', _ns + '.bin'))):
        bad.append('CONTROL: an asset missing a slot the spec has was NOT detected --'
                   ' the asset/spec comparison is broken, so its pass above means nothing')
    _short = _clone(_m)
    if not agrees(_ns, spec_order, _short, 4):
        bad.append('CONTROL: a .bin of the wrong byte length was NOT detected')

# 7. THE APP'S DECLARED ASSET HASHES MATCH THE SHIPPED ASSETS. app.js compares
#    CORPUS_ASSET_HASH against what a device already installed, and re-fetches on
#    a difference -- that is the corpus's only upgrade path. A stale constant is
#    silent in exactly the way the missing path was: everything keeps working on
#    the old data forever.
hash_line = 'app hashes: NOT CHECKED (app.js unreadable)'
try:
    src = io.open(os.path.join(repo, 'app.js'), encoding='utf-8').read()
except Exception:
    src = ''
if src:
    i = src.find('const CORPUS_ASSET_HASH = {')
    if i < 0:
        bad.append('app.js declares no CORPUS_ASSET_HASH -- without it corpusAcquire'
                   ' short-circuits on the namespace alone and a device that already'
                   ' holds the corpus never gets a new slot')
    else:
        block = src[i:src.find('};', i)]
        declared = {}
        for line in block.split('\n')[1:]:
            line = line.strip().rstrip(',')
            if ':' not in line:
                continue
            k, v = line.split(':', 1)
            declared[k.strip()] = v.strip().strip("'").strip('"')
        for ns, meta in sorted(metas.items()):
            want = meta.get('hash')
            got = declared.get(ns)
            if got != want:
                bad.append("app.js CORPUS_ASSET_HASH.%s is %r but corpus/dist/%s.json"
                           " ships %r -- re-stamp it, or no device will ever fetch the"
                           " new corpus" % (ns, got, ns, want))
        for ns in sorted(declared):
            if ns not in ('fdc', 'cnf'):
                bad.append('app.js declares an asset hash for unknown namespace %r' % ns)
        if metas and not [b for b in bad if 'CORPUS_ASSET_HASH' in b]:
            hash_line = 'app hashes: ' + ', '.join(
                '%s=%s' % (n, declared.get(n)) for n in sorted(metas))

if bad:
    print('SLOTS CHECK: FAIL')
    for b in bad[:14]:
        print('  ' + b)
    print('GATE: FAIL'); sys.exit(1)

print('slots: %d total = %d derived + %d judged (%d merges), bar %s, every judgment stated'
      % (len(slots), derived, judged, counts.get('judged_merges', 0), d.get('bar')))
print('  ' + APPEND_LINE + ' (3 planted violations all caught)')
print('  assets agree with the spec: ' + (', '.join(asset_line) if asset_line else 'NONE CHECKED'))
print('  ' + hash_line)
print('GATE: PASS')
PY
rc=$?
rm -f "$DIR/.slots-head.tmp"
exit $rc
