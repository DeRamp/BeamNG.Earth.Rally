#!/usr/bin/env python3
"""Copy the Earth Rally mod into BeamNG.drive (run again after each change; the game must be restarted, or press
Ctrl+L in game to reload its Lua).

    python tools/install.py
    python tools/install.py --user-dir "D:\\BeamNG user folder\\current"
"""
import argparse
import json
import os
import shutil
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SRC = os.path.join(ROOT, 'mod', 'earth_rally')
NAME = 'earth_rally'


def default_user_dir():
    base = os.environ.get('LOCALAPPDATA')
    if base:
        return os.path.join(base, 'BeamNG', 'BeamNG.drive', 'current')
    return os.path.expanduser('~/.local/share/BeamNG/BeamNG.drive/current')


LAYOUT_REL = os.path.join('settings', 'ui_apps', 'originalLayouts', 'default')
EARTH_LAYOUT = 'beamngEarth.uilayout.json'
OUR_LAYOUT = 'earthRallyStage.uilayout.json'
# the game's own rally stage layout's pacenote cards (settings/ui_apps/originalLayouts/mission/rallyModeStage)
PACENOTE_APP = {
    'appName': 'rallyVisualPacenotes', 'appVersion': 1,
    'placement': {'bottom': '', 'height': '20%', 'left': '0px', 'margin': 'auto', 'position': 'absolute',
                  'right': '0px', 'top': '17.5%', 'width': '75%'},
}


def make_layout(earth_layout_path, out_path):
    """The run's layout: BeamNG.Earth's own (its status bar, map, credits) with the game's pacenote cards added."""
    with open(earth_layout_path, encoding='utf-8') as f:
        layout = json.load(f)
    layout['apps'] = [a for a in layout.get('apps', []) if a.get('appName') != PACENOTE_APP['appName']]
    layout['apps'].append(PACENOTE_APP)
    layout['title'] = 'Earth Rally stage'
    layout['type'] = 'earthRallyStage'
    layout['description'] = 'BeamNG.Earth with the rally pacenote cards (Earth Rally, during a stage)'
    with open(out_path, 'w', encoding='utf-8') as f:
        json.dump(layout, f, indent=2)


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument('--user-dir', default=default_user_dir(), help='the BeamNG.drive user folder (…/current)')
    args = ap.parse_args()
    if not os.path.isdir(args.user_dir):
        print(f'No BeamNG.drive user folder at {args.user_dir}: give it with --user-dir')
        return 1
    # (a release zip of the mod in the mods folder too: both would load)
    mods = os.path.join(args.user_dir, 'mods')
    zips = [f for f in (os.listdir(mods) if os.path.isdir(mods) else []) if f.lower().startswith('earth_rally')
            and f.lower().endswith('.zip')]
    if zips:
        print('Warning: ' + ', '.join(zips) + ' is also in ' + mods + ': two copies of Earth Rally would load. '
              'Remove the zip (or this unpacked copy) so only one is there.')
    dest = os.path.join(args.user_dir, 'mods', 'unpacked', NAME)
    if os.path.isdir(dest):
        shutil.rmtree(dest)
    shutil.copytree(SRC, dest)
    # the stage layout from the BeamNG.Earth installed now (else the copy in this repository stays)
    earth_layout = os.path.join(args.user_dir, 'mods', 'unpacked', 'beamng_earth', LAYOUT_REL, EARTH_LAYOUT)
    if os.path.isfile(earth_layout):
        make_layout(earth_layout, os.path.join(dest, LAYOUT_REL, OUR_LAYOUT))
    os.makedirs(os.path.join(args.user_dir, 'earthRally', 'events'), exist_ok=True)
    print(f'Earth Rally installed in {dest}')
    print('In game: load the BeamNG.Earth level, then Ctrl+Alt+K opens the Earth Rally window.')
    return 0


if __name__ == '__main__':
    sys.exit(main())
