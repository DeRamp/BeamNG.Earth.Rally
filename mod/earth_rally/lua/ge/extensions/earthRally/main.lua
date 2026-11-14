-- earthRally_main: Earth Rally's frame loop and its ways in:
--   the menu      a full-screen page of its own (ui/ui-vue/mods/earthRally: Rallies, a rally, a stage, Settings) and
--                 an "Earth Rally" tab in the pause menu; Ctrl+Alt+K opens / closes the page (toggleMenu). The page
--                 asks this extension for its data (uiState, uiRally, uiStage) and sends the buttons here (uiAction,
--                 uiResults, uiSet).
--   the HUD       the game's rally apps and ours in the stage layout, fed every frame from runner.uiFrame (streams
--                 'rallyLoop' and 'earthRally'); previewHud() plays sample frames through it without driving
--   the developer panel   the 1.1.0 ImGui window with each run's checks: shown only with the setting on (or
--                 earthRally_main.toggle() in the console)
local im = ui_imgui
local earth = require('earthRally/earthAdapter')
local events = require('earthRally/events')
local recce = require('earthRally/recce')
local autoRecce = require('earthRally/autoRecce')
local runner = require('earthRally/runner')
local importer = require('earthRally/importer')
local settings = require('earthRally/settings')
local menu = require('earthRally/menu')
local preview = require('earthRally/preview')

local M = {}
local logTag = 'earthRally'
M.VERSION = '1.3.0-alpha'
M.ROUTE = 'earthRally'            -- the menu page's route (ui/ui-vue/mods/earthRally/index.js)
M.STREAM_HZ = 30                  -- the HUD's streams this often while something moves on it
M.STREAM_IDLE_HZ = 2              -- ... and this often once the run is over
M.FAR_FOR_RECCE_M = 300           -- Recce from further than this from the start: taken there first

local show = im.BoolPtr(false)
local selEvent, selStage = 1, 1
local message = nil
local facing = nil       -- after Go to start: turn the car along the stage once BeamNG.Earth has set it down
local scanIn = nil       -- seconds until the import folder is looked at (a file changed in it)
local menuOpen = false   -- the menu page is the screen now (onUiChangedState)
local openAt = nil       -- the page to show when the menu opens next: { view, eventId, stageId }
local lastImport = nil   -- the last import: { at, lines = { { text, ok }... } }
local autoRun = nil      -- the auto recce running, as the page names it: { eventId, stageId, stageName, ss }
local autoLines = {}     -- how the last auto recce of a stage ended, by eventId .. '|' .. stageId:
                         -- { eventId, stageId, ss, kind, text }. One per stage, so a rally can show several at once
                         -- (the mock-up's four rows, four endings); a stage's line goes when its auto recce works.
local selftest = nil     -- the self-test (earthRally/selftest.lua), loaded only when one is asked for
M.SELFTEST_REQUEST = '/earthRally/selftest/request.json'
-- A stage to be taken to as soon as the game is up (tools/playtest.py writes it, and it is used once): the testing
-- loop is install, start the game, drive the stage, and doing the first two by hand each time wastes the evening.
M.PLAYTEST_REQUEST = '/earthRally/playtest.json'
M.PLAYTEST_WAIT_S = 420         -- the world given this long to come up before giving up on it
M.PLAYTEST_SETTLE_S = 12        -- ... and this long settled before the stage is asked for, so BeamNG.Earth has
                                -- streamed the roads round the control before the run puts its boards down
local playtest = nil     -- { event, stage, what, t, levelAsked, ready }

-- The developer panel (the ImGui window): console toggle; the setting shows / hides it.
function M.toggle() show[0] = not show[0] end
function M.show() show[0] = true end
settings.onChange('main', function(key, v) if key == 'devPanel' then show[0] = v == true end end)

-- Go to a UI screen (route): ui_router.navigate (BeamNG 0.40), else the old ChangeState (as BeamNG.Earth's settings).
local function navigate(state)
  local r = rawget(_G, 'ui_router')
  if r and r.navigate and pcall(r.navigate, state) then return true end
  local gh = rawget(_G, 'guihooks')
  if gh and gh.trigger then gh.trigger('ChangeState', { state = state }) return true end
  return false
end
M.navigate = navigate

-- The menu page: opened at view ('rallies', 'rally', 'stage', 'settings'), closed back to driving.
function M.openMenu(view, eventId, stageId)
  if view then openAt = { view = view, eventId = eventId, stageId = stageId } end
  menuOpen = navigate(M.ROUTE)
  return menuOpen
end
function M.closeMenu()
  menuOpen = false
  return navigate('play')
end
-- Ctrl+Alt+K
function M.toggleMenu()
  if menuOpen then return M.closeMenu() end
  local r = runner.current()
  if r and r.resultsOpen and r.state == 'finished' then
    return M.openMenu('rally', r.event.id)
  end
  return M.openMenu()
end
-- The game's UI state. Our HUD is hidden while a menu is up: it is drawn over the pause menu otherwise, which is
-- in the way now that the rally block sits in the top left corner where the menu draws (the user, 2026-11-13).
-- BeamNG.Earth's own apps do the same (its credits.lua: `toState:sub(1, 4) == 'menu' or toState == 'loading'`).
function M.onUiChangedState(toState)
  if type(toState) ~= 'string' then return end
  menuOpen = toState == M.ROUTE
  -- Our own full-screen page counts too: it is not called 'menu...' but it is just as much in the way. So does
  -- BeamNG.Earth's world map, a route of its own ('beamngEarthMap', its credits.lua MAP_ROUTE).
  runner.uiHidden = toState:sub(1, 4) == 'menu' or toState == 'loading' or toState == M.ROUTE
    or toState == 'beamngEarthMap'
end

------------------------------------------------------------------------------------------ the developer panel

local GREY, GREEN, AMBER, RED = im.ImVec4(0.6, 0.6, 0.6, 1), im.ImVec4(0.4, 0.9, 0.4, 1), im.ImVec4(1, 0.75, 0.2, 1),
  im.ImVec4(1, 0.4, 0.4, 1)

local function km(m) return string.format('%.1f km', (m or 0) / 1000) end

local function checksText(c)
  if not c then return {} end
  local lines = {}
  local function add(label, v) lines[#lines + 1] = label .. ': ' .. tostring(v) end
  add('Stage line', c.line == 'matched' and 'the map line on the roads (no recce)' or (c.line or '-'))
  add('Rally engine', c.rallyEngine or '-')
  if c.atc then add('Time control', c.atc) end
  if c.stopControl then add('Stop control', c.stopControl) end
  add('Corners found / notes loaded', tostring(c.cornersFound or '-') .. ' / ' .. tostring(c.notesLoaded or '-'))
  add('Notes called', c.notesCalled)
  add('Origin moved to the stage centre', c.originMoved or '-')
  add('World shifts during the run', c.shifts .. (c.shifts > 0 and
    string.format(' (notes called after: %d)', c.notesCalledAfterShift) or ''))
  add('Heights kept (largest change, m)', c.heightKeptM and string.format('%.2f', c.heightKeptM) or '-')
  add('World not ready during the run (s)', string.format('%.1f', c.notReadyS or 0))
  add('Furthest off the line (m)', string.format('%.0f', c.maxOffM or 0))
  add('Shifts heard by', c.moveSource or '-')
  return lines
end

local function drawRun()
  local r = runner.current()
  if not r then return end
  im.Separator()
  local st = r.state
  if st == 'running' then
    im.TextColored(GREEN, string.format('%s   %s', r.stage.name, runner.formatTime(r.clock)))
    im.Text(string.format('%s of %s%s%s', km((r.along or 0) - r.startM), km(r.finishM - r.startM),
      r.offRoute and '   OFF ROUTE' or '', (r.resets or 0) > 0 and string.format('   resets: %d', r.resets) or ''))
  elseif st == 'toStop' then
    im.TextColored(GREEN, string.format('%s: %s   (flying finish)', r.stage.name, runner.formatTime(r.finalTime)))
    im.TextColored(AMBER, string.format('Stop at the stop control: %.0f m', r.toControlM or 0))
  elseif st == 'toAtc' then
    im.TextColored(AMBER, string.format('Drive to the time control (red clock board) and stop: %.0f m', r.toControlM or 0))
  elseif st == 'toStart' then
    im.TextColored(AMBER, string.format('Drive to the start line and stop on it: %.0f m', math.max(0, r.toControlM or 0)))
  elseif st == 'waitStart' then
    local left = (r.startAt or 0) - (runner.clock() or 0)
    im.TextColored(left <= 5 and GREEN or AMBER, string.format('Start at %s: %.0f s', runner.formatClock(r.startAt),
      math.max(0, math.ceil(left))))
  elseif st == 'finished' then
    im.TextColored(GREEN, string.format('%s: %s%s', r.stage.name, runner.formatTime(r.finalTime),
      (r.penalty or 0) > 0 and string.format('  (stage %s + %d s penalties)', runner.formatTime(r.stageTime), r.penalty) or ''))
    if r.best then im.Text('Best: ' .. runner.formatTime(r.best)) end
  elseif st == 'failed' then
    im.TextColored(RED, 'Stopped: ' .. tostring(r.error))
  else
    im.TextColored(AMBER, r.stage.name .. ': ' .. ({ travel = 'going to the start, the world loading',
      anchor = 'moving the world to the stage', build = 'building the stage', place = 'to the start line',
      })[st] or st)
  end
  if r.clockBase then
    im.TextColored(GREY, 'Rally clock ' .. runner.formatClock(runner.clock()) ..
      (r.startAt and ('   start ' .. runner.formatClock(r.startAt)) or ''))
  end
  for _, l in ipairs(checksText(r.checks)) do im.TextColored(GREY, l) end
  if st == 'finished' or st == 'failed' then
    if im.Button('Close') then runner.abort(true) end
  else
    if im.Button('Stop the run') then runner.abort() end
  end
end

-- (the actions below, shared with the menu page)
local doAction

local function drawWindow()
  im.SetNextWindowSize(im.ImVec2(460, 560), im.Cond_FirstUseEver)
  if not im.Begin('Earth Rally ' .. M.VERSION .. ' (developer)###earthRallyWindow', show) then im.End() return end

  local ok, why = earth.check()
  if not ok then im.TextColored(AMBER, why) end
  if im.Button('Open the menu') then M.openMenu() end
  im.SameLine()
  if im.Button('HUD preview') then M.previewHud() end
  im.SameLine()
  if im.Button('Reload') then events.list(true) selEvent, selStage = 1, 1 end

  local list = events.list()
  for i, e in ipairs(list) do
    if im.Selectable1(e.name .. '##ev' .. i, selEvent == i) then selEvent, selStage = i, 1 end
  end
  local ev = list[selEvent]
  if ev then
    im.Separator()
    for i, s in ipairs(ev.stages) do
      local st = menu.stageStatus(ev.id, s, earth.hasRoadGraph())
      local label = string.format('%s  (%s)  - %s##st%d', s.name, km(s.lengthM), st.note, i)
      if im.Selectable1(label, selStage == i) then selStage = i end
    end
    local stage = ev.stages[selStage]
    if stage then
      im.Separator()
      im.Text(stage.name)
      im.TextColored(GREY, string.format('%s, fits a %s circle', km(stage.lengthM), km(stage.radiusM)))
      local busy = recce.active() or (runner.current() and runner.state() ~= 'finished' and runner.state() ~= 'failed')
      if recce.active() then
        local share, len, n, off, started = recce.progress()
        if started then
          im.TextColored(GREEN, string.format('Recce: %.0f %% (%s, %d points)', share * 100, km(len), n))
        else
          im.TextColored(AMBER, 'Recce: drive to the start of the stage; recording begins there')
        end
        if off and off > 60 then
          im.TextColored(AMBER, string.format('%.0f m from the stage line: follow the orange line', off))
        end
        if im.Button('Save recce') then message = doAction('recceSave').message end
        im.SameLine()
        if im.Button('Save anyway') then message = doAction('recceSaveAnyway').message end
        im.SameLine()
        if im.Button('Cancel recce') then message = doAction('recceCancel').message end
      elseif not busy then
        if im.Button('Go to start') then message = doAction('goStart', ev.id, stage.id).message end
        im.SameLine()
        if im.Button('Route to start') then message = doAction('route', ev.id, stage.id, true).message end
        im.SameLine()
        if im.Button('Start recce') then message = doAction('recce', ev.id, stage.id, true).message end
        if events.stageLine(ev.id, stage.id, stage) then
          im.SameLine()
          if im.Button('Run stage') then message = doAction('drive', ev.id, stage.id, true).message end
        end
      end
      local best = events.best(ev.id, stage.id)
      if best then im.Text('Best time: ' .. runner.formatTime(best)) end
    end
  end
  if message then im.TextWrapped(message) end
  drawRun()
  im.End()
end

------------------------------------------------------------------------------------------ imports

-- The import folder looked at: new or changed maps imported, the list read again, a message for each.
function M.scanImports(always)
  local ok, done = pcall(importer.scan, always)
  if not ok then
    log('E', logTag, 'import: ' .. tostring(done))
    message = 'Import failed: ' .. tostring(done)
    lastImport = { at = os.date('%d %b, %H:%M'), lines = { { text = message, ok = false } } }
    return
  end
  if #done > 0 or always then
    events.list(true)
    selEvent, selStage = 1, 1
  end
  local said, lines = {}, {}
  for _, d in ipairs(done) do
    local text
    if d.removed then text = d.file .. ' taken out of the import folder (its rally is kept)'
    elseif d.ok then text = string.format('%s: %s, %d stage%s', d.file, tostring(d.name), d.stages, d.stages == 1 and '' or 's')
    else text = 'Could not import ' .. d.file .. ': ' .. tostring(d.why) end
    said[#said + 1] = text
    lines[#lines + 1] = { text = text, ok = d.ok == true }
    if d.ok and not d.removed then
      runner.say(string.format('%d stage%s. Open Earth Rally (Ctrl+Alt+K) to drive one.', d.stages,
        d.stages == 1 and '' or 's'), 6, 'success', 'Imported ' .. tostring(d.name))
    else
      runner.say(text, 6, d.ok and 'info' or 'warning', 'Earth Rally import')
    end
  end
  if #said > 0 then
    message = table.concat(said, '\n')
    lastImport = { at = os.date('%d %b, %H:%M'), lines = lines }
  elseif always then
    message = 'Nothing new in the import folder.'
    lastImport = { at = os.date('%d %b, %H:%M'), lines = { { text = message, ok = true } } }
  end
end

-- A file changed in the game's user folder: one in the import folder is looked at a moment later (it may still be
-- being written).
function M.onFileChanged(filename)
  if type(filename) == 'string' and filename:lower():find(importer.IMPORT_DIR:lower(), 1, true) then scanIn = 1.0 end
end

-- The playtest request, every frame until it is done: the BeamNG.Earth level loaded when the game is still at the
-- menu, then the stage driven (or just gone to) once the world is up with a car in it.
local function updatePlaytest(dt)
  playtest.t = playtest.t + dt
  if playtest.t > M.PLAYTEST_WAIT_S then
    log('W', logTag, 'playtest: the world never came up; not going to the stage')
    playtest = nil
    return
  end
  if not earth.check() then
    -- (at the main menu: ask for the level, once, after a moment for the menu to settle)
    if not playtest.levelAsked and playtest.t > 6 then
      playtest.levelAsked = true
      local fr = rawget(_G, 'freeroam_freeroam')
      if not fr and extensions and extensions.load then
        pcall(extensions.load, 'freeroam_freeroam')
        fr = rawget(_G, 'freeroam_freeroam')
      end
      if fr and fr.startFreeroamByName then
        log('I', logTag, 'playtest: loading the BeamNG.Earth level')
        pcall(fr.startFreeroamByName, 'beamng_earth')
      else
        log('W', logTag, 'playtest: cannot load the level (no freeroam_freeroam.startFreeroamByName)')
        playtest = nil
      end
    end
    return
  end
  if not (earth.ready() and getPlayerVehicle and getPlayerVehicle(0)) then
    playtest.ready = 0
    return
  end
  playtest.ready = (playtest.ready or 0) + dt
  if playtest.ready < M.PLAYTEST_SETTLE_S then return end
  local what = playtest.what == 'goStart' and 'goStart' or 'drive'
  local ev, st = playtest.event, playtest.stage
  playtest = nil
  local r = doAction(what, ev, st, true)
  log('I', logTag, string.format('playtest: %s %s / %s: %s', what, tostring(ev), tostring(st),
    r and (r.ok and 'on its way' or tostring(r.message)) or '?'))
  if not (r and r.ok) then
    runner.say(tostring(r and r.message or 'could not go to the stage'), 8, 'warning', 'Playtest')
  end
end

------------------------------------------------------------------------------------------ the auto recce

-- What happened, in a line under the rally's card. Four endings, four colours -- the colour is the Vue's, from
-- `kind`; the words are here (docs/mockups-1.3.0/auto-recce-button.html section 5).
--
-- A written file needs no line at all: the button going away, and the pill turning green, is the whole message. The
-- other three wrote nothing, so each has to say what it found and what would change it -- and none of them may
-- suggest that the auto recce could have downloaded the missing map data, because it never downloads anything.
local function autoText(a, kind, why, how)
  local name = string.format('SS%s %s', tostring(a.ss), tostring(a.stageName))
  if kind == autoRecce.PARTIAL then
    return string.format(
      '%s: %d of %d windows had map data on this computer. The stage is matched nowhere, because %.1f km of it ' ..
      'has none and a line that stops part way is worse than no line. Drive or fly that ground once in ' ..
      'BeamNG.Earth, then run this again.',
      name, how and how.withData or 0, how and how.windows or 0, (how and how.shortM or 0) / 1000)
  elseif kind == autoRecce.NODATA then
    return string.format(
      '%s: no map data on this computer along this stage, so there was nothing to match to. The auto recce never ' ..
      'downloads -- drive or fly the ground once in BeamNG.Earth, or drive the recce.', name)
  end
  return string.format('%s: stopped at window %d of %d -- %s. Nothing was written; the stage is as it was.',
    name, math.min((how and how.done or 0) + 1, how and how.windows or 1), how and how.windows or 0,
    tostring(why or 'no reason given'))
end

local function autoKey(eventId, stageId) return tostring(eventId) .. '|' .. tostring(stageId) end

-- autoRecce's done callback: the only place the menu learns how one ended.
local function autoDone(ok, matched, why, how)
  local a = autoRun
  autoRun = nil
  if not a then return end
  local kind = (how and how.kind) or (ok and autoRecce.DONE or autoRecce.FAILED)
  if ok then
    -- (the stage speaks for itself now: ready, or amber where the map has no road there)
    autoLines[autoKey(a.eventId, a.stageId)] = nil
    message = string.format('Auto recce of %s: done.', a.stageName)
  else
    autoLines[autoKey(a.eventId, a.stageId)] =
      { eventId = a.eventId, stageId = a.stageId, ss = a.ss, kind = kind, text = autoText(a, kind, why, how) }
    message = nil
  end
  log('I', logTag, string.format('auto recce of %s: %s (%s)', tostring(a.stageId), kind, tostring(why or 'written')))
end
M._autoDone = autoDone

------------------------------------------------------------------------------------------ the menu page's buttons

-- One action of the menu page (or the developer panel): returns { ok, message, closeMenu }.
--   drive / route / recce / goStart   a stage's buttons (eventId, stageId)
--   autoRecce                         the auto recce of one stage (eventId, stageId); autoRecceStop stops it
--   recceSave / recceSaveAnyway / recceCancel / abort
--   openFolder / rescan
doAction = function(what, eventId, stageId, fromPanel)
  local ev, stage = nil, nil
  if eventId then ev, stage = menu.findStage(eventId, stageId) end
  local function res(ok, msg, close)
    if ok and close and not fromPanel then M.closeMenu() end
    return { ok = ok == true, message = msg }
  end
  if what == 'openFolder' then
    if importer.openFolder() then return res(true, nil) end
    return res(false, 'The import folder: ' .. importer.folderPath())
  elseif what == 'rescan' then
    M.scanImports(true)
    return res(true, message)
  elseif what == 'abort' then
    runner.abort()
    return res(true, 'Run stopped.')
  elseif what == 'recceSave' or what == 'recceSaveAnyway' then
    local saved, err = recce.stop(true, what == 'recceSaveAnyway')
    return res(saved, saved and 'Recce saved: you can drive the stage.' or err)
  elseif what == 'recceCancel' then
    recce.stop(false)
    return res(true, 'Recce cancelled.')
  elseif what == 'autoRecceStop' then
    local was = autoRun
    autoRun = nil
    -- (autoRecce.cancel does not call the done callback -- a stop is not an ending, and leaves no line behind)
    local stopped = autoRecce.cancel()
    return res(stopped, stopped and string.format('Auto recce of %s stopped.',
      was and was.stageName or 'the stage') or 'No auto recce is running.')
  end
  if not stage then return res(false, 'That stage is not on this computer any more.') end
  local busy = recce.active() or (runner.current() and runner.state() ~= 'finished' and runner.state() ~= 'failed')
  if busy then return res(false, recce.active() and 'A recce is under way: save or cancel it first.' or
    'A run is under way: stop it first.') end
  -- An auto recce holds the page as a recce does: it is one window at a time (autoRecce.start refuses a second
  -- one of its own accord), and a run would move the world's origin out from under the window in flight. This
  -- answers for a second Auto recce too, rather than letting it reach start: start's refusal would arrive after
  -- autoRun had been overwritten, and the page would lose the banner and the row mark of the run still going.
  if autoRecce.active() then
    return res(false, 'An auto recce is under way: stop it first.')
  end
  if what == 'autoRecce' then
    local _, _, ss = menu.findStage(ev.id, stage.id)
    local key = autoKey(ev.id, stage.id)
    autoRun = { eventId = ev.id, stageId = stage.id, stageName = stage.name, ss = ss }
    autoLines[key] = nil
    local ok, why = autoRecce.start(ev, stage, autoDone)
    if not ok then
      -- It can fail inside its first window, in which case autoDone has already run and left the ending's line
      -- behind (and nil'd autoRun) -- which is how that is told apart from a refusal before anything happened.
      if autoRun then autoRun = nil end
      return res(false, why or (autoLines[key] and autoLines[key].text) or 'the auto recce could not be started')
    end
    local pr = autoRecce.progress() or {}
    return res(true, string.format(
      'Auto recce of %s: %d windows. It reads only the map data already on your disk and downloads nothing.',
      stage.name, pr.windows or 0))
  end
  if what == 'drive' then
    local ok, why = runner.start(ev, stage)
    return res(ok, ok and nil or why, true)
  elseif what == 'route' then
    local lat, lon, kind = runner.arrivalPoint(stage)
    local ok, why = false, 'the stage has no start'
    if lat then ok, why = earth.gpsSet(lat, lon, stage.name .. ' ' .. kind) end
    if ok then runner.say('Follow the arrows on the road.', 5, 'info', 'Route set to ' .. stage.name .. "'s " .. kind) end
    return res(ok, ok and ('Route set to ' .. stage.name .. "'s " .. kind .. ': follow the arrows on the road.')
      or ('Could not set a route: ' .. tostring(why)), true)
  elseif what == 'goStart' or what == 'recce' then
    local s = stage.controls and stage.controls.start or { lat = stage.line[1][1], lon = stage.line[1][2] }
    local p = earth.pose()
    local far = what == 'goStart' or not p or require('earthRally/geo').metres(p.lat, p.lon, s.lat, s.lon) > M.FAR_FOR_RECCE_M
    if far then
      local tok, terr = earth.teleport(s.lat, s.lon, stage.name .. ' start')
      if not tok then return res(false, 'Could not go there: ' .. tostring(terr)) end
      facing = { stage = stage, eventId = ev.id, t = 0, ready = 0 }
    end
    if what == 'recce' then
      recce.start(ev, stage)
      runner.say('Follow the orange line on the road to the flying finish (the green ball); the recce saves itself there.',
        8, 'info', 'Recce: ' .. stage.name)
      return res(true, 'Recce started.', true)
    end
    return res(true, 'Waiting for the world to load...', true)
  end
  return res(false, 'unknown action ' .. tostring(what))
end
M._action = doAction

function M.uiAction(what, eventId, stageId)
  local ok, r = pcall(doAction, what, eventId, stageId)
  if not ok then log('E', logTag, 'menu action ' .. tostring(what) .. ': ' .. tostring(r)) return { ok = false, message = tostring(r) } end
  if r.message then message = r.message end
  return r
end

-- The results card's buttons: 'next', 'retry', 'menu' (the rally's page), 'close'.
function M.uiResults(what)
  local r = runner.current()
  local eventId = r and r.event and r.event.id
  local ok, why = runner.resultsAction(what)
  if what == 'menu' then M.openMenu('rally', eventId) end
  if not ok and why then runner.say(tostring(why), 4, 'warning') end
  return { ok = ok == true, message = why }
end

------------------------------------------------------------------------------------------ the menu page's data

local function runSummary()
  local r = runner.current()
  local out = {}
  if r then
    out.run = { state = r.state, eventId = r.event.id, stageId = r.stage.id, stageName = r.stage.name, ss = r.ss,
      busy = r.state ~= 'finished' and r.state ~= 'failed', error = r.error, finalTime = r.finalTime,
      resultsOpen = r.resultsOpen or nil }
  end
  if recce.active() then
    local eid, sid, name = recce.stage()
    local share, len, n, off, started = recce.progress()
    out.recce = { eventId = eid, stageId = sid, stageName = name, share = share, lengthM = len, points = n,
      offM = off, started = started }
  end
  -- the auto recce: whether one can be run at all (the page shows no button where it cannot, rather than a
  -- disabled one on every row), and the one running, with the window it is on
  out.autoOk = earth.hasRoadGraph()
  if autoRecce.active() and autoRun then
    local p = autoRecce.progress() or {}
    out.auto = { eventId = autoRun.eventId, stageId = autoRun.stageId, stageName = autoRun.stageName,
      ss = autoRun.ss, windows = p.windows, done = p.done,
      -- (the step along the line, for the page's sentence: a window is only trustworthy CORRIDOR_M inside its edge)
      stepM = math.floor(autoRecce.RADIUS_M - autoRecce.CORRIDOR_M) }
  end
  return out
end

-- The endings to show under a rally's card: one line per stage, in stage order.
local function autoLinesFor(eventId)
  local out = {}
  for _, l in pairs(autoLines) do
    if l.eventId == eventId then out[#out + 1] = l end
  end
  table.sort(out, function(a, b) return (a.ss or 0) < (b.ss or 0) end)
  return out
end

-- Everything the Rallies and Settings pages show.
function M.uiState()
  local s = runSummary()
  local ok, why = earth.check()
  s.version = M.VERSION
  s.earthOk, s.earthWhy = ok, (not ok) and why or nil
  s.settings = settings.uiState()
  s.rallies = menu.rallies(importer.lastReports)
  s.importFolder = importer.folderPath()
  s.lastImport = lastImport
  s.message = message
  return s
end

-- The page to open at, once (the menu page asks as it opens): { view, eventId, stageId } or nil.
function M.uiOpenAt()
  local at = openAt
  openAt = nil
  return at
end

function M.uiRally(eventId)
  local out = menu.rally(eventId, importer.lastReports, earth.hasRoadGraph())
  if not out then return { missing = true } end
  for k, v in pairs(runSummary()) do out[k] = v end
  out.autoLines = autoLinesFor(eventId)
  return out
end

function M.uiStage(eventId, stageId)
  local _, stage = menu.findStage(eventId, stageId)
  if not stage then return { missing = true } end
  local _, _, arrival = runner.arrivalPoint(stage)
  local out = menu.stage(eventId, stageId, arrival, earth.hasRoadGraph())
  for k, v in pairs(runSummary()) do out[k] = v end
  out.autoLine = autoLines[autoKey(eventId, stageId)]
  return out
end

function M.uiSet(key, value) return settings.set(key, value) end

------------------------------------------------------------------------------------------ the HUD's streams

local streamT, streamOn, inactiveSent = 0, false, true
local previewT = nil
local previewLayout = nil
local unloadNext = false      -- the mod was switched off: stop being a loaded extension next frame (onModDeactivated)

-- The HUD preview: sample frames through the real HUD apps (the stage layout put on for it), without driving.
function M.previewHud()
  if runner.current() and runner.state() ~= 'finished' and runner.state() ~= 'failed' then
    runner.say('Not during a run.', 3, 'warning', 'HUD preview')
    return false
  end
  previewT = 0
  local gs = rawget(_G, 'core_gamestate')
  if gs and gs.getGameState and gs.setGameState and not previewLayout then
    local okS, cur = pcall(gs.getGameState)
    previewLayout = okS and cur and cur.appLayout or 'beamngEarth'
    pcall(gs.setGameState, nil, runner.STAGE_LAYOUT)
  end
  if menuOpen then M.closeMenu() end
  log('I', logTag, string.format('HUD preview: %d s of sample frames', preview.duration()))
  return true
end
function M.previewStop()
  previewT = nil
  local gs = rawget(_G, 'core_gamestate')
  if previewLayout and gs and gs.setGameState and not runner.current() then
    pcall(gs.setGameState, nil, previewLayout ~= runner.STAGE_LAYOUT and previewLayout or 'beamngEarth')
  end
  previewLayout = nil
  inactiveSent = false
end

-- What the HUD's streams carry, logged once each time it changes (the run's state, the stock apps' state, the pieces
-- of ours that are up): in game, "not sent" told apart from "sent but not shown". rl nil: the rallyLoop stream is
-- left alone (the extension gameplay_rallyLoop is loaded: the game's own rally mode sends it).
local streamLogKey = nil
local function showKeys(ours)
  local keys = {}
  for k, v in pairs(type(ours) == 'table' and type(ours.show) == 'table' and ours.show or {}) do
    if v and k ~= 'bigCount' and k ~= 'go' then keys[#keys + 1] = k end
  end
  table.sort(keys)
  return table.concat(keys, ',')
end
function M.streamsKey(rl, ours)
  return table.concat({ tostring(ours and ours.state), tostring(rl and rl.activeState or 'none'),
    tostring(rl and rl.showStageApps), showKeys(ours) }, '|')
end
function M.streamsLine(rl, ours)
  local rlText = rl and string.format('activeState %s, showStageApps %s, theme %s', tostring(rl.activeState),
    tostring(rl.showStageApps), tostring(rl.uiColors and rl.uiColors.theme)) or
    'NOT sent (noRallyLoop: gameplay_rallyLoop is loaded)'
  return string.format('HUD streams (run %s): rallyLoop %s; earthRally show [%s]', tostring(ours and ours.state),
    rlText, showKeys(ours))
end

local function sendStreams(dt)
  local gh = rawget(_G, 'guihooks')
  if not (gh and gh.queueStream) then return end
  if previewT then
    -- (the layout on screen checked once, as for a run)
    if previewT < runner.LAYOUT_CHECK_S and previewT + dt >= runner.LAYOUT_CHECK_S then pcall(runner._logLayout) end
    previewT = previewT + dt
    local rl, ours = preview.frameAt(previewT, settings.get('units'))
    if not rl then M.previewStop() return end
    gh.queueStream('rallyLoop', rl)
    gh.queueStream('earthRally', ours)
    return
  end
  local r = runner.current()
  local over = not r or ((r.state == 'finished' or r.state == 'failed') and not r.resultsOpen
    and (r.sinceFinish or 99) > 5)
  if over then
    -- (once: the stock apps blank, ours hides)
    if not inactiveSent then
      local rl, ours = runner.uiFrame()
      if rl then gh.queueStream('rallyLoop', { activeState = 'inactive', showStageApps = false }) end
      ours.state, ours.show = 'idle', {}
      gh.queueStream('earthRally', ours)
      inactiveSent = true
      if streamLogKey then log('I', logTag, 'HUD streams: the run over, the HUD hidden') end
      streamLogKey = nil
    end
    return
  end
  inactiveSent = false
  streamT = streamT + dt
  local hz = (r.state == 'finished' or r.state == 'failed') and M.STREAM_IDLE_HZ or M.STREAM_HZ
  if streamT < 1 / hz and r.state == streamOn then return end
  streamT, streamOn = 0, r.state
  local rl, ours = runner.uiFrame()
  if rl then gh.queueStream('rallyLoop', rl) end
  gh.queueStream('earthRally', ours)
  local key = M.streamsKey(rl, ours)
  if key ~= streamLogKey then
    streamLogKey = key
    log('I', logTag, M.streamsLine(rl, ours))
  end
end
M._sendStreams = sendStreams

------------------------------------------------------------------------------------------ hooks

function M.onUpdate(dtReal, dtSim)
  -- switched off a frame ago: stop running (see onModDeactivated)
  if unloadNext then
    unloadNext = false
    local ext = rawget(_G, 'extensions')
    if ext and ext.unload then pcall(ext.unload, 'earthRally_main') end
    return
  end
  if scanIn then
    scanIn = scanIn - (dtReal or 0)
    if scanIn <= 0 then scanIn = nil M.scanImports(false) end
  end
  earth.update()
  if recce.active() and recce.update() == 'done' then
    local saved, err = recce.stop(true)
    message = saved and 'Recce saved: you can drive the stage.' or err
    runner.say(message, 6, saved and 'success' or 'warning', 'Recce')
  end
  if recce.active() then pcall(recce.draw, dtReal) end
  if facing then
    facing.t = facing.t + dtReal
    facing.ready = earth.ready() and facing.t > 2 and (facing.ready + dtReal) or 0
    if facing.ready >= runner.TELEPORT_SETTLE_S then
      local fok, placed, how = pcall(runner.faceStage, facing.stage, facing.eventId)
      log('I', logTag, 'Go to start: the car set down (' .. tostring(fok and placed and how or 'not moved') .. ')')
      if message == 'Waiting for the world to load...' then message = nil end
      facing = nil
    elseif facing.t > 120 then
      if message == 'Waiting for the world to load...' then message = 'The world is taking long to load here.' end
      facing = nil
    end
  end
  if playtest then
    local okP, errP = pcall(updatePlaytest, dtReal or 0)
    if not okP then log('E', logTag, 'playtest: ' .. tostring(errP)) playtest = nil end
  end
  local ok, err = pcall(runner.update, dtReal, dtSim)
  if not ok then log('E', logTag, 'run: ' .. tostring(err)) runner.abort(true) message = 'Run stopped: ' .. tostring(err) end
  local okS, errS = pcall(sendStreams, dtReal or 0)
  if not okS then log('E', logTag, 'HUD: ' .. tostring(errS)) end
  if selftest then
    local okT, errT = pcall(selftest.update, dtReal, M.VERSION)
    if not okT then log('E', logTag, 'self-test: ' .. tostring(errT)) pcall(selftest.stop, 'error: ' .. tostring(errT)) end
  end
  if show[0] then
    local okW, errW = pcall(drawWindow)
    if not okW then log('E', logTag, 'window: ' .. tostring(errW)) pcall(im.End) end
  end
end

-- The game's Interact control (Shift+E; the modifier + Y on a pad): on the start line, skip to 6 s before the start.
function M.onGameplayInteract()
  pcall(runner.onGameplayInteract)
end

-- Recovery keys (Backspace: back on the road, +10 s on the stage; Shift+Backspace: flip upright).
function M.backOnRoad() local ok, r = pcall(runner.backOnRoad) return ok and r end
function M.flipUpright() local ok, r = pcall(runner.flipUpright) return ok and r end

-- A reset by the player (the game's trackVehReset hook: once a press, a held rewind included): +10 s during the timed
-- stage (setting resetPenalty).
function M.trackVehReset(vid)
  pcall(runner.onReset, vid)
end

-- (after every other extension's frame work: the start clock's view moved where we want it)
function M.onDrawDebug()
  pcall(runner.placeClockView)
end

-- The in-game self-test (developer tool; tools/selftest.py starts it through a request file, see selftest.lua): a
-- stage run end to end by the game's AI, with checks, and a report in earthRally/selftest/. From the console, in the
-- BeamNG.Earth level: earthRally_main.selfTest('otr24', 'maryhill-up'); earthRally_main.selfTestStop() stops it.
function M.selfTest(eventId, stageId, opts)
  opts = opts or {}
  selftest = selftest or require('earthRally/selftest')
  local ok, why = selftest.start({ event = eventId, stage = stageId, token = opts.token, quit = opts.quit,
    loadLevel = opts.loadLevel, budgetS = opts.budgetS, main = M })
  if not ok then log('W', logTag, 'self-test not started: ' .. tostring(why)) end
  return ok, why
end
function M.selfTestStop() if selftest then selftest.stop('stopped from the console') end end

-- The level left, or back at the menu: the run put away. This is the hook that really fires for a player, so every
-- call in it is pcall'd and the strips are given back even if something before that throws -- tidy() reaches
-- layoutOff sixth of nine, so a throw in the traffic or the props would otherwise take the release with it, and a
-- strip left held outlives the level it was held in.
function M.onClientEndMission()
  if selftest then pcall(selftest.onClientEndMission) end
  if recce.active() then pcall(recce.stop, false) end
  -- An auto recce converts each window through the world's origin, so one still in flight when the level goes
  -- would answer into a world that is not there -- and the page would show a banner for something nothing is
  -- running. It stops the way a recce does, and writes nothing.
  if autoRecce.active() then autoRun = nil; pcall(autoRecce.cancel) end
  if previewT then pcall(M.previewStop) end
  pcall(runner.abort, true)
  pcall(earth.holdStrips, false)
  pcall(earth.reset)
end

-- Earth Rally switched off in the mod manager, or its zip deleted. The game does **not** unload a mod's extensions
-- for this: modmanager.deactivateMod unmounts the zip, sets active = false and fires this hook, and never calls
-- extensions.unload (checked in the game's own Lua, build 302427) -- and this extension is 'manual'
-- (scripts/earth_rally/modScript.lua), so a level change does not unload it either. Without this hook we would keep
-- running inside a switched-off mod: runner.update would re-assert the hold on BeamNG.Earth's strips every frame and
-- put the stage layout back every second, over apps whose files have just been unmounted -- a blank HUD the player
-- cannot get out of until they change level.
--
-- Telling whether the mod that went is ours: deactivateMod unmounts before it fires this, so our own file has gone
-- from the virtual file system. (Steadier than matching the zip's name, which a player can rename.)
M.OUR_FILE = '/lua/ge/extensions/earthRally/main.lua'
function M.onModDeactivated()
  local fs = rawget(_G, 'FS')
  if fs and fs.fileExists and fs:fileExists(M.OUR_FILE) then return end   -- another mod went: not our business
  log('I', logTag, 'Earth Rally switched off: the run stopped and BeamNG.Earth left as it was')
  if recce.active() then pcall(recce.stop, false) end
  -- An auto recce converts each window through the world's origin, so one still in flight when the level goes
  -- would answer into a world that is not there -- and the page would show a banner for something nothing is
  -- running. It stops the way a recce does, and writes nothing.
  if autoRecce.active() then autoRun = nil; pcall(autoRecce.cancel) end
  if previewT then pcall(M.previewStop) end
  pcall(runner.abort, true)
  pcall(earth.holdStrips, false)
  pcall(earth.reset)
  unloadNext = true     -- (not from in here: extensions.hook is walking the extension list while we run)
end

-- The extension unloaded part way through a run -- a full Lua reload (Ctrl+L), extensions.reload, or an unload from
-- the console: everything the run put in the game taken back while there is still code here to do it. This is **not**
-- the hook for the mod being switched off in the mod manager; that is onModDeactivated above, and the game does not
-- unload extensions for it. onExtensionLoaded below cleans up on the way back in, but only if the mod comes back at
-- all -- and BeamNG.Earth leaves its own imgui status bar and banner out while it believes an app holds them, so a
-- hold left behind takes its "server not running" message with it on any layout without its apps.
function M.onExtensionUnloaded()
  if recce.active() then pcall(recce.stop, false) end
  -- An auto recce converts each window through the world's origin, so one still in flight when the level goes
  -- would answer into a world that is not there -- and the page would show a banner for something nothing is
  -- running. It stops the way a recce does, and writes nothing.
  if autoRecce.active() then autoRun = nil; pcall(autoRecce.cancel) end
  if previewT then pcall(M.previewStop) end
  pcall(runner.abort, true)
  pcall(earth.holdStrips, false)
  pcall(earth.reset)
end

function M.onExtensionLoaded()
  -- (boards and tents a run left before a Lua reload: taken away; the car's brake / clutch overrides handed back,
  --  and BeamNG.Earth's strips given back in case a run was cut short holding them)
  pcall(require('earthRally/props').sweep)
  pcall(earth.holdStrips, false)
  local veh = getPlayerVehicle and getPlayerVehicle(0)
  if veh then pcall(runner._vehCtl, veh, 'off') end
  settings.load()
  show[0] = settings.get('devPanel') == true
  -- (new maps in the import folder)
  scanIn = 0.5
  log('I', logTag, 'Earth Rally ' .. M.VERSION .. ' loaded (Ctrl+Alt+K opens its menu)')
  -- a stage to be taken to (tools/playtest.py): read once and the file deleted, so a normal start never does it
  do
    local fs = rawget(_G, 'FS')
    if fs and fs.fileExists and fs:fileExists(M.PLAYTEST_REQUEST) then
      local okR, req = pcall(jsonReadFile, M.PLAYTEST_REQUEST)
      if fs.removeFile then pcall(fs.removeFile, fs, M.PLAYTEST_REQUEST) end
      if okR and type(req) == 'table' and req.event and req.stage then
        playtest = { event = req.event, stage = req.stage, what = req.what, t = 0 }
        log('I', logTag, string.format('playtest: %s / %s when the world is up', tostring(req.event),
          tostring(req.stage)))
      else
        log('W', logTag, 'playtest: the request file could not be read')
      end
    end
  end
  -- a self-test asked for (tools/selftest.py): only then is selftest.lua loaded; the request is used once
  local fs = rawget(_G, 'FS')
  if fs and fs.fileExists and fs:fileExists(M.SELFTEST_REQUEST) then
    selftest = selftest or require('earthRally/selftest')
    local req = selftest.readRequest()
    if req then
      M.selfTest(req.event, req.stage, { token = req.token, quit = req.quit == true, loadLevel = req.loadLevel ~= false,
        budgetS = req.budgetS })
    end
  end
end

return M
