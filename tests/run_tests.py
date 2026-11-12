#!/usr/bin/env python3
"""Run Earth Rally's offline Lua tests (no BeamNG needed) under LuaJIT 2.1, the game's Lua.

    pip install lupa
    python tests/run_tests.py            (all)
    python tests/run_tests.py test_geo   (one)
"""
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
TESTS = ROOT / 'tests'
LUA = ROOT / 'mod' / 'earth_rally' / 'lua' / 'ge' / 'extensions'


def run_one(path):
    import lupa.luajit21 as lj
    lua = lj.LuaRuntime()
    lua.globals().TESTS = TESTS.as_posix()
    lua.execute(f"package.path = '{LUA.as_posix()}/?.lua;' .. package.path")
    lua.execute('dofile(...)', path.as_posix())


def main():
    if len(sys.argv) > 2 and sys.argv[1] == '--child':
        run_one(Path(sys.argv[2]))
        return 0
    names = sys.argv[1:] or [p.stem for p in sorted(TESTS.glob('test_*.lua'))]
    failed = 0
    for name in names:
        path = TESTS / (Path(name).stem + '.lua')
        # (each in its own process: a test's globals and os.exit stay its own)
        r = subprocess.run([sys.executable, __file__, '--child', str(path)])
        if r.returncode != 0:
            failed += 1
            print(f'{path.name}: FAILED (exit {r.returncode})')
    print(f'{len(names) - failed} of {len(names)} test files passed')
    return 1 if failed else 0


if __name__ == '__main__':
    sys.exit(main())
