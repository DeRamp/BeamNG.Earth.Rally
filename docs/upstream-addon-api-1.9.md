# Pull request #1249 body -- api.roadGraph AND the route corridor, as modding API 1.9

This replaces `upstream-roadgraph.md` and `upstream-area-route.md` as the body of
<https://github.com/TecnaGamer/BeamNG.Earth/pull/1249>: the two calls were sent as one change (the owner,
2026-11-14: "please also merge any changes you made to earth into the same PR we sent out earlier").

**Title**

```
Modding API 1.9: a road-graph window an add-on names, and the ground along a route downloaded ahead
```

**Body** (exactly what is posted; nothing below the end marker is part of it)

---
An add-on that needs to know where the roads *are* -- not where the player is -- has nothing to ask, and an
add-on that wants ground the player has never driven has nothing to ask either. This adds both halves, as modding
API **1.9**:

* **`api.roadGraph(lat, lon, opts, callback)`** -- one window of the road graph round a point, built out of what is
  already on disk, fetching nothing.
* **`api.areaPlan(points, opts, callback)` / `api.areaAdd(...)` / `api.areaStatus(id)`** -- what a corridor along a
  route would cost, and the corridor added to the player's own saved areas, through the download tool that already
  exists.

**They are here together because each is the other's missing half.** A road graph that never fetches is the right
answer for a read on the player's frame budget -- it must not outrun the world's own downloads or your rate limits
with your sources -- but it leaves an add-on over unvisited ground with few roads and `complete: false` and no way
forward. The second call is that way forward, and it deliberately does **not** teach the graph to fetch: it goes
through the saved-area tool, which is already gated against hurting the running world, already visible to the
player, already resumable, and already theirs to pause or delete.

They were written on branches of their own and each took the next minor; as one change they are one minor, 1.9,
with `roadGraph` and `areaRoute` both in `FEATURES`.

I write a rally add-on that uses both: it puts a real rally stage on BeamNG.Earth's roads with no recce driven, and
where the map data is missing it offers to fetch the corridor first. Everything below was measured on that, in a
game, on this branch.

## 1. `api.roadGraph`: one window of the road graph


* **`Server.build_navgraph`'s in-process body is now `Server.road_graph_data(aid, x, y, window, cached_only)`**,
  returning `(graph, cells not read)`. `build_navgraph` calls it and keeps its sweep, its write and its logging
  exactly as before, so the player's graph behaves as it does on `dev`. **The pooled branch
  (`self.road_pool is not None`) is untouched by design:** an add-on's request must never take a slot the player's
  world needs, so a request is always built in `api_pool`, the single thread `places` already answers on, and never
  in the road pool.
* **The player's graph file is never a candidate for a request's sweep.** `navgraph.write` takes a filename prefix
  (default `"navgraph"`, so nothing changes for the player) and a request writes `roadgraph_{aid}_{serial}.json`,
  which no part of the mod reads as the AI's graph; `"roadgraph"` joins `ANCHOR_TILE_FILES` so those files are
  cleaned up with the anchor. A successful request sweeps **its own** files down to the newest `ROAD_GRAPH_KEEP` (2,
  so a callback still has time to read the one it was handed) and matches only `roadgraph_{aid}_*.json`.
* **`navgraph.build` is untouched.** `centre` and `window` are already its parameters, and a request's radius is
  passed as `window`. No field, no id scheme and no output format changes, so an add-on reading a requested graph
  reads the same shape the session graph already has.
* **The answer carries the graph, not the name of a file.** `_onRoadGraph` reads and decodes it, so a callback
  gets `nodes`, `edges`, `signals`, `rules`, `lines` and `mph`, with `path` beside them for an add-on that would
  rather read the file itself. `api.places` answers with its rows the same way; an add-on has no business knowing
  the layout of the session folder; and because only the last two graphs of an anchor are kept, a caller that held
  the path rather than the tables could find the file gone. A graph that is built but will not read back is an
  error with `complete` false, rather than an answer that looks empty.
* **A `road_graph` request**, alongside `places`: `{type: "road_graph", id, lat, lon, radius, cachedOnly}` ->
  `road_graph_result {id, nodes, edges, …}`. **The point travels as `lat, lon` and is converted inside
  `road_graph_data`, in the frame the build itself uses** — not by the handler. That matters: the anchor can be
  re-centred while a request waits for the pool, and coordinates worked out before that are then read in a frame
  that has gone. Found in a game: every window of a request landed about 19 km from the point asked for, the same
  offset each time, and because cells over there happened to be cached it answered `complete` with no roads in it. `radius` is clamped to `ROAD_GRAPH_RADIUS_MAX_M` (2000 m, against the session's
  own `WINDOW_M` of 1100: a graph's cost grows with the square of its window) and defaults to `WINDOW_M`. Anything
  that cannot be served answers with a readable `error` rather than throwing: bad coordinates, no map data, a server
  started without roads (`self.s.traffic`, fixed at construction), no anchor committed yet.
* **`cachedOnly` reads the window's layers only where they are already on disk,** through `load_cells` at
  `kind="background"` — the same call the session's own graph uses, so a layer arrives with the same decoding, tag
  joins and neighbour discovery, and a cell that is not there raises rather than being fetched. (An earlier draft
  used `MapData.layer_unkept`, which exists for the API's cachedOnly *places* read. Places do not need those joins;
  roads do, since drivability and road class come from them. In a game that built **0 nodes** from a window whose
  cells were all present — intermittently, because `layer_unkept` answers from `MEM_MB` when the player's own path
  has just filled it.) **That rule covers every layer the graph reads, not only the roads.** `furniture.signals_for`,
  `secrossings.read` and `blockworker._de_routes` each read their cells through `cell(kind="demand")`, which
  downloads at the highest priority there is; a cached-only build takes the `infrastructure` and `road_routes`
  layers from disk too (`mapped_signals` / `secrossings.nodes` over what is there), so "nothing is downloaded" holds
  for all of them and not just the headline one. A point whose cells are not on disk answers `complete: false`
  rather than pulling them. This matters more here than it does for places — a road window is a wide read, and an
  add-on asking for several would otherwise raise the server's own request rate against its upstream sources, whose
  published limits `netfetch` deliberately keeps under. The flag is the request's only mode in this change: there is
  no fetching form of it to get wrong.
* **The rule covers the ground and the cells around the window too, not only the layers the build names.** Two
  reads reach past the cells `cachedOnly` hands the build, and both go at `demand`. `road_graph_data`'s `elev`
  closure samples the DEM, which downloads a tile that is not on disk — the ground of a 16 km window is about 150
  z16 tiles, ~15 MB, at the same priority as the block the player is waiting for. And every decoded roads layer
  carries `MapData`'s own hook to the eight cells around it, which `roads.level_ranges` and `roads.home_copy` read
  while the graph is built: a 2-cell window reached for 17 more cells at `demand`, a 6-cell one over a real cached
  region for 35. A cached-only build now runs in one lane that closes both. `Dem.cached_only()` is checked in
  `_download`, the single place every DEM tile download goes through (Mapterhorn, its CDN packs, AWS and the file
  list), and its loads run in the calling thread rather than the DEM pool, so a read that cannot download is never
  the shared future a block the player waits on ends up waiting for. `gradesep.cached_only()` asks `MapData.has`
  first and then reads at `kind="background"`, the same rule the window's own cells already follow. Both are this
  thread's lane and nothing else sets them, so `build_navgraph` and every other caller run the code they run on
  `dev`.
* **What is not cached is read coarser, never invented, and `complete` stays the question an add-on asks.** The
  graph samples at the anchor's own zoom, which is deeper than Mapterhorn's deepest, so the tile it asks for is one
  the world itself only ever derives from a coarser one — most of the planet has no z16 tile at all. A lane that
  refused every tile it did not have cached would therefore empty windows whose roads were all present, so inside
  it a tile that is not cached is answered the way a source with no tile there is answered and `_make_tile0`'s own
  chain reads the coarser cached tile: measured elevation, upsampled, exactly what the world is built on wherever
  nothing deeper is published (with the z16 tiles of a real cached region removed and only their z15 parents left,
  0.02 m from the real heights on average, 0.28 m at worst, nothing downloaded). AWS is the floor of that chain
  and has no ancestor under it, so a tile it cannot answer for raises instead and the window comes back **empty
  with `complete: false`** rather than at sea level: a node at an invented height reads exactly like a measured one
  to an add-on, which has no way to tell them apart. A tile made with a stand-in is kept for that one build and
  never put in the DEM's LRU, which is the world's: the player's next read of it must download the real one.
* **`complete` is about the window's own cells, deliberately.** A build also reads the eight cells around each of
  its own (`gradesep`) and the land cover a road's surface rule asks for; where one of those is not on disk it goes
  without it exactly as it does when such a read fails for the player, and nothing made short of it is kept
  (`revisit.fault`). That changes a bridge range at the edge of a window, not which roads are in it — and
  `complete` is read as "are these all the roads there are", so answering false for it would have an add-on throw
  away a window it can use. The build runs inside a `revisit.scope()` so those faults stay in it: a fault in a
  thread with no scope of its own is the process's, and without one an add-on's request over ground nobody has
  driven would stop the player's own road tiles being kept in the revisit cache while it ran.
* **`api.lua`: `api.roadGraph(lat, lon, opts, callback)`**, with the request table, the id and the timeout sweep
  copied from `places` — one in-flight table, `_onRoadGraph` dispatching to the callback inside a `pcall` that logs,
  a timed-out request answering `{error = 'timed out'}` rather than hanging. Its wait is its own
  (`M.ROAD_GRAPH_TIMEOUT_S` 90 s, under the places 150: no download is ever waited on, so what is left is the build
  and the requests queued ahead of it). `MINOR` bumped with a `roadGraph` capability name beside the existing flags
  rather than over them, as every minor since `options` has had one, so `has('cachedPlaces')` and the rest still
  answer true.
* **`core.lua`** routes `road_graph_result` to `api._onRoadGraph`, as it already does for `places_result`.
* **`docs/ADDONS.md`**: the call, its `opts` and result tables, the graph's own field layout for an author who has
  not read `navgraph.py`, and the limits below.
* **Untouched:** the session graph and everything fed from it, `map.reset`, traffic spawning, the `--traffic` /
  `--roads` gating, the minimap's tunnel `lines`, and every existing API call and capability flag. An add-on that
  never calls `roadGraph` cannot tell this landed.

### What it does not promise

* **Nothing is downloaded: no map cell and no elevation tile.** Cached-only is the whole contract — every layer the
  graph reads, the cells around them its road rules reach for, and the ground under the nodes. A window over ground
  the player has never been near comes back with few nodes and `complete: false`, and one over ground the app has
  no elevation for at all with none. That is the honest answer rather than a slow one, and `docs/ADDONS.md` says
  what it covers rather than letting an author infer a stronger promise.
* **It is not the AI graph.** A requested graph is written to its own file and never reaches `map.reset`, so it
  cannot move the cars or the traffic.
* **There is no bridge flag.** Nodes on a bridge take the deck height, which is the right height, but nothing in
  `nodes` or `edges` says "this stretch is a bridge". An add-on cannot recover that, and the docs say so rather than
  let an author infer it from the heights.
* **It depends on the server having roads at all.** `--traffic on` and `--roads on` are fixed at construction, so a
  server started without them answers nothing. `has('roadGraph')` cannot see that, so the result carries the reason.

## Why a window rather than a matching call

The first shape considered was an API that did the matching — hand it a line, get back the line on the roads. A
window is the smaller ask in every direction that matters to this repo: it is one wrapper over a function already
run every 400 m, it adds no algorithm for you to own, and the matching's own bugs stay with the add-on that wants
it rather than arriving here as issues. It is also more useful to more than one caller — a route painter, a trail
tool and a stage matcher all want the same window and would each want a different matching call.


## 2. The ground along a route: `api.areaPlan` / `areaAdd` / `areaStatus`


* **`Connection._area_route` takes points as well as `"current"`**: `"route": {"lat": [...], "lon": [...]}`, the
  shape `areas.json` already persists and `areas.check_route` already validates, so nothing in the handler converts
  or re-checks anything and the store's own re-validation on load stays the single implementation. Without it,
  explicit points fell through to the **box** path and the caller was answered *"an area needs south, west, north
  and east in degrees"* — not an error a caller holding a line can act on. The player's own `area_plan` /
  `area_add` accept the same form; the 3D map is untouched and still sends `"current"`.
* **`area_add` now answers a malformed route** instead of dropping it. `_area_route` was called outside the
  handler's try, so a bad message raised in the spawned task and the client was never told anything at all.
* **A one-point line is told what is wrong with it.** `check_route`'s *"no route: plan one with the GPS first"* is
  the right sentence for `"route": "current"` with nothing planned, and nonsense for a caller that sent one point,
  so the empty case keeps it and one point gets *"a route needs at least two points"*. Mismatched list lengths get
  their own line rather than sharing either.
* **`areas.check_layers`: an area may download a subset of the layers.** `plan_steps` already took `layers`;
  `phase_steps` and `steps` now pass one through, and `terrain` and `imagery` are names in the same list because an
  area downloads them too and a caller that wants one layer of the ground does not want the aerial photography of
  it either.
  Measured on a 300 m corridor over a 10 km line: **549 items and 309 MB for the whole ground, 51 items and
  31 MB for `['roads']`** — 9 % of the items, 10 % of the bytes. (Pinned disk only halves, 125 MB to 67 MB, because
  a cell's raw source blocks are shared by its layers and are downloaded whichever layer you asked for. That is
  the honest figure and `plan_route` reports it.)
  * The subset is **stored with the area and re-validated on every load**, like the route's points. It has to be:
    `_pass` re-plans from the stored shape on every pass and after every restart, so an unstored subset would
    silently turn a one-layer area back into a twelve-layer one — and `total` is recomputed at the same moment, so
    nothing would look wrong.
  * `plan_route` **echoes the subset it honoured** (`"layers"`, `[]` for all of them). An older server ignores the
    field and downloads everything, and a capability flag is the *mod's* version, not the app's, so a caller needs
    a way to see that the field landed.
  * Naming every layer is not a subset: `check_layers` answers `None`, so the stored plan stays the plain one and a
    later `all_layers()` is not frozen out of it.
  * **Refused with a mode that builds the world.** A geotile's content is built from the roads, buildings, water,
    land use and land cover of its cells at once, so a narrowed world phase would bake a world with pieces missing
    and keep it pinned, out of the revisit trim, as though it were finished.
  * A narrowed area is **not a finished world**, and `docs/ADDONS.md` says so: what it left out is downloaded on
    demand when the player arrives, exactly as it is anywhere they have not been.
* **`Areas.message()` carries `unavailable` for every area, and `layers` where there is one.** This is the part of
  the change I would most like reviewed, because it is about a promise the existing API quietly breaks:
  **`state: "done"` does not mean the data arrived.** After `MAX_FAILED_PASSES` the items still failing are counted
  unavailable and the area is marked done (`areas.py` `_pass`), and the player reads that off `msg`. A caller that
  has to decide whether to trust the ground needs the number, and inferring it from a sentence is not a contract.
  The one saved area on the machine this was written on finished `done` with **122 of its 1079 items unavailable —
  11 %** — after three failed passes, which is what made this worth insisting on. `_add` now sets `unavailable` and
  `failedPasses` to 0 so every area has them from the moment it exists rather than from its first finished pass.
* **Two new messages, not the existing ones**: `area_route_plan` / `area_route_add` ->
  `area_route_plan_result` / `area_route_add_result`. They could have shared `area_plan` / `area_add`, and they
  must not: the mod keeps **one answer at a time** (`core.lua` `M._areaPlans = { [msg.id] = msg }` and
  `M._areaResults`, replaced rather than added to, and `requestAreaPlan` empties the table before it sends), so an
  add-on sharing those types would take the player's answer out of the area confirm box, or lose its own to it.
  Giving a request its own type is also what lets the handler refuse things structurally rather than by checking:
  * **`fast` is never read from `area_route_add`.** Not defaulted, not validated — the field does not appear in
    the handler. In fast mode every gate that keeps a download from slowing the world is skipped, and the pause
    that makes that survivable is applied by the **mod**, for **any** client, on **any** fast area
    (`core.lua` `fastAreaPause` -> `simhold.pause(true)`): an add-on able to set it could stop the player's physics
    in the middle of whatever they were doing, with no say for the add-on actually driving them. `api.lua` has no
    argument for it either, so there is nothing to leave out. A test sends a **forged** `"fast": true` on this
    message and requires `fast_id` to stay `None`, because api.lua not sending it is politeness and the handler not
    reading it is the guarantee.
  * **`mode` is not read either**: it is always `"data"`. Building the world ahead puts the server's road
    processes to work over every core, and that is the player's choice to make from their own map where they can
    see what it costs.
  * **`"route": "current"` is refused on these types.** The player's planned route is theirs to pre-cache from
    their own map, and an add-on that wants to ask for it can read `api.gpsRoute().points` and send them.
  * Nothing answers the list: `areas.py` already broadcasts `areas` to every connection on every change, so the
    player's own list shows an add-on's area the moment it appears and `api.areaStatus` reads the same broadcast.
    Sending a `result` on it, as `area_add` does, would land in the same `M._areaResults` collision.
* **`api.lua`: `areaPlan(points, opts, callback)`, `areaAdd(points, opts, callback)`, `areaStatus(id)`**, with the
  request table, the id and the timeout sweep copied from `places`. `points` is `{{lat, lon}, ...}` — exactly what
  `api.gpsRoute().points` gives, so a planned route can be handed straight over. The arguments are checked before
  anything goes on the wire (two points at least, 20000 at most, each on the map, `half` present, `layers` a list
  of names), and `areaStatus` answers from `core.areasState()` with a **copy**, as `gpsRoute` does. Its timeout is
  its own (`M.AREA_TIMEOUT_S` 120 s, above the places 150 only in kind: an estimate walks every item of the plan
  and asks each imagery source what it would fetch for every square, and the add walks the plan again).
  `MINOR` bumped with an `areaRoute` capability name beside the existing flags rather than over them.
* **`core.lua`** routes the two results to `api._onAreaPlan` / `api._onAreaAdd`, as it already does for
  `places_result`.
* **`docs/ADDONS.md`**: the three calls, their `opts` and result tables, the layers list, and — at length, because
  this is the part an author will get wrong — what a saved area *is*. It is not a function call with a side effect:
  the player sees it, there are ten slots and when they are full **their** next add fails, its data is pinned and
  survives "Clear cache", it resumes after a restart with no mod involved, one area downloads at a time so an
  add-on's can legitimately sit at zero behind the player's, and `done` is not "the data arrived".
* **Untouched:** the 3D map's area UI and every message it sends, `area_cmd` and its five operations, fast mode
  itself, the box path, `plan` / `add`, the download thread's gates, and every existing API call and capability
  flag. An add-on that never calls `areaPlan` cannot tell this landed.

### What is deliberately not here

* **No remove.** An add-on cannot delete the area it added, and I think that is right for a first version even
  though it is the obvious omission. Doing it safely wants ownership in the store, which does not exist and which
  I did not want to invent on the way past; and the data an area leaves behind is what makes a second visit to the
  same ground free, so leaving it for the player to keep or delete is a defensible default rather than only a gap.
  `docs/ADDONS.md` says plainly that nothing removes it for you and that an add-on should check `areaStatus` for
  the one it added last time rather than adding another. If you would rather it were there, say so and I will
  write it — with an owner field, so a stale id cannot delete the player's own area.
* **No pause, resume, rename, fast or slow.** Those are the player's controls over their own list.
* **No `layers` on `plan` / `add` (the box forms).** Nothing asks for a narrowed box, and adding it would mean
  persisting and re-validating it for a second shape for no caller.

### One thing worth knowing, unrelated to this change

While reading `core.lua` for the fast-mode question: **any add-on can pause the player's game today**, with no API
and no flag. `fastAreaPause` reacts to the `areas` message naming a fast area, and `M.areaCmd(id, area, 'fast')` is
reachable from any Lua in the game, as is `simhold.pause(true)` directly. Nothing in this change makes that worse —
it is the reason this change does not go anywhere near fast mode — but you may want to know it is the case.


## Files


* `server/earthd.py`
* `server/navgraph.py` (no behaviour change; `write`'s new `prefix` defaults to `"navgraph"`)
* `server/dem.py` (`Dem.cached_only()` and `NotOnDisk`, inert unless a caller enters the lane)
* `server/gradesep.py` (`cached_only()` and `NotOnDisk`, the same)
* `server/tests/test_road_graph_api.py` (new)
* `server/tests/test_protocol_agreement.py` (both new message types in the agreement table)
* `mod/beamng_earth/lua/ge/extensions/beamngEarth/api.lua`
* `mod/beamng_earth/lua/ge/extensions/beamngEarth/core.lua`
* `mod/tests/test_api.lua`
* `docs/ADDONS.md`


* `server/areas.py` (`check_layers`, `all_layers`, the subset through `phase_steps` / `steps` / `plan_route` /
  `add_route` / `_add` / `_pass` and the store, `unavailable` in `message()`, `check_route`'s two messages)
* `server/earthd.py` (`_area_route`, the `area_add` guard, `area_route_plan`, `area_route_add`, the dispatch)
* `server/tests/test_areas.py` (`test_layers_subset`, `test_area_route_messages`)
* `server/tests/test_protocol_agreement.py` (both new types both ways, and `route`'s new form on the old two)
* `mod/beamng_earth/lua/ge/extensions/beamngEarth/api.lua`
* `mod/beamng_earth/lua/ge/extensions/beamngEarth/core.lua`
* `mod/tests/test_api.lua`
* `docs/ADDONS.md`


## Validation

Windows 11, Python 3.13, BeamNG.drive 0.40.5, this branch.

### In a game: the road graph

This is the part that matters, and it is what the first four commits of this branch were spent on. BeamNG.drive
0.40.5 with this branch's mod and server, a real cached region (Maryhill, Washington), driven by a third-party
add-on asking for the stage it wanted:

```
auto recce: maryhill-up, 3 window(s) of 1000 m
auto recce: window 1 of 3: 547 new node(s)
auto recce: window 2 of 3: 316 new node(s)
auto recce: window 3 of 3: 209 new node(s)
auto recce: maryhill-up matched, 4.1 km (map line 4.1 km), 0 m with no road in 0 stretch(es), 2 junction(s), 3 window(s)
```

Three windows, each centred where it was asked for, **1.25 s end to end, nothing downloaded**, and the add-on put a
4.1 km rally stage on the roads with no stretch left unmatched: 4097.1 m of line against a 4106.2 m map line, never
more than 0.7 m off the organisers' own line, over 473 road edges. The player's own `navgraph_<aid>_<serial>.json`
sat untouched beside the request's files throughout, which is the claim this change most needed to make good on.

The server's own lines were last captured at `dac0636f`, three commits back, over the same region:

```
road graph: 1000 m at 45.70745,-120.79355 | 6 cell(s), 0 not read -> 548 node(s), 547 edge(s) | cached_only=True
road graph: 1000 m at 45.71384,-120.79496 | 9 cell(s), 0 not read -> 616 node(s), 612 edge(s) | cached_only=True
road graph: 1000 m at 45.72020,-120.80126 | 4 cell(s), 0 not read -> 560 node(s), 558 edge(s) | cached_only=True
```

**The per-window counts moved between the two runs** -- 548 / 312 / 208 then, 547 / 316 / 209 now -- and that is the
change working rather than drift: the cells around a window are read from disk at `background` now instead of being
fetched, so a halo cell that is not cached is simply absent, and a road that crossed the window edge is cut where
the data stops rather than where the road does. Same stage, same ground, same total, a few nodes either way per
window. Nothing was downloaded in either run.

A 16 km stage came out at 28 junctions with no gap, at `dac0636f`; it has not been re-run since.


### In a game: the corridor download

The same add-on, on a 1.26 km stage in Ohio with **no cached roads at all**, asking for the `roads` layer alone
over a 300 m corridor. The estimate first, which fetches nothing:

```
corridor: 44 points
areaPlan -> {
  ok = true,  km = 1.25,  km2 = 1.03,
  items = 30,  missing = 30,
  downloadBytes = 18000000,
  diskBytes = 36760168,
  layers = { "roads" },
  hosts = { { "overturemaps-us-west-2.s3.us-west-2.amazonaws.com", 120, 0 } },
  seconds = 132,  days = 0
}
```

then the add, and the area followed to the end:

```
areaAdd    -> { id = "a2", ok = true }
areaStatus -> { id = "a2", name = "Earth Rally: SS #1 (53)", state = "done",
                done = 30, total = 30, unavailable = 0,
                mode = "data", half = 300, layers = { "roads" } }
```

**18 MB and 43 s wall**, 30 of 30 items, nothing unavailable, `mode = "data"` so no road or tree process was put to
work, and `layers` echoed back as the subset the app honoured. The cache went from 3,415 cached road cells to
3,703; the stage went from 0% of its cells to 100%; and four stages gained coverage rather than one, because the
corridor is dilated by two cells all round. The add-on then matched that stage, which twenty minutes earlier had no
roads to match to at all.

Two figures worth reading together: `downloadBytes` 18 MB against `diskBytes` 36.8 MB. Narrowing the layers cuts
the download to about a tenth (308 MB for the whole ground over a 10 km line, 30.6 MB for `['roads']`) but only
halves the pinned disk, because a cell's raw source blocks are shared between its layers and arrive whichever layer
asked for them. `diskBytes` reports that honestly and an add-on should show the player the download figure.

### A test that drives the mod to the server and back, for each call

The server half and the mod half each have their own suites below, and on the road-graph call both of those were
green while it was broken four separate times — every one of those bugs lived in the gap between the two sides'
stand-ins. So this call has a test that stands in for neither side: BeamNG.Earth's own `api.lua` under LuaJIT, its
own `protocol.py` encoded and decoded both ways, and `Connection.area_route_plan` / `area_route_add` over a real
`areas.Areas` with a real store in a temporary directory. Only the producers are stood in for, as
`server/tests/test_areas.py` stands them in. **95 checks, 0 failed.**

It lives in the add-on's own repository, so it is not in this diff. What it holds down is below, and each line was
checked by putting the bug back and watching it go red, because that is the only way to know a test is
load-bearing:

| put back | checks red |
|---|---|
| `Areas.message()` drops `unavailable` | 5 |
| the layers subset is not persisted | 4 |
| `plan_route` does not echo the subset | 2 |
| `phase_steps` ignores the subset | 1 |
| `area_route_add` reads `fast` from the message | 2 |
| `_onAreaAdd` hands the raw message through (`area` vs `result.id`) | 7 |
| `_area_route` takes only `"current"` again | 32, and then the run gives up |

It also caught a real one while this was being written: a file left in a half-reverted state during that exercise,
which both unit suites were happy with.


The road graph has the same, in the same repository: the real add-on, this branch's `api.lua`, `protocol.py` both
ways and `Connection.road_graph` over a real `mapdata.MapData`. **56 checks for the road graph, 95 for the route
corridor, 0 failed.** Both suites were written because every bug either call has had lived in the gap between the
two sides' stand-ins -- four of them on the road graph, each of which passed both unit suites before a game found
it.

### The suites

**Lua -- `python tools/run_lua_tests.py`:** `Lua modules: 123 passed, 0 failed`. `test_api` carries both calls:
the request as it goes out, one answer a request, another request's answer ignored, every result field defended
against a wrong type, the decoded graph, a graph file that will not read back, the arguments refused before
anything is sent, the estimate and the new area's id decoded, `areaStatus` over the app's area list with
`unavailable` and `msg` surfaced, a **forged** `"fast": true` on the wire requiring the area to stay slow, and
each call's timeout heard once with a failing callback contained.

**Python:** `test_road_graph_api` 26, `test_navgraph` 52, `test_places_api` 26, `test_areas` 25, `test_areaprops`
13, `test_protocol_agreement` 32 -- all OK.

**What was not run, and why, measured rather than assumed.** This machine's `server/earthfast.pyd` is version 295
and `dev` now wants 296, with no Rust toolchain here and an Application Control policy that will not load a freshly
written copy. `plancache.py` binds a 296 kernel at import, so of the 19 modules that import it 13 fail with
*"needs ... earthfast version 296 or newer, version 295 was"*. **None of the 13 imports `areas` or touches a
message either call adds**, and none reaches a road graph, the DEM lane or the neighbour read. CI builds the native
module before the gate.

`git diff --check`: clean.

## One thing worth knowing, unrelated to this change

While reading the saved-area code: **any add-on can already pause the player's game.** `areaCmd(id, 'fast')` on an
area, or `simhold.pause(true)` directly, and `core.lua`'s `M.fastAreaPause` applies the pause for any client on any
fast area. Mid-stage that stops the physics under a run with the add-on getting no say. Nothing here uses it --
`area_route_add` never reads `msg["fast"]` and `api.lua` has no argument for it, which is the guarantee rather than
the politeness -- but it seemed worth mentioning.

🤖 Generated with [Claude Code](https://claude.com/claude-code)

https://claude.ai/code/session_01E8t7g6utD5smCkMxbL4cji

---
