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
local runner = require('earthRally/runner')
local importer = require('earthRally/importer')
local settings = require('earthRally/settings')
local menu = require('earthRally/menu')
local preview = require('earthRally/preview')

local M = {}
local logTag = 'earthRally'
M.VERSION = '1.2.2'
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
function M.onUiChangedState(toState)
  if type(toState) == 'string' then menuOpen = toState == M.ROUTE end
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
      local st = menu.stageStatus(ev.id, s)
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

------------------------------------------------------------------------------------------ the menu page's buttons

-- One action of the menu page (or the developer panel): returns { ok, message, closeMenu }.
--   drive / route / recce / goStart   a stage's buttons (eventId, stageId)
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
  end
  if not stage then return res(false, 'That stage is not on this computer any more.') end
  local busy = recce.active() or (runner.current() and runner.state() ~= 'finished' and runner.state() ~= 'failed')
  if busy then return res(false, recce.active() and 'A recce is under way: save or cancel it first.' or
    'A run is under way: stop it first.') end
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
  local out = menu.rally(eventId, importer.lastReports)
  if not out then return { missing = true } end
  for k, v in pairs(runSummary()) do out[k] = v end
  return out
end

function M.uiStage(eventId, stageId)
  local _, stage = menu.findStage(eventId, stageId)
  if not stage then return { missing = true } end
  local _, _, arrival = runner.arrivalPoint(stage)
  local out = menu.stage(eventId, stageId, arrival)
  for k, v in pairs(runSummary()) do out[k] = v end
  return out
end

function M.uiSet(key, value) return settings.set(key, value) end

------------------------------------------------------------------------------------------ the HUD's streams

local streamT, streamOn, inactiveSent = 0, false, true
local previewT = nil
local previewLayout = nil

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
  local ok, err = pcall(runner.update, dtReal, dtSim)
  if not ok then log('E', logTag, 'run: ' .. tostring(err)) runner.abort(true) message = 'Run stopped: ' .. tostring(err) end
  local okS, errS = pcall(sendStreams, dtReal or 0)
  if not okS then log('E', logTag, 'HUD: ' .. tostring(errS)) end
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

function M.onClientEndMission()
  if recce.active() then recce.stop(false) end
  if previewT then M.previewStop() end
  runner.abort(true)
  earth.reset()
end

function M.onExtensionLoaded()
  -- (boards and tents a run left before a Lua reload: taken away; the car's brake / clutch overrides handed back)
  pcall(require('earthRally/props').sweep)
  local veh = getPlayerVehicle and getPlayerVehicle(0)
  if veh then pcall(runner._vehCtl, veh, 'off') end
  settings.load()
  show[0] = settings.get('devPanel') == true
  -- (new maps in the import folder)
  scanIn = 0.5
  log('I', logTag, 'Earth Rally ' .. M.VERSION .. ' loaded (Ctrl+Alt+K opens its menu)')
end

return M
