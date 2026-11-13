#!/usr/bin/env python3
"""tools/install.py puts the mod's stage layout in the game as it is (1.2.1 in game: it wrote its own 1.1.0 layout
over it, without the HUD apps, so nothing but the pacenote cards showed on a stage), and the layout carries every app
the HUD needs. Installs into a stand-in user folder in a temporary directory, never the game's."""
import json
import os
import subprocess
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
LAYOUT = ROOT / 'mod' / 'earth_rally' / 'settings' / 'ui_apps' / 'originalLayouts' / 'default' / 'earthRallyStage.uilayout.json'
sys.path.insert(0, str(ROOT / 'tools'))


def main():
    import install
    failed = 0

    def check(ok, what):
        nonlocal failed
        print(('ok    ' if ok else 'FAIL  ') + what)
        if not ok:
            failed += 1

    check(install.check_layout(str(LAYOUT)) == [], "the mod's stage layout carries every HUD app")
    layout = json.loads(LAYOUT.read_text(encoding='utf-8'))
    check(layout.get('type') == 'earthRallyStage', 'its type is the one the runner puts on (earthRallyStage)')
    with tempfile.TemporaryDirectory() as tmp:
        user = Path(tmp) / 'current'
        # (a BeamNG.Earth installed with its own layout, as in the game's user folder)
        earth = user / 'mods' / 'unpacked' / 'beamng_earth' / 'settings' / 'ui_apps' / 'originalLayouts' / 'default'
        earth.mkdir(parents=True)
        (earth / 'beamngEarth.uilayout.json').write_text(json.dumps(
            {'type': 'beamngEarth', 'version': 4, 'apps': [{'appName': 'beamngEarthStatus'}]}), encoding='utf-8')
        r = subprocess.run([sys.executable, str(ROOT / 'tools' / 'install.py'), '--user-dir', str(user)],
                           capture_output=True, text=True)
        check(r.returncode == 0, 'install ran (' + ' | '.join((r.stdout + r.stderr).strip().splitlines()) + ')')
        put = (user / 'mods' / 'unpacked' / 'earth_rally' / 'settings' / 'ui_apps' / 'originalLayouts' / 'default'
               / 'earthRallyStage.uilayout.json')
        check(put.is_file() and put.read_bytes() == LAYOUT.read_bytes(), 'the stage layout installed as it is in the mod')
        check('Warning' not in r.stdout, 'no warning about the layout')
        # a saved copy of an old stage layout in the user folder: warned about
        saved = user / 'settings' / 'ui_apps' / 'layouts' / 'default'
        saved.mkdir(parents=True)
        (saved / 'earthRallyStage.uilayout.json').write_text(json.dumps(
            {'type': 'earthRallyStage', 'version': 4, 'apps': [{'appName': 'rallyVisualPacenotes'}]}), encoding='utf-8')
        r = subprocess.run([sys.executable, str(ROOT / 'tools' / 'install.py'), '--user-dir', str(user)],
                           capture_output=True, text=True)
        check(r.returncode == 0 and 'saved copy of the stage layout' in r.stdout, 'an old saved copy of the layout warned about')
    print(f'test_install: {"all passed" if not failed else str(failed) + " failed"}')
    return 1 if failed else 0


if __name__ == '__main__':
    sys.exit(main())
