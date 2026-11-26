# Changelog

Format: [`docs/writing-standard.md`](https://github.com/DeRamp/BeamNG.Earth.Rally/blob/main/docs/writing-standard.md). Downloads:
[Releases](https://github.com/DeRamp/BeamNG.Earth.Rally/releases).

## 1.10.4-alpha: reset and Select (2026-11-26)

Works with BeamNG.drive 0.40.6 · [BeamNG.Earth](https://github.com/TecnaGamer/BeamNG.Earth/releases) 1.10+.

### Fixed
* **D-pad right** on a single stage or in a Casual rally puts you back on the stage road, not your last reset point.
* **Back on the road** now repairs the car on a single stage and in a Casual rally.

### New
* **Select** on a pad opens and closes the rally menu during a full rally. Outside a rally it is still the map.
* **Map** on the time card opens the map; **Rally menu** on the map, or Select, takes you back.

### Known issues
* On a stage, the game's own reset (keyboard **R**, PlayStation pads, wheels) is off: use **Backspace**.

## 1.10.3-alpha: skip transit (2026-11-26)

Works with BeamNG.drive 0.40.6 · [BeamNG.Earth](https://github.com/TecnaGamer/BeamNG.Earth/releases) 1.10+.

Road sections can now be skipped from the time card.

### New
* **Skip transit** on the time card: the car is taken to the next control and checked in on time.
* On a timed rally the clock moves on to your due time; a late car stays late.

### Fixed
* After a skip the car lands on the road, facing the way on.
* A skip no longer repairs the car, in Casual or Realistic.

## 1.10.2-alpha: hand-made rally files (2026-11-26)

Works with BeamNG.drive 0.40.6 · [BeamNG.Earth](https://github.com/TecnaGamer/BeamNG.Earth/releases) 1.10+.

Rallies and seasons can now be written by hand in plain text, no JSON needed.

### New
* **Rally files in plain text**: one `rally.txt` per rally beside its map; `season.txt` for a season.
* The running order, timed sections, weather and real results all go in `rally.txt`.
* Spreadsheets work too: `results.csv`, `weather.csv` and `line.csv`.
* Small mistakes are forgiven: names, times, dates and positions are read however they are written.
* Every import writes an **Import report**: open it from **Last import** on the Rallies page.
* **Templates** to fill in: [download them](https://github.com/DeRamp/BeamNG.Earth.Rally/raw/main/templates/Earth%20Rally%20templates.zip). Guide: [making rally packs](https://github.com/DeRamp/BeamNG.Earth.Rally/blob/main/docs/making-rally-packs.md).

### Changed
* JSON rally packs work as before, and now report broken JSON by line and column.

## 1.10.1-alpha: the co-driver's calls (2026-11-26)

Works with BeamNG.drive 0.40.6 · [BeamNG.Earth](https://github.com/TecnaGamer/BeamNG.Earth/releases) 1.10+.

The co-driver's pacenotes are rebuilt from the road's real shape.

### Changed
* **Corner grades** come from the road's own radius, closer to a pro co-driver's notes.
* Every bend you can see gets a call. One long bend is no longer called as a run of short corners.
* **Crests** are found from the ground along the stage after **Auto recce**, not only from the map.
* The first call says how far away its corner is. A stage that starts in a corner calls it.
* A corner behind a crest is called with the crest.
* The **Casual** co-driver grades corners as easy, medium and hard to match.

### Fixed
* A matched stage line that runs out and back along a side road no longer gets calls there.

## 1.10.0-alpha: the rally loop (2026-11-19)

Works with BeamNG.drive 0.40.6 · [BeamNG.Earth](https://github.com/TecnaGamer/BeamNG.Earth/releases) 1.10+.

Full rallies now run to the clock, at each stage's real time of day and in its weather.

### New

#### Time controls
* **Timed road sections**: a due time at every time control, 10 s a minute late.
* **Services, regroups and the finish** have their own time controls.
* **Early check-in penalty** setting: checking in early costs time. Off by default: you wait for your minute.
* The road section's HUD line shows the rally time, the due time and the time left.
* The time card shows each due time, time in and **transit penalties**.

#### Time of day and weather
* Each stage runs at its real date and time, in the weather it had on the day. The ARA 2026 season has it all.
* **Rally's real time and weather** setting: Off keeps your own sky.
* **Weather** on the Drive stage page: Current, Rally day, Clear, Cloudy, Rain, Storm, Snow or Fog.
* The time card shows each stage's weather.

#### Splits and results
* **Split times** at 25, 50 and 75% of the stage, against your best.
* The rally's results show transit penalties, each stage's time and what each stop cost.

#### On the road
* **Traffic on road sections**: On or Off on the rally's start screen.
* The pop-up cards work with a controller and the keyboard.

### Changed
* **Reset penalty**: the game's reset costs 15 s, **Back on the road** 5 s, on the timed stage.
* **Casual** rallies let you reset and recover the car.
* Starting or continuing a rally puts the game back to normal speed.
* In BeamMP, Earth Rally's menu says it is single player only.

### Known issues
* Where the road map near a time control hasn't loaded, the route can bring you in from the wrong side.

## 1.9.4-alpha: missing road segments (2026-11-19)

Works with BeamNG.drive 0.40.6 · [BeamNG.Earth](https://github.com/TecnaGamer/BeamNG.Earth/releases) 1.10+.

A clearer name for stages with a gap in their road.

### Changed
* **Missing road segments** replaces **Recce recommended** on stages where part of the road isn't on the map.
* **Recce stops short** replaces **Recce recommended** when your own recce ends before the finish.

## 1.9.3-alpha: co-driver settings (2026-11-19)

Works with BeamNG.drive 0.40.6 · [BeamNG.Earth](https://github.com/TecnaGamer/BeamNG.Earth/releases) 1.10+.

Set up your co-driver from Earth Rally's settings page.

### New
* **Co-driver** settings: voice, Casual or Professional calls, call timing, spoken calls and calls on screen.
* **Voice** and **Style** lock during a run and change between runs.

### Changed
* **Settings** page tidied: the old time controls note is gone, the Leaderboards text is shorter.

### Fixed
* **Co-driver style** on a new profile matched to the voice the game actually uses.

## 1.9.2-alpha: roads remembered (2026-11-19)

Works with BeamNG.drive 0.40.6 · [BeamNG.Earth](https://github.com/TecnaGamer/BeamNG.Earth/releases) 1.10+.

**Auto recce** is quicker and finds more of the road on stages drawn with rough lines.

### Changed
* **Auto recce** keeps the roads it reads on disk. Recce the same ground again and the car doesn't move.
* **Auto recce** stops less often along the stage: about 30% fewer stops.

### Fixed
* **Recce recommended** on stages that are road all the way, where the organisers' line cuts across bends.

## 1.9.1-alpha: play from the main menu (2026-11-19)

Works with BeamNG.drive 0.40.6 · [BeamNG.Earth](https://github.com/TecnaGamer/BeamNG.Earth/releases) 1.10+.

Start Earth Rally straight from the game's main menu, no free roam first.

### New
* **Play > Rally > Earth Rally** opens the rally menu. BeamNG.Earth loads when you drive a stage or start a rally.
* A full rally started there uses your last car, or pick one in the game's own vehicle picker.
* A saved rally continues only in the car it was started in.

### Changed
* **Home** fits on one screen, with in-game pictures on **Drive rally** and **Drive stage**.
* BeamNG.drive 0.40.6 no longer shows a version warning.

## 1.9.0-alpha: official BeamNG.Earth (2026-11-19)

Works with BeamNG.drive 0.40.5 · [BeamNG.Earth](https://github.com/TecnaGamer/BeamNG.Earth/releases) 1.10+.

Earth Rally now runs fully on the official BeamNG.Earth: no fork needed, auto recce included.

### Changed
* **Auto recce** works on official BeamNG.Earth. It takes the car along the stage to read the roads, then brings it back.
* Install the [official BeamNG.Earth](https://github.com/TecnaGamer/BeamNG.Earth/releases). The DeRamp fork still works, and its auto recce stays faster.

### Known issues
* **Auto recce** on official BeamNG.Earth is slower: about five minutes for a 30 km stage on ground already downloaded.
* It needs BeamNG.Earth's traffic and roads on; with them off it says so and stops.
* A full rally's prep reads each stage in turn; it no longer downloads the next while you drive.

## 1.8.2-alpha: name prompt and stats update (2026-11-19)

Works with BeamNG.drive 0.40.5 · BeamNG.Earth 1.10+ for **Add from GitHub**, e.g. the
[DeRamp fork](https://github.com/DeRamp/BeamNG.Earth/releases) (official 1.10+ works, without the auto recce).

A pop-up to pick your leaderboard name, and opt-in stats that name your own stages and count players.

### New
* With **Leaderboards** on and no name picked, opening the menu asks for one. **Later** hides it until next time.

### Changed
* **Stats** now send the names of your own imported or home-made rallies and stages, not `custom`.
* **Stats** keep a random player number on your computer, sent on its own to count players. **No** deletes it.
* If you said yes to stats before, you are asked again. What is sent: [privacy](https://github.com/DeRamp/BeamNG.Earth.Rally/blob/main/PRIVACY.md).

## 1.8.1-alpha: the leaderboard helper prompt (2026-11-18)

Works with BeamNG.drive 0.40.5 · BeamNG.Earth 1.10+ for **Add from GitHub**, e.g. the
[DeRamp fork](https://github.com/DeRamp/BeamNG.Earth/releases) (official 1.10+ works, without the auto recce).

A reminder to add the leaderboard helper, and leaderboards on from the start.

### Changed
* **Leaderboards** are on by default. Nothing is sent until you pick a name.
* If you saved your settings before, your own **Leaderboards** choice is kept.
* The stats question comes up the first time the menu opens. Off unless you say yes.

### New
* When the **Earth Rally Leaderboards** helper is not running, opening the menu shows how to add it.
* **Got it** hides it until next time; **Don't show again** hides it until the next update.

## 1.8.0-alpha: leaderboards (2026-11-18)

Works with BeamNG.drive 0.40.5 · BeamNG.Earth 1.10+ for **Add from GitHub**, e.g. the
[DeRamp fork](https://github.com/DeRamp/BeamNG.Earth/releases) (official 1.10+ works, without the auto recce).

Online leaderboards, opt-in stats, and an install through BeamNG.Earth's Add-ons page with the ARA 2026 season included.

### New

#### Leaderboards
* **Leaderboards** per stage: your times against other players, in **Stock** (the game's own cars) and **Open**.
* Turn them on in **Settings > Leaderboards**, then pick a name. The stage page switches between **Rally results** and **Leaderboard**.
* The leaderboard opens on your car's class, and loads fresh times each time you come back to it.
* Runs go through the **Earth Rally Leaderboards** helper beside the game. A run it cannot send waits and is sent later.
* [How the leaderboard works](https://github.com/DeRamp/BeamNG.Earth.Rally/blob/main/docs/online-board.md).

#### Stats
* **Opt-in stats** and error reports, asked as their own question when you turn on Leaderboards. Off unless you say yes.
* Stats carry no name or id. What is sent: [privacy](https://github.com/DeRamp/BeamNG.Earth.Rally/blob/main/PRIVACY.md).

#### Install
* Install and update the mod and the helper from BeamNG.Earth's **Add-ons** page: **Add from GitHub**.
* No **Add from GitHub**? Put the zip from Releases in `mods`.
* The **ARA 2026** season comes with the mod. A copy already in your import folder is used instead, so nothing doubles.
* Two Earth Rally zips in `mods` are named on the Rallies page, with the one to delete.

### Known issues
* The leaderboard needs the helper running in BeamNG.Earth. Without it the stage page says how to start it.

## 1.7.3-alpha: a quicker, sturdier auto recce (2026-11-18)

Works with BeamNG.drive 0.40.5 · [BeamNG.Earth, DeRamp fork](https://github.com/DeRamp/BeamNG.Earth/releases)
(official 1.6+ works, without the auto recce).

A quicker full rally prep, and an auto recce that copes when BeamNG.Earth is slow.

### Changed
* **Full rally:** the next stage's map download starts while the current stage is still being matched.
* Matching is lighter on long stages.
* The log has one timing line per auto recce.

### Fixed
* A part of the stage that BeamNG.Earth did not answer for in time is asked again, instead of ending "no map data".
* After an auto recce, the car is set down on the road at the time control, not left where it landed.

### Known issues
* After **Stop** during a full rally, the next stage's download carries on in BeamNG.Earth's Areas. The message names it.

## 1.7.2-alpha: download progress (2026-11-17)

Works with BeamNG.drive 0.40.5 · [BeamNG.Earth, DeRamp fork](https://github.com/DeRamp/BeamNG.Earth/releases)
(official 1.6+ works, without the auto recce).

A clearer auto recce download, and one **Stop** for a whole rally's stages.

### Changed
* **Progress:** the stage page shows the auto recce's steps, a bar, the time so far and the download size.
* The bar and the stage's pill stripe while it works, so a count that sits still never looks stuck.
* A line says when a big piece is still downloading.
* Held-out stages show their own reason instead of "road missing from the map".

### Fixed
* **Stop all** while a full rally gets its stages ready stops every stage left, not only the one under way.

### Known issues
* After **Stop**, a map download already started carries on in BeamNG.Earth's Areas.

## 1.7.1-alpha: the map downloads (2026-11-16)

Works with BeamNG.drive 0.40.5 · [BeamNG.Earth, DeRamp fork](https://github.com/DeRamp/BeamNG.Earth/releases)
(official 1.6+ works, without the auto recce).

The auto recce's map download, fixed for BeamNG.Earth 1.10.

### Fixed
* Saying **Download** again on a stage uses its area already in BeamNG.Earth instead of adding another.
* The log shows the download's progress every 10 s, and when it finishes.
* A download paused or deleted in BeamNG.Earth's areas stops the auto recce with a message, instead of waiting 30
  minutes.
* The menu says a download can take a few minutes, and carries on if you leave the page.

### Known issues
* The item count can sit still for a minute while big pieces download. It is not stuck.

## 1.7.0-alpha: full stage rally support (2026-11-16)

Works with BeamNG.drive 0.40.5 · [BeamNG.Earth, DeRamp fork](https://github.com/DeRamp/BeamNG.Earth/releases)
(official 1.6+ works, without the auto recce).

Full stage rally support: drive a whole rally from a rally pack, start to finish, with stages, transits, time controls and service.

### New
* **Drive rally** on the home page: any rally whose pack has an event file, run in its own order, day by day.
* Two modes, picked at the start: **Realistic** (no restarts; a recovery sends you to the next service under Super
  Rally) and **Casual** (free recoveries and restarts).
* **Cancelled stages**: skip them as on the day, or drive them all.
* Your car's class is set for you; pick another from the list.
* Transits are driven: the time card lists every control, and **Start transit** routes you to the next.
* Stop at each control's board to check in. At a stage's time control, **Load the stage?** readies it behind a
  loading screen.
* Service and overnight: a board and a tent, a full repair, and the rally saved there. Damage carries over between.
* The rally's own recovery (**Backspace** or **D-pad right**) asks **Recover?** first. The game's resets are off.
* After the last stage, back to service, then **New rally** or **Continue driving**.
* Your rallies on the rally's **Results** tab, overall and in class, with each driven stage's time.

### Changed
* Home page: **Drive rally** and **Drive stage** tiles, and a **Continue** strip for a rally under way.
* Loading screens show each step and a **World** bar, and wait until most of the world around you has loaded
  (setting **World loaded before driving**, default 60%).
* Finish boards and tents stay until you drive out of range.
* One highlight on menus, for mouse and controller alike.

### Known issues
* Transits have no target times, so being late on the road costs nothing.
* If the world moves mid-stage and the co-driver goes quiet, please report it with `beamng.log`.

## 1.6.2-alpha: the loop holds (2026-11-15)

Works with BeamNG.drive 0.40.5 · [BeamNG.Earth, DeRamp fork](https://github.com/DeRamp/BeamNG.Earth/releases)
(official 1.6+ works, without the auto recce).

Fixes to pacenotes, dressing, menus and routing.

### Fixed
* Open sixes and long bends around tight corners are called as sweepers.
* Junctions are called only when they matter.
* Cautions come sooner after a fast straight; short kinks are called a grade more open.
* ATC and stop boards sit along the road; tape runs parallel at shallow junctions.
* The rally menu pauses the game; a controller works on menus and the results card.
* The finish time shows in the top bar; the results card has **Close**.
* **Route to stage** readies the stage as you arrive.

### Known issues
* For earlier calls, raise the game's co-driver timing setting.
* **Start** on a controller opens the game's menu; **B** closes Earth Rally's.

## 1.6.1-alpha: on the stage (2026-11-15)

Works with BeamNG.drive 0.40.5 · [BeamNG.Earth, DeRamp fork](https://github.com/DeRamp/BeamNG.Earth/releases)
(official 1.6+ works, without the auto recce).

Earth Rally does less work each frame on a stage, for players whose frame rate dropped.

### Fixed
* HUD updates are sent only when they change: stage timing about 10 a second, Earth Rally's panel about 1, both were 30.
* Less garbage made for the HUD on every update.
* Stage dressing goes down in short slices with faster road lookups, so arriving at a dressed stretch hitches less.
* Dressing ahead of the car goes down before dressing behind it.

### Known issues
* If your frame rate still falls on a stage, please report it with your graphics preset, GPU and `beamng.log`.

## 1.6.0-alpha: on the stage (2026-11-15)

Works with BeamNG.drive 0.40.5 · [BeamNG.Earth, DeRamp fork](https://github.com/DeRamp/BeamNG.Earth/releases)
(official 1.6+ works, without the auto recce).

Stages are dressed like a real event, from the game's own rally props.

### New
* **Course tape** across every side road the stage doesn't take, reaching past both edges.
* **Direction boards** before junction turns and forks.
* **Junction marshals** behind the tape, on the closed road furthest from a car that misses the turn.
* **Radio and medical points** with warning boards, and **spectator areas** at hairpins and big turns.
* Points marked on the organisers' map are placed where the map puts them ([map tags](https://github.com/DeRamp/BeamNG.Earth.Rally/blob/main/docs/rally-file.md)).
* Where a rally's map marks none of a kind, radio points, marshals and spectators are placed for you.
* Each stage's page shows whether its points come from the map, are placed at random, or are none.

### Changed
* Rallies already imported are read once more on first start, to pick up their map points. Times and recces stay.
* Points right by each other merge into one; props are moved off the road where it is wider than expected.

### Known issues
* Dressing comes from **Auto recce** only. Stages recced before 1.6.0 get direction boards until recced again.
* Props can still land on a road the game's map doesn't have, such as a driveway it is missing.

## 1.5.2-alpha: the time control stays (2026-11-14)

Works with BeamNG.drive 0.40.5 · [BeamNG.Earth, DeRamp fork](https://github.com/DeRamp/BeamNG.Earth/releases)
(official 1.6+ works, without the auto recce).

**Run stage** no longer skips the arrival time control.

### Fixed
* **Auto recce** takes you to the stage's time control, set on the road before its board, not to the start line.
* **Run stage** after **Auto recce**, **Go to start** or a stopped **Recce** no longer counts the time control missed.
* A car standing on the stage is moved back before the time control; a car parked short of it keeps its spot.

## 1.5.1-alpha: the menus clear (2026-11-14)

Works with BeamNG.drive 0.40.5 · BeamNG.Earth modding API 1.6+ (1.9 for the auto recce).

BeamNG.Earth's on-screen text no longer covers the menus.

### Fixed
* BeamNG.Earth's download line, banner and credits no longer draw over the **Escape** menu.
* The same over the rally menu, opened from the **Earth Rally** tab or with **Ctrl + Alt + K**.
* BeamNG.Earth's apps still show in the **HUD apps** editor.

### Known issues
* BeamNG.Earth's text can flash for one frame as a menu opens.

## 1.5.0-alpha: the co-driver (2026-11-14)

Works with BeamNG.drive 0.40.5 · BeamNG.Earth modding API 1.6+ (1.9 for the auto recce).

The pacenotes are rebuilt to call what the road does ([full call list](https://github.com/DeRamp/BeamNG.Earth.Rally/blob/main/docs/pacenotes-1.5.0.md)).

### New

#### Corners
* **Hairpin**, **tight hairpin** and **square** in place of the corner's number.
* **Tightens**, **opens**, **opens and tightens**, **tightens down**.
* **Chicane left / right** for two quick tight corners, one call.
* **Twisty** for a run of flicks; **long sweepers** are called ("six long").
* **Care**, **caution**, **double caution** where a corner comes up faster than it looks.

#### Crests
* Called only where the road ahead is hidden, not wherever the grade changes. **Small** and **big crest**.
* **Down** at the top of a downhill from flat road.
* **Jump**, **big jump**, **dip**, **bad dip**, **up** / **down** on long hills.
* **Into / over crest**, **tightens / opens over crest**, **keep left / right over crest**, **brake over crest**.

#### Bridges, junctions, the finish
* **Over bridge** on lines with bridges added by `tools/auto_recce.py --bridges-only`.
* **Keep left / right** comes before the corner when the fork is inside it.
* **Narrows** where the road gets narrower (drawn roads only so far). **Over finish** on the last note.
* Casual co-driver voices say calls they lack another way (a chicane as two corners).

### Fixed
* A second auto recce keeps the bridges added to the line.
* Crests, jumps and dips are no longer read off bad elevation data.

### Known issues
* Very broad hilltops are not called.
* A stepped descent can call **down** several times close together.
* Co-driver settings (timing, detail, voice) are not in yet.

## 1.4.0-alpha: rally files (2026-11-14)

Works with BeamNG.drive 0.40.5 · BeamNG.Earth modding API 1.6+ (1.9 for the auto recce).

Earth Rally can hold a whole season: drop in a rally pack and get leaderboards against the real crews.

### New
* **Rally packs**: a folder or `.zip` with maps, itinerary, results, rules and pictures. Format: [`docs/rally-file.md`](https://github.com/DeRamp/BeamNG.Earth.Rally/blob/main/docs/rally-file.md).
* Menu is **Rallies > season > rally > stage**, with covers and logos.
* A stage run twice is one row (*SS2 · SS4*); cancelled passes struck out; unused stages say *Not run*.
* **Leaderboards** of real stage times: top 10, plus the crews either side of you.
* **Results**: your rally total, ranked against the finishers.
* **Standings**: season points from finishing order (25, 20, 16 … by default, or the pack's scale).
* Times only placed when your line is within 5 % of the official distance.

### Changed
* The menu opens where you left it. The pause-menu tab is now one **Rally menu** button.
* **HUD preview** moved from Settings to the developer panel.

### Known issues
* A pack imported from a `.zip` has not been tested in game yet. Folders work.

## 1.3.2-alpha: the first stage goes right (2026-11-14)

Works with BeamNG.drive 0.40.5 · BeamNG.Earth modding API 1.6+ (1.9 for the auto recce).

### New
* **Version checks** at startup: game, rally engine and BeamNG.Earth API, in the log and Rallies page.

### Changed
* **Quick start on the line** removed from Settings.

### Fixed
* **No-ATC stages** no longer count down on spawn: you are set 25 m before the line and drive up when ready.
* **Rallies named "Main Route Book"** now take the file's name. Existing rallies are renamed, times kept.

### Known issues
* The menu can lose its styling after BeamNG.Earth's map page opens. `reloadUI()` in the console fixes it.

## 1.3.1-alpha: one Auto recce button (2026-11-14)

Works with BeamNG.drive 0.40.5 · BeamNG.Earth modding API 1.6+ (1.9 for the auto recce).

### New
* **Auto recce** downloads the roads along the stage itself, after asking (e.g. `18 MB?` **Download** / **Not now**).
* **Reset** replaces **Auto recce** once a stage has a line. A driven line asks first.
* Stage tiles are **Length · Corners · Gain · Loss**.

### Fixed
* A download that reports success is re-checked for holes.

### Known issues
* The download estimate can over-ask. **Not now** costs nothing.
* Where the map has no road, the organisers' line is used and no notes are called.

## Older

1.3.0 and earlier: see their [GitHub releases](https://github.com/DeRamp/BeamNG.Earth.Rally/releases).
