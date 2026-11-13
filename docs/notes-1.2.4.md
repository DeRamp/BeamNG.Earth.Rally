# Earth Rally 1.2.4: notes from testing 1.2.3

Items the user reported while testing 1.2.3. Those marked *Built* are in 1.2.4; the rest are still open and will go
into 1.2.5. Nothing is built until the user says so, and UI items get a mock-up before any code.

Built into 1.2.4: 1, 2, 4, 5, and BeamNG.Earth's place name and banner centred under the top row (x 184..884,
against the row's own 0..1068) rather than left-aligned.
Built into 1.2.5: 6, 7, 8, 9, 12. Built into 1.2.5: 2, 3 (by 6), 6, 7, 8, 9, 10, 11, 12. Nothing from this file is open.

1. *Built.* **The rally block belongs in the top left corner.** The card shown before a stage (the rally clock, the stage, the
   ATC and its distance: `.er-next` in app.earthRallyHud.vue) is centred at `top: 82px`. It should sit in the top
   left corner, hard against the edge, as the stage clock and progress meter now do.
   - Mocked up and agreed in principle: docs/mockups-1.2.3/hud.html, the "Before the stage" moment.

2. *Built, and corrected.* **BeamNG.Earth's banner lands across the rally information.** The place-name strip was switched off for the stage at first, which threw away where-you-are to keep a warning you only see when something is wrong (the user). Both are kept and stacked down the left instead: the rally block at 0,0, the place name at 0,128, the banner at 0,196. `setStatusBar` went with it, so nothing of BeamNG.Earth's internals is touched any more -- only placement in our layout. Its warning line ("Server OK - some internet data
   sources not answering: basemap.nationalmap.gov unreachable") is centred at `top: 36px`, over the rally apps.
   Not to be hidden: it says the stage may be running on incomplete map data, which is worth knowing mid-rally.
   Move it directly under the rally block in the top left (`beamngEarthBanner` in earthRallyStage.uilayout.json).
   - In the same mock-up, with a toggle for it.

3. *Fixed in 1.2.5, by item 6.* **The yellow warning boards before the ATC stand off to the right of the road**
   (Maryhill Up). *The first attempt did not work.* The first guess was that the organisers' pin sits further from the road
   than `props.SNAP_M` (30 m), so `roadAt` found nothing and the boards were set out along a straight line from the
   pin. A second, wider look (`SNAP_FAR_M`, 60 m) was added -- and the log says exactly the same thing afterwards:
   `props: atc put down (8 objects, 0 placed by the road map, no road on the map there: straight from the control)`.
   So the road map is genuinely **empty** at the ATC when the props go down, not merely far away.
   Why: the props are put down as soon as the car is within `props.SPAWN_M` of the site, and the run starts with the
   car already beside the ATC, seconds after the level loaded -- BeamNG.Earth has not streamed the roads there yet.
   It was the first, and item 6's fix did it without touching props.lua at all. Confirmed in game (2026-11-13),
   one session, before and after:

       42.5  atc put down (8 objects, 0 placed by the road map, no road on the map there: straight from the control)
      170.9  atc put down (8 objects, 8 placed by the road map, road map 0.8 m from the control, heading 351 deg)

   The road is **0.8 m** from the organisers' pin -- it was never far away, BeamNG.Earth simply had not streamed it
   yet. Starting the run with the car 40 m before the control instead of on top of it gives those seconds back.
   The user, 2026-11-13: "Those yellow boards are right where they need to be."
   Note the first run after a cold start still gets the old behaviour (nothing has streamed yet at all); every run
   after it in the same session is placed by the road map. `SNAP_FAR_M` (60 m) is kept -- a genuinely far pin is
   still worth catching -- but it was aimed at the wrong cause.

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

6. *Built (1.2.5).* **A run started while parked at the ATC checks in at once.** The playtest start (and any player who stops at the
   ATC and picks Drive stage) is checked in the instant the run reaches `toAtc`: in game, 0.03 s after it
   (`run: toAtc` 30.07 s, `Checked in` 30.10 s). `runner.start` only teleports when the car is more than
   `TRAVEL_IF_FARTHER_M` (300 m) from the ATC, and `stepPlace` treats anything within `NO_SET_DOWN_M` (150 m) as
   "driven there" and leaves the car where it stands -- inside the control's 12 m radius, stopped, which is the
   check-in. The whole drive up to the control is skipped.
   - Still to confirm: whether the car was left untouched or set down 40 m back and something closed that distance.
     The run's own `atcSetDown` check tells them apart; one finished run settles it.
   - Two parts: the playtest request could stand the car well back before starting (its own file), and `stepPlace`
     could stop counting "inside the control zone" as "driven there" (`runner.lua`, which players would feel too).

7. *Built (1.2.5).* **The skip-the-wait prompt (right bumper + Y) is cut in half.** Not our geometry: our rally app placements are now
   the same as the game's own `rallyModeStage.uilayout.json`, byte for byte. The cause is inside the stock app,
   `ui/modules/apps/rallyLoop/app.rallyCountdown.vue`: `.rally-countdown-app` is `height: 100%; overflow: hidden`,
   and `.section-interact-hint` hangs below the countdown panel with `margin-top: 1rem` and a `--font-xl` label, so
   panel + gap + hint is taller than the 220 px slot and the bottom of the hint is clipped.
   The height of that slot is ours: `rallyCountdown` in earthRallyStage.uilayout.json. Giving it more (300 px or so)
   should let the hint show in full. The app lays its content out from the top, so the extra should fall below.

8. *Built (1.2.5).* **The stage display should come on at the countdown, not at GO.** Today `hudFrame.build` sends
   `showStageApps = true` (and `uiColors.theme`, without which the stock apps hide themselves) only in `running` and
   `toStop`, so the stage clock and progress meter appear the moment the car is released. They should be up while
   the countdown runs, reading 0:00 and 0 %.
   - `hudFrame.lua`, the `waitStart` branch: `showStageApps`, `uiColors` and a `stageData` with
     `currentSSTime = 0`, `isActive = false` and a zero `completion`. The HUD tests assert what each state sends, so
     they move with it.
   - To decide: whether our own km readout comes on then too, or stays until GO.

9. *Built (1.2.5).* **Our HUD is drawn over the pause menu.** Pressing Escape leaves the rally block (and whatever else the HUD has
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

10. **BeamNG.Earth's own strips off for the stage, all three of them** (the user, 2026-11-13, reversing item 2:
    "let's just go ahead and get rid of the Earth UI... I don't want to see that top debug thing that shows you the
    road you're on and the connection issues. And I also don't want to see where the imagery is coming from").
    - `beamngEarthStatus` (the place name), `beamngEarthBanner` (the data-source warnings) and
      `beamngEarthCredits` (the imagery attribution, bottom left).
    - The minimap stays: that is the game's own `navigation` app, not BeamNG.Earth's. Move it down a little
      (`bottom: 90px` now; nothing sits under it, so ~20px is free).

    **Do not do this by taking the apps out of the layout.** BeamNG.Earth draws each of them with ImGui whenever its
    app is not mounted (core.lua: `if not hudapps.mounted('status') then statusbar.draw(...)`), so dropping them
    moves the same text to a worse place instead of removing it. They stay in the layout, mounted, and are blanked
    through BeamNG.Earth's own flags: `statusbar.enabled`, `banner.enabled`, `credits.setEnabled(on)`
    (statusbar.lua:14, banner.lua:40, credits.lua:70).
    - Not `beamngEarth_settings.set(...)`: that saves the player's settings file, so a run that ended badly would
      change their own preference for good.
    - This brings back `earthAdapter.setStatusBar`, deleted in 1.2.4 when item 2 went the other way, widened to all
      three (`setEarthHud(on)`), called from the runner's layoutOn / layoutOff and again when the mod loads, so a
      run cut short cannot leave them off.
    - Their layout entries (x 184..884, top 128 / 196) stop mattering during a stage, but are left as they are for
      when the strips are on outside one.

11. **The road you are on, and how much of the world has downloaded, in our own flag** (the user, 2026-11-13,
    refining item 10: keep the information, drop BeamNG.Earth's chrome). A small flag to the right of the stage
    time and under the progress bar -- about `left: 288px, top: 114px`, where the timing block ends and the bar's
    slot finishes.
    - **Decided:** a percentage, shown as `30%`, not BeamNG.Earth's `12/40` fraction. The flag **stays** once the
      world is loaded, showing **just the road** then.
    - The road is public API: `beamngEarth_api.place()` returns `{ street, place, region, country }` and `place` is
      in its FEATURES, so `has('place')` version-checks it. `street` is the road.
    - The download figure is **not** in the API. `statusbar.loadingLine(status)` (statusbar.lua:51) parses
      `loading: done/total` out of core's status text, which lives in `core._state().status` (core.lua:244). So it
      needs an internal reach of the kind earthAdapter already makes for the rebase distance, behind a feature
      check, and the percentage is `done / total` worked out by us. It will go quiet if BeamNG.Earth changes that
      wording -- worth asking TecnaGamer for an API at the same time, as the `onBeamNGEarthRebased` PR was.
    - **The data credits stay visible** (the user, 2026-11-13, after the docs were checked). BeamNG.Earth has them
      on by default because CC BY and similar licences ask for visible attribution (credits.lua's header,
      docs/DEVTOOLS.md), and `creditsVisible` is already the player's own setting -- a mod turning it off for them
      is not the same as the player choosing to. So item 10 covers the place-name strip and the banner only.
      It follows that the minimap (the game's `navigation` app) goes to `bottom: 70px`, not 20: the credits hold
      `bottom 0, 560x64`.
    - The flag sits in the corner the stage time and the progress bar make: `left: 288px` (where the timing block
      ends), `top: 68px` (where the bar's art ends), 34 px tall, small text, never reaching the pacenote cards at 189.
    - Mock-up: docs/mockups-1.2.5/hud.html.

12. *Built (1.2.5).* **The start clock's picture-in-picture is in the way of pop-ups.** It sits near the top right corner
    (`runner.M.CLOCK_VIEW_TOP = 0.03`, 3 % of the screen height down, with `placeClockView` putting it there every
    frame), which is where the game's own messages and toasts appear. The user wants it down the right-hand side,
    about halfway down the screen.
    - One place: `placeClockView`'s `y`. Today `math.floor(H * M.CLOCK_VIEW_TOP + 0.5)`; centred it is
      `H * 0.5 - h / 2`, so a `M.CLOCK_VIEW_CENTRE_Y = 0.5` reads better than a "top" gap and stays tunable.
    - The `clockView` setting keeps its three values: `right` (ours, now halfway down), `top` (the game's own
      place, untouched), `off`.
    - 1.1.0 put it above the speedometers and the boost gauge covered it; halfway down the right edge clears both
      that and the pop-ups at the top.

## What the 1.2.5 review turned up (2026-11-13)

The build was read by a bug hunter and a contrarian before it went to the user. Both earned their keep.

**Items 10 and 11 are blocked, and the flag was taken back out of the build.** Switching BeamNG.Earth's status
strip off does not only stop it drawing -- `statusbar.lua:77`:

    function M.request(now, player, online)
      if not M.enabled or not player or not player.lat then return nil end

`M.enabled` gates the `where` request that fills `loc`, and `core.lua:2694` is its only caller. `api.place()` is
`statusbar.location()`, i.e. that same `loc`. So hiding the strip freezes the very road name the flag exists to
show: stale for the whole stage, and empty after a teleported start, because `core.lua` calls `statusbar.reset()`
on a teleport. The headline field of the feature is switched off by the feature.
Knock-on: `core.lua:2251` feeds the minimap's label from the same place, so hiding the strip blanks that too.

Also found before shipping, and the reason to stop and rethink rather than patch:

- `banner.line()` never returns empty -- `banner.lua:167`: `if cur.text ~= '' then return cur.text end; return
  'BeamNG.Earth server connected'`. Our `earthWarning()` promised "nil when all is well", so every stage would have
  carried a permanent amber warning. `banner.current()` is the right surface (core uses it at core.lua:2171).
- The download figure is not world progress. `server/earthd.py` emits `Far field loading: {batch}/{left + batch}`,
  a queue depth -- it goes *backwards* as more tiles are queued. Rendering it as `30%` with a filling bar is less
  truthful than BeamNG.Earth's own `150/433`, not more. And it is scraped from a Python f-string crossing a socket:
  not comparable to the rebase internals, which are Lua functions with stable signatures.
- `setEarthHud` returned a single boolean for two modules, so a half-applied change (one module missing) reported
  failure, and `layoutOff` then never restored the one it *had* turned off: the player's strip stays blank for the
  session.
- It forced the strips **on** at the end rather than back to what they were, and `onExtensionLoaded` did the same on
  every Lua reload -- overriding a player who had turned them off in BeamNG.Earth's own settings.

Where that leaves it: **ask TecnaGamer for an API first** (`api.loading()`, and a read of the place that does not
depend on the strip being visible), as was done for `onBeamNGEarthRebased` in 1.7, and keep BeamNG.Earth's strips
as they are until there is one. The place-name strip alone might still be worth hiding -- it is the clutter the
user objected to -- but only once the road name survives it.

**Caught and fixed in the build:**

- The stage clock coming up at the countdown stacked the stock 288-wide clock on our timecard, both at 0, 0 -- the
  exact fault reported as items 1 and 4. The stage apps now come up as the timecard goes (`TIMECARD_UNTIL_S`), which
  also reads better: they appear as the countdown gets serious, not a minute early.
- `DRIVEN_THERE_MIN_M` was 25, borrowed from `STOP_CONTROL_RADIUS_M`, a constant for a different control. It is 15
  now, derived from `CONTROL_RADIUS_M` (12) and a little over. The band between it and `NO_SET_DOWN_M` is where a
  player who drove up and parked keeps the spot they chose; every metre added to it moves someone who did not ask
  to be moved.
- The menu check copied two of BeamNG.Earth's three terms. Our own full-screen page (`earthRally`) and its world
  map (`beamngEarthMap`) are in now.
- The minimap move is reverted. It only existed to make room for strips that are now staying, and 70px left 6px of
  clearance over the credits instead of 26.

**Noted, not acted on:**

- A better fix for item 6 than moving the car at all: arm the check-in on *entering* the control zone, so a car
  that starts inside must leave and come back. No teleport, no constant. Worth doing if 15 m still bites.
- The 220→300 countdown slot is a workaround for a stock-game bug (`.rally-countdown-app { overflow: hidden }`
  clipping `.section-interact-hint`). Keep it, but report it upstream: it is broken for everyone, not just us.
- Our fix hides our HUD on a menu and leaves the stock rally apps drawn over it. Half the complaint.
- The stock apps' behaviour on `isActive = false` during the countdown is unverified -- one in-game look.

## Carried over, still open

- The blank start board after a new start minute (roadmap 7): never built.
- The 1.2.1 release notes still name the on-stage display as a known issue. It was the dev install script, not the
  release zip: to correct.
