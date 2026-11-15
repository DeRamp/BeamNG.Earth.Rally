# 1.6.0 notes: the stage dressing in game

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

## Review round 3

Fixed: which map points are marks (importer.lua `markKinds`, `NAME_RULES` 4 so the rallies already imported are read
again once). A name is a radio by number only when that is all it is ("R3", "R 3", "Radio 3"), so "Junction R572"
is not one. A control (start, finish, flying finish, stop, ATC / TC, service, regroup: `isControl`) is never a mark
unless a `#pt-` tag says so. The description is read for spectators only, and a "closed" / "no spectators" there
cancels a spectator word only in the same sentence. Spectator facilities (parking, car park, toilets, bus, shuttle,
camping, entrance, tickets, food) are not spectator areas, in a "Spectator Points" folder or not. A `#pt-` tag that
names no known kind falls through to the words (the convention is in `docs/rally-file.md`).

Fixed: a point near two stages is kept on the one whose line is nearest (within 100 m, as before); stages whose
lines are within 10 m of that distance (`MARK_SAME_ROAD_M`: one road drawn twice, a stage and its reverse) all keep it.

Fixed: the page counts the marks with the dressing's span (100 m either side of start .. flying finish) and
off-line limit (`events.stageMarks`), so a kind whose every map point lies outside the stage shows Random, as the
dressing fills it (medical still None). The counts are on the map's line, the dressing's on the line driven; menu.lua's
comment now says that, not "never disagree".

Fixed: `MARSHAL_SHARE` is gone: every junction turn that can have a marshal gets one, at most one per km (which of
two too close is by chance), and the comment that overstated the per-turn draw with it.

Fixed: the stage page's help says "the map doesn't mark ... on this stage, so they're placed for you where the stage
has room" (no "this rally's map", no "the same places every time").

Fixed: a bridge's far end is looked for only from its start to 300 m on (`runner.bridgeEnd`, `BRIDGE_MAX_M`), so a
stage that comes back alongside no longer takes it from the later pass; past 300 m, behind the start or off the
line, the bridge is kept with no span.

Already right: the `NAME_RULES` comment said 1.6.0 (the renumbering commit fixed it).

## 5. A rally with map points on any stage: the others get none, not random (the user, 2026-11-15)

"If a rally event has spots marked on a map for at least one stage, don't assume random on the others, assume zero."
Logged, not acted on yet.

Now: each stage decides alone. A kind with no marks on that stage is filled at random (`dressing.lua`, map marks
first else random per kind), and the stage page shows "Random" (`EarthRally.vue` `ptState`).

Proposed: work out per rally whether the organisers' map marks points at all. If it does, a stage with none of a kind
gets none, and its page shows "None" instead of "Random". Random fill stays only for rallies whose map marks nothing.
Touches `events.stageMarks` (or a new per-event flag next to it), `runner.setupDressing` (pass it to `plan`),
`dressing.plan` (skip the random fill), and `ptState` / help text in `EarthRally.vue`, with tests in `test_dressing`
and `test_menu_rally_files`.

Open: per kind or any kind? (a) A rally that marks radios on some stage gets no random radios, but still random
spectators if it marks no spectators anywhere; or (b) any point of any kind on any stage turns random off for every
kind in that rally. Junction marshals at taped turns are dressing, not map points, so they stay either way.

Fixed (per kind, per rally, as approved: (a)): `events.markedKinds` says which kinds the rally's map marks on any of
its stages (every stored mark, wherever it lies); `runner.setupDressing` passes it to `dressing.plan` as `mapKinds`,
and `plan` fills radio points and spectator areas by chance only for a kind the rally marks nowhere (a kind marked
only outside this stage's span now counts as marked too: none, where review round 3 had made it random). Medical is
still never random; the junction marshals at taped turns still go up whatever the map marks. The stage page gets
`marked` (`menu.stageBase`), and `EarthRally.vue`'s `ptState` shows None for a radio / spectator kind marked on
other stages only, its help line saying so ("this rally's map marks ... on other stages but not this one"); marshals
at 0 still read Random (the junction marshals). Tests: `test_dressing` (mapKinds per kind, the outside-the-span case),
`test_hud` (the page's `marked`), `test_run` (handed to the plan).

## 6. A roadside marshal on the road, its table and chair the wrong way (the user, 2026-11-15)

"If a marshal is on the road, and isn't in an intersection, it should be OFF the road. Saw that on Early Weaver Bend.
The table and chair for these marshals needs to rotate too." Logged, not acted on yet. Seen on Overmountain SS6/9/11
Weaver Bend, 0.8 mi in, about 35.93339 N, 82.95062 W (screenshot taken then: table side-on, chair facing the camera,
blue flag behind). These are map marshals away from a turn (`dressing.lua` `roadsideMarshal`, used when
`turnNear(m.along, MARSHAL_AT_JUNCTION_M)` finds no turn within 40 m).

Likely causes, to check:
- **On the road:** the post stands at `L.half + TENT_OUT` (1.5 m) from the line, with `L.half` one half-width for the
  whole stage. Where the road is wider than that, or the auto-recce line runs off the road's centre, 1.5 m past the
  assumed edge is still on the tarmac. `post()` (radio/medical) has the same exposure; spectators test `clearOf`.
  Proposed: measure the real edge at the post (in props, against the game's road at spawn, as `roadCovers` /
  `alignedRoad` do) and push the whole group out until it is clear, dropping it if it can't be, as tape already does.
- **Turned wrong:** table and chair both take `rightOf(tx, ty)` whatever the side, so the group faces one way on the
  right of the road and the opposite way relative to the road on the left. Proposed: turn with the side so the table's
  long edge runs along the road and the chair sits behind it on the far side, facing the road, on either side (to
  confirm which way the user wants it facing).

Fixed: why the edge shift missed it -- it took only the road map's width less the planned one, never how far the
stage line runs off the road's centre (towards the post: still on the tarmac), and it looked for the road within 2 m
and 45 degrees of the line, so at a bend, where the map's chord lies further off, it found nothing and the post
stayed where the one stage width put it; nothing then checked the post against the road's surface. Now props.lua's
`edgeShift` sets an object as far from the real edge as it was planned from the assumed one (width AND the line's
offset, over how square the way out is to that road), looking within `DRESS_EDGE_NEAR_M` 4 m and
`DRESS_EDGE_MAX_DEG` 60 (the tape refit keeps 45: `DRESS_TAPE_MAX_DEG`); then every object set from the edge is held
`DRESS_CLEAR_MARGIN_M` 0.3 m + its own reach (`dressing.FOOT`) clear of every road the map has there, its group
(`grp`: a post's gazebo, table, chair and flag; a roadside marshal's three; the spectators' camp) pushed out
together in 0.5 m steps up to `DRESS_PUSH_MAX_M` 6 m, and left out, said once in the log, where that does not clear
it (`groupPush`). Boards and bales go on their own. Table and chair: `roadsideMarshal` now sets them as `TENT` on
either side -- both with +Y out from the road (TENT's yaw 90 on the right, mirrored on the left), the table's long
edge along the road `TENT_OUT - 0.6` past the edge, the chair 0.9 m behind it on the far side from the road; the
junction marshal kept as note 2 left it. Tests: `test_props` 5-6 (the line's offset, 3 m off still found, the group
pushed together, left out, no road map), `test_dressing` (either side).

## 7. Two spectator areas side by side, and on the road's edge (the user, 2026-11-15)

"See the double spectator area, these should be merged into one. They also shouldn't stick onto the road like this."
Logged, not acted on yet. Seen on Overmountain Weaver Bend, 1.7 mi in, about 35.94061 N, 82.94383 W (screenshot: two
gazebos one after the other on the right, the striped barrier/barrel row and the spectator board on the road's edge).

- **Doubled:** every spectator point on the organisers' map becomes its own area (`dressing.lua` ~797-804, each
  `m.along ± SPEC_POINT_M` 20 m). The map has two (or more) spectator points a few tens of metres apart for one
  spectator area, so two gazebos go up. Nothing merges them; `props.setDressing` deduplicates only identical keys.
  Proposed: before placing, group the map's spectator points on the same side whose spans overlap or lie within ~100 m,
  and make one area from the first to the last (its apex the middle, still capped at `SPEC_SPAN_MAX_M`).
- **On the road:** the bales/barrels go `BALE_OFF` 1.2 m past the edge the mod assumes, and the spectator board at
  `BOARD_OUT`, with that edge taken from one road width for the whole stage (`L.half`). On a wider road, or where the
  auto-recce line runs off the road's centre, they land on the tarmac. `BALE_CLEAR` only tests against the other roads'
  lines, with the same width. Same root cause as note 6; the same fix (measure the real edge at spawn, push out until
  clear, drop if it can't be) covers both.

Fixed: the map's spectator points on one side within `MERGE_M` 100 m of each other are one area, from
`SPEC_POINT_M` before the first to as far past the last, its apex in the middle, still held to `SPEC_SPAN_MAX_M`
(`dressing.merged`, note 9's merge). On the road: note 6's edge fix (the real edge, the line's offset) sets the
tape, fence and bales; the bales now stand `BALE_OFF` 1.5 m past the edge (was 1.2: clear of it by their 0.75 m
reach) and are pushed off any road one by one, the camp as a group; the tape and fence, laid in runs, are still left
out piece by piece where a road covers them. There is no spectator board in the plan: the "board" on the edge in the
screenshot is most likely the striped barrier (the spectator tape) or a tarp. Tests: `test_dressing` (merging).

## 8. Junction tape long enough but off-centre: past the right edge, short of the left (the user, 2026-11-15)

"I'm seeing the extended caution tape on junctions, but it only is extended off the right side, the left side is
still not wide. The total width is good, but can you center these better?" Logged, not acted on yet.

Candidates, to check in this order:
- **Two-piece tapes refit as if each were the whole tape.** A tape longer than 1.25 x 10 m is planned as two pieces
  (`dressing.lua` `tapePieces`, ~651), and each piece gets `refit(tp.L)` with the whole tape's length. `props.lua`
  `refitTape` (~640) then takes each piece's own origin as the tape's end and puts the centre `rf.len / 2` from it, so
  the two pieces are refit about two different centres, neither the side road's. Wide side roads, where the tape is
  extended, are exactly the two-piece ones. Fix: refit the tape once, before it is split (one `refit` per tape, with
  its true ends, and the pieces made in props from the refit length), or pass each piece its offset from the centre.
- **Not centred on the side road the game has.** The centre is the junction point plus `s` along the side road's
  bearing; `refitTape` reads the width there (`alignedRoad`) but never moves the centre onto that road. Where the
  junction node or the bearing is off the side road's middle, a tape of the right length sits to one side. Fix: take
  the centre from the nearest point on the road `alignedRoad` finds, within a metre or two.
Test: a two-piece unknown-width tape refit against a road centred on the plan must come out symmetric about it.

Fixed: the plan now gives a tape of unknown width as ONE object (the whole tape, its true ends), and props.lua's
`refitTape` refits it once about its middle and splits it into one or two pieces there. (Checked: with an unknown
width always planned as 8 m, such a tape was a single piece already, so the per-piece refit could not happen as
things stood; it is closed off all the same.) The likelier cause, the second: the middle is now moved onto the
centre line of the side road `alignedRoad` finds when that is within `DRESS_TAPE_CENTRE_M` 2 m along the tape, the
cap (maxLen) shortened by twice the move so neither end reaches further towards the stage than the plan allowed.
Tests: `test_props` 7 (planned in dressing, put down in props: on a 19 m side road two pieces symmetric about it,
20.5 m; re-centred on one 1.5 m off; left alone at 3 m).

## 9. Warning boards too close to the road; merge any points that are right by each other (the user, 2026-11-15)

"Warning signs are also too close to the road, move them further out please. Also if two points are right by each
other please merge them, this applies to all things." Logged, not acted on yet.

- **Boards:** radio / medical boards and their warnings stand at `BOARD_OUT = -0.3` (`dressing.lua` 39, used in
  `post()` ~388), 0.3 m *inside* the assumed road edge (copied from props' control boards, where a car stops beside
  them). On a stage they should be outside it: proposed `BOARD_OUT` +1.0 m like the tulip boards (`DIR_BOARD_OUT`), on
  top of the real-edge fix from note 6. (Check the spectator board uses the same constant.)
- **Merge, every kind** (generalises note 7's spectators): before placing, points of the same kind within ~100 m of
  each other along the line (and on the same side) become one: spectators one area over their combined span; radio,
  medical and marshal posts one post at the first. Across kinds, radio + medical already share within `SHARE_M` 50 m;
  add: a marshal post within ~50 m of a radio / medical post is dropped (that post already has its table and chair),
  and a map marshal near a junction turn already goes behind that turn's tape. Applies to map points and random ones
  alike. Distances to be judged in game; tests in `test_dressing` for each pairing.

Fixed: `BOARD_OUT` is +1.0 m (was -0.3): the radio / medical boards and their warnings stand 1 m past the edge, as
the tulip boards; props' control boards at the starts and finishes (`props.BOARD_OUT_M`) are unchanged, and there is
no other stage board using it (the plan has no spectator board). Like every object set from the edge they also get
note 6's real-edge fix and push. Merge (`dressing.merged`, before anything is placed): the map's points of one kind
within `MERGE_M` 100 m along the line -- spectators and marshals on the same side, radio and medical posts always
stand on the right -- are one: spectators one area over the span, radio, medical and marshal one post at the first.
Radio + medical still share within `SHARE_M`. A roadside marshal post within `MARSHAL_NEAR_POST_M` 50 m of a radio
or medical point (the map's or a random one) is left out; a map marshal at a turn still goes behind its tape, and
the junction marshals at taped turns are not dropped (they stand up the closed road, not at the post). The random
points need no merging among themselves (radio 4-6 km apart, spectators 4 km, junction marshals 1 km). Tests:
`test_dressing` (each pairing, a chain, opposite sides, a random radio point).

## Review round 4

Fixed: the roadside marshal's table and chair turned 90 degrees from the +Y-out set-up the user saw: the table's +Y
along the road on either side, now `TENT_OUT` (1.5 m) past the edge; the chair 0.9 m behind it facing the road, its +Y
along the road on the right and against it on the left (assumed from note 2's approved turn: the table's long edge on
its Y, the chair facing its -X); the junction marshal and the post's TENT unchanged (`dressing.lua` `roadsideMarshal`;
`test_dressing`).

Fixed: `edgeShift` takes the larger of the width-only shift and the line-offset one, so a road-map chord on a bend
never pulls an object in (`test_props`: an arc of 30 m chords, the object on the outside).

Fixed: `groupPush` pushes the group away from the nearest centre-line point of the road covering it most, then
straight out; where no push of 6 m clears it, it slides the group 5, 10 or 15 m either way along the stage, with the
pushes tried again at each slide, before leaving it out (logged at 'W'). The Y-branch cases 2f7e4fa narrowed are back
at radius 5 / 7 and pass by the push and the slide (`test_props`, plus a side road across a marshal's group).

Fixed: a dressing object's ground is looked for `DRESS_GROUND_ABOVE_M` + 0.7 m per metre it moved above its planned
height (the first ray reaching as far below), and one moved 0.5 m or more with no ground found is left out, not stood
at z0 (`test_props`).

Fixed: the map's marshals go to their junction turns one mark at a time (`turnNear` per raw mark, one marshal per
turn); only the roadside leftovers are merged (`test_dressing`).

Fixed: `merged` also joins points within `MERGE_GROUND_M` 50 m on the ground that are more than `MERGE_M` apart along
the line (a hairpin's legs); a chain stops growing at `SPEC_SPAN_MAX_M` first to last and the next point starts a
group; a radio / medical post keeps its boards and flag but loses its gazebo, table and chair when a right-hand
spectator area is within `POST_NEAR_SPEC_M` 50 m; the bales are one push group (`test_dressing`).

Fixed: `events.markedKinds` counts only marks some stage would use (`stageMarks`' span and off-line test), and
`dressing.plan` counts only marks within the stage's span for the same reason: a kind marked only outside every span
is filled in by chance again, so the review round 3 "outside the span: none" case is reversed (`test_hud`,
`test_dressing`).

Fixed: `refitTape` finds the crossing along the side road's own direction (s = ((r - c)·n_r) / (d·n_r), still within 2
m), and cuts back only the end that the re-centring takes past the plan's maxLen / 2, not both ends by twice the move
(`test_props`: the cap cut exercised, a side road 30 degrees off square).

Left for later: the full-map scans in `nearEdges`, `roadAt` and `roadCovers` (every node within 250 m, per look) want
a grid index; not done here.
