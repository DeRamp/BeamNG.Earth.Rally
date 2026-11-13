-- The in-game self-test (earthRally/selftest.lua) offline: its pure checks (what each run state's HUD streams must
-- carry, the AI's path, the off-route spot, the verdict), then whole self-tests against a stand-in game and
-- BeamNG.Earth with a fake AI at the wheel: one that passes, and ones that must fail (the 1.2.1 layout file
-- installed, the AI stuck, the world never loading, the game's own rally mode taking the rallyLoop stream). The
-- `game` seam (selftest.game: the vehicle's AI, putting the car down, the UI's layout, loading the level, quitting)
-- is faked: that part is only checked in game.
local T = dofile(TESTS .. '/testlib.lua')

------------------------------------------------------------------------------------------ the stand-in game

local files = {}
function jsonWriteFile(path, data) files[path] = data return true end
function jsonReadFile(path) return files[path] end
FS = {
  fileExists = function(_, path) return files[path] ~= nil end,
  findFiles = function(_, dir)
    local out = {}
    for k in pairs(files) do if k:sub(1, #dir) == dir and k:match('%.json$') then out[#out + 1] = k end end
    table.sort(out)
    return out
  end,
  directoryExists = function() return true end,
  directoryCreate = function() end,
}
local logged = {}
function log(level, tag, msg) logged[#logged + 1] = level .. ' ' .. tostring(msg) end
local testLog = log
function dumps(t) return tostring(t) end

local Q = {}
Q.__index = Q
local function quat(x, y, z, w) return setmetatable({ x = x, y = y, z = z, w = w }, Q) end
Q.__mul = function(a, b)
  return quat(a.w * b.x + a.x * b.w + a.y * b.z - a.z * b.y, a.w * b.y - a.x * b.z + a.y * b.w + a.z * b.x,
              a.w * b.z + a.x * b.y - a.y * b.x + a.z * b.w, a.w * b.w - a.x * b.x - a.y * b.y - a.z * b.z)
end
function vec3(x, y, z) return { x = x or 0, y = y or 0, z = z or 0 } end
function quatFromDir(dir) local h = math.atan2(dir.y, dir.x) return quat(0, 0, math.sin(h / 2), math.cos(h / 2)) end
function quatFromEuler(_, _, z) return quat(0, 0, math.sin(z / 2), math.cos(z / 2)) end

local R = 6371008.8
local anchor = { lat = 47.0, lon = -123.0 }
local function toGame(lat, lon, h)
  local kx = math.rad(1) * R * math.cos(math.rad(anchor.lat))
  return (lon - anchor.lon) * kx, (lat - anchor.lat) * math.rad(1) * R, h or 0
end
local function toGeo(x, y, z)
  local kx = math.rad(1) * R * math.cos(math.rad(anchor.lat))
  return anchor.lat + y / (math.rad(1) * R), anchor.lon + x / kx, z or 0
end
local car = { lat = 47.0, lon = -123.0, alt = 100.5, speed = 0, up = 1 }
local listeners, nextL = {}, 0
local readyFlag = true
local moveAsk = nil
beamngEarth_api = {
  version = function() return 1, 7 end,
  has = function(n) return n == 'transform' or n == 'rebase' or n == 'gpsRoute' end,
  inWorld = function() return true end,
  ready = function() return readyFlag end,
  rebasing = function() return false end,
  pose = function()
    local x, y, z = toGame(car.lat, car.lon, car.alt)
    return { lat = car.lat, lon = car.lon, alt = car.alt, x = x, y = y, z = z, anchorLat = anchor.lat,
             anchorLon = anchor.lon, speed = car.speed or 0 }
  end,
  toGame = toGame, toGeo = toGeo,
  teleport = function(lat, lon) car.lat, car.lon = lat, lon return true end,
  notify = function() return true end,
  gpsSetRoute = function() return true end, gpsClear = function() end,
  on = function(_, fn) nextL = nextL + 1 listeners[nextL] = fn return nextL end,
  off = function(h) listeners[h] = nil end,
}
package.loaded['beamngEarth/rebase'] = { distance = 15000 }
package.loaded['beamngEarth/camshift'] = { RADIUS_MIN = 1000, RADIUS_MAX = 5000 }
beamngEarth_core = {
  rebaseTo = function(lat, lon) moveAsk = { lat = lat, lon = lon, frames = 3 } return true end,
  setRebaseDistance = function(m) return m end,
}

local veh = {
  getPosition = function() local x, y, z = toGame(car.lat, car.lon, car.alt) return vec3(x, y, z) end,
  setPositionRotation = function(_, x, y, z) car.lat, car.lon = toGeo(x, y) car.alt = z end,
  queueLuaCommand = function() end,
  getDirectionVector = function() return { x = 0, y = 1, z = 0 } end,
  getID = function() return 1 end,
}
function getPlayerVehicle() return veh end
-- the game's "flip upright" move (runner.recoverTo): back on its wheels
spawn = { safeTeleport = function(v, pos) v:setPositionRotation(pos.x, pos.y, pos.z) car.up = 1 car.speed = 0 end }

local objects, nextObj = {}, 0
function createObject(class)
  nextObj = nextObj + 1
  local o = { class = class, fields = {}, id = nextObj }
  function o:setField(k, _, v) self.fields[k] = v end
  function o:setPosRot() end
  function o:registerObject(name) self.name = name objects[self.id] = self end
  function o:addObject() end
  function o:getID() return self.id end
  function o:delete() objects[self.id] = nil end
  return o
end
scenetree = { MissionGroup = { addObject = function() end } }
scenetree.findObjectById = function(id) return objects[id] end
scenetree.findObject = function(name) for _, o in pairs(objects) do if o.name == name then return o end end end

local zSnap = { conformSplineGeometry = function() end }
package.loaded['/lua/ge/extensions/editor/rallyEditor/zSnap'] = zSnap
package.loaded['editor/toolUtilities/geom'] = { catmullRomFree = function() end }
local manager = nil
gameplay_rally = {
  loadMission = function(_, dir)
    local nb = files[dir .. '/rally/notebooks/structured.notebook.json']
    if not nb then return false, 'files missing' end
    manager = { notebook = { pacenotes = { sorted = nb.pacenotes } }, drivelineV3 = { spline = { nodes = {}, divPoints = {} } },
      lastPlayedPacenoteIdx = nil, resyncAfterTeleport = function() end,
      enqueueRandomSystemPacenote = function() end, setPacenoteProcessingEnabled = function(self, on) self.notesOn = on end }
    return true
  end,
  unloadMission = function() manager = nil return true end,
  getRallyManager = function() return manager end,
}
local rallyLoopLoaded = false
extensions = { load = function() end, hook = function() end,
  isExtensionLoaded = function(n) return n == 'gameplay_rallyLoop' and rallyLoopLoaded end }
core_camera = { resetCamera = function() end }
core_environment = { getTimeOfDay = function() return { time = 0.25 } end }
local layout = 'beamngEarth'
core_gamestate = { getGameState = function() return { appLayout = layout } end,
  setGameState = function(_, l) layout = l or layout end }
local streams = {}
guihooks = { trigger = function() end, queueStream = function(k, v) streams[#streams + 1] = k end }
ui_imgui = { BoolPtr = function(v) return { [0] = v } end, ImVec4 = function() return {} end }

------------------------------------------------------------------------------------------ a stage with its controls

-- 3 km: north 1 km, a right-hand bend, 1.9 km on; an ATC 150 m before the start, a stop control past the finish
local full = {}
do
  local x, y, h = 0, 0, math.pi / 2
  local function add() local lat, lon = toGeo(x, y) full[#full + 1] = { lat, lon, 100 + y * 0.01 } end
  add()
  for _ = 1, 1000 do x, y = x + math.cos(h), y + math.sin(h) add() end
  local n = math.floor(30 * math.pi / 2)
  for _ = 1, n do h = h - (math.pi / 2) / n x, y = x + math.cos(h), y + math.sin(h) add() end
  for _ = 1, 1900 do x, y = x + math.cos(h), y + math.sin(h) add() end
end
local mapLine, recPts = {}, {}
for i, p in ipairs(full) do
  if i % 25 == 1 then mapLine[#mapLine + 1] = { p[1], p[2] } end
  if i >= 11 and i <= 2860 and i % 4 == 3 then recPts[#recPts + 1] = { p[1], p[2], p[3] + 0.5 } end
end
local event = { format = 1, id = 'st', name = 'Self-test Rally', stages = { {
  id = 'hill', name = 'Hill', lengthM = 3000, radiusM = 1200, centre = { lat = 47.009, lon = -122.990 },
  controls = { start = { lat = full[11][1], lon = full[11][2] }, ff = { lat = full[2900][1], lon = full[2900][2] },
               atc = { lat = full[11][1] - 150 / 111195, lon = full[11][2] },
               stop = { lat = full[#full][1], lon = full[#full][2] + 0.0005 } },
  line = mapLine } } }
files['/earthRally/events/st.json'] = event
files['/earthRally/recce/st__hill.json'] = { format = 1, points = recPts, lengthM = 3000 }

local geo = require('earthRally/geo')
local hud = require('earthRally/hudFrame')
local runner = require('earthRally/runner')
local settings = require('earthRally/settings')
local earth = require('earthRally/earthAdapter')
local st = require('earthRally/selftest')
local main = require('earthRally/main')

------------------------------------------------------------------------------------------ the pure parts

do
  -- the streams each state must carry: hudFrame's own frames pass, broken ones are named
  local run = { state = 'running', stage = { name = 'Hill' }, ss = 1, ssCount = 2, startM = 30, finishM = 3000,
    along = 500, clock = 20, checks = {} }
  local rl, ours = hud.build(run, { now = 100 })
  T.check(st.frameProblem(rl, ours) == nil, 'running: hudFrame\'s frame passes')
  run.offRoute = true
  rl, ours = hud.build(run, { now = 100 })
  T.check(st.frameProblem(rl, ours) == nil and ours.show.offRoute, 'running off route: passes (show.offRoute)')
  local _, oursNoRl = hud.build(run, { now = 100, noRallyLoop = true })
  T.check((st.frameProblem(nil, oursNoRl) or ''):match('rallyLoop not sent'), 'running without the rallyLoop stream: named')
  run.offRoute = nil
  rl, ours = hud.build(run, { now = 100 })
  rl.uiColors = nil
  T.check((st.frameProblem(rl, ours) or ''):match('uiColors'), 'running without the theme (the stage apps hide): named')
  for _, s in ipairs({ 'toAtc', 'toStart', 'waitStart', 'toStop', 'finished', 'travel' }) do
    local r2 = { state = s, stage = { name = 'Hill' }, ss = 1, startM = 30, finishM = 3000, startAt = 130,
      atcTime = 90, toControlM = 50, checks = {}, finalTime = 100, stageTime = 100, sinceFinish = 1 }
    local a, b = hud.build(r2, { now = 100 })
    T.check(st.frameProblem(a, b) == nil, s .. ': hudFrame\'s frame passes (' .. tostring(st.frameProblem(a, b)) .. ')')
  end
  local r3 = { state = 'waitStart', stage = {}, startAt = 130, checks = {} }
  local a3, b3 = hud.build(r3, { now = 100 })
  a3.activeState = 'inactive'
  T.check((st.frameProblem(a3, b3) or ''):match('activeState inactive'), 'waitStart with the stock apps inactive: named')
  -- evaluateStreams: one check per state passed through; a state with no frame fails
  local slog = st.newStreamLog()
  rl, ours = hud.build(run, { now = 100 })
  st.observeFrame(slog, rl, ours)
  st.observeFrame(slog, a3, b3)
  local ev = st.evaluateStreams(slog, { 'travel', 'running', 'waitStart', 'toStop' })
  T.check(#ev == 3 and ev[1].ok and not ev[2].ok and ev[2].detail:match('1 wrong') and not ev[3].ok
    and ev[3].detail:match('no frame'), 'evaluateStreams: per state, the wrong frames and the missing ones')
  -- the AI's path: every 8 m from s0 to s1, ends included; the off-route spot to the right of the line
  local line = { { x = 0, y = 0, z = 1 }, { x = 0, y = 100, z = 2 }, { x = 100, y = 100, z = 3 } }
  local cum = geo.cumulative(line)
  local sc = st.aiScript(line, cum, 10, 150, 8)
  T.check(#sc == 19 and math.abs(sc[1].y - 10) < 1e-9 and math.abs(sc[#sc].x - 50) < 1e-9 and sc[1].z > 1,
    'aiScript: from s0 to s1 every 8 m, with heights (' .. #sc .. ')')
  T.check(#st.aiScript(line, cum, 150, 1000, 8) >= 2, 'aiScript: past the end clamped to the end')
  local p = st.offsetPoint(line, cum, 50, 30)
  T.check(math.abs(p.x - 30) < 1e-9 and math.abs(p.y - 50) < 1e-9, 'offsetPoint: 30 m to the right of the way north')
  local ok, pa, fa = st.summary({ { ok = true }, { ok = true } }, nil)
  T.check(ok and pa == 2 and fa == 0, 'summary: all passed')
  T.check(not st.summary({ { ok = true } }, 'stalled'), 'summary: a stopped test fails even with its checks passed')
  T.check(not st.summary({}, nil), 'summary: no checks is no pass')
end

------------------------------------------------------------------------------------------ the fake game seam

local ai = nil            -- the fake AI: { script, i, s (m along its path) }
local aiStuck = false
local AI_MS = 25
local quitCalled, levelAsked = false, nil
local onScreen = { type = 'earthRallyStage', filename = '/settings/ui_apps/layouts/default/earthRallyStage.uilayout.json',
  version = 5, apps = {} }
for _, n in ipairs(runner.STAGE_APPS) do onScreen.apps[#onScreen.apps + 1] = { appName = n } end
local function placeAt(x, y, z)
  car.lat, car.lon = toGeo(x, y)
  car.alt = z or car.alt
end
st.game.ground = function(_, _, z0) return z0 or 100 end
st.game.place = function(_, pos, _, upsideDown)
  placeAt(pos.x, pos.y, pos.z)
  car.speed, car.up = 0, upsideDown and -1 or 1
  return true
end
st.game.upZ = function() return car.up end
st.game.driveStart = function(_, script)
  ai = { script = script, i = 1, s = 0 }
  placeAt(script[1].x, script[1].y, script[1].z)
end
st.game.driveStop = function() ai = nil car.speed = 0 end
st.game.layout = function() return onScreen, layout end
st.game.inLevel = function() return true end
st.game.loadLevel = function(name) levelAsked = name return true end
st.game.quit = function() quitCalled = true end
st.game.removeFile = function(path) files[path] = nil end
st.game.date = function() return '20261113-120000', '2026-11-13T12:00:00Z' end

local notesCalled = 0
local function aiStep(dt)
  if not ai or aiStuck then return end
  local sc = ai.script
  local left = AI_MS * dt
  while left > 0 and ai.i < #sc do
    local a, b = sc[ai.i], sc[ai.i + 1]
    local seg = math.sqrt((b.x - a.x) ^ 2 + (b.y - a.y) ^ 2)
    local rest = seg - ai.s
    if left < rest then ai.s = ai.s + left left = 0
    else left = left - rest ai.i, ai.s = ai.i + 1, 0 end
  end
  local a, b = sc[ai.i], sc[math.min(#sc, ai.i + 1)]
  local seg = math.max(1e-9, math.sqrt((b.x - a.x) ^ 2 + (b.y - a.y) ^ 2))
  local t = math.min(1, ai.s / seg)
  placeAt(a.x + (b.x - a.x) * t, a.y + (b.y - a.y) * t)
  car.speed = ai.i < #sc and AI_MS or 0
  -- the co-driver: a note every ~500 m, once the stage's notes are on (from GO)
  if manager and manager.notesOn then
    ai.dist = (ai.dist or 0) + AI_MS * dt
    if ai.dist > 500 then ai.dist = 0 notesCalled = notesCalled + 1 manager.lastPlayedPacenoteIdx = notesCalled end
  end
end

local function frame(dt)
  if moveAsk then
    moveAsk.frames = moveAsk.frames - 1
    if moveAsk.frames <= 0 then
      local old = { lat = anchor.lat, lon = anchor.lon }
      anchor = { lat = moveAsk.lat, lon = moveAsk.lon }
      for _, l in pairs(listeners) do l({ lat = anchor.lat, lon = anchor.lon, oldLat = old.lat, oldLon = old.lon, purpose = 'resync' }) end
      moveAsk = nil
    end
  end
  aiStep(dt)
  main.onUpdate(dt, dt)
end

-- a whole self-test from the request file (as tools/selftest.py starts it); returns its report
local function selfTest(maxS, req)
  for k in pairs(files) do if k:match('^/earthRally/selftest/report') then files[k] = nil end end
  anchor = { lat = 47.0, lon = -123.0 }
  car.lat, car.lon, car.speed, car.up = full[1][1] - 0.02, full[1][2], 0, 1
  ai, quitCalled = nil, false
  files[st.REQUEST] = req or { event = 'st', stage = 'hill', token = 'tok1', quit = true }
  main.onExtensionLoaded()
  local dt = 0.1
  for _ = 1, math.floor(maxS / dt) do
    frame(dt)
    if quitCalled or (st.current() and st.current().closed and not st.current().quit) then break end
  end
  for k, v in pairs(files) do if k:match('^/earthRally/selftest/report%-') then return v, k end end
end
local function checkNamed(rep, pat)
  for _, c in ipairs(rep and rep.checks or {}) do if c.name:match(pat) then return c end end
end
local function failedNames(rep)
  local out = {}
  for _, c in ipairs(rep and rep.checks or {}) do if not c.ok then out[#out + 1] = c.name .. ': ' .. tostring(c.detail) end end
  return table.concat(out, ' / ')
end

------------------------------------------------------------------------------------------ a self-test that passes

settings.reset()
do
  local rep, path = selfTest(1500)
  T.check(rep ~= nil and path == '/earthRally/selftest/report-20261113-120000.json', 'a report written (' .. tostring(path) .. ')')
  T.check(files[st.REQUEST] == nil, 'the request used once (deleted)')
  T.check(rep and rep.ok == true and rep.failed == 0 and rep.abortReason == nil,
    'the self-test passes (' .. (rep and (tostring(rep.abortReason) .. ' | ' .. failedNames(rep)) or 'no report') .. ')')
  T.check(rep and rep.token == 'tok1' and rep.version == main.VERSION and rep.event == 'st' and rep.stage == 'hill',
    'the report says which run it is (token, version, stage)')
  for _, name in ipairs({ 'world loaded', 'the run starts', 'stage built', 'stage layout on screen', 'checked in at the ATC',
    'start wait skipped', 'GO', 'forced off route', 'off route on the HUD', 'Back on the road %(Backspace%)',
    'one reset added', 'Flip upright', 'flying finish', 'stop control', 'pacenotes called', 'results card',
    'HUD streams: toAtc', 'HUD streams: toStart', 'HUD streams: waitStart', 'HUD streams: running',
    'HUD streams: toStop', 'no Earth Rally errors' }) do
    local c = checkNamed(rep, name)
    T.check(c and c.ok, 'check passed: ' .. name .. (c and (' (' .. tostring(c.detail) .. ')') or ' (missing)'))
  end
  T.check(quitCalled, 'the game asked to quit at the end (the request said so)')
  T.check(files['/earthRally/results/st__hill.json'] == nil, 'the self-test\'s time taken out of the stage\'s times')
  T.check(runner.current() == nil and layout == 'beamngEarth', 'the run closed, the layout back')
  T.check(rep and rep.timings.stage and rep.timings.offroute and rep.run and rep.run.resets == 1,
    'timings per phase, the run\'s result (one reset)')
  T.check(log == testLog and guihooks.queueStream ~= nil and not tostring(st.current().hookError or ''):match('.'),
    'the log and stream hooks taken out, no error in them')
  if os.getenv('SELFTEST_DUMP') then for _, c in ipairs(rep.checks) do print(c.ok, c.t, c.name, c.detail) end end
  T.check(not st.active(), 'the self-test is over')
end

------------------------------------------------------------------------------------------ self-tests that must fail

-- 1.2.1 in game: the old stage layout file installed (only the pacenote cards)
do
  files['/earthRally/results/st__hill.json'] = { runs = { { finished = true, timeS = 200 } } }
  local apps = onScreen.apps
  onScreen.version, onScreen.apps = 4, { { appName = 'beamngEarthStatus' }, { appName = 'rallyVisualPacenotes' } }
  local rep = selfTest(1500)
  local c = checkNamed(rep, 'stage layout on screen')
  T.check(rep and not rep.ok and c and not c.ok and c.detail:match('missing: earthRallyHud'),
    'an old stage layout on screen: the self-test fails and says what is missing (' .. tostring(c and c.detail) .. ')')
  local res = files['/earthRally/results/st__hill.json']
  T.check(res and #res.runs == 1 and res.runs[1].timeS == 200, 'the player\'s own times put back as they were')
  onScreen.version, onScreen.apps = 5, apps
end

-- the game's own rally mode loaded: the rallyLoop stream is not ours to send
do
  rallyLoopLoaded = true
  local rep = selfTest(1500)
  local c = checkNamed(rep, 'HUD streams: running')
  T.check(rep and not rep.ok and c and not c.ok and c.detail:match('rallyLoop not sent'),
    'no rallyLoop stream: the streams\' check fails (' .. tostring(c and c.detail) .. ')')
  rallyLoopLoaded = false
end

-- the AI stuck on the stage: a stall, reported within the budget
do
  aiStuck = true
  local rep = selfTest(1500)
  T.check(rep and not rep.ok and tostring(rep.abortReason):match('stalled') and rep.elapsedS < 600,
    'the car stuck: the self-test stops with "stalled" (' .. tostring(rep and rep.abortReason) .. ')')
  T.check(runner.current() == nil, 'the run closed after a stall')
  aiStuck = false
end

-- the world never loads: stopped at the world's budget, not left hanging
do
  readyFlag = false
  local old = st.WORLD_BUDGET_S
  st.WORLD_BUDGET_S = 30
  local rep = selfTest(200)
  T.check(rep and not rep.ok and tostring(rep.abortReason):match('world never loaded'),
    'the world never ready: "the world never loaded" (' .. tostring(rep and rep.abortReason) .. ')')
  st.WORLD_BUDGET_S = old
  readyFlag = true
end

-- the whole budget
do
  local rep = selfTest(200, { event = 'st', stage = 'hill', token = 'tok2', quit = true, budgetS = 20 })
  T.check(rep and not rep.ok and tostring(rep.abortReason):match('time budget') and rep.token == 'tok2',
    'the time budget used up: stopped (' .. tostring(rep and rep.abortReason) .. ')')
end

-- an unknown stage, and no self-test without a request
do
  local rep = selfTest(100, { event = 'st', stage = 'nope', token = 'tok3', quit = true })
  T.check(rep and not rep.ok and tostring(rep.abortReason):match('no stage nope'), 'an unknown stage: said so')
  quitCalled = false
  main.onExtensionLoaded()
  T.check(not st.active() and (st.current() == nil or st.current().closed), 'no request file: no self-test')
end

T.done('test_selftest')
