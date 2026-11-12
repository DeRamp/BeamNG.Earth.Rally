# Earth Rally 1.1.0 plan

Theme: polish what 1.0.0-alpha has, and run stages without a recce (notes from the game's own roads).

## Bugs

| # | Bug | Where | Status |
|---|---|---|---|
| 1 | The co-driver keeps calling notes after the flying finish | runner stepRunning | Fixed (test added) |
| 2 | Props at the stop control (and any site well above or below the car when it comes within 350 m) are set at the car's height: buried or floating. The ground search only looks 8-25 m up and 40-80 m down from the car's height and rejects anything over ~27 m off; then it falls back to the car's height. Likely why the stop tent is not seen | props spawn / ground | Open |
| 3 | Pressing "Save recce" before 90 % throws the whole recording away (rec is cleared before the share check), so you cannot carry on driving | recce.stop | Open |
| 4 | The window re-reads every stage's recce file (and the selected stage's results) from disk every frame: frame drops once several stages have recces (a 40 km recce is ~10,000 points) | main drawWindow, events.recce | Open |
| 5 | Reaching the start line in the last 5 s before your start time counts as late: a new start time and +10 s, though you were not late | runner stepToStart (`now > startAt - 5`) | Open |
| 6 | Releasing the control-zone brake sends brake 0 to the car, overriding the player's own held brake (keyboard): the car can roll at the ATC, and at the start after the T-5 release, where 1.5 m of rolling is a jump start | runner brakes / zoneRelease | Open (check in game) |
| 7 | Signs not lined up with the road (user, 2026-11-12). A control's props all take one direction: the nearest road-map edge at the control's spot, and are laid out on a straight line from there. (a) Offsets along the road follow that tangent: the yellow advance boards 150 m before the flying finish and 50 m before the ATC stand in the trees on a winding road, tents a little off on bends. (b) At a junction the nearest edge can be the side road: the whole site turned to it. (c) No road on the map: ATC / stop face the straight line to the start / from the finish. (d) ATC / stop look for the road at the car's height from up to 350 m away. Fix: each object placed on its own: start and flying finish by walking the stage line to the object's distance and taking the line's direction there (road map for the width only); ATC and stop by walking the road map from the control, at junctions taking the edge best aligned with the expected direction, not the nearest; heights from the road map's nodes (also bug 2) | props spawn, runner setupProps | Open |
| 8 | Skipping the ATC (drive straight to the start) gives a 12 s start with no penalty: faster than checking in | runner stepToAtc 'missed' | Open |
| 9 | After a finish the stage layout (pacenote cards) and the boards stay until you press Close | runner finish / main | Open |
| 10 | Progress on the stage line can jump to another part of the line where the stage passes close to itself (Founders super special: 18 m apart at 2.4 and 4.1 km; Dayton 126 m; Wildcat 138 m). The recce searches the whole line every frame; the run does when more than 60 m off the line, which could finish a stage early | recce.update, runner.progress | Open |
| 11 | A car reset or recovery during a recce adds the jump to the recorded line and length | recce.update | Open |
| 12 | The recce records from wherever it was started, even far from the stage start | recce.start / update | Open |
| 13 | The runner's header comment says "next full minute" (it is the next half minute) | runner.lua | Open |

## Polish

- The release zip includes LICENSE.
- `tools/install.py` and the release zip can both be in the mods folder: two copies load. Warn about it.
- The stage layout is a copy of BeamNG.Earth's layout at the time of packaging; a BeamNG.Earth update to its layout
  leaves ours stale. Build it at runtime, or take Earth's layout and add the pacenote app in game.
- The importer: open .kmz directly; stage names with a prefix like "SS1 Kuhnle" do not match "Kuhnle Start".
- Tests: nothing covers recce.lua, props placement heights or events caching.

## Start-line hold (auto brake)

The user (2026-11-12): drop the brake release 5 s before the start; hold the clutch until the start and keep the 30 %
brake, or use launch control where the car has it.

Now: stopped on the start line, the car is frozen (the game's setFreeze) and the brake let go; at T-5 the freeze is
released, and moving 1.5 m after that is a jump start. A frozen car cannot rev, and on a slope the released car can
roll into a jump start.

New behaviour, from stopping on the line until GO:
- **No freeze.** The brake held at 30 %, re-applied every frame (a tap of the player's own brake key otherwise sets it
  back to 0: the game's input keeps only the last value; also bug 6).
- **Manual gearbox:** the clutch held in (100 %) as well, so the player can select first and rev without moving.
- **Launch control where the car has it** (the game's `twoStepLaunch` vehicle controller: Autobello, Barstow, Bastion
  and others): switched on while staged. It arms with the car stopped, throttle on and the brake at 20 % or more on
  a keyboard, 80 % on an analog throttle (pedals, gamepad), and holds the revs at its RPM; it lets go when the brake
  goes to 0. So the brake is held at the arming level (30 % on keyboard, 80 % on analog), and the controller is set back
  to how the player had it after the start.
- **DCT / automatic gearboxes:** the brake hold alone; their own throttle-plus-brake launch does the rest.
- **At GO:** brake and clutch released together in the same frame as the GO call. The clutch let out by the game's
  own auto-clutch on a keyboard, by the player's pedal on a wheel with a clutch.
- **Jump start:** still moving more than 1.5 m from where the car stopped, before GO (the hold makes a roll unlikely).
- The time control and stop control zones are unchanged: 30 % brake until stopped, then let go.

To check in game: which gearbox a car has (manual / sequential / DCT / automatic) and that the clutch input holds on
each; that re-applying the brake every frame does not fight a wheel's pedals badly; the two-step arming on keyboard
and on a gamepad; a steep start line (does 30 % hold the car with the clutch in?).

## Player UI

**Designed with the user, screen by screen** (the user, 2026-11-12: "work with me on the UI"): mock-ups first, agreed,
then built, then tried in game and adjusted. Nothing in this section is final until the user has seen it.

Aim: clean, fun, makes sense to a player who has never seen the mod. One thing on screen at a time, the game's own
look, no developer numbers. The current ImGui window stays as a developer panel (off unless turned on in settings).

**What the game gives us** (BeamNG.drive 0.40.5):
- Vue UI mods (`/ui/ui-vue/mods/<mod>/`, the game's `ui/ui-vue/mods/README.md`): full-screen pages of our own
  (routes), a tab in the pause menu, the game's own components (`BngButton`, cards...). BeamNG.Earth's settings and map
  are made this way.
- The game's rally HUD apps, all fed by one data stream (`rallyLoop`, sample frames in the game's
  `ui/modules/apps/rallyLoop/mockdata/`): **RallyDashboard** (road-section instructions: next control, distance,
  speed limit, stopped / frozen), **RallyCountdown** (the start countdown and GO), **RallyStageProgress** (progress
  bar with km), **RallyStageTiming** (stage clock, splits), **RallyTimecard**, the rally clock and penalties, plus
  **RallyVisualPacenotes** (already used). Fed from Lua with the same fields, they look and behave as the game's
  own rally mode.

**Screens (first ideas, to work through together)**

1. *Earth Rally menu* (a full-screen page; opened from its pause-menu tab, Ctrl+Alt+K, and after a stage):
   - **Rallies**: one card per rally: name, place, stages, total km, how many stages driven, best total.
     An **Add a rally** card: what to do (drop the map in the folder), **Open import folder**, the last import's report.
   - **Stage select** (a rally opened): its stages in order (SS1, SS2...), each with a small drawing of its shape, km,
     surface, a status (Ready / Recce needed), best time. Pick one for the stage page.
   - **Stage page**: the stage's map shape with start and finish, elevation profile, length, surface, corners
     ("62 corners, mostly fast"), your best and last runs. Big **Drive stage** button; **Recce** beside it.
   - **Settings**: units (km / miles), time controls on or off (quick start straight on the line), control-zone
     brake on or off, developer panel on or off.
2. *Driving to the stage* (road section, from Drive stage until the start line): the dashboard: "Next: SS3 Kuhnle,
   8.4 km gravel", distance to the time control, what to do there; route arrows as now.
3. *At the time control*: checked in at 10:42:30, your start time 10:43:30, a countdown to it, "Move up to the start".
4. *On the start line*: the big countdown (30 s, 10 s, 5-4-3-2-1, GO) with the co-driver; a jump start shown.
5. *On the stage*: progress bar (km done / total), stage clock, splits (about every quarter, against your best),
   pacenote cards. Nothing else.
6. *Flying finish*: the time big, penalties, against your best ("-3.4 s, new best!").
7. *Stop control / stage done*: a results card: time, penalties, best, your runs on this stage; **Next stage**,
   **Retry**, **Rally menu**.
8. Messages: the game's own toast style instead of plain text lines.

**Start clock with picture-in-picture** (the user, 2026-11-12: "add the timer prop to the rally start ... it should
zoom in with a picture in picture screen on the timer so you have a good visual on when to start"):
- The game's own system (`gameplay_rallyStartClock`, 0.40.5): it finds every start tree prop
  (`/art/shapes/race/rally/rally_assets/s_rally_start_tree.dae`, a TSStatic) and draws its LED board (time of day,
  stage label, countdown, red / amber / green). During a countdown, the tree within 20 m of the rally engine's start
  line (`getSSStartLinePos`: our SS_start_line) gets a picture-in-picture view at the top of the screen, its border in
  the light's colour, lingering 1.5 s after GO.
- It is fed by `extensions.hook('onRallyDataUpdated', data)`: `activeState = 'countdown'`,
  `rallyClock.wallClockSecs` (our rally clock), `countdownData.timeUntilLaunch` and `state` (`'launched'` at GO); then
  another activeState after GO. The same data as the rallyLoop HUD stream, sent together.
- Today we put down `s_rally_start_clock_display.dae` (the display panel alone): the system ignores it. Replace it with
  the start tree, beside the road at the start line (stock stages: 3-6 m from the start position), facing the car.
- From the ATC on, the board shows the rally clock, so the player can read their start time on it as they arrive.
- To check: the picture-in-picture camera's angle on our placement (the clock type's own getView, else from the start
  line towards the clock), and with BeamNG.Earth's render settings.

**HUD preview in game** (the user agreed, 2026-11-12): a developer command and a developer-panel button that play
sample frames through the real HUD in the stage layout, over the current road, without driving: road section to the
ATC, checked in, moving up, countdown (with the start clock and its picture-in-picture), stage under way with
progress and splits, flying finish, stop control. Built from the game's own sample frames
(`ui/modules/apps/rallyLoop/mockdata/`) with our stage names and distances. The user steps through it and says what
to keep, move or drop. Then web mock-ups for the cards the stock apps do not have (next stage, results).

**Later in this version, if it fits**: *Run the rally*: the stages in the rally's order with a running total time
and a timecard; between stages, the next stage's info and a teleport to its ATC (real road sections come with
itineraries).

**Work**
- Mock-ups of each screen for the user (step 1), then the menu (Vue page + pause-menu tab), then the HUD (rallyLoop
  stream from runner.lua, the stage layout with the stock rally apps), then results and messages; in game after each.
- Check each stock app against its sample frames before relying on it (which fields it needs, how it hides).

## Importer in game (no command line)

Drop a rally's map file into a folder; the mod imports it by itself. Python is no longer needed to play.

**What the game gives us** (checked in BeamNG.drive 0.40.5's own Lua):
- `ZipArchive():openArchiveName(path, 'r')` and `:readFileToMemory(name)`: .kmz files opened directly.
- `libs/slaxml/slaxml` (an XML parser, used by the game's xlsx reader); a small KML/GPX reader of our own is also an
  option (a narrow subset: Placemark, name, LineString / Point coordinates, trk / rte / wpt), easier to test offline.
- The `onFileChanged(filename, type)` hook (the game watches its user folder): a file dropped in is seen at once.
- `Engine.Platform.exploreFolder(path)`: an "Open import folder" button.

**How it works for the player**
1. `<BeamNG user folder>/current/earthRally/import/` is made when the mod loads. The window has an **Open import
   folder** button, and says where it is.
2. Drop `.kml`, `.kmz` or `.gpx` files in. The mod imports each new or changed file when it loads, when one is
   dropped in while the game runs, and from a **Re-scan** button. A message says what happened: "Imported Olympus
   Rally 26: 9 stages".
3. The rally's name is the map's own (the KML document's name), else the file's name.
4. Each rally in the window has an **import report**:
   - every stage with its length and its controls (ATC, start, flying finish, stop) found or missing;
   - points that matched no stage, with the stage whose name is closest ("Kuhnel Stop: did you mean Kuhnle?");
   - controls far from their line, gaps between pieces, stages too wide to run.
5. Fixes in the window, kept in an overrides file beside the event so a re-import keeps them: give an unmatched
   point to a stage and a role, reverse a stage's direction, hide a stage, rename the rally.
6. The original files stay in the folder (delete one to remove its rally, or a **Remove** button).

**Work**
- `importer.lua`: a port of tools/import_kml.py (reading, stage and control matching by name, stitching pieces,
  driving direction, enclosing circle), pure functions so the offline tests run it; tests on the two real files'
  shapes and on hand-made KML / KMZ / GPX samples (namespaces, CDATA names, folders, MultiGeometry).
- Name matching made more forgiving: "SS1 Kuhnle" and "Kuhnle Start", typos (closest name within a small edit
  distance, reported, not silently used).
- Folder scan with an index (file name, size, modified time) so only new or changed files are imported.
- The window: import folder button, report, fixes.
- `tools/import_kml.py` stays for developers, sharing the same test samples so both agree.

**Road matching after import** (the no-recce notes below) needs the roads of the whole stage, beyond the kilometre
the game has loaded, so it runs on BeamNG.Earth's server. Options:
- A new BeamNG.Earth API call (an upstream pull request): players need nothing. Depends on the maintainer; PR #1183
  is still open with no review (2026-11-12).
- A BeamNG.Earth companion add-on (a Python file BeamNG.Earth runs with its own Python, started with it): also needs
  a listing in its add-on registry, and its packaged app's Python must reach the map data code (to check).
- Until one of them is there: imported stages need a recce, as now, and the window says so per stage.

## No-recce notes

Research (2026-11-12, see the conversation notes; scripts were throwaway probes):

- The game drives on BeamNG.Earth's roads: Overture map cells with every bend rounded to an arc by road class
  (track 15 m, unclassified 30 m, tertiary 50 m). BeamNG.Earth's own Python reads them from its cache, downloading
  missing cells (16 cells for Wildcat in ~3 s).
- OTR's lines were traced on OpenStreetMap: 0.1 m median from the game road. The recce lines are 0.6-0.7 m from it.
- Heights from BeamNG.Earth's elevation data match the recce heights to 0.2 m (a steady offset).
- Corners from the snapped map line against the recce's: 90 % (Maryhill Up) and 94 % (Boyd Loop) found, tightest
  radius median x0.95 / x0.78, angle within 3-5 degrees.
- Olympus lines are hand-drawn (points 30-750 m apart): Kuhnle within 12 m of a road; Wildcat has a 453 m stretch with
  no road on the map.

Work:

1. Importer: read / download the cells along each stage, match the line to the road network (most likely chain of
   connected roads through the organiser's points; unmapped stretches keep the organiser's line and are flagged),
   heights from the elevation data, start / finish placed on the matched line. Stages run with no recce.
2. Mod: the recce becomes optional (refines a stage, fills unmapped stretches). Show per stage whether its line is
   matched, recced or needs a recce.
3. Mod: a "Download stage" button using BeamNG.Earth's saved areas (`beamngEarth_core.areaAdd`, internal: through
   earthAdapter), with progress.
4. Validate on all 18 stages: matched length against the route book's distances; Maryhill / Boyd against their recces.

Later (not 1.1.0): line matching and a stage corridor download as BeamNG.Earth API calls (an upstream PR), so players
need no Python.
