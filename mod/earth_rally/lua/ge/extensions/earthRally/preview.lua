-- earthRally/preview: the HUD preview (a developer command: earthRally_main.previewHud()): sample moments of a run
-- played through the real HUD without driving. Each moment is a made-up run table put through hudFrame.build, the
-- same function a real run's frames come from, so the preview shows what a run would. Pure: frameAt(t).
local hudFrame = require('earthRally/hudFrame')

local M = {}

local CLOCK0 = 10 * 3600 + 41 * 60 + 52      -- 10:41:52 on the rally clock
local EVENT = { name = 'Sample Rally', stages = { {}, {}, {}, {}, {}, {}, {}, {}, {} } }
local STAGE = { name = 'Kuhnle', lengthM = 8400 }
local NEXT = { id = 'ss3', ss = 3, name = 'Deckerville', lengthM = 11800 }

local function base(state, extra)
  local r = { state = state, event = EVENT, stage = STAGE, ss = 2, ssCount = 9, startM = 30, finishM = 8430,
    checks = {}, nextStage = NEXT }
  for k, v in pairs(extra or {}) do r[k] = v end
  return r
end

-- The moments: { seconds, label, function(t within it) -> run, rally clock, speed, canSkip }
local START_AT = CLOCK0 + 98
M.MOMENTS = {
  { 3, 'getting ready', function() return base('build'), CLOCK0, 0 end },
  { 5, 'driving to the ATC', function(t) return base('toAtc', { toControlM = 1240 - t * 25 }), CLOCK0 + t, 22 end },
  { 5, 'checked in, moving up', function(t)
      return base('toStart', { atcTime = CLOCK0 + 38, startAt = START_AT, toControlM = 180 - t * 30 }), CLOCK0 + 40 + t, 8 end },
  { 3, 'staged on the line', function(t)
      return base('toStart', { atcTime = CLOCK0 + 38, startAt = START_AT, toControlM = 1, zone = { held = true } }),
        CLOCK0 + 50 + t, 0 end },
  { 4, 'waiting (the skip possible)', function(t)
      return base('waitStart', { atcTime = CLOCK0 + 38, startAt = START_AT }), START_AT - 40 + t, 0, true end },
  { 8, 'the countdown', function(t)
      return base('waitStart', { atcTime = CLOCK0 + 38, startAt = START_AT }), START_AT - 7.99 + t, 0 end },
  { 3, 'GO', function(t) return base('running', { clock = t, along = 30 + t * 5 }), START_AT + t, 10 end },
  { 3, 'jump start', function(t)
      return base('waitStart', { startAt = START_AT, jumpStart = true, jumpStartAt = START_AT - 3 }), START_AT - 3 + t * 0.5, 2 end },
  { 5, 'on the stage', function(t)
      return base('running', { clock = 161.7 + t, along = 3130 + t * 30 }), START_AT + 161.7 + t, 30 end },
  { 5, 'off route', function(t)
      return base('running', { clock = 200 + t, along = 4000, off = 85 + t * 4, offRoute = true, backBearing = -130 }),
        START_AT + 200 + t, 8 end },
  { 5, 'flying finish, a new best', function(t)
      return base('toStop', { clock = 368.9, stageTime = 368.9, finalTime = 368.9, penalty = 0, bestBefore = 372.4,
        sinceFinish = t, toControlM = 600 - t * 30 }), START_AT + 369 + t, 30 end },
  { 5, 'flying finish, slower', function(t)
      return base('toStop', { clock = 364.5, stageTime = 364.5, finalTime = 374.5, penalty = 10, jumpStart = true,
        bestBefore = 372.4, sinceFinish = t, toControlM = 400 - t * 30 }), START_AT + 369 + t, 30 end },
  { 4, 'on to the stop control', function(t)
      return base('toStop', { stageTime = 364.5, finalTime = 374.5, penalty = 10, sinceFinish = 10, toControlM = 220 - t * 50 }),
        START_AT + 380 + t, 15 end },
  { 8, 'stage done', function(t)
      return base('finished', { stageTime = 361.4, finalTime = 391.4, penalty = 30, jumpStart = true, resets = 2,
        bestBefore = 372.4, sinceFinish = 10, resultsOpen = true }), START_AT + 400 + t, 0 end },
}

function M.duration()
  local d = 0
  for _, m in ipairs(M.MOMENTS) do d = d + m[1] end
  return d
end

-- The streams at t seconds into the preview: rallyLoop, earthRally, the moment's label; nil once it is over.
function M.frameAt(t, units)
  local at = 0
  for _, m in ipairs(M.MOMENTS) do
    if t < at + m[1] then
      local run, now, speed, canSkip = m[3](t - at)
      local rl, ours = hudFrame.build(run, { now = now, speed = speed, canSkip = canSkip, units = units, preview = true })
      ours.previewLabel = m[2]
      return rl, ours, m[2]
    end
    at = at + m[1]
  end
  return nil
end

return M
