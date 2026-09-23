"""Measure the matching problem before designing for it.

Two measurements:
  A. CNF vs SR Legacy by NAME -- two databases naming the same foods with no
     shared identifier. This is the problem in its purest form, and both sides
     are to hand.
  B. the real export -- how many items are SCANNED (label composition known, so
     distance-scorable without a human label), and what their names look like.

Aggregates only from B; the export is the user's own data and is never committed.
"""
import json, io, os, re, csv, zipfile, collections, itertools

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = r'C:\Users\thoma\projects\healthtracker'

STOP = set('and or with without in of the a an raw cooked boiled fresh frozen canned '
           'dried prepared unprepared includes commodity usda nfs ns'.split())


def norm(s):
    s = str(s or '').lower()
    s = re.sub(r'\(.*?\)', ' ', s)
    s = re.sub(r'[^a-z0-9 ]+', ' ', s)
    return re.sub(r'\s+', ' ', s).strip()


def toks(s):
    return [t for t in norm(s).split() if t and t not in STOP]


# ---- A. CNF vs SR Legacy ----------------------------------------------------
zs = zipfile.ZipFile(os.path.join(HERE, 'srlegacy.zip'))
sr = json.loads(zs.read(zs.namelist()[0]).decode('utf-8'))
sr_names = [(f.get('description') or '').strip()
            for f in (sr.get('SRLegacyFoods') or []) if f and f.get('description')]

zc = zipfile.ZipFile(os.path.join(HERE, 'cnf.zip'))
rows = list(csv.DictReader(io.StringIO(zc.read('FOOD NAME.csv').decode('cp1252'))))
cnf_names = [(r.get('FoodDescription') or '').strip() for r in rows if r.get('FoodDescription')]

print('A. CNF vs SR Legacy, by name')
print('   SR Legacy names : %d' % len(sr_names))
print('   CNF names       : %d' % len(cnf_names))

sr_exact = set(n.lower() for n in sr_names)
cnf_exact = set(n.lower() for n in cnf_names)
print('   EXACT (case-folded) overlap      : %d  (%.2f%% of CNF)'
      % (len(sr_exact & cnf_exact), 100.0 * len(sr_exact & cnf_exact) / len(cnf_exact)))

sr_norm = collections.defaultdict(list)
for n in sr_names:
    sr_norm[norm(n)].append(n)
cnf_norm = set(norm(n) for n in cnf_names)
both = set(sr_norm) & cnf_norm
print('   NORMALISED overlap               : %d  (%.2f%% of CNF)'
      % (len(both), 100.0 * len(both) / len(cnf_norm)))

# token-set equality, order-insensitive
sr_tok = collections.defaultdict(list)
for n in sr_names:
    sr_tok[frozenset(toks(n))].append(n)
cnf_tok = [frozenset(toks(n)) for n in cnf_names]
hit = sum(1 for t in cnf_tok if t and t in sr_tok)
print('   TOKEN-SET equality               : %d  (%.2f%% of CNF)'
      % (hit, 100.0 * hit / len(cnf_tok)))

# best Jaccard for a sample, to see the shape of "close but not equal"
sr_index = collections.defaultdict(set)
for i, n in enumerate(sr_names):
    for t in toks(n):
        sr_index[t].add(i)
sr_toksets = [set(toks(n)) for n in sr_names]

import random
random.seed(7)
sample = random.sample(range(len(cnf_names)), 400)
buckets = collections.Counter()
examples = []
for i in sample:
    q = set(toks(cnf_names[i]))
    if not q:
        buckets['no-tokens'] += 1
        continue
    cand = set()
    for t in q:
        cand |= sr_index.get(t, set())
    best, bi = 0.0, -1
    for c in cand:
        s2 = sr_toksets[c]
        j = len(q & s2) / float(len(q | s2))
        if j > best:
            best, bi = j, c
    if best >= 1.0:
        buckets['1.00 exact token set'] += 1
    elif best >= 0.8:
        buckets['0.80-0.99'] += 1
    elif best >= 0.6:
        buckets['0.60-0.79'] += 1
    elif best >= 0.4:
        buckets['0.40-0.59'] += 1
    elif best > 0:
        buckets['0.01-0.39'] += 1
    else:
        buckets['0.00 no shared token'] += 1
    if 0.4 <= best < 0.8 and len(examples) < 8:
        examples.append((cnf_names[i], sr_names[bi], round(best, 2)))

print('\n   best token-Jaccard against SR Legacy, 400-name CNF sample:')
for k in ['1.00 exact token set', '0.80-0.99', '0.60-0.79', '0.40-0.59', '0.01-0.39',
          '0.00 no shared token', 'no-tokens']:
    if buckets.get(k):
        print('     %-22s %4d  (%.1f%%)' % (k, buckets[k], 100.0 * buckets[k] / len(sample)))
print('\n   what the ambiguous middle looks like:')
for a, b, j in examples:
    print('     %.2f  CNF: %-44s SR: %s' % (j, a[:44], b[:44]))

# ---- B. the real export ------------------------------------------------------
p = os.path.join(REPO, 'export.json')
if not os.path.exists(p):
    print('\nB. no export.json present')
    raise SystemExit(0)
blob = json.load(io.open(p, encoding='utf-8'))
days = blob.get('days') or {}
items = [it for d in days.values() for it in (d.get('items') or [])]
by_src = collections.Counter(it.get('source') or '?' for it in items)
with_micros = [it for it in items if it.get('micros')]
scans = [it for it in items if it.get('source') == 'scan']
scan_micros = [it for it in scans if it.get('micros')]
named = collections.Counter(norm(it.get('name')) for it in scans)

print('\nB. the export (aggregates only)')
print('   days %d, items %d' % (len(days), len(items)))
print('   by source: %s' % dict(by_src))
print('   items carrying micros        : %d' % len(with_micros))
print('   SCANNED items                : %d' % len(scans))
print('   SCANNED items WITH micros    : %d   <- the distance-scorable core'
      % len(scan_micros))
print('   distinct scanned products    : %d' % len(named))
mc = collections.Counter()
for it in scan_micros:
    mc[len(it.get('micros') or {})] += 1
print('   micros per scanned item      : %s' % dict(sorted(mc.items())))
