# -*- coding: utf-8 -*-
"""Score a matcher's predictions against the evaluation set.

THE DIRECTIONAL RULE, ENFORCED STRUCTURALLY RATHER THAN REMEMBERED.

No accuracy figure is ever printed without its denominator, and below
DIRECTIONAL_N every figure is prefixed DIRECTIONAL. A percentage over seven rows
reads exactly like a percentage over seven hundred once it has been copied into a
sentence, so the label travels with the number instead of sitting in a footnote.

Predictions file:
  {"matcher": "<name/version>",
   "predictions": [{"id": "ev001", "corpus_row": "fdc:123456",
                    "per100": {"kcal": 325, "protein_g": 0.5, ...}}]}

Run:  python eval/score.py eval/set.json predictions.json [eval/tolabel.json]
"""
import io, json, sys
from collections import OrderedDict

DIRECTIONAL_N = 30          # below this, every figure is labelled, not merely noted
TOL = 0.20                  # per-nutrient relative tolerance for "composition agrees"
FLOOR = 1.0                 # absolute floor so near-zero values do not fail on noise
MACROS = ['kcal', 'protein_g', 'fat_g', 'carb_g', 'fiber_g', 'soluble_fiber_g']


def agrees(truth, pred, tol=TOL):
    """Per-nutrient relative agreement. A missing prediction is a miss, never a pass."""
    detail = OrderedDict()
    for k in MACROS:
        if k not in truth:
            continue
        t = float(truth[k])
        if k not in pred:
            detail[k] = False
            continue
        p = float(pred[k])
        detail[k] = abs(p - t) <= max(abs(t) * tol, FLOOR)
    return detail


def pct(n, d):
    return '--' if not d else '%.0f%%' % (100.0 * n / d)


def fmt(label, n, d, directional):
    tag = 'DIRECTIONAL ' if directional else ''
    return '  %s%-34s %s  (%d of %d)' % (tag, label, pct(n, d), n, d)


def main(set_path, pred_path, tolabel_path=None):
    ev = json.load(io.open(set_path, encoding='utf-8'))
    pr = json.load(io.open(pred_path, encoding='utf-8'))
    rows = {r['id']: r for r in ev['rows']}
    preds = {p['id']: p for p in pr.get('predictions', [])}

    n = len(rows)
    directional = n < DIRECTIONAL_N

    answered = [i for i in rows if i in preds]
    row_hits, comp_hits, per_nutrient = 0, 0, OrderedDict((k, [0, 0]) for k in MACROS)

    for i, row in rows.items():
        p = preds.get(i)
        if not p:
            continue
        if row.get('corpus_row') and p.get('corpus_row') == row['corpus_row']:
            row_hits += 1
        d = agrees(row['truth_per100'], p.get('per100') or {})
        if d and all(d.values()):
            comp_hits += 1
        for k, ok in d.items():
            per_nutrient[k][1] += 1
            if ok:
                per_nutrient[k][0] += 1

    print('')
    print('matcher: %s' % pr.get('matcher', '(unnamed)'))
    print('set:     %s  (truth: %s)' % (set_path, ev.get('truth', '?')))
    if directional:
        print('')
        print('  *** %d rows is below the %d-row floor. Every figure below is'
              % (n, DIRECTIONAL_N))
        print('  *** DIRECTIONAL: it indicates, it does not measure.')
    print('')
    print(fmt('coverage (answered)', len(answered), n, directional))
    print(fmt('composition agrees (all macros)', comp_hits, len(answered), directional))
    if any(v[1] for v in per_nutrient.values()):
        print('')
        for k, (h, t) in per_nutrient.items():
            if t:
                print(fmt('  %s' % k, h, t, directional))
    labelled = [r for r in ev['rows'] if r.get('corpus_row')]
    print('')
    print(fmt('exact corpus row', row_hits, len(labelled), directional)
          if labelled else '  exact corpus row                   n/a  (no row labels in set)')

    if tolabel_path:
        tl = json.load(io.open(tolabel_path, encoding='utf-8'))
        qs = tl.get('queries', [])
        done = [q for q in qs if q.get('corpus_row')]
        seed = [q for q in qs if q.get('human_judged')]
        print('')
        print('  labelling worklist: %d of %d queries labelled; %d human-judged (seed)'
              % (len(done), len(qs), len(seed)))
        print('  NOTE: these are the dish cases the matcher exists for. Until they are')
        print('  labelled, nothing above measures that job (D72).')
    print('')


if __name__ == '__main__':
    if len(sys.argv) < 3:
        print(__doc__)
        sys.exit(2)
    main(sys.argv[1], sys.argv[2], sys.argv[3] if len(sys.argv) > 3 else None)
