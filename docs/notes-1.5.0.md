# 1.5.0 notes: the stage dressing in game

Found while the user drove the build (branch `worktree-stage-dressing-1.4.0`, 35d1bb7). Logged, not fixed, while
testing. Each says where in the code and what the fix would be.

## 1. Hay bales in the middle of the street at Y-shaped hairpins (the user, 2026-11-14)

"Occasionally on Y-shaped hairpins, the barrels spawn in the middle of the street."

**Where:** `dressing.lua` ~414-421, the spectator area's three hay bales, put at the inside edge (`half + 1.2` off the
line) at the apex and 12 m either side.

**Why, most likely:** the bales are the only part of a spectator area with **no clearance check**. The camp behind
them walks in until `clearOf()` says it is clear of the road (~425-428); the bales take a fixed offset. At a
Y-shaped hairpin (the inside of the turn is another road, or the hairpin's two legs run close), the point 12 m
either side of the apex lands on that road. A second cause can add to it: the bales are `edged`, so at spawn
props.lua moves them out by the measured road width minus the planned one (up to +6 m), and at a Y the road found
under the point can be the other branch, wider or differently placed, pushing the bale into it.

**Fix to propose:** check each bale with `clearOf()` against the whole stage line (as the camp does) and drop the ones
that land on it; and do not `edge`-shift an object when the road found at spawn is not the stage's own road (its
direction disagrees with the line's by more than ~30 degrees). Worth checking the same for the spectator tape and
fence runs, which share the offset-line logic.

Fixed: each bale checked with `clearOf()` over the whole line and the side roads, left out under 0.7 m clear
(`BALE_CLEAR`), and the spectator tape / fence pieces checked at their middle too (dressing.lua `spectators`); the
spawn-time edge shift skipped when the road found there runs more than 30 degrees off the object's road
(`DRESS_EDGE_MAX_DEG`, props.lua `alignedRoad` / `edgeShift`).

## 2. Chairs and tables turned 90 degrees (the user, 2026-11-14)

"The chairs and tables are 90 degrees off."

**Where:** the control posts (props.lua `TENT`, ~60-66) turn the table and chair **90 degrees** from the road
(`{ 'table', fwd - 0.3, o - 0.6, 90 }`), and those look right in game (shipped since 1.2). dressing.lua's radio post
copies that (`at(..., 90, 'table')`, ~359-360), but the other three places use the direction with no turn:
`junctionMarshal` (~319-320), the organisers' marshal post (~373-374) and the spectator area's chairs (~438). So the
junction marshals' and spectators' tables and chairs come out a quarter turn off.

**Fix to propose:** turn table and chair by 90 degrees in those three places, the same as `TENT`; the showcase row
(`dressShowcase`) puts each shape down as a site would, so it can confirm the rest of the orientations in one look.

Fixed: table and chair turned 90 degrees to the right (as `TENT`'s +90: `rightOf` the way they faced) in
`junctionMarshal`, `roadsideMarshal` and the spectators' chairs; the flags as they were (dressing.lua).

## 3. The tape should reach just past both edges of the road (the user, 2026-11-14)

"The tape should extend just past the edge of the roads."

**Where:** `dressing.tapeFor(halfW)` picks the 6 / 8 / 10 m model by the side road's width, so on a 6 m road the 6 m
tape ends exactly on the edges, and an unknown width (written as 0: always on lines from tools/auto_recce.py, and
wherever the road graph gave none) falls back to 6 m whatever the road really is.

**Fix to propose:** pick the model so each end passes the edge by ~0.5-1 m (the road's width + 1-2 m, the next size
up), and beyond what the 10 m model reaches, scale the tape along its length (a TSStatic takes a scale; the tape
runs along the model's -Y, so a Y scale) rather than leave a gap. Where the width is unknown, read it from the live
road map at the junction when the tape goes down (props.roadAt, as the `edged` objects already do).

Fixed: `tapeFor` takes the shortest model reaching the road's width + 1.5 m (`TAPE_PAST` 0.75 m each end), beyond
10 m the 10 m model stretched along Y (`sy`, the TSStatic `scale` field set in `makeObj`, about the origin); an
unknown width plans as 6 m and carries `refit`, and props.lua fits it at spawn to the road map's side road there
(else 3 m half width), the tape's middle kept (dressing.lua `tapeFor` / `solveJunction`, props.lua `refitTape`). The
junction tape's middle is now checked clear of the stage too: a longer tape across the stage's own later pass
cleared it at both ends.

## 4. The direction (tulip) boards a bit further off the road (the user, 2026-11-14)

"The tulip signs should be a bit further off the road too."

**Where:** dressing.lua places the direction boards at `half + BOARD_OUT`, `BOARD_OUT = -0.3` copied from props.lua's
control boards, so they stand 0.3 m *inside* the road's edge.

**Fix to propose:** a constant of their own, `DIR_BOARD_OUT`, about +1.0 m (just off the edge), leaving the control
boards as they are; the user to say if that is far enough when driven.

Fixed: `DIR_BOARD_OUT = 1.0` for the direction boards only; control, radio and medical boards unchanged
(dressing.lua).

## Checked

- **Every shape the right way round** in the showcase row (`require('earthRally/runner').dressShowcase()`; the user,
  2026-11-14: "all the shapes are the right way!"). So the model axes read from the game's mesh files are right
  (boards face the car, tapes run where they should), and item 2 is not a model-axis error but the heading the
  three layouts give table and chair relative to the road: the showcase puts each shape down on its own along the
  row, where 0 degrees looks right; on the stage, beside a road and a gazebo, it is a quarter turn off.

## Review round 2

Fixed: a tape of unknown width carries `maxLen`, the longest that still clears the stage road (both ends and the
middle, `TAPE_CLEAR`) at the position the walk-in chose, and props.lua's `refitTape` never lays it longer, so at a
fork a wider side road no longer takes the tape onto the stage (dressing.lua `solveJunction`, props.lua `refitTape`).

Fixed: a tape is stretched by at most 1.25 along its length; beyond that it is laid as two overlapping pieces of the
10 m model (each at most 12.5 m, still within `maxLen`), in the plan (`dressing.tapePieces`) and at spawn
(`refitTape`), both pieces with their scale again after a world shift.

Fixed: hay bales, spectator tape and fence carry `offRoad`, and props.lua leaves one out where the road map has any
road, whichever way it runs, whose surface covers its spot (nearer its centre line than its half width + 0.5 m:
`props.roadCovers`); no road map there, it is put down.

Fixed: the edge shift takes a road as the stage's own by position: its centre line within 2 m
(`DRESS_EDGE_NEAR_M`) of the planned stage-line point the object was set from; the angle check is loosened to 45
degrees (`DRESS_EDGE_MAX_DEG`) as a second test, so a Y branch a few degrees off is not taken for the stage road and
the stage road at a tight apex is.

Fixed: the setup message says what an old (format 1) auto recce line lacks -- course tape and marshals; its
junctions still get direction boards from the line -- in the log and once on screen ("Old auto recce line: re-run
Auto recce for course tape and marshals", runner.say); a format 2 file with no junctions, or junctions that did not
place on the driven line, is logged as such instead (runner.lua `setupDressing`).

Fixed: `dressing.plan`'s unused `only` and `existingMarshals` options are gone, with their tests.

Not changed: the stale comment in events.lua (~224, "the live road map fills those in: junctions.merge") stays --
another branch has edits there.
