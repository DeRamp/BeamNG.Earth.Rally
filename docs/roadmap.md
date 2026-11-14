# Earth Rally roadmap

Drafted with the user, 2026-11-13; 1.3.1 and 1.3.2 released 2026-11-14. Each version has one theme; a
version is done when it has been driven in game.
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
| → | The three it did not reach: the automatic ATC **dropped**, pre-loading and the late-start penalty moved to **1.6.0** (the user, 2026-11-14) | |

## 1.4.0: the co-driver

Pacenotes worth trusting.

| Item | Size |
|---|---|
| Pacenote generator overhaul: crests, jumps, cautions from the height profile (2) | L |
| Co-driver settings: call timing, detail, voice (26) | M |
| The self-test hears the co-driver (carried from 1.2): a tracker of our own through setVehicleTracker, so a stage walked by the test calls its notes | S |

## 1.5.0: make and share stages

Players build their own stages and pass them around.

| Item | Size |
|---|---|
| The Earth Rally file: one shareable file with stages (line, heights, controls, notes), the rally and loops; what imports make and the game loads (19) | M |
| Rally setup mode: recce-drive any roads to make a stage, place your own ATC, start, finish and stop (18) | M |
| In-game editor, top-down on the map: draw or reroute stages, drag controls, edit existing stages (11) | L |
| Local leaderboards per rally file, friends' times through shared files (20) | S |

## 1.6.0: on the stage

The stage looks and feels like an event.

| Item | Size |
|---|---|
| Course tape across side roads not taken (5) | M |
| Junction direction signs (6) | S |
| Ghost car and replays (27) | M |
| Atmosphere: spectators, marshals, radio points (29) | M |
| Stage sketches and height profiles (15) | S |
| Stages wider than ~26 km (8) | L |
| Stage pre-loading *before the start*: the corridor loaded while you wait, a loaded % on screen, start any time (21). The on-demand half shipped in 1.3.1; this is the half that runs as you sit at the control. Moved here from 1.3.3 (the user, 2026-11-14) | M |
| No penalty for a late start, just a new minute, as a real rally does. Also takes a permanently-zero row off the results card. Moved here from 1.3.3 (the user, 2026-11-14) | S |

## 1.7.0: the full rally

From a single stage to a whole event.

| Item | Size |
|---|---|
| Run the whole rally: stage order, running total, timecard (9) | M |
| Itineraries: loops, road sections with target times, early / late penalties (10) | M |
| Service: marked service areas, repairs in full-rally mode (24) | M |
| Rally-mode recovery: the game's resets off on stage; prompts for back on stage after an off and a full reset when broken, with the controls shown (17) | S |
| Weather and time of day per stage (25) | M |
| Split times (15) | S |

## 2.0.0: public release

Ready for players who have never heard of it.

| Item | Size |
|---|---|
| Install and update from BeamNG.Earth's Add-ons page (22) | S (the listing comes with 1.3.0) |
| A starter pack of stages (as Earth Rally files) and a tutorial (22) | M |
| Championship / season mode with points (28) | M |
| Pick your rally car and setup; a recce car (12, 13) | M |
| A recovery vehicle (14) | M |
| Online leaderboards: decide then (server, anti-cheat) (20) | L |

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
  pre-loading moved to 1.6.0, and 1.3.2's no-ATC start fixed the part of it that hurt.)
- 1.3.2 before 1.4.0 (the user, 2026-11-14): contained items, every one something a player meets in their first
  stage -- against 1.4.0's generator rewrite, the largest thing left before 1.5.0.
- **There is no 1.3.3** (the user, 2026-11-14). It was drafted to carry what 1.3.2 did not reach, and then
  emptied: the automatic ATC and the start-minute question were dropped (see Dropped), and pre-loading and the
  late-start penalty moved to 1.6.0. So 1.4.0 is next, and the 1.3 line is finished.
- 1.4.0 is the pacenote overhaul on its own (split from 1.3.0, the user, 2026-11-13): large, and best tested on
  the matched lines 1.3.0 gives everyone, which 1.3.1 made reachable on ground nobody has driven.
- 1.5.0's rally file is the base for the editor, setup mode, leaderboards, the starter pack and full rallies, so it
  comes before them.
- 1.6.0 (on the stage) before the full rally (the user, 2026-11-13): it builds on junction data (1.3.0's auto recce)
  and the rally file.
- 1.7.0 needs the rally file (itineraries, service areas live in it).
- 2.0.0 gathers what a newcomer needs, once the content and tools exist to fill a starter pack.
