# Notes for 1.5.1

## 1. Earth's strips over the pause menu (stopgap, remove when BeamNG.Earth fixes it)

*Built, waiting for the user's test.* **BeamNG.Earth's download status shows over the Escape menu** (the user,
2026-11-14). The bug is **BeamNG.Earth's**: it happens with BeamNG.Earth alone, and it is still in its `dev` as of
2026-11-14. Nobody had reported it; its issues and PRs were searched for pause, escape, menu, overlay and loading.
Earth Rally carries a stopgap until BeamNG.Earth fixes it.

**Why it happens.** These were checked in the game's Vue source, BeamNG.Earth's source and `beamng.log`.
- In 0.40, Escape opens the route **`pause`** (`pause.vehicle`, `pause.environment`, ...), and **`menu`** is the main
  menu. The log shows the same: `Router phase ... mountReady for route: pause`.
- The pause route's meta has `uiApps: { shown: false }` (`ui/ui-vue/src/modules/pause/routes.js`). The game's
  `UiAppsOverlay.vue` then takes every UI app away with `v-if`, so BeamNG.Earth's status, banner and credits apps are
  destroyed.
- BeamNG.Earth then draws the same things with imgui (`core.lua`: `if not hudapps.mounted('status') then
  statusbar.draw(...)`), and imgui is drawn over the HTML UI. The strip carries the loading line, `Loading 64% |
  downloading 14 files ...`.
- Its imgui drawing is meant to step aside for a menu, through `credits.hiddenByUi()`. But the state test behind it,
  `credits.lua` `setUiState`, is `toState:sub(1, 4) == 'menu'`, which never matches `pause`. Its credits.lua comments
  still call the pause menu `menu`, so this most likely came with 0.40's new router.
- **Our rally menu has the same problem**, and that part is ours to cover. Opened with Ctrl+Alt+K from driving, the
  apps stay mounted and our full-screen page covers them. But opened from the pause menu's Earth Rally tab, it comes
  straight from `pause` with the apps still taken away. BeamNG.Earth cannot know our route's name, so its imgui
  strips draw over our page.

**The stopgap**, in `mod/.../earthRally/earthMenuFix.lua`: on `pause` / `pause.*` and on our `earthRally` route, it
calls BeamNG.Earth's own `credits.setUiState('menu')`, the state its test was written for. It does this once in
`onUiChangedState` and once more on the next frame, because BeamNG.Earth's hook may run after ours and undo it.
- Everything after that is BeamNG.Earth's own behaviour. Its strip, banner, credits and update/dev-build notices all
  hide behind `hiddenByUi()`, which is what its credits.lua header says should happen in the pause menu.
- **Nothing of ours is left set.** The next state change, for example back to `play`, goes through BeamNG.Earth's
  own hook and puts its state right. That holds even if Earth Rally is reloaded or switched off mid-menu.
- Two pause pages are left alone: `pause.hudApps*` (the HUD-apps editor) and `pause.photomode.overlay.edit*`. Their
  meta sets `shown: true`, so BeamNG.Earth's apps are really on screen there.
- The credits now hide over the pause menu too. That is BeamNG.Earth's own design, not Earth Rally turning
  attribution off; they stay up while driving, including on a stage.
- `runner.uiHidden` now counts `pause` too, with the same two pages left out. Our check had copied BeamNG.Earth's
  `menu` test. That did no harm, because the pause route takes our HUD app down anyway.

**A first version was dropped after review.** It told BeamNG.Earth its strip apps were on screen while paused (the
`hudApp` call a stage uses), then gave them back after a delay. BeamNG.Earth's mount flag is one boolean, and our
own hold could not be told apart from a real app. So a stage ending in the pause menu, or a layout changed in the
HUD-apps editor, left the strips held for the rest of the level. That would have taken BeamNG.Earth's "server not
running" banner with it. It also missed the update notices and the credits.

**How to tell BeamNG.Earth has fixed it.** Its `credits.lua` `setUiState` (or whatever replaces it) hides on
`pause`. To check in game, switch Earth Rally off, press Escape in the BeamNG.Earth level while the world is loading,
and the loading line should not show over the menu. If only `pause` is fixed, our page from the pause tab still
needs the stopgap's `earthRally` case. Keep a cut-down version for that, or ask BeamNG.Earth for a way to name
routes it should hide for.

**Removing the stopgap:**
1. Delete `mod/earth_rally/lua/ge/extensions/earthRally/earthMenuFix.lua` and `tests/test_earth_menu_fix.lua`.
2. In `main.lua`, remove the `earthMenuFix` require, `earthMenuFix.uiState(toState, M.ROUTE)` in
   `onUiChangedState`, and `pcall(earthMenuFix.update)` after `earth.update()` in `onUpdate`.
3. Keep the `pause` check in `runner.uiHidden`. Inline `earthMenuFix.isPause` there: `pause` / `pause.*`, but not
   `pause.hudApps*` or `pause.photomode.overlay.edit*`.
4. In `tests/test_run.lua`, drop the `beamngEarth/credits` stub and the "BeamNG.Earth told" part of the pause-menu
   check. Keep its `runner.uiHidden` part.

**Not reported upstream yet.** The fix for BeamNG.Earth would be one line: `credits.lua` `setUiState` also hides on
`pause` / `pause.*`, apart from the two pages that show apps. Nothing here sends it; the user decides whether to file
it.
