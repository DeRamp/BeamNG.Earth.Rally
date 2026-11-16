---
name: merge-request
description: Land a finished Earth Rally branch on main by opening a pull request and asking the maintainer session to review and merge it. Use when the owner says to merge, land or pull work into main. Only the maintainer changes main.
argument-hint: [branch]
---

Only the `maintainer` session changes `main`. A guard hook blocks merges, commits and pushes to `main` from every
other session. To land work, do these in order.

1. **Preconditions.** The owner has asked for this work to land. `/handoff` has been run on it and its fixes are
   committed. The branch is clean (`git status --porcelain` empty) and is not `main`. Note the head SHA: it is the
   build the owner tested and said to land.
2. **Do not rebase.** The maintainer tests the merge with the current `main` and lands it as a merge commit, so the
   SHAs the owner tested survive. Rebase only when the maintainer sends it back for a conflict.
3. **Push the branch.** `git push -u origin <branch>`. Never push `main`.
4. **Open the PR.** `gh pr create --base main --head <branch> --title "<what it does>" --body-file <file>`. The body:
   - what the change is meant to do, in two or three sentences, and the owner's request it answers;
   - `Handed off at <full SHA>`: the SHA from step 1;
   - the touched tests you ran and their result;
   - what `/handoff` found, what was fixed, and the objections not acted on with the reason.
   If a PR for the branch is already open, reuse it (`gh pr view <branch>`).
5. **Find the maintainer.** ListAgents. If no session named `maintainer` is listed, start it (the owner approved
   this, 2026-11-15): `powershell -ExecutionPolicy Bypass -File "$(git rev-parse --show-toplevel)/tools/maintainer.ps1"`
   from any checkout of this repo. Use forward slashes; Git Bash eats backslashes. The script always starts it in the main checkout as a background session and
   will not start a second one. Wait a minute for its startup checks, then ListAgents again. If it is still not
   listed, tell the owner (they can also merge the PR by hand on GitHub) and stop here.
6. **Send the request** with SendMessage to `maintainer`, plain text, one message:
   `merge-request PR #<N> <url> head <full SHA> branch <branch> from <your session name>. Intent: ... Tests: ...`
7. **Get the verdict.** The maintainer replies by message and always records the verdict as a PR comment. If no reply
   comes, read it with `gh pr view <N> --comments`. Pass it to the owner.
8. **If it is sent back,** do not fix it on your own. Give the owner the findings as a plan, as for any issue: what
   is wrong, the fix, the files. When the owner says to go ahead, fix, run `/handoff` again, hand the build back to
   the owner, and only when they say to land it, push and send a new request with the new head SHA. A conflict is
   the exception the owner need not test: rebase on `origin/main`, re-run the touched tests, push with
   `--force-with-lease`, add `rebased from <old SHA> to <new SHA>, conflict only` to the PR body, and tell the
   owner before sending the new request.
