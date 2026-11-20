"""The checks: what a call says (parse), the rules every stage is held to (no human notes needed), and the
comparison with a professional co-driver's notes where the game has them. Pure Python over plain data."""
import math
import re

# Bump when a rule or its numbers change: runs are only compared with runs of the same rules (check.py).
RULES_VERSION = 2

NUM = {'one': 1, 'two': 2, 'three': 3, 'four': 4, 'five': 5, 'six': 6}
GRADES = {'1', '2', '3', '4', '5', '6', 'flat', 'hairpin', 'square'}


def parse(text):
    """A call's words -> { corners: [(dir, grade)], crest, jump, long, lead (a distance said before the first corner),
    trail (a distance said after the last), link ('into' | 'and' | None), keeps (directions of "keep right",
    "rightish": a slight bend said without a number) }. Reads both the game's words ("five right
    long") and a co-driver's transcriptions ("4 left", "open hairpin right", "6 long")."""
    words = re.findall(r"[a-z']+|\d+(?:\.\d+)?", (text or '').lower())
    words = [str(NUM[w]) if w in NUM else w for w in words]
    words = _km(words)
    out = {'shapeOnly': False, 'corners': [], 'keeps': [], 'crest': False, 'jump': False, 'long': False, 'lead': None, 'trail': None, 'link': None,
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
                if words[i - 1] in ('keep', 'stay'):
                    out['keeps'].append(w)
                continue
            out['corners'].append((w, g))
        elif w in ('leftish', 'rightish'):
            out['keeps'].append(w[:-3])   # "rightish over jump": a slight bend, said
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
        v = float(w)
        if first_corner is not None and i < first_corner:
            out['lead'] = out['lead'] or v
        else:
            out['trail'] = v
    return out


def _km(words):
    """Kilometres said as the game says them ("1 km", "1 point 2 5 km", "7 point 7 5 km") or written ("1.5 km") ->
    one word, in metres ("1250")."""
    out, i = [], 0
    digit = re.compile(r'\d+(?:\.\d+)?')
    while i < len(words):
        w = words[i]
        if digit.fullmatch(w):
            j, frac = i + 1, ''
            if j < len(words) and words[j] == 'point':
                k = j + 1
                while k < len(words) and re.fullmatch(r'\d', words[k]):
                    frac += words[k]
                    k += 1
                if frac and k < len(words) and words[k] == 'km':
                    out.append('%g' % round(float(w + '.' + frac) * 1000))
                    i = k + 1
                    continue
            if j < len(words) and words[j] == 'km':
                out.append('%g' % round(float(w) * 1000))
                i = j + 1
                continue
        out.append(w)
        i += 1
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
LINK_M = 40             # a call this close after the one before is heard as one with it
TURN_DEG = 15           # a turn, for the crest rule: the heading changes this much ...
TURN_WINDOW_M = 40      # ... within this much road
CREST_REACH_M = 30      # a turn this far past where the road comes back into view is still a surprise
CREST_GAP_BINS = ((0, 40), (40, 60), (60, 100), (100, None))   # the summary's histogram of crest-to-turn gaps
EYE_M, TARGET_M = 1.1, 0.6   # driver's eye; what of the road has to be seen (pacenotes.SIGHT_TARGET_M)


def rule_opening(said):
    """The first call is heard at the start line. The road up to the first corner is told when the first call says
    how far it is ("80 4 left", "200 crest into..."), or when it comes within OPENING_M of the line and each call
    after it, up to the first corner, is tied on: a distance said at the end of the one before ("crest 100"), a link
    word ("into", "and"), or no more than LINK_M after it."""
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
        tied = (prev['p']['trail'] is not None or n['p']['link'] in ('into', 'and') or
                n['s0'] - prev['s1'] <= LINK_M)
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


def first_turn(pts, h, s_from, s_to):
    """The first turn in the road starting between s_from and s_to: a heading change of TURN_DEG or more within
    TURN_WINDOW_M. Returns (along where it starts, 'left' | 'right', degrees) or None."""
    i = index_at(pts, s_from)
    while i < len(pts) - 1 and pts[i][3] <= s_to:
        j = index_at(pts, pts[i][3] + TURN_WINDOW_M)
        turn = math.degrees(h[j] - h[i])
        if abs(turn) >= TURN_DEG:
            # where it starts: the first point of the window the heading has moved 3 degrees from
            k = next((k for k in range(i, j + 1) if abs(math.degrees(h[k] - h[i])) >= 3), i)
            return pts[k][3], ('left' if turn > 0 else 'right'), abs(turn)
        i += 1
    return None


def rule_crests(said, pts):
    """Every crest or jump called without a corner, with the road out of sight behind it (hidden_after): the first
    turn in the road there (first_turn, up to CREST_REACH_M past where it comes back into view). Each case is listed
    with its gap (the crest call's end to the turn). It is flagged unless a corner call of the turn's direction
    covers it in the same breath (the next call, linked by "into" / "and"; or a "keep right" / "rightish" of its way
    in the crest's call or that one) or the turn is a corner already being
    driven (a corner call before the crest runs through it). Geometry, not the calls: a hidden turn the recce never
    called is flagged too."""
    out = []
    notes = said['notes']
    start = said['startS'] or 0
    if len(pts) < 10:
        return out
    h = headings(pts)
    for k, n in enumerate(notes):
        p = n['p']
        if not (p['crest'] or p['jump']) or p['corners'] or p['shapeOnly']:
            continue
        top = (n['s0'] + n['s1']) / 2
        hid = hidden_after(pts, top)
        if not hid:
            continue
        t = first_turn(pts, h, hid[0], hid[1] + CREST_REACH_M)
        if not t:
            continue
        s_turn, d, deg = t

        def spans(m, pad=20):
            return (any(c[0] == d for c in m['p']['corners']) and
                    m['s0'] - pad <= s_turn + TURN_WINDOW_M and m['s1'] + pad >= s_turn)
        nxt = notes[k + 1] if k + 1 < len(notes) else None
        linked = d in p['keeps'] or bool(nxt and nxt['p']['link'] in ('into', 'and') and
                                          (spans(nxt) or d in nxt['p']['keeps']))
        driving = any(spans(m, 0) for m in notes[:k])
        called = next((m for m in notes[k + 1:] if spans(m)), None)
        out.append({'atM': top - start, 'cornerAtM': s_turn - start, 'gapM': s_turn - n['s1'], 'dir': d,
                    'deg': deg, 'hidden': (hid[0] - start, hid[1] - start), 'crestCall': n['text'],
                    'cornerCall': called['text'] if called else None, 'linked': linked,
                    'flagged': not (linked or driving)})
    return out


def crest_flags(crests):
    return [c for c in crests if c['flagged']]


def gap_bin(g):
    """The histogram bin a crest-to-turn gap falls in: '0-40', '40-60', '60-100', '100+'."""
    for lo, hi in CREST_GAP_BINS:
        if hi is None or g < hi:
            return f'{lo}-{hi}' if hi is not None else f'{lo}+'
    return None


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
    """ours / pro: [{ s0, s1, p }] along the same spline. Corner by corner (pro corner calls paired one to one with
    ours of the same direction within MATCH_M, nearest pairs first), the grades, the long calls, the crests said with a
    corner, and the first call."""
    r = {'proCorners': 0, 'ourCorners': 0, 'found': 0, 'sameGrade': 0, 'withinOne': 0, 'gradeDiff': 0,
         'graded': 0, 'proLong': 0, 'longFound': 0, 'longSaid': 0, 'proCrestCorner': 0, 'crestCornerSaid': 0,
         'crestCornerCrestOnly': 0, 'misses': [], 'crestMisses': [], 'longMisses': []}
    oc = [(n, d, g) for n in ours for d, g in n['p']['corners']]
    r['ourCorners'] = len(oc)
    pc = [(n, d, g) for n in pro for d, g in n['p']['corners']]
    # one to one: the nearest pairs first, each of ours used once
    pairs = sorted((abs(m['s0'] - n['s0']), a, b) for a, (n, d, _) in enumerate(pc)
                   for b, (m, d2, _) in enumerate(oc) if d2 == d and abs(m['s0'] - n['s0']) <= MATCH_M)
    match, used = {}, set()
    for _, a, b in pairs:
        if a not in match and b not in used:
            match[a] = b
            used.add(b)
    for a, (n, d, g) in enumerate(pc):
        r['proCorners'] += 1
        best = (oc[match[a]][0], oc[match[a]][2]) if a in match else None
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
    for n in pro:
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
    r['ourFirstAtM'] = ours[0]['s0'] - start if ours else None
    r['proFirstAtM'] = pro[0]['s0'] - start if pro else None
    return r
