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

-- ... and nothing put back by the frame after (the page is taken for gone)
mp.uiState(ROUTE, ROUTE)
mp.release()
mp.update()
T.check(not paused and pauseCounter == 0, 'release, then a frame: nothing put back in')

-- an action that moves the car or loads the world started from the page: ours taken back, not put in again until
-- the page is next opened (BeamNG.Earth's holds pause only a game not paused already)
mp.uiState(ROUTE, ROUTE)
mp.suspend()
T.check(not paused and not mp.held() and mp.suspended(), 'an action started: our request taken back')
mp.update()
mp.uiState(ROUTE, ROUTE)
T.check(not paused and not mp.held(), '... and not put in again while the page stays up')
mp.uiState('play', ROUTE)
mp.uiState(ROUTE, ROUTE)
T.check(paused and mp.held() and not mp.suspended(), 'the page opened again: paused again')
mp.uiState('play', ROUTE)
mp.suspend()
T.check(not mp.suspended(), 'suspend with the page closed: nothing to hold off')

-- BeamNG.Earth holding the game itself: our request waits for its hold to end, then goes in
local earthHolds = true
mp.holding = function() return earthHolds end
mp.uiState(ROUTE, ROUTE)
T.check(not paused and not mp.held(), 'BeamNG.Earth holding: no request of ours on top of its hold')
mp.update()
T.check(not mp.held(), '... still holding: still none')
earthHolds = false
mp.update()
T.check(paused and mp.held(), '... its hold over: ours in')
mp.uiState('play', ROUTE)
T.check(not paused, 'closed: running again')
mp.holding = function() error('boom') end
mp.uiState(ROUTE, ROUTE)
T.check(mp.held(), 'a hold check that throws: taken as no hold')
mp.uiState('play', ROUTE)
mp.holding = function() return false end

-- (#63) the world's origin moving (the physics must run): our request taken back, put in again once it is done
local moving = false
mp.waitFor = function() return moving end
mp.uiState(ROUTE, ROUTE)
T.check(paused and mp.held(), 'origin move: the page up, paused')
moving = true
mp.update()
T.check(not paused and not mp.held(), 'origin move under way: our pause request taken back (#63)')
mp.update()
T.check(not paused and not mp.held(), 'origin move under way: not put in again meanwhile')
moving = false
mp.update()
T.check(paused and mp.held(), 'origin moved: paused again')
moving = true
mp.uiState('play', ROUTE)
mp.uiState(ROUTE, ROUTE)
T.check(not paused and not mp.held(), 'the page opened during the move: not paused until it is done')
moving = false
mp.update()
T.check(paused and mp.held(), 'and paused once it is')
mp.uiState('play', ROUTE)
mp.waitFor = function() return false end

-- (#63) every request of ours in now, by id, for the log of game time under them
T.check(mp.heldIds() == nil, 'nothing held: no ids')
mp.uiState(ROUTE, ROUTE)
mp.card('earthRally_ask', true)
local ids = mp.heldIds()
T.check(ids and table.concat(ids, ',') == 'earthRally_ask,earthRally_menu', 'the page and a card held: both ids')
mp.card('earthRally_ask', false)
mp.uiState('play', ROUTE)
T.check(mp.heldIds() == nil, 'all taken back: no ids')

-- no request stack (an older game): the page opens, nothing paused, nothing thrown
simTimeAuthority = nil
mp.uiState(ROUTE, ROUTE)
T.check(not mp.held(), 'no simTimeAuthority: nothing held')
mp.uiState('play', ROUTE)

T.done('test_menu_pause')
