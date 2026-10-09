"""Why the ink sweep missed the collision: it tested a BOX against a BOX.

The constraint is a CIRCLE. `.ringval.calcentre{inset:21%}` makes the centre a
SQUARE inscribed in the ring box -- and a square of the circle's diameter does
not fit inside that circle. Its diagonal is 1.414x its side, so the corners lie
outside.

The two checks I ran were:

    centreOverflows : c.scrollHeight > c.clientHeight     -- box vs its own box
    anyLineWider    : child.width > centre.width           -- box vs box

Neither can see a line of text whose ENDS pass outside the arc, because both
compare widths at y=0 while the circle narrows as |y| grows. Available half-width
at vertical offset y is sqrt(r^2 - y^2), not r.

This generates the arithmetic from the SHIPPED geometry so the failure is shown
rather than argued, and prints which element collides and by how much.
"""
import io
import math

NL = chr(10)

# ---- the shipped geometry, from index.html and app.js -------------------
VIEWBOX = 180.0
CAL_R = 58.0          # CAL_RING_R
STROKE = 9.0          # .calrarc / .calrtrack stroke-width
INSET = 0.21          # .ringval.calcentre

cases = [
    ('360px viewport', 302.0),
    ('390px viewport', 328.0),
]

# measured element widths and heights from the previous ink run at 360
# (calnum 74x33, calunit 19x16, calmac 103x19, calwords 161x38)
STACK = [
    ('calnum', 74.0, 33.0),
    ('calunit', 19.0, 16.0),
    ('calmac', 103.0, 19.0),
    ('calwords', 161.0, 38.0),
]

print('=' * 70)
print('WHY THE INK SWEEP MISSED IT -- box-vs-box against a circular constraint')
print('=' * 70)

for label, boxpx in cases:
    scale = boxpx / VIEWBOX
    inner_r = (CAL_R - STROKE / 2.0) * scale        # inner edge of the calorie arc
    centre_side = boxpx * (1 - 2 * INSET)
    diag = centre_side * math.sqrt(2)
    print('')
    print('%s: ring box %.0fpx, scale %.3f' % (label, boxpx, scale))
    print('  calorie arc inner radius : %.1fpx  (usable circle diameter %.1fpx)'
          % (inner_r, inner_r * 2))
    print('  centre box (inset 21%%)   : %.1fpx square, DIAGONAL %.1fpx'
          % (centre_side, diag))
    print('  -> the box\'s corners sit %.1fpx outside the circle before any text'
          % (diag / 2 - inner_r))

    total_h = sum(h for _, _, h in STACK)
    y = -total_h / 2.0
    print('  stack is %.0fpx tall, centred, so it spans y = %.0f .. %+.0f'
          % (total_h, y, y + total_h))
    print('')
    print('  %-10s %-14s %-10s %-10s %s' % ('element', 'half-width', 'worst |y|',
                                            'allowed', 'verdict'))
    print('  ' + '-' * 62)
    worst = None
    for name, w, h in STACK:
        top, bot = y, y + h
        worst_y = max(abs(top), abs(bot))          # the corner furthest from centre
        allowed = math.sqrt(max(0.0, inner_r ** 2 - worst_y ** 2))
        half = w / 2.0
        over = half - allowed
        verdict = ('COLLIDES by %.1fpx' % over) if over > 0 else 'clear'
        if over > 0 and (worst is None or over > worst[1]):
            worst = (name, over)
        print('  %-10s %-14.1f %-10.1f %-10.1f %s' % (name, half, worst_y, allowed, verdict))
        y = bot
    if worst:
        print('')
        print('  WORST: %s, %.1fpx of ink outside the arc.' % (worst[0], worst[1]))
    else:
        print('')
        print('  no collision at this size for these widths.')

print('')
print('=' * 70)
print('AND THE TWO CHECKS THAT RAN COULD NOT HAVE SEEN IT:')
print('  centreOverflows : scrollHeight > clientHeight  -- a box against ITS OWN box')
print('  anyLineWider    : child.width > centre.width   -- a box against a box')
print('Both compare widths as if the limit were constant. It is sqrt(r^2 - y^2),')
print('so a line that fits at the middle can still put its ends through the arc.')
print('=' * 70)
print('')
print('A WIDER MACRO LINE MAKES IT WORSE, which is what the device showed:')
print('the reported "11.7C" is a DECIMAL where the fixture had "40C" -- every')
print('decimal adds a glyph to the widest line in the disc.')
for extra in (0, 10, 20, 30):
    w = 103.0 + extra
    scale = 302.0 / VIEWBOX
    inner_r = (CAL_R - STROKE / 2.0) * scale
    y0 = -sum(h for _, _, h in STACK) / 2.0 + 33.0 + 16.0
    worst_y = max(abs(y0), abs(y0 + 19.0))
    allowed = math.sqrt(max(0.0, inner_r ** 2 - worst_y ** 2))
    print('  calmac %.0fpx wide -> half %.1f vs allowed %.1f : %s'
          % (w, w / 2, allowed, 'COLLIDES' if w / 2 > allowed else 'clear'))
