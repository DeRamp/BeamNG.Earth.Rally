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
M.FINISH_CARD_S = 4           -- the flying-finish time shown big this long
M.JUMP_CARD_S = 3             -- the jump-start card
M.GO_SHOW_S = 1.5             -- "GO" after the start
M.BIG_COUNT_FROM = 5          -- our big numeral for the last seconds of the countdown (the stock squares light from 5)
M.TIMECARD_UNTIL_S = 10       -- the checked-in / start time line kept on the line until this close to the start
M.MILE_M = 1609.344

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
-- Returns rallyLoop, earthRally.
function M.build(run, ctx)
  ctx = ctx or {}
  local c = ctx.c or {}
  c.stoppedMs, c.startZoneBeforeM, c.stopRadiusM = c.stoppedMs or 1.0, c.startZoneBeforeM or 12, c.stopRadiusM or 25
  c.jumpStartS, c.resetS, c.missedAtcS = c.jumpStartS or 10, c.resetS or 10, c.missedAtcS or 60
  local units = ctx.units == 'mi' and 'mi' or 'km'
  local ours = { v = 1, state = run and run.state or 'idle', units = units, preview = ctx.preview or nil, show = {} }
  if not run then return (not ctx.noRallyLoop) and INACTIVE or nil, ours end

  local s = run.state
  local now = ctx.now or 0
  local speed = ctx.speed or 0
  local show = ours.show
  local stage = run.stage or {}
  local totalM = (run.finishM and run.startM) and (run.finishM - run.startM) or stage.lengthM or 0
  ours.clock, ours.clockText = now, M.clockText(now)
  ours.stage = { ss = run.ss, ssCount = run.ssCount, name = stage.name, rally = run.event and run.event.name,
    lengthM = totalM }
  ours.atcTime, ours.startAt, ours.missedAtc = run.atcTime, run.startAt, run.missedAtc == true
  ours.toControlM = run.toControlM
  ours.finish = finishInfo(run, c)
  if s == 'failed' then ours.error = run.error end

  local ssLabel = run.ss and tostring(run.ss) or ''
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
    rl.scheduleData = { eventType = 'ss_start', label = 'SS' .. ssLabel, ssLabel = ssLabel, totalSSCount = run.ssCount,
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
    rl.scheduleData = { eventType = 'ss_start', label = 'SS' .. ssLabel, ssLabel = ssLabel, totalSSCount = run.ssCount,
      timeDiff = M.diffText(left) }
    -- Staged and ready: the stage clock and the progress meter come up reading zero rather than at GO (the user,
    -- 2026-11-13). uiColors must go with them or the stock apps hide themselves.
    -- Not while our timecard is up: it sits at 0, 0 and so does the stock stage clock (288 wide), so bringing them
    -- up a minute early would stack the two in that corner -- the fault reported as items 1 and 4. They come up as
    -- the timecard goes, TIMECARD_UNTIL_S before the start, which is when the countdown gets serious anyway.
    rl.showStageApps = not show.timecard or nil
    rl.uiColors = { theme = M.THEME }
    rl.stageData = {
      stageHeader = string.format('SS%s · %s', ssLabel, string.upper(stage.name or '')),
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
      stageHeader = string.format('SS%s · %s', ssLabel, string.upper(stage.name or '')),
      label = ssLabel, currentSSTime = s == 'running' and (run.clock or 0) or (run.stageTime or run.clock or 0),
      isActive = s == 'running', isComplete = s == 'toStop', unit = units,
      completion = { distM = done, distPct = totalM > 0 and done / totalM or 0, totalDistM = totalM },
      splits = { { pathnodeId = 1, pathnodeType = 'finish', splitLabel = M.lengthText(totalM, units), distPct = 1,
                   time = s == 'toStop' and run.stageTime or nil } },
    }
    rl.scheduleData = { label = 'SS' .. ssLabel, ssLabel = ssLabel, totalSSCount = run.ssCount }
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
      show.finish = (run.sinceFinish or 0) < M.FINISH_CARD_S or nil
    end
  elseif s == 'finished' then
    local early = (run.sinceFinish or 0) < M.FINISH_CARD_S
    show.finish = (early and run.finalTime) and true or nil
    if run.resultsOpen and not early then
      show.results = true
      local nx = run.nextStage
      ours.results = { finish = ours.finish,
        next = nx and { id = nx.id, ss = nx.ss, name = nx.name, lengthM = nx.lengthM } or nil }
    end
  end
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

  -- a menu is up: ours draws nothing (the stock apps are the game's own business)
  if ctx.uiHidden then ours.show = {} end
  if ctx.noRallyLoop then return nil, ours end
  if rl.activeState == 'inactive' then
    return { activeState = 'inactive', showStageApps = false }, ours
  end
  return rl, ours
end

return M
