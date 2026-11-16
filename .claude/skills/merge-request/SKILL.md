---
name: merge-request
description: Land a finished Earth Rally branch on main by opening a pull request and asking the maintainer session to review and merge it. Use when the owner says to merge, land or pull work into main. Only the maintainer changes main.
argument-hint: [branch]
---

Only the `maintainer` session changes `main`. A guard hook blocks merges, commits and pushes to `main` from every
other session. To land work, do these in order.

1. **Preconditions.** The owner has asked for this work to land. `/handoff` has been run on it and its fixes are
   committed. The branch is clean (`git status --porcelain` empty) and is not `main`.
2. **Rebase on main.** `git fetch origin` then `git rebase origin/main`. If that changed anything, re-run the touched
   tests (`python tests/run_tests.py <test_name> ...`).
3. **Push the branch.** `git push -u origin <branch>` (use `--force-with-lease` only on your own branch after a
   rebase). Never push `main`.
4. **Open the PR.** `gh pr create --base main --head <branch> --title "<what it does>" --body-file <file>`. The body:
   - what the change is meant to do, in two or three sentences, and the owner's request it answers;
   - the touched tests you ran and their result;
   - what `/handoff` found, what was fixed, and the objections not acted on with the reason.
   If a PR for the branch is already open, reuse it (`gh pr view <branch>`).
5. **Find the maintainer.** ListAgents. If no session named `maintainer` is listed, tell the owner to start it with
   `powershell -File tools/maintainer.ps1` from the repo root, and stop here.
6. **Send the request** with SendMessage to `maintainer`, plain text, one message:
   `merge-request PR #<N> <url> head <full SHA> branch <branch> from <your session name>. Intent: ... Tests: ...`
7. **Wait for the reply** and pass it to the owner. If it is sent back, fix the real findings on the same branch,
   re-run the touched tests, push, and send a new request with the new head SHA. Tell the owner about any finding you
   disagree with instead of arguing with the maintainer.
