# Pacenotes for 1.5.0: what the co-driver now calls

Branch `pacenotes`. Everything here is read off the stage line the mod already has (its shape, its heights, and the
junctions, bridges and road widths the recce found). Nothing needs a change to BeamNG.Earth. Gravel / tarmac and
tunnel calls were left out (the user, 2026-11-14).

## How it fits the game

The game's rally engine measures each corner's **number** (one to six) and **length** (short, half long, long,
extra long) itself, off the driveline between a note's two waypoints, and puts in "into" / "and" between notes.
Everything else in a note is ours to write, into six fixed slots: 1 a caution, 2 and 3 before the corner, 4 the
corner, 5 and 6 after it (`gameplay/rally/notebook/structured.lua`). Every call used below is in the game's English
style (`compositors/styles/english/modifiers.lua`, `enthusiast.lua`).

**Voices.** The detailed voices (Alex Kihurani, the default; dirtwheel; HighDef) say every call here. The casual
voices (four of the game's seven packs) say only about a dozen modifiers, no corner shape, and nothing at all for the
rest, so the mod reads which style the player's voice uses (`rallyAdapter.speaks`, from the game's own voice pack
and style files) and leaves out what it cannot say: no silent notes. What a casual voice cannot say in a corner's
shape it hears another way where it can: a crest inside a corner is "over crest" after it (the casual voices say
"crest"), and a chicane is its two corners for a voice with no chicane call. The developer panel shows the style it
found ("Co-driver style"). The voice is read when the notes are built: one changed in Options during a run is used
from the next run (a retry builds them again).

## The calls

| Call | Read from | Where |
|---|---|---|
| hairpin, tight hairpin | 135 degrees or more, tightest radius 20 / 11 m or less (the game's own hairpin test) | in place of the number |
| square | 70 to 115 degrees, radius 18 m or less, 45 m or shorter | in place of the number |
| tightens, opens, opens and tightens | the curvature over the corner's core, one part 1.6 times tighter (2 for the middle) | after the corner |
| over crest, tightens over crest, opens over crest | a crest inside the corner | the corner's shape |
| tightens down | a tightening corner 6 % downhill on average | the corner's shape |
| chicane left / right entry | two tight corners either way, 15 m apart or less, 90 m in all | one note in place of both |
| twisty | four or more fast corners (radius 60 m+) flicking either way, 40 m apart or less | after the first of them; every corner still called |
| care, caution, double caution | the corner's speed against the approach since the last corner (40 / 30 / 22 % of it, from 90 km/h); a care on a corner of 45 degrees or more after 80 m with none; a corner that tightens over a crest from 72 km/h, a caution at least; and, for a voice that cannot say "tightens", a care on a corner that tightens from 72 km/h | slot 1 |
| crest, small crest, big crest; into crest; over crest | the grade change over 20 m either side: 6 % (8 % on its own), big at 14 % | before / after / in a corner, or its own note |
| jump, big jump, over jump | a big crest (14 %) the modelled speed cannot follow: 1.4 g, its vertical radius measured over 10 m (big: 2.4 g and 22 %) | before / after a corner, or its own note |
| brake over crest | a crest just before a corner with a caution (and one caution more) | before the corner |
| dip, bad dip, through dip | the grade change upward: 14 % (18 % on its own), bad at 22 % | before / in / after a corner, or its own note |
| up, down | 8 % or steeper for 100 m or more, on the first corner that ends on it with 60 m of it still to come | after the corner |
| keep left / right over crest | a fork on a crest | its own note |
| narrows | the road's width ahead at most 70 % of the 200 m behind, 1 m (half width) less, and narrow at the point | as a junction: on the corner, or its own note |
| over finish | on the note ending last if it is within 100 m of the finish, else a note of its own | the game's own stages all do it |

Unchanged: at junction, past junction, keep left / right (now before the corner when the fork is inside it), over
bridge.

A note holds two calls before its corner and two after, and one call of each family (jumps, crests, dips). Where
more apply, the highest in `stageWriter.PRIORITY` are spoken: finish, then a jump, a chicane, a crest, keep left /
right, a dip, narrows, a bridge, a junction, twisty, a hill.

Heights no road has -- a step between two samples steeper than 40 % (elevation data does that: one matched line
drops 6 m in 4 m, 150 %) -- are not read: no crest, jump or dip within 20 m of one. Nor round a bridge (60 m either
side): the line's heights there are the valley under the deck, which read as "big jump, bad dip". Only a peak of the
grade change is an event; a dip's two rims are not crests, nor are they when the dip itself gave way to a stronger
crest beside it. A jump has to be a big crest as well: most
lifts over 1.4 g are at the speed model's top speed, where a few centimetres of elevation data decide it.

**Speed model** (`pacenotes.lua`): 8 m/s² sideways, 3 m/s² gained, 7 m/s² braking, 40 m/s (144 km/h) top, from a
standing start. It only has to say where the road is fast and how much slower a corner is.

**Narrows** needs a stage matched in the game (the auto recce): the road graph's widths come from its lane counts.
A file from `tools/auto_recce.py` has no `narrows` key (never looked); one matched in the game has a list, empty
when it found none.

**Left out after review** (2026-11-14): "open hairpin" (a third of them were not hairpins in the game's own notes,
and a descriptor drops the length call), the game's two / three-part corner measurement (its own stages use it once
in 166 shaped corners, and it splits where it likes, not where the corner changes), and "to stop" (the game's own
stages put it past the finish, 14 of 15; the mod turns the co-driver off at the finish, so it would never be heard --
the mod's choice, which could change).

## How it was tuned

- `python tools/pacenote_benchmark.py`: the notes the mod writes on the game's own 15 rally stages (81 km) against
  the game's hand-made ones, per kind of call, within 50 m: found (of the game's) / agreed (of ours). The drivelines
  are followed across as the game's road tools follow them (centripetal Catmull-Rom; `--straight`: straight lines
  between their nodes, as before), their heights by a monotone cubic through the nodes -- not as the game does, which
  takes them off the terrain under each point. Corners 88 % / 97 %; hairpins 86 % / 66 %; square 50 % / 67 %; crests
  47 % / 44 %; opens 40 % / 41 %; tightens 18 % / 43 %; cautions 26 % / 21 % (a care on every corner: 12 %). The drivelines have a node only every 14-40 m, so a sharp hump between two is
  not in them: the jump and dip rows are a floor, and say little (the game calls 34 jumps, we 2). Hills, which that
  spacing does show, agree 2 of 29.
- `python tools/pacenote_survey.py <earthRally folder>`: rates per km over the user's matched stages, a line saved
  under two names counted once (93 stages, 1,299 km): 5.93 notes / km, 4.67 corners / km, cautions on 12 % of
  corners (the game's own stages: 8.1 % of corner notes), crests about 1 / km in all (shapes included), jumps 0.03 / km
  (6 big ones in all), dips 0.13 / km, hairpins 0.14 / km, square 0.10 / km, up / down 0.11 / km. `--casual`: as a
  casual voice hears it (4.92 notes / km, cautions on 16 % of corners; its crests said after the corner, not lost in
  a shape it does not say). `--stage <name>`
  lists one stage's notes in order, with where they are.

Cautions are still the weakest call: the game puts many of its own on plain corners for reasons a line does not show
(a blind entry, a drop, a tree). What its stages' cautions do follow is the straight before a corner (5 % of corners
after less than 30 m, 16-17 % after 80 m or more) and its shape (tightens 21 %, square 19 %, a crest 15 %), not the
radius; hence the care after a straight (the third review, 2026-11-14), which took the benchmark from 10 % / 15 % to
26 % / 21 %. It is fitted to the same 15 stages it is scored on.

## To check in game

1. **Jumps and crests match the road.** The heights are BeamNG.Earth's; whether the road it builds keeps a sharp hump
   the line shows is the one thing the offline tools cannot tell. A "jump" on a road that is flat is the first thing
   to log.
2. **Hairpin / square on the corners they name.** They replace the number, so a wrong one is worse than none.
3. **Cautions** where the corner is a surprise and not on every slow corner.
4. **Chicane**: whether one call in place of the two corners is clear enough.
5. **A casual voice** (Options, rally co-driver): no note goes by in silence, and the crests in corners are said.
6. **Narrows**: no matched line in the backup has the `narrows` key yet (it is new), so it has been tried on drawn
   roads only.

## Not done, for the user to decide

- A co-driver **detail setting** (the roadmap's "Co-driver settings: call timing, detail, voice"): the contrarian
  review would put cautions, jumps, dips, hills and narrows behind it until they are checked in game. It is UI, so
  it waits for a mock-up and the user's word.
- **Cut from 1.5.0, or keep?** The second contrarian review would cut these, on the numbers above; all were in the
  list agreed, so they stay until the user says:
  - twisty: 4 calls in 1,299 km, none where the game has one;
  - chicane: 15 calls, none where the game has one, and each takes two corner numbers away (with it off, the
    benchmark's corners go up a little);
  - up / down: 2 of 29 agree with the game, on data that does show hills;
  - dips: only "bad dip" (22 %), or none -- they cannot be judged offline either way.
- **Hairpin at 16 m, not 20 m** (the game's own test): the benchmark goes from 86 % found / 66 % agreed to 82 % / 80 %.
  It is fitted to the same 15 stages, so a thing to try in game.
- **Jumps at all?** Two thirds of them are where the speed model is at its top speed (144 km/h), so "jump" mostly
  means "a big crest where the road is fast"; the benchmark cannot judge them (the game calls 34, we 2, on drivelines
  too coarse for humps). Behind the detail setting, as a big crest, or as they are. A real check would read the
  game's terrain heights under its own stages.
- **A voice changed mid-run**: the notes are built for the voice at the start; the game rebuilds them for a new one
  at once, so a casual voice picked mid-run can meet notes it cannot say, until the retry. The developer checks
  could flag it.
