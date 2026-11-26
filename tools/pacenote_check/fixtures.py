"""Made-up roads, one for each fault the owner has reported, and controls that must stay quiet. Each road is a plan
(straights and arcs) and a height profile (crests as vertical curves); each has an expectation on what the co-driver
says (the game's words, gamevoice.lua) and on the rules (checks.py). A fault's fixture fails until it is fixed."""
import math

import checks

STEP = 4.0


class Road:
    def __init__(self, name, plan, crests=(), fault=''):
        self.name, self.plan, self.crests, self.fault = name, plan, crests, fault

    def grade(self, s):
        # crests: (top along, length of the vertical curve, grade in, grade out, ramp): grade_in for `ramp` m before
        # the curve, bending to grade_out across it, grade_out for `ramp` m after, flat elsewhere
        for top, lv, g1, g2, ramp in self.crests:
            a, b = top - lv / 2, top + lv / 2
            if a - ramp <= s < a:
                return g1
            if a <= s < b:
                return g1 + (g2 - g1) * (s - a) / lv
            if b <= s < b + ramp:
                return g2
        return 0.0

    def line(self):
        pts = []
        x = y = z = 0.0
        h = math.pi / 2       # heading north
        s = 0.0
        pts.append({'x': x, 'y': y, 'z': z})
        for seg in self.plan:
            if seg[0] == 'kinks':
                # ('kinks', degrees, nodes, length, 'left' | 'right'): a bend as a map draws it -- straight pieces
                # between `nodes` nodes, the turn all at the nodes
                _, deg, nodes, length, d = seg
                piece = length / (nodes + 1)
                kink = math.radians(deg) / nodes * (1 if d == 'left' else -1)
                for k in range(nodes + 1):
                    m = max(1, int(round(piece / STEP)))
                    for _ in range(m):
                        x += math.cos(h) * piece / m
                        y += math.sin(h) * piece / m
                        z += self.grade(s + piece / m / 2) * piece / m
                        s += piece / m
                        pts.append({'x': x, 'y': y, 'z': z})
                    if k < nodes:
                        h += kink
                continue
            if seg[0] == 'straight':
                length, turn = seg[1], 0.0
            else:  # ('arc', radius, degrees, 'left' | 'right')
                _, r, deg, d = seg
                length = r * math.radians(deg)
                turn = math.radians(deg) * (1 if d == 'left' else -1) / length
            n = max(1, int(round(length / STEP)))
            ds = length / n
            for _ in range(n):
                h += turn * ds / 2
                x += math.cos(h) * ds
                y += math.sin(h) * ds
                h += turn * ds / 2
                z += self.grade(s + ds / 2) * ds
                s += ds
                pts.append({'x': x, 'y': y, 'z': z})
        return pts

    def expect(self, said, rules):
        raise NotImplementedError


def corner_notes(said, d=None):
    return [n for n in said['notes'] if any(c[0] == d or d is None for c in n['p']['corners'])]


def at(said, s):
    return s + (said['startS'] or 0)


class OpeningStraight(Road):
    """The rule passes, and the words themselves say a distance before the first corner ("300 four right", or
    "crest 200" then the corner)."""
    def expect(self, said, rules):
        o = rules['opening']
        notes = said['notes']
        k = next((k for k, n in enumerate(notes) if n['p']['corners']), len(notes) - 1)
        told = any(n['p']['lead'] is not None for n in notes[:k + 1]) or \
            any(n['p']['trail'] is not None for n in notes[:k])
        return o['ok'] and told, (f"first call at the line: \"{o['first']}\"; first corner {o['gapM']:.0f} m in" +
                                  ('' if told else '; no distance said'))


class LongBend(Road):
    def __init__(self, name, plan, a, b, d, **k):
        super().__init__(name, plan, **k)
        self.a, self.b, self.d = a, b, d

    def expect(self, said, rules):
        hit = [n for n in corner_notes(said, self.d) if n['s1'] >= at(said, self.a) and n['s0'] <= at(said, self.b)]
        missed = [b for b in rules['bends']]
        # a bend over 200 m is said long
        long_ok = self.b - self.a <= 200 or any(n['p']['long'] for n in hit)
        ok = bool(hit) and not missed and long_ok
        said_ = ' / '.join(n['text'] for n in hit) or 'nothing'
        return ok, (f"bend {self.a:.0f}-{self.b:.0f} m: {said_}" +
                    (f"; {len(missed)} missed stretch(es)" if missed else '') + ('' if long_ok else '; not said long'))


class CornerOverCrest(Road):
    def __init__(self, name, plan, corner_at, d, **k):
        super().__init__(name, plan, **k)
        self.corner_at, self.d = corner_at, d

    def expect(self, said, rules):
        notes = said['notes']
        near = [n for n in notes if abs(n['s0'] - at(said, self.corner_at)) <= 60 or
                (n['s0'] <= at(said, self.corner_at) + 10 and n['s1'] >= at(said, self.corner_at) - 40)]
        both = any(n['p']['corners'] and (n['p']['crest'] or n['p']['jump']) for n in near)
        linked = any(notes[k]['p']['crest'] and not notes[k]['p']['corners'] and k + 1 < len(notes) and
                     notes[k + 1]['p']['corners'] and notes[k + 1]['p']['link'] in ('into', 'and')
                     for k in range(len(notes)) if notes[k] in near)
        ok = (both or linked) and not checks.crest_flags(rules['crests'])
        return ok, 'heard: ' + (' / '.join(n['text'] for n in near) or 'nothing')


class HiddenKink(Road):
    """A turn just behind a sharp crest, small enough that the recce may not call it at all: it has to be called,
    with the crest, and the crest rule must not flag it."""
    def __init__(self, name, plan, turn_at, d, **k):
        super().__init__(name, plan, **k)
        self.turn_at, self.d = turn_at, d

    def expect(self, said, rules):
        near = [n for n in corner_notes(said, self.d) if n['s0'] - 40 <= at(said, self.turn_at) <= n['s1'] + 40]
        flags = checks.crest_flags(rules['crests'])
        seen = [c for c in rules['crests'] if abs(c['cornerAtM'] + (said['startS'] or 0) - at(said, self.turn_at)) <= 60]
        ok = bool(near) and not flags
        return ok, ('heard: ' + (' / '.join(n['text'] for n in near) or 'no call for the turn') +
                    f"; crest rule: {len(seen)} case(s), {len(flags)} flagged")


class Quiet(Road):
    """A control: the road between `a` and `b` has no corner a driver needs called; nothing flagged anywhere."""
    def __init__(self, name, plan, a, b, **k):
        super().__init__(name, plan, **k)
        self.a, self.b = a, b

    def expect(self, said, rules):
        extra = [n for n in corner_notes(said) if n['s0'] >= at(said, self.a) and n['s1'] <= at(said, self.b)]
        ok = not extra and not rules['bends']
        return ok, f"{len(extra)} corner call(s) in {self.a:.0f}-{self.b:.0f} m" + \
            (': ' + ' / '.join(n['text'] for n in extra) if extra else '')


class Hairpin(Road):
    def expect(self, said, rules):
        hp = [n for n in said['notes'] if 'hairpin' in n['text']]
        return bool(hp), 'heard: ' + (' / '.join(n['text'] for n in corner_notes(said)) or 'nothing')


ALL = [
    OpeningStraight('opening-straight-300', [('straight', 300), ('arc', 40, 90, 'right'), ('straight', 250)],
                    fault='silent first 100 m'),
    OpeningStraight('opening-straight-600', [('straight', 600), ('arc', 60, 60, 'left'), ('straight', 250)],
                    fault='silent first 100 m'),
    LongBend('long-open-left-r450', [('straight', 250), ('arc', 450, 45, 'left'), ('straight', 250)],
             250, 250 + 450 * math.radians(45), 'left', fault='long open corners'),
    LongBend('very-wide-right-r700', [('straight', 250), ('arc', 700, 35, 'right'), ('straight', 250)],
             250, 250 + 700 * math.radians(35), 'right', fault='long open corners'),
    LongBend('long-right-r300', [('straight', 250), ('arc', 300, 40, 'right'), ('straight', 250)],
             250, 250 + 300 * math.radians(40), 'right', fault='long open corners'),
    LongBend('map-drawn-left-45deg-400m', [('straight', 250), ('kinks', 45, 5, 400, 'left'), ('straight', 250)],
             250, 650, 'left', fault='long open corners'),
    # pieces of 100 m
    LongBend('map-drawn-right-35deg-500m', [('straight', 250), ('kinks', 35, 4, 500, 'right'), ('straight', 250)],
             250, 750, 'right', fault='long open corners'),
    LongBend('map-drawn-right-35deg-kinks-60m', [('straight', 250), ('kinks', 35, 7, 480, 'right'),
             ('straight', 250)], 250, 730, 'right', fault='long open corners'),
    LongBend('map-drawn-right-35deg-kinks-80m', [('straight', 250), ('kinks', 35, 5, 480, 'right'),
             ('straight', 250)], 250, 730, 'right', fault='long open corners'),
    LongBend('map-drawn-right-35deg-kinks-120m', [('straight', 250), ('kinks', 35, 3, 480, 'right'),
             ('straight', 250)], 250, 730, 'right', fault='long open corners'),
    LongBend('map-drawn-left-20deg-400m', [('straight', 250), ('kinks', 20, 3, 400, 'left'), ('straight', 250)],
             250, 650, 'left', fault='long open corners (under 25 degrees)'),
    # a sharp 25 degree kink right behind a jump: the recce calls it, with the jump (a turn of 15 degrees or more in
    # 40 m behind a crest always got a call in the trials); a gentler one, 20 degrees over 100 m in 25 m pieces, got
    # none ("jump 400") -- below the crest rule's own turn (15 degrees in 40 m), so only this fixture sees it
    HiddenKink('kink-behind-crest', [('straight', 320), ('kinks', 25, 1, 30, 'right'), ('straight', 300)],
               335, 'right', crests=[(310, 14, 0.12, -0.12, 60)], fault='corner over crest'),
    HiddenKink('gentle-bend-behind-jump', [('straight', 320), ('kinks', 20, 3, 100, 'right'), ('straight', 300)],
               370, 'right', crests=[(310, 14, 0.12, -0.12, 60)], fault='corner over crest, not called'),
    CornerOverCrest('right-on-crest', [('straight', 300), ('arc', 45, 70, 'right'), ('straight', 300)],
                    300, 'right', crests=[(300, 50, 0.09, -0.09, 80)], fault='corner over crest'),
    CornerOverCrest('left-behind-crest', [('straight', 340), ('arc', 40, 80, 'left'), ('straight', 300)],
                    340, 'left', crests=[(290, 40, 0.10, -0.10, 80)], fault='corner over crest'),
    CornerOverCrest('right-behind-jump', [('straight', 330), ('arc', 50, 60, 'right'), ('straight', 300)],
                    330, 'right', crests=[(300, 12, 0.12, -0.12, 60)], fault='corner over crest'),
    Quiet('control-gentle-wiggle', [('straight', 200), ('arc', 2000, 6, 'left'), ('arc', 2000, 6, 'right'),
                                    ('arc', 2000, 6, 'left'), ('straight', 200)], 150, 750),
    Quiet('control-small-crest-straight', [('straight', 900)], 0, 900, crests=[(450, 80, 0.03, -0.03, 60)]),
    Hairpin('control-hairpin', [('straight', 150), ('arc', 12, 170, 'left'), ('straight', 200)]),
]
