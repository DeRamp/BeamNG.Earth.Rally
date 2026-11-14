#!/usr/bin/env python3
"""Earth Rally's automated in-game test: a real stage on BeamNG.Earth, with the mod checking itself as it goes
(mod .../earthRally/selftest.lua).

UNSTABLE -- do not gate a release on this. It cannot check the co-driver: the game decides whether to call a
pacenote from the car's rigid-body velocity, and this walks the car along the line rather than driving it, so that
one check fails and the whole run exits 1 every time. The other 22 checks are sound and the report is worth reading,
but a red result here means "the co-driver check is still missing", not "something broke". Until that is fixed
(1.4.0, with the co-driver work), the real check on a release is driving it yourself and writing what you find into
docs/notes-<next version>.md.

    python tools/selftest.py --check-install          only check the installed mod against this repository (read-only:
                                                      the files, the version, the stage layout's apps); safe while the
                                                      game runs
    python tools/selftest.py                          install the mod, start BeamNG.Earth (its launcher), run the test,
                                                      close the game, print the result (exit 1 on a failure)
    python tools/selftest.py --event otr24 --stage maryhill-up --gfx dx11 --timeout 1800
    python tools/selftest.py --keep-open              leave the game open at the end (for a look round)

The full run refuses to start while BeamNG.drive is running (it would install over the mod in use and start a second
game). How the test starts in the game: this script writes earthRally/selftest/request.json in the game's user folder;
the mod reads (and deletes) it when it loads at the main menu, loads the BeamNG.Earth level and runs the stage
(selftest.lua's phases); its report lands in earthRally/selftest/report-<time>.json, which this script waits for.
The request file is always deleted again at the end, so a normal start never runs a test.

The game is started with BeamNG.Earth's launcher (`launcher.py --no-beammp --no-update-check --gfx <renderer>`, from
its .venv), which starts the world server too and stops it when the game closes. --gfx skips the game's renderer
dialog (the launcher then starts BeamNG.drive.exe directly instead of through Steam).
"""
import argparse
import json
import os
import re
import subprocess
import sys
import time
import uuid
import zipfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SRC = ROOT / 'mod' / 'earth_rally'
sys.path.insert(0, str(ROOT / 'tools'))
import install  # noqa: E402

GAME_EXES = ('BeamNG.drive.x64.exe', 'BeamNG.drive.exe')
SELFTEST_REL = Path('earthRally') / 'selftest'
VERSION_RE = re.compile(r"M\.VERSION\s*=\s*'([^']+)'")
LOADED_RE = re.compile(r'Earth Rally (\S+) loaded')
PICKUP_S = 420          # the game seen running this long and the request still there: the mod never read it
CLOSE_WAIT_S = 30       # the game's own quit (asked by the mod) before it is closed from here


# ------------------------------------------------------------------------------------------ the installed mod

def repo_files(src=SRC):
    """{relative posix path: bytes} of the mod in this repository."""
    out = {}
    for p in sorted(src.rglob('*')):
        if p.is_file() and '__pycache__' not in p.parts:
            out[p.relative_to(src).as_posix()] = p.read_bytes()
    return out


def mod_version(main_lua_bytes):
    m = VERSION_RE.search(main_lua_bytes.decode('utf-8', 'replace')) if main_lua_bytes else None
    return m.group(1) if m else None


MAIN_REL = 'lua/ge/extensions/earthRally/main.lua'
LAYOUT_REL = 'settings/ui_apps/originalLayouts/default/earthRallyStage.uilayout.json'


def eol(data):
    return data.replace(b'\r\n', b'\n')


def layout_missing(data):
    """The stage apps a layout file's bytes lack (install.STAGE_APPS), or None when it is not valid JSON."""
    try:
        layout = json.loads(data.decode('utf-8'))
    except (ValueError, UnicodeDecodeError):
        return None
    have = {a.get('appName') for a in layout.get('apps', []) if isinstance(a, dict)}
    return [n for n in install.STAGE_APPS if n not in have]


def last_loaded(log_path):
    """The version in the last "Earth Rally X loaded" line of the game's log, or None."""
    try:
        text = Path(log_path).read_text(encoding='utf-8', errors='replace')
    except OSError:
        return None
    found = LOADED_RE.findall(text)
    return found[-1] if found else None


def check_install(user_dir, src=SRC):
    """The installed mod against the repository: [(status, text)] with status 'ok', 'FAIL' or 'note'."""
    user = Path(user_dir)
    out = []
    want = repo_files(src)
    want_version = mod_version(want.get(MAIN_REL))
    mods = user / 'mods'
    unpacked = mods / 'unpacked' / install.NAME
    zips = sorted(p for p in (mods.iterdir() if mods.is_dir() else [])
                  if p.name.lower().startswith('earth_rally') and p.suffix.lower() == '.zip')
    if not user.is_dir():
        return [('FAIL', f'no BeamNG.drive user folder at {user}')]
    if unpacked.is_dir() and zips:
        out.append(('FAIL', f'two copies installed: {unpacked} and {", ".join(z.name for z in zips)} (both would load)'))
    elif len(zips) > 1:
        out.append(('FAIL', 'more than one Earth Rally zip in ' + str(mods) + ': ' + ', '.join(z.name for z in zips)))
    have, where = None, None
    if unpacked.is_dir():
        have = {p.relative_to(unpacked).as_posix(): p.read_bytes() for p in sorted(unpacked.rglob('*')) if p.is_file()}
        where = str(unpacked)
    elif zips:
        with zipfile.ZipFile(zips[-1]) as z:
            have = {n: z.read(n) for n in z.namelist() if not n.endswith('/') and n != 'LICENSE'}
        where = str(zips[-1])
    if have is None:
        out.append(('FAIL', f'Earth Rally is not installed (no {unpacked}, no earth_rally*.zip in {mods})'))
        return out
    out.append(('ok', 'installed at ' + where))
    # the version
    got_version = mod_version(have.get(MAIN_REL))
    out.append(('ok' if got_version == want_version else 'FAIL',
                f'version: installed {got_version}, this repository {want_version}'))
    # every file as in the repository
    missing = sorted(set(want) - set(have))
    extra = sorted(set(have) - set(want))
    # (line endings aside: a checkout with git's autocrlf has CRLF, another LF; the game reads both alike)
    changed = sorted(n for n in set(want) & set(have) if eol(want[n]) != eol(have[n]))
    eol_only = sorted(n for n in set(want) & set(have) if want[n] != have[n] and n not in changed)
    if missing or extra or changed:
        parts = []
        for label, names in (('missing', missing), ('different', changed), ('not in the repository', extra)):
            if names:
                parts.append(f'{len(names)} {label} ({", ".join(names[:4])}{", ..." if len(names) > 4 else ""})')
        out.append(('FAIL', 'files: ' + '; '.join(parts)))
    else:
        out.append(('ok', f'files: all {len(want)} as in the repository'))
    if eol_only:
        out.append(('note', f'{len(eol_only)} file(s) differ only in line endings (CRLF / LF): the same to the game'))
    # the stage layout: every app the HUD needs (1.2.1: the installed layout had none of them)
    lay = have.get(LAYOUT_REL)
    if lay is None:
        out.append(('FAIL', 'stage layout: not installed (' + LAYOUT_REL + ')'))
    else:
        miss = layout_missing(lay)
        if miss is None:
            out.append(('FAIL', 'stage layout: not valid JSON'))
        elif miss:
            out.append(('FAIL', 'stage layout lacks ' + ', '.join(miss) + ': the on-stage HUD would not show'))
        else:
            out.append(('ok', 'stage layout: all ' + str(len(install.STAGE_APPS)) + ' stage apps ('
                        + ', '.join(install.STAGE_APPS) + ')'))
    # a copy of the layout saved from the game's layout editor is used before the mod's
    saved = user / install.USER_LAYOUT_REL / install.OUR_LAYOUT
    if saved.is_file():
        miss = layout_missing(saved.read_bytes())
        if miss:
            out.append(('FAIL', f'{saved} (a saved copy, used before the mod\'s) lacks ' + ', '.join(miss)
                        + ': delete it'))
        else:
            out.append(('note', f'{saved}: a saved copy of the stage layout (complete) is used before the mod\'s'))
    # the game's mod list
    db = mods / 'db.json'
    if db.is_file():
        try:
            entry = json.loads(db.read_text(encoding='utf-8')).get('mods', {}).get(install.NAME)
        except ValueError:
            entry = None
        if entry is not None and entry.get('active') is False:
            out.append(('FAIL', 'switched off in the game\'s mod list (Main menu > Mods: switch Earth Rally on)'))
        elif entry is not None:
            out.append(('ok', 'switched on in the game\'s mod list'))
    loaded = last_loaded(user / 'beamng.log')
    if loaded:
        out.append(('note', f'the game\'s log: Earth Rally {loaded} loaded last time it started'
                    + ('' if loaded == want_version else ' (not this version: restart the game after installing)')))
    return out


def print_checks(results):
    for status, text in results:
        print(f'{status:5} {text}')
    bad = sum(1 for s, _ in results if s == 'FAIL')
    print('install check: ' + ('OK' if not bad else f'{bad} problem(s)'))
    return bad


# ------------------------------------------------------------------------------------------ the game

def running_exes():
    """The game's processes running now (names), Windows only (elsewhere: empty)."""
    if os.name != 'nt':
        return []
    found = []
    for exe in GAME_EXES:
        try:
            r = subprocess.run(['tasklist', '/FI', f'IMAGENAME eq {exe}', '/FO', 'CSV', '/NH'], capture_output=True,
                               text=True, timeout=20)
        except (OSError, subprocess.TimeoutExpired):
            continue
        if f'"{exe}"' in (r.stdout or ''):
            found.append(exe)
    return found


def close_game(wait_s=20):
    """Close the game: asked first (taskkill without /F: its window is told to close), then forced."""
    for force in (False, True):
        for exe in GAME_EXES:
            subprocess.run(['taskkill', '/IM', exe, '/T'] + (['/F'] if force else []), capture_output=True)
        t0 = time.time()
        while time.time() - t0 < wait_s:
            if not running_exes():
                return True
            time.sleep(1)
    return not running_exes()


def find_earth(start=ROOT):
    """BeamNG.Earth's source folder (with launcher.py): next to this repository or above it, else None."""
    env = os.environ.get('BEAMNG_EARTH_DIR')
    if env and (Path(env) / 'launcher.py').is_file():
        return Path(env)
    for base in [start, *start.parents]:
        for cand in (base / 'beamng.earth', base):
            if (cand / 'launcher.py').is_file() and (cand / 'mod' / 'beamng_earth').is_dir():
                return cand
    return None


def write_request(user_dir, event, stage, token, quit_after, budget_s):
    d = Path(user_dir) / SELFTEST_REL
    d.mkdir(parents=True, exist_ok=True)
    req = {'event': event, 'stage': stage, 'token': token, 'quit': quit_after, 'loadLevel': True,
           'budgetS': budget_s}
    (d / 'request.json').write_text(json.dumps(req, indent=1), encoding='utf-8')
    return d / 'request.json'


def find_report(user_dir, token):
    """The report with this token (the newest if several), or None."""
    d = Path(user_dir) / SELFTEST_REL
    for p in sorted(d.glob('report-*.json'), key=lambda q: q.stat().st_mtime, reverse=True) if d.is_dir() else []:
        try:
            rep = json.loads(p.read_text(encoding='utf-8'))
        except (OSError, ValueError):
            continue
        if rep.get('token') == token:
            return p, rep
    return None


def print_report(rep, path=None):
    print()
    print(f"Earth Rally {rep.get('version')} self-test, {rep.get('event')} / {rep.get('stage')}: "
          f"{'PASS' if rep.get('ok') else 'FAIL'} ({rep.get('passed')} passed, {rep.get('failed')} failed, "
          f"{rep.get('elapsedS')} s)")
    if rep.get('abortReason'):
        print('  stopped: ' + str(rep['abortReason']))
    for c in rep.get('checks', []):
        print(f"  {'ok  ' if c.get('ok') else 'FAIL'} {c.get('name')}" + (f" ({c['detail']})" if c.get('detail') else ''))
    if rep.get('timings'):
        print('  phases (s): ' + ', '.join(f'{k} {v}' for k, v in rep['timings'].items()))
    for e in rep.get('errors') or []:
        print(f"  error logged at {e.get('t')} s [{e.get('tag')}]: {e.get('msg')}")
    if path:
        print('  report: ' + str(path))


class LogTail:
    """New lines of the game's log (it is written afresh at each start: read again from the top when it shrinks)."""

    def __init__(self, path):
        self.path, self.pos = Path(path), 0
        try:
            self.pos = self.path.stat().st_size
        except OSError:
            pass

    def lines(self):
        try:
            size = self.path.stat().st_size
        except OSError:
            return []
        if size < self.pos:
            self.pos = 0
        if size == self.pos:
            return []
        with open(self.path, 'rb') as f:
            f.seek(self.pos)
            data = f.read()
        cut = data.rfind(b'\n') + 1
        self.pos += cut
        return data[:cut].decode('utf-8', 'replace').splitlines()


UNSTABLE_NOTE = (
    'NOTE: the self-test is UNSTABLE. It cannot check the co-driver yet (1.4.0), so it exits 1 on every run.\n'
    '      Read the checks below; do not take the exit code as a verdict on the build.')


def run(args):
    print(UNSTABLE_NOTE)
    user = Path(args.user_dir)
    exes = running_exes()
    if exes:
        print('BeamNG.drive is running (' + ', '.join(exes) + '): close it first. The self-test installs the mod and '
              'starts the game itself. (--check-install works while it runs.)')
        return 2
    earth = Path(args.earth) if args.earth else find_earth()
    if not earth or not (earth / 'launcher.py').is_file():
        print('BeamNG.Earth\'s source folder (with launcher.py) not found: give it with --earth')
        return 2
    if not args.no_install:
        r = subprocess.run([sys.executable, str(ROOT / 'tools' / 'install.py'), '--user-dir', str(user)])
        if r.returncode != 0:
            print('install failed')
            return 1
    if print_checks(check_install(user)):
        print('The installed mod is not this repository\'s: not starting the game.')
        return 1
    token = uuid.uuid4().hex[:12]
    budget = args.budget
    request = write_request(user, args.event, args.stage, token, not args.keep_open, budget)
    py = earth / '.venv' / ('Scripts/python.exe' if os.name == 'nt' else 'bin/python')
    cmd = [str(py if py.is_file() else sys.executable), 'launcher.py', '--no-beammp', '--no-update-check',
           '--gfx', args.gfx]
    print('starting: ' + ' '.join(cmd) + f'  (in {earth})')
    launcher = subprocess.Popen(cmd, cwd=str(earth),
                                creationflags=getattr(subprocess, 'CREATE_NEW_CONSOLE', 0) if os.name == 'nt' else 0)
    tail = LogTail(user / 'beamng.log')
    t0, seen_at, found, why = time.time(), None, None, None
    try:
        while True:
            for line in tail.lines():
                if 'self-test' in line or ('earthRally' in line and ('run: ' in line or 'loaded' in line)):
                    print('  game: ' + line.split('|')[-1].strip()[:200])
            found = find_report(user, token)
            if found:
                break
            up = bool(running_exes())
            if up and seen_at is None:
                seen_at = time.time()
                print(f'  the game is up ({seen_at - t0:.0f} s)')
            if seen_at is not None and not up:
                why = 'the game closed before the self-test reported (crashed?)'
                break
            if seen_at is not None and request.exists() and time.time() - seen_at > PICKUP_S:
                why = (f'the mod never picked up the request in {PICKUP_S} s (Earth Rally not loaded? switched off in '
                       'the mod list?)')
                break
            if time.time() - t0 > args.timeout:
                why = f'no report in {args.timeout} s'
                break
            if launcher.poll() is not None and seen_at is None and time.time() - t0 > 120:
                why = f'BeamNG.Earth\'s launcher ended (code {launcher.returncode}) without starting the game'
                break
            time.sleep(2)
    finally:
        # (never left behind: the next normal start would run a test)
        try:
            request.unlink()
        except OSError:
            pass
        if not args.keep_open:
            t1 = time.time()
            while running_exes() and time.time() - t1 < CLOSE_WAIT_S:
                time.sleep(1)
            if running_exes():
                close_game()
            try:
                launcher.wait(timeout=30)
            except subprocess.TimeoutExpired:
                subprocess.run(['taskkill', '/PID', str(launcher.pid), '/T', '/F'], capture_output=True)
    if not found:
        print('\nself-test: FAIL: ' + str(why))
        return 1
    path, rep = found
    print_report(rep, path)
    print(UNSTABLE_NOTE)
    return 0 if rep.get('ok') else 1


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument('--check-install', action='store_true', help='only check the installed mod (read-only)')
    ap.add_argument('--user-dir', default=install.default_user_dir(), help='the BeamNG.drive user folder (…/current)')
    ap.add_argument('--event', default='otr24', help='the rally (its id in earthRally/events)')
    ap.add_argument('--stage', default='maryhill-up', help='the stage id')
    ap.add_argument('--earth', help='BeamNG.Earth\'s source folder (default: found next to this repository)')
    ap.add_argument('--gfx', default='dx11', choices=['dx11', 'dx12', 'vk'], help='the renderer (skips its dialog)')
    ap.add_argument('--budget', type=int, default=1500, help='the in-game test\'s own time budget (s)')
    ap.add_argument('--timeout', type=int, default=2100, help='give up waiting for the report after this long (s)')
    ap.add_argument('--no-install', action='store_true', help='test the mod as installed (still checked first)')
    ap.add_argument('--keep-open', action='store_true', help='leave the game open after the test')
    ap.add_argument('--src', help='--check-install against this mod folder instead of this repository\'s '
                    '(e.g. another checkout\'s mod/earth_rally)')
    args = ap.parse_args(argv)
    if args.check_install:
        return 1 if print_checks(check_install(args.user_dir, Path(args.src) if args.src else SRC)) else 0
    return run(args)


if __name__ == '__main__':
    sys.exit(main())
