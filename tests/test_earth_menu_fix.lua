-- earthMenuFix (a stopgap for BeamNG.Earth drawing its imgui strips over the pause menu): which states it corrects,
-- and that it tells BeamNG.Earth's credits.setUiState 'menu' for them -- against a copy of that function's test.
local T = dofile(TESTS .. '/testlib.lua')
function log() end

-- BeamNG.Earth's credits.lua setUiState / hiddenByUi, as on dev 2026-11-14 (the map route and big map left out)
local uiHidden = false
local said = {}
package.loaded['beamngEarth/credits'] = {
  setUiState = function(toState)
    said[#said + 1] = toState
    uiHidden = type(toState) == 'string' and (toState:sub(1, 4) == 'menu' or toState == 'loading')
  end,
}
local function earthHook(toState) package.loaded['beamngEarth/credits'].setUiState(toState) end   -- its own hook

local fix = require('earthRally/earthMenuFix')
local ROUTE = 'earthRally'

T.check(fix.isPause('pause') and fix.isPause('pause.vehicle') and fix.isPause('pause.environment.weather'),
  'isPause: the Escape menu and its pages')
T.check(not fix.isPause('menu') and not fix.isPause('play') and not fix.isPause('pauseX') and not fix.isPause(nil),
  'isPause: not the main menu, driving, a lookalike, or nothing')
T.check(not fix.isPause('pause.hudApps') and not fix.isPause('pause.hudApps.editlayout')
  and not fix.isPause('pause.hudApps.editlayout.transform') and not fix.isPause('pause.photomode.overlay.edit')
  and not fix.isPause('pause.photomode.overlay.edit.adjust') and fix.isPause('pause.photomode'),
  'isPause: not the pages that keep the UI apps on screen')
T.check(fix.isPause('pause.hudApps.selector'), 'isPause: the app selector takes the apps away (shown: false), so it counts')
T.check(fix.hides(ROUTE, ROUTE) and not fix.hides(ROUTE, nil) and not fix.hides('play', ROUTE), 'hides: our page too')

-- BeamNG.Earth's hook first, then ours (the order extensions.hook happens to take): hidden at once
uiHidden = false
earthHook('pause'); fix.uiState('pause', ROUTE)
T.check(uiHidden, 'Earth first, then us: hidden at once')
fix.update()
T.check(uiHidden and said[#said] == 'menu', 'the next frame tells it again')
-- ours first, then BeamNG.Earth's (which undoes it): the next frame puts it right
earthHook('play'); fix.uiState('play', ROUTE)
T.check(not uiHidden, 'back to play: shown (BeamNG.Earth\'s own hook)')
fix.uiState('pause.vehicle', ROUTE); earthHook('pause.vehicle')
T.check(not uiHidden, 'us first, then Earth: undone for a frame')
fix.update()
T.check(uiHidden, '... and the next frame hides it')
said = {}
fix.update()
T.check(#said == 0, 'told twice only, not every frame')
-- our page, from the pause tab or from driving (Ctrl+Alt+K)
earthHook(ROUTE); fix.uiState(ROUTE, ROUTE); fix.update()
T.check(uiHidden, 'our page from the pause tab: hidden')
earthHook('play'); fix.uiState('play', ROUTE); fix.update()
earthHook(ROUTE); fix.uiState(ROUTE, ROUTE); fix.update()
T.check(uiHidden, 'our page from driving: hidden')
-- pause and back inside one frame: nothing told by the frame after
said = {}
earthHook('pause'); fix.uiState('pause', ROUTE); earthHook('play'); fix.uiState('play', ROUTE); fix.update()
T.check(#said == 3 and said[3] == 'play' and not uiHidden, 'pause then play in one frame: nothing left told')
-- the HUD-apps editor: BeamNG.Earth's apps are on screen there, left alone
earthHook('pause.hudApps'); fix.uiState('pause.hudApps', ROUTE); fix.update()
T.check(not uiHidden, 'the HUD-apps editor: not touched')
earthHook('play'); fix.uiState('play', ROUTE); fix.update()
T.check(not uiHidden, 'play: nothing of ours left set')

-- BeamNG.Earth absent, or its function renamed: quiet
package.loaded['beamngEarth/credits'] = nil
T.check(pcall(function() fix.uiState('pause', ROUTE); fix.update() end), 'no BeamNG.Earth: quiet')
package.loaded['beamngEarth/credits'] = { setUiState = 'not a function' }
T.check(pcall(function() fix.uiState('pause', ROUTE); fix.update() end), 'a changed BeamNG.Earth: quiet')
package.loaded['beamngEarth/credits'] = nil

T.done('test_earth_menu_fix')
