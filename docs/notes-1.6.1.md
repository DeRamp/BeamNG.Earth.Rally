# Notes for 1.6.1

Performance on a stage. Several players report about 60 fps falling to about 20. The owner's PC does not show it.
Plan: `docs/perf-plan-1.6.1.md`. Bench: `python tools/perf/run_bench.py <quick|drive> --label "<build>"`.

## What the baseline says (released 1.6.0-alpha, the owner's desktop, Low preset, car stopped)

*Suite `quick-20261115-145006`, history on `worktree-perf-plan`.* No measurable Earth Rally cost on this PC.

| Capture | Race active p50 / p99 | Mod idle p50 / p99 |
|---|---|---|
| Weaver Bend 2.3 km, settled (3 pairs) | 4.1-4.7 / 6.4-7.3 ms | 3.6-4.5 / 6.1-6.9 ms |
| GO on the start line (2 pairs) | 3.8-5.3 / 6.4-10.1 ms | 4.5-5.1 / 9.0-10.3 ms |

- **GO:** no gap. The earlier 156 to 82 fps drop did not reproduce.
- **Arriving at 2.3 km:** frames of 30-80 ms, but every Earth Rally hook under 0.35 ms and none in a spike frame.
  That is BeamNG.Earth streaming the world in.
- **The one mod-side signal:** Lua garbage 2,050-2,590 KB/s racing vs 1,150-1,680 idle, and about +0.2 ms Lua.
- **Road map:** 245-279 nodes at the spots (BeamNG.Earth's navgraph is a window round the car).

## The owner's call (2026-11-15)

Fix every performance suspect first, as a build for players' slower PCs, then record while the owner drives a
stage. So the fixes below are **defensive: none has a measured gain on the owner's PC.** The drive recording and
players' reports are the check.

## What this build changes

**1. The HUD's streams** (`main.lua` `sendStreams`, `hudFrame.streamKeys`).
- Each stream is sent when what it shows changes, not on a timer. `streamKeys` turns the run into one string per
  stream, at the precision the apps draw: stage time in tenths, countdown and clocks in seconds, km done to 0.1,
  distances to the metre (to 0.01 / 0.1 m within 5 m of the start line / stop, as the stock readout), the arrow to
  2 degrees, every card.
- Per second, was then now: on the stage stock 30 then about 10, ours 10 then about 1; on the line 30 + 30 then
  about 2 + 2, on the second; off route ours stays up to 30 (the arrow has no easing).
- At least once a second each (`STREAM_FLOOR_S`), which also carries BeamNG.Earth's place, banner and loading.
- Where a distance moves every frame, at most every 0.1 s (`STREAM_GAP_S`, `HUD_GAP_S`), as before.
- The car stopped and the skip hint sampled 4 times a second (`SLOW_SAMPLE_S`), every frame in the start zone and
  near the stop.
- Both sent at once on a state change or a new run.
- `test_hud` steps sample runs at 60 fps and fails if what is drawn changes while a key does not: a field added to
  `build` without its key shows there.
- `STREAM_FIXED_HZ` (bench switch) puts both back on a timer.
- Defensive like the rest: the drive recording was of the timer build, so this has no measurement.

**2. Fewer tables a HUD message** (`runner.lua` `uiFrame`).
- BeamNG.Earth's place, banner and loading asked at most every 0.5 s (`EARTH_ASK_S`), afresh for a new run.
- The rules' constants in one reused table, its values read each time.

**3. The dressing's road-map lookups** (`props.lua`).
- `roadAt`, `roadCovers` and `nearEdges` walked every node per object. On a map of 2,000+ nodes they now read a
  grid index (64 m cells); under that, the old whole walk, in the same order.
- The index is rebuilt after `onNavgraphReloaded` (`main.lua`), a world shift (`props.reset`), a new nodes table,
  or at 10 s old. Nodes changed in the same table without a reload could be missed for up to 10 s; nothing is known
  to do that.
- Offline: identical results on 200 queries over a 3,000-node map (`test_props`); `roadAt` 0.29 to 0.005 ms at
  30,000 nodes (lupa).

**4. A time budget on dressing spawns** (`props.lua` `DRESS_SPAWN_MS`, 3 ms). Spawning stops for the frame once
3 ms have gone. The first object always goes down, so no site stalls. Sites go down 350 m ahead.

**5. Bench: the drive suite** (`tools/perf`). Records 20 s windows while the owner drives, sets and moves nothing.
Each window: state, distance along, statics, nodes, props, layout, start clock, BeamNG.Earth loading, and the
graphics settings and versions. Ends 60 s after the run leaves `running`, or at 20 min.

## Tried and dropped

- **Start clock unloaded 8 s after GO.** The tree's LED board would freeze mid-stage, the unload ran inside the
  update hook pass, and the clock only rescans the scene when it has no tree. Not worth it.
- **Dressing taken away 200 m behind (was 600).** On a switchback, dressing 200-600 m back along the stage is in
  view. Visible change, no measured gain.

## Not fixed

- **Co-driver at GO, the layout check each second, traffic after the run:** small, and traffic after the run is the
  player's own traffic coming back.
- **`feedStartClock` and `drawStartLine` every frame** up to 8-10 s after GO: a few tables a frame, for seconds.

## What the drive recording must answer

- Does frame time follow the static count and BeamNG.Earth's loading (the world), or the mod's state?
- A control for that: the same road driven with the mod idle, at the same preset.
- At the player's preset (Normal or above) with a 60 fps cap, since Low on this desktop hides GPU costs.
- PresentMon CPU and GPU busy, if it can be given the rights (`--presentmon`).
- Ask the reporting players: preset, resolution, GPU, BeamNG.Earth version and traffic setting, `beamng.log`, and
  whether the same road in free roam, no stage, drops too.

## Also for 1.6.1: seen during the 1.6.0 screenshot session

Logged, not fixed (the owner is bug testing; the owner decides which go in 1.6.1 or later). Found on 2026-11-14 while
driving 1.6.0 through BeamNG's in-game MCP server for the marketing screenshots: Weaver Bend (Overmountain), Maryhill
Up (OTR 2024), Valley of the Gods Eastbound (Colorado).

### 1. A season listed twice after its pack gained an `id`

**Seen:** Rallies showed **ARA Nationals 2026** twice (one "0 of 64 driven", one "5 of 64"). With the second season
file moved aside, its eight rallies showed as loose rallies on Rallies.

**Diagnosis (likely):** `seasons/ara-nationals-2026-2.json` and `events/ara26-*-2.json` are left from an import
before the pack's `season.json` had `"id"`. The importer index (`importIndex.json`) only knows the new ids, so the
old files are orphans and nothing removes them. Any player whose pack changes its ids would see the same.

**Fix to consider:** on import, remove (or move to `events-old/`) season and event files that no index entry owns,
after keeping their times by line key. Check against the owner's data first: the `-2` files carry real driven times.

### 2. Stale message after Auto recce finishes

**Seen:** after **Auto recce** on Valley of the Gods Eastbound finished ("Recce recommended", 85 corners), the line
under the buttons still read "Auto recce of Valley of the Gods Eastbound: checking what map data is missing."

**Diagnosis:** the menu's `message` is set when the press starts and not replaced when the sequence ends.

### 3. Weaver Bend: the line past the flying finish leaves the road

**Seen:** following the stage line from the flying finish toward the stop control took the car onto grass, with
BeamNG's "Please make a U-turn" and the stop control 154 m off. Seen with the script AI on the line, not a driver.

**To check:** whether the matched line after the FF follows the road on this stage, or only the map line does.

### 4. BeamNG's footer draws over the menu's key hints

**Seen:** on every menu page, BeamNG's own bottom bar (version, Navigate / OK / Back) covers the menu's
"Esc Back to the game · Ctrl+Alt+K Open / close Earth Rally" row. Cosmetic; visible in every menu screenshot.

### 5. BeamNG.Earth's server notice in the rally block

**Seen:** on the way to the ATC the rally block carried BeamNG.Earth's "Server OK, some internet data sources not
answering: basemap.nationalmap.gov unreachable ..." for the whole transit, three lines tall. Not ours, but it is in
our block; consider a one-line cut.
