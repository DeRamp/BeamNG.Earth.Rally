-- A whole run against a stand-in game and BeamNG.Earth (no BeamNG needed): the recce saved, then a run that travels,
-- moves the world's origin to the stage's centre, writes and loads the rally files (our heights kept), counts down,
-- survives a world shift mid-stage and finishes at the flying finish with a saved time.
local T = dofile(TESTS .. '/testlib.lua')

------------------------------------------------------------------------------------------ the stand-in game

local files = {}
function jsonWriteFile(path, data) files[path] = data return true end
function jsonReadFile(path) return files[path] end
-- (the game's own art, which the stage dressing looks for once per shape: all there, as in the game)
FS = {
  fileExists = function(_, path)
    if path:match('^/art/') or path:match('^/assets/') then return true end
    return files[path] ~= nil
  end,
  removeFile = function(_, path) files[path] = nil end,
  findFiles = function(_, dir, pattern)
    local out = {}
    for k in pairs(files) do if k:sub(1, #dir) == dir and k:match('%.json$') then out[#out + 1] = k end end
    table.sort(out)
    return out
  end,
}
local logErrors = {}
function log(level, tag, msg)
  if level == 'E' then logErrors[#logErrors + 1] = tostring(msg) print('LOG E ' .. tostring(msg)) end
end
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
local stripsMounted = {}      -- BeamNG.Earth's view of which of its strips an app has
beamngEarth_core = {
  rebaseTo = function(lat, lon) moveAsk = { lat = lat, lon = lon, frames = 3 } radiusAtMove = camshift.RADIUS_MAX return true end,
  -- an app saying it is on screen; while one says so, BeamNG.Earth leaves its own imgui drawing of that strip out
  hudApp = function(name, on) stripsMounted[name] = on and true or nil return on and true or false end,
  setRebaseDistance = function(m) rebaseDistance = math.max(2000, math.min(16000, m))
    package.loaded['beamngEarth/rebase'].distance = rebaseDistance return rebaseDistance end,
}

-- the vehicle: its game position from where it is on Earth
local sounds, frozen, inputs, routes, lines = {}, nil, {}, {}, {}
local veh = {
  getPosition = function() local x, y, z = toGame(car.lat, car.lon, car.alt) return vec3(x, y, z) end,
  getDirectionVector = function() return vec3(0, 1, 0) end,
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
-- (#63) the origin moves with the physics on (the loading screen's pause waits: runner.originMoving), the car frozen
-- -- only under a loading screen (runner.loadingUp): never on a load the player is driving through
runner.loadingUp = function() return true end
for _ = 1, 50 do if runner.state() == 'anchor' then break end frames(1) end
T.check(runner.state() == 'anchor' and runner.originMoving() and frozen == true,
  'the origin move: the pause waits for it, the car held still (#63)')
frames(5)
T.check(not runner.originMoving() and frozen == false, 'the origin moved: the car let go, the pause may come on (#63)')
runner.loadingUp = function() return false end
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
T.check(r.checks.notesLoaded == r.checks.notesWritten and r.checks.notesWritten > r.checks.cornersFound,
  'every note written is loaded: one per corner, and the finish (' .. tostring(r.checks.notesLoaded) ..
  ' of ' .. tostring(r.checks.notesWritten) .. ', ' .. tostring(r.checks.cornersFound) .. ' corners)')
T.check(type(r.checks.calls) == 'string' and r.checks.calls:find('finish 1', 1, true) ~= nil,
  'the calls written are listed for the panel (' .. tostring(r.checks.calls) .. ')')
-- The Corners tile is the co-driver's own count, by construction: the tile reads what was worked out from the
-- line (menu.stage -> events.lineFigures -> lineStats.of -> stageWriter.stageCorners) and the run has just
-- written one pacenote per corner the same function found, in the game's own coordinates. If these two ever part,
-- the tile is lying about what will be called. The recce saved above carries no figures of its own -- it stands
-- for a line written by a version before 1.3.1 -- so this also says an older line still gets a number.
do
  local menu = require('earthRally/menu')
  local st = menu.stage('test', 'hill', 'start')
  T.check(st.corners == r.checks.cornersFound, 'the Corners tile is the co-driver\'s own count (' ..
    tostring(st.corners) .. ' vs ' .. tostring(r.checks.cornersFound) .. ')')
  T.check(st.junctions == nil and st.bridges == nil, 'no junctions or bridges tile')
  -- the stage line climbs 10 m in its first kilometre and then runs level east: climb, and no drop
  T.near(st.gainM, 9, 3, 'the stage page has the height the line gains')
  T.check(st.lossM == 0, 'and the height it gives back (' .. tostring(st.lossM) .. ')')
end
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
T.check(camResets >= 2, 'the camera reset after the origin moved and the car was placed (' .. camResets .. ')')
T.check(layout == 'earthRallyStage', 'the pacenote cards layout on for the run (' .. layout .. ')')

-- 1.3.2, the reported bug: this stage's map has no arrival control and the full time controls are on. The car must
-- be set down OUTSIDE the start zone and left alone until it is driven, so the player can wait for the world to
-- load rather than being counted down from where they were put (docs/notes-1.3.0.md #1). This fixture's line
-- begins only 10 m before the start, so the way back along the road runs rather than the way back along the line
-- -- which is the common case in game, where a recce begins on the start line.
local sx, sy = toGame(full[11][1], full[11][2])
local placed = veh.getPosition()
local backM = math.sqrt((placed.x - sx) ^ 2 + (placed.y - sy) ^ 2)
T.check(backM > runner.START_ZONE_BEFORE_M, 'no ATC: the car set down outside the start zone (' ..
  string.format('%.0f m back, the zone is %d m', backM, runner.START_ZONE_BEFORE_M) .. ')')
T.near(backM, runner.CAR_BEFORE_START_M, 3, 'no ATC: set down CAR_BEFORE_START_M before the line')
T.check((r.checks.startSetDown or ''):find('before the line') ~= nil,
  'the run says where it put the car (' .. tostring(r.checks.startSetDown) .. ')')
frames(60)
T.check(runner.state() == 'toStart' and r.startAt == nil,
  'left standing where it was put: no start time, however long (' .. tostring(r.startAt) .. ')')
T.check(frozen ~= true, 'and not held on the line')

-- Rolling forward five metres and stopping is not the line either, and this is the half of it a movement guard
-- alone would miss: the car HAS been driven now, so the guard has lifted, and `along` cannot read less than 0 on a
-- line that begins 10 m before the start -- it is the distance to the start itself that keeps it out of the zone.
do
  local la, lo = toGeo(placed.x, placed.y + 5)
  car.lat, car.lon, car.speed = la, lo, 4
  frames(2)
  car.speed = 0
  frames(8)
  T.check(r.startAt == nil, 'five metres on and stopped: still 20 m short of the line, so not on it (' ..
    tostring(r.startAt) .. ')')
  T.check(frozen ~= true, 'and not held there')
end

-- The flag reaches the start trigger, which neither the run above nor the predicate's own tests prove on their
-- own: a car ON the line, standing still, with the flag still set, must not start anything. (Set by hand because
-- this fixture cannot place a car there -- it takes a start inside a hairpin, and there is no road map here to
-- bend round. runner.onStartLine's tests cover the geometry; this covers the wiring.)
do
  r.startPlaced = { lat = full[11][1], lon = full[11][2] }
  car.lat, car.lon, car.speed = full[11][1], full[11][2], 0
  frames(10)
  T.check(r.startAt == nil, 'the flag reaches the trigger: on the line, standing, and nothing starts')
  T.check(r.startPlaced ~= nil, 'and standing still never lifts it')
  T.check(frozen ~= true, 'and the car is not held there')
end

-- drive up to the line and stop there: now it counts (and the flag set above lifts as the car moves)
car.lat, car.lon, car.speed = full[4][1], full[4][2], 8
frames(2)
car.lat, car.lon, car.speed = full[11][1], full[11][2], 0
frames(8)
T.check(frozen == true and lastCtl() == 'launch' and has(sounds, 'event:UI_Checkpoint'),
  'drove up and stopped on the line: held (the game freeze, launch control on), a sound')
T.check(r.startAt ~= nil, 'and a start time from the moment it stopped')
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
do
  local info = events.stageLineInfo('test', event.stages[1].id, event.stages[1])
  local x = res.runs[1]
  T.check(info and x.lineKey == info.key and x.line == info.kind and type(x.lineM) == 'number' and
    math.abs(x.lineM - (r.finishM - r.startM)) <= 1,
    'the time records the line it was driven on: its identity and its length start to flying finish as timed')
  -- (the recce stops short of the flying finish: the runner times on to it over its run-out, and so does the menu)
  T.check(info and math.abs(x.lineM - info.lengthM) <= 5,
    'and the menu measures the same line, run-out to the flying finish included, to within 5 m (' ..
    tostring(x.lineM) .. ' vs ' .. tostring(info and info.lengthM) .. ')')
  local geo = require('earthRally/geo')
  local function near(a, b) return a and b and geo.metres(a[1], a[2], b[1], b[2]) < 5 end
  T.check(near(x.lineStart, info and info.start) and near(x.lineFinish, info and info.finish) and
    near(x.lineFinish, full[2900]), 'the time records where its start and flying finish were on the line')
  T.check(events.onLine(x, info) and events.bestPlaceable('test', event.stages[1].id, event.stages[1]) == x.timeS,
    'and it is placed on the line it was driven on')
  T.check(r.ssLabel == 'SS1', 'an event with no itinerary: the run carries SS1 by map order (' .. tostring(r.ssLabel) .. ')')
end
T.check(events.addResult('test', 'hill', { finished = true, timeS = 99 }) == 99 and #events.results('test', 'hill').runs == 2,
  'a second time kept beside the first, the best of both')
runner.abort(true)
T.check(manager == nil, 'the co-driver unloaded when the run is closed')
T.check(layout == 'beamngEarth', 'BeamNG.Earth layout back')

------------------------------------------- back along the line, where there is line to back along
-- The fixture above has only 10 m of line before its start, so the car went back along the ROAD. A stage whose
-- line reaches further back than CAR_BEFORE_START_M -- a recce begun well before the line, which is what
-- LINE_BEFORE_START_M keeps -- backs up along the line itself instead, following its bends.
do
  local evL = { format = 1, id = 'backline', name = 'Back along the line', stages = { {
    id = 'hill', name = 'Hill', lengthM = 3000, radiusM = 1200,
    centre = { lat = 47.009, lon = -122.990 },
    controls = { start = { lat = full[60][1], lon = full[60][2] }, ff = { lat = full[2900][1], lon = full[2900][2] } },
    line = mapLine } } }
  files['/earthRally/events/backline.json'] = evL
  events.saveRecce('backline', 'hill', { format = 1, points = recPts, lengthM = 3000 })
  car.lat, car.lon, car.speed = full[1][1] - 0.01, full[1][2], 0        -- 1 km away: travelled to
  local okL, whyL = runner.start(evL, evL.stages[1])
  T.check(okL, 'the run starts on a stage whose line reaches well before the start (' .. tostring(whyL) .. ')')
  frames(80)     -- (the teleport: 2 s, the world 2 s settled, the origin moved, the stage built)
  local rL = runner.current()
  T.check((rL.checks.startSetDown or ''):find('along the line') ~= nil,
    'back along the line, not along the road (' .. tostring(rL.checks.startSetDown) .. ')')
  local bx, by = toGame(full[60][1], full[60][2])
  local cpL = veh.getPosition()
  T.near(math.sqrt((cpL.x - bx) ^ 2 + (cpL.y - by) ^ 2), runner.CAR_BEFORE_START_M, 3,
    'and CAR_BEFORE_START_M back from the start')
  T.check(rL.startAt == nil, 'with no start time until it is driven up')
  runner.abort(true)
end

------------------------------------------- is the car on the start line? (runner.onStartLine)
-- The predicate the start trigger is made of, case by case, because the case that mattered in game cannot be
-- reached from this fixture: a start inside a hairpin, where the line begins a few metres before the start and the
-- road back bends round, so a car set down 25 m back along the road sits a metre or two from the line's first
-- point. geo.locate clamps to the line's ends, so `along` reads 0 there and `off` reads a metre or two -- both
-- terms say "on the line" about a car that was put there and has not moved. Only the placed flag says otherwise.
do
  local Z, OFF = runner.START_ZONE_BEFORE_M, runner.START_ZONE_OFF_M
  -- the ordinary approach: 100 m of line before the start
  T.check(runner.onStartLine(100, 0, 100, false) == true, 'stopped on the line itself: on it')
  T.check(runner.onStartLine(100 - Z + 1, 0, 100, false) == true, 'just inside the zone: on it')
  T.check(runner.onStartLine(100 - Z - 1, 0, 100, false) == false, 'a metre further back than the zone: not on it')
  T.check(runner.onStartLine(100, OFF + 1, 100, false) == false, 'beside the line, not on it')
  T.check(runner.onStartLine(104, 0, 100, false) == false, 'driven past the line: not on it')
  -- a line that begins at the start (a driven recce, or a line matched to the stage): along clamps to 0 and the
  -- distance off the line is what keeps a car standing back there out of the zone
  T.check(runner.onStartLine(0, 20, 0, false) == false, 'a line beginning at the start: 20 m back is not on it')
  T.check(runner.onStartLine(0, 0, 0, false) == true, '... and on the line is')
  -- the hairpin: along 0, off 2, the start 10 m along the line. Both geometric terms say yes.
  T.check(runner.onStartLine(0, 2, 10, false) == true,
    'a hairpin start: by the line alone, a car set down 25 m back along the road reads as ON the line')
  T.check(runner.onStartLine(0, 2, 10, true) == false,
    '... so the placed flag is what holds the countdown until the car has been driven')
  T.check(runner.onStartLine(100, 0, 100, true) == false, 'placed and not yet driven is never on the line')
end

------------------------------------------- a car driven to the start
-- The guard above must not touch this one.
--
-- (The "Quick start on the line" setting was tested here too, until 1.3.2 dropped it: it set the car down on the
-- line and started the clock a few seconds later, which is the thing the no-ATC start was fixed to stop doing.
-- The ordinary path now does what it existed for -- away without waiting on a control -- in a way that lets the
-- player set off when they are ready.)
--
-- A car the player drove up themselves is left where they chose, which is what the ATC path does with its own
-- NO_SET_DOWN_M band. Route to start puts them 80 m short of the line; the run must not shuffle them back to 25.
do
  local onLine = 80
  local lx, ly = toGame(full[11][1], full[11][2])
  local la, lo = toGeo(lx, ly - onLine)
  car.lat, car.lon, car.speed = la, lo, 0
  local okD = runner.start(event, event.stages[1])
  T.check(okD, 'the run starts with the car driven to near the line')
  frames(12)
  local rd = runner.current()
  local cpd = veh.getPosition()
  local movedM = math.sqrt((cpd.x - (lx)) ^ 2 + (cpd.y - (ly - onLine)) ^ 2)
  T.check(rd.checks.startSetDown == 'driven there',
    'driven to the start: not moved (' .. tostring(rd.checks.startSetDown) .. ')')
  T.near(movedM, 0, 2, 'driven to the start: the car is where the player left it')
  T.check(rd.startAt == nil, 'and no start time until they drive up and stop')
  runner.abort(true)
end


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
-- ... and saved with what the line says about itself, worked out once here rather than every time the stage page
-- is looked at
do
  local saved = events.recce('test', 'hill')
  T.check(saved.corners == r.checks.cornersFound, 'the recce is saved with the corner count the co-driver calls (' ..
    tostring(saved.corners) .. ' vs ' .. tostring(r.checks.cornersFound) .. ')')
  T.near(saved.gainM, 9, 3, 'and the height it gained')
  T.check(saved.lossM == 0, 'and the height it lost (' .. tostring(saved.lossM) .. ')')
end

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


-- One corner count, two ways in. The number kept with a line and the number the notebook gets are the same
-- function (stageWriter.stageCorners) over the same stretch of road -- but they reach it differently: a run puts
-- the line into the game's coordinates, while a saved line is measured in a flat frame about its own first point.
-- This runs both over a road with a dozen corners in it, out to lat / lon and back, so a disagreement between
-- those two frames would show here rather than on the owner's stage page.
do
  local geo = require('earthRally/geo')
  local writer = require('earthRally/stageWriter')
  local lineStats = require('earthRally/lineStats')
  -- 12 corners: 200 m straight, a 90 degree turn of radius 70 m, the other way next time
  local line, x, y, h = {}, 0, 0, 0
  local function put() line[#line + 1] = { x = x, y = y, z = 200 + y * 0.02 } end
  put()
  for k = 1, 12 do
    for _ = 1, 40 do x, y = x + math.cos(h) * 5, y + math.sin(h) * 5 put() end
    local steps, turn = 22, (k % 2 == 0) and (math.pi / 2) or -(math.pi / 2)
    for _ = 1, steps do h = h + turn / steps x, y = x + math.cos(h) * 5, y + math.sin(h) * 5 put() end
  end
  -- and two long gentle bends, radius 300 m: not corners, and nothing that reads this road more loosely than the
  -- notebook does may call them (the detector's own maxRadius is 200 m)
  for k = 1, 2 do
    local steps, turn = 63, (k % 2 == 0) and (math.pi / 3) or -(math.pi / 3)
    for _ = 1, steps do h = h + turn / steps x, y = x + math.cos(h) * 5, y + math.sin(h) * 5 put() end
    for _ = 1, 40 do x, y = x + math.cos(h) * 5, y + math.sin(h) * 5 put() end
  end
  local cum = geo.cumulative(line)
  local built = writer.build(line, { startM = 0, finishM = cum[#cum], name = 'Wiggle',
    quatFn = function(qx, qy, qz) local q = quatFromDir(vec3(qx, qy, qz), vec3(0, 0, 1)) return q.x, q.y, q.z, q.w end })
  -- the same road as a line file holds it: lat / lon / height, no controls (the whole line is the stage)
  local points = {}
  for i, p in ipairs(line) do
    local la, lo = toGeo(p.x, p.y)
    points[i] = { la, lo, p.z }
  end
  local fig = lineStats.of(points, { id = 'wiggle', controls = {} })
  T.check(built.corners >= 10, 'the wiggly road has its corners (' .. tostring(built.corners) .. ')')
  T.check(fig.corners == built.corners, 'the count kept with a line is the count the notebook gets (' ..
    tostring(fig.corners) .. ' vs ' .. tostring(built.corners) .. ')')
  local cornerNotes = 0
  for _, pn in ipairs(built.notebook.pacenotes) do if pn.metadata.earthRally.dir then cornerNotes = cornerNotes + 1 end end
  T.check(cornerNotes == built.corners, 'one pacenote per corner, so the tile counts the corner notes (' ..
    cornerNotes .. ' vs ' .. built.corners .. ')')
  -- and the corners inside a stretch with no road on the map are not counted, exactly as no notes are called
  -- there: the same flag, the same padding, off the line's own points
  local muted = {}
  for i, p in ipairs(points) do
    muted[i] = { p[1], p[2], p[3] }
    if cum[i] > 1000 and cum[i] < 3000 then muted[i][4] = 1 end
  end
  local figMuted = lineStats.of(muted, { id = 'wiggle', controls = {} })
  T.check(figMuted.corners < fig.corners, 'corners on a stretch with no road on the map are not counted (' ..
    tostring(figMuted.corners) .. ' vs ' .. tostring(fig.corners) .. ')')
end


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
  T.check(manager.notesOn == true and r2.built and r2.built.stopM ~= nil,
    'the notes stay on past the flying finish, on to the stop control (#47)')
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
  -- on the way to the stop control, well off the line: the car's distance along kept, never a whole-line search a
  -- frame (1.4.0's review: progress() past the end looked through every segment of the stage each frame)
  do
    local geo = require('earthRally/geo')
    local plainLocate, segs = geo.locate, 0
    geo.locate = function(pts, cum, p, lo, hi)
      segs = segs + (math.min(#pts - 1, hi or #pts - 1) - math.max(1, lo or 1) + 1)
      return plainLocate(pts, cum, p, lo, hi)
    end
    local keep = { car.lat, car.lon }
    car.lat, car.lon = full[#full][1] + 0.004, full[#full][2] + 0.006      -- (~450 m off the end)
    frames(3)
    geo.locate = plainLocate
    car.lat, car.lon = keep[1], keep[2]
    T.check(runner.state() == 'toStop' and segs > 0 and segs < 3 * 400,
      'to the stop control off the line: a bounded search, not the whole line each frame (' .. segs .. ' segments in 3 frames, the line ' ..
      #r2.line .. ' points)')
  end
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
  local function stopTentNow(x, y)
    for _, o in pairs(objects) do
      if (o.fields.shapeName or ''):find('gazebo_mod_frame') and (o.pos[1] - x) ^ 2 + (o.pos[2] - y) ^ 2 < 15 ^ 2 then
        return true
      end
    end
    return false
  end
  car.speed = 0
  frames(20)
  T.check(runner.state() == 'finished' and r2.checks.stopControl:find('stopped') ~= nil,
    'stopped at the stop control: stage complete')
  T.check(countObjects() > 0, 'stage done: the stop control tent still there a moment after stopping')
  frames(100)
  T.check(countObjects() > 0 and manager == nil and stopTentNow(sx2, sy2),
    'a few seconds later: the co-driver taken away, the stop control\'s tent left standing (#66)')
  T.check(layout == 'earthRallyStage' and r2.resultsOpen, 'the stage layout kept for the results card')
  -- drive off: the card closes, BeamNG.Earth's layout back
  car.lat, car.lon = toGeo(sx2 + 150, sy2)
  frames(1)
  T.check(not r2.resultsOpen and layout == 'beamngEarth', 'driven off: the results card closed, the layout back')
  T.check(countObjects() > 0, 'driven off 150 m: the finish and stop props still there (#66)')
  -- the world shifts: the sites left behind are dropped, not put down again from the finished run's line
  local carAt = { car.lat, car.lon }
  moveAnchor(anchor.lat + 0.01, anchor.lon, 'rebase')
  car.lat, car.lon = carAt[1], carAt[2]
  frames(10)
  T.check(countObjects() == 0, 'a world shift with the stage over: the props left behind taken away (#66)')
  moveAnchor(anchor.lat - 0.01, anchor.lon, 'rebase')
  car.lat, car.lon = toGeo(sx2 + runner.LEFT_DROP_M + 50, sy2)
  frames(10)
  T.check(countObjects() == 0, 'out of their distance: the props left behind taken away (#66)')
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
  -- no recce: the map line matched to the roads (tools/auto_recce.py) instead
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
  -- (the bend after 900 m of straight is a care: 144 km/h down to under 60; the finish has no corner near it, so it
  --  is a note of its own)
  T.check(got == '5:pastJunction | 5:overBridge | 1:caution,4:corner,5:atJunction | 2:keepLeft | 2:finish',
    'junctions and bridges called, in order, on their corner or on their own, none where there is no road (' .. got .. ')')
  T.check(lm.landmarks == 4 and lm.corners == 1, 'four calls, the one corner (' .. lm.landmarks .. ', ' .. lm.corners .. ')')
  local inOrder, geo = true, require('earthRally/geo')
  local lcum = geo.cumulative(line)
  local prev = -1
  for k = 1, #lm.notebook.pacenotes do
    local p = lm.notebook.pacenotes[k].pacenoteWaypoints[1].pos
    local _, _, s = geo.locate(line, lcum, { x = p[1], y = p[2] })
    if s <= prev then inOrder = false end
    prev = s
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

  -- landed ON the ATC point (where the auto recce's teleport puts the car): set down 40 m before the board, never
  -- taken for "driven there" -- the other half of the auto recce landing at the ATC rather than the start
  car.lat, car.lon, car.speed = alat, alon, 0
  runner.start(ev7, ev7.stages[1])
  frames(80)
  local lx, ly = carXY()
  T.check(runner.current().state == 'toAtc' and runner.current().checks.atcSetDown ~= 'driven there'
    and math.abs(ly - (atcY - 40)) < 2,
    'landed on the ATC: set down 40 m before it (' .. tostring(runner.current().checks.atcSetDown) ..
    string.format(', %.1f m', ly - atcY) .. ')')
  runner.abort(true)

  -- parked on the road between the ATC and a far start (60 m past the board, 540 m short of the line): NOT on the
  -- stage, so the player's spot is kept -- the guard below must not move people off approach roads
  car.lat, car.lon, car.speed = toGeo(ax0, ay0 + 60)
  car.speed = 0
  local kept = { car.lat, car.lon }
  runner.start(ev7, ev7.stages[1])
  frames(80)
  T.check(runner.current().state == 'toAtc' and runner.current().checks.atcSetDown == 'driven there'
    and car.lat == kept[1] and car.lon == kept[2],
    'off the stage, short of the start: kept where it was parked (' .. tostring(runner.current().checks.atcSetDown) .. ')')
  runner.abort(true)

  -- ON the stage, an ATC 20 m before the start (8 m off the road), the car behind the line or into the stage: inside
  -- NO_SET_DOWN_M of the ATC, and at +30 m FARTHER from the start than the ATC is -- the case a straight-line "past"
  -- test let through. Go to start, a stopped Recce or a near Auto recce leave cars here; never "driven there".
  local _, startY = at(full[11][1], full[11][2])
  local cx0, cy0 = toGame(full[11][1] - 20 / 111195, full[11][2])
  local clat, clon = toGeo(cx0 + 8, cy0)
  local ev9 = { format = 1, id = 'test9', name = 'Test Rally 9', stages = { {
    id = 'close', name = 'Close', lengthM = 3000, radiusM = 1200, centre = event.stages[1].centre,
    controls = { start = event.stages[1].controls.start, ff = event.stages[1].controls.ff, atc = { lat = clat, lon = clon } },
    line = event.stages[1].line } } }
  files['/earthRally/events/test9.json'] = ev9
  files['/earthRally/matched/test9__close.json'] = { format = 1, points = recFrom }
  local sx0, sy0 = toGame(full[11][1], full[11][2])
  for _, intoM in ipairs({ -4, 30, 90 }) do
    car.lat, car.lon = toGeo(sx0, sy0 + intoM)
    car.speed = 0
    runner.start(ev9, ev9.stages[1])
    frames(80)
    local qx, qy = carXY()
    T.check(runner.current().state == 'toAtc' and runner.current().checks.atcSetDown ~= 'driven there'
      and qy < startY - 15,
      string.format('on the stage %+d m from the start: set down before the ATC, not left past it (%s, %.1f m)',
        intoM, tostring(runner.current().checks.atcSetDown), qy - startY))
    T.check(not runner.current().missedAtc, string.format('and %+d m: the time control is not counted missed', intoM))
    runner.abort(true)
  end
  -- parked SHORT of an ATC that close to the start (the board 20 m before the line, the car 25 m before the board,
  -- before the line's first point and so more than 8 m off it): not yet at it, so the player's spot is kept
  car.lat, car.lon = toGeo(sx0, sy0 - 45)
  car.speed = 0
  local short = { car.lat, car.lon }
  runner.start(ev9, ev9.stages[1])
  frames(80)
  T.check(runner.current().state == 'toAtc' and runner.current().checks.atcSetDown == 'driven there'
    and car.lat == short[1] and car.lon == short[2],
    'short of a close ATC: kept where it was parked (' .. tostring(runner.current().checks.atcSetDown) .. ')')
  runner.abort(true)

  -- ...and where the ATC is ON the line: the start 100 m further on, so 30 m of line runs before it, the ATC 8 m
  -- before the start on the road and a car parked 20 m short of the board, on the line. Not past it: kept.
  local s2lat = full[11][1] + 100 / 111195
  local ev10 = { format = 1, id = 'test10', name = 'Test Rally 10', stages = { {
    id = 'onl', name = 'On Line', lengthM = 3000, radiusM = 1200, centre = event.stages[1].centre,
    controls = { start = { lat = s2lat, lon = full[11][2] }, ff = event.stages[1].controls.ff,
      atc = { lat = s2lat - 8 / 111195, lon = full[11][2] } },
    line = event.stages[1].line } } }
  files['/earthRally/events/test10.json'] = ev10
  files['/earthRally/matched/test10__onl.json'] = { format = 1, points = recFrom }
  local s2x, s2y = toGame(s2lat, full[11][2])
  car.lat, car.lon = toGeo(s2x, s2y - 28)
  car.speed = 0
  local short2 = { car.lat, car.lon }
  runner.start(ev10, ev10.stages[1])
  frames(80)
  T.check(runner.current().state == 'toAtc' and runner.current().checks.atcSetDown == 'driven there'
    and car.lat == short2[1] and car.lon == short2[2],
    'short of an ATC on the line: kept where it was parked (' .. tostring(runner.current().checks.atcSetDown) .. ')')
  runner.abort(true)
  -- and 10 m into the stage, past that ATC's zone (18 m from the board, so it would be kept without the guard):
  -- set down before it
  car.lat, car.lon = toGeo(s2x, s2y + 10)
  car.speed = 0
  runner.start(ev10, ev10.stages[1])
  frames(80)
  T.check(runner.current().state == 'toAtc' and runner.current().checks.atcSetDown ~= 'driven there',
    'into the stage past an ATC on the line: set down (' .. tostring(runner.current().checks.atcSetDown) .. ')')
  runner.abort(true)

  -- an ATC 6 m before the start and 11 m off the line (inside CONTROL_RADIUS_M of it): its zone would end past the
  -- start line, so the limit is capped at the start zone. A car 6 m into the stage, ~16 m from the board: set down.
  local ev11 = { format = 1, id = 'test11', name = 'Test Rally 11', stages = { {
    id = 'tight', name = 'Tight', lengthM = 3000, radiusM = 1200, centre = event.stages[1].centre,
    controls = { start = { lat = s2lat, lon = full[11][2] }, ff = event.stages[1].controls.ff,
      atc = (function() local la, lo = toGeo(s2x + 11, s2y - 6) return { lat = la, lon = lo } end)() },
    line = event.stages[1].line } } }
  files['/earthRally/events/test11.json'] = ev11
  files['/earthRally/matched/test11__tight.json'] = { format = 1, points = recFrom }
  car.lat, car.lon = toGeo(s2x, s2y + 6)
  car.speed = 0
  runner.start(ev11, ev11.stages[1])
  frames(80)
  T.check(runner.current().state == 'toAtc' and runner.current().checks.atcSetDown ~= 'driven there',
    'an ATC under 12 m before the start: a car just into the stage is set down (' ..
    tostring(runner.current().checks.atcSetDown) .. ')')
  T.check(not runner.current().missedAtc, 'and not counted missed')
  runner.abort(true)

  -- runner.faceAtc, the auto recce's landing: from the raw ATC point (off the road) to the road 40 m before it
  car.lat, car.lon, car.speed = alat, alon, 0
  local fok, fhow = runner.faceAtc(ev7.stages[1])
  local fx, fy = carXY()
  T.check(fok and math.abs(fx) < 0.5 and math.abs(fy - (atcY - 40)) < 2,
    'faceAtc: on the road 40 m before the ATC (' .. tostring(fhow) .. string.format(', %.1f, %.1f', fx, fy - atcY) .. ')')
  T.check(runner.faceAtc(event.stages[1]) == false, 'faceAtc: a stage with no ATC of its own is left alone')
  -- no road found (the road map still the last place's): the car LEFT on the raw point, not put 40 m back across a
  -- field where Run stage would keep it as "driven there"
  do
    local propsM = require('earthRally/props')
    local hadRoad = propsM.roadAt
    propsM.roadAt = function() return nil end
    car.lat, car.lon, car.speed = alat, alon, 0
    local nok, nhow = runner.faceAtc(ev7.stages[1])
    propsM.roadAt = hadRoad
    T.check(not nok and car.lat == alat and car.lon == alon,
      'faceAtc with no road: the car left on the ATC point (' .. tostring(nhow) .. ')')
  end
  car.lat, car.lon, car.speed = alat, alon, 0
  runner.faceAtc(ev7.stages[1])
  -- and Run stage from there keeps the spot: before the board, so "driven there"
  runner.start(ev7, ev7.stages[1])
  frames(80)
  T.check(runner.current().state == 'toAtc' and runner.current().checks.atcSetDown == 'driven there',
    'Run stage after faceAtc: the car kept where faceAtc put it (' .. tostring(runner.current().checks.atcSetDown) .. ')')
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
  pAmount = 5                     -- (BeamNG.Earth putting its amount back after a teleport's hold)
  frames(12)
  T.check(pAmount == 0, 'parked cars put back by someone else during the stage: out of the way again')
  runner.abort(true)
  T.check(tAmount == 8 and pAmount == math.huge, 'after the run: the player amounts back')
  -- parked cars held at 0 by BeamNG.Earth at the check-in, its amount put back later: held, and that amount given back
  pAmount = 0
  car.lat, car.lon, car.speed = full[1][1] - 0.02, full[1][2], 0
  runner.start(ev7, ev7.stages[1])
  frames(80)
  car.lat, car.lon = toGeo(ax1 - 8, ay1 - 5)
  car.speed = 8 frames(1) car.speed = 0 frames(3)
  T.check(runner.current().startAt and pAmount == 0, 'checked in while BeamNG.Earth holds the parked cars')
  pAmount = 6
  frames(12)
  T.check(pAmount == 0, 'its amount put back after the check-in: out of the way again')
  runner.abort(true)
  T.check(pAmount == 6, 'after the run: that amount back')
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

------------------------------------------------------------------------------------------ 1.4.0: the stage dressing in a run
-- Planned as the stage is set out (the matched file's junctions placed on the line), put down and taken away by the
-- car's distance along it, cleared at the end of the stage; a stage whose file kept no side roads (format 1), or with
-- no file, gets no junction dressing (the live road map is not looked at for it: the user, 2026-11-14).
do
  local props = require('earthRally/props')
  local J = require('earthRally/junctions')
  local function shapes(pat)
    local n, ids = 0, {}
    for id, o in pairs(objects) do
      if o.pos and (o.fields.shapeName or ''):find(pat, 1, true) then n = n + 1 ids[#ids + 1] = id end
    end
    return n, ids
  end
  local function evFor(id)
    local ev = { format = 1, id = id, name = 'Dressing ' .. id, stages = { {
      id = 'hill', name = 'Hill', lengthM = 3000, radiusM = 1200, centre = event.stages[1].centre,
      controls = { start = event.stages[1].controls.start, ff = event.stages[1].controls.ff },
      line = event.stages[1].line } } }
    files['/earthRally/events/' .. id .. '.json'] = ev
    return ev
  end

  -- ------------------------------------------------------------ a format 2 file: every junction with its roads
  -- a side road east 300 m up the first straight; a fork keeping left ~1 km along the second
  local evA = evFor('dressA')
  files['/earthRally/matched/dressA__hill.json'] = { format = 2, points = recFrom, junctions = {
    J.encode({ kind = 'straight', side = '', inDeg = 0, outDeg = 0, sides = { { deg = 90, halfW = 3 } } },
      full[311][1], full[311][2]),
    J.encode({ kind = 'fork', side = 'left', inDeg = 90, outDeg = 90, sides = { { deg = 60, halfW = 3 } } },
      full[2011][1], full[2011][2]) } }
  local rA = toTheLine(evA)
  T.check(runner.state() == 'waitStart', 'dressing: waiting on the line (' .. runner.state() .. ')')
  local by, nA = props.dressingSites()
  T.check((by.tape or 0) == 2 and (by.board or 0) == 1,
    'dressing: the stage start puts its sites in, tape at both junctions and a board before the fork (' ..
    tostring(rA.checks.dressing) .. ')')
  T.check(tostring(rA.checks.dressing):find('2 junction(s) from the file (2 with side roads)', 1, true) ~= nil,
    'dressing: the checks say the file\'s junctions and their roads (' .. tostring(rA.checks.dressing) .. ')')
  T.check(shapes('s_tape_road_closure') == 1 and shapes('s_corner_dir') == 0,
    'dressing: at the start, the tape 300 m on is down and nothing further (' .. shapes('s_tape_road_closure') .. ')')
  go(rA)
  T.check(runner.state() == 'running', 'dressing: GO')
  driveTo(11, 1036)
  T.check(shapes('s_tape_road_closure') == 0, 'dressing: 1 km on, the first junction\'s tape taken away behind the car')
  driveTo(1061, 1736)
  -- (the fork 30 degrees off the way on: its tape parallel with the stage, 2 x 3 / sin 30 + 1.5 = 13.5 m, two pieces)
  T.check(shapes('s_tape_road_closure') == 2 and shapes('s_corner_dir45_left') == 1,
    'dressing: nearing the fork, its tape and its board down (' .. shapes('s_tape_road_closure') .. ', ' ..
    shapes('s_corner_dir45_left') .. ')')
  driveTo(1761, #full)
  T.check(runner.state() == 'finished', 'dressing: finished (' .. runner.state() .. ')')
  frames(100, 0.1)
  T.check(select(2, props.dressingSites()) == 0 and shapes('s_tape_road_closure') == 0 and shapes('s_corner_dir') == 0,
    'dressing: the stage done and tidied, its dressing gone')
  runner.abort(true)
  T.check(nA > 0 and select(2, props.dressingSites()) == 0, 'dressing: nothing left after the run')

  -- ------------------------------------------------------------ a format 1 file, and no file: no junction dressing
  -- The file has the junction 300 m up but not its roads; the live road map has that side road. Nothing is read off
  -- the map for it: no tape, no board, no marshal, and the log says once how to get them (Auto recce).
  local evB = evFor('dressB')
  files['/earthRally/matched/dressB__hill.json'] = { format = 1, points = recFrom,
    junctions = { { full[311][1], full[311][2], 'straight', '' } } }
  map = { getMap = function()
    local nodes = {}
    for k = 0, 40 do
      local x, y = toGame(full[1 + 10 * k][1], full[1 + 10 * k][2], 0)
      nodes['r' .. k] = { pos = vec3(x, y, 100), radius = 3.5, links = {} }
      if k > 0 then nodes['r' .. k].links['r' .. (k - 1)] = {} end
    end
    local x0, y0 = toGame(full[311][1], full[311][2], 0)
    local prev = 'r31'
    for m = 1, 6 do
      nodes['e' .. m] = { pos = vec3(x0 + 10 * m, y0, 100), radius = 3, links = { [prev] = {} } }
      prev = 'e' .. m
    end
    return { nodes = nodes }
  end }
  -- (review round 2: the log says what is missing -- tape and marshals; the boards still come from the line -- and so
  -- does the screen, once, through runner.say)
  local said, other = {}, {}
  local plainLogB = log
  log = function(level, tag, msg)
    local m = tostring(msg)
    if m:find('no side roads for this stage (an old auto recce line)', 1, true) and
      m:find('no course tape and no marshals', 1, true) then said[#said + 1] = msg end
    if m:find('no junctions in this stage\'s matched file', 1, true) or m:find('did not place on the driven line', 1, true)
    then other[#other + 1] = m end
    plainLogB(level, tag, msg)
  end
  local function oldLineToasts()
    local n = 0
    for _, t in ipairs(toasts) do
      if t.msg == 'Old auto recce line: re-run Auto recce for course tape and marshals' then n = n + 1 end
    end
    return n
  end
  local toasts0 = oldLineToasts()
  local rB = toTheLine(evB)
  T.check(runner.state() == 'waitStart', 'format 1: waiting on the line (' .. runner.state() .. ')')
  by = props.dressingSites()
  T.check((by.tape or 0) == 0 and (by.board or 0) == 0 and (by.marshal or 0) == 0,
    'format 1: no tape, board or marshal from its junctions (' .. tostring(rB.checks.dressing) .. ')')
  T.check(#said == 1, 'format 1: said once at setup, naming tape and marshals (' .. #said .. ')')
  T.check(oldLineToasts() - toasts0 == 1, 'format 1: and on screen once (' .. (oldLineToasts() - toasts0) .. ')')
  go(rB)
  driveTo(11, 436)
  T.check(shapes('s_tape_road_closure') == 0 and (props.dressingSites().tape or 0) == 0,
    'format 1: driving past the junction the road map shows: nothing added')
  T.check(#said == 1 and oldLineToasts() - toasts0 == 1, 'format 1: and not said again as the car goes')
  runner.abort(true)
  -- a stage line with no junctions in its file (a driven recce's: no auto recce run): not the old line's message, on
  -- screen or in the log, but its own line in the log
  said, other, toasts0 = {}, {}, oldLineToasts()
  local evN = evFor('dressNone')
  files['/earthRally/matched/dressNone__hill.json'] = { format = 2, points = recFrom }
  local rN = toTheLine(evN)
  T.check(runner.state() == 'waitStart' and rN and rN.dress and (props.dressingSites().tape or 0) == 0 and #said == 0 and
    oldLineToasts() == toasts0 and #other == 1 and other[1]:find('no junctions', 1, true),
    'no junctions in a format 2 file: no junction dressing, its own log line, not the old line\'s message (' ..
    tostring(rN and rN.checks.dressing) .. ')')
  runner.abort(true)
  -- a format 2 file whose junction does not place on the line (5 km off it): said as such, not as an old line
  said, other, toasts0 = {}, {}, oldLineToasts()
  local evF = evFor('dressFar')
  files['/earthRally/matched/dressFar__hill.json'] = { format = 2, points = recFrom, junctions = {
    J.encode({ kind = 'straight', side = '', inDeg = 0, outDeg = 0, sides = { { deg = 90, halfW = 3 } } },
      full[311][1] + 0.05, full[311][2]) } }
  local rF = toTheLine(evF)
  T.check(rF and #said == 0 and oldLineToasts() == toasts0 and #other == 1 and
    other[1]:find('1 of the file\'s 1 junction(s) did not place', 1, true),
    'format 2, a junction off the line: logged as not placed, not the old line\'s message (' .. tostring(other[1]) .. ')')
  runner.abort(true)
  log = plainLogB
  map = nil
  T.check(J.live == nil and J.merge == nil and runner.DRESS_LIVE_SCAN == nil,
    'the live road map scan is gone (junctions.live, junctions.merge, runner.DRESS_LIVE_SCAN)')

  -- ------------------------------------------------------------ 1.4.0's review: the switches, the faults, the shifts
  local function evWith(id, fileFrom)
    local ev = evFor(id)
    files['/earthRally/matched/' .. id .. '__hill.json'] = files['/earthRally/matched/' .. fileFrom .. '__hill.json']
    return ev
  end
  -- runner.DRESSING off: no dressing at all
  runner.DRESSING = false
  local rO = toTheLine(evWith('dressOff', 'dressA'))
  T.check(runner.state() == 'waitStart' and rO.dress == nil and select(2, props.dressingSites()) == 0 and
    tostring(rO.checks.dressing):find('off') ~= nil, 'switch: DRESSING off, no dressing (' .. tostring(rO.checks.dressing) .. ')')
  runner.abort(true)
  runner.DRESSING = true

  -- the stage dressing raising as it is set out: the stage still starts, the fault in its checks
  local plainJunctions = events.junctions
  events.junctions = function() error('a fault for the test') end
  local rF = toTheLine(evWith('dressFault', 'dressA'))
  events.junctions = plainJunctions
  T.check(runner.state() == 'waitStart' and rF.dress == nil and
    tostring(rF.checks.dressing):find('^failed: .*a fault for the test') ~= nil,
    'a fault setting the dressing out: the stage still starts, its checks say so (' .. tostring(rF.checks.dressing) .. ')')
  runner.abort(true)

  -- 1.5.0: the organisers' points (the stage's marks) handed to dressing.plan on the line driven, each with its
  -- distance along it and a signed offset (+ right of the way the stage goes, - left), one far off dropped; and the
  -- random fill's seed, the event and the stage
  do
    local D = require('earthRally/dressing')
    local plainPlan, seen = D.plan, nil
    D.plan = function(input) seen = input return plainPlan(input) end
    local evM = evWith('dressMarks', 'dressA')
    local function off(i, ex, ny)
      local x, y = toGame(full[i][1], full[i][2])
      local lat, lon = toGeo(x + ex, y + ny)
      return lat, lon
    end
    local la1, lo1 = off(501, 8, 0)        -- going north: 8 m east, on the right
    local la2, lo2 = off(1501, 0, 6)       -- going east (after the bend): 6 m north, on the left
    local la3, lo3 = off(2001, 0, -236)    -- 236 m south: not on the stage
    evM.stages[1].marks = {
      { kind = 'medical', name = 'MIV 2', lat = la2, lon = lo2 },       -- (not in order: each located on its own)
      { kind = 'radio', name = 'Radio 1', lat = la1, lon = lo1 },
      { kind = 'spectator', name = 'Far', lat = la3, lon = lo3 } }
    local rM = toTheLine(evM)
    D.plan = plainPlan
    local mk = seen and seen.marks or {}
    local byKind = {}
    for _, m in ipairs(mk) do byKind[m.kind] = m end
    local r1, m2 = byKind.radio, byKind.medical
    T.check(#mk == 2 and byKind.spectator == nil, 'marks: two on the driven line, the one 236 m off dropped (' .. #mk .. ')')
    T.check(r1 and math.abs(r1.offLineM - 8) < 1.5 and math.abs((r1.along - rM.startM) - 490) < 15,
      'marks: the radio point 490 m on, 8 m right (+) (' .. tostring(r1 and r1.offLineM) .. ', ' ..
      tostring(r1 and (r1.along - rM.startM)) .. ')')
    T.check(m2 and math.abs(m2.offLineM + 6) < 1.5 and m2.along > r1.along and m2.name == 'MIV 2',
      'marks: the medical point after the bend, 6 m left (-) (' .. tostring(m2 and m2.offLineM) .. ')')
    T.check(seen and seen.seed == 'dressMarks/hill', 'the random fill seeded from the event and the stage (' ..
      tostring(seen and seen.seed) .. ')')
    -- (1.6.0's note 5: the kinds the rally's map marks anywhere -- the far spectator point too -- handed over, so
    -- none of them is filled in by chance)
    local mk2 = seen and seen.mapKinds or {}
    T.check(mk2.radio == true and mk2.medical == true and mk2.spectator == true and mk2.marshal == false,
      'the kinds the rally marks handed to the plan (' .. tostring(mk2.spectator) .. ')')
    T.check(runner._marksOnLine ~= nil and #runner._marksOnLine({ { x = 0, y = 0 } }, { 0 }, mk, toGame) == 0,
      'marksOnLine: no line, no marks')
    runner.abort(true)
  end

  -- the showcase from the console: one of each shape ahead of the car, the log naming them, cleared again
  local D = require('earthRally/dressing')
  veh.getDirectionVector = function() return vec3(0, 1, 0) end
  local before = countObjects()
  local nS = runner.dressShowcase()
  T.check(nS == #D.SHOWCASE and countObjects() == before + nS, 'showcase: one of each shape put down (' .. nS .. ')')
  local cp = veh.getPosition()
  local ahead = true
  for _, o in pairs(objects) do
    if o.pos and (o.fields.shapeName or ''):find('s_corner_dir', 1, true) and math.abs(o.pos[2] - cp.y - 15) > 0.5 then
      ahead = false
    end
  end
  T.check(ahead, 'showcase: 15 m ahead of the car')
  runner.dressShowcaseClear()
  T.check(countObjects() == before, 'showcase: cleared')
  veh.getDirectionVector = nil
end

-- the reset penalty: +10 s a reset during the timed stage, in the result
do
  settings.reset()
  local r5 = toTheLine(event)
  T.check(not runner.onReset(1), 'a reset before the start costs nothing')
  go(r5)
  T.check(runner.state() == 'running', 'running (reset penalty run)')
  T.check(runner.onReset(1) == true and r5.resets == 1, 'a reset on the stage: counted')
  T.check(toastTitled('Reset: %+10 s') ~= nil, 'a toast says so')
  T.check(not runner.onReset(1) and r5.resets == 1, 'the same reset heard twice: counted once')
  frames(10)
  moveAnchor(anchor.lat, anchor.lon, 'rebase')
  T.check(not runner.onReset(1) and r5.resets == 1, 'just after the world moved: not the player\'s reset')
  frames(30)
  T.check(runner.onReset(1) == true and r5.resets == 2, 'a second reset')
  settings.set('resetPenalty', false)
  frames(10)
  T.check(not runner.onReset(1) and r5.resets == 2, 'setting off: not counted')
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
  -- the card's Close (1.6.2, #18): the card gone, the run still there for Retry
  T.check(runner.resultsAction('close') == true and not r5.resultsOpen and runner.current() == r5,
    'Close: the results card shut, nothing else')
  rl, ours = runner.uiFrame()
  T.check(not ours.show.results, '... and the HUD stops drawing it')
  local okR = runner.resultsAction('retry')
  T.check(okR and runner.current() ~= r5 and runner.state() == 'travel', 'Retry: the stage again from the start')
  runner.abort(true)
  settings.reset()
end

-- a stage with no ATC, no zone brake, the clock view off; the HUD through every state of a run
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
  T.check(select(3, runner.arrivalPoint(ev8.stages[1])) == 'ATC', 'a map with an ATC: Route to start goes to it')
  -- the same stage with no arrival control in its map, which is what most real ones are. Put back at the end of
  -- this block: `files` holds this very table, so a stage left without its ATC is a stage the tests after this
  -- one would see without it (which is how this was first written, and test8's own uiStage check caught it).
  local atc8 = ev8.stages[1].controls.atc
  ev8.stages[1].controls.atc = nil
  settings.set('zoneBrake', false)
  settings.set('clockView', 'off')
  T.check(select(3, runner.arrivalPoint(ev8.stages[1])) == 'start', 'no ATC in the map: Route to start goes to the start')
  anchor = { lat = 47.0, lon = -123.0 }
  car.lat, car.lon, car.speed = full[1][1] - 0.02, full[1][2], 0
  T.check(runner.start(ev8, ev8.stages[1]), 'the run on a stage with no ATC starts')
  local r8 = runner.current()
  T.check(r8.atc == nil and r8.ss == 1 and r8.ssCount == 2 and r8.nextStage and r8.nextStage.name == 'Two',
    'no ATC; SS1 of 2, the next stage known')
  local seen = {}
  local function look()
    local rl, ours = runner.uiFrame()
    seen[runner.state()] = { rl = rl, ours = ours }
  end
  car.speed = 3
  for _ = 1, 80 do frames(1) look() if runner.state() == 'toStart' then break end end
  T.check(runner.state() == 'toStart', 'set down for the start line (' .. runner.state() .. ')')
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
  T.check(runner.state() == 'running', 'GO')
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
  ev8.stages[1].controls.atc = atc8
  settings.reset()
end

-- recovery: back on the road (+10 s on the stage), flip upright (free); the stage layout held
do
  settings.reset()
  local teleports = {}
  spawn = { safeTeleport = function(v, pos, rot, _, _, _, _, resetVeh)
    teleports[#teleports + 1] = { pos = pos, rot = rot, reset = resetVeh }
    v:setPositionRotation(pos.x, pos.y, pos.z)
  end }
  local layout = 'beamngEarth'
  local oldGs, oldSpawn = core_gamestate, spawn
  core_gamestate = { getGameState = function() return { appLayout = layout } end,
    setGameState = function(_, l) layout = l end }
  local r10 = toTheLine(event)
  go(r10)
  car.speed = 20
  driveTo(11, 600)
  local fx, fy = toGame(full[600][1], full[600][2])
  car.lat, car.lon = toGeo(fx + 30, fy)
  frames(1)
  local before = r10.resets or 0
  T.check(runner.backOnRoad() == true and #teleports == 1 and teleports[1].reset == false,
    'back on the road: moved as the game flips a car (damage kept)')
  local bx, by = toGame(car.lat, car.lon)
  T.check(math.abs(bx - fx) < 3 and math.abs(by - fy) < 15 and (r10.resets or 0) == before + 1,
    'back on the road: on the stage line where it had got to, +1 reset (' .. string.format('%.1f, %.1f', bx - fx, by - fy) .. ')')
  frames(10)
  veh.getDirectionVector = function() return { x = 0, y = 1, z = 0 } end
  veh.getID = function() return 1 end
  T.check(runner.flipUpright() == true and #teleports == 2 and (r10.resets or 0) == before + 1, 'flip upright: no penalty')
  -- the layout: something puts its own on mid-stage (a car reloaded): ours back within a second
  T.check(layout == 'earthRallyStage', 'the stage layout on for the run')
  layout = 'beamngEarth'
  frames(12)
  T.check(layout == 'earthRallyStage', 'the stage layout put back after something else put its own on')
  -- the radial menu (and the garage, photo mode...) put their own on: left to them (in game, 2026-11-13: the hold
  -- fought the radial menu); quickAccess puts ours back when the menu closes
  layout = 'radial'
  frames(30)
  T.check(layout == 'radial', 'the radial menu\'s layout left alone (' .. layout .. ')')
  layout = 'earthRallyStage'
  frames(12)
  T.check(layout == 'earthRallyStage', 'the radial menu closed: the stage layout still on')
  T.check(runner.holdOver('freeroam', 'beamngEarth') and runner.holdOver('beamngEarth', 'x')
    and runner.holdOver('myLayout', 'myLayout') and not runner.holdOver('radial', 'beamngEarth')
    and not runner.holdOver('garage', 'beamngEarth') and not runner.holdOver('earthRallyStage', 'beamngEarth')
    and not runner.holdOver(nil, 'beamngEarth'), 'holdOver: only the plain driving layouts and the one before the run')
  -- the layout on screen, checked a moment after it was put on (ui_appLayouts, the game's)
  local onScreen = { type = 'earthRallyStage', filename = '/settings/ui_apps/layouts/default/earthRallyStage.uilayout.json',
    version = 5, apps = {} }
  for _, n in ipairs(runner.STAGE_APPS) do onScreen.apps[#onScreen.apps + 1] = { appName = n } end
  ui_appLayouts = { getCurrentLayout = function() return onScreen end }
  local text, missing = runner._logLayout()
  T.check(#missing == 0 and text:match('all the stage apps there') and text:match('game state earthRallyStage'),
    'layout check: ours on screen, complete (' .. text .. ')')
  -- 1.2.1 in game: the 1.1.0 layout file installed (only the pacenote cards)
  onScreen.version, onScreen.apps = 4, { { appName = 'beamngEarthStatus' }, { appName = 'rallyVisualPacenotes' } }
  text, missing = runner._logLayout()
  T.check(#missing == 5 and text:match('missing: earthRallyHud'), 'layout check: an old layout file told apart (' .. text .. ')')
  text = runner.layoutReport('earthRallyStage', nil)
  T.check(text:match('unknown'), 'layout check: no ui_appLayouts')
  ui_appLayouts = nil
  runner.abort(true)
  T.check(layout == 'beamngEarth', 'after the run: the layout before it')
  veh.getDirectionVector, veh.getID = nil, nil
  spawn, core_gamestate = oldSpawn, oldGs
end

-- off route on a real run, with the way back
do
  local r9 = toTheLine(event)
  go(r9)
  car.speed = 20
  driveTo(11, 900)
  local fx, fy = toGame(full[900][1], full[900][2])
  veh.getDirectionVector = function() return { x = 0, y = 1, z = 0 } end   -- (heading north, along the stage)
  local logged, oldLog = {}, log
  log = function(level, tag, msg) logged[#logged + 1] = tostring(msg) oldLog(level, tag, msg) end
  car.lat, car.lon = toGeo(fx + 80, fy)
  frames(1)
  local offLines = 0
  for _, m in ipairs(logged) do if m:match('^off route %(8%d m from the stage line') then offLines = offLines + 1 end end
  T.check(offLines == 1, 'off route logged once when it begins (' .. table.concat(logged, ' / ') .. ')')
  local _, ours = runner.uiFrame()
  T.check(r9.offRoute and ours.show.offRoute and ours.offM > 60 and math.abs(ours.backBearing + 90) < 5,
    '80 m right of the line: off route, the way back to the left (' .. tostring(ours.backBearing) .. ')')
  car.lat, car.lon = toGeo(fx + 50, fy)
  frames(1)
  T.check(r9.offRoute, 'still off route at 50 m (no flicker)')
  car.lat, car.lon = toGeo(fx + 15, fy)
  frames(1)
  T.check(r9.offRoute, 'still off route at 15 m (back within 12 m clears it)')
  car.lat, car.lon = toGeo(fx + 8, fy)
  frames(1)
  _, ours = runner.uiFrame()
  T.check(not r9.offRoute and not ours.show.offRoute and ours.show.km, 'back on the line: the card gone')
  local backLines = 0
  for _, m in ipairs(logged) do if m:match('^back on route') then backLines = backLines + 1 end end
  T.check(backLines == 1, 'back on route logged once')
  log = oldLog
  -- off the track, not on another road: 25 m off a line on the roads is off route (1.2.0 needed 60 m: never seen)
  car.lat, car.lon = toGeo(fx + 25, fy)
  frames(1)
  _, ours = runner.uiFrame()
  T.check(r9.offRoute and ours.show.offRoute, '25 m off the road: off route')
  car.lat, car.lon = toGeo(fx + 5, fy)
  frames(1)
  -- where the line is the organisers' (no road on the map) the old 60 m stands
  local seg = require('earthRally/geo').segAt(r9.cum, r9.along)
  r9.line[seg].gap = true
  car.lat, car.lon = toGeo(fx + 25, fy)
  frames(1)
  T.check(not r9.offRoute, '25 m off where the line is the organisers own: not off route')
  r9.line[seg].gap = nil
  veh.getDirectionVector = nil
  runner.abort(true)
end

-- main.lua: the menu page's data and buttons, the HUD's streams, the preview, Ctrl+Alt+K
do
  -- Enough of ImGui for the developer panel to draw all the way through: any call it makes answers false
  -- (nothing clicked, nothing selected) except Begin, which must say the window is open or the body is skipped.
  -- Names are recorded, so the test can tell "it drew" from "it threw on the first line".
  local imCalls = {}
  ui_imgui = setmetatable({
    BoolPtr = function(v) return { [0] = v } end,
    ImVec4 = function() return {} end,
    ImVec2 = function(x, y) return { x = x, y = y } end,
    Begin = function() imCalls.Begin = (imCalls.Begin or 0) + 1 return true end,
  }, { __index = function(t, k)
    return function() imCalls[k] = (imCalls[k] or 0) + 1 return false end
  end })
  local navs = {}
  ui_router = { navigate = function(r) navs[#navs + 1] = r end }
  local streams = {}
  guihooks.queueStream = function(k, v) streams[#streams + 1] = { k = k, v = v } end
  local main = require('earthRally/main')
  settings.reset()
  events.list(true)          -- (the rallies added by the tests above: read again, as an import does)
  local st = main.uiState()
  T.check(st.version == main.VERSION and #st.rallies >= 3 and #st.settings.schema == #settings.ORDER and st.settings.settings.units == 'km'
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
  -- the Escape menu ('pause' in 0.40): our HUD hidden, and BeamNG.Earth's imgui strips told it is a menu (earthMenuFix)
  do
    local told = {}
    package.loaded['beamngEarth/credits'] = { setUiState = function(s) told[#told + 1] = s end }
    main.onUiChangedState('pause')
    T.check(runner.uiHidden and told[1] == 'menu', 'pause menu: our HUD hidden, BeamNG.Earth told "menu"')
    main.onUiChangedState('pause.hudApps')
    T.check(not runner.uiHidden and #told == 1, 'the HUD-apps editor: the apps stay, nothing told')
    package.loaded['beamngEarth/credits'] = nil
  end
  main.onUiChangedState('play')
  -- the menu page pauses the game (1.6.2, #13: menuPause, tested on its own in test_menu_pause), and the level going
  -- with the page up takes the request back
  do
    local reqs = {}
    simTimeAuthority = { pushPauseRequest = function(id) reqs[id] = true end,
      popPauseRequest = function(id) reqs[id] = nil end }
    main.onUiChangedState('earthRally')
    T.check(reqs.earthRally_menu, 'the menu page: a pause request in')
    main.onUiChangedState('play')
    T.check(not reqs.earthRally_menu, 'closed: taken back')
    main.onUiChangedState('earthRally')
    main.onClientEndMission()
    T.check(not reqs.earthRally_menu, 'the level gone with the page up: taken back')
    main.onUiChangedState('play')
    -- a module reload with the page up: taken back (else every later Escape menu stays paused)
    main.onUiChangedState('earthRally')
    main.onExtensionUnloaded()
    T.check(not reqs.earthRally_menu, 'the module unloaded with the page up: taken back')
    main.onUiChangedState('play')
    -- BeamNG.Earth holding the game itself (its drop hold, a swap): our request waits until it is over
    local hadHeld = beamngEarth_core.heldReason
    beamngEarth_core.heldReason = function() return 'ground' end
    main.onUiChangedState('earthRally')
    T.check(not reqs.earthRally_menu, 'BeamNG.Earth holding: no request of ours over its hold')
    beamngEarth_core.heldReason = nil
    main.onUpdate(0.016, 0.016)
    T.check(reqs.earthRally_menu, '... put in once its hold is over')
    beamngEarth_core.heldReason = hadHeld
    main.onUiChangedState('play')
    simTimeAuthority = nil
  end
  -- Route to start: armed only for a stage with a line to run on (else the route alone, the old message)
  do
    local hadSet, hadGps = beamngEarth_api.gpsSet, beamngEarth_api.gps
    beamngEarth_api.gpsSet = function() return true end
    beamngEarth_api.gps = function() return { lat = 0, lon = 0 } end
    local r = main.uiAction('route', 'test8', 'two')
    T.check(r.ok and runner.approaching() == nil and toasts[#toasts].msg == 'Follow the arrows on the road.',
      'Route to start, no line yet: the route alone (' .. tostring(toasts[#toasts].msg) .. ')')
    r = main.uiAction('route', 'test8', 'hill')
    T.check(r.ok and runner.approaching() ~= nil and toasts[#toasts].msg:find('gets ready') ~= nil,
      'Route to start, a line: armed')
    r = main.uiAction('route', 'test8', 'two')
    T.check(r.ok and runner.approaching() == nil,
      'Route to start elsewhere, on a stage that cannot be armed: the stage armed before is disarmed')
    runner.disarmApproach()
    beamngEarth_api.gpsSet, beamngEarth_api.gps = hadSet, hadGps
  end
  -- Drive stage from the page (1.7.0, #49): the run starts and the page stays up on its loading screen, the game
  -- paused under it; the page closes once the car is at the control and the world round it is in.
  local reqsD = {}
  simTimeAuthority = { pushPauseRequest = function(id) reqsD[id] = true end,
    popPauseRequest = function(id) reqsD[id] = nil end }
  main.onUiChangedState('earthRally')
  anchor = { lat = 47.0, lon = -123.0 }
  car.lat, car.lon, car.speed = full[1][1] - 0.02, full[1][2], 0
  navs = {}
  a = main.uiAction('drive', 'test8', 'hill')
  local ls = require('earthRally/loadScreen')
  T.check(a.ok and runner.current() and navs[1] == nil and ls.active(), 'Drive stage: the run starts under a loading screen')
  T.check(reqsD.earthRally_menu, "Drive stage: the game stays paused under the loading screen")
  local ui = ls.ui()
  T.check(ui and #ui.steps == 4 and ui.steps[4].world and ui.steps[1].state == 'now',
    'the loading screen: three steps and the world last, the first under way')
  ls.cancel()
  main.onUiChangedState('play')
  simTimeAuthority = nil
  T.check(not main.uiAction('drive', 'test8', 'hill').ok, 'not a second run while one is under way')
  -- the streams: both, sent at once for the state (then as what they show changes)
  streams = {}
  local logged, oldLog = {}, log
  log = function(level, tag, msg) logged[#logged + 1] = tostring(msg) oldLog(level, tag, msg) end
  for _ = 1, 10 do main._sendStreams(0.05) end
  log = oldLog
  local streamLines = {}
  for _, m in ipairs(logged) do if m:match('^HUD streams') then streamLines[#streamLines + 1] = m end end
  T.check(#streamLines == 1 and streamLines[1]:match('rallyLoop activeState inactive'),
    'the streams logged once for the state, not every frame (' .. table.concat(streamLines, ' / ') .. ')')
  local line = main.streamsLine(nil, { state = 'running', show = { km = true, offRoute = true, go = true } })
  T.check(line:match('NOT sent %(noRallyLoop') and line:match('show %[km,offRoute%]'),
    'the streams line: the stock stream left alone told, our pieces listed (' .. line .. ')')
  T.check(main.streamsKey({ activeState = 'stageActive', showStageApps = true }, { state = 'running', show = {} })
    ~= main.streamsKey({ activeState = 'stageActive', showStageApps = true }, { state = 'running', show = { offRoute = true } }),
    'the streams logged again when off route shows')
  local kinds = {}
  for _, x in ipairs(streams) do kinds[x.k] = (kinds[x.k] or 0) + 1 end
  T.check((kinds.rallyLoop or 0) >= 1 and (kinds.earthRally or 0) >= 1, 'both streams queued (' ..
    tostring(kinds.rallyLoop) .. ', ' .. tostring(kinds.earthRally) .. ')')
  -- the rates (1.6.1): a stream sent when what it shows changes. One second at 60 fps in each state, the clocks
  -- moving as in play
  do
    local r = runner.current()
    local was = { r.state, r.offRoute, r.clockBase, r.clockRun, r.clock, r.startAt, r.backBearing }
    r.clockBase, r.clockRun = r.clockBase or 36000, r.clockRun or 0
    local function second(state, setup, step)
      r.state = state
      if setup then setup() end
      main._sendStreams(1 / 60)        -- (the state change: both sent at once, not counted)
      streams = {}
      for _ = 1, 60 do
        r.clockRun = r.clockRun + 1 / 60
        if step then step() end
        main._sendStreams(1 / 60)
      end
      local n, rl = {}, {}
      for _, x in ipairs(streams) do
        n[x.k] = (n[x.k] or 0) + 1
        if x.k == 'rallyLoop' then rl[#rl + 1] = x.v end
      end
      return n.rallyLoop or 0, n.earthRally or 0, rl
    end
    local a, b = second('toStart')
    T.check(a <= 3 and b <= 3, 'stream rates: standing before the start, a send or two a second (' .. a .. ', ' .. b .. ')')
    a, b = second('waitStart', function() r.startAt = runner.clock() + 20.5 end)
    T.check(a >= 1 and a <= 3 and b >= 1 and b <= 3,
      'stream rates: on the line, a send as the countdown ticks (' .. a .. ', ' .. b .. ')')
    local rls
    a, b, rls = second('running', function() r.offRoute, r.clock = nil, 30.02 end,
      function() r.clock = r.clock + 1 / 60 end)
    T.check(a >= 9 and a <= 12, 'stream rates: on the stage, the stock stream at its tenths and the clock seconds (' .. a .. ')')
    T.check(b <= 3, 'stream rates: on the stage, ours only as it changes (' .. b .. ')')
    local steps = true
    for k = 2, #rls do
      local d = math.floor(rls[k].stageData.currentSSTime * 10 + 0.5) - math.floor(rls[k - 1].stageData.currentSSTime * 10 + 0.5)
      if d ~= 0 and d ~= 1 then steps = false end
    end
    T.check(steps, 'stream rates: every tenth of the stage time sent, none skipped')
    a, b = second('running', function() r.offRoute, r.backBearing = true, 0 end,
      function() r.clock, r.backBearing = r.clock + 1 / 60, (r.backBearing or 0) + 1 end)
    T.check(b >= 25 and b <= 31, 'stream rates: off route, ours as the arrow turns, at most 30 a second (' .. b .. ')')
    r.state, r.offRoute, r.clockBase, r.clockRun, r.clock, r.startAt, r.backBearing =
      was[1], was[2], was[3], was[4], was[5], was[6], was[7]
    main._sendStreams(1 / 60)
  end
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
  main.uiState()
  local at = main.uiOpenAt()
  T.check(at and at.view == 'rally' and main.uiOpenAt() == nil, 'the page told where to open, once (not taken by a poll)')
  -- The developer panel follows its setting, and draws without throwing. It is developer-only and not held to
  -- the bar the menu page is, but it is the one surface that shows a run's checks while a stage is on, so "it
  -- throws on its first line" should not be something only a log line knows.
  T.check(main.onUpdate ~= nil, 'main loaded')
  imCalls, logErrors = {}, {}
  settings.set('devPanel', true)
  main.onUpdate(0.05, 0.05)
  T.check((imCalls.Begin or 0) == 1, 'the developer panel drew when its setting went on (' ..
    tostring(imCalls.Begin) .. ')')
  T.check(#logErrors == 0, 'and drew all the way through without throwing (' ..
    tostring(logErrors[1]) .. ')')
  T.check((imCalls.Text or 0) + (imCalls.TextWrapped or 0) > 0, 'with something written in it')
  imCalls = {}
  settings.set('devPanel', false)
  main.onUpdate(0.05, 0.05)
  T.check((imCalls.Begin or 0) == 0, 'and nothing is drawn once the setting goes off')
  settings.reset()
end

------------------------------------------------------------------------------------------ the strips given back
-- A run takes BeamNG.Earth's status bar and banner off screen (earthAdapter.holdStrips, through BeamNG.Earth's own
-- mount call), and BeamNG.Earth leaves its imgui drawing of a strip out while it believes an app has it. Nothing else
-- will put them back, and the banner is where "BeamNG.Earth server not running" and "the car is held in place" are
-- said -- so every way out of a run has to give them back, not only the tidy one.
do
  local main = require('earthRally/main')
  local function held()
    local n = 0
    for _, v in pairs(stripsMounted) do if v then n = n + 1 end end
    return n
  end
  -- (a run gets as far as the start line, which is where the stage layout and the hold go on)
  local function toTheLine()
    runner.abort(true)
    car.lat, car.lon = full[1][1], full[1][2]
    local started = runner.start(event, event.stages[1])
    frames(20)
    return started and runner.current() ~= nil
  end
  runner.abort(true)
  T.check(held() == 0, 'before a run: BeamNG.Earth draws its own strips')

  -- the ordinary way out
  T.check(toTheLine(), 'a run for the strips')
  T.check(held() == 2 and stripsMounted.status and stripsMounted.banner,
    'on a stage: the status bar and the banner off screen (' .. held() .. ')')
  runner.abort(true)
  T.check(held() == 0, 'the run over: both strips given back')

  -- the mod switched off or its Lua reloaded mid-stage: given back while there is still code here to do it
  toTheLine()
  T.check(held() == 2, 'on a stage again: both held')
  main.onExtensionUnloaded()
  T.check(held() == 0, 'the mod unloaded mid-stage: both strips given back')

  -- the level left: the hook that really fires for a player, and it gives the strips back even when the tidy that
  -- normally does it is not reached
  toTheLine()
  T.check(held() == 2, 'on a stage: both held')
  main.onClientEndMission()
  T.check(held() == 0, 'the level left: both strips given back')

  -- Earth Rally switched off in the mod manager. The game does not unload a mod's extensions for that, so this is
  -- the only hook that fires: without it the runner would go on re-asserting the hold every frame inside a
  -- switched-off mod. Our own file has gone from the VFS by the time it fires, which is how we know it was us.
  toTheLine()
  T.check(held() == 2, 'on a stage: both held')
  files[main.OUR_FILE] = { some = 'other mod is still mounted' }
  main.onModDeactivated()
  T.check(held() == 2 and runner.current() ~= nil, 'another mod switched off: our run left alone')
  files[main.OUR_FILE] = nil
  local unloaded = {}
  -- (abort unloads the rally start-clock extension of its own accord, so count only ours)
  local function ourUnloads()
    local n = 0
    for _, name in ipairs(unloaded) do if name == 'earthRally_main' then n = n + 1 end end
    return n
  end
  extensions = { unload = function(n) unloaded[#unloaded + 1] = n end }
  main.onModDeactivated()
  T.check(held() == 0 and runner.current() == nil, 'Earth Rally switched off: the strips back and the run stopped')
  T.check(ourUnloads() == 0, 'and not unloaded from inside the hook (the game is walking its extension list)')
  main.onUpdate(0.05, 0.05)
  T.check(ourUnloads() == 1, 'unloaded the frame after (' .. table.concat(unloaded, ',') .. ')')
  main.onUpdate(0.05, 0.05)
  T.check(ourUnloads() == 1, 'and only once')
  extensions = nil

  -- a strip BeamNG.Earth does not know: it answers false without throwing, so the call has to read the answer and
  -- not just survive it (otherwise a renamed strip looks held while it is still on screen)
  local realHudApp2 = beamngEarth_core.hudApp
  beamngEarth_core.hudApp = function(name, on)
    if name == 'banner' then return false end       -- as setMounted answers for a name not in its list
    return realHudApp2(name, on)
  end
  T.check(earth.holdStrips(true) == false, 'a strip it does not know: the hold reports it did not take')
  earth.holdStrips(false)
  beamngEarth_core.hudApp = realHudApp2
  T.check(held() == 0, 'and nothing left held after it')

  -- only one of the two takes: the one that did is still given back (1.2.5 released only when both took, so a
  -- half-held strip stayed off screen for the rest of the session with nothing able to put it back)
  local realHudApp = beamngEarth_core.hudApp
  beamngEarth_core.hudApp = function(name, on)
    if name == 'banner' and on then error('BeamNG.Earth said no') end   -- (a throw, not a refusal: both are covered)
    return realHudApp(name, on)
  end
  toTheLine()
  T.check(stripsMounted.status == true and not stripsMounted.banner, 'one strip of the two taken, the other refused')
  beamngEarth_core.hudApp = realHudApp
  runner.abort(true)
  T.check(held() == 0, 'half held: the one that took is given back too')
end

------------------------------------------------------------------------------------------ the Auto recce button
-- The Lua the menu page's seventh column rests on (docs/mockups-1.3.0/auto-recce-button.html): the statuses and
-- wording the button is shown or hidden by, the progress the page polls, the action routing, the refusals, and the
-- four endings it has to colour differently. The Vue itself cannot be tested offline, so what is tested here is
-- everything the Vue reads.
--
-- BeamNG.Earth is given a road graph here: nodes every 20 m along the stage's own line, handed out a window at a
-- time, so a window covering a stretch of the stage matches it exactly. `graph.*` are the knobs -- an incomplete
-- window (map cells not on this computer), an empty one, a refusal.
do
  local main = require('earthRally/main')
  local auto = require('earthRally/autoRecce')
  settings.reset()
  runner.abort(true)
  events.list(true)

  -- the nodes: the stage's own line, resampled, as lat / lon
  local line = event.stages[1].line
  local fr = auto.frame(line[1][1], line[1][2])
  local flat = {}
  for i, pt in ipairs(line) do flat[i] = fr.xy(pt[1], pt[2]) end
  local nodeLL = {}
  for i, q in ipairs(auto.resample(flat, 20)) do
    local la, lo = fr.latlon(q.x, q.y)
    nodeLL[i] = { la, lo }
  end

  local graph = { pending = {}, calls = 0, refuse = false, empty = false, incomplete = nil, allIncomplete = false }
  local hadHas = beamngEarth_api.has
  local function withRoadGraph(n)
    return n == 'transform' or n == 'rebase' or n == 'gpsRoute' or n == 'roadGraph'
  end
  beamngEarth_api.has = withRoadGraph
  beamngEarth_api.roadGraph = function(lat, lon, opts, cb)
    graph.calls = graph.calls + 1
    local i = graph.calls
    if graph.refuse then return false, 'the stand-in refused the road graph' end
    local nodes, edges = {}, {}
    if not graph.empty then
      local cx, cy = toGame(lat, lon, 0)
      local prev = nil
      for k, pt in ipairs(nodeLL) do
        local x, y = toGame(pt[1], pt[2], 0)
        local name = 'n' .. k
        if math.abs(x - cx) <= opts.radius and math.abs(y - cy) <= opts.radius then
          nodes[name] = { x = x, y = y, z = 100, radius = 4.0 }
          if prev then edges[#edges + 1] = { inNode = prev, outNode = name, drivability = 1.0 } end
          prev = name
        else
          prev = nil
        end
      end
    end
    local complete = not (graph.allIncomplete or graph.incomplete == i)
    graph.pending[#graph.pending + 1] = function() cb({ nodes = nodes, edges = edges, complete = complete }) end
    return true
  end
  local function drain()
    local guard = 0
    while #graph.pending > 0 do
      table.remove(graph.pending, 1)()
      guard = guard + 1
      if guard > 200 then error('the auto recce did not finish') end
    end
  end
  local function resetGraph()
    graph.pending, graph.calls, graph.refuse, graph.empty = {}, 0, false, false
    graph.incomplete, graph.allIncomplete = nil, false
    auto.cancel()
  end
  local function lineFor(stageId)
    for _, l in ipairs(main.uiRally('test8').autoLines or {}) do
      if l.stageId == stageId then return l end
    end
  end

  -- ---------------------------------------------------------------- what the page shows the button by
  T.check(main.uiState().autoOk == true, 'uiState: an auto recce can be run with the capability there')
  local rr = main.uiRally('test8')
  T.check(rr.list[1].status == 'ready' and rr.list[2].status == 'none',
    'uiRally: SS2 is the Recce needed row, which is the only row that gets the button')
  local two = main.uiStage('test8', 'two')
  T.check(two.autoCan == true and two.autoWhy == nil, 'uiStage: the button is offered on a stage with no line')
  T.check(two.note:find('run the auto recce'), 'and the note says so (' .. tostring(two.note) .. ')')
  T.check(main.uiStage('test8', 'hill').autoCan == nil, 'a stage that has a line is not offered one')

  -- the capability missing: no button anywhere, and the reason in words instead of a greyed button with none
  beamngEarth_api.has = hadHas
  T.check(main.uiState().autoOk == false, 'without the capability the page is told there is no auto recce')
  local off = main.uiStage('test8', 'two')
  T.check(off.autoWhy and off.autoWhy:find('road graph'), 'and the stage page is given the reason (' ..
    tostring(off.autoWhy) .. ')')
  T.check(not off.note:find('auto recce'), 'the note does not offer what cannot be run (' .. tostring(off.note) .. ')')
  beamngEarth_api.has = withRoadGraph

  -- ---------------------------------------------------------------- started, polled, stopped
  resetGraph()
  local a = main.uiAction('autoRecce', 'test8', 'two')
  T.check(a.ok and a.message and a.message:find('downloads nothing'),
    'Auto recce starts, and says it downloads nothing (' .. tostring(a.message) .. ')')
  T.check(auto.active(), 'the auto recce is running')
  local prog = main.uiState().auto
  T.check(prog and prog.stageId == 'two' and prog.eventId == 'test8' and prog.ss == 2,
    'uiState.auto names the row the page has to mark')
  T.check(prog and prog.windows and prog.windows >= 4 and prog.done == 0 and prog.stepM == 700,
    'and the window count, how many are done, and the step (' .. tostring(prog and prog.windows) .. ' windows, ' ..
    tostring(prog and prog.stepM) .. ' m)')
  local total = prog and prog.windows or 0
  -- One window at a time. A second Auto recce is refused, and -- the part that bit once -- the refusal leaves the
  -- running one's banner and row mark alone instead of forgetting which row it was.
  local second = main.uiAction('autoRecce', 'test8', 'two')
  T.check(not second.ok and second.message and second.message:find('under way'),
    'not a second auto recce while one is under way (' .. tostring(second.message) .. ')')
  T.check(main.uiState().auto ~= nil, 'and the refusal does not lose the one still running')
  T.check(not main.uiAction('drive', 'test8', 'hill').ok, 'and no run while one is under way')
  T.check(not main.uiAction('recce', 'test8', 'hill').ok, 'and no recce either')
  -- the progress moves as the windows come in
  table.remove(graph.pending, 1)()
  local p2 = main.uiState().auto
  T.check(p2 and p2.done == 1, 'a window answered: one done (' .. tostring(p2 and p2.done) .. ')')
  -- Stop
  local stopped = main.uiAction('autoRecceStop')
  T.check(stopped.ok and not auto.active() and main.uiState().auto == nil, 'Stop ends it and clears the banner')
  T.check(lineFor('two') == nil, 'a stop leaves no ending line behind: it is not an ending')
  T.check(not main.uiAction('autoRecceStop').ok, 'Stop with nothing running: refused')


  -- ---------------------------------------------------------------- ending: no map data anywhere (grey, not red)
  resetGraph()
  graph.allIncomplete = true
  T.check(main.uiAction('autoRecce', 'test8', 'two').ok, 'an auto recce over ground with no map data starts')
  drain()
  local l = lineFor('two')
  T.check(l and l.kind == auto.NODATA, 'none of it covered: the ending is "no map data" (' ..
    tostring(l and l.kind) .. ')')
  T.check(l and l.text:find('nothing to match to') and l.text:find('never') and l.text:find('SS2'),
    'and the line says there was nothing to match to and that it never downloads (' .. tostring(l and l.text) .. ')')
  T.check(main.uiRally('test8').list[2].status == 'none', 'the stage stays Recce needed: nothing was written')
  T.check(main.uiStage('test8', 'two').autoLine ~= nil, 'the stage page carries its own ending too')
  T.check(main.uiState().auto == nil, 'and nothing is left running')

  -- ---------------------------------------------------------------- ending: part of it has no map data
  resetGraph()
  graph.incomplete = 2
  T.check(main.uiAction('autoRecce', 'test8', 'two').ok, 'an auto recce with one window short starts')
  drain()
  l = lineFor('two')
  T.check(l and l.kind == auto.PARTIAL, 'one window of several short: the ending is "partly" (' ..
    tostring(l and l.kind) .. ')')
  T.check(l and l.text:find(string.format('%d of %d windows had map data', total - 1, total), 1, true),
    'and the line counts the windows that did have data (' .. tostring(l and l.text) .. ')')
  local km = tonumber((l and l.text or ''):match('(%d+%.%d) km of it has none'))
  T.check(km and km > 0, 'and the ground that has none, in km (' .. tostring(km) .. ')')
  T.check(l and not l.text:find('download '), 'without ever offering to download the rest')

  -- Try again: the old sentence goes the moment it starts, not when it ends -- a stale ending under a running
  -- progress bar reads as the outcome of the run in front of you.
  resetGraph()
  T.check(lineFor('two') ~= nil, 'the ending is still there before Try again is pressed')
  T.check(main.uiAction('autoRecce', 'test8', 'two').ok, 'Try again starts another')
  T.check(lineFor('two') == nil, 'and the old ending line is gone while it runs')
  main.uiAction('autoRecceStop')

  -- ---------------------------------------------------------------- ending: it stopped part way (the only red one)
  resetGraph()
  T.check(main.uiAction('autoRecce', 'test8', 'two').ok, 'an auto recce that will be cut off starts')
  graph.refuse = true                      -- BeamNG.Earth stops answering after the first window
  drain()
  l = lineFor('two')
  T.check(l and l.kind == auto.FAILED, 'BeamNG.Earth stopping part way is a failure (' ..
    tostring(l and l.kind) .. ')')
  T.check(l and l.text:find('stopped at window 2 of') and l.text:find('Nothing was written'),
    'and the line says where it stopped and that nothing was written (' .. tostring(l and l.text) .. ')')
  T.check(#(main.uiRally('test8').autoLines or {}) == 1, 'one line per stage, not one per attempt')

  -- ---------------------------------------------------------------- the level left while one runs
  -- A window in flight converts its coordinates through the world's origin, so it has to be given up when the
  -- level goes, the way a recce is -- otherwise it answers into a world that is not there, and the page keeps a
  -- banner for something nothing is running.
  resetGraph()
  T.check(main.uiAction('autoRecce', 'test8', 'two').ok, 'an auto recce starts')
  main.onClientEndMission()
  T.check(not auto.active() and main.uiState().auto == nil, 'the level left: the auto recce is given up')
  T.check(#(main.uiRally('test8').autoLines or {}) == 0, 'and it leaves no ending line: it did not end, it stopped')

  -- ---------------------------------------------------------------- ending: done (the button simply goes)
  resetGraph()
  T.check(main.uiAction('autoRecce', 'test8', 'two').ok, 'the auto recce that will work starts')
  drain()
  T.check(events.matched('test8', 'two') ~= nil, 'the matched line is written')
  T.check(lineFor('two') == nil, 'a written line leaves no sentence behind: the pill and the missing button say it')
  local done = main.uiRally('test8')
  T.check(done.list[2].status ~= 'none', 'and the row is no longer Recce needed (' ..
    tostring(done.list[2].status) .. '), so it has no button at all')
  T.check(main.uiStage('test8', 'two').autoCan == nil, 'nor does the stage page')

  beamngEarth_api.has = hadHas
  beamngEarth_api.roadGraph = nil
  settings.reset()
end

------------------------------------------------------------------------------------- Reset a stage's line (1.3.1)

-- "The rerun button should just replace the auto recce button once a stage has recce. Call it 'reset'. Then you
-- can go an manually recce it or use autorecce" (the user, 2026-11-14).
do
  local main = require('earthRally/main')
  local menu = require('earthRally/menu')
  local line = event.stages[1].line
  local evr = { format = 1, id = 'rst', name = 'Reset Rally', stages = {
    { id = 'am', name = 'Auto Matched', lengthM = 3000, line = line },
    { id = 'dr', name = 'Driven', lengthM = 3000, line = line },
    { id = 'bo', name = 'Both', lengthM = 3000, line = line },
    { id = 'no', name = 'Nothing', lengthM = 3000, line = line },
  } }
  files['/earthRally/events/rst.json'] = evr
  events.list(true)

  local function matched(id)
    events.saveMatched('rst', id, { format = 1, points = line, lengthM = 3000, gapM = 0 })
  end
  local function driven(id)
    events.saveRecce('rst', id, { format = 1, points = recFrom, lengthM = 3000, share = 1 })
  end

  -- ------------------------------------------------------------ a matched line: gone, and the stage is 'none'
  matched('am')
  T.check(select(2, events.stageLine('rst', 'am', evr.stages[1])) == 'matched', 'a matched line is there to remove')
  local r = events.resetLine('rst', 'am')
  T.check(r ~= nil and r.matched == true and r.recce == nil, 'reset reports what it removed (matched)')
  T.check(events.matched('rst', 'am') == nil, 'and the matched line is gone')
  T.check(events.stageLine('rst', 'am', evr.stages[1]) == nil, 'the stage has no line at all')
  T.check(menu.stageStatus('rst', evr.stages[1], true).status == 'none',
    'and its pill is back to Recce needed, which is what makes Auto recce show again')

  -- ------------------------------------------------------------ a driven recce: the same, reported as a recce
  driven('dr')
  local r2 = events.resetLine('rst', 'dr')
  T.check(r2 ~= nil and r2.recce == true and r2.matched == nil, 'a driven recce is reported as the recce')
  T.check(events.recce('rst', 'dr') == nil and events.stageLine('rst', 'dr', evr.stages[2]) == nil,
    'and it is gone')

  -- ------------------------------------------------------------ BOTH on disk: both go, which is the whole point
  -- stageLine picks between the two when a stage has both, so removing only the one in use would leave the other
  -- to answer it: the player would press Reset and watch nothing happen.
  matched('bo')
  driven('bo')
  T.check(events.recce('rst', 'bo') ~= nil and events.matched('rst', 'bo') ~= nil, 'both lines on disk')
  local r3 = events.resetLine('rst', 'bo')
  T.check(r3 ~= nil and r3.recce == true and r3.matched == true, 'reset reports both')
  T.check(events.recce('rst', 'bo') == nil and events.matched('rst', 'bo') == nil, 'and removes both files')
  T.check(events.stageLine('rst', 'bo', evr.stages[3]) == nil,
    'so the stage really has no line -- removing one of the two would have left this answering')

  -- ------------------------------------------------------------ nothing to remove: not an error
  local r4 = events.resetLine('rst', 'no')
  T.check(r4 ~= nil and r4.recce == nil and r4.matched == nil, 'a stage with no line: reset is not an error')

  -- ------------------------------------------------------------ a file that will not delete is REPORTED
  -- The caller tells the player their line is gone; if the file is still there it would be back on the next poll.
  matched('am')
  local hadRemove = FS.removeFile
  FS.removeFile = function() end                       -- the game's own removeFile can fail; saveMatched pcalls it
  local r5, why5 = events.resetLine('rst', 'am')
  T.check(r5 == nil and type(why5) == 'string' and why5:find('could not be removed'),
    'a file that will not delete: reset says so rather than claiming success (' .. tostring(why5) .. ')')
  FS.removeFile = hadRemove
  T.check(events.resetLine('rst', 'am') ~= nil and events.matched('rst', 'am') == nil, 'and it removes once it can')

  -- ------------------------------------------------------------ the action, and what it tells the player
  driven('dr')
  local a = main.uiAction('reset', 'rst', 'dr')
  T.check(a.ok and a.message and a.message:find('recce you drove'),
    'uiAction reset names the driven recce (' .. tostring(a.message) .. ')')
  T.check(a.message:find('Run the auto recce, or drive a recce'), 'and says what to do next')
  T.check(events.stageLine('rst', 'dr', evr.stages[2]) == nil, 'and the line is gone')
  matched('am')
  local a2 = main.uiAction('reset', 'rst', 'am')
  T.check(a2.ok and a2.message and a2.message:find('matched line'),
    'a matched line is named as that (' .. tostring(a2.message) .. ')')
  local a3 = main.uiAction('reset', 'rst', 'no')
  T.check(a3.ok and a3.message and a3.message:find('no line to remove'),
    'a stage with nothing to remove is told plainly (' .. tostring(a3.message) .. ')')
  T.check(not main.uiAction('reset', 'rst', 'nope').ok, 'a stage that is not there: refused')

  -- ------------------------------------------------------------ the list row carries the kind the confirm needs
  matched('am')
  driven('dr')
  local card = menu.rally('rst')
  local by = {}
  for _, row in ipairs(card and card.list or {}) do by[row.id] = row end
  T.check(by.am and by.am.line == 'matched', "the list row says a matched line is matched (" ..
    tostring(by.am and by.am.line) .. ')')
  T.check(by.dr and by.dr.line == 'recce', 'and a driven one is a recce (' .. tostring(by.dr and by.dr.line) .. ')')
  T.check(by.no and by.no.line == nil, 'and a stage with no line says nothing')
  events.resetLine('rst', 'am')
  events.resetLine('rst', 'dr')
end

--------------------------------------------------- Auto recce end to end: go, download, match (1.3.1)

-- "add the download, teleport to start, and auto recce features to all work under the one autorecce button"
-- (the user, 2026-11-14). One press: take the player there, offer the missing map data, match.
do
  local main = require('earthRally/main')
  local earth = require('earthRally/earthAdapter')
  local line = event.stages[1].line
  local far = {}                       -- the same shape of line, moved to Ohio: 3400 km from the anchor
  for i, q in ipairs(line) do far[i] = { q[1] - 6.37, q[2] + 37.81 } end
  local evs = { format = 1, id = 'seq', name = 'Sequence Rally', stages = {
    { id = 'near', name = 'Near', lengthM = 3000, line = line },
    { id = 'away', name = 'Away', lengthM = 3000, line = far },
    -- far, with an ATC of its own ~100 m before the start -- inside NO_SET_DOWN_M (150), the band where landing at
    -- the start left Run stage taking the car for "driven there": the auto recce must land at the ATC instead
    { id = 'awayAtc', name = 'Away ATC', lengthM = 3000, line = far, controls = {
      start = { lat = far[1][1], lon = far[1][2] }, atc = { lat = far[1][1] - 0.0009, lon = far[1][2] } } },
    { id = 'awayNoAtc', name = 'Away No ATC', lengthM = 3000, line = far },
    -- a stage each for the blocks that need to be ASKED: a Not now is remembered for the session, so a stage
    -- already declined is never asked again -- which is the point of it, and makes one stage unusable twice
    { id = 'n2', name = 'Near Two', lengthM = 3000, line = line },
    { id = 'n3', name = 'Near Three', lengthM = 3000, line = line },
    { id = 'n4', name = 'Near Four', lengthM = 3000, line = line },
  } }
  files['/earthRally/events/seq.json'] = evs
  events.list(true)

  -- the stand-ins: a road graph that finds nothing (so every match refuses with NODATA), and an area tool that
  -- prices, accepts and finishes a download on command
  local hadHas, hadGraph = beamngEarth_api.has, beamngEarth_api.roadGraph
  local area = { plans = 0, adds = 0, bytes = 18000000, addOk = true, state = 'running', unavailable = 0 }
  beamngEarth_api.has = function(n)
    return n == 'transform' or n == 'rebase' or n == 'gpsRoute' or n == 'roadGraph' or n == 'areaRoute'
  end
  local calls = 0
  local function graphCalls() return calls end
  beamngEarth_api.roadGraph = function(_, _, _, cb)
    calls = calls + 1
    cb({ nodes = {}, edges = {}, complete = false })
    return true
  end
  beamngEarth_api.areaPlan = function(pts, opts, cb)
    area.plans = area.plans + 1
    area.planPts, area.planOpts = pts, opts
    cb({ ok = true, downloadBytes = area.bytes, diskBytes = area.bytes * 2, km = 3.0, items = 30, missing = 30,
         layers = opts.layers })
    return true
  end
  beamngEarth_api.areaAdd = function(pts, opts, cb)
    area.adds = area.adds + 1
    area.lastName, area.addOpts = opts.name, opts
    cb(area.addOk and { ok = true, id = 'a9' } or { ok = false, error = 'the saved areas are full' })
    return true
  end
  beamngEarth_api.areaStatus = function(id)
    if id ~= 'a9' or area.gone then return nil end
    return { id = 'a9', name = area.lastName, state = area.state, done = 12, total = 30,
             unavailable = area.unavailable, msg = area.msg }
  end
  local function tick(n, dt)
    for _ = 1, (n or 1) do main.onUpdate(dt or 0.5, dt or 0.5) end
  end

  T.check(earth.hasAreaRoute() == true, 'the adapter sees the area-route capability')

  -- ------------------------------------------------------------ a NEAR stage: no teleport, straight to matching
  car.lat, car.lon = line[1][1], line[1][2]
  local a = main.uiAction('autoRecce', 'seq', 'near')
  T.check(a.ok, 'a near stage: the auto recce starts (' .. tostring(a.message) .. ')')
  T.check(a.message and a.message:find('checking what map data is missing'),
    'and the FIRST leg is the estimate, which needs no anchor (' .. tostring(a.message) .. ')')
  -- the estimate says 30 of 30 items are missing, so the player is asked before anything else happens
  local stt = main.uiState()
  T.check(stt.auto and stt.auto.phase == 'asking', 'nothing on disk: the player is asked (' ..
    tostring(stt.auto and stt.auto.phase) .. ')')
  T.check(stt.auto.ask and stt.auto.ask.bytes == 18000000, 'and told the figure (' ..
    tostring(stt.auto.ask and stt.auto.ask.bytes) .. ')')
  T.check(area.plans == 1 and area.adds == 0, 'the estimate was asked for and NOTHING downloaded yet (' ..
    area.plans .. ' plan(s), ' .. area.adds .. ' add(s))')
  T.check(area.planOpts and area.planOpts.layers and area.planOpts.layers[1] == 'roads'
    and #area.planOpts.layers == 1,
    'the estimate asks for the roads layer alone, which is the difference between 18 MB and 300')
  T.check(area.planOpts.half == 300, 'and a 300 m corridor each side (' .. tostring(area.planOpts.half) .. ')')
  T.check(area.planOpts.fast == nil and area.planOpts.mode == nil, 'and never fast, which would pause the game')

  -- the player says no: the stage's own refusal is what they are told, not silence
  local hadCalls = graphCalls()
  local no = main.uiAction('autoRecceSkip')
  T.check(no.ok, 'Not now is taken')
  T.check(area.adds == 0, 'with nothing downloaded')
  -- **Not now STOPS** (the user, 2026-11-14: "when I click no to download, it should stop auto recce. instead it
  -- teliports me there and still runs recce"). Nothing moves and nothing is matched -- an earlier cut carried on
  -- to the teleport and the match, which is the behaviour this replaces.
  T.check(main.uiState().auto == nil, 'and the sequence is over')
  T.check(graphCalls() == hadCalls, 'no window was asked for after No (' .. graphCalls() .. ')')
  local after = main.uiStage('seq', 'near')
  T.check(after and after.autoLine and tostring(after.autoLine.text):find('nothing downloaded'),
    'the player is told nothing was downloaded and it stopped (' ..
    tostring(after and after.autoLine and after.autoLine.text) .. ')')
  T.check(main.uiAction('reset', 'seq', 'near').ok, 'and the page is not left busy afterwards')

  -- **The second press does exactly what the first did** (the user: "the seconbd pressa should work the same as
  -- the firest"). It prices the ground again and asks again -- nothing is remembered, so one button never has two
  -- behaviours with no way to tell which is coming.
  local plansWas = area.plans
  main.uiAction('autoRecce', 'seq', 'near')
  T.check(area.plans == plansWas + 1, 'pressing again prices it again (' .. area.plans .. ')')
  T.check(main.uiState().auto and main.uiState().auto.phase == 'asking',
    'and asks again, as the first press did (' .. tostring(main.uiState().auto and main.uiState().auto.phase) .. ')')
  T.check(graphCalls() == hadCalls, 'with still no window asked for (' .. graphCalls() .. ')')
  main.uiAction('autoRecceSkip')

  -- ------------------------------------------------------------ the player says yes
  area.state = 'running'
  local plansAtYes = area.plans
  main.uiAction('autoRecce', 'seq', 'n2')
  T.check(main.uiState().auto and main.uiState().auto.phase == 'asking', 'a stage not yet declined is asked')
  local yes = main.uiAction('autoRecceDownload')
  T.check(yes.ok and area.adds == 1, 'Download starts one download (' .. area.adds .. ')')
  T.check(area.lastName and area.lastName:find('Earth Rally'),
    'the area is named so the player knows whose it is (' .. tostring(area.lastName) .. ')')
  T.check(area.addOpts.fast == nil, 'and is never added fast')
  tick(2)
  local dl = main.uiState().auto
  T.check(dl and dl.phase == 'downloading', 'the sequence is downloading (' .. tostring(dl and dl.phase) .. ')')
  T.check(dl.area and dl.area.total == 30, 'and carries the area progress (' ..
    tostring(dl.area and dl.area.done) .. ' / ' .. tostring(dl.area and dl.area.total) .. ')')
  -- (1.7.2, the page's bar) the size asked about, and how long the count has sat still: it never moves here
  T.check(dl.downloaded == true and type(dl.bytes) == 'number' and dl.bytes > 0,
    'and the size it asked about, for "about N MB in all" (' .. tostring(dl.bytes) .. ')')
  local q0 = dl.quietS
  tick(4)
  local q1 = main.uiState().auto.quietS
  T.check(type(q0) == 'number' and type(q1) == 'number' and q1 >= q0 + 2,
    'and the seconds the count has sat still grow while it does not move (' .. tostring(q0) .. ' -> ' .. tostring(q1) .. ')')

  -- it finishes, the match is tried again -- and the road graph still finds nothing, so it must NOT loop
  area.state = 'done'
  tick(6)
  T.check(area.adds == 1, 'ONE download a press, however the second match goes (' .. area.adds .. ')')
  T.check(area.plans == plansAtYes + 1,
    'and the estimate was asked for once for this press, not again after the download (' .. area.plans .. ')')
  T.check(main.uiState().auto == nil, 'the sequence has ended rather than going round again')
  T.check(main.uiAction('reset', 'seq', 'near').ok, 'and the page is free')

  -- ------------------------------------------------------------ one area a stage (BeamNG.Earth 1.10 has no cap)
  -- The owner had Stage Road three times and Orchard - Shoreline twice (2026-11-16): every Download added another
  -- pinned area. The press is unchanged -- priced and asked every time (the user, 2026-11-14) -- but Download on a
  -- stage that already has an area uses that one.
  area.state = 'running'
  local addsWas = area.adds
  main.uiAction('autoRecce', 'seq', 'n2')
  T.check(main.uiState().auto and main.uiState().auto.phase == 'asking',
    'a stage with an area still downloading is asked, as every press is')
  main.uiAction('autoRecceDownload')
  T.check(main.uiState().auto and main.uiState().auto.phase == 'downloading', 'Download follows it')
  T.check(area.adds == addsWas, 'and adds no second area (' .. area.adds .. ')')
  area.state = 'done'
  tick(6)
  T.check(main.uiState().auto == nil, 'it ends when that download does')
  -- the book is read back from the file: the next session's press still finds the area
  main._areaBookReset()
  area.unavailable, area.msg = 3, '3 items unavailable: Resume tries again'
  main.uiAction('autoRecce', 'seq', 'n2')
  main.uiAction('autoRecceDownload')
  T.check(area.adds == addsWas, 'after a reload, a finished area is not added again (' .. area.adds .. ')')
  tick(6)
  T.check(main.uiState().auto == nil, 'and the sequence ends')
  local un = main.uiStage('seq', 'n2')
  T.check(un and un.autoLine and tostring(un.autoLine.text):find('Resume'),
    'the player is told to resume it (' .. tostring(un and un.autoLine and un.autoLine.text) .. ')')
  area.unavailable, area.msg = 0, nil
  -- paused by the player: not waited on for half an hour
  area.state = 'paused'
  main.uiAction('autoRecce', 'seq', 'n2')
  main.uiAction('autoRecceDownload')
  tick(4)
  T.check(main.uiState().auto == nil, 'a paused area ends the wait (' ..
    tostring(main.uiState().auto and main.uiState().auto.phase) .. ')')
  local pz = main.uiStage('seq', 'n2')
  T.check(pz and pz.autoLine and tostring(pz.autoLine.text):find('paused'),
    'and says it is paused (' .. tostring(pz and pz.autoLine and pz.autoLine.text) .. ')')
  -- deleted mid-download: not waited on either
  area.state = 'running'
  main.uiAction('autoRecce', 'seq', 'n2')
  main.uiAction('autoRecceDownload')
  tick(2)
  area.gone = true
  tick(30)
  T.check(main.uiState().auto == nil, 'a deleted area ends the wait (' ..
    tostring(main.uiState().auto and main.uiState().auto.phase) .. ')')
  local gone = main.uiStage('seq', 'n2')
  T.check(gone and gone.autoLine and tostring(gone.autoLine.text):find('deleted'),
    'and says so (' .. tostring(gone and gone.autoLine and gone.autoLine.text) .. ')')
  T.check(area.adds == addsWas, 'and in all of it, one area for the stage (' .. area.adds .. ')')
  area.gone = false

  -- ------------------------------------------------------------ a FAR stage goes there first
  -- A road-graph window is placed in the anchor's frame, so one asked for 3400 km away lands hundreds of km from
  -- the stage. Measured in a game 2026-11-14; this is the check that the button goes there before asking.
  car.lat, car.lon = line[1][1], line[1][2]
  local wasLat = car.lat
  local b = main.uiAction('autoRecce', 'seq', 'away')
  T.check(b.ok, 'a far stage: the auto recce starts (' .. tostring(b.message) .. ')')
  -- the point of the order the user asked for: asked BEFORE being teleported across the world
  T.check(main.uiState().auto.phase == 'asking', 'the question comes first (' ..
    tostring(main.uiState().auto.phase) .. ')')
  T.near(car.lat, wasLat, 1e-9, 'and the car has NOT been moved yet')
  -- No on a far stage must not move them either: that was the whole complaint
  main.uiAction('autoRecceSkip')
  T.check(main.uiState().auto == nil, 'No stops it')
  T.near(car.lat, wasLat, 1e-9, 'and the car was never moved')

  -- the second press asks again, and it is the DOWNLOAD that sends it on its way
  local b2 = main.uiAction('autoRecce', 'seq', 'away')
  T.check(b2.ok and main.uiState().auto and main.uiState().auto.phase == 'asking',
    'pressing again asks again (' .. tostring(main.uiState().auto and main.uiState().auto.phase) .. ')')
  T.near(car.lat, wasLat, 1e-9, 'still not moved')
  area.state = 'running'
  main.uiAction('autoRecceDownload')
  T.check(main.uiState().auto and main.uiState().auto.phase == 'downloading',
    'saying yes downloads FIRST (' .. tostring(main.uiState().auto and main.uiState().auto.phase) .. ')')
  T.near(car.lat, wasLat, 1e-9, 'and still has not moved them -- download first, then teleport')
  area.state = 'done'
  tick(4)
  T.check(main.uiState().auto and main.uiState().auto.phase == 'going',
    'and only once it is downloaded does it go (' ..
    tostring(main.uiState().auto and main.uiState().auto.phase) .. ')')
  T.near(car.lat, far[1][1], 0.01, 'the car really was moved there')
  main.uiAction('autoRecceStop')
  T.check(main.uiState().auto == nil, 'Stop ends the sequence mid-journey')

  -- ------------------------------------------------------------ a far stage WITH an ATC lands at the ATC
  -- "when you press auto recce, it teliports you to the stage start, this means when you press run stage, you
  -- unintentinaly skip the ATC" (the user, 2026-11-14). Landing at the start left the car within NO_SET_DOWN_M of
  -- a near ATC, so Run stage kept it there and the first thing it did was drive past the time control.
  car.lat, car.lon = line[1][1], line[1][2]
  local faced, hadFace = 0, runner.faceStage
  local atced, hadAtc = 0, runner.faceAtc
  runner.faceStage = function() faced = faced + 1 return true, 'stub' end
  runner.faceAtc = function() atced = atced + 1 return true, 'stub' end
  area.state = 'running'
  T.check(main.uiAction('autoRecce', 'seq', 'awayAtc').ok, 'a far stage with an ATC: the auto recce starts')
  main.uiAction('autoRecceDownload')
  area.state = 'done'
  tick(4)
  T.check(main.uiState().auto and main.uiState().auto.phase == 'going', 'it goes there (' ..
    tostring(main.uiState().auto and main.uiState().auto.phase) .. ')')
  T.near(car.lat, far[1][1] - 0.0009, 1e-6, 'to the ATC, not the start line')
  T.near(car.lon, far[1][2], 1e-6, 'to the ATC (lon)')
  local alat, alon, akind = runner.arrivalPoint(evs.stages[3])
  T.check(akind == 'ATC' and math.abs(alat - car.lat) < 1e-9 and math.abs(alon - car.lon) < 1e-9,
    'the same point Run stage arrives at (' .. tostring(akind) .. ')')
  tick(runner.TELEPORT_SETTLE_S + 4)
  T.check(main.uiState().auto == nil or main.uiState().auto.phase ~= 'going',
    'the landing has settled and the match begun (' .. tostring(main.uiState().auto and main.uiState().auto.phase) .. ')')
  T.check(faced == 0, 'and the car is NOT then moved behind the start line (faceStage called ' .. faced .. 'x)')
  T.check(atced == 1, 'it is set down on the road before the ATC instead (faceAtc called ' .. atced .. 'x)')
  main.uiAction('autoRecceStop')
  -- the control: the same far stage WITHOUT an ATC still lands at the start and is turned along the stage
  car.lat, car.lon = line[1][1], line[1][2]
  area.state = 'running'
  main.uiAction('autoRecce', 'seq', 'awayNoAtc')
  main.uiAction('autoRecceDownload')
  area.state = 'done'
  tick(4)
  T.near(car.lat, far[1][1], 1e-6, 'no ATC: lands at the start')
  tick(runner.TELEPORT_SETTLE_S + 4)
  T.check(faced == 1 and atced == 1, 'and is turned along the stage there (faceStage ' .. faced .. 'x, faceAtc ' ..
    atced .. 'x)')
  runner.faceStage, runner.faceAtc = hadFace, hadAtc
  main.uiAction('autoRecceStop')

  -- ------------------------------------------------------------ a second press while one runs is refused
  car.lat, car.lon = line[1][1], line[1][2]
  main.uiAction('autoRecce', 'seq', 'n3')
  local second = main.uiAction('autoRecce', 'seq', 'n3')
  T.check(not second.ok and second.message:find('under way'),
    'a second auto recce while one waits on the player: refused (' .. tostring(second.message) .. ')')
  T.check(not main.uiAction('drive', 'seq', 'n3').ok, 'and no run either')
  main.uiAction('autoRecceSkip')

  -- ------------------------------------------------------------ an area the app will not take
  area.addOk = false
  main.uiAction('autoRecce', 'seq', 'n4')
  local bad = main.uiAction('autoRecceDownload')
  T.check(bad.ok, 'Download is taken even when the app refuses the area')
  T.check(main.uiState().auto == nil, 'and the sequence ends rather than hanging')
  -- Through autoLines, which is how an async ending reaches the page: `message` is the developer panel's own
  -- string and the Vue never sees it. The two refusals that matter -- the cache share full, all ten slots taken --
  -- would otherwise be written where nobody looks.
  local line9 = main.uiStage('seq', 'n4')
  T.check(line9 and line9.autoLine and tostring(line9.autoLine.text):find('saved areas are full'),
    'the app own reason reaches the stage page, because only the player can act on it (' ..
    tostring(line9 and line9.autoLine and line9.autoLine.text) .. ')')
  area.addOk = true

  -- ------------------------------------------------------------ without the capability: exactly 1.3.0
  beamngEarth_api.has = function(n)
    return n == 'transform' or n == 'rebase' or n == 'gpsRoute' or n == 'roadGraph'
  end
  local before = area.plans
  local c = main.uiAction('autoRecce', 'seq', 'near')
  -- The stand-in road graph answers inside the call, so the refusal is already known when the action returns --
  -- which is what 1.3.0 did too ("it can fail inside its first window, in which case autoDone has already run").
  T.check(not c.ok and tostring(c.message):find('no map data'),
    'without the area capability the stage is simply refused (' .. tostring(c.message) .. ')')
  T.check(area.plans == before, 'and no estimate is ever asked for (' .. area.plans .. ')')
  T.check(main.uiState().auto == nil, 'nothing is left running')

  beamngEarth_api.has, beamngEarth_api.roadGraph = hadHas, hadGraph
  beamngEarth_api.areaPlan, beamngEarth_api.areaAdd, beamngEarth_api.areaStatus = nil, nil, nil
  events.resetLine('seq', 'near')
end

--------------------------------------------- A full rally's next stage looked ahead; the car set down after (1.7.3)

-- docs/plan-recce-speed.md Part A: item 1 (made safer: while a stage runs its own auto recce, only the next stage is
-- priced and its area added; it follows that download at its turn), item 4 (the car set down from the matched ATC when the
-- landing found no road), item 7 (one timing line per auto recce).
do
  local main = require('earthRally/main')
  local auto = require('earthRally/autoRecce')
  local rallyRun = require('earthRally/rallyRun')
  local geo_m = require('earthRally/geo').metres
  local line = event.stages[1].line
  local far = {}
  for i, q in ipairs(line) do far[i] = { q[1] - 6.37, q[2] + 37.81 } end
  local atcPt = { lat = far[1][1] - 0.0009, lon = far[1][2] }
  local evq = { format = 1, id = 'rq', name = 'Queue Rally', stages = {
    { id = 's1', name = 'Stage One', lengthM = 3000, line = far,
      controls = { start = { lat = far[1][1], lon = far[1][2] }, atc = atcPt } },
    { id = 's2', name = 'Stage Two', lengthM = 3000, line = line },
    { id = 's3', name = 'Stage Three', lengthM = 3000, line = line },
    { id = 's4', name = 'Stage Four', lengthM = 3000, line = line },
  } }
  files['/earthRally/events/rq.json'] = evq
  events.list(true)
  local S = evq.stages

  local had = { has = beamngEarth_api.has, roadGraph = beamngEarth_api.roadGraph, areaPlan = beamngEarth_api.areaPlan,
    areaAdd = beamngEarth_api.areaAdd, areaStatus = beamngEarth_api.areaStatus, start = auto.start,
    preparing = rallyRun.preparing, active = rallyRun.active, prepNext = rallyRun.prepNext,
    prepDone = rallyRun.prepDone, uiCard = rallyRun.uiCard, faceAtc = runner.faceAtc,
    faceAtcFrom = runner.faceAtcFrom, log = log, wall = auto.wall }
  local lines = {}
  log = function(level, tag, msg) lines[#lines + 1] = tostring(msg) had.log(level, tag, msg) end
  local function logged(pat)
    local n = 0
    for _, l in ipairs(lines) do if l:find(pat) then n = n + 1 end end
    return n
  end
  beamngEarth_api.has = function(n)
    return n == 'transform' or n == 'rebase' or n == 'gpsRoute' or n == 'roadGraph' or n == 'areaRoute'
  end
  beamngEarth_api.roadGraph = function(_, _, _, cb) cb({ nodes = {}, edges = {}, complete = false }) return true end
  -- the area tool: estimates and adds answered when the test says, areas finished when it says
  local plans, addQ, addNames, status, nAdds = {}, {}, {}, {}, 0
  beamngEarth_api.areaPlan = function(_, _, cb) plans[#plans + 1] = cb return true end
  beamngEarth_api.areaAdd = function(_, opts, cb)
    nAdds = nAdds + 1
    local id = 'q' .. nAdds
    addNames[#addNames + 1] = opts.name
    addQ[#addQ + 1] = function(take, why)
      if take == false then cb({ ok = false, error = why }) return end
      status[id] = { state = 'queued', done = 0 }
      cb({ ok = true, id = id })
    end
    return true
  end
  beamngEarth_api.areaStatus = function(id)
    local st = status[id]
    if not st then return nil end
    return { id = id, name = 'x', state = st.state, done = st.done or 0, total = 30, unavailable = 0 }
  end
  local need = { ok = true, downloadBytes = 34000000, diskBytes = 1, km = 3, items = 59, missing = 59 }
  local none = { ok = true, downloadBytes = 0, diskBytes = 1, km = 3, items = 59, missing = 0 }
  -- the rally's prep, as rallyRun keeps it (rallyRun.getReady / prepNext / prepDone)
  local prep = { list = { S[1], S[2], S[3], S[4] }, i = 0 }
  local prepDone = 0
  rallyRun.preparing = function() return prep end
  rallyRun.active = function() return prep and { eventId = 'rq' } or nil end
  rallyRun.prepNext = function()
    prep.i = prep.i + 1
    prep.current = prep.list[prep.i]
    return prep.current, prep.i, #prep.list
  end
  rallyRun.prepDone = function() prepDone = prepDone + 1 prep = nil end
  rallyRun.uiCard = function()
    if not prep then return nil end
    local rows = {}
    for k, st in ipairs(prep.list) do
      rows[k] = { name = st.name, state = k < prep.i and 'done' or (k == prep.i and 'now' or 'wait') }
    end
    return { prep = { i = prep.i, of = #prep.list, stages = rows } }
  end
  -- the match: recorded, and over at once (its own windows are test_autorecce's)
  local matchedIds, matchOk = {}, false
  auto.start = function(_, stage, done)
    matchedIds[#matchedIds + 1] = stage.id
    if matchOk then
      done(true, { controls = { atc = { lat = atcPt.lat, lon = atcPt.lon, roadLat = atcPt.lat, roadLon = atcPt.lon,
        offM = 0, deg = 0 } } }, nil, { kind = auto.DONE, windows = 2, done = 2, windowsS = 1.5, matchS = 0.002 })
    else
      done(false, nil, 'stand-in', { kind = auto.NODATA, windows = 2, done = 2, windowsS = 1.5, matchS = 0.002 })
    end
    return true
  end
  local atced, fromCalls = 0, {}
  runner.faceAtc = function() atced = atced + 1 return false, 'no road on the map there' end
  runner.faceAtcFrom = function(stage, atc) fromCalls[#fromCalls + 1] = { stage = stage, atc = atc } return true, 'stub' end
  -- (the wall clock the timing line and the look-ahead read, moved on with the frames)
  local now = 0
  auto.wall = function() return now end
  local function tick(n) for _ = 1, (n or 1) do now = now + 0.5 main.onUpdate(0.5, 0.5) end end
  local function settle() tick(runner.TELEPORT_SETTLE_S + 12) end
  local function phase() local a = main.uiState().auto return a and a.phase end
  main._areaBookReset()
  files[main.AREA_BOOK_FILE] = nil
  car.lat, car.lon = line[1][1], line[1][2]

  -- ------------------------------------------------------------ stage 1 the 1.7.0 way, stage 2 looked ahead
  -- (looked ahead only once stage 1 has left its download: BeamNG.Earth downloads one area at a time, in the order
  --  they were added, and neighbouring stages share ground)
  tick()
  T.check(#plans == 1 and prep.i == 1 and phase() == 'planning',
    'look-ahead: stage 1 priced on its own, as a press of the button (' .. #plans .. ' estimate(s))')
  tick(4)
  T.check(#plans == 1, 'no look-ahead while stage 1 is still being priced (' .. #plans .. ')')
  plans[1](need)
  tick()
  T.check(phase() == 'downloading' and nAdds == 1 and addNames[1]:find('Stage One'),
    'stage 1 asked and answered yes for the player, its own area added first (' .. tostring(phase()) .. ')')
  tick(4)
  T.check(#plans == 1, 'no look-ahead estimate while stage 1 is DOWNLOADING, its add not answered (' .. #plans .. ')')
  addQ[1]()                    -- (stage 1's: q1)
  status.q1 = { state = 'downloading', done = 10 }
  tick(6)
  T.check(phase() == 'downloading' and #plans == 1 and nAdds == 1,
    'nor while its download runs: nothing priced or added ahead of it (' .. #plans .. ', ' .. nAdds .. ')')
  status.q1 = { state = 'done', done = 30 }
  tick(2)
  T.check(phase() == 'going', 'its download done, stage 1 goes there (' .. tostring(phase()) .. ')')
  T.check(#plans == 2, 'and only now is stage 2 priced ahead of its turn (' .. #plans .. ')')
  tick(4)
  T.check(#plans == 2, 'and only stage 2: one look-ahead at a time (' .. #plans .. ')')
  plans[2](need)
  T.check(nAdds == 2 and addNames[1]:find('Stage One') and addNames[2]:find('Stage Two'),
    'stage 2 needs ground: its area added ahead, after stage 1\'s (' .. nAdds .. ')')
  addQ[2]()                    -- (stage 2's: q2)
  local book = files[main.AREA_BOOK_FILE]
  T.check(book and book.areas['rq|s1'] and book.areas['rq|s2'] and not book.areas['rq|s3'],
    'each area is in the area book, so no press or rally adds it again')
  local card = main.uiRallyCard()
  T.check(card.prep.stages[2].queued == nil and card.prep.stages[2].area == nil,
    'the tracker rows carry no unused look-ahead fields')
  settle()
  T.check(matchedIds[1] == 's1' and atced == 1, 'and is matched (' .. tostring(matchedIds[1]) .. ')')
  T.check(#fromCalls == 0, 'item 4: not set down from the matched ATC during the prep (the next stage moves it)')
  T.check(logged('auto recce timing: s1: price ') == 1, 'item 7: one timing line for stage 1')

  -- ------------------------------------------------------------ stage 2 follows its own download
  tick(2)
  T.check(prep.i == 2 and phase() == 'downloading', 'stage 2 next, following its download (' .. tostring(phase()) .. ')')
  T.check(#plans == 2, 'not priced again, and stage 3 not looked ahead while stage 2 downloads (' .. #plans .. ')')
  status.q2 = { state = 'done', done = 30 }
  settle()
  T.check(matchedIds[2] == 's2', 'stage 2 matched once its download finished (' .. tostring(matchedIds[2]) .. ')')
  T.check(logged('auto recce timing: s2: .*queued with the rally') == 1, 'item 7: its timing line says so')
  T.check(#plans == 3, 'stage 3 looked ahead while stage 2 went there and matched (' .. #plans .. ')')

  -- ------------------------------------------------------------ an estimate that times out: priced again at its turn
  plans[3]({ ok = false, error = 'timed out' })
  tick()
  T.check(prep.i == 3 and #plans == 4 and phase() == 'planning',
    'stage 3: its look-ahead timed out, so it is priced again at its turn, not taken as "nothing missing" (' ..
    #plans .. ', ' .. tostring(phase()) .. ')')
  tick()
  T.check(#plans == 4, 'and stage 4 is not looked ahead while stage 3 is priced (' .. #plans .. ')')
  plans[4](need)
  tick()
  T.check(phase() == 'downloading' and nAdds == 3 and addNames[3]:find('Stage Three'),
    'stage 3 answered yes and its area added (' .. nAdds .. ')')
  addQ[3]()
  status.q3 = { state = 'done', done = 30 }
  tick(2)
  T.check(matchedIds[3] == 's3', 'stage 3 matched (' .. tostring(matchedIds[3]) .. ')')
  T.check(prep.i == 4 and #plans == 5, 'stage 4 priced at its turn (' .. #plans .. ')')
  plans[5](none)
  tick()
  T.check(matchedIds[4] == 's4' and nAdds == 3, 'stage 4, nothing missing, straight on (' .. tostring(matchedIds[4]) .. ')')
  tick(2)
  T.check(prepDone == 1 and main._rallyQueue() == nil, 'the prep done, its look-ahead cleared')
  T.check(logged('auto recce timing:') == 4, 'one timing line per stage (' .. logged('auto recce timing:') .. ')')
  local order = {}
  for k, nm in ipairs(addNames) do order[k] = nm:match('Stage %a+') end
  T.check(table.concat(order, ',') == 'Stage One,Stage Two,Stage Three',
    'each area added in stage order, the current stage\'s first (' .. table.concat(order, ',') .. ')')

  -- ------------------------------------------------------------ a second rally adds nothing again
  prep, prepDone, matchedIds = { list = { S[1], S[2] }, i = 0 }, 0, {}
  plans = {}
  tick(2)
  plans[1](need)
  tick(3)
  T.check(#plans == 2, 'run again: stage 1 follows its area, then stage 2 is looked ahead (' .. #plans .. ')')
  plans[2](need)
  T.check(nAdds == 3, 'run again: the stages that have areas follow them, none added (' .. nAdds .. ')')
  settle()
  settle()
  T.check(#matchedIds == 2 and prepDone == 1, 'and both are matched (' .. #matchedIds .. ')')
  local bookKeep = files[main.AREA_BOOK_FILE]       -- (the single stage's button below follows stage 1's area)

  -- the prep over and anything still running stopped, between the cases
  local function done()
    prep = nil
    main.uiAction('autoRecceStop')
    tick()
  end
  -- a fresh prep, the area book empty: `go()` starts it, stage 1 priced. With `lead`, stage 1 needs nothing and goes
  -- there, so stage 2 is looked ahead (plans[2])
  local function go(list, lead)
    main._areaBookReset()
    files[main.AREA_BOOK_FILE] = nil
    prep, prepDone, matchedIds, plans = { list = list, i = 0 }, 0, {}, {}
    car.lat, car.lon = line[1][1], line[1][2]       -- (stage 1 far: it goes there, the look-ahead's time)
    tick(2)
    if lead then
      plans[1](none)
      tick(2)
    end
  end

  -- ------------------------------------------------------------ an add that is refused
  go({ S[1], S[2], S[3] }, true)
  local adds0 = nAdds
  plans[2](need)
  addQ[#addQ](false, 'the saved areas are full')
  T.check(logged('would not take the area %(the saved areas are full%)') == 1, 'stage 2: its look-ahead add refused')
  settle()
  settle()
  T.check(prep.i >= 2 and matchedIds[2] == 's2' and #plans == 3 and nAdds == adds0 + 1,
    'at its turn: matched with what is here, not priced or added again (' .. #plans .. ', ' .. (nAdds - adds0) .. ')')
  done()

  -- ------------------------------------------------------------ a queued area missing from BeamNG.Earth's list
  go({ S[1], S[2], S[3] }, true)
  plans[2](need)
  addQ[#addQ]()
  local gone = 'q' .. nAdds
  status[gone] = nil                 -- (taken, then deleted by the player before it was ever listed)
  tick(math.ceil(main.AREA_GONE_S * 2) + 4)   -- (stage 1 done, more than AREA_GONE_S since the add)
  T.check(prep.i == 2, 'stage 2\'s turn (' .. prep.i .. ')')
  tick(math.ceil(main.AREA_GONE_S * 2) + 4)
  T.check(phase() ~= 'downloading' and logged('area ' .. gone .. ' is gone; matching with what is here') == 1,
    'its area never in the list, added longer than AREA_GONE_S ago: taken as gone, not a half-hour wait (' ..
    tostring(phase()) .. ')')
  done()

  -- ------------------------------------------------------------ the QUEUE_WAIT_S fallback
  local hadWait = main.QUEUE_WAIT_S
  -- (a) the estimate never answered: priced again at its turn, and the late answer adds nothing
  go({ S[1], S[2], S[3] }, true)
  local late = plans[2]
  local addsA = nAdds
  settle()
  T.check(prep.i == 2 and #plans == 2 and phase() == nil, 'stage 2\'s turn, its estimate still out: waiting')
  main.QUEUE_WAIT_S = 1
  tick(2)
  T.check(logged("Stage Two's look%-ahead did not settle") == 1 and #plans >= 3 and phase() == 'planning',
    'given up after QUEUE_WAIT_S: priced again, the 1.7.0 way (' .. #plans .. ')')
  late(need)
  T.check(nAdds == addsA, 'and the look-ahead\'s late answer adds no area (' .. (nAdds - addsA) .. ')')
  plans[3](none)
  settle()
  T.check(matchedIds[#matchedIds] == 's2', 'stage 2 matched')
  done()
  main.QUEUE_WAIT_S = hadWait
  -- (b) the add never answered: matched with what is here, and the late add booked, not added a second time
  go({ S[1], S[2], S[3] }, true)
  plans[2](need)
  local lateAdd = addQ[#addQ]
  local addsB = nAdds
  settle()
  main.QUEUE_WAIT_S = 1
  tick(2)
  T.check(logged("Stage Two's look%-ahead did not settle") == 2 and nAdds == addsB
    and phase() ~= 'planning' and phase() ~= 'downloading',
    'its add still out: given up, not priced or added again (' .. tostring(phase()) .. ', ' .. (nAdds - addsB) .. ')')
  settle()
  T.check(matchedIds[#matchedIds] == 's2', 'stage 2 matched with what is here (' .. tostring(matchedIds[#matchedIds])
    .. ')')
  lateAdd()
  T.check(files[main.AREA_BOOK_FILE].areas['rq|s2'] ~= nil and nAdds == addsB,
    'the late add is booked for the next press, and nothing more added')
  main.QUEUE_WAIT_S = hadWait
  done()

  -- ------------------------------------------------------------ the rally gone while a stage waits on its look-ahead
  go({ S[1], S[2], S[3] }, true)
  settle()
  T.check(prep.i == 2 and main._rallyQueue() and main._rallyQueue().next ~= nil,
    'stage 2\'s turn, waiting on its look-ahead estimate')
  local hadActive = rallyRun.active
  rallyRun.active = function() return nil end
  plans[2](none)                     -- (its look-ahead settles: the stage would start now, but the rally is gone)
  local okGone, errGone = pcall(tick, 2)
  rallyRun.active = hadActive
  T.check(okGone and prepDone == 1 and main._rallyQueue() == nil and phase() == nil
    and logged("attempt to index local 'rr'") == 0,
    'no rally any more: the prep ends, nothing started, no error (' .. tostring(errGone) .. ')')
  done()

  -- ------------------------------------------------------------ Stop mid-prep with a look-ahead in flight
  go({ S[1], S[2], S[3] }, true)
  plans[2](need)
  addQ[#addQ]()
  local aheadId = 'q' .. nAdds
  local stop = main.uiAction('autoRecceStop')
  -- (stage 1 is past its own download by now, so only stage 2's is named: one download, singular)
  T.check(stop.ok and tostring(stop.message):find(
    "Auto recce stopped. Stage Two's map download carries on in BeamNG.Earth's Areas.", 1, true),
    'Stop: the look-ahead\'s download is named as still going (' .. tostring(stop.message) .. ')')
  T.check(prepDone == 1 and main._rallyQueue() == nil and phase() == nil, 'and the prep and its look-ahead end')
  status[aheadId] = nil
  -- Stop with stage 1's own estimate still out: its late answer starts nothing
  go({ S[1], S[2], S[3] })
  stop = main.uiAction('autoRecceStop')
  local nP = #plans
  plans[1](need)
  tick(4)
  T.check(#plans == nP and phase() == nil, 'a late estimate after Stop starts nothing (' .. #plans .. ')')
  -- the look-ahead's add still unanswered when Stop is pressed: named too, as BeamNG.Earth may yet take it
  go({ S[1], S[2], S[3] }, true)
  plans[2](need)
  local lateStop, addsS = addQ[#addQ], nAdds
  stop = main.uiAction('autoRecceStop')
  T.check(tostring(stop.message):find("Stage Two's map download carries on", 1, true),
    'Stop with the look-ahead\'s add unanswered: it is named (' .. tostring(stop.message) .. ')')
  lateStop()
  T.check(nAdds == addsS and files[main.AREA_BOOK_FILE].areas['rq|s2'] ~= nil and phase() == nil,
    'and taken after Stop: booked, nothing more added or started')
  status['q' .. nAdds] = nil
  -- the look-ahead's estimate still out when Stop is pressed: its late answer adds nothing
  go({ S[1], S[2], S[3] }, true)
  local lateP, addsC = plans[2], nAdds
  stop = main.uiAction('autoRecceStop')
  T.check(not tostring(stop.message):find("Stage Two", 1, true),
    'Stop with nothing added ahead: nothing named (' .. tostring(stop.message) .. ')')
  lateP(need)
  T.check(nAdds == addsC, 'and the look-ahead\'s late estimate adds no area after Stop (' .. (nAdds - addsC) .. ')')
  -- the look-ahead's add still out when the rally is left: booked if taken, nothing else
  go({ S[1], S[2], S[3] }, true)
  plans[2](need)
  local lateQ = addQ[#addQ]
  main.uiRallyAction('quit', 'rq')
  done()
  lateQ()
  T.check(main._rallyQueue() == nil and phase() == nil, 'left with an add out: its late answer starts nothing')

  -- ------------------------------------------------------------ without the area capability: the 1.7.0 way
  beamngEarth_api.has = function(n)
    return n == 'transform' or n == 'rebase' or n == 'gpsRoute' or n == 'roadGraph'
  end
  prep, prepDone, matchedIds, plans = { list = { S[2], S[3] }, i = 0 }, 0, {}, {}
  car.lat, car.lon = line[1][1], line[1][2]
  tick(4)
  T.check(#plans == 0 and #matchedIds == 2 and prepDone == 1 and main._rallyQueue() == nil,
    'no area capability: no queue, each stage matched as before (' .. #matchedIds .. ')')
  beamngEarth_api.has = function(n)
    return n == 'transform' or n == 'rebase' or n == 'gpsRoute' or n == 'roadGraph' or n == 'areaRoute'
  end

  -- ------------------------------------------------------------ the single stage's button: unchanged, then item 4
  prep = nil
  main.uiAction('autoRecceStop')
  tick()
  main._areaBookReset()
  files[main.AREA_BOOK_FILE] = bookKeep
  local addsS = nAdds
  plans = {}
  car.lat, car.lon = line[1][1], line[1][2]
  local a = main.uiAction('autoRecce', 'rq', 's1')
  T.check(a.ok and #plans == 1 and phase() == 'planning', 'the button still prices its stage (' .. #plans .. ')')
  plans[1](need)
  T.check(phase() == 'asking', 'and still asks (' .. tostring(phase()) .. ')')
  main.uiAction('autoRecceDownload')
  T.check(nAdds == addsS and phase() == 'downloading', 'and follows the area it already has (' .. nAdds .. ')')
  status.q1 = { state = 'done' }
  matchOk = true
  tick(runner.TELEPORT_SETTLE_S + 10)
  T.check(phase() == nil and atced >= 1, 'landed at the ATC with no road there, and matched')
  T.check(#fromCalls == 1 and fromCalls[1].atc and fromCalls[1].atc.roadLat == atcPt.lat and fromCalls[1].stage.id == 's1',
    'item 4: then set down from the matched file\'s ATC (' .. #fromCalls .. ')')
  T.check(logged('auto recce timing: s1: price %d') >= 1 and logged('%(34%.0 MB%)') >= 1,
    'item 7: the button\'s timing line has the price leg and the MB')
  -- a landing that did find a road: not set down again
  runner.faceAtc = function() atced = atced + 1 return true, 'on the road map' end
  car.lat, car.lon = line[1][1], line[1][2]
  plans = {}
  main.uiAction('autoRecce', 'rq', 's1')
  plans[1](none)
  tick(runner.TELEPORT_SETTLE_S + 10)
  T.check(#fromCalls == 1, 'the landing found its road: the car is not moved again (' .. #fromCalls .. ')')
  matchOk = false

  beamngEarth_api.has, beamngEarth_api.roadGraph = had.has, had.roadGraph
  beamngEarth_api.areaPlan, beamngEarth_api.areaAdd, beamngEarth_api.areaStatus = had.areaPlan, had.areaAdd,
    had.areaStatus
  auto.start = had.start
  rallyRun.preparing, rallyRun.active, rallyRun.prepNext, rallyRun.prepDone, rallyRun.uiCard =
    had.preparing, had.active, had.prepNext, had.prepDone, had.uiCard
  runner.faceAtc, runner.faceAtcFrom = had.faceAtc, had.faceAtcFrom
  auto.wall = had.wall
  log = had.log
  main.onUpdate(0.5, 0.5)

  -- ------------------------------------------------------------ runner.faceAtcFrom itself
  -- the matched ATC (on its road, bearing north-south), the start 100 m north of it: the car 40 m south of it on
  -- that bearing, facing north, when the road map has no road there yet
  local propsM = require('earthRally/props')
  local hadRoad = propsM.roadAt
  propsM.roadAt = function() return nil end
  local mLat = math.rad(1) * R
  local stg = { id = 'fa', line = { { 47.01, -123.0 }, { 47.02, -123.0 } },
    controls = { start = { lat = 47.01, lon = -123.0 } } }
  local ctl = { roadLat = 47.01 - 100 / mLat, roadLon = -123.0, deg = 180, offM = 5 }
  car.lat, car.lon = ctl.roadLat + 0.0001, ctl.roadLon + 0.0001
  local hadPlace, face = runner.placeCar, nil
  runner.placeCar = function(veh, pos, f) face = f return hadPlace(veh, pos, f) end
  local ok, how = runner.faceAtcFrom(stg, ctl)
  local dS = geo_m(car.lat, car.lon, ctl.roadLat, ctl.roadLon)
  -- (1.7.3, the owner: "set down on the ATC road point": not 40 m back across ground with no road known, which put it
  --  outside DRIVEN_THERE_MIN_M of the board and had Run stage keep it there as "driven there")
  T.check(ok and dS < 1 and how == 'on the matched ATC road point',
    string.format('faceAtcFrom: no road map yet: on the matched ATC road point itself (%s, %.1f m)', tostring(how), dS))
  T.check(face and face.y > 0.99, 'turned along the matched road, the way on to the start (' ..
    tostring(face and face.y) .. ')')
  T.check(dS < runner.DRIVEN_THERE_MIN_M, 'inside DRIVEN_THERE_MIN_M, so Run stage sets it down properly later')
  -- the road point further than DRIVEN_THERE_MIN_M from the board: left on the raw point for Run stage
  car.lat, car.lon = ctl.roadLat + 0.0001, ctl.roadLon + 0.0001
  local far = { roadLat = ctl.roadLat, roadLon = ctl.roadLon, deg = 180, offM = 20,
    lat = ctl.roadLat, lon = ctl.roadLon + 20 / (mLat * math.cos(math.rad(ctl.roadLat))) }
  local la0 = car.lat
  T.check(runner.faceAtcFrom(stg, far) == false and car.lat == la0,
    'faceAtcFrom: a road point 20 m from the board is not used: the car is not moved')
  runner.placeCar = hadPlace
  car.lat = ctl.roadLat + 0.01
  T.check(runner.faceAtcFrom(stg, ctl) == false, 'faceAtcFrom: a car driven away from the ATC is not moved')
  car.lat = ctl.roadLat
  T.check(runner.faceAtcFrom(stg, { roadLat = ctl.roadLat }) == false, 'faceAtcFrom: no bearing in the file: not moved')
  propsM.roadAt = hadRoad
  runner._camUpdate(1)          -- (the camera resets the placing asked for, done now rather than in a later test)
end

-- A bridge's far end (review round 3): looked for only just past its start, so a stage that comes back alongside
-- (north 1 km, across 5 m, back south) does not take the far end from the return pass, and a far end more than
-- BRIDGE_MAX_M on, or behind the start, is dropped.
do
  local geo = require('earthRally/geo')
  local L = {}
  for y = 0, 1000, 10 do L[#L + 1] = { x = 0, y = y, z = 0 } end
  for y = 1000, 0, -10 do L[#L + 1] = { x = 5, y = y, z = 0 } end
  local cum = geo.cumulative(L)
  local e1 = runner.bridgeEnd(L, cum, 200, { x = 4, y = 260 })
  T.check(e1 and math.abs(e1 - 260) < 1e-6,
    'bridgeEnd: the far end on this pass, not the return pass it is nearer (' .. tostring(e1) .. ')')
  T.check(runner.bridgeEnd(L, cum, 200, { x = 0, y = 600 }) == nil, 'bridgeEnd: 400 m on, longer than any bridge: none')
  T.check(runner.bridgeEnd(L, cum, 200, { x = 0, y = 150 }) == nil, 'bridgeEnd: behind the start: none')
  T.check(runner.bridgeEnd(L, cum, 200, { x = 40, y = 260 }) == nil, 'bridgeEnd: 40 m off the line: none')
end

------------------------------------------------------------------------------------------ Route to start: driven in (GitHub #19)
-- Route to start arms the stage; driven up to it, it gets ready as Run stage would, with no teleport and the car
-- left where it is. The GPS is BeamNG.Earth's until 250 m out, the run's arrows from there.
do
  runner.abort(true)
  map = nil
  anchor = { lat = 47.0, lon = -123.0 }
  local kx = math.rad(1) * R * math.cos(math.rad(47.0))
  local atcLat, atcLon = full[11][1] - 600 / 111195, full[11][2] + 8 / kx      -- 600 m before the start, 8 m east
  local ev = { format = 1, id = 'test19', name = 'Test Rally 19', stages = { {
    id = 'hill', name = 'Hill', lengthM = 3000, radiusM = 1200, centre = event.stages[1].centre,
    controls = { start = event.stages[1].controls.start, ff = event.stages[1].controls.ff,
                 atc = { lat = atcLat, lon = atcLon } },
    line = event.stages[1].line } } }
  files['/earthRally/events/test19.json'] = ev
  files['/earthRally/matched/test19__hill.json'] = { format = 1, points = recFrom }
  local st = ev.stages[1]

  -- BeamNG.Earth's GPS: a destination, cleared by gpsClear; teleports counted
  local gpsDest, clears, teleports = nil, 0, 0
  local hadGps, hadClear, hadTp = beamngEarth_api.gps, beamngEarth_api.gpsClear, beamngEarth_api.teleport
  beamngEarth_api.gps = function() return gpsDest end
  beamngEarth_api.gpsClear = function() gpsDest = nil clears = clears + 1 end
  beamngEarth_api.teleport = function(lat, lon) teleports = teleports + 1 car.lat, car.lon = lat, lon return true end
  local function route(la, lo)
    gpsDest = { lat = la, lon = lo, name = 'x' }
    T.check(runner.armApproach(ev, st), 'Route to start arms the stage')
  end
  -- the car driven north along the road (the ATC's road, 8 m west of its board) at `ms`, one 0.1 s frame at a time,
  -- until `untilFn` says stop; false if the car was ever moved by anything but the driving
  local moved = false
  local function drive(ms, untilFn, maxFrames)
    car.speed = ms
    for _ = 1, maxFrames or 3000 do
      if untilFn() then return true end
      car.lat = car.lat + ms * 0.1 / 111195
      local la, lo = car.lat, car.lon
      frames(1)
      if car.lat ~= la or car.lon ~= lo then moved = true end
    end
    return false
  end
  local geo_m = require('earthRally/geo').metres
  local function toAtcM() return geo_m(car.lat, car.lon, atcLat, atcLon) end

  -- 1. armed 5 km out: nothing loads until the car is within APPROACH_M of the ATC
  car.lat, car.lon, car.speed = atcLat - 5000 / 111195, full[11][2], 0
  route(atcLat, atcLon)
  frames(5)
  T.check(runner.current() == nil and runner.approaching() ~= nil, 'driven in: 5 km out, armed and nothing loaded')
  local routesBefore = #routes
  local cams0 = camResets
  drive(30, function() return runner.current() ~= nil end)
  T.check(runner.current() ~= nil and toAtcM() <= runner.APPROACH_M + 5 and toAtcM() > runner.APPROACH_M - 10,
    string.format('driven in: the stage loads at %.0f m from the ATC', toAtcM()))
  T.check(runner.approaching() == nil, 'driven in: and the route is no longer armed')
  drive(30, function() return runner.state() == 'toAtc' end, 200)
  T.check(runner.state() == 'toAtc' and toAtcM() > 500,
    string.format('driven in: ready to drive (toAtc) while still %.0f m out', toAtcM()))
  T.check(runner.current().checks.atcSetDown == 'driven there' and teleports == 0 and not moved,
    'driven in: never teleported nor set down (' .. tostring(runner.current().checks.atcSetDown) .. ')')
  T.check(runner.current().checks.originMoved == 'yes' and camResets == cams0,
    'driven in: the origin moved with no camera reset (' .. tostring(runner.current().checks.originMoved) .. ', ' ..
    (camResets - cams0) .. ' resets)')
  drive(30, function() return toAtcM() < 300 end)
  T.check(#routes == routesBefore and clears == 0 and gpsDest ~= nil,
    'driven in: BeamNG.Earth\'s GPS leads while the car is far (' .. (#routes - routesBefore) .. ' arrows set)')
  drive(30, function() return toAtcM() < 200 end)
  T.check(#routes > routesBefore and clears == 1, 'driven in: the run\'s arrows from 250 m, the GPS cleared')
  -- rolling through the zone is no check-in; stopping in it is
  drive(10, function() return car.lat >= atcLat end)          -- (beside the board, 8 m off it)
  T.check(runner.current().startAt == nil and not moved, 'driven in: rolling into the ATC zone is not a check-in')
  car.speed = 0 frames(3)
  T.check(runner.current().startAt ~= nil and runner.current().checks.atc ~= nil,
    'driven in: stopped at the board, checked in (' .. tostring(runner.current().checks.atc) .. ')')
  -- checked in: driving off no longer unloads it
  car.lat = atcLat - 3000 / 111195 frames(10)
  T.check(runner.current() ~= nil, 'driven in: checked in, then far away: the run is kept')
  runner.abort(true)

  -- 2. the route cleared, or another destination set, before the car got there: disarmed, nothing loads
  car.lat, car.lon, car.speed = atcLat - 3000 / 111195, full[11][2], 0
  route(atcLat, atcLon)
  gpsDest = nil
  frames(10)
  T.check(runner.approaching() == nil, 'route cleared: disarmed')
  car.lat = atcLat - 500 / 111195 frames(10)
  T.check(runner.current() == nil, 'route cleared: driven near anyway, nothing loads')
  car.lat = atcLat - 3000 / 111195
  route(atcLat, atcLon)
  gpsDest = { lat = atcLat + 0.05, lon = atcLon, name = 'elsewhere' }
  frames(10)
  T.check(runner.approaching() == nil, 'another destination set: disarmed')
  -- a BeamNG.Earth that cannot say where its GPS goes: not armed at all (the route alone, as before)
  beamngEarth_api.gps = nil
  gpsDest = { lat = atcLat, lon = atcLon }
  T.check(not runner.armApproach(ev, st) and runner.approaching() == nil, 'no GPS to ask: not armed')
  car.lat = atcLat - 500 / 111195 frames(10)
  T.check(runner.current() == nil, 'no GPS to ask: driven near, nothing loads')
  beamngEarth_api.gps = function() return gpsDest end
  runner.disarmApproach('test')

  -- 3. loaded, then driven away (past it, or a change of mind) before checking in: unloaded, not re-armed
  car.lat, car.lon, car.speed = atcLat - 1500 / 111195, full[11][2], 0
  route(atcLat, atcLon)
  drive(30, function() return runner.state() == 'toAtc' end)
  T.check(runner.state() == 'toAtc', 'driven away: loaded first')
  car.lat = atcLat - 2500 / 111195 frames(10)
  T.check(runner.current() == nil and runner.approaching() ~= nil,
    'driven away before checking in: unloaded, armed again (the GPS still points there)')
  T.check(toasts[#toasts] and tostring(toasts[#toasts].msg):find('Follow the arrows back') ~= nil,
    'driven away: told (' .. tostring(toasts[#toasts] and toasts[#toasts].msg) .. ')')
  car.lat = atcLat - 900 / 111195 frames(10)
  T.check(runner.current() ~= nil and runner.current().drivenIn ~= nil, 'followed the arrows back: loaded again')
  -- the GPS sent elsewhere meanwhile: put away and not armed again
  gpsDest = nil
  car.lat = atcLat - 2500 / 111195 frames(10)
  T.check(runner.current() == nil and runner.approaching() == nil, 'driven away, the GPS cleared: not armed again')
  T.check(toasts[#toasts] and tostring(toasts[#toasts].msg):find('Route to start to run it') ~= nil,
    'driven away, no route: told to route again (' .. tostring(toasts[#toasts] and toasts[#toasts].msg) .. ')')

  -- 3b. (1.7.0) a full rally's transit: sticky -- armed with no GPS route at all, kept when the GPS is cleared,
  -- loaded as a rally pass, and armed again when driven away from
  runner.abort(true)
  gpsDest = nil
  car.lat, car.lon, car.speed = atcLat - 5000 / 111195, full[11][2], 0
  local started = 0
  T.check(runner.armApproach(ev, st, { sticky = true, title = 'SS4 Hill', rally = true,
    startOpts = { rally = true, ssLabel = 'SS4', keepDamage = true }, onStart = function() started = started + 1 end }),
    'rally transit: armed with no GPS route')
  frames(10)
  T.check(runner.approaching() ~= nil and runner.current() == nil, 'rally transit: kept with the GPS cleared, nothing loaded')
  local ai = runner.approachInfo()
  T.check(ai and ai.name == 'SS4 Hill' and ai.rally == true, 'rally transit: the HUD names the pass')
  drive(30, function() return runner.current() ~= nil end)
  T.check(runner.current() and runner.current().inRally and runner.current().ssLabel == 'SS4' and started == 1,
    'rally transit: loaded as the rally\'s pass, the rally told')
  car.lat = atcLat - 2500 / 111195 frames(10)
  T.check(runner.current() == nil and runner.approaching() ~= nil and runner.approaching().sticky,
    'rally transit: driven away before checking in, armed again with no GPS')
  car.lat = atcLat - 900 / 111195 frames(10)
  T.check(runner.current() ~= nil and started == 2, 'rally transit: back again, loaded again')
  runner.abort(true)
  runner.disarmApproach('test')

  -- 3c. (1.7.0) the full rally through rallyRun: the start on the map, the transit driven, the stage loaded as a
  -- rally pass, a Realistic recovery taking the car to the service it rejoins at (#26, #31, #33)
  do
    local rally = require('earthRally/rally')
    local rallyRun = require('earthRally/rallyRun')
    local parkLat, parkLon = atcLat - 8000 / 111195, full[11][2]
    local evR = { format = 1, id = 'test19r', name = 'Test Rally 19R', stages = ev.stages,
      itinerary = { { ss = 'SS1', stage = 'hill', run = 1, day = 1, km = 3 }, { ss = 'SS2', stage = 'hill', run = 2, day = 1, km = 3 } },
      rallyStops = { { after = 1, kind = 'service', label = 'Service A', name = 'Park',
        place = { name = 'Park', lat = parkLat, lon = parkLon } } },
      rallyStart = { name = 'Park', lat = parkLat, lon = parkLon } }
    files['/earthRally/events/test19r.json'] = evR
    files['/earthRally/matched/test19r__hill.json'] = { format = 1, points = recFrom }
    events.list(true)
    local opened = 0
    rallyRun.ui.openCard = function() opened = opened + 1 end
    rallyRun.ui.closeMenu = function() end
    FS.directoryExists = FS.directoryExists or function() return true end
    FS.directoryCreate = FS.directoryCreate or function() return true end
    local blockedOn = nil
    core_input_actionFilter = { setGroup = function() end, addAction = function(_, _, on) blockedOn = on end }
    local function rframes(n) for _ = 1, n do rallyRun.update(0.1) frames(1) end end
    car.lat, car.lon, car.speed = atcLat - 30000 / 111195, full[11][2], 0
    local si = rallyRun.startInfo('test19r')
    T.check(si and si.services == 1, 'rally: the start screen counts Service A, not the final service (' ..
      tostring(si and si.services) .. ')')
    local okR, whyR = rallyRun.start('test19r', { mode = 'realistic', class = 'L4WD' })
    T.check(okR and blockedOn == true, 'rally: started, the game\'s own recovery blocked (' .. tostring(whyR) .. ')')
    T.check(geo_m(car.lat, car.lon, parkLat, parkLon) < 1, 'rally: the car taken to the start on the map (#26)')
    T.check(rallyRun.uiCard().phase == 'moving', 'rally: on the way while the world loads')
    rframes(60)
    local cardR = rallyRun.uiCard()
    T.check(opened == 1 and cardR.phase == 'stop' and cardR.at.kind == 'start', 'rally: at the start, the time card up')
    T.check(files['/earthRally/rallies/test19r.json'] and files['/earthRally/rallies/test19r.json'].current,
      'rally: saved at the start')
    T.check(rallyRun.goNext() and runner.approaching() and runner.approaching().sticky, 'rally: out of the start, the transit armed')
    T.check(rallyRun.uiCard().phase == 'transit', 'rally: on a transit')
    -- (#58) rolled past the board at speed: nothing loads, nothing asked
    drive(30, function() return car.lat >= atcLat + 15 / 111195 end)
    rframes(3)
    T.check(runner.current() == nil and rallyRun.askInfo() == nil, 'rally: rolling past the board loads nothing (#58)')
    -- (the boards with no road point here: the map's ATC point, a wider ring round it -- stopped 40 m short of it)
    car.lat, car.speed = atcLat - 40 / 111195, 0
    rframes(3)
    local q = rallyRun.askInfo()
    T.check(runner.current() == nil and q and q.loadAsk and q.loadAsk.ss == 'SS1' and rallyRun.asking(),
      'rally: stopped near the ATC point of the map (no road point for its boards), "Load the stage?" asked (#58)')
    T.check(rallyRun.recoverKey() and rallyRun.askInfo() == q, 'rally: the recovery key does nothing while asked (#59)')
    T.check(rallyRun.answerLoad('notYet') and rallyRun.askInfo() == nil, 'rally: Not yet')
    rframes(5)
    T.check(runner.current() == nil and rallyRun.askInfo() == nil, 'rally: Not yet, still stopped there: not asked again')
    car.lat = atcLat - 90 / 111195 rframes(3)
    car.lat = atcLat rframes(3)
    T.check(rallyRun.askInfo() and rallyRun.askInfo().loadAsk, 'rally: left the board and stopped again: asked again')
    -- Load failing: said, and not asked again until the car has left and stopped again
    local realStart = runner.start
    runner.start = function() return false, 'made-up trouble' end
    local okF, whyF = rallyRun.answerLoad('load')
    runner.start = realStart
    T.check(not okF and tostring(whyF):find('made-up trouble', 1, true) ~= nil,
      'rally: Load failed: the reason given (' .. tostring(whyF) .. ')')
    rframes(60)
    T.check(runner.current() == nil and rallyRun.askInfo() == nil, 'rally: Load failed, still stopped: not asked again at once')
    car.lat = atcLat - 90 / 111195 rframes(3)
    car.lat = atcLat rframes(3)
    T.check(rallyRun.askInfo() and rallyRun.askInfo().loadAsk, 'rally: after the failure, left and stopped again: asked')
    local nToasts = #toasts
    T.check(rallyRun.answerLoad('load') and rallyRun.askInfo() == nil, 'rally: Load')
    local cur = runner.current()
    T.check(cur and cur.inRally and cur.ssLabel == 'SS1' and cur.rally and cur.rally.mode == 'realistic',
      'rally: SS1 loaded on the answer, the rally\'s pass')
    -- (#64) checked in behind the card where it stopped, the start time held for Continue, nothing said behind it
    rframes(30)
    T.check(cur.atcTime ~= nil and cur.startHeld and tostring(runner.startNote()):match('^%+%d+ min after Continue$'),
      'rally: checked in behind the card, the start time given at Continue (#64: ' .. tostring(runner.startNote()) .. ')')
    local saidAtc = false
    for k = nToasts + 1, #toasts do
      local m = tostring(toasts[k].msg)
      if m:find('Drive to the time control') or m:find('Your start time') then saidAtc = true end
    end
    T.check(not saidAtc, 'rally: no "drive to the time control" nor start time said behind the card (#64)')
    cur.clockRun = cur.clockRun + 120
    T.check(runner.continueAtc() and not cur.startHeld and cur.startAt >= runner.clock() + runner.START_GAP_S,
      'rally: Continue: the start time from then, not from the check-in (#64)')
    -- Realistic, checked in but not started: the recovery key is free, no question
    T.check(cur.state ~= 'running' and rallyRun.recoverKey() and cur.rally.ask == nil and rallyRun.askInfo() == nil,
      'rally: Realistic before the start: the recovery key is free, nothing asked (' .. tostring(cur.state) .. ')')
    -- a Realistic recovery during the stage: asked first, then the stage given up, the car to Service A (#31)
    cur.state = 'running'
    T.check(rallyRun.recoverKey() and cur.rally.ask ~= nil and rallyRun.asking(), 'rally: the recovery key asks first')
    rallyRun.update(15)
    T.check(cur.rally.ask ~= nil, 'rally: the question does not time out (#59)')
    T.check(rallyRun.recoverKey() and runner.current() == cur, 'rally: pressed again, no answer (#59: only the card)')
    T.check(rallyRun.answer('recover'), 'rally: Recover answered')
    T.check(runner.current() == nil and geo_m(car.lat, car.lon, parkLat, parkLon) < 1,
      'rally: the stage given up, the car taken to the service park')
    rframes(60)
    cardR = rallyRun.uiCard()
    T.check(opened == 2 and cardR.phase == 'stop' and cardR.at.label == 'Service A' and cardR.superRally,
      'rally: at Service A with the Super Rally card')
    T.check(rallyRun.active().results.SS1.superRally, 'rally: SS1 scored under Super Rally')
    T.check(rallyRun.goNext() and rally.current(rallyRun.active()).ss == 'SS2' and runner.approaching(),
      'rally: service out, the transit to SS2 armed')
    -- (#69) Realistic, on the transit: the Recover? question, not a free recovery
    T.check(rallyRun.recoverKey(), 'rally: the recovery key on the transit')
    local tq = rallyRun.askInfo()
    T.check(tq and tq.ask and tq.ask.transit and tq.ask.ss == 'SS2' and tq.ask.stop == nil and not tq.ask.toStop,
      'rally: Realistic transit to the last stage: Recover? asked, no stop to rejoin at -- the final service is none')
    T.check(rallyRun.answer('keep') and rallyRun.askInfo() == nil and runner.approaching(), 'rally: Keep going')
    local li = rallyRun.leaveInfo()
    T.check(li and li.at == 'Service A', 'rally: leaving now continues from Service A')
    -- (the owner) on the way to a stop with no stage before it: recovering takes the car there, nothing missed
    rallyRun.onFinished({ timeS = 200, stageS = 200, penaltyS = 0 })
    T.check(rallyRun.recoverKey(), 'rally: the recovery key on the way to the final service')
    local sq = rallyRun.askInfo()
    T.check(sq and sq.ask and sq.ask.toStop and sq.ask.stop == 'Final service',
      'rally: on the way to a stop: the card says it takes you there, no stage missed (ask.toStop)')
    T.check(rallyRun.answer('keep') and rallyRun.askInfo() == nil, 'rally: Keep going, on to the final service')
    rallyRun.quit()
    T.check(blockedOn == false and runner.approaching() == nil and rallyRun.active() == nil,
      'rally: left, the game\'s recovery back, the transit gone')
    T.check(rallyRun.saved('test19r') and rallyRun.saved('test19r').at == 'Service A', 'rally: the save is at Service A')
    rallyRun.abandon('test19r')
    T.check(rallyRun.saved('test19r') == nil, 'rally: retired, the save deleted')
    core_input_actionFilter = nil
    teleports, moved = 0, false
  end

  -- 3d. (1.7.0 rev 4) the rally's end: the start row on day 1 (#57), the final service driven to after the last stage
  -- and checked in only once stopped (#67), its board and tent (#68), the rally done there and closed (#71)
  do
    local rally = require('earthRally/rally')
    local rallyRun = require('earthRally/rallyRun')
    local props = require('earthRally/props')
    local parkLat, parkLon = atcLat - 8000 / 111195, full[11][2]
    files['/earthRally/events/test19f.json'] = { format = 1, id = 'test19f', name = 'Test Rally 19F', stages = ev.stages,
      itinerary = { { ss = 'SS1', stage = 'hill', run = 1, day = 1, km = 3 } },
      rallyStops = { { after = 1, kind = 'service', label = 'Service A', name = 'Park',
        place = { name = 'Park', lat = parkLat, lon = parkLon } } },
      rallyStart = { name = 'Park', lat = parkLat, lon = parkLon } }
    files['/earthRally/matched/test19f__hill.json'] = { format = 1, points = recFrom }
    events.list(true)
    local opened = 0
    rallyRun.ui.openCard = function() opened = opened + 1 end
    core_input_actionFilter = { setGroup = function() end, addAction = function() end }
    local function rframes(n) for _ = 1, n do rallyRun.update(0.1) frames(1) end end
    car.lat, car.lon, car.speed = parkLat, parkLon, 0
    T.check(rallyRun.start('test19f', { mode = 'casual', class = 'L4WD' }), 'rally end: started')
    rframes(60)
    local c = rallyRun.uiCard()
    local labels = {}
    for _, row in ipairs(c.rows) do labels[#labels + 1] = row.label end
    T.check(table.concat(labels, ' ') == 'Start SS1 Final service' and c.rows[3].final,
      'rally end: the order ends at a final service, the stop the event has after its last pass (#71: ' ..
      table.concat(labels, ' ') .. ')')
    T.check(c.rows[1].day == 1, 'rally end: the start row on day 1 (#57)')
    T.check(rallyRun.goNext() and runner.approaching(), 'rally end: on the transit to SS1')
    -- the stage driven (its finish told to the rally straight away), the final service driven to
    rallyRun.onFinished({ timeS = 200, stageS = 200, penaltyS = 0 })
    T.check(not rally.over(rallyRun.active()) and rallyRun.uiCard().phase == 'toStop',
      'rally end: after the last stage, the drive back to the final service (#71)')
    T.check(props.site('service') ~= nil, 'rally end: the final service has its board and tent (#68)')
    car.lat, car.lon, car.speed = parkLat - 60 / 111195, parkLon, 25
    rframes(10)
    T.check(not rally.over(rallyRun.active()), 'rally end: driven in at speed: not checked in (#67)')
    local ti = rallyRun.transitInfo()
    T.check(ti and ti.stop ~= nil, 'rally end: the HUD line says to stop (#67: ' .. tostring(ti and ti.stop) .. ')')
    T.check(countObjects() > 0, 'rally end: the board and tent put down as the car came near (#68)')
    car.speed = 0
    rframes(5)
    T.check(rally.over(rallyRun.active()) and rallyRun.uiCard().done and #rallyRun.finishedList('test19f') == 1,
      'rally end: stopped at the final service, the rally finished and kept (#71)')
    T.check(rallyRun.endRally() and rallyRun.active() == nil,
      'rally end: New rally / Continue driving: the rally closed (#71)')
    car.lat = parkLat + (runner.LEFT_DROP_M + 100) / 111195
    rframes(10)
    T.check(props.site('service') == nil, 'rally end: driven away, the board and tent taken away (#68)')
    core_input_actionFilter = nil
    rallyRun.abandon('test19f')
    teleports, moved = 0, false
  end

  -- 3d2. (1.7.2) Stop while a full rally gets its stages ready stops them all, through the real prep: the owner
  -- pressed Stop once a stage before, as the next started a frame later. The prep ends at once with the ending
  -- those presses reached -- the stages with no line held out, the rally going on -- and says so; with no stage
  -- left to drive the rally ends, and the message says that instead.
  do
    local rallyRun = require('earthRally/rallyRun')
    local main = require('earthRally/main')
    local parkLat, parkLon = atcLat - 8000 / 111195, full[11][2]
    local base
    for _, st in ipairs(ev.stages) do if st.id == 'hill' then base = st end end
    local stages = {}
    for _, id in ipairs({ 'hill', 'hillB', 'hillC' }) do
      local c = {}
      for k2, v in pairs(base) do c[k2] = v end
      c.id, c.name = id, 'Hill ' .. id
      stages[#stages + 1] = c
    end
    local function evFor(id)
      files['/earthRally/events/' .. id .. '.json'] = { format = 1, id = id, name = 'Test ' .. id, stages = stages,
        itinerary = { { ss = 'SS1', stage = 'hill', run = 1, day = 1, km = 3 },
          { ss = 'SS2', stage = 'hillB', run = 1, day = 1, km = 3 }, { ss = 'SS3', stage = 'hillC', run = 1, day = 1, km = 3 } },
        rallyStops = {}, rallyStart = { name = 'Park', lat = parkLat, lon = parkLon } }
    end
    evFor('test72a')
    evFor('test72b')
    files['/earthRally/matched/test72b__hill.json'] = { format = 1, points = recFrom }
    events.list(true)
    rallyRun.ui.openCard = function() end
    core_input_actionFilter = { setGroup = function() end, addAction = function() end }
    car.lat, car.lon, car.speed = parkLat, parkLon, 0

    -- one stage has its line: the other two held out, the rally goes on
    local okB, whyB = rallyRun.start('test72b', { mode = 'casual', class = 'L4WD' })
    T.check(okB, 'stop all: a rally with two stages to recce started (' .. tostring(whyB) .. ')')
    local pr = rallyRun.preparing()
    T.check(pr and #pr.list == 2, 'stop all: two stages to get ready (' .. tostring(pr and #pr.list) .. ')')
    T.check(main.uiState().auto == nil or main.uiState().auto.prepLeft == 2, 'stop all: two left')
    local r = main.uiAction('autoRecceStop')
    T.check(r.ok and not r.rallyEnded and r.message:find('2 stages with no line held out', 1, true),
      'stop all: one press stops both, and says they are held out (' .. tostring(r.message) .. ')')
    local act = rallyRun.active()
    T.check(rallyRun.preparing() == nil and act ~= nil and #(act.heldOut or {}) == 2,
      'stop all: the prep is over, the rally goes on with both held out (' .. tostring(act and #(act.heldOut or {})) .. ')')
    frames(5)
    T.check(main.uiState().auto == nil, 'stop all: and no auto recce starts on the next frames')
    T.check(not main.uiAction('autoRecceStop').ok, 'stop all: a second Stop finds nothing to stop')
    rallyRun.quit()

    -- no stage has its line: nothing left to drive, the rally ends -- and the message says so
    T.check(rallyRun.start('test72a', { mode = 'casual', class = 'L4WD' }), 'stop all: a rally with every stage to recce started')
    r = main.uiAction('autoRecceStop')
    T.check(r.ok and r.rallyEnded and r.message:find('rally ended', 1, true),
      'stop all: with no line anywhere, Stop says the rally ended (' .. tostring(r.message) .. ')')
    T.check(rallyRun.active() == nil and rallyRun.preparing() == nil, 'stop all: and it has')
    core_input_actionFilter = nil
    rallyRun.abandon('test72a')
    rallyRun.abandon('test72b')
    teleports, moved = 0, false
  end

  -- 3e. (#70) the direction point before an ATC: on the road into it, walked back along the road map; none where the
  -- road into it turns sharply (the old straight line landed on the next road there and sent the car round a block)
  do
    local rallyRun = require('earthRally/rallyRun')
    local props = require('earthRally/props')
    local ax, ay = 1000, 2000
    local aLat, aLon = toGeo(ax, ay)
    local sLat, sLon = toGeo(ax, ay + 100)         -- (the start 100 m north: the stage runs north)
    local stg = { controls = { start = { lat = sLat, lon = sLon } } }
    local function road(pts)
      local nodes = {}
      for k, p in ipairs(pts) do
        nodes['r' .. k] = { pos = { x = p[1], y = p[2], z = 0 }, radius = 3, links = {} }
        if k > 1 then nodes['r' .. k].links['r' .. (k - 1)] = {} nodes['r' .. (k - 1)].links['r' .. k] = {} end
      end
      return nodes
    end
    -- a straight road north through the ATC
    local straight = {}
    for k = -10, 10 do straight[#straight + 1] = { ax, ay + k * 20 } end
    local nodes = road(straight)
    map = { getMap = function() return { nodes = nodes } end }
    props.mapChanged()
    local via = rallyRun.approachVia(stg, aLat, aLon, 'ATC')
    local vx, vy = 0, 0
    if via then vx, vy = toGame(via.lat, via.lon) end
    T.check(via and math.abs(vx - ax) < 0.5 and math.abs(vy - (ay - 60)) < 0.5,
      'approach point: 60 m before the ATC on its own road (#70)')
    -- the road into the ATC turns in from the east 20 m before it: no point rather than one on another road
    nodes = road({ { ax + 200, ay - 20 }, { ax + 100, ay - 20 }, { ax, ay - 20 }, { ax, ay }, { ax, ay + 100 } })
    props.mapChanged()
    T.check(rallyRun.approachVia(stg, aLat, aLon, 'ATC') == nil, 'approach point: a sharp turn just before it: none (#70)')
    map = nil
    props.mapChanged()
    T.check(rallyRun.approachVia(stg, aLat, aLon, 'ATC') == nil, 'approach point: no road map yet: none, looked for later')
  end

  -- 3f. (the owner, rev 4) Realistic, a rally with no stop at all: a recovery rejoins at the next stage's start
  do
    local rally = require('earthRally/rally')
    local rallyRun = require('earthRally/rallyRun')
    local parkLat, parkLon = atcLat - 8000 / 111195, full[11][2]
    files['/earthRally/events/test19n.json'] = { format = 1, id = 'test19n', name = 'Test Rally 19N', stages = ev.stages,
      itinerary = { { ss = 'SS1', stage = 'hill', run = 1, day = 1, km = 3 }, { ss = 'SS2', stage = 'hill', run = 2, day = 1, km = 3 },
        { ss = 'SS3', stage = 'hill', run = 3, day = 1, km = 3 } }, rallyStops = {},
      rallyStart = { name = 'Square', lat = parkLat, lon = parkLon } }
    files['/earthRally/matched/test19n__hill.json'] = { format = 1, points = recFrom }
    events.list(true)
    rallyRun.ui.openCard = function() end
    core_input_actionFilter = { setGroup = function() end, addAction = function() end }
    local function rframes(n) for _ = 1, n do rallyRun.update(0.1) frames(1) end end
    car.lat, car.lon, car.speed = parkLat, parkLon, 0
    T.check(rallyRun.start('test19n', { mode = 'realistic', class = 'L4WD' }), 'no stop: started')
    rframes(60)
    local labels = {}
    for _, row in ipairs(rallyRun.uiCard().rows) do labels[#labels + 1] = row.label end
    T.check(table.concat(labels, ' ') == 'Start SS1 SS2 SS3', 'no stop: no final service (#71: ' .. table.concat(labels, ' ') .. ')')
    T.check(rallyRun.goNext() and runner.approaching(), 'no stop: on the transit to SS1')
    -- the transit: Recover takes the car to SS1's time control, nothing missed
    T.check(rallyRun.recoverKey(), 'no stop: the recovery key on the transit')
    local q = rallyRun.askInfo()
    T.check(q and q.ask and q.ask.transit and q.ask.toStop and q.ask.stop == 'the start of SS1 Hill',
      'no stop: transit Recover? says it takes you to the start of SS1 (' .. tostring(q and q.ask and q.ask.stop) .. ')')
    T.check(rallyRun.answer('recover') and geo_m(car.lat, car.lon, atcLat, atcLon) < 1,
      'no stop: recovered on the transit, the car at SS1\'s time control')
    rframes(60)
    local R = rallyRun.active()
    T.check(rally.current(R).ss == 'SS1' and next(R.results) == nil and runner.approaching(),
      'no stop: nothing missed, the transit to SS1 armed again')
    -- the car there stopped: asked to load; loaded
    T.check(rallyRun.askInfo() and rallyRun.askInfo().loadAsk and rallyRun.answerLoad('load'), 'no stop: SS1 loaded')
    rframes(30)
    local cur = runner.current()
    -- (a run that failed to start: put away and the transit armed again, free -- no Recover? question)
    cur.state = 'failed'
    T.check(rallyRun.recoverKey() and runner.current() == nil and rallyRun.askInfo() == nil and runner.approaching(),
      'a failed stage: the recovery key puts it away, re-arms the transit, asks nothing')
    car.lat, car.speed = atcLat - 90 / 111195, 0 rframes(3)
    car.lat = atcLat rframes(3)
    T.check(rallyRun.askInfo() and rallyRun.answerLoad('load'), 'no stop: SS1 loaded again')
    rframes(30)
    cur = runner.current()
    cur.state = 'running'
    T.check(rallyRun.recoverKey() and cur.rally.ask and cur.rally.ask.stop == 'the start of SS2 Hill',
      'no stop: Recover? on SS1 says the start of SS2 (' .. tostring(cur.rally.ask and cur.rally.ask.stop) .. ')')
    T.check(rallyRun.answer('recover') and runner.current() == nil, 'no stop: SS1 given up')
    T.check(R.results.SS1 and R.results.SS1.superRally and R.results.SS2 == nil and rally.current(R).ss == 'SS2',
      'no stop: SS1 under Super Rally only, on at SS2')
    T.check(geo_m(car.lat, car.lon, atcLat, atcLon) < 1, 'no stop: the car taken to SS2\'s time control')
    rframes(60)
    T.check(runner.approaching() ~= nil, 'no stop: the transit to SS2 armed there')
    -- SS2 done, the last stage given up: the rally ends
    rallyRun.onFinished({ timeS = 200, stageS = 200, penaltyS = 0 })
    car.lat, car.speed = atcLat - 90 / 111195, 0 rframes(3)
    car.lat = atcLat rframes(3)
    T.check(rallyRun.askInfo() and rallyRun.answerLoad('load'), 'no stop: SS3 loaded')
    rframes(30)
    cur = runner.current()
    cur.state = 'running'
    T.check(rallyRun.recoverKey() and cur.rally.ask and cur.rally.ask.stop == nil and cur.rally.ask.last,
      'no stop: Recover? on the last stage says the rally ends (ask.last)')
    T.check(rallyRun.answer('recover') and R.done and R.unclassified, 'no stop: the last stage given up ends the rally')
    rallyRun.endRally()
    rallyRun.abandon('test19n')
    core_input_actionFilter = nil
    teleports, moved = 0, false
  end

  -- 3g. (#63) the origin move waits on BeamNG.Earth's own request: done on any commit after ours, wherever it landed
  -- (its stale resync re-asked at the old anchor), and not given up while a request is still pending
  do
    local est = { anchorId = 1 }
    local anchorWas = anchor
    local realRebase = beamngEarth_core.rebaseTo
    beamngEarth_core._state = function() return est end
    beamngEarth_core.rebaseTo = function(lat, lon) est.pending = { purpose = 'resync', lat = lat, lon = lon } return true end
    runner.abort(true)
    anchor = { lat = 47.0, lon = -123.0 }
    car.lat, car.lon, car.speed = full[1][1], full[1][2], 0
    T.check(runner.start(event, event.stages[1]), 'origin wait: started')
    for _ = 1, 50 do if runner.state() == 'anchor' then break end frames(1) end
    T.check(runner.state() == 'anchor' and est.pending ~= nil, 'origin wait: asked')
    est.pending = { purpose = 'resync', lat = 47.0, lon = -123.0 }       -- (re-asked at the old anchor)
    frames(5)
    T.check(runner.state() == 'anchor', 'origin wait: still pending, waiting')
    est.pending, est.anchorId = nil, 2                                   -- (committed there)
    frames(2)
    local r = runner.current()
    T.check(runner.state() ~= 'anchor' and tostring(r.checks.originMoved):find('^landed') ~= nil,
      'origin wait: committed elsewhere: done, not left to time out (' .. tostring(r.checks.originMoved) .. ')')
    runner.abort(true)
    -- a request that stays pending: waited for past ANCHOR_WAIT_S, given up at ANCHOR_PENDING_MAX_S
    car.lat, car.lon = full[1][1], full[1][2]
    T.check(runner.start(event, event.stages[1]), 'origin wait 2: started')
    for _ = 1, 50 do if runner.state() == 'anchor' then break end frames(1) end
    frames(runner.ANCHOR_WAIT_S + 5, 1)
    T.check(runner.state() == 'anchor', 'origin wait 2: still pending past ANCHOR_WAIT_S: still waiting')
    frames(runner.ANCHOR_PENDING_MAX_S, 1)
    r = runner.current()
    T.check(runner.state() ~= 'anchor' and r.checks.originMoved == 'timed out', 'origin wait 2: given up at last')
    runner.abort(true)
    beamngEarth_core._state, beamngEarth_core.rebaseTo = nil, realRebase
    anchor = anchorWas
  end

  -- 4. a stage with no ATC, the car standing still on the start line when it loads: not counted down until driven
  local lx, ly = toGame(full[11][1], full[11][2])
  car.lat, car.lon = toGeo(lx, ly - 6)
  car.speed = 0
  gpsDest = { lat = full[11][1], lon = full[11][2] }
  T.check(runner.armApproach(event, event.stages[1]), 'no ATC: armed to the start')
  frames(60)
  local held = { car.lat, car.lon }
  T.check(runner.state() == 'toStart' and runner.current().checks.startSetDown == 'driven there'
    and runner.current().startAt == nil and teleports == 0,
    'no ATC, stopped on the line as it loads: kept there, no countdown (' ..
    tostring(runner.current() and runner.current().checks.startSetDown) .. ')')
  car.lat, car.lon = toGeo(lx, ly - 10)       -- (backed up 4 m, then stopped: the player's own stop)
  car.speed = 2 frames(1) car.speed = 0 frames(3)
  T.check(runner.current().startAt ~= nil and held[1] ~= car.lat, 'no ATC: driven and stopped again, counted down')
  runner.abort(true)
  -- rolling in over the start zone: no countdown while it moves
  car.lat, car.lon = toGeo(lx, ly - 400)
  gpsDest = { lat = full[11][1], lon = full[11][2] }
  runner.armApproach(event, event.stages[1])
  drive(8, function() return runner.state() == 'toStart' and geo_m(car.lat, car.lon, full[11][1], full[11][2]) < 8 end)
  T.check(runner.state() == 'toStart' and runner.current().startAt == nil and not moved,
    'no ATC, rolling in: no countdown while the car moves')
  runner.abort(true)

  -- 5. another stage's run under way: waited for; once it is finished, put away for the routed one
  car.lat, car.lon, car.speed = full[1][1], full[1][2], 0
  runner.start(event, event.stages[1])
  frames(40)
  T.check(runner.current().event.id == 'test', 'a stage loaded by Run stage')
  gpsDest = { lat = atcLat, lon = atcLon }
  runner.armApproach(ev, st)
  car.lat, car.lon = atcLat - 300 / 111195, full[11][2]
  frames(10)
  T.check(runner.current().event.id == 'test' and runner.approaching() ~= nil,
    'another run under way: the routed stage waits')
  runner.wrapUp()
  frames(10)
  T.check(runner.current().event.id == 'test19' and runner.current().drivenIn ~= nil,
    'that run finished: put away, the routed stage loaded (' .. runner.current().event.id .. ')')
  -- and Stop the run disarms a route still armed
  runner.armApproach(ev, st)
  runner.abort(true)
  T.check(runner.approaching() == nil, 'Stop the run: the route disarmed')

  -- 6. a Run stage that fails (here: a stage with no line) still disarms the route armed for another stage
  car.lat, car.lon, car.speed = atcLat - 3000 / 111195, full[11][2], 0
  route(atcLat, atcLon)
  local okNo = runner.start(ev, { id = 'noline', name = 'No line', lengthM = 1000, line = st.line })
  T.check(not okNo and runner.approaching() == nil, 'a refused Run stage: the route armed for another stage disarmed')

  -- 7. loaded as the car drove up, then the GPS sent somewhere else while still far: the run's own arrows lead
  car.lat, car.lon, car.speed = atcLat - 1200 / 111195, full[11][2], 0
  route(atcLat, atcLon)
  drive(30, function() return runner.state() == 'toAtc' end)
  local r0 = #routes
  frames(15)
  T.check(runner.state() == 'toAtc' and #routes == r0 and toAtcM() > 400, 'GPS ours and far: it leads')
  gpsDest = { lat = atcLat + 0.05, lon = atcLon, name = 'elsewhere' }
  frames(15)
  T.check(#routes > r0 and toAtcM() > 400, "GPS sent elsewhere: the run's arrows from then on, however far")
  runner.abort(true)

  -- 8. no ATC, the car coming along the stage road from beyond the start: set down behind the line
  local beyond = full[311]
  car.lat, car.lon, car.speed = beyond[1], beyond[2], 0
  gpsDest = { lat = full[11][1], lon = full[11][2] }
  T.check(runner.armApproach(event, event.stages[1]), 'no ATC, from beyond the start: armed')
  frames(60)
  T.check(runner.state() == 'toStart' and runner.current().checks.startSetDown ~= 'driven there'
    and geo_m(car.lat, car.lon, full[11][1], full[11][2]) < 60 and teleports == 0,
    string.format('no ATC, from beyond the start: set down behind the line (%s, %.0f m from it)',
      tostring(runner.current() and runner.current().checks.startSetDown),
      geo_m(car.lat, car.lon, full[11][1], full[11][2])))
  runner.abort(true)

  beamngEarth_api.gps, beamngEarth_api.gpsClear, beamngEarth_api.teleport = hadGps, hadClear, hadTp
end


------------------------------------------------------------------------------------------ 1.7.0: a pass of a full rally
-- runner.start(..., { rally = true }): the time to runner.onFinished and not to the stage's results; no reset penalty
-- (the rally's recovery is the rally's); the results card waits for an answer; the next stage left to the rally;
-- keepDamage: BeamNG.Earth's teleport sets the car down with resetVehicle = false while it is on.
do
  settings.reset()
  local finished, rallyResets = {}, 0
  runner.onFinished = function(res) finished[#finished + 1] = res end
  runner.onRallyReset = function() rallyResets = rallyResets + 1 end
  local calls = {}
  local oldSpawn = spawn
  spawn = { safeTeleport = function(v, pos, rot, _, _, _, _, resetVeh)
    calls[#calls + 1] = { reset = resetVeh }
    if v.setPositionRotation then v:setPositionRotation(pos.x, pos.y, pos.z) end
  end }
  local plain = spawn.safeTeleport
  runner.keepDamage(true)
  T.check(spawn.safeTeleport ~= plain, 'keepDamage: the game\'s safeTeleport wrapped')
  spawn.safeTeleport(getPlayerVehicle(0), vec3(0, 0, 0), nil, nil, nil, false, nil, true)
  T.check(calls[1] and calls[1].reset == false, 'keepDamage: BeamNG.Earth\'s set-down of the car keeps its damage')
  spawn.safeTeleport({}, vec3(0, 0, 0), nil, nil, nil, false, nil, true)
  T.check(calls[2] and calls[2].reset == true, 'keepDamage: another car is reset as asked')
  runner.keepDamage(false)
  T.check(spawn.safeTeleport == plain and not runner.keepingDamage(), 'keepDamage off: the game\'s own function back')

  local nRuns = #(events.results('test', 'hill').runs or {})
  anchor = { lat = 47.0, lon = -123.0 }
  car.lat, car.lon, car.speed = full[1][1] - 0.02, full[1][2], 0
  local okR, whyR = runner.start(event, event.stages[1], { rally = true, ssLabel = 'SS4', keepDamage = true })
  T.check(okR, 'a rally pass starts (' .. tostring(whyR) .. ')')
  local rr = runner.current()
  T.check(rr.inRally and rr.ssLabel == 'SS4' and rr.nextStage == nil, 'in a rally: its SS label, no next stage')
  frames(80)
  T.check(runner.keepingDamage(), 'keepDamage kept on through a rally pass (BeamNG.Earth fall guard)')
  car.lat, car.lon, car.speed = full[9][1], full[9][2], 0
  frames(20)
  go(rr)
  T.check(runner.state() == 'running', 'running (rally pass)')
  T.check(runner.onReset(1) == false and (rr.resets or 0) == 0 and rallyResets == 1,
    'a reset in a rally: no penalty, handed to the rally')
  rr.resetAt = -100
  T.check(runner.onReset(nil) == false and rallyResets == 2, 'a reset with no vehicle id (the radial menu): the rally too')
  local oldBest = events.best
  events.best = function() return nil end      -- (a stage never driven before: no best to show)
  driveTo(11, #full)
  events.best = oldBest
  T.check(runner.state() == 'finished' and #finished == 1 and math.abs(finished[1].timeS - rr.finalTime) < 1e-9,
    'the finish handed to the rally (' .. runner.state() .. ')')
  T.check(#(events.results('test', 'hill').runs or {}) == nRuns, 'a rally time is not a single-stage run')
  local passes = events.results('test', 'hill').rallyPasses or {}
  T.check(#passes == 1 and #passes[1].splits == 3 and passes[1].splits[1] < passes[1].splits[3],
    'a rally pass kept apart, with its three splits (the rally loop)')
  T.check(finished[1].startT == nil and finished[1].finishT == nil, 'an untimed rally: no rally-clock times')
  frames(50)
  local _, oursR = runner.uiFrame()
  T.check(oursR.show.results and oursR.results.next == nil, 'the results card up, no Next stage of its own')
  rr.rally = { mode = 'realistic', ask = { ss = 'SS4' } }
  rr.rallyKey = 'ask'
  _, oursR = runner.uiFrame()
  T.check(oursR.show.recoverAsk and oursR.rally.ask.ss == 'SS4', 'the Recover? question in the stream')
  for _ = 1, 20 do frames(10, 10) end
  T.check(rr.resultsOpen, 'the rally\'s card waits for an answer (no timeout)')
  runner.abort(true)
  T.check(not runner.keepingDamage(), 'keepDamage off once the rally pass ends')
  runner.onFinished, runner.onRallyReset = nil, nil
  spawn = oldSpawn
  settings.reset()
end

------------------------------------------------------------------------------------------ the rally loop: splits
-- Three splits at a quarter, half and three quarters of the timed span, crossed on run.along, against the best run's
-- splits on the stage (a single run or a rally's pass); the card for 5 s; the finish card's list.
do
  local hud = require('earthRally/hudFrame')
  files['/earthRally/results/sp__x.json'] = nil
  T.check(events.bestSplits('sp', 'x') == nil, 'no run with splits: nothing to compare')
  local fr = { event = { id = 'sp' }, stage = { id = 'x' }, state = 'running', startM = 100, finishM = 1100,
    along = 300, clock = 30 }
  runner._splitsTick(fr)
  T.check(fr.splits and #fr.splits == 0 and fr.splitBest == false, 'before a quarter: no split')
  fr.along, fr.clock = 360, 40
  runner._splitsTick(fr)
  T.check(#fr.splits == 1 and fr.splits[1] == 40 and fr.splitShow.n == 1 and fr.splitShow.gapS == nil,
    'split 1 at a quarter: 40 s, no gap on a first run')
  local c = hud.splitCard(fr)
  T.check(c and c.n == 1 and c.timeS == 40, 'the split card up')
  fr.clock = 46
  T.check(hud.splitCard(fr) == nil, 'and gone 5 s on')
  fr.along, fr.clock = 1000, 90
  runner._splitsTick(fr)
  T.check(#fr.splits == 3 and fr.splits[2] == 90 and fr.splits[3] == 90 and fr.splitShow.n == 3,
    'two splits passed in one look: both kept')
  fr.finalTime = 120
  local rows = hud.splitRows(fr)
  T.check(#rows == 4 and rows[4].n == 4 and rows[4].timeS == 120 and rows[4].gapS == nil, 'the finish card: 3 splits and the finish')
  -- a rally's pass kept apart (not a single-stage run), and the best of both compared with
  events.addResult('sp', 'x', { finished = true, timeS = 130, splits = { 41, 85, 100 } })
  events.addRallyPass('sp', 'x', { timeS = 125, splits = { 39, 80, 99 } })
  events.addResult('sp', 'x', { finished = true, timeS = 110 })      -- (faster, but saved before splits)
  T.check(#events.results('sp', 'x').runs == 2 and events.best('sp', 'x') == 110, 'a rally\'s pass is not a run')
  local b = events.bestSplits('sp', 'x')
  T.check(b and b.timeS == 125 and b.splits[1] == 39, 'the best run with splits, a rally\'s pass too')
  local fr2 = { event = { id = 'sp' }, stage = { id = 'x' }, state = 'running', startM = 0, finishM = 1000,
    along = 260, clock = 37.5 }
  runner._splitsTick(fr2)
  T.check(math.abs(fr2.splitShow.gapS - (-1.5)) < 1e-9, 'ahead of the best: a negative gap')
  fr2.finalTime = 127
  rows = hud.splitRows(fr2)
  T.check(#rows == 2 and math.abs(rows[2].gapS - 2) < 1e-9, 'the finish gap against that run\'s time')
  local _, ours = hud.build(fr2, { now = 0 })
  T.check(ours.split and ours.split.n == 1 and ours.show.split and ours.splitsAt[2] == 0.5,
    'the stream: ours.split and the progress bar\'s ticks')
end

------------------------------------------------------------------------------------------ the rally loop: world time
-- earthAdapter.setWorldTime: BeamNG.Earth's api.setWorldTime when it has it; else its real sky's server-clock hook
-- (never the manual mode, which it would save); else the game's TimeOfDay, put back after.
do
  local api = beamngEarth_api
  local had = { has = api.has, set = api.setWorldTime }
  local calls = {}
  api.has = function(n) return n == 'worldTime' or had.has(n) end
  api.setWorldTime = function(e) calls[#calls + 1] = e or 'nil' return true end
  T.check(earth.hasWorldTime() and earth.setWorldTime(1000) == 'api' and calls[1] == 1000, 'the API: the moment passed')
  T.check(earth.setWorldTime(nil) == 'api' and calls[2] == 'nil', 'and given back')
  api.has, api.setWorldTime = had.has, had.set
  T.check(not earth.hasWorldTime(), 'an older BeamNG.Earth: no world time')
  local clockSet, saved = {}, false
  beamngEarth_sky = { getMode = function() return 'real' end, serverClock = function() return clockSet[#clockSet] end,
    setServerClock = function(c) clockSet[#clockSet + 1] = c or false end }
  local how = earth.setWorldTime(6 * 3600 + 18 * 3600, -6 * 3600)
  T.check(how == 'serverClock' and clockSet[1].hours == 18 and clockSet[1].speed == 1,
    'the real sky: its server clock at 18:00 local, its mode untouched')
  T.check(earth.setWorldTime(nil) == 'serverClock' and clockSet[2] == false, 'and the real clock back')
  clockSet = { { hours = 3 } }
  T.check(earth.setWorldTime(100, 0) == false, 'a server clock not ours (BeamMP): left alone')
  local env = core_environment
  local tod = { time = 0.25, play = true }
  core_environment = { getTimeOfDay = function() return { time = tod.time, play = tod.play } end,
    setTimeOfDay = function(t) tod = t end }
  beamngEarth_sky.getMode = function() return 'manual' end
  T.check(earth.setWorldTime(12 * 3600, 0) == 'tod' and math.abs(tod.time) < 1e-9, 'the manual sky: noon set')
  T.check(earth.setWorldTime(nil) == 'tod' and tod.time == 0.25, 'and the time it had put back')
  beamngEarth_sky, core_environment = nil, env
end

------------------------------------------------------------------------------------------ the rally loop: the clock
-- A timed rally's clock in rallyRun: the runner's clock is it, the wait at a time control for the due minute (and its
-- skip), the check-in early or late, the time card's rows and the transit's due time.
do
  local rallyRun = require('earthRally/rallyRun')
  local rally = require('earthRally/rally')
  local wt = require('earthRally/worldTime')
  local settings = require('earthRally/settings')
  local t0 = wt.parse('2031-02-07', '08:00')
  local r = { format = 3, eventId = 'test', name = 'Test Rally', mode = 'casual', class = 'L4WD', timed = true,
    tz = 'America/Chicago', clock = { t = t0 }, road = {}, lateSPerMin = 10, earlySPerMin = 60, results = {},
    serviced = { ['1'] = true }, pos = 2, missed = 0, heldOut = {},
    order = { { kind = 'start', label = 'Start', outT = t0, place = { name = 'Park', lat = 45, lon = -90 } },
      { kind = 'stage', ss = 'SS1', stageId = 'hill', outT = t0, outTargetMin = 20, latenessMin = 10 },
      { kind = 'stage', ss = 'SS2', stageId = 'hill', targetMin = 15, latenessMin = 10 } } }
  rallyRun._setRally(r)
  T.check(runner.rallyClock.now() == t0, 'the runner reads the rally clock')
  rallyRun.clockPaused = function() return false end
  rallyRun.update(1, 60)
  T.check(r.clock.t == t0 + 60, 'it runs with game time')
  rallyRun.clockPaused = function() return true end
  rallyRun.update(1, 60)
  T.check(r.clock.t == t0 + 60, 'and stops under a loading screen or the menu')
  rallyRun.clockPaused = function() return false end
  T.check(rallyRun._dueAt(2) == t0 + 20 * 60 and rallyRun._dueAt(3) == nil,
    'due at SS1\'s control from the start; SS2\'s not known until SS1 is done')
  -- early at the board (08:01, due 08:20), the setting off: the wait, Continue held, the skip
  settings.set('earlyPenalty', false)
  local up = nil
  rallyRun.ui.atControl = function(tc) up = tc end
  rallyRun.atControl(r.order[2], { name = 'Hill', lengthM = 3000 })
  T.check(up and up.due == '08:20' and up.wait and up.wait.leftS == 19 * 60 and up.result == nil,
    'early: the card waits for 08:20 (' .. tostring(up and up.wait and up.wait.leftS) .. ' s)')
  rallyRun.clockPaused = function() return true end
  rallyRun.update(30, 0)
  T.check(r.clock.t == t0 + 90 and up.wait.leftS == 19 * 60 - 30, 'the wait runs on real time under the card')
  T.check(rallyRun.continueOk() == false and rallyRun.waiting(), 'Continue does not check in early with the setting off')
  T.check(rallyRun.skipWait() and r.clock.t == t0 + 20 * 60 and up.result.kind == 'onTime' and up.wait == nil,
    'the skip: the clock to 08:20, on time')
  T.check(rallyRun.skipWait() == false, 'a second skip is a no-op')
  -- the setting on: Continue checks in early, 1 min a minute
  settings.set('earlyPenalty', true)
  r.clock.t = t0 + 17 * 60
  rallyRun.atControl(r.order[2], { name = 'Hill', lengthM = 3000 })
  T.check(up.wait and rallyRun.continueOk() == true and up.result.kind == 'early' and up.result.penaltyS == 180,
    'the setting on: Continue checks in 3 min early, +180 s')
  -- late: checked in at once
  r.clock.t = t0 + 22 * 60 + 5
  rallyRun.atControl(r.order[2], { name = 'Hill', lengthM = 3000 })
  T.check(up.wait == nil and up.result.kind == 'late' and up.result.min == 2 and up.result.penaltyS == 20
    and r.road.SS1.penaltyS == 20, 'late by 2 min: +20 s at once')
  settings.set('earlyPenalty', false)
  -- the time card: its clock, the rows' due and in times, the total
  local cardOk, card = pcall(rallyRun.uiCard)
  T.check(cardOk and card and card.clock and card.clock.date == 'Fri 7 Feb' and card.clock.time == '08:22'
    and card.roadPenaltyS == 20 and card.lateSPerMin == 10, 'the time card: the rally clock and the road total')
  local row = cardOk and card.rows[2]
  T.check(row and row.due == '08:20' and row.timeIn == '08:22' and row.roadPenaltyS == 20 and card.rows[1].outAt == '08:00',
    'the time card: SS1 due 08:20, in 08:22, +20 s; the start out at 08:00')
  -- the start screen's line
  local sa = rallyRun.startsAt(r)
  T.check(sa and sa.text == 'Fri 7 Feb 2031, 08:22 local' and sa.light == 'day', 'the start screen\'s start and light')
  -- the transit: due time at SS2's control from SS1's time out
  r.lastOut, r.pos = t0 + 40 * 60, 3
  local td = rallyRun.transitDue()
  T.check(td and td.due == '08:55' and td.late == 0 and td.leftS == 33 * 60 - 5, 'the transit: due 08:55, time left')
  r.clock.t = t0 + 57 * 60 + 10
  td = rallyRun.transitDue()
  T.check(td.late == 2 and td.penaltyS == 20 and td.leftS < 0, 'late on the transit: 2 min, +20 s so far')
  local hud = require('earthRally/hudFrame')
  local _, ours = hud.build(nil, { rally = true, approach = { name = 'SS2 Hill', distM = 1200, rally = true },
    rallyTransit = td })
  T.check(ours.rally and ours.rally.transit and ours.rally.transit.late == 2 and ours.approach.sub:find('2 min late', 1, true),
    'the HUD stream: ours.rally.transit, and the line says it: ' .. tostring(ours.approach.sub))
  rallyRun._setRally(nil)
  rallyRun.clockPaused = function() return false end
  rallyRun.ui.atControl = nil
  T.check(runner.rallyClock.now() == nil and rallyRun.transitDue() == nil, 'no rally: no clock')
end

T.done('test_run')
