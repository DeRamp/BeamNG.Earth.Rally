# Earth Rally

BeamNG.drive 0.40.5 mod (Lua, `mod/earth_rally/`) that runs real rally stages on BeamNG.Earth, with Python tools in
`tools/`. `docs/roadmap.md` is the source of truth for what each version holds.

## How the owner works

- **An issue means a plan, not a change.** When the owner reports a problem or idea, give the diagnosis, the fix and
  the files it touches, then stop. Build only when told. Exception (the owner, 2026-11-15): findings the maintainer
  sends back on your own merge request are fixed without asking (`/merge-request` step 8), unless one needs a
  design decision. Small fixes go in the next patch, new systems in a later minor.
- **UI: mock-up first** (`docs/mockups-<version>/*.html`, 1920x1080, now/proposed toggle; `docs/mockups-1.2.0/hud.html`
  is the pattern) and wait for OK. Skip the mock-up when the owner has already specified the design.
- **While the owner is testing, log, don't fix:** findings go in `docs/notes-<next version>.md` with the diagnosis.
- **Never touch the live game** (close, launch, install into, start BeamNG) without asking, every time.
- **Start the game only through BeamNG.Earth's launcher**, never Steam (Steam skips the world server):
  `..\beamng.earth\.venv\Scripts\python.exe launcher.py --no-beammp --no-update-check` from the `beamng.earth` folder,
  in a new console. On a restart, wait until no BeamNG.Earth Python process is left, plus a few seconds, then
  confirm the launcher, its server and `BeamNG.drive.exe` are all running.
- **Never install, push, tag or release without being told.** Once the owner says to land work, `/merge-request`
  pushes your own branch and opens its PR, and back-merges `origin/main` into it when needed; those are the only
  pushes it covers (never a force push).
- Never move windows on the owner's desktop.
- The owner dictates by speech-to-text; stray pacenote words ("left 4", "over crest") in a message are game audio.

## Branches and releases

- **Bug fixes only until the alpha MVP is out** (the owner, 2026-11-15); features stay planned in the roadmap.
  README, wiki and posts carry no version number: they say alpha.
- Work on a branch or worktree branched from `main`. `v1.2.0`, `v1.1.0`, `auto-test` are history only.
- **Only the `maintainer` session changes `main`.** It reviews, tests and merges pull requests. To land work, run
  `/merge-request`: it opens a PR and messages the maintainer, starting it first if it is not running
  (`powershell -ExecutionPolicy Bypass -File tools/maintainer.ps1` from the main checkout, a background session; `claude agents` lists it,
  `claude attach <id>` talks to it). A hook (`.claude/hooks/guard_main.py`) blocks
  merges, commits and pushes to `main` from every other session. The owner can still merge by hand on GitHub.
- Release = tag `vX.Y.Z-alpha` on `main` + GitHub pre-release with `dist/earth_rally-X.Y.Z-alpha.zip`. When the owner
  asks for a release, the PR carries the CHANGELOG entry and `M.VERSION` bump and a `Release: X.Y.Z-alpha` line: the
  maintainer publishes it right after merging (`tools/release.py`). No other session tags or releases.
- Rally data (events, recces, matched lines, times, `Rally Docs/`, KML) is organisers' material: never in git.

## Checking work

- Offline tests (no game needed, LuaJIT via `lupa`): `python tests/run_tests.py test_geo` runs one test.
- **Run only the tests the change touches**, not the whole suite by habit.
- Skip `test_arearoute_e2e` and `test_roadgraph_e2e` unless the work touches BeamNG.Earth downloads or the road
  graph: they can hang for an hour.
- `tools/selftest.py` exits 1 on every run (it cannot hear the co-driver). Read its checks, not its exit code.
- `tools/playtest.py` installs, launches and drives a stage: it touches the live game, so ask first.
- The real check is the owner driving it.

## Before handing a build over

Run `/handoff`: the touched tests, then the `debugger` and `contrarian` agents (`.claude/agents/`) in parallel, then
fix what is real and say which objections you are not acting on and why. Never skip it.

## Writing README, changelog and release notes

Every change to `README.md` or `CHANGELOG.md`, and every GitHub release body, follows
[`docs/writing-standard.md`](docs/writing-standard.md). Read it before writing any of them. Check word counts with
`wc -w` before committing.
