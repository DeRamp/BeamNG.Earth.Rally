#!/usr/bin/env python3
"""Publish an Earth Rally release from a commit already on origin/main: tag it, zip it from the tag, publish it.

    python tools/release.py 1.6.1-alpha <commit> --check     checks only, prints the release body, changes nothing
    python tools/release.py 1.6.1-alpha <commit>             checks, then tag, zip, push the tag, GitHub pre-release

<commit> is the merge commit of the release PR (default: origin/main). The release text and version bump are part of
that PR, so the maintainer's review saw them; this script commits nothing and never pushes `main`. It reads every
file from the commit, not the working tree, so it runs from any checkout and a dirty checkout cannot leak into it.
Run by the maintainer session only (the guard hook blocks it elsewhere). It refuses, changing nothing, unless:

- the version is X.Y.Z-alpha and the next patch, minor or major after origin's latest v* tag;
- the commit is on origin/main (after a fetch), and the tag is on neither origin nor here, or on that commit;
- the commit's top CHANGELOG entry is `## X.Y.Z-alpha: <name> (<date>)` with a `Works with` line, within the word
  limit (patch 150, minor 400, counted like `wc -w`);
- the commit's `M.VERSION` is the version, and its README.md names no version;
- the DeRamp BeamNG.Earth fork's latest release has a Windows installer (.exe).

Each step is skipped when already done (tag on that commit, tag on origin, release on GitHub), so if a step fails,
running the same command again is the recovery.
"""
import io
import os
import re
import shutil
import subprocess
import sys
import tarfile
import tempfile
import zipfile

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
REPO = 'DeRamp/BeamNG.Earth.Rally'
FORK = 'DeRamp/BeamNG.Earth'
MAIN_LUA = 'mod/earth_rally/lua/ge/extensions/earthRally/main.lua'
MOD = 'mod/earth_rally'
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


def run(*args, check=True, binary=False):
    if not shutil.which(args[0]) and not os.path.exists(args[0]):
        raise Refuse(f'{args[0]} not found')
    p = subprocess.run(list(args), cwd=ROOT, capture_output=True, **({} if binary else {'text': True, 'encoding': 'utf-8'}))
    if check and p.returncode != 0:
        err = p.stderr.decode('utf-8', 'replace') if binary else p.stderr or p.stdout
        raise Refuse(f'`{" ".join(args)}` failed: {err.strip()}')
    return p if binary else p.stdout.strip()


def ok(*args):
    return subprocess.run(list(args), cwd=ROOT, capture_output=True).returncode == 0


def remote_tags():
    """origin's tags, {name: commit sha}. origin is the truth: local tags can be stale or differ."""
    tags = {}
    for line in run('git', 'ls-remote', '--tags', 'origin').splitlines():
        sha, ref = line.split('\t')
        name = ref.removeprefix('refs/tags/')
        if name.endswith('^{}'):
            tags[name[:-3]] = sha  # an annotated tag's commit
        else:
            tags.setdefault(name, sha)
    return tags


def gh_exe():
    return shutil.which('gh') or r'C:\Program Files\GitHub CLI\gh.exe'


def show(commit, path):
    return run('git', 'show', f'{commit}:{path}').replace('\r\n', '\n')


def vkey(v):
    m = VERSION_RE.match(v)
    return tuple(int(x) for x in m.groups()) if m else None


def next_versions(latest):
    x, y, z = latest
    return {(x, y, z + 1), (x, y + 1, 0), (x + 1, 0, 0)}


def changelog_entry(text, version):
    heads = list(re.finditer(r'^## .*$', text, re.M))
    if not heads:
        raise Refuse('CHANGELOG.md has no entries')
    m = re.match(r'^## (\S+): (.+) \((\d{4}-\d{2}-\d{2})\)$', heads[0].group(0).strip())
    if not m or m.group(1) != version:
        raise Refuse(f'top CHANGELOG entry is `{heads[0].group(0)}`, want `## {version}: <name> (<date>)`')
    end = heads[1].start() if len(heads) > 1 else len(text)
    entry = text[heads[0].start():end].strip() + '\n'
    if 'Works with' not in entry:
        raise Refuse('the CHANGELOG entry has no `Works with` line')
    return m.group(2), entry


def checks(version, commit):
    key = vkey(version)
    if not key:
        raise Refuse(f'version `{version}` is not X.Y.Z-alpha')
    run('git', 'fetch', '-q', 'origin', 'main')
    remote = remote_tags()
    sha = run('git', 'rev-parse', '--verify', commit + '^{commit}')
    if not ok('git', 'merge-base', '--is-ancestor', sha, 'origin/main'):
        raise Refuse(f'{commit} ({sha[:7]}) is not on origin/main')
    tag = 'v' + version
    local = run('git', 'rev-parse', '-q', '--verify', tag + '^{commit}', check=False)
    for where, tagged in (('origin', remote.get(tag)), ('locally', local)):
        if tagged and tagged != sha:
            raise Refuse(f'{tag} exists {where} already, on {tagged[:7]}, not {sha[:7]}')
    if not (local or remote.get(tag)):  # a resumed run has its own tag already; else it must be the next version
        latest = max((vkey(t[1:]) for t in remote if vkey(t[1:])), default=None)
        if latest and key not in next_versions(latest):
            want = ', '.join(f'{a}.{b}.{c}-alpha' for a, b, c in sorted(next_versions(latest)))
            raise Refuse(f'{version} is not the next version after the latest tag (want one of {want})')
    name, entry = changelog_entry(show(sha, 'CHANGELOG.md'), version)
    limit = 150 if key[2] else 400
    words = len(entry.split())
    if words > limit:
        raise Refuse(f'CHANGELOG entry is {words} words, limit {limit}')
    if f"M.VERSION = '{version}'" not in show(sha, MAIN_LUA):
        raise Refuse(f"M.VERSION in {MAIN_LUA} at {sha[:7]} is not '{version}'")
    found = re.search(r'\b\d+\.\d+\.\d+-alpha\b', show(sha, 'README.md'))
    if found:
        raise Refuse(f'README.md names a version ({found.group(0)}); it says alpha only')
    assets = run(gh_exe(), 'release', 'view', '-R', FORK, '--json', 'assets', '-q', '.assets[].name')
    if not any(a.lower().endswith('.exe') for a in assets.split()):
        raise Refuse(f'the {FORK} latest release has no .exe installer')
    body = entry.split('\n', 1)[1].strip() + '\n\n' + INSTALL.format(v=version)
    return sha, name, body, words, limit


def build_zip(tag, version):
    """The tool/package.py layout (the mod's folders at the top, plus LICENSE), from the tag's tree only."""
    tar = run('git', 'archive', '--format=tar', tag, MOD, 'LICENSE', binary=True).stdout
    out = os.path.join(ROOT, 'dist', f'earth_rally-{version}.zip')
    os.makedirs(os.path.dirname(out), exist_ok=True)
    n = 0
    with tarfile.open(fileobj=io.BytesIO(tar)) as t, zipfile.ZipFile(out, 'w', zipfile.ZIP_DEFLATED) as z:
        for m in sorted((m for m in t.getmembers() if m.isfile()), key=lambda m: m.name):
            rel = m.name[len(MOD) + 1:] if m.name.startswith(MOD + '/') else m.name
            z.writestr(rel, t.extractfile(m).read())
            n += 1
    return out, n


def publish(version, sha, name, body):
    tag = 'v' + version
    if not run('git', 'rev-parse', '-q', '--verify', tag, check=False):
        run('git', 'tag', '-a', tag, sha, '-m', f'Earth Rally {version}: {name}')
        print(f'release.py: tagged {tag} on {sha[:7]}')
    if not run('git', 'ls-remote', '--tags', 'origin', f'refs/tags/{tag}'):
        run('git', 'push', 'origin', f'refs/tags/{tag}')
        print(f'release.py: pushed {tag}')
    if ok(gh_exe(), 'release', 'view', tag, '-R', REPO):
        return run(gh_exe(), 'release', 'view', tag, '-R', REPO, '--json', 'url', '-q', '.url') + ' (already published)'
    zip_path, n = build_zip(tag, version)
    print(f'release.py: {zip_path}: {n} files')
    with tempfile.NamedTemporaryFile('w', suffix='.md', delete=False, encoding='utf-8') as f:
        f.write(body)
    try:
        return run(gh_exe(), 'release', 'create', tag, zip_path, '-R', REPO, '--verify-tag', '--prerelease',
                   '--title', f'Earth Rally {version}: {name}', '--notes-file', f.name)
    finally:
        os.unlink(f.name)


def main():
    sys.stdout.reconfigure(encoding='utf-8')
    sys.stderr.reconfigure(encoding='utf-8')
    args = sys.argv[1:]
    dry = '--check' in args
    args = [a for a in args if a != '--check']
    if len(args) not in (1, 2):
        print(__doc__)
        return 1
    version, commit = args[0], (args[1] if len(args) > 1 else 'origin/main')
    try:
        sha, name, body, words, limit = checks(version, commit)
        print(f'release.py: {version} "{name}" on {sha[:7]}, CHANGELOG {words}/{limit} words')
        if dry:
            print('--- release body ---\n' + body)
            return 0
        print('release.py: published ' + publish(version, sha, name, body))
        return 0
    except Refuse as e:
        print(f'release.py: refused: {e}\nNothing after the last "release.py:" line was done; fix it and run the '
              f'same command again.', file=sys.stderr)
        return 1


if __name__ == '__main__':
    sys.exit(main())
