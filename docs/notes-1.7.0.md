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
   - Open a time control card first: "SS1 Low Gap · time control", your time in, Go to the start.
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
