# Performance test plan, 1.6.1

**Status: approved 2026-11-15.** Tools built under `tools/perf/`: run with
`python tools/perf/run_bench.py <smoke|quick|t1|t1b|t2|t3|t4|t5|full> --label "<build>"`.

**Question:** what takes a player from 60 to 20 fps on a stage, and is it Earth Rally?

## What we know already (measured 2026-11-15, this desktop, Low preset)

* **Idle, mod loaded vs unloaded:** no difference. The mod costs nothing until a stage is on.
* **On the start line (waitStart):** 156-166 fps.
* **Clock running, car stopped 32 m in:** 82 fps, p99 32 ms.
* **1.7 km in:** 30 fps, with 731 frames over 50 ms in 10 s. **After the run:** 23 fps.
* **Lua is not the bulk of it:** 2-4 ms a frame, render about 2 ms, UI JS tiny. Lua spikes reach 74-164 ms.
* **Not reliable:** those runs drove or stepped the car down the stage and polled over MCP. Moving the car makes
  BeamNG.Earth load the world, which hides whatever the mod costs.

## What the research says (deep research, 2026-11-15)

* **GE Lua runs on the main thread.** The Lua profiler sees its own time, not what it sets off: UI repaints, draw calls,
  shape loads. A small Lua number clears nothing.
* **BeamNG's own pitfalls:**
  * UI data sent every frame ("really bad").
  * Table and vector churn (GC spikes).
  * Dynamic or animated statics, which lose batching.
* **Engine-wide first:** PresentMon logs CPUBusy and GPUBusy per frame, which says whether a drop is CPU or GPU bound.
* **Judge by slow frames:** p50, p95, p99 frame time, A/B alternated, one tool for every run.
* **Not settled by research:** how big any of these costs is in BeamNG. We measure it.

## Suspects from the code audit

| # | Suspect | Where | Why it fits |
|---|---|---|---|
| 1 | World still loading after the run's teleport and origin move | `runner.lua:485` | Steady fall, stays low after `tidy()`, Lua flat |
| 2 | Stock stage apps switched on at GO, timing streamed at 30 Hz | `hudFrame.lua:232`, `main.lua:1006` | Only change that lines up exactly with GO |
| 3 | Dressing spawn bursts: whole road-graph scans, up to 24 objects a frame | `props.lua:942`, `:454` | The 74-164 ms spikes; grows as the graph grows |
| 4 | Stock start clock rescanning every TSStatic once a second | `gameplay/rallyStartClock.lua:476` | Thousands of statics on Earth; may outlive the run |
| 5 | Co-driver engine switched on at GO | `rallyAdapter.lua:93` | Starts at GO |
| 6 | Stage layout re-applied every second if something flips it | `runner.lua:1584` | Each swap rebuilds every CEF app |
| 7 | Traffic and parked cars back after the run | `runner.lua:903` | Would explain 23 fps after the run |

No per-run leak was found.

## The stage and the spots

* **Stage:** Overmountain Rally 2026, **Weaver Bend** (6.8 km, 733 points, one piece).
  Fallback if it will not load: **Low Gap** (7.0 km).
* **Auto recced first** (2026-11-15): matched 6,741 m, no gaps, at most 9.4 m off the map line, 46 corners.
  Saved to `earthRally/matched/ara26-overmountain__weaver-bend.json`.
* **Three spots:** the start line (0 m), 2.3 km and 4.6 km.
* **No driving.** The car stands still at every capture. It moves only by one teleport per spot.
* **A teleport is never inside a measurement.** After each one, a settle gate must pass before capturing:
  * BeamNG.Earth reports nothing loading (`earth.loading()` nil);
  * the TSStatic count is unchanged for 5 s;
  * the rolling 5 s median frame time is within 5 % of the 5 s before.

  Gate timeout 120 s. If it times out, the spot is logged as "did not settle" and skipped, not measured.
* **Every A/B pair is at the same spot**, after the same settle. Spots are never compared with each other.

## The mod's states

No waiting at the start and no countdown. The bench (`tools/perf/bench.lua`) puts the mod straight into the state a
capture needs. It runs the same lines the real step does, so the same systems come on. It is loaded into the running
game over MCP and changes no mod file: the runner's internals (`setState`, `zoneRelease`, `tidy`) are read from the
upvalues of its public functions, so it measures the installed zip exactly as players have it.

| State | What is on | How the hook gets there |
|---|---|---|
| `none` | Mod loaded, no run: the floor | `runner.abort(true)` |
| `waitStart` | On the line: start tree and its clock, clock view, car held, stage layout | Set `startAt` an hour on, so GO never comes; `setState('waitStart')` |
| `running` | The race active: stage clock, stage apps, co-driver notes, dressing | The GO block of `stepWaitStart` (`runner.lua:1389`): `zoneRelease()`, `notesOn(true)`, `run.clock = 0`, `setState('running')` |
| `finished` | After the run: tidied, traffic back | `M.wrapUp()` with no time, so nothing is written to the results file |

* **The run is set up for real first:** started from the stage menu, through travel, anchor, build and place. That is
  setup, not waiting. The hook acts once the state is `toAtc` or `toStart`.
* **For a spot down the stage**, the hook teleports through BeamNG.Earth and sets `run.prevAlong` and `run.along` to
  that distance. Progress is only searched 600 m ahead (`FOLLOW_AHEAD_M`), so without this the run is off route.
* **Before every capture the recorder checks the state**: `run.state`, `run.along` within 50 m of the spot, notes on,
  and the stage layout active. A wrong state stops the test; it is not measured.
* **A stopped car stays in `running`.** Only setup errors fail a run (`runner.lua:174`), so the clock can run for as
  long as the captures need.
* **The co-driver at a spot:** the hook calls `rallyA.resync()` after the teleport, so the engine picks up from there.
  Check that a note is queued; if not, note it and carry on, since its Lua cost is small.
* **Not shipped:** the bench is a developer tool under `tools/perf/`; the mod zip does not carry it.
* **Placing the car:** a plain move with `runner.placeCar`, not a BeamNG.Earth teleport, so the world's origin stays
  where the run anchored it. The car is held at the line's height until the ground there has streamed in.

## Method, for every test

* **Recorder in the game** writes JSON to `earthRally/bench/`. It records:
  * `hptimer` frame gaps;
  * the engine's time categories;
  * the max (not just the mean) time around each Earth Rally hook;
  * memory churn;
  * the TSStatic count and road-graph node count;
  * BeamNG.Earth loading status.

  It runs the whole scripted test by itself; MCP only starts it, and those frames are dropped. No polling.
* **PresentMon 2.6.0** runs beside it for CPUBusy and GPUBusy (`run_bench.py --presentmon <exe>`). Downloaded to
  `Documents\Claude\tools\PresentMon\` (Intel-signed). It needs admin or the "Performance Log Users" group; until
  then, Optick and the engine categories stand in.
* **Each capture:** 5 s warm-up, then 20 s capture. One change at a time, alternated A B A B, 3 pairs.
* **Report:** p50, p95 and p99 frame time, frames over 33 and 50 ms, and the spread between pairs.
* **Every A/B has an explicit base** (as shipped), and its pairs alternate A B, B A, A B, so a drift over time cancels.
* **A change counts** only when there are at least two pairs, every pair's p99 difference has the same sign, and
  the median difference is larger than the base's own spread over its pairs. Anything else is "no change".
  The dashboard shows how much of the race-vs-idle gap is left.
* **Captures cut short** (a stopped suite) are left out of the report and the history.
* **Controls:** vivace, Low preset, vsync off, background fps limit off, power plan max, camera fixed.
* **The Python watcher** reads the progress file and has a stall timeout of 60 s and a total timeout of 15 min. It
  says when it ends.

## The tests, in order (about 30 min of game time)

**T1. Is it the world or the mod? (about 6 min)** Suspect 1 goes first, because a world still loading looks like a leak.
* A: teleport to the 2.3 km spot in state `none`. Log for 2 min from arrival.
* B: same teleport, then `benchState('running', 2300)`. Log for 2 min from arrival.
* Same fall in both: the world is the trend, and the settle gate handles it.
* Also gives the real settle time, which sets the gate.

**T1b. GO on the start line: the reproduction gate (about 12 min)**
* The one clean drop seen before: 156 fps waiting on the line, 82 fps once the clock ran, car stopped.
* On the line: `waitStart` settled (the base), then GO recorded from GO for 20 s with no warm-up and no settle
  (the start clock is fed until the clock reaches 8 s), then `running` settled, then the mod idle on the same spot.
* 3 pairs, the idle floor first in the middle pair.
* **If no gap shows here or in T1, the switch A/Bs (T3, T4) measure noise around zero:** say so, do not chase them.

**T2. Where does a slow frame go? (about 3 min)** At the 2.3 km spot, settled, in `running`:
* one Optick capture of 10 s with the run;
* one Optick capture of 10 s with the run aborted, same spot.

Read: main thread vs render vs GPU wait; which Lua extension; whether CEF shows.

**T3. What does GO switch on? (about 12 min)** At the 2.3 km spot, settled, in `running`. Take one thing away at a time:
1. HUD streams: `earthRally_main.STREAM_FIXED_HZ` 30 vs 1 (nil: on change).
2. Stock stage apps: stage layout vs plain layout.
3. Co-driver: `rallyAdapter.notesOn(true)` vs `(false)`.
4. Start clock: is `gameplay_rallyStartClock` loaded, and are spikes 1 s apart?
5. Props: shown vs hidden.

Floor: the whole mod unloaded at the same spot.
Repeat only the winning switch at the 4.6 km spot, to check it holds.

**T4. The spawn spikes (about 4 min)**
* Arriving at a spot spawns that stretch's dressing.
* Measure the 10 s after arrival, with `props.DRESS_OBJS_PER_UPDATE` 24 vs 2.
* Alternated over the 2.3 km and 4.6 km spots, 2 arrivals each.
* Line up frames over 50 ms with hook max times and the node count.

**T5. After the run (about 3 min)**
* At the 4.6 km spot, in `finished` (via `wrapUp`, no result written).
* Traffic on vs off.
* Count `stage layout back on` lines in `beamng.log`.
* Check whether `gameplay_rallyStartClock` is still loaded.

**T6. Offline, no game (about 1 min)**
* Dump the road graph at each spot during T3.
* Time `roadAt`, `roadCovers`, `nearEdges` and one whole site's placement in LuaJIT.

**T7. The player's case (about 2 min)**
* Repeat the winning A/B at the 2.3 km spot with a 60 fps cap, so it reads like 60 to 20.

## Quick check, after every fix (about 5 min)

The same short run each time, so fixes can be compared with each other (about 15 min):
* GO on the start line vs the mod idle, 2 pairs.
* Weaver Bend, the 2.3 km spot, settled: `running` vs `none`, 3 pairs alternated.
* One 10 s arrival at 2.3 km in `running` for the spawn spike.

The first quick check runs on `main` before any fix, as the baseline.

## Performance dashboard

The point is to see each fix move the numbers, commit by commit.

**Data**
* `tools/perf_report.py` reads `earthRally/bench/*.json` and appends one summary line per capture to
  `perf/history.jsonl`.
* Each line holds:
  * the commit, branch, whether the tree was dirty, and the date;
  * the test, stage, spot, state and switch;
  * the frame count, p50, p95 and p99, and frames over 33 and 50 ms;
  * the spread between pairs;
  * the engine category means, and each hook's max and mean;
  * CPUBusy and GPUBusy when PresentMon ran.
* Summaries only, a few KB a run, so `perf/history.jsonl` goes in git: the history travels with the code.
  The raw frame files stay in the user folder.

**Page**
* `tools/perf_dashboard.py` writes `perf/dashboard.html`: one self-contained file, opened in a browser, no server.
* It can also be published as a private claude.ai page to look at from another device.

**Mock-up**

```
Earth Rally performance          Weaver Bend, 2.3 km   [state: running v]  [metric: p99 v]
---------------------------------------------------------------------------------------
 Frame time per commit (ms, lower is better)          60 fps ------  30 fps - - - -
  40 |  o
  30 |  |\                                           o = running   x = none (floor)
  20 |  | o--o
  10 |  |     \o---o
   0 |  x--x--x--x--x
       base  fix1 fix2 fix3 fix4
       6ad8 1a2b 3c4d 5e6f 7a8b

 Latest vs baseline      p50     p99    >50 ms/min   gap to floor
   running             -4.1 ms -18.2 ms   -41          12 % left
   spawn arrival         --    -60 ms     -9           --

 Where the frame goes (running, latest)   Lua ##  Render ###  UI #  Present #######
 Earth Rally hooks, max ms               props.update 3.2   runner.update 0.4   sendStreams 0.1
 Last capture, frame trace (20 s)        _._.__|___._.__|__   (| = frame over 50 ms, hover: hooks that frame)
```

* **Trend:** p50 or p99 per commit, `running` against the `none` floor, with 60 and 30 fps lines.
* **Latest vs baseline:** what the last fix gave back, and how much of the gap to the floor is left.
* **Breakdown:** the engine categories as a stacked bar, then the Earth Rally hooks by max time.
* **Trace:** the last capture's frame times, spikes marked, hover for the hook timings in that frame.
* **A result inside the spread between pairs is grey**, marked "no change", so noise is never read as a win.

**When:** built with the recorder, before the first in-game run, so the baseline lands in it.

## Known blind spots (from the review, 2026-11-15)

* **A car standing still** leaves the HUD's progress, speed and distance unchanged and calls no pacenote, so the
  streams and notes A/Bs read the idle cost of those systems, not their cost while driving.
* **A settled world** is not what a driving player sees: BeamNG.Earth keeps loading as they go. T1 (no settle) and
  the arrival captures are the only unsettled measurements.
* **One spot, reached by a 2.3 km move**, holds less world (statics, road nodes) than a player has built up by
  driving there. Compare `counts` with a driven run before trusting a spot result.
* **Low preset on a fast desktop** hides GPU-side costs (draw calls, shadows, lost batching). Run the deciding A/B
  at the player's preset too.
* **`none` is the mod idle** (the run aborted, BeamNG.Earth's layout back), not the mod unloaded.

## Out of scope

* Fixing anything. Findings first.
* BeamNG.Earth's own streaming cost, beyond naming it if T1 points there.

## Afterwards

* Findings and the ranked fixes go in `docs/notes-1.6.1.md`.
* Remove the bench hook.
* Put back the graphics preset Normal and the background fps limit (`restore-settings.json`), `clockView` back to
  `right`, and the power plan.
* Abort any run left open.
