# Plan: pacenote rebuild

Build `1.10.0-alpha+reccecalls`, branch `feature/recce-calls`. All six steps built 2026-11-20, not yet driven.
Results: [`pacenote-check.md`](pacenote-check.md), "Pacenote rebuild".

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
- **Grade score on the owner's stages.** Dropped: no hand-labelling (the owner). The game's own notes are a second truth instead.
- **Constants kept out of the rules.** The rules must not copy the code's constants (hidden-corner 1.1/0.6 m, missed bends 25° over 60-500 m). Each rule gets its own value from the pro data.
- **Measure the map point spacing** on the 31 matched stages: point gaps in bends, and edge lengths on straights. This settles how serious steps 1 and 4 are.

### 1. Smooth curve fit (flaw 2)

- Fit the line once, before any finder: arcs and transitions, or curvature smoothing scaled to the local point spacing.
- Every finder, the speed model and the sight test then use this one curvature.
- Check: fake short corners and split bends go down on the map-like pro stages, with no loss on the clean ones.
- **Built** (`geo.fitTurns`): each map point's turn spread over half its shorter edge, then smoothed. Alone it was mixed; with steps 2-3 it gives same grade +2-5 points, so it stays.

### 2. Our own grade (flaw 1)

- Grade each corner from the fitted radius at its tightest part, held over a minimum length.
- Make the game call that grade. Either place the note's two ends so the game's circle gives our radius, or set the grade directly if the game's note format allows it (to find out).
- This removes the `riskIntensity = -1` "opened" patch and the `racingOpen` rule, unless the checker shows they still help.
- Check: same grade as the pro goes up from 52%.
- **Built** (`pacenotes.fitRadius`, `fitGrade`, `placeForGrade`). Ladder 35/58/111/178/262 m, fitted on 1126 pro and game corners. The game takes no grade directly, so each note carries `riskIntensity` ±1 to make the game say ours. Moving the note's ends was tried and dropped: it cut the notes short. Same grade, pro 52% -> 56%.

### 3. One corner finder (flaw 3)

- One segmenter over the fitted curvature. It splits where the curve changes direction or tightness, with hysteresis instead of fixed cliffs.
- What gets called follows the owner's rule: every corner the driver can see gets a call, whatever its angle. Speed may join or grade calls, but never drops a visible bend.
- Replaces geo.corners, sweepers, open-six and kinkSweepers. Grouping (chicane, twisty) and the stage start stay, on top of the new finder.
- Check: missed bends, split bends, Cathedral Westbound.
- **Built** (`pacenotes.findCorners`). The four finders, `racingOpen` and the kink fixes are gone. Missed bends per km 0.27 -> 0.03 on the pro stages. Step cuts (a tight part in a long bend) are about neutral on the checker; kept for issue #6.

### 4. Heights for crests (flaw 4)

- Sample the ground every 5-10 m along the line where the stage cells are loaded (`castRayStatic`, as recce.lua does), and keep road-graph heights on bridges.
- Fit a smooth vertical profile before the crest, jump and dip logic.
- Offline, the checker uses the map-like pro stages' real heights for the same test.
- Check: crest and jump calls against the pro's.
- **Built** (`autoRecce.sampleRays`, `rayHeights`): ground rays every 4 m while each window is loaded, roads within 80 m of the stage line only. A ray more than 3 m off the graph's height is ignored (bridges). Offline with real heights: map-like crests found 27% -> 39%. Not yet run in game.
- **Dropped:** a smoother height profile. It flattened crests (crests found 27% -> 18%).

### 5. Speed model (flaw 5)

- Run the speed model on the fitted curve. It stays rough on purpose and is read only as relative (cautions, sight distance), never as a real speed.
- **Checked, no change:** the speed model, cautions and crests already read the one fitted curvature (`geo.curvature`).

### 6. Load-time self-check (flaw 7)

- When a stage loads, read back one compiled note's text and grade from the game.
- If it does not match, tell the player the co-driver may be wrong on this game version, instead of a log line only.
- **Built** (`rallyAdapter.gradeCheck`, called from `runner.lua` after the load). If under 70% of 5 or more corners match, the player sees one line once a session. Offline the same test gives 97%. Not yet run in game.

## Owner decisions (2026-11-20)

1. No hand-labelling. The stock game's stages and their notes are the truth.
2. Map-like lines are made from the game's drivelines, with spacing measured on the owner's matched stages (never in git). Heights at the map points only.
3. This branch's earlier fixes may go once the new version beats them on the checker. They went in step 3.
4. Build all six steps, then the owner drives it.
