#!/usr/bin/env python3
"""Build the Earth Rally mod zip for a release: dist/earth_rally-<version>.zip, the mod's folders (lua/, scripts/,
settings/) at the top of the zip as BeamNG.drive's mod manager (and BeamNG.Earth's add-on list) expect.

    python tools/package.py 1.0.0-alpha
"""
import os
import sys
import zipfile

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SRC = os.path.join(ROOT, 'mod', 'earth_rally')


def main():
    if len(sys.argv) != 2:
        print(__doc__)
        return 1
    version = sys.argv[1]
    out_dir = os.path.join(ROOT, 'dist')
    os.makedirs(out_dir, exist_ok=True)
    out = os.path.join(out_dir, f'earth_rally-{version}.zip')
    n = 0
    with zipfile.ZipFile(out, 'w', zipfile.ZIP_DEFLATED) as z:
        for base, _, files in os.walk(SRC):
            for f in sorted(files):
                full = os.path.join(base, f)
                rel = os.path.relpath(full, SRC).replace(os.sep, '/')
                z.write(full, rel)
                n += 1
    print(f'{out}: {n} files')
    return 0


if __name__ == '__main__':
    sys.exit(main())
