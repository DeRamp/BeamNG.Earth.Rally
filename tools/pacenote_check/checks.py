"""The checks: what a call says (parse), the rules every stage is held to (no human notes needed), and the
comparison with a professional co-driver's notes where the game has them. Pure Python over plain data."""
import math
import re

# Bump when a rule or its numbers change: runs are only compared with runs of the same rules (check.py).
RULES_VERSION = 1

NUM = {'one': 1, 'two': 2, 'three': 3, 'four': 4, 'five': 5, 'six': 6}
GRADES = {'1', '2', '3', '4', '5', '6', 'flat', 'hairpin', 'square'}


def parse(text):
    """A call's words -> { corners: [(dir, grade)], crest, jump, long, lead (a distance said before the first corner),
    trail (a distance said after the last), link ('into' | 'and' | None) }. Reads both the game's words ("five right
    long") and a co-driver's transcriptions ("4 left", "open hairpin right", "6 long")."""
    words = re.findall(r"[a-z']+|\d+(?:\.\d+)?", (text or '').lower())
    words = [str(NUM[w]) if w in NUM else w for w in words]
    out = {'shapeOnly': False, 'corners': [], 'crest': False, 'jump': False, 'long': False, 'lead': None, 'trail': None, 'link': None,
           'text': text or ''}
    for i, w in enumerate(words):
        if w in ('left', 'right'):
            g = None
            if i > 0 and words[i - 1] in GRADES:
                g = words[i - 1]
            elif i + 1 < len(words) and words[i + 1] in GRADES:
                g = words[i + 1]
            # "keep left", "stay right", "at junction left" are not corners
            if i > 0 and words[i - 1] in ('keep', 'stay', 'cut', 'tightish', 'junction', 'turn') and g is None:
                continue
            out['corners'].append((w, g))
        elif 'crest' in w:
            out['crest'] = True
        elif 'jump' in w:
            out['jump'] = True
        elif w == 'long':
            out['long'] = True
        elif w in ('tightens', 'opens') and i + 1 < len(words) and words[i + 1] in GRADES:
            out['shapeOnly'] = True   # "tightens 4 over crest": the corner before goes on through it
    if words and words[0] in ('into', 'and'):
        out['link'] = words[0]
    # a number not next to left / right is a distance
    nums = [(i, w) for i, w in enumerate(words) if re.fullmatch(r'\d+(?:\.\d+)?', w)
            and not (i + 1 < len(words) and words[i + 1] in ('left', 'right'))
            and float(w) >= 20]
    first_corner = next((i for i, w in enumerate(words) if w in ('left', 'right')), None)
    for i, w in nums:
        v = float(w) * (1000 if i + 1 < len(words) and words[i + 1] == 'km' else 1)
        if first_corner is not None and i < first_corner:
            out['lead'] = out['lead'] or v
        else:
            out['trail'] = v
    return out


def grade_num(g):
    if g is None:
        return None
    if g in ('hairpin', 'square'):
        return 1 if g == 'hairpin' else 2
    if g == 'flat':
        return 7
    return int(g)


# ---------------------------------------------------------------------------------------------- the stage's road

def headings(pts):
    """pts: [(x, y, z, s)] -> unwrapped heading (radians) at each point."""
    h = [0.0] * len(pts)
    for i in range(1, len(pts)):
        h[i] = math.atan2(pts[i][1] - pts[i - 1][1], pts[i][0] - pts[i - 1][0])
    h[0] = h[1] if len(pts) > 1 else 0
    out = [h[0]]
    for i in range(1, len(h)):
        d = (h[i] - h[i - 1] + math.pi) % (2 * math.pi) - math.pi
        out.append(out[-1] + d)
    return out


def index_at(pts, s):
    lo, hi = 0, len(pts) - 1
    while hi - lo > 1:
        m = (lo + hi) // 2
        if pts[m][3] <= s:
            lo = m
        else:
            hi = m
    return lo


# ---------------------------------------------------------------------------------------------- the rules

OPENING_M = 80          # a first corner further than this from the start line has to be told with its distance
BEND_MIN_DEG = 25       # a stretch turning this much one way ...
BEND_LENGTHS = range(60, 501, 20)   # ... over one of these lengths (m) ...
BEND_COVER = 0.5        # ... has to turn at least this share of it inside corner calls of that direction
BEND_PAD_BEFORE_M = 60  # a call covers the road this far before its corner start (the lead-in a driver is told of)
BEND_PAD_AFTER_M = 40   # ... and this far past its corner end (where it opens out)
SILENCE_M = 600         # a gap between calls longer than this is listed
CREST_GAP_M = 60        # a corner further than this past a crest call may be its own call ("crest 80, 3 left": a pro
                        # does that); nearer and out of sight, it belongs in the crest's call
EYE_M, TARGET_M = 1.1, 0.6   # driver's eye; what of the road has to be seen (pacenotes.SIGHT_TARGET_M)


def rule_opening(said):
    """The first call is heard at the start line. The road up to the first corner is told when the first call says
    how far it is ("80 4 left", "200 crest into..."), or when it comes within OPENING_M of the line and each call
    after it, up to the first corner, is tied on: a distance said at the end of the one before ("crest 100"), or
    close enough to be linked ("into", "and")."""
    notes = said['notes']
    if not notes:
        return None
    start = said['startS'] or 0
    first = notes[0]
    k_corner = next((k for k, n in enumerate(notes) if n['p']['corners']), None)
    gap = (notes[k_corner]['s0'] - start) if k_corner is not None else None
    told = first['p']['lead'] is not None or first['s0'] - start <= OPENING_M
    for k in range(1, (k_corner or 0) + 1):
        prev, n = notes[k - 1], notes[k]
        tied = (prev['p']['trail'] is not None or prev.get('distAfterM') is not None or
                n['p']['link'] in ('into', 'and') or n['s0'] - prev['s1'] <= 40 or n['p']['lead'] is not None)
        told = told and tied
    ok = gap is None or gap <= OPENING_M or told
    return {'ok': ok, 'gapM': gap, 'first': first['text'], 'firstAtM': first['s0'] - start}


def rule_bends(said, pts):
    """Stretches of road that turn BEND_MIN_DEG or more one way over BEND_LENGTHS with no corner call of that
    direction covering at least BEND_COVER of them: the long, open bends a driver needs and does not hear."""
    if len(pts) < 10:
        return []
    h = headings(pts)
    start = said['startS'] or 0
    finish = said['finishS'] or pts[-1][3]
    spans = {'left': [], 'right': []}
    for n in said['notes']:
        for d, _ in n['p']['corners']:
            spans[d].append((n['s0'], n['s1']))

    def inside(s_, d):
        for x0, x1 in spans[d]:
            if x0 - BEND_PAD_BEFORE_M <= s_ <= x1 + BEND_PAD_AFTER_M:
                return True
        return False

    def covered(i, j, d):
        # the share of the window's turning (its way) that is inside a corner call of that direction
        sign = 1 if d == 'left' else -1
        tot = got = 0.0
        for k in range(i + 1, j + 1):
            t = (h[k] - h[k - 1]) * sign
            if t > 0:
                tot += t
                if inside(pts[k][3], d):
                    got += t
        return got / max(tot, 1e-12)

    flagged = []
    s = start + 30
    while s < finish - 60:
        i = index_at(pts, s)
        for L in BEND_LENGTHS:
            if s + L > finish:
                break
            j = index_at(pts, s + L)
            turn = math.degrees(h[j] - h[i])
            if abs(turn) >= BEND_MIN_DEG:
                d = 'left' if turn > 0 else 'right'
                if covered(i, j, d) < BEND_COVER:
                    flagged.append((s, s + L, d, abs(turn)))
                break   # the shortest length that turns enough is the bend
        s += 10
    # one entry per stretch: overlapping windows of one direction are one bend; a stretch where the map has no road
    # (said['mute'], the calls are muted there on purpose) is left out
    out = []
    for d in ('left', 'right'):
        cur = None
        for a, b, d2, t in flagged:
            if d2 != d or any(a <= m1 + 30 and b >= m0 - 30 for m0, m1 in said.get('mute', [])):
                continue
            if cur and a <= cur['b']:
                cur['b'] = max(cur['b'], b)
                cur['deg'] = max(cur['deg'], t)
            else:
                cur = {'a': a, 'b': b, 'dir': d, 'deg': t}
                out.append(cur)
    out.sort(key=lambda o: o['a'])
    for o in out:
        o['fromM'], o['toM'] = o.pop('a') - start, o.pop('b') - start
        o['lengthM'] = o['toM'] - o['fromM']
    return out


def hidden_after(pts, s_top, ahead=200.0):
    """Where the road is out of sight over a crest: the driver's eye EYE_M up, 30 m before the top; the stretch after
    it whose point TARGET_M up cannot be seen. Returns (from, to) along, or None."""
    i_eye = index_at(pts, s_top - 30)
    ex, ey, ez = pts[i_eye][0], pts[i_eye][1], pts[i_eye][2] + EYE_M
    ex_s = pts[i_eye][3]
    j_end = index_at(pts, s_top + ahead)
    lo = None
    hi = None
    # running max of the slope from the eye to the road between it and each point (the horizon)
    best = -1e9
    for j in range(i_eye + 1, j_end + 1):
        x, y, z, s = pts[j]
        dist = s - ex_s
        if dist <= 1:
            continue
        slope_road = (z - ez) / dist
        slope_target = (z + TARGET_M - ez) / dist
        seen = slope_target >= best
        best = max(best, slope_road)
        if s > s_top - 5 and not seen:
            lo = lo if lo is not None else s
            hi = s
        elif lo is not None and seen:
            break
    return (lo, hi) if lo is not None else None


def rule_crests(said, pts):
    """A crest or jump called on its own whose next corner starts out of sight behind it (or within 30 m of where
    the road comes back into view): that corner has to be in the same breath -- "left 4 over crest" or "crest into
    left 4" -- not a later call."""
    out = []
    notes = said['notes']
    start = said['startS'] or 0
    for k, n in enumerate(notes):
        p = n['p']
        if not (p['crest'] or p['jump']) or p['corners'] or p['shapeOnly']:
            continue
        nxt = next((m for m in notes[k + 1:] if m['p']['corners']), None)
        if not nxt:
            continue
        top = (n['s0'] + n['s1']) / 2
        hid = hidden_after(pts, top)
        reach = (hid[1] + 30) if hid else top + 40
        if nxt['s0'] <= reach and nxt['s0'] - n['s1'] <= CREST_GAP_M:
            linked = nxt['p']['link'] in ('into', 'and') and notes.index(nxt) == k + 1
            out.append({'atM': top - start, 'cornerAtM': nxt['s0'] - start, 'gapM': nxt['s0'] - n['s1'],
                        'hidden': hid and (hid[0] - start, hid[1] - start), 'crestCall': n['text'],
                        'cornerCall': nxt['text'], 'linked': linked})
    return [o for o in out if not o['linked']]


def rule_silence(said):
    notes = said['notes']
    start = said['startS'] or 0
    out = []
    for a, b in zip(notes, notes[1:]):
        if b['s0'] - a['s1'] >= SILENCE_M:
            out.append({'fromM': a['s1'] - start, 'toM': b['s0'] - start, 'lengthM': b['s0'] - a['s1']})
    return out


def stage_rules(said, pts):
    return {'opening': rule_opening(said), 'bends': rule_bends(said, pts), 'crests': rule_crests(said, pts),
            'silence': rule_silence(said)}


# ---------------------------------------------------------------------------------------------- against a pro

MATCH_M = 40


def versus_pro(ours, pro, start):
    """ours / pro: [{ s0, s1, p }] along the same spline. Corner by corner (each pro corner call's start, matched to
    the nearest of ours of the same direction within MATCH_M), the grades, the long calls, the crests said with a
    corner, and the first call."""
    r = {'proCorners': 0, 'ourCorners': 0, 'found': 0, 'sameGrade': 0, 'withinOne': 0, 'gradeDiff': 0,
         'graded': 0, 'proLong': 0, 'longFound': 0, 'longSaid': 0, 'proCrestCorner': 0, 'crestCornerSaid': 0,
         'crestCornerCrestOnly': 0, 'misses': [], 'crestMisses': [], 'longMisses': []}
    oc = [(n, d, g) for n in ours for d, g in n['p']['corners']]
    r['ourCorners'] = len(oc)
    for n in pro:
        for d, g in n['p']['corners']:
            r['proCorners'] += 1
            best, bd = None, MATCH_M
            for m, d2, g2 in oc:
                dist = abs(m['s0'] - n['s0'])
                if d2 == d and dist <= bd:
                    best, bd = (m, g2), dist
            pg = grade_num(g)
            if best:
                r['found'] += 1
                og = grade_num(best[1])
                if pg is not None and og is not None:
                    r['graded'] += 1
                    r['sameGrade'] += og == pg
                    r['withinOne'] += abs(og - pg) <= 1
                    r['gradeDiff'] += og - pg
            else:
                r['misses'].append({'atM': n['s0'] - start, 'pro': n['text']})
            if n['p']['long']:
                r['proLong'] += 1
                if best:
                    r['longFound'] += 1
                    r['longSaid'] += best[0]['p']['long']
                else:
                    r['longMisses'].append({'atM': n['s0'] - start, 'pro': n['text']})
        if n['p']['corners'] and (n['p']['crest'] or n['p']['jump']):
            r['proCrestCorner'] += 1
            near = [m for m in ours if abs(m['s0'] - n['s0']) <= MATCH_M or
                    (m['s0'] <= n['s1'] + 10 and m['s1'] >= n['s0'] - 10)]
            if any(m['p']['corners'] and (m['p']['crest'] or m['p']['jump']) for m in near):
                r['crestCornerSaid'] += 1
            else:
                if any((m['p']['crest'] or m['p']['jump']) and not m['p']['corners'] for m in near):
                    r['crestCornerCrestOnly'] += 1
                r['crestMisses'].append({'atM': n['s0'] - start, 'pro': n['text'],
                                         'ours': ' / '.join(m['text'] for m in near) or '(nothing)'})
    r['proFirst'] = pro[0]['text'] if pro else None
    r['ourFirst'] = ours[0]['text'] if ours else None
    r['proFirstLead'] = pro[0]['p']['lead'] if pro else None
    r['ourFirstLead'] = ours[0]['p']['lead'] if ours else None
    return r
