# Notes: 1.9.4-alpha+reccecalls

Built on 1.9.4-alpha, branch `feature/recce-calls`. The pacenote faults the check found
([`pacenote-check.md`](pacenote-check.md)), fixed. Owner: "go ahead and fix all of those issues, including side
issues" (2026-11-19). Numbers before and after: [`pacenote-check.md`, Fixes](pacenote-check.md#fixes-194-alphareccecalls-branch-featurerecce-calls).

## 1. The first call says how far its corner is

- **Was:** "caution two right" at the line, corner 600 m away. The game clears every note's `before` field on load
  and says distances only after a note.
- **Now:** "600 caution two right". `stageWriter.openingCall` gives the distance, rounded as the game rounds (10 m,
  50 m from 100 m, km from 1000 m: "1 point 2 5 km"). `rallyAdapter.setOpening` puts it on the first note after the
  game's own autofill, and again on every resync and at GO. Said from the voice pack's distance clips, as one after a
  note is.
- Only when the first corner is over `stageWriter.OPENING_MIN_M` (80 m) from the line, and not over 2 km (the
  voices have no clip past that). Worded by the game's own compositor where it can. Casual voices say no
  distances, so none here either.
- **Also:** a corner the stage starts in (a hairpin off the line) was left out by `NOTE_CLEAR_M` (25 m). It is now
  called from 25 m on, when 25 m of it or more is left. Several of the owner's stages start in one (Cathedral,
  Taylor Town, Low Gap: hairpins).

## 2. Long bends drawn as kinks

- **Was:** a map draws a long bend as 2-4 kinks of 5-22° with 130-300 m of straight between. Each kink alone was
  too small to call.
- **Now:** `pacenotes.kinkSweepers` reads the heading. A stretch of up to `KINK_WINDOW_M` (500 m) turning
  `KINK_DEG` (20°) or more one way is a sweeper, from its first kink to its last. Kinks no more than `KINK_GAP_M`
  (320 m) apart, turning back no more than `KINK_BACK` (25%) of it, not within `KINK_CLEAR_M` (10 m) of a corner.
  The turn is the heading's own change, so a line's noise either way cancels out.
- Smooth bends too: a 22° bend at 600 m radius was left out on purpose before (1.6.2); now it is a six.
- `lineStats.VERSION` 5: the stage page counts corners again.

## 3. A corner behind a crest

- **Was:** a crest went on a corner's note only within 40 m of it. "crest 40", then "care three left".
- **Now:** a crest within `stageWriter.CREST_INTO_M` (60 m) before a corner, or with the corner out of sight behind
  it (`pacenotes.hiddenAfter`, up to `CREST_HIDDEN_M`, 100 m), is said with it: "crest three left". A jump stays at
  40 m: the note plays before the corner, and a jump further back could come first.
- No more crest calls: the same crests, a few fewer notes (6.91 per km, was 6.96 before this fix).

## 4. Lines that double back (and the overlapping notes)

- **Was:** 5 of the owner's matched lines go out and back on themselves: 280 m up a dead end at Bolster Hollow,
  180 m at Nahwatzel Meadows, 130 m at Yoctangee Street, stubs of 4-25 m at Stillwater and Far Point. The co-driver
  heard each fold as a hairpin, and they were all 6 overlapping notes.
- **Cause:** two. Bolster Hollow and Nahwatzel: the organisers' own line folds back there (175°, 180°), and the
  recce follows it. The other three: the recce routes waypoint to waypoint, and a waypoint put on a spur or just
  past a junction sends the route out and back.
- **Now:** `geo.foldBacks` drops an out-and-back: a point turning 150° or more, the way back within 8 m of the way
  out, to where the line comes back within 4 m. In the auto recce (new lines), the runner, the stage page and the
  timed length (existing lines), `tools/auto_recce.py`, and the check. The owner's files are not changed.

## Listen for in game

- The first call: the distance first, at launch or right after "go". Then a resync (retry, reset to the start): still
  there.
- A long open bend on a map-drawn road: "six left long" where there was nothing.
- A corner just over a crest: one call with the crest in it, not "crest 40" then the corner.
- Bolster Hollow near 2.4 km: no phantom hairpin, and the stage clock and distance still right.

## Open questions

- **Bolster Hollow, Nahwatzel:** the organisers' line goes out and back. Taken as a drawing slip, not a real
  turnaround. If it is real, `geo.FOLD_MAX_M` could be cut to about 40 m (recce stubs only).
- **Times on the 5 folded stages:** the timed length changes (Bolster Hollow by about 560 m). Saved times there
  read as another line, and the online board key (it holds the length) is new for them.
- **The opening distance in game:** set after the rally engine's own fill; not yet heard.
- **More sweepers:** pro precision 85% to 84%. Some of the new bends are ones the pro does not call. No radius cap:
  20 degrees over 500 m is a 1400 m radius; the game calls it a six. Not checked on driven recces (GPS noise).
- **The check confirms some fixes by itself:** it puts on the same opening distance and drops the same folds. The
  opening is simulated, not heard.
- **Crests over 100 m:** 13 hidden turns on the owner's stages are still called apart, all 100 m or more past the
  crest (the pro has 4 of those).

## Drive findings

### 1. One bend called as a run of short corners (owner, 2026-11-19, Cathedral Westbound)

"Way more corners than there actually are... a 5 right, a 5 right, a 5 right short, when really it's like a 5 right
long or extra long, or maybe even a 5 or a 6 right", worst near the start of Cathedral Westbound.

- **Not new in this build.** Cathedral's calls are the same before and after it, apart from a new "hairpin right
  tightens 90" at 24 m (the corner the stage starts in) and two crests folded into corners. Check that 24 m hairpin
  is real.
- **Where:** 1.86-2.25 km ("three right half long", "and five right short", "and six right short 50" with gaps of
  34 m; then "and five left short", "and four left 150") and 4.09 km ("five left short", "and five left short 150",
  30 m apart).
- **Likely cause:** `geo.corners` ends a corner wherever the smoothed radius opens past `maxRadius` (200 m), and joins
  same-way pieces only within `mergeM` (20 m). A long bend whose map line opens out for a moment splits into pieces
  30-35 m apart. Each piece is short, so the game grades it alone and calls it "short".
- **Why the checker missed it:** no rule looks for this. A plain count does not tell it apart: same-way corners
  within 50 m are 0.62/km on the owner's stages and 0.58/km in the pro's own notes. The pro's pairs differ in grade
  ("4 right into 2 right"); ours are near-identical short ones.
- **Plan:**
  - Checker: a rule for split bends: same-way corner calls within ~50 m, grades within one, with the road still
    turning that way between them. Tune it on the pro's own notes and fail it on Cathedral 1.86-2.25 km.
  - A fixture: a 60-degree bend drawn as three arcs with short near-straight bits between.
  - Fix: in `geo.corners` (or `pacenotes.group`), join same-way pieces up to ~50 m apart when the road between keeps
    turning that way and their grades are within one. Measure them as one corner (length "long" or "extra long",
    "tightens" or "opens" where the parts differ).
  - Watch that real "four right into two right" pairs stay apart: pro recall and precision must not drop.

### 2. Idea: let the speed decide what is a corner (owner, 2026-11-19)

"Can we account for the speed that somebody will be driving? ... a big straight with a tiny, tiny right and a tiny,
tiny left, not much of a corner, but you still need to know they are there."

- **Today:** the speed model (`pacenotes.speeds`: 8 m/s² grip, 144 km/h top) only sets cautions, jumps and how far
  over a crest you can see. Which bends become calls is geometry only: `geo.corners` (12° or more, radius 200 m or
  less), the sweepers and the kinks (20° or more within 500 m). The grade is the game's, from the corner's diameter.
- **What speed would add:**
  - **Small kinks on fast roads.** Call a direction change when, at the speed the car gets there, it takes the road
    off a straight line by more than about half a lane within ~2 s of driving. At 140 km/h a 5-8° kink counts; at
    60 km/h it does not. Those would be called as six (or "slight") with "long" where they are long.
  - **Fewer calls on slow, twisty bits.** Same test: a wiggle you take at 50 km/h without steering need not be called.
  - **Helps the split bends (finding 1).** Pieces of one bend are joined if, at that speed, you drive them as one
    steering input (gap under ~1 s).
- **Not changed:** grades stay the game's (from diameter). A speed-based grade ("flat", by gear) would mean
  overriding what the game measures; it is a bigger change, left for later.
- **Plan:** a checker count of small kinks on fast straights (calls the pro makes that we miss, with the model's
  speed there); then the speed test in `pacenotes` replacing the fixed 12° / 20° limits; fixtures for a 6° kink at
  140 km/h (called) and at 50 km/h (not). Check against the pro: recall up, precision not down.

### 3. Every corner you can see gets a call (owner, 2026-11-19)

"Make sure that any corner that's visible to the player does get a call. Just because it's less than 12 degrees
doesn't make it not important to know about, and it can be confusing not to hear a call when you visually see a
corner."

- **Rule (owner's):** a bend the driver can see is called, whatever its angle or speed. This sets the floor for
  idea 2: speed can join or grade calls, never drop a visible bend.
- **Today:** under 12° (`geo.corners`) or 20° over 500 m (kinks) is never called.
- **"Visible", proposed:** the road's heading settles on a new line at least ~4-5° off the old one (steady for
  ~30 m before and after), or the road leaves a straight line by more than a lane width within sight. Small
  wobbles in the map line (a metre or two, no lasting heading change) are not corners and stay quiet.
- **How it is said:** the smallest the game's voice has, six, with "long" where it is long; joined with "into" /
  "and" when it sits close to the next call so twisty bits do not turn into a list. Open: whether a "slight" or
  "flat" word exists in the enthusiast voice (the pro pack has "into flat right" once).
- **Checker:** a "visible bend not called" rule (any settled heading change of 4° or more with no call of that
  direction over it), tuned on the pro's own notes; fixtures with 5° and 8° kinks on a straight (called) and a
  1.5 m map wobble (not called).
- **Risk:** more calls per km. Watch notes/km against the pro and the "split bends" check (finding 1) together.
