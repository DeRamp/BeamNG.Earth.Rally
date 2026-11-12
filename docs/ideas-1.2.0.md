# Ideas for 1.2.0 (noted 2026-11-12; not started)

1.1.0 is the bug fixes and polish from its test notes (docs/test-notes-1.1.0.md); everything new after that goes
here (the user, 2026-11-12).

From the user, during the 1.1.0 build:

0. **The player UI** (the user, 2026-11-12: "1.2.0 will also include the UI changes"): designed together, mock-ups
   first (docs/plan-1.1.0.md, "Player UI plan"), with the UI items from the 1.1.0 test notes: the reset penalty
   switch (item 2), the off-route warning (item 10), a hint when the start-line skip is possible (item 12).
   Not for now (the user, 2026-11-12): split times, stage sketches / elevation profiles. Work on 1.2.0 starts once
   1.1.0 is installed, while the user tests it.

1. **Closed side roads**: course tape (or other in-game barriers) across the side roads at junctions the stage does not
   take, as real stages close them, so the way on is obvious and the wrong way blocked.
2. **Junction direction signs**: arrow signs at the roadside before a junction showing which way the stage goes, as
   on a real stage. (The game's rally assets have direction boards, e.g. `art/shapes/race/rally/rally_assets/
   s_corner_dir_straight.dae`: check what else is in that folder.)

Both need the junctions along the stage (which roads meet there, which one the stage takes): the same work as 1.1.0's
junction calls (test notes item 9), so they build on it.
