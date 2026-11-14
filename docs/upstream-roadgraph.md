# Draft for TecnaGamer/BeamNG.Earth — written, tested, NOT submitted (the push is blocked, see the end)

**Title**

```
Modding API: one road-graph window at a point an add-on names (api.roadGraph)
```

**Body** (exactly what should be posted; nothing below the end marker is part of it)

---

An add-on that needs to know where the roads *are* — not where the player is — has nothing to ask. `api.places` and
`api.buildings` answer for a point of the caller's choosing, but the roads are only ever handed to the game as the
session navigation graph, built around the player's own streaming focus and replaced when they move 400 m
(`navgraph.REBUILD_M`). An add-on that wants to put a route, a trail or a stage line on the real road network has to
walk the player over every metre of it first, which is the thing it was trying to avoid.

The data is already there and already shaped for this. `navgraph.build` takes `centre` and `window` as plain
parameters, and the in-process body of `Server.build_navgraph` is a pure function of (anchor, x, y) plus the cells and
DEM on disk — nothing in it reads the player. The only thing tying a graph to the player is who supplies the centre.
This exposes that one parameter, cached-only, behind a capability flag.

## Changes

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

* **No map cell is downloaded.** Cached-only is the whole contract, for every layer the graph reads. A window over
  ground the player has never been near comes back with few nodes and `complete: false`, and that is the honest
  answer rather than a slow one. The ground heights under the nodes still come from the app's own elevation data,
  which it reads as it does everywhere else; `docs/ADDONS.md` says so rather than letting an author infer a stronger
  promise.
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

## Files

* `server/earthd.py`
* `server/navgraph.py` (no behaviour change; `write`'s new `prefix` defaults to `"navgraph"`)
* `server/tests/test_road_graph_api.py` (new)
* `server/tests/test_protocol_agreement.py` (both new message types in the agreement table)
* `mod/beamng_earth/lua/ge/extensions/beamngEarth/api.lua`
* `mod/beamng_earth/lua/ge/extensions/beamngEarth/core.lua`
* `mod/tests/test_api.lua`
* `docs/ADDONS.md`

## Validation

Windows 11, Python 3.13, this branch at `dac0636f`.

### In a game

This is the part that matters, and it is what the first four commits of this branch were spent on. BeamNG.drive
0.40.5 with this branch's mod and server, a real cached region (Maryhill, Washington), driven by a third-party
add-on asking for the stage it wanted:

```
auto recce: maryhill-up, 3 window(s) of 1000 m
auto recce: window 1 of 3: 548 new node(s)
auto recce: window 2 of 3: 312 new node(s)
auto recce: window 3 of 3: 208 new node(s)
auto recce: maryhill-up matched, 4.1 km (map line 4.1 km), 0 m with no road, 2 junction(s), 3 window(s)
```

and from the server, at the same moment:

```
road graph: 1000 m at 45.70745,-120.79355 | 6 cell(s), 0 not read -> 548 node(s), 547 edge(s) | cached_only=True
road graph: 1000 m at 45.71384,-120.79496 | 9 cell(s), 0 not read -> 616 node(s), 612 edge(s) | cached_only=True
road graph: 1000 m at 45.72020,-120.80126 | 4 cell(s), 0 not read -> 560 node(s), 558 edge(s) | cached_only=True
```

Three windows, each centred where it was asked for, **2.5 s end to end, nothing downloaded**, and the add-on put a
4.1 km rally stage on the roads with no stretch left unmatched. A 16 km stage came out at 28 junctions, also with no
gap. The player's own `navgraph_<aid>_<serial>.json` sat untouched beside the request's files throughout, which is
the claim this change most needed to make good on.

**Four bugs were found this way and are fixed in the commits above** — the answer's shape, the cached-only read, the
frame the window was centred in, and the point being converted before the pool rather than beside the build. Every
one of them passed both unit suites before it was found. That is said plainly because it is the honest state of this
branch: the unit tests are good at each side on its own and were blind to the join, and a test that drives the mod
to the server and back is being written now. **It is not in this pull request yet**; if you would rather wait for it
before reviewing, say so and I will add it to this branch.

### The suites

**Lua — `python -I tools/run_lua_tests.py`:** `Lua modules: 119 passed, 0 failed`. `test_api` is 130 checks against
106 on `dev`, covering the request as it goes out, one answer a request, another request's answer ignored, every
result field defended against a wrong type, the decoded graph and its other fields, a graph file that will not read
back, the app's reason surfaced, bad coordinates / no callback / not connected refused, and the timeout heard once
with a failing callback contained.

**Python — `python -I tools/run_tests.py <the 60 modules of tools/quality_gate.py> test_road_graph_api test_navgraph
test_places_api test_protocol_agreement test_roads test_mapdata_singleflight test_addons --par 4 --timeout 900`:**
`57 OK, 9 not OK`, with `test_road_graph_api` 17 tests, `test_protocol_agreement` 32, `test_places_api` 26,
`test_navgraph` 52, `test_roads` 129 — all OK.

**The nine failures are this machine's, measured rather than assumed.** `server/earthfast.pyd` here is version 290
while `fast.MIN_VERSION` is 295, and there is no Rust toolchain to rebuild it. With this branch's changes stashed,
same tree, same stale binary, `HEAD` at `origin/dev`, the same nine modules fail with the same names and nothing
else. CI builds the native module before the gate.

`git diff --check`: clean.

### One thing this does not answer, deliberately

A road graph reads only what is on disk and fetches nothing, so an add-on over ground the player has never visited
gets few roads and `complete: false`. That is the right answer for *this* call — it must never outrun the world's
own downloads or your rate limits with your sources — but it does leave the question of how an add-on is meant to
get those cells. The answer is a second, separate request: explicit points on `area_plan` / `area_add` (which
already take `(lats, lons, half)` for a route, just not from an add-on) and a modding-API call over them. It is
planned and not written, and deliberately not bundled here so that this one can be reviewed on its own.

🤖 Generated with [Claude Code](https://claude.com/claude-code)

https://claude.ai/code/session_01E8t7g6utD5smCkMxbL4cji

---

## Status, not part of the body

**The patch exists, is tested and is committed. The pull request could not be opened: the push to the fork is
refused by GitHub for a missing OAuth scope, nothing to do with the code.**

The branch `addon-api-road-graph` in `C:\Users\Station\Documents\Claude\beamng.earth` holds one commit,
`7e141800`, 8 files, 766 insertions. `server/earthfast.pyd` is deliberately not in it (it shows as modified only
because Windows held the binary during the checkout). `git diff --check` is clean.

`git push -u deramp addon-api-road-graph` uploaded the whole pack (11,607 objects, ~620 MiB, since the fork had no
`dev` ref to negotiate against) and was then rejected at the ref update:

```
 ! [remote rejected]   addon-api-road-graph -> addon-api-road-graph (refusing to allow an OAuth App to create or
   update workflow `.github/workflows/quality.yml` without `workflow` scope)
```

Measured cause: the `gh` credential for this machine is an OAuth App token (`gho_…`) whose scopes are
`gist, read:org, repo` — no `workflow`. The branch is cut from `dev`, and `dev`'s `.github/workflows/quality.yml`
(blob `de5aed67`) is not the one on the fork (blob `ec03cbc4`, which is upstream `main`'s), so any `dev`-based
branch pushed to the fork counts as updating a workflow file. The fork's `main` is already identical to upstream's
`main` (`e1c72abf`), so there is nothing to sync that would remove the difference. Creating the fork's `dev` ref
server-side instead (`POST /repos/DeRamp/BeamNG.Earth/git/refs` at `36df9058`) is refused the same way (404). There
is no SSH key for github.com on this machine (`~/.ssh` holds only `known_hosts`) and no `GH_TOKEN` / `GITHUB_TOKEN`
in the environment, so there is no second credential to try.

Three ways out, all of which need the account holder:

1. `gh auth refresh -h github.com -s workflow` (interactive browser/device flow), then
   `git push -u deramp addon-api-road-graph`.
2. A personal access token with `workflow` scope used for the push.
3. An SSH key on the account, with the `deramp` remote set to `git@github.com:DeRamp/BeamNG.Earth.git`.

Once the branch is on the fork, the pull request is one command — the body above is final and needs no editing:

```
gh pr create --repo TecnaGamer/BeamNG.Earth --base dev --head DeRamp:addon-api-road-graph \
  --title "Modding API: one road-graph window at a point an add-on names (api.roadGraph)" \
  --body-file <this body>
```

Also changed on this machine: `git config user.name DeRamp` / `user.email DeRamp@users.noreply.github.com`, set
**repository-locally** in the clone (there was no git identity at all, so the commit could not be made without
one), and a `deramp` remote added for the fork. `origin` was never pushed to.
