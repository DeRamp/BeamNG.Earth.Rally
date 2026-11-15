# Changelog

Format: [`docs/writing-standard.md`](https://github.com/DeRamp/BeamNG.Earth.Rally/blob/main/docs/writing-standard.md). Downloads:
[Releases](https://github.com/DeRamp/BeamNG.Earth.Rally/releases).

## 1.6.0: the first supported release (unreleased)

Works with BeamNG.drive 0.40.5 · [BeamNG.Earth, DeRamp fork](https://github.com/DeRamp/BeamNG.Earth/releases)
(official 1.6+ works, without the auto recce).

The first supported release: 1.6.0-alpha plus its bug fixes. 1.6.x updates are bug fixes; new features come in 1.7.

### Changed
* Version is `1.6.0`, no longer alpha. Delete `earth_rally-1.6.0-alpha.zip` before adding the new zip.
* New [wiki](https://github.com/DeRamp/BeamNG.Earth.Rally/wiki) with screenshots and short how-tos.

### Known issues
* Dressing comes from **Auto recce** only. Stages recced before 1.6.0 get direction boards until recced again.
* Props can still land on a road the game's map doesn't have, such as a driveway it is missing.

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
