#!/usr/bin/env python3
"""Encode a namespace into the shipped corpus asset (D114/D115).

DENSE Float32Array, NaN for absence, one namespace per device.

  <ns>.bin   N x 46 little-endian float32, row-major, NaN where the source has
             no value. Absence is never zero: zero is a legitimate value for
             most of these nutrients (D8, D90), so the sentinel has to be
             distinguishable from it -- which is also why it compresses, a run
             of NaNs being one constant four-byte pattern.
  <ns>.json  the index: one entry per row, in row order, plus the meta the
             runtime needs and the attribution the licence requires.

Measured alternative, rejected: a sparse (slot, value) encoding is 1.15x LARGER
over the wire at this occupancy (79-93%), and for CNF larger even uncompressed.
Dense is both smaller and the form in which a mis-indexed slot cannot silently
become a plausible number for the wrong nutrient.

Usage:  python corpus/encode.py --src <dir> --ns fdc|cnf [--out corpus/dist]
"""
import argparse, collections, csv, io, json, os, struct, zipfile, hashlib, gzip

HERE = os.path.dirname(os.path.abspath(__file__))
NAN = struct.pack('<f', float('nan'))

ATTRIBUTION = {
    # The licence requires this to travel with any displayed value, not to sit
    # in a README (D114).
    'cnf': 'Canadian Nutrient File, Health Canada, 2015',
    'fdc': 'USDA FoodData Central, SR Legacy (2018)',
}


def load_spec():
    return json.load(io.open(os.path.join(HERE, 'slots.json'), encoding='utf-8'))


def rows_fdc(src, idx_of, fdc_map):
    z = zipfile.ZipFile(os.path.join(src, 'srlegacy.zip'))
    raw = json.loads(z.read(z.namelist()[0]).decode('utf-8'))
    for f in (raw.get('SRLegacyFoods') or []):
        if not f:
            continue
        vals = {}
        for fn in f.get('foodNutrients', []):
            n = (fn or {}).get('nutrient') or {}
            num = str(n.get('number') or '').strip()
            amt = fn.get('amount')
            if amt is None or num not in fdc_map:
                continue
            vals.setdefault(idx_of[fdc_map[num]], float(amt))
        yield str(f.get('fdcId') or ''), (f.get('description') or '').strip(), vals


def rows_cnf(src, idx_of, cnf_map):
    z = zipfile.ZipFile(os.path.join(src, 'cnf.zip'))

    def rd(name):
        return list(csv.DictReader(io.StringIO(z.read(name).decode('cp1252'))))

    per = collections.defaultdict(dict)
    for r in rd('NUTRIENT AMOUNT.csv'):
        fid = str(r.get('FoodID', '')).strip()
        nid = str(r.get('NutrientID', '')).strip()
        v = (r.get('NutrientValue') or '').strip()
        if not fid or nid not in cnf_map or v == '':
            continue
        try:
            fv = float(v)
        except ValueError:
            continue
        # The licence permits re-expressing per serving but NOT modifying the
        # value, so it is stored exactly as published, per 100 g.
        per[fid].setdefault(idx_of[cnf_map[nid]], fv)
    for r in rd('FOOD NAME.csv'):
        fid = str(r.get('FoodID', '')).strip()
        yield fid, (r.get('FoodDescription') or '').strip(), per.get(fid, {})


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--src', required=True)
    ap.add_argument('--ns', required=True, choices=['fdc', 'cnf'])
    ap.add_argument('--out', default=os.path.join(HERE, 'dist'))
    a = ap.parse_args()

    spec = load_spec()
    slots = [s['slot'] for s in spec['slots']]
    idx_of = {s: i for i, s in enumerate(slots)}
    ns = len(slots)

    gen = (rows_fdc(a.src, idx_of, spec['fdc_number_to_slot']) if a.ns == 'fdc'
           else rows_cnf(a.src, idx_of, spec['cnf_id_to_slot']))

    buf = bytearray()
    index = []
    filled = 0
    for fid, name, vals in gen:
        if not fid or not name:
            continue
        for i in range(ns):
            buf += struct.pack('<f', vals[i]) if i in vals else NAN
        filled += len(vals)
        index.append([fid, name])

    n = len(index)
    os.makedirs(a.out, exist_ok=True)
    digest = hashlib.sha256(bytes(buf)).hexdigest()[:12]

    meta = {
        'ns': a.ns,
        'version': 1,
        'slots': slots,
        'rows': n,
        'cols': ns,
        'hash': digest,
        'absent': 'NaN',
        'basis': 'per 100 g, exactly as published -- values are never modified',
        'attribution': ATTRIBUTION[a.ns],
        'index': index,
    }
    bin_path = os.path.join(a.out, '%s.bin' % a.ns)
    json_path = os.path.join(a.out, '%s.json' % a.ns)
    io.open(bin_path, 'wb').write(bytes(buf))
    io.open(json_path, 'w', encoding='utf-8').write(json.dumps(meta, separators=(',', ':')))

    gz = len(gzip.compress(bytes(buf), 9))
    print('%s: %d rows x %d cols, %.1f%% occupied' % (a.ns, n, ns, 100.0 * filled / max(1, n * ns)))
    print('  %-22s %9d B  (gzip %d B)' % (os.path.basename(bin_path), len(buf), gz))
    print('  %-22s %9d B' % (os.path.basename(json_path), os.path.getsize(json_path)))
    print('  sha256[:12] = %s' % digest)
    if len(buf) != n * ns * 4:
        raise SystemExit('ENCODE FAIL: byte length is not rows x cols x 4')


if __name__ == '__main__':
    main()
