-- The player UI's pure parts (no game): the settings file, the HUD's two streams in every run state (hudFrame), the
-- HUD preview's frames, and the menu page's data (menu.lua over a rally's files).
local T = dofile(TESTS .. '/testlib.lua')

local files = {}
function jsonWriteFile(path, data) files[path] = data return true end
function jsonReadFile(path)
  if files[path] == 'BROKEN' then error('bad json') end
  return files[path]
end
FS = {
  fileExists = function(_, path) return files[path] ~= nil end,
  findFiles = function(_, dir)
    local out = {}
    for k in pairs(files) do if k:sub(1, #dir) == dir and k:match('%.json$') then out[#out + 1] = k end end
    table.sort(out)
    return out
  end,
}
local logged = {}
function log(level, _, msg) logged[#logged + 1] = level .. ' ' .. tostring(msg) end

------------------------------------------------------------------------------------------ settings
local settings = require('earthRally/settings')
do
  local v = settings.load()
  T.check(v.units == 'km' and v.timeControls == 'full' and v.resetPenalty == true and v.zoneBrake == true and
    v.clockView == 'right' and v.devPanel == false, 'no file: the defaults (1.1.0 behaviour, developer panel off)')
  local r = settings.set('units', 'mi')
  T.check(r.ok and settings.get('units') == 'mi' and files[settings.FILE].units == 'mi' and files[settings.FILE].version == 1,
    'a change is saved to the settings file')
  r = settings.set('units', 'furlongs')
  T.check(not r.ok and r.error and settings.get('units') == 'mi', 'a bad value refused, the old one kept')
  r = settings.set('nonsense', true)
  T.check(not r.ok, 'an unknown setting refused')
  T.check(not settings.set('resetPenalty', 'yes').ok and settings.set('resetPenalty', false).ok and
    settings.get('resetPenalty') == false, 'on / off settings take booleans')
  local heard = {}
  settings.onChange('t', function(k, val) heard[#heard + 1] = k .. '=' .. tostring(val) end)
  settings.set('devPanel', true)
  settings.set('devPanel', true)
  T.check(#heard == 1 and heard[1] == 'devPanel=true', 'listeners told once per real change')
  -- read back, with junk in the file
  files[settings.FILE] = { version = 1, units = 'mi', clockView = 'sideways', extra = 1, zoneBrake = false }
  v = settings.load()
  T.check(v.units == 'mi' and v.clockView == 'right' and v.zoneBrake == false, 'read back: good values taken, bad ones defaulted')
  files[settings.FILE] = 'BROKEN'
  v = settings.load()
  T.check(v.units == 'km' and v.timeControls == 'full', 'an unreadable file: the defaults')
  local ui = settings.uiState()
  T.check(#ui.schema == 6 and ui.schema[1].id == 'units' and ui.schema[1].options[2].value == 'mi' and
    ui.schema[1].options[2].label == 'miles' and ui.settings.units == 'km', 'the page gets the schema in order and the values')
  settings.reset()
  files[settings.FILE] = nil
end

------------------------------------------------------------------------------------------ hudFrame
local hud = require('earthRally/hudFrame')
do
  T.check(hud.clockText(10 * 3600 + 43 * 60 + 30) == '10:43:30', 'clock text')
  T.check(hud.diffText(58) == '0:58' and hud.diffText(57.2) == '0:58' and hud.diffText(-3) == '0:00' and
    hud.diffText(75) == '1:15', 'time to the start as the game sends it ("M:SS", rounded up)')
  T.check(hud.lengthText(8400, 'km') == '8.4' and hud.lengthText(8400, 'mi') == '5.2', 'stage length in km / miles')
  local fwd = { x = 0, y = 1 }
  T.near(hud.relBearing(fwd, { x = 0, y = 0 }, { x = 10, y = 0 }), 90, 1e-6, 'the line to the right: +90')
  T.near(hud.relBearing(fwd, { x = 0, y = 0 }, { x = -10, y = 0 }), -90, 1e-6, 'to the left: -90')
  T.near(math.abs(hud.relBearing(fwd, { x = 0, y = 0 }, { x = 0, y = -10 })), 180, 1e-6, 'behind: 180')
  T.near(hud.relBearing({ x = 1, y = 0 }, { x = 0, y = 0 }, { x = 0, y = -5 }), 90, 1e-6, 'heading east, the line south: right')
  T.check(hud.relBearing(nil, { x = 0, y = 0 }, { x = 1, y = 1 }) == nil, 'no heading: no bearing')

  local ev = { name = 'Olympus', stages = { {}, {}, {} } }
  local function run(state, extra)
    local r = { state = state, event = ev, stage = { name = 'Kuhnle', lengthM = 8400 }, ss = 2, ssCount = 3,
      startM = 30, finishM = 8430, checks = {} }
    for k, v in pairs(extra or {}) do r[k] = v end
    return r
  end
  local ctx = { now = 38512, speed = 0 }

  -- no run
  local rl, ours = hud.build(nil, ctx)
  T.check(rl.activeState == 'inactive' and rl.showStageApps == false and ours.state == 'idle' and next(ours.show) == nil,
    'no run: the stock apps inactive, ours shows nothing')
  -- the game's rally mode running: its stream left alone
  rl, ours = hud.build(run('running', { clock = 5, along = 100 }), { now = 1, noRallyLoop = true })
  T.check(rl == nil and ours.state == 'running', 'the game\'s rally loop loaded: no rallyLoop frame from us')

  -- getting ready, and driving to the ATC: our card, the stock apps quiet (no 'tc': it prints "Limit nullkm/h")
  for _, s in ipairs({ 'travel', 'anchor', 'build', 'place' }) do
    rl, ours = hud.build(run(s), ctx)
    T.check(rl.activeState == 'inactive' and ours.show.next and ours.control == 'ready', s .. ': the next-stage card, getting ready')
  end
  rl, ours = hud.build(run('toAtc', { toControlM = 1240 }), ctx)
  T.check(rl.activeState == 'inactive' and ours.show.next and ours.control == 'atc' and ours.toControlM == 1240 and
    ours.stage.ss == 2 and ours.stage.name == 'Kuhnle' and ours.stage.lengthM == 8400 and ours.clockText == '10:41:52',
    'to the ATC: our card with the SS number, name, length, rally clock and distance')

  -- checked in, moving up: the stock proximity (SS badge, distance, "Start in")
  rl, ours = hud.build(run('toStart', { atcTime = 38550, startAt = 38610, toControlM = 180 }), { now = 38552, speed = 8 })
  T.check(rl.activeState == 'vehicleProximity' and rl.scheduleData.eventType == 'ss_start' and rl.scheduleData.label == 'SS2'
    and rl.scheduleData.ssLabel == '2' and rl.scheduleData.timeDiff == '0:58' and rl.vehicleProximity.distance == 180 and
    rl.vehicleProximity.isStartLine and not rl.vehicleProximity.isStopped and not rl.vehicleProximity.isNear,
    'to the start: the stock countdown app\'s proximity, "Start in 0:58"')
  T.check(ours.show.timecard and ours.atcTime == 38550 and ours.startAt == 38610, 'our timecard: checked in, start time')
  rl = hud.build(run('toStart', { startAt = 38610, toControlM = 1, zone = { held = {} } }), { now = 38560, speed = 0 })
  T.check(rl.vehicleProximity.isNear and rl.vehicleProximity.isStopped and rl.vehicleProximity.isFrozen,
    'stopped and held on the line: STAGED')
  rl, ours = hud.build(run('toStart', { toControlM = 50 }), ctx)
  T.check(rl.scheduleData.timeDiff == nil and not ours.show.timecard, 'no start time yet (no ATC): no "Start in", no timecard')

  -- the wait and the countdown
  rl, ours = hud.build(run('waitStart', { startAt = 38610 }), { now = 38580, canSkip = true })
  T.check(rl.activeState == 'countdown' and rl.countdownData.countdown == 30 and rl.rallyClock.canSkipCountdown and
    ours.canSkip and not ours.show.bigCount and ours.show.timecard, 'waiting: the stock squares empty, the skip hint, our timecard')
  rl, ours = hud.build(run('waitStart', { startAt = 38610 }), { now = 38607.2 })
  T.check(rl.countdownData.countdown == 3 and ours.show.bigCount and ours.countdown == 3 and not ours.show.timecard and
    not rl.rallyClock.canSkipCountdown, '3 s to go: 3 squares, our big 3')
  rl, ours = hud.build(run('waitStart', { startAt = 38610 }), { now = 38610 })
  T.check(rl.countdownData.countdown == 0 and not ours.show.bigCount, 'the minute: GO on the squares')
  rl, ours = hud.build(run('waitStart', { startAt = 38610, jumpStart = true, jumpStartAt = 38606 }), { now = 38607 })
  T.check(ours.show.jump, 'a jump start: our red card')
  rl, ours = hud.build(run('waitStart', { startAt = 38610, jumpStart = true, jumpStartAt = 38600 }), { now = 38609 })
  T.check(not ours.show.jump, '... for a few seconds only')
  -- staged and ready (1.2.5): the stage apps are up through the countdown, reading zero, not only from GO
  -- a minute out, our timecard has the corner to itself: the stock stage clock would sit on top of it
  rl, ours = hud.build(run('waitStart', { startAt = 38610 }), { now = 38580 })
  T.check(ours.show.timecard and not rl.showStageApps and not ours.show.km,
    'waiting, a minute out: our timecard alone in the corner, no km readout without its bar')
  -- inside the last seconds the timecard goes and they come up, reading zero
  rl, ours = hud.build(run('waitStart', { startAt = 38610 }), { now = 38604 })
  T.check(not ours.show.timecard and rl.showStageApps == true and rl.uiColors and rl.uiColors.theme
    and rl.stageData and rl.stageData.currentSSTime == 0 and rl.stageData.isActive == false
    and rl.stageData.completion.distM == 0 and rl.stageData.completion.distPct == 0,
    'waiting, the last seconds: the stage clock and progress meter up, reading zero')
  T.check(ours.show.km and ours.doneM == 0 and ours.totalM == rl.stageData.completion.totalDistM,
    'waiting: our km readout up at 0 of the stage')


  -- where the car is: BeamNG.Earth's strips are off screen during a stage, so the HUD carries it
  local WHERE = { place = { street = 'Maryhill Loops Road', place = 'Klickitat County', region = 'Washington',
                            country = 'United States' } }
  rl, ours = hud.build(run('toAtc', { toControlM = 400 }), { now = 38500, place = WHERE.place })
  T.check(ours.show.where == 'next' and ours.where.road == 'Maryhill Loops Road'
    and ours.where.rest == 'Klickitat County, Washington, United States',
    'driving to the stage: the road is a row of our own panel')
  rl, ours = hud.build(run('toStart', { toControlM = 50, atcTime = 38400, startAt = 38600 }),
    { now = 38500, place = WHERE.place })
  T.check(ours.show.where == 'timecard', 'on the way to the line: the row goes on the timecard')
  rl, ours = hud.build(run('running', { clock = 60, along = 1500 }), { now = 38700, place = WHERE.place })
  T.check(ours.show.where == 'sliver', 'on the stage: the thin sliver beside the timer')
  rl, ours = hud.build(run('running', { clock = 60, along = 1500 }), { now = 38700 })
  T.check(ours.where == nil and not ours.show.where, 'nothing to say: no row at all')

  -- the loading figure is BeamNG.Earth's own fraction, never a percentage (it is a queue depth: the total grows)
  rl, ours = hud.build(run('running', { clock = 60, along = 1500 }),
    { now = 38700, place = WHERE.place, loading = { done = 150, total = 433 } })
  T.check(ours.where.loading == '150/433', 'the world still arriving: the fraction as it comes')

  -- a warning is a word of ours from the banner's id, with its level; never the banner's sentence
  rl, ours = hud.build(run('running', { clock = 60, along = 1500 }), { now = 38700, place = WHERE.place,
    earthBanner = { id = 'noserver', level = 'error', text = 'a very long sentence about the server', visible = true } })
  T.check(ours.where.warn and ours.where.warn.label == 'no server' and ours.where.warn.level == 'error'
    and ours.where.warn.text, 'a warning: our word, its level, the full text kept for the panel')
  rl, ours = hud.build(run('running', { clock = 60, along = 1500 }), { now = 38700, place = WHERE.place,
    earthBanner = { id = 'ok', level = 'info', text = '', visible = false } })
  T.check(ours.where and not ours.where.warn, 'all well: no warning, and the road still shown')

  -- a menu is up: the HUD draws nothing (it is over the pause menu otherwise)
  rl, ours = hud.build(run('running', { clock = 60, along = 1500, offRoute = true }),
    { now = 38700, road = 'Maryhill Loops Road', uiHidden = true })
  T.check(next(ours.show) == nil, 'a menu up: our HUD shows nothing')
  T.check(rl ~= nil and rl.showStageApps == true, '... the stock apps are left to the game')

  -- on the stage
  rl, ours = hud.build(run('running', { clock = 0.4, along = 31 }), { now = 38610.4 })
  T.check(ours.show.go and ours.show.km, 'GO just after the start')
  rl, ours = hud.build(run('running', { clock = 161.7, along = 3130 }), { now = 38772 })
  local sd = rl.stageData
  T.check(rl.activeState == 'stageActive' and rl.showStageApps == true and rl.uiColors.theme == '#1f8fff' and
    sd.stageHeader == 'SS2 · KUHNLE' and sd.currentSSTime == 161.7 and sd.isActive, 'on the stage: the stock stage time (theme colour sent)')
  T.check(math.abs(sd.completion.distPct - 3100 / 8400) < 1e-9 and sd.completion.totalDistM == 8400 and #sd.splits == 1 and
    sd.splits[1].pathnodeType == 'finish' and sd.splits[1].splitLabel == '8.4' and sd.unit == 'km',
    'the progress bar: share done, one "finish" split labelled with the length')
  T.check(ours.show.km and ours.doneM == 3100 and ours.totalM == 8400 and not ours.show.go and not ours.show.offRoute,
    'our km readout: 3.1 of 8.4')
  rl, ours = hud.build(run('running', { clock = 200, along = 4000, off = 85, offRoute = true, backBearing = -130 }),
    { now = 38810, units = 'mi' })
  T.check(ours.show.offRoute and ours.show.dimNotes == nil and not ours.show.km and ours.offM == 85
    and ours.backBearing == -130,
    'off route: the amber card in the bar\'s place, and no dim over the notes (1.2.3)')
  T.check(rl.stageData.unit == 'mi' and rl.stageData.splits[1].splitLabel == '5.2' and ours.units == 'mi', 'miles')

  -- the flying finish, on to the stop control
  local fin = { clock = 368.9, stageTime = 368.9, finalTime = 378.9, penalty = 10, jumpStart = true, bestBefore = 372.4,
    toControlM = 220, sinceFinish = 1 }
  rl, ours = hud.build(run('toStop', fin), { now = 38980, speed = 20 })
  T.check(rl.activeState == 'vehicleProximity' and rl.scheduleData.eventType == 'ss_stop' and rl.vehicleProximity.distance == 220
    and not rl.vehicleProximity.isNear and rl.showStageApps and rl.stageData.currentSSTime == 368.9 and rl.stageData.isComplete,
    'to the stop control: the stock SLOW and distance, the stage time kept top-left')
  T.check(ours.show.finish and ours.finish.time == 378.9 and math.abs(ours.finish.delta - 6.5) < 1e-9 and not ours.finish.newBest
    and ours.finish.penalties.jumpStart == 10 and ours.finish.penalty == 10, 'the flying-finish card: slower than the best, the jump start in it')
  fin.sinceFinish = 5
  rl, ours = hud.build(run('toStop', fin), { now = 38984 })
  T.check(not ours.show.finish, '... for a few seconds')
  rl, ours = hud.build(run('toStop', { stageTime = 360, finalTime = 360, penalty = 0, sinceFinish = 0, toControlM = 20 }), ctx)
  T.check(ours.finish.newBest and ours.finish.first and rl.vehicleProximity.isNear, 'a first time is a best; near the stop: STOP')

  -- stage done: the results card (after the finish card), penalties itemised
  local done = { stageTime = 361.4, finalTime = 401.4, penalty = 40, jumpStart = true, resets = 2, latePenalty = 10,
    checks = { lateMinutes = 1 }, bestBefore = 372.4, sinceFinish = 9, resultsOpen = true,
    nextStage = { id = 'ss3', ss = 3, name = 'Deckerville', lengthM = 11800 } }
  rl, ours = hud.build(run('finished', done), { now = 39000, c = { resetS = 10 } })
  local p = ours.results and ours.results.finish.penalties
  T.check(rl.activeState == 'inactive' and rl.showStageApps == false and ours.show.results and not ours.show.finish,
    'stage done: the stock apps blank, our results card')
  T.check(p and p.jumpStart == 10 and p.late == 10 and p.lateMinutes == 1 and p.resets == 20 and p.resetCount == 2 and
    p.missedAtc == 0 and ours.results.next.name == 'Deckerville' and ours.results.next.ss == 3, 'the penalties itemised, the next stage')
  done.resultsOpen = false
  rl, ours = hud.build(run('finished', done), { now = 39000 })
  T.check(not ours.show.results, 'the card closed')
  done.sinceFinish, done.resultsOpen = 1, true
  rl, ours = hud.build(run('finished', done), { now = 39000 })
  T.check(ours.show.finish and not ours.show.results, 'finished at the flying finish (no stop control): the big time first')
  rl, ours = hud.build(run('failed', { error = 'no world' }), ctx)
  T.check(rl.activeState == 'inactive' and ours.error == 'no world' and next(ours.show) == nil, 'failed: nothing shown, the error said')
end

------------------------------------------------------------------------------------------ the HUD preview
do
  local preview = require('earthRally/preview')
  local seen, states, t = {}, {}, 0
  local dur = preview.duration()
  T.check(dur > 30 and dur < 120, 'the preview lasts about a minute (' .. dur .. ' s)')
  while true do
    local rl, ours, label = preview.frameAt(t)
    if not rl then break end
    T.check(ours.preview == true and ours.previewLabel == label, 'preview frames say so (' .. label .. ')')
    for k in pairs(ours.show) do seen[k] = true end
    states[ours.state] = true
    t = t + 0.25
  end
  T.check(t >= dur - 0.25, 'played to the end')
  for _, k in ipairs({ 'next', 'timecard', 'bigCount', 'go', 'jump', 'km', 'offRoute', 'finish', 'results' }) do
    T.check(seen[k], 'the preview shows ' .. k)
  end
  for _, s in ipairs({ 'toAtc', 'toStart', 'waitStart', 'running', 'toStop', 'finished' }) do
    T.check(states[s], 'the preview passes through ' .. s)
  end
  T.check(preview.frameAt(dur + 1) == nil, 'nothing after the end')
end

------------------------------------------------------------------------------------------ the menu's data
do
  local events = require('earthRally/events')
  local menu = require('earthRally/menu')
  local line = { { 47.0, -123.0 }, { 47.01, -123.0 } }
  files['/earthRally/events/ev.json'] = { format = 1, id = 'ev', name = 'Test Rally', source = { file = 'Test 26.kml' },
    stages = {
      { id = 'a', name = 'Alpha', lengthM = 5000, line = line, controls = {} },
      { id = 'b', name = 'Bravo', lengthM = 7000, line = line, controls = { stop = { lat = 47.011, lon = -123 } } },
      { id = 'c', name = 'Charlie', lengthM = 3000, line = line, controls = {} },
    } }
  events.list(true)
  -- Alpha: a matched line all on the map; Bravo: a matched line with a gap; Charlie: nothing
  files['/earthRally/matched/ev__a.json'] = { points = { { 47, -123, 0 }, { 47.01, -123, 0 } }, mapKey = events.mapKey(line),
    junctions = { { 47.001, -123, 'turn' }, { 47.002, -123, 'fork', 'left' } }, bridges = { { 47.003, -123 } } }
  files['/earthRally/matched/ev__b.json'] = { points = { { 47, -123, 0 }, { 47.01, -123, 0 } }, gapM = 1200 }
  files['/earthRally/results/ev__a.json'] = { runs = {
    { finished = true, timeS = 300, penaltyS = 0, date = '2026-11-12T10:00:00Z', checks = { cornersFound = 41 } },
    { finished = true, timeS = 290, penaltyS = 20, resets = 2, date = '2026-11-12T11:00:00Z' },
    { finished = true, timeS = 310, penaltyS = 10, jumpStart = true, date = '2026-11-12T12:00:00Z' } } }
  local cards = menu.rallies()
  T.check(#cards == 1 and cards[1].name == 'Test Rally' and cards[1].file == 'Test 26.kml' and cards[1].stages == 3 and
    cards[1].lengthM == 15000 and cards[1].driven == 1, 'Rallies: a card with stages, km and how many driven')
  local r = menu.rally('ev')
  T.check(#r.list == 3 and r.list[1].ss == 1 and r.list[3].ss == 3 and r.list[1].status == 'ready' and
    r.list[2].status == 'recce' and r.list[3].status == 'none' and r.list[1].best == 290 and r.list[2].best == nil,
    'a rally: SS numbers in map order, each stage\'s status and best')
  local s = menu.stage('ev', 'a', 'start')
  T.check(s.ss == 1 and s.ssCount == 3 and s.junctions == 2 and s.bridges == 1 and s.corners == 41 and s.canDrive and
    s.status == 'ready' and not s.atc and not s.stop, 'a stage: junctions and bridges from its matched line, corners from a run')
  T.check(#s.runs == 3 and s.runs[1].timeS == 310 and s.runs[1].last and s.runs[1].text == '+10 s jump start' and
    s.runs[2].text == '+20 s 2 resets' and s.runs[3].text == 'clean', 'its runs, newest first, penalties in words')
  local s2 = menu.stage('ev', 'b', 'ATC')
  T.check(s2.status == 'recce' and s2.note:find('1.2 km') and s2.atc and s2.stop and s2.junctions == 0,
    'a stage with a gap: recce recommended')
  local s3 = menu.stage('ev', 'c')
  T.check(s3.status == 'none' and not s3.canDrive and s3.corners == nil and s3.junctions == nil, 'no line: no Drive stage')
  T.check(menu.stage('ev', 'zzz') == nil and menu.rally('nope') == nil, 'unknown ids: nil')
end

T.done('test_hud')
