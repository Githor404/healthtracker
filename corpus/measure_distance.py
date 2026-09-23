"""Does nutritional distance separate same-food from different-food?

Name similarity does not: measured, same-food pairs score 0.60 token-Jaccard and
different-food pairs score 0.67. So the question is whether COMPOSITION does the
separating that names cannot.

The corpus contains its own answer. 1,149 CNF names have a token-set-identical
SR Legacy name -- two independent laboratories measuring the same food. Their
distance distribution is what "the same food, measured twice" actually looks
like, and it can be compared against random pairs with no labelling at all.
"""
import json, io, os, re, csv, zipfile, collections, random, math, struct

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = r'C:\Users\thoma\projects\healthtracker'
spec = json.load(io.open(os.path.join(REPO, 'corpus', 'slots.json'), encoding='utf-8'))
SLOTS = [s['slot'] for s in spec['slots']]
NS = len(SLOTS)

STOP = set('and or with without in of the a an raw cooked boiled fresh frozen canned '
           'dried prepared unprepared includes commodity usda nfs ns'.split())


def toks(s):
    s = re.sub(r'\(.*?\)', ' ', str(s or '').lower())
    s = re.sub(r'[^a-z0-9 ]+', ' ', s)
    return frozenset(t for t in s.split() if t and t not in STOP)


def load(ns):
    meta = json.load(io.open(os.path.join(REPO, 'corpus', 'dist', ns + '.json'), encoding='utf-8'))
    raw = io.open(os.path.join(REPO, 'corpus', 'dist', ns + '.bin'), 'rb').read()
    vals = struct.unpack('<%df' % (len(raw) // 4), raw)
    return meta, vals


fm, fv = load('fdc')
cm, cv = load('cnf')
print('fdc %d rows, cnf %d rows, %d slots' % (fm['rows'], cm['rows'], NS))

# the four slots every food has, so distance is always defined on the same axes
# (protein 203, fat 204, carb 205, kcal 208) plus the minerals that clear 95%
AXES = [203, 204, 205, 208, 301, 303, 307]
AX = [SLOTS.index(a) for a in AXES]


def row(vals, i):
    return vals[i * NS:(i + 1) * NS]


def dist(a, b):
    # mean absolute difference, each axis scaled by the pair's own magnitude so a
    # 2 g protein gap is not swamped by a 300 kcal one. Axes absent on either side
    # are skipped -- absence is not zero, so it cannot enter an average.
    used, tot = 0, 0.0
    for k in AX:
        x, y = a[k], b[k]
        if x != x or y != y:
            continue
        m = max(abs(x), abs(y), 1e-6)
        tot += abs(x - y) / m
        used += 1
    return (tot / used) if used >= 4 else None


f_by_tok = collections.defaultdict(list)
for i, (fid, name) in enumerate(fm['index']):
    f_by_tok[toks(name)].append(i)

pairs = []
for j, (cid, name) in enumerate(cm['index']):
    t = toks(name)
    if t and t in f_by_tok:
        pairs.append((j, f_by_tok[t][0], name))
print('token-set-identical CNF/FDC pairs: %d' % len(pairs))

same = []
for j, i, name in pairs:
    d = dist(row(cv, j), row(fv, i))
    if d is not None:
        same.append(d)

random.seed(11)
diff = []
for _ in range(4000):
    j = random.randrange(cm['rows'])
    i = random.randrange(fm['rows'])
    d = dist(row(cv, j), row(fv, i))
    if d is not None:
        diff.append(d)


def pct(a, q):
    a = sorted(a)
    return a[min(len(a) - 1, int(q * len(a)))]


print('\n                       n      p10    p25    p50    p75    p90')
for label, arr in (('SAME food (name-matched)', same), ('RANDOM pairs', diff)):
    print('%-24s %5d  %5.2f  %5.2f  %5.2f  %5.2f  %5.2f'
          % (label, len(arr), pct(arr, .10), pct(arr, .25), pct(arr, .50), pct(arr, .75), pct(arr, .90)))

# separability: at a threshold, what fraction of each side falls below it
print('\n   threshold   same-below   random-below   (a usable threshold keeps')
print('                                             same high and random low)')
for th in (0.10, 0.15, 0.20, 0.30, 0.40, 0.50):
    s = 100.0 * sum(1 for d in same if d <= th) / max(1, len(same))
    r = 100.0 * sum(1 for d in diff if d <= th) / max(1, len(diff))
    print('     %.2f       %5.1f%%        %5.1f%%' % (th, s, r))

# --- is this agreement, or is it value IDENTITY? -----------------------------
z = sum(1 for d in same if d == 0.0)
nz = sorted(d for d in same if d > 0.0)
print('\npairs with distance EXACTLY 0.00 : %d of %d  (%.1f%%)' % (z, len(same), 100.0 * z / len(same)))
print('non-zero pairs                   : %d' % len(nz))
if nz:
    print('  their median / p75 / p90       : %.3f / %.3f / %.3f'
          % (nz[len(nz) // 2], nz[int(.75 * len(nz))], nz[int(.90 * len(nz))]))
