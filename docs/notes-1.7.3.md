# 1.7.2 notes: a faster, sturdier auto recce

Branch `fix/recce-speed`, from `main` at 1.7.1. Build: `1.7.1-alpha+recce`. Part A of `docs/plan-recce-speed.md`.

## What changed

- **A full rally queues every download up front** (item 1). When the prep starts, every stage that needs a line
  is priced at once. The ones missing map data get their area added in the rally's order. Each stage is then
  taken to and matched as its own download finishes, so stage 2 downloads while stage 1 matches. A stage with an
  area in `settings/earthRally_areas.json` uses it: no duplicates. The single-stage button is unchanged: priced and
  asked every press.
- **A window that times out or errors is asked again, twice** (item 3). If it still fails, the stage ends red:
  "BeamNG.Earth did not answer for this part of the stage (timed out), so try the auto recce again". It no longer
  says "no map data". A window with map cells missing is not retried and still says "no map data".
- **The car is put on the road after the match** (item 4). When the landing found no road at the ATC, the car is
  set down from the matched file's ATC: 40 m before the board, facing it. Not during a full rally's prep: the
  next stage's teleport moves the car anyway.
- **Lighter matching on long stages** (item 6). The distance of each road node to the organisers' line now uses
  the segment grid. Same edges, same weights, same matched file: `test_autorecce` checks it against the old code.
- **One timing line per auto recce** (item 7). In `beamng.log`:
  `auto recce timing: <stage>: price 2.1 s, download 106.0 s (34.0 MB), teleport and settle 5.2 s, windows 55.0 s (9), match 0.014 s, total 170.3 s (done)`.
  A rally's stages add "queued with the rally"; their download counts from when the area was added.
- The time card's tracker: the stage whose turn it is shows "Checking the map data" while its estimate is out.
  Waiting stages carry their download's progress in the data (`area`), not yet shown (item 5, mock-up).

## To test (no driving)

- **Cold single stage.** Auto recce a stage with no map data, say Download. In the log, read the
  `auto recce timing:` line. Compare with the same stage on 1.7.1 (the logs of 2026-11-16).
- **Warm single stage.** Press it again: the timing line should show no download and short windows.
- **Landing.** After a match that landed with "no road on the map there", the log says
  `the car set down from the matched ATC`. The car is on the road before the ATC board, facing it.
- **Full rally.** Start the Warden test rally (3 stages) with no lines. The log shows
  `rally: pricing the map data of 3 stage(s) at once`, then one `took the area ... queued` per stage needing data.
  BeamNG.Earth's area list shows them all at once, in stage order. The time card goes through the stages in turn.
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
- **Item 5** (size and time next to "2 of 59"): mock-up only,
  [`docs/mockups-1.7.2/download-progress.html`](mockups-1.7.2/download-progress.html). Waiting for the owner's OK.
- **Part B** (lat/lon road graph, narrower ring): needs a fork release.
- A queued stage whose estimate or add is not answered in 5 minutes falls back to the 1.7.1 way for that stage.
  If its add was still in flight, that stage could get a second area. Not seen; BeamNG.Earth answers in seconds.
