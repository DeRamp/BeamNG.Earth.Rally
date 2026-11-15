---
name: handoff
description: Finish an Earth Rally build before it goes to the owner - touched tests, then the debugger and contrarian agents plus /code-review in parallel, then fixes. Use whenever a build or change is about to be handed over.
---

Run these in order. Do not install into or start the game at any step.

1. **Scope.** Work out the diff being handed over (`git diff main...HEAD`, or the commits named) and write two or
   three sentences on what it is meant to do, from the owner's request and the notes.

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
