# -*- coding: utf-8 -*-
"""Build the matcher evaluation inputs from a HealthTracker export.

TWO POPULATIONS, AND THEY ARE NOT INTERCHANGEABLE.

  set.json      SCANNED rows. A barcode determines the product independently of the
                app, the model and the user, so these carry EXTERNAL truth. They are
                also the only foods the app already resolves WITHOUT a matcher --
                see D72 for why that limits what they can prove.

  tolabel.json  Distinct identity strings from ai-paste rows. These are the cases the
                matcher exists for, and they carry NO truth until a human assigns a
                corpus row. This file is the labelling worklist, not data.

Run:  python eval/build.py export.json eval/
"""
import io, json, os, re, sys
from collections import OrderedDict

MACROS = ['kcal', 'protein_g', 'fat_g', 'carb_g', 'fiber_g', 'soluble_fiber_g']
GRAMS_RE = re.compile(r'scanned\s+([0-9.]+)\s*g')


def per100(d, grams, keys=None):
    f = 100.0 / grams
    ks = keys if keys is not None else MACROS
    return OrderedDict((k, round(d[k] * f, 6)) for k in ks if k in d)


def load(export_path):
    return json.load(io.open(export_path, encoding='utf-8'))


def build_verified(blob):
    rows, dupes = OrderedDict(), []
    for date in sorted(blob.get('days', {})):
        for it in blob['days'][date].get('items', []):
            if it.get('source') != 'scan' or not it.get('barcode'):
                continue
            m = GRAMS_RE.search(it.get('notes', '') or '')
            if not m:
                continue
            grams = float(m.group(1))
            if grams <= 0:
                continue
            bc = str(it['barcode'])
            row = OrderedDict([
                ('id', 'ev%03d' % (len(rows) + 1)),
                ('barcode', bc),
                ('query', it['name']),
                ('truth_per100', per100(it, grams)),
                ('truth_micros_per100', per100(it.get('micros') or {}, grams,
                                               sorted((it.get('micros') or {}).keys()))),
                ('observed', OrderedDict([('date', date), ('grams', grams),
                                          ('confidence', it.get('confidence'))])),
            ])
            if bc in rows:
                dupes.append((bc, rows[bc]['truth_per100'], row['truth_per100']))
                continue
            rows[bc] = row

    name_only = [OrderedDict([('barcode', bc), ('query', e.get('name', ''))])
                 for bc, e in sorted((blob.get('priceLog') or {}).items()) if bc not in rows]
    return list(rows.values()), name_only, dupes


def build_worklist(blob):
    """Distinct identity strings the matcher would actually be asked about."""
    seen = OrderedDict()
    for date in sorted(blob.get('days', {})):
        for it in blob['days'][date].get('items', []):
            if it.get('source') != 'ai-paste':
                continue
            # An R33 consumption EVENT carries no ai_identity -- D70 moved it to the
            # plate -- so it contributes its accepted name instead. Both are strings a
            # matcher would be asked to resolve; `asked_by` says which, because the
            # accepted name is the one worth labelling first.
            model_q = (it.get('ai_identity') or '').strip()
            q = model_q or (it.get('name') or '').strip()
            if not q:
                continue
            e = seen.setdefault(q, OrderedDict([
                ('query', q), ('asked_by', 'model' if model_q else 'accepted'),
                ('times_logged', 0), ('dates', []),
                ('example_notes', (it.get('notes') or '')[:180]),
                ('human_judged', False), ('corpus_row', None), ('undecidable', False),
            ]))
            e['times_logged'] += 1
            if date not in e['dates']:
                e['dates'].append(date)

    # A pick the user actually made is a human judgement about identity. It is not a
    # corpus label, but it is the only row where a person chose between candidates,
    # so it is marked -- those are the seed.
    for pl in (blob.get('plates') or {}).values():
        for pi in pl.get('items', []):
            pick = pi.get('identity_pick')
            if not pick:
                continue
            q = (pi.get('ai_identity') or pi.get('name') or '').strip()
            if q in seen:
                seen[q]['human_judged'] = True
                seen[q]['pick_kind'] = pick.get('kind')
            # the chosen name may differ from the model's top answer
            chosen = (pi.get('name') or '').strip()
            if chosen and chosen in seen:
                seen[chosen]['human_judged'] = True
                seen[chosen]['pick_kind'] = pick.get('kind')
                seen[chosen]['asked_by'] = 'accepted'
    return list(seen.values())


def main(src, outdir):
    blob = load(src)
    rows, name_only, dupes = build_verified(blob)
    work = build_worklist(blob)
    seed = [w for w in work if w['human_judged']]

    io.open(os.path.join(outdir, 'set.json'), 'w', encoding='utf-8', newline='').write(
        json.dumps(OrderedDict([
            ('generated_from', src),
            ('schema_version', blob.get('version')),
            ('truth', 'barcode (external)'),
            ('limits', 'See D72. Barcoded foods are the ones the app already resolves '
                       'without a matcher, so this set cannot measure the dish cases '
                       'the matcher exists for.'),
            ('rows', rows), ('name_only', name_only),
            ('consistency_checks', [OrderedDict([('barcode', b), ('agree', a == c)])
                                    for b, a, c in dupes]),
        ]), indent=2, ensure_ascii=False) + '\n')

    io.open(os.path.join(outdir, 'tolabel.json'), 'w', encoding='utf-8', newline='').write(
        json.dumps(OrderedDict([
            ('generated_from', src),
            ('instructions',
             'Set corpus_row to the identifier of the correct row. If NO row is '
             'correct, set undecidable:true and leave corpus_row null -- that is a '
             'FINDING ABOUT THE CORPUS and a finished label, not a skipped one. '
             'Never guess: a guessed row is noise in the truth column, which is '
             'worse than a smaller set.'),
            ('truth', 'NONE until a human sets corpus_row or marks undecidable'),
            ('labeller', 'single (the app author). See D74: this set measures '
                         'agreement with ONE PERSON JUDGEMENT, not correctness.'),
            ('queries', work),
        ]), indent=2, ensure_ascii=False) + '\n')

    print('verified rows (barcode truth):      %d' % len(rows))
    print('name-only (barcode, no portion):    %d' % len(name_only))
    print('distinct queries to label:          %d' % len(work))
    print('  of which human-judged (seed):     %d' % len(seed))
    done = [w for w in work if w['corpus_row']]
    undec = [w for w in work if w.get('undecidable')]
    print('  labelled with a row:              %d' % len(done))
    print('  marked undecidable (a FINDING):   %d' % len(undec))
    print('  not yet looked at:                %d' % (len(work) - len(done) - len(undec)))
    print('  asked by model / accepted name:   %d / %d'
          % (len([w for w in work if w['asked_by'] == 'model']),
             len([w for w in work if w['asked_by'] == 'accepted'])))
    for b, a, c in dupes:
        print('consistency: %s rescanned -> %s' % (b, 'AGREE' if a == c else 'DISAGREE'))
    print('written: %s, %s' % (os.path.join(outdir, 'set.json'),
                               os.path.join(outdir, 'tolabel.json')))


if __name__ == '__main__':
    main(sys.argv[1] if len(sys.argv) > 1 else 'export.json',
         sys.argv[2] if len(sys.argv) > 2 else 'eval')
