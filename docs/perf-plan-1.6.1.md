# Performance test plan, 1.6.1

**Status: draft, waiting for approval.** Nothing in this plan runs in the game until it is approved.

**Question:** what takes a player from 60 to 20 fps on a stage, and is it Earth Rally?

## What we know already (measured 2026-11-15, this desktop, Low preset)

* **Idle, mod loaded vs unloaded:** no difference. The mod costs nothing until a stage is on.
* **On the start line (waitStart):** 156-166 fps.
* **Clock running, car stopped 32 m in:** 82 fps, p99 32 ms.
* **1.7 km in:** 30 fps, with 731 frames over 50 ms in 10 s.
* **After the run (state none):** 23 fps.
* **Lua is not the bulk of it:** 2-4 ms a frame, render about 2 ms, UI JS tiny. Lua spikes reach 74-164 ms.
* **Already cheap:** `props.update` (mean 0.01 ms), `runner.update` (0.04 ms), `roadAt` (0.06 ms).
* **Not reliable:** those runs teleported the car and polled the game over MCP every 10 s. They show where to look, not the answer.

## What the research says (deep research, 2026-11-15)

* **GE Lua runs on the main thread.** The Lua profiler sees its own time, not what it sets off: UI repaints, draw calls,
  shape loads. A small Lua number clears nothing.
* **BeamNG's own pitfalls:**
  * UI data sent every frame ("really bad").
  * Table and vector churn (GC spikes).
  * Dynamic or animated statics, which lose batching.
* **Engine-wide first:** PresentMon logs FrameTime, CPUBusy and GPUBusy per frame. That says whether a drop is CPU or GPU
  bound, which in-game numbers cannot.
* **Judge by slow frames:** p50, p95, p99 frame time, A/B alternated, one tool for every run.
* **Not settled by research:** how big any of these costs is in BeamNG. Every forum figure failed verification. We measure it.

## Suspects from the code audit

| # | Suspect | Where | Why it fits |
|---|---|---|---|
| 1 | World still loading after the run's teleport and origin move | `runner.lua:485` | Steady fall, stays low after `tidy()`, Lua flat |
| 2 | Stock stage apps switched on at GO, timing streamed at 30 Hz | `hudFrame.lua:226-247`, `main.lua:1006` | Only change that lines up exactly with GO |
| 3 | Dressing spawn bursts: whole road-graph scans, up to 24 objects a frame | `props.lua:942`, `:454` | The 74-164 ms spikes; grows as the graph grows |
| 4 | Stock start clock rescanning every TSStatic once a second | `gameplay/rallyStartClock.lua:476` | Thousands of statics on Earth; may outlive the run |
| 5 | Co-driver engine switched on at GO | `rallyAdapter.lua:93` | Starts at GO; should already be inside the Lua number |
| 6 | Stage layout re-applied every second if something flips it | `runner.lua:1584-1597` | Each swap rebuilds every CEF app |
| 7 | Traffic and parked cars back after the run | `runner.lua:903` | Would explain 23 fps after the run |

No per-run leak was found.

## Method, for every test

* **Recorder in the game** writes JSON to `earthRally/bench/`. It records:
  * `hptimer` frame gaps;
  * the engine's time categories;
  * max (not just mean) time around each Earth Rally hook;
  * memory churn;
  * the TSStatic count and the road-graph node count;
  * BeamNG.Earth loading status.

  MCP only starts it, and those frames are dropped. No polling.
* **PresentMon** runs beside it for CPUBusy and GPUBusy. It is not installed: needs your OK to download.
  Without it, Optick and the engine categories stand in.
* **The AI drives** (`erdrive.lua`). No teleports while measuring. The mod's own **Go to start** resets between drives.
* **Each capture:** 10 s warm-up, then 30 s capture, one change at a time, alternated A B A B, 3 pairs.
* **Report:** p50, p95 and p99 frame time, frames over 33 and 50 ms, and the spread between pairs.
* **A cause counts** when removing it gives back more than 20 % of the gap, outside the spread between pairs.
* **Controls:** vivace, Low preset, vsync off, background fps limit off, power plan max, BeamNG.Earth not loading
  (`earth.loading()` nil) before each capture.
* **Every background script** gets a stall timeout and a total timeout, and reports when it ends.

## The tests, in order

**T1. Is it the world or the mod? (about 8 min)** Suspect 1, first, because a world still loading looks like a leak and
spoils everything after it.
* A: start a run, sit in waitStart for 3 min, no skip.
* B: freeroam at the same start, no run, 3 min.
* Log fps, Earth loading status and the TSStatic count every second.
* Same fall in both: the mod is cleared of the trend, and later tests wait until the world has settled.

**T2. Where does a slow frame go? (about 3 min)**
* One Optick capture of 10 s on the stage, run active, after T1's settle time.
* One capture of the same stretch with no run.
* Read: main thread vs render vs GPU wait; which Lua extension; whether CEF shows.
* Names the suspects worth T3.

**T3. What does GO switch on? (about 10 min)** Car stopped 300 m in, clock running, world settled. Take one thing away
at a time:
1. HUD streams: `earthRally_main.STREAM_HZ` 30 vs 1.
2. Stock stage apps: stage layout vs plain layout.
3. Co-driver: `rallyAdapter.notesOn(true)` vs `(false)`.
4. Start clock: is `gameplay_rallyStartClock` loaded, and are spikes 1 s apart?
5. Props: shown vs hidden.

Floor: the whole mod unloaded at the same spot.

**T4. The spikes (from the T5 data, plus one pair)**
* Line up frames over 50 ms with hook max times and the node count.
* One pair with `props.DRESS_OBJS_PER_UPDATE` 24 vs 2: do the spike frames go?

**T5. What does driving add? (about 8 min)**
* The AI drives the same 1 km three times with a run and three without, alternated.
* Catches dressing placed and removed, pacenote calls, streaming.

**T6. After the run (about 4 min)**
* Same spot, after `tidy()`, traffic on vs off.
* Count `stage layout back on` lines in `beamng.log`.
* Check whether `gameplay_rallyStartClock` is still loaded.

**T7. Offline, no game (about 1 min)**
* Dump the road graph at a small stage (Maryhill, 176 nodes) and a dense one (OTR Founders).
* Time `roadAt`, `roadCovers`, `nearEdges` and one whole site's placement in LuaJIT.

**T8. The player's case**
* Repeat the winning A/B on OTR Founders at a 60 fps cap, with p99 as the measure, so it reads like 60 to 20.

## Out of scope

* Fixing anything. Findings first.
* BeamNG.Earth's own streaming cost, beyond naming it if T1 points there.

## Afterwards

* Findings and the ranked fixes go in `docs/notes-1.6.1.md`.
* Put back the graphics preset Normal and the background fps limit (`restore-settings.json`), `clockView` back to
  `right`, and the power plan.
* Abort any run left open.
