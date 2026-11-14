# Draft for TecnaGamer/BeamNG.Earth — not sent

Written in the house style of the repo's own pull requests (#1218 for an API addition's shape, #1069 for the
`Files` / `Validation` / `Limitations` sections). Nothing is submitted until the user says so.

**Title**

```
Modding API: one road-graph window at a point an add-on names (api.roadGraph)
```

**Body**

---

An add-on that needs to know where the roads *are* — not where the player is — has nothing to ask. `api.places` and
`api.buildings` answer for a point of the caller's choosing, but the roads are only ever handed to the game as the
session navigation graph, built around the player's own streaming focus and replaced when they move 400 m
(`navgraph.REBUILD_M`). An add-on that wants to put a route, a trail or a stage line on the real road network has to
walk the player over every metre of it first, which is the thing it was trying to avoid.

The data is already there and already shaped for this. `navgraph.build` takes `centre` and `window` as plain
parameters, and `Server.build_navgraph` is a pure function of (anchor, x, y) plus the cells and DEM on disk —
nothing in it reads the player. The only thing tying a graph to the player is who supplies the centre. This exposes
that one parameter, cached-only, behind a capability flag.

## Changes

* **`Server.build_navgraph` keeps its sweep for the player's graph only.** It deletes every other
  `navgraph_{aid}_*.json` of the anchor so one graph file is live at a time. An add-on request writes under its own
  name (`roadgraph_{aid}_{reqid}.json`) and sweeps nothing, so **the player's live graph is never deleted** and the
  AI, traffic and minimap see no change. Both the pooled branch and the in-process branch take the same flag; the
  player's path keeps today's behaviour exactly.
* **`navgraph.build` is untouched.** `centre` and `window` are already its parameters, and a request's radius is
  passed as `window`. No field, no id scheme and no output format changes, so an add-on reading a requested graph
  reads the same shape the session graph already has.
* **A `road_graph` request**, alongside `places`: `{type: "road_graph", id, lat, lon, radius, cachedOnly}` ->
  `road_graph_result {id, path, anchorId, serial, complete, error}`. `lat, lon` are converted to the anchor frame
  with the frame's own `geodetic_to_enu` — the inverse of the conversion `build_navgraph` already does on its first
  lines to name the country.
* **`cachedOnly` reads cells through `MapData.layer_unkept`,** as 1.8's `cachedPlaces` does, so a request **fetches
  nothing and queues no background job**: a point whose cells are not on disk answers `complete: false` rather than
  pulling them. This matters more here than it does for places — a road window is a wide read, and an add-on asking
  for several would otherwise double the server's own request rate against its upstream sources, whose published
  limits `netfetch` deliberately keeps under. The flag is the request's only mode in this change: there is no
  fetching form of it to get wrong.
* **`api.lua`: `api.roadGraph(lat, lon, opts, callback)`**, with the request table, the id and the timeout sweep
  copied from `places` — one in-flight table, `_onRoadGraph` dispatching to the callback, a timed-out request
  answering `{error = 'timed out'}` rather than hanging. `MINOR` bumped with a `roadGraph` capability name beside
  the existing flags rather than over them, as every minor since `options` has had one, so `has('cachedPlaces')`
  and the rest still answer true.
* **`core.lua`** routes `road_graph_result` to `api._onRoadGraph`, as it already does for `places_result`.
* **`docs/ADDONS.md`**: the call, its `opts` and result tables, the graph's own field layout for an author who has
  not read `navgraph.py`, and the limits below.
* **Untouched:** the session graph and everything fed from it, `map.reset`, traffic spawning, the `--traffic` /
  `--roads` gating, the minimap's tunnel `lines`, and every existing API call and capability flag. An add-on that
  never calls `roadGraph` cannot tell this landed.

### What it does not promise

* **Nothing is downloaded.** Cached-only is the whole contract. A window over ground the player has never been near
  comes back with few nodes and `complete: false`, and that is the honest answer rather than a slow one.
* **It is not the AI graph.** A requested graph is written to its own file and never reaches `map.reset`, so it
  cannot move the cars or the traffic.
* **There is no bridge flag.** Nodes on a bridge take the deck height, which is the right height, but nothing in
  `nodes` or `edges` says "this stretch is a bridge". An add-on cannot recover that, and the docs should say so
  rather than let an author infer it from the heights.
* **It depends on the server having roads at all.** `--traffic on` and `--roads on` are fixed at construction, so a
  server started without them answers nothing. `has('roadGraph')` cannot see that, so the result carries the reason.

## Why a window rather than a matching call

The first shape considered was an API that did the matching — hand it a line, get back the line on the roads. A
window is the smaller ask in every direction that matters to this repo: it is one wrapper over a function already
run every 400 m, it adds no algorithm for you to own, and the matching's own bugs stay with the add-on that wants
it rather than arriving here as issues. It is also more useful to more than one caller — a route painter, a trail
tool and Earth Rally's auto recce all want the same window and would each want a different matching call.

## Files

* `server/earthd.py`
* `server/navgraph.py` (no behaviour change; the sweep flag's default)
* `server/tests/test_earthd.py`
* `mod/beamng_earth/lua/ge/extensions/beamngEarth/api.lua`
* `mod/beamng_earth/lua/ge/extensions/beamngEarth/core.lua`
* `mod/tests/test_api.lua`
* `docs/ADDONS.md`

## Validation

*(To be filled from a real run before this is opened — the sections above describe the change, not a tested branch.
It will carry: the Python suite, `mod/tests` through `tools/run_lua_tests.py`, a cached-only request over a point
with cells on disk and one without, a request made while the player's own graph is rebuilding to show the live file
survives, and `git diff --check`.)*

---

## Notes for the user, not part of the body

1. **This cannot go as a pull request until the patch exists.** Every PR in that repo carries code, and #1069's
   format has a `Validation` section listing what was actually run. The text above is a design; opening it as a PR
   with no branch behind it would be the wrong thing in the wrong place. It works as a GitHub **issue** today
   unchanged — the prose, the `Changes` list and the two reasoning sections all read correctly as a proposal.
2. **"Modding API 1.9" is already taken.** #1232 (Iliyarne, open) claims 1.9 for `registerShapes`, and `dev` is at
   1.8. So the title above deliberately says no number, and the body says "bumped" rather than naming one.
3. **The precedent this leans on was closed, not merged.** #1218 added `cachedOnly` to places and is CLOSED — yet
   `cachedPlaces` is in `FEATURES` on `dev` today. The idea landed; that contributor's commit did not. #1069 by
   contrast is merged as written. Worth knowing before putting effort into a branch: the likeliest good outcome is
   that the idea is taken and re-authored.
4. **What writing the patch would take:** the server handler and the sweep flag are the only real code (the build
   is untouched), the `api.lua` wrapper is a near-copy of `placesRequest` / `_onPlaces` / `placesTimeouts`, and the
   tests have clear models in `test_api.lua`. Call it a day's work plus a run of both suites.
