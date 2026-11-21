# Plan: pacenote rebuild

Build `1.10.0-alpha+reccecalls`, branch `feature/recce-calls`. Plan only: nothing is built until the owner says go.

## Why

An outside review (2026-11-20) found one root cause under most call faults:

- The road comes in as map points, often far apart, and is never fitted back into smooth curves.
- Four corner finders with hard cut-offs are stacked on that rough line.
- The corner number comes from where a note's ends fall, not from the road's radius (`stageWriter.lua:358`, `pacenotes.lua:147`).
- Same grade as the pro co-driver: 52%.

Drive findings 1-3 in `docs/notes-recce-calls.md` are symptoms of this.

## Order

Each step is measured by the checker before and after. A step that does not improve the numbers is dropped.

### 0. Make the checker honest (first)

- **Map-like pro stages.** Take the 15 pro stages' clean lines, thin them to map-like points (OSM spacing, height only at the points) and run them through our pipeline. Score against the pro's notes: grade, direction, missed and extra corners, length words.
- **Grade score on the owner's stages.** The owner hand-labels about 5 km on two stages. This is the only ground truth on real map roads.
- **Constants kept out of the rules.** The rules must not copy the code's constants (hidden-corner 1.1/0.6 m, missed bends 25° over 60-500 m). Each rule gets its own value from the pro data.
- **Measure the map point spacing** on the 31 matched stages: point gaps in bends, and edge lengths on straights. This settles how serious steps 1 and 4 are.

### 1. Smooth curve fit (flaw 2)

- Fit the line once, before any finder: arcs and transitions, or curvature smoothing scaled to the local point spacing.
- Every finder, the speed model and the sight test then use this one curvature.
- Check: fake short corners and split bends go down on the map-like pro stages, with no loss on the clean ones.

### 2. Our own grade (flaw 1)

- Grade each corner from the fitted radius at its tightest part, held over a minimum length.
- Make the game call that grade. Either place the note's two ends so the game's circle gives our radius, or set the grade directly if the game's note format allows it (to find out).
- This removes the `riskIntensity = -1` "opened" patch and the `racingOpen` rule, unless the checker shows they still help.
- Check: same grade as the pro goes up from 52%.

### 3. One corner finder (flaw 3)

- One segmenter over the fitted curvature. It splits where the curve changes direction or tightness, with hysteresis instead of fixed cliffs.
- What gets called follows the owner's rule: every corner the driver can see gets a call, whatever its angle. Speed may join or grade calls, but never drops a visible bend.
- Replaces geo.corners, sweepers, open-six and kinkSweepers. Grouping (chicane, twisty) and the stage start stay, on top of the new finder.
- Check: missed bends, split bends, Cathedral Westbound.

### 4. Heights for crests (flaw 4)

- Sample the ground every 5-10 m along the line where the stage cells are loaded (`castRayStatic`, as recce.lua does), and keep road-graph heights on bridges.
- Fit a smooth vertical profile before the crest, jump and dip logic.
- Offline, the checker uses the map-like pro stages' real heights for the same test.
- Check: crest and jump calls against the pro's.

### 5. Speed model (flaw 5)

- Run the speed model on the fitted curve. It stays rough on purpose and is read only as relative (cautions, sight distance), never as a real speed.

### 6. Load-time self-check (flaw 7)

- When a stage loads, read back one compiled note's text and grade from the game.
- If it does not match, tell the player the co-driver may be wrong on this game version, instead of a log line only.

## Decisions for the owner

1. **Hand-label about 5 km of your stages** for step 0? It is the only ground truth on real map roads.
2. **Steps 1-3 replace the four finders**, including this branch's kink and crest fixes. Is it OK to drop those once the new finder beats them on the checker?
3. **Ship after step 3** for a drive, or build all six first?
