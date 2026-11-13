# Earth Rally 1.2.2: notes from testing 1.2.1

Items the user reports while testing 1.2.1, to build into 1.2.2. Logged only: no changes until the user says so.

1. **Rally menu: long rally names run out of their card** (e.g. "V1 Rally Colorado 2026 Controls and Route"). Cut
   them short with "…" inside the card.
   - Already built by mistake before this list was started: commit 49f5eb5 (in the 1.2.1 branch, installed). Keep it
     in 1.2.1 or revert it to 1.2.2, as the user prefers.
2. **No start time on screen after the ATC** (Maryhill Up). After checking in, a pop-up shows in the top-right corner
   and then goes away. There should be a start time and the current time at the top of the screen until the start.
3. **No progress bar at the top of the screen on stage** (Maryhill Up, 1.2.1: the layout hold did not bring it back).
   Log of that run (2026-11-13, t=233-280 s): no "layout put back" line, so the stage layout was not replaced; the game's
   top-centre app container logged `visibleApps` twice at 233.9 s (just after the run moved to the ATC). So the layout
   is there but the top-centre apps (start time / clock / progress) aren't showing: look at how the HUD feeds them
   and which apps the top-centre container lists. Likely the same cause as item 2.
4. **Off route shows nothing** (Maryhill Up, 1.2.1): driving off the road, the pacenote cards don't dim and no card or
   message appears. Check whether the runner sets offRoute at all (log it), then whether the HUD gets it: possibly the
   same HUD feed problem as items 2 and 3.
5. **None of the on-stage HUD shows up at all** (the user, after the whole test plan: "I don't think anything is
   showing up on the UI"). Items 2, 3 and 4 are this one fault. The user's idea: a separate rally UI the game swaps to
   when the rally starts. That is the design already: the runner swaps to its own layout `earthRallyStage`
   (settings/ui_apps/originalLayouts/default/earthRallyStage.uilayout.json, runner.lua:248-261) with the HUD app
   `app.earthRallyHud.vue`. So first find why it doesn't show:
   - is the layout applied? (the log has no line either way: log `getGameState().appLayout` after setting it, and the
     layouts the game knows; the user folder's settings/ui_apps/layouts/default/ holds only beamngEarth.uilayout.json)
   - does the HUD app mount and get its data? (the menu's HUD preview, 1.2.0, is a separate path)
   - does the stage's own layout carry the HUD app, at the right size and place?
   If the layout route can't be made reliable, the user's fallback: the rally HUD as its own full-screen overlay,
   shown by the mod itself during a run, independent of the game's app layouts (mock-up to the user first).

(Moved to 1.3.0 by the user: a stage with no ATC gets one added before the start; docs/plan-1.3.0.md.)

## 1.2.1 checks passed

- Start tree: the clock now faces the right way.
- Resets: a held rewind counts once.
- Backspace: back on the stage's road works well.
- New rallies: SnoDrift and SOFR stages show up and run (SOFR's `.kml.xml` files imported).
