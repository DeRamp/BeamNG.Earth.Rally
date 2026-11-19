-- earthRally/rally: the full rally (1.7.0 MVP, docs/plan-1.7.0.md): one rally driven start to finish, stage after
-- stage, with services and overnights between them, in Realistic or Casual mode. Pure: no game calls and no files
-- (rallyRun.lua does those), so all of it tests offline (tests/test_rally.lua).
--
-- What is read:
--   event   earthRally/events/<rallyId>.json: id, name, itinerary [{ ss, stage, run, km, day, cancelled }],
--           rallyStops [{ after, kind = 'service' | 'overnight', name, label, place = { name, lat, lon } }] (pack.lua;
--           nil: no event file, so no full rally), rallyStart { name, lat, lon } (where the rally starts, or nil)
--   board   earthRally/boards/<rallyId>.json: passes [{ ss, field = [[seconds, driver, car, class, championship,
--           notional]...] }] (may be nil: no real results, so no Super Rally times from the field and no places)
--
-- A rally in progress (`r`, saved as it is at each service by rallyRun.lua):
--   { format, eventId, name, mode = 'realistic' | 'casual', class, cancelled = 'real' | 'all', car = { name },
--     order = [{ kind = 'stage', ss, stageId, run, km, day } | { kind = 'start' | 'service' | 'overnight', label, name,
--     place = { name, lat, lon } or nil }] (order[1] is always the start: the rally begins at its start or service
--     park, and the first stage is driven to from there), heldOut = [{ ss, stageId, why }] (stages taken out of the
--     rally: their road is not all on the map),
--     pos (the item to do next; #order + 1 when the rally is over), results = { [ss] = { timeS, stageS, penaltyS,
--     superRally, classBestS, addS } }, missed (stages missed so far: Super Rally), serviced = { ['<pos>'] = true }
--     (string keys: the save is JSON),
--     done, unclassified, traffic = 'on' | 'off' (traffic on the road sections; nil in an older save: the world left alone, as on),
--     (format 3, the rally-loop plan: a timed rally only -- nil for an untimed one, and for a format-2 save)
--     timed = true, tz (the event's time zone), clock = { t (the rally clock: local time, worldTime.lua) },
--     lastOut (the last stage's time out, local; nil when unknown), road = { [ss | 'stop<i>'] = { dueT, inT, kind =
--     'onTime' | 'late' | 'early', min, penaltyS, inType } } (the check-ins at the stages' time controls, and at the
--     stops' "in" controls keyed by their place in order, as serviced is), lateSPerMin, earlySPerMin, earlyFree =
--     { [inType] = true } (the "in" controls where early is free: the event's early_checkin_allowed) }
--   Order items of a timed rally carry: stages { date, firstCar, latenessMin, targetMin, outTargetMin, outT };
--   stops and the start { outT } (the scheduled out time, local); stops { inType, inTargetMin } (the control they are
--   checked in at, and the road section's target to it from the stage before), where the event file gives them.
--
-- Super Rally (ARA RCR 6.3.1, the user's choice): a stage missed scores the fastest real National time in your class
-- on that pass, + 10 min for the first stage missed in the rally and + 7 min for each one after. With no National
-- crew of your class on that pass, the fastest National time of all; with no field at all, NOMINAL_KMH over its km.
local wt = require('earthRally/worldTime')

local M = {}

M.FORMAT = 3          -- (2: the start and the stops' places, 1.7.0 revision 2; a 1 save is not continued. 3: the
                      -- rally clock and road penalties, the rally-loop plan; a 2 save still continues, untimed)
M.FORMATS = { [2] = true, [3] = true }
-- (ARA's, RCR 5.3.12: a timed rally whose pack gives no rules)
M.LATE_S_PER_MIN = 10
M.EARLY_S_PER_MIN = 60
M.CHAMPIONSHIP = 'national'
M.SUPER_FIRST_S = 600
M.SUPER_NEXT_S = 420
M.NOMINAL_KMH = 60
M.CLASSES = { 'RC2', 'O4WD', 'L4WD', 'NA4WD', 'O2WD', 'L2WD' }
M.MODES = { realistic = true, casual = true }

local function lower(s) return type(s) == 'string' and s:lower():gsub('^%s+', ''):gsub('%s+$', '') or '' end

-- The class a car is put in when the player picks none: the drivetrain alone (there are no ARA class rules in the
-- data to go further on). 'AWD' / '4WD' -> L4WD, anything else known -> L2WD, nil when it cannot say.
function M.guessClass(drivetrain)
  local d = lower(drivetrain)
  if d == '' then return nil end
  if d:find('awd') or d:find('4wd') or d:find('all') or d:find('4x4') then return 'L4WD' end
  return 'L2WD'
end

-- The running order: the itinerary's passes (its cancelled ones left out with cancelled = 'real'), each stop after
-- the pass it follows. A stop with no pass after it is the finish, not a stop; two stops with nothing between them
-- (a cancelled pass taken out) are one, an overnight if either was.
-- (#71) The rally's last stop: a service driven to after the last stage, with a stop at its board; the rally is done
-- once the car checks in there (rallyRun.arrive).
function M.finalStop(place, name)
  return { kind = 'service', label = 'Final service', name = name or place.name, final = true,
    place = { name = place.name, lat = place.lat, lon = place.lon } }
end

local function orderOf(event, cancelled)
  local stopsAfter = {}
  for _, s in ipairs(event.rallyStops or {}) do
    if type(s) == 'table' and tonumber(s.after) then
      stopsAfter[tonumber(s.after)] = stopsAfter[tonumber(s.after)] or {}
      table.insert(stopsAfter[tonumber(s.after)], s)
    end
  end
  local out = {}
  local function lastIsStop() return out[#out] and out[#out].kind ~= 'stage' end
  local carry = 0       -- (a pass left out: its lateness and road section added to the next one's)
  -- (a pass left out that a scheduled out time stood before -- a service's, the rally's start: that out time goes on
  -- to the next pass kept, as holdOut does, else the clock reset is lost and lateness runs on past the service, or
  -- the opening road section is untimed)
  local carryOut = nil  -- { t, min }
  for i, p in ipairs(event.itinerary or {}) do
    local outT = wt.parse(p.outDate, p.outAt)
    local lat = tonumber(p.latenessMin)
    if not (p.cancelled == true and cancelled ~= 'all') then
      local it = { kind = 'stage', ss = tostring(p.ss), stageId = p.stage, run = p.run, km = p.km, day = p.day,
        cancelledReal = p.cancelled == true or nil }
      -- (the schedule: timed road sections)
      it.date, it.firstCar, it.latenessMin = p.date, p.firstCar, lat
      it.targetMin = tonumber(p.targetMin) and (tonumber(p.targetMin) + carry) or nil
      it.outTargetMin, it.outT = tonumber(p.outTargetMin), outT
      if not it.outT and carryOut then
        it.outT = carryOut.t
        it.outTargetMin = carryOut.min and tonumber(p.targetMin) and (carryOut.min + tonumber(p.targetMin)) or nil
      end
      carry, carryOut = 0, nil
      out[#out + 1] = it
    else
      carry = carry + (tonumber(p.targetMin) or 0) + (lat or 0)
      if outT then
        carryOut = { t = outT, min = tonumber(p.outTargetMin) and (tonumber(p.outTargetMin) + (lat or 0)) or nil }
      elseif carryOut then
        carryOut.min = carryOut.min and tonumber(p.targetMin) and (carryOut.min + tonumber(p.targetMin) + (lat or 0))
          or nil
      end
    end
    for _, s in ipairs(stopsAfter[i] or {}) do
      local kind = s.kind == 'overnight' and 'overnight' or 'service'
      if #out == 0 then
        -- (nothing driven yet: no stop)
      elseif lastIsStop() then
        local l = out[#out]
        -- (#48: a service and an overnight together: the overnight at the service park)
        if kind == 'overnight' then
          if l.kind == 'service' and l.place then l.atService = true else l.place = s.place or l.place end
          l.kind, l.label = 'overnight', 'Overnight'
        end
      else
        -- (its check-in: a pass left out before it adds its road section and lateness, as to a stage's target; a
        -- stop merged into this one keeps this one's, the control driven into)
        out[#out + 1] = { kind = kind, label = s.label or (kind == 'overnight' and 'Overnight' or 'Service'),
          name = s.name, place = s.place, inType = s.inType,
          inTargetMin = tonumber(s.inTargetMin) and (tonumber(s.inTargetMin) + carry) or nil }
      end
    end
  end
  -- (#71, the owner: after the last stage you still drive back to service, and the rally finishes there. The stop the
  -- event has after its last pass when it has a place, else the last day's service park (below). With no service
  -- anywhere, no final service: the rally ends at its last stage, as before. A trailing stop with no place is dropped)
  local trailing, trailIn = nil, nil
  while lastIsStop() do
    if not trailing and out[#out].place then trailing = out[#out] end
    trailIn = out[#out]           -- (once the loop is done: the first stop after the last stage, the one driven into)
    out[#out] = nil
  end
  -- (#48, the owner: you always drive back to service at the end of a day, and the overnight is there. An overnight
  -- is at the last service park before it -- driven to like a service, the car repaired and the rally saved -- and at
  -- its own place only where the rally had no service before it)
  local lastSvc, day = nil, nil
  for _, it in ipairs(out) do
    if it.kind == 'stage' then
      if it.day ~= day then lastSvc = nil end        -- (the day's own service park only)
      day = it.day
    elseif (it.kind == 'service' or it.atService) and it.place then lastSvc = it
    elseif it.kind == 'overnight' and lastSvc then
      it.parcFerme = it.place and it.place.name or it.name
      it.place = { name = lastSvc.place.name, lat = lastSvc.place.lat, lon = lastSvc.place.lon }
      it.name = lastSvc.name or lastSvc.place.name
    end
  end
  -- (the last day's service park: its last service with a place, the day of the last stage)
  local lastDay = nil
  for _, it in ipairs(out) do if it.kind == 'stage' then lastDay = it.day end end
  local park, dayNow = nil, nil
  for _, it in ipairs(out) do
    if it.kind == 'stage' then dayNow = it.day
    elseif dayNow == lastDay and it.place and (it.kind == 'service' or it.atService) then park = it end
  end
  -- (a stop's scheduled out time: the one the stage after it starts its road section from)
  for k = 2, #out do
    if out[k].kind == 'stage' and out[k].outT and out[k - 1].kind ~= 'stage' then out[k - 1].outT = out[k].outT end
  end
  local fin = trailing or park
  if fin and #out > 0 then
    local f = M.finalStop(fin.place, fin.kind == 'service' and fin.name or (park and park.name) or fin.name)
    -- (its check-in: the stop it stands for, else the stretch after the last pass -- the finish's MTC in)
    local tf = type(event.timing) == 'table' and type(event.timing.finish) == 'table' and event.timing.finish or nil
    if trailIn and trailIn.inTargetMin then
      f.inType, f.inTargetMin = trailIn.inType, trailIn.inTargetMin
    elseif tf then
      f.inType = tf.inType
      f.inTargetMin = tonumber(tf.inTargetMin) and (tonumber(tf.inTargetMin) + carry) or nil
    end
    out[#out + 1] = f
  end
  -- (the services lettered again in this order: one merged away, or the first after a cancelled day, keeps A, B...)
  local n = 0
  for _, it in ipairs(out) do
    if it.kind == 'service' and not it.final then
      n = n + 1
      it.label = 'Service ' .. string.char(64 + math.min(n, 26))
    end
  end
  return out
end
M._orderOf = orderOf

-- Whether a rally can be run as a full rally: an event file (its stops read) and at least one pass.
function M.canRun(event)
  return type(event) == 'table' and type(event.rallyStops) == 'table' and type(event.itinerary) == 'table'
    and #event.itinerary > 0
end

-- Whether any of its passes was cancelled on the day (the start screen offers the choice only then).
function M.cancelledPasses(event)
  local out = {}
  for _, p in ipairs((event and event.itinerary) or {}) do
    if p.cancelled == true then out[#out + 1] = tostring(p.ss) end
  end
  return out
end

-- A new rally. opts: { mode, class, cancelled, car = { name } }. Returns r, or nil and why.
function M.new(event, opts)
  if not M.canRun(event) then return nil, 'this rally has no event file, so it cannot be run as a full rally' end
  opts = opts or {}
  local mode = M.MODES[opts.mode] and opts.mode or 'realistic'
  local cancelled = opts.cancelled == 'all' and 'all' or 'real'
  local order = orderOf(event, cancelled)
  local nStages = 0
  for _, it in ipairs(order) do if it.kind == 'stage' then nStages = nStages + 1 end end
  if nStages == 0 then return nil, 'no stage of this rally is left to drive' end
  -- (the start: where the rally begins, at its start or service park when the event file says where that is)
  local st = type(event.rallyStart) == 'table' and type(event.rallyStart.lat) == 'number' and event.rallyStart or nil
  local tm = type(event.timing) == 'table' and event.timing or nil
  local startT = tm and type(tm.start) == 'table' and wt.parse(tm.start.date, tm.start.time) or nil
  table.insert(order, 1, { kind = 'start', label = 'Start', name = st and st.name or nil,
    place = st and { name = st.name, lat = st.lat, lon = st.lon } or nil, outT = startT })
  local r = { format = M.FORMAT, eventId = event.id, name = event.name, mode = mode,
    class = type(opts.class) == 'string' and opts.class ~= '' and opts.class or 'L4WD', cancelled = cancelled,
    car = type(opts.car) == 'table' and { name = opts.car.name } or nil,
    order = order, pos = 1, results = {}, missed = 0, serviced = {}, done = false, heldOut = {},
    -- (traffic on the road sections, the start screen's choice: 'on' | 'off'; nil in a save from before = on)
    traffic = opts.traffic == 'on' and 'on' or 'off' }
  -- (interface 1: timed when the event has target times, and so a start on its clock)
  if startT then
    local rules = type(event.rules) == 'table' and event.rules or {}
    r.timed, r.tz, r.clock, r.road = true, tm.timezone, { t = startT }, {}
    r.lateSPerMin = tonumber(rules.lateSPerMin) or M.LATE_S_PER_MIN
    r.earlySPerMin = tonumber(rules.earlySPerMin) or M.EARLY_S_PER_MIN
    if type(tm.earlyFree) == 'table' then
      r.earlyFree = {}
      for k, v in pairs(tm.earlyFree) do if v == true then r.earlyFree[k] = true end end
    end
  end
  return r
end

------------------------------------------------------------------------------------------ the rally clock
-- (the rally-loop plan, item 1; ARA RCR 5.3.9, 5.4.4) Due at a stage's time control = the time the road section
-- before it starts from + its target time. It starts from the scheduled out time of the stop or start before it (a
-- service resets you to the schedule), else from the last stage's time out. Local times (worldTime.lua), whole
-- minutes. nil: not known (an untimed rally or section, a stage given up before it).
-- A stop (additions B): due at its "in" control at the stage before it's time out + inTargetMin -- so only the stop
-- right after the stage just done has one (a stage's time out is never known in advance).
function M.dueFor(r, i)
  if not (r and r.timed) then return nil end
  local it = r.order[i]
  if it and it.kind ~= 'stage' and it.kind ~= 'start' then
    local prev = r.order[i - 1]
    local target = tonumber(it.inTargetMin)
    if not (prev and prev.kind == 'stage' and r.results[prev.ss] and r.lastOut and target) then return nil end
    return math.floor(r.lastOut / 60) * 60 + target * 60
  end
  if not (it and it.kind == 'stage') then return nil end
  local prev = r.order[i - 1]
  local base, target
  if prev and prev.kind ~= 'stage' and prev.outT and it.outT == prev.outT then
    base, target = prev.outT, it.outTargetMin
  else
    base, target = r.lastOut, it.targetMin
  end
  if not (base and target) then return nil end
  return math.floor(base / 60) * 60 + target * 60
end

-- A stage's time out: its start time + its lateness time; a stage that took longer: its finish, to the minute down
-- (RCR 5.3.9 a). startT, finishT: local times.
function M.timeOut(item, startT, finishT)
  if not startT then return nil end
  local fin = finishT and math.floor(finishT / 60) * 60 or nil
  local lat = item and tonumber(item.latenessMin)
  if lat then
    local t = math.floor(startT / 60) * 60 + lat * 60
    return (fin and fin > t) and fin or t
  end
  return fin
end

-- The check-in at a stage's time control: on time in the due minute, late or early by whole minutes (a minute or part
-- of one), each late minute lateSPerMin, each early one earlySPerMin when early check-ins cost (earlyPenalty), else
-- nothing. Kept in r.road under key: a stop's 'stop<i>' (its place in order, as serviced keys it), else the stage's
-- ss. At a stop's "in" control the event lets you reach early (r.earlyFree[item.inType]: a regroup, the finish),
-- early is free whatever the setting. Returns { kind, min, penaltyS, free (early allowed there) }.
function M.checkIn(r, item, inT, dueT, earlyPenalty, key)
  local res = { kind = 'onTime', min = 0, penaltyS = 0 }
  if not (r and r.timed and item and inT and dueT) then return res end
  local free = item.inType ~= nil and type(r.earlyFree) == 'table' and r.earlyFree[item.inType] == true
  res.free = free or nil
  local diff = math.floor(inT / 60) - math.floor(dueT / 60)
  if diff > 0 then
    res.kind, res.min, res.penaltyS = 'late', diff, diff * (r.lateSPerMin or M.LATE_S_PER_MIN)
  elseif diff < 0 then
    res.kind, res.min = 'early', -diff
    res.penaltyS = (earlyPenalty and not free) and -diff * (r.earlySPerMin or M.EARLY_S_PER_MIN) or 0
  end
  r.road = type(r.road) == 'table' and r.road or {}
  r.road[key or item.ss] = { dueT = dueT, inT = inT, kind = res.kind, min = res.min, penaltyS = res.penaltyS,
    inType = item.inType }
  return res
end

-- The road penalties so far (s).
function M.roadPenaltyS(r)
  local t = 0
  for _, x in pairs(type(r and r.road) == 'table' and r.road or {}) do t = t + (tonumber(x.penaltyS) or 0) end
  return t
end

-- Every pass of a stage still to come taken out of the rally (#30: its road is not all on the map, so it cannot be
-- driven): not scored, listed in r.heldOut. Two stops left side by side are one (an overnight if either was), and a
-- stop with no stage after it goes. The stop the rally is at stays. Returns how many passes went.
function M.holdOut(r, stageId, why)
  local n = 0
  r.heldOut = type(r.heldOut) == 'table' and r.heldOut or {}
  for i = #r.order, r.pos, -1 do
    local it = r.order[i]
    if it.kind == 'stage' and it.stageId == stageId and not r.results[it.ss] then
      table.remove(r.order, i)
      -- (a timed rally: its lateness and road section go to the stage after it, so that one's due time still adds up)
      local nx, pv = r.order[i], r.order[i - 1]
      -- (a stop right after it is checked in at the end of its road section now: that and its lateness added)
      if nx and nx.kind ~= 'stage' and nx.inTargetMin then
        nx.inTargetMin = it.targetMin and (nx.inTargetMin + it.targetMin + (it.latenessMin or 0)) or nil
      end
      if nx and nx.kind == 'stage' then
        local add = (it.latenessMin or 0)
        if it.outT and pv and pv.kind ~= 'stage' then
          nx.outT = it.outT
          nx.outTargetMin = it.outTargetMin and (it.outTargetMin + add + (nx.targetMin or 0)) or nil
        elseif nx.targetMin and it.targetMin then
          nx.targetMin = nx.targetMin + it.targetMin + add
        end
      end
      table.insert(r.heldOut, 1, { ss = it.ss, stageId = stageId, why = why })
      n = n + 1
    end
  end
  if n == 0 then return 0 end
  -- (#71: the final service taken off while the stops left side by side are merged, and put back after: a stop
  -- before it is not merged into it, nor is it dropped as a stop with no stage after it)
  local final = nil
  if #r.order > r.pos and r.order[#r.order].final then final = table.remove(r.order) end
  -- (from after pos: a stop already passed stays as it was; one the rally now stands at is its next stop)
  local i = math.max(2, r.pos + 1)
  while i <= #r.order do
    local a, b = r.order[i - 1], r.order[i]
    if a.kind ~= 'stage' and b.kind ~= 'stage' then
      -- (#48: the overnight is at the service park: the service's place kept)
      if b.kind == 'overnight' and a.kind == 'service' then a.kind, a.label, a.place = 'overnight', 'Overnight', a.place or b.place end
      -- (the later stop's out time is the one the stage after them starts from: serviceOut and dueFor agree; the
      -- first one's check-in kept, the control driven into)
      a.outT = b.outT or a.outT
      table.remove(r.order, i)
    else
      i = i + 1
    end
  end
  local dropped = nil
  while #r.order > r.pos and r.order[#r.order].kind ~= 'stage' do
    dropped = r.order[#r.order]
    r.order[#r.order] = nil
  end
  -- (nothing left to drive: the rally is over)
  if M.stagesLeft(r) == 0 then r.pos, r.done = #r.order + 1, true return n end
  if final then
    -- (a stop dropped after the last stage: the final service is checked in at its control, the one driven into)
    if dropped then final.inType, final.inTargetMin = dropped.inType, dropped.inTargetMin end
    r.order[#r.order + 1] = final
  end
  return n
end

-- How many stages are left to drive from where the rally is.
function M.stagesLeft(r)
  local n = 0
  for i = r.pos, #r.order do if r.order[i].kind == 'stage' then n = n + 1 end end
  return n
end

-- A rally read back from its save: r, or nil when it is not one this reader knows.
function M.valid(r)
  return type(r) == 'table' and M.FORMATS[r.format] == true and type(r.order) == 'table' and #r.order > 0
    and type(r.pos) == 'number' and type(r.results) == 'table' and M.MODES[r.mode] ~= nil
end

function M.current(r) return r and r.order[r.pos] or nil end
function M.over(r) return r == nil or r.done == true or r.pos > #r.order end

-- The next stage from where the rally is (the current item, or the first stage after it), and its index.
function M.nextStage(r)
  for i = r.pos, #r.order do
    if r.order[i].kind == 'stage' then return r.order[i], i end
  end
  return nil
end

-- The stages driven or scored so far, in running order (each { item, result }).
function M.doneStages(r)
  local out = {}
  for _, it in ipairs(r.order) do
    if it.kind == 'stage' and r.results[it.ss] then out[#out + 1] = { item = it, result = r.results[it.ss] } end
  end
  return out
end

-- The rally total: the stage times, and the road penalties (a timed rally).
function M.totalS(r)
  local t = 0
  for _, d in ipairs(M.doneStages(r)) do t = t + (d.result.timeS or 0) end
  return t + M.roadPenaltyS(r)
end

local function finishIfOver(r)
  if r.pos > #r.order then r.done = true end
end

-- The stage driven to its finish: its time kept, the rally on to the next item. res: { timeS, stageS, penaltyS }.
-- Returns the item driven, or nil and why.
function M.stageDone(r, res)
  local it = M.current(r)
  if not (it and it.kind == 'stage') then return nil, 'the rally is not on a stage' end
  r.results[it.ss] = { timeS = res.timeS, stageS = res.stageS, penaltyS = res.penaltyS or 0 }
  -- (a timed rally: the road section on from it starts at its time out)
  if r.timed then r.lastOut = res.outT end
  r.lastPos = r.pos
  r.pos = r.pos + 1
  finishIfOver(r)
  return it
end

-- Casual only: the stage just driven again (its time taken back). Returns the stage item, or nil and why.
function M.restart(r)
  if r.mode ~= 'casual' then return nil, 'no restarts in Realistic mode' end
  if M.over(r) then return nil, 'the rally is over' end
  local i = r.lastPos
  local it = i and r.order[i]
  if not (it and it.kind == 'stage') then return nil, 'no stage to restart' end
  -- (only while nothing has been done since: a service out of the way, the next stage started, it is gone)
  for j = i + 1, math.min(r.pos, #r.order) do
    if M.isServiced(r, j) then return nil, 'the service after it is done' end
  end
  r.results[it.ss] = nil
  r.pos, r.lastPos, r.done = i, nil, false
  return it
end

-- The National field on a pass: rows { timeS, name, class, car }, fastest first, notional times left out (they are
-- assigned, not driven) unless withNotional (the overall totals: the real classification counts them). nil when the
-- board has no such pass.
function M.field(board, ss, withNotional)
  if type(board) ~= 'table' then return nil end
  for _, p in ipairs(board.passes or {}) do
    if tostring(p.ss) == tostring(ss) then
      local rows, seen = {}, {}
      for _, f in ipairs(p.field or {}) do
        if type(f) == 'table' and type(f[1]) == 'number' and (withNotional or f[6] ~= true)
          and lower(f[5]) == M.CHAMPIONSHIP then
          local key = lower(f[2])
          if key ~= '' and not seen[key] then
            seen[key] = true
            rows[#rows + 1] = { timeS = f[1], name = f[2], car = f[3], class = f[4], key = key }
          end
        end
      end
      table.sort(rows, function(a, b) return a.timeS < b.timeS end)
      return rows
    end
  end
  return nil
end

-- The time a missed stage scores: { timeS, classBestS, addS, from = 'class' | 'field' | 'nominal' }.
-- nth: how many stages have been missed in the rally, this one included.
function M.superRallyTime(board, item, class, nth)
  local add = nth <= 1 and M.SUPER_FIRST_S or M.SUPER_NEXT_S
  local rows = M.field(board, item.ss) or {}
  local best, from = nil, nil
  for _, row in ipairs(rows) do
    if lower(row.class) == lower(class) then best, from = row.timeS, 'class' break end
  end
  if not best and rows[1] then best, from = rows[1].timeS, 'field' end
  if not best then
    best, from = (tonumber(item.km) or 10) / M.NOMINAL_KMH * 3600, 'nominal'
    best = math.floor(best * 10 + 0.5) / 10
  end
  return { timeS = best + add, classBestS = best, addS = add, from = from }
end

-- (the owner, rev 4) A rally with no stop at all in its running order -- no service, overnight or regroup, only its
-- start and its stages: there a recovery rejoins at the next stage's start, not at a service.
function M.noStops(r)
  for _, it in ipairs(r.order or {}) do
    if it.kind ~= 'stage' and it.kind ~= 'start' then return false end
  end
  return true
end

-- Realistic: the stage given up. It and every stage before the next service or overnight score Super Rally times,
-- and the rally goes on from that stop. With none left, the rally ends unclassified. A rally with no stops at all
-- (M.noStops): only the stage given up scores Super Rally, and the rally goes on at the next stage (out.stage).
-- Returns { missed = [{ item, result }], stop = the stop rejoined at or nil, stage = the stage rejoined at or nil },
-- or nil and why.
function M.recover(r, board)
  if r.mode ~= 'realistic' then return nil, 'recovering ends a stage in Realistic mode only' end
  local it = M.current(r)
  if not (it and it.kind == 'stage') then return nil, 'the rally is not on a stage' end
  local out = { missed = {} }
  local i = r.pos
  local one = M.noStops(r)
  while i <= #r.order and r.order[i].kind == 'stage' and not (one and i > r.pos) do
    local st = r.order[i]
    r.missed = (r.missed or 0) + 1
    local sr = M.superRallyTime(board, st, r.class, r.missed)
    local res = { timeS = sr.timeS, superRally = true, classBestS = sr.classBestS, addS = sr.addS, from = sr.from }
    r.results[st.ss] = res
    out.missed[#out.missed + 1] = { item = st, result = res }
    i = i + 1
  end
  r.lastPos = nil
  r.lastOut = nil      -- (no time out of a stage given up: the next road section is untimed unless a stop resets it)
  -- (#71: the final service is where the rally finishes, not a stop to rejoin at: the last stages given up end it
  -- unclassified, as before there was one)
  if i <= #r.order and r.order[i].final then i = #r.order + 1 end
  if i > #r.order then
    r.pos, r.done, r.unclassified = #r.order + 1, true, true
  else
    r.pos = i
    if r.order[i].kind == 'stage' then out.stage = r.order[i] else out.stop = r.order[i] end
  end
  r.superRally = out.missed
  return out
end

-- The stop the rally is at done: the car repaired (the caller), the rally saved (the caller), and now out of it.
function M.isServiced(r, pos) return type(r.serviced) == 'table' and r.serviced[tostring(pos or r.pos)] == true end
function M.serviced(r)
  local it = M.current(r)
  if not (it and it.kind ~= 'stage') then return false end
  r.serviced = type(r.serviced) == 'table' and r.serviced or {}
  r.serviced[tostring(r.pos)] = true
  return true
end
-- A Realistic loop cut short by a quit (the save holds the times since the last service, not the car): back where
-- the loop got to. loop = { results = { stage results, in order }, started = a stage begun and not finished }. The
-- stage begun counts as recovered (Super Rally): quitting is no free restart. Returns r.
function M.replayLoop(r, loop, board)
  if type(loop) ~= 'table' or r.mode ~= 'realistic' then return r end
  local res = type(loop.results) == 'table' and loop.results or {}
  if #res == 0 and not loop.started then return r end
  local it = M.current(r)
  if it and it.kind ~= 'stage' then M.serviceOut(r) end
  for _, x in ipairs(res) do
    if M.over(r) then break end
    -- (a stage given up with no service to rejoin at: scored under Super Rally again, the rally on at the next stage)
    if x.recovered then
      if not M.recover(r, board) then break end
    elseif not M.stageDone(r, x) then break end
  end
  it = M.current(r)
  if loop.started and it and it.kind == 'stage' then M.recover(r, board) end
  return r
end

function M.serviceOut(r)
  local it = M.current(r)
  if not (it and it.kind ~= 'stage') then return nil end
  -- (a timed rally: out at the stop's scheduled time -- the clock jumps, lateness never carries past it)
  if r.timed and it.outT and type(r.clock) == 'table' then r.clock.t = it.outT end
  r.superRally = nil
  r.pos = r.pos + 1
  finishIfOver(r)
  return M.current(r)
end

-- Ranked: rows sorted by timeS, with you (yourS) placed after the crews you tie with. { pos, of }.
local function placeIn(times, yourS)
  local pos = 1
  for _, t in ipairs(times) do if t <= yourS + 1e-6 then pos = pos + 1 end end
  return pos, #times + 1
end

-- Your place on one pass: { pos, of, classPos, classOf, rows = the crews round you (and the top three) } or nil
-- with no field.
M.ROWS_TOP, M.ROWS_NEAR = 3, 1
function M.stageStanding(board, item, timeS, class)
  local rows = M.field(board, item.ss)
  if not rows or #rows == 0 or type(timeS) ~= 'number' then return nil end
  local all, cls = {}, {}
  for _, row in ipairs(rows) do
    all[#all + 1] = row.timeS
    if lower(row.class) == lower(class) then cls[#cls + 1] = row.timeS end
  end
  local pos, of = placeIn(all, timeS)
  local cpos, cof = placeIn(cls, timeS)
  -- the list: the top ROWS_TOP, then you with ROWS_NEAR either side
  local list = {}
  for i, row in ipairs(rows) do
    local p = i < pos and i or i + 1
    list[#list + 1] = { pos = p, name = row.name, class = row.class, timeS = row.timeS }
  end
  table.insert(list, pos, { pos = pos, you = true, name = 'You', class = class, timeS = timeS })
  local lead = list[1].timeS
  local shown, gap = {}, false
  for i, row in ipairs(list) do
    row.gapS = row.timeS - lead
    if i <= M.ROWS_TOP or math.abs(i - pos) <= M.ROWS_NEAR then
      if gap then shown[#shown + 1] = { gap = true } gap = false end
      shown[#shown + 1] = row
    else
      gap = true
    end
  end
  if gap then shown[#shown + 1] = { gap = true } end
  return { pos = pos, of = of, classPos = cpos, classOf = cof, rows = shown }
end

-- Your place overall after the stages done so far, against the National crews with a time on every one of them:
-- { pos, of, classPos, classOf, gapS (to the leader) } or nil with no field.
function M.standing(r, board)
  local done = M.doneStages(r)
  if #done == 0 or type(board) ~= 'table' then return nil end
  local acc, n = {}, 0
  for _, d in ipairs(done) do
    local rows = M.field(board, d.item.ss, true)
    if rows and #rows > 0 then
      n = n + 1
      for _, row in ipairs(rows) do
        local a = acc[row.key] or { n = 0, t = 0, class = row.class }
        if a.n == n - 1 then a.n, a.t = n, a.t + row.timeS end
        acc[row.key] = a
      end
    end
  end
  if n == 0 then return nil end
  -- (your total over the same passes: the ones with a field, and your road penalties, as "Your total" counts them)
  local mine = M.roadPenaltyS(r)
  for _, d in ipairs(done) do
    local rows = M.field(board, d.item.ss, true)
    if rows and #rows > 0 then mine = mine + (d.result.timeS or 0) end
  end
  local all, cls = {}, {}
  for _, a in pairs(acc) do
    if a.n == n then
      all[#all + 1] = a.t
      if lower(a.class) == lower(r.class) then cls[#cls + 1] = a.t end
    end
  end
  if #all == 0 then return nil end
  table.sort(all)
  local pos, of = placeIn(all, mine)
  local cpos, cof = placeIn(cls, mine)
  return { pos = pos, of = of, classPos = cpos, classOf = cof, gapS = mine - math.min(all[1], mine), totalS = mine }
end

-- A finished rally as it is kept for the Results tab: { totalS, mode, class, car, unclassified, date, passes, stops,
-- roadPenaltyS, roadKept }. A timed rally's passes carry roadS (the road penalty getting to its time control; nil with none),
-- and stops lists each stop checked in at a cost: { label, inType, min, penaltyS, after (the ss of the stage before) }.
function M.finished(r, date)
  local passes = {}
  local road = r.timed and type(r.road) == 'table' and r.road or {}
  for _, d in ipairs(M.doneStages(r)) do
    local x = road[d.item.ss]
    local pen = x and tonumber(x.penaltyS)
    passes[#passes + 1] = { ss = d.item.ss, timeS = d.result.timeS, superRally = d.result.superRally or nil,
      roadS = (pen and pen > 0) and pen or nil }
  end
  -- (a stop gets a chip only where it cost something: an on-time or free check-in adds none)
  local stops, after = {}, nil
  for i, it in ipairs(r.order or {}) do
    if it.kind == 'stage' then
      after = it.ss
    elseif it.kind ~= 'start' then
      local x = road['stop' .. i]
      local pen = x and tonumber(x.penaltyS)
      if pen and pen > 0 then
        stops[#stops + 1] = { label = it.label, inType = x.inType or it.inType, min = x.min, penaltyS = pen,
          after = after }
      end
    end
  end
  return { totalS = math.floor(M.totalS(r) * 10 + 0.5) / 10, mode = r.mode, class = r.class,
    car = r.car and r.car.name or nil, unclassified = r.unclassified or nil, date = date, passes = passes,
    stops = #stops > 0 and stops or nil, roadPenaltyS = r.timed and M.roadPenaltyS(r) or nil,
    -- (roadS and stops kept: a timed rally finished before this has neither, and its Results strip stays as it was)
    roadKept = r.timed and true or nil }
end

-- Your finished rallies' best, for the Results tab: a classified Realistic one (the lowest total) before any Casual
-- one -- Casual's free recoveries and restarts would beat it every time -- then a classified Casual one, then an
-- unclassified one. nil with none.
local function rankOf(f)
  if f.unclassified then return 3 end
  return f.mode == 'realistic' and 1 or 2
end
function M.bestFinished(list)
  local best = nil
  for _, f in ipairs(list or {}) do
    if type(f) == 'table' and type(f.totalS) == 'number' then
      if not best or rankOf(f) < rankOf(best) or (rankOf(f) == rankOf(best) and f.totalS < best.totalS - 1e-6) then
        best = f
      end
    end
  end
  return best
end

-- Where a finished rally places against the real National totals (the crews with a time on every pass it scored):
-- { pos, of, classPos, classOf } or nil.
function M.finishedStanding(f, board)
  if type(f) ~= 'table' or f.unclassified then return nil end
  local r = { class = f.class, order = {}, results = {},
    road = tonumber(f.roadPenaltyS) and { all = { penaltyS = tonumber(f.roadPenaltyS) } } or nil }
  for _, p in ipairs(f.passes or {}) do
    r.order[#r.order + 1] = { kind = 'stage', ss = p.ss }
    r.results[p.ss] = { timeS = p.timeS }
  end
  return M.standing(r, board)
end

return M
