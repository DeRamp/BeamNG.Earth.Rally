# Notes for 1.6.2

Every open issue, #5 to #19. The owner (2026-11-15): the enhancements among them are gameplay-loop bugs to fix before
the alpha MVP, and the Recce notes update milestone items are fixes to the 1.5.0 recce update. No mock-ups: "I just
want to see what you come up with". Preview of the finish strip and the route cue: `docs/mockups-1.6.2/finish.html`.

Built by four agents on `r162-*` branches, merged into `release-1.6.2`; reviewed by two debuggers, the contrarian and
`/code-review high`; their findings fixed in a second round (`r162-fx-*`) and that round debugged again.

## What changed

- **#6, #7** open sixes (20°+ over 60 m+, radius 250 m or less) and the long part of a bend around a tight corner are
  called as sweepers. #7 was the same cause: a crest alone meant its corner was never found.
- **#10** junctions called only when obvious: forks, side roads within 60° of the way in, side roads as wide as the
  stage within 100°, and any junction where the stage turns. 77 calls to 37 on the five stages here.
- **#11** after 300 m with nothing called tighter than a six, at 30 m/s or more, cautions come in sooner
  (55 / 40 / 28%). Cautions 17 to 25 on the five stages.
- **#12** corners 30 m or shorter and 45° or less are called one grade more open when the racing line allows
  (`riskIntensity = -1`; checked in the game's `compositorUtil.lua:218-229`, not gated by any setting).
- **#5** the ATC and stop are laid along the road: saved by Auto recce (`controls` in the matched file), and at run
  time put down again once BeamNG.Earth's road map covers them (never within 30 m of the car, gives up after 2 min).
- **#9** at junctions of 15° to 45°, the tape runs parallel to the stage road. Under 15° it falls back to square.
- **#13** the rally menu pauses through the game's pause requests; a player's own pause is kept. Let go while a menu
  action moves the car or loads (auto recce, recce, go to start, drive), and while BeamNG.Earth holds the game.
- **#14** controller on the menu page (d-pad, A, B back, bumpers for tabs) and on the results card.
- **#17** the finish time sits in the top bar beside the stage clock: big for 3 s, then a strip to the stop. The
  stage clock stops at the final time; the gap reads "vs best".
- **#18** Close on the results card.
- **#19** Route to stage arms the stage; within 1 km it loads without moving the car; the GPS leads to 250 m, then the
  stage's arrows. Drive 2 km away before check-in and it is put away, re-armed while the route still points there.
  The game's Messages app shows "Route to <stage> · 4.2 km · gets ready as you arrive".

## Known before the drive

- **#11 timing** ("not enough warning") cannot be moved per note: the game starts every call from one global
  co-driver timing setting (`codriverTiming.lua:17-49`). Raising that setting is the lever.
- **Start on a controller** opens the game's Escape menu rather than closing ours (the game's UI eats the press,
  `uiNav/eventProcessor.js`). B closes it.
- **The results card's controller support** claims an "activity" popup so the pad reaches it. Untried in game.
- **#5 on existing stages** works through the run-time fix only until a stage is auto recced again.
- No matched stage here has a real #7 sample; the synthetic test covers it.

## Test plan

Km positions come from the generator on the matched stages here and can be about 0.2 km out. Listen, don't stop:
note the km of anything wrong. Things to watch on every stage: the menu pausing (#13), the finish strip (#17), the
Close button and the pad on the results card (#14, #18).

**1. ARA Snodrift: Black River-Camp (16.3 km). Run it from the menu first, without a new Auto recce.**

| Km | Issue | Expect |
|---|---|---|
| ATC | #5 | Tent along the road, not half off it (the run-time fix) |
| 0.82, 3.78, 4.74, 6.02, 7.35, 13.04, 13.98 | #6 | Open bends called ("six", "six long") |
| 2.0, 2.63, 13.94 | #10 | Junction still called |
| 0.20, 0.49, 2.04, 4.27, 5.00 | #10 | No junction call |
| 2.6 (double), 3.5, 9.9 (triple), 10.7 | #11 | Caution into the corner after the straight |
| 1.99, 2.67, 4.09, 13.22 | #12 | Short kinks a grade more open than before |
| 4.13, 4.27 / 4.31, 11.04 | #9 | Tape parallel to the stage road at the sharp forks |

Then Auto recce it and look at the ATC once more: the saved road point, the recce path.

**2. Route to stage: from Black River-Camp's stop to Meaford Mills (#19).** Open the menu (it pauses), press Route to
stage, close it. Drive. The Messages line counts down; at 1 km the stage loads with no camera snap; at 250 m the
stage's arrows take over; roll in, stop, check in. Once, drive off more than 2 km before checking in, then come back.

**3. ARA Snodrift: Meaford Mills (10.3 km).**

| Km | Issue | Expect |
|---|---|---|
| 0.51, 0.77 | #9 | Tape parallel (26° and 38° sides) |
| 1.22, 3.15 (six then five), 5.59 | #6 | Open bends called |
| 0.30, 3.60, 9.48 | #12 | Kinks a grade more open |
| 7.75 (double), 9.04 | #11 | Caution after the straight |
| 0.18, 2.34, 3.16, 6.21 | #10 | No junction call |
| Stop | #5 | Stop board on the road (it is 519 m off the line, so this is the run-time fix) |

**4. ARA Snodrift: 622 East Branch (7.4 km).**

| Km | Issue | Expect |
|---|---|---|
| 0.48, 2.75, 6.35 | #9 | Tape parallel (27°, 22°, 26°) |
| 3.12, 5.47, 6.42, 6.58 | #6 | Open bends called; at 5.5 and 6.6 a six then the corner |
| 2.85, 3.97, 4.75 | #12 | Kinks a grade more open |
| 0.54, 0.97, 3.79, 5.77 | #10 | No junction call |

**Optional, if time:** Overmountain Weaver Bend for short kinks (0.79, 0.90, 1.05, 3.52) and the care at 4.4.

## Findings from the drive

(Logged here while the owner tests; nothing is changed until they say.)
