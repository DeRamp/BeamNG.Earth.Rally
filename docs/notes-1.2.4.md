# Earth Rally 1.2.4: notes from testing 1.2.3

Items the user reported while testing 1.2.3. Those marked *Built* are in 1.2.4; the rest are still open and will go
into 1.2.5. Nothing is built until the user says so, and UI items get a mock-up before any code.

Built into 1.2.4: 1, 2, 4, 5, and BeamNG.Earth's place name and banner centred under the top row (x 184..884,
against the row's own 0..1068) rather than left-aligned.
Still open: 3, 6, 7, 8, 9.

1. *Built.* **The rally block belongs in the top left corner.** The card shown before a stage (the rally clock, the stage, the
   ATC and its distance: `.er-next` in app.earthRallyHud.vue) is centred at `top: 82px`. It should sit in the top
   left corner, hard against the edge, as the stage clock and progress meter now do.
   - Mocked up and agreed in principle: docs/mockups-1.2.3/hud.html, the "Before the stage" moment.

2. *Built, and corrected.* **BeamNG.Earth's banner lands across the rally information.** The place-name strip was switched off for the stage at first, which threw away where-you-are to keep a warning you only see when something is wrong (the user). Both are kept and stacked down the left instead: the rally block at 0,0, the place name at 0,128, the banner at 0,196. `setStatusBar` went with it, so nothing of BeamNG.Earth's internals is touched any more -- only placement in our layout. Its warning line ("Server OK - some internet data
   sources not answering: basemap.nationalmap.gov unreachable") is centred at `top: 36px`, over the rally apps.
   Not to be hidden: it says the stage may be running on incomplete map data, which is worth knowing mid-rally.
   Move it directly under the rally block in the top left (`beamngEarthBanner` in earthRallyStage.uilayout.json).
   - In the same mock-up, with a toggle for it.

3. **The yellow warning boards before the ATC stand off to the right of the road, not either side of it**
   (Maryhill Up). *Tried and did not work.* The first guess was that the organisers' pin sits further from the road
   than `props.SNAP_M` (30 m), so `roadAt` found nothing and the boards were set out along a straight line from the
   pin. A second, wider look (`SNAP_FAR_M`, 60 m) was added -- and the log says exactly the same thing afterwards:
   `props: atc put down (8 objects, 0 placed by the road map, no road on the map there: straight from the control)`.
   So the road map is genuinely **empty** at the ATC when the props go down, not merely far away.
   Why: the props are put down as soon as the car is within `props.SPAWN_M` of the site, and the run starts with the
   car already beside the ATC, seconds after the level loaded -- BeamNG.Earth has not streamed the roads there yet.
   Two ways out, and they may be the same fix as item 6: start the run further from the ATC so the roads arrive
   first, or let a site put its props down again once a road appears (today `s.objs` is set once and never revisited).

4. *Built.* **The "checked in / your start time" card is in the way of the skip-the-wait prompt** (right bumper + Y on a pad).
   `.er-timecard` is centred at `top: 318px`; the game's own prompt for Interact lands under or behind it. Either
   move the card or leave that strip of screen free while the prompt is up.

5. *Built: removed.* **The grey behind the results card does not reach the edge of the screen.** At the stop control the card comes up
   over `.er-dim-all` (`position: absolute; inset: 0; background: rgba(8, 10, 14, 0.55)` in app.earthRallyHud.vue),
   which is meant to dim the whole screen but stops short of the edges, so it reads as a panel rather than as the
   game dimming. The app itself is the full screen (earthRallyStage.uilayout.json: top 0, left 0, 100% x 100%; its
   app.json the same), so the inset is coming from the game's own app host around it, not from our CSS.
   The user's call: **keep the results card, drop the grey behind it.** Two lines, the same shape as the pacenote
   grey-out removed in 1.2.3 -- an overlay of ours sized to something other than what it covers.

6. **A run started while parked at the ATC checks in at once.** The playtest start (and any player who stops at the
   ATC and picks Drive stage) is checked in the instant the run reaches `toAtc`: in game, 0.03 s after it
   (`run: toAtc` 30.07 s, `Checked in` 30.10 s). `runner.start` only teleports when the car is more than
   `TRAVEL_IF_FARTHER_M` (300 m) from the ATC, and `stepPlace` treats anything within `NO_SET_DOWN_M` (150 m) as
   "driven there" and leaves the car where it stands -- inside the control's 12 m radius, stopped, which is the
   check-in. The whole drive up to the control is skipped.
   - Still to confirm: whether the car was left untouched or set down 40 m back and something closed that distance.
     The run's own `atcSetDown` check tells them apart; one finished run settles it.
   - Two parts: the playtest request could stand the car well back before starting (its own file), and `stepPlace`
     could stop counting "inside the control zone" as "driven there" (`runner.lua`, which players would feel too).

7. **The skip-the-wait prompt (right bumper + Y) is cut in half.** Not our geometry: our rally app placements are now
   the same as the game's own `rallyModeStage.uilayout.json`, byte for byte. The cause is inside the stock app,
   `ui/modules/apps/rallyLoop/app.rallyCountdown.vue`: `.rally-countdown-app` is `height: 100%; overflow: hidden`,
   and `.section-interact-hint` hangs below the countdown panel with `margin-top: 1rem` and a `--font-xl` label, so
   panel + gap + hint is taller than the 220 px slot and the bottom of the hint is clipped.
   The height of that slot is ours: `rallyCountdown` in earthRallyStage.uilayout.json. Giving it more (300 px or so)
   should let the hint show in full. The app lays its content out from the top, so the extra should fall below.

8. **The stage display should come on at the countdown, not at GO.** Today `hudFrame.build` sends
   `showStageApps = true` (and `uiColors.theme`, without which the stock apps hide themselves) only in `running` and
   `toStop`, so the stage clock and progress meter appear the moment the car is released. They should be up while
   the countdown runs, reading 0:00 and 0 %.
   - `hudFrame.lua`, the `waitStart` branch: `showStageApps`, `uiColors` and a `stageData` with
     `currentSSTime = 0`, `isActive = false` and a zero `completion`. The HUD tests assert what each state sends, so
     they move with it.
   - To decide: whether our own km readout comes on then too, or stays until GO.

9. **Our HUD is drawn over the pause menu.** Pressing Escape leaves the rally block (and whatever else the HUD has
   up) on screen over the menu, which makes it awkward to pick things. Not BeamNG.Earth's doing: its own apps hide
   themselves on a menu (`credits.lua:87`, `uiHidden = toState:sub(1, 4) == 'menu' or toState == 'loading' ...`,
   which both its directives honour). Ours has no such check at all -- `app.earthRallyHud.vue` never looks at the UI
   state, and `onUpdate` keeps running while the game is paused, so `hudFrame` keeps feeding it.
   It only became obvious in 1.2.4: the cards used to be centred at `top: 82px` / `top: 318px`, off to the side of
   the menu, and are now at `0, 0` where the menu draws.
   - The fix that matches BeamNG.Earth: an `onUiChangedState` on our side, and `hudFrame` sending an empty `show`
     while a menu is up, so every piece of the HUD goes at once rather than card by card (main.lua, hudFrame.lua, and
     the HUD tests).
   - To decide: whether it hides on any menu at all, or stays up for the pause menu's own Earth Rally tab.

## Carried over, still open

- The blank start board after a new start minute (roadmap 7): never built.
- The 1.2.1 release notes still name the on-stage display as a known issue. It was the dev install script, not the
  release zip: to correct.
