-- earthRally/menuPause: the game paused while the menu page is up (1.6.2, #13), the way the game's own pause menu does
-- it in 0.40 (ui/pause/routeLifecycleCallbacks.lua: simTimeAuthority.pushPauseRequest('ui_pause_home_tab') on the way
-- in, popPauseRequest on the way out; the livery editor does the same).
--
-- Why a pause REQUEST and not simTimeAuthority.pause(true) / pause(false): the request stack remembers whether the
-- game was already paused when the first request came in (wasPausedBeforePushRequest) and only unpauses when the last
-- request goes AND it was not. So:
--   - a game the player paused themselves (J) before opening the menu stays paused when it closes
--   - the Escape menu's own request and ours can overlap (pause > Earth Rally tab > our page, in either order of their
--     leave and our enter) without one unpausing under the other
--   - nothing of ours unpauses a game we did not pause
--
-- The stage clock: the runner's clocks (the stage time, the rally clock, the countdown) all run on game time (dtSim,
-- runner.update), so they stop with the physics, exactly as they already do under the Escape menu. Pausing gains the
-- player nothing on the clock: the car is frozen with it.
--
-- earthMenuFix (the stopgap about BeamNG.Earth's strips over the pause menu) is not touched by this: it works on UI
-- states, and a pause changes no UI state.
--
-- held: we have a request in. Kept so a push is never doubled and a pop never sent for a request we did not make.
-- pageUp: our page is the UI state now. suspended: an action that moves the car or loads the world (auto recce, recce,
-- go to start, run stage) was started from the page: our request taken back and not put in again until the page is
-- next opened -- BeamNG.Earth's own holds (the drop hold, a generation swap: simhold.pause) take the game's plain
-- pause only when it is not paused already, so with ours in they take none, and closing the page would run the
-- physics in the middle of their hold.
-- M.holding: BeamNG.Earth holding the game itself (earthAdapter.holding, set by main.lua): our request waits until
-- it is over (M.update), for the same reason.
local M = {}

M.REQUEST_ID = 'earthRally_menu'
M.holding = function() return false end

local held, pageUp, suspended = false, false, false

-- The game's simTimeAuthority, when it has the request stack (0.40); nil otherwise (then the menu just does not pause).
local function sta()
  local s = rawget(_G, 'simTimeAuthority')
  if type(s) == 'table' and type(s.pushPauseRequest) == 'function' and type(s.popPauseRequest) == 'function' then
    return s
  end
  return nil
end

local function earthHolds()
  local ok, h = pcall(M.holding)
  return ok and h == true
end

-- Our request put in, if the page wants one and nothing above says to wait.
local function take()
  if held or not pageUp or suspended or earthHolds() then return end
  local s = sta()
  if not s then return end
  held = true
  pcall(s.pushPauseRequest, M.REQUEST_ID)
end

function M.held() return held end
function M.suspended() return suspended end

-- The UI state changed (main.onUiChangedState): our page up, a request in; anything else, ours taken back.
function M.uiState(toState, ourRoute)
  local want = toState ~= nil and toState == ourRoute
  if not want then M.release() return end
  pageUp = true
  take()
end

-- Every frame (main.onUpdate): a request held back while BeamNG.Earth held the game, put in once its hold is over.
function M.update()
  if pageUp and not held and not suspended then take() end
end

-- An action that moves the car or loads the world started from the page: our request taken back until the page is
-- next opened.
local function pop()
  if not held then return end
  held = false
  local s = sta()
  if s then pcall(s.popPauseRequest, M.REQUEST_ID) end
end
function M.suspend()
  if pageUp then suspended = true end
  pop()
end

-- (1.7.0, #43) A pause request of its own for a card over driving (the stage's finish card at the stop box): held
-- while on is true, taken back when false. Not while BeamNG.Earth holds the game (its holds take the plain pause
-- only when it is not paused already).
local cards = {}
function M.card(id, on)
  local s = sta()
  if not s then return end
  if on and not cards[id] and not earthHolds() then
    cards[id] = true
    pcall(s.pushPauseRequest, id)
  elseif not on and cards[id] then
    cards[id] = nil
    pcall(s.popPauseRequest, id)
  end
end
function M.cardHeld(id) return cards[id] == true end

-- Our request taken back, if there is one, and the page taken for closed: on leaving the page, and when the level
-- goes, the mod is switched off or reloaded with the page up (a request left behind would hold the next level paused,
-- and every Escape menu after it).
function M.release()
  pageUp, suspended = false, false
  pop()
end
-- Everything taken back: the level going, the mod off or reloaded.
function M.releaseAll()
  M.release()
  for id in pairs(cards) do M.card(id, false) end
end

return M
