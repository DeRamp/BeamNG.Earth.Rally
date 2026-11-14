# Earth Rally

Real-world rally stages for [BeamNG.Earth](https://github.com/TecnaGamer/BeamNG.Earth): drive a real rally's stages
on the real roads, timed, with BeamNG.drive's own co-driver calling pacenotes made from the road.

Status: alpha (1.3.1, in testing: **one Auto recce button** -- it fetches the map data along the stage if
BeamNG.Earth has none, takes you to the start, and works the line out from the roads there, with no recce to drive
and no Python). Needs BeamNG.drive 0.40.5 and BeamNG.Earth with modding API 1.6 or newer (1.7, with the
`onBeamNGEarthRebased` event, is used when present: BeamNG.Earth's dev builds from 1.9.1-beta.dev.398).

> ### The auto recce needs a BeamNG.Earth that does not exist yet
>
> It is built on **modding API 1.9**: `api.roadGraph`, which asks BeamNG.Earth for one window of its road graph
> around a point, and `api.areaPlan` / `areaAdd` / `areaStatus`, which price and fetch the ground along a route
> through BeamNG.Earth's own saved-area downloader. Both are in
> [one pull request waiting on TecnaGamer](https://github.com/TecnaGamer/BeamNG.Earth/pull/1249); until he merges
> it, the only BeamNG.Earth that can answer is the fork it is on:
> **`github.com/DeRamp/BeamNG.Earth`, branch `addon-api-road-graph`**.
>
> **With a stock BeamNG.Earth, Earth Rally works exactly as 1.2.5 did** -- the mod asks `api.has('roadGraph')` and
> `api.has('areaRoute')`, gets no for an answer to both, and shows no auto recce anywhere. Nothing is broken and
> nothing else changes; you drive a recce, as before. The only thing you lose is the feature this version is named
> for. With the road graph but not the area call, the auto recce works wherever you have already been and says so
> where you have not, which is exactly what 1.3.0 did.

**Open it in game with Ctrl + Alt + K**, or from the pause menu's **Earth Rally** tab ([all controls](#controls)).

## How it works

1. **Add a rally**: drop its map (`.kml`, `.kmz` or `.gpx`) into the import folder. Each line becomes a stage; the
   named points next to it (start, flying finish, stop, ATC) become its controls. No command line for this.
2. **The stage's line on the road.** A stage is timed and called on one of these:
   - **a recce** you drive once in game: the stage's map line is drawn on the road ahead of you (orange; a green ball
     at the flying finish) and the mod records the line you drive, with real heights;
   - **an auto recce**: its map line matched to BeamNG.Earth's roads, no recce to drive. Press **Auto recce** on
     a stage that needs a line and one button does the lot: it works out whether BeamNG.Earth has the map data
     along the stage and **tells you how much there is to download and asks first** (the roads layer alone, about
     18 MB for a short stage); then it takes you to the start, because a road graph can only be asked for near
     where you are; then it asks for the roads a window at a time and works the line out from them -- a 4 km stage
     in about a second and a half. Say **Not now** and it stops without moving you or downloading anything.
     Where the map has no road the organisers' line is used, no notes are called there, and the stage still says a
     recce is better. It needs the BeamNG.Earth above. (The same thing offline, over BeamNG.Earth's source with
     Python: `tools/auto_recce.py`, below.)
   - **Reset**: once a stage has a line, the Auto recce button becomes **Reset**, which removes it so you can make
     it again -- with the auto recce or by driving a recce. A line you drove is confirmed first, because that one
     cannot be made again.

   A recce, when there is one, is used first (unless it was saved short and the matched line covers the stage).
3. **Run** the stage, through its controls as in a real rally:
   - The mod takes you just before the arrival time control (ATC) and moves BeamNG.Earth's world origin to the middle
     of the stage, so the world does not shift under you on any stage up to ~26 km across.
   - Once you check in at the ATC the game's traffic and parked cars are cleared for the stage (back after it).
   - The game's route arrows lead to each control. In a control's zone the brakes ease in as you near the board (none at
     the zone's edge, 30 % at the board, so you can roll up to the boards and tent; brake harder yourself if you like) and a sound says you are in once you stop.
   - At the ATC you get your start time on the rally clock: the next half minute at least 30 s on (30-60 s), more
     when the start line is far from the ATC (time to drive there at ~36 km/h). Driving past the ATC is a missed time
     control (+60 s).
   - On the start line you are held until GO (the game's own hold, as its rally countdown does: rev freely, the car
     does not move), with the car's launch control switched on where it has one. The start tree's LED clock counts down, with the game's
     picture-in-picture view of it in the top right corner (a setting); the game's rally countdown shows the squares and the
     rally clock, a big 5-4-3-2-1 and GO; the co-driver says 30 s, good luck, 10 s, 5-4-3-2-1, go.
     Early? The game's **Interact** control (Shift+E; the modifier + Y on a pad), stopped on the line, skips to 6 s
     before your start, as its rally mode does. Moving off before GO is a jump start (+10 s); reaching the line after your start time is late (+10 s a minute,
     and the next half minute).
   - On the stage: the game's own stage clock and progress bar, the km done, and an OFF ROUTE warning (how far, and
     which way back) when you leave the stage's line. Each car reset during the timed stage costs 10 s (a setting).
   - Where you are, and whether the world is still arriving, are shown by the rally display itself: as a row of the
     card before a stage, and as a thin line beside the stage clock on it. BeamNG.Earth's own place-name strip and
     connection banner are off screen for the stage so there is one panel and not three; its data credits stay.
   - The clock stops at the flying finish (a sound): your time big, against your best; the notes stop and you drive on
     to the stop control. Stopped there, the stage's results card: the time, each penalty, your best, and **Next
     stage**, **Retry**, **Rally menu** (or just drive off). The boards and the co-driver are tidied away a few
     seconds after you stop.
   - Each control has the game's own rally boards beside the road, following its bends, and a gazebo at the ATC,
     start and stop. The pacenote cards show during the run. Times and penalties are kept.

Pacenotes: corners are found from the stage's line; the game works out each one's severity and the distance calls
and voices them with its own co-driver voice pack. On stages with an auto recce (below), junctions and bridges are
called too: "at junction" on a turn there, "past junction", "keep left / right" at a fork, "over bridge".

## Install

Download `earth_rally-<version>.zip` from [Releases](https://github.com/DeRamp/BeamNG.Earth.Rally/releases) and put it in `%LOCALAPPDATA%\BeamNG\BeamNG.drive\current\mods\`. Updating? Delete the old version's zip first. Or, from this folder:

```
python tools/install.py
```

(Only one of the two: both in the mods folder would load two copies; the install script warns about it.)

In game: Freeroam > BeamNG.Earth, then open the Earth Rally menu (see **Controls** below):
your rallies, each rally's stages, a stage's page with **Drive stage**, **Route to start** (BeamNG.Earth's GPS to the
stage's ATC, or its start, so you can drive there instead of teleporting) and **Recce** (for a stage that needs one),
and your times.

**Settings** (in the menu and the pause-menu tab, saved in `settings/earthRally.json` in the user folder): units
(km / miles), time controls (full, or a quick start on the line without the ATC), the reset penalty, the
control-zone brake, where the start clock's close-up shows (right / top / off), and the developer panel (the old
Earth Rally window with each run's checks; `earthRally_main.toggle()` in the console opens it too).

## Controls

| what | keyboard | controller | other ways |
|---|---|---|---|
| **Open / close the Earth Rally menu** | **Ctrl + Alt + K** (Esc closes it too) | none by default: bind one (below) | the pause menu (Esc) > **Earth Rally** tab; or the console (**`~`**): `earthRally_main.toggleMenu()` |
| Skip the wait on the start line (stopped on the line, before your start) | **Shift + E** (the game's Interact) | the modifier + **Y** (Interact) | |
| Reset the car (+10 s on a stage when the reset penalty is on) | **R** / **Insert** (the game's own) | the game's own | |
| **Back on the road**: the car on the stage's road where you got to, facing on (+10 s on a stage, as a reset) | **Backspace** | none by default: bind one | |
| **Flip upright**: back on its wheels where it is (no penalty) | **Shift + Backspace** | none by default: bind one | the game's radial menu |
| Developer panel (each run's checks) | | | Settings > developer panel, or the console: `earthRally_main.toggle()` |

**Change a key:** Options > Controls > Bindings, category **Gameplay**, the actions starting **Earth Rally:**. Any key or
controller button works there.

**The menu does not open?**

1. Make sure you are in the BeamNG.Earth level (Freeroam > BeamNG.Earth), and try the pause menu's **Earth Rally**
   tab instead of the key.
2. Press **`~`** for the console and type `earthRally_main.toggleMenu()`.
   - The menu opens: the mod works and only the key is not reaching the game. On some keyboard layouts (German,
     French, Nordic...) Ctrl + Alt is AltGr, and some overlays or hotkey tools take Ctrl + Alt + K: bind another key
     (above).
   - `attempt to index global 'earthRally_main' (a nil value)`: the mod is not loaded. Main menu > **Mods**: switch
     Earth Rally on. Not in the list? The zip must sit, still zipped, directly in
     `%LOCALAPPDATA%\BeamNG\BeamNG.drive\current\mods\`. BeamMP switches local mods off when you join a server,
     so switch it back on after playing online. Only one Earth Rally zip at a time.
3. Still nothing: `beamng.log` in `%LOCALAPPDATA%\BeamNG\BeamNG.drive\current\` should have the line
   `Earth Rally 1.2.5 loaded`; open an issue with the lines that mention `earth_rally` or `earthRally`.

## Adding a rally

You need a map of the rally's stages: a `.kml` or `.kmz` (Google Earth, Google My Maps, or what most organisers
publish) or a `.gpx` file.

### 1. Check the map

The importer reads two kinds of thing from the file:

- **Lines are stages.** Each line (a KML path, a GPX track or route) becomes one stage, named after the line. A stage
  drawn in several pieces in one placemark is joined up in driving order.
- **Points are controls.** A point becomes a control of the stage whose name it shares, plus one of these words:

  | word in the point's name | control |
  |---|---|
  | `ATC`, `TC` | arrival time control (optional; used when within 1.5 km of the start) |
  | `Start`, `SS` | start line |
  | `FF`, `Flying`, `Finish` | flying finish (the clock stops here) |
  | `Stop` | stop control (optional; used when within 3 km of the finish) |

  For a line called `Maryhill Up`, points called `Maryhill Up Start`, `Maryhill Up FF` and `Maryhill Up Stop`
  match it. Case, years (`26`, `2026`), version tags (`V2`) and stage numbers (`SS3`) are ignored, and a shorter name
  works when only one stage starts with it (`Maryhill FF`). Points with words like `Service`, `Regroup`, `Spectator`
  or `Jump` are kept as plain points, not controls.

Without a start point a stage starts at the line's first point; without a flying finish it ends at the line's last
point. So the smallest file that works is one line per stage, drawn in the driving direction.

Making your own: in [Google My Maps](https://www.google.com/mymaps), draw a line along the stage's roads and add
markers named as above, then Export to KML/KMZ.

### 2. Drop it in the import folder

In the Earth Rally window press **Open import folder** (it is
`%LOCALAPPDATA%\BeamNG\BeamNG.drive\current\earthRally\import\`) and put the file there. It is imported at once if
the game is running, else when the game next starts (**Re-scan** looks again). A message says what was imported, and
the rally's **Import report** in the window lists each stage with its length and controls, and anything to fix:

- **"... matches no stage: did you mean ...?"**: a point's name doesn't match a stage's (often a typo). Rename it in
  the map and save the file again: it is imported again by itself.
- **its start control is ... m from the line**: the point is in the wrong place, or matched the wrong stage.
- **drawn in pieces with gaps**: fine; the recce (or the auto recce) fills them in.
- **too wide to run for now**: the stage is more than ~26 km across (the world would shift during it).

Change the file and it is imported again (**Re-scan** imports every file again). Taking a file out of the folder
does not delete its rally: delete `earthRally/events/<rally>.json` yourself to remove one.
A rally imported before with `tools/import_kml.py` from the same file keeps its id, so its recces and times still
belong to it.

The organisers' maps are theirs: the import folder and the event files are in your BeamNG user folder, not in this
repository. Don't commit or share them.

Where things are kept (your BeamNG.drive user folder, `%LOCALAPPDATA%\BeamNG\BeamNG.drive\current` on Windows):
`earthRally/import/` (the maps you dropped in), `earthRally/events/` (imported rallies), `earthRally/recce/` (recce
lines), `earthRally/matched/` (map lines matched to the roads), `earthRally/results/` (times),
`earthRally/runtime/` (the stage files written for the rally engine at each run).

### 3. The auto recce (developer tool, for now)

`tools/auto_recce.py` routes each stage's map line along BeamNG.Earth's own roads (the ones the game draws, bends
rounded as it rounds them) and takes heights from BeamNG.Earth's elevation data, so the stage runs without a recce.
It needs BeamNG.Earth's source and its Python environment:

```
<beamng.earth>/.venv/Scripts/python.exe tools/auto_recce.py --earth <beamng.earth> --event olympus26
```

On the two stages with a recce to compare (OTR's Maryhill Up and Boyd Loop) the matched line is 0.6-0.7 m from the
driven line (median), heights within ~0.1 m, and ~90 % of the corners the same. The plan is to move it into
BeamNG.Earth's server as an API call so players need nothing.

`tools/import_kml.py` still imports a map from the command line (the same result as the import folder).

## The run's checks

The developer panel (Settings > Developer panel) lists what each run found out, also saved with its time:

| check | what it tells |
|---|---|
| Stage line | the recce, or the map line on the roads |
| Rally engine | the game's rally engine took the stage on this level |
| Corners found / notes loaded | our corners, and the notes the co-driver has |
| Notes called | the co-driver spoke |
| Origin moved to the stage centre | BeamNG.Earth moved its world origin when asked |
| World shifts during the run | should be 0; if not, the co-driver's positions are stale after it |
| Heights kept | near 0: the game kept our heights instead of setting the line down on missing terrain |
| World not ready during the run | the world fell behind the car |
| Furthest off the line | the stage line against where you drove |

## Development

- `mod/earth_rally/lua/ge/extensions/earthRally/`: `main.lua` (the menu's Lua side, the HUD's streams, the developer
  panel), `runner.lua` (a run), `hudFrame.lua` (what the HUD shows, one pure function), `settings.lua`, `menu.lua` (the
  menu's data), `preview.lua` (the HUD preview: `earthRally_main.previewHud()`), `recce.lua`,
  `importer.lua` (maps from the import folder), `stageWriter.lua` (the rally engine's files), `geo.lua` (geometry,
  corner detection, progress along a line), `events.lua` (files), `props.lua` (boards, tents, start tree),
  `earthAdapter.lua` (the only file using BeamNG.Earth), `rallyAdapter.lua` (the only file using the game's rally
  engine).
- `mod/earth_rally/ui/`: the HUD apps (`modules/apps/EarthRallyHud`, `EarthRallyResults`; their `.vue` in
  `modules/apps/earthRally/`, as the game's rally apps) and the menu (`ui-vue/mods/earthRally/`: a page of its own and
  the pause-menu tab). The stage layout (`settings/ui_apps/.../earthRallyStage`) puts them with the game's rally apps.
- **Branches:** work on `main`. A release is a tag on it (`vX.Y.Z-alpha`) and a GitHub pre-release carrying the zip
  from `python tools/package.py <version>`. `v1.2.0`, `v1.1.0` and `auto-test` are kept as history and nothing new
  goes on them: everything they hold is in `main` and in the tags. (`v1.2.0` was the working branch from 1.2.0 all
  the way to 1.2.5, by which point its name said nothing and `main` had sat at the 1.2.1 release for days.)
- Tests, no game needed: `pip install lupa`, then `python tests/run_tests.py` (the importer is also checked against
  `tools/import_kml.py` on the maps in `../Rally Docs/` when they are there).
  `tests/test_roadgraph_e2e.py` drives the auto recce end to end against BeamNG.Earth's own server code -- a
  `beamng.earth` checkout beside this one, or `$BNGE_REPO`; it says what is missing and passes without one. It
  reaches into that checkout read-only and talks to no network. It also reports a fifth bug it found in
  `api.roadGraph` (a cached-only window does download cells); `BNGE_RG_E2E_STRICT=1` makes that count as a
  failure.
- **In-game self-test** (`tools/selftest.py`, the mod's `earthRally/selftest.lua`) -- **unstable; not a gate on a
  release.** It cannot check the co-driver yet, so it exits 1 on every run: read its checks, do not read its exit
  code as a verdict (1.4.0 fixes it, with the co-driver work). The real check on a release is driving it yourself
  and writing what you find into `docs/notes-<next version>.md`, which is where every fix in 1.2.3 to 1.2.5 came
  from.
  - `python tools/selftest.py --check-install`: the installed mod against this repository (read-only, fine while the
    game runs): every file, the version, the stage layout's apps (the 1.2.1 fault: an old layout with no HUD app),
    a saved copy of the layout, two copies installed, the mod switched off, the version the game last loaded.
  - `python tools/selftest.py` (the game closed; BeamNG.Earth's source next to this folder, or `--earth <folder>`):
    installs the mod, checks the install, starts BeamNG.Earth's launcher (`--no-beammp --gfx dx11`), and the mod runs
    OTR 2024's Maryhill Up by itself (`--event`, `--stage` for another): the car put at the ATC and the start line,
    the wait skipped once the world is quiet, the car then walked along the stage line, a forced off route, Back on
    the road, Flip upright, the stop control, the results card. It checks the stage layout on screen with all its
    apps, both HUD streams in each state, and errors logged; it then closes the game, prints each check and exits 1
    on a failure (~4 min). A window on screen shows the phase and each check as it is made. The report:
    `earthRally/selftest/report-<time>.json` in the user folder. The stage's times are put back as they were.
  - What it cannot check yet: **the co-driver**. The game decides whether to look at its pacenotes from the car's
    rigid-body velocity, and a car set down frame by frame has none, so no note is called and that one check fails.
    The game's own AI does make them play, but it cannot drive a BeamNG.Earth stage reliably: `ai.driveUsingPath`
    keeps its route in a graph installed with `mapmgr.setCustomMap()`, and BeamNG.Earth tells every vehicle to
    `mapmgr.requestMap()` whenever it streams new roads, which throws that route away. For 1.3.0.
  - In game, from the console in the BeamNG.Earth level: `earthRally_main.selfTest('otr24', 'maryhill-up')`
    (`earthRally_main.selfTestStop()` stops it). Without a request the self-test is never loaded.
- **Driving it yourself**: `python tools/playtest.py` installs the mod, starts the game and goes straight to a stage
  (`--event`, `--stage`; `--goto` to be taken to the start rather than put into a run). Through Steam, so Steam Input
  reaches the game and a controller works -- BeamNG's launch-options dialog shows as a result, and `--gfx dx11` skips
  it at the cost of Steam. The request is used once, so a normal start of the game never does any of it.
- `docs/plan-1.2.0.md`: the 1.2.0 plan (the player UI). `docs/roadmap.md` and `docs/version-plans.md`: where this
  is going. `docs/notes-<version>.md`: what was reported while testing the version before it, and what came of each
  one. `docs/mockups-<version>/`: the screen as it was agreed before it was built.

## Plan

In 1.3.0 so far: the auto recce, in this mod's own Lua on BeamNG.Earth's `api.roadGraph` (the pull request above).
Still to come before it is a full release (`docs/plan-1.3.0.md`): version checks at startup; the stage corridor
loaded before the start, and on demand for a stage you have never been near -- which is what the auto recce needs to
work anywhere rather than only on ground you have driven; an ATC added to stages without one; and no time penalty
for a late start, as in a real rally. Later: the co-driver (better pacenotes, and the self-test hearing them),
course tape, junction direction signs, stages wider than ~26 km, itineraries (loops, road sections, service), an
in-game editor.

## License

Code: MIT, see [LICENSE](LICENSE). BeamNG.drive is a trademark of BeamNG GmbH; this is an unofficial fan
project. The rally boards, tents and co-driver voice are the game's own assets, used from the game at runtime and not
included here. Rally maps and route books belong to their organisers and are not part of this repository.
