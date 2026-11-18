-- The full rally (1.7.0): rally.lua's running order, Super Rally, Casual restarts, the places against the field, a
-- save that survives JSON, and pack.lua's services read from an event file. All on a made-up rally: every time and
-- every name is invented. No organisers' data here.
local T = dofile(TESTS .. '/testlib.lua')
function log() end
local rally = require('earthRally/rally')
local pack = require('earthRally/pack')

------------------------------------------------------------------------------------------ a made-up rally

-- 10 passes over 5 roads, two days: Service A after SS3, overnight after SS6, Service B after SS8. SS7 was cancelled.
local function event()
  local it = {}
  local spec = { { 'SS1', 'a', 1, 1 }, { 'SS2', 'b', 1, 1 }, { 'SS3', 'c', 1, 1 }, { 'SS4', 'a', 2, 1 },
    { 'SS5', 'b', 2, 1 }, { 'SS6', 'c', 2, 1 }, { 'SS7', 'd', 1, 2 }, { 'SS8', 'e', 1, 2 }, { 'SS9', 'd', 2, 2 },
    { 'SS10', 'e', 2, 2 } }
  for i, x in ipairs(spec) do
    it[i] = { ss = x[1], stage = x[2], run = x[3], day = x[4], km = 10 + i, cancelled = x[1] == 'SS7' }
  end
  return { id = 'made-up', name = 'Made-up Rally', itinerary = it,
    rallyStops = { { after = 3, kind = 'service', name = 'The Park', label = 'Service A' },
      { after = 6, kind = 'overnight', label = 'Overnight' },
      { after = 8, kind = 'service', name = 'The Park', label = 'Service B' } } }
end

-- the field: four National crews and one regional, on SS1-SS3 and SS4
local function row(t, name, class, champ, notional) return { t, name, 'Car', class, champ or 'national', notional == true } end
local board = { passes = {
  { ss = 'SS1', field = { row(700, 'Ann Able', 'RC2'), row(720, 'Ben Bold', 'L4WD'), row(760, 'Cal Calm', 'L4WD'),
    row(800, 'Dee Dune', 'L2WD'), row(650, 'Reg Ional', 'RC2', 'regional') } },
  { ss = 'SS2', field = { row(300.0, 'Ann Able', 'RC2'), row(303.7, 'Ben Bold', 'L4WD'), row(310, 'Cal Calm', 'L4WD'),
    row(330, 'Dee Dune', 'L2WD'), row(200, 'Zed Notional', 'L4WD', 'national', true) } },
  { ss = 'SS3', field = { row(860, 'Ann Able', 'RC2'), row(851.2, 'Cal Calm', 'L4WD'), row(870, 'Ben Bold', 'L4WD'),
    row(900, 'Dee Dune', 'L2WD') } },
  { ss = 'SS4', field = { row(690, 'Ann Able', 'RC2'), row(800, 'Dee Dune', 'L2WD') } },
} }

-- (a rally out of its start and on its way to SS1: what every test below the running order begins with)
local function newR(e, opts)
  local r = rally.new(e, opts)
  rally.serviced(r)
  rally.serviceOut(r)
  return r
end

------------------------------------------------------------------------------------------ the running order

do
  local r = rally.new(event(), { mode = 'realistic', class = 'L4WD' })
  local labels = {}
  for _, it in ipairs(r.order) do labels[#labels + 1] = it.kind == 'stage' and it.ss or it.label end
  T.check(table.concat(labels, ' ') == 'Start SS1 SS2 SS3 Service A SS4 SS5 SS6 Overnight SS8 Service B SS9 SS10',
    'as it really ran: ' .. table.concat(labels, ' '))
  local all = rally.new(event(), { cancelled = 'all' })
  labels = {}
  for _, it in ipairs(all.order) do labels[#labels + 1] = it.kind == 'stage' and it.ss or it.label end
  T.check(table.concat(labels, ' ') == 'Start SS1 SS2 SS3 Service A SS4 SS5 SS6 Overnight SS7 SS8 Service B SS9 SS10',
    'run them all: ' .. table.concat(labels, ' '))
  T.check(rally.cancelledPasses(event())[1] == 'SS7', 'the cancelled pass is named for the start screen')
  T.check(all.mode == 'realistic', 'Realistic unless Casual is asked for')
end

do
  -- a stop with nothing after it is the finish; two stops with only a cancelled pass between them are one
  local e = event()
  e.rallyStops[#e.rallyStops + 1] = { after = 10, kind = 'service', label = 'Service C' }
  e.rallyStops[#e.rallyStops + 1] = { after = 7, kind = 'service', label = 'Service X' }
  local r = rally.new(e, {})
  local labels = {}
  for _, it in ipairs(r.order) do labels[#labels + 1] = it.kind == 'stage' and it.ss or it.label end
  T.check(table.concat(labels, ' ') == 'Start SS1 SS2 SS3 Service A SS4 SS5 SS6 Overnight SS8 Service B SS9 SS10',
    'a trailing stop dropped, two stops merged into the overnight: ' .. table.concat(labels, ' '))
  T.check(rally.new({ id = 'x', itinerary = e.itinerary }) == nil, 'no event file (no stops read): no full rally')
end

------------------------------------------------------------------------------------------ Realistic and Super Rally

do
  local r = newR(event(), { mode = 'realistic', class = 'L4WD' })
  T.check(rally.current(r).ss == 'SS1', 'the rally starts at SS1')
  rally.stageDone(r, { timeS = 898.0, stageS = 898.0, penaltyS = 0 })
  T.check(rally.current(r).ss == 'SS2', 'on to SS2')
  T.check(rally.restart(r) == nil, 'no restarts in Realistic')
  local out = rally.recover(r, board)
  T.check(out and #out.missed == 2, 'SS2 given up: it and SS3 are missed')
  T.near(r.results.SS2.timeS, 903.7, 1e-6, 'SS2: the L4WD fastest + 10 min')
  T.near(r.results.SS3.timeS, 1271.2, 1e-6, 'SS3: the L4WD fastest + 7 min')
  T.check(r.results.SS2.from == 'class', 'from the class')
  T.check(out.stop and out.stop.label == 'Service A' and rally.current(r).label == 'Service A',
    'back in at Service A')
  T.check(not rally.isServiced(r), 'the service is still to be done')
  T.check(rally.serviced(r) and rally.isServiced(r), 'the service done')
  rally.serviceOut(r)
  T.check(rally.current(r).ss == 'SS4', 'and on from SS4')
  -- a later stage given up: + 7 min, the class missing on that pass -> the fastest National time
  rally.stageDone(r, { timeS = 700 })
  rally.stageDone(r, { timeS = 330 })
  rally.recover(r, board)        -- SS6: no field at all -> nominal
  T.check(r.results.SS6.from == 'nominal', 'no field on the pass: a nominal time')
  T.near(r.results.SS6.addS, 420, 1e-6, 'a third stage missed: + 7 min')
  T.check(rally.current(r).label == 'Overnight', 'back in at the overnight')
  local sr = rally.superRallyTime(board, { ss = 'SS4' }, 'L4WD', 4)
  T.check(sr.from == 'field' and math.abs(sr.timeS - (690 + 420)) < 1e-6, 'no L4WD on SS4: the fastest National')
  -- the last stage given up: nothing to rejoin at
  rally.serviceOut(r)
  rally.stageDone(r, { timeS = 600 })      -- SS8
  rally.serviceOut(r)                       -- Service B
  rally.stageDone(r, { timeS = 600 })      -- SS9
  local last = rally.recover(r, board)     -- SS10
  T.check(last and last.stop == nil and r.done and r.unclassified, 'given up after the last service: unclassified')
  T.check(rally.over(r), 'and the rally is over')
  local f = rally.finished(r, '2026-11-15T00:00:00Z')
  T.check(f.unclassified and f.mode == 'realistic' and #f.passes == 9, 'kept as finished, unclassified, 9 passes')
end

------------------------------------------------------------------------------------------ Casual

do
  local r = newR(event(), { mode = 'casual', class = 'L4WD' })
  T.check(rally.recover(r, board) == nil, 'no Super Rally in Casual')
  rally.stageDone(r, { timeS = 900 })
  local it = rally.restart(r)
  T.check(it and it.ss == 'SS1' and r.results.SS1 == nil and rally.current(r).ss == 'SS1', 'Casual: SS1 again')
  rally.stageDone(r, { timeS = 880 })
  rally.stageDone(r, { timeS = 320 })
  rally.stageDone(r, { timeS = 870 })      -- SS3, now at Service A
  T.check(rally.current(r).label == 'Service A', 'at Service A')
  T.check(rally.restart(r) ~= nil, 'SS3 can be restarted before its service is done')
  rally.stageDone(r, { timeS = 865 })
  rally.serviced(r)
  T.check(rally.restart(r) == nil, '... but not once the service is done')
  T.near(rally.totalS(r), 880 + 320 + 865, 1e-6, 'the total')
end

------------------------------------------------------------------------------------------ places

do
  local r = newR(event(), { class = 'L4WD' })
  rally.stageDone(r, { timeS = 740 })
  local st = rally.stageStanding(board, r.order[2], 740, 'L4WD')
  T.check(st.pos == 3 and st.of == 5, 'SS1: 3rd of 5 (the regional crew left out): ' .. st.pos .. '/' .. st.of)
  T.check(st.classPos == 2 and st.classOf == 3, 'SS1: 2nd of 3 in L4WD')
  local you = nil
  for _, x in ipairs(st.rows) do if x.you then you = x end end
  T.check(you and you.pos == 3 and math.abs(you.gapS - 40) < 1e-6, 'you in the list, 40 s off the lead')
  local ov = rally.standing(r, board)
  T.check(ov and ov.pos == 3 and ov.of == 5 and ov.classPos == 2, 'overall after SS1: P3, L4WD 2nd')
  rally.stageDone(r, { timeS = 299 })      -- (the notional 200 is not a crew)
  ov = rally.standing(r, board)
  T.check(ov.pos == 3 and math.abs(ov.gapS - 39) < 1e-6, 'overall after SS2: 1039 is 3rd (1023.7 2nd), 39 s off: '
    .. ov.pos .. ' ' .. ov.gapS)
end

------------------------------------------------------------------------------------------ the save

do
  local r = newR(event(), { mode = 'realistic', class = 'O4WD', car = { name = 'A Car' } })
  rally.stageDone(r, { timeS = 800 })
  rally.recover(r, board)
  rally.serviced(r)
  local back = T.jsonDecode(T.jsonEncode(r))
  T.check(rally.valid(back), 'the save reads back as a rally')
  T.check(rally.isServiced(back), 'the service done is still done after JSON (string keys)')
  T.check(rally.current(back).label == 'Service A' and back.results.SS3.superRally == true, 'at Service A, SS3 scored')
  rally.serviceOut(back)
  T.check(rally.current(back).ss == 'SS4', 'and goes on from SS4')
  T.check(not rally.valid({ format = 1 }), 'not a rally')
end

do
  local best = rally.bestFinished({ { totalS = 5000, unclassified = true }, { totalS = 4000, mode = 'casual' },
    { totalS = 5600, mode = 'realistic' }, { totalS = 5500, mode = 'realistic' } })
  T.check(best.totalS == 5500 and best.mode == 'realistic', 'the best Realistic run before a faster Casual one')
  T.check(rally.bestFinished({ { totalS = 5000, unclassified = true }, { totalS = 6000, mode = 'casual' } }).mode
    == 'casual', 'a classified Casual run before an unclassified one')
  T.check(rally.guessClass('AWD') == 'L4WD' and rally.guessClass('RWD') == 'L2WD' and rally.guessClass(nil) == nil,
    'the class guessed from the drivetrain')
end

------------------------------------------------------------------------------------------ pack: the stops

do
  -- SVC rows; a service on a refuel-zone control ("RZ1"); a change of day; a class's own copy of the running order
  local function ss(c, st, day) return { type = 'SS', control = c, stage = st, day = day, run = 1 } end
  local ev = {
    service = { { type = 'service', control = 'RZ1', location = 'park' }, { type = 'regroup', control = 'TC9A' } },
    locations = { { id = 'park', name = 'Big Park, Somewhere' } },
    itinerary = {
      { type = 'MTC_OUT', control = 'TC0', day = 1 }, ss('SS1', 'A', 1), ss('SS2', 'B', 1),
      { type = 'SVC_IN', control = 'TC2B', day = 1 }, { type = 'SVC_OUT', control = 'TC2C', day = 1 },
      ss('SS3', 'A', 1), { type = 'MTC_IN', control = 'TC3A', day = 1 },
      ss('SS4', 'B', 2), { type = 'other', control = 'RZ1', day = 2 }, ss('SS5', 'A', 2),
      { type = 'SVC_OUT', control = 'TC5C', day = 2 },
      -- a class's copy: SS4 again with a service after it, then nothing new
      ss('SS4', 'B', 2), { type = 'SVC_OUT', control = 'TC4C', day = 2 },
    },
  }
  local lineId = { A = 'a', B = 'b' }
  local it, stops = pack._itineraryOf(ev, {}, lineId, function() end)
  T.check(#it == 5, 'five passes, the copy left out')
  local got = {}
  for _, s in ipairs(stops) do got[#got + 1] = s.after .. ':' .. s.label .. (s.name and (':' .. s.name) or '') end
  T.check(table.concat(got, ' ') == '2:Service A 3:Overnight 4:Service B:Big Park', 'the stops: ' .. table.concat(got, ' '))
  local _, none = pack._itineraryOf(nil, { { id = 'a', lengthM = 1000 } }, lineId, function() end)
  T.check(none == nil, 'no event file: no stops')
  -- a pass with no line in the map, then a service: the service is still read
  local ev2 = { itinerary = { ss('SS1', 'A', 1), ss('SS2', 'X', 1), { type = 'SVC_IN', control = 'TC2B', day = 1 },
    ss('SS3', 'B', 1) } }
  local it2, stops2 = pack._itineraryOf(ev2, {}, lineId, function() end)
  T.check(#it2 == 2 and stops2 and #stops2 == 1 and stops2[1].after == 1,
    'an unmatched pass before a service: the service kept, after SS1')
end

------------------------------------------------------------------------------------------ a quit mid-loop

do
  local saved = newR(event(), { mode = 'realistic', class = 'L4WD' })
  rally.stageDone(saved, { timeS = 900 })
  rally.stageDone(saved, { timeS = 330 })
  rally.stageDone(saved, { timeS = 880 })
  rally.serviced(saved)                    -- the save at Service A
  local r = newR(event(), { mode = 'realistic', class = 'L4WD' })
  for k, v in pairs(saved) do r[k] = v end
  rally.replayLoop(r, { results = { { timeS = 700 } }, started = true }, board)
  T.check(r.results.SS4.timeS == 700, 'the loop\'s finished stage kept')
  T.check(r.results.SS5.superRally and r.results.SS6.superRally, 'the stage quit during and the rest of the loop: Super Rally')
  T.check(rally.current(r).label == 'Overnight', 'back in at the overnight')
  local c = newR(event(), { mode = 'casual', class = 'L4WD' })
  rally.replayLoop(c, { results = { { timeS = 700 } }, started = true }, board)
  T.check(rally.current(c).ss == 'SS1' and not c.results.SS1, 'Casual: no loop replayed')
  -- Casual: no restart once the last stage is done
  for _ = 1, 20 do
    local it = rally.current(c)
    if not it then break end
    if it.kind == 'stage' then rally.stageDone(c, { timeS = 100 }) else rally.serviced(c) rally.serviceOut(c) end
  end
  T.check(rally.over(c) and rally.restart(c) == nil, 'Casual: no restart after the last stage')
end

------------------------------------------------------------------------------------------ 1.7.0 rally loop fixes

do
  -- #26: the rally starts at its start, on the map when the event file says where
  local e = event()
  e.rallyStart = { name = 'The Park', lat = 45.5, lon = -84.5 }
  e.rallyStops[1].place = { name = 'The Park', lat = 45.5, lon = -84.5 }
  local r = rally.new(e, { mode = 'realistic', class = 'L4WD' })
  local it = rally.current(r)
  T.check(it.kind == 'start' and it.label == 'Start' and it.place and it.place.lat == 45.5, 'the rally starts at the park')
  T.check(rally.nextStage(r).ss == 'SS1', 'with SS1 next')
  T.check(r.order[5].label == 'Service A' and r.order[5].place.name == 'The Park', 'Service A keeps its place')
  local plain = rally.new(event(), {})
  T.check(rally.current(plain).kind == 'start' and rally.current(plain).place == nil, 'no place: a start all the same')
end

do
  -- #32: a Realistic recovery on SS1 misses SS1-SS3 and rejoins at Service A, then SS4
  local r = newR(event(), { mode = 'realistic', class = 'L4WD' })
  T.check(rally.current(r).ss == 'SS1', 'on SS1')
  local out = rally.recover(r, board)
  local missed = {}
  for _, m in ipairs(out.missed) do missed[#missed + 1] = m.item.ss end
  T.check(table.concat(missed, ' ') == 'SS1 SS2 SS3', 'SS1 given up: SS1-SS3 missed: ' .. table.concat(missed, ' '))
  T.check(rally.current(r).label == 'Service A', 'at Service A')
  rally.serviced(r)
  rally.serviceOut(r)
  T.check(rally.current(r).ss == 'SS4', 'out of Service A to SS4, not SS6: ' .. tostring(rally.current(r).ss))
end

do
  -- #30: a stage held out of the rally: every pass of it to come goes, the stops round it close up
  local r = newR(event(), { mode = 'realistic', class = 'L4WD' })
  local n = rally.holdOut(r, 'c', 'its road is missing')
  local labels = {}
  for _, it in ipairs(r.order) do labels[#labels + 1] = it.kind == 'stage' and it.ss or it.label end
  T.check(n == 2 and table.concat(labels, ' ') == 'Start SS1 SS2 Service A SS4 SS5 Overnight SS8 Service B SS9 SS10',
    'SS3 and SS6 held out: ' .. table.concat(labels, ' '))
  T.check(#r.heldOut == 2 and r.heldOut[1].ss == 'SS3', 'listed as held out')
  T.check(rally.current(r).ss == 'SS1', 'still on SS1')
  -- a whole loop held out: the two stops either side become one
  rally.holdOut(r, 'a', 'x')
  rally.holdOut(r, 'b', 'x')
  labels = {}
  for _, it in ipairs(r.order) do labels[#labels + 1] = it.kind == 'stage' and it.ss or it.label end
  T.check(table.concat(labels, ' ') == 'Start Overnight SS8 Service B SS9 SS10', 'a day held out: ' .. table.concat(labels, ' '))
  -- everything held out: the rally is over
  rally.holdOut(r, 'd', 'x')
  rally.holdOut(r, 'e', 'x')
  T.check(rally.over(r) and rally.stagesLeft(r) == 0, 'nothing left: over')
  -- a stage already driven keeps its time
  local r2 = newR(event(), { mode = 'casual', class = 'L4WD' })
  rally.stageDone(r2, { timeS = 800 })
  rally.holdOut(r2, 'a', 'x')
  T.check(r2.results.SS1 and r2.results.SS1.timeS == 800 and rally.current(r2).ss == 'SS2', 'SS1 driven: kept; SS4 gone')
end

do
  -- pack: where each stop is, from the event file's places
  local function ss(c, st, day) return { type = 'SS', control = c, stage = st, day = day, run = 1 } end
  local ev = {
    service = { { type = 'service', control = 'TC2B-TC2C', location = 'svc' } },
    locations = { { id = 'mtc', name = 'Town Square', lat = 1.0, lon = 2.0 },
      { id = 'svc', name = 'The Service Park (Friday), Town', lat = 1.1, lon = 2.1 },
      { id = 'svcout', name = 'Service Out', lat = 1.2, lon = 2.2 },
      { id = 'day2', name = 'Day Two Start', lat = 1.3, lon = 2.3 }, { id = 'nopos', name = 'Nowhere' } },
    itinerary = {
      { type = 'MTC_OUT', control = 'TC0', day = 1, location = 'mtc' }, ss('SS1', 'A', 1),
      { type = 'SVC_IN', control = 'TC2B', day = 1, location = 'svcout' },
      { type = 'SVC_OUT', control = 'TC2C', day = 1, location = 'svcout' }, ss('SS2', 'B', 1),
      { type = 'MTC_IN', control = 'TC3A', day = 1, location = 'nopos' },
      { type = 'MTC_OUT', control = 'TC3B', day = 2, location = 'day2' }, ss('SS3', 'A', 2),
    },
  }
  local _, stops, start = pack._itineraryOf(ev, {}, { A = 'a', B = 'b' }, function() end)
  T.check(start and start.name == 'Town Square' and start.lat == 1.0, 'the start: the first MTC out')
  T.check(stops[1].place and stops[1].place.name == 'The Service Park' and stops[1].place.lat == 1.1,
    'the service: its service area first')
  T.check(stops[2].kind == 'overnight' and stops[2].place and stops[2].place.name == 'Day Two Start',
    "the overnight: the next morning's start")
  ev.itinerary[1].location = 'nopos'
  local _, _, start2 = pack._itineraryOf(ev, {}, { A = 'a', B = 'b' }, function() end)
  T.check(start2 and start2.name == 'The Service Park', "no start place: the first service's")
end

------------------------------------------------------------------------------------------ #48: overnight at service
do
  local ev = event()
  ev.rallyStops[1].place = { name = 'Park A', lat = 1, lon = 2 }
  ev.rallyStops[2].place = { name = 'Parc Ferme', lat = 5, lon = 6 }
  local ord = rally._orderOf(ev, 'real')
  local on
  for _, it in ipairs(ord) do if it.kind == 'overnight' then on = it end end
  T.check(on and on.place and on.place.name == 'Park A' and on.place.lat == 1 and on.parcFerme == 'Parc Ferme',
    'the overnight is at the last service park, driven back to (#48)')
  -- a service and the overnight on top of each other: at that service
  local ev2 = event()
  ev2.rallyStops[2].after = 3
  ev2.rallyStops[1].place = { name = 'Park A', lat = 1, lon = 2 }
  ev2.rallyStops[2].place = { name = 'Parc Ferme', lat = 5, lon = 6 }
  local ord2 = rally._orderOf(ev2, 'real')
  local on2
  for _, it in ipairs(ord2) do if it.kind == 'overnight' then on2 = it end end
  T.check(on2 and on2.place and on2.place.name == 'Park A', 'a service and the overnight together: at the service park')
  -- no service before it: its own place
  local ev3 = event()
  ev3.rallyStops[1].after = 9
  ev3.rallyStops[2].place = { name = 'Parc Ferme', lat = 5, lon = 6 }
  local ord3 = rally._orderOf(ev3, 'real')
  local on3
  for _, it in ipairs(ord3) do if it.kind == 'overnight' then on3 = it end end
  T.check(on3 and on3.place and on3.place.name == 'Parc Ferme', 'no service before it: the overnight at its own place')
end

------------------------------------------------------------------------------------------ #71: the final service
do
  local function labelsOf(order)
    local out = {}
    for _, it in ipairs(order) do out[#out + 1] = it.kind == 'stage' and it.ss or it.label end
    return table.concat(out, ' ')
  end
  -- the last day's service park: Service B (day 2) has a place
  local ev = event()
  ev.rallyStops[3].place = { name = 'Park B', lat = 3, lon = 4 }
  local r = rally.new(ev, {})
  T.check(labelsOf(r.order) == 'Start SS1 SS2 SS3 Service A SS4 SS5 SS6 Overnight SS8 Service B SS9 SS10 Final service',
    'after the last stage, a final service (#71): ' .. labelsOf(r.order))
  local fin = r.order[#r.order]
  T.check(fin.final and fin.kind == 'service' and fin.place.name == 'Park B', 'at the last day\'s service park')
  -- a stop after the last pass with a place: there
  local ev2 = event()
  ev2.rallyStops[#ev2.rallyStops + 1] = { after = 10, kind = 'service', label = 'Service C', name = 'Finish Park',
    place = { name = 'Finish Park', lat = 7, lon = 8 } }
  local fin2 = rally.new(ev2, {}).order
  fin2 = fin2[#fin2]
  T.check(fin2.final and fin2.place.name == 'Finish Park', 'the event\'s own stop after the last pass, when it has a place')
  -- no service with a place anywhere: no final service, not one at the rally's start (the rally ends at its last
  -- stage, as before)
  local ev3 = event()
  ev3.rallyStart = { name = 'Start Square', lat = 9, lon = 10 }
  local o3 = rally.new(ev3, {}).order
  T.check(not o3[#o3].final and o3[#o3].kind == 'stage', 'no service park: no final service, not at the start')
  T.check(not rally.new(event(), {}).order[#rally.new(event(), {}).order].final, 'no place at all: no final service')
  -- the rally is over only once checked in there
  local rr = newR(ev, { mode = 'casual' })
  while rally.current(rr).kind == 'stage' or not rally.current(rr).final do
    local it = rally.current(rr)
    if it.kind == 'stage' then rally.stageDone(rr, { timeS = 100 }) else rally.serviced(rr) rally.serviceOut(rr) end
  end
  T.check(not rally.over(rr) and rally.current(rr).final, 'after the last stage: on the way to the final service')
  rally.serviced(rr)
  rally.serviceOut(rr)
  T.check(rally.over(rr) and rr.done, 'checked in at the final service: the rally is over')
  -- the last stage given up in Realistic: the final service is no stop to rejoin at, unclassified
  local rl = newR(ev, { mode = 'realistic', class = 'L4WD' })
  while rally.current(rl).ss ~= 'SS10' do
    local it = rally.current(rl)
    if it.kind == 'stage' then rally.stageDone(rl, { timeS = 100 }) else rally.serviced(rl) rally.serviceOut(rl) end
  end
  local out = rally.recover(rl, board)
  T.check(out and out.stop == nil and rl.done and rl.unclassified, 'SS10 given up: unclassified, not at the final service')
  -- held out: the stops before the final service merged as before, the final service kept
  local rh = newR(ev, {})
  rally.holdOut(rh, 'e', 'missing')
  T.check(labelsOf(rh.order) == 'Start SS1 SS2 SS3 Service A SS4 SS5 SS6 Overnight SS9 Final service',
    'a stage held out: the final service kept last (' .. labelsOf(rh.order) .. ')')
end

------------------------------------------------------------------------------------------ no stop at all (the owner, rev 4)
do
  -- a rally with no service, overnight or regroup: a recovery rejoins at the next stage's start, only the stage given
  -- up scored under Super Rally; on the last stage it ends the rally
  local e = event()
  e.rallyStops = {}
  e.rallyStart = { name = 'Start Square', lat = 9, lon = 10 }
  local r = newR(e, { mode = 'realistic', class = 'L4WD' })
  T.check(rally.noStops(r) and not rally.noStops(newR(event(), {})), 'no stop at all: told from a rally with services')
  rally.serviceOut(r)
  local out = rally.recover(r, board)
  T.check(out and #out.missed == 1 and out.missed[1].item.ss == 'SS1' and out.stage and out.stage.ss == 'SS2'
    and out.stop == nil and rally.current(r).ss == 'SS2' and not r.done,
    'no stop: SS1 given up, only it under Super Rally, on at the start of SS2')
  T.check(r.results.SS1.superRally and r.results.SS2 == nil, 'no stop: SS2 not missed')
  while rally.current(r).ss ~= 'SS10' do rally.stageDone(r, { timeS = 100 }) end
  out = rally.recover(r, board)
  T.check(out and out.stage == nil and out.stop == nil and r.done and r.unclassified,
    'no stop: the last stage given up ends the rally, unclassified')

  -- Continue after a quit: never saved since the start, so the loop replays SS1 driven, SS2 given up, SS3 driven
  local q = newR(e, { mode = 'realistic', class = 'L4WD' })
  rally.replayLoop(q, { results = { { timeS = 600 }, { recovered = true }, { timeS = 650 } } }, board)
  T.check(rally.current(q).ss == 'SS4' and q.results.SS1.timeS == 600 and q.results.SS2.superRally
    and q.results.SS3.timeS == 650, 'no stop: a recovery in the loop replayed as one, the next time on SS3')
end

------------------------------------------------------------------------------------------ the rally clock (rally-loop)
-- worldTime.lua: dates, local clocks, zones, the sun. Made-up times and places.
local wt = require('earthRally/worldTime')
do
  T.check(wt.daysFromCivil(1970, 1, 1) == 0 and wt.daysFromCivil(2000, 3, 1) == 11017, 'days from the civil date')
  local y, m, d = wt.civilFromDays(wt.daysFromCivil(2028, 2, 29))
  T.check(y == 2028 and m == 2 and d == 29, 'and back (a leap day)')
  local t = wt.parse('2031-03-14', '18:05')
  T.check(t and wt.hm(t) == '18:05' and wt.dateText(t) == 'Fri 14 Mar', 'parsed and written: ' .. tostring(wt.dateText(t)))
  T.check(wt.startText(t) == 'Fri 14 Mar 2031, 18:05 local', 'the start screen\'s line: ' .. tostring(wt.startText(t)))
  T.check(wt.parse('2031-03-14', 'noon') == nil and wt.parse(nil, '10:00') == nil, 'not a time: nil')
  -- zones: standard and summer time
  T.check(wt.utcOffset('America/Chicago', wt.parse('2031-02-07', '12:00')) == -6 * 3600, 'Chicago in winter: -6')
  T.check(wt.utcOffset('America/Chicago', wt.parse('2031-08-07', '12:00')) == -5 * 3600, 'Chicago in summer: -5')
  T.check(wt.utcOffset('America/Phoenix', wt.parse('2031-08-07', '12:00')) == -7 * 3600, 'Phoenix: no summer time')
  T.check(wt.utcOffset('Europe/London', wt.parse('2031-07-01', '12:00')) == 3600, 'London in summer: +1')
  T.check(wt.utcOffset('Australia/Sydney', wt.parse('2031-01-10', '12:00')) == 11 * 3600, 'Sydney in January: +11')
  T.check(wt.utcOffset('Australia/Sydney', wt.parse('2031-07-10', '12:00')) == 10 * 3600, 'Sydney in July: +10')
  local off, known = wt.utcOffset('Nowhere/Made_Up', 0, 31)
  T.check(off == 2 * 3600 and known == false, 'an unknown zone: its longitude\'s hour')
  -- (US summer time from the second Sunday of March: 2031-03-09)
  T.check(wt.utcOffset('America/New_York', wt.parse('2031-03-09', '01:30')) == -5 * 3600
    and wt.utcOffset('America/New_York', wt.parse('2031-03-09', '03:30')) == -4 * 3600, 'the US switch in March')
  T.check(wt.toUtc(wt.parse('2031-02-07', '12:00'), 'America/Chicago') == wt.parse('2031-02-07', '18:00'),
    'a local time to the UTC instant')
  -- the sun (a made-up place at 45 N, 90 W, on Chicago time)
  local e = wt.sunElevationDeg(2031, 3, 20, 20, 0, 0, 0)
  T.check(e < -20, 'the equinox, 20:00 UTC at 0, 0: the sun down (' .. string.format('%.1f', e) .. ')')
  T.near(wt.sunElevationDeg(2031, 3, 20, 12, 0, 0, 0), 88, 4, 'the equinox, noon at 0, 0: the sun overhead')
  T.check(wt.light(wt.parse('2031-02-07', '12:30'), 'America/Chicago', 45, -90) == 'day', 'midday: day')
  T.check(wt.light(wt.parse('2031-02-07', '19:30'), 'America/Chicago', 45, -90) == 'night', 'a February evening: night')
  T.check(wt.light(wt.parse('2031-02-07', '17:20'), 'America/Chicago', 45, -90) == 'dusk', 'sunset: dusk')
  T.check(wt.light(wt.parse('2031-02-07', '07:15'), 'America/Chicago', 45, -90) == 'dawn', 'sunrise: dawn')
  T.check(wt.light(t, 'America/Chicago', nil, nil) == nil, 'no place: no light')
end

-- pack.itineraryOf reads the schedule: a made-up two-day event. Day 1: start 08:00, TC1 (20 min), SS1 (bogey 10),
-- TC2 (15), SS2 (bogey 8), regroup in (12), service in (10) and out 09:40 (30), TC3 (18), SS3; a regional crew's own
-- row (not ours: its target never counts). Day 2: MTC out 07:00, TC4 (10), SS4.
local function timedEvent()
  local function row(t) t.classes = t.classes or { 'national', 'regional' } return t end
  return {
    event = { timezone = 'America/Chicago' },
    locations = { { id = 'pk', name = 'Made-up Park, Town', lat = 45.0, lon = -90.0 } },
    itinerary = {
      row({ type = 'MTC_OUT', control = 'TC0', date = '2031-02-07', first_car = '08:00', location = 'pk', day = 1 }),
      row({ type = 'ATC', control = 'TC1', date = '2031-02-07', target_min = 20, first_car = '08:20', day = 1 }),
      row({ type = 'SS', control = 'SS1', stage = 'A', date = '2031-02-07', first_car = '08:23', lateness_min = 10, day = 1 }),
      row({ type = 'ATC', control = 'TC2', date = '2031-02-07', target_min = 15, first_car = '08:48', day = 1 }),
      row({ type = 'SS', control = 'SS2', stage = 'B', date = '2031-02-07', first_car = '08:51', lateness_min = 8, day = 1 }),
      row({ type = 'RGC_IN', control = 'TC2A', date = '2031-02-07', target_min = 12, first_car = '09:11', day = 1 }),
      row({ type = 'MTC_IN', control = 'TC2A', date = '2031-02-07', target_min = 12, first_car = '09:11', day = 1,
        classes = { 'regional' } }),
      row({ type = 'SVC_IN', control = 'TC2B', date = '2031-02-07', target_min = 10, first_car = '09:21', location = 'pk', day = 1 }),
      row({ type = 'SVC_OUT', control = 'TC2C', date = '2031-02-07', target_min = 30, first_car = '09:40', location = 'pk', day = 1 }),
      row({ type = 'ATC', control = 'TC3', date = '2031-02-07', target_min = 18, first_car = '09:58', day = 1 }),
      row({ type = 'SS', control = 'SS3', stage = 'A', run = 2, date = '2031-02-07', first_car = '10:01', lateness_min = 10, day = 1 }),
      row({ type = 'MTC_IN', control = 'TC3A', date = '2031-02-07', target_min = 20, first_car = '10:31', location = 'pk', day = 1 }),
      row({ type = 'MTC_OUT', control = 'TC3B', date = '2031-02-08', first_car = '07:00', location = 'pk', day = 2 }),
      row({ type = 'ATC', control = 'TC4', date = '2031-02-08', target_min = 10, first_car = '07:10', day = 2 }),
      row({ type = 'SS', control = 'SS4', stage = 'B', run = 2, date = '2031-02-08', first_car = '07:13', lateness_min = 8, day = 2 }),
    } }
end

do
  local it, stops, start, timing = pack._itineraryOf(timedEvent(), {}, { A = 'a', B = 'b' }, function() end)
  T.check(#it == 4 and it[1].date == '2031-02-07' and it[1].firstCar == '08:23' and it[1].latenessMin == 10,
    'a pass carries its date, start and lateness')
  T.check(it[1].outAt == '08:00' and it[1].outTargetMin == 20, 'the first pass: from the start, 20 min')
  T.check(it[2].targetMin == 15 and it[2].outAt == nil, 'SS2: the road section from SS1, 15 min')
  T.check(it[3].targetMin == 12 + 10 + 30 + 18 and it[3].outAt == '09:40' and it[3].outTargetMin == 18,
    'SS3: through the service (the regional crew\'s row left out), and from its out time: ' .. tostring(it[3].targetMin))
  T.check(it[4].outDate == '2031-02-08' and it[4].outAt == '07:00' and it[4].outTargetMin == 10,
    'SS4: from the next morning\'s start')
  T.check(timing and timing.timezone == 'America/Chicago' and timing.start.date == '2031-02-07'
    and timing.start.time == '08:00', 'the rally is timed: its zone and start')
  T.check(stops[1].kind == 'service' and stops[1].outAt == '09:40' and stops[2].kind == 'overnight'
    and stops[2].outAt == '07:00', 'the stops carry their out times')
  -- no target anywhere: untimed
  local ev2 = timedEvent()
  for _, r in ipairs(ev2.itinerary) do r.target_min = nil end
  local _, _, _, t2 = pack._itineraryOf(ev2, {}, { A = 'a', B = 'b' }, function() end)
  T.check(t2 == nil, 'no target times: untimed')
end

local function timedRally(opts)
  local it, stops, start, timing = pack._itineraryOf(timedEvent(), {}, { A = 'a', B = 'b' }, function() end)
  return rally.new({ id = 'tm', name = 'Timed Rally', itinerary = it, rallyStops = stops, rallyStart = start,
    timing = timing, rules = opts and opts.rules }, opts or {})
end

do
  local r = timedRally({ mode = 'realistic' })
  T.check(r.timed and r.tz == 'America/Chicago' and wt.hm(r.clock.t) == '08:00' and r.lateSPerMin == 10
    and r.earlySPerMin == 60, 'a timed rally: its clock at the start, ARA\'s penalties by default')
  rally.serviced(r)
  rally.serviceOut(r)
  T.check(wt.hm(rally.dueFor(r, r.pos)) == '08:20', 'due at TC1: the start + 20 min')
  -- (late: the minute you check in during counts -- 08:22:30 is 2 min late, due 08:20)
  local res = rally.checkIn(r, rally.current(r), wt.parse('2031-02-07', '08:22') + 30, rally.dueFor(r, r.pos), false)
  T.check(res.kind == 'late' and res.min == 2 and res.penaltyS == 20, 'late in the minute 08:22: 2 min, +20 s')
  -- the stage started 08:25, took 9:30 (inside its 10 min lateness): time out 08:35; due at TC2 08:50
  local outT = rally.timeOut(rally.current(r), wt.parse('2031-02-07', '08:25'), wt.parse('2031-02-07', '08:34') + 30)
  T.check(wt.hm(outT) == '08:35', 'time out: start + lateness')
  T.check(wt.hm(rally.timeOut(rally.current(r), wt.parse('2031-02-07', '08:25'), wt.parse('2031-02-07', '08:41') + 20))
    == '08:41', 'a stage slower than its lateness: time out at its finish, to the minute down')
  rally.stageDone(r, { timeS = 570, outT = outT })
  T.check(wt.hm(rally.dueFor(r, r.pos)) == '08:50', 'due at TC2: time out + 15 min')
  res = rally.checkIn(r, rally.current(r), wt.parse('2031-02-07', '08:50') + 59, rally.dueFor(r, r.pos), false)
  T.check(res.kind == 'onTime' and res.penaltyS == 0, 'in the due minute: on time')
  res = rally.checkIn(r, rally.current(r), wt.parse('2031-02-07', '08:47'), rally.dueFor(r, r.pos), false)
  T.check(res.kind == 'early' and res.min == 3 and res.penaltyS == 0, 'early with the setting off: no cost')
  res = rally.checkIn(r, rally.current(r), wt.parse('2031-02-07', '08:47'), rally.dueFor(r, r.pos), true)
  T.check(res.kind == 'early' and res.penaltyS == 180, 'early with the setting on: 1 min a minute')
  T.check(rally.roadPenaltyS(r) == 200 and r.road.SS1.penaltyS == 20, 'the road penalties kept per control')
  rally.stageDone(r, { timeS = 400, outT = wt.parse('2031-02-07', '09:00') })
  T.check(rally.current(r).kind == 'service' and wt.hm(rally.current(r).outT) == '09:40', 'Service A: out at 09:40')
  T.check(math.abs(rally.totalS(r) - (570 + 400 + 200)) < 1e-9, 'the total: stage times and road penalties')
  rally.serviced(r)
  rally.serviceOut(r)
  T.check(wt.hm(r.clock.t) == '09:40' and wt.hm(rally.dueFor(r, r.pos)) == '09:58',
    'out of service at its scheduled time, whatever the clock said; due at TC3 09:58')
  rally.stageDone(r, { timeS = 560, outT = wt.parse('2031-02-07', '10:11') })
  T.check(rally.current(r).kind == 'overnight', 'the overnight')
  rally.serviced(r)
  rally.serviceOut(r)
  T.check(wt.dateText(r.clock.t) == 'Sat 8 Feb' and wt.hm(r.clock.t) == '07:00'
    and wt.hm(rally.dueFor(r, r.pos)) == '07:10', 'the next morning: out at 07:00, due 07:10')
  local f = rally.finished(r, 'x')
  T.check(f.roadPenaltyS == 200 and math.abs(f.totalS - (570 + 400 + 560 + 200)) < 0.05, 'the finished rally keeps them')
  -- a recovery: no time out to count from
  r.lastOut = 1
  rally.stageDone(r, { timeS = 1 })
  T.check(r.lastOut == nil, 'a stage with no time out: none')
  -- the pack's rules win
  local r2 = timedRally({ rules = { lateSPerMin = 5, earlySPerMin = 30 } })
  T.check(r2.lateSPerMin == 5 and r2.earlySPerMin == 30, 'the pack\'s penalties used')
  -- untimed and format-2 saves
  local u = rally.new(event(), {})
  T.check(u.timed == nil and u.clock == nil and rally.dueFor(u, 2) == nil and rally.roadPenaltyS(u) == 0,
    'an untimed rally: no clock, no due times')
  local old = rally.new(event(), {})
  old.format = 2
  T.check(rally.valid(old) and rally.valid(r) and r.format == 3, 'a format-2 save still continues (untimed)')
  -- a stage held out: its time goes to the next one's road section
  local r3 = timedRally({})
  rally.serviced(r3)
  rally.serviceOut(r3)
  rally.holdOut(r3, 'b', 'test')
  T.check(rally.current(r3).ss == 'SS1', 'SS2 and SS4 held out')
  rally.stageDone(r3, { timeS = 1, outT = wt.parse('2031-02-07', '08:35') })
  T.check(rally.current(r3).kind == 'service', 'on to the service')
end

------------------------------------------------------------------------------------------ review fixes (rally-loop)
do
  -- (C) a cancelled first stage: the next one is timed from the rally's start (08:00 + 20 + SS1's 10 + 15 = 08:45)
  local it, stops, start, timing = pack._itineraryOf(timedEvent(), {}, { A = 'a', B = 'b' }, function() end)
  it[1].cancelled = true
  local r = rally.new({ id = 'tm', name = 'Timed Rally', itinerary = it, rallyStops = stops, rallyStart = start,
    timing = timing }, { cancelled = 'real' })
  T.check(r.order[2].ss == 'SS2', 'cancelled SS1 left out')
  rally.serviced(r)
  rally.serviceOut(r)
  T.check(wt.hm(rally.dueFor(r, r.pos) or 0) == '08:45', 'cancelled first stage: the opening section still timed: '
    .. tostring(rally.dueFor(r, r.pos) and wt.hm(rally.dueFor(r, r.pos))))
  -- (C) a cancelled pass after a service: the next pass starts from the service's out time (09:40 + 18 + SS3's 10
  -- + 30 = 10:38), not from the stage before the service. The overnight taken away so SS4 follows straight on.
  it, stops, start, timing = pack._itineraryOf(timedEvent(), {}, { A = 'a', B = 'b' }, function() end)
  it[3].cancelled = true
  it[4].outDate, it[4].outAt, it[4].outTargetMin = nil, nil, nil
  local kept = {}
  for _, s in ipairs(stops) do if s.after ~= 3 then kept[#kept + 1] = s end end
  r = rally.new({ id = 'tm', name = 'Timed Rally', itinerary = it, rallyStops = kept, rallyStart = start,
    timing = timing }, { cancelled = 'real' })
  rally.serviced(r)
  rally.serviceOut(r)
  rally.stageDone(r, { timeS = 1, outT = wt.parse('2031-02-07', '08:35') })
  rally.stageDone(r, { timeS = 1, outT = wt.parse('2031-02-07', '09:30') })
  T.check(rally.current(r).kind == 'service' and wt.hm(rally.current(r).outT or 0) == '09:40',
    'cancelled pass after the service: the service keeps its out time')
  rally.serviced(r)
  rally.serviceOut(r)
  T.check(rally.current(r).ss == 'SS4' and wt.hm(rally.dueFor(r, r.pos) or 0) == '10:38',
    'cancelled pass after the service: due from the service\'s out time: '
    .. tostring(rally.dueFor(r, r.pos) and wt.hm(rally.dueFor(r, r.pos))))
end

do
  -- (D) a stage held out between Service A and the overnight: the two stops merge, out at the overnight's time
  local r = timedRally({ mode = 'realistic' })
  rally.serviced(r)
  rally.serviceOut(r)
  rally.stageDone(r, { timeS = 1, outT = wt.parse('2031-02-07', '08:35') })
  rally.stageDone(r, { timeS = 1, outT = wt.parse('2031-02-07', '09:00') })
  rally.holdOut(r, 'a', 'test')
  local stop = rally.current(r)
  T.check(stop.kind == 'overnight' and r.order[r.pos + 1].ss == 'SS4', 'the stops merged: an overnight, then SS4')
  T.check(wt.dateText(stop.outT) == 'Sat 8 Feb' and wt.hm(stop.outT) == '07:00', 'the merged stop: the later out time')
  rally.serviced(r)
  rally.serviceOut(r)
  T.check(wt.hm(r.clock.t) == '07:00' and wt.hm(rally.dueFor(r, r.pos) or 0) == '07:10',
    'out of the merged stop and due at TC4 agree')
end

do
  -- (J) the overall place counts the road penalties, as "Your total" does
  local r = newR(event(), { class = 'L4WD' })
  rally.stageDone(r, { timeS = 715 })
  local ov = rally.standing(r, board)
  T.check(ov.pos == 2, 'overall: 715 is 2nd')
  r.road = { SS1 = { penaltyS = 30 } }
  ov = rally.standing(r, board)
  T.check(ov.pos == 3 and math.abs(ov.gapS - 45) < 1e-6 and math.abs(ov.totalS - rally.totalS(r)) < 1e-6,
    'overall with 30 s of road penalties: 745 is 3rd, 45 s off, the same total')
  r.timed = true
  local f = rally.finished(r, 'x')
  local fs = rally.finishedStanding(f, board)
  T.check(fs and fs.pos == 3, 'a finished rally placed with its road penalties too')
end

do
  -- (K) summer time at the changeovers, on the wall clock (2026: US 8 Mar / 1 Nov, EU 29 Mar / 25 Oct, AU 5 Apr /
  -- 4 Oct)
  local function off(tz, d, hm) return wt.utcOffset(tz, wt.parse(d, hm)) / 3600 end
  local cases = {
    { 'America/New_York', '2026-03-08', '01:59', -5 }, { 'America/New_York', '2026-03-08', '03:00', -4 },
    { 'America/New_York', '2026-11-01', '00:30', -4 }, { 'America/New_York', '2026-11-01', '01:30', -4 },
    { 'America/New_York', '2026-11-01', '02:00', -5 },
    { 'Europe/London', '2026-03-29', '00:59', 0 }, { 'Europe/London', '2026-03-29', '02:00', 1 },
    { 'Europe/London', '2026-10-25', '01:30', 1 }, { 'Europe/London', '2026-10-25', '02:00', 0 },
    { 'Europe/Paris', '2026-03-29', '03:00', 2 }, { 'Europe/Paris', '2026-10-25', '02:30', 2 },
    { 'Europe/Paris', '2026-10-25', '03:00', 1 },
    { 'Australia/Sydney', '2026-04-05', '02:30', 11 }, { 'Australia/Sydney', '2026-04-05', '03:00', 10 },
    { 'Australia/Sydney', '2026-10-04', '01:59', 10 }, { 'Australia/Sydney', '2026-10-04', '03:00', 11 },
  }
  for _, c in ipairs(cases) do
    local got = off(c[1], c[2], c[3])
    T.check(got == c[4], string.format('summer time: %s %s %s is %+g (%+g)', c[1], c[2], c[3], c[4], got))
  end
end

T.done('test_rally')
