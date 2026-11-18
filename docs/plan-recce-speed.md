# Plan: a faster, lighter, sturdier auto recce

Branch `fix/recce-speed`, from `main` at 1.7.1. Build: `1.7.2-alpha+recce`. Mod-side work lands as the next patch.
Status: **Part A items 1, 3, 4, 6, 7 built** (`docs/notes-1.7.3.md`). Item 5 shipped in 1.7.2. Item 1 was
narrowed to one stage looked ahead, item 4 to the matched road point, item 3 to timeouts and exceptions (2026-11-17).
Item 1 as built: the next stage is priced and added only once the current one has left its download, because
BeamNG.Earth downloads one area at a time in the order added, and neighbouring stages share ground. So it saves at
most each stage's teleport, settle and windows (about 60 s cold, not measured yet); the downloads themselves still
run end to end.

## Where the time goes (measured, 2026-11-16 logs)

From `beamng.log` and BeamNG.Earth's `server.log` for Perkins (7.0 km, 9 windows, fork.1):

| Leg | Cold (first press) | Warm (second press) |
| --- | --- | --- |
| Price the ground (`areaPlan`) | ~2 s | ~2 s |
| Download, 34 MB, 59 items | ~106 s (counter sat on "2 of 59"; the owner pressed again at 50 s) | none |
| Teleport and settle | 5 s | none (already there) |
| 9 road-graph windows | **55 s** (13 s for the first, 21 s for the fourth) | **3.2 s** |
| Our Lua matching | 14 ms | 12 ms |

- **Our Lua is not the cost.** The matching takes milliseconds. The game-side cost is decoding each window's JSON.
- **The cold windows are slow because they fight the world load.** In `server.log`, the windows ran while BeamNG.Earth
  built terrain (9 s), trees, road tiles and the far field for the new anchor. The server also hit its memory cap and
  dropped caches ("the server at 12965 MB of 12541"), so freshly downloaded cells were decoded more than once.
  BeamNG.Earth answers add-on requests on **one thread** (`api_pool`), so the windows queue behind each other.
- **The download over-asks.** BeamNG.Earth widens every route by two map cells each side (`areas.CELL_RING = 2`, about
  3.5-5 km). The windows read about 1.2 km each side of the line.
- **Every auto recce lands off the road.** All four logged runs say "landed at the ATC: left where it landed (no road
  on the map there)". The car is placed before the live road map round it has arrived.
- **A slow window reads as missing map data.** A window that times out (90 s) or errors is marked incomplete. The
  stage then ends "N m of the stage has no map data on this computer", which is wrong. Nothing retries it.
- **A full rally does each stage end to end, one after another:** price, download, teleport, wait for the world,
  match, and only then start the next stage's download.

## Part A: in the mod (patch, no BeamNG.Earth change)

Ranked by gain for the player.

1. **A full rally queues every download up front.** Price all the stages that need a line, add all their areas at
   once, then teleport and match each one as its own download finishes. Stage 2 downloads while stage 1 matches.
   Expected gain on a 6-stage rally: most of 5 downloads' wall time. (Corrected: BeamNG.Earth downloads one area
   at a time, so the downloads cannot overlap each other. The gain is at most each stage's teleport, settle and
   windows, about 60 s cold, overlapped with the next stage's download.)
   Files: `main.lua` (`stepRallyPrep`, `autoSeqStep`), `rallyRun.lua` (`prepInfo` states).
2. **Let the world settle before asking for windows.** After a teleport, wait until BeamNG.Earth has built the first
   block and its road tiles before the first window, instead of a fixed `TELEPORT_SETTLE_S`. The windows then run on
   a quiet server with a warm cell cache, not in a memory squeeze. Total time should drop, and frame hitches during
   the load should drop with it. This needs a measurement first (item 7) to confirm.
   Files: `main.lua` (`GOING` tick), `earthAdapter.lua` (a "world busy" read, if BeamNG.Earth exposes one).
3. **Retry a failed window, and say the right thing.** A window that times out or errors is asked again, up to 2
   times. If it still fails, the ending says BeamNG.Earth did not answer and asks the player to try again. It no longer
   says "no map data". Incomplete because of missing cells stays as it is.
   Files: `autoRecce.lua` (`onWindow`, `matchAndWrite`), `main.lua` (`autoText`).
4. **Put the car on the road after the match.** The matched file already has the ATC on its road, with the road's
   bearing (`controls.atc`). When the first placement failed, place the car from that once the line is written.
   Files: `main.lua` (`autoDone`), `runner.lua` (`faceAtc` from a known road point).
5. **Show the download moving.** Next to "2 of 59", show the size and elapsed time ("34 MB · 0:45"). The owner
   re-pressed because the counter looked stuck. UI text: mock-up first.
   Files: `main.lua` (status), `ui/` menu and time card, `docs/mockups-1.7.2/`.
6. **Lighter matching on long stages.** `build` and the off-line check measure every node against every point of the
   organisers' line. On a 7 km stage that is 14 ms. On a 40 km stage it is roughly 30x that, in one frame. Use the
   segment grid (`segGrid`) that `M.junctions` already uses. Same output, tested offline against the current code.
   Files: `autoRecce.lua` (`build`, `match`), `tests/test_autorecce.lua`.
7. **One timing line per auto recce.** Log each leg's seconds (price, download and MB, teleport, settle, windows, match)
   in one line, so before and after can be compared from the log with no driving.
   Files: `main.lua`, `autoRecce.lua`.

## Part B: in the BeamNG.Earth fork (fork.2, separate go)

These need a fork release and an `api.has(...)` gate in the mod, so the mod works the same on fork.1.

8. **Road-graph nodes in lat/lon, and a corridor request.** The teleport exists only because node positions come back
   in the anchor's frame, which drifts far from the anchor. If BeamNG.Earth answers with lat/lon and reads one
   corridor in one build, the auto recce can match before any teleport, with each cell decoded once. A full rally
   could then get every stage ready with no teleports at all. Needs a spike first: check that the build's
   anchor-dependent parts (grading, bridge decks, DEM zoom) still give right heights far from the anchor.
9. **A narrower ring for a route area.** An `opts.ring` on `areaPlan` / `areaAdd`, so Earth Rally can ask for one
   cell each side instead of two. Expected: about 40% less to download per stage.

## How it is checked

- Offline: `test_autorecce` (item 6 gives the same matched file as now on the stored test stages), plus touched tests.
- In game, with the owner's OK, and no driving: auto recce one cold stage and one warm stage on 1.7.1 and on this
  build, read item 7's timing line. Then a short full rally (Warden test rally, 3 stages) for item 1.
- `/handoff` before it reaches the owner.

## Not doing

- Asking for windows in parallel: BeamNG.Earth builds them on one thread, so it would not be faster.
- Bigger windows: a window's cost grows with its area, and the cells read per km of stage come out about the same.
- Skipping the price question on a single stage: the owner wants it asked every press (2026-11-14).
