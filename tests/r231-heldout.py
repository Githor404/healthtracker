#!/usr/bin/env python3
# R231 / R239 -- THE HELD-OUT CHECK, re-runnable.
#
#   python tests/r231-heldout.py <events.json>     (from tests/r231-extract.ps1)
#
# Pre-registered (R231/6): does a stage-1 nutrient model predict the glucose rise
# (and the 2 h area) on meals it has NOT seen better than a carb-only baseline?
# Leave-one-out; ridge regression on standardised inputs at three strengths; a
# paired bootstrap of the error difference. Meals holding an uncounted item are
# excluded (R233.1/7); provisional ones are counted and reported.
# R239: re-run each time the judged CLEAN meals grow by 15 since the last recorded
# check (DECISIONS.md, "R231 held-out"), and record the result there. The user is
# told only when the model first beats the baseline -- "beats" = its rise error is
# lower than carbs-only's AND the 95% interval of the difference excludes zero.
# No shares and no trigger flags ship while it does not.
import json, math, random, sys
random.seed(231)
d = json.load(open(sys.argv[1], encoding='utf-8'))
ev = d['events']
judged = [e for e in ev if e['judged']]
usable = [e for e in judged if e['nUncounted'] == 0]
print('eating events %d, judged %d, excluded for an uncounted item %d, usable %d, provisional among usable %d'
      % (len(ev), len(judged), len(judged) - len(usable), len(usable), sum(1 for e in usable if e['nProvisional'])))
clean = [e for e in usable if e['cleanBefore'] and e['cleanAfter']]
print('usable and clean (no food 2 h either side) %d; overlapping %d' % (len(clean), len(usable) - len(clean)))

def feats(e, names):
    h = e['hour']
    f = {'carbs': e['carbs'], 'fat': e['fat'], 'protein': e['protein'], 'fibre': e['fiber'], 'alcohol': e['alcohol'],
         'evening': 1.0 if h >= 17 else 0.0, 'prior_carbs': e['priorCarbs'], 'after_carbs': e['afterCarbs'],
         'net_carbs': e['carbs'] - e['fiber']}
    return [f[n] for n in names]

def solve(A, b):
    n = len(A); M = [A[i][:] + [b[i]] for i in range(n)]
    for c in range(n):
        p = max(range(c, n), key=lambda r: abs(M[r][c]))
        M[c], M[p] = M[p], M[c]
        if abs(M[c][c]) < 1e-12: return None
        for r in range(n):
            if r != c:
                k = M[r][c] / M[c][c]
                for j in range(c, n + 1): M[r][j] -= k * M[c][j]
    return [M[i][n] / M[i][i] for i in range(n)]

def ridge_fit(X, y, lam):
    # standardise columns; intercept unpenalised
    p = len(X[0]) if X else 0
    mu = [sum(r[j] for r in X) / len(X) for j in range(p)]
    sd = [math.sqrt(sum((r[j] - mu[j]) ** 2 for r in X) / len(X)) or 1.0 for j in range(p)]
    Z = [[(r[j] - mu[j]) / sd[j] for j in range(p)] for r in X]
    ym = sum(y) / len(y)
    A = [[sum(Z[k][i] * Z[k][j] for k in range(len(Z))) + (lam if i == j else 0) for j in range(p)] for i in range(p)]
    bb = [sum(Z[k][i] * (y[k] - ym) for k in range(len(Z))) for i in range(p)]
    w = solve(A, bb) if p else []
    return (mu, sd, w, ym)

def ridge_pred(m, x):
    mu, sd, w, ym = m
    return ym + sum(w[j] * (x[j] - mu[j]) / sd[j] for j in range(len(w)))

def loo(rows, names, ykey, lam):
    errs = []
    for i in range(len(rows)):
        tr = rows[:i] + rows[i + 1:]
        X = [feats(e, names) for e in tr]; y = [e[ykey] for e in tr]
        m = ridge_fit(X, y, lam) if names else (None, None, [], sum(y) / len(y))
        p = ridge_pred(m, feats(rows[i], names)) if names else sum(y) / len(y)
        errs.append(rows[i][ykey] - p)
    return errs

def mae(e): return sum(abs(x) for x in e) / len(e)
def boot_diff(e1, e2, B=4000):
    n = len(e1); ds = []
    for _ in range(B):
        idx = [random.randrange(n) for _ in range(n)]
        ds.append(sum(abs(e1[i]) for i in idx) / n - sum(abs(e2[i]) for i in idx) / n)
    ds.sort(); return ds[int(0.025 * B)], ds[int(0.975 * B)], sum(1 for x in ds if x > 0) / B

def spearman(a, b):
    def rk(v):
        o = sorted(range(len(v)), key=lambda i: v[i]); r = [0] * len(v); i = 0
        while i < len(o):
            j = i
            while j + 1 < len(o) and v[o[j + 1]] == v[o[i]]: j += 1
            for k in range(i, j + 1): r[o[k]] = (i + j) / 2
            i = j + 1
        return r
    ra, rb = rk(a), rk(b); n = len(a); ma = sum(ra) / n; mb = sum(rb) / n
    num = sum((ra[i] - ma) * (rb[i] - mb) for i in range(n)); den = math.sqrt(sum((x - ma) ** 2 for x in ra) * sum((x - mb) ** 2 for x in rb))
    return num / den if den else float('nan')

for label, rows in (('ALL USABLE (overlap as covariates)', usable), ('CLEAN ONLY', clean)):
    print('\n=== %s, n = %d ===' % (label, len(rows)))
    ys = [e['rise'] for e in rows]
    print('rise mmol/L: median %.2f, range %.1f to %.1f; carbs median %.0f g (range %.0f-%.0f)' % (
        sorted(ys)[len(ys) // 2], min(ys), max(ys), sorted(e['carbs'] for e in rows)[len(rows) // 2], min(e['carbs'] for e in rows), max(e['carbs'] for e in rows)))
    print('spearman carbs~rise %.2f' % spearman([e['carbs'] for e in rows], ys))
    for ykey in ('rise', 'iauc'):
        base = loo(rows, [], ykey, 0)
        carb = loo(rows, ['carbs'], ykey, 0.0)
        res = {'mean only': base, 'carbs only': carb}
        for lam in (1.0, 5.0, 20.0):
            res['stage-1, ridge lam=%g' % lam] = loo(rows, ['carbs', 'fat', 'protein', 'fibre', 'alcohol', 'evening'] + (['prior_carbs', 'after_carbs'] if rows is usable else []), ykey, lam)
        print('  %s -- held-out (leave-one-out) mean absolute error:' % ykey)
        for k, v in res.items(): print('     %-28s %8.3f' % (k, mae(v)))
        best = min((k for k in res if k.startswith('stage')), key=lambda k: mae(res[k]))
        lo, hi, pbetter = boot_diff(res['carbs only'], res[best])
        print('     best stage-1 vs carbs-only: MAE difference (carbs-only minus model) 95%% CI [%.3f, %.3f]; share of resamples where the model is better %.2f' % (lo, hi, pbetter))
        lo2, hi2, p2 = boot_diff(res['mean only'], res['carbs only'])
        print('     carbs-only vs mean-only:   difference 95%% CI [%.3f, %.3f]; share better %.2f' % (lo2, hi2, p2))

# ---- the verdict line, on the rise over all usable meals ---------------------
rows = usable
base_c = loo(rows, ['carbs'], 'rise', 0.0)
best = None
for lam in (1.0, 5.0, 20.0):
    e = loo(rows, ['carbs', 'fat', 'protein', 'fibre', 'alcohol', 'evening', 'prior_carbs', 'after_carbs'], 'rise', lam)
    if best is None or mae(e) < mae(best[1]): best = (lam, e)
lo, hi, pb = boot_diff(base_c, best[1])
beats = mae(best[1]) < mae(base_c) and lo > 0
print()
print('VERDICT: usable %d, clean %d; rise MAE carbs-only %.3f vs stage-1 %.3f (lam %g); difference 95%% CI [%.3f, %.3f] -> %s'
      % (len(usable), len(clean), mae(base_c), mae(best[1]), best[0], lo, hi, 'BEATS THE BASELINE' if beats else 'does not beat the baseline'))
