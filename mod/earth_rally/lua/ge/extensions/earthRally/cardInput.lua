-- earthRally/cardInput: the pad and the keys for the HUD's cards ("Load the stage?", Recover?, the stage's finish
-- card: app.earthRallyResults.vue), taken in Lua (the owner, 2026-11-19: "controller support doesn't work on the
-- pop-up menus").
--
-- Why not the game's UI nav (as revision 4 tried): in 0.40.6 every HUD app is drawn inside the apps overlay's host
-- with prevent-uinav (ui-vue modules/apps/views/UiAppsOverlay.vue -> AppHost.vue: bng-uinav-suppressed and
-- bng-no-child-nav on the host). The game's nav tracker (services/uiNavTracker.js isLiveUiElement) counts nothing
-- inside such a host as a live owner of ok / back / the d-pad, so it never turns their MenuIndependent action maps on
-- (core/input/bindings.lua setMenuActionsEnabled) and A never sends a UINavigation event at all: the card's capture
-- listener on the window logged no ui_nav while the card was up and its popup state reported (the owner's log,
-- 2026-11-19, t = 262-267). A HUD app cannot take the pad through the UI; a Lua action map can.
--
-- So, while a card is up: our action map (core/input/actions/earthRally.json, actionMap "EarthRallyCard", bound in
-- settings/inputmaps: A / Enter = ok, B = back, the d-pad / arrows / left stick = move) is pushed first in the
-- stack, and the game's own actions on those buttons (its UI nav, the radial menu, the camera's look
-- back, the car's shift up and parking brake, its interaction triggers, its reset and recovery) are filtered out
-- (core/input/actionFilter.lua) until the card is gone and every button pressed on it is up again. The pick is ours
-- and goes to the card in the stream (ours.card = { pick, pad }); the card's mouse clicks come through here too
-- (M.click), so a click and a key on one press act once. Works with the game paused: input actions run regardless.
local M = {}
local logTag = 'earthRally'

M.MAP = 'EarthRallyCard'           -- (the action map: <name>ActionMap)
M.FILTER = 'earthRallyCard'        -- (our group in the game's action filter)
-- the game's actions on the card's buttons (its settings/inputmaps xidevice.json and keyboard.json), off while it is up
M.BLOCKED = {
  'menu_item_select', 'menu_item_back', 'menu_item_up', 'menu_item_down', 'menu_item_left', 'menu_item_right',
  'menu_item_focus_lr', 'menu_item_focus_ud', 'accept', 'decline', 'bigMapControllerSelect',
  'toggleRadialMenuMulti', 'look_back', 'nodegrabberStrength',
  'shiftUp', 'parkingbrake', 'triggerAction0', 'reset_physics', 'recover_vehicle', 'earthRally_rallyRecover',
  'photomodeDecreaseFov', 'photomodeIncreaseFov', 'photomodeRollCameraLeft', 'photomodeRollCameraRight',
}
M.RELEASE_WAIT_S = 1.5   -- the card gone: its buttons kept from the game until they are up, at most this long
M.SAME_PRESS_S = 0.25    -- the same press arriving twice (the UI and the map, a click and a key): acted on once
M.ACTED_HOLD_S = 1.0     -- after a press acts, the same card takes no other until the HUD shows what it did
M.STICK_ON, M.STICK_OFF = 0.5, 0.35

-- (main.lua) acts on a card's button: earthRally_main.uiResults
M.act = function(what) end
-- (main.lua) the pick moved: the last frame sent again with it
M.changed = function() end
-- the game, swappable by the tests
M.sys = {
  push = function(name)
    local f = rawget(_G, 'pushActionMapHighestPriority') or rawget(_G, 'pushActionMap')
    if not f then return false end
    return f(name) ~= false
  end,
  pop = function(name)
    local f = rawget(_G, 'popActionMap')
    if f then f(name) end
  end,
  filter = function(group, list, on)
    local af = rawget(_G, 'core_input_actionFilter')
    if not (af and af.setGroup and af.addAction) then return false end
    af.setGroup(group, list)
    af.addAction(0, group, on == true)
    return true
  end,
}

local now = 0
local card = nil       -- the card in the last frame sent: { up = 'ask' | 'load' | 'res', order = [...], key }
local pick = nil
local pad = false      -- the last press on the card from a pad (its ring drawn)
local active = false   -- the card is taking the buttons
local taken = false    -- our map pushed and the game's actions filtered
local takenAt = nil    -- (the card gone: when; the buttons given back once released, or after RELEASE_WAIT_S)
local held = {}        -- buttons down through our map
local last = nil       -- the last press acted on: { kind, src, t }
local acted = nil      -- { key, t }: the card a press acted on
local stickHeld = { x = false, y = false }

-- Pure: which card a frame of our stream shows, and its buttons in their order on the card (as the card's own
-- `up` and `order`: app.earthRallyResults.vue). nil with none, or in the HUD preview.
function M.cardOf(ours)
  if type(ours) ~= 'table' or ours.preview then return nil end
  local show = type(ours.show) == 'table' and ours.show or {}
  local rally = type(ours.rally) == 'table' and ours.rally or nil
  if show.recoverAsk and rally and rally.ask then return 'ask', { 'recover', 'keep' } end
  if show.loadAsk and rally and rally.loadAsk then return 'load', { 'load', 'notYet' } end
  local res = ours.results
  if show.results and type(res) == 'table' and res.finish then
    local rc = rally and rally.card
    if rc then return 'res', rc.canRestart and { 'continue', 'restart', 'close' } or { 'continue', 'close' } end
    return 'res', res.next and { 'next', 'retry', 'menu', 'close' } or { 'retry', 'menu', 'close' }
  end
  return nil
end
M.BACK = { ask = 'keep', load = 'notYet', res = 'close' }

local function say(line) log('I', logTag, 'card input: ' .. line) end

-- A frame of our stream about to be sent (main.lua): the card it shows. Returns the card's part of the stream,
-- { pick, pad }, or nil with no card.
function M.frame(ours)
  local up, order = M.cardOf(ours)
  if not up then
    -- (gone: it has shown what the last press did)
    card, pick, acted = nil, nil, nil
    return nil
  end
  local key = up .. ':' .. table.concat(order, ',')
  if not card or card.key ~= key then
    -- (a new card, or its buttons changed under it: a rally's arrive after the stage's -- the first one picked)
    card = { up = up, order = order, key = key }
    pick = order[1]
  end
  return M.streamInfo()
end
function M.streamInfo() if card then return { pick = pick, pad = pad or nil } end return nil end
function M.pick() return pick end
function M.card() return card end
function M.active() return active end
function M.taken() return taken end

local function take(on)
  if on == taken then return end
  taken = on
  if on then
    local okP, pushed = pcall(M.sys.push, M.MAP)
    local okF, filtered = pcall(M.sys.filter, M.FILTER, M.BLOCKED, true)
    say(string.format('the pad and the keys taken for the card (%s)%s%s', card and card.up or '?',
      (okP and pushed) and '' or ', NO action map to push', (okF and filtered) and '' or ', NO action filter'))
  else
    pcall(M.sys.pop, M.MAP)
    pcall(M.sys.filter, M.FILTER, M.BLOCKED, false)
    say('the pad and the keys given back')
  end
end

-- Every frame (main.onUpdate), paused or not. ctx: { menuOpen (our page), uiHidden (a menu over the HUD: Escape and
-- Start stay the game's, so a card can never shut the player out of the pause menu; opening it gives the buttons
-- back), resPaused / askPaused (the finish card's / a question's pause held: without it the car can still be live,
-- and its buttons stay the car's -- the card then takes the mouse only) }
function M.update(dt, ctx)
  now = now + (dt or 0)
  ctx = ctx or {}
  local want = card ~= nil and not ctx.menuOpen and not ctx.uiHidden and (card.up == 'res' and ctx.resPaused == true or card.up ~= 'res' and ctx.askPaused == true)
  if want ~= active then
    active = want
    if want then
      take(true)
      takenAt = nil
    elseif taken then
      takenAt = now
    end
    if not want then pad, stickHeld.x, stickHeld.y = false, false, false end
  end
  if not active and taken then
    local anyHeld = next(held) ~= nil
    if not anyHeld or now - (takenAt or now) >= M.RELEASE_WAIT_S then
      held = {}
      take(false)
    end
  end
end

local function isPad(src) return type(src) == 'string' and src:find('xinput', 1, true) ~= nil end

-- (a press the card should not act on now: a second arrival of one press, or the card has not yet shown what the
-- last one did)
local function ignored(kind, src)
  if last and last.kind == kind and last.src ~= src and now - last.t < M.SAME_PRESS_S then return 'the same press twice' end
  if (kind == 'ok' or kind == 'back') and acted and card and acted.key == card.key and now - acted.t < M.ACTED_HOLD_S then
    return 'the card still on its last answer'
  end
  return nil
end

local function press(what, kind, src)
  acted = { key = card.key, t = now }
  last = { kind = kind, src = src, t = now }
  say(string.format('%s (%s) on %s: pressed %s', kind, tostring(src), card.up, what))
  local ok, err = pcall(M.act, what)
  if not ok then log('E', logTag, 'card input: ' .. tostring(err)) end
end

-- A button (our map's actions, or the card's own UI forwarding: src 'ui'): 'ok', 'back', 'prev', 'next'.
-- Returns true when the card acted on it.
function M.press(kind, src, axis)
  src = src or '?'
  -- (a button down through our map: kept from the game until it is up; not the stick, which has no release)
  if src ~= 'ui' and not axis then held[kind] = true end
  if not (active and card) then return false end
  local why = ignored(kind, src)
  if why then
    say(string.format('%s (%s) on %s: ignored, %s', kind, tostring(src), card.up, why))
    return false
  end
  if isPad(src) then pad = true end
  if kind == 'ok' then
    if not pick then pick = card.order[1] end
    press(pick, kind, src)
    return true
  elseif kind == 'back' then
    press(M.BACK[card.up] or 'close', kind, src)
    return true
  elseif kind == 'prev' or kind == 'next' then
    local i = 1
    for j, b in ipairs(card.order) do if b == pick then i = j end end
    i = math.max(1, math.min(#card.order, i + (kind == 'next' and 1 or -1)))
    pick = card.order[i]
    last = { kind = kind, src = src, t = now }
    say(string.format('%s (%s) on %s: pick %s', kind, tostring(src), card.up, pick))
    pcall(M.changed)
    return true
  end
  return false
end

function M.release(kind) held[kind] = nil end

-- The left stick (axis 'x' or 'y', up and right positive): one move per push past STICK_ON, the next once it is back
-- under STICK_OFF.
function M.stick(axis, v, src)
  v = tonumber(v) or 0
  if math.abs(v) < M.STICK_OFF then stickHeld[axis] = false return false end
  if stickHeld[axis] or math.abs(v) < M.STICK_ON then return false end
  stickHeld[axis] = true
  local kind
  if axis == 'x' then kind = v > 0 and 'next' or 'prev' else kind = v > 0 and 'prev' or 'next' end
  return M.press(kind, src or 'stick', true)
end

-- A mouse click on one of the card's buttons (the card's own @click): acted on unless the same card has just acted.
function M.click(what)
  if card and acted and acted.key == card.key and now - acted.t < M.ACTED_HOLD_S then
    say(string.format('click %s on %s: ignored, the card still on its last answer', tostring(what), card.up))
    return false
  end
  if card then
    acted = { key = card.key, t = now }
    say(string.format('click on %s: pressed %s', card.up, tostring(what)))
  end
  local ok, err = pcall(M.act, what)
  if not ok then log('E', logTag, 'card input: ' .. tostring(err)) end
  return true
end

-- Everything given back (the level going, the mod off or reloaded).
function M.reset()
  active, card, pick, pad, acted, last, held = false, nil, nil, false, nil, nil, {}
  stickHeld.x, stickHeld.y = false, false
  if taken then take(false) end
end

return M
