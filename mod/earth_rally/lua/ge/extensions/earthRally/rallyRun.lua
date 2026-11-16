-- earthRally/rallyRun: the full rally in the game (1.7.0, docs/plan-1.7.0.md). rally.lua keeps the rally's rules and
-- numbers; this drives it: the stages got ready, the car put at the start and at each service on the map, the
-- transits driven between them, the stages started through the runner, the time card's data, recovery, service (the
-- car repaired, the rally saved), leaving and coming back, retiring, and the finish kept for the Results tab.
--
--   the save   /earthRally/rallies/<rallyId>.json: { format, current = the rally as it was at its last service (or
--              its start), finished = [rally.finished...] }. Written only at the start and at each service: leave
--              anywhere else and you come back at the last service (the user's rule: damage never needs saving).
--   recovery   BeamNG's own (reset, recover, reload, teleports, the vehicle menus) blocked for the whole rally, put
--              back when it ends or is left; the mod's Backspace (D-pad right on a pad) is the rally's recovery
--              (main.backOnRoad): Casual -> back on the stage line, free; Realistic -> the Recover? question, then
--              Super Rally and the car taken to the service it rejoins at.
--   the map    (#26, #31, #33) the start, each service and each overnight is a place from the event file. The rally
--              begins at the start; a service is driven into (GPS arrows, ARRIVE_M); a recovery and an overnight move
--              the car there. Out of each, the next stage is driven to: its run loads as the car arrives
--              (runner.armApproach, sticky). A stop with no place on the map is done where the car is.
--   the prep   (#23, #30) starting (and continuing) a rally runs the auto recce on every stage still to come that
--              has no line yet (main.lua drives it: M.prep*), then holds out of the rally every stage whose line
--              has stretches with no road on the map.
--   the menu   main.lua sets M.ui = { openCard(), closeMenu() }.
local runner = require('earthRally/runner')
local rally = require('earthRally/rally')
local events = require('earthRally/events')
local menu = require('earthRally/menu')
local earth = require('earthRally/earthAdapter')
local geo = require('earthRally/geo')

local M = {}
local logTag = 'earthRally'

M.DIR = '/earthRally/rallies/'
M.FORMAT = 1
M.FILTER = 'earthRallyRally'
-- BeamNG's actions that move, reset, repair or swap the car, blocked during a rally (as its career mode blocks them:
-- career.lua blockInputActions; core/input/actionFilter.lua's groups vehicleTeleporting, vehicleMenues,
-- vehicleSwitching, physicsControls and funStuff, plus reset_physics, which its group leaves out for scenarios).
M.BLOCKED = {
  'reset_physics', 'reset_all_physics', 'recover_vehicle', 'recover_vehicle_alt', 'recover_to_last_road',
  'reload_vehicle', 'reload_all_vehicles', 'loadHome', 'saveHome', 'dropPlayerAtCamera', 'dropPlayerAtCameraNoReset',
  'vehicle_selector', 'parts_selector', 'vehicledebugMenu', 'switch_previous_vehicle', 'switch_next_vehicle',
  'slower_motion', 'faster_motion', 'toggle_slow_motion',
  'forceField', 'funBoom', 'funBreak', 'funExtinguish', 'funFire', 'funHinges', 'funTires', 'funRandomTire',
  'latchesOpen', 'latchesClose', 'funBoost', 'funBoostBackwards', 'funFling', 'funFlingDownward',
}
M.ARRIVE_M = 150          -- a service driven to: done this close to its place
M.ARRIVE_POLL_S = 0.5     -- ... looked at this often
M.MOVE_WAIT_S = 120       -- a move to a stop: the world given this long to load there, then the stop done anyway
M.GAP_HOLD_M = 250        -- a stage whose line has more than this of road missing on the map is held out (#30)

M.ui = {}
local R = nil          -- the rally in progress (rally.lua's r), or nil
local savedResults     -- the results in its save (leaveInfo: what leaving now loses)
local ev, board = nil, nil
local blocked = false
local card = nil       -- the last stage's card for the results card: { ss, name, timeS, stage = standing, overall }
local recoveredAt = nil -- (the Super Rally card: shown once at the stop rejoined at)
local askT = nil       -- how long the Recover? question has been up
local loop = nil       -- Realistic: the times since the last save ({ results, started }), kept in the save file
local move = nil       -- the car on its way to a stop by teleport: { item, t, ready }
local toStop = nil     -- a service being driven to: { item, lat, lon, t, distM }
local prep = nil       -- the stages being got ready: { list = [stage], i, then = fn, done = {}, current }

local function say(text, s, kind, title) pcall(runner.say, text, s or 4, kind or 'info', title) end

------------------------------------------------------------------------------------------ the save

local function pathOf(id) return M.DIR .. tostring(id) .. '.json' end

function M.readFile(id)
  local p = pathOf(id)
  local ok, t = pcall(function() return FS:fileExists(p) and jsonReadFile(p) or nil end)
  if not (ok and type(t) == 'table' and t.format == M.FORMAT) then return { format = M.FORMAT, finished = {} } end
  if type(t.finished) ~= 'table' then t.finished = {} end
  if t.current ~= nil and not rally.valid(t.current) then t.current = nil end
  return t
end

-- (through a temporary file, so a save cut short leaves the last one whole: events.saveMatched's way)
local function writeFile(id, t)
  local p = pathOf(id)
  if not FS:directoryExists(M.DIR) then pcall(FS.directoryCreate, FS, M.DIR) end
  local tmp = p .. '.part'
  if type(FS.renameFile) == 'function' then
    jsonWriteFile(tmp, t, true)
    local ok, done = pcall(FS.renameFile, FS, tmp, p)
    if ok and done ~= false then return true end
    pcall(FS.removeFile, FS, tmp)
  end
  return jsonWriteFile(p, t, true)
end

local function copy(x)
  if type(x) ~= 'table' then return x end
  local o = {}
  for k, v in pairs(x) do o[k] = copy(v) end
  return o
end

local function itemLabel(it)
  if not it then return nil end
  if it.kind == 'stage' then return it.ss end
  return it.label
end

local function save()
  if not R then return end
  local t = M.readFile(R.eventId)
  R.savedLabel = itemLabel(rally.current(R)) or R.savedLabel
  t.current = copy(R)
  savedResults = t.current.results
  t.current.savedAt = os.date('!%Y-%m-%dT%H:%M:%SZ')
  t.loop = nil
  loop = { results = {} }
  writeFile(R.eventId, t)
end

-- Realistic only: the loop's times written as they happen, so leaving mid-loop is no free restart (rally.replayLoop
-- on resume). The car is not kept: the game saves only at a service.
local function saveLoop()
  if not (R and R.mode == 'realistic' and loop) then return end
  local t = M.readFile(R.eventId)
  t.loop = copy(loop)
  writeFile(R.eventId, t)
end

-- A rally saved and not finished: the rally page's Continue card. { at, next, mode, class, savedAt, done } or nil.
function M.saved(id)
  local t = M.readFile(id)
  local r = t.current
  if not r then return nil end
  local it = rally.current(r)
  local nx = rally.nextStage(r)
  local at = it and it.kind ~= 'stage' and (it.kind == 'start' and 'the start' or it.label) or (nx and nx.ss) or 'the start'
  return { mode = r.mode, class = r.class, savedAt = r.savedAt, at = at, next = nx and nx.ss or nil,
    done = #rally.doneStages(r) }
end

function M.finishedList(id) return M.readFile(id).finished end

------------------------------------------------------------------------------------------ BeamNG's own recovery

function M.block(on)
  local af = rawget(_G, 'core_input_actionFilter')
  if not (af and af.setGroup and af.addAction) then
    if on then log('W', logTag, 'rally: the game has no action filter here; its own recovery stays on') end
    blocked = false
    return false
  end
  if on and blocked then return true end      -- (off is always sent: a reload must never leave it blocked)
  local ok, err = pcall(function()
    af.setGroup(M.FILTER, M.BLOCKED)
    af.addAction(0, M.FILTER, on == true)
  end)
  if not ok then log('E', logTag, 'rally: action filter: ' .. tostring(err)) return false end
  blocked = on == true
  log('I', logTag, 'rally: BeamNG\'s own recovery ' .. (blocked and 'blocked' or 'back'))
  return true
end
function M.blocked() return blocked end

------------------------------------------------------------------------------------------ the car

-- The car the player is in: { name, drivetrain } (the game's vehicle details), or nil.
function M.car()
  local veh = getPlayerVehicle and getPlayerVehicle(0)
  if not veh then return nil end
  local out = { name = 'your car' }
  local cv = rawget(_G, 'core_vehicles')
  if cv and cv.getCurrentVehicleDetails then
    local ok, d = pcall(cv.getCurrentVehicleDetails)
    if ok and type(d) == 'table' then
      local cfg = type(d.configs) == 'table' and d.configs or {}
      local model = type(d.model) == 'table' and d.model or {}
      local brand = cfg.Brand or model.Brand
      local nm = cfg.Name or model.Name
      if nm then out.name = (brand and not tostring(nm):find(tostring(brand), 1, true)) and (brand .. ' ' .. nm) or nm end
      out.drivetrain = cfg.Drivetrain or model.Drivetrain
      if type(out.drivetrain) == 'table' then out.drivetrain = out.drivetrain[1] end
    end
  end
  return out
end

-- The car put right where it stands (the game's own "Repair here": spawn.safeTeleport at its own place with
-- resetVehicle = true, core/recoveryPrompt.lua repairHere).
function M.repair()
  local veh = getPlayerVehicle and getPlayerVehicle(0)
  pcall(runner.keepDamage, false)
  local sp = rawget(_G, 'spawn')
  if not (veh and sp and sp.safeTeleport) then return false end
  local ok, err = pcall(function()
    local d = veh:getDirectionVector()
    sp.safeTeleport(veh, veh:getPosition(), quatFromDir(vec3(d.x, d.y, 0)), nil, nil, nil, nil, true)
  end)
  if not ok then log('E', logTag, 'rally: repair: ' .. tostring(err)) end
  return ok
end

------------------------------------------------------------------------------------------ the rally

function M.active() return R end
function M.inRun()
  local r = runner.current()
  return R ~= nil and r ~= nil and r.inRally == true
end
local function runLive()
  local r = runner.current()
  return r ~= nil and r.inRally == true and r.state ~= 'finished' and r.state ~= 'failed'
end

local function load(id)
  ev = menu.findEvent(id)
  board = ev and events.boards(id) or nil
  return ev
end

local function stageOf(item) return item and select(2, menu.findStage(R and R.eventId or (ev and ev.id), item.stageId)) end
local function stageName(item)
  local s = R and stageOf(item)
  return s and s.name or item.stageId
end

-- Why a stage cannot be driven in a rally, or nil when it can (#30): no line on the roads, or a line with stretches
-- the map has no road for.
function M.stageProblem(eventId, stage)
  local line, kind = events.stageLine(eventId, stage.id, stage)
  if not line then return 'no line on the roads' end
  if kind == 'matched' and type(line.gaps) == 'table' then
    local gapM = 0
    for _, g in ipairs(line.gaps) do
      if type(g) == 'table' and type(g[1]) == 'number' and type(g[2]) == 'number' then gapM = gapM + (g[2] - g[1]) end
    end
    if gapM > M.GAP_HOLD_M then
      return string.format('%.1f km of its road is missing from the map', gapM / 1000), gapM
    end
  end
  return nil
end

-- The start screen's data: { name, canRun, why, car, class (guessed), classes, cancelled = ['SS8'...], stages,
-- days, services, crews, first, toRecce (stages with no line yet), heldOut (stages that cannot be driven), saved }.
function M.startInfo(id)
  local e = menu.findEvent(id)
  if not e then return { missing = true, id = id } end
  local car = M.car()
  local r = rally.canRun(e) and rally.new(e, { cancelled = 'all' }) or nil
  local days, svc, stages = {}, 0, 0
  local seen, toRecce, held = {}, 0, {}
  for _, it in ipairs(r and r.order or {}) do
    if it.kind == 'stage' then
      stages = stages + 1
      if it.day then days[it.day] = true end
      if not seen[it.stageId] then
        seen[it.stageId] = true
        local st = select(2, menu.findStage(id, it.stageId))
        if st then
          local why = M.stageProblem(id, st)
          if why == 'no line on the roads' then toRecce = toRecce + 1
          elseif why then held[#held + 1] = { name = st.name, why = why } end
        end
      end
    elseif it.kind == 'service' then svc = svc + 1 end
  end
  local nd = 0
  for _ in pairs(days) do nd = nd + 1 end
  local b = events.boards(id)
  local crews = {}
  for _, p in ipairs(b and b.passes or {}) do
    for _, row in ipairs(rally.field(b, p.ss) or {}) do crews[row.key] = true end
  end
  local nCrews = 0
  for _ in pairs(crews) do nCrews = nCrews + 1 end
  return { id = id, name = e.name, canRun = r ~= nil, why = (not r) and 'This rally has no event file, so it ' ..
      'cannot be run as a full rally.' or nil,
    car = car, class = car and rally.guessClass(car.drivetrain) or 'L4WD', classes = rally.CLASSES,
    cancelled = rally.cancelledPasses(e), stages = stages, days = nd, services = svc, crews = nCrews,
    start = type(e.rallyStart) == 'table' and e.rallyStart.name or nil, toRecce = toRecce, heldOut = held,
    saved = M.saved(id), inProgress = R and R.eventId or nil }
end

------------------------------------------------------------------------------------------ getting the stages ready

-- The stages still to come that have no line yet, once each (main.lua runs the auto recce on them).
local function needingRecce()
  local out, seen = {}, {}
  for i = R.pos, #R.order do
    local it = R.order[i]
    if it.kind == 'stage' and not seen[it.stageId] then
      seen[it.stageId] = true
      local st = stageOf(it)
      if st and not events.stageLine(R.eventId, st.id, st) then out[#out + 1] = st end
    end
  end
  return out
end

-- Every stage still to come that cannot be driven taken out of the rally (rally.holdOut). Returns the names held out.
local function holdOutBad()
  local names, seen = {}, {}
  for i = #R.order, R.pos, -1 do
    local it = R.order[i]
    if it and it.kind == 'stage' and not seen[it.stageId] then
      seen[it.stageId] = true
      local st = stageOf(it)
      local why
      if st then why = M.stageProblem(R.eventId, st) else why = 'not on this computer any more' end
      if why then
        rally.holdOut(R, it.stageId, why)
        table.insert(names, 1, (st and st.name or it.stageId) .. ' (' .. why .. ')')
        log('I', logTag, 'rally: ' .. tostring(st and st.name or it.stageId) .. ' held out: ' .. why)
      end
    end
  end
  return names
end

local finish     -- (below)

-- The prep as main.lua sees it: the next stage to run the auto recce on, or nil when the list is done.
function M.prepNext()
  if not (R and prep) then return nil end
  prep.i = prep.i + 1
  prep.current = prep.list[prep.i]
  return prep.current, prep.i, #prep.list
end
function M.preparing() return prep end
-- main.lua: every stage on the list tried. The rally goes on.
function M.prepDone()
  if not (R and prep) then return end
  local thenDo = prep.thenDo
  prep = nil
  local held = holdOutBad()
  if #held > 0 then
    say(table.concat(held, '; '), 10, 'warning', #held == 1 and 'Held out of the rally' or (#held .. ' stages held out'))
  end
  if rally.over(R) then
    say('No stage left in this rally can be driven on this computer.', 8, 'warning', R.name)
    -- (stages already driven: the rally finished with them, scored; none: nothing to keep)
    if next(R.results or {}) then finish() else M.quit() end
    return
  end
  if thenDo then thenDo() end
end

-- Get the stages ready, then thenDo(). With nothing to recce, at once.
local function getReady(thenDo)
  local list = needingRecce()
  if #list == 0 then
    prep = { list = {}, i = 0, thenDo = thenDo }
    M.prepDone()
    return
  end
  prep = { list = list, i = 0, thenDo = thenDo }
  log('I', logTag, string.format('rally: %d stage(s) to get ready with the auto recce', #list))
  say(string.format('The auto recce makes the line of %d %s: you are taken to each one.', #list,
    #list == 1 and 'stage' or 'stages'), 8, 'info', 'Getting the stages ready')
end

------------------------------------------------------------------------------------------ the stops on the map

local function gpsOff() pcall(earth.gpsClear) end

-- At the stop the rally is at (the car there): repaired, the rally saved, the time card up.
local function arrive()
  move, toStop = nil, nil
  if not R then return end
  local it = rally.current(R)
  if not it or it.kind == 'stage' then return end
  if runner.current() and not runLive() then pcall(runner.abort, true) end
  gpsOff()
  M.repair()
  rally.serviced(R)
  save()
  log('I', logTag, 'rally: at ' .. tostring(it.label) .. (it.name and (' (' .. it.name .. ')') or ''))
  if M.ui.openCard then M.ui.openCard() end
end

-- The car taken to the stop the rally is at (a teleport to its place; with none, it is done where the car is).
local function goToStop()
  local it = R and rally.current(R)
  if not it or it.kind == 'stage' then return false end
  toStop = nil
  runner.disarmApproach('the rally moved on')
  if runner.current() then pcall(runner.abort, true) end
  if not (it.place and it.place.lat) then arrive() return true end
  pcall(runner.keepDamage, false)
  local ok, why = earth.teleport(it.place.lat, it.place.lon, it.place.name or it.label)
  if not ok then
    log('W', logTag, 'rally: could not go to ' .. tostring(it.label) .. ': ' .. tostring(why))
    arrive()
    return true
  end
  move = { item = it, t = 0, ready = 0 }
  if M.ui.closeMenu then M.ui.closeMenu() end
  say('On the way to ' .. (it.name or it.label) .. '.', 4, 'info', it.label)
  return true
end

-- A service driven to: the GPS set to its place, done once the car is within ARRIVE_M.
local function driveToStop()
  local it = R and rally.current(R)
  if not (it and it.kind ~= 'stage' and it.place and it.place.lat) then return goToStop() end
  toStop = { item = it, lat = it.place.lat, lon = it.place.lon, t = 0 }
  pcall(earth.gpsSet, it.place.lat, it.place.lon, it.place.name or it.label)
  log('I', logTag, 'rally: transit to ' .. tostring(it.label))
  return true
end

-- The next stage driven to: the GPS to its time control, and its run loaded as the car arrives (runner.armApproach).
local function armTransit()
  local it = R and rally.current(R)
  if not (it and it.kind == 'stage') then return false, 'the rally is not on its way to a stage' end
  if not ev then load(R.eventId) end
  local stage = stageOf(it)
  if not stage then return false, it.ss .. ': that stage is not on this computer any more' end
  local lat, lon, kind = runner.arrivalPoint(stage)
  if not lat then return false, it.ss .. ': the stage has no start' end
  local title = it.ss .. ' ' .. stage.name
  pcall(earth.gpsSet, lat, lon, title .. ' ' .. kind)
  local ok = runner.armApproach(ev, stage, { sticky = true, title = title, rally = true,
    startOpts = { rally = true, ssLabel = it.ss, keepDamage = true },
    onStart = function() M.onStageLoaded() end })
  if not ok then return false, it.ss .. ': the stage could not be got ready' end
  log('I', logTag, 'rally: transit to ' .. title)
  return true
end

-- The stage loaded where the car is now (a teleport: a Casual restart, the debug panel's skip). Returns ok, why.
local function startHere(it)
  if not ev then load(R.eventId) end
  local stage = stageOf(it)
  if not stage then return false, it.ss .. ': that stage is not on this computer any more' end
  runner.disarmApproach('the rally moved on')
  toStop = nil
  card = nil
  local ok, why = runner.start(ev, stage, { rally = true, ssLabel = it.ss, keepDamage = true })
  if not ok then return false, why end
  M.onStageLoaded()
  return true
end

-- (runner: the rally's stage loaded, by the transit's arrival or startHere)
function M.onStageLoaded()
  local r = runner.current()
  if not (R and r) then return end
  card = nil
  r.rally = { mode = R.mode }
  r.rallyKey = 'rally:' .. R.mode .. ':' .. tostring(r.ssLabel)
end

------------------------------------------------------------------------------------------ start, continue, leave

finish = function()
  local t = M.readFile(R.eventId)
  t.current, t.loop, loop = nil, nil, nil
  t.finished[#t.finished + 1] = rally.finished(R, os.date('!%Y-%m-%dT%H:%M:%SZ'))
  writeFile(R.eventId, t)
  M.block(false)
  gpsOff()
  runner.disarmApproach('the rally is over')
  toStop, move = nil, nil
  log('I', logTag, string.format('rally: %s finished, %.1f s%s', R.name, rally.totalS(R),
    R.unclassified and ' (unclassified)' or ''))
end

-- Start a new rally (opts: mode, class, cancelled). The one saved for it before is replaced (at the start, once the
-- stages are ready). Returns ok, why.
function M.start(id, opts)
  if R and not R.done then return false, 'a rally is under way: leave it first' end
  if not load(id) then return false, 'that rally is not on this computer any more' end
  local car = M.car()
  if not car then return false, 'get in a car first' end
  local r, why = rally.new(ev, { mode = opts and opts.mode, class = opts and opts.class,
    cancelled = opts and opts.cancelled, car = car })
  if not r then return false, why end
  R, card, recoveredAt, askT, move, toStop = r, nil, nil, nil, nil, nil
  savedResults = nil
  loop = { results = {} }
  M.block(true)
  log('I', logTag, string.format('rally: %s started (%s, %s, cancelled stages %s)', R.name, R.mode, R.class,
    R.cancelled))
  if M.ui.closeMenu then M.ui.closeMenu() end
  getReady(function() goToStop() end)
  return true
end

-- Back to the rally saved for it, at its last service (or its start). Returns ok, why.
function M.resume(id)
  if R and not R.done and R.eventId ~= id then return false, 'another rally is under way: leave it first' end
  local t = M.readFile(id)
  if not t.current then return false, 'there is no rally saved for this one' end
  if not load(id) then return false, 'that rally is not on this computer any more' end
  local car = M.car()
  if not car then return false, 'get in a car first' end
  local want = type(t.current.car) == 'table' and t.current.car.name or nil
  if want and car.name ~= want then
    return false, 'this rally was started in the ' .. tostring(want) .. ': get in that car to continue it'
  end
  pcall(runner.abort, true)
  runner.disarmApproach('a rally continued')
  R, card, recoveredAt, askT, move, toStop = t.current, nil, nil, nil, nil, nil
  savedResults = t.current.results
  M.block(true)
  loop = { results = {} }
  if R.mode == 'realistic' and type(t.loop) == 'table' then
    local missedBefore = R.missed or 0
    rally.replayLoop(R, t.loop, board)
    log('I', logTag, string.format('rally: resumed mid-loop, %d stage(s) kept%s', #(t.loop.results or {}),
      t.loop.started and ', the stage left during scored under Super Rally' or ''))
    if rally.over(R) then
      finish()
      if M.ui.openCard then M.ui.openCard() end
      return true
    end
    if (R.missed or 0) > missedBefore then recoveredAt = R.pos end
    -- (the loop's times are in the rally now: saved as they are, so a second leave and continue does not replay
    -- them again on top of themselves)
    save()
  end
  if M.ui.closeMenu then M.ui.closeMenu() end
  getReady(function()
    local it = rally.current(R)
    if it and it.kind ~= 'stage' then goToStop()
    elseif it then
      -- (left between two stages: the car is not kept, so it goes straight to the next stage's start)
      local ok, why = startHere(it)
      if not ok then say(tostring(why), 6, 'warning', R.name) end
    end
  end)
  return true
end

-- Leave the rally (continue later): BeamNG's recovery back, the run stopped. The save stays at its last service.
function M.quit()
  if not R then return true end
  if M.inRun() then pcall(runner.abort, true) end
  runner.disarmApproach('the rally was left')
  if toStop or (R and not R.done) then gpsOff() end
  R, card, recoveredAt, loop, askT, move, toStop, prep = nil, nil, nil, nil, nil, nil, nil, nil
  M.block(false)
  return true
end

-- Retire: the saved rally thrown away (its finished ones kept).
function M.abandon(id)
  if R and R.eventId == id then M.quit() end
  local t = M.readFile(id)
  if t.current or t.loop then
    t.current, t.loop = nil, nil
    writeFile(id, t)
  end
  return true
end

-- What leaving now costs, for its confirm: { at = where you continue from, superRally = the stage scored under Super
-- Rally (Realistic, mid-stage), redo = [stages driven again] (Casual: the times since the save are not kept) }.
function M.leaveInfo()
  if not R then return nil end
  local out = { at = R.savedLabel == 'Start' and 'the start' or R.savedLabel or 'the start' }
  if R.mode == 'realistic' then
    local r = runner.current()
    if runLive() and r.state == 'running' then out.superRally = r.ssLabel end
  else
    local redo = {}
    for _, d in ipairs(rally.doneStages(R)) do
      if not (savedResults and savedResults[d.item.ss]) then redo[#redo + 1] = d.item.ss end
    end
    out.redo = redo
  end
  return out
end

------------------------------------------------------------------------------------------ the way through it

-- The time card's main button. At a stop: out of it, to the next stage. Otherwise: back to driving (the transit
-- armed again if it was lost). Returns ok, why.
function M.goNext()
  if not R then return false, 'no rally under way' end
  if rally.over(R) then return false, 'the rally is over' end
  if prep then return false, 'the stages are being got ready' end
  if move then return false, 'on the way to ' .. tostring(move.item.label) end
  if runLive() then return true end              -- (a stage under way: just back to it)
  local it = rally.current(R)
  if it.kind ~= 'stage' then
    if not rally.isServiced(R) then
      -- (not there yet: a service is driven to, an overnight or a stop with no place is gone to)
      if it.kind == 'service' and it.place and not recoveredAt then
        if not toStop then driveToStop() end
        return true
      end
      goToStop()
      return true
    end
    rally.serviceOut(R)
    recoveredAt = nil
    it = rally.current(R)
    if not it then return false, 'the rally is over' end
  end
  return armTransit()
end

-- The runner's finish (runner.onFinished, a pass of the rally): its time kept, the results card's data made, and the
-- way on armed: the next stage's transit, or the service's.
function M.onFinished(res)
  if not R then return end
  local it, why = rally.stageDone(R, res)
  if not it then log('W', logTag, 'rally: ' .. tostring(why)) return end
  if loop and not rally.over(R) then
    loop.results[#loop.results + 1] = { timeS = res.timeS, stageS = res.stageS, penaltyS = res.penaltyS }
    loop.started = false
    saveLoop()
  end
  local st = rally.stageStanding(board, it, res.timeS, R.class)
  local ov = rally.standing(R, board)
  local stage = stageOf(it)
  local nx = rally.current(R)
  card = { ss = it.ss, name = stage and stage.name or it.stageId, timeS = res.timeS, stage = st, overall = ov,
    mode = R.mode, canRestart = R.mode == 'casual' and not rally.over(R), last = rally.over(R),
    next = nx and (nx.kind == 'stage' and (nx.ss .. ' ' .. stageName(nx)) or nx.label) or nil }
  local r = runner.current()
  if r then
    r.rally = { mode = R.mode, card = card }
    r.rallyKey = 'card:' .. it.ss .. ':' .. tostring(res.timeS)
  end
  if rally.over(R) then finish() return end
  if nx.kind == 'stage' then armTransit()
  elseif nx.kind == 'service' and nx.place then driveToStop() end
end
runner.onFinished = function(res) M.onFinished(res) end

-- The rally's recovery key (main.backOnRoad). On a transit (no stage loaded, the game's own recovery blocked): the
-- car put back on the nearest road, free -- road sections are not timed. During a stage of the rally: below.
-- Returns true when it was the rally's.
function M.recoverKey()
  if not R or R.done then return false end
  if not M.inRun() or not runLive() then
    if move or prep then return true end
    -- (a stage that failed to start: put away, its transit armed again, the car put back on the road)
    if M.inRun() and runner.current().state == 'failed' then
      pcall(runner.abort, true)
      local it = rally.current(R)
      if it and it.kind == 'stage' then armTransit() end
    end
    local ok = runner.recoverToRoad()
    if not ok then say('No road found near the car.', 3, 'warning', 'Recovery') end
    return true
  end
  local r = runner.current()
  if R.mode == 'casual' or r.state ~= 'running' then
    runner.backOnRoad()           -- (free: no reset penalty in a rally run)
    return true
  end
  -- Realistic, on the stage: the question first; the key again while it is up is the answer (a keyboard player has
  -- no pointer on the driving screen). Not a double press (within CONFIRM_GAP_S), nor with a menu over the question.
  if r.rally and r.rally.ask then
    if (askT or 0) < M.CONFIRM_GAP_S or runner.uiHidden then return true end
    return (M.answer('recover')) or true
  end
  r.rally = r.rally or { mode = R.mode }
  r.rally.ask = { ss = r.ssLabel, name = r.stage and r.stage.name,
    stop = (function()
      for i = R.pos + 1, #R.order do
        if R.order[i].kind ~= 'stage' then return R.order[i].label end
      end
      return nil
    end)() }
  r.rallyKey = 'ask:' .. tostring(r.ssLabel) .. ':' .. tostring(os.clock())
  askT = 0
  return true
end

-- (main.onUpdate) the Recover? question timed out, a teleport to a stop settling, a service driven to, a stage
-- started (Realistic: from then on leaving scores it under Super Rally).
M.ASK_S, M.CONFIRM_GAP_S = 10, 1
function M.update(dt)
  dt = dt or 0
  if askT then
    local r = runner.current()
    if not (r and r.rally and r.rally.ask) then askT = nil
    else
      askT = askT + dt
      if askT > M.ASK_S then
        askT = nil
        r.rally.ask = nil
        r.rallyKey = 'gone:' .. tostring(os.clock())
      end
    end
  end
  if not R then return end
  if loop and not loop.started and R.mode == 'realistic' then
    local r = runner.current()
    if r and r.inRally and r.state == 'running' then loop.started = true saveLoop() end
  end
  if move then
    move.t = move.t + dt
    move.ready = earth.ready() and move.t > 2 and (move.ready + dt) or 0
    if move.ready >= runner.TELEPORT_SETTLE_S or move.t > M.MOVE_WAIT_S then
      if move.t > M.MOVE_WAIT_S then log('W', logTag, 'rally: the world took long to load at the stop') end
      arrive()
    end
  elseif toStop then
    toStop.t = toStop.t - dt
    if toStop.t <= 0 then
      toStop.t = M.ARRIVE_POLL_S
      local p = earth.pose()
      if p and p.lat then
        toStop.distM = geo.metres(p.lat, p.lon, toStop.lat, toStop.lon)
        if toStop.distM <= M.ARRIVE_M and not runLive() then arrive() end
      end
    end
  end
end

-- The service being driven to, for the HUD's line and the game's Messages app: { name, distM, rally } or nil.
local tInfo
function M.transitInfo()
  if not (R and toStop) then tInfo = nil return nil end
  local d = math.floor((toStop.distM or 0) / 10 + 0.5) * 10
  if not (tInfo and tInfo.item == toStop.item and tInfo.distM == d) then
    tInfo = { item = toStop.item, name = toStop.item.label .. (toStop.item.name and (' · ' .. toStop.item.name) or ''),
      distM = d, rally = true }
  end
  return tInfo
end

-- The Recover? question answered: 'recover' (the stage ends, Super Rally, the car to the next stop) or 'keep'.
function M.answer(what)
  if not (R and M.inRun()) then return false, 'no rally stage under way' end
  local r = runner.current()
  if what ~= 'recover' then
    if r.rally then r.rally.ask = nil end
    r.rallyKey = 'kept:' .. tostring(os.clock())
    return true
  end
  if not (r.state == 'running' and r.rally and (r.rally.ask or r.rally.forced)) then
    return false, 'the stage is not under way'
  end
  local out, why = rally.recover(R, board)
  if not out then return false, why end
  askT = nil
  pcall(runner.abort, true)
  card = nil
  if rally.over(R) then
    finish()
    say('No service is left to rejoin at: the rally ends unclassified.', 6, 'warning', 'Rally over')
    if M.ui.openCard then M.ui.openCard() end
  else
    recoveredAt = R.pos
    goToStop()
  end
  return true
end

-- A reset that got past the block (the game's radial menu, a script): Realistic counts it as giving the stage up.
function M.onRallyReset()
  if not (R and M.inRun()) then return end
  if R.mode == 'realistic' and runner.current().state == 'running' then
    say('A reset during a Realistic rally ends the stage.', 6, 'warning', 'Super Rally')
    local r = runner.current()
    r.rally = r.rally or { mode = R.mode }
    r.rally.forced = true
    M.answer('recover')
  end
end
runner.onRallyReset = function() M.onRallyReset() end
runner.transitSource = function() return M.transitInfo() end
runner.rallyOn = function() return R ~= nil and not R.done end

-- The results card's buttons in a rally: 'continue' (the time card; an overnight is gone to), 'restart' (Casual: the
-- stage again, from its start), 'close' (back to driving: the transit is armed already).
function M.resultsAction(what)
  if not R then return false, 'no rally' end
  if what == 'restart' then
    local it, why = rally.restart(R)
    if not it then return false, why end
    card = nil
    toStop = nil
    gpsOff()
    return startHere(it)
  elseif what == 'continue' or what == 'menu' then
    pcall(runner.closeResults)
    local it = rally.current(R)
    if it and it.kind == 'overnight' and not rally.isServiced(R) then goToStop() return true end
    if M.ui.openCard then M.ui.openCard() end
    return true
  end
  pcall(runner.closeResults)
  return true
end

------------------------------------------------------------------------------------------ the developer panel (#29)

-- Skip the transit: the car taken to where it was driving (the next stage's start, or the service).
function M.debugSkipTransit()
  if not R then return false, 'no rally' end
  if prep or move then return false, 'busy' end
  local it = rally.current(R)
  if not it then return false, 'the rally is over' end
  if it.kind == 'stage' then
    if runLive() then return false, 'the stage is loaded already' end
    return startHere(it)
  end
  if rally.isServiced(R) then return false, 'at the stop already: Service out first' end
  return goToStop()
end

-- What the developer panel shows of the rally: a line, or nil.
function M.debugLine()
  if not R then return nil end
  local it = rally.current(R)
  return string.format('%s · %s · at %s%s%s%s', R.name, R.mode, tostring(itemLabel(it) or 'the end'),
    prep and ' · getting ready' or '', move and ' · moving to the stop' or '',
    toStop and string.format(' · driving to %s (%.0f m)', toStop.item.label, toStop.distM or -1) or '')
end

------------------------------------------------------------------------------------------ the time card's data

-- Everything the time card shows: the running order with your times and places, where you are and what is next,
-- the Super Rally card, the overall standing, what leaving costs. nil with no rally.
function M.uiCard()
  if not R then return nil end
  if not ev then load(R.eventId) end
  local rows = {}
  local cur = rally.current(R)
  for i, it in ipairs(R.order) do
    local row = { kind = it.kind, label = it.kind == 'stage' and it.ss or it.label, name = it.kind == 'stage'
      and stageName(it) or it.name, km = it.km, day = it.day, next = i == R.pos or nil, done = i < R.pos or nil }
    if it.kind == 'stage' then
      local res = R.results[it.ss]
      if res then
        row.timeS, row.superRally = res.timeS, res.superRally or nil
        local stp = rally.stageStanding(board, it, res.timeS, R.class)
        if stp then row.pos, row.of = stp.pos, stp.of end
      end
      row.cancelledReal = it.cancelledReal
    end
    rows[#rows + 1] = row
  end
  local nx, nxi = rally.nextStage(R)
  local nextStage = nil
  if nx then
    local s = stageOf(nx)
    nextStage = { ss = nx.ss, name = s and s.name or nx.stageId, km = nx.km, lengthM = s and s.lengthM }
  end
  local sr = nil
  if recoveredAt and recoveredAt == R.pos and R.superRally then
    sr = {}
    local add = 0
    for _, m in ipairs(R.superRally) do
      sr[#sr + 1] = { ss = m.item.ss, name = stageName(m.item), classBestS = m.result.classBestS,
        addS = m.result.addS, timeS = m.result.timeS, from = m.result.from }
      add = add + (m.result.addS or 0)
    end
    sr = { rows = sr, addS = add, at = cur and cur.label }
  end
  local held = {}
  for _, h in ipairs(R.heldOut or {}) do held[#held + 1] = { ss = h.ss, why = h.why } end
  -- where the car is in the rally now: 'prep', 'moving', 'stop' (at a service, done), 'toStop' (driving to it),
  -- 'transit' (driving to the next stage), 'stage' (a stage loaded), 'done'
  local phase
  if rally.over(R) then phase = 'done'
  elseif prep then phase = 'prep'
  elseif move then phase = 'moving'
  elseif runLive() then phase = 'stage'
  elseif cur and cur.kind ~= 'stage' then phase = rally.isServiced(R) and 'stop' or (toStop and 'toStop' or 'toGo')
  else phase = 'transit' end
  local ap = runner.approachInfo()
  local transit = nil
  if phase == 'transit' and ap then transit = { name = ap.name, distM = ap.distM }
  elseif phase == 'toStop' and toStop then transit = { name = cur.label .. (cur.name and (' · ' .. cur.name) or ''),
    distM = toStop.distM } end
  return {
    id = R.eventId, name = R.name, mode = R.mode, class = R.class, car = R.car and R.car.name,
    cancelled = R.cancelled, rows = rows, pos = R.pos, phase = phase, transit = transit,
    at = cur and { kind = cur.kind, label = cur.kind == 'stage' and cur.ss or cur.label,
      name = cur.kind == 'stage' and stageName(cur) or cur.name, serviced = rally.isServiced(R) or nil } or nil,
    prep = prep and { i = prep.i, of = #prep.list, name = prep.current and prep.current.name } or nil,
    nextStage = nextStage, nextIndex = nxi, superRally = sr, overall = rally.standing(R, board),
    totalS = rally.totalS(R), done = rally.over(R) or nil, unclassified = R.unclassified or nil,
    heldOut = #held > 0 and held or nil, leave = M.leaveInfo(), hasBoard = board ~= nil or nil,
  }
end

-- The rally's Results tab: your best finished rally against the real National totals. nil with none.
function M.resultsFor(id)
  local list = M.finishedList(id)
  local best = rally.bestFinished(list)
  if not best then return nil end
  local st = rally.finishedStanding(best, events.boards(id))
  return { totalS = best.totalS, mode = best.mode, class = best.class, car = best.car, date = best.date,
    unclassified = best.unclassified, pos = st and st.pos, of = st and st.of, classPos = st and st.classPos,
    classOf = st and st.classOf, count = #list }
end

-- (the level left, the mod switched off: the game's own recovery back whatever happens)
function M.release()
  M.block(false)
  runner.keepDamage(false)
end

return M
