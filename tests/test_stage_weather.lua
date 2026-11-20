-- (plan G) Weather on Drive stage: the pick (hidden setting stageWeather), Rally day from the pass the stage page
-- shows, BeamNG.Earth's presets, set through earthAdapter.setScene with no clock and given back only when it set it.
local T = dofile(TESTS .. '/testlib.lua')
function log() end

-- a BeamNG.Earth with the two hooks (as earthAdapter checks them)
local preset, clock = nil, nil
beamngEarth_sky = { setServerClock = function(c) clock = c return c end, serverClock = function() return clock end }
-- (as BeamNG.Earth's weather.lua: setPreset(nil) keeps the preset's message as lastMsg until a real one comes;
--  onWeather takes a real message only with no preset set)
local lastMsg = { code = 1, real = true, utcOffsetS = 28800, lat = -34, lon = 116 }
beamngEarth_weather = {
  PRESETS = { clear = { code = 0 }, rain = { code = 63 }, fog = { code = 45 } },
  setPreset = function(n)
    local m = n and beamngEarth_weather.PRESETS[n] or nil
    preset = m and n or nil
    if m then lastMsg = m end
    return m ~= nil
  end,
  preset = function() return preset end,
  current = function() return lastMsg end,
  onWeather = function(m) if not preset then lastMsg = m end end,
}

local settings = require('earthRally/settings')
settings.reset()
local sw = require('earthRally/stageWeather')
local e = { id = 'ev', itinerary = { { ss = 'SS1', weather = { code = 61, tempC = 9 } }, { ss = 'SS5' } } }
local stage = { id = 'quarry' }

T.check(sw.pick() == 'current', 'the default: Current')
T.check(sw.apply(e, stage) == false and preset == nil and clock == nil, 'Current: nothing set')

-- Rally day: the shown pass's stored weather
T.check(sw.pagePass('ev', 'quarry', { board = { pass = 'SS1' } }) == 'SS1', 'the leaderboard\'s pass is the page\'s')
settings.set('stageWeather', 'rallyday')
T.check(sw.apply(e, stage) and preset == 'earthrally' and beamngEarth_weather.PRESETS.earthrally.code == 61
  and clock == nil, 'Rally day: that pass\'s weather, no clock')
T.check(sw.giveBack() and preset == nil and beamngEarth_weather.PRESETS.earthrally == nil, 'given back')
T.check(lastMsg.real == true and lastMsg.code == 1, 'the real weather back at once, not at the next real message')
T.check(lastMsg.utcOffsetS == nil and lastMsg.lat == nil, 'handed back without its time zone and place')
-- a preset's message left as current is never kept as the real one
lastMsg = { code = 95, preset = 'storm' }
settings.set('stageWeather', 'rallyday')
sw.apply(e, stage)
T.check(beamngEarth_weather.PRESETS.earthrally.earthRallyReal == nil, 'a preset message is not the real weather')
sw.giveBack()
lastMsg = { code = 1, real = true }
T.check(sw.giveBack() == false, 'given back once')
-- a pass with none stored: as Current
sw.pagePass('ev', 'quarry', { board = { pass = 'SS5' } })
T.check(sw.apply(e, stage) == false and preset == nil, 'Rally day on a pass with none: nothing set')
-- no board, one pass: that pass
T.check(sw.pagePass('ev', 'quarry', { passes = { { ss = 'SS1' } } }) == 'SS1', 'no board, one pass: that one')

-- a preset, copied into our own entry
settings.set('stageWeather', 'fog')
T.check(sw.apply(e, stage) and preset == 'earthrally' and beamngEarth_weather.PRESETS.earthrally.code == 45,
  'Fog: BeamNG.Earth\'s preset, as ours')
T.check(beamngEarth_weather.PRESETS.earthrally ~= beamngEarth_weather.PRESETS.fog, 'a copy, not their table')
-- set again over ours (a restart): the real weather kept from before the first
settings.set('stageWeather', 'clear')
T.check(sw.apply(e, stage) and beamngEarth_weather.PRESETS.earthrally.code == 0
  and beamngEarth_weather.PRESETS.earthrally.earthRallyReal.real == true, 'set again: the real weather still kept')
T.check(table.concat(sw.presets(), ' ') == 'clear rain fog', 'the row offers only the presets this BeamNG.Earth has')
settings.set('stageWeather', 'fog')
-- a preset this BeamNG.Earth lacks: nothing
settings.set('stageWeather', 'snow')
T.check(sw.apply(e, stage) == false and preset == nil, 'a preset not there: the last given back, nothing set')

-- a server's weather (BeamMP) is left alone
preset = 'storm'
settings.set('stageWeather', 'rain')
T.check(sw.apply(e, stage) == false and preset == 'storm', 'someone else\'s weather: left')
preset = nil

-- a rally under way owns it: not cleared by a run's tidy
T.check(sw.apply(e, stage) and sw.isOn(), 'Rain set')
package.loaded['earthRally/rallyRun'] = { active = function() return { pos = 1, order = { {} } } end }
T.check(sw.giveBack() == false and preset == 'earthrally' and not sw.isOn(), 'a rally running: its weather left')
-- a finished rally kept until quit is not under way: given back
T.check(sw.apply(e, stage), 'Rain set again')
package.loaded['earthRally/rallyRun'] = { active = function() return { done = true, pos = 1, order = {} } end }
T.check(sw.giveBack() and preset == nil, 'a finished rally: given back')
package.loaded['earthRally/rallyRun'] = nil

-- Rally day with no page shown since a reload: the pass the page would show
sw._reset()
package.loaded['earthRally/menu'] = { stage = function() return { board = { pass = 'SS1' } } end }
settings.set('stageWeather', 'rallyday')
T.check(sw.apply(e, stage) and beamngEarth_weather.PRESETS.earthrally.code == 61, 'Rally day, page never opened: SS1')
sw.giveBack()
package.loaded['earthRally/menu'] = nil

-- an unknown saved value reads as Current
sw._reset()
T.check(settings.set('stageWeather', 'hail').ok == false, 'not a pick: refused')

-- (notes-rally-loop 1) BeamNG.Earth in Manual: put in Real while ours is set, the player's mode (and time) back after
do
  local skyMode, wxMode, todSet, fog = 'manual', 'manual', nil, 0.001
  beamngEarth_sky.getMode = function() return skyMode end
  beamngEarth_sky.setMode = function(m) skyMode = m end
  beamngEarth_weather.getMode = function() return wxMode end
  beamngEarth_weather.setMode = function(m) wxMode = m end
  core_environment = { getTimeOfDay = function() return { time = 0.25, play = false } end,
    setTimeOfDay = function(t) todSet = t end, getFogDensity = function() return fog end,
    setFogDensity = function(v) fog = v end }
  local ea = require('earthRally/earthAdapter')
  T.check(ea.setScene({ hours = 17 }, { code = 63 }) and skyMode == 'real' and wxMode == 'real',
    'Manual: sky and weather in Real while ours is set')
  T.check(ea.setScene({ hours = 18 }, { code = 0 }) and clock.earthRallyMode == 'manual'
    and beamngEarth_weather.PRESETS.earthrally.earthRallyMode == 'manual', 'set again: the Manual kept, not our Real')
  fog = 0.05                 -- (the stage's fog, written by BeamNG.Earth in Real)
  T.check(ea.clearScene() and skyMode == 'manual' and wxMode == 'manual' and todSet and todSet.time == 0.25,
    "given back: Manual again, the player's time of day back")
  T.check(fog == 0.001, "given back: the player's own fog back (" .. tostring(fog) .. ')')
  skyMode, wxMode, todSet = 'real', 'real', nil
  ea.setScene({ hours = 17 }, { code = 63 })
  ea.clearScene()
  T.check(skyMode == 'real' and wxMode == 'real' and todSet == nil, 'Real: left Real, the time not touched')
  core_environment = nil
end

T.done('test_stage_weather')
