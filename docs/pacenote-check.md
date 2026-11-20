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
  (`path.autofillDistanceCalls`: next non-isolated note, either way round, `cs` measuring, `#` blocker; notes whose
  corners overlap are listed) and the words (`compositorUtil.compositePhraseEntries`, english enthusiast or casual).
  The checks read the phrase the player hears ("three right half long over crest 300"), not our own fields.
- **Three sets of stages:**
  - **fixtures** (`fixtures.py`): made-up roads, one per reported fault, plus controls that must stay quiet. A
    fault's fixture fails until it is fixed.
  - **pro**: the 15 game stages with a professional co-driver's notes (`pro_ak` notebook + `voicepacks/pro`
    transcriptions, matched to notes as `path.getCustomAudioAssignment` does). The real ground truth.
  - **mine**: the owner's matched lines (`earthRally/matched`), rules only. Stages under 0.5 km are skipped, and
    so is a second copy of the same road (start and end within 20 m, length within 2%: Warden v1 / v2).
- **Rules** (`checks.py`), each checked against the pro's own notes so they do not flag what a human co-driver does:
  - *opening*: a first corner more than 80 m from the line is told with its distance, or by calls tied on from the
    line (a distance said at the end of the call before, "into" / "and", or under 40 m apart). The pro fails it on
    0 of 15 stages.
  - *missed bends*: a stretch turning 25° or more one way (over 60 to 500 m) that is less than half inside corner
    calls of that direction (counting 60 m before a call and 40 m after it). Map gaps are skipped. The pro trips it
    0.10/km.
  - *hidden corner after a crest*: from the road, not the calls. For each crest or jump called alone, the first
    turn (15° within 40 m) where the road is out of sight behind it (1.1 m eye, 0.6 m of road), up to 30 m past.
    Flagged unless the next call is linked ("into" / "and") and calls that turn, or a "keep right" / "rightish"
    says it, or a corner already being driven runs through it. Every case is listed with its gap; the summary
    counts the flags and bins the gaps (0-40, 40-60, 60-100, 100+ m). The pro is flagged 6 times in 77 km, all at
    60 m or more.
  - *long silences*: gaps over 600 m, listed only.
- **Against the pro:** corners found (same direction, within 40 m, one to one), same grade, within one grade, grade
  bias, "long" corners found and said long, crest-with-corner calls said together, first call within 80 m of the
  line. Per km is start to finish on every set. A stage with an empty pro notebook is skipped.
- **Fixtures** for long bends also need the word "long" on bends over 200 m; the opening fixtures need the words to
  say the distance.
- **History:** each run is compared with the last run with the same stages, scope, style, rules
  (`checks.RULES_VERSION`, now 2; bump it when a rule changes) and `--game` / `--folder`; every number is marked
  better or WORSE.

## Baseline (main, 1.9.3-alpha, rules v2)

| | Ours | Pro's own notes |
|---|---|---|
| Fixtures passed | 11 of 19 | |
| Pro corners found | 71% (precision 85%) | |
| Same grade / within one | 52% / 90% | |
| Pro "long" corners found / said long | 73% / 55% | |
| Pro crest-with-corner said together | 36% | |
| First call within 80 m, pro stages | 5 of 15 | |
| Silent openings, pro stages | 10 of 15 | 0 of 15 |
| Missed bends, pro stages | 0.25/km | 0.10/km |
| Hidden turn after a crest, pro stages | 14 (gaps 1 / 7 / 3 / 3) | 6 (0 / 0 / 2 / 4) |
| Silent openings, owner's 31 stages | 17 | |
| Missed bends, owner's stages | 93 (0.22/km) | |
| Hidden turn after a crest, owner's stages | 35 (0 / 7 / 13 / 15) | |
| Overlapping notes, owner's stages | 6 | |

Gaps: crest call to turn, 0-40 / 40-60 / 60-100 / 100+ m. 15 pro stages (77 km), 31 owner's (414 km).

## The three faults, as the check sees them

1. **Silent start.** The first note plays at the start line (`triggerType` 15) and the game says a distance only
   *after* a note (`path.autofillDistanceCalls`), so the straight before the first corner is never told: "care four
   left" with the corner 594 m away. The pro opens with the distance ("80 4 left"). The composer does say a
   distance before a note when the note's `before` field holds one, but autofill clears that field on load.
   Checked in game (2026-11-19, Warden Hillside, hooks on the rally manager): the first call fires when the car
   first moves (at launch, or on the roll up to the line, then held and played at GO right after "go"). It is
   never lost, and always said with no distance ("caution two right", corner 614 m away).
2. **Long open corners.** A clean arc is called ("six left extra long"). A bend drawn the way a map draws it is
   not: a few straight pieces meeting at small kinks (fixture `map-drawn-right-35deg-500m`, 35° over 500 m: nothing
   called). Between kinks the smoothed curvature drops to zero for longer than `pacenotes.SWEEP_GAP_M` (30 m), so the
   sweeper finder sees pieces of 7° each. The kink fixtures (35° over 480-500 m) are called with pieces of 60 m,
   not 80, 100 or 120 m; 20° over 400 m is not called at all.
   On the owner's roads it is kinks, further apart: 7 of 8 flagged bends looked at are 2 to 4 kinks of 5-22°
   (each a few 4 m points) with nearly straight runs of 130-300 m between; 1 is small kinks every 20-75 m.
3. **Crest instead of the corner.** A crest more than `stageWriter.HEIGHT_BEFORE_M` (40 m) before a corner gets its
   own note ("crest 40", then "care three left"), even when the corner is out of sight behind it. The pro says
   "crest into 3 left" or "3 left over crest" there, and calls a crest alone ("big jump 100") only when the corner is
   further on. A sharp turn hidden behind a crest is always called, with the crest, in the fixtures; a gentle one
   (20° over 100 m, fixture `gentle-bend-behind-jump`) gets no call at all.

## Limits

- The harness has not yet been checked against the game itself. The pro stages show it lines up note by note, but a
  one-off check in game (load a stage, read each note's text) would confirm the corner numbers. That needs the
  owner's OK to use the game.
- The road the game measures on is its spline through the driveline nodes. This follows it as
  `tools/pacenote_benchmark.py` does, not through the game's terrain snapping.
- The pro's grades are a person's and may lean differently from the game's ladder. Read the grade numbers as a
  trend, not a target.
- The rules are ours. The pro's own notes keep them honest, and the owner's drive stays the real check.
