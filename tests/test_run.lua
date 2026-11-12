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
    return { lat = car.lat, lon = car.lon, alt = car.alt, x = x, y = y, z = z, anchorLat = anchor.lat, anchorLon = anchor.lon,
             speed = car.speed or 0 }
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
local camshift = { RADIUS_MIN = 1000, RADIUS_MAX = 5000 }
package.loaded['beamngEarth/camshift'] = camshift
local radiusAtMove = nil
beamngEarth_core = {
  rebaseTo = function(lat, lon) moveAsk = { lat = lat, lon = lon, frames = 3 } radiusAtMove = camshift.RADIUS_MAX return true end,
  setRebaseDistance = function(m) rebaseDistance = math.max(2000, math.min(16000, m))
    package.loaded['beamngEarth/rebase'].distance = rebaseDistance return rebaseDistance end,
}

-- the vehicle: its game position from where it is on Earth
local sounds, frozen, inputs, routes, lines = {}, nil, {}, {}, {}
local veh = {
  getPosition = function() local x, y, z = toGame(car.lat, car.lon, car.alt) return vec3(x, y, z) end,
  setPositionRotation = function(_, x, y, z) car.lat, car.lon = toGeo(x, y) car.alt = z end,
  queueLuaCommand = function(_, cmd) inputs[#inputs + 1] = cmd end,
}
function getPlayerVehicle() return veh end

-- scene objects (the controls' boards and tents)
local objects, nextObj = {}, 0
function createObject(class)
  nextObj = nextObj + 1
  local o = { class = class, fields = {}, id = nextObj }
  function o:setField(k, _, v) self.fields[k] = v end
  function o:setPosRot(x, y, z, qx, qy, qz, qw) self.pos = { x, y, z } self.q = { qx, qy, qz, qw } end
  function o:registerObject(name) self.name = name objects[self.id] = self end
  function o:addObject() end
  function o:getID() return self.id end
  function o:delete() objects[self.id] = nil end
  return o
end
scenetree = { MissionGroup = { addObject = function() end }, findObjectById = function(_, id) return objects[id] end }
setmetatable(scenetree, { __index = function(t, k) return rawget(t, k) end })
scenetree.findObjectById = function(id) return objects[id] end
scenetree.findObject = function(name) for _, o in pairs(objects) do if o.name == name then return o end end end
local function countObjects() local n = 0 for _, o in pairs(objects) do if o.class == 'TSStatic' then n = n + 1 end end return n end

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
                lastPlayedPacenoteIdx = nil, resyncAfterTeleport = function() end, race = race, dl = dl,
                enqueueRandomSystemPacenote = function(_, name) lines[#lines + 1] = name end,
                setPacenoteProcessingEnabled = function(self, on) self.notesOn = on end,
                triggerPacenote = function(self, pn) self.firstCalls = (self.firstCalls or 0) + 1 lines[#lines + 1] = 'note:' .. pn.name end,
                drivelineRoute = { events = {} } }
    for i, pn in ipairs(nb.pacenotes) do pn.id = i end
    return true
  end,
  unloadMission = function() manager = nil return true end,
  getRallyManager = function() return manager end,
}
extensions = { load = function() end }
local camResets = 0
core_camera = { resetCamera = function() camResets = camResets + 1 end }
Engine = { Audio = { playOnce = function(_, ev) sounds[#sounds + 1] = ev end } }
core_vehicleBridge = { executeAction = function(_, action, on) if action == 'setFreeze' then frozen = on end end }
core_groundMarkers = { setPath = function(t) routes[#routes + 1] = t or false end }
local function has(list, v) for _, x in ipairs(list) do if x == v then return true end end return false end
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
T.check(radiusAtMove == 30, 'the camera moved at the origin move only within 30 m of the car (' .. tostring(radiusAtMove) .. ')')
T.check(camshift.RADIUS_MIN == 1000 and camshift.RADIUS_MAX == 5000, 'BeamNG.Earth camera radius put back after')
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
T.check(runner.state() == 'toStart', 'on the start line (' .. runner.state() .. ')')
frames(8)
T.check(frozen == true and has(sounds, 'event:UI_Checkpoint'), 'stopped on the line: held, a sound')
T.check(camResets >= 2, 'the camera reset after the origin moved and the car was placed (' .. camResets .. ')')
T.check(layout == 'earthRallyStage', 'the pacenote cards layout on for the run (' .. layout .. ')')
-- the car stands on the start line, in game coordinates of the new origin
local sx, sy = toGame(full[11][1], full[11][2])
local cp = veh.getPosition()
T.check(math.sqrt((cp.x - sx) ^ 2 + (cp.y - sy) ^ 2) < 6, 'the car on the start line')

frames(120)
T.check(runner.state() == 'running', 'GO (' .. runner.state() .. ')')
T.check(frozen == false, 'let go before the start')
T.check(has(lines, 'countdown3') and has(lines, 'countdown1') and has(lines, 'countdowngo'),
  'the co-driver counted down')
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


-- a stage with its time controls: an ATC 150 m before the start, a stop control 300 m past the finish
do
  local ev2 = { format = 1, id = 'test2', name = 'Test Rally 2', stages = { {
    id = 'hill', name = 'Hill', lengthM = 3000, radiusM = 1200, centre = event.stages[1].centre,
    controls = { start = event.stages[1].controls.start, ff = event.stages[1].controls.ff,
                 atc = { lat = full[11][1] - 150 / 111195, lon = full[11][2] },
                 stop = { lat = full[#full][1], lon = full[#full][2] + 0.0005 } },
    line = event.stages[1].line } } }
  files['/earthRally/events/test2.json'] = ev2
  events.saveRecce('test2', 'hill', { format = 1, points = recFrom, lengthM = 3000 })
  anchor = { lat = 47.0, lon = -123.0 }
  car.lat, car.lon, car.speed = full[1][1] - 0.01, full[1][2], 0      -- 1 km away: a teleport to the ATC
  local ok2, why2 = runner.start(ev2, ev2.stages[1])
  T.check(ok2, 'the run with controls starts (' .. tostring(why2) .. ')')
  frames(80)     -- (the teleport: 2 s, the world 2 s settled, the origin moved, the stage built)
  local r2 = runner.current()
  T.check(runner.state() == 'toAtc', 'driving to the ATC (' .. runner.state() .. ')')
  local ax, ay = toGame(ev2.stages[1].controls.atc.lat, ev2.stages[1].controls.atc.lon)
  local cp3 = veh.getPosition()
  local dAtc = math.sqrt((cp3.x - ax) ^ 2 + (cp3.y - ay) ^ 2)
  T.check(dAtc > 30 and dAtc < 50, 'the car put ~40 m before the ATC (' .. string.format('%.0f', dAtc) .. ' m)')
  T.check(countObjects() >= 6, 'the ATC and start boards and tents put down (' .. countObjects() .. ')')
  local shapes = {}
  for _, o in pairs(objects) do if o.fields.shapeName then shapes[o.fields.shapeName:match('([^/]+)%.dae$')] = true end end
  T.check(shapes.s_rally_signboard_time_control and shapes.s_rally_signboard_start and shapes.s_rally_gazebo_mod_frame_3x3,
    'the time control and start boards and a gazebo')
  -- roll up to the ATC and stop
  T.check(#routes > 0 and routes[#routes] ~= false, 'route arrows to the ATC')
  car.speed = 8
  car.lat, car.lon = toGeo(ax, ay - 5)
  inputs = {}
  frames(2)
  T.check(runner.state() == 'toAtc', 'not checked in while moving')
  T.check(inputs[1] and inputs[1]:find("'brake', 0.30"), 'braked at 30 % in the ATC zone')
  car.speed = 0
  frames(2)
  local clk = runner.clock()
  T.check(r2.startAt and r2.startAt % 30 == 0 and r2.startAt - clk >= 29 and r2.startAt - clk <= 61,
    'checked in: the start time the next half minute at least 30 s on, never 60 s past (' .. runner.formatClock(r2.startAt) .. ', now ' ..
    runner.formatClock(clk) .. ')')
  T.check(r2.checks.atc:find('checked in') ~= nil, 'checked in at the ATC')
  T.check(inputs[#inputs]:find("'brake', 0, 2", 1, true) ~= nil, 'the brake let go once stopped')
  frames(20)
  T.check(runner.state() == 'toStart' and frozen == false, 'let go: on to the start line')
  -- on to the start line
  car.lat, car.lon, car.speed = full[11][1], full[11][2], 6
  frames(2)
  T.check(runner.state() == 'toStart', 'no start while still rolling')
  car.lat, car.lon, car.speed = full[9][1], full[9][2], 0
  frames(20)
  T.check(runner.state() == 'waitStart', 'stopped on the start line: waiting for the minute (' .. runner.state() .. ')')
  frames(1)
  T.check(routes[#routes] == false, 'no route arrows once at the start')
  T.check(manager.notesOn == false, 'no stage notes called before the start')
  T.check(frozen == true, 'held on the line while waiting')
  local drawn = 0
  debugDrawer = debugDrawer or {}
  debugDrawer.drawSquarePrism = function() drawn = drawn + 1 end
  Point2F = Point2F or function(a, b) return { a, b } end
  ColorF = ColorF or function(r, g, b, a) return { r, g, b, a } end
  frames(2)
  T.check(drawn >= 2, 'the start line drawn on the road')
  local tcBoards = 0
  for _, o in pairs(objects) do if (o.fields.shapeName or ''):find('signboard_time_control.dae') then tcBoards = tcBoards + 1 end end
  T.check(tcBoards == 2, 'a time control board on each side of the road (' .. tcBoards .. ')')
  local releasedAt = nil
  lines = {}
  for _ = 1, 1200 do
    frames(1)
    if not releasedAt and frozen == false then releasedAt = r2.startAt - runner.clock() end
    if runner.state() == 'running' then break end
  end
  T.check(releasedAt and releasedAt <= 5.05 and releasedAt > 4, 'let go 5 s before the start (' .. tostring(releasedAt) .. ')')
  T.check(manager.notesOn == true, 'the stage notes on from GO')
  T.check(runner.state() == 'running', 'GO at the start minute (with controls)')
  T.check(math.abs(runner.clock() - r2.startAt) < 0.2, 'the stage clock from the minute itself')
  T.check(has(lines, 'countdown5') and has(lines, 'countdowngo') and not r2.jumpStart, 'counted down, no jump start')
  local order = table.concat(lines, ' ')
  T.check(order:find('warningSeconds30 precountdown') ~= nil, '"30 seconds", then good luck (' .. order .. ')')
  T.check(order:find('warningSeconds10') ~= nil and order:find('countdowngo') ~= nil, '"10 seconds" ... go')
  T.check(not manager.firstCalls and next(manager.drivelineRoute.events) == nil,
    'the first note left to the engine (nothing called or marked by us)')
  sounds = {}
  car.speed = 30
  for i = 11, #full, 25 do
    car.lat, car.lon = full[i][1], full[i][2]
    frames(1, 1.0)
    if runner.state() ~= 'running' then break end
  end
  T.check(runner.state() == 'toStop' and r2.finalTime, 'the clock stopped at the flying finish, on to the stop control')
  T.check(has(sounds, 'event:UI_CountdownGo'), 'a sound at the flying finish')
  local ffx2, ffy2 = toGame(full[2900][1], full[2900][2])
  local tentAtFinish, tents = false, 0
  for _, o in pairs(objects) do
    if (o.fields.shapeName or ''):find('gazebo_mod_frame') then
      tents = tents + 1
      if (o.pos[1] - ffx2) ^ 2 + (o.pos[2] - ffy2) ^ 2 < 20 ^ 2 then tentAtFinish = true end
    end
  end
  T.check(not tentAtFinish and tents >= 2, 'no tent at the flying finish, tents at the controls (' .. tents .. ')')
  local shapes2 = {}
  for _, o in pairs(objects) do if o.fields.shapeName then shapes2[o.fields.shapeName:match('([^/]+)%.dae$')] = true end end
  T.check(shapes2.s_rally_signboard_finish and shapes2.s_rally_signboard_finish_entry, 'the finish boards put down')
  car.lat, car.lon = ev2.stages[1].controls.stop.lat, ev2.stages[1].controls.stop.lon
  frames(2)
  local stopTent = false
  local sx2, sy2 = toGame(ev2.stages[1].controls.stop.lat, ev2.stages[1].controls.stop.lon)
  for _, o in pairs(objects) do
    if (o.fields.shapeName or ''):find('gazebo_mod_frame') and (o.pos[1] - sx2) ^ 2 + (o.pos[2] - sy2) ^ 2 < 15 ^ 2 then
      stopTent = true
    end
  end
  T.check(stopTent, 'a tent at the stop control')
  car.speed = 0
  frames(20)
  T.check(runner.state() == 'finished' and r2.checks.stopControl:find('stopped') ~= nil,
    'stopped at the stop control: stage complete')
  runner.abort(true)
  T.check(countObjects() == 0, 'the boards and tents taken away with the run')
end

T.done('test_run')
