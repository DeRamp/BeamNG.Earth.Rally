-- earthRally/runner: one timed run of a stage, through its controls as in a real rally: arrival time control
-- (ATC), start, flying finish, stop control.
--
--   travel     the car to the ATC (else the start; a BeamNG.Earth teleport when it is far), the world loaded
--   anchor     the world's origin moved to the stage's centre, so no world shift happens during the run for any
--              stage up to ~26 km across (BeamNG.Earth shifts the world 15-16 km from its origin)
--   build      the stage line (the recce) put into game coordinates now, the rally engine's files written and
--              loaded: its co-driver calls the pacenotes
--   place      the car 40 m before the ATC (else on the start line), the controls' boards and tents put down
--   toAtc      drive to the ATC and stop at it (checked in)
--   toStart    drive to the start line and stop on it
--   countdown  5 s; moving before the end is a jump start (+10 s)
--   running    our clock (game time: a pause stops it); progress along the line; the clock stops at the flying finish
--              and the time is kept in earthRally/results
--   toStop     drive on to the stop control and stop at it
--   finished
--
-- Everything is kept as lat / lon and put into game coordinates again whenever the world's origin moves, so the
-- clock and the finish never go wrong; the co-driver's own copy is not moved yet (milestone 5), and the run's
-- checks say whether that happened.
local geo = require('earthRally/geo')
local props = require('earthRally/props')
local earth = require('earthRally/earthAdapter')
local rallyA = require('earthRally/rallyAdapter')
local writer = require('earthRally/stageWriter')
local events = require('earthRally/events')

local M = {}
local logTag = 'earthRally'

M.TRAVEL_IF_FARTHER_M = 300
M.ANCHOR_CLOSE_M = 500         -- the origin already this close to the stage's centre: left where it is
M.ANCHOR_WAIT_S = 25
M.COUNTDOWN_S = 5
M.JUMP_START_M = 1.5
M.JUMP_START_PENALTY_S = 10
M.LINE_BEFORE_START_M = 30     -- of the recce kept before the start line
M.CAR_BEHIND_LINE_M = 4
M.Z_BELOW_POSE_M = 0.5         -- the road under the car's reference point
M.FINISH_OFF_M = 40            -- across the finish this close to the line: finished
M.TIMING_RUN_OUT_M = 300       -- the timing line carried on past the recce's end (a recce may stop short of the finish)
M.CONTROL_ON_LINE_M = 60       -- a start / finish control this close to the line is where it is on the line
M.OFF_ROUTE_M = 60
M.RUNTIME_DIR = '/earthRally/runtime/'
M.MAX_REBASE_M = 16000
M.FACE_AHEAD_M = 25            -- the car faces the stage line this far ahead (a few metres of recce can wobble)
M.TELEPORT_SETTLE_S = 2        -- BeamNG.Earth sets the car down a moment after the world is ready: wait for it
M.ATC_MAX_FROM_START_M = 1500  -- an ATC farther from the start than this is not this stage's (left out)
M.STOP_MAX_FROM_FINISH_M = 3000
M.CAR_BEFORE_ATC_M = 40
M.CONTROL_RADIUS_M = 12        -- stopped this close to a control's board: checked in
M.STOP_CONTROL_RADIUS_M = 25
M.STOPPED_MS = 1.0
M.START_ZONE_BEFORE_M = 12     -- stopped this far before the start line (or less), beside it: on the line
M.START_ZONE_OFF_M = 8

local run = nil

local function say(text, s) earth.notify(text, s or 4) log('I', logTag, text) end
function M.state() return run and run.state or 'idle' end
function M.current() return run end

local function fail(why)
  if not run then return end
  run.state, run.error = 'failed', why
  say('Earth Rally: ' .. why, 8)
end

-- The recce as { {lat, lon, alt}... } cut round the stage: from a little before the start control to the end.
local function stageLatLon(stage, recce)
  local pts = recce.points
  local o = pts[1]
  local function flat(lat, lon)
    return { x = geo.metres(o[1], o[2], o[1], lon) * (lon < o[2] and -1 or 1),
             y = geo.metres(o[1], o[2], lat, o[2]) * (lat < o[1] and -1 or 1) }
  end
  local line = {}
  for i, p in ipairs(pts) do line[i] = flat(p[1], p[2]) end
  local cum = geo.cumulative(line)
  local function along(ctl, default)
    if not ctl then return default end
    local _, _, s, off = geo.locate(line, cum, flat(ctl.lat, ctl.lon))
    if off > 200 then return default end
    return s
  end
  local total = cum[#cum]
  local startS = along(stage.controls and stage.controls.start, 0)
  local finishS = along(stage.controls and stage.controls.ff, total)
  if finishS <= startS + 100 then startS, finishS = 0, total end
  local first = math.max(0, startS - M.LINE_BEFORE_START_M)
  local out = {}
  for i, p in ipairs(pts) do
    if cum[i] >= first then out[#out + 1] = p end
  end
  return out, startS - first, finishS - first
end

-- (the stage line in game coordinates, for the world's origin now)
local function project()
  local pts = {}
  for i, p in ipairs(run.latlon) do
    local x, y, z = earth.toGame(p[1], p[2], (p[3] or 0) - M.Z_BELOW_POSE_M)
    if not x then return false end
    pts[i] = { x = x, y = y, z = z }
  end
  local recceEnd = geo.cumulative(pts)
  recceEnd = recceEnd[#recceEnd]
  pts = geo.extend(pts, M.TIMING_RUN_OUT_M, false)
  run.line, run.cum = pts, geo.cumulative(pts)
  -- the start and the flying finish where their controls are along the line (the finish may lie past the recce's
  -- end, on the run-out), else where the recce put them
  local scale = recceEnd / math.max(1, run.latlonLength)
  run.startM, run.finishM = run.startFlat * scale, run.finishFlat * scale
  local ctl = run.stage.controls or {}
  local function at(c)
    if not c then return nil end
    local x, y = earth.toGame(c.lat, c.lon, 0)
    if not x then return nil end
    local _, _, s, off = geo.locate(pts, run.cum, { x = x, y = y })
    return off <= M.CONTROL_ON_LINE_M and s or nil
  end
  run.startM = at(ctl.start) or run.startM
  local f = at(ctl.ff)
  if f and f > run.startM + 100 then run.finishM = f end
  return true
end

-- The camera reset (as the game's own camera reset key): asked for after the world's origin moves and after the car is
-- moved, when a chase camera's own smoothing still follows the old place. Done the next frame and again a little
-- later, once the car has settled. pending: { seconds from now... }.
local camResets = {}
function M.resetCameraSoon()
  camResets[#camResets + 1] = 0.05
  camResets[#camResets + 1] = 0.6
end
local function camUpdate(dt)
  if #camResets == 0 then return end
  local due = false
  for i = #camResets, 1, -1 do
    camResets[i] = camResets[i] - dt
    if camResets[i] <= 0 then table.remove(camResets, i) due = true end
  end
  if due then
    local cam = rawget(_G, 'core_camera')
    if cam and cam.resetCamera then pcall(cam.resetCamera, 0) end
  end
end
M._camUpdate = camUpdate

-- Put the car at pos facing along dir (game coordinates; dir may climb or fall), as the game's own start positions do
-- (gameplay/race/startPosition.lua: quatFromDir(forward, up), turned half round for the vehicle's frame).
function M.placeCar(veh, pos, dir)
  local l = math.sqrt(dir.x * dir.x + dir.y * dir.y + (dir.z or 0) ^ 2)
  if l < 1e-6 then return false end
  local q = quatFromEuler(0, 0, math.pi) * quatFromDir(vec3(dir.x / l, dir.y / l, (dir.z or 0) / l), vec3(0, 0, 1))
  veh:setPositionRotation(pos.x, pos.y, pos.z, q.x, q.y, q.z, q.w)
  M.resetCameraSoon()
  return true
end

-- The direction from s along a line to FACE_AHEAD_M further on (with the climb).
local function aheadDir(line, cum, s)
  local a = geo.pointAt(line, cum, s)
  local b = geo.pointAt(line, cum, s + M.FACE_AHEAD_M)
  return { x = b.x - a.x, y = b.y - a.y, z = (b.z or 0) - (a.z or 0) }, a
end

-- The run's screen layout (settings/ui_apps/.../earthRallyStage: BeamNG.Earth's own with the game's pacenote cards),
-- and back to the one before when the run ends.
M.STAGE_LAYOUT = 'earthRallyStage'
local function layoutOn()
  local gs = rawget(_G, 'core_gamestate')
  if not (gs and gs.setGameState and gs.getGameState) or run.oldLayout then return end
  local ok, cur = pcall(gs.getGameState)
  run.oldLayout = ok and cur and cur.appLayout or 'beamngEarth'
  if run.oldLayout ~= M.STAGE_LAYOUT then pcall(gs.setGameState, nil, M.STAGE_LAYOUT) end
end
local function layoutOff()
  local gs = rawget(_G, 'core_gamestate')
  if run and run.oldLayout and gs and gs.setGameState then
    pcall(gs.setGameState, nil, run.oldLayout ~= M.STAGE_LAYOUT and run.oldLayout or 'beamngEarth')
  end
  if run then run.oldLayout = nil end
end

local function carPos()
  local veh = getPlayerVehicle and getPlayerVehicle(0)
  if not veh then return nil end
  local p = veh:getPosition()
  return { x = p.x, y = p.y, z = p.z }, veh
end

function M.start(event, stage)
  if run and run.state ~= 'finished' and run.state ~= 'failed' then return false, 'a run is under way' end
  local ok, why = earth.check()
  if not ok then return false, why end
  ok, why = rallyA.check()
  if not ok then return false, why end
  local recce = events.recce(event.id, stage.id)
  if not recce then return false, 'drive the recce of this stage first' end
  if not carPos() then return false, 'get in a car first' end
  M.abort(true)

  local latlon, startFlat, finishFlat = stageLatLon(stage, recce)
  local flatLen = 0
  for i = 2, #latlon do flatLen = flatLen + geo.metres(latlon[i - 1][1], latlon[i - 1][2], latlon[i][1], latlon[i][2]) end
  run = {
    event = event, stage = stage, state = 'travel', t = 0, latlon = latlon, latlonLength = flatLen,
    startFlat = startFlat, finishFlat = finishFlat,
    dir = M.RUNTIME_DIR .. event.id .. '__' .. stage.id, id = 'beamng_earth/earthRally/' .. event.id .. '/' .. stage.id,
    checks = { moveSource = earth.moveSource(), shifts = 0, notesCalledAfterShift = 0, notReadyS = 0,
               maxOffM = 0, notesCalled = 0 },
    oldRebase = earth.rebaseDistance(),
  }
  run.moveHandle = earth.onMoved(function(info) M._moved(info) end)

  -- the time controls round the stage (from the event's map), when they are near enough to be its own
  local ctl = stage.controls or {}
  local st0 = ctl.start or { lat = latlon[1][1], lon = latlon[1][2] }
  if ctl.atc then
    local d = geo.metres(ctl.atc.lat, ctl.atc.lon, st0.lat, st0.lon)
    if d <= M.ATC_MAX_FROM_START_M and d >= 5 then run.atc = ctl.atc end
  end
  local ff0 = ctl.ff or { lat = latlon[#latlon][1], lon = latlon[#latlon][2] }
  if ctl.stop and geo.metres(ctl.stop.lat, ctl.stop.lon, ff0.lat, ff0.lon) <= M.STOP_MAX_FROM_FINISH_M then
    run.stopCtl = ctl.stop
  end

  local s = run.atc and { run.atc.lat, run.atc.lon } or latlon[1]
  local p = earth.pose()
  if p and geo.metres(p.lat, p.lon, s[1], s[2]) > M.TRAVEL_IF_FARTHER_M then
    local tok, twhy = earth.teleport(s[1], s[2], stage.name .. (run.atc and ' ATC' or ' start'))
    if not tok then fail('could not go to the start: ' .. tostring(twhy)) return false, twhy end
    run.teleported = true
  end
  say('Earth Rally: ' .. stage.name .. ': getting ready')
  return true
end

-- The world's origin moved (earthAdapter): our line follows; the co-driver's does not (yet).
function M._moved(info)
  if not run then return end
  if run.state == 'running' or run.state == 'countdown' or run.state == 'toStart' or run.state == 'toAtc' then
    run.checks.shifts = run.checks.shifts + 1
    run.shiftedAtNote = run.checks.notesCalled
    log('W', logTag, string.format('the world shifted during the run (%s, %s): the co-driver keeps its old positions',
      tostring(info.purpose), tostring(info.source)))
  end
  if run.line then project() end
  props.reset()            -- (put down again where they belong, in the new frame)
  run.lastMove = info
end

local function setState(s)
  run.state, run.t = s, 0
  log('I', logTag, 'run: ' .. s)
end

local function stepTravel(dt)
  run.t = run.t + dt
  if run.teleported and run.t < 2 then return end
  if not earth.ready() then
    run.readyFor = 0
    if run.t > 180 then fail('the world did not load at the start') end
    return
  end
  run.readyFor = (run.readyFor or 0) + dt
  if run.teleported and run.readyFor < M.TELEPORT_SETTLE_S then return end
  setState('anchor')
  local c = run.stage.centre
  local la, lo = earth.anchor()
  if not c or (la and geo.metres(la, lo, c.lat, c.lon) <= M.ANCHOR_CLOSE_M) then
    run.checks.originMoved = 'not needed'
    setState('build')
    return
  end
  local ok, why = earth.moveOriginTo(c.lat, c.lon)
  run.anchorAsked = ok
  if not ok then
    run.checks.originMoved = 'refused: ' .. tostring(why)
    log('W', logTag, 'origin not moved to the stage centre: ' .. tostring(why))
    setState('build')
  end
end

local function stepAnchor(dt)
  run.t = run.t + dt
  local c = run.stage.centre
  local la, lo = earth.anchor()
  if la and geo.metres(la, lo, c.lat, c.lon) <= M.ANCHOR_CLOSE_M and not earth.rebasing() and earth.ready() then
    run.checks.originMoved = 'yes'
    M.resetCameraSoon()
    setState('build')
  elseif run.t > M.ANCHOR_WAIT_S then
    run.checks.originMoved = 'timed out'
    log('W', logTag, 'origin never moved to the stage centre: the world may shift during the run')
    setState('build')
  end
end

local function stepBuild()
  if run.oldRebase then earth.setRebaseDistance(M.MAX_REBASE_M) end
  if not project() then fail('could not put the stage into game coordinates') return end
  local okB, built = pcall(writer.build, run.line, { startM = run.startM, finishM = run.finishM, name = run.stage.name,
    quatFn = function(x, y, z) local q = quatFromDir(vec3(x, y, z), vec3(0, 0, 1)) return q.x, q.y, q.z, q.w end })
  if not okB then fail('could not build the stage: ' .. tostring(built)) return end
  writer.write(run.dir, built)
  run.built = built
  local ok, why = rallyA.load(run.id, run.dir)
  run.checks.rallyEngine = ok and 'loaded' or ('failed: ' .. tostring(why))
  run.checks.cornersFound = built.corners
  if not ok then
    log('E', logTag, 'rally engine: ' .. tostring(why) .. ' (the run goes on without a co-driver)')
  else
    local st = rallyA.status()
    run.checks.notesLoaded = st and st.notes or 0
    local worst, lowest = rallyA.heightCheck(built.nodes)
    run.checks.heightKeptM = worst
    run.checks.lowestDrivelineZ = lowest
  end
  setState('place')
end

local function progress(p)
  local n = #run.line
  local lo = (run.seg or 1) - 30
  local hi = (run.seg or 1) + 120
  local i, _, along, off = geo.locate(run.line, run.cum, p, lo, hi)
  if off > M.OFF_ROUTE_M then i, _, along, off = geo.locate(run.line, run.cum, p) end
  run.seg = math.min(i, n - 1)
  return along, off
end

-- (a control's place in game coordinates now)
local function ctlGame(c)
  local x, y = earth.toGame(c.lat, c.lon, 0)
  return x and { x = x, y = y } or nil
end

-- The controls' boards and tents (props.lua), each facing the way the car comes through it.
local function setupProps()
  props.clear()
  local sdir, sp = aheadDir(run.line, run.cum, run.startM)
  local slat, slon = earth.toGeo(sp.x, sp.y, sp.z)
  props.setSite('start', slat, slon, sdir, sp.z)
  local fdir, fp = aheadDir(run.line, run.cum, run.finishM)
  local flat, flon = earth.toGeo(fp.x, fp.y, fp.z)
  props.setSite('ff', flat, flon, fdir, fp.z)
  if run.atc then
    local a = ctlGame(run.atc)
    if a then props.setSite('atc', run.atc.lat, run.atc.lon, { x = sp.x - a.x, y = sp.y - a.y }) end
  end
  if run.stopCtl then
    local b = ctlGame(run.stopCtl)
    if b then props.setSite('stop', run.stopCtl.lat, run.stopCtl.lon, { x = b.x - fp.x, y = b.y - fp.y }) end
  end
end

-- The car on the start line, facing the stage.
local function toStartLine(veh)
  local dir, s = aheadDir(run.line, run.cum, run.startM)
  local l = math.sqrt(dir.x * dir.x + dir.y * dir.y)
  local pos = { x = s.x - dir.x / l * M.CAR_BEHIND_LINE_M, y = s.y - dir.y / l * M.CAR_BEHIND_LINE_M, z = (s.z or 0) + 1.0 }
  M.placeCar(veh, pos, dir)
end

-- The ground near the car (the ATC's spot has no height of its own): a ray down, trees above it left out.
local function groundNear(x, y, z0)
  local ray = rawget(_G, 'castRayStatic')
  if ray then
    for _, t in ipairs({ { 8, 40 }, { 25, 80 } }) do
      local top = z0 + t[1]
      local d = ray(vec3(x, y, top), vec3(0, 0, -1), t[2])
      if d and d < t[2] and math.abs(top - d - z0) <= t[1] + 2 then return top - d end
    end
  end
  return z0
end

local function stepPlace()
  local p, veh = carPos()
  if not veh then fail('no car') return end
  setupProps()
  local a = run.atc and ctlGame(run.atc)
  if a then
    -- 40 m before the ATC, on the way from it to the start (the road the ATC is on, as near as the map tells)
    local _, sp = aheadDir(run.line, run.cum, run.startM)
    local dx, dy = sp.x - a.x, sp.y - a.y
    local l = math.sqrt(dx * dx + dy * dy)
    local pos = { x = a.x - dx / l * M.CAR_BEFORE_ATC_M, y = a.y - dy / l * M.CAR_BEFORE_ATC_M }
    pos.z = groundNear(pos.x, pos.y, p.z) + 1.0
    M.placeCar(veh, pos, { x = dx, y = dy, z = 0 })
    setState('toAtc')
    say('Earth Rally: drive to the time control and stop at its red board', 6)
  else
    toStartLine(veh)
    setState('countdown')
    run.lastShown = nil
  end
  rallyA.resync()
  layoutOn()
end

local function speed()
  local p = earth.pose()
  return p and p.speed or 0
end

local function stepToAtc(dt)
  run.t = run.t + dt
  local p = carPos()
  local a = ctlGame(run.atc)
  if not (p and a) then return end
  props.update(p, earth.toGame)
  local d = math.sqrt((p.x - a.x) ^ 2 + (p.y - a.y) ^ 2)
  run.toControlM = d
  if d <= M.CONTROL_RADIUS_M and speed() < M.STOPPED_MS then
    run.checks.atc = 'checked in'
    setState('toStart')
    say('Checked in. Drive to the start line and stop on it.', 5)
    return
  end
  -- (driven on past it to the start: the ATC missed)
  local along, off = progress(p)
  if along >= run.startM - M.START_ZONE_BEFORE_M and off <= M.START_ZONE_OFF_M then
    run.checks.atc = 'missed'
    setState('toStart')
  end
end

local function stepToStart(dt)
  run.t = run.t + dt
  local p = carPos()
  if not p then return end
  props.update(p, earth.toGame)
  local along, off = progress(p)
  run.toControlM = run.startM - along
  if along > run.startM + 2 and off <= M.START_ZONE_OFF_M then
    if not run.overLine then say('Back up behind the start line.', 3) end
    run.overLine = true
    return
  end
  run.overLine = false
  if along >= run.startM - M.START_ZONE_BEFORE_M and off <= M.START_ZONE_OFF_M and speed() < M.STOPPED_MS then
    setState('countdown')
    run.lastShown = nil
  end
end


local function stepCountdown(dt)
  run.t = run.t + dt
  do local cp = carPos() if cp then props.update(cp, earth.toGame) end end
  -- (the car settles when set down: where it stands after the first second is where it must stay)
  local p = carPos()
  if p and run.t >= 1 and not run.settled then run.settled = p end
  if p and run.settled and not run.jumpStart and geo.dist2d(p, run.settled) > M.JUMP_START_M then
    run.jumpStart = true
    say('Jump start: +' .. M.JUMP_START_PENALTY_S .. ' s', 3)
  end
  local left = math.ceil(M.COUNTDOWN_S - run.t)
  if left ~= run.lastShown and left > 0 then
    run.lastShown = left
    if ui_message then ui_message(tostring(left), 1, 'earthRallyCount') end
  end
  if run.t >= M.COUNTDOWN_S then
    if ui_message then ui_message('GO', 1.5, 'earthRallyCount') end
    run.clock = 0
    setState('running')
  end
end

local function stepRunning(dtSim)
  run.clock = run.clock + dtSim
  if not earth.ready() then run.checks.notReadyS = run.checks.notReadyS + dtSim end
  local st = rallyA.status()
  if st and st.lastCalled and st.lastCalled ~= run.lastNote then
    run.lastNote = st.lastCalled
    run.checks.notesCalled = run.checks.notesCalled + 1
    if run.checks.shifts > 0 then run.checks.notesCalledAfterShift = run.checks.notesCalledAfterShift + 1 end
  end
  if earth.rebasing() then return end
  local p = carPos()
  if not p then return end
  props.update(p, earth.toGame)
  local along, off = progress(p)
  run.along, run.off = along, off
  if off > run.checks.maxOffM then run.checks.maxOffM = off end
  if along >= run.finishM and off <= M.FINISH_OFF_M then
    local time = run.clock + (run.jumpStart and M.JUMP_START_PENALTY_S or 0)
    local checks = run.checks
    local best = events.addResult(run.event.id, run.stage.id, { finished = true, timeS = time,
      jumpStart = run.jumpStart == true, date = os.date('!%Y-%m-%dT%H:%M:%SZ'), checks = checks })
    run.finalTime, run.best = time, best
    log('I', logTag, 'run checks: ' .. dumps(checks))
    local text = string.format('%s: %s%s', run.stage.name, M.formatTime(time), best and best < time and
      ('  (best ' .. M.formatTime(best) .. ')') or '  (best)')
    if run.stopCtl then
      setState('toStop')
      say(text .. '. Drive on to the stop control and stop at it.', 8)
    else
      setState('finished')
      say(text, 8)
      M.release()
    end
  end
end

local function stepToStop(dt)
  run.t = run.t + dt
  local p = carPos()
  local b = ctlGame(run.stopCtl)
  if not (p and b) then return end
  props.update(p, earth.toGame)
  local d = math.sqrt((p.x - b.x) ^ 2 + (p.y - b.y) ^ 2)
  run.toControlM = d
  if d <= M.STOP_CONTROL_RADIUS_M and speed() < M.STOPPED_MS then
    run.checks.stopControl = 'stopped'
    setState('finished')
    say('Stage complete: ' .. M.formatTime(run.finalTime), 6)
    M.release()
  end
end

-- Every frame (main.lua).
function M.update(dtReal, dtSim)
  camUpdate(dtReal or 0)
  if not run then return end
  local s = run.state
  if s == 'travel' then stepTravel(dtReal)
  elseif s == 'anchor' then stepAnchor(dtReal)
  elseif s == 'build' then stepBuild()
  elseif s == 'place' then stepPlace()
  elseif s == 'toAtc' then stepToAtc(dtReal)
  elseif s == 'toStart' then stepToStart(dtReal)
  elseif s == 'countdown' then stepCountdown(dtSim)
  elseif s == 'running' then stepRunning(dtSim)
  elseif s == 'toStop' then stepToStop(dtReal) end
end

-- BeamNG.Earth's rebase distance back, the co-driver kept until the next run (its notes stay readable).
function M.release()
  if not run then return end
  if run.oldRebase then earth.setRebaseDistance(run.oldRebase) run.oldRebase = nil end
  if run.moveHandle then earth.offMoved(run.moveHandle) run.moveHandle = nil end
end

function M.abort(quiet)
  if not run then return end
  M.release()
  layoutOff()
  props.clear()
  rallyA.unload()
  if not quiet and run.state ~= 'finished' then say('Earth Rally: run stopped') end
  run = nil
end

-- After a 'Go to start' teleport (BeamNG.Earth keeps the car's heading): the car turned to face along the stage, where
-- it stands. true once done.
function M.faceStage(stage)
  local p, veh = carPos()
  if not (p and veh and stage.line and #stage.line >= 2) then return false end
  local s = stage.controls and stage.controls.start
  local o = s and { s.lat, s.lon } or stage.line[1]
  -- the map line's point FACE_AHEAD_M+ on from the start
  local ahead = stage.line[#stage.line]
  for i = 2, #stage.line do
    local q = stage.line[i]
    if geo.metres(o[1], o[2], q[1], q[2]) >= M.FACE_AHEAD_M then ahead = q break end
  end
  local ax, ay = earth.toGame(o[1], o[2], 0)
  local bx, by = earth.toGame(ahead[1], ahead[2], 0)
  if not (ax and bx) then return false end
  return M.placeCar(veh, { x = p.x, y = p.y, z = p.z + 0.3 }, { x = bx - ax, y = by - ay, z = 0 })
end

function M.formatTime(s)
  if not s then return '--:--.-' end
  local m = math.floor(s / 60)
  return string.format('%d:%04.1f', m, s - m * 60)
end

return M
