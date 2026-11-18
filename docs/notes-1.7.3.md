# 1.7.3 notes: a faster, sturdier auto recce

Branch `fix/recce-speed`, from `main` at 1.7.1, merged with 1.7.2. Build: `1.7.2-alpha+recce`. Part A of
`docs/plan-recce-speed.md`. Item 5 (size and time next to the count) shipped in 1.7.2 as the download progress bar.

## What changed

- **A full rally looks one stage ahead** (item 1, made safer on the owner's word, 2026-11-17). While a stage runs
  its own auto recce, the next stage is priced and, if map data is missing, its area added. So stage 2 downloads
  while stage 1 matches. Only the next stage: Stop or leaving the rally leaves at most one extra download.
  - Stage 1 goes the 1.7.0 way: priced, the question answered yes for the player.
  - At its turn a looked-ahead stage follows its own download, with no new estimate.
  - A look-ahead estimate that failed or timed out is not "nothing missing": the stage is priced again at its turn.
  - An add BeamNG.Earth refused: at its turn the stage is matched with what is here and the ending says why.
  - Not answered `QUEUE_WAIT_S` (300 s) after its turn came: given up, and a late answer adds nothing. An add still
    out is booked if it is taken later; the stage is matched with what is here.
  - A looked-ahead area missing from BeamNG.Earth's list, added more than `AREA_GONE_S` ago, counts as deleted.
  - A stage with an area in `settings/earthRally_areas.json` uses it: no duplicates.
  - **Stop** names the look-ahead's download when one was added and is still going:
    "Auto recce stopped. Map downloads already started, Stage Two's too, carry on in BeamNG.Earth's Areas."
  - The single-stage button is unchanged: priced and asked every press.
- **A window that times out is asked again after 2 s** (item 3), twice. Timeouts, exceptions and answers that could
  not be read are retried. If it still fails, the stage ends red: "BeamNG.Earth did not answer for this part of the
  stage (timed out), so try the auto recce again". It no longer says "no map data".
  - Errors that asking again cannot change end at once with their own reason: BeamNG.Earth's roads off, started
    without roads, no world yet, bad coordinates (the strings in the fork's `server/earthd.py` road_graph handler).
  - A window with map cells missing is not retried and still says "no map data".
- **The car is put on the road after the match** (item 4). When the landing found no road at the ATC, the car is
  set down from the matched file's ATC. With the road map in by now: 40 m before the board on the road, facing it.
  Without it: on the matched ATC road point, at its ground height, turned along the road toward the start. That keeps
  it inside `DRIVEN_THERE_MIN_M` (15 m) of the board, so Run stage sets it down properly later. Not during a full
  rally's prep: the next stage's teleport moves the car anyway.
- **Lighter matching on long stages** (item 6). The distance of each road node to the organisers' line now uses
  the segment grid. Same edges, same weights, same matched file: `test_autorecce` checks it against the old code.
- **One timing line per auto recce** (item 7). In `beamng.log`:
  `auto recce timing: <stage>: price 2.1 s, download 106.0 s (34.0 MB), teleport and settle 5.2 s, windows 55.0 s (9), match 0.014 s, total 170.3 s (done)`.
  A looked-ahead stage adds "queued with the rally"; its download counts from when its area was added.

## To test (no driving)

- **Cold single stage.** Auto recce a stage with no map data, say Download. In the log, read the
  `auto recce timing:` line. Compare with the same stage on 1.7.1 (the logs of 2026-11-16).
- **Warm single stage.** Press it again: the timing line should show no download and short windows.
- **Landing.** After a match that landed with "no road on the map there", the log says
  `the car set down from the matched ATC: on the matched ATC road point` (or `on the road map`). The car is on the
  road at the ATC, facing the start. Press Run stage: it should set the car down 40 m before the board.
- **Full rally.** Start the Warden test rally (3 stages) with no lines. The log shows
  `rally: pricing the map data of <stage 2> ahead of its turn` while stage 1 runs, then
  `took the area ... downloading ahead`. BeamNG.Earth's area list never has more than the current stage's and the
  next one's being added.
- **Stop all** during the prep, after stage 2's area was added: the message names stage 2's download.
- **Rally twice.** Delete the matched lines (Reset) and start the rally again: no new areas in BeamNG.Earth's list.
- **The owner's own check:** drive a stage after the auto recce, from the ATC.

## Item 2: does BeamNG.Earth say when the world has settled?

Research only, nothing built. What the mod can read today:

- `api.ready()` is `core.groundReady()`: no pending teleport, the car placed, the drop hold over. The auto recce
  already waits for it plus `TELEPORT_SETTLE_S` (2 s). It does not mean the block is graded or the roads are in.
- **Graded block:** the server's `anchor_ready` carries `provisional`, and the graded block follows as
  `terrain_refresh`. `core.lua` does not keep that flag, so nothing says "graded yet". Not readable.
- **Road tiles:** `roads.readyAround(anchorId, x, y, r)` (internal, `beamngEarth/roads`) says whether the road
  tiles within r are made and solid. `roads.status()` gives `queued` and `walksQueued`. Readable through
  `package.loaded`, not part of the API.
- **The game's road map** (what `props.roadAt` and `faceAtc` read): BeamNG.Earth's `navgraph.lua` resets the
  game's map when the server's `navgraph` for the anchor arrives. `navgraph.graph().anchor` and
  `navgraph.status().applies` say whether the map is the new anchor's. The game also fires
  `onNavgraphReloaded`, which `main.lua` already receives. This is why every 1.7.1 landing said "no road on the
  map there": the car is placed before this reset.
- **The server being busy:** nothing. `api_pool` is one thread with no queue length exposed.

Proposed change:

- **In the mod, now possible:** after `api.ready()` and the 2 s settle, wait (at most about 20 s) until the
  game's map has been reset since the teleport (an `onNavgraphReloaded` after it) and `roads.readyAround` is true
  round the car, read tolerantly through `earthAdapter.internals()`. Then place the car and ask the first window.
  This would also fix item 4 at its root.
- **In the fork (fork.2, with Part B):** `api.has('worldSettled')` and `api.worldSettled()` returning
  `{ ground, graded, roads, roadMap }`, plus a `worldSettled` event. `graded` needs `core.lua` to keep
  `anchor_ready.provisional` and clear it on `terrain_refresh`.
- Measure first: item 7's timing line, cold and warm, before and after.

## Not done

- **Item 2** (wait for the world): research above, nothing built.
- **Part B** (lat/lon road graph, narrower ring): needs a fork release.
- **The look-ahead's download is not shown** on the waiting stage's row: no UI without a mock-up.
- **Item 4, a matched road point 15 m or more from the board:** not used. The car stays on the raw point for Run
  stage to set down. The match snaps a control up to 30 m (`CONTROL_SNAP_M`).
