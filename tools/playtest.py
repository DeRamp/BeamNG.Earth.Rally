#!/usr/bin/env python3
"""Install Earth Rally, start the game, and go straight to a stage: the testing loop in one command.

    python tools/playtest.py                                  otr24 / maryhill-up, the stage driven
    python tools/playtest.py --event olympus26 --stage kuhnle
    python tools/playtest.py --goto                           taken to the start, not put into a run
    python tools/playtest.py --no-install                     the mod as installed
    python tools/playtest.py --gfx dx11                       no launch dialog, but no Steam Input either

It writes earthRally/playtest.json in the game's user folder; the mod reads (and deletes) it when it loads at the
main menu, loads the BeamNG.Earth level, waits for the world, and then drives the stage (main.lua, updatePlaytest).
The file is used once, so a normal start of the game never does any of this.

The game is started with BeamNG.Earth's launcher, which starts the world server too, and through Steam, so that
Steam Input reaches it and a controller works. BeamNG's launch-options dialog shows as a result: the launcher hands
over to Steam only when it passes the game no arguments, and -gfx, which would skip that dialog, is an argument.
"""
import argparse
import json
import os
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / 'tools'))
import install  # noqa: E402
import selftest  # noqa: E402

REQUEST_REL = Path('earthRally') / 'playtest.json'


def write_request(user_dir, event, stage, what):
    p = Path(user_dir) / REQUEST_REL
    p.parent.mkdir(parents=True, exist_ok=True)
    p.write_text(json.dumps({'event': event, 'stage': stage, 'what': what}, indent=1), encoding='utf-8')
    return p


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument('--user-dir', default=install.default_user_dir(), help="the BeamNG.drive user folder (…/current)")
    ap.add_argument('--event', default='otr24', help='the rally (its id in earthRally/events)')
    ap.add_argument('--stage', default='maryhill-up', help='the stage id')
    ap.add_argument('--goto', action='store_true', help='go to the start instead of driving the stage')
    ap.add_argument('--no-install', action='store_true', help='leave the installed mod alone')
    ap.add_argument('--earth', help="BeamNG.Earth's source folder (default: found next to this repository)")
    ap.add_argument('--gfx', choices=['dx11', 'dx12', 'vk'],
                    help="the renderer, which also skips BeamNG's launch-options dialog -- but the game is then "
                         "started directly, and Steam Input (a controller) does not reach it")
    ap.add_argument('--no-steam', action='store_true',
                    help="start the game directly rather than through Steam (implied by --gfx)")
    args = ap.parse_args(argv)

    if selftest.running_exes():
        print('BeamNG.drive is running: close it first.')
        return 2
    earth = Path(args.earth) if args.earth else selftest.find_earth()
    if not earth or not (earth / 'launcher.py').is_file():
        print("BeamNG.Earth's source folder (with launcher.py) not found: give it with --earth")
        return 2
    if not args.no_install:
        if subprocess.run([sys.executable, str(ROOT / 'tools' / 'install.py'),
                           '--user-dir', str(args.user_dir)]).returncode != 0:
            print('install failed')
            return 1
    if selftest.print_checks(selftest.check_install(args.user_dir)):
        print("The installed mod is not this repository's: not starting the game.")
        return 1

    req = write_request(args.user_dir, args.event, args.stage, 'goStart' if args.goto else 'drive')
    print(f'{req}: {args.event} / {args.stage}, '
          + ('taken to the start' if args.goto else 'the stage driven'))
    py = earth / '.venv' / ('Scripts/python.exe' if os.name == 'nt' else 'bin/python')
    cmd = [str(py if py.is_file() else sys.executable), 'launcher.py', '--no-beammp', '--no-update-check']
    # Through Steam by default: Steam Input only reaches a game Steam started, so a controller needs it (the user,
    # 2026-11-13; BeamNG.Earth's launcher says the same, GitHub #218). BeamNG's own launch-options dialog shows as a
    # result -- the launcher hands over to Steam only when it passes the game no arguments, and -gfx, which skips
    # that dialog, is an argument. Tick "don't show again" in the dialog itself to be rid of it and keep Steam.
    if args.gfx:
        cmd += ['--gfx', args.gfx]
    print('starting: ' + ' '.join(cmd) + f'  (in {earth})')
    subprocess.Popen(cmd, cwd=str(earth),
                     creationflags=getattr(subprocess, 'CREATE_NEW_CONSOLE', 0) if os.name == 'nt' else 0)
    print('The game is starting. It will load BeamNG.Earth and go to the stage by itself.')
    return 0


if __name__ == '__main__':
    sys.exit(main())
