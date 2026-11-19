-- earthRally_main: Earth Rally's frame loop and its ways in:
--   the menu      a full-screen page of its own (ui/ui-vue/mods/earthRally: Rallies, a rally, a stage, Settings) and
--                 an "Earth Rally" tab in the pause menu; Ctrl+Alt+K opens / closes the page (toggleMenu). The page
--                 asks this extension for its data (uiState, uiSeason, uiRally, uiStage) and sends the buttons here (uiAction,
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
local hudFrame = require('earthRally/hudFrame')
local versions = require('earthRally/versions')
local earthMenuFix = require('earthRally/earthMenuFix') -- STOPGAP: remove with BeamNG.Earth's fix (the file says)
local stats = require('earthRally/stats')             -- anonymous stats, opt-in (+stats)
local report = require('earthRally/report')           -- Report a problem: a GitHub issue in the browser (+stats)
local menuPause = require('earthRally/menuPause')     -- the game paused while the menu page is up (1.6.2, #13)
local rally = require('earthRally/rally')             -- the full rally (1.7.0): its rules and numbers
local rallyRun = require('earthRally/rallyRun')       -- ... and driving it in the game
local loadScreen = require('earthRally/loadScreen')   -- the page's loading screen (1.7.0, #49)
local online = require('earthRally/online')         -- the online leaderboard (prototype): via the companion
menuPause.holding = earth.holding                    -- (BeamNG.Earth's own holds: our request waits for them)
-- (#63: the run moving the world's origin needs the physics on: the page's pause waits for it, the screen shows it.
-- Only under a loading screen -- the page's pause otherwise stays as it was -- and the run holds the car still then)
menuPause.waitFor = function() return loadScreen.active() ~= nil and runner.originMoving() end
runner.loadingUp = function() return loadScreen.active() ~= nil end
runner.cardPaused = function() return menuPause.cardHeld('earthRally_results') end
loadScreen.moving = function() return runner.originMoving() or earth.rebasing() == true end

local M = {}
local logTag = 'earthRally'
local logPausedSim         -- (below, by onUpdate)
M.VERSION = '1.8.0-alpha+helperprompt'
M.ROUTE = 'earthRally'            -- the menu page's route (ui/ui-vue/mods/earthRally/index.js)
M.STREAM_FLOOR_S = 1             -- the HUD's streams sent when what they show changes, and at least this often
M.STREAM_GAP_S = 0.1              -- ... the stock stream at most this often outside waitStart / running
M.ARROW_GAP_S = 1 / 30            -- ... ours off route at most this often (the way-back arrow turns with no easing)
M.HUD_GAP_S = 0.1                 -- ... ours at most this often on the road sections (the distance in metres)
M.SLOW_SAMPLE_S = 0.25            -- the car stopped and the skip hint looked at this often (they ask for its pose)
M.STREAM_FIXED_HZ = nil           -- (the bench: both streams on a timer at this rate instead, as before 1.6.1)
M.FAR_FOR_RECCE_M = 300           -- Recce from further than this from the start: taken there first

local show = im.BoolPtr(false)
local selEvent, selStage = 1, 1
local message = nil
local facing = nil       -- after Go to start: turn the car along the stage once BeamNG.Earth has set it down
local scanIn = nil       -- seconds until the import folder is looked at (a file changed in it)
local menuOpen = false   -- the menu page is the screen now (onUiChangedState)
local statsMenuUp = false  -- the same, as stats last saw it (onUiChangedState only)
local openAt = nil       -- the page to show when the menu opens next: { view, eventId, stageId }
local helperDone = false -- (#77) the helper prompt was shown and closed in this menu open (or not wanted)
local earthSeen = false  -- the BeamNG.Earth level has been loaded at least once since the mod loaded. The version
                         -- check runs again then: that is where the game's rally engine can be looked at without
                         -- dragging it in at the main menu, which is a cost every start for an answer wanted
                         -- before a stage (versions.lua).
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
settings.onChange('main', function(key, v)
  if key == 'devPanel' then show[0] = v == true end
  if key == 'onlineBoard' then
    online.enable(v == true)
    if v == true then pcall(stats.sessionStart) pcall(stats.flushSoon) end
  end
end)

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
  if not view and rallyRun.active() then view = 'timecard' end   -- (a full rally under way: its time card)
  if view then openAt = { view = view, eventId = eventId, stageId = stageId } end
  menuOpen = navigate(M.ROUTE)
  return menuOpen
end
function M.closeMenu()
  menuOpen = false
  return navigate('play')
end
-- (the full rally's time card is a view of the menu page: rallyRun opens it after a recovery and from Continue)
rallyRun.ui.openCard = function() return M.openMenu('timecard') end
rallyRun.ui.closeMenu = function() if menuOpen then pcall(menuPause.suspend) return M.closeMenu() end end

------------------------------------------------------------------------------------------ the loading screens (#49)
-- Wherever the menu used to close and the world then loaded in view, the page stays up (or opens) on a loading screen
-- (loadScreen.lua) until the car is placed and the world round it has loaded to the setting's share. The game stays
-- paused under it: BeamNG.Earth loads while paused (the drive of 2026-11-16, docs/notes-1.7.0.md #10), and the
-- run's loading steps go on real time (runner.update's travel / anchor / build / place). Except the move of the
-- world's origin to the stage, which BeamNG.Earth does only with the physics on: the pause waits for it, the car held
-- still by the run (#63, menuPause.waitFor).

-- Up on the page: opened at `view` when the menu is not up.
local function showLoading(view)
  -- (the page's pause put back if an auto recce from it had taken it back: the rally's prep, #34)
  pcall(menuPause.resume)
  if not menuOpen then M.openMenu(view) end
end

-- After a run was started (runner.start): its steps until the car is at its control. after(ok, why) at the end.
local function stageLoading(ev, stage, kick, after, opts)
  opts = opts or {}
  local _, _, kind = runner.arrivalPoint(stage)
  local where = kind == 'ATC' and 'the time control' or 'the start'
  local ss = menu.ssLabel(ev, stage.id)
  local steps = { 'The map at ' .. where, 'The stage: line, pacenotes, controls, dressing', 'Your car at ' .. where }
  loadScreen.begin({ kind = 'stage', kick = kick, title = (ss and (ss .. ' ') or '') .. stage.name,
    sub = stage.lengthM and string.format('%.1f km', stage.lengthM / 1000) or nil, steps = steps,
    tip = opts.tip, thenView = opts.thenView,
    probe = function()
      local r = runner.current()
      if not r then return 1, nil, nil, 'the run was stopped' end
      if r.state == 'failed' then return 1, nil, nil, tostring(r.error or 'the stage could not be got ready') end
      local s = r.state
      local i = (s == 'travel' and 1) or ((s == 'anchor' or s == 'build') and 2) or (s == 'place' and 3) or 4
      return i, (i - 1) / #steps, steps[math.min(i, #steps)]
    end,
    done = after })
  showLoading(opts.thenView)
end
M._stageLoading = stageLoading

-- A single stage's loading screen: the menu closed at its end; a failure stays on the page with the reason.
local function closeAfter(ok, why)
  if ok then
    if menuOpen then M.closeMenu() end
  else
    message = 'Could not get ready: ' .. tostring(why)
    runner.say(message, 6, 'warning', 'Earth Rally')
  end
end

-- (rallyRun's) a move or a stage loading in a full rally: the screen, then the time card or driving.
rallyRun.ui.loading = function(what, item, stage)
  local r = rallyRun.active()
  if not r then return end
  local kick = r.name
  if what == 'stage' then
    local ev = menu.findEvent(r.eventId)
    if not (ev and stage) then return end
    return stageLoading(ev, stage, kick, function(ok, why)
      if ok then if menuOpen then M.closeMenu() end
      else runner.say('Could not get the stage ready: ' .. tostring(why), 6, 'warning', r.name) M.openMenu('timecard') end
    end, { thenView = 'timecard' })
  end
  -- a move to a stop: the teleport, the car there, then the time card (rallyRun.arrive opens it)
  local label = item and (item.kind == 'start' and 'the start' or item.label) or 'the stop'
  local steps = { 'The map around ' .. (item and item.name or label), 'Your car at ' .. label }
  loadScreen.begin({ kind = 'move', kick = kick .. (what == 'resume' and ' · continuing' or ''),
    title = 'Going to ' .. label, sub = item and item.name or nil, steps = steps, thenView = 'timecard',
    tip = item and item.kind == 'service' and 'Damage is repaired at service. The game saves here.' or nil,
    probe = function()
      local mv = rallyRun.moving()
      if mv then
        local i = earth.ready() and 2 or 1
        return i, (i - 1) / #steps, steps[i]
      end
      return #steps + 1
    end,
    done = function() if rallyRun.active() then M.openMenu('timecard') end end })
  showLoading('timecard')
end

-- (rallyRun's, #40) the time control card: the stage loading behind it, Continue once it and the world are ready.
-- (#64) Its steps start with the check-in (the time in is the moment the car stopped at the board) and the move of
-- the world to the stage (#63); the start time is given when Continue is pressed (runner.continueAtc), so the card
-- says so (tc.startNote) and, once the run has checked in behind it, tc.checkedIn.
rallyRun.ui.atControl = function(tc, stage)
  local steps = { 'Checked in', 'Moving the world to the stage', 'Line, pacenotes, controls',
    'Junctions taped, stage dressed' }
  tc.startNote = 'given when you continue'
  loadScreen.begin({ kind = 'atc', kick = 'Time control · in', title = tostring(tc.ss) .. ' ' .. tostring(tc.name),
    sub = (tc.km and (tc.km .. ' km · ') or '') .. tostring(tc.rally) .. (tc.day and (' · day ' .. tc.day) or ''),
    steps = steps, card = tc, button = 'Continue', thenView = 'timecard',
    probe = function()
      local r = runner.current()
      if not r then return 1, nil, nil, 'the stage was put away' end
      if r.state == 'failed' then return 1, nil, nil, tostring(r.error or 'the stage could not be got ready') end
      local st = r.state
      if r.atcTime then
        tc.checkedIn = true
        tc.startNote = runner.startNote() or tc.startNote
      end
      -- (ready only once checked in: the start time is the check-in's, given again at Continue)
      local i = ((st == 'travel' or st == 'anchor') and 2) or (st == 'build' and 3) or (st == 'place' and 4)
        or ((st == 'toAtc' and not r.atcTime) and 4) or 5
      return i, (i - 1) / #steps, steps[math.min(i, #steps)]
    end,
    done = function(ok, why)
      -- (#64: the start time from now, and "Move up to the start line" said, not before)
      pcall(runner.continueAtc)
      if ok then if menuOpen then M.closeMenu() end
      else runner.say('Could not get the stage ready: ' .. tostring(why), 6, 'warning', tostring(tc.ss)) end
    end })
  showLoading('timecard')
end

-- The page's loading screen, nil with none (polled by EarthRallyLoading.vue).
function M.uiLoading() return loadScreen.ui() end
function M.uiLoadingContinue() return loadScreen.continue() end
-- Ctrl+Alt+K
function M.toggleMenu()
  if menuOpen then return M.closeMenu() end
  -- (a rally's finish card up, the game paused under it, #43: the key takes its Continue -- the card put away)
  local rc = runner.current()
  if rallyRun.active() and rc and rc.inRally and rc.resultsOpen then
    pcall(rallyRun.resultsAction, 'continue')
    return true
  end
  if rallyRun.active() then return M.openMenu('timecard') end   -- (a full rally: its time card)
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
  -- (the page closed under a time control card that is ready: taken as its Continue, #40)
  if not menuOpen then pcall(loadScreen.pageClosed) end
  -- stats: sent while the menu is up (the game is paused there); the menu left with the question still up is a No.
  -- (their own flag, set only here: openMenu/closeMenu set menuOpen before this event comes, so a change of
  -- menuOpen was never seen -- found in game, 2026-11-16)
  local was = statsMenuUp
  statsMenuUp = menuOpen
  if menuOpen and not was then pcall(stats.sessionStart) pcall(stats.flushSoon) pcall(online.forgetBoards) end
  -- (#77) the Leaderboards helper looked for once per menu open: the pop-up if it does not answer
  if menuOpen and not was then helperDone = false pcall(online.probeStart) end
  if was and not menuOpen then pcall(stats.menuClosed) end
  -- Our own full-screen page counts too: it is not called 'menu...' but it is just as much in the way. So does
  -- BeamNG.Earth's world map, a route of its own ('beamngEarthMap', its credits.lua MAP_ROUTE).
  -- 'pause' is the in-game Escape menu in 0.40 ('menu' is the main menu); this check missed it, as BeamNG.Earth's does.
  runner.uiHidden = toState:sub(1, 4) == 'menu' or earthMenuFix.isPause(toState) or toState == 'loading'
    or toState == M.ROUTE or toState == 'beamngEarthMap'
  earthMenuFix.uiState(toState, M.ROUTE)
  menuPause.uiState(toState, M.ROUTE)
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
  add('Corners found / notes written / loaded', tostring(c.cornersFound or '-') .. ' / ' ..
    tostring(c.notesWritten or '-') .. ' / ' .. tostring(c.notesLoaded or '-'))
  if c.calls and c.calls ~= '' then add('Calls', c.calls) end
  if c.voiceStyle then add('Co-driver style', c.voiceStyle) end
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

-- (1.7.0, #29) The full rally's testing tools: long rallies stepped through without driving every metre.
local function drawRally()
  local line = rallyRun.debugLine()
  if not line then return end
  im.Separator()
  im.TextColored(GREEN, 'Full rally (testing)')
  im.TextWrapped(line)
  local r = runner.current()
  if r and r.inRally and r.state == 'running' then
    if im.Button('Jump to 500 m before the finish') then
      message = runner.debugJump(500) and 'Jumped: drive the last 500 m.' or 'Could not jump.'
    end
    im.SameLine()
    if im.Button('100 m') then message = runner.debugJump(100) and 'Jumped: drive the last 100 m.' or 'Could not jump.' end
  end
  if im.Button('Skip the transit (teleport there)') then
    local ok, why = rallyRun.debugSkipTransit()
    message = ok and 'Transit skipped.' or ('Not skipped: ' .. tostring(why))
  end
end

-- (the actions below, shared with the menu page)
local doAction

local function drawWindow()
  im.SetNextWindowSize(im.ImVec2(460, 560), im.Cond_FirstUseEver)
  if not im.Begin('Earth Rally ' .. M.VERSION .. ' (developer)###earthRallyWindow', show) then im.End() return end

  local ok, why = earth.check()
  if not ok then im.TextColored(AMBER, why) end
  for _, f in ipairs(versions.current()) do
    im.TextWrapped(f.text)
    if f.level == 'error' then im.TextColored(AMBER, '(a stage cannot be loaded)') end
  end
  if im.Button('Open the menu') then M.openMenu() end
  im.SameLine()
  if im.Button('HUD preview') then M.previewHud() end
  im.SameLine()
  if im.Button('Reload') then events.list(true) selEvent, selStage = 1, 1 end

  -- The old rally list (rallies, their stages, a stage's buttons), collapsed: the menu does all of it now (#36).
  -- Nothing below reads selEvent / selStage; the run and rally tools work on what is under way.
  if im.CollapsingHeader1('Rallies (old)##earthRallyOldList') then
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
  end
  if message then im.TextWrapped(message) end
  drawRun()
  drawRally()
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
    local many = (d.rallies or 1) > 1      -- (a season pack: pack.lua)
    if d.removed then
      text = d.file .. ' taken out of the import folder (' .. (many and 'its rallies are' or 'its rally is') .. ' kept)'
    elseif d.ok and many then
      text = string.format('%s: %s, %d rallies, %d stages', d.file, tostring(d.name), d.rallies, d.stages)
    elseif d.ok then text = string.format('%s: %s, %d stage%s', d.file, tostring(d.name), d.stages, d.stages == 1 and '' or 's')
    else text = 'Could not import ' .. d.file .. ': ' .. tostring(d.why) end
    if d.ok and d.warnings and #d.warnings > 0 then
      text = text .. string.format(' (%d warning%s: see the log)', #d.warnings, #d.warnings == 1 and '' or 's')
    end
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
  -- (the stage's real SS label from the rally file, or its name alone on a stage the itinerary never runs)
  local name = a.ssLabel and string.format('%s %s', a.ssLabel, tostring(a.stageName)) or tostring(a.stageName)
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

-- (1.7.2) The page's Download step: ticked only for a download BeamNG.Earth took (or one the stage already had),
-- not one it refused. sq.downloaded is set as Download is pressed, before the answer.
local function autoDownloaded(sq)
  return sq ~= nil and sq.downloaded == true and sq.areaId ~= nil and not sq.addRefused
end
-- (1.7.2) A full rally getting its stages ready: the stages left with the one under way, or nil with no prep.
local function prepLeft()
  local pr = rallyRun.preparing()
  if not (pr and type(pr.list) == 'table') then return nil end
  return math.max(1, #pr.list - math.max(1, pr.i or 0) + 1)
end

local autoSeq = nil   -- { ev, stage, ss, phase, t, ready, plan, areaId, downloaded, why, how, tm, leftOff }
-- (1.7.3, item 1) a full rally's one stage looked ahead (stepRallyPrep): { prep, eventId, e = { [stageId] = entry },
-- next, nextI, nextN, waited }; entry: { stage, priced, priceS, plan, needs, had, adding, areaId, addedAt, refused,
-- failed, resolved, taken }
local rallyQ = nil
local queueAheadDownloading   -- (below, with the look-ahead: Stop reads it)

-- The saved area each stage's download went into: autoKey -> { id, name }, kept in the user folder so a second
-- press -- this session or the next -- follows the area it already has instead of adding another. BeamNG.Earth
-- 1.10 dropped its ten-area cap (upstream PR #1264), so nothing else stops a stage piling up copies of itself, each
-- one pinned on the player's disk (the owner had Stage Road three times and Orchard - Shoreline twice, 2026-11-16).
M.AREA_BOOK_FILE = '/settings/earthRally_areas.json'
M.AREA_LOG_EVERY_S = 10      -- a progress line in the log this often while downloading (it was silent: read as a hang)
M.AREA_GONE_S = 10           -- the area missing from BeamNG.Earth's list this long: the player deleted it
local areaBook = nil
local function areaBookLoad()
  if areaBook then return areaBook end
  local ok, t = pcall(function()
    return FS:fileExists(M.AREA_BOOK_FILE) and jsonReadFile(M.AREA_BOOK_FILE) or nil
  end)
  areaBook = (ok and type(t) == 'table' and type(t.areas) == 'table') and t.areas or {}
  return areaBook
end
local function areaBookPut(key, id, name)
  areaBookLoad()[key] = { id = id, name = name }
  local ok, ret = pcall(jsonWriteFile, M.AREA_BOOK_FILE, { version = 1, areas = areaBook }, true)
  if not ok or ret == false then
    log('W', logTag, 'auto recce: could not save the area list: ' .. tostring(ret))
  end
end
-- The status of the area booked for `key`, when BeamNG.Earth still has it; else nil. Matched on the id (BeamNG.Earth
-- never hands one out twice) and the name we booked it under (a stage renamed is a different corridor) -- not on the
-- name BeamNG.Earth shows, which it cuts to 60 characters.
local function areaBookStatus(key, name)
  local b = areaBookLoad()[key]
  if type(b) ~= 'table' or type(b.id) ~= 'string' or b.name ~= name then return nil end
  return earth.areaStatus(b.id)
end
M._areaBookReset = function() areaBook = nil end

local autoSeqStep     -- (declared here: autoDone drives the sequence on, and is defined above it)

-- (1.7.3, item 7) One line in the log per auto recce with each leg's seconds, so a build can be compared with the
-- one before from the log alone, with no driving: price, download (and its MB from the estimate), teleport and
-- settle, the windows, the match. On the game's high-resolution wall clock (autoRecce.wall). A leg that did not
-- happen says "none". A full rally's stage (item 1) was priced and its download added up front, so its download
-- counts from when its area was added, not from when its turn came.
local function wall() return autoRecce.wall() end
local function logTiming(sq, how, ending)
  if not (sq and sq.tm) then return end
  local tm, now = sq.tm, wall()
  local function secs(v) return v and string.format('%.1f s', v) or 'none' end
  local dl = tm.dl or (tm.dl0 and (now - tm.dl0)) or nil
  local go = tm.go or (tm.go0 and (now - tm.go0)) or nil
  log('I', logTag, string.format('auto recce timing: %s: price %s, download %s%s, teleport and settle %s, ' ..
    'windows %s%s, match %s, total %.1f s%s (%s)', tostring(sq.stage.id), secs(tm.price), secs(dl),
    tm.mb and string.format(' (%.1f MB)', tm.mb) or '', secs(go), secs(how and how.windowsS),
    (how and how.windows) and string.format(' (%d)', how.windows) or '',
    (how and how.matchS) and string.format('%.3f s', how.matchS) or 'none', now - (tm.t0 or now),
    tm.queued and ', queued with the rally' or '', tostring(ending or (how and how.kind) or 'ended')))
end

-- (1.3.0 to the first cut of 1.3.1 had an autoFixable() here, to decide whether a refusal was one a download
-- could mend. The order changed -- the ground is priced before the match rather than after it -- so nothing asks
-- that question any more: the estimate's own `missing` decides, and the match happens once and is final.)

-- autoRecce's done callback: the only place the menu learns how one ended.
local function autoDone(ok, matched, why, how)
  local a = autoRun
  autoRun = nil
  if not a then return end
  pcall(stats.record, 'recce_done', { result = ok and 'ok' or 'failed' })
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
      local sq = autoSeq
      autoSeq = nil
      logTiming(sq, how, kind)
      -- (1.7.3, item 4) The landing found no road at the ATC (the road map round the car had not come in yet: every
      -- logged 1.7.1 run said so), so the car was left on the organisers' raw point. The matched file has the ATC on
      -- its road now, with the road's bearing (controls.atc): the car set down from that (runner.faceAtcFrom: before
      -- the board on the road map's road if it is in by now, else on the matched road point, turned along the road,
      -- 1.7.3). Not in a full rally's prep: the next stage's teleport, or the rally's own
      -- move to its start, takes the car away the moment this one is done, so setting it down would be for nothing.
      if sq.leftOff and not rallyRun.preparing() then
        local atc = type(matched) == 'table' and type(matched.controls) == 'table' and matched.controls.atc or nil
        local fok, placed, pHow = pcall(runner.faceAtcFrom, sq.stage, atc)
        log('I', logTag, string.format('auto recce: the car set down from the matched ATC: %s',
          fok and (placed and tostring(pHow) or ('not moved (' .. tostring(pHow) .. ')')) or tostring(placed)))
      end
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
      { eventId = a.eventId, stageId = a.stageId, ss = a.ss, ssLabel = a.ssLabel, kind = kind,
        text = autoText(a, kind, why, how) }
    message = nil
  end
  log('I', logTag, string.format('auto recce of %s: %s (%s)', tostring(a.stageId), kind, tostring(why or 'written')))
end
M._autoDone = autoDone

-- Start the matching leg: the same call the 1.3.0 button made, with the banner and the row mark it sets.
local function autoStartMatch(ev, stage, ss)
  local key = autoKey(ev.id, stage.id)
  autoRun = { eventId = ev.id, stageId = stage.id, stageName = stage.name, ss = ss, ssLabel = menu.ssLabel(ev, stage.id) }
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
      ssLabel = menu.ssLabel(sq.ev, sq.stage.id), kind = kind or autoRecce.FAILED, text = msg }
    message = msg                                   -- (the developer panel as well, which reads this one)
  end
  log('I', logTag, 'auto recce sequence of ' .. tostring(sq.stage.id) .. ': ended (' .. tostring(msg or 'reported')
    .. ')')
  logTiming(sq, sq.how, kind or (sq.how and sq.how.kind) or (msg and autoRecce.FAILED) or nil)
end

-- The sequence, one event at a time. `what` is 'tick', 'planned', 'added', 'answer' or 'matched'.
-- Returns true when it has taken an ending over and the player must not be told yet.
autoSeqStep = function(what, arg)
  local sq = autoSeq
  if not sq then return false end

  -- Go to the stage if it is far, then match. The last two legs, reached once the ground is as good as it is
  -- going to get: downloaded, declined, or nothing missing in the first place.
  --
  -- Going there lands at the stage's ARRIVAL point (runner.arrivalPoint: its ATC when it has one of its own, else
  -- its start), the same place Run stage would take the car. Landing at the start instead skipped any ATC within
  -- about NO_SET_DOWN_M (150 m) of the line: Run stage found the car that near it, left it where it stood
  -- ("driven there"), and the first thing it did was drive past the time control (the user, 2026-11-14: "when you
  -- press run stage, you unintentinaly skip the ATC"). Landing on the ATC point itself is inside
  -- DRIVEN_THERE_MIN_M, and runner.faceAtc sets it down 40 m before the board, on the road, facing it. (Run stage's
  -- own "on the stage" check covers the other ways a car ends up at the start: Go to start, a stopped Recce.)
  local function goThenMatch()
    if sq.tm and sq.tm.dl0 and not sq.tm.dl then sq.tm.dl = wall() - sq.tm.dl0 end
    local lat, lon, kind = runner.arrivalPoint(sq.stage)
    if not lat then lat, lon, kind = sq.stage.line[1][1], sq.stage.line[1][2], 'start' end
    local p = earth.pose()
    local away = (not p) and math.huge or require('earthRally/geo').metres(p.lat, p.lon, lat, lon)
    if away > M.GO_IF_FURTHER_M then
      local tok, terr = earth.teleport(lat, lon, sq.stage.name .. ' ' .. kind)
      if not tok then autoSeqEnd('Could not go to the stage: ' .. tostring(terr)) return end
      sq.phase, sq.t, sq.ready, sq.arrival = M.GOING, 0, 0, kind
      if sq.tm then sq.tm.go0 = wall() end
      return
    end
    sq.phase, sq.t = 'matching', 0
    local ok, why = autoStartMatch(sq.ev, sq.stage, sq.ss)
    if not ok then autoSeqEnd('The auto recce could not start: ' .. tostring(why)) end
  end
  sq.goThenMatch = goThenMatch

  if what == 'planned' then
    local r = arg
    if sq.tm and not sq.tm.price then sq.tm.price = wall() - sq.tm.t0 end
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
    if sq.tm then sq.tm.mb = (r.downloadBytes or 0) / 1e6 end
    log('I', logTag, string.format('auto recce: %s needs %.1f MB of map data (%d of %d item(s) missing)',
      sq.stage.name, (r.downloadBytes or 0) / 1e6, r.missing or 0, r.items or 0))
    return true

  elseif what == 'answer' then
    if arg ~= true then
      -- **Not now stops.** (The user, 2026-11-14: "when I click no to download, it should stop auto recce.
      -- instead it teliports me there and still runs recce".) An earlier cut of this carried on to the teleport
      -- and the match, on the reasoning that the estimate over-asks -- `missing` counts a corridor dilated by two
      -- map cells, wider than the road graph reads -- so declining ought not to cost the chance of a match. That
      -- reasoning was about the feature; being flung across the world after saying no is about the player, and
      -- the player is right. No means no: nothing moves and nothing is matched.
      --
      -- The over-asking is answered a better way: the decline is remembered for this stage, so pressing Auto
      -- recce again goes straight to the stage and matches with whatever is already on disk, with no question.
      -- That is said in as many words below, because a button that does something different the second time has
      -- to tell you so.
      log('I', logTag, 'auto recce: the player declined the download; stopping')
      autoSeqEnd(string.format('%s: nothing downloaded, and the auto recce stopped.', sq.stage.name),
        autoRecce.NODATA)
      return true
    end
    -- Yes, and this stage already has an area from an earlier press: follow that one rather than add the same
    -- corridor again. The press itself is unchanged (priced and asked every time, the user, 2026-11-14); only what
    -- Download does differs, and what it does is the download the player already has. A finished one goes straight
    -- on to the match, carrying its unavailable count if it has one.
    local name = 'Earth Rally: ' .. sq.stage.name
    local had = areaBookStatus(autoKey(sq.ev.id, sq.stage.id), name)
    if sq.tm then sq.tm.dl0 = wall() end
    if had then
      sq.areaId, sq.phase, sq.t, sq.downloaded, sq.logT, sq.seen = had.id, M.DOWNLOADING, 0, true, 0, true
      log('I', logTag, string.format('auto recce: %s already has area %s (%s, %d of %d): using it, not adding '
        .. 'another', sq.stage.name, had.id, tostring(had.state), had.done or 0, had.total or 0))
      return true
    end
    local pts = autoRecce.corridor(sq.stage.line)
    sq.phase, sq.t, sq.downloaded = M.DOWNLOADING, 0, true
    local ok, why = earth.areaAdd(pts, name, function(r) autoSeqStep('added', r) end)
    if not ok then autoSeqEnd('Could not start the download: ' .. tostring(why)) end
    return true

  elseif what == 'queued' then
    -- (1.7.3, item 1) A full rally's stage whose ground was priced, and whose download was added, while the stage
    -- before it ran (queueLookAhead, by stepRallyPrep): no estimate and no question now, only the wait for its own
    -- download, if it has one, and then the same going and matching as a press of the button.
    local e = arg
    if sq.tm then
      sq.tm.price, sq.tm.queued = e.priceS, true
      if e.needs and e.plan then sq.tm.mb = (e.plan.downloadBytes or 0) / 1e6 end
    end
    sq.plan = e.plan
    if e.areaId then
      sq.areaId, sq.phase, sq.t, sq.downloaded, sq.logT, sq.seen = e.areaId, M.DOWNLOADING, 0, true, 0, e.had or nil
      -- (added a while ago: missing from BeamNG.Earth's list now means deleted, not "too fresh to be listed yet", so
      --  the area-gone ending can fire rather than a half-hour wait. The tick says the same once it is that old.)
      sq.addedAt = e.addedAt
      if e.addedAt and wall() - e.addedAt > M.AREA_GONE_S then sq.seen = true end
      if sq.tm then sq.tm.dl0 = e.addedAt or wall() end
      log('I', logTag, string.format('auto recce: %s: following its queued download (area %s)', sq.stage.name,
        tostring(e.areaId)))
      return true
    end
    if e.refused then sq.addRefused = e.refused end
    goThenMatch()
    return true

  elseif what == 'added' then
    local r = arg
    if type(r) ~= 'table' or r.ok ~= true or type(r.id) ~= 'string' then
      -- the refusal worth surfacing rather than working around: the saved areas' share of the cache is full, the
      -- disk has no room, or (BeamNG.Earth before 1.10) all ten slots are taken. The player's to act on. The stage
      -- is still tried with what is here.
      local reason = tostring(type(r) == 'table' and r.error or 'no reason given')
      log('I', logTag, 'auto recce: BeamNG.Earth would not take the area (' .. reason .. ')')
      sq.addRefused = reason
      goThenMatch()
      return true
    end
    sq.areaId, sq.t, sq.logT = r.id, 0, 0
    areaBookPut(autoKey(sq.ev.id, sq.stage.id), r.id, 'Earth Rally: ' .. sq.stage.name)
    log('I', logTag, string.format('auto recce: BeamNG.Earth took the area (%s): downloading', r.id))
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
    elseif sq.areaPaused then
      note = "Its download is paused in BeamNG.Earth's areas: resume it there, then run the auto recce again."
    elseif sq.areaGone then
      note = "Its download was deleted from BeamNG.Earth's areas before it finished."
    elseif (sq.unavailable or 0) > 0 then
      note = string.format('The download finished with %d item(s) nothing could fetch. %s',
        sq.unavailable, tostring(sq.areaMsg or 'Resume that area to try those again.'))
    end
    if not note then
      autoSeqEnd(nil)
      return false              -- nothing to add: autoDone reports the stage's own ending, as 1.3.0 does
    end
    local own = autoText({ ss = sq.ss, ssLabel = menu.ssLabel(sq.ev, sq.stage.id), stageName = sq.stage.name }, arg,
      sq.why, sq.how)
    autoSeqEnd((own and (own .. ' ') or '') .. note, arg)
    return true

  elseif what == 'tick' then
    sq.t = sq.t + (arg or 0)
    -- (1.7.2) the download's own clock, for the page: sq.t starts again when BeamNG.Earth takes the area, which
    -- would put the time shown back to 0:00 a moment into the download
    if sq.phase == M.DOWNLOADING then sq.dlS = (sq.dlS or 0) + (arg or 0) end
    if sq.phase == M.GOING then
      sq.ready = earth.ready() and sq.t > 2 and (sq.ready + (arg or 0)) or 0
      if sq.ready >= runner.TELEPORT_SETTLE_S then
        -- (at the ATC: set down on the road before its board, as Run stage would. Not faceStage, which puts the car
        -- behind the START line -- the very skip this landing exists to avoid)
        local fok, placed, how = pcall(sq.arrival == 'ATC' and runner.faceAtc or runner.faceStage, sq.stage, sq.ev.id)
        if sq.tm and sq.tm.go0 then sq.tm.go = wall() - sq.tm.go0 end
        -- (item 4: left on the raw ATC point, no road there yet: autoDone sets it down from the matched file instead)
        sq.leftOff = (sq.arrival == 'ATC' and not (fok and placed)) or nil
        log('I', logTag, string.format('auto recce: landed at the %s: %s', tostring(sq.arrival),
          fok and (placed and tostring(how) or ('left where it landed' .. (how and (' (' .. tostring(how) .. ')') or '')))
          or tostring(placed)))
        sq.phase, sq.t = 'matching', 0
        local ok, why = autoStartMatch(sq.ev, sq.stage, sq.ss)
        if not ok then autoSeqEnd('The auto recce could not start: ' .. tostring(why)) end
      elseif sq.t > M.WORLD_WAIT_S then
        autoSeqEnd('The world is taking long to load here: try the auto recce again.')
      end
    elseif sq.phase == M.DOWNLOADING and sq.areaId then
      local st = earth.areaStatus(sq.areaId)
      if st or (sq.addedAt and wall() - sq.addedAt > M.AREA_GONE_S) then sq.seen = true end
      -- (1.7.2) when the item count last moved, for the page's "still going" line: the items differ a lot in size,
      -- so the count can sit still for most of a minute while a big one comes down (Perkins: 2 of 59 for 45 s)
      if st and st.done ~= sq.lastDone then sq.lastDone, sq.lastDoneT = st.done, sq.dlS or 0 end
      if st and sq.t - (sq.logT or 0) >= M.AREA_LOG_EVERY_S then
        sq.logT = sq.t
        log('I', logTag, string.format('auto recce: downloading %s: %s, %d of %d item(s), %d s', tostring(sq.areaId),
          tostring(st.state), st.done or 0, st.total or 0, math.floor(sq.t)))
      end
      if st and st.state == 'paused' then
        -- paused by the player in BeamNG.Earth's areas: it will not move until they resume it, so match with what
        -- is here and say so, rather than show "downloading" for half an hour
        log('I', logTag, 'auto recce: area ' .. tostring(sq.areaId) .. ' is paused; matching with what is here')
        sq.areaPaused = true
        goThenMatch()
      elseif st and (st.state == 'done' or st.state == 'failed') then
        -- `done` does not mean every tile arrived: after enough failed passes the rest are counted unavailable and
        -- the area is marked done anyway (measured here: an area finished done with 122 of 1079 unavailable). So
        -- the ground is re-checked by matching rather than trusted, and the area's own message is carried through.
        sq.unavailable, sq.areaMsg = st.unavailable, st.msg
        if (st.unavailable or 0) > 0 then
          log('I', logTag, string.format('auto recce: the download finished with %d item(s) unavailable (%s)',
            st.unavailable, tostring(st.msg)))
        end
        log('I', logTag, string.format('auto recce: the download of %s finished (%d of %d) after %d s',
          tostring(sq.areaId), st.done or 0, st.total or 0, math.floor(sq.t)))
        goThenMatch()
      elseif not st and sq.seen and sq.t > M.AREA_GONE_S then
        -- seen in BeamNG.Earth's list and gone from it now (the player deleted it): waiting would be forever. (Not
        -- before it was ever seen: a fresh add can be missing from the broadcast for a moment.)
        log('I', logTag, 'auto recce: area ' .. tostring(sq.areaId) .. ' is gone; matching with what is here')
        sq.areaGone = true
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
-- queued: (1.7.3) a full rally's stage looked ahead while the stage before it ran (stepRallyPrep's queue entry): no
-- estimate and no question, only its own download's wait. Nothing else passes it: the button is priced and asked
-- every press.
doAction = function(what, eventId, stageId, fromPanel, queued)
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
    -- (a Realistic rally's stage is given up with the recovery key, under Super Rally: stopping it here would be a
    --  free restart)
    local cur, rr = runner.current(), rallyRun.active()
    if cur and cur.inRally and rr and rr.mode == 'realistic' and cur.state == 'running' then
      return res(false, 'In a Realistic rally, give the stage up with the recovery key (Backspace, D-pad right), or leave the rally from its time card.')
    end
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
    -- (1.7.3) the stage under way still downloading its own area: with the look-ahead's, two downloads go on
    local ownDl = autoSeq ~= nil and autoSeq.phase == M.DOWNLOADING
    autoSeq = nil
    -- (autoRecce.cancel does not call the done callback -- a stop is not an ending, and leaves no line behind)
    local stopped = autoRecce.cancel() or hadSeq
    -- (1.7.2) A full rally getting its stages ready runs one auto recce after another (stepRallyPrep), so stopping
    -- only the one under way had the next start a frame later: the player pressed Stop once a stage (the owner,
    -- 2026-11-16: "it should stop all downloads ... otherwise you have to keep clicking it"). Stop now ends the prep
    -- here and now, with the ending those presses reached: prepDone holds out the stages with no line and the rally
    -- goes on -- or, with no stage left to drive, ends, as it always has. Not rallyRun.quit: a rally just started is
    -- not saved until its first service, so leaving one that still has stages would throw it away, and Save and
    -- quit has its own button and confirm. Ended now rather than on the next frame, so the message says what
    -- happened, and no frame is left with a prep that has stopped but still shows a stage under way.
    -- A download BeamNG.Earth already took carries on in its Areas: its API cannot pause or remove one.
    if rallyRun.preparing() then
      -- (1.7.3) the next stage's look-ahead: its area, if one was added, downloads on too, so it is named
      local ahead = queueAheadDownloading()
      rallyQ = nil
      local held, ended = rallyRun.prepDone()
      log('I', logTag, string.format('auto recce: stopped with the rally prep: %d stage(s) held out%s', held or 0,
        ended and ', none left to drive: the rally ended' or ''))
      local msg = ended and 'Auto recce stopped. No stage has its line yet, so the rally ended.'
        or (held or 0) > 0 and string.format('Auto recce stopped. %d %s with no line held out of the rally.', held,
          held == 1 and 'stage' or 'stages')
        or 'Auto recce stopped.'
      -- (the look-ahead starts only once the stage under way is past its download, so with it named the plural
      --  is for the case where that stage is following an area of its own still coming down)
      if ownDl and ahead then
        msg = msg .. string.format(" Map downloads already started carry on in BeamNG.Earth's Areas, %s's too.", ahead)
      elseif ahead then
        msg = msg .. string.format(" %s's map download carries on in BeamNG.Earth's Areas.", ahead)
      elseif hadSeq then msg = msg .. " A map download already started carries on in BeamNG.Earth's Areas." end
      local out = res(true, msg)
      out.rallyEnded = ended == true
      return out
    end
    return res(stopped, stopped and string.format('Auto recce of %s stopped.',
      was and was.stageName or 'the stage') or 'No auto recce is running.')
  end
  if not stage then return res(false, 'That stage is not on this computer any more.') end
  -- (1.7.0) a full rally under way holds the car: no other stage, recce or teleport until it is quit (its time card)
  local rr = rallyRun.active()
  if rr and not rr.done and what ~= 'reset' and not (what == 'autoRecce' and rallyRun.preparing()) then
    return res(false, 'A full rally is under way: leave it from its time card first.')
  end
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
  -- (a recce or an auto recce takes the car elsewhere or drives the stage: Route to start is not armed through it)
  if what == 'recce' or what == 'goStart' or what == 'autoRecce' then runner.disarmApproach(what) end
  -- (they move the car or load the world: the menu's pause request taken back for them, BeamNG.Earth's holds take the
  --  game's plain pause only when it is not paused already, and not put in again until the page is next opened)
  -- (Drive, Go to start and Recce keep the page up on a loading screen now, the game paused under it: 1.7.0, #49)
  if what == 'autoRecce' then pcall(menuPause.suspend) end
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
    autoSeq = { ev = ev, stage = stage, ss = ss, phase = 'planning', t = 0, ready = 0, tm = { t0 = wall() } }
    if type(queued) == 'table' then
      autoSeqStep('queued', queued)
      if not autoSeq then return res(false, (autoLines[autoKey(ev.id, stage.id)] or {}).text or
        'the auto recce could not be started') end
      return res(true, string.format('Auto recce of %s: its map data was looked at with the stage before it.',
        stage.name))
    end
    -- The estimate first, because it needs no anchor: `areaPlan` takes lat/lon on the server and knows nothing of
    -- the player's frame, so the ground can be priced from where the player is standing. That is what lets the
    -- question be asked before they are teleported across the world.
    --
    -- **Every press does the same thing** (the user, 2026-11-14: "none of this re ordering of what the button
    -- does nonsense the seconbd pressa should work the same as the firest"). An earlier cut remembered a Not now
    -- and made the next press skip the question: one button with two behaviours and no way to tell which you were
    -- about to get. Nothing is remembered -- press it again and it asks again.
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
      return res(true, string.format('Auto recce of %s: going to the %s first.', stage.name,
        autoSeq.arrival == 'ATC' and 'time control' or 'start'))
    end
    local pr = autoRecce.progress() or {}
    return res(true, string.format('Auto recce of %s: %d windows. %s', stage.name, pr.windows or 0,
      earth.hasAreaRoute() and 'It reads the map data on your disk, and asks before downloading any it needs.'
        or 'It reads only the map data already on your disk and downloads nothing.'))
  end
  if what == 'drive' then
    local ok, why = runner.start(ev, stage)
    if ok and not fromPanel then stageLoading(ev, stage, 'Drive stage · ' .. tostring(ev.name), closeAfter) end
    return res(ok, ok and nil or why, fromPanel)
  elseif what == 'route' then
    local lat, lon, kind = runner.arrivalPoint(stage)
    local ok, why = false, 'the stage has no start'
    if lat then ok, why = earth.gpsSet(lat, lon, stage.name .. ' ' .. kind) end
    -- (GitHub #19: the stage gets itself ready as the car comes near, runner.armApproach)
    -- (only for a stage with a line to run on, and a BeamNG.Earth whose GPS can be read back: without it a route
    --  cleared or changed could not be told, and the stage would load whenever the car came by; the route alone then)
    -- (a new route replaces any stage armed before, even when this one cannot be armed itself)
    if ok then runner.disarmApproach('route set elsewhere') end
    local armed = ok and events.stageLine(ev.id, stage.id, stage) ~= nil and runner.armApproach(ev, stage)
    if ok then runner.say(armed and 'Follow the arrows on the road: the stage gets ready as you get near.'
      or 'Follow the arrows on the road.', 5, 'info', 'Route set to ' .. stage.name .. "'s " .. kind) end
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
      if not fromPanel then
        local steps = { 'The map at the start', 'Your car at the start' }
        loadScreen.begin({ kind = 'stage', kick = (what == 'recce' and 'Recce · ' or 'Go to start · ') .. tostring(ev.name),
          title = stage.name, steps = steps, done = closeAfter,
          probe = function()
            if facing and facing.stage == stage then
              local i = earth.ready() and 2 or 1
              return i, (i - 1) / #steps, steps[i]
            end
            return #steps + 1
          end })
      end
    end
    if what == 'recce' then
      recce.start(ev, stage)
      runner.say('Follow the orange line on the road to the flying finish (the green ball); the recce saves itself there.',
        8, 'info', 'Recce: ' .. stage.name)
      return res(true, 'Recce started.', not far)
    end
    return res(true, 'Waiting for the world to load...', false)
  end
  return res(false, 'unknown action ' .. tostring(what))
end
M._action = doAction

function M.uiAction(what, eventId, stageId)
  local ok, r = pcall(doAction, what, eventId, stageId)
  if not ok then
    log('E', logTag, 'menu action ' .. tostring(what) .. ': ' .. tostring(r))   -- (stats: recorded by stats.watchLog)
    return { ok = false, message = tostring(r) }
  end
  if r.message then message = r.message end
  return r
end

-- The results card's buttons: 'next', 'retry', 'menu' (the rally's page), 'close'.
function M.uiResults(what)
  -- (#58: "Load the stage?" at the time control's board; #69: Recover? on a transit -- no stage run to route by)
  if what == 'load' or what == 'notYet' then
    local ok, why = rallyRun.answerLoad(what)
    if not ok and why then runner.say(tostring(why), 4, 'warning') end
    return { ok = ok == true, message = why }
  end
  local q = rallyRun.askInfo()
  if q and q.ask and (what == 'recover' or what == 'keep') then
    local ok, why = rallyRun.answer(what)
    if not ok and why then runner.say(tostring(why), 4, 'warning') end
    return { ok = ok == true, message = why }
  end
  local r = runner.current()
  if r and r.inRally then
    -- (a full rally's card: Continue to the time card, Restart in Casual, Close; the Recover? question's answers)
    local ok, why
    if what == 'recover' or what == 'keep' then ok, why = rallyRun.answer(what)
    else ok, why = rallyRun.resultsAction(what) end
    if not ok and why then runner.say(tostring(why), 4, 'warning') end
    return { ok = ok == true, message = why }
  end
  local eventId = r and r.event and r.event.id
  local ok, why = runner.resultsAction(what)
  if what == 'menu' then M.openMenu('rally', eventId) end
  -- (Next stage / Retry: the new run's loading screen, #49)
  local nr = runner.current()
  if ok and (what == 'next' or what == 'retry') and nr and nr.state == 'travel' then
    stageLoading(nr.event, nr.stage, (what == 'retry' and 'Retry · ' or 'Next stage · ') .. tostring(nr.event.name),
      closeAfter)
  end
  if not ok and why then runner.say(tostring(why), 4, 'warning') end
  return { ok = ok == true, message = why }
end

------------------------------------------------------------------------------------------ the menu page's data

local function runSummary()
  local r = runner.current()
  local out = {}
  if r then
    out.run = { state = r.state, eventId = r.event.id, stageId = r.stage.id, stageName = r.stage.name, ss = r.ss,
      ssLabel = menu.ssLabel(r.event, r.stage.id),
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
      ss = autoRun.ss, ssLabel = autoRun.ssLabel, windows = p.windows, done = p.done, phase = 'matching',
      downloaded = autoDownloaded(autoSeq),
      -- (the step along the line, for the page's sentence: a window is only trustworthy CORRIDOR_M inside its edge)
      stepM = math.floor(autoRecce.RADIUS_M - autoRecce.CORRIDOR_M) }
  elseif autoSeq then
    -- the legs with no window count of their own: going to the stage, pricing the ground, waiting on the player,
    -- downloading. The row and the banner follow `phase`, so one press reads as one thing throughout.
    local st = autoSeq.areaId and earth.areaStatus(autoSeq.areaId) or nil
    out.auto = { eventId = autoSeq.ev.id, stageId = autoSeq.stage.id, stageName = autoSeq.stage.name,
      ss = autoSeq.ss, ssLabel = menu.ssLabel(autoSeq.ev, autoSeq.stage.id), phase = autoSeq.phase,
      waitedS = math.floor((autoSeq.phase == M.DOWNLOADING and autoSeq.dlS or autoSeq.t) or 0),
      downloaded = autoDownloaded(autoSeq),
      -- (1.7.2, the page's bar) the size asked about, and how long the item count has sat still (nil until the
      -- area has been seen: nothing has been counted yet, so nothing has sat still)
      bytes = autoSeq.plan and autoSeq.plan.downloadBytes or nil,
      quietS = autoSeq.phase == M.DOWNLOADING and autoSeq.lastDoneT
        and math.floor((autoSeq.dlS or 0) - autoSeq.lastDoneT) or nil }
    if autoSeq.phase == M.ASKING and autoSeq.plan then
      out.auto.ask = { bytes = autoSeq.plan.downloadBytes, diskBytes = autoSeq.plan.diskBytes,
        km = autoSeq.plan.km, items = autoSeq.plan.items, missing = autoSeq.plan.missing }
    end
    if st then
      out.auto.area = { state = st.state, done = st.done, total = st.total, unavailable = st.unavailable,
        msg = st.msg, name = st.name }
    end
  end
  -- (1.7.2) a full rally getting its stages ready: how many are left with this one, so Stop can say it stops them all
  if out.auto then out.auto.prepLeft = prepLeft() end
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
  -- what changed under the mod since it was built (versions.lua): nothing to show in the normal case
  s.versionNotes = versions.notes()
  s.settings = settings.uiState()
  s.stats = stats.uiState()
  s.rallies = menu.rallies(importer.lastReports)
  -- the Rallies page: seasons, loose rallies and single stages (menu.home); `rallies` above stays for the pause
  -- menu's tab, which lists every rally flat
  s.home = menu.home(importer.lastReports)
  s.importFolder = importer.folderPath()
  s.lastImport = lastImport
  s.message = message
  local a = rallyRun.active()
  s.rallyActive = a and { id = a.eventId, name = a.name, done = a.done or nil } or nil
  s.helperPrompt = M.helperPromptWanted() or nil
  return s
end

-- (#77) The pop-up asking the player to install the Leaderboards helper: it did not answer when the menu opened,
-- "Don't show this again" was not ticked on this version, no stage, full rally or recce is running, and the stats question
-- is not up (online.promptWanted).
local helperWhy = nil
function M.helperPromptWanted()
  if not menuOpen or helperDone then return false end
  local probe = online.probeResult()
  if probe ~= 'no' then
    -- (the helper answered, or the check is under way or too early after the game started: said once in the log)
    if probe ~= nil and probe ~= helperWhy then helperWhy = probe log('I', logTag, 'helper pop-up held: probe ' .. tostring(probe)) end
    return false
  end
  -- (on a stage: its countdown or timed section, not a run driving to or waiting at the start -- found in test,
  -- 2026-11-18, #77: a stage picked earlier held it back for good)
  local st = runner.current() and runner.state() or 'idle'
  local onStage = st == 'countdown' or st == 'launched' or st == 'running'
  local running = onStage or rallyRun.active() ~= nil or recce.active() or autoRecce.active()
  local okC, consent = pcall(stats.consent)
  local ok, want = pcall(online.promptWanted, { probe = online.probeResult(), version = M.VERSION,
    dismissedFor = online.promptDismissedFor(), running = running, done = helperDone,
    consent = settings.get('onlineBoard') == true and okC and consent == 'ask' })
  -- (why it shows or not, once per menu open, for the log)
  local why = string.format('probe %s, run %s, rally %s, recce %s, dismissed for %s', tostring(online.probeResult()), st,
    tostring(rallyRun.active() ~= nil), tostring(recce.active() or autoRecce.active()), tostring(online.promptDismissedFor()))
  if why ~= helperWhy then helperWhy = why log('I', logTag, 'helper pop-up ' .. ((ok and want) and 'shown' or 'held') .. ': ' .. why) end
  return ok and want == true
end

-- The pop-up's Got it: hidden until the next menu open; with "Don't show this again" ticked, until another version.
function M.uiHelperPrompt(what, dontShow)
  if what == 'close' then
    helperDone = true
    if dontShow == true then online.promptDismiss(M.VERSION) end
  end
  return { ok = true }
end

-- The page to open at, once (the menu page asks as it opens): { view, eventId, stageId } or nil.
function M.uiOpenAt()
  local at = openAt
  openAt = nil
  return at
end

function M.uiRally(eventId)
  local out = menu.rally(eventId, importer.lastReports, earth.hasRoadGraph())
  if not out then return { missing = true, id = eventId } end
  for k, v in pairs(runSummary()) do out[k] = v end
  out.autoLines = autoLinesFor(eventId)
  -- (1.7.0) the full rally: whether it can be run (an event file), the one saved, your best finished one
  local e = menu.findEvent(eventId)
  out.fullRally = rally.canRun(e) or nil
  local okS, saved = pcall(rallyRun.saved, eventId)
  out.rallySaved = okS and saved or nil
  local okF, fin = pcall(rallyRun.resultsFor, eventId)
  out.rallyFinished = okF and fin or nil
  local a = rallyRun.active()
  out.rallyActive = a and { id = a.eventId, name = a.name, done = a.done or nil } or nil
  return out
end

-- A season's page (menu.season): its rounds and standings.
function M.uiSeason(seasonId)
  local out = menu.season(seasonId)
  if not out then return { missing = true, id = seasonId } end
  for k, v in pairs(runSummary()) do out[k] = v end
  return out
end

-- pass: the leaderboard's pass ('SS4'), nil for the one you place best on
function M.uiStage(eventId, stageId, pass)
  local _, stage = menu.findStage(eventId, stageId)
  if not stage then return { missing = true, eventId = eventId, id = stageId } end   -- (ids: the page tells whose)
  local _, _, arrival = runner.arrivalPoint(stage)
  local out = menu.stage(eventId, stageId, arrival, earth.hasRoadGraph(), pass)
  for k, v in pairs(runSummary()) do out[k] = v end
  out.autoLine = autoLines[autoKey(eventId, stageId)]
  return out
end

function M.uiSet(key, value) return settings.set(key, value) end

------------------------------------------------------------------------------------------ the online board

-- A stage as the online board knows it (online.stageDesc): where it starts and finishes on the line it is timed on.
local function onlineDesc(eventId, stageId)
  local e, stage = menu.findStage(eventId, stageId)
  if not stage then return nil end
  local info = events.stageLineInfo(eventId, stageId, stage)
  if not info then return nil end
  return online.stageDesc(e and e.name, stage.name, info.start, info.finish, info.lengthM)
end

-- The stage page's Online tab: { status, board = { data, error, asking }, last = the last run sent }.
-- board: 'stock' | 'open'.
function M.uiOnline(eventId, stageId, board, force)
  -- (no board picked yet: the class of the car being driven, #74)
  local b = board
  if b ~= 'open' and b ~= 'stock' then
    local cv = rawget(_G, 'core_vehicles')
    local okD, d = false, nil
    if cv and cv.getCurrentVehicleDetails then okD, d = pcall(cv.getCurrentVehicleDetails) end
    local okB, cls = false, nil
    if okD and type(d) == 'table' and type(d.current) == 'table' and d.current.key then okB, cls = pcall(online.boardFor, d) end
    b = (okB and cls) or 'stock'    -- (no car: Stock)
  end
  local out = { status = online.status(), boardName = b, naming = online.lastRegister }
  if out.status.on then
    local desc = onlineDesc(eventId, stageId)
    out.hasLine = desc ~= nil
    out.board = desc and online.board(desc, b, force == true) or nil
    -- (the last run sent, on its own stage's board only)
    local last = online.lastResult
    if desc and last and last.stageKey == online.stageKey(desc) then out.last = last end
  end
  return out
end

-- A name for the online board (the first one makes the player). Answered on the next uiOnline (naming).
function M.uiOnlineName(name)
  online.lastRegister = { asking = true }
  online.register(tostring(name or ''), function(r)
    online.lastRegister = { ok = r.ok, error = r.error }
  end)
  return { ok = true }
end

------------------------------------------------------------------------------------------ the full rally (1.7.0)

-- The start screen's data (rallyRun.startInfo).
function M.uiRallyStart(eventId)
  local ok, r = pcall(rallyRun.startInfo, eventId)
  if not ok then log('E', logTag, 'rally start: ' .. tostring(r)) return { missing = true, id = eventId } end
  return r
end

-- The time card's data (rallyRun.uiCard), or { none = true } with no rally.
function M.uiRallyCard()
  local ok, r = pcall(rallyRun.uiCard)
  if not ok then log('E', logTag, 'time card: ' .. tostring(r)) return { none = true, error = tostring(r) } end
  -- (the stages being got ready: the one in progress's auto recce, for the tracker, #34)
  if r and r.prep then
    local okA, sum = pcall(runSummary)
    r.prep.auto = okA and sum and sum.auto or nil
    -- (1.7.3, item 1) a stage whose turn it is but whose look-ahead estimate or add is not answered yet is checking
    -- its map data, not "starting" (with the stages left, for Stop all, as runSummary gives the stage under way)
    local q = rallyQ
    if q and q.prep == rallyRun.preparing() and not r.prep.auto and q.next then
      local rr = rallyRun.active()
      r.prep.auto = { phase = 'planning', eventId = rr and rr.eventId, stageId = q.next.id, stageName = q.next.name,
        prepLeft = prepLeft() }
    end
  end
  return r or { none = true }
end

-- The full rally's buttons: start (opts: mode, class, cancelled), resume, go (out of service, on to the next stage),
-- quit (Save and quit: its save kept), abandon (Retire: its save deleted), endNew / endDrive (#71, the finished card:
-- done with the rally, kept as finished; the page then opens Home, or the menu closes to plain free roam).
-- Returns { ok, message, view }.
function M.uiRallyAction(what, eventId, opts)
  local function go(ok, why, view)
    if not ok and why then message = why end
    return { ok = ok == true, message = why, view = view }
  end
  local ok, r = pcall(function()
    if what == 'start' then
      if runner.current() and runner.state() ~= 'finished' and runner.state() ~= 'failed' then
        return go(false, 'A run is under way: stop it first.')
      end
      if recce.active() or autoRecce.active() or autoSeq then return go(false, 'A recce is under way: finish it first.') end
      local okS, why = rallyRun.start(eventId, type(opts) == 'table' and opts or {})
      return go(okS, why, okS and 'timecard' or nil)
    elseif what == 'resume' then
      if recce.active() or autoRecce.active() or autoSeq then return go(false, 'A recce is under way: finish it first.') end
      local okS, why = rallyRun.resume(eventId)
      return go(okS, why, okS and 'timecard' or nil)
    elseif what == 'go' then
      local okS, why = rallyRun.goNext()
      -- (not when Go arrived at a stop at once -- one with no place on the map: its card is the next step)
      local card = okS and rallyRun.uiCard()
      if okS and menuOpen and not (card and card.phase == 'stop') and not loadScreen.active() then M.closeMenu() end
      return go(okS, why)
    elseif what == 'quit' or what == 'abandon' then
      -- (left while the stages are being got ready: the auto recce under way stops with it)
      local act = rallyRun.active()
      if rallyRun.preparing() and act and act.eventId == eventId then
        autoSeq, rallyQ = nil, nil
        if autoRecce.active() then autoRun = nil; pcall(autoRecce.cancel) end
      end
    end
    if what == 'endNew' or what == 'endDrive' then
      local okE, why = rallyRun.endRally()
      if okE and what == 'endDrive' and menuOpen then M.closeMenu() end
      return go(okE, why, okE and what == 'endNew' and 'home' or nil)
    end
    if what == 'quit' then              -- Save and quit: continue later from the last service
      rallyRun.quit()
      return go(true, nil, 'rally')
    elseif what == 'abandon' then       -- Retire: the saved rally deleted
      rallyRun.abandon(eventId)
      return go(true, nil, 'rally')
    end
    return go(false, 'unknown rally action ' .. tostring(what))
  end)
  if not ok then log('E', logTag, 'rally action ' .. tostring(what) .. ': ' .. tostring(r)) return { ok = false, message = tostring(r) } end
  return r
end

-- Settings > Privacy and the first-open question (EarthRallyPrivacy.vue, EarthRally.vue): 'yes' / 'no' (the
-- answer, or the switch), 'shown' (the question came up), 'openFolder', 'report' (a = what the player wrote, b = save the log).
function M.uiStats(what, a, b)
  local ok, r = pcall(function()
    if what == 'yes' or what == 'no' then stats.answer(what == 'yes') if what == 'yes' then stats.flushSoon() end
    elseif what == 'shown' then stats.prompting()     -- (the question is on screen: leaving now is a No)
    elseif what == 'hidden' then stats.unprompt()     -- (it went without an answer)
    elseif what == 'openFolder' then stats.openFolder()
    elseif what == 'report' then
      local cur = runner.current()
      local env = versions.env and versions.env(M.VERSION) or {}
      return report.open(a, b == true, { mod = M.VERSION, game = rawget(_G, 'beamng_version'),
        earth = env.earth and (tostring(env.earth.major) .. '.' .. tostring(env.earth.minor)) or nil,
        stage = cur and cur.stage and ((cur.event and cur.event.name or '?') .. ' / ' .. tostring(cur.stage.name)) or nil })
    end
    return { ok = true }
  end)
  if not ok then log('E', logTag, 'stats ' .. tostring(what) .. ': ' .. tostring(r)) return { ok = false, message = tostring(r) } end
  r.stats = stats.uiState()
  return r
end

------------------------------------------------------------------------------------------ the HUD's streams

local streamT, streamOn, inactiveSent = 0, false, true
local askSentKey = nil      -- (the rally question last sent with no run on: #58, #69)
local hudT, slowT, slowSample, rlKey, hudKey, streamRun = 0, 0, nil, nil, nil, nil
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

-- A Route to start armed with no run on (1.6.2): our HUD is not on screen (it lives in the stage layout), so the
-- line goes through the game's Messages app, in every layout's top-left apps: one message of our own category,
-- replaced as the distance changes (0.1 km, hudFrame.approachKey), re-sent before it times out, cleared once the
-- route is disarmed, the stage loads or a menu is up.
M.ROUTE_MSG_CATEGORY = 'earthRallyRoute'   -- (the Messages app reads a category as a regular expression)
M.ROUTE_MSG_S = 2
local routeMsgKey, routeMsgT = nil, 0
local routeAp, routeApKey = nil, nil
local function routeMessage(gh, dt, on)
  local ap = on and not runner.uiHidden and (runner.approachInfo() or rallyRun.transitInfo()) or nil
  local units, key
  if ap and ap == routeAp then key = routeApKey
  elseif ap then units = settings.get('units'); key = hudFrame.approachKey(ap, units); routeAp, routeApKey = ap, key
  else routeAp, routeApKey = nil, nil end
  routeMsgT = routeMsgT + (dt or 0)
  if key == routeMsgKey and (not key or routeMsgT < M.ROUTE_MSG_S) then return end
  routeMsgKey, routeMsgT = key, 0
  if not gh.trigger then return end
  if ap then
    pcall(gh.trigger, 'Message', { msg = hudFrame.approachText(ap, units or settings.get('units')), ttl = M.ROUTE_MSG_S * 2 + 1,
      category = M.ROUTE_MSG_CATEGORY, icon = 'raceFlag' })
  else
    pcall(gh.trigger, 'Message', { msg = '', category = M.ROUTE_MSG_CATEGORY, clear = true })
  end
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
  routeMessage(gh, dt, over)
  -- (#58, #69: a rally's question with no stage on screen -- "Load the stage?", Recover? on a transit: our stream
  -- carries it, sent when it changes and at the floor's pace)
  local okQ, q = pcall(rallyRun.askInfo)
  if over and okQ and q then
    hudT = hudT + dt
    local key = tostring(q.key) .. '|' .. tostring(runner.uiHidden)
    if key ~= askSentKey or hudT >= M.STREAM_FLOOR_S then
      askSentKey, hudT = key, 0
      local _, ours = runner.uiFrame()
      gh.queueStream('earthRally', ours)
      log('I', logTag, M.streamsLine(nil, ours))
    end
    inactiveSent = false
    return
  end
  askSentKey = nil
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
  streamT, hudT, slowT = streamT + dt, hudT + dt, slowT + dt
  local s = r.state
  -- (a new run is fresh too, in whatever state: its first frame is sent at once)
  local fresh = s ~= streamOn or r ~= streamRun
  streamRun = r
  -- (1.6.1: each message re-draws the apps, so a stream is sent when what it shows changes (runner.uiKeys), not on
  -- a timer: the stock stage time's tenths, the countdown's seconds, km done, the cards. Both at once on a new
  -- state, and each at least every STREAM_FLOOR_S, which also carries what the keys leave out: BeamNG.Earth's place,
  -- banner and loading. Where a distance in metres moves every frame, at most once per STREAM_GAP_S / HUD_GAP_S)
  -- (every frame inside the start zone or near the stop: the stock 'staged' / 'stop' badge follows the car there)
  local closeIn = (s == 'toStart' and r.zone ~= nil)
    or (s == 'toStop' and (r.toControlM or 1e9) < (runner.STOP_CONTROL_RADIUS_M or 25) + 5)
  if fresh or closeIn or not slowSample or slowT >= M.SLOW_SAMPLE_S then slowT, slowSample = 0, runner.uiSlow() end
  local kr, kh = runner.uiKeys(slowSample)
  local gapR = (s == 'running' or s == 'waitStart') and 0 or M.STREAM_GAP_S
  local gapH = (s == 'toAtc' or s == 'toStart' or s == 'toStop' or s == 'travel') and M.HUD_GAP_S
    or (s == 'running' and r.offRoute) and M.ARROW_GAP_S or 0
  local rlDue = fresh or streamT >= M.STREAM_FLOOR_S or (kr ~= rlKey and streamT >= gapR)
  local hudDue = fresh or hudT >= M.STREAM_FLOOR_S or (kh ~= hudKey and hudT >= gapH)
  if M.STREAM_FIXED_HZ then rlDue, hudDue = fresh or streamT >= 1 / M.STREAM_FIXED_HZ, fresh or hudT >= 1 / M.STREAM_FIXED_HZ end
  if not (rlDue or hudDue) then return end
  -- (only the stock stream due, and the game's own rally mode has it: nothing of ours to send this time)
  if not hudDue and not fresh and extensions and extensions.isExtensionLoaded
    and extensions.isExtensionLoaded('gameplay_rallyLoop') then
    streamT, rlKey = 0, kr
    return
  end
  streamOn = s
  local rl, ours = runner.uiFrame()
  if rlDue then
    streamT, rlKey = 0, kr
    if rl then gh.queueStream('rallyLoop', rl) end
  end
  if hudDue then
    hudT, hudKey = 0, kh
    gh.queueStream('earthRally', ours)
    local key = M.streamsKey(rl, ours)
    if key ~= streamLogKey then
      streamLogKey = key
      log('I', logTag, M.streamsLine(rl, ours))
    end
  end
end
M._sendStreams = sendStreams

------------------------------------------------------------------------------------------ hooks

-- (1.7.0, #23) A full rally getting its stages ready: the auto recce run on each stage with no line, one after the
-- other, its download question answered yes (the player asked for the rally), then the rally told.
--
-- (1.7.3, item 1, docs/plan-recce-speed.md) One stage looked ahead. Once a stage under way has LEFT its download
-- (going there, settling or matching; or nothing to download), the NEXT stage on the list is priced (areaPlan needs
-- no anchor) and, with ground missing, its area added: the next stage downloads while this one teleports, settles
-- and asks its windows. Not sooner, for two reasons. BeamNG.Earth downloads one area at a time, in the order they
-- were added, so an area added ahead of this stage's own would hold this stage up for the whole of the next one's
-- download. And neighbouring stages share ground: priced before this stage's download finished, the next stage
-- counts the shared items as missing and gets a second area over the same ground. Only that one: at most one look-ahead is out at a time, so Stop or leaving the
-- rally leaves at most one download the player has not reached yet (the owner, 2026-11-17: "keep, made safer"; the
-- first cut priced and added every stage at once). At its turn the stage follows its own download. A look-ahead
-- whose estimate failed or timed out is no answer: the stage is priced again at its turn, the 1.7.0 way, its
-- question answered yes. A stage that already has an area in the area book follows that one, as a press of the
-- button does, so a rally run twice adds nothing twice. Without the area capability there is no look-ahead. The
-- single stage's button is untouched: priced and asked every press.
M.QUEUE_WAIT_S = 300         -- a look-ahead not settled this long after its stage's turn came: given up (below)
local prepWas = nil
-- (rallyQ: declared with autoSeq, above, as uiRallyCard and Stop read it too)

-- This look-ahead's answer still wanted: the same prep, the same queue, not settled or given up on.
local function queueLive(q, e)
  return rallyQ == q and q.prep == rallyRun.preparing() and not e.resolved
end

-- Add the look-ahead's area, its estimate having said ground is missing.
local function queueAdd(q, e)
  local name = 'Earth Rally: ' .. e.stage.name
  local key = autoKey(q.eventId, e.stage.id)
  e.adding = true
  local ok, why = earth.areaAdd(autoRecce.corridor(e.stage.line), name, function(r)
    local took = type(r) == 'table' and r.ok == true and type(r.id) == 'string'
    -- (booked whatever became of the rally since: the area is in the player's list now, and the next press or the
    --  next rally must follow it rather than add another)
    if took then areaBookPut(key, r.id, name) end
    if not queueLive(q, e) then
      if took then log('I', logTag, string.format('rally: %s: BeamNG.Earth took the area (%s) after the look-ahead '
        .. 'was given up: booked for the next press', e.stage.name, r.id)) end
      return
    end
    e.adding = false
    if took then
      e.areaId, e.addedAt = r.id, wall()
      log('I', logTag, string.format('rally: %s: BeamNG.Earth took the area (%s): downloading ahead', e.stage.name,
        r.id))
    else
      e.refused = tostring(type(r) == 'table' and r.error or 'no reason given')
      log('I', logTag, string.format('rally: %s: BeamNG.Earth would not take the area (%s)', e.stage.name, e.refused))
    end
    e.resolved = true
  end)
  if not ok and queueLive(q, e) then
    e.adding, e.refused, e.resolved = false, tostring(why or 'the download could not be started'), true
  end
end

-- Price the stage after the one under way, once, if it has no entry yet. Called every frame while a stage's own
-- auto recce runs, once lookAheadDue says that stage is past its download.
local function queueLookAhead(q)
  local pr = q.prep
  local st = pr.list and pr.list[(pr.i or 0) + 1]
  if not (st and st.line) or q.e[st.id] then return end
  local e = { stage = st }
  q.e[st.id] = e
  local t0 = wall()
  log('I', logTag, string.format('rally: pricing the map data of %s ahead of its turn', tostring(st.name)))
  local function priced(r)
    if e.priced or not queueLive(q, e) then return end
    e.priced, e.priceS = true, wall() - t0
    if type(r) ~= 'table' or r.ok ~= true or type(r.downloadBytes) ~= 'number' then
      -- (timed out or failed: no answer, which is not "nothing missing". Priced again at its turn, the 1.7.0 way.)
      e.failed, e.resolved = tostring(type(r) == 'table' and r.error or r), true
      log('I', logTag, string.format('rally: %s: no estimate ahead (%s): priced again at its turn', st.name, e.failed))
      return
    end
    e.plan = r
    if (r.missing or 0) <= 0 or r.downloadBytes <= 0 then e.resolved = true return end
    e.needs = true
    log('I', logTag, string.format('rally: %s needs %.1f MB of map data (%d of %d item(s) missing)', st.name,
      r.downloadBytes / 1e6, r.missing or 0, r.items or 0))
    local had = areaBookStatus(autoKey(q.eventId, st.id), 'Earth Rally: ' .. st.name)
    if had then
      e.areaId, e.had, e.addedAt, e.resolved = had.id, true, wall(), true
      log('I', logTag, string.format('rally: %s already has area %s: using it, not adding another', st.name, had.id))
      return
    end
    queueAdd(q, e)
  end
  local pts = autoRecce.corridor(st.line)
  local ok, why = false, 'no corridor'
  if pts then ok, why = earth.areaPlan(pts, priced) end
  if not ok then priced({ ok = false, error = tostring(why or 'BeamNG.Earth refused the estimate') }) end
end

-- The stage under way has left its download (see above): going there, settling or matching. Its estimate saying
-- nothing is missing, failing, or its add refused all go straight on to going or matching too.
local function lookAheadDue()
  if not autoSeq then return autoRecce.active() end
  return autoSeq.phase == M.GOING or autoSeq.phase == 'matching'
end
M._lookAheadDue = lookAheadDue

-- For Stop's message: the name of the stage whose look-ahead area was added and is still downloading, or whose add
-- is still unanswered (BeamNG.Earth may yet take it), its turn not come yet; or nil.
queueAheadDownloading = function()
  local q = rallyQ
  if not (q and q.prep == rallyRun.preparing()) then return nil end
  for _, e in pairs(q.e) do
    if e.adding and not e.taken then return e.stage.name end
    if e.areaId and not e.had and not e.taken then
      local st = earth.areaStatus(e.areaId)
      if not (st and (st.state == 'done' or st.state == 'failed')) then return e.stage.name end
    end
  end
  return nil
end
M._rallyQueue = function() return rallyQ end

local function stepRallyPrep(dt)
  local pr = rallyRun.preparing()
  if not pr then prepWas, rallyQ = nil, nil return end
  if prepWas ~= pr then
    prepWas, rallyQ = pr, nil
    local rr0 = rallyRun.active()
    if rr0 and earth.hasRoadGraph() and earth.hasAreaRoute() then
      rallyQ = { prep = pr, eventId = rr0.eventId, e = {}, waited = 0 }
    end
  end
  local q = rallyQ
  if autoSeq or autoRecce.active() then
    if autoSeq and autoSeq.phase == M.ASKING then autoSeqStep('answer', true) end
    -- (the stage under way runs its own auto recce: the next one is looked ahead once this one is past its download)
    if q and lookAheadDue() then queueLookAhead(q) end
    return
  end
  local rr = rallyRun.active()
  local st, i, n
  if q and q.next then
    st, i, n = q.next, q.nextI, q.nextN
    -- (the rally gone while this stage waited for its look-ahead: nothing to run it in)
    if not rr then rallyQ = nil rallyRun.prepDone() return end
  else
    st, i, n = rallyRun.prepNext()
    if not (rr and st) then rallyQ = nil rallyRun.prepDone() return end
    if q then q.next, q.nextI, q.nextN, q.waited = st, i, n, 0 end
  end
  -- (its turn, but its look-ahead's estimate or add not answered yet: wait for it, a while)
  local e = q and q.e[st.id]
  if e and not e.resolved then
    q.waited = q.waited + (dt or 0)
    if q.waited < M.QUEUE_WAIT_S then return end
    -- Given up: marked settled and refused, so an answer that comes late adds nothing more (queueLive). An add still
    -- out may yet be taken: it is booked then, and this stage is matched with what is here now rather than priced
    -- and added a second time. An estimate still out: the stage priced again at its turn, the 1.7.0 way.
    log('W', logTag, 'rally: ' .. tostring(st.name) .. "'s look-ahead did not settle: getting it ready alone")
    e.resolved, e.refused = true, 'it did not answer in time'
    if not e.adding then e = nil end
  end
  if e and e.failed then e = nil end                -- (no estimate ahead: priced at its turn)
  if e then e.taken = true end
  if q then q.next = nil end
  runner.say(string.format('%s (%d of %d): making its line on the roads.', st.name, i, n), 6, 'info', 'Auto recce')
  local r = doAction('autoRecce', rr.eventId, st.id, true, e)
  if not (r and r.ok) then
    log('W', logTag, 'rally: the auto recce of ' .. tostring(st.name) .. ' did not start: ' .. tostring(r and r.message))
  end
end

-- (#63) The game time that passes while a pause request of ours is in, once a second: the third drive's log had the
-- rally clock and BeamNG.Earth's anchor commits going on under the page's request, so the next drive shows whether
-- it stops the physics at all.
local pausedLog = nil
logPausedSim = function(dtReal, dtSim)
  local ids = menuPause.heldIds()
  if not ids then pausedLog = nil return end
  pausedLog = pausedLog or { real = 0, sim = 0 }
  pausedLog.real, pausedLog.sim = pausedLog.real + dtReal, pausedLog.sim + dtSim
  if pausedLog.real < 1 then return end
  log('I', logTag, string.format('pause held (%s): %.2f s of game time in %.2f s', table.concat(ids, ', '),
    pausedLog.sim, pausedLog.real))
  pausedLog.real, pausedLog.sim = 0, 0
end

function M.onUpdate(dtReal, dtSim)
  pcall(rallyRun.update, dtReal)
  local okP, errP = pcall(stepRallyPrep, dtReal or 0)
  if not okP then log('E', logTag, 'rally prep: ' .. tostring(errP)) end
  -- (1.7.3, item 3) a road-graph window waiting to be asked again after a timeout
  local okU, errU = pcall(autoRecce.update)
  if not okU then log('E', logTag, 'auto recce: ' .. tostring(errU)) end
  pcall(stats.update, dtReal)
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
  pcall(online.update, dtReal or 0)
  pcall(earthMenuFix.update)   -- (ahead of earth.update, which is not pcall'd)
  pcall(menuPause.update)      -- (a pause request held back while BeamNG.Earth held the game)
  pcall(logPausedSim, dtReal or 0, dtSim or 0)
  -- (#43) the stage's finish card at the stop box: the game paused while it gives the options (not under our page,
  -- which has its own request)
  do
    local r = runner.current()
    local want = r ~= nil and r.resultsOpen == true and r.state == 'finished' and r.stopCtl ~= nil and not menuOpen
      and not runner.uiHidden
    pcall(menuPause.card, 'earthRally_results', want)
    -- (#58, #59, #69: a rally's question -- "Load the stage?", Recover? -- paused under it too, so A and the pad
    -- reach its card and not the car)
    local okA, asking = pcall(rallyRun.asking)
    pcall(menuPause.card, 'earthRally_ask', okA and asking == true and not menuOpen and not runner.uiHidden)
  end
  local okL, errL = pcall(loadScreen.update, dtReal or 0)
  if not okL then log('E', logTag, 'loading screen: ' .. tostring(errL)) loadScreen.cancel() end
  earth.update()
  -- In the BeamNG.Earth level: the version check again, now that the game's rally engine can be looked at without
  -- dragging it in at the main menu (versions.lua says why). Once per level, and quiet unless something changed
  -- since the last time, so this is not a per-frame cost.
  if not earthSeen and earth.inWorld() then
    earthSeen = true
    pcall(versions.check, M.VERSION)
  end
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
-- (1.7.0) In a full rally's stage the key is the rally's recovery (rallyRun.recoverKey: free in Casual, the Recover?
-- question in Realistic).
function M.backOnRoad()
  local okR, mine = pcall(rallyRun.recoverKey)
  if okR and mine then return true end
  local ok, r = pcall(runner.backOnRoad) return ok and r end
function M.flipUpright() local ok, r = pcall(runner.flipUpright) return ok and r end
-- (1.7.0, #25) The pad's rally recovery (D-pad right): the rally's recovery key, and nothing outside a full rally --
-- there the same button is the game's own reset, which a stage counts already.
function M.rallyRecover()
  local r = rallyRun.active()
  if not r or r.done then return false end
  local ok, r = pcall(rallyRun.recoverKey)
  return ok and r
end

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

-- The road map rebuilt (map.reset: BeamNG.Earth's navgraph as roads stream in): the props' index of its nodes
-- is stale (1.6.1).
function M.onNavgraphReloaded()
  pcall(require('earthRally/props').mapChanged)
end

-- The level left, or back at the menu: the run put away. This is the hook that really fires for a player, so every
-- call in it is pcall'd and the strips are given back even if something before that throws -- tidy() reaches
-- layoutOff sixth of nine, so a throw in the traffic or the props would otherwise take the release with it, and a
-- strip left held outlives the level it was held in.
function M.onClientEndMission()
  pcall(menuPause.releaseAll)   -- (the menu's pause request, if the level went with the page up)
  if selftest then pcall(selftest.onClientEndMission) end
  if recce.active() then pcall(recce.stop, false) end
  -- An auto recce converts each window through the world's origin, so one still in flight when the level goes
  -- would answer into a world that is not there -- and the page would show a banner for something nothing is
  -- running. It stops the way a recce does, and writes nothing.
  -- autoSeq as well: a sequence between its legs has no window in flight, so cancelling the auto recce alone
  -- would leave it behind and the page busy for ever (the guard in doAction refuses everything while one runs)
  autoSeq, rallyQ = nil, nil
  if autoRecce.active() then autoRun = nil; pcall(autoRecce.cancel) end
  if previewT then pcall(M.previewStop) end
  pcall(rallyRun.quit)          -- (a full rally: left, its save kept, BeamNG's own recovery back)
  pcall(rallyRun.release)
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
  pcall(menuPause.releaseAll)   -- (the menu's pause request, if it went with the page up)
  if recce.active() then pcall(recce.stop, false) end
  -- An auto recce converts each window through the world's origin, so one still in flight when the level goes
  -- would answer into a world that is not there -- and the page would show a banner for something nothing is
  -- running. It stops the way a recce does, and writes nothing.
  -- autoSeq as well: a sequence between its legs has no window in flight, so cancelling the auto recce alone
  -- would leave it behind and the page busy for ever (the guard in doAction refuses everything while one runs)
  autoSeq, rallyQ = nil, nil
  if autoRecce.active() then autoRun = nil; pcall(autoRecce.cancel) end
  if previewT then pcall(M.previewStop) end
  pcall(rallyRun.quit)          -- (a full rally: left, its save kept, BeamNG's own recovery back)
  pcall(rallyRun.release)
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
  pcall(online.enable, false)  -- (the companion's socket closed: nothing reads it once the module goes)
  pcall(online.probeStop)      -- (#77: and the helper look's, if one is under way)
  pcall(stats.unwatchLog)      -- (the game's log function given back)
  pcall(menuPause.releaseAll)   -- (the menu's pause request, if the module goes with the page up: a reload)
  if recce.active() then pcall(recce.stop, false) end
  -- An auto recce converts each window through the world's origin, so one still in flight when the level goes
  -- would answer into a world that is not there -- and the page would show a banner for something nothing is
  -- running. It stops the way a recce does, and writes nothing.
  -- autoSeq as well: a sequence between its legs has no window in flight, so cancelling the auto recce alone
  -- would leave it behind and the page busy for ever (the guard in doAction refuses everything while one runs)
  autoSeq, rallyQ = nil, nil
  if autoRecce.active() then autoRun = nil; pcall(autoRecce.cancel) end
  if previewT then pcall(M.previewStop) end
  pcall(rallyRun.quit)          -- (a full rally: left, its save kept, BeamNG's own recovery back)
  pcall(rallyRun.release)
  pcall(runner.abort, true)
  pcall(earth.holdStrips, false)
  pcall(earth.reset)
end

function M.onExtensionLoaded()
  -- (boards and tents a run left before a Lua reload: taken away; the car's brake / clutch overrides handed back,
  --  and BeamNG.Earth's strips given back in case a run was cut short holding them)
  pcall(require('earthRally/props').sweep)
  pcall(earth.holdStrips, false)
  pcall(rallyRun.release)      -- (a full rally's block on the game's recovery, if a reload cut it short)
  local veh = getPlayerVehicle and getPlayerVehicle(0)
  if veh then pcall(runner._vehCtl, veh, 'off') end
  settings.load()
  show[0] = settings.get('devPanel') == true
  online.VERSION = M.VERSION
  online.enable(settings.get('onlineBoard') == true)
  online.markLoaded()          -- (#77: a helper look in the next 15 s is not trusted, it may still be starting)
  pcall(stats.init, M.VERSION)
  -- stats (#76): through the leaderboard's companion, only while the leaderboard is on; Earth Rally's errors in the
  -- log recorded as they happen (only with the player's yes)
  stats.transport = online.sendStats
  stats.active = online.enabled
  pcall(stats.watchLog)
  -- (new maps in the import folder)
  scanIn = 0.5
  log('I', logTag, 'Earth Rally ' .. M.VERSION .. ' loaded (Ctrl+Alt+K opens its menu)')
  -- what this machine is, and anything that has changed under the mod since it was built (roadmap 23). The game's
  -- half can be read now; BeamNG.Earth's is read again in onUpdate when it turns up, which is usually later.
  earthSeen = false
  versions.reset()
  pcall(versions.check, M.VERSION)
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
