"""How do corpus names mark dry / raw / cooked, and how often?

The detector has to be built from what the names actually say, not from what a
reasonable schema would say.
"""
import json, io, os, re, collections, struct

REPO = r'C:\Users\thoma\projects\healthtracker'
OUT = {}
for ns in ('cnf', 'fdc'):
    meta = json.load(io.open(os.path.join(REPO, 'corpus', 'dist', ns + '.json'), encoding='utf-8'))
    names = [n for _i, n in meta['index']]
    OUT[ns] = (meta, names)

DRY = ['dry', 'dried', 'dehydrated', 'uncooked', 'instant', 'powder', 'mix', 'concentrate', 'flakes']
RAW = ['raw', 'fresh']
COOKED = ['cooked', 'boiled', 'baked', 'roasted', 'fried', 'steamed', 'prepared',
          'simmered', 'grilled', 'braised', 'poached', 'stewed', 'microwaved', 'toasted']

for ns, (meta, names) in OUT.items():
    print('=== %s: %d names' % (ns, len(names)))
    hit = collections.Counter()
    for n in names:
        low = ' ' + re.sub(r'[^a-z0-9]+', ' ', n.lower()) + ' '
        for grp, words in (('dry', DRY), ('raw', RAW), ('cooked', COOKED)):
            if any((' ' + w + ' ') in low for w in words):
                hit[grp] += 1
    none = len(names) - sum(1 for n in names
                            if any((' ' + w + ' ') in ' ' + re.sub(r'[^a-z0-9]+', ' ', n.lower()) + ' '
                                   for w in DRY + RAW + COOKED))
    for k in ('dry', 'raw', 'cooked'):
        print('   %-7s %5d  (%.1f%%)' % (k, hit[k], 100.0 * hit[k] / len(names)))
    print('   none    %5d  (%.1f%%)' % (none, 100.0 * none / len(names)))

    # the words that actually carry weight, individually
    per = collections.Counter()
    for n in names:
        low = ' ' + re.sub(r'[^a-z0-9]+', ' ', n.lower()) + ' '
        for w in DRY + RAW + COOKED:
            if (' ' + w + ' ') in low:
                per[w] += 1
    print('   top state words: %s' % ', '.join('%s=%d' % (w, c) for w, c in per.most_common(12)))
    print()

# the ramen case, concretely
meta, names = OUT['cnf']
raw = io.open(os.path.join(REPO, 'corpus', 'dist', 'cnf.bin'), 'rb').read()
vals = struct.unpack('<%df' % (len(raw) // 4), raw)
SL = meta['slots']
KC = SL.index(208)
COLS = meta['cols']
print('=== the ramen case: what the candidate list actually offers')
for i, n in enumerate(names):
    if 'ramen' in n.lower() or ('noodle' in n.lower() and len(n) < 70):
        k = vals[i * COLS + KC]
        print('   %-62s %s kcal/100g' % (n[:62], ('%.0f' % k) if k == k else '-'))
