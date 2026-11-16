#!/usr/bin/env python3
"""Publish an Earth Rally release from the main checkout: the last steps of the /release skill, in one command.

    python tools/release.py 1.6.1-alpha --check     checks only, prints the release body, changes nothing
    python tools/release.py 1.6.1-alpha             checks, then commit, tag, zip, push, GitHub pre-release

Run by the maintainer session only (the guard hook blocks it elsewhere), in the repo root, on `main`, after the
CHANGELOG entry, README and `M.VERSION` edits are made and left uncommitted. It refuses, changing nothing, unless:

- the version is X.Y.Z-alpha, newer than the latest v* tag, and not tagged yet;
- local main is origin/main (after a fetch), with no untracked files staged by accident (only tracked edits commit);
- the top CHANGELOG entry is `## X.Y.Z-alpha: <name> (<date>)` with a `Works with` line, within the word limit
  (patch 150, minor 400, counted like `wc -w`);
- `M.VERSION` in the mod is the new version, and README.md names no version;
- the DeRamp BeamNG.Earth fork's latest release has a Windows installer (.exe).

Commit `X.Y.Z-alpha: <name>`, annotated tag `vX.Y.Z-alpha`, then `tools/package.py`, then one atomic push of main
and the tag, then `gh release create` with the CHANGELOG entry plus the install block from docs/writing-standard.md
and the zip as the only asset. If the push or the release fails, it says what is done and what is left.
"""
import os
import re
import shutil
import subprocess
import sys
import tempfile

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
REPO = 'DeRamp/BeamNG.Earth.Rally'
FORK = 'DeRamp/BeamNG.Earth'
MAIN_LUA = os.path.join(ROOT, 'mod', 'earth_rally', 'lua', 'ge', 'extensions', 'earthRally', 'main.lua')
VERSION_RE = re.compile(r'^(\d+)\.(\d+)\.(\d+)-alpha$')
INSTALL = """---
**Install:**
1. Install BeamNG.Earth from [the DeRamp fork](https://github.com/DeRamp/BeamNG.Earth/releases), with its installer, as you
   would the official one.
2. Download `earth_rally-{v}.zip` below and put it, still zipped, in
   `%LOCALAPPDATA%\\BeamNG\\BeamNG.drive\\current\\mods\\`. Delete the old Earth Rally zip first.

[README](https://github.com/DeRamp/BeamNG.Earth.Rally/blob/main/README.md) · [Player guide](https://github.com/DeRamp/BeamNG.Earth.Rally/blob/main/docs/guide.md) · [Full changelog](https://github.com/DeRamp/BeamNG.Earth.Rally/blob/main/CHANGELOG.md)
"""


class Refuse(Exception):
    pass


def run(*args, check=True):
    p = subprocess.run(list(args), cwd=ROOT, capture_output=True, text=True, encoding='utf-8')
    if check and p.returncode != 0:
        raise Refuse(f'`{" ".join(args)}` failed: {(p.stderr or p.stdout).strip()}')
    return p.stdout.strip()


def gh_exe():
    return shutil.which('gh') or r'C:\Program Files\GitHub CLI\gh.exe'


def read(path):
    with open(path, encoding='utf-8') as f:
        return f.read()


def vkey(v):
    m = VERSION_RE.match(v)
    return tuple(int(x) for x in m.groups()) if m else None


def changelog_entry(version):
    text = read(os.path.join(ROOT, 'CHANGELOG.md'))
    heads = list(re.finditer(r'^## .*$', text, re.M))
    if not heads:
        raise Refuse('CHANGELOG.md has no entries')
    m = re.match(r'^## (\S+): (.+) \((\d{4}-\d{2}-\d{2})\)$', heads[0].group(0))
    if not m or m.group(1) != version:
        raise Refuse(f'top CHANGELOG entry is `{heads[0].group(0)}`, want `## {version}: <name> (<date>)`')
    end = heads[1].start() if len(heads) > 1 else len(text)
    entry = text[heads[0].start():end].strip() + '\n'
    if 'Works with' not in entry:
        raise Refuse('the CHANGELOG entry has no `Works with` line')
    return m.group(2), entry


def checks(version):
    key = vkey(version)
    if not key:
        raise Refuse(f'version `{version}` is not X.Y.Z-alpha')
    if run('git', 'symbolic-ref', '--short', '-q', 'HEAD', check=False) != 'main':
        raise Refuse('not on main')
    run('git', 'fetch', '-q', '--tags', 'origin')
    if run('git', 'rev-parse', 'HEAD') != run('git', 'rev-parse', 'origin/main'):
        raise Refuse('local main is not origin/main: `git pull --ff-only` first')
    if run('git', 'diff', '--cached', '--name-only'):
        raise Refuse('something is staged already; leave the edits unstaged, this script stages tracked files only')
    tags = [t for t in run('git', 'tag', '--list', 'v*').split() if vkey(t[1:])]
    if 'v' + version in run('git', 'tag', '--list').split():
        raise Refuse(f'tag v{version} exists already')
    latest = max(tags, key=lambda t: vkey(t[1:])) if tags else None
    if latest and vkey(latest[1:]) >= key:
        raise Refuse(f'{version} is not newer than {latest}')
    name, entry = changelog_entry(version)
    limit = 150 if key[2] else 400
    words = len(entry.split())
    if words > limit:
        raise Refuse(f'CHANGELOG entry is {words} words, limit {limit}')
    if f"M.VERSION = '{version}'" not in read(MAIN_LUA):
        raise Refuse(f"M.VERSION in main.lua is not '{version}'")
    readme = read(os.path.join(ROOT, 'README.md'))
    found = re.search(r'\b\d+\.\d+\.\d+-alpha\b', readme)
    if found:
        raise Refuse(f'README.md names a version ({found.group(0)}); it says alpha only')
    assets = run(gh_exe(), 'release', 'view', '-R', FORK, '--json', 'assets', '-q', '.assets[].name')
    if not any(a.lower().endswith('.exe') for a in assets.split()):
        raise Refuse(f'the {FORK} latest release has no .exe installer')
    changed = run('git', 'diff', '--name-only')
    if not changed:
        raise Refuse('no edits to commit (CHANGELOG, README, M.VERSION)')
    body = entry.split('\n', 1)[1].strip() + '\n\n' + INSTALL.format(v=version)
    return name, body, changed.split(), words, limit


def publish(version, name, body):
    done = []
    try:
        run('git', 'commit', '-q', '-a', '-m', f'{version}: {name}')
        done.append('commit ' + run('git', 'rev-parse', '--short', 'HEAD'))
        run('git', 'tag', '-a', 'v' + version, '-m', f'Earth Rally {version}: {name}')
        done.append('tag v' + version)
        run(sys.executable, os.path.join('tools', 'package.py'), version)
        zip_path = os.path.join('dist', f'earth_rally-{version}.zip')
        done.append('zip ' + zip_path)
        run('git', 'push', '--atomic', 'origin', 'main', f'refs/tags/v{version}')
        done.append('pushed main and tag')
        with tempfile.NamedTemporaryFile('w', suffix='.md', delete=False, encoding='utf-8') as f:
            f.write(body)
        try:
            url = run(gh_exe(), 'release', 'create', 'v' + version, zip_path, '-R', REPO, '--verify-tag',
                      '--prerelease', '--title', f'Earth Rally {version}: {name}', '--notes-file', f.name)
        finally:
            os.unlink(f.name)
        return url
    except Refuse as e:
        raise Refuse(f'{e}\nDone so far: {", ".join(done) or "nothing"}. Finish the rest by hand, do not re-run.')


def main():
    args = sys.argv[1:]
    dry = '--check' in args
    args = [a for a in args if a != '--check']
    if len(args) != 1:
        print(__doc__)
        return 1
    version = args[0]
    try:
        name, body, changed, words, limit = checks(version)
        print(f'release.py: {version} "{name}", CHANGELOG {words}/{limit} words, commits: {", ".join(changed)}')
        if dry:
            print('--- release body ---\n' + body)
            return 0
        print('release.py: published ' + publish(version, name, body))
        return 0
    except Refuse as e:
        print(f'release.py: refused: {e}', file=sys.stderr)
        return 1


if __name__ == '__main__':
    sys.exit(main())
