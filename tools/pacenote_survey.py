#!/usr/bin/env python3
"""What the co-driver would call on every matched line in a folder: each call's count per km, over all of them.

    python tools/pacenote_survey.py <earthRally user folder or its matched/ folder> [--stage <part of a file name>]
                                    [--casual]

Builds each stage's notebook with the mod's own stageWriter.build (under LuaJIT through lupa, as the offline tests
do), the whole matched line taken as the stage, so the thresholds in pacenotes.lua can be tuned against real roads
before anyone drives them. With --stage it prints that stage's notes one by one, in order, with where they are.
A line saved twice (the same points under two names) is counted once. --casual: as a casual voice hears it (the
calls the game's english/casual style says, below), what the rallyAdapter.speaks filter does in game.
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
# gameplay/rally/compositors/styles/english/casual.lua (0.40.5): its modifiers, their aliases, its descriptors; no
# corner shapes
CASUAL = ['overJump', 'crest', 'watersplash', 'ontoGravel', 'ontoIce', 'ontoTarmac', 'ontoMud', 'slippy', 'stop',
          'toStop', 'finish', 'chicaneLeftEntry', 'chicaneRightEntry', 'jump', 'badDipJump', 'badJump', 'bigJump',
          'brakeOverCrest', 'middleOverCrest', 'keepLeftOverCrest', 'keepMiddleOverCrest', 'keepRightOverCrest',
          'overCrest', 'crestOnly', 'intoCrest', 'longCrest', 'bigCrest', 'smallCrest', 'water', 'intoWater',
          'overFinish', 'descriptor:flat', 'descriptor:square', 'descriptor:hairpin', 'descriptor:openHairpin',
          'descriptor:tightHairpin']


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
    ap.add_argument('--casual', action='store_true')
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
      return function(line, landmarks, speaks)
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
          if off <= 15 then
            local item = { s = s, type = lm.type }
            if lm.endX then
              local _, _, s2, off2 = geo.locate(line, cum, { x = lm.endX, y = lm.endY })
              if off2 <= 15 then item.sEnd = s2 end
            end
            lms[#lms + 1] = item
          end
        end
        return writer.build(line, { startM = 0, finishM = cum[#cum], mute = mute, landmarks = lms,
                                    quatFn = function() return 0, 0, 0, 1 end, speaks = speaks })
      end''')
    geo = lua.require('earthRally/geo')
    locate, cumulative = geo.locate, geo.cumulative

    speaks = lua.table_from({k: True for k in CASUAL}) if a.casual else None
    total = Counter()
    km, stages, twins = 0.0, 0, 0
    seenLines = set()
    for f in files:
        m = json.loads(f.read_text(encoding='utf-8'))
        pts = m.get('points') or []
        if len(pts) < 50:
            continue
        key = (len(pts), tuple(round(x, 6) for x in pts[0][:2]), tuple(round(x, 6) for x in pts[-1][:2]))
        if key in seenLines:
            twins += 1
            continue
        seenLines.add(key)
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
            far = at(b[2], b[3]) if len(b) >= 4 else None
            lms.append(dict(at(b[0], b[1]), type='overBridge',
                            **({'endX': far['x'], 'endY': far['y']} if far else {})))
        for n in m.get('narrows') or []:
            lms.append(dict(at(n[0], n[1]), type='narrows'))
        lt = lua.table_from([lua.table_from({k: v for k, v in p.items() if v is not None and v is not False})
                             for p in line])
        lmt = lua.table_from([lua.table_from(x) for x in lms])
        built = build(lt, lmt, speaks)
        if a.stage:
            line_t, cum_t = lt, cumulative(lt)
        km += built.lengthM / 1000
        stages += 1
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
                _, _, along, _ = locate(line_t, cum_t, lua.table_from({'x': p[1], 'y': p[2]}))
                print('%3d  %6.0f m  %s' % (n, along, ' | '.join(words)))
    print('%d stages (%d more the same line as one of them, left out), %.1f km, %d notes (%.2f / km; one finish '
          'note on each stage among them)%s' % (stages, twins, km, total['notes'], total['notes'] / max(km, 1e-9),
                                               ', as a casual voice hears them' if a.casual else ''))
    for k, v in sorted(total.items(), key=lambda kv: -kv[1]):
        if k != 'notes':
            print('  %-22s %6d   %6.2f / km' % (k, v, v / max(km, 1e-9)))
    return 0


if __name__ == '__main__':
    sys.exit(main())
