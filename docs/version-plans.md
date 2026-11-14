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

The full order and the reasoning are in docs/plan-1.3.0.md. In short, and not in the obvious order:

0. Answer the auto recce's three unknowns with a throwaway spike, building nothing. They are the only real unknowns in
   this version, and if one fails the whole shape of it changes -- better to know in an afternoon than at the end.
1. Version checks at startup (23): small, and it protects everything after.
2. Stage pre-loading with how much is loaded on screen (21); mock-up first. Before the auto recce, not after: a
   road-graph read is cached-only, and this is what puts the corridor's cells on disk for it.
3. The auto recce (1): the backbone, and the large one, in this mod's own Lua on api.roadGraph -- not a companion
   add-on. Stage page mock-up first. Revisit the self-test's settle gate when
   it lands -- that gate is a workaround for the problem this step fixes properly.
4. Folder-based import (4), the automatic ATC (3), and dropping the late-start penalty: contained, offline tests,
   and the easiest to drop if the auto recce needs the time.
5. Release 1.3.0 as a **full** release, tested on a clean PC rather than this one; ask TecnaGamer to list Earth
   Rally (mod + auto recce) in the add-on registry.

Nothing goes upstream for 1.3.0 (the user, 2026-11-13): the api.hudHide pull request was drafted, reviewed and
dropped -- docs/plan-1.3.0.md, "The strips: no pull request" -- and the mount call Earth Rally already uses stays,
with the strips now given back on every way out of a run.

Not in 1.3.0: the self-test's co-driver check, which moves to 1.4.0 with the rest of the co-driver work. Note that
until it is done `tools/selftest.py` exits 1 on every run, so it is a report to read rather than a gate to trust
(docs/plan-1.3.0.md says what it would take to make it one meanwhile).

Done: on a clean PC, a dropped-in map's stages drive without a recce, with no Python installed. **Released
2026-11-13.** Step 1 (version checks), step 2 (pre-loading before the start) and step 4 (folders, the automatic ATC,
the late-start penalty) were not reached and are now 1.3.2, which is what step 4 said would happen if the auto recce
needed the time. It did.

## 1.3.1: the auto recce fetches what it needs

The full plan is docs/plan-1.3.1.md.

1. Measure the box against the corridor over the 116 stages here: it decides whether the box form of area_add is a
   fallback worth having, and it builds nothing.
2. Upstream, into the pull request that is already open rather than a second one: explicit points on area_plan and
   area_add, and api.preloadRoute over them -- with a mod-to-server-and-back test, which 1.3.0 did without and paid
   for four times over.
3. The mod asks for the stretch its coverage record says is missing, behind has('preloadRoute'), and the player says
   yes to the download first.
4. The screen (**mock-up first**): downloading as a phase in front of matching; a fifth ending for a refused
   download.

Done: a map dropped in for ground never driven matches its stages, having asked first. **Released
2026-11-14.**

Two things went differently from the plan above and are worth keeping. Step 2's `api.preloadRoute` was not written:
`area_plan` / `area_add` with explicit points is the whole of what was needed, so the upstream change is two calls
and not three -- less to ask of TecnaGamer and less for him to maintain. And step 3's `has('preloadRoute')` became
`has('areaRoute')` for the same reason. Step 4's four phases became one button, at the user's direction: price, ask,
download, go, match, with every press doing the same thing.

## 1.3.2: the first stage goes right

Six contained items, in the order that makes each one smaller. No new unknowns, and nothing here needs BeamNG.Earth
to change, so unlike 1.3.0 and 1.3.1 this version can be finished without waiting on anyone.

1. **Version checks at startup (23).** First, as it was first in 1.3.0's plan, and for the same reason: it protects
   everything after it, and a mod that says plainly "BeamNG.Earth changed under me" is worth more than a mod that
   half-works. Small, offline-testable.
2. **The no-ATC start guard (`docs/notes-1.3.0.md` #1).** Set the car down beyond the start zone rather than inside
   it, and do not accept "stopped on the line" until the car has moved since it was placed -- the same two moves
   `M.DRIVEN_THERE_MIN_M` already makes on the ATC path. Before the automatic ATC, not after: it is the actual
   reported bug, it is a handful of lines, and it is the honest fix for anyone who keeps a stage without controls.
   **One question for the user first** (asked in the notes, still unanswered): after you drive up and stop on a
   no-ATC stage's line, is it still a flat 12 s (`NO_ATC_START_S`, which exists so the co-driver's 10-second call
   fits), or a real start minute as checking in gives you? The guard is the same either way.
3. **The automatic ATC (3).** ~50 m before the start, walked back along the road -- so every stage starts the same
   way and the special case above is retired rather than maintained. Uses the matched line's own geometry, which
   every stage now has.
4. **No penalty for a late start.** A new minute instead, as a real rally does. Small, and it stops the world's
   loading from costing time, which is the same complaint pre-loading answers from the other side.
5. **Folder-based import (4).** Three of the twelve rallies here came in as one "Main Route Book"; the fixture for
   that is a real file on this machine, so it is testable offline before it is seen in game.
6. **Stage pre-loading before the start (21), mock-up first.** The corridor loaded while you wait at the control,
   with a loaded % on screen and the start available whenever you want it. Last because it is the only M in the
   list and because 1.3.1's downloader is the machinery it stands on -- `areaPlan` / `areaAdd` / `areaStatus` over
   the stage corridor is already written, tested and in a release; this is a second caller of it with a different
   trigger and a screen of its own.

Done: a map with folders and no ATCs imports, every stage has an arrival control, a slow world costs no time, and
the user drives one from the import folder to the finish without touching anything else.

## 1.4.0: the co-driver

0. The self-test's co-driver check (carried from 1.2, deferred from 1.3.0): `drivelineRoute:setVehicleTracker()` is
   the lead -- a duck-typed tracker reporting a synthetic speed and position would drive the whole pacenote
   pipeline with no real vehicle. It belongs here: a test that listens for pacenotes is worth most in the version
   that changes them, and it gates every change below. docs/plan-1.3.0.md has the findings and what was tried.
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

1. Course tape (5) and junction direction signs (6) from the junction data the auto recce finds.
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
