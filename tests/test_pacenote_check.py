"""tools/pacenote_check/checks.py: reading a call's words and the rules, on made-up calls (no game, no Lua)."""
import math
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'tools' / 'pacenote_check'))
import checks  # noqa: E402

failed = 0


def check(name, cond):
    global failed
    if not cond:
        failed += 1
        print('FAIL', name)


p = checks.parse('80 4 left')
check('pro lead distance', p['lead'] == 80 and p['corners'] == [('left', '4')])
p = checks.parse('into three right half long over crest 300')
check('game words', p['corners'] == [('right', '3')] and p['crest'] and p['trail'] == 300 and p['link'] == 'into')
p = checks.parse('keep left over crest')
check('keep is not a corner', p['corners'] == [] and p['crest'])
p = checks.parse('six left extra long 1 point 5 km')
check('long', p['long'] and p['corners'] == [('left', '6')])
check('km distance', p['trail'] == 1500)
check('1 km', checks.parse('crest 1 km')['trail'] == 1000)
check('1 point 2 5 km', checks.parse('four right 1 point 2 5 km')['trail'] == 1250)
check('7 point 7 5 km', checks.parse('over finish 7 point 7 5 km')['trail'] == 7750)
check('km lead', checks.parse('1 point 2 km six left')['lead'] == 1200)
p = checks.parse('tightens 4 over crest')
check('shape only', p['shapeOnly'] and p['crest'] and not p['corners'])
p = checks.parse('care hairpin left 200')
check('hairpin', p['corners'] == [('left', 'hairpin')] and p['trail'] == 200)


def note(s0, s1, text, **k):
    return dict({'s0': s0, 's1': s1, 'text': text, 'p': checks.parse(text)}, **k)


# the opening: a corner 300 m in, said at the line with no distance, is silent; with "300" before it, told
said = {'startS': 0, 'finishS': 1000, 'notes': [note(300, 330, 'four left'), note(600, 620, 'over finish')]}
check('opening silent', not checks.rule_opening(said)['ok'])
said['notes'][0] = note(300, 330, '300 four left')
check('opening told', checks.rule_opening(said)['ok'])
# a crest at the line with its distance after it, then the corner: told
said['notes'] = [note(20, 30, 'crest 270'), note(300, 330, 'four left')]
check('opening chained', checks.rule_opening(said)['ok'])
# ... but not when the words leave the distance out, whatever autofill measured
said['notes'] = [note(20, 30, 'crest', distAfterM=270), note(300, 330, 'four left')]
check('opening not chained without the words', not checks.rule_opening(said)['ok'])
said['notes'] = [note(20, 30, 'crest'), note(55, 80, 'into four left')]
check('opening linked', checks.rule_opening(said)['ok'])

# a straight road with one long bend, 40 degrees right over 300 m from 300 m in
pts = []
x = y = 0.0
h = 0.0
s = 0.0
for i in range(0, 900):
    if 300 <= s < 600:
        h -= math.radians(40) / 300
    x += math.cos(h)
    y += math.sin(h)
    s += 1
    pts.append((x, y, 0.0, s))
said = {'startS': 0, 'finishS': 900, 'notes': []}
check('bend uncalled', len(checks.rule_bends(said, pts)) == 1)
said['notes'] = [note(310, 590, 'six right extra long')]
check('bend called', checks.rule_bends(said, pts) == [])
said['notes'] = [note(310, 590, 'six left extra long')]
check('bend called the wrong way', len(checks.rule_bends(said, pts)) == 1)
said['mute'] = [(250, 650)]
check('bend where the map has no road', checks.rule_bends(said, pts) == [])

# a crest at 300 m (12 % up to 12 % down over 20 m); the road turns 40 degrees left over 30 m from `turn_at`
def crest_road(turn_at):
    pts, x, y, z, h = [], 0.0, 0.0, 0.0, math.pi / 2
    for i in range(0, 700):
        g = 0.12 if 200 <= i < 290 else (0.12 - 0.24 * (i - 290) / 20 if 290 <= i < 310 else
                                         (-0.12 if 310 <= i < 400 else 0))
        if turn_at <= i < turn_at + 30:
            h += math.radians(40) / 30
        x += math.cos(h)
        y += math.sin(h)
        z += g
        pts.append((x, y, z, float(i)))
    return pts


pts = crest_road(335)
said = {'startS': 0, 'finishS': 700, 'notes': [note(295, 305, 'crest 30'), note(335, 360, 'four left')]}
c = checks.rule_crests(said, pts)
check('corner hidden after a crest', len(c) == 1 and c[0]['flagged'] and c[0]['dir'] == 'left')
check('its gap', c and 20 <= c[0]['gapM'] <= 35)
said['notes'][1] = note(335, 360, 'into four left')
check('crest into corner', checks.crest_flags(checks.rule_crests(said, pts)) == [])
said['notes'] = [note(295, 305, 'crest')]
check('hidden turn never called', len(checks.crest_flags(checks.rule_crests(said, pts))) == 1)
said['notes'] = [note(280, 360, 'four left over crest')]
check('crest in the corner call', checks.rule_crests(said, pts) == [])
pts = crest_road(560)
said['notes'] = [note(295, 305, 'crest 250'), note(560, 590, 'four left')]
check('corner far past the crest', checks.rule_crests(said, pts) == [])
check('gap bins', [checks.gap_bin(g) for g in (0, 39, 40, 59, 60, 99, 100, 500)] ==
      ['0-40', '0-40', '40-60', '40-60', '60-100', '60-100', '100+', '100+'])

# against a pro: one of ours is paired with one pro call only
ours = [note(100, 120, 'four left')]
pro = [note(95, 120, '4 left'), note(110, 130, '3 left')]
v = checks.versus_pro(ours, pro, 0)
check('one to one', v['found'] == 1 and v['sameGrade'] == 1)

print('test_pacenote_check:', 'FAILED %d' % failed if failed else 'all passed')
sys.exit(1 if failed else 0)
