#!/usr/bin/env python3
"""Derive the micronutrient corpus SLOT LIST (D114).

The slot list is APPEND-ONLY FOREVER, so it is derived from what the sources
actually populate and never curated from memory. Two sets are produced and kept
separately countable, because a curated list wearing a derivation's clothes
would be the failure this guards against:

  DERIVED  -- every nutrient clearing >=90% coverage in EITHER source, keyed by
              the USDA SR nutrient number (FDC exposes it as `nutrient.number`;
              CNF uses it as `NutrientID`).
  JUDGED   -- hand-ruled entries, each named with its reason: merges where two
              source numbers are one nutrient, and additions for nutrients the
              app already stores that fall below the bar.

WHY THE BAR IS EVALUATED ON THE UNION. FDC's retinol activity equivalents is
SR 320 at 88.8% and CNF's is 814 at 95.4%: the two halves of ONE nutrient fell
on opposite sides of the threshold. Applied per-namespace, the bar would make a
nutrient exist or not depending on locale, with nothing on the surface to
explain why. The union plus this override table is what stops that.

SOURCES (not committed -- see corpus/README.md):
  FoodData_Central_sr_legacy_food_json_2018-04.zip   7,793 foods
  cnf-fcen-csv.zip                                   5,690 foods

Usage:  python corpus/derive_slots.py --src <dir-with-the-two-zips> [--check]
        --check re-derives and fails if corpus/slots.json would change.
"""
import argparse, collections, csv, io, json, os, sys, zipfile

BAR = 0.90

# ---- JUDGED, every entry named --------------------------------------------
# MERGES: one nutrient carried under two different source numbers. The canonical
# slot is FDC's number where FDC has the nutrient at all, because FDC is the
# default namespace; CNF's number maps into it.
MERGES = [
    {'slot': 320, 'from_cnf': 814,
     'why': 'Retinol activity equivalents. FDC SR 320 (88.8%) is BELOW the bar and CNF 814 '
            '(95.4%) is above it -- the two halves of one nutrient on opposite sides. Without '
            'this merge, vitamin A would exist or not depending on locale.'},
    {'slot': 328, 'from_cnf': 339,
     'why': 'Vitamin D (D2+D3). The sources use entirely different numbers -- FDC 328, CNF 339 '
            '-- for the same quantity in the same unit.'},
]

# ADDITIONS: nutrients the app already stores (MICRO_SPEC) that fall below the
# bar. A corpus that cannot hold a nutrient the app already has is the cost the
# generosity ruling was written against: an unused slot is 4 bytes, a missing
# one is a schema that cannot hold the value.
ADDITIONS = [
    {'slot': 328, 'key': 'vitamin_d_ug', 'label': 'Vitamin D', 'unit': 'ug',
     'why': 'In MICRO_SPEC and supplied by OFF labels today. Clears the bar in NEITHER source: '
            '66.5% in SR Legacy (SR 328) and 87.9% in CNF (id 339), which is why it is also a merge.'},
    {'slot': 269, 'key': 'sugars_g', 'label': 'Sugars', 'unit': 'g',
     'why': 'In MICRO_SPEC and supplied by OFF labels today. 77.1% in SR Legacy, below the bar. '
            'FDC 269 and CNF 269 agree, so no merge is needed.'},
]

# The app's existing keys, mapped onto their slots so the corpus can hold what
# the app already stores. Slots not named here get a key derived from the source
# name at build time.
MICRO_KEYS = {
    307: 'sodium_mg', 306: 'potassium_mg', 301: 'calcium_mg', 303: 'iron_mg',
    304: 'magnesium_mg', 309: 'zinc_mg', 601: 'cholesterol_mg', 320: 'vitamin_a_ug',
    401: 'vitamin_c_mg', 328: 'vitamin_d_ug', 418: 'vitamin_b12_ug', 417: 'folate_ug',
    606: 'saturated_fat_g', 269: 'sugars_g',
}


def _rows(z, name):
    b = z.read(name)
    for enc in ('utf-8-sig', 'cp1252', 'latin-1'):
        try:
            return list(csv.DictReader(io.StringIO(b.decode(enc))))
        except UnicodeDecodeError:
            continue
    raise SystemExit('undecodable: ' + name)


def measure(src):
    zs = zipfile.ZipFile(os.path.join(src, 'srlegacy.zip'))
    raw = json.loads(zs.read(zs.namelist()[0]).decode('utf-8'))
    foods = [f for f in (raw.get('SRLegacyFoods') or []) if f]
    sr_total = len(foods)
    sr = {}
    for f in foods:
        seen = set()
        for fn in f.get('foodNutrients', []):
            n = (fn or {}).get('nutrient') or {}
            num = n.get('number')
            if num is None or fn.get('amount') is None:
                continue
            num = str(num).strip()
            if num in seen:
                continue
            seen.add(num)
            e = sr.setdefault(num, {'name': n.get('name'), 'unit': n.get('unitName'), 'count': 0})
            e['count'] += 1

    zc = zipfile.ZipFile(os.path.join(src, 'cnf.zip'))
    cnf_def = {}
    for r in _rows(zc, 'NUTRIENT NAME.csv'):
        cnf_def[str(r['NutrientID']).strip()] = (r.get('NutrientName', '').strip(),
                                                 r.get('NutrientUnit', '').strip())
    cnf_total = len(_rows(zc, 'FOOD NAME.csv'))
    pairs = set()
    cnf_pop = collections.Counter()
    for r in _rows(zc, 'NUTRIENT AMOUNT.csv'):
        fid = str(r.get('FoodID', '')).strip()
        nid = str(r.get('NutrientID', '')).strip()
        if not fid or not nid or (r.get('NutrientValue') or '').strip() == '':
            continue
        if (fid, nid) in pairs:
            continue
        pairs.add((fid, nid))
        cnf_pop[nid] += 1
    return sr, sr_total, cnf_def, cnf_pop, cnf_total


def build(src):
    sr, sr_total, cnf_def, cnf_pop, cnf_total = measure(src)
    sr_ok = {k for k, v in sr.items() if v['count'] / sr_total >= BAR}
    cnf_ok = {k for k, c in cnf_pop.items() if c / cnf_total >= BAR}
    derived = sorted(sr_ok | cnf_ok, key=lambda k: int(k) if k.isdigit() else 10 ** 6)

    merged_away = {str(m['from_cnf']): m['slot'] for m in MERGES}
    # Coverage is read THROUGH the merge. Reading it off the canonical number
    # alone made vitamin D report CNF 0.0% when CNF holds it at 87.9% under 339 --
    # the artifact would have understated the evidence its own ruling rests on.
    slot_to_cnf = {m['slot']: str(m['from_cnf']) for m in MERGES}

    def cnf_pct_for(slot):
        nid = slot_to_cnf.get(slot, str(slot))
        return round(cnf_pop.get(nid, 0) / cnf_total * 100, 1)

    def cnf_name_for(slot):
        nid = slot_to_cnf.get(slot, str(slot))
        return (cnf_def.get(nid) or (None, None))[0]
    slots = {}
    for num in derived:
        slot = merged_away.get(num, int(num) if num.isdigit() else None)
        if slot is None:
            continue
        s = sr.get(str(slot)) or sr.get(num)
        c = cnf_def.get(str(slot)) or cnf_def.get(num)
        slots.setdefault(slot, {
            'slot': slot,
            'origin': 'derived',
            'fdc_name': (sr.get(str(slot)) or {}).get('name'),
            'fdc_pct': round((sr.get(str(slot), {}).get('count', 0)) / sr_total * 100, 1),
            'cnf_name': cnf_name_for(slot),
            'cnf_pct': cnf_pct_for(slot),
            'unit': (s or {}).get('unit') or (c or (None, None))[1],
        })

    for a in ADDITIONS:
        slot = a['slot']
        e = slots.get(slot)
        if e is None:
            e = slots[slot] = {
                'slot': slot, 'origin': 'judged',
                'fdc_name': (sr.get(str(slot)) or {}).get('name'),
                'fdc_pct': round((sr.get(str(slot), {}).get('count', 0)) / sr_total * 100, 1),
                'cnf_name': cnf_name_for(slot),
                'cnf_pct': cnf_pct_for(slot),
                'unit': a['unit'],
            }
        e['why'] = a['why']
        e['label'] = a['label']

    # source -> slot maps, which are what the encoder reads
    fdc_map, cnf_map = {}, {}
    for slot in slots:
        if str(slot) in sr:
            fdc_map[str(slot)] = slot
        if str(slot) in cnf_def:
            cnf_map[str(slot)] = slot
    for m in MERGES:
        cnf_map[str(m['from_cnf'])] = m['slot']
        if str(m['slot']) in sr:
            fdc_map[str(m['slot'])] = m['slot']

    for slot, e in slots.items():
        e.setdefault('key', MICRO_KEYS.get(slot))

    out = {
        'version': 1,
        'bar': BAR,
        'sr_foods': sr_total,
        'cnf_foods': cnf_total,
        'counts': {
            'derived': sum(1 for e in slots.values() if e['origin'] == 'derived'),
            'judged_additions': sum(1 for e in slots.values() if e['origin'] == 'judged'),
            'judged_merges': len(MERGES),
            'total': len(slots),
        },
        'merges': MERGES,
        'additions': ADDITIONS,
        'slots': [slots[k] for k in sorted(slots)],
        'fdc_number_to_slot': fdc_map,
        'cnf_id_to_slot': cnf_map,
    }
    return out


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--src', required=True)
    ap.add_argument('--check', action='store_true')
    a = ap.parse_args()
    out = build(a.src)
    here = os.path.dirname(os.path.abspath(__file__))
    path = os.path.join(here, 'slots.json')
    text = json.dumps(out, indent=1, sort_keys=True) + '\n'
    if a.check:
        cur = io.open(path, encoding='utf-8').read() if os.path.exists(path) else ''
        if cur != text:
            print('SLOTS CHECK: FAIL - slots.json does not match a fresh derivation')
            sys.exit(1)
        print('SLOTS CHECK: PASS - slots.json matches a fresh derivation')
        return
    io.open(path, 'w', encoding='utf-8').write(text)
    c = out['counts']
    print('derived %d + judged additions %d (merges %d) = %d slots'
          % (c['derived'], c['judged_additions'], c['judged_merges'], c['total']))
    print('wrote', path)


if __name__ == '__main__':
    main()
