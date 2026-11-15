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

**1. The HUD's streams** (`main.lua` `sendStreams`).
- Our HUD (the whole-screen app, re-drawn on each message) at 10 Hz (`HUD_STREAM_HZ`), was 30.
- Kept at 30 Hz: on the line (its countdown numeral moves with the stock lights) and while off route (the arrow).
- The stock apps' stream at 30 Hz only in waitStart and running (their clock's tenths), 10 Hz in the other states.
- Both sent at once on any state change. Nothing built when only the stock stream is due and the game's rally mode
  has it.

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
