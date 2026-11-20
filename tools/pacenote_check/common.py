"""Shared by the pacenote check tools: a Lua runtime with the mod and the game-voice harness loaded, and the stages
(the player's matched lines, the game's own hand-made rally stages, the fixtures) turned into lines for
stageWriter.build. Reads only."""
import json
import math
import os
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
LUA = ROOT / 'mod' / 'earth_rally' / 'lua' / 'ge' / 'extensions'
HERE = Path(__file__).resolve().parent
DEFAULT_GAME = r'C:/Program Files (x86)/Steam/steamapps/common/BeamNG.drive'
R_EARTH = 6371008.8


def user_folder():
    base = Path(os.environ.get('LOCALAPPDATA', '')) / 'BeamNG' / 'BeamNG.drive' / 'current' / 'earthRally'
    return base


def runtime(game=DEFAULT_GAME):
    """A LuaJIT (or Lua 5.1 where LuaJIT is blocked) runtime: the mod on package.path, the harness set up."""
    try:
        import lupa.luajit21 as lj
        lua = lj.LuaRuntime()
    except Exception:  # LuaJIT's DLL blocked by application control on some PCs
        import lupa.lua51 as lj
        lua = lj.LuaRuntime()
    lua.execute(f"package.path = '{LUA.as_posix()}/?.lua;{HERE.as_posix()}/?.lua;' .. package.path")
    lua.execute("""if not bit then
      local function b(f) return function(a, c) local r, m = 0, 1 a, c = a % 4294967296, c % 4294967296
        while a > 0 or c > 0 do if f(a % 2, c % 2) then r = r + m end a, c, m = math.floor(a / 2), math.floor(c / 2), m * 2 end return r end end
      bit = { band = b(function(x, y) return x == 1 and y == 1 end), bor = b(function(x, y) return x == 1 or y == 1 end),
        bxor = b(function(x, y) return x ~= y end), lshift = function(a, n) return (a * 2 ^ n) % 4294967296 end,
        rshift = function(a, n) return math.floor((a % 4294967296) / 2 ^ n) end, tobit = function(a) return a end }
    end
    loadstring = loadstring or load""")
    voice = lua.require('gamevoice')
    voice.setup((Path(game) / 'lua').as_posix())
    build = lua.execute('''
      local writer = require('earthRally/stageWriter')
      local geo = require('earthRally/geo')
      return function(line, landmarks, speaks, startM, finishM)
        local cum = geo.cumulative(line)
        local mute, from = {}, nil
        for i, p in ipairs(line) do
          if p.gap then from = from or cum[i]
          elseif from then mute[#mute + 1] = { from - writer.MUTE_PAD_M, cum[i] + writer.MUTE_PAD_M } from = nil end
        end
        if from then mute[#mute + 1] = { from - writer.MUTE_PAD_M, cum[#cum] } end
        local lms = {}
        for _, lm in ipairs(landmarks or {}) do
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
        return writer.build(line, { startM = startM or 0, finishM = finishM or cum[#cum], mute = mute,
                                    landmarks = lms, quatFn = function() return 0, 0, 0, 1 end, speaks = speaks })
      end''')
    return lua, voice, build


def to_lua(lua, line, landmarks=()):
    lt = lua.table_from([lua.table_from({k: v for k, v in p.items() if v is not None and v is not False})
                         for p in line])
    lmt = lua.table_from([lua.table_from(x) for x in landmarks])
    return lt, lmt


def _ground_m(a, b):
    c = math.cos(math.radians((a[0] + b[0]) / 2))
    return math.hypot(math.radians(a[0] - b[0]) * R_EARTH, math.radians(a[1] - b[1]) * R_EARTH * c)


def _length_m(pts):
    return sum(_ground_m(p, q) for p, q in zip(pts, pts[1:]))


def matched_stages(folder=None, stage=None, skipped=None):
    """The player's matched lines: (name, line, landmarks, junctions, at), each road once: a line that starts and
    ends within 20 m of one already read, and is within 2 % of its length, is the same stage (another event's copy);
    it goes in `skipped` (a dict) instead."""
    folder = Path(folder) if folder else user_folder()
    if (folder / 'matched').is_dir():
        folder = folder / 'matched'
    seen = {}
    kept = []
    for f in sorted(folder.glob('*.json')):
        if stage and stage not in f.name:
            continue
        m = json.loads(f.read_text(encoding='utf-8'))
        pts = m.get('points') or []
        if len(pts) < 50:
            continue
        key = (len(pts), tuple(round(x, 6) for x in pts[0][:2]), tuple(round(x, 6) for x in pts[-1][:2]))
        if key in seen:
            if skipped is not None:
                skipped[f.stem] = 'same line as ' + seen[key]
            continue
        seen[key] = f.stem
        length = _length_m(pts)
        same = next((n for n, a, b, L in kept if _ground_m(a, pts[0]) <= 20 and _ground_m(b, pts[-1]) <= 20 and
                     abs(L - length) <= 0.02 * max(L, length)), None)
        if same:
            if skipped is not None:
                skipped[f.stem] = 'same road as ' + same
            continue
        kept.append((f.stem, pts[0], pts[-1], length))
        lat0, lon0 = pts[0][0], pts[0][1]
        c = math.cos(math.radians(lat0))

        def at(la, lo):
            return {'x': math.radians(lo - lon0) * R_EARTH * c, 'y': math.radians(la - lat0) * R_EARTH}
        line = []
        for p in pts:
            q = at(p[0], p[1])
            q['z'] = p[2] if len(p) > 2 else None
            q['gap'] = len(p) > 3 and p[3] == 1
            line.append(q)
        lms = []
        for b in m.get('bridges') or []:
            far = at(b[2], b[3]) if len(b) >= 4 else None
            lms.append(dict(at(b[0], b[1]), type='overBridge',
                            **({'endX': far['x'], 'endY': far['y']} if far else {})))
        for n in m.get('narrows') or []:
            lms.append(dict(at(n[0], n[1]), type='narrows'))
        yield f.stem, line, lms, m.get('junctions') or [], at


def junction_landmarks(lua, junctions, at):
    jm = lua.require('earthRally/junctions')
    out = []
    for j in junctions:
        t = {'turn': 'atJunction', 'straight': 'pastJunction'}.get(j[2])
        if j[2] == 'fork':
            t = 'keepLeft' if j[3] == 'left' else 'keepRight'
        if t and not jm.obvious(jm.decode(lua.table_from(j, recursive=True))):
            t = None
        if t:
            out.append(dict(at(j[0], j[1]), type=t))
    return out


def game_spline(nodes, spacing=1.0):
    """A game driveline's nodes followed as the game's road tools do (tools/pacenote_benchmark.py spline)."""
    sys.path.insert(0, str(ROOT / 'tools'))
    import pacenote_benchmark
    return pacenote_benchmark.spline(nodes, spacing)


def pro_stages(game=DEFAULT_GAME, stage=None):
    """The game's rally stages with a pro co-driver's notes: (name, driveline nodes, pro notebook, transcriptions
    {clip: {description}})."""
    base = Path(game) / 'gameplay' / 'missions'
    for f in sorted(base.glob('*/rallyStage/*/rally/notebooks/pro_ak.notebook.json')):
        rally = f.parents[1]
        name = f.parents[4].name + '/' + f.parents[2].name
        if stage and stage not in name:
            continue
        tp = rally / 'voicepacks' / 'pro' / 'transcriptions.json'
        dl = rally / 'drivelineSpline.json'
        if not tp.exists() or not dl.exists():
            continue
        nodes = [tuple(n[:3]) for n in json.loads(dl.read_text(encoding='utf-8'))['nodes']]
        # the start line and the finish: the race's start position and its last pathnode
        start = finish = None
        rf = f.parents[2] / 'race.race.json'
        if rf.exists():
            try:
                race = json.loads(rf.read_text(encoding='utf-8'))
                if race.get('startPositions'):
                    start = race['startPositions'][0]['pos']
                if race.get('pathnodes'):
                    finish = race['pathnodes'][-1]['pos']
            except (ValueError, KeyError, IndexError):
                pass
        yield (name, nodes, json.loads(f.read_text(encoding='utf-8')),
               json.loads(tp.read_text(encoding='utf-8')), start, finish)
