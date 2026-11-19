#!/usr/bin/env python3
"""Publish an Earth Rally release from a commit already on origin/main: tag it, zip it from the tag, publish it.

    python tools/release.py 1.8.0-alpha <commit> --check       checks only, prints the release body, changes nothing
    python tools/release.py 1.8.0-alpha <commit>               checks, then tag, zip, push the tag, GitHub release
    python tools/release.py 1.8.0-alpha [<ref>] --build-only   only the zip, from <ref> (default HEAD): no checks,
                                                               no tag, nothing pushed (to look at it before a release)
    --pack PATH       the ARA 2026 season folder put in the zip (default: the Rally Files folder on the owner's PC)

<commit> is the commit on main that carries the release text and version bump (default: origin/main). This script
commits nothing and never pushes `main`. It reads every
file from the commit, not the working tree, so it runs from any checkout and a dirty checkout cannot leak into it.
The one exception is the ARA 2026 season (organisers' material, never in git): it is read from --pack and goes into
the zip as the folder pack earthRally/import/ARA Nationals 2026/, so the mod's one release asset carries it.
Releases are full releases, not pre-releases: BeamNG.Earth's Add-ons page installs only the newest full release.
It refuses, changing nothing, unless:

- the version is X.Y.Z-alpha and the next patch, minor or major after origin's latest v* tag;
- the commit is on origin/main (after a fetch), and the tag is on neither origin nor here, or on that commit;
- the commit's top CHANGELOG entry is `## X.Y.Z-alpha: <name> (<date>)` with a `Works with` line, within the word
  limit (patch 150, minor 400, counted like `wc -w`);
- the commit's `M.VERSION` is the version, and its README.md names no version;
- the --pack folder is there, with its season.json at its top.

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
MAIN_LUA = 'mod/earth_rally/lua/ge/extensions/earthRally/main.lua'
MOD = 'mod/earth_rally'
VERSION_RE = re.compile(r'^(\d+)\.(\d+)\.(\d+)-alpha$')
# The ARA 2026 season, a folder pack, and where it goes in the zip (pack.lua finds it under /earthRally/import/).
PACK_DEFAULT = os.path.join(os.path.expanduser('~'), 'Documents', 'Claude', 'Rally Files', 'ARA Nationals 2026')
PACK_IN_ZIP = 'earthRally/import/ARA Nationals 2026/'
# Written into the pack folder in the zip: the season is the organisers' material, not under the mod's licence.
PACK_NOTICE = ('# ARA Nationals 2026\n\n'
               'The route books, maps, results and pictures in this folder belong to the event organisers and the\n'
               'American Rally Association (ARA). They come with Earth Rally for convenience and are not under\n'
               "Earth Rally's MIT licence.\n")
INSTALL = """---
**Install:**
1. Install [BeamNG.Earth](https://github.com/TecnaGamer/BeamNG.Earth/releases) 1.10 or newer with its installer.
2. In BeamNG.Earth, open **Add-ons** > **Add from GitHub**, paste `DeRamp/BeamNG.Earth.Rally` and press **Install**.
3. Paste `DeRamp/earth-rally-leaderboards` the same way, press **Install**, then **Start** (tick
   **Start with BeamNG.Earth**).
4. In game: **Freeroam > BeamNG.Earth**, then **Ctrl + Alt + K** for the menu. The ARA 2026 season is included.

No **Add from GitHub**? Put `earth_rally-{v}.zip` from below, still zipped, in `mods`.

**Moving from the zip install:** delete `earth_rally-*.zip` from `%LOCALAPPDATA%\\BeamNG\\BeamNG.drive\\current\\mods\\`.

[README](https://github.com/DeRamp/BeamNG.Earth.Rally/blob/main/README.md) · [Player guide](https://github.com/DeRamp/BeamNG.Earth.Rally/blob/main/docs/guide.md) · [Full changelog](https://github.com/DeRamp/BeamNG.Earth.Rally/blob/main/CHANGELOG.md)
"""


class Refuse(Exception):
    pass


def run(*args, check=True, binary=False):
    if not shutil.which(args[0]) and not os.path.exists(args[0]):
        raise Refuse(f'{args[0]} not found')
    p = subprocess.run(list(args), cwd=ROOT, capture_output=True, **({} if binary else {'text': True, 'encoding': 'utf-8', 'errors': 'replace'}))
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


def pack_files(pack):
    """The ARA season folder's files, [(path on disk, path in the zip)], sorted. Refuses when it is not there."""
    if not os.path.isfile(os.path.join(pack, 'season.json')):
        raise Refuse(f'the ARA 2026 pack is not at {pack} (no season.json there): give its folder with --pack PATH')
    out = []
    for base, dirs, files in os.walk(pack):
        dirs.sort()
        for f in sorted(files):
            if f.startswith('.') or f.lower() in ('thumbs.db', 'desktop.ini'):
                continue
            full = os.path.join(base, f)
            out.append((full, PACK_IN_ZIP + os.path.relpath(full, pack).replace(os.sep, '/')))
    return out


def checks(version, commit, pack):
    key = vkey(version)
    if not key:
        raise Refuse(f'version `{version}` is not X.Y.Z-alpha')
    pack_files(pack)
    run('git', 'fetch', '-q', 'origin', 'main')
    remote = remote_tags()
    sha = run('git', 'rev-parse', '--verify', commit + '^{commit}')
    # main's own line (merge commits), not a commit of some branch that main merged
    if sha not in run('git', 'rev-list', '--first-parent', 'origin/main').split():
        raise Refuse(f'{commit} ({sha[:7]}) is not on the first-parent line of origin/main')
    tag = 'v' + version
    local = run('git', 'rev-parse', '-q', '--verify', tag + '^{commit}', check=False)
    for where, tagged in (('origin', remote.get(tag)), ('locally', local)):
        if tagged and tagged != sha:
            raise Refuse(f'{tag} exists {where} already, on {tagged[:7]}, not {sha[:7]}')
    released = {t: c for t, c in remote.items() if vkey(t[1:]) and t != tag}
    if released:
        latest = max(released, key=lambda t: vkey(t[1:]))
        if not ok('git', 'merge-base', '--is-ancestor', released[latest], sha):
            raise Refuse(f'{sha[:7]} does not descend from the latest release {latest}')
        if not remote.get(tag) and key not in next_versions(vkey(latest[1:])):  # origin's tag means a resumed run
            want = ', '.join(f'{a}.{b}.{c}-alpha' for a, b, c in sorted(next_versions(vkey(latest[1:]))))
            raise Refuse(f'{version} is not the next version after {latest} (want one of {want})')
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
    body = entry.split('\n', 1)[1].strip() + '\n\n' + INSTALL.format(v=version)
    return sha, name, body, words, limit


def build_zip(tag, version, pack):
    """The tool/package.py layout (the mod's folders at the top, plus LICENSE), from the tag's tree only, plus the
    ARA 2026 season from pack (a folder on this PC) under PACK_IN_ZIP. The one release asset."""
    files = pack_files(pack)
    tar = run('git', 'archive', '--format=tar', tag, MOD, 'LICENSE', binary=True).stdout
    out = os.path.join(ROOT, 'dist', f'earth_rally-{version}.zip')
    os.makedirs(os.path.dirname(out), exist_ok=True)
    n, pack_bytes = 0, 0
    with tarfile.open(fileobj=io.BytesIO(tar)) as t, zipfile.ZipFile(out, 'w', zipfile.ZIP_DEFLATED) as z:
        for m in sorted((m for m in t.getmembers() if m.isfile()), key=lambda m: m.name):
            rel = m.name[len(MOD) + 1:] if m.name.startswith(MOD + '/') else m.name
            if rel.startswith(PACK_IN_ZIP):
                raise Refuse(f'{tag} has {rel} in git: rally data is never in git')
            z.writestr(rel, t.extractfile(m).read())
            n += 1
        for full, rel in files:
            z.write(full, rel)
            pack_bytes += os.path.getsize(full)
        if PACK_IN_ZIP + 'NOTICE.md' not in {rel for _, rel in files}:
            z.writestr(PACK_IN_ZIP + 'NOTICE.md', PACK_NOTICE)
    print(f'release.py: {out}: {n} mod files + ARA 2026 pack {len(files)} files, {pack_bytes / 1e6:.1f} MB '
          f'(zip {os.path.getsize(out) / 1e6:.1f} MB)')
    return out, n + len(files)


def publish(version, sha, name, body, pack):
    tag = 'v' + version
    on_origin = bool(run('git', 'ls-remote', '--tags', 'origin', f'refs/tags/{tag}'))
    if not run('git', 'rev-parse', '-q', '--verify', tag, check=False):
        if on_origin:  # an earlier run pushed it: take origin's tag object, do not make a second one
            run('git', 'fetch', '-q', 'origin', f'refs/tags/{tag}:refs/tags/{tag}')
        else:
            run('git', 'tag', '-a', tag, sha, '-m', f'Earth Rally {version}: {name}')
            print(f'release.py: tagged {tag} on {sha[:7]}')
    if not on_origin:
        run('git', 'push', 'origin', f'refs/tags/{tag}')
        print(f'release.py: pushed {tag}')
    zip_name = f'earth_rally-{version}.zip'
    # Looked up in the full list, which holds drafts too: gh makes a draft, uploads, then publishes, so a failed
    # or killed run can leave a draft without the zip.
    found = run(gh_exe(), 'api', f'repos/{REPO}/releases', '--paginate', '-q',
                f'.[] | select(.tag_name == "{tag}") | [.id, .draft, .prerelease, .html_url, '
                f'([.assets[].name] | join(","))] | map(tostring) | join(" ")')
    if found:
        rid, draft, pre, url, *assets = found.splitlines()[0].split(' ')
        assets = ','.join(assets).split(',')
        if draft == 'false' and pre == 'false' and zip_name in assets:
            return url + ' (already published)'
        if zip_name not in assets:
            zip_path, n = build_zip(tag, version, pack)
            run(gh_exe(), 'release', 'upload', tag, zip_path, '-R', REPO, '--clobber')
        run(gh_exe(), 'api', '-X', 'PATCH', f'repos/{REPO}/releases/{rid}', '-F', 'draft=false', '-F', 'prerelease=false')
        return url + ' (finished an incomplete release)'
    zip_path, n = build_zip(tag, version, pack)
    with tempfile.NamedTemporaryFile('w', suffix='.md', delete=False, encoding='utf-8') as f:
        f.write(body)
    try:
        return run(gh_exe(), 'release', 'create', tag, zip_path, '-R', REPO, '--verify-tag',
                   '--title', f'Earth Rally {version}: {name}', '--notes-file', f.name)
    finally:
        os.unlink(f.name)


def main():
    sys.stdout.reconfigure(encoding='utf-8')
    sys.stderr.reconfigure(encoding='utf-8')
    args = sys.argv[1:]
    dry = '--check' in args
    build_only = '--build-only' in args
    pack = PACK_DEFAULT
    if '--pack' in args:
        i = args.index('--pack')
        if i + 1 >= len(args):
            print(__doc__)
            return 1
        pack = args[i + 1]
        del args[i:i + 2]
    args = [a for a in args if a not in ('--check', '--build-only')]
    if len(args) not in (1, 2):
        print(__doc__)
        return 1
    pack = os.path.abspath(pack)
    try:
        if build_only:     # (the zip only, from a ref: no checks, no tag, nothing pushed or published)
            ref = args[1] if len(args) > 1 else 'HEAD'
            if not vkey(args[0]):
                raise Refuse(f'version `{args[0]}` is not X.Y.Z-alpha')
            build_zip(run('git', 'rev-parse', '--verify', ref + '^{commit}'), args[0], pack)
            return 0
        version, commit = args[0], (args[1] if len(args) > 1 else 'origin/main')
        sha, name, body, words, limit = checks(version, commit, pack)
        print(f'release.py: {version} "{name}" on {sha[:7]}, CHANGELOG {words}/{limit} words')
        if dry:
            print('--- release body ---\n' + body)
            return 0
        print('release.py: published ' + publish(version, sha, name, body, pack))
        return 0
    except Refuse as e:
        print(f'release.py: refused: {e}\nSteps printed above as "release.py:" are done (a failed `gh release create` '
              f'may also have left a draft release). Fix the cause and run the same command again: it carries on '
              f'from what is done.', file=sys.stderr)
        return 1


if __name__ == '__main__':
    sys.exit(main())
