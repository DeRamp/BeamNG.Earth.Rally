#!/usr/bin/env python3
"""The pacenote check: what the co-driver will actually say on every stage, held to rules and to a professional
co-driver's notes, scored, and compared with the last run -- so a change to the pacenotes can be judged before anyone
drives it.

    python tools/pacenote_check/check.py [--label "<what changed>"] [--stage <part of a name>] [--maps]
                                         [--only fixtures|pro|mine] [--style enthusiast|casual] [--game <folder>]
                                         [--list] [--no-history]

Three sets of stages, all built with the mod's own stageWriter.build and spoken with the game's own Lua
(gamevoice.lua: the game's corner measuring, distance calls and words):
  fixtures  made-up roads, one per known fault (fixtures.py); each passes or fails
  pro       the game's rally stages that carry a pro co-driver's notes (pro_ak notebook + its transcriptions):
            corners found, grades, long calls, corners over crests, the first call
  mine      the player's matched lines (earthRally/matched): the rules only (opening, missed bends, crests with a
            hidden corner, long silences)
Results: out/pacenote-check/ (history.jsonl, last.json, maps/*.svg); not in git -- they carry positions on organisers'
routes. Reads the game and the player's folder; writes only there. Needs `pip install lupa`.
"""
import argparse
import datetime
import json
import math
import subprocess
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import checks  # noqa: E402
import common  # noqa: E402
import fixtures  # noqa: E402
import maps  # noqa: E402

OUT = common.ROOT / 'out' / 'pacenote-check'


def py_said(said):
    notes = []
    for i in range(1, len(said.notes) + 1):
        e = said.notes[i]
        notes.append({'n': e.n, 's0': e.s0, 's1': e.s1, 'text': e.text or '', 'diameter': e.diameter,
                      'distAfterM': e.distAfterM, 'p': checks.parse(e.text or '')})
    pts = [(p.pos.x, p.pos.y, p.pos.z, p.s) for p in (said.spline[i] for i in range(1, len(said.spline) + 1))]
    return {'notes': notes, 'startS': said.startS, 'finishS': said.finishS,
            'errors': [said.errors[i] for i in range(1, len(said.errors) + 1)]}, pts


def nearest_s(pts, x, y, from_i=0):
    best, bi = 1e18, from_i
    for i in range(from_i, len(pts)):
        d = (pts[i][0] - x) ** 2 + (pts[i][1] - y) ** 2
        if d < best:
            best, bi = d, i
    return bi, pts[bi][3]


def pro_notes(nb, transcriptions, pts):
    """The pro notebook's notes with their words, assigned to notes as path.getCustomAudioAssignment does."""
    sorted_pn = nb['pacenotes']
    disk = sorted(transcriptions.keys(), key=lambda b: _clip_key(b))
    disk = [b for b in disk if _clip_key(b)[0] < 10 ** 8]
    idx = {b: i + 1 for i, b in enumerate(disk)}
    anchors = [(0, 0)]
    for k, pn in enumerate(sorted_pn, 1):
        for b in pn.get('customAudioAnchors') or []:
            if b in idx:
                anchors.append((idx[b], k))
    anchors.sort()
    anchors.append((len(disk) + 1, len(sorted_pn) + 1))
    at = {a: n for a, n in anchors[1:-1]}
    texts = {k: [] for k in range(1, len(sorted_pn) + 1)}
    cur = 0
    for ai, b in enumerate(disk, 1):
        while cur + 1 < len(anchors) and ai > anchors[cur + 1][0]:
            cur += 1
        n = at.get(ai)
        if n is None:
            (la, ln), (ra, rn) = anchors[cur], anchors[cur + 1]
            t = (ai - la) / max(ra - la, 1)
            n = math.floor(ln + t * (rn - ln) + 0.5)
        n = min(max(n, 1), len(sorted_pn))
        texts[n].append(transcriptions[b].get('description') or '')
    out = []
    from_i = 0
    for k, pn in enumerate(sorted_pn, 1):
        wps = {w['waypointType']: w['pos'] for w in pn['pacenoteWaypoints']}
        cs, ce = wps.get('cornerStart'), wps.get('cornerEnd')
        if not cs or not ce:
            continue
        i0, s0 = nearest_s(pts, cs[0], cs[1], max(0, from_i - 200))
        _, s1 = nearest_s(pts, ce[0], ce[1], i0)
        from_i = i0
        text = ' '.join(texts[k])
        out.append({'s0': s0, 's1': s1, 'text': text, 'p': checks.parse(text)})
    return out


def _clip_key(b):
    import re
    m = re.match(r'^pacenote_(\d+)([a-z]?)_?(\d*)\.ogg$', b)
    if not m:
        return (10 ** 9, b)
    return (int(m.group(1)), m.group(2), int(m.group(3) or 0))


def gaps_on(line, pts):
    """The stretches of the line with no road on the map (its gap points), along the spline."""
    out, cur = [], None
    i = 0
    for p in line:
        if p.get('gap'):
            i, s = nearest_s(pts, p['x'], p['y'], max(0, i - 50))
            cur = [s, s] if cur is None else [cur[0], s]
        elif cur is not None:
            out.append(tuple(cur))
            cur = None
    if cur is not None:
        out.append(tuple(cur))
    return out


def git_rev():
    try:
        r = subprocess.run(['git', 'rev-parse', '--short', 'HEAD'], cwd=common.ROOT, capture_output=True, text=True)
        d = subprocess.run(['git', 'status', '--porcelain', '--', 'mod'], cwd=common.ROOT, capture_output=True,
                           text=True)
        return r.stdout.strip() + ('+dirty' if d.stdout.strip() else '')
    except OSError:
        return '?'


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--label', default='')
    ap.add_argument('--stage')
    ap.add_argument('--maps', action='store_true')
    ap.add_argument('--only', choices=['fixtures', 'pro', 'mine'])
    ap.add_argument('--style', default='enthusiast', choices=['enthusiast', 'casual'])
    ap.add_argument('--game', default=common.DEFAULT_GAME)
    ap.add_argument('--folder', help='earthRally user folder (default: the game\'s current one)')
    ap.add_argument('--list', action='store_true', help='print every call of each stage')
    ap.add_argument('--no-history', action='store_true')
    a = ap.parse_args()

    lua, voice, build = common.runtime(a.game)
    opts = lua.table_from({'style': a.style})
    OUT.mkdir(parents=True, exist_ok=True)
    result = {'when': datetime.datetime.now().isoformat(timespec='seconds'), 'rev': git_rev(), 'label': a.label,
              'style': a.style, 'fixtures': {}, 'pro': {}, 'mine': {}}

    def speak(line, lms=(), startM=None, finishM=None):
        lt, lmt = common.to_lua(lua, line, lms)
        b = build(lt, lmt, None, startM, finishM)
        said, pts = py_said(voice.say(b, opts))
        return said, pts

    def show(name, said):
        if not a.list:
            return
        print(f'--- {name}')
        st = said['startS'] or 0
        for n in said['notes']:
            print(f"  {n['s0'] - st:7.0f} m  {n['text']}")

    # ---- fixtures
    if a.only in (None, 'fixtures'):
        for fx in fixtures.ALL:
            if a.stage and a.stage not in fx.name:
                continue
            said, pts = speak(fx.line())
            show('fixture ' + fx.name, said)
            rules = checks.stage_rules(said, pts)
            ok, why = fx.expect(said, rules)
            result['fixtures'][fx.name] = {'ok': ok, 'why': why, 'calls': [n['text'] for n in said['notes']]}
            if a.maps:
                maps.write(OUT / 'maps' / f'fixture-{fx.name}.svg', 'fixture ' + fx.name, said, pts, rules)

    # ---- the game's stages with a pro's notes
    if a.only in (None, 'pro'):
        for name, nodes, nb, tr, start, finish in common.pro_stages(a.game, a.stage):
            line = [{'x': p['x'], 'y': p['y'], 'z': p['z']} for p in common.game_spline(nodes)]
            along = [0.0]
            for p, q in zip(line, line[1:]):
                along.append(along[-1] + math.dist((p['x'], p['y']), (q['x'], q['y'])))
            lpts = [(p['x'], p['y'], 0, s) for p, s in zip(line, along)]
            startM = nearest_s(lpts, start[0], start[1])[1] if start else None
            finishM = nearest_s(lpts, finish[0], finish[1])[1] if finish else None
            if startM is not None and finishM is not None and finishM <= startM + 500:
                finishM = None
            said, pts = speak(line, (), startM, finishM)
            show('pro ' + name, said)
            pro = pro_notes(nb, tr, pts)
            rules = checks.stage_rules(said, pts)
            vs = checks.versus_pro(said['notes'], pro, said['startS'] or 0)
            # the same rules over the pro's own notes: what a human co-driver "fails" -- the rules' false alarms
            selfRules = checks.stage_rules({'notes': pro, 'startS': said['startS'], 'finishS': said['finishS']}, pts)
            result['pro'][name] = {'versus': vs, 'rules': rules, 'proRules': selfRules, 'km': (pts[-1][3]) / 1000}
            if a.maps:
                maps.write(OUT / 'maps' / f"pro-{name.replace('/', '__')}.svg", 'pro ' + name, said, pts, rules,
                           pro=pro)

    # ---- the player's stages
    if a.only in (None, 'mine'):
        for name, line, lms, junc, at in common.matched_stages(a.folder, a.stage):
            said, pts = speak(line, lms + common.junction_landmarks(lua, junc, at))
            said['mute'] = gaps_on(line, pts)
            show(name, said)
            rules = checks.stage_rules(said, pts)
            st, fi = said['startS'] or 0, said['finishS'] or pts[-1][3]
            result['mine'][name] = {'rules': rules, 'km': (fi - st) / 1000, 'notes': len(said['notes'])}
            if a.maps:
                maps.write(OUT / 'maps' / f'{name}.svg', name, said, pts, rules)

    summary = summarise(result)
    result['summary'] = summary
    last = OUT / 'last.json'
    prev = None
    hist = OUT / 'history.jsonl'
    if hist.exists():
        for ln in hist.read_text(encoding='utf-8').splitlines():
            try:
                h = json.loads(ln)
            except ValueError:
                continue
            if (h.get('style') == a.style and h.get('scope') == scope(a) and
                    h.get('rules') == checks.RULES_VERSION):
                prev = h
    report(result, summary, prev)
    last.write_text(json.dumps(result, indent=1, default=str), encoding='utf-8')
    if not a.no_history:
        with hist.open('a', encoding='utf-8') as f:
            f.write(json.dumps({'when': result['when'], 'rev': result['rev'], 'label': a.label, 'style': a.style,
                                'scope': scope(a), 'rules': checks.RULES_VERSION, 'summary': summary}) + '\n')
    return 0


def scope(a):
    return (a.only or 'all') + (':' + a.stage if a.stage else '')


def summarise(r):
    s = {}
    if r['fixtures']:
        s['fixturesPassed'] = sum(1 for v in r['fixtures'].values() if v['ok'])
        s['fixtures'] = len(r['fixtures'])
    if r['pro']:
        t = {}
        for v in r['pro'].values():
            for k, x in v['versus'].items():
                if isinstance(x, (int, float)) and not isinstance(x, bool):
                    t[k] = t.get(k, 0) + x
        s['proCornerRecall'] = t['found'] / max(t['proCorners'], 1)
        s['proCornerPrecision'] = t['found'] / max(t['ourCorners'], 1)
        s['proSameGrade'] = t['sameGrade'] / max(t['graded'], 1)
        s['proWithinOneGrade'] = t['withinOne'] / max(t['graded'], 1)
        s['proGradeBias'] = t['gradeDiff'] / max(t['graded'], 1)
        s['proLongFound'] = t['longFound'] / max(t['proLong'], 1)
        s['proLongSaid'] = t['longSaid'] / max(t['proLong'], 1)
        s['proCrestCornerSaid'] = t['crestCornerSaid'] / max(t['proCrestCorner'], 1)
        s['proCrestCornerCrestOnly'] = t['crestCornerCrestOnly']
        s['proFirstToldDistance'] = sum(1 for v in r['pro'].values() if v['versus']['ourFirstLead'])
        s['proStages'] = len(r['pro'])
    # proSelf: the rules over the pro's own notes -- how often a human co-driver "fails" them (false alarms)
    for key, src, field in (('pro', 'pro', 'rules'), ('proSelf', 'pro', 'proRules'), ('mine', 'mine', 'rules')):
        if not r[src]:
            continue
        rs = [v[field] for v in r[src].values()]
        km = sum(v['km'] for v in r[src].values())
        s[key + 'OpeningsSilent'] = sum(1 for x in rs if x['opening'] and not x['opening']['ok'])
        s[key + 'MissedBends'] = sum(len(x['bends']) for x in rs)
        s[key + 'MissedBendsPerKm'] = s[key + 'MissedBends'] / max(km, 1e-9)
        s[key + 'HiddenCornersAfterCrest'] = sum(len(x['crests']) for x in rs)
        s[key + 'LongSilences'] = sum(len(x['silence']) for x in rs)
        s[key + 'Stages'] = len(rs)
        s[key + 'Km'] = km
    return s


# lower is better for these; higher for the rest
LOWER = ('OpeningsSilent', 'MissedBends', 'HiddenCornersAfterCrest', 'LongSilences', 'CrestOnly')


def report(r, s, prev):
    p = (prev or {}).get('summary', {})
    print(f"pacenote check  {r['when']}  {r['rev']}  style {r['style']}  {r['label']}")
    if prev:
        print(f"  compared with {prev['when']} {prev['rev']} {prev.get('label', '')}")
    for name, v in r['fixtures'].items():
        print(f"  fixture {name:28s} {'PASS' if v['ok'] else 'FAIL'}  {v['why']}")
    for k, v in s.items():
        if k in ('fixtures', 'proStages', 'mineStages', 'proKm', 'mineKm', 'proSelfStages', 'proSelfKm'):
            continue
        old = p.get(k)
        mark = ''
        if isinstance(old, (int, float)) and fmt(k, old) != fmt(k, v):
            better = (v < old) if any(x in k for x in LOWER) else (v > old)
            if k == 'proGradeBias':
                better = abs(v) < abs(old)
            mark = f"   was {fmt(k, old)}  {'better' if better else 'WORSE'}"
        print(f'  {k:30s} {fmt(k, v):>8s}{mark}')
    if r['mine']:
        print(f"  ({s.get('mineStages')} of your stages, {s.get('mineKm', 0):.0f} km; "
              f"{s.get('proStages', 0)} pro stages, {s.get('proKm', 0):.0f} km)")


def fmt(k, v):
    if isinstance(v, float) and (k.startswith('pro') and ('Recall' in k or 'Precision' in k or 'Grade' in k and
                                                          'Bias' not in k or 'Long' in k or 'CrestCornerSaid' in k)):
        return f'{v:.0%}'
    if isinstance(v, float):
        return f'{v:.2f}'
    return str(v)


if __name__ == '__main__':
    sys.exit(main())
