-- earthRally/rallyRun: the full rally in the game (1.7.0 MVP, docs/plan-1.7.0.md). rally.lua keeps the rally's
-- rules and numbers; this drives it: the stages started through the runner, the time card's data, recovery, service
-- (the car repaired, the rally saved), quitting and coming back, and the finish kept for the Results tab.
--
--   the save   /earthRally/rallies/<rallyId>.json: { format, current = the rally as it was at its last service (or
--              its start), finished = [rally.finished...] }. Written only at the start and at each service: quit
--              anywhere else and you come back at the last service (the user's rule: damage never needs saving).
--   recovery   BeamNG's own (reset, recover, reload, teleports, the vehicle menus) blocked for the whole rally, put
--              back when it ends or is left; the mod's Backspace is the rally's recovery (main.backOnRoad):
--              Casual -> back on the stage line, free; Realistic -> the Recover? question, then Super Rally.
--   the menu   main.lua sets M.ui = { openCard(), closeMenu(), suspendPause() } (the time card is a view of the
--              menu page: EarthRallyTimeCard.vue).
local runner = require('earthRally/runner')
local rally = require('earthRally/rally')
local events = require('earthRally/events')
local menu = require('earthRally/menu')

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

M.ui = {}
local R = nil          -- the rally in progress (rally.lua's r), or nil
local ev, board = nil, nil
local blocked = false
local card = nil       -- the last stage's card for the results card: { ss, name, timeS, stage = standing, overall }
local recoveredAt = nil -- (the Super Rally card: shown once at the stop rejoined at)
local askT = nil       -- how long the Recover? question has been up

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

local function save()
  if not R then return end
  local t = M.readFile(R.eventId)
  t.current = copy(R)
  t.current.savedAt = os.date('!%Y-%m-%dT%H:%M:%SZ')
  writeFile(R.eventId, t)
end

-- A rally saved and not finished: the rally page's Continue card. { pos, label, total, mode, class, savedAt } or nil.
function M.saved(id)
  local t = M.readFile(id)
  local r = t.current
  if not r then return nil end
  local it = rally.current(r)
  local nx = rally.nextStage(r)
  return { mode = r.mode, class = r.class, savedAt = r.savedAt, at = it and it.label or (nx and nx.ss) or 'the start',
    next = nx and nx.ss or nil, done = #rally.doneStages(r) }
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

local function load(id)
  ev = menu.findEvent(id)
  board = ev and events.boards(id) or nil
  return ev
end

-- The start screen's data: { name, canRun, why, car, class (guessed), classes, cancelled = ['SS8'...], stages,
-- days, services, saved }.
function M.startInfo(id)
  local e = menu.findEvent(id)
  if not e then return { missing = true, id = id } end
  local car = M.car()
  local r = rally.canRun(e) and rally.new(e, { cancelled = 'all' }) or nil
  local days, svc, stages = {}, 0, 0
  for _, it in ipairs(r and r.order or {}) do
    if it.kind == 'stage' then stages = stages + 1 if it.day then days[it.day] = true end
    elseif it.kind == 'service' then svc = svc + 1 end
  end
  local nd = 0
  for _ in pairs(days) do nd = nd + 1 end
  local first = r and rally.nextStage(r)
  local firstStage = first and select(2, menu.findStage(id, first.stageId))
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
    first = first and { ss = first.ss, name = firstStage and firstStage.name or first.stageId } or nil,
    saved = M.saved(id), inProgress = R and R.eventId or nil }
end

-- Start a new rally (opts: mode, class, cancelled). The one saved for it before is replaced. Returns ok, why.
function M.start(id, opts)
  if R and not R.done then return false, 'a rally is under way: quit it first' end
  if not load(id) then return false, 'that rally is not on this computer any more' end
  local car = M.car()
  if not car then return false, 'get in a car first' end
  local r, why = rally.new(ev, { mode = opts and opts.mode, class = opts and opts.class,
    cancelled = opts and opts.cancelled, car = car })
  if not r then return false, why end
  R, card, recoveredAt = r, nil, nil
  M.block(true)
  save()
  log('I', logTag, string.format('rally: %s started (%s, %s, cancelled stages %s)', R.name, R.mode, R.class,
    R.cancelled))
  return true
end

-- Back to the rally saved for it, at its last service (or its start). Returns ok, why.
function M.resume(id)
  if R and not R.done and R.eventId ~= id then return false, 'another rally is under way: quit it first' end
  local t = M.readFile(id)
  if not t.current then return false, 'there is no rally saved for this one' end
  if not load(id) then return false, 'that rally is not on this computer any more' end
  pcall(runner.abort, true)
  R, card, recoveredAt = t.current, nil, nil
  -- (every save is made with the car put right -- the start, a service -- so it is put right again)
  M.repair()
  M.block(true)
  return true
end

-- Leave the rally: BeamNG's recovery back, the run stopped. The save stays at its last service.
function M.quit()
  if not R then return true end
  if M.inRun() then pcall(runner.abort, true) end
  R, card, recoveredAt = nil, nil, nil
  M.block(false)
  return true
end

-- Throw the saved rally away (Start again from the Continue card).
function M.abandon(id)
  if R and R.eventId == id then M.quit() end
  local t = M.readFile(id)
  if t.current then
    t.current = nil
    writeFile(id, t)
  end
  return true
end

local function finish()
  local t = M.readFile(R.eventId)
  t.current = nil
  t.finished[#t.finished + 1] = rally.finished(R, os.date('!%Y-%m-%dT%H:%M:%SZ'))
  writeFile(R.eventId, t)
  M.block(false)
  log('I', logTag, string.format('rally: %s finished, %.1f s%s', R.name, rally.totalS(R),
    R.unclassified and ' (unclassified)' or ''))
end

-- At a service or an overnight not yet done: the car repaired, the rally saved. Returns true when one was done.
function M.serviceIfDue()
  if not R or rally.over(R) then return false end
  local it = rally.current(R)
  if not it or it.kind == 'stage' or rally.isServiced(R) then return false end
  if M.inRun() then
    local r = runner.current()
    if r.state ~= 'finished' and r.state ~= 'failed' then return false end
    pcall(runner.abort, true)
  end
  M.repair()
  rally.serviced(R)
  save()
  say(it.label .. ': the car is repaired and the rally saved.', 5, 'success', it.label)
  return true
end

local function stageOf(item) return select(2, menu.findStage(R.eventId, item.stageId)) end

-- The next thing on the time card: out of a service, or to the next stage's start. Returns ok, why.
function M.goNext()
  if not R then return false, 'no rally under way' end
  if rally.over(R) then return false, 'the rally is over' end
  local it = rally.current(R)
  if it.kind ~= 'stage' then
    M.serviceIfDue()
    rally.serviceOut(R)
    recoveredAt = nil
    it = rally.current(R)
    if not it then return false, 'the rally is over' end
  end
  if not ev then load(R.eventId) end
  local stage = stageOf(it)
  if not stage then return false, it.ss .. ': that stage is not on this computer any more' end
  card = nil
  local ok, why = runner.start(ev, stage, { rally = true, ssLabel = it.ss, keepDamage = true })
  if not ok then return false, why end
  local r = runner.current()
  if r then
    r.rally = { mode = R.mode }
    r.rallyKey = 'rally:' .. R.mode
  end
  return true
end

-- The runner's finish (runner.onFinished, a pass of the rally): its time kept, the results card's data made.
function M.onFinished(res)
  if not R then return end
  local it, why = rally.stageDone(R, res)
  if not it then log('W', logTag, 'rally: ' .. tostring(why)) return end
  local st = rally.stageStanding(board, it, res.timeS, R.class)
  local ov = rally.standing(R, board)
  local stage = stageOf(it)
  card = { ss = it.ss, name = stage and stage.name or it.stageId, timeS = res.timeS, stage = st, overall = ov,
    mode = R.mode, canRestart = R.mode == 'casual', last = rally.over(R) }
  local r = runner.current()
  if r then
    r.rally = { mode = R.mode, card = card }
    r.rallyKey = 'card:' .. it.ss .. ':' .. tostring(res.timeS)
  end
  if rally.over(R) then finish() end
end
runner.onFinished = function(res) M.onFinished(res) end

-- The rally's recovery key (main.backOnRoad), during a stage of the rally. Returns true when it was the rally's.
function M.recoverKey()
  if not M.inRun() then return false end
  local r = runner.current()
  if R.mode == 'casual' or r.state ~= 'running' then
    runner.backOnRoad()           -- (free: no reset penalty in a rally run)
    return true
  end
  -- Realistic, on the stage: the question first; the key again while it is up is the answer (a keyboard player has
  -- no pointer on the driving screen)
  if r.rally and r.rally.ask then return (M.answer('recover')) or true end
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

-- (main.onUpdate) the Recover? question taken down after ASK_S unanswered: the player drove on.
M.ASK_S = 10
function M.update(dt)
  if not askT then return end
  local r = runner.current()
  if not (r and r.rally and r.rally.ask) then askT = nil return end
  askT = askT + (dt or 0)
  if askT > M.ASK_S then
    askT = nil
    r.rally.ask = nil
    r.rallyKey = 'gone:' .. tostring(os.clock())
  end
end

-- The Recover? question answered: 'recover' (the stage ends, Super Rally, on at the next stop) or 'keep'.
function M.answer(what)
  if not (R and M.inRun()) then return false, 'no rally stage under way' end
  local r = runner.current()
  if what ~= 'recover' then
    if r.rally then r.rally.ask = nil end
    r.rallyKey = 'kept:' .. tostring(os.clock())
    return true
  end
  local out, why = rally.recover(R, board)
  if not out then return false, why end
  pcall(runner.abort, true)
  card = nil
  if rally.over(R) then
    finish()
    say('No service is left to rejoin at: the rally ends unclassified.', 6, 'warning', 'Rally over')
  else
    recoveredAt = R.pos
    M.serviceIfDue()
  end
  if M.ui.openCard then M.ui.openCard() end
  return true
end

-- A reset that got past the block (the game's radial menu, a script): Realistic counts it as giving the stage up.
function M.onRallyReset()
  if not (R and M.inRun()) then return end
  if R.mode == 'realistic' and runner.current().state == 'running' then
    say('A reset during a Realistic rally ends the stage.', 6, 'warning', 'Super Rally')
    M.answer('recover')
  end
end
runner.onRallyReset = function() M.onRallyReset() end

-- The results card's buttons in a rally: 'continue' (the time card), 'restart' (Casual: the stage again), 'close'.
function M.resultsAction(what)
  if not R then return false, 'no rally' end
  if what == 'restart' then
    local it, why = rally.restart(R)
    if not it then return false, why end
    card = nil
    return M.goNext()
  elseif what == 'continue' or what == 'menu' then
    pcall(runner.closeResults)
    M.serviceIfDue()
    if M.ui.openCard then M.ui.openCard() end
    return true
  end
  pcall(runner.closeResults)
  return true
end

------------------------------------------------------------------------------------------ the time card's data

local function stageName(item)
  local s = R and stageOf(item)
  return s and s.name or item.stageId
end

-- Everything the time card shows: the running order with your times and places, what is next, the Super Rally card,
-- the overall standing. nil with no rally.
function M.uiCard()
  if not R then return nil end
  if not ev then load(R.eventId) end
  M.serviceIfDue()
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
  local r = runner.current()
  return {
    id = R.eventId, name = R.name, mode = R.mode, class = R.class, car = R.car and R.car.name,
    cancelled = R.cancelled, rows = rows, pos = R.pos, at = cur and { kind = cur.kind, label = cur.kind == 'stage'
      and cur.ss or cur.label, name = cur.kind == 'stage' and stageName(cur) or cur.name,
      serviced = rally.isServiced(R) or nil } or nil,
    nextStage = nextStage, nextIndex = nxi, superRally = sr, overall = rally.standing(R, board),
    totalS = rally.totalS(R), done = rally.over(R) or nil, unclassified = R.unclassified or nil,
    running = (r and r.inRally and r.state ~= 'finished' and r.state ~= 'failed') or nil,
    hasBoard = board ~= nil or nil,
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
