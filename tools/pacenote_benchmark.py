#!/usr/bin/env python3
"""The co-driver's notes against the game's own hand-made ones: for each kind of call, how many of the game's we
also call (recall) and how many of ours the game also has (precision), within a distance.

    python tools/pacenote_benchmark.py [--game "<BeamNG.drive folder>"] [--radius 50] [--stage <part of a path>]
                                       [--straight]

Runs the mod's own stageWriter.build (under LuaJIT through lupa, as the offline tests do) on the drivelineSpline.json
of every rally stage the game ships that has a structured notebook, the whole driveline taken as the stage, and
matches notes by where their first waypoint is. Those drivelines carry the real road surface's heights -- but a node
only every 14 to 40 m (gaps up to 200 m), where a matched line has one every 4 m. They are followed as the game's
road tools do (editor/toolUtilities/geom.lua catmullRomFree: centripetal Catmull-Rom across, a monotone Steffen
cubic for the heights), a point about every metre, not joined by straight lines (--straight: as before, every node a
kink in the heights). A short sharp hump between two nodes is in neither: read the height rows as a floor. The game's notes are a person's, so neither side is "the truth" -- but
a call that agrees with them nowhere is not one to trust. The finish row means nothing here: each driveline runs on
past the finish to the stop control, and the whole of it is taken as the stage. The rate per km over real stages is tools/pacenote_survey.py.
Reads only; writes nothing. Needs `pip install lupa`. (Built from the contrarian review of 2026-11-14.)
"""
import argparse
import collections
import glob
import json
import math
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
LUA = ROOT / 'mod' / 'earth_rally' / 'lua' / 'ge' / 'extensions'
DEFAULT_GAME = r'C:/Program Files (x86)/Steam/steamapps/common/BeamNG.drive'


def _cr(p0, p1, p2, p3, t, alpha=0.5):
    # centripetal Catmull-Rom between p1 and p2 (Barry-Goldman), t in [0, 1]
    def tj(ti, a, b):
        return ti + max(math.dist(a, b), 1e-6) ** alpha
    t0 = 0.0
    t1 = tj(t0, p0, p1)
    t2 = tj(t1, p1, p2)
    t3 = tj(t2, p2, p3)
    u = t1 + (t2 - t1) * t

    def lerp(a, b, ta, tb):
        w = (u - ta) / (tb - ta)
        return tuple(x + (y - x) * w for x, y in zip(a, b))
    a1, a2, a3 = lerp(p0, p1, t0, t1), lerp(p1, p2, t1, t2), lerp(p2, p3, t2, t3)
    b1, b2 = lerp(a1, a2, t0, t2), lerp(a2, a3, t1, t3)
    return lerp(b1, b2, t1, t2)


def _steffen(z0, z1, z2, z3, t):
    # monotone (Steffen 1990) cubic between z1 and z2 on unit spacing, t in [0, 1]
    def slope(sa, sb):
        if sa * sb <= 0:
            return 0.0
        p = (sa + sb) / 2
        return math.copysign(1, sa) * min(abs(sa), abs(sb), abs(p) / 2) * 2
    s0, s1, s2 = z1 - z0, z2 - z1, z3 - z2
    m1, m2 = slope(s0, s1), slope(s1, s2)
    a = m1 + m2 - 2 * s1
    b = 3 * s1 - 2 * m1 - m2
    return ((a * t + b) * t + m1) * t + z1


def spline(nodes, spacing=1.0):
    # the driveline's nodes followed as the game's road tools do, a point about every `spacing` m
    n = len(nodes)
    if n < 3:
        return [{'x': p[0], 'y': p[1], 'z': p[2]} for p in nodes]
    out = []
    for j in range(n - 1):
        i0, i3 = max(0, j - 1), min(n - 1, j + 2)
        p0, p1, p2, p3 = nodes[i0], nodes[j], nodes[j + 1], nodes[i3]
        if i0 == j:
            p0 = tuple(2 * a - b for a, b in zip(p1, p2))
        if i3 == j + 1:
            p3 = tuple(2 * a - b for a, b in zip(p2, p1))
        div = max(1, int(math.dist(p1[:2], p2[:2]) / spacing + 0.5))
        for k in range(0 if j == 0 else 1, div + 1):
            t = k / div
            x, y = _cr(p0[:2], p1[:2], p2[:2], p3[:2], t)
            out.append({'x': x, 'y': y, 'z': _steffen(p0[2], p1[2], p2[2], p3[2], t)})
    return out


def kind_of(t):
    if t == 'caution':
        return 'caution'
    if t in ('jump', 'bigJump', 'overJump', 'badJump', 'badDipJump'):
        return 'jump'
    if 'rest' in t.lower():
        return 'crest'
    if t in ('dip', 'badDip', 'throughDip', 'overDip'):
        return 'dip'
    if t.startswith('chicane'):
        return 'chicane'
    if t in ('twisty', 'narrows', 'finish', 'toStop'):
        return t
    if t in ('up', 'down'):
        return 'hill'
    return None


def kinds(items):
    out = set()
    for k in '123456':
        it = items.get(k) or {}
        t = it.get('type') if isinstance(it, dict) else None
        if not t:
            continue
        if t == 'corner':
            out.add('corner')
            d, s = it.get('descriptor'), it.get('shape')
            if d in ('hairpin', 'openHairpin', 'tightHairpin'):
                out.add('hairpin')
            if d == 'square':
                out.add('square')
            if s and 'Crest' in s:
                out.add('crest')
            if s in ('tightens', 'tightensDown', 'tightensOverCrest'):
                out.add('tightens')
            if s in ('opens', 'opensOverCrest'):
                out.add('opens')
            continue
        c = kind_of(t)
        if c:
            out.add(c)
    return out


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--game', default=DEFAULT_GAME)
    ap.add_argument('--radius', type=float, default=50.0)
    ap.add_argument('--stage')
    ap.add_argument('--straight', action='store_true')
    a = ap.parse_args()

    import lupa.luajit21 as lj
    lua = lj.LuaRuntime()
    lua.execute(f"package.path = '{LUA.as_posix()}/?.lua;' .. package.path")
    build = lua.execute('''
      local writer = require('earthRally/stageWriter')
      local geo = require('earthRally/geo')
      return function(line)
        local cum = geo.cumulative(line)
        return writer.build(line, { startM = 0, finishM = cum[#cum], quatFn = function() return 0, 0, 0, 1 end })
      end''')

    tot = collections.defaultdict(lambda: [0, 0, 0, 0])
    km, stages = 0.0, 0
    files = sorted(glob.glob(str(Path(a.game) / 'gameplay' / 'missions' / '*' / 'rallyStage' / '*' / 'rally' /
                                 'drivelineSpline.json')))
    for f in files:
        if a.stage and a.stage not in f:
            continue
        nbf = Path(f).parent / 'notebooks' / 'structured.notebook.json'
        if not nbf.exists():
            continue
        nb = json.loads(nbf.read_text(encoding='utf-8'))
        dl = json.loads(Path(f).read_text(encoding='utf-8'))
        nodes = [tuple(n[:3]) for n in dl['nodes']]
        line = [{'x': p[0], 'y': p[1], 'z': p[2]} for p in nodes] if a.straight else spline(nodes)
        b = build(lua.table_from([lua.table_from(p) for p in line]))
        km += b.lengthM / 1000
        stages += 1
        game = []
        for pn in nb['pacenotes']:
            it = (pn.get('structured') or {}).get('items') or {}
            w = pn['pacenoteWaypoints'][0]['pos']
            game.append(((w[0], w[1]), kinds(it)))
        ours = []
        for i in range(1, len(b.notebook.pacenotes) + 1):
            pn = b.notebook.pacenotes[i]
            it = pn.structured['items']
            d = {}
            for k in '123456':
                x = it[k]
                if x.type:
                    d[k] = {'type': x.type, 'descriptor': x.descriptor, 'shape': x.shape}
            p = pn.pacenoteWaypoints[1].pos
            ours.append(((p[1], p[2]), kinds(d)))
        every = set()
        for _, k in game + ours:
            every |= k
        for kk in every:
            g = [p for p, k in game if kk in k]
            o = [p for p, k in ours if kk in k]
            tot[kk][0] += len(g)
            tot[kk][1] += len(o)
            tot[kk][2] += sum(1 for p in g if any(math.dist(p, q) <= a.radius for q in o))
            tot[kk][3] += sum(1 for q in o if any(math.dist(p, q) <= a.radius for p in g))
    if not stages:
        print('no rally stages with a notebook under', a.game)
        return 1
    print(f'{stages} stages, {km:.1f} km, within {a.radius:.0f} m, ' +
          ('nodes joined by straight lines' if a.straight else "the game's spline through the nodes"))
    print('kind        game  ours   recall        precision')
    for kk, (g, o, rc, pr) in sorted(tot.items()):
        print(f'{kk:10s} {g:5d} {o:5d}   {rc:4d} {rc / max(g, 1):5.0%}   {pr:4d} {pr / max(o, 1):5.0%}')
    return 0


if __name__ == '__main__':
    sys.exit(main())
