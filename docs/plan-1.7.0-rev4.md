# 1.7.0 revision 4: build plan (issues #51-#71)

The third drive's findings: `docs/notes-1.7.0.md`, "Third drive" 1-21, each with a diagnosis and a fix idea, then
"Owner's decisions on the third drive". The approved screens: `docs/mockups-1.7.0/rev4.html` (open it, read every
screen's note). Where this plan and the notes differ, this plan wins (it folds the decisions in).

Three builders work at once in this worktree, each on its own files. **Touch only your own files.** If you need
something from another builder's files, it is in "Interfaces" below; if it is not, write it down in your report
instead of editing their file.

| Builder | Files it owns | Issues |
|---|---|---|
| **Lua** | `mod/earth_rally/lua/**` (runner, rallyRun, rally, props, loadScreen, main, menu, hudFrame, menuPause, earthAdapter, stageWriter, ...), `tests/**` | #58 #59 (Lua side) #63 #64 #65 #66 #67 #68 #69 #70 #71 (Lua side) #54 (data) #57 (day of the start row) |
| **Menu** | `mod/earth_rally/ui/ui-vue/mods/earthRally/**` | #51 #52 #53 #54 #55 #56 #57 #60 #61 #63 (bar) #64 (card) #71 (card) |
| **HUD** | `mod/earth_rally/ui/modules/apps/earthRally/**` | #58 (prompt card) #59 #62 #67 (HUD line, if the HUD app draws it) #69 |

Bug fixes only: no new systems beyond what the notes describe. Comments in the code's own style (why, not what).
Real rally names never in tests or comments: made-up names only.

## Decisions folded in

- #56 Class stays with Car. Rally settings = Mode + Cancelled stages.
- #57 main button "Start transit · to SS4 Name" everywhere (also from a service).
- #59 no "key again = recover"; no 10 s timeout. A / D-pad / stick on the card, B = Keep going. The game pauses.
- #68 one red time control board and one tent at a service / overnight / regroup point.
- #54 the stage chips stay; a driven stage's chip shows your time on it ("SS3 6:12.4"). Position and total "--".
- #71 finished card: New rally (selected by default) and Continue driving.
- #69 Realistic: no free recovery on a transit; the key raises the same Recover? question (recover = back in at the
  next service under Super Rally, the stages skipped scored under Super Rally). Casual unchanged.
- #63 the origin move happens with physics running and the car held still, before the loading pause comes on.
- #58 the load starts only after a full stop at the ATC board AND a yes to "Load the stage?". The prompt pauses the
  game too (so A reaches it, as #59), a small change from the mock-up's note.

## Interfaces (Lua provides, Vue reads)

1. **Loading screen data** (`earthRally_main.uiLoading()`, `loadScreen.ui()`): add
   - `moving = true` while the world's origin move is not done (BeamNG.Earth's anchor not committed / rebasing, or
     the run still in its `anchor` state). The World bar shows a moving stripe and "Moving the world..." then.
   - ATC card (`kind = 'atc'`): `card.timeIn` (as now, the moment the car stopped), `card.checkedIn = true` once
     checked in, `card.startNote` = "given when you continue" until ready, then e.g. "+1 min after Continue".
     The first step text is "Checked in", the second "Moving the world to the stage".
2. **Load prompt (#58)** in the HUD stream (hudFrame `ours.rally`): `ours.rally.loadAsk = { ss, name, km }` and
   `show.loadAsk = true` while it is up. Answers through the results card's action call, the same path as
   `recover` / `keep`: the HUD app's `act(what)` calls `earthRally_main.uiResults(what)`; the Lua side routes
   `'load'` and `'notYet'` to rallyRun (as it routes `recover` / `keep` to `rallyRun.answer`). Not yet: the car must move away (beyond the board radius) and stop at the board again to re-ask.
3. **Recover? (#59, #69)**: as now, `ours.rally.ask` / `show.recoverAsk`; `ask.transit = true` when raised on a
   transit. While it or the load prompt is up the game is paused (`menuPause.card`, as the finish card). Answers
   `'recover'` / `'keep'` unchanged.
4. **HUD line (#67)**: approaching any control, once within its radius and not stopped: the existing HUD
   approach line (hudFrame) says "Stop at the time control's red board" (ATC) or "Stop at the board to check in"
   (service, overnight, regroup) with the distance. Lua-side text; the HUD app only shows it if it is its line.
5. **Results tab (#54)**: the rally results data (menu.lua `results`) gets per chip `timeS` (your best on that
   stage, nil if not driven). Vue formats it with the existing time helper.
6. **Finished card (#71)**: time card data `done = true` as now. New actions on the menu page's rally action call
   (store.js `rallyAction(what, id)` → `earthRally_main.uiRallyAction(what, id, opts)`): `'endNew'` (finish the rally, keep it as finished, stage layout off, then the page
   opens Home) and `'endDrive'` (the same, then close the menu: plain BeamNG.Earth free roam). Answer `{ ok }`.
7. **Time card (#57)**: the start row carries `day` (the first stage's day) so the Day 1 header goes above it.
   Main button label: `goLabel` (Vue) "Start transit · to SS1 Name" at the start and out of a service.

## Per builder, the work

**Lua**
- #58 runner `atBoard`: fire only when stopped (`STOPPED_MS`) within `AT_BOARD_M` of the board; drop the any-speed
  (`AT_BOARD_PASS_M`) and start-line (`AT_BOARD_START_M`) cases. rallyRun's arrive handler raises `loadAsk`; `'load'`
  runs today's ATC load; `'notYet'` clears it until the car leaves and stops again.
- #63 the stage load at the ATC (and every loading screen that teleports or moves the origin): run the anchor step
  first with physics on and the car held (BeamNG.Earth's hold or a freeze), push the pause only once the origin is
  moved or the wait gave up. Check `beamngEarth/core.lua` in `..\..\..\..\beamng.earth-fork-release` (read only)
  for what blocks a commit while paused (~line 2024) and a rebase's phase 2 (~2927). `loadScreen.ui().moving`.
- #64 skip the `toAtc` message when the rally checks in behind the card; no "Drive to the time control" after
  Continue. The start time is given when Continue is pressed (now + the usual minute), not at the check-in.
- #65 log one line per pacenote called by our side if there is a hook for it, and a line when notes go on/off. On
  a world shift during a run, rebuild the co-driver's positions in the new frame if it is cheap; otherwise log
  and leave it for the owner's drive (say which in the report).
- #66 the finish and stop control sites stay after `tidy`, dropped by distance (beyond `props.SPAWN_M`) or at the
  next stage's setup or a teleport.
- #67 every arrival (service, overnight, regroup, end service) needs a stop: drop `ARRIVE_M` at any speed; stopped
  within the radius (keep `ARRIVE_NEAR_M` 500 m for the venue point, or the board's 25 m once #68 places one; use
  the board when it is placed). HUD line as interface 4.
- #68 a props site kind for service / overnight / regroup: one TC board + a tent, placed on the nearest road to the
  stop's point (`props.roadAt`), facing along it. Put out when that stop is armed, dropped by distance after.
- #69 `rallyRun.recoverKey` on a transit in Realistic: raise the Recover? question (`ask.transit = true`); recover
  = rejoin at the next service under Super Rally (the stages before it missed). Casual unchanged.
- #59 pause while `ask` is up; drop `ASK_S` and the key-again path.
- #70 `approachVia`: put the direction point on the road, 30-60 m back from the ATC along the road map, or skip it
  when the route already arrives the right way. Must not send the car round a block.
- #71 `rally.orderOf`: after the last stage always a final service (the last day's service park, else the rally
  start's place), driven to with a stop; the rally is done there. `endNew` / `endDrive` actions (interface 6).
- #54 per-stage times in the results chips (interface 5). #57 the start row's day (interface 7).
- Tests: update / add in the matching `tests/test_*.lua`; run only those touched
  (`python tests/run_tests.py test_run test_rally ...`). Never `test_arearoute_e2e` / `test_roadgraph_e2e`.

**Menu** (Vue in `ui-vue/mods/earthRally/`)
- #51 one selection: outline on focus only; mouseenter focuses the element. All selectable tiles / cards / rows.
- #52 Drive rally cards: the highlight drawn above the picture (`::after` layer).
- #53 BeamNG's bottom strip (version line, its button hints) must not cover ours: find how the game's own
  full-screen pages handle it (the game's ui-vue source is not in this repo; look at how `EarthRally.vue` is routed
  and what layout it uses). If it cannot be hidden, keep our prompts bar clear of it. Say in the report which.
- #55 Results opened from Drive rally: remember it (like `startFrom`), crumbs "Home › Drive rally › X results",
  Back and B go back to Drive rally with the same rally picked.
- #56 Start the rally layout as the mock-up: "Rally settings" header, big Start at the lower right (selected on
  open), warnings above it.
- #57 time card: Day header above Start (interface 7), big "Start transit · to X" lower right, selected on open.
- #60 the loading screen replaces the page: the page underneath is not drawn while it is up; solid background.
- #61 Continue on the ATC card is focused when it appears, and A presses it whenever it is ready (an ok handler on
  the overlay), wherever the focus is.
- #63 World bar: `L.moving` → moving stripe + "Moving the world...".
- #64 ATC card rows: Time in, Due, Start time (`card.startNote`), Then.
- #54 Results tab (`EarthRallyResults.vue`): no overlay, no greyed table; "Your rally" card with "--" position,
  "N of M stages driven", chips with times, total "--".
- #71 finished card: result, Full results, two big buttons, New rally selected.

**HUD** (`ui/modules/apps/earthRally/app.earthRallyResults.vue`)
- #62 the finish card: A presses the picked button at once. Log every ok / d-pad the card gets (gameLog). Give the
  picked button the real focus as the card comes up and when its buttons change. Test the logic with the game
  paused under it (it is now).
- #59 the Recover? card: A / D-pad / stick pick, B = Keep going; drop "Backspace or D-pad → again" and "drive on
  and it goes after 10 s" from its text. Ring always shown (one selection).
- #58 the "Load the stage?" card (interface 2), same look and behaviour as Recover?: Load (A, selected) / Not yet (B).
- #69 Recover? text when `ask.transit`: "Recovering ends your transit. You rejoin at <stop> under Super Rally."

## Done means

- Each builder: touched tests pass; a short report: what changed per issue (files, functions), what it could not
  do and why, anything the other builders must know.
- Then the lead runs `/handoff` (debugger + contrarian + /code-review) over the whole diff.
