#!/usr/bin/env python3
"""Publish docs/wiki/*.md and docs/media/*.jpg to the GitHub wiki (the pages' images load from its images/ folder).

    python tools/publish_wiki.py            # clone, copy, commit, push
    python tools/publish_wiki.py --dry-run  # clone, copy, show what would change

The wiki's git repository exists only after its first page has been made on the web: open
https://github.com/DeRamp/BeamNG.Earth.Rally/wiki and press "Create the first page" (save it as is) once.
docs/wiki/ is the source; edits made on the web are overwritten by the next publish.
"""
import argparse
import glob
import os
import shutil
import stat
import subprocess
import sys
import tempfile

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
WIKI_URL = 'https://github.com/DeRamp/BeamNG.Earth.Rally.wiki.git'


def git(*args, cwd=None):
    return subprocess.run(['git', *args], cwd=cwd, check=True, capture_output=True, text=True).stdout


def _rm_readonly(func, path, _exc):
    os.chmod(path, stat.S_IWRITE)   # git's pack files are read-only on Windows
    func(path)


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument('--dry-run', action='store_true', help='show the changes, commit and push nothing')
    args = ap.parse_args()
    dirty = git('status', '--porcelain', '--', 'docs/wiki', 'docs/media', cwd=ROOT).strip()
    if dirty and not args.dry_run:
        print('docs/wiki or docs/media has uncommitted changes. Commit them first:\n' + dirty)
        return 1
    work = tempfile.mkdtemp(prefix='er-wiki-')
    try:
        try:
            git('clone', '--depth', '1', WIKI_URL, work)
        except subprocess.CalledProcessError as e:
            print('Could not clone the wiki: ' + (e.stderr or '').strip())
            print('Make its first page on the web first: https://github.com/DeRamp/BeamNG.Earth.Rally/wiki')
            return 1
        for f in glob.glob(os.path.join(work, '*.md')):
            os.remove(f)        # pages removed from docs/wiki/ go from the wiki too
        for f in glob.glob(os.path.join(ROOT, 'docs', 'wiki', '*.md')):
            shutil.copy(f, work)
        img = os.path.join(work, 'images')
        os.makedirs(img, exist_ok=True)
        for f in glob.glob(os.path.join(img, '*.jpg')):
            os.remove(f)        # images removed from docs/media/ go too
        for f in glob.glob(os.path.join(ROOT, 'docs', 'media', '*.jpg')):
            shutil.copy(f, img)
        git('add', '-A', cwd=work)
        status = git('status', '--short', cwd=work)
        if not status.strip():
            print('The wiki is up to date.')
            return 0
        print(status)
        if args.dry_run:
            print('Dry run: nothing pushed.')
            return 0
        head = git('rev-parse', '--short', 'HEAD', cwd=ROOT).strip()
        try:
            git('commit', '-m', 'Wiki from docs/wiki at ' + head, cwd=work)
            git('push', cwd=work)
        except subprocess.CalledProcessError as e:
            print('git ' + e.cmd[1] + ' failed: ' + (e.stderr or e.stdout or '').strip())
            return 1
        print('Published: https://github.com/DeRamp/BeamNG.Earth.Rally/wiki')
        return 0
    finally:
        shutil.rmtree(work, onerror=_rm_readonly)


if __name__ == '__main__':
    sys.exit(main())
