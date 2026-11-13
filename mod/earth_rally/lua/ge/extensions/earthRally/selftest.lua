-- earthRally/selftest: the in-game self-test (developer tool; no effect on play unless asked). It runs a real stage
-- end to end with nobody at the wheel and writes what it found to a report, so a release can be checked without a
-- play-test (1.2.2: the install script wrote an old stage layout over the mod's and no HUD app showed; only a human
-- noticed).
--
-- Started by:
--   the request file /earthRally/selftest/request.json in the user folder (tools/selftest.py writes it before it starts
--     the game: { event, stage, token, quit, loadLevel, budgetS }); read and deleted when the mod loads (main.lua), so
--     it runs once
--   the console, in the BeamNG.Earth level: earthRally_main.selfTest('otr24', 'maryhill-up')
--
-- What it does (phases):
--   boot      a few seconds for the game to settle; the BeamNG.Earth level loaded when the game is not in it
--   world     until BeamNG.Earth is in its world, ready, with a car (WORLD_BUDGET_S)
--   prep      the run started (runner.start): travel, origin moved, stage built, car placed (PREP_BUDGET_S)
--   liaison   the car put at the ATC (checked in), then on the start line; the wait skipped (runner.skipCountdown, the
--             Interact key's skip) (LIAISON_BUDGET_S)
--   stage     the game's AI drives the stage line (ai.driveUsingPath with a script: the line itself, no road graph
--             needed); a stall (no progress for STALL_S) fails. Once OFFROUTE_AT_M into the stage:
--   offroute  the car moved OFFROUTE_M off the line (off route and the HUD's card expected), Backspace's action
--             (back on the road: on the line, one more reset), then the car turned on its roof and Shift+Backspace's
--             (flip upright: on its wheels, no reset); the AI drives on
--   stop      at the flying finish: the car put at the stop control (the run finishes there)
--   results   the results card's show flag expected in the HUD stream
--   done      the run closed, the stage's times put back as they were, the report written; the game quit when asked
-- Throughout: the stage layout on screen with every stage app (LAYOUT_CHECK_S after it is put on), both HUD streams
-- with the flags each run state should send (frameProblem), errors logged (log 'E') collected.
--
-- Report: /earthRally/selftest/report-<time>.json, and one log line "self-test: PASS|FAIL ...".
-- Its pure parts (frameProblem, evaluateStreams, aiScript, offsetPoint, summary) are tested offline
-- (tests/test_selftest.lua), the phases against a stand-in game; the `game` seam below is what only the game can do.
local geo = require('earthRally/geo')
local runner = require('earthRally/runner')
local events = require('earthRally/events')
local earth = require('earthRally/earthAdapter')
local settings = require('earthRally/settings')
local props = require('earthRally/props')
local hudFrame = require('earthRally/hudFrame')

local M = {}
local logTag = 'earthRally'

M.DIR = '/earthRally/selftest/'
M.REQUEST = M.DIR .. 'request.json'
M.LEVEL = 'beamng_earth'
M.BOOT_S = 8                -- after the request is read (the mod loads at the main menu): the menu settles first
M.WORLD_BUDGET_S = 420      -- the level and BeamNG.Earth's world loaded, a car in it
M.WORLD_SETTLE_S = 5
M.PREP_BUDGET_S = 300       -- travel (the world at the ATC), origin, build, place
M.LIAISON_BUDGET_S = 180    -- ATC check-in, start line, the skipped wait, GO
M.STALL_S = 60              -- on the stage: no STALL_M of progress for this long is a stall
M.STALL_M = 25
M.STOP_BUDGET_S = 90
M.RESULTS_WAIT_S = hudFrame.FINISH_CARD_S + 6
M.DEFAULT_BUDGET_S = 1500   -- the whole test
M.LAYOUT_CHECK_S = runner.LAYOUT_CHECK_S + 1.5
M.OFFROUTE_M = 30           -- the forced off route: this far off the line (75 where the line is the organisers')
M.OFFROUTE_GAP_M = 75
M.OFFROUTE_AT_M = 800       -- ... this far into the stage (a third of it on a short one)
M.OFFROUTE_WAIT_S = 4
M.BACK_ON_LINE_M = 6        -- back on the road: within this of the line
M.UPRIGHT_Z = 0.7           -- the car's up vector's height on its wheels (on its roof: below 0)
M.AI_STEP_M = 8             -- the AI's script: a point this often along the line
M.AI_SPEED_MS = 22          -- at most (80 km/h): finishing matters, not the time
M.AI_AGGRESSION = 0.45
M.AI_PAST_FINISH_M = 150
M.MAX_ERRORS = 60

------------------------------------------------------------------------------------------ pure parts

-- A problem with one frame of the two HUD streams for the run state it says (ours.state), or nil when the frame is
-- what that state should send (hudFrame.build): the game's rally apps' stream (rl; nil: not sent) and ours.
function M.frameProblem(rl, ours)
  if type(ours) ~= 'table' then return 'no earthRally frame' end
  local s, show = ours.state, type(ours.show) == 'table' and ours.show or {}
  local needRl = s == 'toStart' or s == 'waitStart' or s == 'running' or s == 'toStop'
  if needRl and type(rl) ~= 'table' then
    return 'rallyLoop not sent (the game\'s own rally mode, gameplay_rallyLoop, loaded?)'
  end
  if s == 'toAtc' then
    if not show.next then return 'toAtc: show.next missing' end
    if ours.control ~= 'atc' then return 'toAtc: control ' .. tostring(ours.control) end
  elseif s == 'toStart' then
    if rl.activeState ~= 'vehicleProximity' then return 'toStart: rallyLoop activeState ' .. tostring(rl.activeState) end
    if ours.control ~= 'start' then return 'toStart: control ' .. tostring(ours.control) end
  elseif s == 'waitStart' then
    if rl.activeState ~= 'countdown' then return 'waitStart: rallyLoop activeState ' .. tostring(rl.activeState) end
    if type(rl.countdownData) ~= 'table' then return 'waitStart: no countdownData' end
  elseif s == 'running' then
    if rl.activeState ~= 'stageActive' then return 'running: rallyLoop activeState ' .. tostring(rl.activeState) end
    if rl.showStageApps ~= true then return 'running: showStageApps not true' end
    if not (type(rl.uiColors) == 'table' and rl.uiColors.theme) then return 'running: no uiColors.theme (the stage apps hide)' end
    if not (show.km or show.offRoute) then return 'running: neither show.km nor show.offRoute' end
    if show.offRoute and not show.dimNotes then return 'running: off route without show.dimNotes' end
  elseif s == 'toStop' then
    if rl.showStageApps ~= true then return 'toStop: showStageApps not true' end
    if rl.activeState ~= 'vehicleProximity' then return 'toStop: rallyLoop activeState ' .. tostring(rl.activeState) end
    if ours.control ~= 'stop' then return 'toStop: control ' .. tostring(ours.control) end
  end
  return nil
end

-- The stream frames seen, per run state: { [state] = { frames, bad, problem (the first), shows = { key = n } } }.
function M.newStreamLog() return {} end
function M.observeFrame(slog, rl, ours)
  local s = type(ours) == 'table' and tostring(ours.state) or 'none'
  local e = slog[s]
  if not e then e = { frames = 0, bad = 0, shows = {} } slog[s] = e end
  e.frames = e.frames + 1
  local p = M.frameProblem(rl, ours)
  if p then
    e.bad = e.bad + 1
    e.problem = e.problem or p
  end
  for k, v in pairs(type(ours) == 'table' and type(ours.show) == 'table' and ours.show or {}) do
    if v then e.shows[k] = (e.shows[k] or 0) + 1 end
  end
  return p
end

-- One check per run state the stage went through: { { name, ok, detail }... }. statesReached: the states in order.
function M.evaluateStreams(slog, statesReached)
  local out = {}
  for _, s in ipairs(statesReached or {}) do
    if s == 'toAtc' or s == 'toStart' or s == 'waitStart' or s == 'running' or s == 'toStop' then
      local e = slog[s]
      local ok = e ~= nil and e.frames > 0 and e.bad == 0
      local detail = not e and 'no frame sent in this state' or
        string.format('%d frames, %d wrong%s', e.frames, e.bad, e.problem and (': ' .. e.problem) or '')
      out[#out + 1] = { name = 'HUD streams: ' .. s, ok = ok, detail = detail }
    end
  end
  return out
end

-- The AI's path: the line from s0 to s1 every `step` m (x, y, z), starting on s0 (the AI puts the car on its first
-- point). line, cum: runner's run.line / run.cum (game coordinates now).
function M.aiScript(line, cum, s0, s1, step)
  step = step or M.AI_STEP_M
  local total = cum[#cum]
  s1 = math.min(s1, total)
  local out = {}
  local s = math.max(0, s0)
  while s < s1 do
    local p = geo.pointAt(line, cum, s)
    out[#out + 1] = { x = p.x, y = p.y, z = p.z or 0 }
    s = s + step
  end
  local p = geo.pointAt(line, cum, s1)
  out[#out + 1] = { x = p.x, y = p.y, z = p.z or 0 }
  return out
end

-- A point `off` m to the right of the line at s (left for off < 0), and the line's direction there.
function M.offsetPoint(line, cum, s, off)
  local p, dir = geo.pointAt(line, cum, s)
  return { x = p.x + dir.y * off, y = p.y - dir.x * off, z = p.z }, dir
end

-- The report's verdict: ok (every check passed and nothing stopped the test), passed, failed.
function M.summary(checks, abortReason)
  local passed, failed = 0, 0
  for _, c in ipairs(checks) do if c.ok then passed = passed + 1 else failed = failed + 1 end end
  return failed == 0 and abortReason == nil and passed > 0, passed, failed
end

------------------------------------------------------------------------------------------ the game seam

-- What only the game does (replaced by fakes in tests/test_selftest.lua).
M.game = {}
function M.game.vehicle() return getPlayerVehicle and getPlayerVehicle(0) or nil end
function M.game.pos(veh) local p = veh:getPosition() return { x = p.x, y = p.y, z = p.z } end
function M.game.speed() local p = earth.pose() return p and p.speed or 0 end
function M.game.ground(x, y, z0) return runner.groundNear(x, y, z0) end
-- The car put at pos facing dir (game coordinates): on its wheels, or on its roof (upsideDown).
function M.game.place(veh, pos, dir, upsideDown)
  if not upsideDown then return runner.placeCar(veh, pos, dir) end
  local l = math.sqrt(dir.x * dir.x + dir.y * dir.y)
  local q = quatFromEuler(0, 0, math.pi) * quatFromDir(vec3(dir.x / l, dir.y / l, 0), vec3(0, 0, -1))
  veh:setPositionRotation(pos.x, pos.y, pos.z, q.x, q.y, q.z, q.w)
  runner.resetCameraSoon()
  return true
end
-- The height of the car's up vector (1 on its wheels on the flat, -1 on its roof), or nil.
function M.game.upZ(veh)
  local ok, u = pcall(function() return veh:getDirectionVectorUp() end)
  return ok and u and u.z or nil
end
-- The car's own AI along `script` ({ x, y, z }...): the game's driveUsingPath with a script (vehicle/ai.lua: its own
-- path graph from the points, no road map needed; it sets the car on the first point). Speed and aggression first:
-- the script branch keeps the ones set before.
function M.game.driveStart(veh, script)
  local parts = {}
  for i, p in ipairs(script) do parts[i] = string.format('{x=%.2f,y=%.2f,z=%.2f}', p.x, p.y, p.z) end
  local cmd = string.format('ai.setSpeed(%.1f) ai.setSpeedMode("limit") ai.setAggression(%.2f) ai.setAvoidCars("off") '
    .. 'ai.driveUsingPath({script = {%s}})', M.AI_SPEED_MS, M.AI_AGGRESSION, table.concat(parts, ','))
  veh:queueLuaCommand(cmd)
end
function M.game.driveStop(veh, hold)
  veh:queueLuaCommand(hold and 'ai.setMode("stop")' or 'ai.setMode("disabled")')
end
function M.game.layout()
  local ui = rawget(_G, 'ui_appLayouts')
  local ok, cur = pcall(function() return ui and ui.getCurrentLayout and ui.getCurrentLayout() end)
  local gs = rawget(_G, 'core_gamestate')
  local okS, st = pcall(function() return gs and gs.getGameState and gs.getGameState() end)
  return ok and cur or nil, okS and st and st.appLayout or nil
end
function M.game.inLevel()
  local ok, f = pcall(function() return getMissionFilename() end)
  return ok and type(f) == 'string' and f ~= ''
end
function M.game.loadLevel(name)
  local fr = rawget(_G, 'freeroam_freeroam')
  if not fr and extensions and extensions.load then pcall(extensions.load, 'freeroam_freeroam') fr = rawget(_G, 'freeroam_freeroam') end
  if not (fr and fr.startFreeroamByName) then return false, 'no freeroam_freeroam.startFreeroamByName' end
  local ok, err = pcall(fr.startFreeroamByName, name)
  return ok, ok and nil or tostring(err)
end
function M.game.quit() local q = rawget(_G, 'quit') if q then pcall(q) end end
function M.game.removeFile(path) local fs = rawget(_G, 'FS') if fs and fs.removeFile then pcall(fs.removeFile, fs, path) end end
function M.game.date() return os.date('%Y%m%d-%H%M%S'), os.date('!%Y-%m-%dT%H:%M:%SZ') end

------------------------------------------------------------------------------------------ the test

local T = nil           -- the test under way: nil when none

function M.active() return T ~= nil and not T.closed end
function M.current() return T end

local function now() return T and T.t or 0 end

local function check(name, ok, detail)
  T.checks[#T.checks + 1] = { name = name, ok = ok == true, detail = detail ~= nil and tostring(detail) or nil,
    t = math.floor(now() * 10 + 0.5) / 10 }
  log(ok and 'I' or 'W', logTag, string.format('self-test: %s %s%s', ok and 'ok  ' or 'FAIL', name,
    detail ~= nil and (' (' .. tostring(detail) .. ')') or ''))
end
M._check = function(...) return check(...) end

local function phase(p)
  if T.phase then T.timings[T.phase] = math.floor((now() - T.phaseAt) * 10 + 0.5) / 10 end
  T.phase, T.phaseAt, T.step, T.stepAt = p, now(), nil, now()
  log('I', logTag, 'self-test: phase ' .. p)
end
local function step(s) T.step, T.stepAt = s, now() end
local function inStep() return now() - (T.stepAt or 0) end
local function inPhase() return now() - (T.phaseAt or 0) end

local finish        -- (below)
local function fail(why)
  if not T or T.closed then return end
  T.abortReason = T.abortReason or why
  check('the test ran to its end', false, why)
  finish()
end

-- (hooks put in for the test, taken out at its end: the HUD streams seen, errors logged)
local function hooksOn()
  local gh = rawget(_G, 'guihooks')
  if gh and gh.queueStream and not T.origQueue then
    local orig = gh.queueStream
    T.origQueue, T.gh = orig, gh
    gh.queueStream = function(name, data, ...)
      if T and not T.closed then
        local okO, errO = pcall(function()
          if name == 'rallyLoop' then T.pendingRl = data
          elseif name == 'earthRally' then
            M.observeFrame(T.streams, T.pendingRl, data)
            T.lastOurs, T.lastRl = data, T.pendingRl
            if type(data) == 'table' and type(data.show) == 'table' then
              if data.show.offRoute then T.sawOffRouteShow = true end
              if data.show.results then T.sawResultsShow = true end
            end
            T.pendingRl = nil
          end
        end)
        if not okO then T.hookError = tostring(errO) end
      end
      return orig(name, data, ...)
    end
  end
  local lg = rawget(_G, 'log')
  if lg and not T.origLog then
    T.origLog = lg
    rawset(_G, 'log', function(level, tag, msg, ...)
      if level == 'E' and T and not T.closed and #T.errors < M.MAX_ERRORS then
        T.errors[#T.errors + 1] = { t = math.floor(now() * 10 + 0.5) / 10, tag = tostring(tag), msg = tostring(msg) }
      end
      return lg(level, tag, msg, ...)
    end)
  end
end
local function hooksOff()
  if T.origQueue and T.gh then T.gh.queueStream = T.origQueue end
  if T.origLog then rawset(_G, 'log', T.origLog) end
  T.origQueue, T.origLog = nil, nil
end

-- (the stage's times as they were before the test: its time is not the player's)
local function copy(v)
  if type(v) ~= 'table' then return v end
  local out = {}
  for k, x in pairs(v) do out[k] = copy(x) end
  return out
end
local function resultsSnapshot()
  local path = events.RESULTS_DIR .. tostring(T.eventId) .. '__' .. tostring(T.stageId) .. '.json'
  local fs = rawget(_G, 'FS')
  local had = fs and fs.fileExists and fs:fileExists(path)
  T.results = { path = path, had = had == true, data = had and copy(jsonReadFile(path)) or nil }
end
local function resultsRestore()
  local r = T.results
  if not r then return end
  if r.had and r.data then jsonWriteFile(r.path, r.data, true) else M.game.removeFile(r.path) end
  events.forget()
  T.results = nil
end

-- Start a test. opts: { event, stage, token, quit, loadLevel (default true from a request), budgetS, main (the
-- earthRally_main table: Backspace's and Shift+Backspace's actions through it) }. Returns true, or false and why.
function M.start(opts)
  if M.active() then return false, 'a self-test is under way' end
  opts = opts or {}
  if not (opts.event and opts.stage) then return false, 'give an event and a stage id' end
  T = { eventId = opts.event, stageId = opts.stage, token = opts.token, quit = opts.quit == true,
    loadLevel = opts.loadLevel ~= false, budgetS = tonumber(opts.budgetS) or M.DEFAULT_BUDGET_S, main = opts.main,
    t = 0, checks = {}, timings = {}, states = {}, streams = M.newStreamLog(), errors = {}, closed = false }
  local _, iso = M.game.date()
  T.startedAt = iso
  log('I', logTag, string.format('self-test: %s / %s (budget %d s)', T.eventId, T.stageId, T.budgetS))
  phase('boot')
  return true
end

-- Stop the test now (it reports what it found so far as failed).
function M.stop(why) if M.active() then fail(why or 'stopped by hand') end end

local function findStage()
  for _, e in ipairs(events.list(true)) do
    if e.id == T.eventId then
      for _, s in ipairs(e.stages or {}) do if s.id == T.stageId then return e, s end end
      return e, nil
    end
  end
end

local function carAt(veh, pos, dir, lift, upsideDown)
  local z = M.game.ground(pos.x, pos.y, pos.z or M.game.pos(veh).z)
  return M.game.place(veh, { x = pos.x, y = pos.y, z = z + (lift or 1.0) }, { x = dir.x, y = dir.y, z = 0 }, upsideDown)
end

local function driveFrom(r, veh, along)
  local script = M.aiScript(r.line, r.cum, along, r.finishM + M.AI_PAST_FINISH_M)
  if #script < 2 then return false end
  M.game.driveStart(veh, script)
  T.driving = true
  T.progressAt, T.progressM = now(), along
  return true
end

local function stopDriving(veh, hold)
  if T.driving and veh then M.game.driveStop(veh, hold) end
  T.driving = false
end

local function layoutCheck()
  local cur, stateName = M.game.layout()
  local text, missing = runner.layoutReport(stateName, cur)
  local ok = type(cur) == 'table' and cur.type == runner.STAGE_LAYOUT and missing ~= nil and #missing == 0
  check('stage layout on screen with every stage app', ok, text)
end

-- phases ----------------------------------------------------------------------------------

local function stepBoot()
  if inPhase() < M.BOOT_S then return end
  if not earth.check() and not M.game.inLevel() and T.loadLevel then
    local ok, why = M.game.loadLevel(M.LEVEL)
    T.levelLoadAsked = true
    if not ok then fail('could not load the BeamNG.Earth level: ' .. tostring(why)) return end
  end
  phase('world')
end

local function stepWorld(dt)
  local ok = earth.check() and earth.ready() and M.game.vehicle() ~= nil
  T.worldFor = ok and (T.worldFor or 0) + dt or 0
  if T.worldFor >= M.WORLD_SETTLE_S then
    check('BeamNG.Earth world loaded with a car', true, string.format('%.0f s', inPhase()))
    local ev, stage = findStage()
    if not ev then fail('no rally ' .. tostring(T.eventId) .. ' in earthRally/events') return end
    if not stage then fail('no stage ' .. tostring(T.stageId) .. ' in ' .. tostring(T.eventId)) return end
    T.settings = {}
    for _, k in ipairs(settings.ORDER or {}) do T.settings[k] = settings.get(k) end
    hooksOn()
    resultsSnapshot()
    local okS, why = runner.start(ev, stage)
    check('the run starts', okS, why)
    if not okS then fail('runner.start: ' .. tostring(why)) return end
    T.run = runner.current()
    phase('prep')
  elseif inPhase() > M.WORLD_BUDGET_S then
    local why = select(2, earth.check())
    fail(string.format('the world never loaded in %d s (%s)', M.WORLD_BUDGET_S, tostring(why or
      (earth.ready() and 'no car' or 'BeamNG.Earth not ready'))))
  end
end

local function stepPrep()
  local s = runner.state()
  if s == 'toAtc' or s == 'toStart' then
    check('stage built: line, rally engine, car placed', T.run.checks.rallyEngine == 'loaded',
      'rally engine ' .. tostring(T.run.checks.rallyEngine) .. ', line ' .. tostring(T.run.checks.line) ..
      ', corners ' .. tostring(T.run.checks.cornersFound) .. ', notes ' .. tostring(T.run.checks.notesLoaded))
    phase('liaison')
  elseif inPhase() > M.PREP_BUDGET_S then
    fail(string.format('the run stayed in %s for %d s', s, M.PREP_BUDGET_S))
  end
end

local function stepLiaison()
  local r, s = T.run, runner.state()
  local veh = M.game.vehicle()
  if not veh then return end
  if s == 'toAtc' then
    if T.step ~= 'atc' then step('atc') T.placedAtc = nil end
    if not T.placedAtc and inStep() >= 1 then
      -- on the road a few metres before the ATC's boards, facing on to the start
      local ax, ay = earth.toGame(r.atc.lat, r.atc.lon, 0)
      local a = props.sitePoint('atc') or (ax and { x = ax, y = ay })
      local sp = geo.pointAt(r.line, r.cum, r.startM)
      if a then
        local dir = { x = sp.x - a.x, y = sp.y - a.y }
        local spot = runner.roadSpot(a.x, a.y, dir, -6, sp)
        carAt(veh, { x = spot.x, y = spot.y, z = spot.z }, { x = spot.dx, y = spot.dy }, 1.0)
        T.placedAtc = true
      end
    end
    if inStep() > 30 then fail('not checked in at the ATC within 30 s of being put there') end
  elseif s == 'toStart' then
    if T.step ~= 'start' then
      step('start')
      T.placedStart = nil
      if r.atc then check('checked in at the ATC', r.atcTime ~= nil and r.startAt ~= nil, r.checks.atc) end
    end
    if not T.placedStart and inStep() >= 1 then
      local p = geo.pointAt(r.line, r.cum, r.startM - runner.CAR_BEHIND_LINE_M)
      local ahead = geo.pointAt(r.line, r.cum, r.startM + runner.FACE_AHEAD_M)
      carAt(veh, p, { x = ahead.x - p.x, y = ahead.y - p.y }, 1.0)
      T.placedStart = true
    end
    if inStep() > 30 then fail('not held on the start line within 30 s of being put there') end
  elseif s == 'waitStart' then
    if T.step ~= 'wait' then step('wait') T.skipped = nil end
    if not T.skipped and runner.canSkip() then
      T.skipped = runner.skipCountdown()
      check('the start wait skipped (Interact)', T.skipped)
    end
    if inStep() > 90 then fail('no GO within 90 s on the start line') end
  elseif s == 'running' then
    check('GO: the stage clock runs', true, string.format('start %s', runner.formatClock(r.startAt)))
    T.offrouteAt = r.startM + math.min(M.OFFROUTE_AT_M, (r.finishM - r.startM) / 3)
    -- (from where the car stands on the line: the AI sets the car on its path's first point)
    driveFrom(r, veh, (geo.follow(r.line, r.cum, M.game.pos(veh), r.startM, 200, 200, 1e9)))
    phase('stage')
    return
  end
  if inPhase() > M.LIAISON_BUDGET_S then fail(string.format('no GO in %d s (stuck in %s)', M.LIAISON_BUDGET_S, s)) end
end

local function stepStage()
  local r, s = T.run, runner.state()
  local veh = M.game.vehicle()
  if s == 'toStop' or s == 'finished' then
    stopDriving(veh, true)
    check('flying finish reached', r.finalTime ~= nil, r.finalTime and runner.formatTime(r.finalTime))
    phase(s == 'toStop' and 'stop' or 'results')
    return
  end
  if s ~= 'running' or not veh then fail('the run left the stage: ' .. tostring(s) .. ' ' .. tostring(r.error or '')) return end
  local along = r.along or r.startM
  if along > (T.progressM or 0) + M.STALL_M then T.progressM, T.progressAt = along, now() end
  if now() - (T.progressAt or now()) > M.STALL_S then
    fail(string.format('the car stalled %.0f m into the stage (no progress for %d s: the AI stuck?)', along - r.startM,
      M.STALL_S))
    return
  end
  if r.offRoute and not T.forcedOff then T.strayOffRoute = (T.strayOffRoute or 0) + 1 end
  if not T.offrouteDone and along >= T.offrouteAt then phase('offroute') end
end

local function stepOffroute()
  local r = T.run
  local veh = M.game.vehicle()
  if runner.state() ~= 'running' or not veh then fail('the run left the stage during the recovery checks') return end
  local st = T.step
  if not st then
    stopDriving(veh, true)
    step('settle')
  elseif st == 'settle' and inStep() >= 1.5 then
    local along = r.along or r.startM
    local pt = r.line[geo.segAt(r.cum, along)]
    local off = (pt and pt.gap) and M.OFFROUTE_GAP_M or M.OFFROUTE_M
    local p, dir = M.offsetPoint(r.line, r.cum, along, off)
    T.forcedOff, T.offAlong = true, along
    carAt(veh, p, dir, 1.0)
    step('off')
  elseif st == 'off' then
    if r.offRoute and T.lastOurs and T.lastOurs.state == 'running' and T.lastOurs.show and T.lastOurs.show.offRoute then
      check('forced off route: offRoute set', true, string.format('%.0f m off', r.off or -1))
      check('off route on the HUD (show.offRoute, notes dimmed)', T.lastOurs.show.dimNotes == true)
      step('back')
    elseif inStep() > M.OFFROUTE_WAIT_S then
      check('forced off route: offRoute set', r.offRoute == true, string.format('%.0f m off', r.off or -1))
      check('off route on the HUD (show.offRoute, notes dimmed)', T.sawOffRouteShow == true, 'not in the earthRally stream')
      step('back')
    end
  elseif st == 'back' then
    T.resetsBefore = r.resets or 0
    local fn = T.main and T.main.backOnRoad or runner.backOnRoad
    T.backOk = fn() == true
    step('backCheck')
  elseif st == 'backCheck' and inStep() >= 1.5 then
    local _, off = geo.follow(r.line, r.cum, M.game.pos(veh), T.offAlong, 200, 200, 1e9)
    local penalty = T.settings and T.settings.resetPenalty ~= false
    local want = T.resetsBefore + (penalty and 1 or 0)
    check('Back on the road (Backspace): on the line, off route cleared', T.backOk and not r.offRoute and
      off <= M.BACK_ON_LINE_M, string.format('%.1f m from the line', off))
    check('Back on the road: ' .. (penalty and 'one reset added' or 'no reset (reset penalty off)'), (r.resets or 0) == want,
      string.format('resets %d -> %d', T.resetsBefore, r.resets or 0))
    -- on its roof where it is, then flip upright
    local p = M.game.pos(veh)
    local _, dir = geo.pointAt(r.line, r.cum, r.along or T.offAlong)
    carAt(veh, p, dir, 0.8, true)
    step('roof')
  elseif st == 'roof' and inStep() >= 2.5 then
    T.roofUp = M.game.upZ(veh)
    T.resetsBefore = r.resets or 0
    local fn = T.main and T.main.flipUpright or runner.flipUpright
    T.flipOk = fn() == true
    step('flipCheck')
  elseif st == 'flipCheck' and inStep() >= 2.5 then
    local up = M.game.upZ(veh)
    check('Flip upright (Shift+Backspace): on its wheels, no reset', T.flipOk and up ~= nil and up >= M.UPRIGHT_Z and
      (r.resets or 0) == T.resetsBefore, string.format('up %.2f on the roof, %.2f after; resets %d -> %d',
      T.roofUp or -9, up or -9, T.resetsBefore, r.resets or 0))
    T.offrouteDone, T.forcedOff = true, false
    -- on along the stage from where the car stands
    local along = select(1, geo.follow(r.line, r.cum, M.game.pos(veh), r.along or T.offAlong, 200, 200, 1e9))
    driveFrom(r, veh, along)
    phase('stage')
  end
end

local function stepStop()
  local r, s = T.run, runner.state()
  local veh = M.game.vehicle()
  if s == 'finished' then phase('results') return end
  if not veh then return end
  if T.step ~= 'placed' and inPhase() >= 2 then
    local bx, by = earth.toGame(r.stopCtl.lat, r.stopCtl.lon, 0)
    local b = props.sitePoint('stop') or (bx and { x = bx, y = by })
    local fp = geo.pointAt(r.line, r.cum, r.finishM)
    if b then
      local spot = runner.roadSpot(b.x, b.y, { x = b.x - fp.x, y = b.y - fp.y }, -6, nil)
      carAt(veh, { x = spot.x, y = spot.y, z = spot.z }, { x = spot.dx, y = spot.dy }, 1.0)
      step('placed')
    end
  end
  if inPhase() > M.STOP_BUDGET_S then fail(string.format('not stopped at the stop control in %d s', M.STOP_BUDGET_S)) end
end

local function stepResults()
  local r = T.run
  if T.step ~= 'wait' then
    step('wait')
    if r.stopCtl then check('stopped at the stop control', r.checks.stopControl ~= nil, r.checks.stopControl) end
    check('pacenotes called', (r.checks.notesCalled or 0) > 0, string.format('%d called of %s loaded',
      r.checks.notesCalled or 0, tostring(r.checks.notesLoaded)))
    check('time kept', r.finalTime ~= nil and r.best ~= nil, r.finalTime and runner.formatTime(r.finalTime))
  end
  if T.sawResultsShow then
    check('results card shown (show.results)', true, string.format('%.1f s after the finish', r.sinceFinish or -1))
    finish()
  elseif inStep() > M.RESULTS_WAIT_S then
    check('results card shown (show.results)', false, 'not in the earthRally stream in ' .. M.RESULTS_WAIT_S .. ' s')
    finish()
  end
end

-- the report ------------------------------------------------------------------------------

local function report()
  local ok, passed, failed = M.summary(T.checks, T.abortReason)
  local stamp = M.game.date()
  local r = T.run
  local out = {
    format = 1, tool = 'Earth Rally self-test', version = T.version, token = T.token, event = T.eventId,
    stage = T.stageId, startedAt = T.startedAt, elapsedS = math.floor(now() + 0.5), ok = ok, passed = passed,
    failed = failed, abortReason = T.abortReason, checks = T.checks, timings = T.timings, states = T.states,
    streams = T.streams, errors = T.errors, settings = T.settings, levelLoadAsked = T.levelLoadAsked or nil,
    strayOffRouteFrames = T.strayOffRoute, hookError = T.hookError,
    run = r and { finalTime = r.finalTime, stageTime = r.stageTime, penalty = r.penalty, resets = r.resets,
      checks = r.checks } or nil,
  }
  local path = M.DIR .. 'report-' .. stamp .. '.json'
  local fs = rawget(_G, 'FS')
  if fs and fs.directoryExists and not fs:directoryExists(M.DIR) then pcall(function() fs:directoryCreate(M.DIR, true) end) end
  local okW = pcall(jsonWriteFile, path, out, true)
  log(ok and 'I' or 'W', logTag, string.format('self-test: %s %d/%d checks (%s / %s, %d s)%s; report %s',
    ok and 'PASS' or 'FAIL', passed, passed + failed, tostring(T.eventId), tostring(T.stageId), out.elapsedS,
    T.abortReason and (': ' .. T.abortReason) or '', okW and path or '(could not be written)'))
  T.reportPath = okW and path or nil
  return out
end

finish = function()
  if not T or T.closed then return end
  T.closed = true
  if T.phase then T.timings[T.phase] = math.floor((now() - T.phaseAt) * 10 + 0.5) / 10 end
  local veh = M.game.vehicle()
  if veh and T.run then pcall(M.game.driveStop, veh, false) end
  T.driving = false
  for _, c in ipairs(M.evaluateStreams(T.streams, T.stateOrder or {})) do
    T.checks[#T.checks + 1] = { name = c.name, ok = c.ok, detail = c.detail, t = math.floor(now() * 10 + 0.5) / 10 }
  end
  local own = {}
  for _, e in ipairs(T.errors) do
    if e.tag:find('earthRally') or e.msg:find('earthRally') then own[#own + 1] = e.msg end
  end
  T.checks[#T.checks + 1] = { name = 'no Earth Rally errors logged', ok = #own == 0,
    detail = #own > 0 and table.concat(own, ' | '):sub(1, 400) or nil, t = math.floor(now() * 10 + 0.5) / 10 }
  if T.run then pcall(runner.abort, true) end
  pcall(resultsRestore)
  hooksOff()
  T.report = report()
  if T.quit then T.quitIn = 3 end
end

-- Every frame (main.lua), while a test is on (and a moment after, to quit the game when asked).
function M.update(dtReal, version)
  if not T then return end
  dtReal = dtReal or 0
  T.t = T.t + dtReal
  T.version = T.version or version
  if T.closed then
    if T.quitIn then
      T.quitIn = T.quitIn - dtReal
      if T.quitIn <= 0 then T.quitIn = nil M.game.quit() end
    end
    return
  end
  -- the run's states in order (each once), for the streams' checks
  local s = runner.current() and runner.state() or nil
  if s and s ~= T.lastState then
    T.lastState = s
    T.states[#T.states + 1] = { state = s, t = math.floor(T.t * 10 + 0.5) / 10 }
    T.stateOrder = T.stateOrder or {}
    local seen = false
    for _, x in ipairs(T.stateOrder) do if x == s then seen = true end end
    if not seen then T.stateOrder[#T.stateOrder + 1] = s end
  end
  -- the stage layout, once it has been on a moment
  if T.run and T.run.oldLayout and not T.layoutChecked then
    T.layoutOnAt = T.layoutOnAt or T.t
    if T.t - T.layoutOnAt >= M.LAYOUT_CHECK_S then T.layoutChecked = true layoutCheck() end
  end
  if T.run and runner.current() ~= T.run then fail('the run went away (stopped or replaced)') return end
  if s == 'failed' then fail('the run failed: ' .. tostring(T.run.error)) return end
  if T.t > T.budgetS then fail(string.format('time budget of %d s used up (in %s)', T.budgetS, tostring(T.phase))) return end
  local p = T.phase
  if p == 'boot' then stepBoot()
  elseif p == 'world' then stepWorld(dtReal)
  elseif p == 'prep' then stepPrep()
  elseif p == 'liaison' then stepLiaison()
  elseif p == 'stage' then stepStage()
  elseif p == 'offroute' then stepOffroute()
  elseif p == 'stop' then stepStop()
  elseif p == 'results' then stepResults() end
end

-- (the game's level closed under the test)
function M.onClientEndMission()
  if M.active() and T.run then fail('the level was closed') end
end

-- The request file (tools/selftest.py): read and deleted. Returns the request table, or nil.
function M.readRequest()
  local fs = rawget(_G, 'FS')
  if not (fs and fs.fileExists and fs:fileExists(M.REQUEST)) then return nil end
  local ok, req = pcall(jsonReadFile, M.REQUEST)
  M.game.removeFile(M.REQUEST)
  if not (ok and type(req) == 'table') then
    log('E', logTag, 'self-test: the request file could not be read')
    return nil
  end
  return req
end

return M
