-- menuPause (1.6.2, #13): the menu page pauses the game through the game's pause-request stack, and only ever takes
-- back its own request -- against a copy of simTimeAuthority's push / pop (BeamNG.drive 0.40.5 lua/ge/simTimeAuthority.lua).
local T = dofile(TESTS .. '/testlib.lua')
function log() end

-- simTimeAuthority's request stack, as in 0.40.5 (the replay and core_intapi branches left out)
local paused = false
local calls = {}
local pauseCounter, wasPausedBefore, requests = 0, false, {}
local function pause(p) calls[#calls + 1] = p; paused = p end
simTimeAuthority = {
  getPause = function() return paused end,
  pause = pause,
  togglePause = function() pause(not paused) end,
  pushPauseRequest = function(id)
    if requests[id] then return end
    requests[id] = true
    if pauseCounter == 0 then wasPausedBefore = paused end
    pauseCounter = pauseCounter + 1
    pause(true)
  end,
  popPauseRequest = function(id)
    if not requests[id] then return end
    requests[id] = nil
    pauseCounter = math.max(0, pauseCounter - 1)
    if pauseCounter == 0 and not wasPausedBefore then pause(false) end
  end,
}
local STA = simTimeAuthority

local mp = require('earthRally/menuPause')
local ROUTE = 'earthRally'

-- opened from driving: paused; closed: running again
mp.uiState(ROUTE, ROUTE)
T.check(paused and mp.held(), 'the page up: the game paused')
mp.uiState(ROUTE, ROUTE)
T.check(pauseCounter == 1, 'the same state twice: one request, not two')
mp.uiState('play', ROUTE)
T.check(not paused and not mp.held(), 'back to driving: running again')

-- the player had paused it themselves (J) before opening the page: still paused after
STA.togglePause()
T.check(paused, '(paused by the player)')
mp.uiState(ROUTE, ROUTE)
mp.uiState('play', ROUTE)
T.check(paused, 'a game the player paused stays paused when the page closes')
STA.togglePause()

-- through the Escape menu: pause > Earth Rally tab > our page > play, the game's own request leaving first...
STA.pushPauseRequest('ui_pause_home_tab')
STA.popPauseRequest('ui_pause_home_tab')
mp.uiState(ROUTE, ROUTE)
T.check(paused, 'from the Escape menu (its request gone first): paused')
mp.uiState('play', ROUTE)
T.check(not paused, '... and running again on the way out')
-- ... or ours arriving first: the two overlap, and neither unpauses under the other
STA.pushPauseRequest('ui_pause_home_tab')
mp.uiState(ROUTE, ROUTE)
STA.popPauseRequest('ui_pause_home_tab')
T.check(paused, 'the Escape menu\'s request gone, ours still in: paused')
mp.uiState('pause', ROUTE)            -- back from our page to the Escape menu
STA.pushPauseRequest('ui_pause_home_tab')
T.check(paused, 'back to the Escape menu: paused (its own request)')
STA.popPauseRequest('ui_pause_home_tab')
T.check(not paused, 'and the Escape menu closed: running')

-- a pop for a request we never made: never sent (the Escape menu's pause is not ours to lift)
STA.pushPauseRequest('ui_pause_home_tab')
local n = #calls
mp.uiState('play', ROUTE)
mp.release()
T.check(paused and #calls == n, 'nothing of ours in: nothing taken back, the Escape menu stays paused')
STA.popPauseRequest('ui_pause_home_tab')

-- the level goes with the page up: release() takes the request back, once
mp.uiState(ROUTE, ROUTE)
mp.release()
T.check(not paused and not mp.held() and pauseCounter == 0, 'release: our request taken back')
mp.release()
T.check(pauseCounter == 0, 'release twice: harmless')

-- no request stack (an older game): the page opens, nothing paused, nothing thrown
simTimeAuthority = nil
mp.uiState(ROUTE, ROUTE)
T.check(not mp.held(), 'no simTimeAuthority: nothing held')
mp.uiState('play', ROUTE)

T.done('test_menu_pause')
