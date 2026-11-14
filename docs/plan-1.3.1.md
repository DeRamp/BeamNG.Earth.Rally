# Earth Rally 1.3.1 plan

**The auto recce fetches what it needs.** Done when pressing **Auto recce** on a stage over ground the player has
never been near downloads that stage's corridor, says how it is going, and then matches the line -- instead of
answering "no map data on this computer yet" and writing nothing.

Decided with the user, 2026-11-13, after driving 1.3.0-alpha.

(A note on the number: this project has put features in minor versions and fixes in patch ones. 1.3.1 carrying a
feature is the user's call and reads fine if 1.3.x is treated as the 1.3 alpha series, but it is worth saying once
so nobody later reads the history as inconsistent.)

## Why this is the next thing

1.3.0's auto recce reads **only map cells already on disk and downloads nothing**. That is deliberate -- a road
graph request must never outrun the world the player is driving in, nor double the server's own request rate
against its upstream data sources. It also means the feature only works where the player has already been.

On this machine that is most of twelve rallies, so it looked fine. For anyone dropping in a map of somewhere they
have not driven -- which is the whole of 1.3.0's stated goal, *"a dropped-in map drives with no recce"* -- the
answer today is a polite refusal. The feature is finished except for the data.

## What already exists, and the one thing that does not

**BeamNG.Earth can already do the download.** `server/areas.py` has an area pre-cache with a **route corridor**
mode: a route plus a half width, walked in order, fetching `area_layers()` over the corridor's tiles. That set is
`mapdata.LAYERS + ("building_parts", "places")`, and `roads` is a plain vector layer in it, not one of the
`OPTIONAL_LAYERS` built only on request (`server/mapdata.py:131-137`). So the corridor pre-cache fetches exactly the
cells a road-graph window needs. It reports progress, it can be paused, resumed and deleted (`area_cmd`), and it has
a `fast` mode the mod already pauses the game for.

**What does not exist is a way for an add-on to ask for it over a line of its own.** The client messages are
`area_plan`, `area_add` and `area_cmd` (`server/earthd.py:8677-8681`), and a route area is only ever
`{"route": "current"}` -- the player's last planned GPS route (`_area_route`, `earthd.py:8146-8152`). There is no
points form, and the modding API exposes none of it at all.

So the stage corridor cannot be asked for today. Three ways round that, and they are not equal.

### 1. Ask upstream for the points form -- CHOSEN (the user, 2026-11-13)

Extend `area_plan` / `area_add` to take explicit points beside `route: "current"`, and expose it through the modding
API: something of the shape `api.preloadRoute(points, halfM, opts, callback)` with progress, plus a way to cancel.
`Areas.plan_route` / `add_route` already take `(lats, lons, half, ...)`, so the server change is small -- the same
shape as `api.roadGraph`: a parameter that already exists, exposed at a point of the caller's choosing.

**It goes in a pull request of its own, not in the `api.roadGraph` one** (the user, 2026-11-13). The draft of this
plan argued for folding them together -- one reviewer, one review -- and the user overruled it, rightly: the road
graph is written, tested and working in a game, and holding it back to grow a second feature would cost it its place
in the queue for no benefit to the thing already finished. `api.roadGraph` goes out as it stands and starts being
reviewed; the corridor pre-load follows as a second request once it is written.

The cost of that split, stated so nobody is surprised: the road graph arrives upstream without a way to fetch the
data it reads, so a reviewer may well ask how an add-on is supposed to get cells it does not have. The answer is
this plan, and the pull request should say so in a line rather than leave him to wonder.

### 2. Use the box form through the internal message (works today, and costs)

`area_add` also takes a plain `{s, w, n, e}` box, which needs nothing new. The mod could send that message itself
(`net.send`, as `earthAdapter` already reaches internals).

The cost is real. A stage's bounding box is far bigger than its corridor: Dalles Mtn Up is 16 km and bends, so its
box is on the order of 150 km2 against perhaps 10 km2 of corridor -- **more than ten times the download** for the
same answer. And a saved area is a player-facing thing: it appears in the 3D map's list and stays there until
something deletes it, so the mod would be creating and tidying up entries in a UI it does not own.

Worth keeping as the fallback if the upstream ask is refused or slow, and worth measuring before dismissing: if a
typical stage's box is only two or three times its corridor, the simplicity may win.

### 3. Point the player's GPS at the stage and use `route: "current"` (rejected)

It would work with today's server and no new API. It also replaces whatever the player was navigating to, in a
feature that has nothing to do with navigation. Not acceptable for a button press.

## The order

### 1. Measure the box against the corridor (an afternoon, builds nothing)

For each of the user's 116 stages, the bounding box area against the corridor area at the half width the auto recce
would want. That single number decides whether option 2 is a sane fallback or only a theoretical one, and it is
pure arithmetic over files already here.

### 2. The upstream ask, as a second pull request

The points form plus the modding API call, written and tested the way `api.roadGraph` was -- and this time with the
mod-to-server-and-back test that 1.3.0 did without (see "What 1.3.0 taught" below) written at the same time, not
after. It branches from the road-graph branch, since it builds on nothing in it but will conflict if it does not.

If the road graph's review asks for changes, those go on **its** branch; this one rebases. The two are not merged
into one request at any point.

### 3. The mod side, behind its own capability flag

- `earthAdapter` gains the wrapper, gated on `api.has('preloadRoute')` as the road graph is on `has('roadGraph')`.
- The auto recce, on finding a stretch with no map data, asks for that corridor rather than giving up -- and then
  runs itself again. The coverage record it already keeps says exactly which stretch is missing, so it can ask for
  the part it needs rather than the whole stage.
- **A download is not a button press.** It can take minutes, it uses someone's connection, and it should be the
  player's choice: the stage says how much it would fetch and asks, rather than starting on its own. The figure is
  available before committing -- `area_plan` answers `downloadBytes`, `diskBytes`, `seconds` and `days` without
  fetching anything.

### 4. The screen for it (**mock-up first**)

1.3.0's running state already has the shape: the pill becomes the progress. Downloading is a second phase in front
of matching, so the pill reads something like `Downloading 41 MB` and then `Auto recce 7 / 19`. The four endings
gain a fifth: *asked to download and the player said no*. The same rule as before -- the pill answers "can I drive
this now", the sentence under the card says what happened.

### 5. The limits that do not go away

Say them on the page rather than letting a player find them:

- A stage can be somewhere with no road data at all, and no amount of downloading fixes that.
- The auto recce still never downloads **on its own**; this version only adds a way to say yes.

## Also in 1.3.1: the stage page's four tiles (the user, 2026-11-13)

> "it dosent tell you how many corners there are after you recce a stage. it should drop bridges and junctions, and
> instead give you elevation gain/loss"

The tiles today are **Length · Corners · Junctions · Bridges**. They become **Length · Corners · Climb · Drop** (the
wording is the mock-up's to settle).

### Corners is a bug, and the cause is known

`corners` is not read from the stage's line at all. `menu.lua:124-130` walks the stage's past **runs** and takes
`r.checks.cornersFound` from the first one that has it -- a figure the rally engine works out while building a run.
So a stage you have recced but never driven has no runs, no `cornersFound`, and the tile shows a dash. It only ever
fills in after you have driven the thing, which is the one moment you no longer need to be told.

It is knowable from the line alone: the corner finding is the rally engine's own, run against the driveline when a
stage is built (`rallyAdapter`), and the same pass could run over a line when it is saved -- at the end of a recce,
and at the end of an auto recce -- and be kept with it. Worth checking whether that pass needs a loaded world or
only the points; if it needs the world, the fallback is to compute corners from the line's own geometry, which is
cheaper but will not agree exactly with what the co-driver calls, and a figure that disagrees with the notes is
worse than no figure.

### Junctions and bridges go

Bridges first, because it is already decided: an in-game auto recce cannot find them (BeamNG.Earth's road graph
carries no bridge flag), so the tile reads 0 on every stage this version can produce and would be a permanent lie.
Junctions goes with it as the user's call -- it is a number that means little to a driver on its own.

### Climb and drop

Summed from the line's own heights: every rise added, every fall added, reported separately. Both lines carry them
-- a recce's are the car's positions, an auto recce's are the road graph's drivable surface. Two things to settle in
the doing:

- **Noise.** Summing every point of a 4 m-spaced line adds up GPS jitter and surface wobble into hundreds of false
  metres. It needs a threshold, and the threshold needs choosing against real lines rather than picked -- the 116
  stages in the backup are the sample.
- **The two line kinds will not agree**, since one is where a car drove and the other is where the road surface is.
  Worth measuring on a stage that has both before deciding whether that matters.

**Mock-up first**, as any UI change: four tiles with two of them changed is a small drawing, but the wording and
the units (m or ft, following the existing distance setting) are exactly what a mock-up settles cheaply.

## What 1.3.0 taught, and what this version must not repeat

The auto recce was broken four separate times, and every one was in the gap between the two codebases -- the answer
shape, the cell read, the frame the window was centred in, and the mod writing a line with no roads in it. Every one
passed both unit suites. The mod was tested against a stand-in server and the server against a stand-in mod, and the
bugs lived exactly where the stand-ins disagreed with each other.

So the rule for 1.3.1: **anything crossing that boundary gets a test that drives mod to server and back before it is
called done.** One is being written now for the road graph; the pre-load call gets one in the same place, in the
same shape, at the same time.

## Not in this version

- The corridor pre-load **before a stage starts** (roadmap item 21) -- the comfort case, so a stage does not begin
  into a world still arriving. Same machinery, different trigger, and it belongs with the stage start rather than
  with the auto recce. It gets easier once this lands.
- Anything about which junctions the auto recce finds. It does differ from the Python tool -- Maryhill Up came out
  with 2 junctions against 5, Dalles Mtn Up with 28 against 14 (measured, 2026-11-13) -- but the user is catching
  note errors by driving the stages rather than by comparing the two (their call, 2026-11-13), so there is no
  offline comparison to wait for. Anything heard on a stage goes in docs/notes-1.3.x.md like any other report.
