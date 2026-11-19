# 1.7.4 notes: play from the main menu

Branch `feature/main-menu`, build `1.7.3-alpha+mainmenu` (c8c1088). An Earth Rally tile on Play > Rally; BeamNG.Earth
loads when a stage is driven or a rally started; the rally's car picked in the game's vehicle picker
(`docs/mockups-1.7.3+mainmenu/car.html`). Driven by the owner 2026-11-18, started from the main menu.

## Findings (logged, not fixed)

### 1. Drive from the main menu hung on "Loading BeamNG.Earth" until Escape

The owner: "it got stuck on loading into a rally. I pressed escape and it finished loading in ... I waited for a
while."

From `beamng.log` (Drive stage, OTR 2024 Final, SS4 Maryhill Up):

- 54.4 s: the level load starts. `startFreeroamByName` runs the whole load inside our call, so our own log line
  "from the menu: loading BeamNG.Earth" only appears at 58.0 s, after the level is already loaded.
- 58.0 s: `loadWorldThen` puts our page up at once (`showLoading`: `M.openMenu()`), under the game's own loading
  screen, which is still up.
- 60.2 s: the game hides its loading screen. Our page is already the UI state, so `menuOpen` stays true.
- 144.0 s: "Loading BeamNG.Earth done after 83.7 s". This came only after the owner's Escape.

**Diagnosis.** `updateWorldWait` counts the 2 s settle only once `w.shown` is set. It sets `w.shown` only on reopening
the page, which needs `not menuOpen and lastUi == 'play'`. Our page was never closed, so neither condition was ever
true and the wait stalled with the world up. Escape went to `pause` and back to `play`, which closed and reopened
the page, set `w.shown`, and the stage ran 2 s later.

**Fix (for the owner's go):** in `updateWorldWait`, once `inWorld`, also set `w.shown` when the page is already up
and the game's loading screen has gone. Two candidate checks:

- `core_gamestate`'s loading status;
- the "loading screen is unloaded" point.

Keep the reopen on `play` for when the page was closed. Test: the page up throughout (no `play` change), and the
stage runs.

**Fixed** (the owner's go, 2026-11-18): once BeamNG.Earth is in its world and the game's loading screen has gone
(`core_gamestate.loading()` false), the wait counts the page as shown if it is already up. If the game left the UI
on `play`, the page is put back. Test: `test_run`, "the page up the whole time".

### 2. The Rally page tile's picture

The owner wanted it "more obviously Earth Rally". It is now the GitHub social preview (the jump shot with the
EARTH RALLY wordmark), cut to 16:9 at 960x540. Source: `Earth Rally marketing/social/github-social-preview.jpg`.
