-- cardInput (2026-11-19): the pad and the keys on the HUD's cards are taken in Lua while a card is up (a HUD app gets
-- no UI nav in 0.40.6), the pick follows the d-pad / stick, A presses it, B is the card's back, and the game's own
-- actions on those buttons are filtered until the card is gone and its buttons are up.
local T = dofile(TESTS .. '/testlib.lua')
local logs = {}
function log(_, _, line) logs[#logs + 1] = line end

local ci = require('earthRally/cardInput')
local pushed, filtered, acted, changed = 0, nil, {}, 0
ci.sys = {
  push = function(name) pushed = pushed + 1 return name == 'EarthRallyCard' end,
  pop = function() pushed = pushed - 1 end,
  filter = function(group, list, on) filtered = on and list or nil return true end,
}
ci.act = function(what) acted[#acted + 1] = what end
ci.changed = function() changed = changed + 1 end
local function has(list, x) for _, v in ipairs(list or {}) do if v == x then return true end end return false end
local function lastLog() return logs[#logs] or '' end

local loadFrame = { show = { loadAsk = true }, rally = { loadAsk = { ss = 1, name = 'Canal Road' } } }
local CTX = { menuOpen = false, uiHidden = false, resPaused = false, askPaused = true }

-- which card a frame shows, as the card itself decides
T.check(ci.cardOf(loadFrame) == 'load', 'the load question')
T.check(select(1, ci.cardOf({ show = { recoverAsk = true, loadAsk = true },
  rally = { ask = {}, loadAsk = {} } })) == 'ask', 'Recover? over a load question')
local up, order = ci.cardOf({ show = { results = true }, results = { finish = {}, next = { name = 'x' } } })
T.check(up == 'res' and table.concat(order, ' ') == 'next retry menu close', 'a stage\'s finish card with a next stage')
up, order = ci.cardOf({ show = { results = true }, results = { finish = {} }, rally = { card = { canRestart = true } } })
T.check(table.concat(order, ' ') == 'continue restart close', 'a rally\'s finish card, Casual')
T.check(ci.cardOf({ preview = true, show = { loadAsk = true }, rally = { loadAsk = {} } }) == nil, 'not in the HUD preview')
T.check(ci.cardOf({ show = {} }) == nil, 'no card')

-- nothing taken with no card; a press does nothing
ci.update(0.1, CTX)
T.check(not ci.active() and pushed == 0 and filtered == nil, 'no card: the pad is the game\'s')
T.check(ci.press('ok', 'xinput0') == false and #acted == 0, 'no card: A does nothing here')

-- "Load the stage?" up (the game paused under it): the map pushed, the game's buttons filtered, the first picked
local info = ci.frame(loadFrame)
T.check(info and info.pick == 'load', 'the card up: Load picked first (sent in the stream)')
ci.update(0.1, CTX)
T.check(ci.active() and pushed == 1 and has(filtered, 'menu_item_select') and has(filtered, 'shiftUp')
  and not has(filtered, 'toggleMenues') and has(filtered, 'earthRally_rallyRecover') and has(filtered, 'reset_physics'),
  'the card up: our map pushed, the game\'s A / B / d-pad / menu / rally recovery filtered')
ci.update(0.1, CTX)
T.check(pushed == 1, 'pushed once, not every frame')
-- the d-pad moves the pick (and the stream is sent again with it); it stops at the ends
T.check(ci.press('next', 'xinput0') and ci.pick() == 'notYet' and changed == 1, 'd-pad right: Not yet picked')
ci.release('next')
ci.press('next', 'xinput0') ci.release('next')
T.check(ci.pick() == 'notYet', 'd-pad right again: stays on the last button')
T.check(ci.streamInfo().pad == true, 'a pad press: the ring drawn')
T.check(lastLog():find('next (xinput0) on load: pick notYet', 1, true) ~= nil, 'each input logged: ' .. lastLog())
ci.press('prev', 'keyboard0') ci.release('prev')
T.check(ci.pick() == 'load', 'the left arrow: back to Load')
-- the stick: once per push, again only after it comes back
ci.stick('x', 0.8, 'xinput0')
ci.stick('x', 0.9, 'xinput0')
T.check(ci.pick() == 'notYet', 'the stick right: one move per push')
ci.stick('x', 0.1, 'xinput0')
ci.stick('y', 0.8, 'xinput0')
T.check(ci.pick() == 'load', 'the stick up: the button before')
ci.stick('y', 0, 'xinput0')
-- A presses the pick, once
T.check(ci.press('ok', 'xinput0') and acted[1] == 'load', 'A: Load pressed')
T.check(lastLog():find('ok (xinput0) on load: pressed load', 1, true) ~= nil, 'A logged: ' .. lastLog())
T.check(ci.press('ok', 'ui') == false and #acted == 1, 'the same press arriving from the UI too: acted on once')
ci.update(0.3, CTX)
T.check(ci.press('ok', 'xinput0') == false and #acted == 1, 'A again before the card shows what it did: nothing')
T.check(ci.click('notYet') == false and #acted == 1, '... nor a click on the same card')
-- the card goes; the buttons stay ours until A is up
ci.frame({ show = {} })
ci.update(0.1, CTX)
T.check(not ci.active() and pushed == 1 and filtered ~= nil, 'the card gone with A still down: the game\'s A held back')
ci.release('ok')
ci.update(0.1, CTX)
T.check(pushed == 0 and filtered == nil, 'A up: the pad and the keys given back')
-- (a button never released: given back after RELEASE_WAIT_S anyway)
ci.frame(loadFrame) ci.update(0.1, CTX)
ci.press('back', 'xinput0')
T.check(acted[#acted] == 'notYet', 'B on the load question: Not yet')
ci.frame({ show = {} }) ci.update(0.1, CTX)
T.check(pushed == 1, '(B still down)')
ci.update(ci.RELEASE_WAIT_S + 0.1, CTX)
T.check(pushed == 0 and filtered == nil, 'a button never seen up: given back after a while')

-- a question whose pause the game refused (BeamNG.Earth holding it): the car's buttons stay the car's
ci.frame(loadFrame) ci.update(0.1, { askPaused = false })
T.check(not ci.active() and pushed == 0, "a question not paused: mouse only, the pad stays the car's")
ci.frame({ show = {} }) ci.update(0.1, CTX)
-- B on each card
ci.frame({ show = { recoverAsk = true }, rally = { ask = {} } }) ci.update(1.5, CTX)
ci.press('back', 'xinput0')
T.check(acted[#acted] == 'keep', 'B on Recover?: Keep going')
ci.release('back')
-- the finish card: only while its pause is held (a flying finish rolling on keeps the car's buttons)
local resFrame = { show = { results = true }, results = { finish = {} }, rally = { card = {} } }
ci.frame(resFrame)
ci.update(1.5, CTX)
T.check(not ci.active(), 'the finish card without its pause: the car\'s buttons stay the car\'s')
ci.update(0.1, { resPaused = true })
T.check(ci.active() and ci.pick() == 'continue', 'the finish card, paused: taken, Continue picked')
ci.press('back', 'xinput0')
T.check(acted[#acted] == 'close', 'B on the finish card: Close')
ci.release('back')
-- a menu over the HUD (the pause menu, our page): given back while it is up
ci.update(1.5, { resPaused = true, uiHidden = true })
T.check(not ci.active() and pushed == 0, 'the pause menu over the card: the pad is the menu\'s')
ci.update(0.1, { resPaused = true })
T.check(ci.active() and pushed == 1, 'the menu closed: the card takes it again')
-- the buttons changed under the card (a rally's part arriving): the first one picked again
ci.press('next', 'xinput0') ci.release('next')
ci.frame({ show = { results = true }, results = { finish = {} }, rally = { card = { canRestart = true } } })
T.check(ci.pick() == 'continue', 'new buttons: the first picked again')
-- a click acts (and is logged)
ci.update(1.5, { resPaused = true })
T.check(ci.click('restart') and acted[#acted] == 'restart', 'a click on the card acts')
ci.reset()
T.check(pushed == 0 and filtered == nil and not ci.active(), 'reset: everything given back')

T.done('test_card_input')
