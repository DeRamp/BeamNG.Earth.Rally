#!/usr/bin/env python3
"""The guard hook (.claude/hooks/guard_main.py) blocks main-changing git/gh commands outside the maintainer session.

Builds a throwaway repo whose origin URL names Earth Rally: a checkout on `main` (ROOT) and a worktree on a feature
branch (WT), plus an unrelated repo (OTHER) on `main`. Each case pipes hook input into the script and checks the
exit code: 2 = blocked, 0 = allowed. Needs git; no game, no network.
"""
import json
import subprocess
import sys
import tempfile
from pathlib import Path

HOOK = Path(__file__).resolve().parents[1] / '.claude' / 'hooks' / 'guard_main.py'


def git(*args, cwd):
    subprocess.run(['git', *args], cwd=cwd, check=True, capture_output=True)


def make_repo(path, url):
    path.mkdir()
    git('init', '-q', '-b', 'main', cwd=path)
    git('-c', 'user.name=t', '-c', 'user.email=t@t', 'commit', '-q', '--allow-empty', '-m', 'init', cwd=path)
    git('tag', 'v1.0.0', cwd=path)
    git('-c', 'user.name=t', '-c', 'user.email=t@t', 'commit', '-q', '--allow-empty', '-m', 'two', cwd=path)
    git('remote', 'add', 'origin', url, cwd=path)


def cases(ROOT, WT, OTHER):
    unix_root = '/' + ROOT[0].lower() + ROOT[2:].replace('\\', '/') if ROOT[1:2] == ':' else ROOT
    return [
        # gh
        (2, ROOT, None, 'gh pr merge 3 --rebase'),
        (2, WT, None, 'gh pr merge 5 --repo DeRamp/BeamNG.Earth.Rally'),
        (2, WT, None, 'gh pr -R DeRamp/BeamNG.Earth.Rally merge 5'),
        (2, WT, None, 'gh -R DeRamp/BeamNG.Earth.Rally pr merge 5'),
        (2, WT, None, '& "C:\\Program Files\\GitHub CLI\\gh.exe" pr merge 4'),
        (0, ROOT, None, 'gh pr merge 5 -R DeRamp/BeamNG.Earth'),
        (0, OTHER, None, 'gh pr merge 2'),
        (0, WT, None, 'gh pr create --base main --head x --title t --body-file b.md'),
        # who is allowed
        (0, ROOT, ('maintainer', None), 'gh pr merge 3'),
        (2, ROOT, ('maintainer', 'sub1'), 'gh pr merge 3'),
        (0, ROOT, ('debugger', 'sub2'), 'git diff main...HEAD'),
        # commits and merges on main
        (2, ROOT, None, 'git commit -m x'),
        (2, ROOT, None, 'git pull'),
        (2, ROOT, None, 'git pull --ff-only origin feature'),
        (0, ROOT, None, 'git pull --ff-only'),
        (0, ROOT, None, 'git pull --ff-only origin main'),
        (0, ROOT, None, 'git merge --abort'),
        (0, ROOT, None, 'git rebase --abort'),
        (2, ROOT, None, 'git commit -m --abort'),
        (2, ROOT, None, 'GIT_EDITOR=true git rebase --continue'),
        (0, ROOT, None, 'git status && git log --oneline -3 | head'),
        (0, ROOT, None, 'git commit-tree --help'),
        (0, ROOT, None, "echo 'git commit; gh pr merge' > notes.txt"),
        # reset
        (0, ROOT, None, 'git reset'),
        (0, ROOT, None, 'git reset CLAUDE.md'),
        (0, ROOT, None, 'git reset HEAD CLAUDE.md'),
        (2, ROOT, None, 'git reset --hard origin/main'),
        (2, ROOT, None, 'git reset HEAD~1'),
        (2, ROOT, None, 'git reset v1.0.0'),
        (2, ROOT, None, 'git reset feature'),
        # feature worktree is free
        (0, WT, None, 'git commit -m x'),
        (0, WT, None, 'git rebase origin/main'),
        (0, WT, None, 'git push -u origin feature'),
        (0, WT, None, 'git push -u origin HEAD'),
        (0, WT, None, 'git push --force-with-lease origin feature'),
        (0, WT, None, 'git push 2>&1 | tail -3'),
        # pushes to main
        (2, WT, None, 'git push origin HEAD:main'),
        (2, WT, None, 'git push origin +refs/heads/x:refs/heads/main'),
        (2, WT, None, 'git push --all'),
        (2, ROOT, None, 'git push origin HEAD'),
        (2, ROOT, None, 'git push origin @'),
        (2, ROOT, None, 'git push origin 2>&1'),
        (2, ROOT, None, 'git push 2>&1 | tail -3'),
        (2, ROOT, None, 'git push origin > out.txt'),
        (2, ROOT, None, 'git push origin 2> err.txt'),
        (2, ROOT, None, 'git push origin *> $null'),
        # reaching main from elsewhere
        (2, WT, None, f'git fetch && git -C {ROOT} merge foo'),
        (2, WT, None, f'cd {ROOT} && git merge foo'),
        (2, WT, None, f'cd "{ROOT}"; git commit -m x'),
        (2, WT, None, f'Push-Location {ROOT}; git commit -m x'),
        (2, WT, None, f'cd {unix_root} && git commit -m x'),
        (2, WT, None, f'git -C {unix_root} commit -m x'),
        (2, WT, None, 'git checkout main && git merge feat && git push'),
        (2, WT, None, 'git switch main; git commit -m x'),
        (0, ROOT, None, 'git checkout -b fix && git commit -m x'),
        (0, ROOT, None, 'git switch -c fix origin/main && git commit -m x'),
        (0, ROOT, None, 'git switch feature && git push'),
        (2, ROOT, None, 'git checkout README.md && git commit -m x'),
        (2, ROOT, None, 'git checkout . && git commit -m x'),
        (2, ROOT, None, 'git checkout -- f && git commit -m x'),
        # branch refs
        (2, WT, None, 'git branch -f main HEAD'),
        (0, WT, None, 'git branch -f other HEAD'),
        (0, WT, None, 'git branch -f mine main'),
        (2, WT, None, 'git branch -M feature main'),
        (2, WT, None, 'git branch -m feature main'),
        (2, WT, None, 'git branch -C feature main'),
        (2, WT, None, 'git branch -D feature main'),
        (0, WT, None, 'git branch -D old'),
        (2, WT, None, 'git update-ref refs/heads/main abc'),
        (2, WT, None, 'git update-ref -m msg refs/heads/main HEAD'),
        # message bodies are data
        (0, WT, None, "git commit -m @'\nfix: don't push\ngit push origin main\n'@"),
        (0, WT, None, "git commit -F - <<'EOF'\nfix things\ngit push origin main\nEOF\ngit log -1"),
        (2, WT, None, "git commit -F - <<'EOF'\nmsg\nEOF\ngit push origin main"),
        # the release script
        (2, ROOT, None, 'python tools/release.py 1.6.1-alpha'),
        (0, WT, None, 'python tools/release.py 1.6.1-alpha --check'),
        (0, WT, None, 'python -m py_compile tools/release.py'),
        (0, WT, None, 'git diff tools/release.py'),
        (2, WT, None, 'uv run python tools/release.py 1.6.1-alpha'),
        (2, WT, None, r'py -3 tools\release.py 1.6.1-alpha'),
        (0, ROOT, ('maintainer', None), 'python tools/release.py 1.6.1-alpha'),
        (2, ROOT, ('maintainer', 'sub1'), 'python tools/release.py 1.6.1-alpha'),
        (0, WT, None, 'python tools/package.py 1.6.1-alpha'),
        (0, OTHER, None, 'python tools/release.py 1.0.0'),
        (2, WT, None, 'py -3 -u tools/release.py 1.6.1-alpha'),
        (2, WT, None, 'python -X utf8 tools/release.py 1.6.1-alpha'),
        (2, WT, None, 'python3.12 tools/release.py 1.6.1-alpha'),
        (2, OTHER, None, f'python {ROOT}/tools/release.py 1.6.1-alpha'),
        (2, OTHER, None, f'cd {OTHER} && python {unix_root}/tools/release.py 1.6.1-alpha'),
        # other repos are not guarded
        (0, OTHER, None, 'git commit -m x'),
    ]


def run(case):
    want, cwd, who, cmd = case
    data = {'tool_name': 'Bash', 'cwd': cwd, 'tool_input': {'command': cmd}}
    if who:
        data['agent_type'], agent_id = who
        if agent_id:
            data['agent_id'] = agent_id
    p = subprocess.run([sys.executable, str(HOOK)], input=json.dumps(data), capture_output=True, text=True)
    return p.returncode == want, p.returncode


def main():
    failed = 0
    with tempfile.TemporaryDirectory() as tmp:
        tmp = Path(tmp)
        root, other, wt = tmp / 'rally', tmp / 'other', tmp / 'rally-wt'
        make_repo(root, 'https://github.com/DeRamp/BeamNG.Earth.Rally.git')
        make_repo(other, 'https://github.com/DeRamp/BeamNG.Earth.git')
        git('worktree', 'add', '-q', '-b', 'feature', str(wt), cwd=root)
        all_cases = cases(str(root), str(wt), str(other))
        for case in all_cases:
            ok, rc = run(case)
            if not ok:
                failed += 1
                print(f'FAIL: want {case[0]} got {rc}: {case[3]!r} in {Path(case[1]).name} as {case[2]}')
        for raw in ('notjson', '[1]', '{"tool_input": "x"}'):
            p = subprocess.run([sys.executable, str(HOOK)], input=raw, capture_output=True, text=True)
            if p.returncode != 0:
                failed += 1
                print(f'FAIL: bad input {raw!r} exit {p.returncode}')
        total = len(all_cases) + 3
    print(f'test_guard_main: {total - failed} passed, {failed} failed')
    return 1 if failed else 0


if __name__ == '__main__':
    sys.exit(main())
