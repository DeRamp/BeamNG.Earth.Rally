#!/usr/bin/env python3
"""The co-driver's notes against the game's own hand-made ones: for each kind of call, how many of the game's we
also call (recall) and how many of ours the game also has (precision), within a distance.

    python tools/pacenote_benchmark.py [--game "<BeamNG.drive folder>"] [--radius 50] [--stage <part of a path>]

Runs the mod's own stageWriter.build (under LuaJIT through lupa, as the offline tests do) on the drivelineSpline.json
of every rally stage the game ships that has a structured notebook, the whole driveline taken as the stage, and
matches notes by where their first waypoint is. Those drivelines carry the real road surface's heights -- but a node
only every 20 to 40 m, where a matched line has one every 4 m, so a short sharp hump (a jump, a dip) is often not in
them at all: read the height rows as a floor. The game's notes are a person's, so neither side is "the truth" -- but
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
        line = [{'x': n[0], 'y': n[1], 'z': n[2]} for n in dl['nodes']]
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
    print(f'{stages} stages, {km:.1f} km, within {a.radius:.0f} m')
    print('kind        game  ours   recall        precision')
    for kk, (g, o, rc, pr) in sorted(tot.items()):
        print(f'{kk:10s} {g:5d} {o:5d}   {rc:4d} {rc / max(g, 1):5.0%}   {pr:4d} {pr / max(o, 1):5.0%}')
    return 0


if __name__ == '__main__':
    sys.exit(main())
