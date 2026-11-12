# Earth Rally 1.2.0 plan

Theme: the player UI (menus, the in-car HUD, results), designed with the user: mock-ups first
(`docs/mockups-1.2.0/`, open `index.html`), nothing built in game until agreed. Then the other 1.2.0 ideas
(docs/ideas-1.2.0.md): course tape across side roads, junction direction signs.

Decided so far (the user, 2026-11-12): no split times, no stage sketches or elevation profiles for now. The UI items
from the 1.1.0 test notes come with it: the reset penalty switch (item 2), the off-route warning (item 10), the
start-line skip hint (item 12).

Status: mock-ups and this research done (2026-11-12). The UI built (build order 1-8, 2026-11-12), offline-tested,
not yet tried in game: see "Built" and "Defaults chosen, to confirm" below. Course tape and junction signs not started.

## The mock-ups

| file | what |
|---|---|
| `menu.html` | Rallies (cards; Add a rally with Open import folder and the last import report) → Rally page (SS, name, km, Ready / Recce recommended, best) → Stage page (length, corners, junctions, bridges, runs; Drive stage, Route to start, Recce). Settings |
| `hud.html` | At 1920×1080 over the 1.1.0 stage layout (pacenote cards, start clock view, speedometer): 1 driving to the stage, 2 at the ATC, 3 the start (countdown, GO, jump start), 4 on the stage, 4 off route, 5 flying finish (new best / slower), on to the stop control, 7 messages. Each piece tagged *stock* (a game rally app), *ours* (a Vue component of ours) or *have* (already in 1.1.0) |
| `results.html` | 6 stage done at the stop control: time, penalties itemised, best; Next stage, Retry, Rally menu |

Stage names and lengths are the two real rallies' (from the maps' line names and lengths only; no map data in the
repo). Both maps have 9 lines, so both rallies show 9 stages (the pitch said 12 and 6). Times, corner counts and the
import report are sample data.

## What the game gives (BeamNG.drive 0.40.5, checked in its files)

### The stock rally HUD apps

All in `ui/modules/apps/rallyLoop/` (the `Rally*` folders hold only `app.json`; the `.vue` files are
`rallyLoop/app.<directive>.vue`). Each subscribes to one stream, `rallyLoop` (`useStreams(['rallyLoop'])`), and
copies its sub-tables with `Object.assign`, so a field not sent keeps its last value. Positions in the game's own
rally layout (`settings/ui_apps/originalLayouts/mission/rallyModeStage.uilayout.json`): RallyStageTiming top-left
288 px wide, RallyStageProgress top at x 288, 780 wide, RallyCountdown top 82 centred 450 wide, pacenotes as ours.

| app | shows | fields it reads |
|---|---|---|
| **RallyCountdown** (`app.rallyCountdown.vue`, VehicleProximity / CountdownWidget) | `activeState = 'vehicleProximity'`: a badge (SS2 / ATC label, or STOP / SLOW / BACK / STAGED by distance) and the distance; an instruction; "Start in M:SS". `'countdown'`: 5 red squares filling from 5 s, a green bar at 0, the rally clock big. A hint row "[Interact] Skip Clock" | `activeState`; `rallyClock.wallClockTime {time, ampm}`, `canSkipCountdown`, `canSkipTimeControls`, `isTimeControlSkipAvailable`; `scheduleData.eventType` (`'tc'`, `'ss_start'`, `'ss_stop'`), `label`, `ssLabel`, `timeDiff` (a string "M:SS"), `speedLimitDisplay`, `speedUnit`, `isSpeeding`, `inServicePark`; `vehicleProximity.distance` (m; > 200 shown in km), `isNear`, `isStopped`, `isFrozen`, `isStartLine`, `isOverLineAllowed`; `countdownData.countdown` (whole seconds; 0 = GO) |
| **RallyDashboard** (`app.rallyDashboard.vue`) | Event clock (pink), "Your time" (`totalTime`), instructions: fixed texts for `service_in` and `tc` ("Reach TC1 between … Penalty for each minute early or late") | `activeState`; `rallyClock.wallClockTime`, `totalTime`; `scheduleData.eventType`, `label`, `eventWallClockStart/End`. Hidden while `stageActive` |
| **RallyStageTiming** (`app.rallyStageTiming.vue`) | Header (italic) and the stage time big on the theme colour; split rows | `stageData.stageHeader` (else "STAGE {label} / {scheduleData.totalSSCount}"), `currentSSTime` (s), `splits[]` (rows for each with a `time`, except `pathnodeType = 'finish'`); `uiColors.theme`; `showStageApps` |
| **RallyStageProgress** (`app.rallyStageProgress.vue`, DistanceWidgetSVGRect) | A track with the fill and a marker at `distPct`, split ticks, the finish tick labelled with the last split's `splitLabel` + unit | `stageData.completion.distPct` (0..1), `completion.totalDistM`, `splits[]` (`pathnodeType` starting `split_` for ticks; the last one's `splitLabel` for the finish label), `unit`; `uiColors.theme`; `showStageApps` |
| **RallyTimecard** (`app.rallyTimecard.vue`) | TIME CARD: total time, a row per TC (due / actual / status) and SS (time taken), a penalties card grouped by event; shown / hidden with Interact (`RallyGameplayInteract` event) | `rallyClock.totalTime`, `isNgrcMode`; `timecardData[]` (`label`, `group`, `isStageEntry`, `stageTime`, `scheduledTime`, `recordedTime`, `status`), `penaltyData {totalPenalty, groups[{eventGroup, totalPenalty, penalties[{type, amount, count}]}]}`, `missionName` |
| **RallyVisualPacenotes** | the pacenote cards (already used, fed by the rally engine itself) | — |

Sample frames: `rallyLoop/mockdata/road-section.json`, `countdown-sequence.json`, `stage-in-progress.json`
(and events `RallyClockSkipped`, `RallyGameplayInteract`).

Gotchas found in the apps' code:
- RallyStageTiming and RallyStageProgress are `display: none` unless **`uiColors.theme`** is sent (and
  `showStageApps` is not false). Send `uiColors = { theme = '#1f8fff' }` (the game's stage colour,
  `gameplay/rally/loop/uiColors.lua`) and `showStageApps = true`.
- RallyStageProgress labels the finish from the **last split's `splitLabel`**: with no splits the finish has no
  label. Send one split `{ pathnodeId = 1, pathnodeType = 'finish', splitLabel = '8.4', distPct = 1 }` (RallyStageTiming
  skips `finish` rows, so no split row shows). No km-done readout on the stock bar.
- RallyCountdown with `eventType = 'tc'` shows "Limit {speedLimitDisplay}{speedUnit}" while approaching: without a
  speed limit it prints "Limit nullkm/h". Use it for the ATC only with a limit, or not at all (our card instead).
- `timeDiff` is shown as sent: send a string ("0:58"), as the game's rallyLoopManager (`formatDuration`).
- `countdownData.countdown` is whole seconds, the squares light from 5; GO at 0.
- RallyDashboard's instruction texts are fixed (TC time windows, service bays): not ours.

### How the stream gets there

`guihooks.queueStream('rallyLoop', data)` each frame. In the game it comes from `gameplay_rallyLoop` (its loop
manager, or `standaloneFallbackStream.lua`, fed by `extensions.hook('onRallyDataUpdated', partial)` from the
flowgraph nodes). That extension is not loaded by the rally engine (`gameplay_rally`, which we load); only the rally
editor and rally-loop flowgraphs load it.

Two ways for us:
1. **Send `rallyLoop` ourselves** (recommended): runner builds the whole table each frame and queues it, with
   `gameplay_rallyLoop` not loaded (check `extensions.isExtensionLoaded('gameplay_rallyLoop')` and leave the stream
   alone when it is: the game's own rally mode is running). Full control of every field.
2. Load `gameplay_rallyLoop` and hook `onRallyDataUpdated` (we already do for the start clock). Its fallback takes
   `stageData` from the rally engine's own stage tracker (`rallyManager:getActiveStageData`, which we never start: our
   timing is ours), and drops countdown frames when the start clock's 3D view is on (setting
   `rallyStartCountdownDisplay`). Not a fit.

`onRallyDataUpdated` keeps going to `gameplay_rallyStartClock` as now (its LED board and the picture-in-picture);
the rallyLoop stream is a separate, UI-only copy of the same clock data.

## Each HUD moment

What renders it, the fields, what runner.lua has, and what it lacks. "ours" = `EarthRallyHud` (below).

| # | moment | renders it | fields sent | runner has | to add |
|---|---|---|---|---|---|
| 1 | Driving to the stage (`toAtc`; `toStart` without an ATC) | ours (stock look). Route arrows: BeamNG.Earth's GPS, as now | our stream: rally clock, stage SS number, name, km, (surface), the control's kind, distance, what to do | `M.clock()`, `run.toControlM`, `run.stage`, `run.atc` | SS number (stage's index in its event); surface (open question). (Alternative: stock RallyCountdown proximity with `eventType = 'tc'` + a speed limit we do not have) |
| 2 | Checked in at the ATC, moving up (`toStart` after check-in) | stock **RallyCountdown** (proximity, `eventType = 'ss_start'`) + our timecard line | `activeState = 'vehicleProximity'`; `scheduleData = {eventType='ss_start', label='SS2', ssLabel='2', timeDiff='0:58'}`; `vehicleProximity = {distance = run.toControlM, isNear = within the start zone, isStopped, isFrozen = held, isStartLine = true}`; `rallyClock.wallClockTime`, `canSkipCountdown = M.canSkip()`; ours: checked-in time, start time | `run.atcTime`, `run.startAt`, `run.toControlM`, `M.canSkip()`, `run.zone` | `isNear` / `isStopped` from the zone; `run.atcTime` kept as is |
| 3 | Start line, countdown (`waitStart`) | stock **RallyCountdown** (`activeState = 'countdown'`) + the start clock view (have) + our big numeral and jump-start card | `countdownData = {countdown = ceil(startAt - clock), state = 'counting' / 'go'}`, `rallyClock.wallClockTime`, `canSkipCountdown` (the "[Interact] Skip Clock" row: item 12's hint) | `run.startAt`, `M.clock()`, `run.jumpStart`, `M.canSkip()` | the numeral moves from `ui_message` to ours (or is dropped: question) |
| 4 | On the stage (`running`) | stock **RallyStageTiming** + **RallyStageProgress**; pacenote cards (have); ours: km done | `activeState = 'stageActive'`; `stageData = {stageHeader='SS2 · KUHNLE', currentSSTime = run.clock, isActive = true, completion = {distPct, totalDistM}, splits = {finish only}, unit}`; `uiColors.theme`; `showStageApps = true` | `run.clock`, `run.along`, `run.startM`, `run.finishM` | — |
| 4 | Off route | ours, in the progress bar's place | our stream: `off` (m), `backBearing` (deg, relative to the car's heading) | `run.off`, `M.OFF_ROUTE_M` (60 m) | the bearing to the line's point at `run.along` against the car's direction; a little hysteresis (on at 60 m, off at 40 m) |
| 5 | Flying finish (`running` → `toStop`) | ours, ~4 s; RallyStageTiming keeps the final time | our stream: final time, delta to the best before this run, new best, penalties included | `run.finalTime`, `run.penalty`, `run.best` | `run.best` is the best *including* this run (events.addResult): take `events.best()` before adding |
| – | On to the stop control (`toStop`) | stock **RallyCountdown** proximity, `eventType = 'ss_stop'` (yellow SLOW, distance). Not in the pitch: free if wanted | `scheduleData.eventType = 'ss_stop'`, `vehicleProximity.distance = run.toControlM`, `isNear` | `run.toControlM`, `run.zone` | — |
| 6 | Stage done (`finished`, stopped at the stop control) | ours (`EarthRallyResults`, interactive) | stage time, each penalty, total, best, the next stage | `run.stageTime`, `run.jumpStart`, `run.latePenalty`, `run.checks.lateMinutes`, `run.missedAtc`, the event's stages | reset count; the next stage; Retry (runner.start on the same stage); the tidy-up (8 s) to wait while the card is open |
| 7 | Messages | the game's toasts: `guihooks.trigger('toastrMsg', {type = 'info' / 'warning' / 'success', title, msg, config = {timeOut = ms}})` (as `gameplay/lowPerformance.lua`) | — | `say()` / `earth.notify` | `say(text, s, kind)` → a toast; BeamNG.Earth's notify kept as the fallback |

The stock RallyTimecard is not used: TC due / actual rows and grouped penalties, toggled by Interact (which we use
for the skip), no buttons.

`activeState = 'inactive'` (and nothing else) is sent once the run is tidied away, so the stock apps blank.

## Our Vue pieces

1. **EarthRallyHud** (moments 1, 2's timecard line, 3's numeral and jump start, 4's km readout and off route, 5):
   a Vue UI app of the mod, `ui/modules/apps/EarthRallyHud/app.json` (`directive`, `domElement`, `"vue": true`,
   `interactive: "no"`) with `app.vue` beside it (the game's `ui/apps.lua` finds a colocated `app.vue`), placed in
   our stage layout (`earthRallyStage.uilayout.json`) full-width at the top. It reads our own stream
   (`guihooks.queueStream('earthRally', {...})`, `useStreams(['earthRally'])`). One component switching on the
   run's state, so only one thing shows at a time. The stock look: `rgba(66,70,81,.8)` panels, radius 8 px, the
   pink rally clock, `#1f8fff` stage colour, Noto Sans / Overpass Mono.
2. **EarthRally** (the menu): a full-screen route of ours (rallies, rally, stage, settings as child views or one
   component with its own view state).
3. **EarthRallyResults** (moment 6): interactive. Either a route shown over the game (as the game's mission end
   screens) or an interactive UI app in the stage layout. To try both in game.

### A full-screen page and a pause-menu tab (ui/ui-vue/mods/README.md; BeamNG.Earth does both)

Files under `ui/ui-vue/mods/earthRally/` in the mod zip. `index.js` exports `onLoad` / `onUnload`:

- **Route** ("Standalone routes"): `window.bngRoutes.add([{ path: SOURCE, routes }])` with
  `{ path: '/earth-rally', name: 'earthRally', component: EarthRally, meta: { luaRoute: { title: 'Earth Rally',
  backTarget: 'play' } } }`, then `await lua.extensions.ui_router_routeManager.registerModRoutes(SOURCE,
  toLuaRoutes(routes))`; on unload remove both (Vue first, then Lua with `{ fallbackRoute: 'play' }`). Opened from
  Lua with `ui_router.navigate('earthRally')` (BeamNG.Earth's `settings.lua M.navigate`, falling back to
  `guihooks.trigger('ChangeState', {state = ...})`). Ctrl+Alt+K (our input action) toggles it.
- **Pause-menu tab** ("Pause menu"): `await lua.extensions.ui_pause_actions.registerModTab({ id: 'earthRally',
  label: 'Earth Rally', icon: …, card2ComponentName })`, then `registerModButton({ id, tabId: 'earthRally', label,
  componentName: '/ui/ui-vue/mods/earthRally/<Card>.vue', props })` per page (BeamNG.Earth: one button per
  settings page, `EarthSettingsPage.vue` with a `page` prop). Ours: "Rallies" (a card with the current rally and
  an Open Earth Rally button navigating to the route) and "Settings" (the settings in the card).
  `unregisterModTab(id)` on unload removes its buttons.
- Vue talks to Lua as BeamNG.Earth does: `window.bngApi.engineLua("earthRally_main.uiRallies()", cb)` (the result
  comes back as JSON), with a poll while a page is open; or `lua.extensions.earthRally_main.uiRallies()` through
  `@/bridge` (a promise).
- Built-in components from `@/common/components/base` (BngButton with `accent`, BngCard, BngPill, BngBinding for
  key hints). Errors show in the UI and the DevTools console; the Vue debug overlay's Mods panel reloads a mod.

### Settings: how they are stored

As BeamNG.Earth (`lua/ge/extensions/beamngEarth/settings.lua`): a Lua module owns them, with a schema of defaults
(today's behaviour, so a missing or broken file changes nothing), saved with `jsonWriteFile('/settings/earthRally.json',
values, true)` and read with `jsonReadFile` (the user folder's `settings/`). The Vue page gets `uiState()` and
calls `uiSet(key, value)`, which validates, saves and answers with every value. Not the game's own `settings`
(`settings.getValue`): that is the game's options list.

| key | values (default) | in the runner |
|---|---|---|
| `units` | `km` / `mi` (km) | display only (Vue; stageData.unit and the finish label) |
| `timeControls` | `full` / `quick` (full) | `quick`: no ATC (`run.atc = nil`), set down on the start line (as Go to start), start a few seconds after stopping (`NO_ATC_START_S`) |
| `resetPenalty` | on / off (on) | `onVehicleResetted(vid)` for the player's car while `running`: +10 s each, counted in `run.resets` and the result |
| `zoneBrake` | on / off (on) | `zone()` without the brake (check-in by stopping still counts) |
| `clockView` | `right` / `top` / `off` (right) | `right`: `CLOCK_VIEW_RIGHT` / `CLOCK_VIEW_BOTTOM` as 1.1.0; `top`: leave the game's place; `off`: the view switched off (to find how: the view's `active` flag, or not feeding `countdown`, which also stops the LED board's countdown) |
| `devPanel` | on / off (off) | the ImGui window only when on (Ctrl+Alt+K then opens the page; the panel from the page's settings) |

### What runner.lua sends

One function, `runner.uiFrame()`, called each frame by main.lua while a run exists, returns two tables:
`rallyLoop` (the stock apps' fields above) and `earthRally` (ours: `{ state, stage = {ss, name, km}, clock,
atcTime, startAt, toControlM, controlKind, canSkip, jumpStart, off, backBearing, along, total, finish =
{time, delta, best, newBest, penalties = {jumpStart, late, resets, missedAtc}}, next = {id, ss, name, km} }`),
queued with `guihooks.queueStream`. Pure and testable offline (tests/test_run.lua) like the rest of the runner;
main.lua does the queueing. Units and wording are the Vue side's.

## Build order

1. **Settings module** (Lua, with tests) and the reset penalty (test item 2): it changes results, so first.
2. **runner.uiFrame** + the `rallyLoop` / `earthRally` streams, with tests; main.lua queues them.
3. **Stock apps in our stage layout** (RallyCountdown, RallyStageTiming, RallyStageProgress at the stock places;
   BeamNG.Earth's status app moved off the progress bar). In game: moments 2, 3, 4 and the stop.
4. **EarthRallyHud** (moments 1, 3's extras, 4's km and off route, 5). In game.
5. **Toasts** for the runner's messages.
6. **EarthRallyResults** (moment 6), with Next stage / Retry / Rally menu.
7. **The menu page and the pause-menu tab** (rallies, rally, stage, settings); the ImGui window becomes the
   developer panel. In game.
8. **HUD preview** (plan-1.1.0's agreed dev command: sample frames through the real HUD without driving), if still
   wanted: with uiFrame it is a list of frames.
9. Then the course tape and the junction signs (below).

After each step: tried in game with the user, adjusted.

## Course tape and junction direction signs (ideas 1 and 2)

**Game assets** (`content/art_shapes.zip`, all `.dae` under `art/shapes/race/rally/rally_assets/` unless said):
- Road closure tape: `s_tape_road_closure_6m.dae`, `s_tape_road_closure_8m.dae`, `s_tape_road_closure_10m.dae`
  (pick by the side road's width). Also `s_spectator_tape_5m.dae`, `s_spectator_tape_big_a/_b/_center.dae`.
- Direction boards: `s_corner_dir_left.dae`, `s_corner_dir_right.dae`, `s_corner_dir_straight.dae`,
  `s_corner_dir45_left.dae`, `s_corner_dir45_right.dae`, `s_corner_dir135_right.dae`, `s_corner_dir225_left.dae`;
  `s_corner_marker.dae`.
- Other barriers if the tape is too thin to read: `art/shapes/race/s_concrete_arrow_barrier.dae`,
  `art/shapes/race/chevron_x1.dae` / `chevron_x3.dae`, `art/shapes/race/cone.dae`, `art/shapes/objects/race_arrowsign_1_L.dae`
  / `_R.dae`, `art/shapes/objects/arrowboard_L.dae` / `_R.dae`, `art/shapes/objects/constructionbarrier_arrows.dae`.
- The ones we already put down: signboards (`s_rally_signboard_*.dae`), the gazebo, `s_rally_start_tree.dae`.

**Data.** The matched file's `junctions` are `[lat, lon, kind, side]` per junction on the stage line (kind `turn` /
`straight` / `fork`, side `left` / `right` for a fork), from `tools/match_roads.py landmarks()`: road-map nodes with
3+ roads on the line, side roads 40 m+ long, one per 25 m. It knows each side road's direction there (`ways`, the
`sides` list) but does not save it. Add to each junction: the stage's way in and way out (bearings) and each side
road's bearing (and its width class if Overture has it): `[lat, lon, kind, side, inDeg, outDeg, [sideDeg...]]`, old
files still read (the mod uses what is there). In game, BeamNG.Earth's road map (`map.getMap()` nodes and links, as
props.lua's `roadAt` / `walkRoad`) could give the same at the junction when the file lacks it, but only for the
kilometre loaded round the car: the file is better.

**Placing** (props.lua, as the controls' boards: each object on its own, heights from the ground under it, facing
along the road):
- *Tape*: across each side road the stage does not take, a few metres into it from the junction (6-10 m: past the
  main road's edge), square to the side road, the length by its width. On a `turn`, the road straight on is a side
  road too (taped). Put down while the car is within ~400 m (as the controls), taken away with the stage.
- *Direction board*: before the junction on the side of the turn, ~50-100 m before (as real stages), arrow by the
  turn's angle: < 30° straight (`s_corner_dir_straight`), 30-60° `dir45_*`, 60-120° `dir_left/right`, more `dir135` /
  `dir225`. Forks: `dir45` toward the kept side. Skip `straight` past a minor side road (the tape says it) unless
  the user wants boards there too.
- Tests offline: positions and turns from a junction table (as test_props), roads in every direction.

## Built (2026-11-12, not yet installed or tried in game)

| piece | files | wired to |
|---|---|---|
| Settings | `earthRally/settings.lua` (`/settings/earthRally.json`) | runner (`timeControls`, `resetPenalty`, `zoneBrake`, `clockView`), the HUD (`units`), main (`devPanel`) |
| Reset penalty | `runner.onVehicleResetted` (main.lua's `onVehicleResetted` hook) | +10 s a reset while `running` (not within 2 s of an origin move, debounced 0.5 s); `resets`, `resetPenaltyS` in the result |
| uiFrame | `earthRally/hudFrame.lua` (pure), `runner.uiFrame()` | main.lua queues `rallyLoop` and `earthRally` at 30 Hz (2 Hz once over; `inactive` once at the end); `rallyLoop` left alone while `gameplay_rallyLoop` is loaded |
| Stock apps | `settings/ui_apps/.../earthRallyStage.uilayout.json` (version 5) | RallyCountdown (top 82, centred), RallyStageTiming (left 0, top 64), RallyStageProgress (left 288, top 64: under BeamNG.Earth's status bar, left where it is); the game's toasts box (`topLeftApps`) moved to 1467 / 42 as in the game's rally layout |
| Our HUD | `ui/modules/apps/EarthRallyHud/app.json` + `ui/modules/apps/earthRally/app.earthRallyHud.vue` (full screen, click-through) | stream `earthRally`, its `show` table |
| Results card | `ui/modules/apps/EarthRallyResults/app.json` + `.../earthRally/app.earthRallyResults.vue` (interactive) | `earthRally_main.uiResults('next' / 'retry' / 'menu')`; the stage layout kept until a button, driving 100 m on from where the car stopped, or 2 min |
| Toasts | `runner.say(text, s, kind, title)` | `guihooks.trigger('toastrMsg', ...)`, BeamNG.Earth's notify without guihooks |
| Menu | `ui/ui-vue/mods/earthRally/` (index.js, EarthRally.vue, EarthRallyTab.vue, EarthRallySettings.vue, EarthRallySide.vue, store.js); `earthRally/menu.lua` | route `earthRally` (Ctrl+Alt+K: `earthRally_main.toggleMenu`), pause-menu tab "Earth Rally" (Rallies, Settings); `uiState`, `uiRally`, `uiStage`, `uiAction` (drive = `runner.start`, route = `earth.gpsSet` to `runner.arrivalPoint`, recce = `recce.start` with a teleport first when 300 m+ away, openFolder, rescan, abort, recce save / cancel), `uiSet` |
| Developer panel | main.lua's ImGui window | shown only with the setting on (or `earthRally_main.toggle()` in the console) |
| HUD preview | `earthRally/preview.lua`; `earthRally_main.previewHud()` (also a button in Settings and the developer panel) | about a minute of sample moments through `hudFrame.build`, the stage layout on for it |

Tests: `tests/test_hud.lua` (settings, every state of both streams, the preview, the menu's data),
`tests/test_run.lua` (the reset penalty, quick start, zone brake off, clock view off, off route with the way back,
the HUD across a real run, Retry, main.lua's page API, streams, preview and Ctrl+Alt+K).

### Defaults chosen, to confirm

The open questions below, answered with these defaults (the user had not answered yet); each is one place to change:

1. Countdown: the stock squares (RallyCountdown) plus our big numeral for the last 5 s (`hudFrame.BIG_COUNT_FROM`), and
   GO for 1.5 s (`GO_SHOW_S`). `ui_message` no longer shows the numbers.
2. "gravel" dropped: the next-stage card says the length only.
3. Km done: a small readout of ours beside the stock progress bar (`.er-km` in app.earthRallyHud.vue).
4. The stop control's SLOW + distance: kept (stock RallyCountdown, `eventType = 'ss_stop'`).
5. Results: a card in the HUD (an interactive app) at the stop control, after the flying finish's big time (4 s,
   `FINISH_CARD_S`); without a stop control it comes up at the flying finish. Closes on a button, driving 100 m on
   (`runner.RESULTS_CLOSE_M`), or after 2 min (`RESULTS_TIMEOUT_S`).
6. Pacenote cards dimmed while off route: a dark panel of ours over the stock app's place (`.er-dim-notes`).
7. BeamNG.Earth's status app left alone; the stock stage time and progress bar moved down to top 64 px under it
   (the layout file), our km readout and off-route card with them.
8. The turbo gauge left where it is; the clock view's place is the setting (right / top / off).
9. SS numbers in map order (the stage's place in the rally's file).
10. Pause menu: its own "Earth Rally" tab (Rallies, Settings).

### To check in game (not verifiable offline)

- The Vue files compile and mount (the game compiles them at runtime: errors in the UI and the DevTools console);
  `app.<directive>.vue` found for our two apps' `app.json` as for the stock rally apps.
- The layout: the stage layout file's version 5 replaces a saved version 4; positions at 1920x1080 and other
  resolutions; our full-screen HUD drawn above the stock apps (the off-route card covering the progress bar).
- The results card's buttons clickable while driving (an interactive app; the mouse cursor), and the empty card area
  not catching the mouse.
- The route opens with Ctrl+Alt+K and closes with Esc / Ctrl+Alt+K; `onUiChangedState` names it `earthRally`.
- The pause-menu tab, its two pages, the `flag` icon.
- The toasts (titles, one per message), their place (topLeftApps moved).
- The reset hook: one `onVehicleResetted` per reset (R, Insert, recover), none from BeamNG.Earth's own car moves.
- Settings saved to `settings/earthRally.json` and read back after a restart.

## Open questions for the user (answered for now by the defaults above)

1. Countdown on the line: the stock 5 squares + rally clock, a big 5-4-3-2-1-GO numeral, or both?
2. "8.4 km gravel": the surface is not known now. Drop it, or find it (Overture road `surface` / class in
   match_roads.py, where mapped)?
3. Km done: a small readout beside the stock progress bar (as drawn), or our own bar?
4. The stop control's SLOW + distance (stock, free): keep?
5. Results card: a page over the game (mouse / pad, like the mission end screen) or a card in the HUD? Shown when
   stopped at the stop control, or right at the flying finish?
6. The pacenote cards while off route: keep them, or hide until back on the line?
7. BeamNG.Earth's status app sits where the stock progress bar goes: move it (where?) or move the bar down?
8. The start clock view still overlaps the turbo gauge at 1080p (test notes): move the gauge in our layout?
9. Stage numbers: map order (SS1 = first line in the file), as drawn? Real rallies run some stages twice.
10. Pause-menu tab: its own "Earth Rally" tab (as BeamNG.Earth), or a button in the shared Mods tab?
