-- earthRally/gameTile: an "Earth Rally" tile on the game's own Rally page (Play > Rally, route menu.rallySelector), so
-- the menu opens from the main menu without going into free roam first (the owner, 2026-11-18).
--
-- The Rally page is the game's gameplay selector with a filter on it: only tiles whose `type` is the translated
-- "Rally Stage" or "Rally Loop" label show (0.40.5 ui/gameplaySelector/general.lua, GAMEPLAY_ROUTE_PRESETS). Its tiles
-- come from every extension answering onGameplaySelectorGetTiles, and a tile's details panel and buttons from
-- onGameplaySelectorGetDetails -- the hooks the game's own campaign and mission tiles use. main.lua answers both
-- and calls this.
--
--   M.tiles(items, backend, tr)                     our tile added to items (the gameplay selector only)
--   M.details(item, details, buttons, backend, open) our details panel, for our tile only; open() opens the menu
local M = {}

M.KEY = 'earthRally'
M.NAME = 'Earth Rally'
M.PREVIEW = '/ui/modules/apps/earthRally/tile.jpg'
M.TYPE_LABEL = 'bigMap.missionLabels.rallyStage'   -- (what puts it on the Rally page: its filter's own value)
M.ORDER = -1e12                                     -- (first among the game's rally stages: theirs are -date)
M.DESCRIPTION = 'Real rally stages on real roads, on BeamNG.Earth\'s map of the world. Pick a rally or a stage: ' ..
  'BeamNG.Earth loads when you drive.'

function M.tiles(items, backend, tr)
  if type(items) ~= 'table' or type(backend) ~= 'table' or backend.backendName ~= 'gameplaySelector' then return end
  tr = tr or function(k) return k end
  local item = {
    key = M.KEY,
    name = M.NAME,
    preview = M.PREVIEW,
    favouriteIdx = 0,
    showFavouriteIconPercent = 0,
    showDetails = { earthRally = true, key = M.KEY },
    system = 'challenges',
    type = tr(M.TYPE_LABEL),
    level = 'BeamNG.Earth',
    sourceIcons = { { icon = 'puzzleModule' } },
    order = M.ORDER,
    validBackends = { gameplaySelector = true },
  }
  items[#items + 1] = item
  return item
end

function M.details(item, details, buttons, backend, open)
  if type(item) ~= 'table' or not item.earthRally or type(details) ~= 'table' then return end
  if not (buttons and buttons.addButton) then return end
  local fav = false
  if backend and backend.isFavourite then
    local ok, f = pcall(backend.isFavourite, M.KEY)
    fav = ok and f == true
  end
  details[#details + 1] = {
    headerTitle = M.NAME,
    description = M.DESCRIPTION,
    preview = M.PREVIEW,
    isFavourite = fav,
    specifications = { {
      { icon = 'flag', label = 'Map', value = 'BeamNG.Earth' },
      { icon = 'info', label = 'Needs', value = 'BeamNG.Earth\'s launcher running (its world server)' },
    } },
    tags = { { icon = 'puzzleModule', label = 'Earth Rally mod' } },
    buttonInfo = {
      buttons.addButton(function()
        if backend and backend.trackRecent then pcall(backend.trackRecent, M.KEY) end
        if open then open() end
      end, {
        label = 'Open Earth Rally',
        icon = 'flag',
        primary = true,
        isDoubleClickAction = true,
      }),
    },
  }
end

return M
