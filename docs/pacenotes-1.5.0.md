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
voices (four of the game's seven packs) say only about a dozen modifiers and nothing at all for the rest, so the mod
reads which style the player's voice uses (`rallyAdapter.speaks`, from the game's own voice pack and style files)
and leaves out what it cannot say: no silent notes. The developer panel shows the style it found
("Co-driver style").

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
| care, caution, double caution | the corner's speed against the approach since the last corner; and a corner that tightens on a fast approach (one more over a crest) | slot 1 |
| crest, small crest, big crest; into crest; over crest | the grade change over 20 m either side: 6 % (8 % on its own), big at 14 % | before / after / in a corner, or its own note |
| jump, big jump, over jump | a crest the modelled speed cannot follow: 1.4 g over its 10 m radius (big: 2.4 g and a big crest) | before / after a corner, or its own note |
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

Heights no road has -- a step between two samples steeper than 25 % (elevation data does that: one matched line
drops 6 m in 4 m) -- are not read: no crest, jump or dip within 20 m of one. A dip's two rims are not crests.

**Speed model** (`pacenotes.lua`): 8 m/s² sideways, 3 m/s² gained, 7 m/s² braking, 40 m/s (144 km/h) top, from a
standing start. It only has to say where the road is fast and how much slower a corner is.

**Narrows** needs a stage matched in the game (the auto recce): the road graph's widths come from its lane counts.
A file from `tools/auto_recce.py` has no `narrows` key (never looked); one matched in the game has a list, empty
when it found none.

**Left out after review** (2026-11-14): "open hairpin" (a third of them were not hairpins in the game's own notes,
and a descriptor drops the length call), the game's two / three-part corner measurement (its own stages use it once
in 166 shaped corners, and it splits where it likes, not where the corner changes), and "to stop" (a note past the
finish, where the co-driver is already off).

## How it was tuned

- `python tools/pacenote_benchmark.py`: the notes the mod writes on the game's own 15 rally stages (80.8 km) against
  the game's hand-made ones, per kind of call, within 50 m. Corners 98 % of ours where the game has one; hairpins 84 %
  found, 63 % agreed; crests 46 % / 45 %; cautions 24 % / 23 % (from 10 % / 17 % before the review). The game's
  drivelines have a node only every 20-40 m, so a sharp hump is often not in them: the jump and dip rows are a floor.
- `python tools/pacenote_survey.py <earthRally folder>`: rates per km over the user's 116 matched stages (1,514 km):
  5.74 notes / km, 4.61 corners / km, cautions on 9.2 % of corners (the game's own stages: 8.7 %), crests about
  1 / km in all, jumps 0.06 / km (3 big ones in all), dips 0.08 / km, hairpins 0.13 / km, square 0.09 / km.
  `--stage <name>` lists one stage's notes in order, with where they are.

## To check in game

1. **Jumps and crests match the road.** The heights are BeamNG.Earth's; whether the road it builds keeps a sharp hump
   the line shows is the one thing the offline tools cannot tell. A "jump" on a road that is flat is the first thing
   to log.
2. **Hairpin / square on the corners they name.** They replace the number, so a wrong one is worse than none.
3. **Cautions** where the corner is a surprise and not on every slow corner.
4. **Chicane**: whether one call in place of the two corners is clear enough.
5. **A casual voice** (Options, rally co-driver): no note goes by in silence.

## Not done, for the user to decide

- A co-driver **detail setting** (the roadmap's "Co-driver settings: call timing, detail, voice"): the contrarian
  review would put cautions, jumps, dips, hills and narrows behind it until they are checked in game. It is UI, so
  it waits for a mock-up and the user's word.
