# Earth Rally roadmap

Drafted with the user, 2026-11-13; 1.3.1 and 1.3.2 released 2026-11-14. Each version has one theme; a
version is done when it has been driven in game.
Planned features carry no number: `+name`, built on the release named, and numbered (the next minor) only when
the owner merges and releases them (CLAUDE.md, "Feature builds"). Older entries kept their numbers.
Sizes are rough (S: a session, M: a few, L: a week or more of sessions). Numbers in brackets are the roadmap items
from the planning list.

## 1.2.2: the stage display works (released)

| | Item | Size |
|---|---|---|
| ✔ | The on-stage display reaches the game (start time, clock, progress bar, off-route card, finish, results) | built |
| ✔ | The layout hold leaves the radial menu alone | built |
| ✔ | Long rally names cut short in the menu | built |
| | Start tree board blank after a new start minute (7) | S |
| ✔ | Automated in-game test and install check (30): `tools/selftest.py` | built |
| ✔ | Housekeeping: our BeamNG.Earth clone moved to its dev branch | built |

## 1.3.0: stages for everyone (released 2026-11-13)

Any imported map drives with no recce and no Python, and starts when you're ready.

| | Item | Size |
|---|---|---|
| ✔ | The auto recce for every player (1): a dropped-in map's stages drive with no recce and no Python -- in the mod's own Lua, over `api.roadGraph`, not a companion add-on | built |
| → | Everything else that was in this version is now **1.3.2** below: the auto recce took the time | |

## 1.3.1: the auto recce fetches what it needs (released 2026-11-14)

One Auto recce button: it prices the map data along the stage, asks before fetching anything, takes you to the
start, and matches the line. Release notes in docs/release-1.3.1.md.

| | Item | Size |
|---|---|---|
| ✔ | The box measured against the corridor over the 116 stages here | built |
| ✔ | Upstream, into the open pull request rather than a second one: explicit points on `area_plan` / `area_add`, as modding API 1.9 ([#1249](https://github.com/TecnaGamer/BeamNG.Earth/pull/1249), waiting on TecnaGamer) | built |
| ✔ | The auto recce asks for what is missing, with the player saying yes to the download first (`areaPlan` gives the figure without fetching) | built |
| ✔ | The screen for it: downloading as a phase in front of matching, and an ending for "asked, and told no" | built |
| ✔ | **Reset** replaces Auto recce once a stage has a line; Gain / Loss tiles on the stage page | built |

**Known, carried:** the estimate can over-ask -- it counts the download tool's items over a corridor dilated by two
map cells, wider than the road graph reads, so a stage that would have matched from what you already have can still
be offered a download. One press on fully-cached Maryhill answers it; if it does over-ask, the fix is to what gets
asked for, not to the button.

## 1.3.2: the first stage goes right (released 2026-11-14)

The start that counted itself down before the player was ready, three rallies wearing the same name, and a mod
that said nothing when the two projects under it moved on. Release notes in docs/release-1.3.2.md.

| | Item | Size |
|---|---|---|
| ✔ | A stage with no ATC starts its countdown the moment it spawns you (`docs/notes-1.3.0.md` #1): the car was set down 4 m back inside a 12 m start zone, so "stopped on the line" fired at once. **90 of the 116 stages here have no ATC in their map**, so this was the ordinary path, not an edge of it | built |
| ✔ | Version checks at startup, a clear message when BeamNG or BeamNG.Earth changed (23) | built |
| ✔ | Naming a rally from its map file (4): three of the twelve rallies here came in as "Main Route Book". Written on this roadmap as "maps that group stages in folders import properly" -- the folders were never the problem, the name was | built |
| ✔ | "Quick start on the line" dropped from Settings (the user, 2026-11-14): it did the thing the no-ATC start was fixed to stop doing, kept as an option, and the sharing of one code path between the two is most of why that bug existed | built |
| → | The three it did not reach: the automatic ATC **dropped**, pre-loading and the late-start penalty moved to **on the stage** (now 1.6.0) (the user, 2026-11-14) | |

## 1.4.0: rally files (released 2026-11-14)

Seasons, rallies and stages in nested menus with cover pictures, real results on every stage's leaderboard, and
season standings, from a rally pack dropped into the import folder. Built on its own branch alongside on the stage,
and released first, so every version after it moved up one (the user, 2026-11-14). Release notes in
docs/release-1.4.0.md; the format in docs/rally-file.md.

| | Item | Size |
|---|---|---|
| ✔ | The rally pack: a season, rally or stage manifest with maps, itinerary, results, rules and pictures, in a folder or a zip; ids that survive a rename (the first part of 19) | built |
| ✔ | Nested menus: Rallies > season > rally > stage, with covers; the menu opens where it was left | built |
| ✔ | Local leaderboards against the real results (20): the top 10, and the crews either side of you; a time only placed on a line within 5 % of the official distance | built |
| ✔ | A rally total and its place; season standings from each rally's finishing order (the first part of 28) | built |
| ✔ | The pause menu's tab down to one **Rally menu** button; the Settings page's HUD preview button gone | built |

## 1.5.2: the time control stays (released 2026-11-14)

A patch: Run stage no longer skips the ATC after Auto recce, Go to start or a stopped Recce. Auto recce lands at the
ATC, and a car on the stage line is never taken for one driven up to the board; docs/notes-1.5.2.md has the detail
and what is left open.

## 1.5.1: the menus clear (released 2026-11-14)

A patch: BeamNG.Earth's imgui strips no longer draw over the Escape menu or the rally menu. It is BeamNG.Earth's bug
(its menu check misses 0.40's `pause` route), and the fix is a stopgap of ours to remove once BeamNG.Earth fixes it;
docs/notes-1.5.1.md says how to tell, and what to remove.

## 1.5.0: the co-driver (released 2026-11-14)

Pacenotes worth trusting, from the line and its heights. Built on its own branch alongside on the stage and
released first, so on the stage moved up to 1.6.0 (as the rally files did for 1.4.0). It was 1.6.0, 1.5.0 and
1.4.0 before that. Driven by the user four times on the way; release notes in docs/release-1.5.0.md, every call and
its figures in docs/pacenotes-1.5.0.md.

| | Item | Size |
|---|---|---|
| ✔ | Pacenote generator overhaul (2): hairpin / square, tightens / opens, chicane, twisty, long sweepers, cautions, crests from the driver's sight, "down" at a downhill's top, jumps, dips, hills, narrows, over finish; every call fitted to what the player's co-driver voice can say | built |
| ✔ | Bridges on lines matched in the game: `tools/auto_recce.py --bridges-only`, kept by a later recce | built |
| → | Not reached: co-driver settings (call timing, detail, voice) (26), and the self-test hearing the co-driver (carried from 1.2). Where they go is for the user to say | |

## 1.6.0: on the stage (released 2026-11-15)

The stage looks like an event: course tape, direction boards, junction marshals, radio and medical points and
spectator areas, all from the game's own rally props, from the auto recce's junctions and the organisers' map points.
Driven by the user on Overmountain; findings and fixes in docs/notes-1.6.0.md, the design in
docs/plan-1.6.0-stage-dressing.md.

| | Item | Size |
|---|---|---|
| ✔ | Course tape across side roads not taken (5) | built |
| ✔ | Junction direction signs (6) | built |
| ✔ | Atmosphere: spectators, marshals, radio points (29), from the organisers' map first, placed by rule otherwise | built |
| → | Not reached, for the user to place: ghost car and replays (27), stage sketches and height profiles (15), stages wider than ~26 km (8), stage pre-loading before the start (21), no penalty for a late start | |

## 1.6.2: the loop holds (released 2026-11-15)

Every open issue (#5-#19) fixed. The owner called the enhancements among them gameplay-loop bugs to fix before the
alpha MVP (2026-11-15), and moved the Recce notes update milestone into it as fixes to 1.5.0. Notes, test plan and
the owner's findings in docs/notes-1.6.2.md.

| | Item | Size |
|---|---|---|
| ✔ | Pacenotes: open sixes and long bends called (#6, #7), obvious junctions only (#10), caution after long straights (#11), short kinks a grade more open (#12) | built |
| ✔ | Dressing: ATC and stop on the road (#5), tape parallel at acute junctions (#9) | built |
| ✔ | Menus: rally menu pauses (#13), controller (#14), finish time in the top bar (#17), Close on the results card (#18) | built |
| ✔ | Route to stage gets the stage ready as you arrive (#19) | built |

## 1.7.0: full stage rally support (released 2026-11-16)

From a single stage to a whole event: moved ahead of make and share stages (the owner, 2026-11-15). The design is
the full-rally GDD (draft 2, kept with the owner's rally data: it carries real crews and times). The MVP chains the
stages: road sections skipped, saved only at service. Plan in docs/plan-1.7.0.md, test plan in docs/notes-1.7.0.md.

| | Item | Size |
|---|---|---|
| ✔ | Run the whole rally: stage order from the event file, services and overnights, the time card, the running total and places against the real National field (9) | built |
| ✔ | Two modes: Realistic (Super Rally on a recovery, no restarts) and Casual (free recoveries and restarts) | built |
| ✔ | Service: full repair at each service and overnight; damage carried between them; saved only there (24) | built |
| ✔ | Rally-mode recovery: the game's resets and teleports off for the whole rally, Backspace is the rally's (17) | built |
| ✔ | Your finished rallies on the rally's Results tab, overall and in class, the mode marked | built |
| | Itineraries driven: road sections with target times, early / late penalties (10) | M |
| | Shakedown and recce in the loop; a pad default for the rally's recovery | M |
| | Weather and time of day per stage (25) | M |
| | Split times (15) | S |

## 1.8.0: leaderboards

Online leaderboards and opt-in stats through the Earth Rally Leaderboards helper, and install through BeamNG.Earth's
Add-ons page with the ARA 2026 season included. Design in docs/online-board.md and docs/research-online-leaderboards.md.

| | Item | Size |
|---|---|---|
| ✔ | Leaderboards per stage and class (Stock / Open) through the helper beside the game (20; #72-#75) | built |
| ✔ | Opt-in stats and error reports through the same helper (#76) | built |
| ✔ | Install and update both from BeamNG.Earth's Add-ons page; ARA 2026 in the mod (22) | built |

## 1.9.1-alpha: play from the main menu

The owner asked for it, 2026-11-18. Released 2026-11-19.

| | Item | Size |
|---|---|---|
| ✔ | An Earth Rally tile on the game's Play > Rally page that opens the menu with no level loaded | built |
| ✔ | BeamNG.Earth loads only when a stage is driven or a rally started, then the button runs | built |

## 1.9.0: make and share stages

Players build their own stages and pass them around.

| Item | Size |
|---|---|
| The Earth Rally file: one shareable file with stages (line, heights, controls, notes), the rally and loops; what imports make and the game loads (19). 1.4.0's rally pack is the reading half: this is the writing half, and lines, heights and notes in it | M |
| Rally setup mode: recce-drive any roads to make a stage, place your own ATC, start, finish and stop (18) | M |
| In-game editor, top-down on the map: draw or reroute stages, drag controls, edit existing stages (11) | L |
| Friends' times through shared files (20; local leaderboards against real results came in 1.4.0) | S |
| A pop-up on menu open when the Leaderboards helper does not answer: how to install it, "Don't show this again" until a new version (#77; built on `feature/helper-prompt`) | S |

## 2.0.0: public release

Ready for players who have never heard of it.

| Item | Size |
|---|---|
| A starter pack of stages (as Earth Rally files) and a tutorial (22) | M |
| Championship / season mode with points (28) | M |
| Pick your rally car and setup; a recce car (12, 13) | M |
| A recovery vehicle (14) | M |
| Online leaderboards: anti-cheat, past the helper's checks (20) | L |

## Out of scope for now

- Multiplayer (BeamMP): BeamNG.Earth's shared world origin conflicts with ours.

## Dropped

Decided against, with the reason, so they are not proposed again.

- **An ATC added to stages that have none** (planning item 3), dropped 2026-11-14 by the user. It was to retire
  the no-ATC start path by giving every stage a control. On real organisers' maps that is not a tidy-up but a
  change to nearly everything: **90 of the 116 stages here have no arrival control**, so it would have added a
  control and a check-in wait to almost every stage anyone drives. 1.3.2's no-ATC start already gives those
  stages a start worth having, so the special case stays and is no longer temporary.
- **A real start minute on a stage with no ATC**, dropped 2026-11-14 by the user. It stays a flat 12 s
  (`runner.NO_ATC_START_S`, which exists so the co-driver's 10-second call fits). The question only mattered as a
  companion to the automatic ATC above.
- **Watching for the menu losing its styling** after BeamNG.Earth's map page has been opened: not a roadmap item.
  It is intermittent, it is upstream of both mods, and `reloadUI()` clears it; `docs/notes-1.3.2.md` #1 has the
  investigation and what each reading of the probe would mean if it comes back.

## Why this order

- 1.3.0 first because it removes the biggest barrier: before it, every stage needed a recce driven. (The slow
  start seen on SnoDrift was to be fixed by pre-loading and an automatic ATC; the ATC has since been dropped and
  pre-loading moved to on the stage (now 1.6.0), and 1.3.2's no-ATC start fixed the part of it that hurt.)
- 1.3.2 before the co-driver (the user, 2026-11-14): contained items, every one something a player meets in their
  first stage -- against the pacenote generator's rewrite, the largest thing left before the rally file.
- **There is no 1.3.3** (the user, 2026-11-14). It was drafted to carry what 1.3.2 did not reach, and then
  emptied: the automatic ATC and the start-minute question were dropped (see Dropped), and pre-loading and the
  late-start penalty moved to on the stage. So the 1.3 line is finished.
- 1.4.0 (rally files) released ahead of on the stage (the user, 2026-11-14): it was built alongside it on a branch
  of its own and finished first. The menus and the leaderboards are the parts of the rally file a player sees, and
  `+share`'s writing half builds on the same format.
- 1.5.0 (the co-driver) released ahead of on the stage (the user, 2026-11-14): built alongside it on a branch of
  its own and finished first, as the rally files were. Its height reading and sight crests are what on the stage's
  height profiles and sketches can draw on.
- 1.6.0 (on the stage) before the rally file (the user, 2026-11-14; it was 1.6.0, then 1.4.0 and 1.5.0). Course tape and
  junction signs stand on the junction data 1.3.0's auto recce already finds, so the heart of it needs nothing from
  later versions. It was first placed after the rally file because it was said to build on that too; in its new
  place, anything here that would have lived in the file (a ghost's run, most likely) has to be kept on this
  machine per stage until `+share` can carry it -- to settle when 1.6.0 is planned.
- The co-driver was the pacenote overhaul on its own (split from 1.3.0, the user, 2026-11-13): large, and best
  tested on the matched lines 1.3.0 gives everyone, which 1.3.1 made reachable on ground nobody has driven.
- The full rally (now 1.7.0) ahead of make and share stages (the owner, 2026-11-15): 1.4.0's rally pack already
  reads the itineraries and service areas it needs, so it no longer waits on the writing half.
- Leaderboards (1.8.0) ahead of make and share stages (the owner, 2026-11-18).
- 1.9.0's rally file is the base for the editor, setup mode and the starter pack, so it comes before them.
- On the stage before the full rally (the user, 2026-11-13), and now before everything after 1.3 (2026-11-14).
- 2.0.0 gathers what a newcomer needs, once the content and tools exist to fill a starter pack.
