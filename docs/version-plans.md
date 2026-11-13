# Earth Rally: a plan for each version

The order of work inside each version from docs/roadmap.md, what each step depends on, and when the version is done.
Every version: UI changes are shown to the user as mock-ups before they are built; while the user tests, reports are
logged (docs/notes-<version>.md), not fixed on the spot; a release only when the user says.

## 1.2.2: the stage display works

1. In-game test of what is built (the on-stage display, the radial menu, long names). First, on any machine:
   `python tools/selftest.py --check-install`, then drive Maryhill Up (or `python tools/selftest.py`).
2. If the display still fails: the new log lines (`stage layout: ...`, `HUD streams (run ...)`) say whether the
   layout or the data is missing.
3. The blank start board after a new start minute (roadmap 7): runner.feedStartClock against the game's
   `rescheduleNextSSStart` (docs/ideas-1.2.0.md).
4. First real run of the self-test (tools/selftest.py): check the AI drives a BeamNG.Earth stage, fix what doesn't.
5. Fix the 1.2.1 release notes' known issue (the display bug was the install script, not the release zip).

Done: the display seen in game through a whole stage; the self-test passes on Maryhill Up.

## 1.3.0: stages for everyone

1. Version checks at startup (23): small, and it protects everything after.
2. Folder-based import (4) and the automatic ATC (3): importer and runner, offline tests.
3. Stage pre-loading with a loaded % (21): BeamNG.Earth's area pre-cache along the stage corridor; mock-up of the
   loading display first.
4. The matcher add-on (1), in the order in docs/plan-1.3.0.md: companion file from match_roads.py, tested with the
   dev tree's `--run-addon`; a small upstream PR (server/ on the companion's path, folder env vars); a local.json
   entry; the stage page's matcher status (mock-up first).
5. Release 1.3.0 as a full (not pre-) release; ask TecnaGamer to list Earth Rally (mod + matcher) in the add-on
   registry.

Done: on a clean PC, a dropped-in map's stages drive without a recce, with no Python installed.

## 1.4.0: the co-driver

1. Agree with the user what the overhaul covers (call style, which features).
2. Heights along the matched line: crests, jumps, dips; cautions from tightening corners and narrow sections.
3. Better corner grading and distance calls, checked against the game's own stages' notebooks.
4. Co-driver settings (26): call timing, detail, voice (menu mock-up first).

Done: the user drives three known stages and trusts the calls.

## 1.5.0: make and share stages

1. The Earth Rally file format (19): versioned, one file per rally; stages carry line, heights, controls, notes;
   imports write it; old event files converted.
2. Rally setup mode (18): recce with no line, place ATC / start / finish / stop with a key, save as a stage.
3. Top-down editor (11): stage line and controls on BeamNG.Earth's map, drag controls, reroute along roads (uses
   1.3.0's routing), edit existing stages; keeps edits when the source map is re-imported (warns).
4. Local leaderboards (20) tied to the file's fingerprint.

Done: the user makes a stage in game, shares the file, and it runs on another PC with no recce.

## 1.6.0: on the stage

1. Course tape (5) and junction direction signs (6) from the junction data the matcher finds.
2. Ghost car and replays (27).
3. Atmosphere (29): spectators, marshals, radio points.
4. Height profiles / stage sketches (15).
5. Stages wider than ~26 km (8): follow BeamNG.Earth's world shifts mid-stage (API 1.7's onBeamNGEarthRebased).

Done: a long stage with tape, signs and a ghost, end to end.

## 1.7.0: the full rally

1. Run the whole rally (9): stage order, running total, timecard.
2. Itineraries (10): loops, road sections with target times and early / late penalties.
3. Service (24): service areas in the file and the editor, repairs in full-rally mode.
4. Rally-mode recovery (17): the game's resets off on stage; prompts with controls shown; a full repair's penalty
   to agree.
5. Weather and time of day per stage (25); split times (15).

Done: a full imported rally (e.g. Olympus) driven start to finish with service.

## 2.0.0: public release

1. Install and update from BeamNG.Earth's Add-ons page (22).
2. A starter pack of stages and a tutorial.
3. Championship mode (28); pick your rally and recce car (12, 13); a recovery vehicle (14).
4. Decide on online leaderboards (20).

Done: a new player installs it from the Add-ons page and finishes a stage without help.
