# Notes for 1.5.1

## 1. Earth's strips over the pause menu (stopgap, remove when BeamNG.Earth fixes it)

*Built, waiting for the user's test.* **BeamNG.Earth's download status shows over the Escape menu** (the user,
2026-11-14). **Not ours**: it happens with BeamNG.Earth alone, it is still in its `dev` as of 2026-11-14, and nobody
had reported it (issues and PRs searched for pause / escape / menu / overlay / loading). Earth Rally carries a stopgap
until BeamNG.Earth fixes it.

**Why it happens.** These were checked in the game's Vue source, BeamNG.Earth's source and `beamng.log`.
- In 0.40, Escape opens the route **`pause`** (`pause.vehicle`, `pause.environment`, ...). **`menu`** is the main
  menu. The log shows the same: `Router phase ... mountReady for route: pause`.
- The pause route's meta has `uiApps: { shown: false }` (`ui/ui-vue/src/modules/pause/routes.js`). The game's
  `UiAppsOverlay.vue` then takes every UI app away with `v-if`, so BeamNG.Earth's status, banner and credits apps are
  destroyed. Each one sends `hudApp(name, false)` as it goes.
- BeamNG.Earth then draws the same strip with imgui (`core.lua`: `if not hudapps.mounted('status') then
  statusbar.draw(...)`), and imgui is drawn over the HTML UI. That strip carries the loading line, `Loading 64% |
  downloading 14 files ...`.
- That imgui drawing is meant to hide for a menu, but `credits.lua` `setUiState` tests
  `toState:sub(1, 4) == 'menu'`, which never matches `pause`.
- It does not happen over our rally menu because our `earthRally` route does not set `uiApps`. The apps stay mounted,
  so there is no imgui fallback, and our full-screen page covers them. During a stage our runner holds the strips
  anyway.

**The stopgap**, in `mod/.../earthRally/pauseStrips.lua`:
- While the state is `pause` / `pause.*`, it holds BeamNG.Earth's `status` and `banner` with
  `earthAdapter.holdStrips`, the same internal `core.hudApp` call a stage already uses. BeamNG.Earth then leaves out
  its imgui drawing.
- The **credits are not held**. We never take the attribution down, so the credits line may still show over the
  pause menu until BeamNG.Earth's own fix.
- After the menu closes, the hold stays on for 4 s, because BeamNG.Earth's apps re-announce themselves every 3 s.
  Only then are strips given back, and only those that were **not** on screen before the pause. BeamNG.Earth's mount
  flag is one boolean, not a count, so giving back a strip whose app is back would mark it gone again. Its imgui strip
  would then draw over its own app for up to 3 s.
- `runner.uiHidden` now counts `pause` too. Our own check had copied BeamNG.Earth's `menu` test. That did no harm,
  because our HUD is a UI app and the pause route takes it down anyway.

**How to tell BeamNG.Earth has fixed it.** Its `credits.lua` `setUiState` (or whatever replaces it) hides on
`pause`. Check that with Earth Rally switched off: press Escape in the BeamNG.Earth level while the world is
loading, and the loading line should not show over the menu.

**Removing the stopgap, once BeamNG.Earth's fix is in the minimum version we support:**
1. Delete `mod/earth_rally/lua/ge/extensions/earthRally/pauseStrips.lua` and `tests/test_pause_strips.lua`.
2. In `main.lua`, remove the `pauseStrips` require, the `pauseStrips.uiState(toState)` call in `onUiChangedState`,
   the `pauseStrips.update` call before `runner.update` in `onUpdate`, and the four `pcall(pauseStrips.reset)` lines
   after `pcall(earth.holdStrips, false)`.
3. Keep the `runner.uiHidden` `pause` check. Inline `pauseStrips.isPause` there as
   `toState == 'pause' or toState:sub(1, 6) == 'pause.'`.
4. `earthAdapter.stripMounted` has no other caller: remove it. `holdStrips`'s `names` argument can stay or go.

**Not reported upstream yet.** The one-line fix for BeamNG.Earth would be `credits.lua` `setUiState` also hiding on
`toState:sub(1, 5) == 'pause'`. It would cover the credits too. It is drafted here, not sent; the user decides
whether to file it.
