"""PreToolUse guard: only the maintainer session may change Earth Rally's `main`.

Claude Code runs this before every Bash and PowerShell call and passes the call as JSON on stdin. A session started
with `claude --agent maintainer` sends `agent_type: "maintainer"` and no `agent_id`; it is allowed everything. A
subagent named maintainer carries an `agent_id` and is treated like any other session. Elsewhere, a command that
would change `main` of this repo (origin URL contains REPO) is blocked with exit code 2 and the reason on stderr:

- `gh pr merge` (unless `-R`/`--repo` names another repository)
- `git push` to `main` (named in a refspec, `--all`/`--mirror`, or a bare push while on `main`)
- `git branch -f/-D/-m/-M ... main`, `git update-ref refs/heads/main`
- `git commit/merge/rebase/cherry-pick/revert/am/pull/reset` while on `main`, except `pull --ff-only`,
  `--abort`/`--quit`, and a `reset` that only unstages paths

`git checkout X`/`git switch X` and `cd` earlier in the same command line are followed.
This is a guardrail against mistakes, not a security boundary: aliases, `sh -c` and scripts get past it.
Set GUARD_MAIN_LOG to a file path to append each hook input there (to re-check `agent_type` after an update).
"""

import json
import os
import re
import shlex
import subprocess
import sys

MAINTAINER = "maintainer"
REPO = "beamng.earth.rally"
MAIN = {"main", "master"}
CHANGES_CURRENT = {"commit", "merge", "rebase", "cherry-pick", "revert", "am", "pull", "reset"}
GIT_OPTS_WITH_VALUE = {"-C", "-c", "--git-dir", "--work-tree", "--namespace", "--exec-path"}
RESET_MODES = {"--hard", "--soft", "--mixed", "--keep", "--merge"}
REASON = (
    "Blocked: only the maintainer session changes Earth Rally's `main`. Work on your own branch and land it with "
    "/merge-request (opens a PR and asks the maintainer to review and merge)."
)


HEREDOC = re.compile(r"<<-?\s*(['\"]?)(\w+)\1[^\n]*\n.*?^\s*\2\s*$", re.S | re.M)
HERESTRING = re.compile(r"@(['\"])\r?\n.*?^\1@", re.S | re.M)
REDIRECT = re.compile(r"^\d*>{1,2}(&\d*)?$|^\d*>{1,2}\S+$|^<\S*$")
ENV_PREFIX = re.compile(r"^[A-Za-z_][A-Za-z0-9_]*=")


def strip_bodies(command):
    """Drop heredoc and PowerShell here-string bodies: they are data (commit messages), not commands."""
    command = HEREDOC.sub(lambda m: m.group(0).split("\n", 1)[0], command)
    return HERESTRING.sub("''", command)


def win_path(path):
    """Git Bash spells C:\\x as /c/x; os.path does not know that."""
    m = re.match(r"^/([a-zA-Z])(/|$)(.*)", path)
    return f"{m.group(1).upper()}:/{m.group(3)}" if m else path


def join(base, path):
    path = win_path(path)
    return path if os.path.isabs(path) else os.path.join(base, path)


def segments(command):
    """Split a shell line into simple commands on ; && || | and newlines (quotes respected roughly)."""
    command = strip_bodies(command)
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
        elif ch in ";|\n&" and not (ch == "&" and buf and buf[-1] == ">"):  # keep 2>&1 whole
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
    toks = [t[1:-1] if len(t) > 1 and t[0] == t[-1] and t[0] in "\"'" else t for t in toks]
    while toks and ENV_PREFIX.match(toks[0]):  # GIT_EDITOR=true git ...
        toks = toks[1:]
    return [t for t in toks if not REDIRECT.match(t)]


def exe(token):
    name = re.split(r"[\\/]", token)[-1].lower()
    return name[:-4] if name.endswith(".exe") else name


def git_out(directory, *args):
    try:
        out = subprocess.run(["git", "-C", directory, *args], capture_output=True, text=True, timeout=5)
        return out.stdout.strip()
    except Exception:
        return ""


class State:
    """Directory and assumed branch as the command line runs; git is asked once per directory."""

    def __init__(self, cwd):
        self.dir = cwd
        self.branch_override = {}
        self.cache = {}

    def _key(self):
        return os.path.normcase(os.path.abspath(self.dir))

    def ours(self):
        key = self._key()
        if ("url", key) not in self.cache:
            self.cache[("url", key)] = REPO in git_out(self.dir, "remote", "get-url", "origin").lower()
        return self.cache[("url", key)]

    def branch(self):
        key = self._key()
        if key in self.branch_override:
            return self.branch_override[key]
        if ("br", key) not in self.cache:
            self.cache[("br", key)] = git_out(self.dir, "symbolic-ref", "--short", "-q", "HEAD")
        return self.cache[("br", key)]

    def set_branch(self, name):
        self.branch_override[self._key()] = name


def names_main(ref, state):
    ref = ref.lstrip("+")
    dst = ref.split(":")[-1] if ":" in ref else ref
    if dst in ("HEAD", "@"):  # `git push origin HEAD` pushes the current branch
        dst = state.branch()
    return dst.removeprefix("refs/heads/") in MAIN


def looks_like_commit(arg):
    # Plain HEAD is left out: resetting to HEAD only unstages, the branch stays put.
    return bool(re.search(r"[~^@]|^origin/|^[0-9a-f]{7,40}$", arg))


def git_blocked(args, state):
    """args: everything after `git`. Returns a reason or None."""
    saved_dir = state.dir
    i = 0
    while i < len(args) and args[i].startswith("-"):
        opt = args[i]
        if opt in GIT_OPTS_WITH_VALUE and i + 1 < len(args):
            if opt == "-C":
                state.dir = join(state.dir, args[i + 1])
            i += 2
        else:
            i += 1
    try:
        if i >= len(args):
            return None
        sub, rest = args[i], args[i + 1:]
        positional = [a for a in rest if not a.startswith("-")]

        if sub in ("checkout", "switch"):
            new = next((rest[j + 1] for j, a in enumerate(rest[:-1]) if a in ("-b", "-B", "-c", "-C")), None)
            if new or (positional and "--" not in rest and "--detach" not in rest):
                state.set_branch(new or positional[0])
            elif "--detach" in rest:
                state.set_branch("")
            return None
        if sub not in CHANGES_CURRENT | {"push", "branch", "update-ref"} or not state.ours():
            return None
        if sub == "push":
            if any(a in ("--all", "--mirror") for a in rest):
                return "git push --all/--mirror"
            refspecs = positional[1:]
            if any(names_main(r, state) for r in refspecs):
                return "git push to main"
            if not refspecs and state.branch() in MAIN:
                return "git push while on main"
            return None
        if sub == "branch":
            moving = any(a in ("-f", "--force", "-D", "-d", "--delete", "-m", "-M", "--move") for a in rest)
            # `git branch -f mine main` moves mine, not main: only the first name is the branch acted on
            return "git branch moving or deleting main" if moving and positional[:1] and positional[0] in MAIN else None
        if sub == "update-ref":
            return "git update-ref on main" if positional[:1] and names_main(positional[0], state) else None
        if state.branch() not in MAIN:
            return None
        if any(a in ("--abort", "--quit") for a in rest):
            return None
        if sub == "pull" and "--ff-only" in rest:
            return None
        if sub == "reset" and not RESET_MODES & set(rest) and not any(looks_like_commit(p) for p in positional):
            return None
        return f"git {sub} on main"
    finally:
        state.dir = saved_dir  # `git -C dir` applies to that one command only


def gh_blocked(toks, state):
    if len(toks) > 2 and toks[1] == "pr" and toks[2] == "merge":
        for j, a in enumerate(toks):
            if a in ("-R", "--repo") and j + 1 < len(toks):
                return "gh pr merge" if REPO in toks[j + 1].lower() else None
            if a.startswith("--repo="):
                return "gh pr merge" if REPO in a.lower() else None
        return "gh pr merge" if state.ours() else None
    return None


def check(command, cwd):
    state = State(cwd)
    for seg in segments(command):
        toks = tokens(seg)
        if not toks:
            continue
        head = exe(toks[0])
        if head in ("cd", "set-location", "sl", "pushd", "push-location") and len(toks) > 1:
            state.dir = join(state.dir, toks[-1])
            continue
        if head == "&" and len(toks) > 1:  # PowerShell call operator: & "C:\...\gh.exe" pr merge
            toks, head = toks[1:], exe(toks[1])
        reason = None
        if head == "gh":
            reason = gh_blocked(toks, state)
        elif head == "git":
            reason = git_blocked(toks[1:], state)
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
        if not isinstance(data, dict):
            return 0
        if data.get("agent_type") == MAINTAINER and not data.get("agent_id"):
            return 0
        command = (data.get("tool_input") or {}).get("command") or ""
        reason = check(command, data.get("cwd") or os.getcwd())
    except Exception as e:  # never break every shell call over a parsing bug
        print(f"guard_main.py: {e}", file=sys.stderr)
        return 0
    if reason:
        print(f"{REASON} ({reason})", file=sys.stderr)
        return 2
    return 0


if __name__ == "__main__":
    sys.exit(main())
