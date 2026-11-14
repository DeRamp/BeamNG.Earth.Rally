#!/usr/bin/env python3
"""tools/auto_recce.py (junction_entry, bearing) and the mod (junctions.encode / dirToBearing, Lua) write a junction
the same way in the matched file, format 2: [lat, lon, kind, side, inDeg, outDeg, [[sideDeg, halfW], ...], half],
bearings clockwise from north to 0.1 degree, halfW and half 0 where it is not known (always, from the tool). Roads every way."""
import math
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
LUA = ROOT / 'mod' / 'earth_rally' / 'lua' / 'ge' / 'extensions'
sys.path.insert(0, str(ROOT / 'tools'))


def main():
    import auto_recce
    import lupa.luajit21 as lj
    lua = lj.LuaRuntime()
    lua.execute(f"package.path = '{LUA.as_posix()}/?.lua;' .. package.path")
    J = lua.eval("require('earthRally/junctions')")
    n = bad = 0

    def check(ok, name):
        nonlocal n, bad
        n += 1
        if not ok:
            bad += 1
            print('FAIL:', name)

    # the compass both sides agree on, every 7.5 degrees, and the four points named
    for name, v, want in (('north', (0, 1), 0), ('east', (1, 0), 90), ('south', (0, -1), 180), ('west', (-1, 0), 270)):
        check(abs(auto_recce.bearing(v) - want) < 1e-9, f'the tool: a road heading {name} is {want}')
    worst = 0.0
    for k in range(48):
        b = k * 7.5
        v = (math.sin(math.radians(b)) * 9, math.cos(math.radians(b)) * 9)
        d = abs(auto_recce.bearing(v) - J.dirToBearing(v[0], v[1]))
        worst = max(worst, min(d, 360 - d))
    check(worst < 1e-9, f'the tool and the mod read every direction the same (worst {worst})')

    # one entry each way: a turn with two side roads, written by both
    w_in, w_out = (0.3, 12.0), (12.0, -0.2)
    sides = [(0.0, 15.0), (-15.0, 0.4), (-0.001, 15.0)]
    py = auto_recce.junction_entry(47.1, -123.2, 'turn', '', w_in, w_out, sides)
    rec = lua.table_from({
        'kind': 'turn', 'side': '',
        'inDeg': J.dirToBearing(*w_in), 'outDeg': J.dirToBearing(*w_out),
        'sides': lua.table_from([lua.table_from({'deg': J.dirToBearing(*w)}) for w in sides]),
    })
    e = J.encode(rec, 47.1, -123.2)
    lu = [e[1], e[2], e[3], e[4], e[5], e[6], [[s[1], s[2]] for s in e[7].values()], e[8]]
    check(py == lu, f'the same entry from the tool and the mod ({py} / {lu})')
    check(py[6][2][0] == 0, 'just west of north rounds to 0, not 360')
    check(all(s[1] == 0 for s in py[6]), 'the tool writes 0 for a width it does not know')
    check(len(py) == 8 and py[7] == 0, "the eighth entry, the stage road's half width: 0 from the tool (not known)")
    print(f'test_junction_format: {n - bad} passed, {bad} failed')
    return 1 if bad else 0


if __name__ == '__main__':
    sys.exit(main())
