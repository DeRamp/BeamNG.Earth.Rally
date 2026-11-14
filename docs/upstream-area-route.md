# Draft for TecnaGamer/BeamNG.Earth — written, tested, NOT submitted (the user reviews every PR body first)

**Title**

```
Modding API: the ground along a route downloaded ahead (api.areaPlan / api.areaAdd), layers subset, never fast
```

**Body** (exactly what should be posted; nothing below the end marker is part of it)

---

`api.places(..., cachedOnly = true)` and anything else that reads only what is on disk leave an add-on with one
question they cannot answer: how does the ground get there in the first place? Today an add-on has to hope the
player has already driven where it needs to look, or send them to the 3D map with instructions.

The tool for it already exists, is already gated against hurting the running world, is already visible to the
player and is already resumable: saved areas. And `Areas.plan_route` / `Areas.add_route` are already generic — they
take arbitrary points and validate them through `check_route`, with nothing downstream assuming a GPS origin. The
only thing refusing a caller's own line is the message handler, which answers `"route": "current"` and nothing
else. This opens that one parameter, adds a layers subset so a corridor need not cost ten times what the caller
wants, and puts both behind a capability flag — with fast mode deliberately out of reach.

## Changes

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

Windows 11, Python 3.13, BeamNG.drive not launched (see the end of this section).

### Not in a game yet, and that is the gap in this

The road-graph pull request leaned on an in-game run, and this one cannot: the machine it was written on had
BeamNG.drive in use throughout and the app will not start on it at all (see the note at the end). Everything below
is outside the game. What that leaves unchecked is the one thing a stand-in cannot reach — whether an add-on
calling `areaAdd` mid-session behaves itself against a live download thread with the player driving — and the
mod-to-server test below exists because that is exactly the gap four bugs lived in last time. Treat the figures as
real and the in-game behaviour as untested, and say so if you would rather wait for one.

### A mod-to-server-and-back test, written with the change

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

### The suites

**Lua — `python tools/run_lua_tests.py`:** `Lua modules: 123 passed, 0 failed`. `test_api` is **154 checks against
106 on `dev`**, covering the request as it goes out (no `fast`, no `mode`), the ten argument refusals that happen
before anything is sent, the estimate and the new area's id decoded, every result field defended against a wrong
type, `areaStatus` over the area list (`unavailable` and `msg` surfaced, an empty `msg` as nil, an older app's
missing field as 0, and a copy the caller cannot edit), and a timeout heard once with a failing callback contained.

**Python — `python tools/run_tests.py test_areas test_areaprops`:** `2 OK, 0 not OK` — `test_areas` **25 tests
against 23 on `dev`**, `test_areaprops` 13. The two new ones are `test_layers_subset` (the names `check_layers`
takes and refuses, what each one narrows, the estimate, the store, the plan a resume walks, and a stored subset
naming a layer this version no longer has being dropped as a bad route is) and `test_area_route_messages` (both new
types through a real session, the subset echoed, five refusals in words, the forged `"fast": true`, and the
player's own `area_plan` / `area_add` taking the same points).

**Python — `python tools/run_tests.py test_protocol_agreement`:** `1 OK` — 32 tests in 77 s, with both new message
types in the agreement table both ways, `route`'s new form on the old two, and `layers` on `area_plan_result`.

**The measured cost of the layers subset**, on a 300 m corridor over a 10 km line, through the real `plan_route`:

```
whole ground   549 items   309 MB to download   125 MB pinned
['roads']       51 items    31 MB               67 MB pinned
```

9 % of the items and 10 % of the bytes. Pinned disk only halves because a cell's raw source blocks are shared by
its layers and come down whichever one was asked for — `diskBytes` reports that honestly rather than scaling with
the subset.

`git diff --check`: clean. The branch merges into `dev` cleanly (`git merge-tree`), including over the New York
shard work that landed on `dev` after it was cut.

### What was not run, and why

**This machine cannot run the app or much of its suite, and the cause has nothing to do with this change.** Its
`server/earthfast.pyd` is VERSION **295** against `dev`'s `fast.MIN_VERSION` of **296**, there is no Rust toolchain
on it to rebuild (`cargo` and `rustc` are both absent), and the committed binary cannot be swapped in — Windows
holds the file and an Application Control policy blocks loading a freshly written copy. So `earthd` itself refuses
to start (`fast.require(fast.MIN_VERSION, "the world server")` in `main`), and `plancache.py`'s
`fast.native(296, "shared road stages")` takes out every suite that reaches the shared plan store: **of the 19
modules that import `plancache`, 13 fail and 6 pass**, every failure carrying *"shared road stages (…) needs the
server's native module (earthfast) version 296 or newer, version 295 was"*. None of the 13 imports `areas` or
touches a message this change adds. The wider quality gate was therefore not run as a whole; the modules this
change touches were each run at the head of the branch, as above.

## A note on #1249

This branch is cut from `dev` independently of the open road-graph pull request and shares no file change with it
except one line: both add a name to `api.lua`'s `FEATURES` and bump `MINOR`. Whichever lands second needs that one
line rebased. They are complementary rather than competing — the road graph reads what is on disk and downloads
nothing, deliberately, and this is how the ground gets on disk — and that pull request's own closing section names
this as the separate change it was holding out for.

🤖 Generated with [Claude Code](https://claude.com/claude-code)

https://claude.ai/code/session_01E8t7g6utD5smCkMxbL4cji

---

## Status, not part of the body

**The patch is written, tested and pushed. The pull request has NOT been opened** — the body above is for
review first.

Branch `addon-api-area-route` in `C:\Users\Station\Documents\Claude\beamng.earth`, pushed to
`deramp/addon-api-area-route`. Three commits, 8 files, 879 insertions:

```
913661e4  Modding API: the ground along a route downloaded ahead (api.areaPlan / areaAdd / areaStatus), never fast
16c0e18e  A saved area's route may be points the caller names, not only the one the player planned
1d6c05b2  A saved area downloads only the layers it was asked for, and says what never arrived
```

Cut from `dev` at `2cd8b7a4`; `dev` has since moved to `2c661ea5` (the New York shard work). Not rebased onto it:
`server/earthfast.pyd` shows as modified in the working tree because Windows held the binary during the checkout,
and a rebase wants a clean tree. It is not in any of the three commits, and `git merge-tree` says the branch merges
into the current `dev` with no conflict, `server/earthd.py` included.

The pull request, when the body is approved, is one command:

```
gh pr create --repo TecnaGamer/BeamNG.Earth --base dev --head DeRamp:addon-api-area-route \
  --title "Modding API: the ground along a route downloaded ahead (api.areaPlan / api.areaAdd), layers subset, never fast" \
  --body-file <this body>
```

**Two things worth deciding before it goes:**

1. **There is no in-game run behind it.** The validation section says so plainly rather than hiding it. The game
   was in use and the app cannot start on this machine anyway (the earthfast gap above). If the in-game run is
   wanted first, the thing to drive is an `areaAdd` mid-session with the player moving, watching that the download
   thread's gates hold and that nothing pauses.
2. **No remove in the API.** Written up above as a deliberate decision with its reasoning, and offered to him. If
   you would rather ship it with one, it wants an owner field in `areas.json` so a stale id cannot delete the
   player's own area — a bigger change than it sounds.

Also: `docs/upstream-roadgraph.md` says the road-graph push was refused for a missing `workflow` OAuth scope. That
is now stale — `deramp/addon-api-road-graph` exists on the fork and this branch pushed without complaint.
