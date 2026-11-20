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
