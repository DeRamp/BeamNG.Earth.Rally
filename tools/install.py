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
USER_LAYOUT_REL = os.path.join('settings', 'ui_apps', 'layouts', 'default')
OUR_LAYOUT = 'earthRallyStage.uilayout.json'
# The apps the stage layout must carry for the on-stage HUD (the runner logs the same check in game).
# (1.1.0 to 1.2.1: this script wrote its own stage layout over the mod's, BeamNG.Earth's with only the pacenote cards
# added, so the HUD apps and the game's rally apps 1.2.0 put in the layout never reached the game: nothing but the
# pacenote cards showed on a stage. The mod's layout file is copied as it is now.)
STAGE_APPS = ('earthRallyHud', 'earthRallyResults', 'rallyCountdown', 'rallyStageTiming', 'rallyStageProgress',
              'rallyVisualPacenotes')


def check_layout(path):
    """The stage apps missing from the layout file at path (empty: all there)."""
    with open(path, encoding='utf-8') as f:
        layout = json.load(f)
    have = {a.get('appName') for a in layout.get('apps', [])}
    return [n for n in STAGE_APPS if n not in have]


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
    missing = check_layout(os.path.join(dest, LAYOUT_REL, OUR_LAYOUT))
    if missing:
        print('Warning: the stage layout installed lacks ' + ', '.join(missing) + ': the HUD would not show.')
    # (a copy of the layout the player saved from the game's layout editor is used before the mod's)
    user_layout = os.path.join(args.user_dir, USER_LAYOUT_REL, OUR_LAYOUT)
    if os.path.isfile(user_layout):
        user_missing = check_layout(user_layout)
        if user_missing:
            print(f'Warning: {user_layout} (a saved copy of the stage layout) lacks ' + ', '.join(user_missing)
                  + ': delete it (or reset the layout in the game) so the mod\'s is used.')
    os.makedirs(os.path.join(args.user_dir, 'earthRally', 'events'), exist_ok=True)
    print(f'Earth Rally installed in {dest}')
    print('In game: load the BeamNG.Earth level, then Ctrl+Alt+K opens the Earth Rally window.')
    return 0


if __name__ == '__main__':
    sys.exit(main())
