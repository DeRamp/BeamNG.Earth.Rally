---
name: merge-request
description: Land a finished Earth Rally branch on main by opening a pull request and asking the maintainer session to review and merge it. Use when the owner says to merge, land or pull work into main. Only the maintainer changes main.
argument-hint: [branch]
---

Only the `maintainer` session changes `main`. A guard hook blocks merges, commits and pushes to `main` from every
other session. To land work, do these in order.

1. **Preconditions.** The owner has asked for this work to land. `/handoff` has been run on it and its fixes are
   committed. The branch is clean (`git status --porcelain` empty) and is not `main`. Note the head SHA `/handoff`
   reviewed: it is the `Handed off at` SHA. The owner does not have to have driven it; if they have not, say so in
   the PR body.
2. **Never rebase; back-merge instead.** `git fetch origin`, then if `origin/main` has moved since the branch started,
   `git merge --no-edit origin/main` into the branch now, so the maintainer finds no conflict. Resolve conflicts
   keeping both sides (a `docs/notes-*.md` written on both sides is the usual one: keep every line of each), re-run
   the touched tests, commit. Never rebase a pushed branch: that needs a force push. If you back-merged, the PR body
   gets a line `back-merged origin/main at <merge SHA>`; the head SHA is now that merge.
3. **Push the branch.** `git push -u origin <branch>`. Never push `main`.
4. **Open the PR.** `gh pr create --base main --head <branch> --title "<what it does>" --body-file <file>`. The body:
   - what the change is meant to do, in two or three sentences, and the owner's request it answers;
   - `Handed off at <full SHA>`: the SHA from step 1;
   - the touched tests you ran and their result;
   - what `/handoff` found, what was fixed, and the objections not acted on with the reason;
   - `Release: X.Y.Z-alpha` on its own line, only when the owner asked for this work to be released, and the same
     version in the step 6 message. The maintainer then publishes it right after the merge. The branch must carry
     the release text, written by `docs/writing-standard.md` and reviewed in `/handoff`: the new top `CHANGELOG.md`
     entry `## X.Y.Z-alpha: <name> (<date>)` and `M.VERSION` set to the version (plus any versioned doc renames).
     The version is the next patch, minor or major after the latest tag.
   If a PR for the branch is already open, reuse it (`gh pr view <branch>`).
5. **Find the maintainer.** ListAgents. If no session named `maintainer` is listed, start it (the owner approved
   this, 2026-11-15): `powershell -ExecutionPolicy Bypass -File "$(dirname "$(git rev-parse --path-format=absolute --git-common-dir)")/tools/maintainer.ps1"`
   from any checkout of this repo. That is main's copy in the main checkout; your branch's copy may be stale or
   missing. Use forward slashes; Git Bash eats backslashes. The script always starts it in the main checkout as a background session and
   will not start a second one. Wait a minute for its startup checks, then ListAgents again. If it is still not
   listed, tell the owner (they can also merge the PR by hand on GitHub) and stop here.
6. **Send the request** with SendMessage to `maintainer`, plain text, one message:
   `merge-request PR #<N> <url> head <full SHA> branch <branch> from <your session name>. Release: <version or none>. Intent: ... Tests: ...`
7. **Get the verdict.** The maintainer replies by message and always records the verdict as a PR comment. If no reply
   comes, read it with `gh pr view <N> --comments`. Pass it to the owner.
8. **If it is sent back,** fix it yourself without waiting on the owner (the owner, 2026-11-15: no friction):
   - **Conflict:** back-merge `origin/main` as in step 2, re-run the touched tests, push (a normal push, never
     force), add `back-merged origin/main at <SHA> for a conflict` to the PR body, and send a new request at once.
   - **CONFIRMED findings:** fix them, re-run the touched tests and `/handoff` over the fix commits only (not the
     whole branch again), push, and send a new request with the new head SHA. If a finding needs a design decision, give the owner a plan instead and stop.
   Tell the owner what you did in your report.
