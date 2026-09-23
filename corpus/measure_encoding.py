"""Dense vs sparse, measured on the real 46 slots and the real values.

The acquisition path pays the COMPRESSED cost, so both forms are gzipped. Dense
uses NaN as the absent sentinel -- absence is never zero (D8), and zero is a
legitimate value for most of these nutrients.
"""
import zipfile, json, csv, io, os, struct, gzip, collections

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = r'C:\Users\thoma\projects\healthtracker'
spec = json.load(io.open(os.path.join(REPO, 'corpus', 'slots.json'), encoding='utf-8'))
SLOTS = [s['slot'] for s in spec['slots']]
IDX = {s: i for i, s in enumerate(SLOTS)}
FDC_MAP = {k: v for k, v in spec['fdc_number_to_slot'].items()}
CNF_MAP = {k: v for k, v in spec['cnf_id_to_slot'].items()}
NS = len(SLOTS)
print('slots: %d' % NS)


def sr_rows():
    z = zipfile.ZipFile(os.path.join(HERE, 'srlegacy.zip'))
    raw = json.loads(z.read(z.namelist()[0]).decode('utf-8'))
    for f in (raw.get('SRLegacyFoods') or []):
        if not f:
            continue
        vals = {}
        for fn in f.get('foodNutrients', []):
            n = (fn or {}).get('nutrient') or {}
            num = str(n.get('number') or '').strip()
            amt = fn.get('amount')
            if amt is None or num not in FDC_MAP:
                continue
            vals.setdefault(IDX[FDC_MAP[num]], float(amt))
        yield vals


def cnf_rows():
    z = zipfile.ZipFile(os.path.join(HERE, 'cnf.zip'))

    def rows(name):
        return list(csv.DictReader(io.StringIO(z.read(name).decode('cp1252'))))
    per = collections.defaultdict(dict)
    for r in rows('NUTRIENT AMOUNT.csv'):
        fid = str(r.get('FoodID', '')).strip()
        nid = str(r.get('NutrientID', '')).strip()
        v = (r.get('NutrientValue') or '').strip()
        if not fid or nid not in CNF_MAP or v == '':
            continue
        try:
            fv = float(v)
        except ValueError:
            continue
        per[fid].setdefault(IDX[CNF_MAP[nid]], fv)
    n_foods = len(rows('FOOD NAME.csv'))
    return per, n_foods


def report(label, rows, n_foods):
    filled = 0
    dense = bytearray()
    sparse = bytearray()
    NAN = struct.pack('<f', float('nan'))
    hist = collections.Counter()
    for vals in rows:
        filled += len(vals)
        hist[len(vals)] += 1
        # dense: NS float32, NaN where absent
        for i in range(NS):
            if i in vals:
                dense += struct.pack('<f', vals[i])
            else:
                dense += NAN
        # sparse: u8 count, then (u8 slot index, f32 value) pairs
        sparse += struct.pack('<B', min(len(vals), 255))
        for i in sorted(vals):
            sparse += struct.pack('<Bf', i, vals[i])
    cells = n_foods * NS
    gz_d = len(gzip.compress(bytes(dense), 9))
    gz_s = len(gzip.compress(bytes(sparse), 9))
    print()
    print('--- %s: %d foods x %d slots = %d cells' % (label, n_foods, NS, cells))
    print('    occupied cells      : %d (%.1f%%)' % (filled, 100.0 * filled / cells))
    print('    mean slots per food : %.1f of %d' % (filled / max(1, n_foods), NS))
    print('    DENSE  raw %9d B  gzip %9d B' % (len(dense), gz_d))
    print('    SPARSE raw %9d B  gzip %9d B' % (len(sparse), gz_s))
    print('    sparse/dense raw  %.2fx   gzip %.2fx' % (
        len(sparse) / max(1, len(dense)), gz_s / max(1, gz_d)))
    return len(dense), gz_d, len(sparse), gz_s


d1, g1, s1, h1 = report('SR Legacy', sr_rows(), 7793)
per, nf = cnf_rows()
d2, g2, s2, h2 = report('CNF', (per[k] for k in sorted(per)), nf)

print()
print('=== BOTH NAMESPACES TOGETHER ===')
print('    DENSE  raw %9d B (%.2f MB)  gzip %9d B (%.2f MB)'
      % (d1 + d2, (d1 + d2) / 1048576.0, g1 + g2, (g1 + g2) / 1048576.0))
print('    SPARSE raw %9d B (%.2f MB)  gzip %9d B (%.2f MB)'
      % (s1 + s2, (s1 + s2) / 1048576.0, h1 + h2, (h1 + h2) / 1048576.0))
print('    over the wire, sparse is %.2fx dense' % ((h1 + h2) / float(g1 + g2)))
