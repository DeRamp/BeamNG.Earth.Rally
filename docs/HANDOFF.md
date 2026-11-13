# Handoff: where Earth Rally stands (2026-11-13, moving from the laptop to the desktop)

Read this first in a new session. It replaces the laptop session's memory.

## The project

Earth Rally (this repo, github.com/DeRamp/BeamNG.Earth.Rally, MIT, by DeRamp): a BeamNG.drive 0.40.5 mod that
runs real rally stages on BeamNG.Earth (github.com/TecnaGamer/BeamNG.Earth, a streamed real-world map mod), timed,
with the game's own co-driver calling pacenotes made from the road. Maps (KML/KMZ/GPX, also `.kml.xml`) dropped in
`%LOCALAPPDATA%\BeamNG\BeamNG.drive\current\earthRally\import\` become rallies.

Upstream: our PR "Modding API 1.7: onBeamNGEarthRebased" (TecnaGamer/BeamNG.Earth#1183) is merged into BeamNG.Earth's
`dev` (b28afde9); in dev builds from 1.9.1-beta.dev.398, not in stable 1.9.1-beta.

## Branches and releases

- `main`: the 1.2.1 release (tag v1.2.1-alpha). Releases so far: v1.0.0-alpha, v1.1.0-alpha, v1.2.0-alpha,
  v1.2.1-alpha (all GitHub pre-releases), v1.2.2-alpha (pre-release, NOT yet tried in game; see below).
- `v1.2.0`: the working branch (despite its name): 1.2.2 plus the self-test, roadmap and plans. Continue here (or
  rename it).
- `auto-test`: the self-test's own branch, already merged into v1.2.0.

## What's in progress

**1.2.2 (built, not yet tried in game).** docs/notes-1.2.2.md. The on-stage display (start time, clock, progress
bar, off-route card, finish time, results card) never showed in 1.2.1 testing. Cause: `tools/install.py` still ran an
old 1.1.0 step that wrote its own stage layout over the mod's, without the HUD apps (only the install script: the
release zips were fine). Fixed (e4148b6), plus: the 1 s layout hold no longer fights the radial menu; new log lines
(`stage layout put on`, `stage layout: game state ...; on screen ...`, `HUD streams (run ...)`, `off route` /
`back on route`); long rally names cut short in the menu. Next: install, drive Maryhill Up (OTR 2024), check the
display end to end. The 1.2.1 release notes and main's README say the display doesn't work in 1.2.1: that is wrong
for the zip (it was our install script), still to correct.

**Self-test (roadmap item 30, built, offline only).** `tools/selftest.py`: with the game closed, installs, launches
BeamNG.Earth, the game's AI drives Maryhill Up, checks the HUD, calls, off route, recovery, finish and results, writes
`earthRally/selftest/report-*.json`, closes the game. `--check-install` (safe with the game open) compares the
installed mod with the repo. Never run in game yet: the AI's driving on BeamNG.Earth roads, the launcher start and
the game closing are unverified.

**Plans:** docs/roadmap.md (versions 1.2.2 to 2.0.0, agreed with the user), docs/version-plans.md (each version's
steps and "done"), docs/plan-1.3.0.md (matcher add-on design + research findings), docs/research-1.3.0/ (matcher
draft). Version order: 1.3.0 stages for everyone, 1.4.0 the co-driver, 1.5.0 make and share, 1.6.0 on the stage,
1.7.0 the full rally, 2.0.0 public release.

## How the user works (from the laptop session's memory)

- **UI together:** for any menu/HUD/screen work, show a mock-up first and wait for agreement before writing UI code.
  The user wants it clean, fun and sensible for an average player; the ImGui window is developer-only.
- **While the user is testing, only log** what they report (docs/notes-<next version>.md). No code changes, installs
  or commits until they say. (They said: "Don't make any changes right now. I just want you to store these for the
  next version.")
- **Scope:** small things reported while testing go into the next patch version; large new systems go to a later
  minor version (propose which). Releases only when the user asks; they're published as GitHub pre-releases so far.
- The user often dictates with speech-to-text: game sounds (co-driver calls) sometimes end up in messages.
- Don't install or push without the user saying so.

## Setting up the desktop

1. **Game:** BeamNG.drive 0.40.5.
2. **BeamNG.Earth (dev branch, to get API 1.7):** clone github.com/TecnaGamer/BeamNG.Earth, `git switch dev`, make
   its `.venv` (its README), run its launcher: `.venv\Scripts\python.exe launcher.py --no-beammp`. On the laptop the
   launcher failed with "the native module (server/earthfast) is version 222, older than 285": a stale locally
   replaced `server/earthfast.pyd`; `git checkout -- server/earthfast.pyd` restored dev's (version 290). A fresh clone
   won't have this. (Or use a dev build exe 1.9.1-beta.dev.398+.)
3. **Earth Rally:** either the release zip (v1.2.2-alpha) into
   `%LOCALAPPDATA%\BeamNG\BeamNG.drive\current\mods\` (delete older Earth Rally zips), or clone this repo, switch to
   `v1.2.0`, and `python tools/install.py` (unpacked; not both at once).
4. **Tools:** Python 3.12, `pip install lupa` (offline tests: `python tests/run_tests.py`, 11 files), GitHub CLI
   (`gh auth login`).
5. **Your rally data is not on GitHub** (organisers' maps; keep it private). Copy from the laptop:
   - `%LOCALAPPDATA%\BeamNG\BeamNG.drive\current\earthRally\` (imported rallies, recces, matched lines, times),
   - the `Rally Docs` folder (the original maps and route books).
   Matched lines can also be remade on the desktop with `tools/match_roads.py --earth <beamng.earth> --event <id>`
   (needs BeamNG.Earth's .venv; it downloads road/height data on first use).

## Open items not yet in a version

- Missed-ATC +60 s penalty and a full run on Schafer: never checked in game.
- Matching results for the user's new rallies (2026-11-13): LSPR, SnoDrift, Overmountain and most of Rally Colorado
  fully on the road map; 100 Acre Wood, OFR and SOFR Friday/Saturday have stretches with no road on the map.
  SOFR's (and one other map's) controls didn't import: their points are named just "Start" / "Finish" (folder-based
  import is roadmap 4, in 1.3.0).
