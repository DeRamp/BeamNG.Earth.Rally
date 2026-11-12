#!/usr/bin/env python3
"""Copy the Earth Rally mod into BeamNG.drive (run again after each change; the game must be restarted, or press
Ctrl+L in game to reload its Lua).

    python tools/install.py
    python tools/install.py --user-dir "D:\\BeamNG user folder\\current"
"""
import argparse
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


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument('--user-dir', default=default_user_dir(), help='the BeamNG.drive user folder (…/current)')
    args = ap.parse_args()
    if not os.path.isdir(args.user_dir):
        print(f'No BeamNG.drive user folder at {args.user_dir}: give it with --user-dir')
        return 1
    dest = os.path.join(args.user_dir, 'mods', 'unpacked', NAME)
    if os.path.isdir(dest):
        shutil.rmtree(dest)
    shutil.copytree(SRC, dest)
    os.makedirs(os.path.join(args.user_dir, 'earthRally', 'events'), exist_ok=True)
    print(f'Earth Rally installed in {dest}')
    print('In game: load the BeamNG.Earth level, then Ctrl+Alt+K opens the Earth Rally window.')
    return 0


if __name__ == '__main__':
    sys.exit(main())
