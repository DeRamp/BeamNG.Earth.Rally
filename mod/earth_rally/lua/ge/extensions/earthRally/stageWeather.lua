-- (plan G) Weather on Drive stage: the stage page's Weather row. The pick is kept in the hidden setting stageWeather:
--   'current'  BeamNG.Earth's weather as it is: nothing set (the default)
--   'rallyday' the weather stored in the pack for the pass the stage page shows (its leaderboard's pass, or the
--              stage's only pass); with none stored there, as 'current'
--   'clear' | 'cloudy' | 'rain' | 'storm' | 'snow' | 'fog'  BeamNG.Earth's own presets (beamngEarth_weather.PRESETS)
-- Set as a single stage loads (runner.start, not in a rally: a rally sets its own, plan E) through the same hook as
-- the rally's weather (earthAdapter.setScene, the weather only: no clock), given back when the run ends or is left.

local M = {}

local earth = require('earthRally/earthAdapter')
local settings = require('earthRally/settings')

-- (the picks and their order: settings.lua's stageWeather; the row's words: EarthRally.vue's WX_PICKS)
M.PRESET_ORDER = { 'clear', 'cloudy', 'rain', 'storm', 'snow', 'fog' }
M.PRESETS = { clear = true, cloudy = true, rain = true, storm = true, snow = true, fog = true }

-- (the pass the stage page last showed, per stage: Rally day's weather is that pass's)
local shown = {}
local on = false

local function key(eventId, stageId) return tostring(eventId) .. '/' .. tostring(stageId) end

-- The stored weather of pass `ss` in event e's itinerary (BeamNG.Earth's weather message), or nil.
function M.passWeather(e, ss)
  if not (e and ss) then return nil end
  for _, p in ipairs(type(e.itinerary) == 'table' and e.itinerary or {}) do
    if tostring(p.ss) == tostring(ss) and type(p.weather) == 'table' then return p.weather end
  end
  return nil
end

-- The pass the stage page shows: the leaderboard's, else the stage's only pass. Kept for runner.start, and returned.
function M.pagePass(eventId, stageId, out)
  local ss = out and out.board and out.board.pass or nil
  if not ss and out and type(out.passes) == 'table' and #out.passes == 1 then ss = out.passes[1].ss end
  shown[key(eventId, stageId)] = ss
  return ss
end

-- BeamNG.Earth's presets this BeamNG.Earth has (the row offers only these), in the row's order.
function M.presets()
  local wx = rawget(_G, 'beamngEarth_weather')
  local out = {}
  for _, p in ipairs(M.PRESET_ORDER) do
    if type(wx) == 'table' and type(wx.PRESETS) == 'table' and type(wx.PRESETS[p]) == 'table' then out[#out + 1] = p end
  end
  return out
end

function M.pick()
  local p = settings.get('stageWeather')
  return (p == 'rallyday' or M.PRESETS[p]) and p or 'current'
end

-- The weather message to set for this stage, or nil (leave BeamNG.Earth's own).
function M.msgFor(e, stage)
  local p = M.pick()
  if p == 'rallyday' then
    local k = key(e and e.id, stage and stage.id)
    if shown[k] == nil and e and stage then
      -- (a run started without the stage page open since the last Lua reload -- a results card's Next, a Route to
      --  start: the pass the page would show, worked out the same way)
      local okM, out = pcall(function() return require('earthRally/menu').stage(e.id, stage.id) end)
      if okM and out then M.pagePass(e.id, stage.id, out) end
    end
    return M.passWeather(e, shown[k])
  elseif M.PRESETS[p] then
    local wx = rawget(_G, 'beamngEarth_weather')
    local m = type(wx) == 'table' and type(wx.PRESETS) == 'table' and wx.PRESETS[p] or nil
    return type(m) == 'table' and m or nil
  end
  return nil
end

-- Set as a single stage's run starts. Returns true when something was set.
function M.apply(e, stage)
  M.giveBack()
  local msg = M.msgFor(e, stage)
  if not msg then return false end
  local ok, set, why = pcall(earth.setScene, nil, msg)
  if ok and set then
    on = true
    log('I', 'earthRally', 'stage weather: ' .. M.pick())
    return true
  end
  log('W', 'earthRally', 'stage weather not set (' .. tostring(ok and why or set) .. ')')
  return false
end

-- Given back (the run ended or was left). Only what this set.
function M.giveBack()
  if not on then return false end
  on = false
  -- (a rally under way owns the clock and weather now: rallyRun.setWorld set its own, left alone)
  -- (a finished rally kept until quit is not under way)
  local rr = package.loaded['earthRally/rallyRun']
  local R = rr and rr.active and rr.active()
  if R and not require('earthRally/rally').over(R) then return false end
  pcall(earth.clearScene)
  return true
end

function M.isOn() return on end

-- (tests)
function M._reset() shown, on = {}, false end

return M
