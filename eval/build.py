# -*- coding: utf-8 -*-
"""Build the matcher evaluation set from a HealthTracker export.

ONLY SCANNED ITEMS ARE USED. A scan carries a barcode, and the barcode is external
truth: it determines the product independently of anything the app, the model or the
user asserted. Every other row in the log is the model's own guess, a user
correction of that guess, or both -- none of which can grade a matcher without
grading it against itself.

Run:  python eval/build.py export.json eval/set.json
"""
import io, json, re, sys
from collections import OrderedDict

MACROS = ['kcal', 'protein_g', 'fat_g', 'carb_g', 'fiber_g', 'soluble_fiber_g']
GRAMS_RE = re.compile(r'scanned\s+([0-9.]+)\s*g')


def per100(item, grams):
    """Rebuild the per-100 g profile the scan was scaled from."""
    out = OrderedDict()
    f = 100.0 / grams
    for k in MACROS:
        if k in item:
            out[k] = round(item[k] * f, 6)
    return out


def build(export_path, out_path):
    blob = json.load(io.open(export_path, encoding='utf-8'))
    rows = OrderedDict()          # barcode -> row
    dupes = []                    # same barcode scanned twice: a free consistency check

    for date in sorted(blob.get('days', {})):
        for it in blob['days'][date].get('items', []):
            if it.get('source') != 'scan' or not it.get('barcode'):
                continue
            m = GRAMS_RE.search(it.get('notes', '') or '')
            if not m:
                continue          # no stated portion -> cannot rebuild per-100 g
            grams = float(m.group(1))
            if grams <= 0:
                continue
            bc = str(it['barcode'])
            row = OrderedDict([
                ('id', 'ev%03d' % (len(rows) + 1)),
                ('barcode', bc),
                ('query', it['name']),
                ('truth_per100', per100(it, grams)),
                ('truth_micros_per100', OrderedDict(
                    (k, round(v * 100.0 / grams, 6)) for k, v in sorted((it.get('micros') or {}).items()))),
                ('observed', OrderedDict([
                    ('date', date),
                    ('grams', grams),
                    ('confidence', it.get('confidence')),
                ])),
            ])
            if bc in rows:
                dupes.append((bc, rows[bc]['truth_per100'], row['truth_per100']))
                continue
            rows[bc] = row

    # Barcodes seen only in the price log: a real product with an OFF-derived name,
    # but no logged portion, so no composition truth. Named, and kept separate.
    name_only = []
    for bc, entry in sorted((blob.get('priceLog') or {}).items()):
        if bc not in rows:
            name_only.append(OrderedDict([('barcode', bc), ('query', entry.get('name', ''))]))

    out = OrderedDict([
        ('generated_from', export_path),
        ('schema_version', blob.get('version')),
        ('note', 'Scanned rows only. See D72 for what this set cannot measure.'),
        ('rows', list(rows.values())),
        ('name_only', name_only),
        ('consistency_checks', [
            OrderedDict([('barcode', bc), ('first', a), ('second', b),
                         ('agree', a == b)]) for bc, a, b in dupes]),
    ])
    io.open(out_path, 'w', encoding='utf-8', newline='').write(
        json.dumps(out, indent=2, ensure_ascii=False) + '\n')
    return out


if __name__ == '__main__':
    src = sys.argv[1] if len(sys.argv) > 1 else 'export.json'
    dst = sys.argv[2] if len(sys.argv) > 2 else 'eval/set.json'
    o = build(src, dst)
    print('rows (barcode + composition truth): %d' % len(o['rows']))
    print('name-only (barcode, no portion):    %d' % len(o['name_only']))
    for c in o['consistency_checks']:
        print('consistency: %s rescanned -> per-100g %s' % (c['barcode'], 'AGREE' if c['agree'] else 'DISAGREE'))
    print('written: %s' % dst)
