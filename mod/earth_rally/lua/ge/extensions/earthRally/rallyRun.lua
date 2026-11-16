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
--              begins at the start; a service is driven into (GPS arrows, stopped at its board: #67, #68); a recovery
--              and an overnight move
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
local props = require('earthRally/props')

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
-- (#67) A stop driven to is checked in only once the car is stopped (runner.STOPPED_MS): within BOARD_ARRIVE_M of its
-- board when its board and tent are down (#68), else within ARRIVE_NEAR_M of its point (the venue, not always on a
-- road). Driven through, nothing happens: the GPS keeps pointing there, the HUD line says to stop.
M.BOARD_ARRIVE_M = 25
M.ARRIVE_NEAR_M = 500
M.ARRIVE_POLL_S = 0.5     -- (looked at this often)
M.MOVE_WAIT_S = 120       -- a move to a stop: the world given this long to load there, then the stop done anyway
M.GAP_HOLD_M = 250        -- a stage whose line has more than this of road missing on the map is held out (#30)

M.ui = {}
local R = nil          -- the rally in progress (rally.lua's r), or nil
local savedResults     -- the results in its save (leaveInfo: what leaving now loses)
local ev, board = nil, nil
local blocked = false
local card = nil       -- the last stage's card for the results card: { ss, name, timeS, stage = standing, overall }
local recoveredAt = nil -- (the Super Rally card: shown once at the stop rejoined at)
-- (#58, #69) a question up with no stage under way: { loadAsk = { ss, name, km } } or { ask = { ..., transit = true } },
-- with its key for the HUD's stream. The game is paused while it (or a stage's own Recover?) is up: main.lua.
local question = nil
local loop = nil       -- Realistic: the times since the last save ({ results, started }), kept in the save file
local move = nil       -- the car on its way to a stop by teleport: { item, t, ready }
local toStop = nil     -- a service being driven to: { item, lat, lon, t, distM }
local transitGps = nil -- the next stage's GPS, to set again once the stage before has let the arrows go (#42)
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
function M.moving() return move end

-- The time card's tracker while the stages are got ready (#34): { i, of, name, stages = [{ ss, name, km, state =
-- 'done' | 'failed' | 'now' | 'wait' }], have = [SS of the stages with a line already] }. main.lua adds the stage in
-- progress's detail (its auto recce: going, downloading, window x of y).
function M.prepInfo()
  if not prep then return nil end
  if not ev and R then load(R.eventId) end
  local out = { i = prep.i, of = #prep.list, name = prep.current and prep.current.name, stages = {} }
  for k, st in ipairs(prep.list) do
    local state = 'wait'
    if k < prep.i then
      state = events.stageLine(R.eventId, st.id, st) and 'done' or 'failed'
    elseif k == prep.i then state = 'now' end
    out.stages[k] = { ss = ev and menu.ssLabel(ev, st.id) or nil, name = st.name,
      km = st.lengthM and math.floor(st.lengthM / 100 + 0.5) / 10 or nil, state = state }
  end
  return out
end
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
    if next(R.results or {}) then
      finish()
      if M.ui.openCard then M.ui.openCard() end
    else M.quit() end
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

-- (#68) The stop's board and tent (props' 'service' site) at its place, put down as the car comes near: on the nearest
-- road (props.roadAt), along it. Not set again for the stop it is already for.
local function stopSite(it)
  if not (it and it.place and it.place.lat) then return end
  local s = props.site('service')
  if s and s.lat == it.place.lat and s.lon == it.place.lon and not s.left then return end
  s = props.setSite('service', it.place.lat, it.place.lon, nil)
  s.rally = true
end
-- (left: taken away by distance once the car has driven off, runner's sitesTick)
local function leaveStopSite()
  local s = props.site('service')
  if s then s.left = true end
end
-- The car's distance to the stop's board (game coordinates), or nil while its props are not down.
local function boardM(p)
  local b = props.sitePoint('service')
  if not (b and p and p.lat) then return nil end
  local x, y = earth.toGame(p.lat, p.lon, 0)
  if not x then return nil end
  return math.sqrt((x - b.x) ^ 2 + (y - b.y) ^ 2)
end

-- At the stop the rally is at (the car there): repaired, the rally saved, the time card up.
local function arrive()
  move, toStop = nil, nil
  if not R then return end
  local it = rally.current(R)
  if not it or it.kind == 'stage' then return end
  if runner.current() and not runLive() then pcall(runner.abort, true) end
  gpsOff()
  stopSite(it)
  if it.final then
    -- (#71: checked in at the final service: the rally is done here, kept as finished)
    rally.serviced(R)
    rally.serviceOut(R)
    finish()
    leaveStopSite()
    log('I', logTag, 'rally: at the final service, the rally is over')
    if M.ui.openCard then M.ui.openCard() end
    return
  end
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
  -- (the page stays up on a loading screen until the car is there and the world round it is in: #49)
  if M.ui.loading then M.ui.loading('move', it) elseif M.ui.closeMenu then M.ui.closeMenu() end
  return true
end

-- A service driven to: the GPS set to its place, done once the car is stopped at its board (M.update).
local function driveToStop()
  local it = R and rally.current(R)
  if not (it and it.kind ~= 'stage' and it.place and it.place.lat) then return goToStop() end
  toStop = { item = it, lat = it.place.lat, lon = it.place.lon, t = 0 }
  stopSite(it)
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
  -- (#45, #70) Into the ATC the right way: the GPS through a point a little before it on its own road, then to the
  -- ATC. The road map round the ATC is there only once the car is near: looked for again on the way (M.update).
  local tg = { via = M.approachVia(stage, lat, lon, kind) }
  local function setGps()
    local via = tg.via
    local okR = via and select(2, pcall(earth.gpsRoute, { { lat = via.lat, lon = via.lon, name = title .. ' approach' },
      { lat = lat, lon = lon, name = title .. ' ' .. kind } }))
    if okR ~= true then pcall(earth.gpsSet, lat, lon, title .. ' ' .. kind) end
  end
  setGps()
  -- (#42: armed at the flying finish, the stage's own arrows to its stop control clear the GPS: set again once that
  -- run has let them go, M.update)
  tg.set, tg.again = setGps, not runLive()
  if not tg.via and kind == 'ATC' then tg.lookVia = { stage = stage, lat = lat, lon = lon, kind = kind } end
  transitGps = tg
  local ok = runner.armApproach(ev, stage, { sticky = true, title = title, rally = true,
    startOpts = { rally = true, ssLabel = it.ss, keepDamage = true },
    onStart = function() M.onStageLoaded() end,
    -- (#40: loaded at the ATC, behind the time control card; #58: once the car has stopped there and the player
    -- said yes to "Load the stage?")
    atBoard = true, onArrive = function() M.atControl(it, stage) end,
    onAsk = function() M.askLoad(it, stage) end })
  if not ok then return false, it.ss .. ': the stage could not be got ready' end
  log('I', logTag, 'rally: transit to ' .. title)
  return true
end

-- (#45, #70) A point before the stage's ATC (its start with none) on the road into it, so the GPS brings the car in
-- the way the stage runs: walked back APPROACH_VIA_BACK_M along the road map (props.walkRoad) from the road at the ATC,
-- turned to lead on to the start. Until 1.7.0 rev 4 it was a straight line 150 m back from the start through the ATC,
-- which ignored the roads: where the road into the ATC bends, it landed on another road and the GPS sent the car round
-- the block (the third drive, #70). A point the walk cannot keep on the same road (a sharp turn at a junction, the
-- road map's end) is no point: none is better than one on the wrong road. The way the stage runs: the ATC towards the
-- start, or with the ATC on top of the start the stage line's first stretch. { lat, lon } or nil (no road map there
-- yet: looked for again as the car comes near, M.update).
M.APPROACH_VIA_BACK_M = { 60, 45, 30 }
M.APPROACH_VIA_LOOK_M = 1500      -- (the road map round the ATC looked at from this close)
M.APPROACH_VIA_ON_ROAD_M = 4      -- (the walked point still this close to a road running the same way)
function M.approachVia(stage, lat, lon, kind)
  local ctl = stage.controls or {}
  local line = stage.line
  local fromLat, fromLon
  local st = ctl.start or (line and line[1] and { lat = line[1][1], lon = line[1][2] })
  if kind == 'ATC' and st and geo.metres(lat, lon, st.lat, st.lon) >= 20 then
    fromLat, fromLon = st.lat, st.lon
  elseif line and #line >= 2 then
    -- (the first point some 50 m into the line, carried to the control: the way the stage runs from it)
    local k = 2
    while k < #line and geo.metres(line[1][1], line[1][2], line[k][1], line[k][2]) < 50 do k = k + 1 end
    fromLat, fromLon = lat + (line[k][1] - line[1][1]), lon + (line[k][2] - line[1][2])
  end
  if not fromLat then return nil end
  local d = geo.metres(lat, lon, fromLat, fromLon)
  if not d or d < 1 then return nil end
  -- (fromLat / fromLon is the far side, past the ATC the way the stage runs: towards it is the way the car goes)
  local ax, ay = earth.toGame(lat, lon, 0)
  local tx, ty = earth.toGame(fromLat, fromLon, 0)
  if not (ax and tx) then return nil end
  local edge = props.roadAt(ax, ay, { x = tx - ax, y = ty - ay })
  if not edge then return nil end
  edge = props.orient(edge, { x = tx, y = ty })
  for _, back in ipairs(M.APPROACH_VIA_BACK_M) do
    local w = props.walkRoad(edge, -back)
    local on = w and props.roadAt(w.x, w.y, { x = w.dx, y = w.dy }, M.APPROACH_VIA_ON_ROAD_M)
    if on and math.abs(on.dx * w.dx + on.dy * w.dy) >= 0.9 then
      local vla, vlo = earth.toGeo(w.x, w.y, 0)
      if vla then return { lat = vla, lon = vlo, backM = back } end
    end
  end
  return nil
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
  if M.ui.loading then M.ui.loading('stage', it, stage) end
  return true
end

-- (#58) Stopped at the stage's ATC board: "Load the stage?" asked (the HUD's card, the game paused under it).
function M.askLoad(it, stage)
  if not R then return end
  question = { loadAsk = { ss = it.ss, name = stage.name,
    km = stage.lengthM and math.floor(stage.lengthM / 100 + 0.5) / 10 or nil },
    key = 'load:' .. tostring(it.ss) .. ':' .. tostring(os.clock()) }
  pcall(runner.askLayout, true)
  log('I', logTag, 'rally: stopped at the time control of ' .. tostring(it.ss) .. ', asked to load it')
end

-- The answer: 'load' (the stage loads behind the time control card) or 'notYet' (asked again once the car has left
-- the board and stopped at it again). Returns ok, why.
function M.answerLoad(what)
  if not (question and question.loadAsk) then return false, 'no stage is waiting to load' end
  question = nil
  pcall(runner.askLayout, false)
  return runner.answerLoad(what == 'load')
end

-- (#40) At the stage's ATC: the time control card up over the stage loading, its Continue once it is ready.
function M.atControl(it, stage)
  if not R then return end
  local r = runner.current()
  local tc = { ss = it.ss, name = stage.name, km = stage.lengthM and math.floor(stage.lengthM / 100 + 0.5) / 10,
    day = it.day, rally = R.name, timeIn = r and runner.formatClock(runner.clock() or 0) or nil }
  log('I', logTag, 'rally: at the time control of ' .. tostring(it.ss) .. ', the stage loads behind its card')
  if M.ui.atControl then M.ui.atControl(tc, stage) end
end

-- (runner: the rally's stage loaded, by the transit's arrival or startHere)
function M.onStageLoaded()
  transitGps = nil
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
  R, card, recoveredAt, question, move, toStop = r, nil, nil, nil, nil, nil
  savedResults = nil
  -- (the rally saved before is replaced now, as the start screen says, not only once the car is at the start)
  local t0 = M.readFile(id)
  if t0.current or t0.loop then t0.current, t0.loop = nil, nil writeFile(id, t0) end
  loop = { results = {} }
  M.block(true)
  log('I', logTag, string.format('rally: %s started (%s, %s, cancelled stages %s)', R.name, R.mode, R.class,
    R.cancelled))
  -- (the page stays on the time card, which follows the stages being got ready: #34)
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
  R, card, recoveredAt, question, move, toStop = t.current, nil, nil, nil, nil, nil
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
  getReady(function()
    local it = rally.current(R)
    if it and it.kind ~= 'stage' then goToStop()
    elseif it then
      -- (left between two stages: back at the last stop's place, the transit to the stage driven from there -- a
      -- leave and continue is no skip of a road section, #33)
      local from
      for i = R.pos - 1, 1, -1 do
        local s = R.order[i]
        if s.kind ~= 'stage' then from = s.place and s.place.lat and s break end
      end
      if from and earth.teleport(from.place.lat, from.place.lon, from.place.name or from.label) then
        if M.ui.loading then M.ui.loading('resume', from) end
        move = { item = from, t = 0, ready = 0, thenDo = function()
          local okT, whyT = armTransit()
          if not okT then say(tostring(whyT), 6, 'warning', R.name) end
          if M.ui.openCard then M.ui.openCard() end
        end }
      else
        local ok, why = startHere(it)
        if not ok then say(tostring(why), 6, 'warning', R.name) end
      end
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
  -- (the service's board and tent: taken away now, unless the rally ended there and the car stands by it)
  local s = props.site('service')
  if s and s.rally and not s.left then props.dropSite('service') end
  R, card, recoveredAt, loop, move, toStop, prep = nil, nil, nil, nil, nil, nil, nil
  if question then question = nil pcall(runner.askLayout, false) end
  M.block(false)
  return true
end

-- (#71) The finished card's two buttons, both done with the rally (it is kept as finished already): the run and the
-- stage layout put away, BeamNG's own recovery back. main.lua then opens Home (New rally) or closes the menu
-- (Continue driving). Returns ok, why.
function M.endRally()
  if not R then return true end
  if not rally.over(R) then return false, 'the rally is not over: Save and quit, or Retire' end
  pcall(runner.abort, true)
  return M.quit()
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
      if (it.kind == 'service' or it.kind == 'overnight') and it.place and not recoveredAt then
        if not toStop then driveToStop()
        elseif (toStop.distM or math.huge) <= M.ARRIVE_NEAR_M and M.stoppedNow() then arrive() end
        return true
      end
      goToStop()
      return true
    end
    local wasPlaced = it.place and it.place.lat
    leaveStopSite()
    rally.serviceOut(R)
    recoveredAt = nil
    it = rally.current(R)
    if not it then return false, 'the rally is over' end
    -- (a stop with no place on the map was done where the car stood, which may be anywhere: taken to the stage)
    if not wasPlaced and it.kind == 'stage' then return startHere(it) end
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
    next = nx and (nx.kind == 'stage' and (nx.ss .. ' ' .. stageName(nx)) or nx.label) or nil,
    driven = nx and (nx.kind == 'stage' or ((nx.kind == 'service' or nx.kind == 'overnight') and nx.place ~= nil)) or nil }
  local r = runner.current()
  if r then
    r.rally = { mode = R.mode, card = card }
    r.rallyKey = 'card:' .. it.ss .. ':' .. tostring(res.timeS)
  end
  if rally.over(R) then finish() return end
  if nx.kind == 'stage' then armTransit()
  elseif (nx.kind == 'service' or nx.kind == 'overnight') and nx.place then driveToStop() end
end
runner.onFinished = function(res) M.onFinished(res) end

-- The car stopped (under the stop speed, BeamNG.Earth's pose).
function M.stoppedNow()
  local p = earth.pose()
  return p ~= nil and (p.speed or 0) < runner.STOPPED_MS
end

-- The stop the rally rejoins at after a recovery from item i on: the next stop's label (nil: none).
local function nextStopLabel(from)
  for i = from, #R.order do
    if R.order[i].kind ~= 'stage' then return R.order[i].label end
  end
  return nil
end

-- A question up (#59: the recovery key does nothing then; A on its card answers it).
function M.asking()
  if question then return true end
  local r = R and runner.current()
  return r ~= nil and r.inRally == true and r.rally ~= nil and r.rally.ask ~= nil
end

-- The rally's recovery key (main.backOnRoad). On a transit (no stage loaded, the game's own recovery blocked): in
-- Casual the car put back on the nearest road, free -- road sections are not timed; in Realistic (#69) the Recover?
-- question, as on a stage. During a stage of the rally: below. Returns true when it was the rally's.
function M.recoverKey()
  if not R or R.done then return false end
  -- (#59: a question up is answered on its card, A / B; the key, which is also the pad's "right", does nothing)
  if M.asking() then return true end
  if not M.inRun() or not runLive() then
    if move or prep then return true end
    -- (a stage that failed to start: put away, its transit armed again, the car put back on the road)
    if M.inRun() and runner.current().state == 'failed' then
      pcall(runner.abort, true)
      local it = rally.current(R)
      if it and it.kind == 'stage' then armTransit() end
    end
    -- (#69) Realistic: no free recovery on a transit. Recover = back in at the next service under Super Rally, the
    -- stages before it missed (on the way to a stop, taken to it). Waiting at a stop is no transit: free there.
    local cur = rally.current(R)
    local onTransit = cur and (cur.kind == 'stage' or (toStop ~= nil and not rally.isServiced(R)))
    if R.mode == 'realistic' and onTransit then
      local nx = cur.kind == 'stage' and stageOf(cur)
      question = { ask = { transit = true, ss = cur.kind == 'stage' and cur.ss or nil, name = nx and nx.name or nil,
        stop = cur.kind == 'stage' and nextStopLabel(R.pos) or cur.label },
        key = 'ask:transit:' .. tostring(os.clock()) }
      pcall(runner.askLayout, true)
      log('I', logTag, 'rally: Recover? asked on the transit to ' .. tostring(itemLabel(cur)))
      return true
    end
    local ok = runner.recoverToRoad()
    if not ok then say('No road found near the car.', 3, 'warning', 'Recovery')
    elseif R.mode == 'casual' then M.repair() end      -- (Casual: a car broken on a road section is fixed too)
    return true
  end
  local r = runner.current()
  if R.mode == 'casual' or r.state ~= 'running' then
    runner.backOnRoad()           -- (free: no reset penalty in a rally run)
    return true
  end
  -- Realistic, on the stage: the question (#59: the game paused under it, answered on its card: no time-out, and the
  -- key again is no answer)
  r.rally = r.rally or { mode = R.mode }
  r.rally.ask = { ss = r.ssLabel, name = r.stage and r.stage.name, stop = nextStopLabel(R.pos + 1) }
  r.rallyKey = 'ask:' .. tostring(r.ssLabel) .. ':' .. tostring(os.clock())
  return true
end

-- (the HUD's stream: runner.askSource / askKey) A question with no stage under way, as ours.rally carries it, or nil.
function M.askInfo()
  if not (R and question) then return nil end
  question.mode = R.mode
  return question
end
runner.askSource = function() return M.askInfo() end
runner.askKey = function() return question and question.key or nil end

-- (main.onUpdate) a teleport to a stop settling, a service driven to, a stage started (Realistic: from then on
-- leaving scores it under Super Rally).
function M.update(dt)
  dt = dt or 0
  -- ("Load the stage?" whose approach went -- the rally moved on, a run started: nothing left to answer)
  if question and question.loadAsk then
    local a = runner.approaching()
    if not (a and a.asked) then question = nil pcall(runner.askLayout, false) end
  end
  if not R then return end
  if loop and not loop.started and R.mode == 'realistic' then
    local r = runner.current()
    if r and r.inRally and r.state == 'running' then loop.started = true saveLoop() end
  end
  -- (#42) the transit's GPS set again once the finished stage's run let its arrows go, and whenever it has none
  if transitGps and not move and not toStop then
    local rr = runner.current()
    local cur = rally.current(R)
    if not (cur and cur.kind == 'stage') or not runner.approaching() then transitGps = nil
    elseif not runLive() and not (rr and rr.routeTarget) then
      transitGps.t = (transitGps.t or 0) - dt
      if transitGps.t <= 0 then
        transitGps.t = M.ARRIVE_POLL_S
        -- (not near the ATC: arrived there, BeamNG.Earth's GPS clears itself, and must not be sent round again)
        local ap = runner.approachInfo()
        local far = not (ap and ap.distM) or ap.distM > 300
        -- (#70: the road map round the ATC in now: its direction point on the road, and the GPS set through it)
        local lv = transitGps.lookVia
        if lv and far and ap and ap.distM and ap.distM <= M.APPROACH_VIA_LOOK_M then
          local okV, via = pcall(M.approachVia, lv.stage, lv.lat, lv.lon, lv.kind)
          if okV and via then
            transitGps.lookVia, transitGps.via = nil, via
            transitGps.set()
            log('I', logTag, string.format('rally: the GPS set through %s\'s approach, %d m before its time control',
              tostring(cur.ss), via.backM or 0))
          end
        elseif lv and not far then
          transitGps.lookVia = nil
        end
        if far and (not transitGps.again or earth.gps() == nil) then
          transitGps.again = true
          transitGps.set()
          log('I', logTag, 'rally: the GPS set to ' .. tostring(cur.ss) .. ' again')
        end
      end
    end
  end
  if move then
    move.t = move.t + dt
    move.ready = earth.ready() and move.t > 2 and (move.ready + dt) or 0
    if move.ready >= runner.TELEPORT_SETTLE_S or move.t > M.MOVE_WAIT_S then
      if move.t > M.MOVE_WAIT_S then log('W', logTag, 'rally: the world took long to load at the stop') end
      local thenDo = move.thenDo
      if thenDo then move = nil thenDo() else arrive() end
    end
  elseif toStop then
    toStop.t = toStop.t - dt
    if toStop.t <= 0 then
      toStop.t = M.ARRIVE_POLL_S
      -- (#42) The stage's own arrows (to its stop control) clear BeamNG.Earth's GPS and wipe the road arrows as the run
      -- ends, so the service's GPS set at the finish was gone: set again once the stage's run has let the arrows go,
      -- and whenever the GPS has no destination after that.
      local rr0 = runner.current()
      if not runLive() and not (rr0 and rr0.routeTarget) then
        local g = earth.gps()
        if not toStop.gpsAgain or g == nil then
          toStop.gpsAgain = true
          local it = toStop.item
          pcall(earth.gpsSet, toStop.lat, toStop.lon, it.place and it.place.name or it.label)
          log('I', logTag, 'rally: the GPS set to ' .. tostring(it.label) .. ' again')
        end
      end
      local p = earth.pose()
      if p and p.lat then
        toStop.distM = geo.metres(p.lat, p.lon, toStop.lat, toStop.lon)
        -- (#67, #68: stopped at its board once that is down, else stopped near its point; never at speed)
        toStop.boardM = boardM(p)
        local stopped = (p.speed or 0) < runner.STOPPED_MS
        local there
        if toStop.boardM then there = toStop.boardM <= M.BOARD_ARRIVE_M
        else there = toStop.distM <= M.ARRIVE_NEAR_M end
        local rr = runner.current()
        local cardUp = rr and rr.resultsOpen       -- (the stage's card read first: arriving takes the run away)
        if not runLive() and not cardUp and stopped and there then
          arrive()
        end
      end
    end
  end
end

-- The service being driven to, for the HUD's line and the game's Messages app: { name, distM, rally } or nil.
local tInfo
function M.transitInfo()
  -- (#35) Waiting at a stop (the start, a service, after its card was closed): never nothing on screen. The line says
  -- the rally is ready and how to go on.
  if R and not toStop and not move and not prep and not R.done and not rally.over(R) and not runLive() then
    local it = rally.current(R)
    if it and it.kind ~= 'stage' then
      local nx = rally.nextStage(R)
      local name
      if rally.isServiced(R) then
        name = (it.kind == 'start' and 'Rally ready' or (it.label .. ' done')) ..
          (nx and (' · ' .. nx.ss .. ' ' .. stageName(nx) .. ' next') or '')
      else
        name = 'Next: ' .. tostring(it.label) .. (it.name and (' · ' .. it.name) or '')
      end
      if not (tInfo and tInfo.waiting and tInfo.name == name) then
        tInfo = { name = name, rally = true, waiting = true }
      end
      return tInfo
    end
  end
  if not (R and toStop) then tInfo = nil return nil end
  local d = toStop.distM and math.floor(toStop.distM / 10 + 0.5) * 10 or nil
  -- (#67: near the stop, the line says to stop at its board -- or near its point while its board is not down)
  local near = toStop.boardM or toStop.distM
  local stop = near and near <= runner.STOP_HINT_M and
    (toStop.boardM and 'Stop at the board to check in' or 'Stop here to check in') or nil
  if not (tInfo and tInfo.item == toStop.item and tInfo.distM == d and tInfo.stop == stop) then
    tInfo = { item = toStop.item, name = toStop.item.label .. (toStop.item.name and (' · ' .. toStop.item.name) or ''),
      distM = d, rally = true, stop = stop }
  end
  return tInfo
end

-- The Recover? question answered: 'recover' (the stage ends, Super Rally, the car to the next stop) or 'keep'.
function M.answer(what)
  -- (#69: the transit's question)
  if R and question and question.ask then
    question = nil
    pcall(runner.askLayout, false)
    if what ~= 'recover' then return true end
    local cur = rally.current(R)
    if cur and cur.kind == 'stage' then
      local out, why = rally.recover(R, board)
      if not out then return false, why end
      runner.disarmApproach('recovered on the transit')
      card = nil
      if rally.over(R) then
        finish()
        say('No service is left to rejoin at: the rally ends unclassified.', 6, 'warning', 'Rally over')
        if M.ui.openCard then M.ui.openCard() end
        return true
      end
      recoveredAt = R.pos
    end
    log('I', logTag, 'rally: recovered on the transit, on to ' .. tostring(itemLabel(rally.current(R))))
    goToStop()
    return true
  end
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
events.keepShown = function(id) return R ~= nil and not R.done and R.eventId == id end

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
    -- (#48: an overnight is driven to now, at the service park, as a service is; one with no place is gone to)
    if it and it.kind == 'overnight' and not it.place and not rally.isServiced(R) then goToStop() return true end
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
  -- (#57: the start is on the first stage's day, so its day's header goes above it)
  local firstDay = nil
  for _, it in ipairs(R.order) do if it.kind == 'stage' then firstDay = it.day break end end
  for i, it in ipairs(R.order) do
    local row = { kind = it.kind, label = it.kind == 'stage' and it.ss or it.label, name = it.kind == 'stage'
      and stageName(it) or it.name, km = it.km, day = it.day or (it.kind == 'start' and firstDay or nil),
      next = i == R.pos or nil, done = i < R.pos or nil, final = it.final or nil }
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
    prep = prep and M.prepInfo() or nil,
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
