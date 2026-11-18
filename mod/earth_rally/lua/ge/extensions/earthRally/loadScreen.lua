-- earthRally/loadScreen: the menu page's loading screen (1.7.0, #49; docs/mockups-1.7.0/loading.html). Wherever the
-- menu used to close and the world loaded in view (Drive, Go to start, Recce, a rally's Start / Continue, a move to a
-- stop), the page stays up on this instead: what is loading, its steps, and last the world round the car, which must
-- reach the player's "World loaded before driving" share (settings.worldLoaded, 60% by default) before it lets go.
--
--   M.begin(spec)   spec = { kick, title, sub, tip, steps = { 'text', ... } (the world step is added last),
--                   probe = fn() -> step (1.. the step now; past the last = all done), bar (0..1 or nil), barText,
--                   failed (a reason: the screen ends at once), done = fn(ok, why) (called once, at the end),
--                   button = 'Continue' (wait for M.continue() once ready instead of ending by itself),
--                   noWorld = true (no world step: ends when the steps do; the world loading for a button
--                   pressed at the main menu, whose car is not where the stage is) }
--   M.update(dt)    every frame (main.onUpdate)
--   M.ui()          the page's data, nil with none (moving = true while the world's origin moves, #63)
--   M.continue()    the ready button pressed
--   M.cancel()      put away with nothing called
-- The probe is pcall'd: an error ends the screen with the error as the reason.
local M = {}

M.WORLD_WAIT_S = 90       -- the world share not reached this long after the rest is done: let go anyway
M.STEP_WAIT_S = 300       -- a step that never finishes: let go (the probe's own timeouts come first: the run's
                          -- world wait, 180 s, then BeamNG.Earth's origin move, up to runner.ANCHOR_PENDING_MAX_S)

local earth = require('earthRally/earthAdapter')
local settings = require('earthRally/settings')
local logTag = 'earthRally'

local cur = nil
-- (#63) The world's origin on its way to the stage (main.lua sets it: the run's anchor step, BeamNG.Earth rebasing):
-- the World bar shows "Moving the world..." then, not a stuck 0%.
M.moving = function() return false end

function M.need()
  local v = tonumber(settings.get('worldLoaded'))
  return v or 60
end

-- The world share now (0..100): BeamNG.Earth's counts, else ready() as all or nothing.
function M.world()
  local ok, w = pcall(earth.worldLoaded)
  if ok and type(w) == 'number' then return w end
  local okR, r = pcall(earth.ready)
  return (okR and r) and 100 or 0
end

function M.active() return cur end

function M.begin(spec)
  if cur then log('I', logTag, 'loading screen: ' .. tostring(cur.title) .. ' replaced') end
  cur = { spec = spec, title = spec.title, step = 1, t = 0, worldT = 0, world = 0 }
  log('I', logTag, 'loading screen: ' .. tostring(spec.title))
  return cur
end

local function finish(ok, why)
  local c = cur
  cur = nil
  if not c then return end
  log('I', logTag, string.format('loading screen: %s %s after %.1f s%s', tostring(c.title), ok and 'done' or 'ended',
    c.t, why and (' (' .. tostring(why) .. ')') or ''))
  if c.spec.done then
    local okD, err = pcall(c.spec.done, ok, why)
    if not okD then log('E', logTag, 'loading screen: ' .. tostring(err)) end
  end
end

function M.update(dt)
  local c = cur
  if not c then return end
  dt = dt or 0
  c.t = c.t + dt
  local n = #(c.spec.steps or {})
  local okP, step, bar, barText, failed = pcall(c.spec.probe or function() return n + 1 end)
  if not okP then finish(false, tostring(step)) return end
  if failed then finish(false, failed) return end
  if c.ready then return end
  c.step, c.bar, c.barText = tonumber(step) or 1, bar, barText
  c.world = c.spec.noWorld and 0 or M.world()
  if c.step <= n then
    if c.t > M.STEP_WAIT_S then
      log('W', logTag, 'loading screen: ' .. tostring(c.title) .. ' took too long, let go')
      finish(true, 'took too long')
    end
    return
  end
  if c.spec.noWorld then finish(true) return end
  c.worldT = c.worldT + dt
  local enough = c.world >= M.need()
  if not enough and c.worldT <= M.WORLD_WAIT_S then return end
  -- (BeamNG.Earth still holding the car -- its drop hold after a teleport: the page's pause comes off only after it,
  -- or the physics would run in the middle of its hold; menuPause.lua)
  local okH, held = pcall(earth.holding)
  if okH and held and c.worldT <= 2 * M.WORLD_WAIT_S then return end
  if not enough then log('W', logTag, string.format('loading screen: the world at %d%% after %d s, let go', c.world,
    M.WORLD_WAIT_S)) end
  if c.spec.button then
    c.ready = true
    return
  end
  finish(true)
end

function M.continue()
  if not (cur and cur.ready) then return false end
  finish(true)
  return true
end

function M.cancel() cur = nil end

-- The page closed under the screen: one waiting for its button ends at once if ready, else by itself once ready
-- (nobody is there to press it).
function M.pageClosed()
  if not cur then return end
  if cur.ready then M.continue() return end
  cur.spec.button = nil
end

function M.ui()
  local c = cur
  if not c then return nil end
  local need = M.need()
  local steps = {}
  local n = #(c.spec.steps or {})
  for i, s in ipairs(c.spec.steps or {}) do
    steps[i] = { text = s, state = (c.ready or i < c.step) and 'done' or (i == c.step and 'now' or 'wait') }
  end
  if not c.spec.noWorld then
    steps[n + 1] = { text = string.format('The world around you: at least %d%%', need), world = true,
      state = c.ready and 'done' or (c.step > n and 'now' or 'wait') }
  end
  return { kick = c.spec.kick, title = c.spec.title, sub = c.spec.sub, tip = c.spec.tip, kind = c.spec.kind,
    steps = steps, bar = c.bar, barText = c.barText, world = c.world, need = need,
    worldReady = c.ready or (c.step > n and c.world >= need) or nil, ready = c.ready or nil,
    button = c.spec.button, card = c.spec.card, thenView = c.spec.thenView, noWorld = c.spec.noWorld or nil,
    moving = (not c.ready and (function() local ok, m = pcall(M.moving) return ok and m == true end)()) or nil }
end

return M
