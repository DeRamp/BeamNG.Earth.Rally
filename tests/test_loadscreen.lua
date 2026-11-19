-- loadScreen (1.7.0, #49 / #40): the menu page's loading screen -- its steps, the world gate at the setting's share,
-- the Continue button, a failure, the world read from BeamNG.Earth's load counts.
local T = dofile(TESTS .. '/testlib.lua')
function log() end

-- BeamNG.Earth: ready, and its core state's load counts round the car
local ready, lp, anchorId = true, nil, 4
beamngEarth_api = { ready = function() return ready end }
beamngEarth_core = { _state = function() return { loadProgress = lp, anchorId = anchorId } end }

local earth = require('earthRally/earthAdapter')
local settings = require('earthRally/settings')
local ls = require('earthRally/loadScreen')
settings.reset()

-- the world share
lp = { anchorId = 4, ground = { 1, 1 }, roads = { 30, 60 }, trees = { 9, 39 }, far = { 1, 500 } }
T.check(earth.worldLoaded() == 40, 'world: ground, roads and trees counted, the far ring left out (40%)')
lp.anchorId = 3
T.check(earth.worldLoaded() == 0, 'world: counts from before the teleport (another anchor) are not used')
ready = false
lp.anchorId = 4
T.check(earth.worldLoaded() == 0, 'world: nothing until BeamNG.Earth is ready')
ready = true
lp = nil
T.check(earth.worldLoaded() == nil and ls.world() == 100, 'world: no counts from this BeamNG.Earth: ready() alone')

-- a screen: steps, then the world at the setting's share
local step, ended = 1, nil
lp = { anchorId = 4, ground = { 1, 1 }, roads = { 10, 100 }, trees = { 0, 0 } }
ls.begin({ title = 'Going to Service A', steps = { 'The map', 'Your car' },
  probe = function() return step end, done = function(ok, why) ended = { ok = ok, why = why } end })
ls.update(0.1)
local ui = ls.ui()
T.check(ui and #ui.steps == 3 and ui.steps[1].state == 'now' and ui.steps[3].world and ui.need == 60,
  'the steps, the world last at the default 60%')
step = 3
ls.update(0.1)
T.check(ls.active() and not ended and ls.ui().steps[3].state == 'now', 'the steps done: waits for the world (11%)')
lp.roads = { 70, 100 }
ls.update(0.1)
T.check(ended and ended.ok and not ls.active(), 'the world at 71%: done')

-- the setting moves the gate
settings.reset()
local okSet = settings.validate('worldLoaded', 80)
T.check(okSet == 80 and settings.validate('worldLoaded', 55) == nil, 'the setting: 40-90 in tens')

-- the time control card: waits for Continue
ended = nil
ls.begin({ title = 'SS2', steps = { 'a' }, button = 'Continue', probe = function() return 2 end,
  done = function(ok) ended = ok end })
ls.update(0.1)
T.check(ls.ui().ready and not ended, 'ready: waits for Continue')
T.check(ls.continue() and ended == true and not ls.active(), 'Continue ends it')

-- a failure ends it at once
ended = nil
ls.begin({ title = 'x', steps = { 'a' }, probe = function() return 1, nil, nil, 'the run was stopped' end,
  done = function(ok, why) ended = { ok = ok, why = why } end })
ls.update(0.1)
T.check(ended and ended.ok == false and ended.why == 'the run was stopped', 'a failure ends it with the reason')

-- the world never gets there: let go after WORLD_WAIT_S
ended = nil
lp.roads = { 0, 100 }
ls.begin({ title = 'y', steps = {}, probe = function() return 1 end, done = function(ok) ended = ok end })
ls.update(1)
T.check(not ended, 'the world at 1%: waiting')
ls.update(ls.WORLD_WAIT_S + 1)
T.check(ended == true, 'let go after WORLD_WAIT_S anyway')

-- the page closed while the time control card is still loading: it ends by itself once ready (#40)
ended = nil
lp.roads = { 100, 100 }
local stp = 1
ls.begin({ title = 'z', steps = { 'a' }, button = 'Continue', probe = function() return stp end,
  done = function(ok) ended = ok end })
ls.update(0.1)
ls.pageClosed()
stp = 2
ls.update(0.1)
T.check(ended == true and not ls.active(), 'page closed before ready: ends by itself once ready')

-- (#63) the world's origin moving: said on the page (the World bar's "Moving the world...")
local mv = true
ls.moving = function() return mv end
ls.begin({ title = 'm', steps = { 'a' }, button = 'Continue', probe = function() return 1 end })
ls.update(0.1)
T.check(ls.ui().moving == true, 'origin moving: moving = true (#63)')
mv = false
T.check(ls.ui().moving == nil, 'origin moved: moving gone')
ls.moving = function() error('boom') end
T.check(ls.ui().moving == nil, 'a moving check that throws: not moving')
ls.cancel()
ls.moving = function() return false end

-- noWorld (a button pressed at the main menu: the BeamNG.Earth level loading): no world step, done with its steps
-- even with the world round the car at nothing
lp = 0
local nwStep, nwEnd = 1, nil
ls.begin({ title = 'Loading BeamNG.Earth', steps = { 'a', 'b' }, noWorld = true,
  probe = function() return nwStep end, done = function(ok) nwEnd = ok end })
local nwUi = ls.ui()
T.check(nwUi.noWorld and #nwUi.steps == 2, 'noWorld: no world step on the page')
nwStep = 3
ls.update(0.1)
T.check(nwEnd == true and not ls.active(), 'noWorld: done with its steps, the world not waited for')
lp = nil

T.done('test_loadscreen')
