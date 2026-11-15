# 1.5.0 on the stage: stage dressing (plan)

Drafted 2026-11-14 in its own worktree (branch `worktree-stage-dressing-1.4.0`), alongside the rally-file work and
the roadmap edits going on elsewhere; nothing here touches `docs/roadmap.md`, `docs/version-plans.md` or the menus.
**Renumbered 1.5.0** (2026-11-15): 1.4.0 went to the rally files, released on main first; this branch was drafted as 1.4.0, and its docs were renamed when main was merged in.

**A plan, not a build: nothing is written until the user says go.**

The part of 1.5.0 that makes a stage look like an event: course tape across the side roads not taken (roadmap item
5), direction boards before the junctions (6), and atmosphere: radio points, medical points, marshal posts and
spectator areas (29). The rest of 1.5.0 (pre-loading, the late-start penalty, stages wider than ~26 km, the ghost,
stage sketches) is not on this branch.

## What the user decided (2026-11-14)

- **People are implied, not modelled.** BeamNG ships no human figures at all (no spectators, marshals or
  pedestrians: the nearest are a Santa and a scarecrow). A spectator area is tape, fence, tarps, a gazebo and
  chairs; a marshal post is a chair, a table and a flag. All stock, all in the game's shared art (on every level).
- **The organisers' map first, automatic where it says nothing.** Radio, medical, spectator and marshal points
  come from the imported map when it marks them, and are placed by rule when it does not.
- **Junctions from the live road map too**, not only from the auto recce's matched file, so a stage with only a
  manual recce (or a matched file older than this version) still gets tape and boards. *Dropped (the user,
  2026-11-14): dressing from the auto recce only* -- see section 1.
- **This branch is tape, boards and atmosphere.** Not the ghost and not stage sketches.

## What there is to build on

**The props system already does the hard part.** `props.lua` puts the game's own rally shapes down as TSStatics at
"sites" (a lat / lon and a driving direction), each object walked along the road and set off its edge, its height
from a ray down to the ground with trees rejected; lazily, once the car is within 350 m; again after a BeamNG.Earth
world shift (`runner._moved` → `props.reset()`); all in one `earthRally_props` group swept on a reload. Its
`LAYOUTS` table (atc / start / ff / stop) is the shape every new kind below takes. `runner.stepPlace` →
`setupProps()` is where sites are registered, `tidy` / `abort` where they go.

**Junctions: found, then mostly thrown away.** `autoRecce.junctions` (autoRecce.lua:475-547) works out, at every
road-graph node of degree 3+ on the line, the road the stage comes in by, the one it leaves by, and every side road
40 m+ long, each as a direction. It keeps only `{along, kind, side}`, and the matched file stores
`[lat, lon, kind, side]` (autoRecce.lua:754). Node half-widths are read from `api.roadGraph` and dropped too
(autoRecce.lua:1004, "1.5.0's question"). Tape needs the side roads' directions, and its length wants their width.

**The organisers' points: read, then mostly thrown away.** `importer.readKml` keeps a placemark's name and first
point, never its folder, style or description; only atc / start / ff / stop become a stage's `controls`; the rest
land in an event-level `points` list nothing reads (importer.lua:509).

**What the maps here actually mark** (all 12 source maps, 9 rallies, 116 lines):

| Rally | Radio | Medical | Spectator | Marshal |
|---|---|---|---|---|
| Overmountain | ~30, in "Medical/Radio" folders and a radio-blue style | 3 on route ("Fire and Ambulance", "MIV"); 5 off site (hospital, landing zones) | as tags ("C - R3 - Spectators") and descriptions | 64, folders "Marshals", named "Gulf - MP 9 - HIGH" |
| SOFR Fri / Sat | - | - | - | 84 / 32, folder "Waypoints/Marshals", named only by route-book number ("2000") |
| 100 Acre Wood | 12 ("Radio") | - | 4 ("Spectator 10") | - |
| Rally Colorado | 1 | 3 ("Midpoint - Medical, Spectators") | 1 | - |
| Olympus | - | - | 4 ("Deckerville Spectator Area"), ~30 m off the line | - |
| LSPR, OFR, SnoDrift, OTR, SOFR Thu | none | none | none | none |

5 of 9 rallies, about 34 of 116 stages, mark at least one. Except the off-site medical places, every one sits on
the line or within ~50 m of it. **No spectator polygons anywhere**: spectator areas are points. The decisive detail:
**names alone are not enough** (SOFR's 116 marshal posts are bare numbers, found only by their folder), so the
importer has to read folders and styles.

**The assets** (`content/art_shapes.zip`, `/art/shapes/race/rally/rally_assets/` unless said; the shapes the game's
own rally missions use most):

- Tape: `s_tape_road_closure_6m` / `_8m` / `_10m` (across a road), `s_spectator_tape_5m`, `_big_a/_b/_center`;
  mesh fence `s_spectator_grid_a_2m` / `_b_2m` / `_center`; tarps `s_spectator_tarp_4m` (+ `_02`, `_03`, `_angle`).
- Boards: `s_corner_dir_{left,right,straight}`, `s_corner_dir45_{left,right}`, `s_corner_dir135_right`,
  `s_corner_dir225_left`; `s_rally_signboard_{radio_point,radio_point_warning,medical_point,medical_warning}`.
- Posts: the gazebo, table and chair props.lua already uses; hay bales
  (`/assets/meshes/props/race_event/equipment/s_haybaleround_alt_01`, `_large_01`); `/art/shapes/race/flagMarker`.

## The design

### 1. Junctions with their side roads

- **The matched file keeps them** (format 2): each junction becomes
  `[lat, lon, kind, side, inDeg, outDeg, [[sideDeg, halfW], ...]]`, bearings in degrees from north, half-width
  from the road graph's node radius. Format 1 files still read (as `plan-1.2.0.md` proposed), with no side roads.
  `tools/auto_recce.py` writes the same shape.
- **The live road map: dropped (the user, 2026-11-14): dressing from the auto recce only.** The stage is dressed
  once, at its start, from the matched file's junctions; a driven recce may still be run after the auto recce, and
  the file's junctions are placed onto its line (`junctions.placeInOrder`). A stage whose file has no side roads (no
  auto recce, or format 1) gets no tape, boards or junction marshals, and the log says once: `no side roads for this
  stage: run Auto recce to dress its junctions`. The radio points and spectator areas need only the line and its
  corners, so every stage has them. (Built first, then taken out: `junctions.live` / `junctions.merge` and
  runner.lua's scan as the car went.)

### 2. Course tape and direction boards

- **Tape** across every side road the stage does not take, ~8 m into it from the junction (past the main road's
  edge), square to it, `_6m` / `_8m` / `_10m` by the side road's width (6 m when unknown). On a `turn`, the road
  straight on is taped too. Side roads under 40 m long (driveways, field gates) are left alone, as now.
- **A direction board** ~75 m before every `turn` and `fork`, on the side of the turn, arrow by the angle between
  the way in and the way out: under 30° `straight`, 30-60° `dir45`, 60-120° `left/right`, beyond that
  `dir135_right` / `dir225_left`. No board at a `straight` junction (the tape says it).
- **The organisers' "Barricade" points** (OTR, 5 of them, all on the line) put tape across the nearest side road
  at that point if there is a junction within ~30 m; otherwise nothing.

### 3. The organisers' points (importer)

- `readKml` keeps each placemark's **folder path, style and description** with its name.
- A point is classified into one or more of **radio / medical / spectator / marshal** by words in any of the four
  (`radio`, `R1`-style tags, a radio style; `medical`, `ambulance`, `MIV`, `fire and ambulance`; `spectator(s)`;
  a `marshal(s)` folder or style, `MP 9`-style tags). "Gulf - Radio, Spectator" is both. The control rules
  (`ROLE_WORDS` / `OTHER_WORDS`) are unchanged.
- Each point within **100 m of a stage's line** is kept on that stage as `marks`
  `[{ kind, name, lat, lon, distM, offLineM }]`, as `controls` are. Farther points (hospitals, landing zones) are
  dropped from the stage: they are not on it.
- **Already-imported rallies are re-read once**, keeping their ids, the way `importer.NAME_RULES` re-read them in
  1.3.2, so the 12 rallies here pick their points up without the player doing anything.
- Caution marks ("!", "!!!", "Danger 3/7"), countdown boards ("300 / 200 / 100") and VC / speed points are not
  dressing: kept, but left for 1.5.0's co-driver to read.

### 4. Atmosphere

Each kind is a `props.LAYOUTS` entry, placed like the controls (along the road, off its edge, on the ground):

- **Radio point:** `radio_point_warning` ~100 m before, `radio_point` at the point, a marshal post just after
  (gazebo, table, chair).
- **Medical point:** `medical_warning` ~100 m before, `medical_point` at it, a gazebo. Where a radio point is
  within 50 m, the two share one post.
- **Marshal post:** a chair, a folding table and a flag marker, off the road's edge. **At a junction, on the closed
  road behind its tape** (~5 m behind, a little off that road's centre), never on the stage (the user, 2026-11-14,
  from the mock-up): of the closed roads, the one **furthest from where a car that misses the turn would go** --
  the least in line with the way in -- so an overshooting car never reaches the marshal. With one closed road, that
  one.
- **Spectator area:** on the inside of the corner, set back: a run of `s_spectator_tape_5m` 4-6 m off the road's
  edge along ~30 m of road, mesh fence behind it, a tarp or two, one gazebo, chairs, a couple of hay bales at the
  road's edge in front.

**Where the map marks none of a kind, per stage, by rule:**

- **Radio** every ~5 km (as real stages space them), none in the last 1 km before the finish.
- **Spectator areas** at most one per ~4 km: the stage's tightest hairpins (from the corners `stageWriter.stageCorners`
  already finds for the pacenotes, via `geo.corners`) and its biggest turns at junctions, none in the first 500 m.
- **Marshals** at turns at junctions (as junction marshals), at most one per ~1 km.
- **Medical: only where the map marks it.** An invented medical point is the one that would mislead.

A stage the map marks radio points on gets no automatic radio points; a kind it is silent about is still filled.

### 5. The object count

Today a site is put down at 350 m and taken away only at the end of the stage. A 25 km stage with tape at 80
junctions, boards, marshals and radio points would be hundreds of objects by the finish, so **sites more than
~600 m behind the car are taken away** (they are not coming back on a stage), and every layout has a fixed object
budget.

## Order of work

1. **Junction geometry kept**: matched format 2, the shared pure junction function (the live-map finder: dropped); offline
   tests with roads in every direction (as `test_autorecce` / `test_props`).
2. **Tape and boards**: the two new kinds in `props.lua`, sites from step 1 in `runner.stepBuild`, despawn behind.
3. **The organisers' points**: importer folders / styles / descriptions, `marks` per stage, the one re-read;
   tests on fixtures shaped like the maps here (not the organisers' files themselves). **Waits on the rally-file
   work:** its worktree (`BeamNG.Earth.Rally-rally-files`, branch `rally-files`) has uncommitted changes to
   `importer.lua`, `events.lua` and `main.lua` (seen 2026-11-14), so this step is built on top of those once they
   are committed, not beside them. Steps 1, 2 and 4 do not touch the importer.
4. **Atmosphere**: the four layouts and the automatic fill.
5. Offline suite, then **a debugger and a contrarian** over the build, then the user drives it.

Done when: an Overmountain stage (the map's own radio and marshal points) and an LSPR or OFR stage (all
automatic) driven end to end with tape, boards and radio points standing where they should.

## Settled (the user, 2026-11-14)

1. **No parked car at radio points.** BeamNG's cars are vehicles, not shapes: spawning one costs physics and risks
   taking the player's camera. The gazebo and boards say it.
2. **No switch on this branch:** dressing is always on. "Stage dressing: full / tape and boards / off" in Settings
   is UI (mock-up first) and the menus are the rally-file session's ground; it comes when they are free.
3. **A mock-up first:** top-down drawings of each layout at true scale in `docs/mockups-1.5.0/stage.html`, agreed
   before the placement code is written.
4. **Passed to the rally-file session** (2026-11-14): reserve `marks` beside `controls` on a stage in its format,
   shape `[{ kind, name, lat, lon, distM, offLineM }]`, so 1.6.0's file can carry them.

## Checking it in game

**The models' turns.** Which way each dressing model faces was read from its mesh data, never seen standing. To see
them: stand a car on an open road, open the game's Lua console (the GE Lua, `~`) and run

    require('earthRally/runner').dressShowcase()

One of each dressing shape goes down in a row 15 m ahead of the car, across the way it faces, each turned by the same
code as on a stage driven towards them (boards' faces to the car, arrows pointing their own way, tape, fence and tarps
laid across the road left to right). The log (`earthRally`, `dressing showcase: ...`) names them in order, left to
right. Take it away with

    require('earthRally/runner').dressShowcaseClear()

(a Lua reload, Ctrl+L, sweeps it too). No change to main.lua is needed: `require` hands back the module main.lua
already loaded.

**The switch** (no UI yet, see Settled 2): `runner.DRESSING` (the dressing at all), `true`, read at each stage's
start. From the console: `require('earthRally/runner').DRESSING = false`, then start the stage again.

**What the log says** at a stage's start: `stage dressing: N site(s), M junction(s) from the file (K with side
roads)`, and with none that has its side roads `no side roads for this stage: run Auto recce to dress its junctions`; a tape left
out because its side road is the stage's own later pass says so once; a shape missing from the game is named once.

## Not changed by this branch

The menus and HUD, `docs/roadmap.md`, `docs/version-plans.md`, and the rally-file work. When this merges, the
roadmap's 1.5.0 rows for items 5, 6 and 29 point here.
