-- earthRally/menu: what the menu page shows (ui/ui-vue/mods/earthRally: Rallies, a rally's stages, a stage), built
-- from the files on this computer (events.lua) as plain tables for the Vue side (lengths in metres, times in
-- seconds, dates as written; units and wording are the page's). No game calls.
local events = require('earthRally/events')

local M = {}

M.RUNS_SHOWN = 8

-- Why the Auto recce button is not offered, when it is not. There are two reasons and they are not the same
-- sentence: this one (the capability is missing -- an older BeamNG.Earth), and the capability being there while the
-- server has no roads at all, which only a result can report (docs/upstream-roadgraph.md). The page shows this one
-- beside the button rather than in a tooltip: a disabled BngButton takes no pointer events, so it can never show
-- one.
M.AUTO_UNAVAILABLE = 'Auto recce needs BeamNG.Earth to hand out its road graph, and this one does not: it is ' ..
  'older than the version that added it. Update BeamNG.Earth, or drive the recce.'

local function basename(f) return f and tostring(f):match('([^/\\]+)$') or nil end

-- A stage's line and what it means for the player:
--   status 'ready'  notes from the stage's own roads (matched, all on the map) or a recce
--          'recce'  recce recommended: part of the stage has no road on the map, or the recce stops short
--          'none'   no line yet: a recce is needed before it can be driven
--
-- autoRecce: can this BeamNG.Earth run an auto recce (earthAdapter.hasRoadGraph, passed in -- no game calls here)?
-- It changes only the wording of the 'none' note: "drive its recce first" stopped being the only answer the moment
-- the auto recce had a button, and offering it where it cannot run would be worse than not mentioning it.
function M.stageStatus(eventId, stage, autoRecce)
  local line, kind = events.stageLine(eventId, stage.id, stage)
  local out = { kind = kind, status = 'none',
    note = autoRecce and 'No line on the roads yet: run the auto recce, or drive its recce.'
                      or 'No line on the roads yet: drive its recce.' }
  if kind == 'recce' then
    local shortM = events.recceShortM(events.recce(eventId, stage.id), stage, events.matched(eventId, stage.id))
    if shortM >= events.RECCE_SHORT_OF_FF_M then
      out.status, out.shortM = 'recce', shortM
      out.note = string.format('Your recce stops %d m before the flying finish: drive it again.', math.floor(shortM))
    else
      out.status, out.note = 'ready', 'Notes from your recce.'
    end
  elseif kind == 'matched' then
    local gap = line.gapM or 0
    if gap > 0 then
      out.status, out.gapM = 'recce', gap
      out.note = string.format('%.1f km of it has no road on the map (no notes there) until you drive its recce.',
        gap / 1000)
    else
      out.status, out.note = 'ready', "Notes from the map's roads, all the way. No recce needed."
    end
  end
  return out
end

-- A run's penalties in a few words: 'clean', '+10 s jump start', '+20 s, 2 resets'.
function M.penaltyText(r)
  local pen = r.penaltyS or 0
  if pen <= 0 then return 'clean' end
  local why = {}
  if r.jumpStart then why[#why + 1] = 'jump start' end
  if (r.lateMinutes or 0) > 0 then why[#why + 1] = 'late' end
  if (r.resets or 0) > 0 then why[#why + 1] = r.resets == 1 and '1 reset' or (r.resets .. ' resets') end
  if r.missedAtc then why[#why + 1] = 'missed time control' end
  return string.format('+%d s%s', math.floor(pen + 0.5), #why > 0 and (' ' .. table.concat(why, ', ')) or '')
end

-- A rally's card on the Rallies page.
function M.rallyCard(e, report)
  local km, driven = 0, 0
  for _, s in ipairs(e.stages or {}) do
    km = km + (s.lengthM or 0)
    if events.best(e.id, s.id) then driven = driven + 1 end
  end
  local src = e.source and e.source.file or e.file
  return { id = e.id, name = e.name, file = basename(src), stages = #(e.stages or {}), lengthM = km, driven = driven,
    report = report and report.lines or nil }
end

function M.rallies(reports)
  local out = {}
  for i, e in ipairs(events.list()) do out[i] = M.rallyCard(e, reports and reports[e.id]) end
  return out
end

local function findEvent(eventId)
  for _, e in ipairs(events.list()) do if e.id == eventId then return e end end
end
M.findEvent = findEvent

function M.findStage(eventId, stageId)
  local e = findEvent(eventId)
  if not e then return nil end
  for i, s in ipairs(e.stages or {}) do if s.id == stageId then return e, s, i end end
  return e
end

-- A rally's page: its stages in map order (SS1 = the first line in the file).
function M.rally(eventId, reports, autoRecce)
  local e = findEvent(eventId)
  if not e then return nil end
  local out = M.rallyCard(e, reports and reports[e.id])
  out.list = {}
  for i, s in ipairs(e.stages or {}) do
    local st = M.stageStatus(e.id, s, autoRecce)
    -- `line` is st.kind ('recce' | 'matched' | nil), the same field the stage page already gets. The row needs
    -- it for Reset: a driven recce cannot be made again and is confirmed before it goes, a matched line is 1.25 s
    -- of work and is not. Without it the row would have to treat both alike, and the cheap case is the common one.
    out.list[i] = { id = s.id, ss = i, name = s.name, lengthM = s.lengthM, status = st.status, line = st.kind,
      best = events.best(e.id, s.id) }
  end
  return out
end

-- A stage's page: its numbers, line, controls and the player's runs (newest first).
-- arrival: the run's first control ('ATC' / 'start', runner.arrivalPoint).
function M.stage(eventId, stageId, arrival, autoRecce)
  local e, s, i = M.findStage(eventId, stageId)
  if not s then return nil end
  local st = M.stageStatus(e.id, s, autoRecce)
  -- The four tiles' last three numbers all come from the stage's own line: the corners the co-driver will call on
  -- it and the height it gains and loses (events.lineFigures, kept with the line when it was saved). Until 1.3.1
  -- the corner count was taken from the stage's past runs instead -- so a stage recced but never driven showed a
  -- dash, which is the one moment the number is worth having. There is one dash left and it means "no line yet".
  local fig = events.lineFigures(e.id, s.id, s) or {}
  local runs = {}
  local all = events.results(e.id, s.id).runs or {}
  for k = #all, 1, -1 do
    local r = all[k]
    if r.finished and #runs < M.RUNS_SHOWN then
      runs[#runs + 1] = { date = r.date, timeS = r.timeS, stageS = r.stageS, penaltyS = r.penaltyS or 0,
        text = M.penaltyText(r), last = #runs == 0 or nil }
    end
  end
  local ctl = s.controls or {}
  return {
    eventId = e.id, rally = e.name, id = s.id, ss = i, ssCount = #e.stages, name = s.name, lengthM = s.lengthM,
    status = st.status, note = st.note, line = st.kind,
    corners = fig.corners, gainM = fig.gainM, lossM = fig.lossM,
    atc = arrival == 'ATC', stop = ctl.stop ~= nil, best = events.best(e.id, s.id), runs = runs,
    canDrive = st.kind ~= nil,
    -- the Auto recce button's own two answers: it is offered on a stage with no line, and when it cannot be
    -- offered at all the page says why beside it rather than greying it with nothing to read
    autoCan = st.status == 'none' or nil,
    autoWhy = (st.status == 'none' and not autoRecce) and M.AUTO_UNAVAILABLE or nil,
  }
end

return M
