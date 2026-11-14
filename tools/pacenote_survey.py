#!/usr/bin/env python3
"""What the co-driver would call on every matched line in a folder: each call's count per km, over all of them.

    python tools/pacenote_survey.py <earthRally user folder or its matched/ folder> [--stage <part of a file name>]

Builds each stage's notebook with the mod's own stageWriter.build (under LuaJIT through lupa, as the offline tests
do), the whole matched line taken as the stage, so the thresholds in pacenotes.lua can be tuned against real roads
before anyone drives them. With --stage it prints that stage's notes one by one, in order, with where they are.
Reads only; writes nothing. Needs `pip install lupa`.
"""
import argparse
import json
import math
import sys
from collections import Counter
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
LUA = ROOT / 'mod' / 'earth_rally' / 'lua' / 'ge' / 'extensions'
R_EARTH = 6371008.8


def flat(points):
    lat0, lon0 = points[0][0], points[0][1]
    c = math.cos(math.radians(lat0))
    out = []
    for p in points:
        out.append({'x': math.radians(p[1] - lon0) * R_EARTH * c, 'y': math.radians(p[0] - lat0) * R_EARTH,
                    'z': p[2] if len(p) > 2 else None, 'gap': len(p) > 3 and p[3] == 1})
    return out


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('folder')
    ap.add_argument('--stage')
    a = ap.parse_args()
    folder = Path(a.folder)
    if (folder / 'matched').is_dir():
        folder = folder / 'matched'
    files = sorted(folder.glob('*.json'))
    if a.stage:
        files = [f for f in files if a.stage in f.name]
    if not files:
        print('no matched lines in', folder)
        return 1

    import lupa.luajit21 as lj
    lua = lj.LuaRuntime()
    lua.execute(f"package.path = '{LUA.as_posix()}/?.lua;' .. package.path")
    build = lua.execute('''
      local writer = require('earthRally/stageWriter')
      local geo = require('earthRally/geo')
      return function(line, landmarks)
        local cum = geo.cumulative(line)
        local mute, from = {}, nil
        for i, p in ipairs(line) do
          if p.gap then from = from or cum[i]
          elseif from then mute[#mute + 1] = { from - writer.MUTE_PAD_M, cum[i] + writer.MUTE_PAD_M } from = nil end
        end
        if from then mute[#mute + 1] = { from - writer.MUTE_PAD_M, cum[#cum] } end
        local lms = {}
        for _, lm in ipairs(landmarks) do
          local _, _, s, off = geo.locate(line, cum, lm)
          if off <= 15 then lms[#lms + 1] = { s = s, type = lm.type } end
        end
        return writer.build(line, { startM = 0, finishM = cum[#cum], mute = mute, landmarks = lms,
                                    quatFn = function() return 0, 0, 0, 1 end })
      end''')

    total = Counter()
    km = 0.0
    for f in files:
        m = json.loads(f.read_text(encoding='utf-8'))
        pts = m.get('points') or []
        if len(pts) < 50:
            continue
        line = flat(pts)
        lat0, lon0 = pts[0][0], pts[0][1]
        c = math.cos(math.radians(lat0))

        def at(la, lo):
            return {'x': math.radians(lo - lon0) * R_EARTH * c, 'y': math.radians(la - lat0) * R_EARTH}
        lms = []
        for j in m.get('junctions') or []:
            t = {'turn': 'atJunction', 'straight': 'pastJunction'}.get(j[2])
            if j[2] == 'fork':
                t = 'keepLeft' if j[3] == 'left' else 'keepRight'
            if t:
                lms.append(dict(at(j[0], j[1]), type=t))
        for b in m.get('bridges') or []:
            lms.append(dict(at(b[0], b[1]), type='overBridge'))
        for n in m.get('narrows') or []:
            lms.append(dict(at(n[0], n[1]), type='narrows'))
        lt = lua.table_from([lua.table_from({k: v for k, v in p.items() if v is not None and v is not False})
                             for p in line])
        lmt = lua.table_from([lua.table_from(x) for x in lms])
        built = build(lt, lmt)
        km += built.lengthM / 1000
        calls = built.calls
        for k in calls.keys():
            total[k] += calls[k]
        total['notes'] += built.notes
        if a.stage:
            nb = built.notebook
            for n in range(1, len(nb.pacenotes) + 1):
                pn = nb.pacenotes[n]
                it = pn.structured['items']
                words = []
                for s in '123456':
                    x = it[s]
                    if x.type:
                        w = x.type
                        if x.type == 'caution':
                            w = 'caution %d' % x.level
                        if x.type == 'corner':
                            md = pn.metadata.earthRally
                            w = 'corner %s %.0fdeg r%.0f' % (md.dir, md.angleDeg, md.minRadius)
                            if x.descriptor:
                                w += ' ' + x.descriptor
                            if x.shape:
                                w += ' ' + x.shape
                        words.append(w)
                p = pn.pacenoteWaypoints[1].pos
                print('%3d  %s' % (n, ' | '.join(words)))
    print('%d stages, %.1f km, %d notes (%.2f / km)' % (len(files), km, total['notes'], total['notes'] / max(km, 1e-9)))
    for k, v in sorted(total.items(), key=lambda kv: -kv[1]):
        if k != 'notes':
            print('  %-22s %6d   %6.2f / km' % (k, v, v / max(km, 1e-9)))
    return 0


if __name__ == '__main__':
    sys.exit(main())
