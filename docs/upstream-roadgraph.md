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
* **A `road_graph` request**, alongside `places`: `{type: "road_graph", id, lat, lon, radius, cachedOnly}` ->
  `road_graph_result {id, path, anchorId, serial, complete, error}`. `lat, lon` are converted to the active anchor's
  frame with the frame's own `geodetic_to_enu` — the inverse of the conversion `build_navgraph` already does on its
  first lines to name the country. `radius` is clamped to `ROAD_GRAPH_RADIUS_MAX_M` (2000 m, against the session's
  own `WINDOW_M` of 1100: a graph's cost grows with the square of its window) and defaults to `WINDOW_M`. Anything
  that cannot be served answers with a readable `error` rather than throwing: bad coordinates, no map data, a server
  started without roads (`self.s.traffic`, fixed at construction), no anchor committed yet.
* **`cachedOnly` reads the window's layers only where they are already on disk,** through `MapData.layer_unkept` as
  1.8's `cachedPlaces` does, so a wide read neither fetches nor pushes the road tiles' own roads layers out of
  `MEM_MB`. **That rule covers every layer the graph reads, not only the roads.** `furniture.signals_for`,
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

Windows 11, Python 3.13, this branch at `7e14180`.

**Lua — `python -I tools/run_lua_tests.py`, the whole suite:**

```
test_api.lua: LuaJIT 2.1.1774896198 (offline/stubbed)
test_api: 126 passed, 0 failed
...
Lua modules: 119 passed, 0 failed
```

`test_api` is 126 checks against 106 on `dev`. The 20 new ones cover: the request sent cached-only with its radius,
`opts` omitted (no radius sent, so the app's default), one answer a request and nothing after it, another request's
answer ignored, every result field defended against a wrong type (`path = 7`, `complete = 'yes'`, `error = 42` all
come out nil / false), the app's reason surfaced, bad coordinates / no callback / not connected refused, the timeout
heard exactly once with a failing callback contained, and a road graph and a places request in flight together each
timing out on its own wait.

**Python — `python -I tools/run_tests.py <the 60 modules of tools/quality_gate.py> test_places_api test_navgraph
test_road_graph_api test_roads test_mapdata_singleflight test_addons --par 4 --timeout 900`:** 66 modules,
`57 OK, 9 not OK`.

```
== test_road_graph_api        OK        0.8s  16 tests
== test_protocol_agreement    OK       94.3s  32 tests
== test_places_api            OK        1.0s  26 tests
== test_navgraph              OK        1.0s  52 tests
== test_roads                 OK       15.0s  129 tests
== test_mapdata_singleflight  OK        0.5s  8 tests
== test_protocol              OK        0.1s  5 tests
done: 57 OK, 9 not OK: test_roadcorners (FAIL), test_world_cache (FAIL), test_worldbundle (FAIL),
test_germany (FAIL), test_cache (FAIL), test_roadgeo (FAIL), test_plancache (FAIL), test_netfetch (FAIL),
test_bake_formats (FAIL)
```

**The nine failures are this machine's, and were measured as such rather than assumed.** The checkout's
`server/earthfast.pyd` is version 290 while `fast.MIN_VERSION` on `dev` is 295 — `fast.NativeMissing: world bundle
needs the server's native module (earthfast) version 295 or newer, version 290 was` — and there is no Rust toolchain
here to run `tools/build_native.py`. With this branch's changes stashed, in the same working tree with the same
stale binary and `HEAD` at `36df9058` (`origin/dev`), the same nine modules fail with the same test names and
nothing else:

```
done: 0 OK, 9 not OK: test_roadgeo (FAIL), test_cache (FAIL), test_netfetch (FAIL), test_roadcorners (FAIL),
test_bake_formats (FAIL), test_worldbundle (FAIL), test_germany (FAIL), test_plancache (FAIL),
test_world_cache (FAIL)
```

CI builds the native module before the gate, so these should pass there.

`git diff --check`: clean.

### What this run does not cover

No in-game or live-server run: there is no BeamNG.drive install, no cargo and no cached map region on the machine
this was written on. So `road_graph_data`'s cached-only path is exercised against a `MapData` stand-in whose `has`,
`layer_unkept` and `cell` are all recorded (which is how "no cell is fetched for any layer of the window" is
asserted), over real `mapgeom.Features` road lines rather than a real session's cells, and nothing here measures a
real window. The two numbers that would finish the review — a 2000 m window's build time and node count over a real
city, and a request made while the player's own graph is rebuilding, to watch the live file survive in a running
session rather than in a temporary directory — want a machine with the app and a downloaded region.

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
