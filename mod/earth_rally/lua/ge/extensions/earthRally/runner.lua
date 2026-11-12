-- earthRally/runner: one timed run of a stage, through its controls as in a real rally: arrival time control
-- (ATC), start, flying finish, stop control.
--
--   travel     the car to the ATC (else the start; a BeamNG.Earth teleport when it is far), the world loaded
--   anchor     the world's origin moved to the stage's centre, so no world shift happens during the run for any
--              stage up to ~26 km across (BeamNG.Earth shifts the world 15-16 km from its origin)
--   build      the stage line (the recce, else the line matched to BeamNG.Earth's roads) put into game coordinates
--              now, the rally engine's files written and loaded: its co-driver calls the pacenotes
--   place      the car 40 m before the ATC (else on the start line), the controls' boards and tents put down
--   toAtc      drive to the ATC (the game's route arrows show the way); the car is braked in its zone and checked
--              in once stopped: its start time is the next half minute (hh:mm:00 / :30) at least 30 s on (the rally
--              clock). Driving past it to the start is a missed time control (+60 s)
--   toStart    drive to the start line; braked to a stop on it, then held there (brake, clutch on a manual, the car's
--              launch control where it has one) until GO
--   waitStart  wait for the start time; the co-driver: 30 s, 10 s, 5..1, go. Moving off before it is a jump start
--              (+10 s); reaching the line after it is late (+10 s a minute, and the next half minute)
--   running    the stage clock from the start time (game time: a pause stops it); a sound at the flying finish,
--              where the clock stops, the notes stop and the time is kept in earthRally/results
--   toStop     drive on to the stop control; braked to a stop in its zone
--   finished   the boards, the rally engine and the stage layout taken away
-- (Without an ATC the start time is a few seconds after the car stops on the line.)
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
M.FINISH_OFF_GAP_M = 150       -- ... this close where the line there is the organisers' (no road on the map)
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
M.LANDMARK_OFF_M = 15          -- a junction or bridge this close to the stage line is on it
M.CONTROL_RADIUS_M = 12        -- stopped this close to a control's board: checked in
M.STOP_CONTROL_RADIUS_M = 25
M.STOPPED_MS = 1.0
M.START_ZONE_BEFORE_M = 12     -- stopped this far before the start line (or less), beside it: on the line
M.START_ZONE_OFF_M = 8
M.START_GAP_S = 30             -- the start time at least this long after checking in at the ATC: the next half
                               -- minute mark (hh:mm:00 or hh:mm:30) from there, so the wait is 30-60 s
M.LATE_GAP_S = 10              -- late at the start: the next half-minute mark at least this far on
M.LIAISON_MS = 10              -- the drive from the ATC to the start line timed at this speed (36 km/h) ...
M.ROAD_FACTOR = 1.3            -- ... over the straight distance times this (the road winds) ...
M.STOP_ALLOW_S = 20            -- ... plus this to stop on the line: a far ATC gets more than START_GAP_S
M.MUTE_PAD_M = 30              -- no notes this far either side of a stretch with no road on the map
M.TIDY_AFTER_S = 8             -- the stage's boards and co-driver taken away this long after it is done
M.START_LINE_SHOW_M = 250      -- the start line drawn on the road while the car is this close to it
M.NO_ATC_START_S = 12          -- without an ATC: the start this long after stopping on the line (the 10 s call fits)
M.LATE_PENALTY_S = 10          -- a minute (or part) late at the start
M.MISSED_TC_PENALTY_S = 60     -- the ATC driven past without stopping at it
M.BRAKE_LEVEL = 0.30           -- the brake in a control zone and on the start line (0..1; the player can add more)
M.ZONE_HOLD_S = 1.5            -- stopped on the start line this long before the wait for the start time begins
M.FOLLOW_BACK_M = 150          -- the car's progress looked for this far behind ...
M.FOLLOW_AHEAD_M = 600         -- ... and this far ahead of where it was along the stage line
M.ROUTE_REFRESH_S = 5          -- the route arrows planned again this often (BeamNG.Earth's road map changes as you go)
M.SOUND_STOPPED = 'event:UI_Checkpoint'
M.SOUND_FINISH = 'event:UI_CountdownGo'

local run = nil

-- The rally clock (seconds of the day): the game's time of day when the run began, carried on with game time (so a
-- pause stops it, as the stage clock).
local function todNow()
  local env = rawget(_G, 'core_environment')
  local ok, tod = pcall(function() return env and env.getTimeOfDay and env.getTimeOfDay() end)
  if ok and type(tod) == 'table' and tonumber(tod.time) then return ((tod.time + 0.5) % 1) * 86400 end
  return os.time() % 86400
end
function M.clock() return run and run.clockBase and (run.clockBase + run.clockRun) or nil end
function M.formatClock(t)
  if not t then return '--:--:--' end
  t = math.floor(t + 0.5) % 86400
  return string.format('%02d:%02d:%02d', math.floor(t / 3600), math.floor(t / 60) % 60, t % 60)
end


local function say(text, s) earth.notify(text, s or 4) log('I', logTag, text) end
function M.state() return run and run.state or 'idle' end
function M.current() return run end

local function fail(why)
  if not run then return end
  run.state, run.error = 'failed', why
  say('Earth Rally: ' .. why, 8)
end

-- The stage line (a recce, or the map line matched to the roads: { points = { {lat, lon, alt}... } }) cut round the
-- stage: from a little before the start control to the end.
local function stageLatLon(stage, source)
  local pts = source.points
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
    -- (gap: a stretch of a matched line with no road on the map, the organisers' line there: no notes on it)
    pts[i] = { x = x, y = y, z = z, gap = p[4] == 1 or nil }
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
  -- (a flying finish on a stretch with no road on the map: the line there is the organisers', maybe well off the road)
  local fi = geo.segAt(run.cum, run.finishM)
  run.finishInGap = false
  for k = math.max(1, fi - 10), math.min(#pts, fi + 10) do if pts[k].gap then run.finishInGap = true end end
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
  local source, kind = events.stageLine(event.id, stage.id, stage)
  if not source then return false, 'this stage has no line on the roads yet: drive its recce first' end
  if not carPos() then return false, 'get in a car first' end
  M.abort(true)

  local latlon, startFlat, finishFlat = stageLatLon(stage, source)
  local flatLen = 0
  for i = 2, #latlon do flatLen = flatLen + geo.metres(latlon[i - 1][1], latlon[i - 1][2], latlon[i][1], latlon[i][2]) end
  run = {
    event = event, stage = stage, state = 'travel', t = 0, latlon = latlon, latlonLength = flatLen,
    startFlat = startFlat, finishFlat = finishFlat,
    dir = M.RUNTIME_DIR .. event.id .. '__' .. stage.id, id = 'beamng_earth/earthRally/' .. event.id .. '/' .. stage.id,
    checks = { moveSource = earth.moveSource(), shifts = 0, notesCalledAfterShift = 0, notReadyS = 0,
               maxOffM = 0, notesCalled = 0, line = kind },
    oldRebase = earth.rebaseDistance(),
    clockBase = todNow(), clockRun = 0,
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
  if run.state == 'running' or run.state == 'waitStart' or run.state == 'toStart' or run.state == 'toAtc' then
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
    earth.originMoved()
    M.resetCameraSoon()
    setState('build')
  elseif run.t > M.ANCHOR_WAIT_S then
    earth.originMoved()
    run.checks.originMoved = 'timed out'
    log('W', logTag, 'origin never moved to the stage centre: the world may shift during the run')
    setState('build')
  end
end

local function stepBuild()
  if run.oldRebase then earth.setRebaseDistance(M.MAX_REBASE_M) end
  if not project() then fail('could not put the stage into game coordinates') return end
  -- (no notes on the stretches of a matched line with no road on the map: its hand-drawn corners are not the road's)
  local mute, from = {}, nil
  for i, p in ipairs(run.line) do
    if p.gap then from = from or run.cum[i]
    elseif from then mute[#mute + 1] = { from - M.MUTE_PAD_M, run.cum[i] + M.MUTE_PAD_M } from = nil end
  end
  if from then mute[#mute + 1] = { from - M.MUTE_PAD_M, run.cum[#run.cum] } end
  run.checks.notesMutedKm = 0
  for _, r in ipairs(mute) do run.checks.notesMutedKm = run.checks.notesMutedKm + (r[2] - r[1]) / 1000 end
  -- junctions and bridges (from the matched line's map data) found on the line the stage runs on
  local lms = {}
  for _, lm in ipairs(events.landmarks(run.event.id, run.stage.id, run.stage)) do
    local x, y = earth.toGame(lm.lat, lm.lon, 0)
    if x then
      local _, _, s, off = geo.locate(run.line, run.cum, { x = x, y = y })
      if s and off and off <= M.LANDMARK_OFF_M then lms[#lms + 1] = { s = s, type = lm.type } end
    end
  end
  local okB, built = pcall(writer.build, run.line, { startM = run.startM, finishM = run.finishM, name = run.stage.name,
    mute = mute, landmarks = lms,
    quatFn = function(x, y, z) local q = quatFromDir(vec3(x, y, z), vec3(0, 0, 1)) return q.x, q.y, q.z, q.w end })
  if not okB then fail('could not build the stage: ' .. tostring(built)) return end
  writer.write(run.dir, built)
  run.built = built
  local ok, why = rallyA.load(run.id, run.dir)
  rallyA.notesOn(false)        -- (no calls on the way to the start: on at GO)
  run.checks.rallyEngine = ok and 'loaded' or ('failed: ' .. tostring(why))
  run.checks.cornersFound = built.corners
  run.checks.junctionsBridges = built.landmarks
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

-- The car's progress along the stage line: followed from where it was, so it never jumps to another part of the
-- stage that passes close by (geo.follow).
local function progress(p)
  local along, off = geo.follow(run.line, run.cum, p, run.prevAlong, M.FOLLOW_BACK_M, M.FOLLOW_AHEAD_M, M.OFF_ROUTE_M)
  run.prevAlong = along
  return along, off
end

-- The game's start clock fed as its own rally modes feed it (gameplay_rallyStartClock.onRallyDataUpdated): the rally
-- clock, the seconds to the start, and 'countdown' while the car waits on the line (its picture-in-picture view).
M.CLOCK_EXT = 'gameplay_rallyStartClock'
local function feedStartClock()
  if not (run and run.clockBase and extensions and extensions.hook and rawget(_G, M.CLOCK_EXT)) then return end
  local now = M.clock()
  local s = run.state
  local data = { rallyClock = { wallClockSecs = now % 86400 } }
  if s == 'waitStart' then data.activeState = 'countdown'
  elseif s == 'running' then data.activeState = 'stageActive'
  else data.activeState = 'vehicleProximity' end
  if run.startAt then
    local left = run.startAt - now
    data.countdownData = left > 0 and s ~= 'running' and { timeUntilLaunch = left, state = 'countdown' }
      or { timeUntilLaunch = 0, state = 'launched' }
  end
  pcall(extensions.hook, 'onRallyDataUpdated', data)
end
M._feedStartClock = feedStartClock
local function startClockOff()
  if run and run.clockExtOwned and extensions and extensions.unload then pcall(extensions.unload, M.CLOCK_EXT) end
  if run then run.clockExtOwned = nil end
end

-- The start clock's picture-in-picture on the right of the screen, above the speedometers (the game puts it at the top
-- in the middle, in the driver's view). The game's extension sets its place every frame from fixed values; this moves
-- it after that, in onDrawDebug (main.lua): the last hook before the frame is drawn. Its size stays the game's.
M.CLOCK_VIEW_NAME = 'rallyStartClockView'
M.CLOCK_VIEW_RIGHT = 0.015      -- (gap to the screen's right edge, share of its width)
M.CLOCK_VIEW_BOTTOM = 0.36      -- (the view's bottom this share of the screen's height above its bottom edge)
function M.placeClockView()
  if not (run and rawget(_G, M.CLOCK_EXT)) then return end     -- (only in our runs: the game's rally mode keeps its own)
  local rvm = rawget(_G, 'RenderViewManagerInstance')
  if not (rvm and rvm.getView) then return end
  local ok, view = pcall(rvm.getView, rvm, M.CLOCK_VIEW_NAME)
  if not (ok and view and view.active) then return end
  local canvas = scenetree.findObject and scenetree.findObject('Canvas')
  if not (canvas and canvas.getWindowClientSizeXY) then return end
  local W, H = canvas:getWindowClientSizeXY()
  local res = view.resolution
  local w, h = res and res.x, res and res.y
  if not (W and H and w and h and w > 1 and h > 1) then return end
  local x = math.floor(W - w - W * M.CLOCK_VIEW_RIGHT + 0.5)
  local y = math.floor(H - h - H * M.CLOCK_VIEW_BOTTOM + 0.5)
  view.compositeRect = RectI(math.max(0, x), math.max(0, y), w, h)
end

-- (a control's place in game coordinates now)
local function ctlGame(c)
  local x, y = earth.toGame(c.lat, c.lon, 0)
  return x and { x = x, y = y } or nil
end

-- The controls' boards and tents (props.lua), each facing the way the car comes through it.
-- (fwd m along the stage line from s0, in game coordinates now: run.line follows world shifts)
local function linePath(s0)
  return function(fwd)
    if not run or not run.line then return nil end
    local p, dir = geo.pointAt(run.line, run.cum, s0 + fwd)
    return { x = p.x, y = p.y, z = p.z, dx = dir.x, dy = dir.y }
  end
end

local function setupProps()
  props.clear()
  local sdir, sp = aheadDir(run.line, run.cum, run.startM)
  local slat, slon = earth.toGeo(sp.x, sp.y, sp.z)
  props.setSite('start', slat, slon, sdir, sp.z, linePath(run.startM))
  local fdir, fp = aheadDir(run.line, run.cum, run.finishM)
  local flat, flon = earth.toGeo(fp.x, fp.y, fp.z)
  props.setSite('ff', flat, flon, fdir, fp.z, linePath(run.finishM))
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

-- A place for the car on the road near (x, y), the way dir (game coordinates), fwd m along the road from there (back
-- for fwd < 0): the road map's road (props.roadAt: the one best aligned with dir, within props.SNAP_M) walked along
-- its bends; with no road on the map there, straight along dir. Returns { x, y, z (or nil), dx, dy, road }.
function M.roadSpot(x, y, dir, fwd)
  fwd = fwd or 0
  local e = props.roadAt(x, y, dir)
  if e then
    local w = fwd ~= 0 and props.walkRoad(e, fwd) or e
    return { x = w.x, y = w.y, z = w.z, dx = w.dx, dy = w.dy, road = true }
  end
  local l = math.sqrt(dir.x * dir.x + dir.y * dir.y)
  if l < 1e-6 then dir, l = { x = 0, y = 1 }, 1 end
  return { x = x + dir.x / l * fwd, y = y + dir.y / l * fwd, dx = dir.x / l, dy = dir.y / l, road = false }
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


-- The game's traffic and parked cars out of the way for the stage, as its own missions do it (missionManager: the
-- traffic, police and parking systems frozen with gameplay_traffic.freezeState, their cars stashed with
-- setActive(0)); put back as they were at the tidy-up (the cars shown again, then gameplay_traffic.unfreezeState).
local function trafficOff()
  if not run or run.trafficStash then return end
  local gt, gp = rawget(_G, 'gameplay_traffic'), rawget(_G, 'gameplay_parking')
  local getObj = rawget(_G, 'getObjectByID')
  local player = getPlayerVehicle and getPlayerVehicle(0)
  local playerId = player and player.getID and player:getID()
  local stash = { ids = {} }
  local ids = {}
  if gt and gt.getTrafficList then
    local ok, l = pcall(gt.getTrafficList)
    if ok and type(l) == 'table' then for _, id in ipairs(l) do ids[#ids + 1] = id end end
  end
  if gp and gp.getParkedCarsList then
    local ok, l = pcall(gp.getParkedCarsList)
    if ok and type(l) == 'table' then for _, id in ipairs(l) do ids[#ids + 1] = id end end
  end
  if gt and gt.freezeState then
    local ok, a, b, c = pcall(gt.freezeState, { exceptVehicleId = playerId })
    if ok then stash.traffic, stash.police, stash.parking = a, b, c end
  end
  if getObj then
    for _, id in ipairs(ids) do
      if id ~= playerId then
        local o = getObj(id)
        if o and o.getActive and o:getActive() then
          pcall(o.setActive, o, 0)
          stash.ids[#stash.ids + 1] = id
        end
      end
    end
  end
  run.trafficStash = stash
  run.checks.trafficHidden = #stash.ids
  if #stash.ids > 0 then log('I', logTag, 'traffic and parked cars out of the way for the stage: ' .. #stash.ids) end
end

local function trafficOn()
  local stash = run and run.trafficStash
  if not stash then return end
  run.trafficStash = nil
  local getObj = rawget(_G, 'getObjectByID')
  if getObj then
    for _, id in ipairs(stash.ids) do
      local o = getObj(id)
      if o then pcall(o.setActive, o, 1) end
    end
  end
  local gt = rawget(_G, 'gameplay_traffic')
  if gt and gt.unfreezeState and (stash.traffic or stash.parking) then
    pcall(gt.unfreezeState, stash.traffic, stash.police, stash.parking)
  end
end
M._trafficOff = function() trafficOff() end

local function stepPlace()
  local p, veh = carPos()
  if not veh then fail('no car') return end
  setupProps()
  local a = run.atc and ctlGame(run.atc)
  if a then
    -- 40 m before the ATC on the road it is on (the road map's road beside it, best aligned with the way on to the
    -- start, walked back along its bends), facing along it; never the organisers' point itself, which can be metres
    -- off the road
    local _, sp = aheadDir(run.line, run.cum, run.startM)
    local spot = M.roadSpot(a.x, a.y, { x = sp.x - a.x, y = sp.y - a.y }, -M.CAR_BEFORE_ATC_M)
    spot.z = groundNear(spot.x, spot.y, spot.z or p.z) + 1.0
    M.placeCar(veh, spot, { x = spot.dx, y = spot.dy, z = 0 })
    run.checks.atcSetDown = spot.road and 'on the road map' or 'no road on the map there'
    setState('toAtc')
    say('Earth Rally: drive to the time control and stop at its red board', 6)
  else
    toStartLine(veh)
    trafficOff()
    setState('toStart')
  end
  rallyA.resync()
  layoutOn()
end

local function speed()
  local p = earth.pose()
  return p and p.speed or 0
end

local function sound(ev)
  local eng = rawget(_G, 'Engine')
  if eng and eng.Audio and eng.Audio.playOnce then pcall(eng.Audio.playOnce, 'AudioGui', ev) end
end

-- The car's controls in a control zone and on the start line.
--
-- In a control zone (moving): the brake at least BRAKE_LEVEL through the vehicle controller's override
-- (electrics.values.brakeOverride: the player's own harder braking kept, their input handed back untouched when it is
-- cleared), let go as the car stops, before the arcade gearbox's "brake at a standstill selects reverse" can act.
--
-- On the start line, from stopping until GO: the game's freeze (as its own rally countdown holds a staged car,
-- gameplay/rally/.../stagedCountdownUtils): the car cannot move, the engine revs freely (the frozen gearbox lets the
-- clutch out, as the game's perfectLaunch does), and its brake output reads full, so the car's launch control (the
-- game's twoStepLaunch controller, switched on for the start) arms on the throttle. Both let go at GO. Not a brake
-- override there: on the arcade gearbox (the game's default) a held brake on a stopped car selects reverse and then
-- swaps brake and throttle, which drove the car backwards (review 2026-11-12).
--
-- Vehicle Lua (sent with queueLuaCommand; defined again with each command, so a changed mod is not left running its
-- old version in a car after Ctrl+L):
--   'zone'    the brake override at least `level`
--   'launch'  launch control on (its state before kept)
--   'off'     the override cleared, launch control as the player had it
-- (its two globals set with rawset / read with rawget: the vehicle's Lua logs a warning for each new global otherwise)
M.VEH_CTL = [[
rawset(_G, 'earthRally_ctl', function(mode, level)
  local ev = electrics.values
  local st = rawget(_G, 'earthRally_st')
  if mode == 'off' then
    ev.brakeOverride = nil
    if st and st.ts then
      for _, c in ipairs(st.ts) do if c.setTwoStep then pcall(c.setTwoStep, st.tsWas == true, true) end end
    end
    rawset(_G, 'earthRally_st', nil)
    return
  end
  if not st then st = {} rawset(_G, 'earthRally_st', st) end
  if mode == 'launch' then
    ev.brakeOverride = nil
    if not st.ts then
      local ok, ts = pcall(function() return controller.getControllersByType('twoStepLaunch') end)
      if ok and type(ts) == 'table' and ts[1] then
        st.ts, st.tsWas = ts, false
        local s = ts[1].getState and ts[1].getState() or {}
        for k, v in pairs(s) do if type(k) == 'string' and k:sub(-8) == '_enabled' then st.tsWas = v == true end end
        for _, c in ipairs(ts) do if c.setTwoStep then pcall(c.setTwoStep, true, true) end end
      end
    end
    return
  end
  ev.brakeOverride = math.max(input.brake or 0, level or 0)
end)
]]
-- (every car sent a control since the last 'off', so a car the player switched away from is let go too)
local ctlCars = {}           -- vehicle id (or the object) -> the vehicle
local function carKey(veh)
  local ok, id = pcall(function() return veh:getID() end)
  return ok and id or veh
end
local function vehCtl(veh, mode, level)
  if not veh then return end
  local cmd = M.VEH_CTL .. string.format('earthRally_ctl(%q, %.2f)', mode, level or 0)
  pcall(function() veh:queueLuaCommand(cmd) end)
  if mode ~= 'off' then ctlCars[carKey(veh)] = veh end
end
M._vehCtl = vehCtl

-- The car held still (the game's freeze).
local function freeze(veh, on)
  local vb = rawget(_G, 'core_vehicleBridge')
  if veh and vb and vb.executeAction then pcall(vb.executeAction, veh, 'setFreeze', on) end
  if on and veh then ctlCars[carKey(veh)] = veh end
end

-- A control zone: inZone each frame. The car braked (BRAKE_LEVEL) from the moment it is in it; once it stops a sound
-- ('stopped' in that frame, 'done' a frame later) and the brake let go, or let go when it leaves the zone. keepHeld
-- (the start line): once stopped the car is held (freeze, launch control) until zoneRelease() at GO.
local function zone(inZone, dt, keepHeld)
  local _, veh = carPos()
  local z = run.zone
  if not z then
    if not inZone then return nil end
    z = { t = 0 }
    run.zone = z
  end
  if z.stopped then
    z.t = z.t + dt
    if keepHeld then return z.t >= M.ZONE_HOLD_S and 'done' or 'held' end
    run.zone = nil
    return 'done'
  end
  if not inZone then
    vehCtl(veh, 'off')
    run.zone = nil
    return nil
  end
  if speed() < M.STOPPED_MS then
    z.stopped = true
    vehCtl(veh, 'off')
    if keepHeld then
      freeze(veh, true)
      vehCtl(veh, 'launch')
      z.held = veh
    end
    sound(M.SOUND_STOPPED)
    return 'stopped'
  end
  vehCtl(veh, 'zone', M.BRAKE_LEVEL)
  return 'moving'
end
-- Brake, freeze and launch control handed back (GO, the end of a run), on every car they were sent to.
local function zoneRelease()
  if not run then return end
  local _, veh = carPos()
  if veh and run.zone then ctlCars[carKey(veh)] = veh end
  for _, car in pairs(ctlCars) do
    freeze(car, false)
    vehCtl(car, 'off')
  end
  ctlCars = {}
  run.zone = nil
end

-- The game's route arrows on the road to a control (core_groundMarkers, as BeamNG.Earth's GPS draws its own; the
-- GPS's destination cleared first so the two do not fight). Planned again every ROUTE_REFRESH_S.
local function routeTo(target, dt)
  local gm = rawget(_G, 'core_groundMarkers')
  if not (gm and gm.setPath) then return end
  run.routeT = (run.routeT or 0) - (dt or 0)
  if target and run.routeT > 0 and run.routeTarget == target then return end
  if target and not run.routeTarget then earth.gpsClear() end
  run.routeT, run.routeTarget = M.ROUTE_REFRESH_S, target
  if target then
    local p = target.pos
    pcall(gm.setPath, vec3(p.x, p.y, p.z or 0))
  else
    pcall(gm.setPath, nil)
  end
end
local function routeOff()
  if run and run.routeTarget then
    local gm = rawget(_G, 'core_groundMarkers')
    if gm and gm.setPath then pcall(gm.setPath, nil) end
    run.routeTarget = nil
  end
end

local function stepToAtc(dt)
  run.t = run.t + dt
  local p = carPos()
  -- (where its boards stand on the road once they are down; the map's point until then)
  local a = props.sitePoint('atc') or ctlGame(run.atc)
  if not (p and a) then return end
  props.update(p, earth.toGame)
  local d = math.sqrt((p.x - a.x) ^ 2 + (p.y - a.y) ^ 2)
  run.toControlM = d
  run.atcTarget = run.atcTarget or {}
  run.atcTarget.pos = { x = a.x, y = a.y, z = p.z }
  if not (run.zone and run.zone.stopped) then routeTo(run.atcTarget, dt) end   -- (none once stopped in the zone)
  local zs = zone(d <= M.CONTROL_RADIUS_M, dt)
  if zs == 'stopped' then
    local now = M.clock()
    run.atcTime = now
    -- the next half minute at least START_GAP_S on, more when the start line is far (driven at LIAISON_MS)
    local sp = geo.pointAt(run.line, run.cum, run.startM)
    local far = math.sqrt((sp.x - a.x) ^ 2 + (sp.y - a.y) ^ 2) * M.ROAD_FACTOR
    local gap = math.max(M.START_GAP_S, far / M.LIAISON_MS + M.STOP_ALLOW_S)
    run.startAt = math.ceil((now + gap) / 30) * 30
    run.checks.atc = 'checked in ' .. M.formatClock(now)
    trafficOff()
    say(string.format('Checked in at %s. Your start time: %s. Move up to the start line.', M.formatClock(now),
      M.formatClock(run.startAt)), 8)
    -- (the co-driver's own pre-start lines: the voice packs have no "move up" line)
    rallyA.systemNote('commsCheck')
    rallyA.systemNote('beltsCheck')
  elseif zs == 'done' then
    setState('toStart')
  elseif not zs then
    -- (driven on past it to the start: the ATC missed)
    local sp = geo.pointAt(run.line, run.cum, run.startM)
    local near = (p.x - sp.x) ^ 2 + (p.y - sp.y) ^ 2 <= 100 ^ 2
    local along, off
    if near then along, off = progress(p) end
    if near and along >= run.startM - M.START_ZONE_BEFORE_M and off <= M.START_ZONE_OFF_M then
      run.checks.atc = 'missed'
      run.missedAtc = true
      trafficOff()
      say(string.format('Time control missed: +%d s', M.MISSED_TC_PENALTY_S), 5)
      setState('toStart')
    end
  end
end

local function stepToStart(dt)
  run.t = run.t + dt
  local p = carPos()
  if not p then return end
  props.update(p, earth.toGame)
  local along, off = progress(p)
  run.toControlM = run.startM - along
  local sp = geo.pointAt(run.line, run.cum, run.startM)
  run.startTarget = run.startTarget or {}
  run.startTarget.pos = sp
  if not (run.zone and run.zone.stopped) then routeTo(run.startTarget, dt) end   -- (none once stopped in the zone)
  if along > run.startM + 2 and off <= M.START_ZONE_OFF_M and not run.zone then
    if not run.overLine then say('Back up behind the start line.', 3) end
    run.overLine = true
    return
  end
  run.overLine = false
  local zs = zone(along >= run.startM - M.START_ZONE_BEFORE_M and along <= run.startM + 3 and off <= M.START_ZONE_OFF_M, dt,
    true)
  if zs == 'stopped' then
    routeOff()
    run.staged = p              -- (where it stopped: moving away from here before GO is a jump start)
    local now = M.clock()
    if not run.startAt and run.missedAtc then
      -- the ATC driven past: a start time as if checked in here, and the penalty
      run.startAt = math.ceil((now + M.START_GAP_S) / 30) * 30
      say('Start time ' .. M.formatClock(run.startAt) .. '. Wait for it.', 5)
    elseif not run.startAt then
      run.startAt = now + M.NO_ATC_START_S
    elseif now > run.startAt then
      -- late at the start: the next half minute, and a penalty for each minute (or part) late
      local newStart = math.ceil((now + M.LATE_GAP_S) / 30) * 30
      local mins = math.max(1, math.ceil((now - run.startAt) / 60))
      run.latePenalty = mins * M.LATE_PENALTY_S
      run.checks.lateMinutes = mins
      say(string.format('Late at the start: +%d s. New start time %s', run.latePenalty, M.formatClock(newStart)), 6)
      run.startAt = newStart
      rallyA.systemNote('rescheduled')
    else
      say('Start time ' .. M.formatClock(run.startAt) .. '. Wait for your minute' ..
        (run.startAt - M.clock() > M.SKIP_TO_S + 10 and ' (Interact, Shift+E: skip the wait).' or '.'), 5)
    end
  elseif zs == 'done' then
    -- (the co-driver from the start afresh: whatever it picked up on the way here is dropped)
    rallyA.resync()
    setState('waitStart')
    run.lastShown = nil
  end
end

-- The start line across the road (white, edge to edge where the road's width is known), drawn while the car is near.
local lineColor = nil
local function drawStartLine()
  if not (run and run.line and debugDrawer and debugDrawer.drawSquarePrism) then return end
  local s = run.state
  if not (s == 'toAtc' or s == 'toStart' or s == 'waitStart' or (s == 'running' and (run.clock or 0) < 10)) then return end
  local p = carPos()
  local sp, dir = geo.pointAt(run.line, run.cum, run.startM)
  if not (p and sp) or (p.x - sp.x) ^ 2 + (p.y - sp.y) ^ 2 > M.START_LINE_SHOW_M ^ 2 then return end
  if not run.startHalf then
    local road = props.roadAt(sp.x, sp.y, dir)
    run.startHalf = road and road.half or 3.5
  end
  local h = run.startHalf
  local rx, ry = dir.y, -dir.x
  local z = (sp.z or p.z) + 0.04
  lineColor = lineColor or ColorF(1, 1, 1, 0.95)
  local ok = pcall(function()
    debugDrawer:drawSquarePrism(vec3(sp.x - rx * h, sp.y - ry * h, z), vec3(sp.x + rx * h, sp.y + ry * h, z),
      Point2F(0.03, 0.45), Point2F(0.03, 0.45), lineColor)
  end)
  if not ok then run.noStartLine = true end
end
M._drawStartLine = drawStartLine

local function stepWaitStart(dt)
  run.t = run.t + dt
  routeOff()                   -- (no route arrows at the start, nor on the stage)
  local p = carPos()
  if p then props.update(p, earth.toGame) end
  local left = run.startAt - M.clock()
  -- held on the line until GO (the freeze, launch control on), so the player can rev without moving; moving off
  -- before GO (a held car that was not, e.g. a switched car) is still a jump start (the stage clock runs from the start)
  run.staged = run.staged or p
  if p and run.staged and not run.jumpStart and geo.dist2d(p, run.staged) > M.JUMP_START_M then
    run.jumpStart = true
    rallyA.systemNote('falseStart')
    say('Jump start: +' .. M.JUMP_START_PENALTY_S .. ' s', 3)
  end
  -- the co-driver: "30 seconds", "good luck"; "10 seconds" and the first note; 5..1; go and the first note again
  local before = run.prevLeft or math.huge
  run.prevLeft = left
  if before > 30 and left <= 30 and left > 25 then
    rallyA.systemNote('warningSeconds30')
    rallyA.systemNote('precountdown')
  end
  if before > 10 and left <= 10 and left > 5.5 then rallyA.systemNote('warningSeconds10') end
  local n = math.ceil(left)
  if n >= 1 and n <= 5 and n ~= run.lastShown then
    run.lastShown = n
    rallyA.systemNote('countdown' .. n)
    if ui_message then ui_message(tostring(n), 1, 'earthRallyCount') end
  end
  if left <= 0 then
    zoneRelease()              -- (the car let go in the frame of the GO call)
    rallyA.notesOn(true)       -- (the stage's notes from GO only)
    rallyA.systemNote('countdowngo')
    -- (the first note is the engine's own: its 'immediate' note, read as the car pulls away. Calling it ourselves and
    -- marking it called froze the engine's step to the next note, which only moves on when it plays one itself.)
    if ui_message then ui_message('GO', 1.5, 'earthRallyCount') end
    run.clock = -left          -- (from the minute itself, not this frame)
    setState('running')
  end
end

-- Skipping the wait on the start line, as the game's rally mode does (flowgraph rallySuperCountdown): the game's
-- Interact control (gameplay_interact: Shift+E, the modifier + Y on a pad) while held on the line, stopped, more than
-- SKIP_TO_S before the start, moves the rally clock on to SKIP_TO_S before it (the start tree's clock with it); the 30 s
-- and 10 s calls are passed over, so only 5-4-3-2-1-go plays. Not again for SKIP_DEBOUNCE_S.
M.SKIP_TO_S = 6
M.SKIP_DEBOUNCE_S = 2
M.SKIP_MAX_MS = 2 / 3.6          -- (stopped: under 2 km/h)
function M.canSkip()
  if not (run and run.state == 'waitStart' and run.startAt and run.clockBase) then return false end
  if run.jumpStart or (run.skipAt and run.t - run.skipAt < M.SKIP_DEBOUNCE_S) then return false end
  if speed() >= M.SKIP_MAX_MS then return false end
  return run.startAt - M.clock() > M.SKIP_TO_S + 0.5
end

function M.skipCountdown()
  if not M.canSkip() then return false end
  local left = run.startAt - M.clock()
  run.clockRun = run.clockRun + (left - M.SKIP_TO_S)
  run.prevLeft = M.SKIP_TO_S        -- (the 30 s and 10 s calls passed over)
  run.skipAt = run.t
  run.checks.skippedS = (run.checks.skippedS or 0) + (left - M.SKIP_TO_S)
  log('I', logTag, string.format('start countdown skipped: %.0f s on', left - M.SKIP_TO_S))
  return true
end

-- (the game's Interact control: main.lua passes on its hook)
function M.onGameplayInteract() return M.skipCountdown() end

local function stepRunning(dtSim)
  routeOff()
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
  if along >= run.finishM and off <= (run.finishInGap and M.FINISH_OFF_GAP_M or M.FINISH_OFF_M) then
    sound(M.SOUND_FINISH)
    rallyA.notesOn(false)        -- (the stage is over: no more calls on the way to the stop control or after)
    run.stageTime = run.clock
    run.penalty = (run.jumpStart and M.JUMP_START_PENALTY_S or 0) + (run.latePenalty or 0)
      + (run.missedAtc and M.MISSED_TC_PENALTY_S or 0)
    local time = run.clock + run.penalty
    local checks = run.checks
    local best = events.addResult(run.event.id, run.stage.id, { finished = true, timeS = time, stageS = run.clock,
      penaltyS = run.penalty, jumpStart = run.jumpStart == true, lateMinutes = checks.lateMinutes,
      missedAtc = run.missedAtc == true, line = checks.line,
      startAt = M.formatClock(run.startAt), date = os.date('!%Y-%m-%dT%H:%M:%SZ'), checks = checks })
    run.finalTime, run.best = time, best
    log('I', logTag, 'run checks: ' .. dumps(checks))
    local text = string.format('%s: %s%s', run.stage.name, M.formatTime(time), best and best < time and
      ('  (best ' .. M.formatTime(best) .. ')') or '  (best)')
    if run.stopCtl then
      setState('toStop')
      say(text .. '. Drive on to the stop control and stop at it.', 8)
    else
      say(text, 8)
      M.wrapUp()
    end
  end
end

local function stepToStop(dt)
  run.t = run.t + dt
  local p = carPos()
  local b = props.sitePoint('stop') or ctlGame(run.stopCtl)
  if not (p and b) then return end
  props.update(p, earth.toGame)
  local d = math.sqrt((p.x - b.x) ^ 2 + (p.y - b.y) ^ 2)
  run.toControlM = d
  run.stopTarget = run.stopTarget or {}
  run.stopTarget.pos = { x = b.x, y = b.y, z = p.z }
  if not (run.zone and run.zone.stopped) then routeTo(run.stopTarget, dt) end   -- (none once stopped in the zone)
  local zs = zone(d <= M.STOP_CONTROL_RADIUS_M, dt)
  if zs == 'stopped' then
    routeOff()
    run.checks.stopControl = 'stopped ' .. M.formatClock(M.clock())
    say('Stage complete: ' .. M.formatTime(run.finalTime), 6)
  elseif zs == 'done' then
    M.wrapUp()
  end
end

local tidy        -- (below)

-- Every frame (main.lua).
function M.update(dtReal, dtSim)
  camUpdate(dtReal or 0)
  if not run then return end
  if not run.noStartLine then drawStartLine() end
  if run.clockBase then run.clockRun = run.clockRun + (dtSim or 0) end
  local s = run.state
  -- the game's start clock: the LED board on the start tree (props.lua), and its picture-in-picture during the
  -- countdown (gameplay_rallyStartClock, fed here). Loaded once the tree is down, for the run only: until it has a
  -- tree it looks through every static object in the scene once a second, and BeamNG.Earth's scene is large.
  if not run.clockExtTried and props.placed('start') and extensions and extensions.load then
    run.clockExtTried = true
    if not rawget(_G, M.CLOCK_EXT) then
      pcall(extensions.load, M.CLOCK_EXT)
      run.clockExtOwned = rawget(_G, M.CLOCK_EXT) ~= nil
    end
  end
  if s == 'toAtc' or s == 'toStart' or s == 'waitStart' or (s == 'running' and (run.clock or 0) < 8) then
    feedStartClock()
  end
  if s == 'finished' and run.tidyIn then
    run.tidyIn = run.tidyIn - (dtReal or 0)
    if run.tidyIn <= 0 then run.tidyIn = nil tidy() end
  end
  if s == 'travel' then stepTravel(dtReal)
  elseif s == 'anchor' then stepAnchor(dtReal)
  elseif s == 'build' then stepBuild()
  elseif s == 'place' then stepPlace()
  elseif s == 'toAtc' then stepToAtc(dtSim)
  elseif s == 'toStart' then stepToStart(dtSim)
  elseif s == 'waitStart' then stepWaitStart(dtSim)
  elseif s == 'running' then stepRunning(dtSim)
  elseif s == 'toStop' then stepToStop(dtSim) end
end

-- BeamNG.Earth's rebase distance back, and no more listening for origin moves.
function M.release()
  if not run then return end
  if run.oldRebase then earth.setRebaseDistance(run.oldRebase) run.oldRebase = nil end
  if run.moveHandle then earth.offMoved(run.moveHandle) run.moveHandle = nil end
end

-- Everything the run put in the game taken away (the result stays in `run` for the window until it is closed).
tidy = function()
  trafficOn()
  earth.originMoved()
  zoneRelease()
  routeOff()
  M.release()
  layoutOff()
  props.clear()
  startClockOff()
  rallyA.unload()
end

-- The stage done (at the flying finish without a stop control, else at the stop control): its result kept, the rest
-- tidied away so the player drives on in plain BeamNG.Earth.
function M.wrapUp()
  if not run then return end
  setState('finished')
  -- (the car let go, the route arrows off at once; the boards, the co-driver and the stage layout a few seconds
  -- later, so the stop control's tent does not vanish the moment the car stops)
  zoneRelease()
  routeOff()
  M.release()
  run.tidyIn = M.TIDY_AFTER_S
end

function M.abort(quiet)
  if not run then return end
  tidy()
  if not quiet and run.state ~= 'finished' then say('Earth Rally: run stopped') end
  run = nil
end

-- Where a stage's run begins: its ATC when it has one of its own (near enough the start), else its start.
-- Returns lat, lon, what ('ATC' / 'start').
function M.arrivalPoint(stage)
  local ctl = stage.controls or {}
  local st = ctl.start or (stage.line and stage.line[1] and { lat = stage.line[1][1], lon = stage.line[1][2] })
  if not st then return nil end
  if ctl.atc then
    local d = geo.metres(ctl.atc.lat, ctl.atc.lon, st.lat, st.lon)
    if d <= M.ATC_MAX_FROM_START_M and d >= 5 then return ctl.atc.lat, ctl.atc.lon, 'ATC' end
  end
  return st.lat, st.lon, 'start'
end

-- After a 'Go to start' teleport (to the organisers' start point, which can be metres off the road): the car put on
-- the road behind the start line, facing along the stage. On the stage's line on the roads (recce or matched) when it
-- has one; else on the road map's road beside the start; else where it stands, turned along the stage. Returns true
-- once done, and how ('stage line', 'road map', 'turned only').
function M.faceStage(stage, eventId)
  local p, veh = carPos()
  if not (p and veh and stage.line and #stage.line >= 2) then return false end
  local s = stage.controls and stage.controls.start
  local o = s and { s.lat, s.lon } or stage.line[1]
  -- 1. the stage's line on the roads: the start's point on it, the car CAR_BEHIND_LINE_M back
  local source = eventId and events.stageLine(eventId, stage.id, stage)
  if source and source.points and #source.points >= 2 then
    local pts = source.points
    local best, bestD = 1, math.huge
    for i, q in ipairs(pts) do
      local d = geo.metres(o[1], o[2], q[1], q[2])
      if d < bestD then best, bestD = i, d end
    end
    if bestD <= 200 then
      local back, ahead = pts[1], pts[#pts]
      for i = best, 1, -1 do
        back = pts[i]
        if geo.metres(pts[best][1], pts[best][2], pts[i][1], pts[i][2]) >= M.CAR_BEHIND_LINE_M then break end
      end
      for i = best + 1, #pts do
        if geo.metres(pts[best][1], pts[best][2], pts[i][1], pts[i][2]) >= M.FACE_AHEAD_M then ahead = pts[i] break end
      end
      local bx, by, bz = earth.toGame(back[1], back[2], back[3] or 0)
      local ax, ay = earth.toGame(pts[best][1], pts[best][2], 0)
      local fx, fy = earth.toGame(ahead[1], ahead[2], 0)
      if bx and ax and fx and (fx - ax) ^ 2 + (fy - ay) ^ 2 > 1 then
        local z = groundNear(bx, by, back[3] and bz or p.z) + 1.0
        return M.placeCar(veh, { x = bx, y = by, z = z }, { x = fx - ax, y = fy - ay, z = 0 }), 'stage line'
      end
    end
  end
  -- the map line's way at the start
  local ahead = stage.line[#stage.line]
  for i = 2, #stage.line do
    local q = stage.line[i]
    if geo.metres(o[1], o[2], q[1], q[2]) >= M.FACE_AHEAD_M then ahead = q break end
  end
  local ax, ay = earth.toGame(o[1], o[2], 0)
  local bx, by = earth.toGame(ahead[1], ahead[2], 0)
  if not (ax and bx) then return false end
  local dir = { x = bx - ax, y = by - ay }
  -- 2. the road map's road beside the start point
  local spot = M.roadSpot(ax, ay, dir, -M.CAR_BEHIND_LINE_M)
  if spot.road then
    local z = groundNear(spot.x, spot.y, spot.z or p.z) + 1.0
    return M.placeCar(veh, { x = spot.x, y = spot.y, z = z }, { x = spot.dx, y = spot.dy, z = 0 }), 'road map'
  end
  -- 3. no road known here: where it stands, turned along the stage
  return M.placeCar(veh, { x = p.x, y = p.y, z = p.z + 0.3 }, { x = dir.x, y = dir.y, z = 0 }), 'turned only'
end

function M.formatTime(s)
  if not s then return '--:--.-' end
  local m = math.floor(s / 60)
  return string.format('%d:%04.1f', m, s - m * 60)
end

return M
