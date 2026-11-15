-- STOPGAP for a BeamNG.Earth bug: remove this file (and its three calls in main.lua) once BeamNG.Earth hides its own
-- strips on the pause menu. docs/notes-1.4.1.md, "Earth's strips over the pause menu", says how to tell.
--
-- The bug (BeamNG.Earth dev 2026-11-14, BeamNG.drive 0.40): pressing Escape opens the game's route 'pause'. Its route
-- meta says `uiApps: { shown: false }`, and the game's UiAppsOverlay.vue takes the apps away with v-if, so every UI app
-- is destroyed -- BeamNG.Earth's status strip, banner and credits with them. Each says hudApp(name, false) as it goes,
-- and BeamNG.Earth then draws the same thing with imgui instead (its core.lua: `if not hudapps.mounted('status') then
-- statusbar.draw(...)`), on top of the menu, because imgui is drawn over the game's HTML UI. Its imgui drawing is meant
-- to step aside for a menu, but its check (credits.lua setUiState) is `toState:sub(1, 4) == 'menu'`: in 0.40 'menu' is
-- the main menu, and the in-game Escape menu is 'pause' / 'pause.*', which it never matches. So the download line
-- ("Loading 64% | downloading 14 files ...") and the connection banner sit over the pause menu.
--
-- The stopgap: while the pause menu is up, tell BeamNG.Earth its status and banner apps are on screen
-- (earthAdapter.holdStrips, the same internal call a stage already makes), so it leaves its imgui drawing out. The
-- data credits are not touched, by Earth Rally's rule that their attribution never has an off switch of ours, so
-- they may still show over the menu until BeamNG.Earth's own fix.
--
-- Giving them back is the careful part. BeamNG.Earth's mount flag is one boolean per strip, not a count, so a
-- hudApp(name, false) from us after its apps came back with the menu's closing would mark them gone again -- and it
-- would draw its imgui strip over its own app until the app's next hello (every 3 s, its app.js). So:
--   * the hold stays on AFTER_S after the menu closes, longer than that hello, so the apps have said they are back;
--   * then only the strips that were NOT on screen before the menu opened are given back. The ones that were have
--     their apps back and saying so, and giving those back would be the clobbering above.
-- "On screen before" is any frame of the last SEEN_S before the pause: the apps are destroyed when the router swaps
-- routes, which can land a frame or so ahead of the onUiChangedState that tells us about it.
local M = {}

M.AFTER_S = 4.0     -- s the hold stays on after the pause menu closes (BeamNG.Earth's apps say hello every 3 s)
M.SEEN_S = 1.0      -- a strip on screen this recently before the pause counts as on screen

local paused = false    -- the pause menu is up (onUiChangedState)
local holding = false   -- we are holding the strips for it
local after = nil       -- s of the hold left once the menu has closed
local heldFrom = nil    -- clock when the hold began
local clock = 0
local seenAt = {}       -- strip name -> clock when BeamNG.Earth last had it on screen, while we were not holding

-- The game's in-game Escape menu: 'pause' and its sub-pages ('pause.vehicle', 'pause.environment', ...).
function M.isPause(toState)
  return type(toState) == 'string' and (toState == 'pause' or toState:sub(1, 6) == 'pause.')
end

function M.uiState(toState) paused = M.isPause(toState) end

-- Every frame, before the runner (whose stage hold then re-asserts in the same frame if a stage wants the strips).
-- earth: earthAdapter (holdStrips, stripMounted, EARTH_STRIPS).
function M.update(dt, earth)
  clock = clock + (dt or 0)
  if paused then
    if not holding then heldFrom = clock end
    holding, after = true, M.AFTER_S
    earth.holdStrips(true)
    return
  end
  if not holding then
    for _, n in ipairs(earth.EARTH_STRIPS) do
      if earth.stripMounted(n) then seenAt[n] = clock end
    end
    return
  end
  after = after - (dt or 0)
  if after > 0 then earth.holdStrips(true) return end
  local give, since = {}, heldFrom - M.SEEN_S
  for _, n in ipairs(earth.EARTH_STRIPS) do
    if not (seenAt[n] and seenAt[n] >= since) then give[#give + 1] = n end
  end
  if #give > 0 then earth.holdStrips(false, give) end
  holding, after, heldFrom = false, nil, nil
end

-- Forgotten, not given back: the unload / level-end paths give every strip back themselves (holdStrips(false)).
function M.reset()
  paused, holding, after, heldFrom, clock, seenAt = false, false, nil, nil, 0, {}
end

M._holding = function() return holding end

return M
