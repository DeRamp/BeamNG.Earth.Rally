**One Auto recce button.** Press it on a stage that needs a line and it does the whole job: works out whether BeamNG.Earth has the map data along the stage and tells you how much there is to download, takes you to the start, and matches the line to the roads there.

Before this version the auto recce only worked where you had already driven. Of the 116 stages in the twelve rallies on my own machine, **82 had no cached roads at all** — the feature was unavailable on more than two thirds of them. Now the stage fetches its own ground.

### How it goes

1. **Press Auto recce.** The mod prices the ground along the stage — a 300 m corridor, the roads layer alone — without downloading anything.
2. **It asks.** `18 MB?` in the status pill, with **Download** and **Not now** beside it. Nothing is fetched until you say so.
3. **Download**, and it fetches through BeamNG.Earth's own saved-area downloader: gated so it cannot slow the world down, visible in your area list, and yours to pause or delete.
4. **Then it takes you to the start** — a road graph can only be asked for near where you are — and matches the line.

**Not now stops it.** Nothing moves and nothing is matched. Press Auto recce again and it asks again: every press does the same thing.

Measured in a game: a 1.26 km stage in Ohio with no cached roads came to **18 MB, downloaded in 43 seconds**, 30 of 30 items, and then matched. A 4 km cached stage still matches in about **a second and a half**.

### Reset

Once a stage has a line, the Auto recce button becomes **Reset** — it removes the line so you can make it again, with the auto recce or by driving a recce. A line you *drove* is confirmed first, because that is the one that cannot be made again in a second and a half.

### The stage page's tiles

**Length · Corners · Gain · Loss**, replacing Junctions and Bridges. Corners is the mod's own count — the same figure the co-driver's notes come from — so it is there as soon as a stage has a line rather than only after you have driven it. Gain and Loss come from the line's own heights.

Checked both ways: Dalles Mountain Up reads 545.0 m gain / 219.4 m loss and Dalles Mountain Down reads 218.7 / 544.9 — the same road in opposite directions, matching to a tenth of a metre.

### It needs a BeamNG.Earth that does not exist yet

This version is built on **modding API 1.9**: `api.roadGraph` for the road graph window, and `api.areaPlan` / `areaAdd` / `areaStatus` for the corridor download. Both are in [one pull request waiting on TecnaGamer](https://github.com/TecnaGamer/BeamNG.Earth/pull/1249). Until it is merged, the only BeamNG.Earth that can answer is the fork it lives on:

**`github.com/DeRamp/BeamNG.Earth`, branch `addon-api-road-graph`**

**With a stock BeamNG.Earth nothing is broken.** The mod asks `api.has('roadGraph')` and `api.has('areaRoute')`, gets no for an answer to both, and shows no auto recce anywhere — it behaves exactly as 1.2.5 did and you drive a recce as before. With the road graph but not the area call, the auto recce works wherever you have already been and says so where you have not, exactly as 1.3.0 did.

### Also fixed

- A download that reports success can still leave holes — an area can finish with items nothing could fetch — so the stage is re-checked rather than trusted, and BeamNG.Earth's own message is passed on to you instead of being swallowed.
- `fast` area mode is never used. It pauses the game for any client, which mid-stage would stop the physics under a run.
- The corridor sent to BeamNG.Earth is decimated to a point every 30 m: the area tool keeps those points verbatim in a file it rewrites whenever any area changes, and a stage line sent whole is a quarter of a megabyte of it.

### Known

- A stage whose map genuinely has no road along part of it still cannot be matched there, and no download fixes that; the organisers' line is used and no notes are called.
- The estimate can over-ask. It counts the download tool's own items over a corridor dilated by two map cells, which is wider than the road graph reads, so a stage that would have matched from what you already have can still be offered a download. **Not now** costs nothing.
- `seconds` in a matched line's file reads 0 for a recce that took under a second (`os.time` has whole-second resolution). Cosmetic; nothing reads it.

Tests: 14 of 14 files, **1,224 checks, 0 failed** — including two that drive the mod to BeamNG.Earth's real server and back, 56 checks for the road graph and 95 for the corridor download.
