# Earth Rally 1.3.0 plan

**Stages for everyone.** Done when, on a clean PC with no Python installed, a map dropped in the import folder
drives without a recce.

Everything here is backbone. The route editor and rally setup mode are 1.5.0 and are not touched: they are built on
top of what this version lays down (the matched line, the stage file, the corridor), and starting them before the
backbone is solid would mean building an editor for a thing that still changes underneath it.

## Decided with the user (2026-11-13)

- **Version checks warn, they do not refuse.** A BeamNG.drive or BeamNG.Earth this mod does not know says so and
  lets the player carry on. "If people have issues, they'll just have to let me know and we'll fix them."
- **Pre-loading is a feature, not a wall.** The stage never refuses to start. You can drive up through the controls
  while the world is still arriving; the mod tells you how it is going, and the natural place for that is the
  control zone between the ATC and the start, where you are stopped anyway.
- **Being late to the start costs nothing.** This is a change to what the mod does today (`LATE_PENALTY_S`, 10 s a
  minute). Real rallies do not fine you for a late start -- they give you a new minute -- and waiting for the world
  to load must not cost a player time either. So: a new start minute, no penalty, and the late path keeps only the
  reschedule. `M.LATE_PENALTY_S`, `run.latePenalty`, `checks.lateMinutes` and the penalty's row on the results card
  all go with it; the jump start, the missed time control and the reset penalty stay.
- **The automatic ATC sits close to the start.** Measured on OTR 2024, where the organisers put theirs 36 m
  (Maryhill Up, the one the user picked as right), 43, 46, 50, 56, 66, 72 and 510 m before the start -- so ~50 m,
  inside the real cluster and near Maryhill's. Walked back along the road rather than straight: if the walk reaches
  a junction first, take any arm of it and place the ATC there, which is what a real organiser does with the road
  they are given.
- **The clean test happens on this desktop**, not another machine: the mod uninstalled completely, then installed
  from the release zip as a player would, with maps re-imported. The user's recorded times are expendable
  ("we're doing testing anyway") -- but say so before deleting anything, every time.
- **Upstream pull requests: yes, and show them first.** They go out as DeRamp from the existing fork
  (github.com/DeRamp/BeamNG.Earth), and the user reads the text before anything is sent.

## The order, and why it is not the obvious one

`docs/version-plans.md` had the small safe items first and the auto recce last. That is the wrong way round. The
auto recce is the only part with real unknowns, and the three that matter are answerable in an afternoon -- but if any
of them comes back "no", the whole shape of this version changes. Leaving them to the end means finding out when
there is no room left to change course. So the unknowns are answered first, and nothing is built on them until they
are.

The self-test's co-driver gap is **not** in this version (the user, 2026-11-13). It moves to 1.4.0, which is the
co-driver version: the pacenote work happens there, so the test that listens for pacenotes belongs with it rather
than ahead of a version about roads.

### 0. Answer the auto recce's unknowns, build nothing (an afternoon)

A throwaway spike, thrown away afterwards. Three questions, all from the research below:

- Does a companion run by the **packaged** BeamNG.Earth app import the server's modules? The research says yes
  (`build_app.py` hidden-imports every `server/*.py`); confirm it on a real packaged build rather than by reading.
- Where is the packaged app's download cache? The auto recce must read the data the player's BeamNG.Earth already
  fetched, not fetch it again.
- Can a companion find the BeamNG user folder? Today there is no env var for it. If not, the fallback chain
  (`apppaths.saved_user_dir()`, then `install.candidate_user_dirs()`) has to carry it.

If the answers hold, the companion approach stands and the rest of this plan is sound. If one fails, stop and
re-plan before writing a line of it -- the alternatives (the auto recce in the mod's own Lua; an auto recce
service in the world server) are different enough that no work carries over.

### 1. Version checks at startup (23) (small)

A clear message when BeamNG.drive or BeamNG.Earth is not the version this mod knows, instead of a stage failing
halfway with something obscure. Small, and it protects everything after it -- including the auto recce, which will be
reading another project's file formats.

### The auto recce cannot run in our own Lua (spike, 2026-11-13)

A second spike asked whether the auto recce could happen in Earth Rally's own Lua, in the running game, with no Python
and nothing upstream -- the cheapest shape there is, and the one the companion review pointed at. **It cannot.**

BeamNG.Earth only ever hands the game process **one 2200 m square of road data centred on the player**, and replaces
it every 400 m they move (`server/navgraph.py:50` `WINDOW_M = 1100.0`, `:1246` `REBUILD_M = 400.0`; the previous
window's file is deleted, `server/earthd.py:2242`). A 12 km stage needs six of those at an absolute minimum and
realistically eight to twelve. The only thing that moves the window is the player's own car position
(`earthd.py:9402`, from the mod's `pose` message) -- so an auto recce in Lua means driving the corridor first, which is
the recce this version exists to remove.

The hoped-for way round it does not exist either: 1.3.0's corridor pre-cache (`server/areas.py`) has no navgraph
phase at all -- `grep -c navgraph server/areas.py` is **0**. Its modes are `data` and `world` (`areas.py:186`), which
fetch cells, DEM, imagery and road geotile content. None of that produces a graph anywhere along the corridor, so
"match while the pre-cache runs" has nothing to match against. Teleport-hopping the player along the stage, or
deleting their car so the free camera drives the streaming focus, both work on paper and both stream the entire world
along the corridor to harvest a few thousand graph nodes. Neither is acceptable.

**What the spike found that is worth keeping.** If the window problem were solved, a Lua auto recce would be *better*
than `tools/auto_recce.py`, not merely equal: the graph is already simplified to a 0.6 m chord with junction
connectors shared by construction, so the whole road-graph build (~140 lines of cell reading, vertex merging and
dead-end bridging) disappears; node `z` is the drivable surface with bridge decks and tunnel floors baked in, so the
**DEM dependency disappears entirely**; and it carries road width, `rough` (OSM smoothness) and `rumble`, none of
which the Python tool has. Node ids are stable across windows and anchors (`navgraph.py:1249-1270`), so stitching
would be sound. The one real loss is bridges: no node or edge carries a bridge flag, so the `overBridge` pacenote
landmark could not be derived.

**So the ask upstream should be `api.roadGraph(lat, lon, radiusM, callback)`, not `api.matchLine`.** One window of
road data at a point we name, built from cells already on disk. `Server.build_navgraph` (`earthd.py:2226-2302`) is
already a pure function of (anchor, x, y) plus cached data, and `navgraph.build` already takes an arbitrary centre
and window as parameters (`navgraph.py:359`) -- upstream runs it every 400 m regardless. It is strictly smaller than
asking for an auto recce, and it keeps the matching, our bugfixes and the organisers' route-book data inside Earth Rally.

*One claim from the spike that does not hold, checked before acting on it:* it reported that a partly matched line
could reach the stage runner today, because `lineValid` (`events.lua:56`) only tests for two points and nothing in
the mod reads a matched line's `gaps`. The premise is right and the conclusion is wrong -- `auto_recce.py` never
writes a partial line. A stretch with no road is filled with the organisers' own line, eased in and out over
`BLEND_M` so there is no kink, and each of those points is flagged so no notes are called there
(`auto_recce.py:483-503, 541-545`). The line always spans the whole stage and `gaps` is metadata. It remains a fair
warning for any *incremental* design: do not write the file until coverage is complete.

### 2. The auto recce (the backbone proper, and the large one)

In the order in "Auto recce for every player" below: the companion file made from `tools/auto_recce.py`, tested
first against the dev tree's `--run-addon`, then against the packaged app; the status file; the stage page's auto
recce state (**mock-up first**); a `local.json` entry for testing; the registry entry by pull request last.

Done when a map dropped into the import folder on a machine with no Python recces itself, with the stage page
showing progress while it happens.

### 3. Stage pre-loading, with how much is loaded on screen (21) (medium)

BeamNG.Earth's area pre-cache along the stage corridor before the start, so a stage does not begin into a world that
is still arriving. **Mock-up of the loading display first.**

This one has already shown its teeth: in 1.2 the self-test started a stage mid-stream and the car was off the line
280 m in, and the ATC's boards were set out from the organisers' pin because the road map had not arrived. The
settle gate in `selftest.lua` is a workaround for a real problem that this step fixes properly, for players too --
so when it lands, that gate should be revisited rather than left in.

### 4. The import smalls (4, 3), and the late-start rule (small, and genuinely small)

- Maps that group each stage with its controls in folders (SOFR and others): read the folders, not only the names.
  Two of the user's own rallies import with no controls today because their points are called just "Start" and
  "Finish".
- An ATC added to stages without one, so every stage starts the same way: ~50 m before the start, walked back
  along the road, taking any arm of the first junction it meets (see the decisions above for where that number
  comes from).
- **No penalty for a late start**, just a new minute, as a real rally does -- and so that waiting for the world to
  load can never cost a player time. Touches `runner.stepToStart`, the results card and the HUD's penalty rows.

Left to last deliberately: they are contained, they have offline tests, and they are the easiest things to drop if
the auto recce turns out to need the time.

### 5. Release

A **full** release, not a pre-release -- the first one. That is a different bar: the version checks in step 1 have
to be in, the self-test has to pass end to end, and a clean PC has to be the thing actually tested rather than this
one. Then ask TecnaGamer to list Earth Rally and the auto recce in BeamNG.Earth's add-on registry.

## Auto recce for every player (no Python, no developer tool)

Today a stage runs without a recce only when `tools/auto_recce.py` has matched its line to BeamNG.Earth's roads, and
that needs Python and BeamNG.Earth's source. Players who import their own maps get "recce needed" on every stage.

### How

- **Earth Rally Auto Recce**: a BeamNG.Earth *companion* add-on (docs/ADDONS.md, "Programs beside the game"), made
  from `auto_recce.py`: one Python file, installed from BeamNG.Earth's Add-ons page and run by BeamNG.Earth's own Python
  (`BeamNG.Earth --run-addon`), so players need no Python. The packaged app bundles every `server/*.py` module
  (tools/build_app.py), so `mapdata`, `mapcells`, `dem` and `roads` import as they do in the source tree.
- Set to **start with BeamNG.Earth**. It watches `earthRally/events/`; any stage with no file in `earthRally/matched/`
  (or an older one than its event) is matched and written there. A status file (`earthRally/autoRecce.json`: per stage
  queued / matching / done / failed, with progress) tells the mod what it is doing.
- **In game**, automatic, no button. The stage page shows the auto recce's state:

  ```
  Stillwater                     12.4 km
  Line: auto recce running… (3 of 9 stages)
  ```

  Without the auto recce installed, the page says how to install it instead of only "recce needed".
- **Distribution**: a registry entry (kind `companion`, `run: {args: [...]}`, autostart) by pull request to
  BeamNG.Earth's add-on registry, its asset a `.py` in this repo's releases. Until merged: BeamNG.Earth's local list
  (`%LOCALAPPDATA%\beamng-earth\addons\local.json`).

### To find out first

- That a companion run by the packaged app (not the source tree) imports the server's modules.
- The packaged app's download cache folder (the source tree's is `~/.cache/beamng-earth`), so the auto recce uses the
  data the player's BeamNG.Earth already downloaded.
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
  mod zip, `beamng-mod`; the auto recce, `companion`), same repo. `run.args` flags only (`["--watch"]`).
  - **No registry autostart**: "Start with BeamNG.Earth" is the player's toggle (addons.py:847).
  - **Blocker:** Install only offers non-pre-releases (addons.py:437-448); every Earth Rally release so far is a
    pre-release. 1.3.0 has to be a full release.
  - The asset must have GitHub's SHA-256 digest and be one `.py` (addonrun.py:30).
- **Talking to the game:** files in the user folder (the game can't read run.log). `events.lua`'s `readOnce` caches
  a missing file too (events.lua:20-31): drop that entry when the auto recce reports a stage done.
- **auto_recce.py changes:** optional `--earth`/`--event`; a `--watch` loop (~5 s, skip files still being written);
  atomic writes with retry; `autoRecce.json` with a heartbeat; an `autoRecce` version in matched files; idle priority and
  smaller pools (`MapData(threads=2)`, `Dem(fetch_workers=4)`): it inherits the server's pinned cores (cpupin.py:244,
  budget.py:669). One self-contained file, no multiprocessing. ~0-35 s per stage.
- **autoRecce.json:** `{format:1, autoRecce, pid, heartbeat, state: idle|matching, queued,
  current:{event,stage,since}|null, stages:{"ev__st":{state: done|failed, seconds?, error?, at}}}`; a heartbeat older
  than ~30 s = not running. Requests from the mod: `earthRally/autoRecce-request.json`.
- **local.json entry for testing:** `{"id":"earth-rally-auto-recce","name":"Earth Rally Auto Recce","author":"DeRamp",
  "repo":"DeRamp/BeamNG.Earth.Rally","kind":"companion","asset":"^earth_rally_auto_recce\\.py$",
  "local":{"file":"<path>","tag":"1.3.0-dev"},"run":{"args":["--watch"]},"minEarth":"1.9.0"}`; restart the server
  after editing.
- **Draft:** `earth_rally_auto_recce_draft.py` in the session scratchpad (`research-1.3.0/`); a dry run through
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

Two things 1.2 left behind. Neither is in 1.3.0 in the end: one moved to 1.4.0 where the work it tests belongs, and
the other was reviewed and dropped. Both write-ups are kept here because this is where the findings were made.

### The self-test cannot check the co-driver -- deferred to 1.4.0

*Not in 1.3.0.* It moves to the co-driver version, where the pacenote work is. The findings are kept here because
this is where they were made.

**What it costs in the meantime.** The pacenote check fails on every run, so `tools/selftest.py` exits 1 every time:
as it stands it cannot be used as a pass/fail gate at all, and a test that is always red is a test nobody reads. If
it is to be useful through 1.3.0 it needs that one check reported as a known gap rather than a failure -- a few
lines, honest as long as the report says plainly that the co-driver was not checked. Worth doing before leaning on
the self-test for anything in 1.3.0; not worth doing if it is only going to be run by hand.

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

### The strips: no pull request (closed, 2026-11-13)

Earth Rally takes BeamNG.Earth's place-name strip and connection banner off screen for a stage by dropping the apps
from its stage layout and then telling BeamNG.Earth they are mounted anyway (`core.hudApp`), so it does not draw them
with ImGui instead. An `api.hudHide` was drafted to replace that, reviewed, and **not sent**. The decision is the
user's (2026-11-13: "avoid having to do that push entirely ... so nobody else has any issues"), and the review had
already reached the same place:

- **The drafted API would have let any add-on hide BeamNG.Earth's data credits with one call.** Its `credits.lua`
  says the strip is on by default because "CC BY and similar licences ask for visible attribution". No prose in a
  docs page makes that safe, and this project had already decided for itself (docs/notes-1.2.4.md) that "a mod
  turning it off for them is not the same as the player choosing to".
- **The patch had a real defect**, and it was the same shape as the one found on our own side: a hold could be taken
  and never released -- `hudapps._reset()` has no production caller, `onClientEndMission` does not clear holds, and
  BeamNG.Earth's own Add-ons page can uninstall the holder, after which no code exists in the session that can give
  the strip back. For `credits` that is attribution off for the session with the player unable to restore it.
- Two factual errors in the docs it added (a frame rate the status bar no longer shows; a manifest `id` field that
  does not exist), and `banner` made hideable although `banner.lua`'s first line is "never silent" and it carries
  "server not running" and "the car is held in place".
- It also claimed `core.hudApp` is "a published entry point". It is not -- `grep -rn hudApp docs/` in BeamNG.Earth
  returns nothing. That claim is now corrected in `earthAdapter.lua`, where it had been repeated.

**So the mount call stays, knowingly.** What makes that defensible rather than lazy: it fails cheaply (the strips
stay on screen; nothing is stuck or lost, and a renamed strip is now reported rather than assumed held), and it is
released on every way out of a run that can leave one held: the level being left (`main.onClientEndMission`, every
call pcall'd so a throw in the tidy cannot take the release with it), a Lua reload or console unload
(`main.onExtensionUnloaded`), and the mod being switched off in the mod manager (`main.onModDeactivated` -- the game
does **not** unload a mod's extensions for that, checked in its own Lua, so without that hook the runner would go on
re-asserting the hold every frame inside a switched-off mod). All four paths are tested in `tests/test_run.lua`.

A version check cannot be the safety net here, and an earlier draft of this wrongly said it would be: `core.hudApp`
is not part of the versioned API surface, so a change to it need not bump the minor. The real protection is that the
state we assert is BeamNG.Earth's own default in both layouts it ships, that only its three imgui draw gates read
mount state at all, and that `M.place()` and the minimap keep their data throughout. It also never touches `credits`:
`earthAdapter.EARTH_STRIPS` is `status` and `banner` only.

The draft is on the local branch `addon-api-hud-hide` in the BeamNG.Earth clone, unpushed, kept for reference.

## Also for later

- Maps that group each stage with its controls in folders (SOFR, and one with points named "ATC 10, 14", "Start",
  "Finish"): read the folders, not only the names.
- Earlier notes: a blank start board after a reschedule, course tape, junction direction signs.
