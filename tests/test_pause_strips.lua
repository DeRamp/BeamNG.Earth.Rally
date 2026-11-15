-- pauseStrips (a stopgap for BeamNG.Earth drawing its imgui strips over the pause menu): what it holds, for how
-- long, and what it gives back -- against a stand-in of BeamNG.Earth's mount flag, which is one boolean per strip.
local T = dofile(TESTS .. '/testlib.lua')
function log() end

local mounted = {}      -- BeamNG.Earth's hudapps: name -> true
beamngEarth_core = { hudApp = function(name, on)
  if name ~= 'status' and name ~= 'banner' and name ~= 'credits' then return false end
  mounted[name] = on and true or nil
  return on and true or false
end }
package.loaded['beamngEarth/hudapps'] = { mounted = function(n) return mounted[n] == true end }

local earth = require('earthRally/earthAdapter')
local ps = require('earthRally/pauseStrips')
local calls = {}
local realHold = earth.holdStrips
earth.holdStrips = function(on, names)
  calls[#calls + 1] = { on = on, names = names and table.concat(names, ',') or 'all' }
  return realHold(on, names)
end

local function frames(n, dt) for _ = 1, n do ps.update(dt or 0.1, earth) end end
local function app(name, on) beamngEarth_core.hudApp(name, on) end   -- what BeamNG.Earth's app.js says

T.check(ps.isPause('pause') and ps.isPause('pause.vehicle') and not ps.isPause('menu') and not ps.isPause('play')
  and not ps.isPause('pauseX') and not ps.isPause(nil), 'isPause: pause and its sub-pages only')
T.check(earth.stripMounted('status') == false, 'stripMounted reads BeamNG.Earth\'s flag')

-- 1. Free roam, BeamNG.Earth's apps in the layout: Escape takes them down, the hold covers it, they come back.
do
  ps.reset(); mounted = {}; calls = {}
  app('status', true); app('banner', true); app('credits', true)
  frames(5)
  app('status', false); app('banner', false); app('credits', false)   -- the pause route destroys the apps
  frames(1)                                                           -- (a frame before the state change)
  ps.uiState('pause')
  frames(3)
  T.check(mounted.status and mounted.banner, 'pause: status and banner held, so no imgui fallback')
  T.check(not mounted.credits, 'pause: the credits are never ours to hold')
  ps.uiState('pause.environment'); frames(2)
  T.check(ps._holding() and mounted.status, 'a pause sub-page: still held')
  ps.uiState('play')
  app('status', true); app('banner', true); app('credits', true)     -- the apps come back and say so
  frames(10)
  T.check(ps._holding(), 'closed: the hold stays on through AFTER_S')
  calls = {}
  frames(40)
  T.check(not ps._holding(), 'after AFTER_S: the hold is over')
  local gaveBack = false
  for _, c in ipairs(calls) do if c.on == false then gaveBack = true end end
  T.check(not gaveBack and mounted.status and mounted.banner,
    'strips that were on screen before are not given back (that would clobber the apps\' own true)')
end

-- 2. A layout without BeamNG.Earth's apps (its imgui strips were drawn): those are given back, and only those.
do
  ps.reset(); mounted = {}; calls = {}
  app('banner', true)          -- banner app in the layout, status drawn by imgui
  frames(5)
  app('banner', false)
  ps.uiState('pause'); frames(3)
  T.check(mounted.status and mounted.banner, 'pause: both held')
  ps.uiState('play'); app('banner', true)
  frames(50)
  local last = calls[#calls]
  T.check(last and last.on == false and last.names == 'status', 'only the strip that had no app is given back')
  T.check(not mounted.status and mounted.banner, 'imgui status bar back, banner app untouched')
end

-- 3. The pause opened again inside AFTER_S: one hold, still measured from the first pause.
do
  ps.reset(); mounted = {}; calls = {}
  frames(5)                                 -- nothing on screen (another layout)
  ps.uiState('pause'); frames(2)
  ps.uiState('play'); frames(10)
  ps.uiState('pause'); frames(2)
  T.check(ps._holding() and mounted.status, 'reopened: held')
  ps.uiState('play'); frames(50)
  T.check(not ps._holding() and not mounted.status and not mounted.banner, 'both given back at the end')
end

-- 4. A stage under the pause: its hold (runner, after us in the frame) wins; we give nothing back over it.
do
  ps.reset(); mounted = {}; calls = {}
  local stage = true
  local function frame()
    ps.update(0.1, earth)
    if stage then earth.holdStrips(true) end   -- runner.update's per-frame hold
  end
  for _ = 1, 5 do frame() end
  ps.uiState('pause'); for _ = 1, 5 do frame() end
  ps.uiState('play'); for _ = 1, 60 do frame() end
  T.check(mounted.status and mounted.banner, 'stage: strips still held after the pause hold ends')
  -- the stage ends while paused: layoutOff gives them back, the pause hold takes them again next frame
  ps.uiState('pause'); frame()
  stage = false; earth.holdStrips(false)
  frame()
  T.check(mounted.status and mounted.banner, 'stage ended in the pause menu: still held while it is up')
end

-- 5. reset() (level end, unload) forgets the hold without calling BeamNG.Earth.
do
  ps.reset(); mounted = {}; calls = {}
  ps.uiState('pause'); frames(2)
  calls = {}
  ps.reset(); frames(5)
  T.check(not ps._holding() and #calls == 0, 'reset: nothing held, nothing called (the caller gave the strips back)')
end

-- 6. No BeamNG.Earth: nothing throws.
do
  local saved = beamngEarth_core
  beamngEarth_core = nil
  package.loaded['beamngEarth/hudapps'] = nil
  ps.reset()
  local ok = pcall(function() frames(3); ps.uiState('pause'); frames(3); ps.uiState('play'); frames(60) end)
  T.check(ok and earth.stripMounted('status') == nil, 'no BeamNG.Earth: quiet')
  beamngEarth_core = saved
end

T.done('test_pause_strips')
