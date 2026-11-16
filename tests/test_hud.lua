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
  T.check(v.units == 'km' and v.resetPenalty == true and v.zoneBrake == true and
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
  T.check(v.units == 'km', 'an unreadable file: the defaults')
  local ui = settings.uiState()
  T.check(#ui.schema == #settings.ORDER and ui.schema[1].id == 'units' and ui.schema[1].options[2].value == 'mi' and
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
    and not rl.vehicleProximity.isNear and rl.showStageApps and rl.stageData.currentSSTime == 378.9 and rl.stageData.isComplete,
    'to the stop control: the stock SLOW and distance, the stage clock stopped at the time that counts (penalty in: 1.6.2)')
  T.check(ours.show.finish and ours.finish.time == 378.9 and math.abs(ours.finish.delta - 6.5) < 1e-9 and not ours.finish.newBest
    and ours.finish.penalties.jumpStart == 10 and ours.finish.penalty == 10, 'the flying-finish card: slower than the best, the jump start in it')
  T.check(ours.show.finish == 'big', 'at the line: the time at its larger size (beside the stage clock, not mid-screen: #17)')
  local kBig = select(2, hud.streamKeys(run('toStop', fin), { now = 38980 }))
  fin.sinceFinish = hud.FINISH_BIG_S + 0.1
  rl, ours = hud.build(run('toStop', fin), { now = 38980 })
  local kTucked = select(2, hud.streamKeys(run('toStop', fin), { now = 38980 }))
  T.check(ours.show.finish == 'tucked' and kBig ~= kTucked,
    '... a few seconds, then tucked into the top bar, and the stream says so (keys ' .. kBig .. ' / ' .. kTucked .. ')')
  fin.sinceFinish = 60
  rl, ours = hud.build(run('toStop', fin), { now = 38984 })
  T.check(ours.show.finish == 'tucked', '... and kept, tucked, all the way to the stop control')
  T.check(hud.finishPhase(run('running', {})) == nil and hud.finishPhase(nil) == nil, 'finishPhase: nothing before the finish')
  rl, ours = hud.build(run('toStop', { stageTime = 360, finalTime = 360, penalty = 0, sinceFinish = 0, toControlM = 20 }), ctx)
  T.check(ours.finish.newBest and ours.finish.first and rl.vehicleProximity.isNear, 'a first time is a best; near the stop: STOP')

  -- a Route to start armed (1.6.2): the line in the rally block's corner once a run is over, never during one
  local ap = { name = 'Deckerville', distM = 4230 }
  rl, ours = hud.build(run('finished', { finalTime = 300, stageTime = 300, sinceFinish = 9, resultsOpen = true }),
    { now = 38990, approach = ap })
  T.check(ours.show.approach and ours.approach.name == 'Deckerville' and ours.approach.distM == 4230,
    'route armed, the run over: the approach line is up')
  rl, ours = hud.build(run('running', { clock = 20, along = 300 }), { now = 38990, approach = ap })
  T.check(not ours.show.approach, '... and not during a run')
  rl, ours = hud.build(run('finished', { finalTime = 300, sinceFinish = 9, resultsOpen = true }),
    { now = 38990, approach = ap, uiHidden = true })
  T.check(not ours.show.approach, '... nor with a menu up')
  T.check(hud.approachText(ap, 'km') == 'Route to Deckerville · 4.2 km · gets ready as you arrive'
    and hud.approachText({ name = 'X' }, 'mi') == 'Route to X · gets ready as you arrive' and hud.approachText(nil) == nil,
    'the line as words, for the Messages app: ' .. tostring(hud.approachText(ap, 'km')))
  local fr = run('finished', { finalTime = 300, sinceFinish = 9, resultsOpen = true })
  local function ko(a) return select(2, hud.streamKeys(fr, { now = 38990, units = 'km', approach = a })) end
  T.check(ko({ name = 'D', distM = 4230 }) == ko({ name = 'D', distM = 4240 })
    and ko({ name = 'D', distM = 4230 }) ~= ko({ name = 'D', distM = 4130 }) and ko(nil) ~= ko({ name = 'D', distM = 4230 })
    and ko({ name = 'D', distM = 4230 }) ~= ko({ name = 'E', distM = 4230 }),
    'the approach line in our stream key: its stage, and the distance to 0.1 km as drawn')
  T.check(hud.approachKey({ name = 'D', distM = 1600 }, 'mi') ~= hud.approachKey({ name = 'D', distM = 1450 }, 'mi'),
    '... 0.1 mi in miles')

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
  T.check(ours.stage.ssLabel == 'SS2' and ours.results.next.ssLabel == 'SS3',
    'a run carrying no SS label (an old event file): SS numbers by map order, as before')

  -- the SS label the menu names (menu.ssLabel, carried by the runner): its passes; false: its name alone
  rl, ours = hud.build(run('running', { clock = 10, along = 300, ssLabel = 'SS4 · SS9' }), { now = 38772 })
  T.check(rl.stageData.stageHeader == 'SS4 · SS9 · KUHNLE' and ours.stage.ssLabel == 'SS4 · SS9',
    'a stage run twice: both passes in the header and on our HUD, as the menu names them')
  T.check(rl.scheduleData.label == 'SS4' and rl.scheduleData.ssLabel == '4' and rl.stageData.label == '4',
    "and the stock apps' one-SS badge: its first pass only, never '4 · SS9' (" .. tostring(rl.scheduleData.ssLabel) .. ')')
  rl, ours = hud.build(run('toStart', { ssLabel = 'SS4 · SS9', startAt = 38610, toControlM = 50 }), { now = 38552 })
  T.check(rl.scheduleData.label == 'SS4' and rl.scheduleData.ssLabel == '4', 'the same on the way to the start')
  rl, ours = hud.build(run('running', { clock = 10, along = 300, ssLabel = false }), { now = 38772 })
  T.check(rl.stageData.stageHeader == 'KUHNLE' and rl.scheduleData.label == 'Kuhnle' and rl.stageData.label == 'Kuhnle'
    and ours.stage.ssLabel == '', 'a stage the itinerary never runs: its name, no made-up SS number, no empty badge')
  rl, ours = hud.build(run('toStart', { ssLabel = false, startAt = 38610, toControlM = 50 }), { now = 38552 })
  T.check(rl.scheduleData.label == 'Kuhnle' and rl.scheduleData.ssLabel == 'Kuhnle', 'and on the way to the start')
  T.check(hud.stockLabel('SS2 · SS4', 'X') == 'SS2' and hud.stockLabel('SS7', 'X') == 'SS7' and
    hud.stockLabel('', 'Wildcat') == 'Wildcat' and hud.stockLabel('2 · 5', 'X') == '2', 'stockLabel')
  local d2 = {}
  for k, v in pairs(done) do d2[k] = v end
  d2.nextStage = { id = 'ss3', ss = 3, ssLabel = false, name = 'Deckerville', lengthM = 11800 }
  rl, ours = hud.build(run('finished', d2), { now = 39000 })
  T.check(ours.results.next.ssLabel == '', 'the next stage, never run: its name alone')
  T.check(hud.ssText('SS5', 2) == 'SS5' and hud.ssText(false, 2) == '' and hud.ssText(nil, 2) == 'SS2' and
    hud.ssText(nil, nil) == '', 'ssText')

  done.resultsOpen = false
  rl, ours = hud.build(run('finished', done), { now = 39000 })
  T.check(not ours.show.results, 'the card closed')
  done.sinceFinish, done.resultsOpen = 1, true
  rl, ours = hud.build(run('finished', done), { now = 39000 })
  T.check(ours.show.finish == 'big' and not ours.show.results, 'finished at the flying finish (no stop control): the big time first')
  done.sinceFinish = (hud.FINISH_BIG_S + hud.FINISH_CARD_S) / 2
  rl, ours = hud.build(run('finished', done), { now = 39000 })
  T.check(ours.show.finish == 'tucked' and not ours.show.results, '... tucked away until the results card')
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
      { id = 'a', name = 'Alpha', lengthM = 5000, line = line, controls = {}, marks = {
        { kind = 'radio', name = 'Radio 1', lat = 47.002, lon = -123 },
        { kind = 'radio', name = 'Radio 2', lat = 47.006, lon = -123 },
        { kind = 'marshal', name = 'Marshal 1', lat = 47.004, lon = -123 } } },
      { id = 'b', name = 'Bravo', lengthM = 7000, line = line, controls = { stop = { lat = 47.011, lon = -123 } } },
      { id = 'c', name = 'Charlie', lengthM = 3000, line = line, controls = {} },
    } }
  events.list(true)
  -- A line to be measured: 600 m north, a 90 degree right-hand corner of radius 40 m, 600 m east, climbing all the
  -- way (0.04 m a metre, about 50 m in all) and never falling. One corner, a real climb, no drop.
  local KY, KX = 111195, 75800           -- m a degree at 47 N, near enough for a test line
  local function bent()
    local pts, x, y, h = {}, 0, 0, math.pi / 2
    local function add() pts[#pts + 1] = { 47.0 + y / KY, -123.0 + x / KX, 100 + #pts * 0.16 } end
    add()
    for _ = 1, 150 do x, y = x + math.cos(h) * 4, y + math.sin(h) * 4 add() end
    for _ = 1, 16 do h = h - (math.pi / 2) / 16 x, y = x + math.cos(h) * 4, y + math.sin(h) * 4 add() end
    for _ = 1, 150 do x, y = x + math.cos(h) * 4, y + math.sin(h) * 4 add() end
    return pts
  end

  -- Alpha: a matched line all on the map; Bravo: a matched line with a gap; Charlie: nothing
  files['/earthRally/matched/ev__a.json'] = { points = bent(), mapKey = events.mapKey(line),
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
  T.check(s.ss == 1 and s.ssCount == 3 and s.canDrive and s.status == 'ready' and not s.atc and not s.stop,
    'a stage: its number, its line and its controls')
  -- the four tiles are Length, Corners, Gain, Loss: Junctions and Bridges went in 1.3.1 (the landmark data stays,
  -- it is what the pacenotes are made of -- only the two tiles are gone)
  T.check(s.junctions == nil and s.bridges == nil, 'no junctions or bridges tile')
  -- Corners comes off the line, which this stage has, and NOT out of the run that recorded cornersFound 41: that
  -- was the 1.3.0 bug the other way round -- a stage with a line and no runs had nothing to show.
  T.check(s.corners == 1, 'corners from the line: the one corner on it (' .. tostring(s.corners) .. ')')
  T.near(s.gainM, 50, 2, 'the climb along it')
  T.check(s.lossM == 0, 'and nothing given back (' .. tostring(s.lossM) .. ')')
  T.check(#s.runs == 3 and s.runs[1].timeS == 310 and s.runs[1].last and s.runs[1].text == '+10 s jump start' and
    s.runs[2].text == '+20 s 2 resets' and s.runs[3].text == 'clean', 'its runs, newest first, penalties in words')
  -- The figures a line was saved with are the ones shown, never worked out again: the page asks for a stage every
  -- two seconds while it is open, so what is kept with the line has to be what is read. Nothing but a stored
  -- figure can make this line read 7 corners.
  files['/earthRally/matched/ev__a.json'].corners = 7
  files['/earthRally/matched/ev__a.json'].gainM = 11.1
  files['/earthRally/matched/ev__a.json'].lossM = 22.2
  -- (of an older count -- before a chicane was one note -- they are not: worked out again)
  events.forget()
  local sOld = menu.stage('ev', 'a', 'start')
  T.check(sOld.corners == 1, 'figures kept by an older version are counted again (' .. tostring(sOld.corners) .. ')')
  files['/earthRally/matched/ev__a.json'].figures = require('earthRally/lineStats').VERSION
  events.forget()
  local sKept = menu.stage('ev', 'a', 'start')
  T.check(sKept.corners == 7 and sKept.gainM == 11.1 and sKept.lossM == 22.2,
    'the figures kept with the line are the ones shown (' .. tostring(sKept.corners) .. ')')
  files['/earthRally/matched/ev__a.json'].figures = nil
  files['/earthRally/matched/ev__a.json'].corners = nil
  files['/earthRally/matched/ev__a.json'].gainM, files['/earthRally/matched/ev__a.json'].lossM = nil, nil
  events.forget()
  local s2 = menu.stage('ev', 'b', 'ATC')
  T.check(s2.status == 'recce' and s2.note:find('1.2 km') and s2.atc and s2.stop,
    'a stage with a gap: recce recommended')
  -- a line of two points 1.1 km apart, both at height 0: a straight with no corner, and no height to read (every
  -- point at one height is a line that was given none, not a flat road) -- so Gain and Loss are dashes
  T.check(s2.corners == 0 and s2.gainM == nil and s2.lossM == nil, 'a straight line with no heights: 0 corners, no climb')
  local s3 = menu.stage('ev', 'c')
  T.check(s3.status == 'none' and not s3.canDrive and s3.corners == nil and s3.gainM == nil,
    'no line: no Drive stage, and the one dash that means no line')
  -- the points row (docs/mockups-1.6.0/stage-points.html): the map's counts per kind, and a stage that marks
  -- nothing still carries all four at 0, so its row reads Random / None rather than not being drawn
  local m = s.marks
  T.check(m and m.radio == 2 and m.marshal == 1 and m.medical == 0 and m.spectator == 0,
    'a stage\'s marks: the map\'s count of each kind, 0 for a kind it marks none of')
  local m3 = s3.marks
  T.check(m3 and m3.radio == 0 and m3.medical == 0 and m3.spectator == 0 and m3.marshal == 0,
    'a stage the map marks nothing on: all four kinds, each 0')
  -- 1.6.0's note 5: the kinds the rally's map marks on any stage, on every stage's page (a kind marked elsewhere and
  -- not here reads None, not Random)
  local k3 = s3.marked
  T.check(k3 and k3.radio == true and k3.marshal == true and k3.medical == false and k3.spectator == false and
    s.marked and s.marked.radio == true, 'marked: the rally\'s kinds, the same on a stage with none of its own')
  local kz = events.markedKinds('nope')
  T.check(kz.radio == false and kz.medical == false and kz.spectator == false and kz.marshal == false,
    'markedKinds: an unknown rally marks nothing')
  -- review round 4: only the marks some stage would use count -- a radio point 500 m off the line, a spectator point
  -- 5 km past the finish: not marked; a marshal on the line within the span: marked
  files['/earthRally/events/evu.json'] = { format = 1, id = 'evu', name = 'Unused Marks', source = { file = 'U.kml' },
    stages = { { id = 'u', name = 'U', lengthM = 5000, line = line, controls = {}, marks = {
      { kind = 'radio', name = 'Far off', lat = 47.002, lon = -123, distM = 2000, offLineM = 500 },
      { kind = 'spectator', name = 'Past it', lat = 47.002, lon = -123, distM = 10000, offLineM = 5 },
      { kind = 'marshal', name = 'On it', lat = 47.002, lon = -123, distM = 2500, offLineM = 5 } } } } }
  events.list(true)
  local ku = events.markedKinds('evu')
  T.check(ku.radio == false and ku.spectator == false and ku.marshal == true and ku.medical == false,
    'markedKinds: a mark no stage would use (too far off the line, past the finish) does not count')
  T.check(menu.stage('ev', 'zzz') == nil and menu.rally('nope') == nil, 'unknown ids: nil')
end

------------------------------------------------------------------------------------------ 1.6.1: the stream keys
-- main.lua sends a stream only when hudFrame.streamKeys's string for it changes. The contract: whenever what the
-- apps draw from build's frame changes, at the precision they draw it, the key changes too. Sample runs stepped at
-- 60 fps through the states, the drawn text compared frame by frame. (The stock progress bar moves with the stage
-- time's tenths, so its distPct is not in the drawn text.)
do
  local function r10(v) return v and tostring(math.floor(v * 10 + 0.5)) or '-' end
  local function r1(v) return v and tostring(math.floor(v + 0.5)) or '-' end
  local function flags(t)
    local ks = {}
    for k, v in pairs(t or {}) do if v then ks[#ks + 1] = k .. '=' .. tostring(v) end end
    table.sort(ks)
    return table.concat(ks, ',')
  end
  local function drawn(rl, ours)
    local o = ours or {}
    -- (the rally clock is drawn only in the panel on the way to a stage: not once the run is over)
    local parts = { o.state, flags(o.show), o.state ~= 'finished' and o.clockText or '-', tostring(o.countdown), tostring(o.canSkip),
      (o.show and o.show.next) and r1(o.toControlM) or '-',
      r10(o.doneM and o.doneM / 1000), r1(o.offM), r1(o.backBearing and o.backBearing / 2), r1(o.atcTime), r1(o.startAt),
      tostring(o.missedAtc), o.finish and r10(o.finish.time) or '-',
      (o.show and o.show.approach and o.approach) and (o.approach.name .. r10(o.approach.distM and o.approach.distM / 1000)) or '-' }
    local mine = table.concat(parts, '#')
    parts = {}
    if rl then
      local sd, vp, cd, sc = rl.stageData or {}, rl.vehicleProximity or {}, rl.countdownData or {}, rl.scheduleData or {}
      parts[#parts + 1] = table.concat({ tostring(rl.activeState), tostring(rl.showStageApps), r10(sd.currentSSTime),
        tostring(sd.isActive), tostring(sd.isComplete), tostring(cd.countdown), tostring(sc.timeDiff),
        vp.distance and (math.abs(vp.distance) < 5 and string.format(vp.isStartLine and '%.2f' or '%.1f', vp.distance) or r1(vp.distance)) or '-',
        tostring(vp.isNear), tostring(vp.isStopped), tostring(vp.isFrozen),
        rl.rallyClock and rl.rallyClock.wallClockTime and rl.rallyClock.wallClockTime.time or '-' }, '|')
    end
    return table.concat(parts, '#'), mine
  end
  local stage = { name = 'Weaver Bend', lengthM = 6800 }
  -- each case: a run, and a step(run, t) moving it as play would; ctx's now is the rally clock
  local cases = {
    { 'on the line', { state = 'waitStart', startM = 0, finishM = 6800, stage = stage, startAt = 36025.3 },
      function(r, t) end, 36000 },
    { 'on the stage', { state = 'running', startM = 0, finishM = 6800, stage = stage, startAt = 36000, along = 0, clock = 0 },
      function(r, t) r.clock, r.along = t, 32 * t end, 36000 },
    { 'off route', { state = 'running', startM = 0, finishM = 6800, stage = stage, startAt = 36000, along = 900,
      clock = 40, offRoute = true, off = 20, backBearing = 0 },
      function(r, t) r.clock, r.off, r.backBearing = 40 + t, 20 + 3 * t, (t * 70) % 360 end, 36040 },
    { 'to the time control', { state = 'toAtc', startM = 0, finishM = 6800, stage = stage, toControlM = 900 },
      function(r, t) r.toControlM = math.max(0, 900 - 25 * t) end, 35900 },
    { 'onto the start line', { state = 'toStart', startM = 0, finishM = 6800, stage = stage, startAt = 36090,
      toControlM = 6, atcTime = 35990, zone = {} },
      function(r, t) r.toControlM = 6 - 0.4 * t end, 36000 },
    { 'to the start', { state = 'toStart', startM = 0, finishM = 6800, stage = stage, startAt = 36090, toControlM = 300,
      atcTime = 35990 },
      function(r, t) r.toControlM = math.max(0, 300 - 15 * t) if r.toControlM < 10 then r.zone = { held = t > 21 } end end,
      36000 },
    { 'to the stop', { state = 'toStop', startM = 0, finishM = 6800, stage = stage, startAt = 36000, finalTime = 300.4,
      stageTime = 300.4, sinceFinish = 0, toControlM = 200 },
      function(r, t) r.sinceFinish, r.toControlM = t, math.max(0, 200 - 20 * t) end, 36300 },
    -- (1.6.2: a Route to start armed while the results card is up, the car driving towards the next stage)
    { 'route armed, results up', { state = 'finished', startM = 0, finishM = 6800, stage = stage, startAt = 36000,
      finalTime = 300.4, stageTime = 300.4, sinceFinish = 9, resultsOpen = true },
      function(r, t) r.approachAt = { name = 'Deckerville', distM = 5000 - 30 * t } end, 36400 },
  }
  for _, cs in ipairs(cases) do
    local name, run, step, t0 = cs[1], cs[2], cs[3], cs[4]
    local prevD, prevK, prevO, prevKo, misses, frames = nil, nil, nil, nil, 0, 0
    local changes, sawRl = { 0, 0 }, false
    for f = 0, 60 * 25 do
      local t = f / 60
      step(run, t)
      local now = t0 + t
      local speed = run.state == 'toStart' and math.max(0, 15 - t) or 20
      local ctx = { now = now, speed = speed, units = 'km', canSkip = false, approach = run.approachAt }
      local rl, ours = hud.build(run, ctx)
      local kr, ko = hud.streamKeys(run, { now = now, units = 'km', stopped = speed < 1.0, canSkip = false, stopRadiusM = 25,
        approach = run.approachAt })
      local d, o = drawn(rl, ours)
      sawRl = sawRl or (rl ~= nil and rl.activeState ~= 'inactive')
      for _, pr in ipairs({ { prevD, d, prevK, kr, 'stock' }, { prevO, o, prevKo, ko, 'ours' } }) do
        if pr[1] and pr[2] ~= pr[1] then changes[pr[5] == 'stock' and 1 or 2] = changes[pr[5] == 'stock' and 1 or 2] + 1 end
        if pr[1] and pr[2] ~= pr[1] and pr[4] == pr[3] then
          misses = misses + 1
          if misses == 1 then print('  first miss, ' .. name .. ' (' .. pr[5] .. ') at ' .. t .. ' s:\n    ' .. pr[1]
            .. '\n    ' .. pr[2]) end
        end
      end
      prevD, prevK, prevO, prevKo, frames = d, kr, o, ko, frames + 1
    end
    T.check((changes[1] > 0 or not sawRl) and changes[2] > 0, 'stream keys: ' .. name .. ', the drawn text moves (' .. changes[1]
      .. ', ' .. changes[2] .. ')')
    T.check(misses == 0, 'stream keys: ' .. name .. ', every change drawn changes the key (' .. misses .. ' missed in '
      .. frames .. ' frames)')
  end
end

------------------------------------------------------------------------------------------ 1.7.0: hints, transits

do
  local h = hud.hintsFor('running', { rally = true })
  T.check(h and h[1].what == 'Recover' and h[1].keys:find('D-pad') ~= nil, 'a rally stage: recovery on the pad named')
  local h1 = hud.hintsFor('running', {})
  T.check(h1 and h1[1].keys == 'Backspace', "a single stage: Backspace only (D-pad right is the game's own reset)")
  T.check(hud.hintsFor('finished', {}) == nil, 'no hints once the stage is over')
  local rl, ours = hud.build({ state = 'running', stage = { name = 'X', lengthM = 1000 }, startM = 0, finishM = 1000,
    clock = 30, along = 100, off = 0, inRally = true }, { now = 100 })
  T.check(ours.show.hints and ours.hints[1].keys:find('D-pad') ~= nil, 'the strip is in the stream on a rally stage')
  local _, hidden = hud.build({ state = 'running', stage = { name = 'X', lengthM = 1000 }, startM = 0, finishM = 1000,
    clock = 30, along = 100, off = 0 }, { now = 100, uiHidden = true })
  T.check(not hidden.show.hints, 'a menu up: no strip')
  -- a rally's transit with no stage loaded: the line to where the car is going, said as a transit
  local _, tr = hud.build(nil, { rally = true, approach = { name = 'SS4 Hill', distM = 4200, rally = true } })
  T.check(tr.show.approach and tr.approach.label == 'Transit' and tr.approach.name == 'SS4 Hill', 'a transit: its line')
  local _, none = hud.build(nil, { approach = { name = 'Hill', distM = 4200 } })
  T.check(not none.show.approach, 'a plain Route to start with no run: left to the Messages app, as before')
  T.check(hud.approachText({ name = 'SS4 Hill', distM = 4200, rally = true }, 'km'):find('^Transit to SS4 Hill') ~= nil,
    'the Messages app line says transit')
  -- (#67) near a control: the line says to stop at its board
  local _, near = hud.build(nil, { rally = true, approach = { name = 'SS4 Hill', distM = 120, rally = true,
    stop = "Stop at the time control's red board" } })
  T.check(near.approach and near.approach.sub == "Stop at the time control's red board" and near.approach.stop ~= nil,
    'near the time control: the HUD line says to stop at its board (#67)')
  T.check(hud.approachText({ name = 'Service A', distM = 120, rally = true, stop = 'Stop at the board to check in' }, 'km')
    == 'Service A · 0.1 km · Stop at the board to check in', 'and the Messages line')
  T.check(hud.approachKey({ name = 'A', distM = 120, stop = 'x' }, 'km') ~= hud.approachKey({ name = 'A', distM = 150,
    stop = 'x' }, 'km'), 'near a control the stream follows the distance to 10 m')
  -- (#58, #69) a rally question with no stage under way: in our stream, and nothing with a menu up
  local _, la = hud.build(nil, { rally = true, rallyAsk = { mode = 'realistic', loadAsk = { ss = 'SS4', name = 'Hill' } } })
  T.check(la.rally and la.rally.loadAsk and la.show.loadAsk and not la.show.recoverAsk, '"Load the stage?" sent (#58)')
  local _, ta = hud.build(nil, { rally = true, rallyAsk = { mode = 'realistic', ask = { transit = true, stop = 'Service B' } } })
  T.check(ta.rally and ta.rally.ask.transit and ta.show.recoverAsk, 'Recover? on a transit sent (#69)')
  local _, hid = hud.build(nil, { rally = true, uiHidden = true, rallyAsk = { loadAsk = { ss = 'SS4' } } })
  T.check(not hid.show.loadAsk and hid.rally == nil, 'a menu up: not drawn')
end

T.done('test_hud')
