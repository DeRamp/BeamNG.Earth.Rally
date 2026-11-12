-- A whole run against a stand-in game and BeamNG.Earth (no BeamNG needed): the recce saved, then a run that travels,
-- moves the world's origin to the stage's centre, writes and loads the rally files (our heights kept), counts down,
-- survives a world shift mid-stage and finishes at the flying finish with a saved time.
local T = dofile(TESTS .. '/testlib.lua')

------------------------------------------------------------------------------------------ the stand-in game

local files = {}
function jsonWriteFile(path, data) files[path] = data return true end
function jsonReadFile(path) return files[path] end
FS = {
  fileExists = function(_, path) return files[path] ~= nil end,
  findFiles = function(_, dir, pattern)
    local out = {}
    for k in pairs(files) do if k:sub(1, #dir) == dir and k:match('%.json$') then out[#out + 1] = k end end
    table.sort(out)
    return out
  end,
}
function log(level, tag, msg) if level == 'E' then print('LOG E ' .. tostring(msg)) end end
function dumps(t) return tostring(t) end
local messages = {}
function ui_message(text) messages[#messages + 1] = text end

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

-- BeamNG.Earth: a flat world round its origin (anchor), which can move
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
local car = { lat = 47.0, lon = -123.0, alt = 100.5 }
local listeners, nextL = {}, 0
local readyFlag = true
local moveAsk = nil
local function fireMoved(purpose, old)
  for _, l in pairs(listeners) do l({ lat = anchor.lat, lon = anchor.lon, oldLat = old.lat, oldLon = old.lon, purpose = purpose }) end
end
local function moveAnchor(lat, lon, purpose)
  local old = { lat = anchor.lat, lon = anchor.lon }
  anchor = { lat = lat, lon = lon }
  fireMoved(purpose, old)
end
beamngEarth_api = {
  version = function() return 1, 7 end,
  has = function(n) return n == 'transform' or n == 'rebase' or n == 'gpsRoute' end,
  inWorld = function() return true end,
  ready = function() return readyFlag end,
  rebasing = function() return false end,
  pose = function()
    local x, y, z = toGame(car.lat, car.lon, car.alt)
    return { lat = car.lat, lon = car.lon, alt = car.alt, x = x, y = y, z = z, anchorLat = anchor.lat, anchorLon = anchor.lon }
  end,
  toGame = toGame, toGeo = toGeo,
  teleport = function(lat, lon) car.lat, car.lon = lat, lon return true end,
  notify = function(text) messages[#messages + 1] = text return true end,
  gpsSetRoute = function() return true end, gpsClear = function() end,
  on = function(ev, fn) nextL = nextL + 1 listeners[nextL] = fn return nextL end,
  off = function(h) listeners[h] = nil end,
}
local rebaseDistance = 15000
package.loaded['beamngEarth/rebase'] = { distance = 15000 }
beamngEarth_core = {
  rebaseTo = function(lat, lon) moveAsk = { lat = lat, lon = lon, frames = 3 } return true end,
  setRebaseDistance = function(m) rebaseDistance = math.max(2000, math.min(16000, m))
    package.loaded['beamngEarth/rebase'].distance = rebaseDistance return rebaseDistance end,
}

-- the vehicle: its game position from where it is on Earth
local veh = {
  getPosition = function() local x, y, z = toGame(car.lat, car.lon, car.alt) return vec3(x, y, z) end,
  setPositionRotation = function(_, x, y, z) car.lat, car.lon = toGeo(x, y) car.alt = z end,
}
function getPlayerVehicle() return veh end

-- the game's rally engine: loads the files, and its driveline load sets heights down on the terrain (z = 0)
-- unless the snap is replaced, as the real one does on BeamNG.Earth outside the loaded kilometre
local zSnap = { conformSplineGeometry = function(spline) for _, n in ipairs(spline.nodes) do n.z = 0 end end }
local geom = { catmullRomFree = function() end }
package.loaded['/lua/ge/extensions/editor/rallyEditor/zSnap'] = zSnap
package.loaded['editor/toolUtilities/geom'] = geom
local manager = nil
gameplay_rally = {
  loadMission = function(id, dir, _, _, opts)
    assert(opts and opts.owner == 'external', 'owner external')
    local race = files[dir .. '/race.race.json']
    local dl = files[dir .. '/rally/drivelineSpline.json']
    local nb = files[dir .. '/rally/notebooks/structured.notebook.json']
    if not (race and dl and nb) then return false, 'files missing' end
    local nodes = {}
    for i, n in ipairs(dl.nodes) do nodes[i] = { x = n[1], y = n[2], z = n[3] } end
    local spline = { nodes = nodes, divPoints = {} }
    zSnap.conformSplineGeometry(spline, false, 4)
    for _, n in ipairs(nodes) do spline.divPoints[#spline.divPoints + 1] = n end
    manager = { notebook = { pacenotes = { sorted = nb.pacenotes } }, drivelineV3 = { spline = spline },
                lastPlayedPacenoteIdx = nil, resyncAfterTeleport = function() end, race = race, dl = dl }
    return true
  end,
  unloadMission = function() manager = nil return true end,
  getRallyManager = function() return manager end,
}
extensions = { load = function() end }
local layout = 'beamngEarth'
core_gamestate = { getGameState = function() return { appLayout = layout } end,
  setGameState = function(_, l) layout = l or layout end }

------------------------------------------------------------------------------------------ a stage

-- 3 km: north 1 km, a right-hand hairpin-ish bend (radius 30 m), then 1.9 km on
local function stageLine()
  local pts, x, y, h = {}, 0, 0, math.pi / 2
  local function add() local lat, lon = toGeo(x, y) pts[#pts + 1] = { lat, lon, 100 + y * 0.01 } end
  add()
  for _ = 1, 1000 do x, y = x + math.cos(h), y + math.sin(h) add() end
  for _ = 1, math.floor(30 * math.pi / 2) do h = h - (math.pi / 2) / math.floor(30 * math.pi / 2)
    x, y = x + math.cos(h), y + math.sin(h) add() end
  for _ = 1, 1900 do x, y = x + math.cos(h), y + math.sin(h) add() end
  return pts
end
local full = stageLine()
local mapLine, recPts = {}, {}
for i, p in ipairs(full) do
  if i % 25 == 1 then mapLine[#mapLine + 1] = { p[1], p[2] } end
  if i % 4 == 1 then recPts[#recPts + 1] = { p[1], p[2], p[3] + 0.5 } end
end
local last = full[#full]
local event = { format = 1, id = 'test', name = 'Test Rally', stages = { {
  id = 'hill', name = 'Hill', lengthM = 3000, radiusM = 1200,
  centre = { lat = 47.009, lon = -122.990 },
  controls = { start = { lat = full[11][1], lon = full[11][2] }, ff = { lat = full[2900][1], lon = full[2900][2] } },
  line = mapLine } } }
files['/earthRally/events/test.json'] = event

local events = require('earthRally/events')
local runner = require('earthRally/runner')
local earth = require('earthRally/earthAdapter')

T.check(#events.list() == 1, 'the event is listed')
local ok, why = runner.start(event, event.stages[1])
T.check(not ok and why:match('recce'), 'no run before a recce')
-- (as in game: the recce began on the start line and stopped 40 m before the flying finish, full[2900])
local recFrom = {}
for k, p in ipairs(recPts) do
  if (k - 1) * 4 + 1 > 2860 then break end
  local d = math.sqrt(((p[1] - full[11][1]) * 111195) ^ 2 + ((p[2] - full[11][2]) * 75800) ^ 2)
  if #recFrom > 0 or d < 3 then recFrom[#recFrom + 1] = p end
end
events.saveRecce('test', 'hill', { format = 1, points = recFrom, lengthM = 3000 })
T.check(events.recce('test', 'hill') ~= nil, 'the recce is read back')

------------------------------------------------------------------------------------------ the run

local function frames(n, dt)
  for _ = 1, n do
    if moveAsk then
      moveAsk.frames = moveAsk.frames - 1
      if moveAsk.frames <= 0 then moveAnchor(moveAsk.lat, moveAsk.lon, 'resync') moveAsk = nil end
    end
    earth.update()
    runner.update(dt or 0.1, dt or 0.1)
  end
end

car.lat, car.lon = full[1][1], full[1][2]
ok, why = runner.start(event, event.stages[1])
T.check(ok, 'the run starts (' .. tostring(why) .. ')')
frames(5)
T.check(runner.current().checks.originMoved == 'yes', 'the origin moved to the stage centre (' ..
  tostring(runner.current().checks.originMoved) .. ')')
T.check(math.abs(anchor.lat - 47.009) < 1e-9, 'the anchor is at the centre')
T.check(rebaseDistance == 16000, 'the rebase distance raised for the run')
frames(3)
local r = runner.current()
T.check(r.checks.rallyEngine == 'loaded', 'the rally engine loaded (' .. tostring(r.checks.rallyEngine) .. ')')
T.check((r.checks.cornersFound or 0) >= 1, 'the bend is a corner (' .. tostring(r.checks.cornersFound) .. ')')
T.check(r.checks.notesLoaded == r.checks.cornersFound, 'one note per corner')
T.check(r.checks.heightKeptM ~= nil and r.checks.heightKeptM < 0.01, 'our heights kept, not set down on the terrain ('
  .. tostring(r.checks.heightKeptM) .. ')')
T.check(zSnap.conformSplineGeometry ~= nil and select(1, pcall(function()
  local s = { nodes = { { x = 0, y = 0, z = 5 } } } zSnap.conformSplineGeometry(s) return s.nodes[1].z end)) ,
  'the game\'s snap is back after the load')
local race = manager.race
T.check(race.startPositions[1].name == 'SS_start_line' and race.startPositions[2].name == 'SS_stop_control',
  'start line and stop control')
T.check(#race.pathnodes >= 3 and race.endNode == race.pathnodes[#race.pathnodes].oldId, 'pathnodes to the finish')
-- the rally engine drops a start line, pathnode or note on the very end of its route: the driveline carries on
-- before the start and past the finish
local dlNodes = manager.dl.nodes
local function nodeDist(p, n) return math.sqrt((p[1] - n[1]) ^ 2 + (p[2] - n[2]) ^ 2) end
T.check(nodeDist(race.startPositions[1].pos, dlNodes[1]) >= 50, 'route before the start line (' ..
  string.format('%.0f', nodeDist(race.startPositions[1].pos, dlNodes[1])) .. ' m)')
T.check(nodeDist(race.pathnodes[#race.pathnodes].pos, dlNodes[#dlNodes]) >= 100, 'route past the finish (' ..
  string.format('%.0f', nodeDist(race.pathnodes[#race.pathnodes].pos, dlNodes[#dlNodes])) .. ' m)')
local firstCs = files[r.dir .. '/rally/notebooks/structured.notebook.json'].pacenotes[1].pacenoteWaypoints[1].pos
T.check(nodeDist(firstCs, race.startPositions[1].pos) >= 20, 'no note on the start line')
T.check(runner.state() == 'countdown', 'counting down (' .. runner.state() .. ')')
T.check(layout == 'earthRallyStage', 'the pacenote cards layout on for the run (' .. layout .. ')')
-- the car stands on the start line, in game coordinates of the new origin
local sx, sy = toGame(full[11][1], full[11][2])
local cp = veh.getPosition()
T.check(math.sqrt((cp.x - sx) ^ 2 + (cp.y - sy) ^ 2) < 6, 'the car on the start line')

frames(52)
T.check(runner.state() == 'running', 'GO')
T.check(not r.jumpStart, 'no jump start')

-- drive: 25 m per frame along the stage; a world shift halfway
local driven = 0
for i = 11, #full, 25 do
  car.lat, car.lon = full[i][1], full[i][2]
  if i > 1500 and not r.shiftDone then
    moveAnchor(car.lat, car.lon, 'rebase')
    r.shiftDone = true
  end
  frames(1, 1.0)
  driven = driven + 1
  if runner.state() ~= 'running' then break end
end
T.check(runner.state() == 'finished', 'finished (' .. runner.state() .. ')')
T.check(r.checks.shifts == 1, 'the world shift was counted (' .. r.checks.shifts .. ')')
T.check(r.checks.maxOffM < 5, 'never off the line, across the shift (' .. string.format('%.1f', r.checks.maxOffM) .. ')')
local ffx, ffy = toGame(full[2900][1], full[2900][2])
local cp2 = veh.getPosition()
T.check(math.sqrt((cp2.x - ffx) ^ 2 + (cp2.y - ffy) ^ 2) < 30, 'finished at the flying finish, past the recce end')
T.check(r.finalTime and r.finalTime > 100 and r.finalTime < 130, 'a time of ~2 min (' .. tostring(r.finalTime) .. ')')
T.check(rebaseDistance == 15000, 'the rebase distance back')
local res = events.results('test', 'hill')
T.check(#res.runs == 1 and res.runs[1].finished, 'the time saved')
T.check(events.addResult('test', 'hill', { finished = true, timeS = 99 }) == 99 and #events.results('test', 'hill').runs == 2,
  'a second time kept beside the first, the best of both')
runner.abort(true)
T.check(manager == nil, 'the co-driver unloaded when the run is closed')
T.check(layout == 'beamngEarth', 'BeamNG.Earth layout back')


-- the recce: the map line drawn ahead of the car on the ground, the driven line saved at the end
local drawn = 0
debugDrawer = { drawLineInstance = function() drawn = drawn + 1 end, drawSphere = function() end }
function ColorF(r, g, b, a) return { r, g, b, a } end
local rays = 0
function castRayStatic(o, _, maxd)
  rays = rays + 1
  local ground = 100
  local canopy = (math.floor(o.x / 15) % 10 == 0) and 130 or nil
  if canopy and o.z > canopy then return o.z - canopy end
  local d = o.z - ground
  if d >= 0 and d <= maxd then return d end
  return nil
end
local vmt = { __add = function(a, b) return vec3(a.x + b.x, a.y + b.y, a.z + b.z) end }
local plainVec3 = vec3
function vec3(x, y, z) return setmetatable(plainVec3(x, y, z), vmt) end
local recce = require('earthRally/recce')
car.lat, car.lon = full[1][1], full[1][2]
recce.start(event, event.stages[1])
local done = nil
for i = 1, #full, 3 do
  car.lat, car.lon, car.alt = full[i][1], full[i][2], full[i][3]
  local res = recce.update()
  recce.draw()
  if res == 'done' then done = i break end
end
T.check(drawn > 20, 'the stage line drawn ahead (' .. drawn .. ' segments)')

T.check(done ~= nil and done > #full * 0.9, 'the recce ends at the stage end')
T.check(recce.stop(true) == true and #events.recce('test', 'hill').points > 300, 'the recce saved')

-- the drawn line stays on the ground (z 100 + the lift), never on a treetop (130)
local zs = {}
debugDrawer.drawLineInstance = function(_, a, b) zs[#zs + 1] = a.z zs[#zs + 1] = b.z end
car.lat, car.lon, car.alt = full[1500][1], full[1500][2], 100.5
recce.start(event, event.stages[1])
recce.update()
recce.draw(1)
local high = 0
for _, z in ipairs(zs) do if math.abs(z - 101) > high then high = math.abs(z - 101) end end
T.check(#zs > 40 and high < 0.6, 'the line on the ground, under the trees (' .. #zs .. ' ends, worst ' .. high .. ' m)')
recce.stop(false)

T.done('test_run')
