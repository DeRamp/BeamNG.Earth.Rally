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
-- (the rally clock from a fixed time of day, 18:00:00: the start times do not depend on when the test runs)
core_environment = { getTimeOfDay = function() return { time = 0.25 } end }
local function lastCtl()
  for i = #inputs, 1, -1 do
    local m = inputs[i]:match('earthRally_ctl%("(%a+)"')
    if m then return m, inputs[i] end
  end
end
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
T.check(frozen == true and lastCtl() == 'launch' and has(sounds, 'event:UI_Checkpoint'),
  'stopped on the line: held (the game freeze, launch control on), a sound')
T.check(camResets >= 2, 'the camera reset after the origin moved and the car was placed (' .. camResets .. ')')
T.check(layout == 'earthRallyStage', 'the pacenote cards layout on for the run (' .. layout .. ')')
-- the car stands on the start line, in game coordinates of the new origin
local sx, sy = toGame(full[11][1], full[11][2])
local cp = veh.getPosition()
T.check(math.sqrt((cp.x - sx) ^ 2 + (cp.y - sy) ^ 2) < 6, 'the car on the start line')

frames(120)
T.check(runner.state() == 'running', 'GO (' .. runner.state() .. ')')
T.check(lastCtl() == 'off' and frozen == false, 'let go at GO')
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
  -- the brake eases in: a little at the zone's edge, more nearer the board, full at it, never less again
  local function brakeNow() local _, cmd = lastCtl() return cmd and tonumber(cmd:match('"zone", ([%d%.]+)')) end
  car.lat, car.lon = toGeo(ax, ay - 10)
  inputs = {}
  frames(1)
  local atEdge = brakeNow()
  car.lat, car.lon = toGeo(ax, ay - 5)
  frames(1)
  local nearer = brakeNow()
  T.check(runner.state() == 'toAtc', 'not checked in while moving')
  T.check(atEdge and nearer and atEdge < 0.1 and nearer > atEdge and nearer < 0.3,
    'the brake eases in towards the board (' .. tostring(atEdge) .. ' at 10 m, ' .. tostring(nearer) .. ' at 5 m)')
  car.lat, car.lon = toGeo(ax, ay)
  frames(1)
  T.check(math.abs((brakeNow() or 0) - 0.30) < 0.01, '30 % at the board')
  car.lat, car.lon = toGeo(ax, ay + 4)
  frames(1)
  T.check(math.abs((brakeNow() or 0) - 0.30) < 0.01, 'past the board: still 30 %')
  car.speed = 0
  frames(2)
  local clk = runner.clock()
  T.check(r2.startAt and r2.startAt % 30 == 0 and r2.startAt - clk >= 29 and r2.startAt - clk <= 61,
    'checked in: the start time the next half minute at least 30 s on, never 60 s past (' .. runner.formatClock(r2.startAt) .. ', now ' ..
    runner.formatClock(clk) .. ')')
  T.check(r2.checks.atc:find('checked in') ~= nil, 'checked in at the ATC')
  T.check(has(lines, 'commsCheck') and has(lines, 'beltsCheck'), 'the co-driver at the ATC: intercom check, belts')
  T.check(lastCtl() == 'off', 'the brake let go once stopped')
  frames(20)
  T.check(runner.state() == 'toStart' and lastCtl() == 'off', 'let go: on to the start line')
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
  local releasedAt, heldAll = nil, true
  lines = {}
  for _ = 1, 1200 do
    inputs = {}
    frames(1)
    if runner.state() == 'waitStart' and frozen ~= true then heldAll = false end
    for _, c in ipairs(inputs) do if c:find('earthRally_ctl("zone"', 1, true) then heldAll = false end end
    if not releasedAt and frozen == false then releasedAt = r2.startAt - runner.clock() end
    if runner.state() == 'running' then break end
  end
  T.check(heldAll, 'held (frozen) the whole wait, no brake override (arcade would select reverse)')
  T.check(releasedAt and releasedAt <= 0.001 and releasedAt > -0.2, 'let go at GO, not before (' .. tostring(releasedAt) .. ')')
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
  T.check(manager.notesOn == false, 'the stage notes off at the flying finish')
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
  T.check(countObjects() > 0, 'stage done: the stop control tent still there a moment after stopping')
  frames(100)
  T.check(countObjects() == 0 and manager == nil,
    'a few seconds later: boards and co-driver taken away (not left until Close)')
  T.check(layout == 'earthRallyStage' and r2.resultsOpen, 'the stage layout kept for the results card')
  -- drive off: the card closes, BeamNG.Earth's layout back
  car.lat, car.lon = toGeo(sx2 + 150, sy2)
  frames(1)
  T.check(not r2.resultsOpen and layout == 'beamngEarth', 'driven off: the results card closed, the layout back')
  runner.abort(true)
end

------------------------------------------------------------------------------------------ the car's controls (vehicle Lua)
do
  local ts = { enabled = false }
  ts.setTwoStep = function(on) ts.enabled = on end
  ts.getState = function() return { twoStepLaunch_enabled = ts.enabled, twoStepLaunch_rpm = 4000 } end
  local gearbox = 'manualGearbox'
  local env = { electrics = { values = {} }, input = { brake = 0, state = { throttle = { filter = 0 } } },
    FILTER_KBD = 0, FILTER_KBD2 = 3, math = math, pairs = pairs, ipairs = ipairs, pcall = pcall, type = type,
    next = next,
    powertrain = { getDevicesByType = function(t) return t == gearbox and { { type = t } } or {} end },
    controller = { getControllersByType = function(t) return t == 'twoStepLaunch' and { ts } or {} end },
    rawset = rawset, rawget = rawget }
  -- (as the vehicle's Lua, which warns on a new global set plainly: a write to env that is not rawset fails here)
  env._G = env
  setmetatable(env, { __newindex = function(_, k) error('a plain global set in the vehicle: ' .. tostring(k)) end })
  local function vrun(mode, level)
    local f = assert(loadstring(runner.VEH_CTL .. string.format('earthRally_ctl(%q, %.2f)', mode, level or 0)))
    setfenv(f, env)
    f()
  end
  local ev = env.electrics.values
  vrun('zone', 0.3)
  T.check(ev.brakeOverride == 0.3 and ev.clutchOverride == nil, 'zone: 30 % brake, no clutch')
  env.input.brake = 1
  vrun('zone', 0.3)
  T.check(ev.brakeOverride == 1, 'zone: the player\'s own harder braking kept')
  env.input.brake = 0
  vrun('launch')
  T.check(ev.brakeOverride == nil and ts.enabled == true,
    'on the start line: launch control on, no brake override (the freeze holds the car)')
  vrun('off')
  T.check(ev.brakeOverride == nil and ts.enabled == false, 'off: launch control as the player had it')
  ts.enabled = true
  vrun('launch') vrun('off')
  T.check(ts.enabled == true, 'a player who had it on keeps it on')
end

------------------------------------------------------------------------------------------ props on a winding road
do
  local props = require('earthRally/props')
  props.clear()
  -- the road map: a right-hand bend of radius 100 m round (0, 0), nodes every 10 m, and a side road at its middle
  local nodes, R0 = {}, 100
  local names = {}
  for i = 0, 60 do
    local a = math.pi - i * (10 / R0)
    local n = 'n' .. i
    nodes[n] = { pos = vec3(R0 * math.cos(a), R0 * math.sin(a), 50), radius = 3.5, links = {} }
    names[i] = n
    if i > 0 then nodes[n].links[names[i - 1]] = {} nodes[names[i - 1]].links[n] = {} end
  end
  local mid = nodes[names[30]].pos
  nodes.side = { pos = vec3(mid.x * 1.3, mid.y * 1.3, 50), radius = 3, links = { [names[30]] = {} } }
  nodes[names[30]].links.side = {}
  map = { getMap = function() return { nodes = nodes } end }
  local toGameId = function(lat, lon) return lon, lat, 0 end      -- (the site's lat / lon read as x / y here)
  local function onArc(o) return math.abs(math.sqrt(o.pos[1] ^ 2 + o.pos[2] ^ 2) - R0) end
  -- the time control at the side road's junction, driven along the bend (clockwise)
  local a30 = math.pi - 30 * (10 / R0)
  local dir = { x = math.sin(a30), y = -math.cos(a30) }
  props.setSite('atc', mid.y, mid.x, dir, nil)
  props.update({ x = mid.x, y = mid.y, z = 0 }, toGameId)      -- (the car 50 m below: its height is not the road's)
  local entries, worst, zs = 0, 0, true
  for _, o in pairs(objects) do
    local shape = o.fields.shapeName or ''
    if not o.pos then shape = '' end
    if shape:find('signboard_time_control') then
      worst = math.max(worst, math.abs(onArc(o) - 3.2))
      if shape:find('entry') then entries = entries + 1 end
    end
    if o.pos and math.abs(o.pos[3] - 50) > 0.01 then zs = false end
  end
  T.check(entries == 2 and worst < 0.6, 'the ATC boards beside the bend, 50 m back round it too (worst ' ..
    string.format('%.2f', worst) .. ' m off)')
  T.check(zs, 'every object at the road\'s height, not the car\'s')
  local e = props.roadAt(mid.x, mid.y, dir)
  T.check(e and e.a ~= 'side' and e.b ~= 'side', 'at the junction, the road along the driving direction (not the side road)')
  props.clear()
  -- the flying finish along the stage line: the board 150 m before it, round the bend
  local function path(fwd)
    local a = a30 - fwd / R0
    return { x = R0 * math.cos(a), y = R0 * math.sin(a), z = 50, dx = math.sin(a), dy = -math.cos(a) }
  end
  props.setSite('ff', mid.y, mid.x, dir, 50, path)
  props.update({ x = mid.x, y = mid.y, z = 0 }, toGameId)
  local fe = 0
  for _, o in pairs(objects) do
    if (o.fields.shapeName or ''):find('finish_entry') and math.abs(onArc(o) - (3.5 + 0.5)) < 0.6 then fe = fe + 1 end
  end
  T.check(fe == 2, 'the finish warning boards 150 m back along the stage line, beside the road (' .. fe .. ')')
  props.clear()
  map = nil
end

------------------------------------------------------------------------------------------ progress on a stage that passes close by
do
  local geo = require('earthRally/geo')
  local line = {}
  for y = 0, 500, 10 do line[#line + 1] = { x = 0, y = y } end
  for y = 500, 0, -10 do line[#line + 1] = { x = 15, y = y } end      -- (back down 15 m beside itself)
  local cum = geo.cumulative(line)
  local along = geo.follow(line, cum, { x = 1, y = 250 }, 240, 150, 600, 60)
  T.near(along, 250, 1, 'on the way up, beside the way down: still on the way up')
  local along2 = geo.follow(line, cum, { x = 14, y = 250 }, 760, 150, 600, 60)
  T.near(along2, 515 + 250, 1, 'on the way down: on the way down')
  local along3 = geo.follow(line, cum, { x = 40, y = 250 }, 240, 150, 600, 20)
  T.near(along3, 250, 1, 'well off the line: the part nearest where it was along it')
end

------------------------------------------------------------------------------------------ the recce's fixes
do
  local recce = require('earthRally/recce')
  car.lat, car.lon, car.alt = full[1][1] + 0.01, full[1][2], 100       -- 1 km from the stage
  recce.start(event, event.stages[1])
  recce.update()
  local _, _, n, _, started = recce.progress()
  T.check(n == 0 and not started, 'not recording on the way to the stage')
  for i = 1, 600, 3 do
    car.lat, car.lon, car.alt = full[i][1], full[i][2], full[i][3]
    recce.update()
  end
  local _, len0 = recce.progress()
  car.lat, car.lon = full[900][1], full[900][2]          -- (a reset: 300 m on in one go)
  recce.update()
  local _, len1, n1, _, started1 = recce.progress()
  T.check(started1 and n1 > 100, 'recording from the start')
  T.check(len1 - len0 < 5, 'a reset\'s jump not counted as driven (' .. string.format('%.0f', len1 - len0) .. ' m)')
  local ok, why = recce.stop(true)
  T.check(not ok and why:find('drive on') and recce.active(), 'Save before the end: not saved, and the recce goes on')
  recce.stop(false)
  T.check(not recce.active(), 'cancelled')
end

------------------------------------------------------------------------------------------ late rule, missed ATC, start clock, a matched line
do
  local hooks, loaded = {}, {}
  extensions.load = function(n) loaded[n] = true if n == 'gameplay_rallyStartClock' then gameplay_rallyStartClock = {} end end
  extensions.unload = function(n) loaded[n] = nil _G[n] = nil end
  extensions.hook = function(name, d) if name == 'onRallyDataUpdated' then hooks[#hooks + 1] = d end end
  local ev3 = { format = 1, id = 'test3', name = 'Test Rally 3', stages = { {
    id = 'hill', name = 'Hill', lengthM = 3000, radiusM = 1200, centre = event.stages[1].centre,
    controls = { start = event.stages[1].controls.start, ff = event.stages[1].controls.ff,
                 atc = { lat = full[11][1] - 150 / 111195, lon = full[11][2] } },
    line = event.stages[1].line } } }
  files['/earthRally/events/test3.json'] = ev3
  -- no recce: the map line matched to the roads (tools/match_roads.py) instead
  files['/earthRally/matched/test3__hill.json'] = { format = 1, points = recFrom }
  local function toAtcRun()
    anchor = { lat = 47.0, lon = -123.0 }
    car.lat, car.lon, car.speed = full[1][1] - 0.01, full[1][2], 0
    local ok3, why3 = runner.start(ev3, ev3.stages[1])
    frames(80)
    return ok3, why3
  end
  local ok3, why3 = toAtcRun()
  local r3 = runner.current()
  T.check(ok3 and r3.checks.line == 'matched' and runner.state() == 'toAtc',
    'a stage with no recce runs on its matched line (' .. tostring(why3) .. ')')
  T.check(loaded.gameplay_rallyStartClock, 'the game\'s start clock loaded for the run')
  local tree = false
  for _, o in pairs(objects) do if (o.fields.shapeName or ''):find('s_rally_start_tree') then tree = true end end
  T.check(tree, 'the start tree at the start (the start clock\'s board)')
  -- check in at the ATC
  local ax, ay = toGame(ev3.stages[1].controls.atc.lat, ev3.stages[1].controls.atc.lon)
  car.lat, car.lon = toGeo(ax, ay - 5)
  car.speed = 8 frames(1) car.speed = 0 frames(3)
  T.check(r3.startAt ~= nil, 'checked in')
  frames(20)
  -- arrive on the start line 3 s before the start time: not late
  while runner.clock() < r3.startAt - 3 do frames(1) end
  car.lat, car.lon, car.speed = full[9][1], full[9][2], 0
  local startAt = r3.startAt
  frames(1)
  T.check(not r3.latePenalty and r3.startAt == startAt, 'on the line 3 s before the start time: not late')
  hooks = {}
  for _ = 1, 100 do frames(1) if runner.state() == 'running' then break end end
  local countdown = false
  for _, d in ipairs(hooks) do
    if d.activeState == 'countdown' and d.countdownData and d.countdownData.timeUntilLaunch > 0 then countdown = true end
  end
  T.check(countdown, 'the start clock fed its countdown while the car waits (its picture-in-picture view)')
  T.check(runner.state() == 'running', 'GO')
  runner.abort(true)
  T.check(not loaded.gameplay_rallyStartClock, 'the start clock unloaded with the run')
  -- again, driving past the ATC to the start: missed, +60 s
  toAtcRun()
  local r4 = runner.current()
  car.lat, car.lon, car.speed = full[9][1], full[9][2], 6
  frames(2)
  T.check(r4.missedAtc and runner.state() == 'toStart', 'the ATC driven past: missed')
  car.speed = 0
  frames(3)
  T.check(r4.startAt and r4.startAt - runner.clock() >= 25, 'a start time as if checked in on the line')
  for _ = 1, 1000 do frames(1) if runner.state() == 'running' then break end end
  car.speed = 30
  for i = 11, #full, 25 do
    car.lat, car.lon = full[i][1], full[i][2]
    frames(1, 1.0)
    if runner.state() ~= 'running' then break end
  end
  local res4 = events.results('test3', 'hill').runs
  local last4 = res4[#res4]
  T.check(last4 and last4.missedAtc and last4.penaltyS == 60, 'the missed time control in the result: +60 s')
  T.check(events.best('test3', 'hill') == last4.timeS, 'its best time')
  runner.abort(true)
end

------------------------------------------------------------------------------------------ which line a stage runs on
do
  local st = event.stages[1]
  files['/earthRally/events/test5.json'] = nil
  events.forget()
  -- a matched line from this map, and a recce saved short ("Save anyway", 60 %): the matched line covers the stage
  files['/earthRally/matched/test5__hill.json'] = { format = 1, points = recFrom, mapKey = events.mapKey(st.line) }
  files['/earthRally/recce/test5__hill.json'] = { format = 1, points = recFrom, share = 0.6 }
  local _, kind = events.stageLine('test5', 'hill', st)
  T.check(kind == 'matched', 'a recce saved short loses to a whole matched line (' .. tostring(kind) .. ')')
  files['/earthRally/recce/test5__hill.json'] = { format = 1, points = recFrom, share = 0.95 }
  events.forget()
  _, kind = events.stageLine('test5', 'hill', st)
  -- (recFrom stops 40 m before the flying finish, as the 1.0 recce on Maryhill did; the matched line goes on past it)
  local wholeLine = {}
  for k = 1, #full, 4 do wholeLine[#wholeLine + 1] = { full[k][1], full[k][2], full[k][3] } end
  files['/earthRally/matched/test5__hill.json'].points = wholeLine
  events.forget()
  _, kind = events.stageLine('test5', 'hill', st)
  T.check(kind == 'matched', 'a recce stopping 40 m before the flying finish loses to a whole matched line (' .. tostring(kind) .. ')')
  local whole = {}
  for k, p in ipairs(recFrom) do whole[k] = p end
  whole[#whole + 1] = { full[2900][1], full[2900][2], 130 }
  files['/earthRally/recce/test5__hill.json'] = { format = 1, points = whole, share = 0.95 }
  events.forget()
  _, kind = events.stageLine('test5', 'hill', st)
  T.check(kind == 'recce', 'a full recce first')
  -- the junctions and bridges kept with the matched line, as the notes take them
  files['/earthRally/matched/test5__hill.json'].junctions = { { 47.0, -123.0, 'turn', '' }, { 47.0, -123.0, 'straight', '' },
    { 47.0, -123.0, 'fork', 'left' }, { 47.0, -123.0, 'fork', 'right' } }
  files['/earthRally/matched/test5__hill.json'].bridges = { { 47.0, -123.0, 47.0001, -123.0 } }
  local types = {}
  for _, l in ipairs(events.landmarks('test5', 'hill', st)) do types[#types + 1] = l.type end
  T.check(table.concat(types, ' ') == 'atJunction pastJunction keepLeft keepRight overBridge',
    'junctions and bridges from the matched line (' .. table.concat(types, ' ') .. ')')
  -- a matched line from an older version of the map is not used
  files['/earthRally/recce/test5__hill.json'] = nil
  files['/earthRally/matched/test5__hill.json'].mapKey = '1:0:0:0:0'
  events.forget()
  local l3 = events.stageLine('test5', 'hill', st)
  T.check(l3 == nil, 'a matched line made from another version of the map: not used')
end

------------------------------------------------------------------------------------------ no notes where the map has no road
do
  local writer = require('earthRally/stageWriter')
  -- a straight line with a sharp bend at 1000 m and another at 2000 m; the second on a stretch with no road
  local line, x, y, h = {}, 0, 0, math.pi / 2
  local function step() x, y = x + math.cos(h), y + math.sin(h) line[#line + 1] = { x = x, y = y, z = 0 } end
  line[1] = { x = 0, y = 0, z = 0 }
  for k = 1, 3000 do
    if (k > 1000 and k <= 1047) or (k > 2000 and k <= 2047) then h = h - (math.pi / 2) / 47 end
    step()
  end
  local qf = function() return 0, 0, 0, 1 end
  local all = writer.build(line, { startM = 100, finishM = 2900, quatFn = qf })
  local muted = writer.build(line, { startM = 100, finishM = 2900, quatFn = qf, mute = { { 1950, 2100 } } })
  T.check(all.corners == 2 and muted.corners == 1, 'the corner on the stretch with no road gets no note (' ..
    all.corners .. ' / ' .. muted.corners .. ')')

  -- junctions and bridges: a turn at a junction on the first bend, a side road and a bridge on the straight, a fork,
  -- and a junction on the stretch with no road (no call)
  local lm = writer.build(line, { startM = 100, finishM = 2900, quatFn = qf, mute = { { 1950, 2100 } }, landmarks = {
    { s = 1020, type = 'atJunction' }, { s = 500, type = 'pastJunction' }, { s = 700, type = 'overBridge' },
    { s = 1500, type = 'keepLeft' }, { s = 2020, type = 'pastJunction' } } })
  local found = {}
  for _, pn in ipairs(lm.notebook.pacenotes) do
    local it = pn.structured.items
    local kinds = {}
    for k = 1, 6 do if it[tostring(k)].type then kinds[#kinds + 1] = k .. ':' .. it[tostring(k)].type end end
    found[#found + 1] = table.concat(kinds, ',')
  end
  local got = table.concat(found, ' | ')
  T.check(got == '5:pastJunction | 5:overBridge | 4:corner,5:atJunction | 2:keepLeft',
    'junctions and bridges called, in order, on their corner or on their own, none where there is no road (' .. got .. ')')
  T.check(lm.landmarks == 4 and lm.corners == 1, 'four calls, the one corner (' .. lm.landmarks .. ', ' .. lm.corners .. ')')
  local inOrder = true
  for k = 2, #lm.notebook.pacenotes do
    local a = lm.notebook.pacenotes[k - 1].pacenoteWaypoints[1].pos
    local b = lm.notebook.pacenotes[k].pacenoteWaypoints[1].pos
    if b[2] < a[2] and b[1] >= a[1] then inOrder = false end
  end
  T.check(inOrder and lm.notebook.pacenotes[1].triggerType == 15, 'notes in driving order, the first one immediate')
end

------------------------------------------------------------------------------------------ a far ATC, late minutes
do
  local ev6 = { format = 1, id = 'test6', name = 'Test Rally 6', stages = { {
    id = 'hill', name = 'Hill', lengthM = 3000, radiusM = 1200, centre = event.stages[1].centre,
    controls = { start = event.stages[1].controls.start, ff = event.stages[1].controls.ff,
                 atc = { lat = full[11][1] - 600 / 111195, lon = full[11][2] } },      -- 600 m before the start
    line = event.stages[1].line } } }
  files['/earthRally/events/test6.json'] = ev6
  files['/earthRally/matched/test6__hill.json'] = { format = 1, points = recFrom }
  anchor = { lat = 47.0, lon = -123.0 }
  car.lat, car.lon, car.speed = full[1][1] - 0.02, full[1][2], 0
  runner.start(ev6, ev6.stages[1])
  frames(80)
  local r6 = runner.current()
  local ax, ay = toGame(ev6.stages[1].controls.atc.lat, ev6.stages[1].controls.atc.lon)
  car.lat, car.lon = toGeo(ax, ay - 5)
  car.speed = 8 frames(1) car.speed = 0 frames(3)
  local gap = r6.startAt and (r6.startAt - runner.clock()) or 0
  -- 600 m x 1.3 at 10 m/s = 78 s, + 20 s to stop: at least ~98 s, on a half minute
  T.check(gap >= 95 and gap <= 130, 'a start line 600 m from the ATC: time to get there (' .. string.format('%.0f', gap) .. ' s)')
  -- arrive 55 s late: one minute late (+10 s), not two
  while runner.clock() < r6.startAt + 55 do frames(1) end
  car.lat, car.lon, car.speed = full[9][1], full[9][2], 0
  frames(2)
  T.check(r6.latePenalty == 10, 'under a minute late: +10 s (' .. tostring(r6.latePenalty) .. ')')
  runner.abort(true)
end

------------------------------------------------------------------------------------------ the car set down on the road
do
  -- the road map: the stage's road (running north from its first point), nodes every 10 m from 1 km south of it to
  -- its bend, in game coordinates for the world's origin of the moment (it moves to the stage's centre during a run)
  local function roadMap()
    local nodes, prev = {}, nil
    local x0, y0 = toGame(full[1][1], full[1][2], 0)
    for k = -100, 100 do
      local n = 'r' .. k
      nodes[n] = { pos = vec3(x0, y0 + k * 10, 100 + k * 0.1), radius = 3, links = {} }
      if prev then nodes[n].links[prev] = {} nodes[prev].links[n] = {} end
      prev = n
    end
    return nodes
  end
  map = { getMap = function() return { nodes = roadMap() } end }
  -- (the car against the road: across it, and along it from the start)
  local function carXY()
    local x, y = toGame(car.lat, car.lon, 0)
    local rx, ry = toGame(full[1][1], full[1][2], 0)
    return x - rx, y - ry
  end
  local function at(lat, lon) local x, y = toGame(lat, lon, 0) local rx, ry = toGame(full[1][1], full[1][2], 0) return x - rx, y - ry end

  -- Run stage: an ATC drawn 8 m east of the road, 600 m before the start: the car on the road 40 m before it
  local ax0, ay0 = toGame(full[11][1] - 600 / 111195, full[11][2])
  local alat, alon = toGeo(ax0 + 8, ay0)
  local _, atcY = at(full[11][1] - 600 / 111195, full[11][2])
  local ev7 = { format = 1, id = 'test7', name = 'Test Rally 7', stages = { {
    id = 'hill', name = 'Hill', lengthM = 3000, radiusM = 1200, centre = event.stages[1].centre,
    controls = { start = event.stages[1].controls.start, ff = event.stages[1].controls.ff, atc = { lat = alat, lon = alon } },
    line = event.stages[1].line } } }
  files['/earthRally/events/test7.json'] = ev7
  files['/earthRally/matched/test7__hill.json'] = { format = 1, points = recFrom }
  anchor = { lat = 47.0, lon = -123.0 }
  car.lat, car.lon, car.speed = full[1][1] - 0.02, full[1][2], 0
  runner.start(ev7, ev7.stages[1])
  frames(80)
  local x, y = carXY()
  T.check(runner.current().state == 'toAtc' and math.abs(x) < 0.5 and math.abs(y - (atcY - 40)) < 2,
    'Run stage: the car on the road 40 m before an ATC drawn off it (' .. string.format('%.1f, %.1f', x, y - atcY) .. ')')
  runner.abort(true)

  -- driven to the ATC (Route to start), no teleport: the car is not moved
  local nx, ny = toGame(alat, alon)
  car.lat, car.lon, car.speed = toGeo(nx - 30, ny - 60)
  car.speed = 0
  local before = { car.lat, car.lon }
  runner.start(ev7, ev7.stages[1])
  frames(80)
  T.check(runner.current().state == 'toAtc' and car.lat == before[1] and car.lon == before[2] and
    runner.current().checks.atcSetDown == 'driven there', 'driven to the ATC: left where it is')
  runner.abort(true)

  -- Route to start: to the ATC when the stage has its own, else to the start
  local la, lo, what = runner.arrivalPoint(ev7.stages[1])
  T.check(what == 'ATC' and la == alat and lo == alon, 'Route to start: to the stage\'s ATC (' .. tostring(what) .. ')')
  la, lo, what = runner.arrivalPoint(event.stages[1])
  T.check(what == 'start' and la == full[11][1], 'Route to start: to the start when there is no ATC')

  -- traffic and parked cars: out of the way once checked in at the ATC (their active amounts 0, as BeamNG.Earth does
  -- over a teleport), the player's amounts back at the tidy-up
  local tAmount, pAmount = 8, math.huge
  gameplay_traffic = { getState = function() return 'on' end, getTrafficVars = function() return { activeAmount = tAmount } end,
    setActiveAmount = function(n) tAmount = n end }
  gameplay_parking = { getState = function() return true end, getParkingVars = function() return { activeAmount = pAmount } end,
    setActiveAmount = function(n) pAmount = n end }
  car.lat, car.lon, car.speed = full[1][1] - 0.02, full[1][2], 0
  runner.start(ev7, ev7.stages[1])
  frames(80)
  T.check(tAmount == 8 and pAmount == math.huge, 'traffic and parked cars still there on the way to the ATC')
  local ax1, ay1 = toGame(alat, alon)
  car.lat, car.lon = toGeo(ax1 - 8, ay1 - 5)
  car.speed = 8 frames(1) car.speed = 0 frames(3)
  T.check(runner.current().startAt and tAmount == 0 and pAmount == 0, 'checked in at the ATC: traffic and parked cars out of the way')
  runner.abort(true)
  T.check(tAmount == 8 and pAmount == math.huge, 'after the run: the player amounts back')
  getObjectByID, gameplay_traffic, gameplay_parking = nil, nil, nil

  -- Go to start with the stage's line on the roads: on it, 4 m behind the start, whatever the organisers' point
  local sx, sy = toGame(full[11][1], full[11][2], 0)
  local _, sAlong = at(full[11][1], full[11][2])
  car.lat, car.lon = toGeo(sx - 12, sy + 3)        -- (where the teleport put it: 12 m left, in the trees)
  local placed, how = runner.faceStage(event.stages[1], 'test')
  x, y = carXY()
  T.check(placed and how == 'stage line' and math.abs(x) < 0.5 and math.abs(y - (sAlong - 4)) < 1.5,
    'Go to start: on the stage line behind the start (' .. tostring(how) .. ', ' .. string.format('%.1f, %.1f', x, y - sAlong) .. ')')

  -- Go to start on a stage with no line on the roads yet: on the road map's road beside the start
  local ev8 = { format = 1, id = 'test8', name = 'Test Rally 8', stages = { {
    id = 'hill', name = 'Hill', lengthM = 3000, radiusM = 1200, centre = event.stages[1].centre,
    controls = { start = { lat = select(1, toGeo(sx + 9, sy)), lon = select(2, toGeo(sx + 9, sy)) } },
    line = event.stages[1].line } } }
  car.lat, car.lon = toGeo(sx + 9, sy)
  placed, how = runner.faceStage(ev8.stages[1], 'test8')
  x, y = carXY()
  T.check(placed and how == 'road map' and math.abs(x) < 0.5 and math.abs(y - (sAlong - 4)) < 1.5,
    'Go to start, no stage line: on the road map\'s road (' .. tostring(how) .. ', ' .. string.format('%.1f, %.1f', x, y - sAlong) .. ')')
  map = nil
end

------------------------------------------------------------------------------------------ skipping the wait on the start line
do
  anchor = { lat = 47.0, lon = -123.0 }
  car.lat, car.lon, car.speed = full[1][1] - 0.02, full[1][2], 0
  runner.start(event, event.stages[1])
  frames(1)
  T.check(not runner.canSkip(), 'no skip before the start line (' .. runner.state() .. ')')
  frames(80)
  car.lat, car.lon, car.speed = full[9][1], full[9][2], 0
  frames(20)
  local r = runner.current()
  T.check(runner.state() == 'waitStart', 'waiting on the start line (' .. runner.state() .. ')')
  -- (a start time well ahead, as after an early arrival)
  r.startAt = math.ceil((runner.clock() + 70) / 30) * 30
  r.staged, r.jumpStart = nil, nil      -- (the car moved by hand onto the line above: not a jump start)
  r.prevLeft = nil
  frames(1)
  car.speed = 3
  T.check(not runner.onGameplayInteract(), 'no skip while rolling')
  car.speed = 0
  lines = {}
  T.check(runner.onGameplayInteract() == true, 'Interact on the line: skipped')
  T.check(math.abs((r.startAt - runner.clock()) - 6) < 0.05, '6 s to go after the skip (' ..
    string.format('%.2f', r.startAt - runner.clock()) .. ')')
  T.check(not runner.onGameplayInteract(), 'not again straight away, nor inside the last seconds')
  for _ = 1, 600 do frames(1) if runner.state() == 'running' then break end end
  local order = table.concat(lines, ' ')
  T.check(runner.state() == 'running' and math.abs(runner.clock() - r.startAt) < 0.2, 'GO at the start time after a skip')
  T.check(not order:find('warningSeconds10') and not order:find('warningSeconds30') and order:find('countdown5') and
    order:find('countdowngo'), 'after a skip: only 5-4-3-2-1-go (' .. order .. ')')
  runner.abort(true)
end

------------------------------------------------------------------------------------------ 1.2.0: settings in the run, the HUD
local settings = require('earthRally/settings')
local toasts = {}
guihooks = { trigger = function(name, d) if name == 'toastrMsg' then toasts[#toasts + 1] = d end end }
local function toastTitled(pat)
  for _, t in ipairs(toasts) do if tostring(t.title):find(pat) then return t end end
end
-- (a run of `ev` from far off to the start line, waiting there; the start time brought close)
local function toTheLine(ev)
  anchor = { lat = 47.0, lon = -123.0 }
  car.lat, car.lon, car.speed = full[1][1] - 0.02, full[1][2], 0
  local ok5, why5 = runner.start(ev, ev.stages[1])
  frames(80)
  car.lat, car.lon, car.speed = full[9][1], full[9][2], 0
  frames(20)
  local r5 = runner.current()
  return r5, ok5, why5
end
local function go(r5)
  r5.startAt = math.min(r5.startAt, runner.clock() + 2)
  r5.staged, r5.jumpStart = nil, nil      -- (the car moved by hand onto the line: not a jump start)
  for _ = 1, 100 do frames(1) if runner.state() == 'running' then break end end
end
local function driveTo(i0, i1, step)
  for i = i0, i1, step or 25 do
    car.lat, car.lon = full[i][1], full[i][2]
    frames(1, 1.0)
    if runner.state() ~= 'running' then break end
  end
end

-- the reset penalty: +10 s a reset during the timed stage, in the result
do
  settings.reset()
  local r5 = toTheLine(event)
  T.check(not runner.onVehicleResetted(1), 'a reset before the start costs nothing')
  go(r5)
  T.check(runner.state() == 'running', 'running (reset penalty run)')
  T.check(runner.onVehicleResetted(1) == true and r5.resets == 1, 'a reset on the stage: counted')
  T.check(toastTitled('Reset: %+10 s') ~= nil, 'a toast says so')
  T.check(not runner.onVehicleResetted(1) and r5.resets == 1, 'the same reset heard twice: counted once')
  frames(10)
  moveAnchor(anchor.lat, anchor.lon, 'rebase')
  T.check(not runner.onVehicleResetted(1) and r5.resets == 1, 'just after the world moved: not the player\'s reset')
  frames(30)
  T.check(runner.onVehicleResetted(1) == true and r5.resets == 2, 'a second reset')
  settings.set('resetPenalty', false)
  frames(10)
  T.check(not runner.onVehicleResetted(1) and r5.resets == 2, 'setting off: not counted')
  settings.set('resetPenalty', true)
  driveTo(11, #full)
  T.check(runner.state() == 'finished', 'finished (reset penalty run: ' .. runner.state() .. ')')
  local runs = events.results('test', 'hill').runs
  local last5 = runs[#runs]
  T.check(last5.resets == 2 and last5.resetPenaltyS == 20 and last5.penaltyS == 20 and
    math.abs(last5.timeS - last5.stageS - 20) < 1e-9, 'the resets in the result: +20 s in the time')
  -- the results card: the HUD frame, Retry starts the stage again
  local rl, ours = runner.uiFrame()
  T.check(rl.activeState == 'inactive' and ours.finish and ours.finish.penalties.resets == 20 and
    ours.finish.penalties.resetCount == 2, 'the HUD has the resets itemised')
  T.check(r5.resultsOpen and r5.sinceFinish ~= nil, 'the results card open at the flying finish (no stop control)')
  frames(50)
  rl, ours = runner.uiFrame()
  T.check(ours.show.results and ours.results.finish.time == r5.finalTime and ours.results.next == nil,
    'the results card after the big time (the last stage: no Next stage)')
  T.check(runner.resultsAction('next') == false, 'no next stage on a one-stage rally')
  local okR = runner.resultsAction('retry')
  T.check(okR and runner.current() ~= r5 and runner.state() == 'travel', 'Retry: the stage again from the start')
  runner.abort(true)
  settings.reset()
end

-- quick start (no ATC), no zone brake, the clock view off; the HUD through every state of a run
do
  local hooks = {}
  extensions.hook = function(name, d) if name == 'onRallyDataUpdated' then hooks[#hooks + 1] = d end end
  local ev8 = { format = 1, id = 'test8', name = 'Test Rally 8', stages = { {
    id = 'hill', name = 'Hill', lengthM = 3000, radiusM = 1200, centre = event.stages[1].centre,
    controls = { start = event.stages[1].controls.start, ff = event.stages[1].controls.ff,
                 atc = { lat = full[11][1] - 150 / 111195, lon = full[11][2] } },
    line = event.stages[1].line }, { id = 'two', name = 'Two', lengthM = 4000, line = event.stages[1].line } } }
  files['/earthRally/events/test8.json'] = ev8
  events.saveRecce('test8', 'hill', { format = 1, points = recFrom, lengthM = 3000 })
  T.check(select(3, runner.arrivalPoint(ev8.stages[1])) == 'ATC', 'full time controls: Route to start goes to the ATC')
  settings.set('timeControls', 'quick')
  settings.set('zoneBrake', false)
  settings.set('clockView', 'off')
  T.check(select(3, runner.arrivalPoint(ev8.stages[1])) == 'start', 'quick start: Route to start goes to the start')
  anchor = { lat = 47.0, lon = -123.0 }
  car.lat, car.lon, car.speed = full[1][1] - 0.02, full[1][2], 0
  T.check(runner.start(ev8, ev8.stages[1]), 'the quick-start run starts')
  local r8 = runner.current()
  T.check(r8.atc == nil and r8.ss == 1 and r8.ssCount == 2 and r8.nextStage and r8.nextStage.name == 'Two',
    'quick start: no ATC; SS1 of 2, the next stage known')
  local seen = {}
  local function look()
    local rl, ours = runner.uiFrame()
    seen[runner.state()] = { rl = rl, ours = ours }
  end
  car.speed = 3
  for _ = 1, 80 do frames(1) look() if runner.state() == 'toStart' then break end end
  T.check(runner.state() == 'toStart', 'quick start: set down for the start line (' .. runner.state() .. ')')
  -- roll onto the line: no zone brake
  inputs = {}
  car.lat, car.lon, car.speed = full[9][1], full[9][2], 3
  frames(2)
  look()
  local braked = false
  for _, c in ipairs(inputs) do if c:find('earthRally_ctl("zone"', 1, true) then braked = true end end
  T.check(not braked, 'zone brake off: no brake in the start zone')
  car.speed = 0
  for _ = 1, 20 do frames(1) look() end
  T.check(runner.state() == 'waitStart' and r8.startAt - runner.clock() <= runner.NO_ATC_START_S,
    'stopped on the line: the start a few seconds on (' .. runner.state() .. ')')
  hooks = {}
  for _ = 1, 200 do frames(1) look() if runner.state() == 'running' then break end end
  local cd = false
  for _, d in ipairs(hooks) do if d.activeState == 'countdown' then cd = true end end
  T.check(not cd and #hooks > 0, 'clock view off: the start clock never told "countdown" (its view stays off)')
  T.check(runner.state() == 'running', 'GO (quick start)')
  car.speed = 30
  for i = 11, #full, 25 do
    car.lat, car.lon = full[i][1], full[i][2]
    frames(1, 1.0)
    look()
    if runner.state() ~= 'running' then break end
  end
  look()
  frames(1)
  look()
  -- what the HUD showed in each state
  T.check(seen.toStart and seen.toStart.rl.activeState == 'vehicleProximity' and seen.toStart.rl.scheduleData.label == 'SS1',
    'HUD to the start: the stock proximity, SS1')
  T.check(seen.waitStart and seen.waitStart.rl.activeState == 'countdown' and seen.waitStart.rl.countdownData.countdown ~= nil,
    'HUD on the line: the stock countdown')
  local run = seen.running
  T.check(run and run.rl.activeState == 'stageActive' and run.rl.uiColors.theme and run.rl.stageData.stageHeader == 'SS1 · HILL'
    and run.ours.show.km and run.ours.totalM > 2800, 'HUD on the stage: stage time, progress, our km')
  T.check(seen.finished and seen.finished.ours.finish and seen.finished.ours.finish.first,
    'HUD at the finish: the first time on this stage')
  T.check(toastTitled('Hill: ') ~= nil, 'a toast with the time at the flying finish')
  -- off route: the amber card once 60 m off, gone within 40 m
  runner.abort(true)
  settings.reset()
end

-- off route on a real run, with the way back
do
  local r9 = toTheLine(event)
  go(r9)
  car.speed = 20
  driveTo(11, 900)
  local fx, fy = toGame(full[900][1], full[900][2])
  veh.getDirectionVector = function() return { x = 0, y = 1, z = 0 } end   -- (heading north, along the stage)
  car.lat, car.lon = toGeo(fx + 80, fy)
  frames(1)
  local _, ours = runner.uiFrame()
  T.check(r9.offRoute and ours.show.offRoute and ours.offM > 60 and math.abs(ours.backBearing + 90) < 5,
    '80 m right of the line: off route, the way back to the left (' .. tostring(ours.backBearing) .. ')')
  car.lat, car.lon = toGeo(fx + 50, fy)
  frames(1)
  T.check(r9.offRoute, 'still off route at 50 m (no flicker)')
  car.lat, car.lon = toGeo(fx + 20, fy)
  frames(1)
  _, ours = runner.uiFrame()
  T.check(not r9.offRoute and not ours.show.offRoute and ours.show.km, 'back on the line: the card gone')
  veh.getDirectionVector = nil
  runner.abort(true)
end

-- main.lua: the menu page's data and buttons, the HUD's streams, the preview, Ctrl+Alt+K
do
  ui_imgui = { BoolPtr = function(v) return { [0] = v } end, ImVec4 = function() return {} end }
  local navs = {}
  ui_router = { navigate = function(r) navs[#navs + 1] = r end }
  local streams = {}
  guihooks.queueStream = function(k, v) streams[#streams + 1] = { k = k, v = v } end
  local main = require('earthRally/main')
  settings.reset()
  events.list(true)          -- (the rallies added by the tests above: read again, as an import does)
  local st = main.uiState()
  T.check(st.version == main.VERSION and #st.rallies >= 3 and #st.settings.schema == 6 and st.settings.settings.units == 'km'
    and st.importFolder, 'uiState: the rallies, the settings, the import folder')
  local rr = main.uiRally('test8')
  T.check(rr.name == 'Test Rally 8' and #rr.list == 2 and rr.list[1].status == 'ready' and rr.list[2].status == 'none',
    'uiRally: the stages and their status')
  local ss = main.uiStage('test8', 'hill')
  T.check(ss.atc and ss.canDrive and ss.ss == 1 and ss.name == 'Hill', 'uiStage: SS1 Hill, with its ATC')
  T.check(main.uiStage('test8', 'nope').missing, 'uiStage: an unknown stage')
  T.check(main.uiSet('units', 'mi').ok and settings.get('units') == 'mi', 'uiSet: a setting changed')
  settings.reset()
  local a = main.uiAction('drive', 'test8', 'nope')
  T.check(not a.ok and a.message, 'a button for a stage that is not there: refused, said why')
  -- Ctrl+Alt+K: the page, again: back to driving
  main.toggleMenu()
  main.onUiChangedState('earthRally')
  main.toggleMenu()
  T.check(navs[1] == 'earthRally' and navs[2] == 'play', 'Ctrl+Alt+K opens the menu page and closes it')
  main.onUiChangedState('play')
  -- Drive stage from the page: the run starts, the page closes
  anchor = { lat = 47.0, lon = -123.0 }
  car.lat, car.lon, car.speed = full[1][1] - 0.02, full[1][2], 0
  navs = {}
  a = main.uiAction('drive', 'test8', 'hill')
  T.check(a.ok and runner.current() and navs[1] == 'play', 'Drive stage: the run starts, back to the game')
  T.check(not main.uiAction('drive', 'test8', 'hill').ok, 'not a second run while one is under way')
  -- the streams: both, every frame or so
  streams = {}
  for _ = 1, 10 do main._sendStreams(0.05) end
  local kinds = {}
  for _, x in ipairs(streams) do kinds[x.k] = (kinds[x.k] or 0) + 1 end
  T.check((kinds.rallyLoop or 0) >= 5 and (kinds.earthRally or 0) >= 5, 'both streams queued (' ..
    tostring(kinds.rallyLoop) .. ', ' .. tostring(kinds.earthRally) .. ')')
  T.check(main.previewHud() == false, 'no HUD preview during a run')
  main.uiAction('abort')
  streams = {}
  main._sendStreams(0.05)
  main._sendStreams(0.05)
  T.check(#streams == 2 and streams[1].v.activeState == 'inactive' and streams[2].v.state == 'idle',
    'the run gone: the stock apps told inactive once, ours idle')
  -- the HUD preview: the stage layout on, sample frames, the layout back
  layout = 'beamngEarth'
  T.check(main.previewHud() and layout == 'earthRallyStage', 'HUD preview: the stage layout on')
  streams = {}
  for _ = 1, 2000 do main._sendStreams(0.05) end
  local prevFrames, shown = 0, {}
  for _, x in ipairs(streams) do
    if x.k == 'earthRally' and x.v.preview then
      prevFrames = prevFrames + 1
      for k in pairs(x.v.show) do shown[k] = true end
    end
  end
  T.check(prevFrames > 500 and shown.results and shown.offRoute and shown.bigCount, 'the preview\'s frames went out')
  T.check(layout == 'beamngEarth', 'after the preview: the layout back')
  -- the results card's Rally menu: the card closed, the page opened at the rally
  navs = {}
  T.check(main.uiResults('menu').ok == false and navs[1] == 'earthRally', 'Rally menu with no run: still opens the page')
  local st2 = main.uiState()
  T.check(st2.openAt and st2.openAt.view == 'rally' and main.uiState().openAt == nil, 'the page told where to open, once')
  -- the developer panel follows its setting
  settings.set('devPanel', true)
  T.check(main.onUpdate ~= nil, 'main loaded')
  settings.reset()
end

T.done('test_run')
