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

------------------------------------------------------------------- Auto recce, end to end (1.3.1)

-- One button, three things: take the player to the stage, download the map data along it if BeamNG.Earth has none,
-- then match the line (the user, 2026-11-14: "add the download, teleport to start, and auto recce features to all
-- work under the one autorecce button").
--
-- **Why the teleport is not a convenience.** A road-graph window is placed in the active anchor's ENU frame, and
-- that frame drops the up component. Measured in a game 2026-11-14: a stage in Ohio asked for from an anchor at
-- Maryhill, Washington came out at e=3,028,418 m n=36,397 m u=-763,610 m, and the window converted back to
-- 40.55,-86.49 -- Indiana, 380 km from the stage. It reported "no map data" truthfully, about ground nobody asked
-- about. It failed safely only because nothing was cached in Indiana; with cells there it would have matched the
-- stage against the wrong roads. So the player is taken to the stage BEFORE any window is asked for, and the
-- frame is local to it.
--
-- **The order is: price the ground, ask, download, THEN go, then match** (the user, 2026-11-14: "re order things
-- so it downloads first, then teliports"). It is possible because `areaPlan` is frame-free -- it takes lat/lon
-- server-side and needs no anchor, so the ground can be priced from anywhere, before anything moves. Three things
-- follow from doing it this way round:
--   * the player is asked BEFORE being teleported across the world, rather than after;
--   * no match is spent discovering what the estimate already knew;
--   * and there is one match a press, so no loop is possible -- whatever it reports is final.
-- The cost, stated rather than hidden: `missing` counts the area tool's own items over a corridor dilated by two
-- map cells all round, which is wider than the road graph reads. So a stage whose windows are all cached can still
-- have missing items out in that ring and be offered a download it does not need. **Not now carries on** to the
-- teleport and the match for exactly that reason -- declining costs the player nothing.
M.GO_IF_FURTHER_M = 5000     -- the car this far from the start: go there first (nearer, the frame is already local)
M.WORLD_WAIT_S = 120         -- waiting for the world after a teleport, then give up on it
M.AREA_WAIT_S = 1800         -- waiting for a download; it is gated to 40% duty while the car moves

M.GOING, M.ASKING, M.DOWNLOADING = 'going', 'asking', 'downloading'

local autoSeq = nil   -- { ev, stage, ss, phase, t, ready, plan, areaId, downloaded, why, how }

local autoSeqStep     -- (declared here: autoDone drives the sequence on, and is defined above it)

-- (1.3.0 to the first cut of 1.3.1 had an autoFixable() here, to decide whether a refusal was one a download
-- could mend. The order changed -- the ground is priced before the match rather than after it -- so nothing asks
-- that question any more: the estimate's own `missing` decides, and the match happens once and is final.)

-- autoRecce's done callback: the only place the menu learns how one ended.
local function autoDone(ok, matched, why, how)
  local a = autoRun
  autoRun = nil
  if not a then return end
  local kind = (how and how.kind) or (ok and autoRecce.DONE or autoRecce.FAILED)
  -- A sequence still running is told how its match went, so it can add anything the download could not do -- the
  -- app refusing the area, or items nothing could fetch -- beside the stage's own reason. There is one match a
  -- press, so this is always the sequence's last step and it never asks for another.
  --
  -- The matched line is ALWAYS cleared here, whichever way it went. A sequence left behind by a match that
  -- succeeded would make the page busy for ever: the guard in doAction refuses every action while one is running,
  -- so Reset, Drive, Recce and the next Auto recce would all answer "an auto recce is under way" until a reload.
  -- (test_run found exactly that: 11 checks red, all of them the guard refusing something unrelated.)
  if autoSeq and autoSeq.ev.id == a.eventId and autoSeq.stage.id == a.stageId then
    if ok then
      autoSeq = nil
    else
      autoSeq.why, autoSeq.how = why, how
      if autoSeqStep('matched', kind) then return end
    end
  end
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

-- Start the matching leg: the same call the 1.3.0 button made, with the banner and the row mark it sets.
local function autoStartMatch(ev, stage, ss)
  local key = autoKey(ev.id, stage.id)
  autoRun = { eventId = ev.id, stageId = stage.id, stageName = stage.name, ss = ss }
  autoLines[key] = nil
  local ok, why = autoRecce.start(ev, stage, autoDone)
  if not ok then
    if autoRun then autoRun = nil end
    return false, why or (autoLines[key] and autoLines[key].text) or 'the auto recce could not be started'
  end
  return true
end

-- End the sequence. `msg`, when there is one, is what the player is told -- and it goes into autoLines, NOT into
-- `message`.
--
-- `message` is the ImGui developer panel's own string and reaches the Vue UI not at all: the menu gets a message
-- only as the RETURN VALUE of an action it called (store.js sets busyMsg from it). Every leg of this sequence
-- after the first ends asynchronously, with no action waiting on a return, so anything written to `message` here
-- would be seen by nobody -- including the two refusals that matter most, the saved areas being full and all ten
-- slots taken, which only the player can do anything about. autoLines is how 1.3.0's own async endings reach the
-- page (under the rally card, and as stg.autoLine on the stage page), so these go the same way.
--
-- `kind` picks the colour: FAILED for something that went wrong, NODATA for the player declining a download --
-- declining is not an error, and should not be painted as one.
local function autoSeqEnd(msg, kind)
  local sq = autoSeq
  autoSeq = nil
  if not sq then return end
  if msg then
    autoLines[autoKey(sq.ev.id, sq.stage.id)] = { eventId = sq.ev.id, stageId = sq.stage.id, ss = sq.ss,
      kind = kind or autoRecce.FAILED, text = msg }
    message = msg                                   -- (the developer panel as well, which reads this one)
  end
  log('I', logTag, 'auto recce sequence of ' .. tostring(sq.stage.id) .. ': ended (' .. tostring(msg or 'reported')
    .. ')')
end

-- The sequence, one event at a time. `what` is 'tick', 'planned', 'added', 'answer' or 'matched'.
-- Returns true when it has taken an ending over and the player must not be told yet.
autoSeqStep = function(what, arg)
  local sq = autoSeq
  if not sq then return false end

  -- Go to the stage if it is far, then match. The last two legs, reached once the ground is as good as it is
  -- going to get: downloaded, declined, or nothing missing in the first place.
  local function goThenMatch()
    local st = sq.stage.controls and sq.stage.controls.start
      or { lat = sq.stage.line[1][1], lon = sq.stage.line[1][2] }
    local p = earth.pose()
    local away = (not p) and math.huge or require('earthRally/geo').metres(p.lat, p.lon, st.lat, st.lon)
    if away > M.GO_IF_FURTHER_M then
      local tok, terr = earth.teleport(st.lat, st.lon, sq.stage.name .. ' start')
      if not tok then autoSeqEnd('Could not go to the stage: ' .. tostring(terr)) return end
      sq.phase, sq.t, sq.ready = M.GOING, 0, 0
      return
    end
    sq.phase, sq.t = 'matching', 0
    local ok, why = autoStartMatch(sq.ev, sq.stage, sq.ss)
    if not ok then autoSeqEnd('The auto recce could not start: ' .. tostring(why)) end
  end
  sq.goThenMatch = goThenMatch

  if what == 'planned' then
    local r = arg
    -- No estimate, or a bad one: carry on without it rather than stopping. The stage may well match from what is
    -- already here, and refusing to try because the pricing failed would be the worse answer.
    if type(r) ~= 'table' or r.ok ~= true or type(r.downloadBytes) ~= 'number' then
      log('I', logTag, 'auto recce: no estimate (' .. tostring(type(r) == 'table' and r.error or r) ..
        '), carrying on with what is on disk')
      goThenMatch()
      return true
    end
    if (r.missing or 0) <= 0 or (r.downloadBytes or 0) <= 0 then
      log('I', logTag, 'auto recce: the ground along ' .. tostring(sq.stage.id) .. ' is already here')
      goThenMatch()
      return true
    end
    sq.plan, sq.phase, sq.t = r, M.ASKING, 0
    log('I', logTag, string.format('auto recce: %s needs %.1f MB of map data (%d of %d item(s) missing)',
      sq.stage.name, (r.downloadBytes or 0) / 1e6, r.missing or 0, r.items or 0))
    return true

  elseif what == 'answer' then
    if arg ~= true then
      -- Declining is not an ending. The stage may match from what is on disk, and if it cannot the match will say
      -- so in its own words -- which is a better answer than one made up here before anything was tried.
      log('I', logTag, 'auto recce: the player declined the download; carrying on with what is on disk')
      goThenMatch()
      return true
    end
    local pts = autoRecce.corridor(sq.stage.line)
    sq.phase, sq.t, sq.downloaded = M.DOWNLOADING, 0, true
    local ok, why = earth.areaAdd(pts, 'Earth Rally: ' .. sq.stage.name, function(r) autoSeqStep('added', r) end)
    if not ok then autoSeqEnd('Could not start the download: ' .. tostring(why)) end
    return true

  elseif what == 'added' then
    local r = arg
    if type(r) ~= 'table' or r.ok ~= true or type(r.id) ~= 'string' then
      -- the refusal worth surfacing rather than working around: the saved areas' share of the cache is full, or
      -- all ten slots are taken. Both are the player's to act on. The stage is still tried with what is here.
      local reason = tostring(type(r) == 'table' and r.error or 'no reason given')
      log('I', logTag, 'auto recce: BeamNG.Earth would not take the area (' .. reason .. ')')
      sq.addRefused = reason
      goThenMatch()
      return true
    end
    sq.areaId, sq.t = r.id, 0
    return true

  elseif what == 'matched' then
    -- One match a press, so this is always the end: there is nothing left to try and nothing to loop over.
    --
    -- Anything the download could not do is said HERE, beside the stage's own reason, and taking the ending over
    -- (true) is what makes it stick: autoDone writes its own autoText into autoLines straight after this returns,
    -- so a note left behind by returning false is overwritten and the player never sees it. Only the stage's
    -- reason would survive -- and "the auto recce never downloads" is exactly the wrong thing to tell someone
    -- whose download was just refused for want of a cache slot.
    local note = nil
    if sq.addRefused then
      note = 'BeamNG.Earth would not take the download: ' .. sq.addRefused
    elseif (sq.unavailable or 0) > 0 then
      note = string.format('The download finished with %d item(s) nothing could fetch. %s',
        sq.unavailable, tostring(sq.areaMsg or 'Resume that area to try those again.'))
    end
    if not note then
      autoSeqEnd(nil)
      return false              -- nothing to add: autoDone reports the stage's own ending, as 1.3.0 does
    end
    local own = autoText({ ss = sq.ss, stageName = sq.stage.name }, arg, sq.why, sq.how)
    autoSeqEnd((own and (own .. ' ') or '') .. note, arg)
    return true

  elseif what == 'tick' then
    sq.t = sq.t + (arg or 0)
    if sq.phase == M.GOING then
      sq.ready = earth.ready() and sq.t > 2 and (sq.ready + (arg or 0)) or 0
      if sq.ready >= runner.TELEPORT_SETTLE_S then
        pcall(runner.faceStage, sq.stage, sq.ev.id)
        sq.phase, sq.t = 'matching', 0
        local ok, why = autoStartMatch(sq.ev, sq.stage, sq.ss)
        if not ok then autoSeqEnd('The auto recce could not start: ' .. tostring(why)) end
      elseif sq.t > M.WORLD_WAIT_S then
        autoSeqEnd('The world is taking long to load here: try the auto recce again.')
      end
    elseif sq.phase == M.DOWNLOADING and sq.areaId then
      local st = earth.areaStatus(sq.areaId)
      if st and (st.state == 'done' or st.state == 'failed') then
        -- `done` does not mean every tile arrived: after enough failed passes the rest are counted unavailable and
        -- the area is marked done anyway (measured here: an area finished done with 122 of 1079 unavailable). So
        -- the ground is re-checked by matching rather than trusted, and the area's own message is carried through.
        sq.unavailable, sq.areaMsg = st.unavailable, st.msg
        if (st.unavailable or 0) > 0 then
          log('I', logTag, string.format('auto recce: the download finished with %d item(s) unavailable (%s)',
            st.unavailable, tostring(st.msg)))
        end
        goThenMatch()
      elseif sq.t > M.AREA_WAIT_S then
        autoSeqEnd('The download is taking very long: it carries on in the background, so try again later.')
      end
    end
    return true
  end
  return false
end

------------------------------------------------------------------------------------------ the menu page's buttons

-- One action of the menu page (or the developer panel): returns { ok, message, closeMenu }.
--   drive / route / recce / goStart   a stage's buttons (eventId, stageId)
--   autoRecce                         the auto recce of one stage (eventId, stageId); autoRecceStop stops it
--   reset                             remove a stage's line, both kinds, so it can be made again
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
  elseif what == 'autoRecceDownload' or what == 'autoRecceSkip' then
    -- (up here with Stop, before the busy guard: the sequence makes the page busy, so a question it asked would
    --  otherwise be refused by the guard the asking itself put up -- the player could neither say yes nor no)
    if not (autoSeq and autoSeq.phase == M.ASKING) then return res(false, 'Nothing is waiting to be downloaded.') end
    local nm = autoSeq.stage.name
    autoSeqStep('answer', what == 'autoRecceDownload')
    return res(true, what == 'autoRecceDownload' and ('Downloading the map data along ' .. nm .. '.') or nil)
  elseif what == 'autoRecceStop' then
    local was = autoRun or (autoSeq and { stageName = autoSeq.stage.name })
    autoRun = nil
    -- the sequence goes with it: a teleport already happened and a download already added carries on in the
    -- background (it is the player's area now), but nothing further is asked for and nothing is written
    local hadSeq = autoSeq ~= nil
    autoSeq = nil
    -- (autoRecce.cancel does not call the done callback -- a stop is not an ending, and leaves no line behind)
    local stopped = autoRecce.cancel() or hadSeq
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
  if autoRecce.active() or autoSeq then
    -- autoSeq as well as autoRecce.active(): between the legs -- going to the stage, pricing the ground, waiting
    -- on the player, downloading -- no window is in flight, so this guard is the only thing standing between a
    -- second press and two sequences on one stage.
    return res(false, 'An auto recce is under way: stop it first.')
  end
  if what == 'reset' then
    -- Behind the same busy and autoRecce.active() guards as an auto recce, and for the same reason: the runner and
    -- the auto recce both read the stage's line while they work, so removing it under either is how a car gets
    -- driven off the end of a line that is no longer there.
    local removed, why = events.resetLine(ev.id, stage.id)
    if not removed then return res(false, why or 'that line could not be removed') end
    -- the ending text from the last auto recce goes with it, or the page would still be showing "matched, 4.1 km"
    -- under a stage that now has no line at all
    autoLines[autoKey(ev.id, stage.id)] = nil
    if not (removed.recce or removed.matched) then
      return res(true, string.format('%s had no line to remove.', stage.name))
    end
    local what_ = (removed.recce and removed.matched) and 'its recce and its matched line'
      or (removed.recce and 'the recce you drove' or 'its matched line')
    return res(true, string.format('%s: %s removed. Run the auto recce, or drive a recce.', stage.name, what_))
  end
  if what == 'autoRecce' then
    local _, _, ss = menu.findStage(ev.id, stage.id)
    autoSeq = { ev = ev, stage = stage, ss = ss, phase = 'planning', t = 0, ready = 0 }
    -- The estimate first, because it needs no anchor: `areaPlan` takes lat/lon on the server and knows nothing of
    -- the player's frame, so the ground can be priced from where the player is standing. That is what lets the
    -- question be asked before they are teleported across the world.
    if earth.hasAreaRoute() then
      local pts = autoRecce.corridor(stage.line)
      if pts then
        local ok, why = earth.areaPlan(pts, function(r) autoSeqStep('planned', r) end)
        if ok then
          return res(true, string.format('Auto recce of %s: checking what map data is missing.', stage.name))
        end
        log('I', logTag, 'auto recce: no estimate (' .. tostring(why) .. ')')
      end
    end
    -- No fetching capability (or no corridor to price): straight to the 1.3.0 path, and the promise 1.3.0 made
    -- here still holds because nothing can be downloaded.
    autoSeqStep('planned', nil)
    if not autoSeq then return res(false, (autoLines[autoKey(ev.id, stage.id)] or {}).text or
      'the auto recce could not be started') end
    if autoSeq.phase == M.GOING then
      return res(true, string.format('Auto recce of %s: going to the start first.', stage.name))
    end
    local pr = autoRecce.progress() or {}
    return res(true, string.format('Auto recce of %s: %d windows. %s', stage.name, pr.windows or 0,
      earth.hasAreaRoute() and 'It reads the map data on your disk, and asks before downloading any it needs.'
        or 'It reads only the map data already on your disk and downloads nothing.'))
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
  -- whether the one button can also fetch the ground: the page says "downloads nothing" without it, and offers the
  -- download with it, so this has to reach the UI rather than being decided in the Lua alone
  out.autoCanFetch = earth.hasRoadGraph() and earth.hasAreaRoute()
  if autoRecce.active() and autoRun then
    local p = autoRecce.progress() or {}
    out.auto = { eventId = autoRun.eventId, stageId = autoRun.stageId, stageName = autoRun.stageName,
      ss = autoRun.ss, windows = p.windows, done = p.done, phase = 'matching',
      -- (the step along the line, for the page's sentence: a window is only trustworthy CORRIDOR_M inside its edge)
      stepM = math.floor(autoRecce.RADIUS_M - autoRecce.CORRIDOR_M) }
  elseif autoSeq then
    -- the legs with no window count of their own: going to the stage, pricing the ground, waiting on the player,
    -- downloading. The row and the banner follow `phase`, so one press reads as one thing throughout.
    local st = autoSeq.areaId and earth.areaStatus(autoSeq.areaId) or nil
    out.auto = { eventId = autoSeq.ev.id, stageId = autoSeq.stage.id, stageName = autoSeq.stage.name,
      ss = autoSeq.ss, phase = autoSeq.phase, waitedS = math.floor(autoSeq.t or 0) }
    if autoSeq.phase == M.ASKING and autoSeq.plan then
      out.auto.ask = { bytes = autoSeq.plan.downloadBytes, diskBytes = autoSeq.plan.diskBytes,
        km = autoSeq.plan.km, items = autoSeq.plan.items, missing = autoSeq.plan.missing }
    end
    if st then
      out.auto.area = { state = st.state, done = st.done, total = st.total, unavailable = st.unavailable,
        msg = st.msg, name = st.name }
    end
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
  if autoSeq then
    local okSeq, errSeq = pcall(autoSeqStep, 'tick', dtReal or 0)
    if not okSeq then log('E', logTag, 'auto recce sequence: ' .. tostring(errSeq)) autoSeq = nil end
  end
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
  -- autoSeq as well: a sequence between its legs has no window in flight, so cancelling the auto recce alone
  -- would leave it behind and the page busy for ever (the guard in doAction refuses everything while one runs)
  autoSeq = nil
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
  -- autoSeq as well: a sequence between its legs has no window in flight, so cancelling the auto recce alone
  -- would leave it behind and the page busy for ever (the guard in doAction refuses everything while one runs)
  autoSeq = nil
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
  -- autoSeq as well: a sequence between its legs has no window in flight, so cancelling the auto recce alone
  -- would leave it behind and the page busy for ever (the guard in doAction refuses everything while one runs)
  autoSeq = nil
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
