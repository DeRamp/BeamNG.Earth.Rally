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
graph request must never outrun the world the player is driving in, nor spend the server's rate limits with its
upstream sources. It also means the feature works only where the player has already driven: most of twelve rallies
on this machine, and none of a map dropped in for somewhere new. 1.3.0's stated goal was *"a dropped-in map drives
with no recce"*. The feature is finished except for the data.

## The decisions (the user, 2026-11-13)

**1. Use BeamNG.Earth's own download-a-cached-area tool, fed a shape. A route corridor, not a polygon.**

Not a fetching mode on `api.roadGraph`. A research pass recommended that and it was overruled, rightly: the open
pull request argues at length that a road graph must *never* fetch, and teaching it to fetch after all would undo
the argument it is being reviewed on. The area tool already exists, is already gated against hurting the running
world, is already visible to the player and is already resumable.

**Route rather than polygon, and the reason is honesty rather than bytes:** in bytes the two are the same. Measured
over 116 real stages, a bounding box costs **1.03x** a 300 m corridor at the median, 1.32x at p90, never worse than
2.0x -- `CELL_RING = 2` dilates any corridor into a band about 7 km wide, which swallows the geometric difference.
(An earlier draft of this plan claimed "more than ten times". It was wrong, which is why the research pass was run.)
A corridor is still the right request: it describes the ground the stage crosses, it does not claim a county because
a stage runs diagonally across one, and it is the shape a reviewer would expect an add-on to ask for.

**2. We write whatever API we need ourselves, and open a pull request once it works. We do not ask him for
anything.** No question first, no waiting on an answer -- the same way `api.roadGraph` was done: written, tested in
a game, submitted. If a layer subset is wanted, we write that too rather than requesting it.

That removes the only thing that was blocking this version. Nothing here waits on another person.

### What we have to write, and it is small

`Areas.plan_route(lats, lons, half, mode)` and `Areas.add_route(lats, lons, half, name, mode, fast)`
(`server/areas.py:469, 578`) are **already generic**: they take arbitrary points and validate them through
`check_route`, with nothing downstream assuming a GPS origin. The only thing refusing our line is the message
handler:

```python
def _area_route(self, msg):                      # server/earthd.py:8146
    if msg.get("route") != "current":
        return None
    pts = self.route_points or []
```

So: let `_area_route` accept explicit points beside `"current"`, and expose it through the modding API behind a
capability flag. A flag is mandatory rather than nice -- on today's server, points fall through `_area_route` to the
**box** path and the player is told *"an area needs south, west, north and east in degrees"*, which an add-on
cannot act on.

Worth writing in the same change, since we are in there: a **`layers` subset**, so an add-on's corridor can fetch
the roads alone. The cost section below is why that is the difference between 330 MB and a tenth of it. And **`fast`
must not be reachable by an add-on at all** -- see further down.

**It is a pull request of its own**, not folded into the `api.roadGraph` one (the user, 2026-11-13). That one is
written, tested, working in a game and already open; holding it back to grow a second feature would cost it its
place in the queue and buy the finished thing nothing.

## What it costs, measured

Stated plainly so the trade is chosen rather than discovered. Over the 116 stage lines on this machine, a 300 m
corridor through the area tool costs a **median ~330 MB**, p90 ~474 MB, worst ~822 MB; as pinned disk, median
553 MB and up to 1.4 GB.

What the auto recce needs out of that is the `roads` layer of a median **20 cells** -- on the order of **20-60 MB**.
The rest is the other nine layers, the terrain and the aerial imagery, which `phase_steps` fetches for every
corridor tile with no way to narrow the set, plus the two-cell ring. **So this route costs roughly 5-30x what the
feature needs** -- which is the argument for writing the `layers` subset ourselves rather than living with it.

Either way: **the player is asked before anything downloads, and told the figure.** `area_plan` answers
`downloadBytes` without fetching (~20-25% high against this machine's own numbers, and self-correcting as it
learns). Show that and nothing else: `seconds` is a serial-request model with no bandwidth or concurrency in it,
`days` is always 0 here, and `km2` is the geometric corridor, some 24x smaller than the footprint downloaded.

## What a saved area is, and what that forces

An area is not a function call with a side effect. It is a persistent object in the player's world, and each of
these was read in the source rather than assumed:

- It persists in `<cache>/areas/areas.json` and **survives a restart**: an incomplete area is re-queued on the next
  server start and resumes **unasked**, with no mod and no client involved.
- **The player sees it** in the 3D map's area list, line drawn, broadcast to every connection on every change.
  There are no saved areas on this machine today, so the first the player ever sees would be one Earth Rally made.
- `MAX_AREAS = 10`. The mod competes for the player's ten slots, and when full **their own** add fails.
- Its data is **pinned**: never evicted, surviving "Clear cache". `PIN_SHARE` is 0.9 of a default 20 GB cap, and at
  0.5-1.4 GB a stage, ten stages is 5-14 GB un-evictable. `_add` refuses past that share with a message telling the
  player to raise their cache size, which the mod must surface rather than swallow.
- One area downloads at a time, in list order. A mod area appended last waits behind anything already queued, so a
  progress display can legitimately sit at zero and must not read as broken.
- `area_cmd` offers only `pause | resume | delete | fast | slow`. No rename, no hide, no ownership.

**`fast` must be hard-wired off, in the mod and in anything we expose.** In fast mode every gate is skipped, 24
threads run, and the server re-pins the game's threads to its first cores -- and the pause that makes it survivable
is applied by **BeamNG.Earth's own `core.lua`, for any client, on any fast area** (`M.fastAreaPause` ->
`simhold.pause(true)`). Mid-stage that pauses the player's physics out from under a run and Earth Rally never gets a
say. Our API must not offer it. (It also means any add-on can pause the player's game today, which is worth a line
in the pull request.)

In **normal** mode a download cannot outrun the world, three deep: `_gate` waits on `pacer.hold()` and
`Server.live_busy()`; `_pace` holds it to 40% duty while the car moves; and at the limiter `predownload` takes a
host slot non-blocking and a token only above the 0.75-burst `BACKGROUND_RESERVE`, behind even prefetch. That is the
reassurance this design rests on, and it checks out.

## The order

### 1. The retry guard (ours, small, first)

`complete` requires every cell in a window's bbox to have a readable `roads` layer, and there are **two ways it
stays false after a download that worked**: a cell stored through the parquet fallback lands at a path `has()` does
not check, and a cell whose roads layer decodes to `None` counts as missing. Either gives *download -> still
incomplete -> download again*, forever.

So: **one download attempt per press, then report.** Never loop, whatever the coverage record says afterwards. It
depends on nothing else here, so it goes first and the loop can never exist.

### 2. The upstream half, written and tested here

`_area_route` taking points, the modding-API call over it, the `layers` subset, `fast` not exposed, and a capability
flag. Tested the way `api.roadGraph` was -- and with a mod-to-server-and-back test written at the same time rather
than after. `tests/test_roadgraph_e2e.py` is the pattern: the real add-on, the real `api.lua`, the real wire, the
real server, and a check that reintroducing each bug turns it red.

### 3. The mod side, behind that flag

- `earthAdapter` gains the wrapper; everything gated as the road graph is on `has('roadGraph')`.
- The auto recce, finding a stretch with no map data, offers the download rather than giving up. Its coverage record
  resolves to a **window** (a 2.4 km square stepped 700 m), not a cell, and the corridor is ring-dilated anyway, so
  "ask for just the missing part" saves little. Per-stage is the honest granularity.
- The line is **decimated to 20-50 m before sending**: points are persisted verbatim into `areas.json` and
  re-validated on every load, and a 6000-point line is ~250 KB of JSON rewritten on every area change.
- Everything in "What a saved area is" is handled rather than discovered: the pin refusal surfaced, the queue wait
  explained, `fast` never sent, and the area tidied up afterwards -- or deliberately left, but decided.

### 4. The screen (**mock-up first**)

1.3.0's running state already has the shape: the pill becomes the progress, and downloading is a phase in front of
matching. The four endings gain a fifth: asked, and told no. How loud the confirmation needs to be depends on
whether the `layers` subset lands, so this follows step 2.

## Also in 1.3.1: running an auto recce again (the user, 2026-11-13)

> "I can't run auto recce on Maryhill as it's already been recced, we should add a reset button to run it again"

**There is no way back.** The Auto recce button shows only on stages tagged *Recce needed*. The moment a line
exists the button is gone, so a line the player is unhappy with -- a bad match, a wrong-looking one, one made before
a fix -- can only be removed by deleting a file by hand. This was foreseen when the button was specified ("an amber
stage needs a way to retry") and shipped anyway; it is now a real obstruction, hit while testing.

It is not only a convenience. 1.3.1 changes what an auto recce produces (the gain/loss figures are stored with the
line, and the auto recce's heights are to be fixed), so every line made before those changes is stale, and there is
currently no way for a player to refresh one.

**What it needs to cover**, which is more than one button:

- A line the player wants re-made, on a stage that already has one.
- The difference between a line from an **auto recce** and a **driven recce**. Re-running the auto recce over
  someone's driven recce would throw away the thing they spent real time on: a recce must not be silently replaced,
  and the two want different wording.
- What "reset" means exactly: re-run the auto recce in place, or remove the line and leave the stage as it was?
  The first is what the user asked for; the second is what the word says. Probably both, worded plainly.
- Where it lives. The stage page has room (its action row already holds four buttons). A stage **list** row does
  not, and the Status column cannot take a second control -- that arithmetic is already in
  `docs/mockups-1.3.1/`/`mockups-1.3.0/`.

**Mock-up first**, as any UI change, and it folds naturally into the 1.3.0 button's four endings: a fifth path from
a stage that is already *Ready*.

## Also in 1.3.1: the stage page's four tiles (the user, 2026-11-13)

> "it dosent tell you how many corners there are after you recce a stage. it should drop bridges and junctions, and
> instead give you elevation gain/loss"

The tiles today are **Length · Corners · Junctions · Bridges**. They become **Length · Corners · Gain · Loss** --
the mock-up (`docs/mockups-1.3.1/stage-tiles.html`) drew Climb and Drop and put the wording up for a decision; the
owner chose **Gain** and **Loss** (2026-11-13), and that is what is built. Everything else in the drawing stands.

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
