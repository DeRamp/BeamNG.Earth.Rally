-- STOPGAP for a BeamNG.Earth bug: remove this file (and its calls in main.lua) once BeamNG.Earth hides its imgui
-- drawing on the pause menu itself. docs/notes-1.5.1.md, "Earth's strips over the pause menu", says how to tell and
-- what to remove.
--
-- The bug (BeamNG.Earth dev 2026-11-14, BeamNG.drive 0.40): Escape opens the game's route 'pause'. Its route meta says
-- `uiApps: { shown: false }`, and the game's UiAppsOverlay.vue takes the apps away with v-if, so BeamNG.Earth's status
-- strip, banner and credits apps are destroyed. BeamNG.Earth then draws the same things with imgui (core.lua: `if not
-- hudapps.mounted('status') then statusbar.draw(...)`), and imgui is drawn over the game's HTML UI -- the download
-- line ("Loading 64% | downloading 14 files ...") over the menu. Its imgui drawing does step aside for a menu, through
-- credits.hiddenByUi(), but the state test behind it (credits.lua setUiState) is `toState:sub(1, 4) == 'menu'`: in
-- 0.40 'menu' is the main menu, and the in-game Escape menu is 'pause' / 'pause.*', which it never matches.
--
-- The stopgap corrects that one test from outside: on a state BeamNG.Earth should have hidden for, its own
-- setUiState is told 'menu', the state it was written for. Everything else is BeamNG.Earth's own behaviour: its strips,
-- banner, credits and update notices all hide behind hiddenByUi(), as its credits.lua header says they should in the
-- pause menu, and the next state change (back to 'play') puts it right by itself -- nothing of ours is left set if
-- this goes wrong, or if Earth Rally goes away mid-menu.
--
-- Also our own menu page ('earthRally'): opened from the pause menu's Earth Rally tab it comes straight from 'pause',
-- with the apps still taken away, and BeamNG.Earth cannot know our route's name.
local M = {}

-- pause sub-pages where the game keeps the UI apps on screen (their meta says shown: true): the HUD-apps editor and
-- photo mode's overlay editor. BeamNG.Earth's apps are really there, so they are left alone.
M.APPS_SHOWN = { 'pause.hudApps', 'pause.photomode.overlay.edit' }

local pending = false   -- told once in onUiChangedState; told again next frame (BeamNG.Earth's hook may run after ours)

-- The in-game Escape menu, less the sub-pages that show the apps.
function M.isPause(toState)
  if type(toState) ~= 'string' or not (toState == 'pause' or toState:sub(1, 6) == 'pause.') then return false end
  for _, p in ipairs(M.APPS_SHOWN) do
    if toState == p or toState:sub(1, #p + 1) == p .. '.' then return false end
  end
  return true
end

-- A state BeamNG.Earth's imgui drawing should step aside for, and does not know about.
function M.hides(toState, ourRoute)
  return M.isPause(toState) or (ourRoute ~= nil and toState == ourRoute)
end

-- BeamNG.Earth's credits module, only if it is already loaded (never loaded on its behalf). nil when absent or changed.
local function setUiState()
  local c = package.loaded['beamngEarth/credits']
  if type(c) == 'table' and type(c.setUiState) == 'function' then return c.setUiState end
  return nil
end

local function tell()
  local f = setUiState()
  if f then pcall(f, 'menu') end
end

function M.uiState(toState, ourRoute)
  pending = M.hides(toState, ourRoute)
  if pending then tell() end
end

-- Every frame: the second telling, once.
function M.update()
  if not pending then return end
  pending = false
  tell()
end

return M
