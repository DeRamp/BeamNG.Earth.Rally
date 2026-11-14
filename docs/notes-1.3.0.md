# What was found testing 1.3.0-dev

Reports from the user driving the build, and what came of each. The same shape as `docs/notes-1.2.4.md`.

---

## 1. A stage with no ATC starts its countdown the moment it spawns you (reported 2026-11-13)

> "when you start a stage that dosent have an atc, the stage imediatly starts a count down. instead it should spawn
> you behind the start line so you can wait for the game to load before you go"

**Diagnosed, not yet fixed.** Plan below; no code changed.

### Why it happens

The car *is* already put behind the start line -- `toStartLine()` places it `CAR_BEHIND_LINE_M` = **4 m** back. The
countdown is not fired by the spawn; it is fired by the car being **stopped inside the start zone**, and
`START_ZONE_BEFORE_M` = **12 m**. Four is less than twelve, so the car is set down stationary *inside* the zone, the
zone reports `stopped` on the first frames it is asked, and `runner.lua:1001` runs:

```lua
    elseif not run.startAt then
      run.startAt = now + M.NO_ATC_START_S        -- 12 s
```

So the start time is 12 seconds after the stage loads, whatever the world is doing, and there is no way to wait.

### This is the same defect as the ATC one, in the path that was missed

`M.DRIVEN_THERE_MIN_M` (runner.lua:60) was added on 2026-11-13 for exactly this, and its comment says it plainly:

> A car standing on the control is stopped inside its zone, so the check-in fires at once and the drive up to it
> never happens (in game: `run: toAtc` and `Checked in` 0.03 s apart, the car having respawned beside the ATC).

The ATC path got the guard. The no-ATC path has the identical problem and did not. Worth recording as a process
note rather than only a bug: the fix named the pattern and the sibling path was never checked for it.

### The options

1. **The automatic ATC (already step 4 of this release, roadmap item 3).** Every stage gets an ATC ~50 m before the
   start, so there is no no-ATC path to get wrong and every stage starts the same way: check in when you are ready,
   get a start minute. This is the proper fix and it is already in the plan.
2. **The guard, on its own and now (small).** Set the car down beyond the start zone rather than inside it, and do
   not accept "stopped on the line" as a start trigger until the car has actually moved since it was placed -- the
   same two moves the ATC path makes. Then the player sits on the approach as long as they like, drives up, stops,
   and the clock starts. It is a handful of lines and it is the actual reported bug.
3. **Hold the clock until the world is loaded.** This is what the report asks for in motive, but it belongs to
   stage pre-loading (roadmap item 21, and the on-demand item added 2026-11-13), not to a third mechanism of its
   own. On its own it would also be fragile: loading finishes and starts again as the car moves.

**Recommended:** 2 now, because it is the bug and it hands the player back control; 1 as already planned, which
makes every stage uniform and retires the special case; 3 only as part of pre-loading.

**One question for the user before 2 is written:** on a stage with no ATC, after you drive up and stop on the line,
should it still be a flat 12 s (`NO_ATC_START_S`, which exists so the co-driver's 10-second call fits), or should it
give you a real start minute the way checking in at an ATC does? A minute is what a rally does; 12 s is friendlier
on a stage that has no controls at all. Not blocking -- the guard is the same either way.

---

## 2. Where the Auto recce button goes (the user, 2026-11-13)

> "for adding an auto recce buton, that should go to the right of the status colum when a map has the recce needed
> tag btw."

**Specified, not built. A mock-up comes first** (the project's rule for any UI change), and the mock-up has to answer
the three questions below rather than guess at them.

### What it means against the UI as it stands

The stage list is a six-column grid in `EarthRally.vue` (`.er-srow`,
`grid-template-columns: 100px 1fr 130px 260px 150px 30px`): **Stage · Name · Length · Status · Best · ›**. The Status
column is 260 px with `padding-left: 30px` and holds one `.er-pill`, whose three states come from `store.js`:

| `status` | pill | meaning |
|---|---|---|
| `ready` | **Ready** (green) | notes from the stage's own roads, or from a recce |
| `recce` | **Recce recommended** (amber) | a matched line exists but part of the stage has no road on the map |
| `none` | **Recce needed** (red) | no line at all |

So "the recce needed tag" is `status == 'none'`, and the button sits in or just after the Status cell on those rows.

### Three things the mock-up has to settle

1. **Inside the Status cell, or a column of its own?** The cell has room beside the pill, which needs no grid change
   -- but rows with and without a button would be ragged down the list. A seventh column is tidier and costs a
   header cell and a reflow of the widths. Both will be drawn.
2. **Only `Recce needed`?** Yes, and the reason is worth writing down: a `Recce recommended` stage already has a
   matched line, and its amber state means `gapM > 0` -- stretches with **no road on the map**. Running the auto
   recce again cannot fill those, because there is nothing there to match to. So the button on an amber row would
   promise something it cannot do. `Recce needed` only.
3. **The running state.** This is the part with no precedent in the UI: an auto recce is asynchronous, takes several
   road-graph windows (~18 at a 1000 m radius for a 12 km stage) and can fail part way. A button that just sits
   there pressed is not enough -- the row needs to show progress, and the pill needs a fourth state while it runs.
   That state is the mock-up's real work.

Also worth drawing while we are there: the stage page's own action row (`Drive stage` · `Route to start` · `Recce`)
is where someone who opened a stage would look for it, so it probably wants an **Auto recce** button too, disabled
with the reason shown when BeamNG.Earth cannot hand out its road graph.
