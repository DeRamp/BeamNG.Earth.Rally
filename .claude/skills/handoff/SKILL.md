---
name: handoff
description: Finish an Earth Rally build before it goes to the owner - touched tests, then the debugger and contrarian agents plus /code-review in parallel, then fixes. Use whenever a build or change is about to be handed over.
---

Run these in order. Do not install into or start the game at any step.

1. **Scope.** Work out the diff being handed over and write two or three sentences on what it is meant to do, from
   the owner's request and the notes. Review only what no reviewer has seen (the owner, 2026-11-15): on a first
   handoff, the branch's own changes (`git diff main...HEAD`); after that, only the commits since the last reviewed
   SHA: the `Reviewed head` line of the maintainer's last verdict comment if there is one, else the PR body's
   `Handed off at` SHA (or, before a PR exists, the commit your last `/handoff` report named). A back-merge of `main` counts only for its conflict resolution
   (`git show --remerge-diff <merge>`), never for `main`'s own changes.

2. **Touched tests.** Run only the tests for the files changed: `python tests/run_tests.py <test_name> ...`. Skip
   `test_arearoute_e2e` and `test_roadgraph_e2e` unless the diff touches BeamNG.Earth downloads or the road graph.
   Fix failures before going on.

3. **Review, in parallel, in one message:**
   - the `debugger` agent: the diff range, the intent, the files.
   - the `contrarian` agent: the diff range, the intent, and the stated reasoning (commit messages, notes doc).
     Give it the code and the reasoning, not the conclusion you want confirmed.
   - `/code-review high` on the same range, report only (no `--fix`).

4. **Fix what is real.** Re-run the touched tests. If a fix is more than small, run the debugger once more on it.

5. **Report to the owner:**
   - what was built, the branch and commit;
   - what the reviewers found and what was fixed;
   - objections not acted on, each with the reason;
   - that the build is ready to install, and that you are waiting to be told before touching the game.
