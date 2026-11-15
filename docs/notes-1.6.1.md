# Notes for 1.6.1

Performance on a stage. Players report about 60 fps falling to about 20. Plan: `docs/perf-plan-1.6.1.md`.
Bench: `python tools/perf/run_bench.py quick --label "<build>"`; history in `perf/history.jsonl` on
`worktree-perf-plan` (suite `quick-20261115-145006`).

## What the baseline says (released 1.6.0-alpha zip, this desktop, Low preset, car stopped)

**Earth Rally costs no measurable frame time in any state the quick run covers.**

| Capture | Race active p50 / p99 | Mod idle p50 / p99 |
|---|---|---|
| Weaver Bend 2.3 km, settled (3 pairs) | 4.1-4.7 / 6.4-7.3 ms | 3.6-4.5 / 6.1-6.9 ms |
| GO on the start line (2 pairs) | 3.8-5.3 / 6.4-10.1 ms | 4.5-5.1 / 9.0-10.3 ms |
| Waiting on the line | 5.2-5.5 / 7.9-8.1 ms | - |

- **Settled:** about +0.4 ms p99 with the race on. Inside what a player could notice: no.
- **GO:** no gap between running, waiting and idle. The earlier 156 to 82 fps drop did not reproduce.
- **Arriving at 2.3 km:** p99 58.5 ms, 13 frames over 50 ms, worst 81 ms. But every Earth Rally hook stayed
  under 0.35 ms a frame (`props.update` at most 0.04 ms), and none of the 19 spike frames had a mod hook in it.
  The spikes are the world streaming in, not the mod.
- **Engine categories, arrival:** Lua 3.3 ms mean (all GE Lua, BeamNG.Earth included), render 1.9, shadows 1.3,
  file watchers 0.7.
- **Road map:** 245-279 nodes at the spots. BeamNG.Earth's navgraph is a window round the car, so it stays small.

## Tried and reverted: dressing spawn index (suspect 3 in the plan)

*Built as 4b678c8, reverted. Not shipped.*

- **Idea:** `roadAt`, `roadCovers` and `nearEdges` walk every road-map node per dressing object. A grid index
  plus a 3 ms spawn budget a frame.
- **Offline (T6, lupa):** identical answers on 400 queries; `roadAt` 0.29 to 0.005 ms at 30k nodes.
- **Why reverted:** the real map has under 300 nodes, so a whole-map walk costs microseconds, and `props.update`
  never passed 0.04 ms on arrival. There is no cost for it to remove, so the bench could not show a gain.

## Not fixed, and why

- **Stock start clock rescans** (`gameplay/rallyStartClock.lua:476`): `startClock` was off whenever the mod was
  idle, so it did not outlive the run in these captures. After-the-run (T5) is not in the quick run.
- **Stock stage apps and 30 Hz streams at GO:** the GO test shows no gap.
- **Co-driver at GO, the layout re-applied each second, traffic after the run:** nothing to see in these numbers.

## What the bench cannot see yet (the plan's blind spots, now the likely answer)

- **A car standing still.** No pacenotes, no HUD changes, no new dressing. A driving player has all three.
- **A settled world.** A driving player keeps BeamNG.Earth streaming; the arrival capture shows that alone
  costs 30-80 ms frames, with or without the mod.
- **Low preset.** Render and shadows are 3 ms here; a player's preset may be GPU bound.

**Next, needs the owner's approval (a change to the plan):** a driven A/B. The AI drives the same stretch of
Weaver Bend, mod running vs mod idle, alternated, at the player's preset. If the gap stays near zero, the 60 to
20 fps is BeamNG.Earth streaming, which is out of scope for Earth Rally and goes upstream.
