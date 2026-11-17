# 1.7.0 notes: the full rally MVP

Branch `full-rally-mvp`, from `main` at 1.6.2. Plan: [`plan-1.7.0.md`](plan-1.7.0.md).

## Revision 2 (issues #23-#33)

The first drive's findings are now issues #23-#33. This revision answers all of them.

| Issue | What changed |
|---|---|
| #23 | The auto recce runs on Start for every stage with no line. Downloads are accepted for you. |
| #24 | The time card is trimmed: no "full repair · game saves" on each row, shorter start screen. |
| #25 | D-pad right is the rally's recovery on an Xbox pad (`xidevice_earthRally.json`). |
| #26 | The rally starts at the event file's start place, at the first service when there is none. |
| #27 | Control hints in the HUD's bottom-left: recover, flip upright, time card, skip the wait. |
| #28 | Leave rally (continue later) and Retire (save deleted), each with a confirm saying what it costs. |
| #29 | Dev panel: jump 500 m or 100 m before the finish; skip the transit. Not in the main UI. |
| #30 | A stage with more than 250 m of its road missing from the map is held out of the rally and listed. |
| #31 | A Realistic recovery takes you to the service you rejoin at; you drive the transit from there. |
| #32 | Logs show the car did go to SS4's stage; the "SS6" was not reproduced. A test now checks SS1 → SS4. |
| #33 | Services are places on the map. Transits are driven: follow the GPS, the stage loads as you arrive. |

## Before driving

- **Re-import happens by itself.** The pack reader is newer again (places), so the first scan imports every pack.
  Your times and ids are kept.
- **The dev panel** (Settings → Developer panel) has the new rally tools under the run tools.
- The mock-ups were skipped for this revision: you asked for it built.

## Open questions for the owner

- **Transit lengths** are not measured. Some ARA transits are 30-50 km. Is a player skip out of service wanted
  after all? (#33 says dev panel only, as built.)
- **No pad button for the time card.** Service out, Leave and Retire need Ctrl+Alt+K.
- **A broken car on a transit in Realistic** can only Leave. Casual's transit recovery repairs it.
- **#32:** where on screen did "SS6" show? The logs say SS4's stage loaded.
- **Saves from the first MVP build** are not continued (the save format changed). Start the rally again.

## Test plan (one rally with an event file, day 1)

1. **Start (Casual):** the start screen lists stages to recce and stages held out. Start: any recces run first,
   then the car goes to the start place and the time card opens.
2. **Transit:** Go on the time card. Follow the GPS arrows to SS1's time control. The Messages app shows the
   transit and distance; the hints show recovery and the time card. The stage loads as you arrive.
3. **Transit recovery:** off the road on a transit, Backspace or D-pad right puts you back on the nearest road.
4. **Dev panel:** on SS1, jump 500 m before the finish. At the end, the card stays until you drive on.
5. **Service:** after the last stage before a service, follow the GPS to the service. On arrival the car is
   repaired, the game saves, the card opens. Service out arms the next transit.
6. **Realistic recovery:** Start again in Realistic. On SS1, Backspace twice. You land at the service you rejoin
   at with the Super Rally card, then drive to the right stage (SS4 in the old SS1 case).
7. **Leave and Continue:** Leave rally from the time card. Its confirm says where you continue from. Continue on
   the rally page brings you back there.
8. **Retire:** from the time card or the rally page. The confirm says the save is deleted. It is.
9. **BeamNG's recovery off** during the rally; back after Leave or Retire.
10. **Finish** (if you get that far): the finish card, then the Results tab.

## Revision 3 (issues #34-#50, built 2026-11-16)

All 17 findings below are built on `full-rally-mvp`. Not yet driven. Changes from the plan:
- #40: a stage with an ATC loads when the car stops at the ATC's board, behind the time control card. Only the ATC's
  boards and tent go out ahead; the start's props appear behind the card.
- #43: the game pauses under the finish card only at a stop control. Ctrl+Alt+K takes the card's Continue.
- #46: tape from the ATC reaches only about 30 m before the start (the stage line starts 30 m before it).
- #48: the overnight is at the same day's service park, driven to; with none that day, at its own place, driven to.
- #49: the World bar reads BeamNG.Earth's load counts round the car (ground, roads, trees). No fork change needed.
- #50: the rally under way is never hidden by a rescan; a saved one whose file is gone is.

## Findings

(Logged here while the owner drives, with the diagnosis. Not fixed during the drive.)

1. **The rally's auto recce runs blind.** Start closes the menu, then the recces run with only a message per stage.
   You can't tell what it's doing or how far along it is. *Diagnosis:* `rallyRun.start` calls `ui.closeMenu()`
   before `getReady`. The time card's prep panel (`EarthRallyFull.vue`, "GETTING THE STAGES READY") shows only
   "name (i of n)", and the card is closed anyway. The single-stage auto recce's progress (`st.auto`: going,
   downloading %, window x of y) is shown on the rally page only. Issue #34. The owner calls it a bug fix and said
   **No mock-up** (2026-11-16). **Not built yet:** it waits until the owner has found all of this version's bugs
   and says go.
   *Plan:*
   - Start keeps the menu up on the time card instead of closing it. The auto recce runs fine under the menu's pause
     (finding 10: Wasp's whole recce ran paused, 400-471 s), so `menuPause.suspend()` may not even be needed.
   - The card's prep panel lists each stage: waiting, running, done, or failed with the reason.
   - For the stage in progress, the panel shows going to the stage, download %, window x of y, and a bar.
   - The card closes by itself when the car goes to the start.
   - Files: `rallyRun.lua` (no `closeMenu` on Start during prep, keep each stage's result), `main.lua` (`st.auto`
     detail into the card), `EarthRallyFull.vue` (the panel), `tests/test_run.lua`.

2. **After the auto recce, nothing on screen says the rally is ready to run** (Overmountain Rally). With the menu
   closed, nothing says what to do next. The only way in is the time card's "Drive to SS1 Low Gap" button. The
   owner's rule: *while a rally is running, the player is never left without one of the gameplay loops to be in.*
   *Diagnosis (the log):*
   - 715 s: the prep ended. Newport Speedway was held out, having no road on the map.
   - 719 s: the car reached the Start, and `arrive()` opened the time card. That part worked.
   - 748 s: the card was closed. The rally then sat at the Start in phase `stop`.
   - 845 s: the owner reopened the card and pressed Go. The transit to SS1 was armed then.
   - In phase `stop`, nothing outside the card says the rally is waiting on you. There is no HUD line and no GPS,
     only the generic "time card" hint. Closing the card leaves you nowhere.
   - It is not only the Start: a service after its card is closed is the same phase.
   - Finding 1 makes it worse: the card appears out of nowhere after the blind prep, so it reads as a menu to
     dismiss.
   *Fix idea (not built):*
   - In phase `stop`, the HUD always shows what is next and how to go: "Rally ready · SS1 Low Gap next · [pad /
     key] open the time card to start".
   - Or Go becomes a HUD prompt on its own, so the card isn't the only way in.
   - Check every rally phase for a state with nothing on screen (`stop`, `toGo`, `moving`, `done`).
   - Files: `rallyRun.lua` (`uiCard`/HUD data), `hudFrame.lua` (the line and hint), `app.earthRallyHud.vue`,
     `tests/test_hud.lua`, `tests/test_run.lua`. Issue #35.

3. **Developer panel: hide the rally list** (feature, next version). The menu now does everything the panel's
   list did (go to a stage, recce, auto recce, drive), so the panel needs only its tools. *Where:* `main.lua`
   `drawWindow`, which draws the list of rallies, then each stage of the selected rally, then that stage's buttons.
   *Idea:* drop the list or hide it behind a collapsed "Rallies (old)" header. Before removing it, check that
   nothing else in the panel reads `selEvent` / `selStage`. The run tools and the full rally tools work on the run
   or rally under way, not on the selection. Issue #36.

4. **Radio and medical tents spawn before the start line** (Overmountain SS1 Low Gap; next version). Both stand at
   the same spot before the start. The owner: points that close to the start are merged with the start, so they
   belong past the start line. *Diagnosis:*
   - `dressing.lua` keeps the map's points from `MARKS_SPAN_PAD_M` (100 m) before the start to as far past the
     finish (the filter at ~780).
   - `post()` then places each point at its own `along`, so a point 0-100 m before the start puts its boards and
     tent before the line.
   - A radio and a medical point within `SHARE_M` (50 m) share one post. Here the two came out on top of each
     other, so check whether the share worked, given the medical is only `MEDICAL_AFTER` (8 m) on.
   *Fix (the owner's call):* leave them out. A radio or medical point within N m of the start or the finish is not
   placed at all: the start and finish tents stand in for it, as at a real rally. Files: `dressing.lua`,
   `tests/test_dressing.lua`. Issue #37.

5. **"Leave rally" becomes "Save and quit"** (next version). Retire stays Retire. *Where:*
   - `EarthRallyFull.vue`: the button (~155), the confirm's button (~142) and its heading "LEAVE THE RALLY?" (~137).
   - `runner.lua` ~1758: the stuck-transit warning names "Leave rally".
   - Comments in `main.lua` and `rallyRun.lua`.
   *Watch:* the game saves only at a service, so "Save and quit" mid-loop doesn't save the spot you're at. The
   confirm already says "You continue later from <last service>", plus the Super Rally and "driven again" warnings.
   Keep those so the name doesn't promise more than it does. Issue #38.

6. **The menu opens on a choice: Drive stage or Drive rally** (next version). The owner wants it more legible to
   players who just want to play.
   - **Drive stage:** the rallies list as it is now. Open a rally, pick a stage, drive it, as today.
   - **Drive rally:** choose a rally, then into its full rally (the start screen, or Continue for a saved one).
   *Where:* `EarthRally.vue` views (`rallies`, `season`, `rally`, `stage`, `settings`, `rallyStart`, `timecard`).
   It would add a new home view in front of `rallies`, with a Drive rally list next to it. `back()` and the
   breadcrumbs change with them.
   *To settle when built:*
   - The Drive rally list shows only rallies with an event file (no event file, no full rally), with a saved
     rally's Continue on its row.
   - Single-stage packs and seasons stay under Drive stage.
   - Settings stays reachable from the home screen.
   - A rally under way opens straight on its time card (as Ctrl+Alt+K does now) or on the home screen.
   - Mock-up: `docs/mockups-1.7.0/home.html`, awaiting OK. Issue #39.
   *The owner, adding to it:*
   - Make Start, the rally button and the rest of the full rally much more obvious. That is what the player cares
     about, not all the little stages.
   - For the mock-up, look at DiRT Rally's menus, BeamNG's own Rally mode (`gameplay_rally` in 0.40) and other
     rally games for inspiration: how big the play choices are, how a rally / championship is picked, how much of
     the stage list shows up front. Borrow the ideas, not their look or art.
   - Stages stay one level down (Drive stage, or inside a rally's page).

7. **On a transit, load the stage at the ATC behind a menu** (next version). Load the stage when the car reaches
   the ATC, not on the way, and open a menu then, so the loading transition is hidden from the player.
   *Now:*
   - `runner.armApproach` loads the stage `APPROACH_M` (1000 m) before the ATC while you're still driving
     (`runner.lua:82`; the log: "the stage loads 1000 m from its ATC").
   - The loading (world, props, the car placed) happens in view, mid-drive.
   - 1000 m was picked so the ATC's arrows and boards exist before you reach them: BeamNG.Earth streams the map in
     only around the car.
   *Fix idea:*
   - On a rally transit, arm the approach to fire on arrival at the ATC (within the arrive distance, or stopped
     near it).
   - Open a time control card first: "SS1 Low Gap · time control", your time in, and a **Continue** button (the
     owner: you're just continuing on).
   - Load the stage behind it, and enable Go once the stage is ready.
   - The game runs under the card (`menuPause.suspend`), as Go already does.
   - **The owner: the boards and tents should still appear for the ATC and the start.** So split the load:
     - On the approach, at `APPROACH_M` as now, place only the ATC and start props (boards, tents) as a light
       prop set.
     - The full stage (line, dressing, run) loads at the ATC behind the card.
     - Check that BeamNG.Earth has the ground there by then. It is the same 1 km lead as today.
   - Files: `runner.lua` (an arrive mode for armApproach), `props.lua` (the control props alone), `rallyRun.lua`, `EarthRallyFull.vue` (the TC card),
     `tests/test_run.lua`. A mock-up of the TC card first, unless the owner skips it. Issue #40.

8. **The pad does nothing on a rally stage's finish card** until you click Time card with the mouse (next
   version). *Where:* `app.earthRallyResults.vue`, the 1.6.2 #14 controller support. It reports an activity popup
   so the game lets the pad's menu buttons through, uses a no-nav scope (`earthRallyResults`), and moves a "picked"
   button with the d-pad. *Likely cause (not confirmed, check in game):*
   - **The pick goes stale in a rally.** `picked` is set to `order[0]` only when `up` changes (`watch(up)`). The
     card comes up from the single-stage results (`res`) before the rally's part (`rc`) arrives. So the pick is
     "next" or "retry", which aren't buttons on the rally card (continue / restart / close).
   - Then no ring shows, and A presses `act('retry')`, which a rally ignores.
   - The d-pad's `pick()` starts from index -1, so it can land on a button. Whether it does depends on timing.
   - Second suspect: a menu or card open just before (the HUD or another scope) holding nav, so this card's scope
     doesn't take it on mount.
   *Fix idea:*
   - Re-pick whenever `order` changes, not only `up`. Reset `picked` if it isn't in `order`.
   - Check in game that the popup state is reported and the scope is active, by logging both as the card opens.
   - Files: `app.earthRallyResults.vue`, plus a check in `tests/test_hud.lua` if it covers the order. Issue #41.

9. **Transit to a service: no blue arrows** (Warden Test Rally, after SS1 Canal Road; next version). After the
   stage's finish card and Continue, the card says "transit to Service A", but the map shows no arrows.
   *Diagnosis (the log and the code; likely, not confirmed):*
   - 1862 s: "rally: transit to Service A". `rallyRun.onFinished` → `driveToStop()` sets BeamNG.Earth's GPS to
     the service at once, while the stage's run is still alive (finish card up, stop control).
   - The runner's own arrows and BeamNG.Earth's GPS both draw through `core_groundMarkers`.
   - When the run is put away, `runner.routeOff()` / `routeTo(nil)` call `core_groundMarkers.setPath(nil)`. That
     wipes the GPS's arrows too, and nothing sets the GPS again.
   - The stage transit (`armTransit`) doesn't hit this: its arrows are the runner's own, re-planned every
     `ROUTE_REFRESH_S`.
   - This is the first driven service transit of the drive. On Overmountain, Service A was reached by a Realistic
     recovery (a teleport).
   *Fix idea:*
   - Set the service GPS only once the stage's run is put away, or re-set it from `rallyRun.update` while
     `toStop` is live and `earth.gps()` has no destination.
   - Or have the runner skip clearing the markers when it doesn't own them.
   - The card's foot ("Close and follow the arrows") should be checked against what's on screen.
   - Files: `rallyRun.lua` (driveToStop timing or re-set), `runner.lua` (routeOff), `tests/test_run.lua`.
     Issue #42.

10. **Every rally menu pauses the game, the finish card included** (next version). At the stop box after a stage,
    the game should pause while the card gives you your options.
    *Now:*
    - The menu page (time card, rally pages) already pauses (`menuPause`, 1.6.2 #13).
    - It stops pausing (`menuPause.suspend`) once an action from it moves the car or loads the world: Go, Start,
      Continue.
    - The stage finish card (`app.earthRallyResults.vue`) is a HUD app over driving. It reports a non-modal
      "activity" popup so the car's controls stay live, and it closes when you drive off (`runner.lua`).
    - Nothing pauses there.
    *Fix idea:*
    - While the finish card (or the Recover? question) is up, put in a pause request, the same as `menuPause`
      with its own id, and take it back when the card closes.
    - "Or just drive off: the card closes" then goes; the card's foot and the runner's drive-off close change
      with it.
    - A pad's B or Close leaves the card.
    *Checked, the owner was right: the game does load while paused.* This drive's log:
    - 400-471 s: our menu's pause request was in (`pushPauseRequest earthRally_menu` at 400.3, popped at 471.5).
      Meanwhile the auto recce teleported to Wasp (BeamNG.Earth "Preparing terrain", "Anchor #4 ... teleport"),
      loaded terrain blocks and static collision, and matched all 12 windows.
    - 720-748 s: paused at the Start. 30 distant-view textures streamed in.
    So the loading card of #40 and the moments after Go / Start can pause too.
    *Still to check when built:*
    - Anything that waits on game time (dtSim) stalls under a pause: the runner's clocks and steps (`runner.update`),
      a car settling after a teleport, physics placing the car.
    - Check the stage build and the car placement in `runner.start`, and `rallyRun.update`'s move settle (dtReal).
      Unpause for the last step where it needs physics, and keep the card up over it.
    - Files: `app.earthRallyResults.vue`, `runner.lua` (the drive-off close and the card's timeout), `hudFrame.lua`
      (the foot line), `menuPause.lua` (a second request id or a shared helper), `tests/test_hud.lua`. Issue #43.

11. **The time card's "Back to driving" names what you go back to** (next version), for example "Back to the
    transit · SS2 Wasp" or "Back to the stage · SS1 Low Gap". *Where:* `EarthRallyFull.vue` `goLabel` (~200).
    - The `transit` and `toStop` phases (and `done`) fall to the default "Back to driving".
    - `stage` already says "Back to the stage". It would gain the stage's name.
    - The card has the data: `c.transit.name` (the next stage or the service), `c.at`.
    - Labels: transit → "Back to the transit · to SS2 Wasp"; toStop → "Back to the transit · to Service A";
      stage → "Back to SS1 Low Gap". Issue #44.

12. **The transit route enters the ATC the wrong way** (Warden Test Rally, SS2 Hillside → SS3 Canal Bank; next
    version). The blue line led into SS3's ATC from the wrong side.
    *Diagnosis (code and log; likely):*
    - Both legs of the route aim at a point and ignore the direction you should arrive in:
      - `armTransit` sets BeamNG.Earth's GPS to the ATC point (`rallyRun.lua` ~423). Its planner takes the
        shortest road there.
      - Inside `GPS_HANDOVER_M` (250 m), the runner's own arrows take over (`runner.routeTo(run.atcTarget)`,
        `core_groundMarkers.setPath` to one point). Also shortest.
    - So when the shortest way in is from beyond the ATC (along the stage road from the start side), you arrive
      backwards.
    - The log: the ATC props were put down heading 90° (2403 s). The route's way in isn't logged.
    - Also in the log: the transit to SS3 was armed twice (2263 s and 2312 s). Worth checking why; a recovery or
      the card?
    *Fix idea:*
    - Route to an approach point first: a point on the road ~150-300 m before the ATC, against the stage's
      direction (from the stage line's lead-in or the road graph). Then go on to the ATC.
    - If `core_groundMarkers.setPath` takes a list of waypoints (check in 0.40), the runner's leg can be
      [approach point, ATC].
    - BeamNG.Earth's GPS takes one destination, so aim it at the approach point, and the runner hands over from
      there.
    - With no road before the ATC (a dead end), keep today's behaviour.
    - Files: `rallyRun.lua` (armTransit's GPS target), `runner.lua` (`armApproach` / `routeTo` with an approach
      point), `tests/test_run.lua`. Issue #45.

13. **Junction closures continue through the time control zones** (next version): from the ATC to the start, and
    from the flying finish to the stop control.
    *Diagnosis:*
    - `dressing.plan` keeps only junctions with `startM <= along <= finishM` (`dressing.lua` ~790). Tape and
      direction boards stop at the start line and the flying finish.
    - Direction boards also stay off before the start on purpose (`j.along - BOARD_BEFORE >= startM`).
    *Fix idea:*
    - Widen the junction span to the ATC's `along` before the start and the stop's `along` after the finish:
      `run.atcM` / `run.stopM`, or worked out the way `runner.lua` ~240 finds start and finish on the line.
    - Junctions there get tape (the road is closed) but no direction boards: you aren't racing there.
    *To check:*
    - Does the matched line reach back to the ATC and on to the stop? The auto recce matches the organisers' line,
      which may start at the start control. Where it doesn't, the junctions there aren't known, and the line (or
      only the junction search) has to be extended along the road to the ATC and stop.
    - The cap on tape (`BUDGET.tape`) per stage.
    - Files: `dressing.lua`, `runner.lua` (the span passed in), maybe `autoRecce.lua` (the lead-in / lead-out
      matched), `tests/test_dressing.lua`. Issue #46.

14. **Pacenotes continue from the flying finish to the stop control** (next version).
    *Diagnosis:*
    - `stageWriter.stageCorners` resamples only `slice(line, startM, finishM)` (`stageWriter.lua:75`), so no
      corner is found past the finish.
    - The last call is "finish". The pacenote file (the game's rally format) is built for start → finish too.
    *Fix idea:*
    - Find corners on to the stop's `along` and call them after "finish": the co-driver reads the road to the stop.
    - Keep the stage's own numbers (length, the race distance, the time) at start → finish.
    - If the game's pacenote player drops notes past its finish marker, the notes after it are fed by our own caller
      (`coDriver` / the runner) instead.
    *To check:* as with finding 13, whether the matched line reaches the stop. Files: `stageWriter.lua`, the
    co-driver / runner caller, `tests/test_pacenotes.lua` (or whichever covers `stageCorners`). Issue #47.

15. **Close on the finish card after SS3 routes you nowhere** (Warden Test Rally; next version). The next stop was
    "a service". *Diagnosis (the saved rally and the log): not the same bug as #42.*
    - After SS3 the next stop is the **Overnight** (Warden Parc Fermé), not a service. The running order is
      Start, SS1, Service A, SS2, SS3, Overnight, SS5, SS6. SS4 is held out.
    - As built in revision 2 (#33), an overnight is *gone to* (a teleport from the time card's Go), not driven. So
      `rallyRun.onFinished` arms nothing for it (`kind == 'overnight'`; no "transit to" in the log after SS3's
      finish at 2554 s).
    - The finish card's foot then says "Time card (Ctrl+Alt+K) to go on". Close leaves you with no route and no
      prompt.
    - The same gap as finding 2 (#35): a rally phase with nothing on screen.
    *The owner's decision:* you always drive back to service at the end of a day, and the overnight happens there.
    - After the day's last stage, the next stop is the service, driven to (GPS, as finding 9 / #42).
    - Arriving at the service repairs the car and saves. Then the overnight follows at the service: full repair,
      the save, day 2's time card. No teleport to a separate parc fermé.
    - Where the event file lists the overnight with no service before it, the rally adds one (`rally.lua` builds the
      running order), with its place the overnight's place or the day's service park.
    - Needs #42 fixed (the GPS wiped when the run is put away).
    - Files: `rally.lua` (the running order: a service before each overnight), `rallyRun.lua` (`onFinished`),
      `tests/test_rally.lua`, `tests/test_run.lua`. Issue #48.

16. **A loading screen wherever the menu closes for a load** (next version). Continue on a left rally closes the
    menu for about a minute while the world loads, then the time card comes back. The owner wants a loading screen
    there and at every load like it.
    *Every place the menu closes and then loads (from the code):*
    - Full rally:
      - Start (`rallyRun.start`, `rallyRun.lua:489`: closes, then the prep and the teleport to the Start).
      - Continue (`rallyRun.resume`, :527: closes, then the teleport to the last service, then the card reopens).
      - Any teleport to a stop (`goToStop`, :398: a Realistic recovery, an overnight).
      - Go on the time card (`main.lua:1036`).
    - Single stages, from the menu (`doAction` with close, `main.lua:691`):
      - Drive (`:811`: the world at the ATC, the stage built, the car placed).
      - Route.
      - Go to start and Recce (`:839-841`: "Waiting for the world to load...").
    - Also: a stage restart (Casual), Next stage / Retry on the finish card, and the auto recce's trips to each
      stage (finding 1).
    *Fix idea:*
    - A loading view in the menu page (the time card's style): what is loading ("Going to Service A", "Loading SS2
      Wasp"), and BeamNG.Earth's progress where it reports one (its terrain / download state, as `st.auto.area`
      shows for downloads).
    - The page stays up over the load. Finding 10 shows the game loads fine while paused.
    - It closes, or turns into the next card, once the car is placed and the world is ready.
    - One helper for all the places above, rather than each closing the menu itself: `ui.loading(text)` →
      `ui.loaded()`.
    - Mock-up: `docs/mockups-1.7.0/loading.html` (with #34 and #40), awaiting OK. The owner: all the loading
      screens are built together.
    - **The owner: the loading screen doesn't close until BeamNG.Earth has loaded at least 60% of the world around
      the car.** It's the last step, with its own progress bar and a 60% mark. The same holds for #40's ATC card:
      Go waits for it. *To check when built:* what BeamNG.Earth reports for this. Its terrain blocks and tiles loaded
      around the car's anchor are likely, via the modding API or `core` internals as `earthAdapter.holding` reads
      them. If it has no count, add one in the fork (`fork-release`).
    - **The owner: a setting for the threshold.** "World loaded before driving", 40-90% in steps of 10, default
      60%. A row in `settings.lua`'s `SCHEMA` / `ORDER`, so `EarthRallySettings.vue` needs no change. The loading
      screens read it, say "at least N%", and the bar's mark moves with it. Mock-up: the Settings screen in
      `loading.html`.
    - Files: `main.lua`, `rallyRun.lua`, `runner.lua` (the stage's ready moment), `EarthRally.vue` (a loading
      view), `tests/test_run.lua`. Issue #49.

17. **A rally whose file is removed from the import folder stays in the game** (bug fix, this version). Keep its
    data (times, recces, lines, saves). Show only the rallies whose file is in `earthRally/import/`, so a pack the
    player updates or removes no longer shows.
    *Diagnosis:*
    - `importer.lua` turns each file in `/earthRally/import/` into `earthRally/events/<id>.json`, and
      `events.list` (`events.lua:46`) lists every file in `events/`. Nothing checks that the source is still there.
    - Each event records its source: `pack = { file = "Warden-Test-Rally.zip", fingerprint }` (a pack) or
      `source.file`.
    *Fix idea:*
    - `events.list` skips an event whose `pack.file` / `source.file` is no longer in the import folder. Check
      against the importer's scan (`importIndex.json`), not a disk check per event per frame.
    - Its data stays on disk, so putting the file back brings the rally back with its times.
    - An updated pack (same name, new fingerprint) already re-imports. Check that the old event isn't left beside
      the new one when the ids differ.
    - Events with no source record (made by `tools/import_kml.py` before the import folder): keep showing them, or
      the owner's own dev rallies vanish.
    - A rally under way or saved whose file is removed: hide it too, but don't delete the save.
    - Files: `events.lua`, `importer.lua`, `tests/test_import.lua`. Issue #50.

## Third drive (revision 3, 2026-11-16)

(Logged while the owner drives. Not fixed during the drive.)

1. **Mouse and controller highlights are separate.** The orange outline follows the mouse and the controller's
   selection on their own, so two options can be lit at once. They should be one highlight.
   *Diagnosis:* the tiles and cards style `&:hover, &:focus` alike (`EarthRallyHomeMenu.vue:91`, `:115`;
   `EarthRallyHome.vue:83`). Hover is the mouse, focus is the controller's nav, and nothing ties them.
   *Fix idea:* outline on `:focus` only; on `mouseenter` focus the element (and blur the old one), so the mouse
   moves the one selection. Apply it to every page's selectable tiles, cards and rows (Home, Home menu, Pick,
   Season, Settings, the time card). Files: the `earthRally/*.vue` pages, maybe a shared directive.

2. **Drive rally: no highlight on the rally cards.** On the Drive rally page the cards never show the orange outline,
   neither from the mouse, the controller nor the picked one. Clicking a card works.
   *Diagnosis:* `.er-pk-rc` draws the outline inside the card (`outline-offset: -4px`, `EarthRallyPick.vue:144`).
   The card's picture, art and shade are absolutely positioned over the whole card (`inset: 0`), so they paint on
   top of the card's own outline and hide it. Likely also why the picked card (`.on`) shows nothing.
   *Fix idea:* draw the highlight on a `::after` layer above the picture (`inset: 0; border: 4px solid orange;
   border-radius` to match, `pointer-events: none`), or set the outline outside the card (`outline-offset: 0`, with
   room in the grid's padding). Keep one look for picked vs selected (#51: one selection). File: `EarthRallyPick.vue`.

3. **The game's own footer draws over ours.** BeamNG's bottom text (the Steam login and "alpha 0.40.5") and its own
   controller-button hints show on top of Earth Rally's button hints.
   *Diagnosis (not yet checked in the game):* our hint bar is part of the page (the loading screen's `.er-load-foot`
   is `position: fixed`, `z-index: 50`, `EarthRallyLoading.vue:85`/`:89`), but the game draws its version line and
   its button-hint bar in its own layer above every page. Which screen it was is to be confirmed (loading screen,
   Home, or both).
   *Fix idea:* either give the game's layer room (keep our hints off the bottom strip it uses, or drop ours where
   the game's own hints already say the same), or hide the game's hint bar and version line while our page is up,
   if the game lets a page do that. Check how the game's own full-screen pages (Logbook, career) handle it.
   Files: `EarthRally.vue`, `EarthRallyLoading.vue`.

4. **Results: drop the "real top 10 is waiting" overlay.** Until every stage has a time, a rally's Results tab
   greys the table under "The real top 10 is waiting / Your total goes in here once every stage has a time."
   The owner: leave it out. Not being on the list already says you have no total. Instead show the "Your rally" card
   as if you had times, with the position as "--" and the reason in as few words as possible.
   *Where:* `EarthRallyResults.vue`. The overlay is line 40 (`waiting`, line 51, also greys the table at line 29).
   The left card is "Drive all N stages to get a rally result" with a bar and chips (lines 8-15) until complete,
   then "Your rally" with the place (lines 16-25).
   *Fix idea:*
   - Remove the overlay and the greying: the table shows plainly.
   - Left card, not complete: "Your rally", the big place as "--", one short line under it, e.g.
     "3 of 6 stages driven". Keep or drop the chips: to confirm with the owner (they show which are left).
   - Total and gap: "--" too, or left out until complete.
   - Mock-up first (UI change).

5. **Results from Drive rally lands you in Drive stage.** On Drive rally, Results for a rally (e.g. Rally Colorado)
   opens its results, but Back then goes through the Drive stage pages, not back to Drive rally.
   *Diagnosis:* `openResults` (`EarthRally.vue:683`) just opens the rally's own page (`openRally`, the Drive stage
   one) on its Results tab. Nothing records that it came from Drive rally, so the crumbs read
   "Home > Drive stage > (season) > Rally Colorado" and `back()` (`:714`) goes to the season or the Rallies list.
   The start screen already handles this with `startFrom = 'pick'` (`:687`, crumbs `:425`, back `:716`).
   *Fix idea:* the same for results: remember it came from Drive rally; crumbs "Home > Drive rally > Rally Colorado
   results"; Back (and B) go to Drive rally with the same rally still picked. Cleared when the rally page is opened
   any other way. Maybe show only the Results there, not the rally page's other tabs. File: `EarthRally.vue`.

6. **Start the rally: the Start button is small and lost among the settings.** On the start screen the Start button
   is small, doesn't read as the way in, and sits in the same card as the settings (Mode, Cancelled stages).
   The owner: move it away from the settings, as a big Start button at the lower right, as in any other game; and
   give the settings a "Rally settings" header.
   *Where:* `EarthRallyFull.vue`, `kind === 'start'` (lines 12-50). Two cards: left the rally, Car and Class; right
   Mode, Cancelled stages, then `.er-foot` with the notes (to recce, held out, replaces your save, another under
   way) and the Start button (`er-wide`, line 47).
   *Fix idea:*
   - A "Rally settings" header over Mode and Cancelled stages (maybe Class too: to confirm with the owner).
   - Start out of the card: a big main button fixed at the lower right of the page, like Home's Continue.
     Keep "at 08:00" on it (or under it) and its disabled state when there's no car.
   - The warnings (replaces your save, another rally under way) stay next to the button, just above it.
   - Mock-up first (UI change).

7. **Time card after Start: the Start row sits above Day 1, and the go button looks like an option.** After Start
   the rally loads fine, then opens the time card, which looks much like the start screen just left.
   - The time card lists "Start" above the "Day 1" header. You start on day 1, so Start belongs under Day 1.
     *Diagnosis:* the start is put first in the running order with no day (`rally.lua:137`), and the day header
     only goes on stage rows (`dayHead`, `EarthRallyFull.vue:244`), so Day 1 first appears at SS1, under Start.
     *Fix idea:* the Day 1 header above the Start row (give the start the first stage's day, or let `dayHead`
     put a day's header on its first row of any kind). Same check for service and overnight rows at a day's edge.
   - "Drive to SS1 ..." is a small, plain button and reads as an option. The owner: a big main button, as #56's
     Start, saying plainly "Start transit" (e.g. "Start transit · to SS1 Name").
     *Where:* `goLabel` (`EarthRallyFull.vue:207`, phase 'stop' at the start), the buttons at lines 95 and 129.
     *Fix idea:* the time card's main action as #56's big lower-right button; label "Start transit · to SS1 Name"
     at the start; out of a service maybe "Service out · start transit to SS2 Name" (to confirm). Mock-up first.
   - (The time card looking like the start screen: probably fixed by #56 and the big button here. Ask the owner if
     more is wanted.)

8. **SS1's load at the time control: paused but nothing loading, triggered before the car stopped, no warning.**
   Arriving at SS1 Canal Road's time control, the game paused for the stage load. The pause is fine, but nothing
   was loading while it sat there. The owner also wants:
   - the car to come to a complete stop at the timing tent before the load starts;
   - a prompt first that asks you to load the stage, so it doesn't take you by surprise.
   *From the log (third drive, game time):*
   - 879.6 "Stop at the time control's red board." 896.9 "near its ATC, the stage loads", the card goes up.
   - 896.9 to 921.97 the run sits in `anchor`: it asked BeamNG.Earth to move the origin to the stage centre and
     waits up to `ANCHOR_WAIT_S` (25 s, `runner.lua:44`). BeamNG.Earth did a resync at 920.2, but the run still
     gave up at 921.97: "origin never moved to the stage centre: the world may shift during the run".
     So ~25 s of a paused card with nothing visibly moving: the "nothing loading" the owner saw.
   - 921.97 to 922.18 build, place, props, check-in, toStart: the actual stage load took 0.2 s.
   *Diagnosis:*
   - The origin move likely doesn't run (or runs late) while the game is paused: BeamNG.Earth's anchor / rebase
     work may be driven by sim time or need the car to move. Before 1.7.0 this step ran unpaused. To check in
     BeamNG.Earth (`beamngEarth_core`, moveOriginTo / rebasing) before changing anything.
   - The trigger (`atBoard`, `runner.lua:1741-1784`) fires stopped within 25 m of the board, but also at any speed
     within 10 m of it (`AT_BOARD_PASS_M`), or within 60 m of the start line (`AT_BOARD_START_M`). So it can fire
     while still rolling.
   *Fix idea:*
   - Trigger only on a full stop at the board (drop the "at any speed" and start-line cases, or keep only a
     driven-past fallback that asks to turn back).
   - When stopped at the board: a prompt "Load SS1 Canal Road?" with Load (A) / not yet, before pausing.
     Mock-up first (UI).
   - The anchor step: find out why the origin move stalls under the pause; either run that step unpaused (before
     the card pauses), or skip the move when the ATC is already close to the stage (as `ANCHOR_CLOSE_M`), or cut
     the wait. And show it on the card as its own step ("Moving the world to the stage") with progress.

9. **The Recover? question is awkward: pause it, and drive it with A and the D-pad / stick.** In a Realistic
   rally's stage, the recovery key brings up "Recover?" (Recover · Super Rally / Keep going). The owner wants it to
   pause the game while it's up, ask, and take the same A button and stick / D-pad navigation as the menus.
   *Where:* the question is on the HUD's results card (`app.earthRallyResults.vue:19-27`), raised by
   `rallyRun.recoverKey` (`rallyRun.lua:729`). It is built to be answered while driving: no pause, the key again
   to recover, and it goes by itself after 10 s of driving on (`ASK_S`, `rallyRun.lua:773`; "Drive on and it goes
   after 10 s"). The card is a non-modal activity popup so the car's controls stay live; it moves its pick with
   the nav's focus_r / focus_d (`:18`) and draws the ring only with a controller.
   *Diagnosis:* because the car's controls stay live, the stick and D-pad drive the car rather than the card, and
   D-pad right is also the recovery key itself, so the pad has no clean way to pick.
   *Fix idea:*
   - Pause on the question (`menuPause.card('earthRally_recover', true)`, as the finish card), and make it modal
     while up, so A / D-pad / stick go to the card. B = Keep going.
   - Drop the 10 s time-out and "drive on and it goes" (it can't time out while paused). Keep "the key again =
     recover" for the keyboard, or not: to confirm.
   - The pick ring always shown (one selection, #51).
   - Check the Casual and transit recoveries: they are instant (no question), so unchanged.

10. **The loading screen shows the menu behind it.** When a loading screen comes up, the menu page it was opened
    from is still visible behind it. It shouldn't be: the loading screen should be all you see.
    *Diagnosis:* `EarthRallyLoading.vue` is an overlay inside the menu page (`EarthRally.vue:15`), `position:
    fixed; inset: 0` with a 92% see-through background (`rgba(10, 12, 16, 0.92)`, `:85`). The page under it (top
    bar, crumbs, cards) stays drawn and shows through. The mock-up (`docs/mockups-1.7.0/loading.html`) had it as
    its own screen.
    *Fix idea:* while a loading screen is up, don't draw the page under it (the page's content `v-if` off, or the
    loading screen in place of the page rather than over it), and make its background its own: solid, or the
    stage / rally picture darkened, as the mock-up. Check the game's own layer above (#53) at the same time.

    *Update to #8 (owner, later in the drive):* "nothing loading while paused" is taken back: the load works fine.
    #8 keeps only the full stop at the board and the prompt before loading. The 25 s anchor time-out in the log
    stays a note, not a bug: look at it only if a load is slow again.

11. **Loading screen: Continue isn't selected when it appears.** On the time control card, once the stage is ready,
    A does nothing until you move the selection onto Continue first. The footer even says "A Continue".
    *Diagnosis:* the ready button is a new element swapped in for the disabled "Loading the stage..." one
    (`v-if="L.ready"`, `EarthRallyLoading.vue:29-30`). It carries `v-bng-ui-nav-focus="1"`, but that directive
    focuses only when its page comes up with a controller in use, not for a button appearing later on a page
    already up; and with the disabled button there before, nothing on the card had the focus.
    *Fix idea:* A on the loading screen presses Continue whenever it's ready, wherever the focus is
    (`v-bng-on-ui-nav:ok` on the overlay, calling `cont()` when `L.ready`), and also focus the button when it
    appears (a watch on `L.ready`). Same check for any other button that appears late (finish card, Recover? #59).

12. **Finish card: A doesn't open the time card straight away.** After finishing a stage, A does nothing until you
    select the time card button first.
    *From the log:* 1315.83 the finish card pauses the game (`earthRally_results`); 1316.14 "results card up (res):
    popup state reported true, popup open true, nav scope active, pick continue, buttons continue close". So the
    card thinks Continue is picked and its nav scope has the pad, yet the first A didn't press it. A press itself
    isn't logged, so it's not known whether the A reached the card at all.
    *Diagnosis (to confirm):* the card takes A through `v-bng-on-ui-nav:ok="pressPicked"`
    (`app.earthRallyResults.vue:16`). Likely the game's nav sends "ok" to the element with the focus, and nothing
    on the card has the real focus until the D-pad moves it (the pick ring is the card's own, drawn by `ring()`, not
    the game's focus). Possibly also the pause (new in this build) changing which action map takes A. Same family as
    #61.
    *Fix idea:* log each A / D-pad the card gets, to see what arrives. Then give Continue the real focus as the card
    comes up (and as its buttons change), so A presses it at once; keep the card's ring and the focus as one
    (#51). Test with the game paused under it.

13. **Loading screen: the World bar doesn't move while the game is paused.** Every other step loads fine; the
    World bar stays put while paused.
    *From the log:* SS1 Canal Road's card was up 82.2 s, SS2 Hillside's 69.8 s; "Going to the start" and "Going to
    Service A" ~4 s. No "the world at N% ... let go" warnings.
    *Diagnosis (BeamNG.Earth fork, `beamngEarth/core.lua`):*
    - The bar reads `loadProgress` (`earthAdapter.worldLoaded`), and reads 0 while its `anchorId` isn't the current
      anchor's.
    - BeamNG.Earth holds back an anchor's commit / resync while the game is paused (`core.lua:2024`: "vehicles move
      only with physics running"), and a rebase's second phase only counts down with physics running (`:2927`).
    - So under our pause the new anchor round the stage waits to commit, its counts don't apply, and the bar sits.
      Same cause as the 25 s anchor wait in #58's log.
    - (The counts themselves keep coming: the pose and `updateWorld` run on real time, `:1949`, `:2963`.)
    *Fix idea, to choose:*
    - Let the anchor / rebase step run before our pause comes on: the card shows, the pause waits until the
      origin move is done (a few frames of physics with the car held), then pauses for the rest of the load.
    - Or a BeamNG.Earth fork change: an API call to let a commit through while paused for a held car (as the map
      view already does, `mapOpen`). Fork change = its own release.
    - Either way, the World bar shows "Moving the world" while the anchor is not committed rather than a stuck 0%.

14. **After the ATC load, the time control should already be done.** Once you press Continue on the time control
    card, you should only have to drive to the start line.
    *From the log:* it already checks in behind the card. SS2 Hillside: 1187.06 "run: toAtc", "Hillside: Drive to
    the time control and stop at its red board."; 1187.09 "Checked in 08:24:08: Your start time: 08:25:00. Move up
    to the start line."; 1187.15 "run: toStart". Continue was pressed 44 s later (1231.84). Same on SS1.
    *Diagnosis:* the check-in happens, but the player isn't shown it:
    - the runner still passes through `toAtc` for a frame and says "Drive to the time control and stop at its red
      board." first (`runner.lua`, the toAtc message), so that message is queued with the check-in's;
    - the card says "Start time: given at the red board" and "Then: move up to the start line"
      (`EarthRallyLoading.vue:17-18`), never the time you got;
    - (to check) whether the start time given at check-in has gone by during a long pause (the rally clock vs the
      44 s wait), which would make the start feel like it wasn't set up.
    *Fix idea:*
    - In a rally's ATC load, skip `toAtc`'s message (straight to the check-in), so only "Move up to the start line"
      shows after Continue.
    - The card shows the check-in: "Checked in 08:24:08", "Start time 08:25:00" once done.
    - Give the start time from when Continue is pressed (or hold the clock while the card is up), so it's never
      due before you can drive.
    - Ask the owner what they saw after Continue (the old message, the ATC HUD, the clock).

15. **No pacenotes after a long paused load: only the start calls.** When the time control card was left up for a
    while, the co-driver gave only the start (intercom check, belts, countdown) and then no notes on the stage.
    *From the log and the runtime files:*
    - The notebooks were written and loaded: canal-road 9 notes, hillside 7, canal-bank 5 (`earthRally/runtime/
      warden-test-rally-v2__*/rally/notebooks/structured.notebook.json`; the same counts as the V1 rally earlier
      today, so the writer's output didn't change with #47).
    - After each "go", no other "playing ... pacenote" line. Only system calls are logged, so it isn't certain the
      game logs ordinary notes at all: to check against a drive where notes were heard.
    - The origin never moved to the stage centre on any of the three (#58 / #63: the anchor move waits while
      paused). On SS3 Canal Bank the world then shifted during the load: 1511.5 "the world shifted during the run
      (resync, event): the co-driver keeps its old positions", Anchor #15 at 46.97987, -119.03466.
    - SS1's start time also ran out under the card: 993.9 "We've been given a new start minute." (#64).
    *Diagnosis (to confirm):* the notes' trigger points are in the world frame of the moment the stage was built.
      A resync / rebase that lands after the build (held back by the pause, #63) moves the world under them, so the
      car never meets them. Or the note checks run on sim time and something about the long pause leaves them
      off (the run's `notesOn` at the start: check it was turned on).
    *Fix idea:* first a log line per note called (ours, from the runner) and one when notes go on, to tell the two
    apart. Then: fix #63 so the origin move is done before the stage is built; and on a world shift during a run,
    rebuild the co-driver's positions in the new frame instead of keeping the old ones.

16. **Leaving the stop control, the finish tent vanishes at once.** When you leave the stage's stop control to
    start the transit, the finish / stop control props (tent, boards) disappear straight away. They should stay
    until you're out of loading distance, like any other site.
    *Diagnosis:* ending the run tidies it (`runner.lua` `tidy`, ~:1968), which calls `props.clear()` and removes
    every site, the finish and stop included. Sites otherwise come and go by distance (`props.SPAWN_M` = 350 m,
    `props.lua:31`), but cleared sites are gone, not left to the distance rule.
    *Fix idea:* at the end of a rally stage, keep the finish and stop sites (and their tape) as sites left behind:
    don't clear them in `tidy`; drop each once the car is beyond `SPAWN_M` (or a little more) from it, or at the
    next stage's setup. Same for the start / ATC sites if the car is still near them (a restart). Check the props
    don't stay forever if the car is teleported away (a move to a stop: dropped on the move).

17. **Controls entered at speed: service taken at ~100 mph.** You should have to stop to enter any time control,
    service included. The owner drove into service at about 100 mph and it counted.
    *Diagnosis:* a service (and any stop driven to: overnight, parc fermé, regroup) is done within `ARRIVE_M`
    (150 m) of its place at any speed, or within `ARRIVE_NEAR_M` (500 m) when stopped (`rallyRun.lua:45-48`,
    the check at `:841`). Only the second needs a stop. The stage ATC has the same kind of rolling fallbacks
    (#58: `AT_BOARD_PASS_M`, `AT_BOARD_START_M`).
    *Fix idea:*
    - Every control (ATC, service in / out, overnight, regroup) is entered only when stopped
      (`speed < STOPPED_MS`) within its distance; no "at any speed" case.
    - A board or a marker to stop at for the stops too (a service's point is the venue, not always on a road: keep
      the 500 m radius for the stopped case, maybe with the HUD's "Stop to check in" once within it).
    - Driving through without stopping: nothing happens (the GPS keeps pointing there), with a "Stop to check in"
      line on the HUD.

18. **No tent at service.** A service park has nothing there; it should have a tent.
    *Diagnosis:* only stage controls get props: start, flying finish, ATC, stop (`runner.lua:874-889`, kinds in
    `props.lua:92-95`). Service, overnight and regroup stops have no site at all; they are a GPS point and a radius
    (`rallyRun.lua`, `ARRIVE_M`).
    *Fix idea:* a 'service' site kind: a time control board and a tent (as the ATC's), put at the service's place
    on the nearest road (`props.roadAt`, as the transit recovery finds a road), facing along it. Put out when the
    service is armed, dropped when the car leaves it (by distance, as #66). It gives #67 a place to stop at
    ("stop at the service board"). To confirm with the owner: just a tent, or service-in / service-out boards too,
    and whether overnight / regroup get the same.

19. **Transit: the car can be reset in a Realistic rally.** On a transit in a Realistic rally the owner could reset
    the car.
    *Diagnosis:* as planned, not a slip: `docs/plan-1.7.0.md:80` "Recovery on a transit puts the car on the nearest
    road, free", for both modes. `rallyRun.recoverKey` (`rallyRun.lua:729`): off a live run it calls
    `runner.recoverToRoad()` (and in Casual also repairs). The game's own reset is blocked during a rally.
    *To ask the owner:* which reset it was (Backspace / D-pad right = ours; the game's own R / Insert = a leak in the
    block), and what Realistic should do on a transit:
    - no recovery at all on a transit (stuck = Leave, or call for help with a time penalty);
    - or a recovery with a cost (a time penalty on the time card, e.g. +5 min, or counted as lateness at the next
      control);
    - repairs: Realistic already doesn't repair on a transit (`notes` line 35).
    *Fix idea:* once decided, `recoverKey`'s transit branch by mode. Log which key did it.
    *Owner:* it was D-pad right, the rally's own recovery (no leak in the game's reset block). Still to decide: what
    Realistic does on a transit.

20. **Transit SS5 Canal Bank to SS6 Canal Road routes the long way round.** Instead of crossing the bridge and
    turning left then right straight into the time control, the GPS sends the car straight on past the turn to the
    time control, round to the crossroad, and in from there: much more transit time. Turning right there also
    gives the right way into the time control. The owner asks whether it's the routing trying to get the right
    direction. (Log: "transit to SS6 Canal Road" at 2037.6 and again at 2052.5.)
    *Diagnosis:* yes, almost certainly the direction point (#40 / revision 3). `rallyRun.approachVia`
    (`rallyRun.lua:469`) adds a GPS waypoint `APPROACH_VIA_M` (150 m) behind the ATC, on a straight line drawn
    back from the start through the ATC. It ignores the roads: where the road into the ATC bends (the turn off
    the bridge road), the point 150 m back lands on another road (here, likely the crossroad), and the GPS routes
    through it. The car must reach within 40 m of it before the GPS lets it go.
    *Fix idea:*
    - Put the direction point on the road: walk back from the ATC along the road map (BeamNG.Earth's navgraph /
      `props.roadAt` steps) rather than a straight line, and only 30-60 m, so it's on the approach road itself.
    - Or skip it when the plain route already arrives the right way (route to the ATC, check the last leg's
      heading against the stage's; add the via only if it's the wrong way).
    - Test on this transit (SS5 to SS6, Warden V2) and on SS3's (armed twice earlier).

21. **The rally's end: drive back to service, then two big buttons.** After the last stage the rally is over at
    once. The owner:
    - you should still have to drive back to service after the last stage (the rally finishes there);
    - "Close the rally" is too small; replace it with two big buttons:
      - **New rally**: back to the Earth Rally Home menu;
      - **Continue driving**: closes the menus and puts you back in plain BeamNG.Earth free roam (its own HUD
        and layout, not the stage's).
    *Where:*
    - The running order ends with the last stage when the event has no service after it (`rally.lua` orderOf);
      the rally is `done` once that stage's result is in.
    - The finished card (`EarthRallyFull.vue:77-82`, "RALLY FINISHED" with total and place); its only button is
      "Close the rally" (`:142`, outlined, small), which calls `quit` and opens the rally's page (`leave`, `:199`).
    *Fix idea:*
    - `orderOf`: after the last stage, always end at a final service / finish (the day's last service park, or the
      rally start's place, as #48's overnight); driven to with a stop (#67), the tent (#68). Done there.
    - The finished card: the result, then the two main buttons, big, as #56 / #57.
    - Continue driving: `quit` (save kept as finished), close the menu, the stage layout off, BeamNG.Earth's HUD back
      (`layoutOff`, as `tidy`).
    - New rally: the same, then open Home.
    - Mock-up first (with #56 / #57's buttons).

### Owner's decisions on the third drive (2026-11-16, after the rev 4 mock-ups)

The mock-ups (`docs/mockups-1.7.0/rev4.html`) are OK'd, with these answers:
1. #56: Class stays with Car (left card). Rally settings = Mode and Cancelled stages.
2. #57: the button reads "Start transit · to SS4 Name" from a service too (no "Service out").
3. #59: no "press the key again to recover": only A on the card.
4. #68: one board and a tent at the service point for now (a full service park is later work). Overnight and
   regroup: the same single board / tent.
5. #54: keep the stage chips. Once a stage is driven, its chip shows your time on it (e.g. "SS3 6:12.4"). Total
   "--" until complete.
6. #71: the finished card opens with **New rally** selected (not Continue driving).
7. #69: Realistic has no free recovery on a transit. The recovery key on a transit gives the same Recover? card
   as on a stage: recover = back to the next service under Super Rally. Casual unchanged.
8. #63: do the origin move with the car held still before the pause comes on (no fork change). The owner expects
   this to also fix #65 (no pacenotes after a paused load).

### Owner's recovery rules (2026-11-16, after the rev 4 review)

- Realistic, recover on a transit to a service: taken to that service; nothing is missed, no penalty.
- A rally with no service anywhere:
  - recover on a stage: that stage under Super Rally, taken to the start of the next stage;
  - recover on a transit: taken to the next stage's start, nothing missed;
  - recover on the last stage: the rally ends.
- No transit after the last stage when the rally has no service: it ends at the last stage.

## Revision 4 (issues #51-#71, built 2026-11-16)

Built on `full-rally-mvp`; not yet driven. Changes from the plan and the mock-ups:
- #58: the "Load the stage?" prompt pauses the game too (so A reaches it, as Recover?).
- #58: besides 25 m from the board, a stop within 60 m of the start line, or of an off-road ATC point, also counts.
- #63: the diagnosis changed in review. The drive log shows our pause did not stop sim time, and BeamNG.Earth
  replaced our origin move with a resync at its old anchor; on SS3 its request landed 22 s after we gave up, mid
  stage. Now: wait for BeamNG.Earth's own request to finish (up to 90 s), whatever anchor it lands on. New log lines:
  the origin move's ask / pending / commit, game time passing under each Earth Rally pause, each pacenote called and
  notes on/off. Read these after the next drive.
- #64: the card has no Due row: the rally keeps no due time to show.
- #71: no final service when the rally has no service (the owner's rule).
- Recovery rules: see "Owner's recovery rules" above.
- Not done: rebuilding the co-driver's positions after a mid-run world shift (#65); the next drive's log decides.
