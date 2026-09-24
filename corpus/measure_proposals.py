"""How many of the real items does the matcher propose anything for at all?

Mirrors app.js exactly: the same stop list, the same tokeniser, the same Jaccard
ranking, the same seven axes, the same 0.20 line. Aggregates only -- the export
is the user's own data and is never committed.
"""
import json, io, os, re, struct, collections

REPO = r'C:\Users\thoma\projects\healthtracker'
NS = 'cnf'                      # the user is in Canada; this is their namespace

meta = json.load(io.open(os.path.join(REPO, 'corpus', 'dist', NS + '.json'), encoding='utf-8'))
raw = io.open(os.path.join(REPO, 'corpus', 'dist', NS + '.bin'), 'rb').read()
vals = struct.unpack('<%df' % (len(raw) // 4), raw)
SLOTS = meta['slots']
COLS = meta['cols']
INDEX = meta['index']

STOP = ('and or with without in of the a an raw cooked boiled fresh frozen canned '
        'dried prepared unprepared includes commodity usda nfs ns').split()


def toks(s):
    t = re.sub(r'\(.*?\)', ' ', str(s or '').lower())
    t = re.sub(r'[^a-z0-9 ]+', ' ', t).split()
    out = []
    for x in t:
        if x and x not in STOP and x not in out:
            out.append(x)
    return out


idx = collections.defaultdict(list)
for r, (_id, nm) in enumerate(INDEX):
    for tk in toks(nm):
        idx[tk].append(r)


def candidates(name, limit=8):
    q = toks(name)
    if not q:
        return []
    score = collections.Counter()
    for tk in q:
        for r in idx.get(tk, ()):
            score[r] += 1
    out = []
    for r, c in score.items():
        t = toks(INDEX[r][1])
        union = len(t) + len(q) - c
        out.append((c / union if union else 0, c, r))
    out.sort(reverse=True)
    return out[:limit]


AXES = [203, 204, 205, 208, 301, 303, 307]
AXI = [SLOTS.index(a) for a in AXES]
FIELD = {203: 'protein_g', 204: 'fat_g', 205: 'carb_g', 208: 'kcal'}
MICRO = {301: 'calcium_mg', 303: 'iron_mg', 307: 'sodium_mg'}


def vector(it):
    g = it.get('grams')
    try:
        g = float(g)
    except (TypeError, ValueError):
        return None
    if not g > 0:
        return None
    v = {}
    for slot in AXES:
        x = None
        if slot in FIELD:
            x = it.get(FIELD[slot])
        elif slot in MICRO:
            x = (it.get('micros') or {}).get(MICRO[slot])
        if x is None or x == '':
            continue
        try:
            v[slot] = float(x) * (100.0 / g)
        except (TypeError, ValueError):
            pass
    return v


def row(r):
    return vals[r * COLS:(r + 1) * COLS]


def dist(v, r):
    rr = row(r)
    used, tot = 0, 0.0
    for slot in AXES:
        a = v.get(slot)
        b = rr[SLOTS.index(slot)]
        if a is None or b != b:
            continue
        m = max(abs(a), abs(b), 1e-6)
        tot += abs(a - b) / m
        used += 1
    return (tot / used) if used >= 4 else None


blob = json.load(io.open(os.path.join(REPO, 'export.json'), encoding='utf-8'))
items = [it for d in (blob.get('days') or {}).values() for it in (d.get('items') or [])]

by_src = collections.Counter()
prop = collections.Counter()
grams = collections.Counter()
scan_best = []
none_named = []

for it in items:
    src = it.get('source') or '?'
    by_src[src] += 1
    c = candidates(it.get('name'))
    prop[(src, bool(c))] += 1
    if not c:
        none_named.append(it.get('name'))
    if it.get('grams'):
        grams[src] += 1
    if src == 'scan' and c:
        v = vector(it)
        if v:
            ds = [(dist(v, r), r) for _, _, r in c]
            ds = [(d, r) for d, r in ds if d is not None]
            if ds:
                ds.sort()
                scan_best.append((it.get('name'), ds[0][0], INDEX[ds[0][1]][1]))

print('namespace: %s  (%d rows)' % (NS, len(INDEX)))
print('items: %d   by source: %s' % (len(items), dict(by_src)))
print('items carrying grams: %s' % dict(grams))
print()
print('DOES THE MATCHER PROPOSE ANYTHING AT ALL?')
for src in sorted(by_src):
    yes = prop[(src, True)]
    print('  %-10s %2d of %2d items get at least one candidate  (%.0f%%)'
          % (src, yes, by_src[src], 100.0 * yes / by_src[src]))
if none_named:
    print('\n  names that produced NO candidate at all: %d' % len(none_named))
    for n in none_named[:6]:
        print('    %s' % str(n)[:60])

print()
print('SCANNED ITEMS -- what the 0.20 line would do')
if not scan_best:
    print('  none scorable (a vector needs grams and four shared axes)')
else:
    below = [x for x in scan_best if x[1] <= 0.20]
    print('  scorable: %d' % len(scan_best))
    print('  would PROPOSE (<=0.20): %d' % len(below))
    print('  would DECLINE ( >0.20): %d' % (len(scan_best) - len(below)))
    print()
    for nm, d, best in sorted(scan_best, key=lambda x: x[1]):
        print('    %.3f  %-34s -> %s' % (d, str(nm)[:34], str(best)[:44]))
