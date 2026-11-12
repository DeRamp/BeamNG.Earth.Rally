-- earthRally_main: Earth Rally's window (Ctrl+Alt+K, or earthRally_main.toggle() in the console) and its frame
-- loop: the rallies on this computer, each stage's recce and timed runs.
local im = ui_imgui
local earth = require('earthRally/earthAdapter')
local events = require('earthRally/events')
local recce = require('earthRally/recce')
local runner = require('earthRally/runner')
local importer = require('earthRally/importer')

local M = {}
local logTag = 'earthRally'
M.VERSION = '1.1.0'

local show = im.BoolPtr(false)
local selEvent, selStage = 1, 1
local message = nil
local facing = nil       -- after Go to start: turn the car along the stage once BeamNG.Earth has set it down
local scanIn = nil       -- seconds until the import folder is looked at (a file changed in it)

function M.toggle() show[0] = not show[0] end
function M.show() show[0] = true end

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
    im.Text(string.format('%s of %s%s', km((r.along or 0) - r.startM), km(r.finishM - r.startM),
      (r.off or 0) > runner.OFF_ROUTE_M and '   OFF ROUTE' or ''))
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

local function drawWindow()
  im.SetNextWindowSize(im.ImVec2(460, 560), im.Cond_FirstUseEver)
  if not im.Begin('Earth Rally ' .. M.VERSION .. '###earthRallyWindow', show) then im.End() return end

  local ok, why = earth.check()
  if not ok then im.TextColored(AMBER, why) end

  local list = events.list()
  if #list == 0 then
    im.TextWrapped('No rallies yet. Put a rally map (.kml, .kmz or .gpx) in the import folder: it is imported at once.')
  end
  if im.Button('Open import folder') then
    if not importer.openFolder() then message = 'The import folder: ' .. importer.folderPath() end
  end
  im.SameLine()
  if im.Button('Re-scan') then M.scanImports(true) end
  im.SameLine()
  if im.Button('Reload') then events.list(true) selEvent, selStage = 1, 1 end

  for i, e in ipairs(list) do
    if im.Selectable1(e.name .. '##ev' .. i, selEvent == i) then selEvent, selStage = i, 1 end
  end
  local ev = list[selEvent]
  if ev then
    im.Separator()
    local rep = importer.lastReports[ev.id]
    if rep and #rep.lines > 0 and im.TreeNode1('Import report (' .. tostring(rep.file) .. ')##imp' .. ev.id) then
      for _, l in ipairs(rep.lines) do im.TextWrapped(l) end
      im.TreePop()
    end
    for i, s in ipairs(ev.stages) do
      local line, kind = events.stageLine(ev.id, s.id, s)
      local note = '  - recce needed'
      if kind == 'recce' then note = ''
      elseif kind == 'matched' then
        note = (line.gapM or 0) > 0 and string.format('  - on the map roads (%s not on the map: a recce is better)',
          km(line.gapM)) or '  - on the map roads'
      end
      local label = string.format('%s  (%s)%s##st%d', s.name, km(s.lengthM), note, i)
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
        if im.Button('Save recce') then
          local saved, err = recce.stop(true)
          message = saved and 'Recce saved.' or err
        end
        im.SameLine()
        if im.Button('Save anyway') then
          local saved, err = recce.stop(true, true)
          message = saved and 'Recce saved.' or err
        end
        im.SameLine()
        if im.Button('Cancel recce') then recce.stop(false) end
      elseif not busy then
        if im.Button('Go to start') then
          local s = stage.controls and stage.controls.start or { lat = stage.line[1][1], lon = stage.line[1][2] }
          local tok, terr = earth.teleport(s.lat, s.lon, stage.name .. ' start')
          message = tok and 'Waiting for the world to load...' or ('Could not go there: ' .. tostring(terr))
          if tok then facing = { stage = stage, t = 0, ready = 0 } end
        end
        im.SameLine()
        if im.Button('Start recce') then recce.start(ev, stage) message = 'Follow the orange line on the road to the flying finish (the green ball); the recce saves itself there.' end
        if events.stageLine(ev.id, stage.id, stage) then
          im.SameLine()
          if im.Button('Run stage') then
            local rok, rerr = runner.start(ev, stage)
            message = rok and nil or rerr
          end
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

-- The import folder looked at: new or changed maps imported, the list read again, a message for each.
function M.scanImports(always)
  local ok, done = pcall(importer.scan, always)
  if not ok then log('E', logTag, 'import: ' .. tostring(done)) message = 'Import failed: ' .. tostring(done) return end
  if #done > 0 or always then
    events.list(true)
    selEvent, selStage = 1, 1
  end
  local said = {}
  for _, d in ipairs(done) do
    local text
    if d.removed then text = d.file .. ' taken out of the import folder (its rally is kept)'
    elseif d.ok then text = string.format('Imported %s: %d stage%s', tostring(d.name), d.stages, d.stages == 1 and '' or 's')
    else text = 'Could not import ' .. d.file .. ': ' .. tostring(d.why) end
    said[#said + 1] = text
    earth.notify('Earth Rally: ' .. text, 6)
  end
  if #said > 0 then message = table.concat(said, '\n')
  elseif always then message = 'Nothing new in the import folder.' end
end

-- A file changed in the game's user folder: one in the import folder is looked at a moment later (it may still be
-- being written).
function M.onFileChanged(filename)
  if type(filename) == 'string' and filename:lower():find(importer.IMPORT_DIR:lower(), 1, true) then scanIn = 1.0 end
end

function M.onUpdate(dtReal, dtSim)
  if scanIn then
    scanIn = scanIn - (dtReal or 0)
    if scanIn <= 0 then scanIn = nil M.scanImports(false) end
  end
  earth.update()
  if recce.active() and recce.update() == 'done' then
    local saved, err = recce.stop(true)
    message = saved and 'Recce saved: you can run the stage.' or err
    earth.notify('Earth Rally: ' .. message, 6)
  end
  if recce.active() then pcall(recce.draw, dtReal) end
  if facing then
    facing.t = facing.t + dtReal
    facing.ready = earth.ready() and facing.t > 2 and (facing.ready + dtReal) or 0
    if facing.ready >= runner.TELEPORT_SETTLE_S then
      pcall(runner.faceStage, facing.stage)
      if message == 'Waiting for the world to load...' then message = nil end
      facing = nil
    elseif facing.t > 120 then
      if message == 'Waiting for the world to load...' then message = 'The world is taking long to load here.' end
      facing = nil
    end
  end
  local ok, err = pcall(runner.update, dtReal, dtSim)
  if not ok then log('E', logTag, 'run: ' .. tostring(err)) runner.abort(true) message = 'Run stopped: ' .. tostring(err) end
  if show[0] then
    local okW, errW = pcall(drawWindow)
    if not okW then log('E', logTag, 'window: ' .. tostring(errW)) pcall(im.End) end
  end
end

function M.onClientEndMission()
  if recce.active() then recce.stop(false) end
  runner.abort(true)
  earth.reset()
end

function M.onExtensionLoaded()
  -- (boards and tents a run left before a Lua reload: taken away; the car's brake / clutch overrides handed back)
  pcall(require('earthRally/props').sweep)
  local veh = getPlayerVehicle and getPlayerVehicle(0)
  if veh then pcall(runner._vehCtl, veh, 'off') end
  -- (new maps in the import folder)
  scanIn = 0.5
  log('I', logTag, 'Earth Rally ' .. M.VERSION .. ' loaded (Ctrl+Alt+K opens its window)')
end

return M
