#!/usr/bin/env python3
"""The in-game importer (importer.lua, run under LuaJIT through lupa) against tools/import_kml.py on the real maps in
Rally Docs/ (not in the repository: skipped when they are not there). Both must find the same stages, lengths,
controls and centres, so a rally imported either way runs the same."""
import math
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
LUA = ROOT / 'mod' / 'earth_rally' / 'lua' / 'ge' / 'extensions'
sys.path.insert(0, str(ROOT / 'tools'))


def main():
    docs = sorted(p for p in (ROOT.parent / 'Rally Docs').glob('*') if p.suffix.lower() in ('.kml', '.kmz', '.gpx'))
    if not docs:
        print('test_import_parity: no maps in Rally Docs/: skipped')
        return 0
    import import_kml
    import lupa.luajit21 as lj
    lua = lj.LuaRuntime()
    lua.execute(f"package.path = '{LUA.as_posix()}/?.lua;' .. package.path")
    lua.execute('function log() end')
    imp = lua.eval("require('earthRally/importer')")
    passed = failed = 0

    def check(ok, what):
        nonlocal passed, failed
        if ok:
            passed += 1
        else:
            failed += 1
            print('FAIL:', what)

    for path in docs:
        if path.suffix.lower() == '.kmz':
            continue
        py, _ = import_kml.build_event(str(path), 'x', 'X')
        text = path.read_text(encoding='utf-8', errors='replace')
        parsed = imp.parse(text, 'gpx' if path.suffix.lower() == '.gpx' else 'kml')
        ev, _ = imp.build(parsed, 'x', 'X', path.name)
        ls = [ev.stages[i + 1] for i in range(len(ev.stages))]
        check(len(ls) == len(py['stages']), f'{path.name}: {len(ls)} stages in Lua, {len(py["stages"])} in Python')
        for a, b in zip(ls, py['stages']):
            name = f'{path.name} {b["id"]}'
            check(a.id == b['id'], f'{name}: id {a.id}')
            check(abs(a.lengthM - b['lengthM']) < 1.0, f'{name}: length {a.lengthM} vs {b["lengthM"]}')
            lc = sorted(k for k in ('atc', 'start', 'ff', 'stop') if a.controls[k] is not None)
            check(lc == sorted(b['controls']), f'{name}: controls {lc} vs {sorted(b["controls"])}')
            for k in lc:
                check(abs(a.controls[k].distM - b['controls'][k]['distM']) < 1.0, f'{name}: {k} along the line')
            d = math.hypot((a.centre.lat - b['centre']['lat']) * 111195,
                           (a.centre.lon - b['centre']['lon']) * 111195 * math.cos(math.radians(b['centre']['lat'])))
            check(d < 1.0 and abs(a.radiusM - b['radiusM']) < 1.0, f'{name}: centre {d:.2f} m apart')
            check(len(a.line) == len(b['line']), f'{name}: {len(a.line)} line points vs {len(b["line"])}')
    print(f'test_import_parity: {passed} passed, {failed} failed')
    return 1 if failed else 0


if __name__ == '__main__':
    sys.exit(main())
