#!/usr/bin/env python3
"""Every Lua file of the mod compiles under LuaJIT 2.1 (the game's Lua): a syntax error anywhere stops the mod
loading, and most files are not loaded by any other test."""
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def main():
    import lupa.luajit21 as lj
    lua = lj.LuaRuntime()
    check = lua.eval('function(s, n) local f, e = loadstring(s, n) return e end')
    bad = 0
    files = sorted((ROOT / 'mod').rglob('*.lua'))
    for f in files:
        err = check(f.read_text(encoding='utf-8'), str(f.relative_to(ROOT)))
        if err:
            bad += 1
            print('FAIL:', err)
    print(f'test_compile: {len(files) - bad} passed, {bad} failed')
    return 1 if bad else 0


if __name__ == '__main__':
    sys.exit(main())
