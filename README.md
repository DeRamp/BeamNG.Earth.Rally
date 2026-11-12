# Earth Rally

Real-world rally stages for [BeamNG.Earth](https://github.com/TecnaGamer/BeamNG.Earth): drive a real rally's stages
on the real roads, timed, with BeamNG.drive's own co-driver calling pacenotes made from the road.

Status: alpha. Needs BeamNG.drive 0.40.5 and BeamNG.Earth with
modding API 1.6 or newer (1.7, with the `onBeamNGEarthRebased` event, is used when present).

## How it works

1. **Import** a rally's map (KML or GPX) with `tools/import_kml.py`. Each line becomes a stage; the named points
   next to it (start, flying finish, stop, ATC) become its controls. The event file goes to your game's user folder,
   not to this repository: organisers' maps are theirs.
2. **Recce** each stage once in game: the stage's map line is drawn on the road ahead of you (orange; a green ball at
   the flying finish) and the mod records the line you drive (with real heights). Not the GPS: its route planner does
   not take cars on forest roads. Hand-drawn maps cut corners and have no heights; the recce line is what stages are timed and called on.
3. **Run** the stage, through its controls as in a real rally. The mod takes you just before the arrival time
   control (ATC), moves BeamNG.Earth's world origin to the middle of the stage (so the world does not shift under you
   for any stage up to ~26 km across) and writes the stage for the game's rally engine. The game's route arrows lead
   to each control; in a control's zone the brakes come on at 30 % and a sound says you are in once you stop. At the ATC you are
   given your start time on the rally clock: the next half minute at least 30 s on (never more than 60 s). Wait on the start line for it, held still until the countdown
   (the co-driver counts the last five seconds down); moving off early is a jump start (+10 s), arriving after it is
   late (+10 s a minute, and the next minute). The clock stops at the flying finish (a sound), and you drive on to
   the stop control. Each control has the game's own rally boards just off the road edge, and a gazebo at the ATC,
   start, finish and stop. The pacenote cards show during the run. Times and penalties are kept.

Pacenotes: corners are found from the recce line; the game works out each one's severity and the distance calls and
voices them with its own co-driver voice pack.

## Install (from this folder)

```
python tools/install.py
```

Or put the release zip in `%LOCALAPPDATA%\BeamNG\BeamNG.drive\current\mods\`. Then add a rally (below).

In game: Freeroam > BeamNG.Earth, then **Ctrl+Alt+K** opens the Earth Rally window (or type
`earthRally_main.toggle()` in the console, `~`). Pick a stage, **Go to start**, **Start recce**, drive it to the
flying finish; then **Run stage**.

## Adding a rally from a KML or GPX file

You need [Python 3.10+](https://www.python.org/downloads/) and a map of the rally's stages: a `.kml` (Google Earth,
Google My Maps, or what most organisers publish) or a `.gpx` file. A `.kmz` is a zipped KML: rename it to `.zip`,
unzip it, and use the `doc.kml` inside.

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
  match it. Case, years (`26`, `2026`) and version tags (`V2`) are ignored, and a shorter name works when only one
  stage starts with it (`Maryhill FF`). Points with words like `Service`, `Regroup`, `Spectator` or `Jump` are kept as
  plain points, not controls.

Without a start point a stage starts at the line's first point; without a flying finish it ends at the line's last
point. So the smallest file that works is one line per stage, drawn in the driving direction.

Making your own: in [Google My Maps](https://www.google.com/mymaps), draw a line along the stage's roads and add
markers named as above, then Export to KML/KMZ (tick "Export to a .KML file").

### 2. Import it

From this folder:

```
python tools/import_kml.py "path/to/your rally.kml" --id myrally --name "My Rally 2026"
```

- `--id`: a short name for the event file (letters, numbers, dashes). Importing again with the same id replaces it.
- `--name`: what the window shows. Both are optional (the file's name is used).

It prints each stage with its length and the controls it found, for example:

```
My Rally 2026: 2 stages -> C:\Users\you\AppData\Local\BeamNG\BeamNG.drive\current\earthRally\events\myrally.json
  maryhill-up        4.1 km, fits a  1.2 km circle; controls: atc start ff stop
  kuhnle             8.4 km, fits a  1.7 km circle, 3 pieces (largest gap 60 m); controls: start ff
  controls not matched to a stage (kept as plain points): Kuhnel Stop
```

Check that list:

- **controls not matched**: a point's name doesn't match any stage's name (often a typo). Rename it in the map and
  import again.
- **its start control is ... m from the line**: the point is in the wrong place, or matched the wrong stage.
- **gaps between pieces**: fine; the recce drive fills them in.
- **fits a ... km circle** over 13 km: too wide for now (the world would shift during the stage).

### 3. Load it in game

In the Earth Rally window press **Reload** (no restart needed); the rally and its stages appear in the list. Each
stage needs one recce before it can be run: the map line is only a guide, and the recce records the road you
actually drive.

The event files are kept in your BeamNG user folder, not in this repository. Organisers' maps are theirs; don't
commit or share them.

Where things are kept (your BeamNG.drive user folder, `%LOCALAPPDATA%\BeamNG\BeamNG.drive\current` on Windows):
`earthRally/events/` (imported rallies), `earthRally/recce/` (recce lines), `earthRally/results/` (times),
`earthRally/runtime/` (the stage files written for the rally engine at each run).

## The run's checks (milestone 0)

The window lists what each run found out, also saved with its time:

| check | what it tells |
|---|---|
| Rally engine | the game's rally engine took the stage on this level |
| Corners found / notes loaded | our corners, and the notes the co-driver has |
| Notes called | the co-driver spoke |
| Origin moved to the stage centre | BeamNG.Earth moved its world origin when asked |
| World shifts during the run | should be 0; if not, the co-driver's positions are stale after it (milestone 5) |
| Heights kept | near 0: the game kept the recce heights instead of setting the line down on missing terrain |
| World not ready during the run | the world fell behind the car |
| Furthest off the line | the recce line against where you drove |

## Development

- `mod/earth_rally/lua/ge/extensions/earthRally/`: `main.lua` (window), `runner.lua` (a run), `recce.lua`,
  `stageWriter.lua` (the rally engine's files), `geo.lua` (geometry, corner detection), `events.lua` (files),
  `earthAdapter.lua` (the only file using BeamNG.Earth), `rallyAdapter.lua` (the only file using the game's rally
  engine).
- Tests, no game needed: `pip install lupa`, then `python tests/run_tests.py`.

## Plan

0. In-game proof on one stage (now).
1. Importer matched to OpenStreetMap roads.
2. One timed stage, polished (the stage area downloaded ahead).
3. Recce refinements. 4. Better pacenotes (crests, cautions). 5. Stages wider than ~26 km (the co-driver re-placed
   when the world shifts). 6. Itineraries: loops, road sections, time controls, service. 7. An in-game editor.

## License

Code: MIT, see [LICENSE](LICENSE). BeamNG.drive is a trademark of BeamNG GmbH; this is an unofficial fan
project. The rally boards, tents and co-driver voice are the game's own assets, used from the game at runtime and not
included here. Rally maps and route books belong to their organisers and are not part of this repository.
