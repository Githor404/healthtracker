"""Map the 46 slots onto Cronometer's grouping, and name what does not fit."""
import json, io, os, collections

REPO = r'C:\Users\thoma\projects\healthtracker'
spec = json.load(io.open(os.path.join(REPO, 'corpus', 'slots.json'), encoding='utf-8'))
slots = {s['slot']: s for s in spec['slots']}

# group, parent (for nesting), note
M = {
    203: ('Protein', None, None),
    204: ('Lipids', None, None),
    205: ('Carbohydrates', None, None),
    207: ('General', None, 'MISFIT: analytical residue, not a nutrient anyone eats toward'),
    208: ('General', None, None),
    221: ('General', None, 'MISFIT: not macro, not micro -- its own thing'),
    255: ('General', None, None),
    262: ('General', None, 'MISFIT: not macro, not micro'),
    263: ('General', None, 'MISFIT: not macro, not micro'),
    268: ('General', 208, 'MISFIT: the SAME quantity in another unit, not a second nutrient'),
    269: ('Carbohydrates', 205, None),
    291: ('Carbohydrates', 205, None),
    301: ('Minerals', None, None), 303: ('Minerals', None, None),
    304: ('Minerals', None, None), 305: ('Minerals', None, None),
    306: ('Minerals', None, None), 307: ('Minerals', None, None),
    309: ('Minerals', None, None), 312: ('Minerals', None, None),
    318: ('Vitamins', 320, 'MISFIT: the same vitamin A in IU -- an alternate expression, not a part'),
    319: ('Vitamins', 320, None),
    320: ('Vitamins', None, 'MISFIT: a computed EQUIVALENT (retinol + carotenoid conversion), so its children are inputs, not parts'),
    328: ('Vitamins', None, None),
    401: ('Vitamins', None, None), 404: ('Vitamins', None, None),
    405: ('Vitamins', None, None), 406: ('Vitamins', None, None),
    409: ('Vitamins', 406, 'MISFIT: a computed EQUIVALENT (includes tryptophan conversion), not a part of preformed niacin'),
    415: ('Vitamins', None, None),
    417: ('Vitamins', None, None),
    418: ('Vitamins', None, None),
    431: ('Vitamins', 417, None),
    601: ('Lipids', None, None),
    606: ('Lipids', 204, None),
    617: ('Lipids', 645, None),
    618: ('Lipids', 646, 'omega-6 (linoleic)'),
    621: ('Lipids', 646, 'omega-3 (DHA)'),
    631: ('Lipids', 646, 'omega-3 (DPA)'),
    645: ('Lipids', 204, None),
    646: ('Lipids', 204, None),
    806: ('Vitamins', 417, None),
    814: ('Vitamins', 320, 'merged into 320'),
    815: ('Vitamins', 417, 'MISFIT: a computed EQUIVALENT (DFE), so it sits beside total folate rather than under it'),
    832: ('Lipids', 646, 'omega-6 (GLA)'),
    854: ('Lipids', 646, 'omega-6'),
    861: ('Lipids', 646, 'omega-3'),
}

order = ['General', 'Carbohydrates', 'Lipids', 'Protein', 'Vitamins', 'Minerals']
by_group = collections.defaultdict(list)
unmapped = []
for n in sorted(slots):
    if n not in M:
        unmapped.append(n)
        continue
    by_group[M[n][0]].append(n)

print('46 slots onto Cronometer-style groups\n')
for g in order:
    ns = by_group.get(g, [])
    print('%s (%d)' % (g, len(ns)))
    for n in ns:
        grp, parent, note = M[n]
        e = slots[n]
        nm = e.get('label') or e.get('fdc_name') or e.get('cnf_name') or '?'
        indent = '    ' if parent else '  '
        if parent and M.get(parent) and M[parent][1]:
            indent = '      '
        print('%s%-40s [%s]%s' % (indent, nm[:40], n, (' <- ' + note) if note else ''))
    print()

if unmapped:
    print('UNMAPPED: %s' % unmapped)

mis = [(n, M[n][2]) for n in sorted(M) if M[n][2] and M[n][2].startswith('MISFIT')]
print('--- do not fit cleanly (%d of 46) ---' % len(mis))
for n, why in mis:
    e = slots[n]
    nm = e.get('label') or e.get('fdc_name') or e.get('cnf_name') or '?'
    print('  [%s] %-34s %s' % (n, nm[:34], why[8:]))

# families that would render as complete while missing their best-known members
print('\n--- incomplete families ---')
have_o3 = [n for n in (621, 631, 861) if n in slots]
print('  Omega-3 present : %s' % have_o3)
print('  Omega-3 MISSING : ALA 18:3 n-3 (851) and EPA 20:5 n-3 (629) -- neither cleared')
print('                    the 90%% bar, so a nested "Omega-3" group would show 3')
print('                    members and silently omit the two a reader looks for.')
