"""Do the food log and the glucose stream overlap at all?

The mockup puts "Glucose rose 2.8 - back in 2 h" on a meal header. That line can
only render for a meal that HAS a response, and a response needs glucose readings
around that meal's time.

glucose.csv on this machine covers 3 days (2026-09-30 .. 2026-10-02). The food log
covers 2026-07-16 .. 2026-09-26. Those do not overlap. But glucose.csv is only one
imported slice -- the 514 MB Apple Health export is the real source, so the
question is what IT holds.

Streamed, not parsed: a substring test per line, no XML tree, no regex.
"""
import io, collections

XML = r'C:\Users\thoma\projects\HTprivate\export.xml'
NEEDLE = 'HKQuantityTypeIdentifierBloodGlucose'
KEY = 'startDate="'

days = collections.Counter()
seen = 0
with io.open(XML, encoding='utf-8', errors='replace') as f:
    for line in f:
        if NEEDLE not in line:
            continue
        seen += 1
        i = line.find(KEY)
        if i < 0:
            continue
        day = line[i + len(KEY): i + len(KEY) + 10]
        if len(day) == 10 and day[4] == '-':
            days[day] += 1

print('glucose records in the Apple Health export: %d' % seen)
print('distinct days: %d' % len(days))
if days:
    ks = sorted(days)
    print('range: %s .. %s' % (ks[0], ks[-1]))
    print('')
    # the food log's own span, for the overlap
    import json
    d = json.load(io.open(r'C:\Users\thoma\projects\healthtracker\export.json', encoding='utf-8'))
    fooddays = set()
    for k, v in (d.get('days') or {}).items():
        if [it for it in (v.get('items') or []) if it and not it.get('_auto')]:
            fooddays.add(k)
    both = sorted(fooddays & set(days))
    print('days WITH FOOD: %d' % len(fooddays))
    print('days with GLUCOSE: %d' % len(days))
    print('DAYS WITH BOTH: %d' % len(both))
    if both:
        print('  %s' % ', '.join(both))
        tot = sum(days[b] for b in both)
        print('  glucose readings on those days: %d (avg %.0f per day)' % (tot, tot / len(both)))
    else:
        print('  NONE -- no meal in the log can have a glucose response')
