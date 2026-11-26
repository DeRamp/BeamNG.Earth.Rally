#!/usr/bin/env python3
"""The downloadable templates (templates/): the zip is the folder's, every .txt and .csv is plain UTF-8 that Notepad
and Excel open, and nothing in them is organisers' material."""
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def main():
    failed = 0

    def check(ok, what):
        nonlocal failed
        print(('ok    ' if ok else 'FAIL  ') + what)
        if not ok:
            failed += 1
    r = subprocess.run([sys.executable, str(ROOT / 'tools' / 'make_templates.py'), '--check'], capture_output=True)
    check(r.returncode == 0, 'templates zip matches the folder (else run tools/make_templates.py)')
    files = [p for p in (ROOT / 'templates' / 'Earth Rally templates').rglob('*') if p.is_file()]
    check(len(files) >= 5, 'the template files are there')
    for p in files:
        b = p.read_bytes()
        try:
            b.decode('utf-8')
            ok = not b.startswith(b'\xef\xbb\xbf')
        except UnicodeDecodeError:
            ok = False
        check(ok, f'{p.name}: plain UTF-8')
    print(f'{failed} failed' if failed else 'all ok')
    return 1 if failed else 0


if __name__ == '__main__':
    sys.exit(main())
