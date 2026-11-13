# Earth Rally 1.3.0 plan

## Road matching for every player (no Python, no developer tool)

Today a stage runs without a recce only when `tools/match_roads.py` has matched its line to BeamNG.Earth's roads, and
that needs Python and BeamNG.Earth's source. Players who import their own maps get "recce needed" on every stage.

### How

- **Earth Rally Matcher**: a BeamNG.Earth *companion* add-on (docs/ADDONS.md, "Programs beside the game"), made from
  `match_roads.py`: one Python file, installed from BeamNG.Earth's Add-ons page and run by BeamNG.Earth's own Python
  (`BeamNG.Earth --run-addon`), so players need no Python. The packaged app bundles every `server/*.py` module
  (tools/build_app.py), so `mapdata`, `mapcells`, `dem` and `roads` import as they do in the source tree.
- Set to **start with BeamNG.Earth**. It watches `earthRally/events/`; any stage with no file in `earthRally/matched/`
  (or an older one than its event) is matched and written there. A status file (`earthRally/matcher.json`: per stage
  queued / matching / done / failed, with progress) tells the mod what it is doing.
- **In game**, automatic, no button. The stage page shows the matcher's state:

  ```
  Stillwater                     12.4 km
  Line: matching to the roads… (3 of 9 stages)
  ```

  Without the matcher installed, the page says how to install it instead of only "recce needed".
- **Distribution**: a registry entry (kind `companion`, `run: {args: [...]}`, autostart) by pull request to
  BeamNG.Earth's add-on registry, its asset a `.py` in this repo's releases. Until merged: BeamNG.Earth's local list
  (`%LOCALAPPDATA%\beamng-earth\addons\local.json`).

### To find out first

- That a companion run by the packaged app (not the source tree) imports the server's modules.
- The packaged app's download cache folder (the source tree's is `~/.cache/beamng-earth`), so the matcher uses the data
  the player's BeamNG.Earth already downloaded.
- Show the stage-page mock-up to the user before building it.

### Research findings (2026-11-13)

- **Imports.** The packaged app works: build_app.py:144,198-199 hidden-imports every `server/*.py`; dev.375's exe
  contains numpy, mapdata, mapcells, dem, roads, apppaths and install. The **dev tree** does not: `launcher.run_addon`
  (launcher.py:268-276) never adds `server/` to sys.path, so the companion needs a fallback (or a one-line upstream fix).
- **Process.** The world server is the companion's parent (addonrun.py:157-173) and kills it when it ends: all writes
  atomic. The shared download cache is safe across processes (cache.py:233-238 tmp + replace, xproc.py locks).
- **Folders.** Cache: `apppaths.saved_cache_dir() or default_cache_dir()`, `~/.cache/beamng-earth` on Windows too
  (earthd.py:10817, apppaths.py:33). No env var gives a companion the user or cache folder: fall back to
  `apppaths.saved_user_dir()` then `install.candidate_user_dirs()`; better, an upstream PR adding `BNGEARTH_USER_DIR`,
  `BNGEARTH_CACHE_DIR`, `BNGEARTH_DATA_DIR` (not `BNE_*`: those are build switches, revisit.py:140-166).
- **Registry.** `addons.json` in TecnaGamer/BeamNG.Earth-data (addons.py:78), edited by hand by TecnaGamer with the
  author's agreement after checking the files. One entry = one kind + one asset: Earth Rally needs two entries (the
  mod zip, `beamng-mod`; the matcher, `companion`), same repo. `run.args` flags only (`["--watch"]`).
  - **No registry autostart**: "Start with BeamNG.Earth" is the player's toggle (addons.py:847).
  - **Blocker:** Install only offers non-pre-releases (addons.py:437-448); every Earth Rally release so far is a
    pre-release. 1.3.0 has to be a full release.
  - The asset must have GitHub's SHA-256 digest and be one `.py` (addonrun.py:30).
- **Talking to the game:** files in the user folder (the game can't read run.log). `events.lua`'s `readOnce` caches
  a missing file too (events.lua:20-31): drop that entry when the matcher reports a stage done.
- **match_roads.py changes:** optional `--earth`/`--event`; a `--watch` loop (~5 s, skip files still being written);
  atomic writes with retry; `matcher.json` with a heartbeat; a `matcher` version in matched files; idle priority and
  smaller pools (`MapData(threads=2)`, `Dem(fetch_workers=4)`): it inherits the server's pinned cores (cpupin.py:244,
  budget.py:669). One self-contained file, no multiprocessing. ~0-35 s per stage.
- **matcher.json:** `{format:1, matcher, pid, heartbeat, state: idle|matching, queued, current:{event,stage,since}|null,
  stages:{"ev__st":{state: done|failed, seconds?, error?, at}}}`; a heartbeat older than ~30 s = not running. Requests
  from the mod: `earthRally/matcher-request.json`.
- **local.json entry for testing:** `{"id":"earth-rally-matcher","name":"Earth Rally Matcher","author":"DeRamp",
  "repo":"DeRamp/BeamNG.Earth.Rally","kind":"companion","asset":"^earth_rally_matcher\\.py$",
  "local":{"file":"<path>","tag":"1.3.0-dev"},"run":{"args":["--watch"]},"minEarth":"1.9.0"}`; restart the server
  after editing.
- **Draft:** `earth_rally_matcher_draft.py` in the session scratchpad (`research-1.3.0/`); a dry run through
  `launcher.py --run-addon` found 0 stages pending.
- **Build order:** companion file, tested via the dev `--run-addon` → small upstream PR (path fix, env vars, maybe an
  autostart default) → local.json entry → the mod's status display (mock-up first) → 1.3.0 as a full release → ask
  TecnaGamer to list it.
- **Open:** list the mod zip itself too? (`oldFiles` takes exact names: every hand-installed versioned zip would need
  naming.) Does TecnaGamer want trust "reviewed" or "latest"?

## Pacenote generator overhaul

Moved to 1.4.0 (the co-driver) when the user split 1.3.0 in two (2026-11-13; docs/roadmap.md). Details to agree
with the user.

## A stage with no ATC gets one

Some maps (SnoDrift) have stages without an ATC. The run then starts the countdown straight away, and the world takes
long enough to load that it is already running when the player can drive. When a stage has no ATC, add one a short way
before the start along the stage's road (the user: "just up the road from the stage start"), so the player checks in
and gets a start time as usual. Put in 1.3.0 by the user (2026-11-13), with the pacenote overhaul.

## Carried out of 1.2

Two things 1.2 left behind, both worth doing early because the rest of 1.3 leans on them.

### The self-test cannot check the co-driver

`tools/selftest.py` walks the car along the stage line: deterministic, about four minutes, 22 of 23 checks. The one
it cannot make is the co-driver, and the reason is in the game rather than in us. `drivelineRoute:onUpdate` only
looks at its pacenotes when `updateSpeedMph > minEvalSpeedMph` (1 mph), and that speed comes from
`getPlayerVehicle(0):getVelocityXYZ()` through `VehicleTracker:speedMs()`. A car set down frame by frame has no
rigid-body velocity, so the gate never opens and not one note is called. Position is only read after that gate.

The game's own AI does make them play, but it cannot drive a BeamNG.Earth stage: `ai.driveUsingPath` with a script
keeps its route in a private graph installed through `mapmgr.setCustomMap()`, and BeamNG.Earth's navgraph tells every
vehicle to `mapmgr.requestMap()` whenever it streams new roads, which throws that route away. In game it then drove
in straight lines off the stage. Giving the path a 5 m corridor (`r`, which otherwise defaults to the car's own
width) got it round a stage once, in 8.6 minutes with six rescues and a 229 m excursion: a pass, propped up, and not
the same way twice.

The lead worth following is `drivelineRoute:setVehicleTracker()` -- public, and used by the rally manager itself. A
duck-typed tracker reporting a synthetic speed and position would drive the whole pacenote pipeline with no vehicle
involved, which would give the walked run its co-driver check and keep it deterministic. Setting the car's velocity
with `applyClusterVelocityScaleAdd` was tried and did not work: the velocity is real enough to move the car, but the
teleport each frame leaves the tracker reading zero.

### A pull request to BeamNG.Earth for `api.hudHide`

Earth Rally takes BeamNG.Earth's place-name strip and connection banner off screen for a stage by dropping the apps
from its stage layout and then telling BeamNG.Earth they are mounted anyway (`core.hudApp`, its own published call),
so it does not draw them with ImGui instead. That touches no data path and no player setting, and it is the only
option available today -- but it is a polite fiction, and upstream could tidy it away without warning.

The clean shape is about 30 lines and no JS: `hudapps.setHidden(name, by, on)` and `hudapps.hidden(name)` beside the
mount registry, four `and not hudapps.hidden(...)` terms in `core.hudTexts` and its two ImGui draw calls, and
`api.hudHide` / `hudShow` / `hudHidden` behind `has('hud')` with a minor bump. The same size and shape as the
`onBeamNGEarthRebased` contribution. Earth Rally would gate on `api.has('hud')` and drop the mount call where it is
available.

## Also for later

- Maps that group each stage with its controls in folders (SOFR, and one with points named "ATC 10, 14", "Start",
  "Finish"): read the folders, not only the names.
- Earlier notes: a blank start board after a reschedule, course tape, junction direction signs.
