-- earthRally/hudFrame: what the screen shows during a run, from the run's state, in one pure function (no game
-- calls: runner.uiFrame passes in the clock and the car's speed; the HUD preview passes in sample runs).
--
--   rallyLoop   the stream the game's own rally apps read (ui/modules/apps/rallyLoop: RallyCountdown,
--               RallyStageTiming, RallyStageProgress), with their gotchas (docs/plan-1.2.0.md):
--               - each app copies the sub-tables it gets with Object.assign: a field not sent keeps its last value,
--                 and nil cannot be sent, so a field is sent only once it means something (the apps are mounted
--                 afresh with our stage layout each run)
--               - activeState is read every frame (missing: 'inactive'); uiColors.theme too (missing: the stage
--                 apps are hidden)
--               - the progress bar labels its finish with the last split's splitLabel: one 'finish' split is sent
--                 (RallyStageTiming skips 'finish' rows)
--               - countdownData.countdown whole seconds (5 squares from 5, GO at 0; null reads as GO)
--               - scheduleData.timeDiff a string ("0:58"); eventType 'tc' is never sent (it prints a speed limit
--                 we do not have: our own card covers the drive to the ATC)
-- (1.2.3: there is no longer a dim over the pacenote cards while off route. It was a plain box the size of the
--  stock app's whole slot, and the cards fill about a fifth of that, so most of it dimmed the scenery -- "just a big
--  rectangle" (the user, 2026-11-13). The 1.2.0 mock-up never had one.)
--   earthRally  ours (ui/modules/apps/EarthRallyHud, EarthRallyResults): the run's numbers in metres and seconds
--               and a `show` table saying which piece is up, so the Vue side only draws (units and words are its)
local M = {}

M.THEME = '#1f8fff'           -- the game's stage colour (gameplay/rally/loop/uiColors.lua: stage)
M.FINISH_CARD_S = 4           -- the flying-finish time up this long before the results card (no stop control)
M.FINISH_BIG_S = 3            -- ... and at its larger size this long, then tucked into the top bar (#17, 1.6.2)
M.JUMP_CARD_S = 3             -- the jump-start card
M.GO_SHOW_S = 1.5             -- "GO" after the start
M.BIG_COUNT_FROM = 5          -- our big numeral for the last seconds of the countdown (the stock squares light from 5)
M.TIMECARD_UNTIL_S = 10       -- the checked-in / start time line kept on the line until this close to the start
M.MILE_M = 1609.344

-- A stage's SS label on the HUD: label as the runner carries it (menu.ssLabel: 'SS3', 'SS2 · SS4'), '' when it is
-- false (a stage its rally's itinerary never runs: the HUD says its name alone), or SS<ss> by map order when the run
-- carries none (as every run did before rally files).
function M.ssText(label, ss)
  if type(label) == 'string' then return label end
  if label == false or ss == nil then return '' end
  return 'SS' .. tostring(ss)
end

-- What the stock apps are sent as a stage's label ('SS4'; their ssLabel is the number after "SS": '4'). They show
-- it in a badge made for one SS number, so a stage run twice ('SS4 · SS9') sends its first pass only; a stage the
-- itinerary never runs (label '') sends its name, never an empty badge. label: M.ssText's.
function M.stockLabel(label, name)
  if type(label) ~= 'string' or label == '' then return tostring(name or '') end
  return (label:match('^(.-)%s*·') or label):gsub('%s+$', '')
end

-- 'HH:MM:SS' of a time of day (s).
function M.clockText(t)
  if not t then return '--:--:--' end
  t = math.floor(t + 0.5) % 86400
  return string.format('%02d:%02d:%02d', math.floor(t / 3600), math.floor(t / 60) % 60, t % 60)
end

-- 'M:SS' of a wait (s, rounded up, never below 0), as the game's rallyLoopManager sends timeDiff.
function M.diffText(s)
  s = math.max(0, math.ceil((s or 0) - 1e-6))
  return string.format('%d:%02d', math.floor(s / 60), s % 60)
end

-- A length in the player's unit, one decimal ('8.4').
function M.lengthText(m, units)
  local v = (m or 0) / (units == 'mi' and M.MILE_M or 1000)
  return string.format('%.1f', v)
end

-- The way to `to` from `from`, against the heading `dir` (game coordinates, x east, y north): degrees clockwise,
-- -180..180 (0 straight ahead, 90 to the right, +-180 behind). nil without a heading.
function M.relBearing(dir, from, to)
  if not (dir and from and to) then return nil end
  local dx, dy = dir.x or 0, dir.y or 0
  local tx, ty = to.x - from.x, to.y - from.y
  if dx * dx + dy * dy < 1e-12 or tx * tx + ty * ty < 1e-12 then return nil end
  local ccw = math.atan2(dx * ty - dy * tx, dx * tx + dy * ty)
  return -math.deg(ccw)
end

local function penalties(run, c)
  local resets = run.resets or 0
  return {
    jumpStart = run.jumpStart and c.jumpStartS or 0,
    late = run.latePenalty or 0, lateMinutes = run.checks and run.checks.lateMinutes or 0,
    resets = resets * c.resetS, resetCount = resets,
    missedAtc = run.missedAtc and c.missedAtcS or 0,
  }
end

-- The flying-finish time's size now (1.6.2, #17: the 1.2.0 card was 800 px wide in the middle of the screen, over
-- the road just as the car crosses the line): 'big' for FINISH_BIG_S, the card beside the stage clock in the top bar
-- (where the km readout was), then 'tucked', the same place at the bar's own height, until the stop control (toStop)
-- or the results card (finished). nil before the finish.
function M.finishPhase(run)
  if not (run and run.finalTime) then return nil end
  return (run.sinceFinish or 0) < M.FINISH_BIG_S and 'big' or 'tucked'
end

-- The stage time at the flying finish, against the best before this run.
local function finishInfo(run, c)
  if not run.finalTime then return nil end
  local best = run.bestBefore
  return {
    time = run.finalTime, stageTime = run.stageTime, penalty = run.penalty or 0, best = best,
    delta = best and (run.finalTime - best) or nil, newBest = best == nil or run.finalTime < best, first = best == nil,
    penalties = penalties(run, c),
  }
end

-- A word of our own for BeamNG.Earth's banner, by its id (its banner.lua sets them): its own sentence runs to a
-- hundred characters and more, which belongs in the panel before a stage, not across a stage.
-- (every banner id BeamNG.Earth can raise: its strip is off screen during a stage, so an id missing from here is a
--  warning nobody draws at all. 'offline' and 'degraded' are its data-source warnings -- "areas never visited have
--  no terrain" -- which matter more to a stage on streamed ground than they do to free driving.)
M.WARN_WORDS = { noserver = 'no server', lost = 'reconnecting', edge = 'world edge',
                 drophold = 'loading ground', starting = 'starting', offline = 'offline data',
                 degraded = 'data missing' }

-- Where the car is and what BeamNG.Earth has to say about it, for the HUD's own row (its strips are off screen
-- during a stage). nil when there is nothing to say.
function M.whereOf(ctx)
  local p = ctx.place
  local rest = {}
  if type(p) == 'table' then
    for _, k in ipairs({ 'place', 'region', 'country' }) do
      if type(p[k]) == 'string' and p[k] ~= '' then rest[#rest + 1] = p[k] end
    end
  end
  local road = type(p) == 'table' and type(p.street) == 'string' and p.street ~= '' and p.street or nil
  local b = ctx.earthBanner
  local warn = nil
  if type(b) == 'table' and b.visible and M.WARN_WORDS[b.id] then
    warn = { label = M.WARN_WORDS[b.id], level = b.level or 'info', text = b.text }
  end
  local load = nil
  if type(ctx.loading) == 'table' and tonumber(ctx.loading.done) and tonumber(ctx.loading.total) then
    load = string.format('%d/%d', ctx.loading.done, ctx.loading.total)
  end
  if not (road or #rest > 0 or warn or load) then return nil end
  return { road = road, rest = #rest > 0 and table.concat(rest, ', ') or nil, warn = warn, loading = load }
end

local INACTIVE = { activeState = 'inactive', showStageApps = false }

-- A Route to start armed (1.6.2): the stage and how far off it is, one line in the rally block's corner. Ours is on
-- screen only in the stage layout, so this is for a run that is over with its layout still up (the results card);
-- with none, the player's own layout is up and main.lua says the same line through the game's Messages app
-- (M.approachText). An armed route waits while a run is under way (runner.stepApproach): nothing then.
-- (1.7.0) A full rally's transit (a.rally) says so: 'Transit', and what happens on arrival.
function M.approachLine(ours, ctx)
  local a = ctx.approach
  if type(a) ~= 'table' or ctx.uiHidden then return end
  -- (#67: a.stop, near a control: what to do there, "Stop at the board to check in", in place of the usual line)
  ours.approach = { name = a.name, distM = a.distM, label = a.waiting and 'Rally' or (a.rally and 'Transit' or 'Route'),
    sub = a.stop or (a.waiting and 'time card: Ctrl+Alt+K to go on' or (a.rally and 'follow the arrows' or 'gets ready as you arrive')),
    stop = a.stop }
  ours.show.approach = true
end

-- The same line as words, for the game's Messages app: 'Route to Kuhnle · 4.2 km · gets ready as you arrive'.
function M.approachText(a, units)
  if type(a) ~= 'table' then return nil end
  local d = a.distM and (' · ' .. M.lengthText(a.distM, units) .. (units == 'mi' and ' mi' or ' km')) or ''
  -- (the HUD app is not on screen between stages: the Messages line carries the transit's controls, #27)
  -- (#35: a rally waiting at a stop for the player: what is next and how to go on)
  if a.waiting then
    return tostring(a.name) .. ' · open the time card to go on: Ctrl+Alt+K'
  end
  if a.stop then return tostring(a.name or 'the stage') .. d .. ' · ' .. a.stop end
  if a.rally then
    return 'Transit to ' .. tostring(a.name or 'the stage') .. d ..
      ' · follow the arrows · Recover: Backspace / D-pad → · Time card: Ctrl+Alt+K'
  end
  return 'Route to ' .. tostring(a.name or 'the stage') .. d .. ' · gets ready as you arrive'
end

-- (1.7.0, #27) The controls for what the player can do now, a short strip at the foot of the screen: { { keys,
-- what }... } or nil. ctx.rally: a full rally is under way (its recovery has a pad button, D-pad right).
function M.hintsFor(state, ctx)
  local rallyOn = ctx and ctx.rally
  local recover = { keys = rallyOn and 'Backspace · D-pad →' or 'Backspace', what = 'Recover' }
  local menuKey = { keys = 'Ctrl+Alt+K', what = rallyOn and 'Time card' or 'Menu' }
  if state == 'transit' then
    return { recover, menuKey }
  elseif state == 'toAtc' or state == 'toStart' or state == 'running' or state == 'toStop' then
    return { recover, { keys = 'Shift+Backspace', what = 'Flip upright' }, menuKey }
  elseif state == 'waitStart' then
    return { { keys = 'Shift+E · RB+Y', what = 'Skip the wait' }, menuKey }
  end
  return nil
end

-- The approach line's part of our stream key: the stage, and the distance as drawn (0.1 km / 0.1 mi).
function M.approachKey(a, units)
  if type(a) ~= 'table' then return 'ap-' end
  local step = units == 'mi' and M.MILE_M / 10 or 100
  -- (near a control the line counts down in metres: drawn to 10 m there)
  if a.stop then step = 10 end
  return 'ap' .. tostring(a.name) .. '|' .. (a.distM and tostring(math.floor(a.distM / step + 0.5)) or '-') .. '|' ..
    tostring(a.stop)
end

-- (#58, #69) A rally's question with no stage under way (ctx.rallyAsk): sent as ours.rally, as a stage's own Recover?
-- is, with show.loadAsk ("Load the stage?") or show.recoverAsk (Recover? on a transit).
function M.askOn(ours, ctx)
  local q = ctx.rallyAsk
  if type(q) ~= 'table' or ctx.uiHidden then return end
  ours.rally = q
  if q.loadAsk then ours.show.loadAsk = true end
  if q.ask then ours.show.recoverAsk = true end
end

-- The two streams for `run` (nil: no run). ctx:
--   now           the rally clock (s of the day)
--   speed         the car's speed (m/s)
--   canSkip       the start-line skip is possible now (runner.canSkip)
--   units         'km' / 'mi'
--   noRallyLoop   true: leave the rallyLoop stream alone (the game's own rally mode is running): nil is returned
--   c             the runner's numbers: stoppedMs, startZoneBeforeM, stopRadiusM, jumpStartS, resetS, missedAtcS
--   road          the road the car is on (BeamNG.Earth), or nil
--   loadPct       how much of the world round the car has arrived, 0..100, or nil once it is all there
--   earthWarn     what BeamNG.Earth's banner would say, or nil
--   place         where the car is (BeamNG.Earth): { street, place, region, country }, or nil
--   earthBanner   BeamNG.Earth's banner: { id, level, text, visible }, or nil
--   loading       the world still arriving: { done, total }, or nil
--   uiHidden      a menu is up: the HUD draws nothing (it is over the pause menu otherwise)
--   preview       true in the HUD preview (said in our stream)
--   approach      a Route to start armed (runner.approachInfo): { name, distM, stop }, or nil
--   rallyAsk      a full rally's question with no stage under way (rallyRun.askInfo): { mode, ask } (Recover? on a
--                 transit, ask.transit = true) or { mode, loadAsk = { ss, name, km } } ("Load the stage?", #58)
-- Returns rallyLoop, earthRally.
--
-- (M.streamKeys, below, must change whenever what build gives the screen changes: a value added to build that the
-- screen draws needs its place in the keys too, at the precision it is drawn at)
function M.build(run, ctx)
  ctx = ctx or {}
  local c = ctx.c or {}
  c.stoppedMs, c.startZoneBeforeM, c.stopRadiusM = c.stoppedMs or 1.0, c.startZoneBeforeM or 12, c.stopRadiusM or 25
  c.jumpStartS, c.resetS, c.missedAtcS = c.jumpStartS or 10, c.resetS or 10, c.missedAtcS or 60
  local units = ctx.units == 'mi' and 'mi' or 'km'
  local ours = { v = 1, state = run and run.state or 'idle', units = units, preview = ctx.preview or nil, show = {} }
  if not run then
    -- (1.7.0: a full rally's transit, no stage loaded: the line to where the car is going, and its controls)
    if ctx.rally and type(ctx.approach) == 'table' and not ctx.uiHidden then
      M.approachLine(ours, ctx)
      ours.hints = M.hintsFor('transit', ctx)
      ours.show.hints = ours.hints and true or nil
    end
    M.askOn(ours, ctx)
    return (not ctx.noRallyLoop) and INACTIVE or nil, ours
  end

  local s = run.state
  local now = ctx.now or 0
  local speed = ctx.speed or 0
  local show = ours.show
  local stage = run.stage or {}
  local totalM = (run.finishM and run.startM) and (run.finishM - run.startM) or stage.lengthM or 0
  ours.clock, ours.clockText = now, M.clockText(now)
  local label = M.ssText(run.ssLabel, run.ss)
  ours.stage = { ss = run.ss, ssLabel = label, ssCount = run.ssCount, name = stage.name,
    rally = run.event and run.event.name, lengthM = totalM }
  ours.atcTime, ours.startAt, ours.missedAtc = run.atcTime, run.startAt, run.missedAtc == true
  ours.toControlM = run.toControlM
  ours.finish = finishInfo(run, c)
  if s == 'failed' then ours.error = run.error end

  -- (the stock apps' label is one SS, or the stage's name (M.stockLabel); their ssLabel is the number after "SS" as
  -- they were always sent it: '2' for SS2)
  local stock = M.stockLabel(label, stage.name)
  local ssLabel = label ~= '' and stock:gsub('^SS', '') or stock
  local header = label ~= '' and (label .. ' · ' .. string.upper(stage.name or '')) or string.upper(stage.name or '')
  local rl = { activeState = 'inactive', showStageApps = false,
    rallyClock = { wallClockSecs = now, wallClockTime = { time = M.clockText(now), ampm = '' }, use24hFormat = true,
                   canSkipCountdown = false, canSkipTimeControls = false, isTimeControlSkipAvailable = false } }

  if s == 'travel' or s == 'anchor' or s == 'build' or s == 'place' then
    show.next = true
    ours.control = 'ready'
  elseif s == 'toAtc' then
    show.next = true
    ours.control = 'atc'
  elseif s == 'toStart' then
    ours.control = 'start'
    show.timecard = (run.atcTime or run.startAt or run.missedAtc) and true or nil
    rl.activeState = 'vehicleProximity'
    rl.scheduleData = { eventType = 'ss_start', label = stock, ssLabel = ssLabel, totalSSCount = run.ssCount,
      timeDiff = run.startAt and M.diffText(run.startAt - now) or nil }
    local d = run.toControlM or 0
    rl.vehicleProximity = { distance = d, distanceToPlane = d, isNear = run.zone ~= nil,
      isStopped = speed < c.stoppedMs, isFrozen = run.zone ~= nil and run.zone.held ~= nil, isStartLine = true,
      isOverLineAllowed = false, usingGroundMarkerDistance = false }
  elseif s == 'waitStart' then
    ours.control = 'start'
    local left = (run.startAt or now) - now
    local n = math.max(0, math.ceil(left - 1e-6))
    ours.countdown = n
    ours.canSkip = ctx.canSkip == true
    show.bigCount = n >= 1 and n <= M.BIG_COUNT_FROM or nil
    show.timecard = left > M.TIMECARD_UNTIL_S or nil
    rl.activeState = 'countdown'
    rl.rallyClock.canSkipCountdown = ctx.canSkip == true
    rl.countdownData = { countdown = n, state = n > 0 and 'counting' or 'go' }
    rl.scheduleData = { eventType = 'ss_start', label = stock, ssLabel = ssLabel, totalSSCount = run.ssCount,
      timeDiff = M.diffText(left) }
    -- Staged and ready: the stage clock and the progress meter come up reading zero rather than at GO (the user,
    -- 2026-11-13). uiColors must go with them or the stock apps hide themselves.
    -- Not while our timecard is up: it sits at 0, 0 and so does the stock stage clock (288 wide), so bringing them
    -- up a minute early would stack the two in that corner -- the fault reported as items 1 and 4. They come up as
    -- the timecard goes, TIMECARD_UNTIL_S before the start, which is when the countdown gets serious anyway.
    rl.showStageApps = not show.timecard or nil
    rl.uiColors = { theme = M.THEME }
    rl.stageData = {
      stageHeader = header,
      label = ssLabel, currentSSTime = 0, isActive = false, isComplete = false, unit = units,
      completion = { distM = 0, distPct = 0, totalDistM = totalM },
      splits = { { pathnodeId = 1, pathnodeType = 'finish', splitLabel = M.lengthText(totalM, units), distPct = 1 } },
    }
    ours.doneM, ours.totalM = 0, totalM
    -- (with the stage apps, not before them: on its own it floats with no progress bar to sit against)
    show.km = not show.timecard or nil
  elseif s == 'running' or s == 'toStop' then
    local done = math.max(0, math.min(totalM, (run.along or run.startM or 0) - (run.startM or 0)))
    if s == 'toStop' then done = totalM end
    ours.doneM, ours.totalM = done, totalM
    rl.showStageApps = true
    rl.uiColors = { theme = M.THEME }
    rl.stageData = {
      stageHeader = header,
      label = ssLabel,
      -- (past the finish the stage clock stops at the time that counts, penalties in: the finish strip beside it
      --  showed 6:14.5 against its 6:04.5 (1.6.2))
      currentSSTime = s == 'running' and (run.clock or 0) or (run.finalTime or run.stageTime or run.clock or 0),
      isActive = s == 'running', isComplete = s == 'toStop', unit = units,
      completion = { distM = done, distPct = totalM > 0 and done / totalM or 0, totalDistM = totalM },
      splits = { { pathnodeId = 1, pathnodeType = 'finish', splitLabel = M.lengthText(totalM, units), distPct = 1,
                   time = s == 'toStop' and (run.finalTime or run.stageTime) or nil } },
    }
    rl.scheduleData = { label = stock, ssLabel = ssLabel, totalSSCount = run.ssCount }
    if s == 'running' then
      rl.activeState = 'stageActive'
      ours.offM, ours.backBearing = run.off, run.backBearing
      show.offRoute = run.offRoute or nil
      show.km = not run.offRoute or nil
      show.go = (run.clock or 0) < M.GO_SHOW_S or nil
    else
      ours.control = 'stop'
      rl.activeState = 'vehicleProximity'
      rl.scheduleData.eventType = 'ss_stop'
      local d = run.toControlM or 0
      rl.vehicleProximity = { distance = d, distanceToPlane = d, isNear = d <= c.stopRadiusM,
        isStopped = speed < c.stoppedMs, isFrozen = false, isStartLine = false, isOverLineAllowed = false,
        usingGroundMarkerDistance = false }
      show.finish = M.finishPhase(run)    -- (kept, tucked, all the way to the stop)
    end
  elseif s == 'finished' then
    local early = (run.sinceFinish or 0) < M.FINISH_CARD_S
    show.finish = early and M.finishPhase(run) or nil
    if run.resultsOpen and not early then
      show.results = true
      local nx = run.nextStage
      ours.results = { finish = ours.finish,
        next = nx and { id = nx.id, ss = nx.ss, ssLabel = M.ssText(nx.ssLabel, nx.ss), name = nx.name,
          lengthM = nx.lengthM } or nil }
    end
  end
  -- (1.7.0) a pass of a full rally: rallyRun.lua's card data (run.rally: mode, the stage and overall places, the
  -- crews round you; ask = the Recover? question in Realistic mode, up while it waits on an answer)
  if run.rally then
    ours.rally = run.rally
    if run.rally.ask and not ctx.uiHidden then show.recoverAsk = true end
  end
  M.askOn(ours, ctx)
  -- the jump-start card, a few seconds from the moment
  if run.jumpStart and run.jumpStartAt and now - run.jumpStartAt < M.JUMP_CARD_S and (s == 'waitStart' or s == 'running') then
    show.jump = true
  end

  -- where the car is: a row of whichever panel is up, or the thin sliver beside the stage time once the stock
  -- stage apps are on (there is no panel of ours then)
  ours.where = M.whereOf(ctx)
  if ours.where then
    show.where = (show.next and 'next') or (show.timecard and 'timecard')
      or ((s == 'running' or s == 'toStop' or s == 'waitStart') and 'sliver') or nil
  end

  if s == 'finished' or s == 'failed' then M.approachLine(ours, ctx) end
  -- the controls for now (#27)
  ours.hints = M.hintsFor(s, { rally = run.inRally })
  show.hints = ours.hints and not ctx.preview and true or nil

  -- a menu is up: ours draws nothing (the stock apps are the game's own business)
  if ctx.uiHidden then ours.show = {} end
  if ctx.noRallyLoop then return nil, ours end
  if rl.activeState == 'inactive' then
    return { activeState = 'inactive', showStageApps = false }, ours
  end
  return rl, ours
end

-- What each stream shows now, as two short strings (rallyLoop, earthRally): main.lua sends a stream again only when
-- its string changes (1.6.1: each message re-draws the apps, and almost nothing on them changes 30 times a second).
-- Every value build gives the screen, at the precision it is drawn at: the stock stage time in tenths (rounded as
-- the stock app rounds), counts and clocks in whole seconds, km done to 0.1, distances to the metre, the way-back
-- arrow to 2 degrees, and every card's on or off. Built from the run's own numbers: no tables. BeamNG.Earth's
-- place, banner and loading are left to main.lua's once-a-second floor.
-- k: now (the rally clock, s), uiHidden, units, stopped (the car stopped, sampled), canSkip (sampled), stopRadiusM.
local function b(v) return v and '1' or '0' end
local function i(v) return tostring(math.floor((tonumber(v) or 0) + 0.5)) end
-- (a distance to a control as the stock proximity readout draws it: to the metre, but within NEAR_M of the control
-- to `fine` (0.01 at the start line, 0.1 at the stop: VehicleProximity.vue's toFixed), its sign kept -- 'go back')
M.NEAR_M = 5
local function near(v, fine)
  v = tonumber(v) or 0
  if math.abs(v) >= M.NEAR_M then return i(v) end
  return tostring(math.floor(v / fine + 0.5)) .. 'f'
end
local streamKeys
function M.streamKeys(run, k)
  local kr, ko = streamKeys(run, k)
  if run and (run.state == 'finished' or run.state == 'failed') then
    ko = ko .. '|' .. M.approachKey(not k.uiHidden and k.approach or nil, k.units)
  end
  return kr, ko
end
streamKeys = function(run, k)
  if not run then return 'none', 'none' end
  local s = run.state
  local now = k.now or 0
  local sec = math.floor(now + 0.5)      -- (the clocks round to the nearest second: clockText)
  local common = s .. '|' .. b(k.uiHidden) .. '|' .. tostring(k.units) .. '|' .. b(run.jumpStart and run.jumpStartAt
    and now - run.jumpStartAt < M.JUMP_CARD_S) .. '|' .. i(run.atcTime) .. '|' .. i(run.startAt) .. '|' .. b(run.missedAtc)
    .. '|' .. tostring(run.finalTime) .. '|' .. tostring(run.rallyKey) .. '|'
  if s == 'waitStart' then
    local left = (run.startAt or now) - now
    local n = math.max(0, math.ceil(left - 1e-6))
    local tail = n .. '|' .. b(left > M.TIMECARD_UNTIL_S) .. '|' .. b(k.canSkip) .. '|' .. sec
    return common .. tail, common .. tail
  elseif s == 'running' then
    local tenth = math.floor((run.clock or 0) * 10 + 0.5)
    local rl = common .. tenth .. '|' .. sec
    local ours = common .. b(run.offRoute) .. '|' .. b((run.clock or 0) < M.GO_SHOW_S) .. '|' .. sec .. '|'
    if run.offRoute then
      ours = ours .. i(run.off) .. '|' .. tostring(math.floor((tonumber(run.backBearing) or 0) / 2 + 0.5))
    else
      local step = k.units == 'mi' and M.MILE_M / 10 or 100
      ours = ours .. tostring(math.floor(math.max(0, (run.along or 0) - (run.startM or 0)) / step + 0.5))   -- (toFixed(1))
    end
    return rl, ours
  elseif s == 'toStop' then
    local tail = near(run.toControlM, 0.1) .. '|' .. b((run.toControlM or 0) <= (k.stopRadiusM or 25)) .. '|' .. b(k.stopped)
      .. '|' .. tostring(M.finishPhase(run))
      .. '|' .. tostring(run.finalTime or run.stageTime) .. '|' .. sec
    return common .. tail, common .. tostring(M.finishPhase(run)) .. '|' .. sec
  elseif s == 'toStart' then
    local diff = run.startAt and math.max(0, math.ceil(run.startAt - now - 1e-6)) or -1
    local tail = near(run.toControlM, 0.01) .. '|' .. b(k.stopped) .. '|' .. b(run.zone) .. b(run.zone and run.zone.held)
      .. '|' .. diff .. '|' .. sec
    return common .. tail, common .. sec
  elseif s == 'finished' or s == 'failed' then
    local tail = b((run.sinceFinish or 0) < M.FINISH_CARD_S) .. '|' .. tostring(M.finishPhase(run)) .. '|'
      .. b(run.finalTime) .. '|' .. b(run.resultsOpen)
      .. '|' .. b(run.nextStage) .. '|' .. tostring(run.error)
    return common .. tail, common .. tail
  end
  -- (travel, anchor, build, place, toAtc: the next control's panel, the distance to it and the rally clock)
  local tail = i(run.toControlM) .. '|' .. sec
  return common .. tail, common .. tail
end

return M
