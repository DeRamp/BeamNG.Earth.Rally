#!/usr/bin/env python3
"""The mod (events.mapKey, Lua) and tools/match_roads.py (map_key) describe a stage's map line the same way, on the
real event files in the game's user folder (skipped when there are none): else every matched line would be taken for
one made from another version of the map, and not used."""
import json
import os
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
LUA = ROOT / 'mod' / 'earth_rally' / 'lua' / 'ge' / 'extensions'
sys.path.insert(0, str(ROOT / 'tools'))


def main():
    events = Path(os.environ.get('LOCALAPPDATA', '')) / 'BeamNG' / 'BeamNG.drive' / 'current' / 'earthRally' / 'events'
    files = sorted(events.glob('*.json')) if events.is_dir() else []
    if not files:
        print('test_mapkey: no events in the game folder: skipped')
        return 0
    import match_roads
    import lupa.luajit21 as lj
    lua = lj.LuaRuntime()
    lua.execute(f"package.path = '{LUA.as_posix()}/?.lua;' .. package.path")
    lua.execute('FS = {} function log() end')
    ev_mod = lua.eval("require('earthRally/events')")
    n = bad = 0
    for f in files:
        e = json.loads(f.read_text(encoding='utf-8'))
        for st in e.get('stages', []):
            n += 1
            # the line as the game's JSON reader gives it: a Lua table of {lat, lon}
            t = lua.table_from([lua.table_from(p) for p in st['line']])
            if ev_mod.mapKey(t) != match_roads.map_key(st['line']):
                bad += 1
                print('FAIL:', f.name, st['id'], ev_mod.mapKey(t), match_roads.map_key(st['line']))
    print(f'test_mapkey: {n - bad} passed, {bad} failed')
    return 1 if bad else 0


if __name__ == '__main__':
    sys.exit(main())
