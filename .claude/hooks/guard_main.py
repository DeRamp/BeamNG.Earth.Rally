"""PreToolUse guard: only the maintainer session may change `main`.

Claude Code runs this before every Bash and PowerShell call and passes the call as JSON on stdin. When the session
was started with `--agent maintainer`, the input carries `agent_type: "maintainer"` and everything is allowed.
Anywhere else, a command that would change `main` is blocked with exit code 2 and the reason on stderr:

- `gh pr merge`
- `git push` to `main` (named in a refspec, `--all`/`--mirror`, or a bare push while on `main`)
- `git branch -f/-D/-m/-M ... main`, `git update-ref refs/heads/main`
- `git commit/merge/rebase/cherry-pick/revert/am/pull/reset` while the checkout is on `main`

This is a guardrail against mistakes, not a security boundary: aliases, `sh -c` and scripts get past it.
Set GUARD_MAIN_LOG to a file path to append each hook input there (used to check `agent_type`).
"""

import json
import os
import re
import shlex
import subprocess
import sys

MAINTAINER = "maintainer"
MAIN = {"main", "master"}
CHANGES_CURRENT = {"commit", "merge", "rebase", "cherry-pick", "revert", "am", "pull", "reset"}
GIT_OPTS_WITH_VALUE = {"-C", "-c", "--git-dir", "--work-tree", "--namespace", "--exec-path"}
REASON = (
    "Blocked: only the maintainer session changes `main`. Work on your own branch and land it with "
    "/merge-request (opens a PR and asks the maintainer to review and merge)."
)


def segments(command):
    """Split a shell line into simple commands on ; && || | and newlines (quotes respected roughly)."""
    parts, buf, quote, i = [], [], None, 0
    while i < len(command):
        ch = command[i]
        if quote:
            buf.append(ch)
            if ch == quote:
                quote = None
        elif ch in "\"'":
            quote = ch
            buf.append(ch)
        elif ch in ";|\n&":
            parts.append("".join(buf))
            buf = []
            while i + 1 < len(command) and command[i + 1] in "|&":
                i += 1
        else:
            buf.append(ch)
        i += 1
    parts.append("".join(buf))
    return [p.strip() for p in parts if p.strip()]


def tokens(segment):
    # Non-POSIX mode keeps backslashes, so unquoted Windows paths survive; strip the quotes it leaves on.
    try:
        toks = shlex.split(segment, posix=False)
    except ValueError:
        toks = segment.split()
    return [t[1:-1] if len(t) > 1 and t[0] == t[-1] and t[0] in "\"'" else t for t in toks]


def exe(token):
    name = re.split(r"[\\/]", token)[-1].lower()
    return name[:-4] if name.endswith(".exe") else name


def current_branch(directory):
    try:
        out = subprocess.run(
            ["git", "-C", directory, "symbolic-ref", "--short", "-q", "HEAD"],
            capture_output=True, text=True, timeout=10,
        )
        return out.stdout.strip()
    except Exception:
        return ""


def names_main(ref):
    ref = ref.lstrip("+")
    dst = ref.split(":")[-1] if ":" in ref else ref
    dst = dst.removeprefix("refs/heads/")
    return dst in MAIN


def git_blocked(args, directory):
    """args: everything after `git`. Returns a reason or None."""
    i = 0
    while i < len(args) and args[i].startswith("-"):
        opt = args[i]
        if opt in GIT_OPTS_WITH_VALUE and i + 1 < len(args):
            if opt == "-C":
                directory = os.path.join(directory, args[i + 1])
            i += 2
        else:
            i += 1
    if i >= len(args):
        return None
    sub, rest = args[i], args[i + 1:]
    positional = [a for a in rest if not a.startswith("-")]

    if sub == "push":
        if any(a in ("--all", "--mirror") for a in rest):
            return "git push --all/--mirror"
        refspecs = positional[1:]
        if any(names_main(r) for r in refspecs):
            return "git push to main"
        if not refspecs and current_branch(directory) in MAIN:
            return "git push while on main"
        return None
    if sub == "branch":
        if any(a in ("-f", "--force", "-D", "-d", "--delete", "-m", "-M", "--move") for a in rest) and any(
            p in MAIN for p in positional
        ):
            return "git branch moving or deleting main"
        return None
    if sub == "update-ref":
        if any(p.removeprefix("refs/heads/") in MAIN for p in positional[:1]):
            return "git update-ref on main"
        return None
    if sub in CHANGES_CURRENT and current_branch(directory) in MAIN:
        return f"git {sub} on main"
    return None


def check(command, cwd):
    directory = cwd
    for seg in segments(command):
        toks = tokens(seg)
        if not toks:
            continue
        head = exe(toks[0])
        if head in ("cd", "set-location", "sl", "pushd") and len(toks) > 1:
            target = toks[-1]
            directory = target if os.path.isabs(target) else os.path.join(directory, target)
            continue
        if head == "&" and len(toks) > 1:  # PowerShell call operator: & "C:\...\gh.exe" pr merge
            toks, head = toks[1:], exe(toks[1])
        if head == "gh" and len(toks) > 2 and toks[1] == "pr" and toks[2] == "merge":
            return "gh pr merge"
        if head == "git":
            reason = git_blocked(toks[1:], directory)
            if reason:
                return reason
    return None


def main():
    raw = sys.stdin.read()
    log = os.environ.get("GUARD_MAIN_LOG")
    if log:
        with open(log, "a", encoding="utf-8") as f:
            f.write(raw.strip() + "\n")
    try:
        data = json.loads(raw)
    except ValueError:
        return 0
    if data.get("agent_type") == MAINTAINER:
        return 0
    command = (data.get("tool_input") or {}).get("command") or ""
    reason = check(command, data.get("cwd") or os.getcwd())
    if reason:
        print(f"{REASON} ({reason})", file=sys.stderr)
        return 2
    return 0


if __name__ == "__main__":
    sys.exit(main())
