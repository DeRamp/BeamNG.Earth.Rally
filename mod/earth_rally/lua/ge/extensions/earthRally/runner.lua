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
local settings = require('earthRally/settings')
local hudFrame = require('earthRally/hudFrame')

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
M.NO_SET_DOWN_M = 150          -- a car driven to within this of the ATC is not moved ...
M.DRIVEN_THERE_MIN_M = 15      -- ... unless it is this near or nearer, when it is set down before the control.
                               -- A car standing on the control is stopped inside its zone, so the check-in fires at
                               -- once and the drive up to it never happens (in game, 2026-11-13: `run: toAtc` and
                               -- `Checked in` 0.03 s apart, the car having respawned beside the ATC). Derived from
                               -- CONTROL_RADIUS_M (12) and a few metres over, not picked: the band between this and
                               -- NO_SET_DOWN_M is where a player who drove up and parked keeps the spot they chose,
                               -- and every metre added to it is a player moved who did not ask to be.
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
M.MUTE_PAD_M = writer.MUTE_PAD_M   -- no notes this far either side of a stretch with no road on the map: the
                               -- stage writer's own, so the corner count kept with a line (lineStats.lua) mutes
                               -- the same stretches this run does
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
M.RESET_PENALTY_S = 10         -- each car reset during the timed stage (setting resetPenalty)
M.RESET_DEBOUNCE_S = 0.5       -- (one reset can be heard more than once)
M.RESET_AFTER_MOVE_S = 2       -- (no reset counted this soon after the world's origin moved: not the player's)
M.OFF_ROUTE_CLEAR_M = 40       -- (where the line is the organisers': off route from OFF_ROUTE_M, back within this)
-- Off route where the line follows the road (a recce, or matched to the map's roads: within a metre or so of the
-- road's middle): off the road and away, not only on a wrong road 60 m off as in 1.2.0, which never showed for a car
-- off the track (in game, 2026-11-13). Back on the route within OFF_ROUTE_ON_ROAD_CLEAR_M (no flicker at the edge).
M.OFF_ROUTE_ON_ROAD_M = 20
M.OFF_ROUTE_ON_ROAD_CLEAR_M = 12
M.TRAFFIC_HOLD_S = 1           -- traffic and parked cars kept away this often during the stage
M.LAYOUT_HOLD_S = 1            -- the stage layout put back this often if the game's plain layout came back
-- The layouts the hold puts ours back over: the plain driving ones the game or BeamNG.Earth put back on their own (a
-- car reloaded or replaced mid-stage), and the one before the run. Any other is the game's for the moment and left
-- alone: the radial menu's 'radial' (quickAccess.lua puts the one before it back when the menu closes), the garage,
-- photo mode, a mission (in game, 2026-11-13: the hold fought the radial menu).
M.HOLD_OVER = { freeroam = true, beamngEarth = true, beamngEarthMP = true }
M.LAYOUT_CHECK_S = 2           -- the layout on screen logged this long after ours was put on (the UI switches later)
-- The apps the stage layout must carry for the HUD to show (the check logged at each run).
M.STAGE_APPS = { 'earthRallyHud', 'earthRallyResults', 'rallyCountdown', 'rallyStageTiming', 'rallyStageProgress',
  'rallyVisualPacenotes' }
M.RECOVER_UP_M = 0.5           -- a car put back on the road / upright: this far above the ground
M.RESULTS_CLOSE_M = 100        -- the results card closes once the car is driven this far from where it stopped ...
M.RESULTS_TIMEOUT_S = 120      -- ... or after this long
M.uiHidden = false             -- a game menu is up: the HUD draws nothing (main.lua's onUiChangedState sets it)
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


-- A message: the game's toasts (guihooks 'toastrMsg', as gameplay/lowPerformance.lua), BeamNG.Earth's notify line
-- without them. kind: 'info' / 'success' / 'warning' / 'error'; title: its first line (else 'Earth Rally').
function M.say(text, s, kind, title)
  local gh = rawget(_G, 'guihooks')
  if gh and gh.trigger then
    -- (label: the toast's id there; one shared id would replace each toast with the next)
    pcall(gh.trigger, 'toastrMsg', { type = kind or 'info', title = title or 'Earth Rally', msg = text,
      label = 'earthRally: ' .. tostring(title) .. ': ' .. tostring(text), config = { timeOut = math.floor((s or 4) * 1000) } })
  else
    earth.notify((title and (title .. ': ') or '') .. text, s or 4)
  end
  log('I', logTag, (title and (title .. ': ') or '') .. text)
end
local function say(text, s, kind, title) M.say(text, s, kind, title) end
function M.state() return run and run.state or 'idle' end
function M.current() return run end

local function fail(why)
  if not run then return end
  run.state, run.error = 'failed', why
  say(why, 8, 'error', 'Earth Rally: run stopped')
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

-- The run's screen layout (settings/ui_apps/.../earthRallyStage: BeamNG.Earth's own with the game's rally apps and
-- our HUD apps), and back to the one before when the run ends.
M.STAGE_LAYOUT = 'earthRallyStage'

-- The game state's layout now (core_gamestate), or nil.
local function stateLayout()
  local gs = rawget(_G, 'core_gamestate')
  local ok, cur = pcall(function() return gs and gs.getGameState and gs.getGameState() end)
  return ok and cur and cur.appLayout or nil
end

-- Pure: a line on the layout the UI has on screen, from the game state's layout name and the game's current layout
-- (ui_appLayouts.getCurrentLayout(): { type, filename, apps = { { appName }... } }), and the apps of STAGE_APPS it
-- lacks (empty when it is ours and complete). 1.2.1 in game: the layout file installed had none of the HUD apps
-- (tools/install.py wrote its 1.1.0 layout over ours), so nothing but the pacenote cards showed.
function M.layoutReport(stateName, cur)
  if type(cur) ~= 'table' then
    return string.format('game state %s; on screen: unknown (no ui_appLayouts)', tostring(stateName)), nil
  end
  local have = {}
  for _, a in ipairs(type(cur.apps) == 'table' and cur.apps or {}) do
    if type(a) == 'table' and a.appName then have[a.appName] = true end
  end
  local missing = {}
  for _, n in ipairs(M.STAGE_APPS) do if not have[n] then missing[#missing + 1] = n end end
  local text = string.format('game state %s; on screen: %s (%s, version %s), %d apps; %s', tostring(stateName),
    tostring(cur.type), tostring(cur.filename), tostring(cur.version), #(type(cur.apps) == 'table' and cur.apps or {}),
    #missing == 0 and 'all the stage apps there' or ('missing: ' .. table.concat(missing, ', ')))
  return text, missing
end

local function logLayout()
  local ui = rawget(_G, 'ui_appLayouts')
  local okC, cur = pcall(function() return ui and ui.getCurrentLayout and ui.getCurrentLayout() end)
  local text, missing = M.layoutReport(stateLayout(), okC and cur or nil)
  if cur and type(cur) == 'table' and cur.type ~= M.STAGE_LAYOUT then
    log('W', logTag, 'stage layout NOT on screen: ' .. text)
  elseif missing and #missing > 0 then
    log('W', logTag, 'stage layout on screen WITHOUT the HUD apps (an old layout file installed?): ' .. text)
  else
    log('I', logTag, 'stage layout: ' .. text)
  end
  return text, missing
end
M._logLayout = logLayout

local function layoutOn()
  local gs = rawget(_G, 'core_gamestate')
  if not (gs and gs.setGameState and gs.getGameState) or run.oldLayout then return end
  run.oldLayout = stateLayout() or 'beamngEarth'
  if run.oldLayout ~= M.STAGE_LAYOUT then pcall(gs.setGameState, nil, M.STAGE_LAYOUT) end
  run.layoutCheckIn = M.LAYOUT_CHECK_S
  -- BeamNG.Earth's own strips off screen for the stage: the HUD shows what they carried, in its own panel.
  -- stripsHeld means "we asked", not "every strip took": holdStrips asks for two and can get one, and the one it got
  -- still has to be given back. (1.2.5 released only when both took, so a half-held strip stayed off screen for the
  -- rest of the session -- and BeamNG.Earth leaves its own imgui drawing out while it believes an app has the strip,
  -- so that is its connection banner gone, with the "server not running" message in it.)
  run.stripsHeld = true
  local held = earth.holdStrips(true)
  log('I', logTag, string.format('stage layout put on (was %s; game state now %s)%s', tostring(run.oldLayout),
    tostring(stateLayout()), held and "; BeamNG.Earth's strips off screen" or ''))
end
local function layoutOff()
  local gs = rawget(_G, 'core_gamestate')
  if run and run.oldLayout and gs and gs.setGameState then
    local back = run.oldLayout ~= M.STAGE_LAYOUT and run.oldLayout or 'beamngEarth'
    pcall(gs.setGameState, nil, back)
    log('I', logTag, 'stage layout off: ' .. tostring(back) .. ' back')
  end
  -- (outside the check above: the strips go back even when the layout never went on)
  if run and run.stripsHeld then
    earth.holdStrips(false)
    run.stripsHeld = nil
  end
  if run then run.oldLayout = nil end
end

-- Pure: whether the hold puts the stage layout back over `name` (the game state's layout now; oldLayout: the one before
-- the run).
function M.holdOver(name, oldLayout)
  if name == nil or name == M.STAGE_LAYOUT then return false end
  return M.HOLD_OVER[name] == true or name == oldLayout
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
  if not source then
    -- (the auto recce named only where it can actually be run: an older BeamNG.Earth has no road graph to
    --  match against, and the menu offers no button there either)
    return false, earth.hasRoadGraph()
      and 'this stage has no line on the roads yet: run the auto recce, or drive its recce'
      or 'this stage has no line on the roads yet: drive its recce first'
  end
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
    clockBase = todNow(), clockRun = 0, realT = 0, resets = 0,
  }
  -- its SS number (the stage's place in the rally's map) and the next stage
  run.ssCount = #(event.stages or {})
  for i, st in ipairs(event.stages or {}) do
    if st == stage or st.id == stage.id then
      run.ss = i
      local nx = event.stages[i + 1]
      if nx then run.nextStage = { id = nx.id, ss = i + 1, name = nx.name, lengthM = nx.lengthM } end
      break
    end
  end
  run.moveHandle = earth.onMoved(function(info) M._moved(info) end)

  -- the time controls round the stage (from the event's map), when they are near enough to be its own
  local ctl = stage.controls or {}
  local st0 = ctl.start or { lat = latlon[1][1], lon = latlon[1][2] }
  -- (setting timeControls 'quick': no ATC, the car set down on the start line, the start a few seconds after stopping)
  run.quick = settings.get('timeControls') == 'quick'
  if ctl.atc and not run.quick then
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
  say(stage.name .. ': getting ready', 4, 'info', 'Earth Rally')
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
  run.movedAt = run.realT
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
  -- (the view shows only while the state is 'countdown': setting clockView 'off' never says so; the LED board on the
  -- start tree still counts down from countdownData)
  if s == 'waitStart' and settings.get('clockView') ~= 'off' then data.activeState = 'countdown'
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

-- The start clock's picture-in-picture in the top right corner of the screen (the game puts it at the top in the
-- middle, in the driver's view; above the speedometers, as in 1.1.0, the boost gauge covered it). The game's extension sets its place every frame from fixed values; this moves
-- it after that, in onDrawDebug (main.lua): the last hook before the frame is drawn. Its size stays the game's.
M.CLOCK_VIEW_NAME = 'rallyStartClockView'
M.CLOCK_VIEW_RIGHT = 0.015      -- (gap to the screen's right edge, share of its width)
M.CLOCK_VIEW_CENTRE_Y = 0.5     -- (the view's middle this far down the screen, share of its height). It sat 3 %
                                -- from the top until 1.2.5, where the game's own messages and toasts appear and it
                                -- was in their way (the user, 2026-11-13). Halfway down the right edge clears both
                                -- those and the boost gauge that covered it when 1.1.0 put it above the speedometers.
function M.placeClockView()
  if not (run and rawget(_G, M.CLOCK_EXT)) then return end     -- (only in our runs: the game's rally mode keeps its own)
  if settings.get('clockView') ~= 'right' then return end       -- ('top': where the game puts it; 'off': not shown)
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
  local y = math.floor(H * M.CLOCK_VIEW_CENTRE_Y - h / 2 + 0.5)
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
    if a then
      local site = props.setSite('atc', run.atc.lat, run.atc.lon, { x = sp.x - a.x, y = sp.y - a.y })
      site.toward, site.away = { lat = slat, lon = slon }, nil      -- (its road's way: the one leading on to the start)
    end
  end
  if run.stopCtl then
    local b = ctlGame(run.stopCtl)
    if b then
      local site = props.setSite('stop', run.stopCtl.lat, run.stopCtl.lon, { x = b.x - fp.x, y = b.y - fp.y })
      site.toward, site.away = nil, { lat = flat, lon = flon }      -- (its road's way: the one leading on from the finish)
    end
  end
end


-- A place for the car on the road near (x, y), the way dir (game coordinates), fwd m along the road from there (back
-- for fwd < 0): the road map's road (props.roadAt: the one best aligned with dir, within props.SNAP_M) walked along
-- its bends; with no road on the map there, straight along dir. Returns { x, y, z (or nil), dx, dy, road }.
function M.roadSpot(x, y, dir, fwd, toward)
  fwd = fwd or 0
  local e = props.orient(props.roadAt(x, y, dir), toward)
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
      if d and d < t[2] and math.abs(top - d - z0) <= t[1] + 2 then return top - d, true end
    end
  end
  return z0, ray and false or nil      -- (false: looked and found no ground near z0; nil: no ray to look with)
end
M.groundNear = groundNear     -- (the self-test puts the car down with it)


-- The game's traffic and parked cars out of the way for the stage: their systems' active amounts set to 0 (the cars
-- pooled away, out of sight), as BeamNG.Earth itself does over a teleport (navgraph.lua / parking.lua onTeleport), and
-- the player's amounts back at the tidy-up. BeamNG.Earth's adaptive traffic reads a 0 set by someone else as traffic
-- off and leaves it alone until the amount changes again. (Not the missions' freezeState: on BeamNG.Earth it drops the
-- parking system's sites, which only BeamNG.Earth sets, so the parked cars came back unmanaged: review 2026-11-12.)
local function systems()
  local gt, gp = rawget(_G, 'gameplay_traffic'), rawget(_G, 'gameplay_parking')
  local out = {}
  if gt and gt.setActiveAmount and gt.getTrafficVars and gt.getState and gt.getState() == 'on' then
    out.traffic = { set = gt.setActiveAmount, get = function() return (gt.getTrafficVars() or {}).activeAmount end }
  end
  if gp and gp.setActiveAmount and gp.getParkingVars and gp.getState and gp.getState() then
    out.parking = { set = gp.setActiveAmount, get = function() return (gp.getParkingVars() or {}).activeAmount end }
  end
  return out
end

-- Held, not set once: each TRAFFIC_HOLD_S until the tidy-up, any system showing cars again is set back to 0. BeamNG.Earth
-- holds its parked cars at 0 over a teleport and puts its amount back once the place is built, and starts its parking
-- only once it knows the place's driveways: at the check-in either can still be to come, and the parked cars came back
-- at Maryhill's start (in game, 2026-11-13). The first amount seen that is not 0 is the player's, given back after.
local function trafficHold()
  local stash = run and run.trafficStash
  if not stash then return end
  for name, s in pairs(systems()) do
    local ok, cur = pcall(s.get)
    -- (0 now: none showing, or BeamNG.Earth holding them over a teleport: looked at again next time)
    if ok and cur ~= nil and cur ~= 0 then
      if pcall(s.set, 0) and stash[name] == nil then
        stash[name] = cur
        log('I', logTag, (name == 'parking' and 'parked cars' or 'traffic') .. ' out of the way for the stage')
      end
    end
  end
  run.checks.trafficHidden = (stash.traffic and 'traffic ' or '') .. (stash.parking and 'parked cars' or '')
end

local function trafficOff()
  if not run or run.trafficStash then return end
  run.trafficStash, run.trafficHoldT = {}, 0
  trafficHold()
end

local function trafficOn()
  local stash = run and run.trafficStash
  if not stash then return end
  run.trafficStash = nil
  local sys = systems()
  for name, amount in pairs(stash) do
    local s = sys[name]
    -- (only where it is still our 0: an amount the player or BeamNG.Earth changed since is theirs)
    if s then
      local ok, cur = pcall(s.get)
      if ok and cur == 0 then pcall(s.set, amount) end
    end
  end
end
M._trafficOff = function() trafficOff() end

-- The car on the start line, facing the stage (on the ground there: a ray down from the line's height).
local function toStartLine(veh)
  local dir, s = aheadDir(run.line, run.cum, run.startM)
  local l = math.sqrt(dir.x * dir.x + dir.y * dir.y)
  local pos = { x = s.x - dir.x / l * M.CAR_BEHIND_LINE_M, y = s.y - dir.y / l * M.CAR_BEHIND_LINE_M }
  pos.z = groundNear(pos.x, pos.y, s.z or 0) + 1.0
  M.placeCar(veh, pos, dir)
end

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
    local d2a = p and ((p.x - a.x) ^ 2 + (p.y - a.y) ^ 2)
    local near = p and not run.teleported and d2a <= M.NO_SET_DOWN_M ^ 2 and d2a > M.DRIVEN_THERE_MIN_M ^ 2
    if near then
      -- (driven here, e.g. by Route to start: left where it is)
      run.checks.atcSetDown = 'driven there'
    else
      local spot = M.roadSpot(a.x, a.y, { x = sp.x - a.x, y = sp.y - a.y }, -M.CAR_BEFORE_ATC_M, sp)
      local z, hit = groundNear(spot.x, spot.y, spot.z or p.z)
      -- (a road from the place before the teleport, its road map not yet rebuilt here: its height is not the ground's)
      if spot.road and hit == false then
        spot = M.roadSpot(a.x, a.y, { x = sp.x - a.x, y = sp.y - a.y }, 0, sp)
        spot.road = false
        z = groundNear(a.x, a.y, p.z)
        spot.x, spot.y = a.x - spot.dx * M.CAR_BEFORE_ATC_M, a.y - spot.dy * M.CAR_BEFORE_ATC_M
      end
      spot.z = z + 1.0
      M.placeCar(veh, spot, { x = spot.dx, y = spot.dy, z = 0 })
      run.checks.atcSetDown = spot.road and 'on the road map' or 'no road on the map there'
    end
    setState('toAtc')
    say('Drive to the time control and stop at its red board.', 6, 'info', run.stage.name)
  else
    toStartLine(veh)
    setState('toStart')
  end
  rallyA.resync()
  layoutOn()
end

local resultsUpdate      -- (below)

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
-- near: how close to the control's point (0 at the zone's edge, 1 at the board / the start line): the brake eases in
-- with it, from nothing at the edge to BRAKE_LEVEL at the board, so the player can roll right up to the boards and
-- tent (the user, 2026-11-12: the full brake at the edge stopped the car short of them). It never eases off again
-- in the zone (a car past the board keeps the full brake).
local function zone(inZone, dt, keepHeld, near)
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
  -- (setting zoneBrake off: no brake, stopping in the zone still counts)
  if settings.get('zoneBrake') == false then return 'moving' end
  local want = M.BRAKE_LEVEL * math.max(0, math.min(1, near or 1))
  z.level = math.max(z.level or 0, want)
  vehCtl(veh, 'zone', z.level)
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
  local zs = zone(d <= M.CONTROL_RADIUS_M, dt, false, 1 - d / M.CONTROL_RADIUS_M)
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
    say(string.format('Your start time: %s. Move up to the start line.', M.formatClock(run.startAt)), 8, 'success',
      'Checked in ' .. M.formatClock(now))
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
      say('You drove past the time control.', 5, 'warning', string.format('Time control missed: +%d s', M.MISSED_TC_PENALTY_S))
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
    if not run.overLine then say('Back up behind the start line.', 3, 'warning') end
    run.overLine = true
    return
  end
  run.overLine = false
  local zs = zone(along >= run.startM - M.START_ZONE_BEFORE_M and along <= run.startM + 3 and off <= M.START_ZONE_OFF_M, dt,
    true, 1 - (run.startM - along) / M.START_ZONE_BEFORE_M)
  if zs == 'stopped' then
    routeOff()
    run.staged = p              -- (where it stopped: moving away from here before GO is a jump start)
    trafficOff()                -- (a stage with no ATC: here; else already at the check-in)
    local now = M.clock()
    if not run.startAt and run.missedAtc then
      -- the ATC driven past: a start time as if checked in here, and the penalty
      run.startAt = math.ceil((now + M.START_GAP_S) / 30) * 30
      say('Start time ' .. M.formatClock(run.startAt) .. '. Wait for it.', 5, 'info')
    elseif not run.startAt then
      run.startAt = now + M.NO_ATC_START_S
    elseif now > run.startAt then
      -- late at the start: the next half minute, and a penalty for each minute (or part) late
      local newStart = math.ceil((now + M.LATE_GAP_S) / 30) * 30
      local mins = math.max(1, math.ceil((now - run.startAt) / 60))
      run.latePenalty = mins * M.LATE_PENALTY_S
      run.checks.lateMinutes = mins
      say('New start time ' .. M.formatClock(newStart) .. '.', 6, 'warning',
        string.format('Late at the start: +%d s', run.latePenalty))
      run.startAt = newStart
      rallyA.systemNote('rescheduled')
    else
      say('Start time ' .. M.formatClock(run.startAt) .. '. Wait for your minute' ..
        (run.startAt - M.clock() > M.SKIP_TO_S + 10 and ' (Interact, Shift+E: skip the wait).' or '.'), 5, 'info')
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
    run.jumpStartAt = M.clock()
    rallyA.systemNote('falseStart')
    log('I', logTag, 'jump start: +' .. M.JUMP_START_PENALTY_S .. ' s')
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
    rallyA.systemNote('countdown' .. n)       -- (the numeral on screen: the HUD's, hudFrame show.bigCount)
  end
  if left <= 0 then
    zoneRelease()              -- (the car let go in the frame of the GO call)
    rallyA.notesOn(true)       -- (the stage's notes from GO only)
    rallyA.systemNote('countdowngo')        -- (GO on screen: the HUD's, hudFrame show.go)
    -- (the first note is the engine's own: its 'immediate' note, read as the car pulls away. Calling it ourselves and
    -- marking it called froze the engine's step to the next note, which only moves on when it plays one itself.)
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
  local p, veh = carPos()
  if not p then return end
  props.update(p, earth.toGame)
  local along, off = progress(p)
  run.along, run.off = along, off
  if off > run.checks.maxOffM then run.checks.maxOffM = off end
  -- off route (a wrong turn): on beyond OFF_ROUTE_M, off again within OFF_ROUTE_CLEAR_M; the way back to the line (its
  -- point level with the car) against the car's heading, for the HUD's arrow
  local onOff, clearOff = M.OFF_ROUTE_ON_ROAD_M, M.OFF_ROUTE_ON_ROAD_CLEAR_M
  local pt = run.line[geo.segAt(run.cum, along)]
  if pt and pt.gap then onOff, clearOff = M.OFF_ROUTE_M, M.OFF_ROUTE_CLEAR_M end
  local wasOff = run.offRoute == true
  if off > onOff then run.offRoute = true elseif off <= clearOff then run.offRoute = false end
  -- (logged on each change: in game, "not detected" told apart from "not shown")
  if (run.offRoute == true) ~= wasOff then
    log('I', logTag, string.format('%s (%.0f m from the stage line at %.0f m; threshold %d m%s)',
      run.offRoute and 'off route' or 'back on route', off, along - (run.startM or 0), run.offRoute and onOff or clearOff,
      pt and pt.gap and ', no road on the map here' or ''))
  end
  if run.offRoute then
    local back = geo.pointAt(run.line, run.cum, along)
    local okD, d = pcall(function() return veh:getDirectionVector() end)
    run.backBearing = okD and d and hudFrame.relBearing({ x = d.x, y = d.y }, p, back) or nil
  else
    run.backBearing = nil
  end
  if along >= run.finishM and off <= (run.finishInGap and M.FINISH_OFF_GAP_M or M.FINISH_OFF_M) then
    sound(M.SOUND_FINISH)
    rallyA.notesOn(false)        -- (the stage is over: no more calls on the way to the stop control or after)
    run.offRoute, run.backBearing = false, nil
    run.stageTime = run.clock
    local resetPen = (run.resets or 0) * M.RESET_PENALTY_S
    run.penalty = (run.jumpStart and M.JUMP_START_PENALTY_S or 0) + (run.latePenalty or 0)
      + (run.missedAtc and M.MISSED_TC_PENALTY_S or 0) + resetPen
    local time = run.clock + run.penalty
    local checks = run.checks
    run.bestBefore = events.best(run.event.id, run.stage.id)      -- (the best before this run: the HUD's difference)
    local best = events.addResult(run.event.id, run.stage.id, { finished = true, timeS = time, stageS = run.clock,
      penaltyS = run.penalty, jumpStart = run.jumpStart == true, lateMinutes = checks.lateMinutes,
      missedAtc = run.missedAtc == true, resets = run.resets or 0, resetPenaltyS = resetPen, line = checks.line,
      startAt = M.formatClock(run.startAt), date = os.date('!%Y-%m-%dT%H:%M:%SZ'), checks = checks })
    run.finalTime, run.best = time, best
    run.sinceFinish = 0
    log('I', logTag, 'run checks: ' .. dumps(checks))
    local title = string.format('%s: %s', run.stage.name, M.formatTime(time))
    local text = (run.bestBefore == nil and 'Your first time on this stage.') or
      (time < run.bestBefore and string.format('A new best (%.1f s faster).', run.bestBefore - time)) or
      ('Best ' .. M.formatTime(run.bestBefore) .. '.')
    if run.stopCtl then
      setState('toStop')
      say(text .. ' Drive on to the stop control and stop at it.', 8, 'success', title)
    else
      say(text, 8, 'success', title)
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
  local zs = zone(d <= M.STOP_CONTROL_RADIUS_M, dt, false, 1 - d / M.STOP_CONTROL_RADIUS_M)
  if zs == 'stopped' then
    routeOff()
    run.checks.stopControl = 'stopped ' .. M.formatClock(M.clock())
  elseif zs == 'done' then
    M.wrapUp()
  end
end

local tidy        -- (below)

-- The results card (the HUD's, at the stop control; at the flying finish without one): open from the stage's end until
-- the player picks Next stage / Retry / Rally menu, drives RESULTS_CLOSE_M on from where the car came to rest, or
-- RESULTS_TIMEOUT_S passes. The stage layout (where the card is) stays until then.
function M.closeResults()
  if not (run and run.resultsOpen) then return end
  run.resultsOpen = false
  if run.state == 'finished' and not run.tidyIn then layoutOff() end
end
resultsUpdate = function(dt)
  run.resultsT = (run.resultsT or 0) + dt
  if run.resultsT > M.RESULTS_TIMEOUT_S then M.closeResults() return end
  local p = carPos()
  if not p then return end
  if not run.restPos then
    if speed() < M.STOPPED_MS then run.restPos = p end
  elseif geo.dist2d(p, run.restPos) > M.RESULTS_CLOSE_M then
    M.closeResults()
  end
end

-- Every frame (main.lua).
function M.update(dtReal, dtSim)
  camUpdate(dtReal or 0)
  if not run then return end
  run.realT = (run.realT or 0) + (dtReal or 0)
  if run.sinceFinish then run.sinceFinish = run.sinceFinish + (dtReal or 0) end
  if run.resultsOpen then resultsUpdate(dtReal or 0) end
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
  -- the stage layout held while the run has it on: a car reloaded (Ctrl+R) or replaced mid-stage put the game's own
  -- layout back, and the progress bar, the finish time and the results card were gone (in game, 2026-11-13)
  -- Only over the plain driving layouts (holdOver): the radial menu, the garage, photo mode keep theirs.
  if run.oldLayout then
    -- (held, not set once: the strips' apps say "gone" as the layout swap destroys them)
    if run.stripsHeld then earth.holdStrips(true) end
    if run.layoutCheckIn then
      run.layoutCheckIn = run.layoutCheckIn - (dtReal or 0)
      if run.layoutCheckIn <= 0 then run.layoutCheckIn = nil pcall(logLayout) end
    end
    run.layoutHoldT = (run.layoutHoldT or 0) + (dtReal or 0)
    if run.layoutHoldT >= M.LAYOUT_HOLD_S then
      run.layoutHoldT = 0
      local gs = rawget(_G, 'core_gamestate')
      local cur = stateLayout()
      if M.holdOver(cur, run.oldLayout) and gs and gs.setGameState then
        pcall(gs.setGameState, nil, M.STAGE_LAYOUT)
        run.layoutCheckIn = M.LAYOUT_CHECK_S
        run.layoutLeft = nil
        log('I', logTag, 'stage layout back on (' .. tostring(cur) .. ' had been put on)')
      elseif cur ~= M.STAGE_LAYOUT and cur ~= run.layoutLeft then
        run.layoutLeft = cur
        log('I', logTag, 'stage layout: the game put ' .. tostring(cur) .. ' on; left to it')
      elseif cur == M.STAGE_LAYOUT then
        run.layoutLeft = nil
      end
    end
  end
  if run.trafficStash then
    run.trafficHoldT = (run.trafficHoldT or 0) + (dtReal or 0)
    if run.trafficHoldT >= M.TRAFFIC_HOLD_S then run.trafficHoldT = 0 trafficHold() end
  end
  if s == 'finished' and run.tidyIn then
    run.tidyIn = run.tidyIn - (dtReal or 0)
    if run.tidyIn <= 0 then run.tidyIn = nil tidy(run.resultsOpen) end
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
-- (keepLayout: the stage layout left on, for the results card)
tidy = function(keepLayout)
  trafficOn()
  earth.originMoved()
  zoneRelease()
  routeOff()
  M.release()
  if not keepLayout then layoutOff() end
  props.clear()
  startClockOff()
  rallyA.unload()
end

-- The stage done (at the flying finish without a stop control, else at the stop control): its result kept, the rest
-- tidied away so the player drives on in plain BeamNG.Earth.
function M.wrapUp()
  if not run then return end
  setState('finished')
  run.resultsOpen = run.finalTime ~= nil
  run.resultsT, run.restPos = 0, nil
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
  if not quiet and run.state ~= 'finished' then say('Run stopped.', 4, 'info') end
  run = nil
end

-- Where a stage's run begins: its ATC when it has one of its own (near enough the start), else its start.
-- Returns lat, lon, what ('ATC' / 'start').
function M.arrivalPoint(stage)
  local ctl = stage.controls or {}
  local st = ctl.start or (stage.line and stage.line[1] and { lat = stage.line[1][1], lon = stage.line[1][2] })
  if not st then return nil end
  if ctl.atc and settings.get('timeControls') ~= 'quick' then
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

-- A reset by the player (the game's trackVehReset hook, from main.lua: once a press of reset, recover or the radial
-- menu's reset, as the game's own modes count them; not onVehicleResetted, which a held recover (the rewind) fires
-- when pressed and again when let go: two resets for one, in game 2026-11-13): the player's car reset during the
-- timed stage costs RESET_PENALTY_S each (setting resetPenalty), counted in the result. Not one heard again within
-- RESET_DEBOUNCE_S, nor one just after the world's origin moved (BeamNG.Earth moving the car is not the player's).
function M.onReset(vid)
  if not (run and run.state == 'running') then return false end
  if settings.get('resetPenalty') == false then return false end
  local _, veh = carPos()
  if not veh then return false end
  local okI, id = pcall(function() return veh:getID() end)
  if okI and id ~= nil and vid ~= nil and id ~= vid then return false end
  local t = run.realT or 0
  if earth.rebasing() or (run.movedAt and t - run.movedAt < M.RESET_AFTER_MOVE_S) then return false end
  if run.resetAt and t - run.resetAt < M.RESET_DEBOUNCE_S then return false end
  run.resetAt = t
  run.resets = (run.resets or 0) + 1
  say(string.format('%d reset%s on this stage.', run.resets, run.resets == 1 and '' or 's'), 3, 'warning',
    string.format('Reset: +%d s', M.RESET_PENALTY_S))
  return true
end

-- Recovery, as rally games have it (the player's ask, 2026-11-13): the car moved as the game's own radial-menu "flip
-- upright" moves it (spawn.safeTeleport, the damage kept), not reset or rewound.
local function recoverTo(veh, pos, dir)
  local sp = rawget(_G, 'spawn')
  local l = math.sqrt(dir.x * dir.x + dir.y * dir.y)
  if l < 1e-6 then return false end
  local d = vec3(dir.x / l, dir.y / l, 0)
  if sp and sp.safeTeleport then
    local ok = pcall(sp.safeTeleport, veh, vec3(pos.x, pos.y, pos.z), quatFromDir(d), nil, nil, nil, nil, false)
    if ok then M.resetCameraSoon() return true end
  end
  return M.placeCar(veh, pos, d)
end

-- Back on the road: the car on the stage line where it had got to, facing on along the stage. A reset (RESET_PENALTY_S
-- on the timed stage, setting resetPenalty). On the way to the start and the stop control too (no penalty there).
function M.backOnRoad()
  if not (run and run.line and (run.state == 'toAtc' or run.state == 'toStart' or run.state == 'running'
    or run.state == 'toStop')) then
    say('Back on the road: during a stage only.', 3, 'info')
    return false
  end
  local p, veh = carPos()
  if not p then return false end
  local along = run.along or select(1, progress(p))
  local dir, at = aheadDir(run.line, run.cum, along)
  local pos = { x = at.x, y = at.y }
  pos.z = groundNear(pos.x, pos.y, at.z or p.z) + M.RECOVER_UP_M
  if not recoverTo(veh, pos, dir) then return false end
  if run.state == 'running' then M.onReset(nil) end
  run.offRoute, run.backBearing = false, nil
  return true
end

-- Flip upright: the car turned back onto its wheels where it is, facing the way it faced. No penalty: it gains
-- nothing (the time lost on its roof is the cost), as a push back over by the marshals.
function M.flipUpright()
  local p, veh = carPos()
  if not p then return false end
  local okD, d = pcall(function() return veh:getDirectionVector() end)
  if not (okD and d) then return false end
  local pos = { x = p.x, y = p.y }
  pos.z = groundNear(pos.x, pos.y, p.z) + M.RECOVER_UP_M
  if not recoverTo(veh, pos, { x = d.x, y = d.y }) then return false end
  pcall(extensions.hook, 'onVehicleFlippedUpright', veh:getID())
  return true
end

-- What the screen shows now: the game's rally apps' stream and ours (hudFrame.lua). main.lua queues them.
-- Returns rallyLoop (nil: leave that stream alone, the game's own rally mode is running), earthRally.
function M.uiFrame()
  return hudFrame.build(run, {
    now = M.clock() or 0, speed = run and speed() or 0, canSkip = M.canSkip(), units = settings.get('units'),
    uiHidden = M.uiHidden, place = earth.place(), earthBanner = earth.earthBanner(), loading = earth.loading(),
    noRallyLoop = extensions and extensions.isExtensionLoaded and extensions.isExtensionLoaded('gameplay_rallyLoop')
      or false,
    c = { stoppedMs = M.STOPPED_MS, startZoneBeforeM = M.START_ZONE_BEFORE_M, stopRadiusM = M.STOP_CONTROL_RADIUS_M,
          jumpStartS = M.JUMP_START_PENALTY_S, resetS = M.RESET_PENALTY_S, missedAtcS = M.MISSED_TC_PENALTY_S },
  })
end

-- The results card's buttons: 'next' (the rally's next stage), 'retry' (this one again), 'menu' / 'close' (the card
-- closed; main.lua opens the menu). Returns ok, why.
function M.resultsAction(what)
  if not run then return false, 'no run' end
  local ev, st = run.event, run.stage
  if what == 'next' then
    local nx = run.nextStage
    if not nx then return false, 'this was the last stage' end
    for _, s in ipairs(ev.stages or {}) do
      if s.id == nx.id then return M.start(ev, s) end
    end
    return false, 'the next stage is not in the rally'
  elseif what == 'retry' then
    return M.start(ev, st)
  end
  M.closeResults()
  return true
end

function M.formatTime(s)
  if not s then return '--:--.-' end
  local m = math.floor(s / 60)
  return string.format('%d:%04.1f', m, s - m * 60)
end

return M
