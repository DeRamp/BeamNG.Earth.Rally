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
local M = {}

M.REQUEST_ID = 'earthRally_menu'

local held = false

-- The game's simTimeAuthority, when it has the request stack (0.40); nil otherwise (then the menu just does not pause).
local function sta()
  local s = rawget(_G, 'simTimeAuthority')
  if type(s) == 'table' and type(s.pushPauseRequest) == 'function' and type(s.popPauseRequest) == 'function' then
    return s
  end
  return nil
end

function M.held() return held end

-- The UI state changed (main.onUiChangedState): our page up, a request in; anything else, ours taken back.
function M.uiState(toState, ourRoute)
  local want = toState ~= nil and toState == ourRoute
  if want == held then return end
  local s = sta()
  if not s then return end
  if want then
    held = true
    pcall(s.pushPauseRequest, M.REQUEST_ID)
  else
    M.release()
  end
end

-- Our request taken back, if there is one: on leaving the page, and when the level goes or the mod is switched off
-- with the page up (a request left behind would hold the next level paused).
function M.release()
  if not held then return end
  held = false
  local s = sta()
  if s then pcall(s.popPauseRequest, M.REQUEST_ID) end
end

return M
