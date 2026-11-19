# The pacenote check

Built on 1.9.3-alpha, branch `feature/pacenote-check`. A way to judge a change to the pacenotes before anyone drives
it: what the co-driver will actually say on every stage, scored, and compared with the last run.

```
python tools/pacenote_check/check.py --label "what changed"      # everything, ~10 s
python tools/pacenote_check/check.py --only fixtures --list      # the made-up roads, every call printed
python tools/pacenote_check/check.py --stage far-point --maps    # one stage, with its map
python tests/test_pacenote_check.py                              # the checker's own test (no game)
```

Results go to `out/pacenote-check/` (not in git: they hold positions on organisers' routes): `last.json` (every
flag, every call), `history.jsonl` (one summary per run), `maps/*.svg` (open in a browser).

## What it does

- **Speaks like the game.** `gamevoice.lua` runs the game's own Lua from the player's BeamNG.drive folder (nothing
  copied into the repo) on the notebook `stageWriter.build` writes. It covers the corner measurement
  (`geoPacenotes.measurePartition` on the driveline's 2 m spline), the distance calls
  (`path.autofillDistanceCalls`) and the words (`compositorUtil.compositePhraseEntries`, english enthusiast or casual).
  The checks read the phrase the player hears ("three right half long over crest 300"), not our own fields.
- **Three sets of stages:**
  - **fixtures** (`fixtures.py`): made-up roads, one per reported fault, plus controls that must stay quiet. A
    fault's fixture fails until it is fixed.
  - **pro**: the 15 game stages with a professional co-driver's notes (`pro_ak` notebook + `voicepacks/pro`
    transcriptions, matched to notes as `path.getCustomAudioAssignment` does). The real ground truth.
  - **mine**: the owner's matched lines (`earthRally/matched`), rules only.
- **Rules** (`checks.py`), each checked against the pro's own notes so they do not flag what a human co-driver does:
  - *opening*: a first corner more than 80 m from the line is told with its distance, or by calls tied on from the
    line. The pro fails it on 0 of 15 stages.
  - *missed bends*: a stretch turning 25° or more one way (over 60 to 500 m) that is less than half inside corner
    calls of that direction (counting 60 m before a call and 40 m after it). Map gaps are skipped. The pro trips it
    0.10/km.
  - *hidden corner after a crest*: a crest or jump called alone, with a corner starting out of sight behind it
    (sight from a 1.1 m eye to 0.6 m of road) and within 60 m. The pro trips it 3 times in 81 km.
  - *long silences*: gaps over 600 m, listed only.
- **Against the pro:** corners found (same direction, within 40 m), same grade, within one grade, grade bias,
  "long" corners found and said long, crest-with-corner calls said together, the first call.
- **History:** each run is compared with the last run of the same scope, style and rules (`checks.RULES_VERSION`;
  bump it when a rule changes) and every number is marked better or WORSE.

## Baseline (main, 1.9.3-alpha)

| | Ours | Pro's own notes |
|---|---|---|
| Fixtures passed | 9 of 13 | |
| Pro corners found | 74% (precision 89%) | |
| Same grade / within one | 51% / 90% | |
| Pro "long" corners found / said long | 73% / 55% | |
| Pro crest-with-corner said together | 36% | |
| Silent openings, pro stages | 10 of 15 | 0 of 15 |
| Missed bends, pro stages | 0.23/km | 0.10/km |
| Hidden corner after a crest, pro stages | 9 | 3 |
| Silent openings, owner's 34 stages | 19 | |
| Missed bends, owner's stages | 94 (0.22/km) | |
| Hidden corner after a crest, owner's stages | 12 | |

## The three faults, as the check sees them

1. **Silent start.** The first note plays at the start line (`triggerType` 15) and the game says a distance only
   *after* a note (`path.autofillDistanceCalls`), so the straight before the first corner is never told: "care four
   left" with the corner 594 m away. The pro opens with the distance ("80 4 left"). The composer does say a
   distance before a note when the note's `before` field holds one, but autofill clears that field on load.
2. **Long open corners.** A clean arc is called ("six left extra long"). A bend drawn the way a map draws it is
   not: a few straight pieces meeting at small kinks (fixture `map-drawn-right-35deg-500m`, 35° over 500 m: nothing
   called). Between kinks the smoothed curvature drops to zero for longer than `pacenotes.SWEEP_GAP_M` (30 m), so the
   sweeper finder sees pieces of 7° each.
3. **Crest instead of the corner.** A crest more than `stageWriter.HEIGHT_BEFORE_M` (40 m) before a corner gets its
   own note ("crest 40", then "care three left"), even when the corner is out of sight behind it. The pro says
   "crest into 3 left" or "3 left over crest" there, and calls a crest alone ("big jump 100") only when the corner is
   further on.

## Limits

- The harness has not yet been checked against the game itself. The pro stages show it lines up note by note, but a
  one-off check in game (load a stage, read each note's text) would confirm the corner numbers. That needs the
  owner's OK to use the game.
- The road the game measures on is its spline through the driveline nodes. This follows it as
  `tools/pacenote_benchmark.py` does, not through the game's terrain snapping.
- The pro's grades are a person's and may lean differently from the game's ladder. Read the grade numbers as a
  trend, not a target.
- The rules are ours. The pro's own notes keep them honest, and the owner's drive stays the real check.
