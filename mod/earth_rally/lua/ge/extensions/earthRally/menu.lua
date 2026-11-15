-- earthRally/menu: what the menu page shows (ui/ui-vue/mods/earthRally: Rallies, a rally's stages, a stage), built
-- from the files on this computer (events.lua) as plain tables for the Vue side (lengths in metres, times in
-- seconds, dates as written; units and wording are the page's). No game calls.
local events = require('earthRally/events')
local boards = require('earthRally/boards')

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
-- driven: the stages with a time that can be placed (events.bestPlaceable: on the line the stage runs on now), the
-- one meaning of "driven" on every page.
function M.rallyCard(e, report)
  local km, driven = 0, 0
  for _, s in ipairs(e.stages or {}) do
    km = km + (s.lengthM or 0)
    if events.bestPlaceable(e.id, s.id, s) then driven = driven + 1 end
  end
  local src = e.source and e.source.file or e.file
  return { id = e.id, name = e.name, file = basename(src), stages = #(e.stages or {}), lengthM = km, driven = driven,
    report = report and report.lines or nil }
end

function M.rallies(reports)
  local out = {}
  for _, e in ipairs(events.list()) do
    if type(e.retired) ~= 'table' then out[#out + 1] = M.rallyCard(e, reports and reports[e.id]) end
  end
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

-- A rally's page: its stages in map order (SS1 = the first line in the file), and what a rally file adds
-- (M.addRallyFiles below: banner, passes, Place, Results, Rules).
function M.rally(eventId, reports, autoRecce)
  local out = M.rallyBase(eventId, reports, autoRecce)
  if out then M.addRallyFiles(out, findEvent(eventId)) end
  return out
end

function M.rallyBase(eventId, reports, autoRecce)
  local e = findEvent(eventId)
  if not e then return nil end
  local out = M.rallyCard(e, reports and reports[e.id])
  out.list = {}
  for i, s in ipairs(e.stages or {}) do
    local st = M.stageStatus(e.id, s, autoRecce)
    -- `line` is st.kind ('recce' | 'matched' | nil), the same field the stage page already gets. The row needs
    -- it for Reset: a driven recce cannot be made again and is confirmed before it goes, a matched line is 1.25 s
    -- of work and is not. Without it the row would have to treat both alike, and the cheap case is the common one.
    -- (oldLine: it has times, none of them on the line it runs on now: the row says "Old line")
    local best = events.best(e.id, s.id)
    out.list[i] = { id = s.id, ss = i, name = s.name, lengthM = s.lengthM, status = st.status, line = st.kind,
      best = best, oldLine = (best ~= nil and events.bestPlaceable(e.id, s.id, s) == nil) or nil }
  end
  return out
end

-- A stage's page: its numbers, line, controls and the player's runs (newest first).
-- arrival: the run's first control ('ATC' / 'start', runner.arrivalPoint). pass: the leaderboard's pass ('SS4'),
-- nil for the one you place best on.
function M.stage(eventId, stageId, arrival, autoRecce, pass)
  local e, s, i = M.findStage(eventId, stageId)
  if not s then return nil end
  local out = M.stageBase(e, s, i, arrival, autoRecce)
  M.addStageRallyFiles(out, e, s, i, pass)
  return out
end

function M.stageBase(e, s, i, arrival, autoRecce)
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

------------------------------------------------------------------------------------------ rally files
-- What a pack adds (docs/rally-file.md; the mock-up is docs/mockups-rally-files/menu.html): seasons, covers, the
-- running order with its passes, your place against the real field, your rally result, the season standings and
-- the rules. Read from the files pack.lua wrote and worked out by boards.lua. An event file with none of the new
-- fields (a loose map, or one imported before rally files) comes out as it always did, plus its SS numbers as
-- passes.

M.STANDINGS_TOP = 10     -- the season's standings: the top 10, and you
M.RESULTS_TOP = 10       -- a rally's results: the real top 10, and you
-- The one rule the game applies today is a fixed 10 s jump start (runner.JUMP_START_PENALTY_S: the runner does
-- not read an event's rules yet). The Rules tab marks the false start "in game" only when the file's first offence
-- is that same figure, so the mark never says the game charges what the file says while it charges something else.
M.GAME_FALSE_START_S = 10

-- Where the menu loads a picture from: the ONE place a path the importer wrote (pack.MEDIA_DIR,
-- '/earthRally/media/<rallyId>/cover.png') becomes what the page puts in an <img src>.
-- UNVERIFIED IN GAME: the path is handed over as it is, a '/'-rooted path in the game's virtual file system, on the
-- guess that the UI (served from that same file system) resolves it against the user folder. If the in-game check
-- finds another form is needed (a scheme, a prefix), it changes here and nowhere else. The page draws a rally plate
-- under every picture and drops a picture that fails to load, so a wrong guess shows plates, not holes.
-- v: a short fingerprint of what the picture was copied from, put on as ?v=, so a re-import with a new cover is
-- loaded again rather than taken from the page's cache (the file keeps its name: cover.png).
function M.mediaUrl(path, v)
  if type(path) ~= 'string' or path == '' then return nil end
  if type(v) == 'string' and v ~= '' then return path .. '?v=' .. v end
  return path
end

-- (the pack's fingerprint, short: '1234:0a1b2c3d' gives '0a1b2c3d')
local function shortPrint(e)
  local fp = type(e.pack) == 'table' and e.pack.fingerprint
  if type(fp) ~= 'string' then return nil end
  local h = fp:match(':(%x+)$') or fp:gsub('[^%w]', '')
  return h:sub(-8)
end

local function mediaOf(e)
  local m = type(e.media) == 'table' and e.media or {}
  local out, any, v = {}, false, shortPrint(e)
  for _, k in ipairs({ 'cover', 'logo', 'photo' }) do
    out[k] = M.mediaUrl(m[k], v)
    any = any or out[k] ~= nil
  end
  return any and out or nil
end

-- (a value worked out again only when what it is made of has changed: the page asks every second or two, and a
-- season's standings rank every crew of every pass of every round. deps are compared by identity: events.lua hands
-- out the same tables until a file is read again, so a re-import, a new board or a new best is a changed dep.)
local memo = {}
local function memoised(key, deps, fn)
  local m = memo[key]
  if m and #m.deps == #deps then
    local same = true
    for i = 1, #deps do if m.deps[i] ~= deps[i] then same = false break end end
    if same then return m.value end
  end
  local v = fn()
  memo[key] = { deps = deps, value = v }
  return v
end
function M.forgetMemo() memo = {} end

-- The season an event is a round of, when that season's file is on this computer and lists it; else nil (the event
-- shows as a rally of its own).
local function seasonOfEvent(e)
  local s = type(e.season) == 'table' and e.season.id ~= nil and events.season(e.season.id) or nil
  if not s then return nil end
  for _, id in ipairs(s.rounds) do if id == e.id then return s end end
  return nil
end

-- A rally of one stage and no season: the Rallies page shows it as a stage, and it opens on the stage's page.
local function isSingle(e) return #(e.stages or {}) == 1 and seasonOfEvent(e) == nil end

local function boardOf(e) return e.boards ~= nil and events.boards(e.id) or nil end

-- (your best on each stage that can be placed, on the line the stage runs on now (events.bestPlaceable):
-- { [stageId] = seconds }; each stage's length start to flying finish on that line: { [stageId] = metres }, none
-- for a stage with no line (boards.lua measures the map's then); and both as a list for memoised's deps)
local function bestsOf(e)
  local by, lineM, deps = {}, {}, {}
  for _, s in ipairs(e.stages or {}) do
    local b = events.bestPlaceable(e.id, s.id, s)
    local info = events.stageLineInfo(e.id, s.id, s)
    by[s.id] = b
    lineM[s.id] = info and info.lengthM or nil
    deps[#deps + 1] = b or false
    deps[#deps + 1] = info and info.lengthM or false
  end
  return by, deps, lineM
end
M._bestsOf = bestsOf

-- Each stage's passes in running order: { [stageId] = { { ss, run, km, cancelled }... } }, the stage ids in the
-- order they are first run, and { [stageId] = true } for the stages the itinerary never runs. With no itinerary (a
-- map on its own, an older file): each stage once, SS1, SS2... in map order, as the page always numbered them. A
-- stage the itinerary never runs has no passes (the page says "Not run", never a made-up SS number), and comes last.
local function passesOf(e)
  local by, order = {}, {}
  for _, it in ipairs(type(e.itinerary) == 'table' and e.itinerary or {}) do
    local s = type(it) == 'table' and boards.stageOf(e, { stage = it.stage, stageId = it.stageId }) or nil
    if s and it.ss ~= nil then
      if not by[s.id] then by[s.id] = {} order[#order + 1] = s.id end
      local list = by[s.id]
      list[#list + 1] = { ss = tostring(it.ss), run = it.run, km = it.km, cancelled = it.cancelled == true }
    end
  end
  local itin, notRun = #order > 0, {}
  for i, s in ipairs(e.stages or {}) do
    if not by[s.id] then
      by[s.id] = itin and {} or { { ss = 'SS' .. i, run = 1, cancelled = false } }
      if itin then notRun[s.id] = true end
      order[#order + 1] = s.id
    end
  end
  return by, order, notRun
end

-- A stage's SS label where the page and its banners name it: its passes ('SS2 · SS4'), 'SS3' by map order with no
-- itinerary, nil for a stage the itinerary never runs (say its name alone; never a made-up SS number).
function M.ssLabel(e, stageId)
  if type(e) ~= 'table' then return nil end
  local by, _, notRun = passesOf(e)
  if notRun[stageId] then return nil end
  local l = {}
  for _, p in ipairs(by[stageId] or {}) do l[#l + 1] = p.ss end
  return #l > 0 and table.concat(l, ' · ') or nil
end

-- (the itinerary's passes that name a stage of the map, in running order: { { stage, index (map order), cancelled
-- }... }; empty with no itinerary)
local function runningOrder(e)
  local out, idx = {}, {}
  for i, s in ipairs(e.stages or {}) do idx[s.id] = i end
  for _, it in ipairs(type(e.itinerary) == 'table' and e.itinerary or {}) do
    local s = type(it) == 'table' and boards.stageOf(e, { stage = it.stage, stageId = it.stageId }) or nil
    if s and it.ss ~= nil then out[#out + 1] = { stage = s, index = idx[s.id], cancelled = it.cancelled == true } end
  end
  return out
end

-- How many SS the rally runs: its itinerary's counted passes (not cancelled), or nil with no itinerary (the map's
-- stages are its SS then).
function M.passCount(e)
  if type(e) ~= 'table' then return nil end
  local order = runningOrder(e)
  if #order == 0 then return nil end
  local n = 0
  for _, p in ipairs(order) do if not p.cancelled then n = n + 1 end end
  return n
end

-- The stage to drive after this one, and its place in the map's order: the stage of the next counted pass after
-- this stage's first pass in the itinerary's running order (a pass of this same stage skipped); with no itinerary,
-- or for a stage the itinerary never runs, the next stage in map order that the itinerary does run. nil at the end.
function M.nextStage(e, stageId)
  if type(e) ~= 'table' then return nil end
  local order = runningOrder(e)
  local at = nil
  for k, p in ipairs(order) do if p.stage.id == stageId then at = k break end end
  if at then
    for k = at + 1, #order do
      local p = order[k]
      if not p.cancelled and p.stage.id ~= stageId then return p.stage, p.index end
    end
    return nil
  end
  local _, _, notRun = passesOf(e)
  local after = false
  for i, s in ipairs(e.stages or {}) do
    if after and s.id ~= stageId and not notRun[s.id] then return s, i end
    if s.id == stageId then after = true end
  end
  return nil
end

-- Your place on a stage: the better of your placings over its passes (the user, 2026-11-14), each from that pass's
-- leaderboard with your best time and the stage's length (boards.lua's 5% rule): lineM, start to flying finish on
-- the line you are timed on (events.stageLineInfo), else the map's (boards.stageLengthM). Returns { pos, of, pass }
-- or nil; when nil, also the reason a counted pass gave ('noTime' | 'lineMismatch'), or nothing when the board has
-- no counted pass of this stage.
function M.stagePlace(board, stage, bestS, lineM)
  if type(board) ~= 'table' then return nil end
  local first = boards.stageBoard(board, stage, { bestS = bestS, lineM = lineM })
  if first.reason == 'noPasses' or first.reason == 'noBoard' then return nil end
  local best, why = nil, nil
  for _, p in ipairs(first.passes) do
    if not p.cancelled then
      local b = boards.stageBoard(board, stage, { pass = p.ss, bestS = bestS, lineM = lineM })
      if b.you then
        if not best or b.you.pos < best.pos then best = { pos = b.you.pos, of = b.you.of, pass = p.ss } end
      else
        why = why or b.reason
      end
    end
  end
  return best, (not best) and why or nil
end

-- What the rally page needs that takes working out, kept until a time, the board or the event changes.
local function rallyData(e, board)
  local by, bd, lineM = bestsOf(e)
  local deps = { e, board or false }
  for _, x in ipairs(bd) do deps[#deps + 1] = x end
  return memoised('rally:' .. tostring(e.id), deps, function()
    local passes, order, notRun = passesOf(e)
    local byStage = {}
    for _, s in ipairs(e.stages or {}) do
      local d = { passes = passes[s.id], notRun = notRun[s.id] }
      if board then d.place, d.why = M.stagePlace(board, s, by[s.id], lineM[s.id]) end
      byStage[s.id] = d
    end
    return { byStage = byStage, order = order, bests = by,
      result = board and boards.rallyResult(e, board, by, { lineMByStage = lineM }) or nil }
  end)
end

-- A season's standings and each round's rally result, kept until something under them changes.
local function seasonData(s)
  local rounds, deps = {}, { s }
  for ri, id in ipairs(s.rounds or {}) do
    local e = findEvent(id)
    local board = e and boardOf(e) or nil
    local by, bd, lineM = {}, {}, {}
    if e then by, bd, lineM = bestsOf(e) end
    rounds[ri] = { event = e or { id = id, name = tostring(id), stages = {} }, board = board, bestByStage = by,
      lineMByStage = lineM, found = e ~= nil }
    deps[#deps + 1] = e or false
    deps[#deps + 1] = board or false
    for _, x in ipairs(bd) do deps[#deps + 1] = x end
  end
  return memoised('season:' .. tostring(s.id), deps, function()
    local results = {}
    for ri, rd in ipairs(rounds) do
      if rd.found then
        results[ri] = boards.rallyResult(rd.event, rd.board, rd.bestByStage, { lineMByStage = rd.lineMByStage })
      end
    end
    return { standings = boards.standings(s, rounds, { top = M.STANDINGS_TOP }), results = results,
      rounds = rounds }
  end)
end

-- (a number as the rules write it: 10, 2.5)
local function num(x) return x == math.floor(x) and string.format('%d', x) or string.format('%g', x) end
local function perMinute(s)
  if s >= 60 and s % 60 == 0 then return num(s / 60) .. ' min a minute' end
  return num(s) .. ' s a minute'
end

-- The Rules tab: one short line for each rule the file has (the five the format knows, so five at most), in a fixed
-- order: { { label, value, inGame }... }, or nil when it has none (the tab is hidden).
function M.rulesLines(rules)
  if type(rules) ~= 'table' then return nil end
  local out = {}
  local fs = rules.falseStartS
  if type(fs) == 'table' and type(fs[1]) == 'number' then
    local v = {}
    for i, x in ipairs(fs) do if type(x) == 'number' then v[i] = num(x) else break end end
    out[#out + 1] = { label = 'False start', value = table.concat(v, ' / ') .. ' s',
      inGame = fs[1] == M.GAME_FALSE_START_S or nil }
  end
  if type(rules.lateSPerMin) == 'number' then
    out[#out + 1] = { label = 'Late at a time control', value = perMinute(rules.lateSPerMin) }
  end
  if type(rules.earlySPerMin) == 'number' then
    out[#out + 1] = { label = 'Early at a time control', value = perMinute(rules.earlySPerMin) }
  end
  if type(rules.maxLatenessMin) == 'number' then
    out[#out + 1] = { label = 'More than ' .. num(rules.maxLatenessMin) .. ' min late in a day', value = 'out' }
  end
  if type(rules.startIntervalMin) == 'number' then
    out[#out + 1] = { label = 'Cars start', value = num(rules.startIntervalMin) .. ' min apart' }
  end
  return #out > 0 and out or nil
end

local function datesOf(d)
  if type(d) ~= 'table' or (d.from == nil and d.to == nil) then return nil end
  return { from = d.from or d.to, to = d.to or d.from }
end

-- (the earliest from and the latest to of a list of { from, to })
local function span(acc, d)
  if not d then return end
  if d.from and (not acc.from or d.from < acc.from) then acc.from = d.from end
  if d.to and (not acc.to or d.to > acc.to) then acc.to = d.to end
end

local function seasonRef(season, e)
  if not season then return nil end
  return { id = season.id, name = season.name, round = type(e.season) == 'table' and e.season.round or nil }
end

-- Your points for one round of a season, when you were placed in it.
local function roundPoints(season, eventId)
  local you = seasonData(season).standings.you
  if not you then return nil end
  for ri, id in ipairs(season.rounds) do
    if id == eventId then
      local pr = you.perRound and you.perRound[ri]
      return pr and pr.pos and pr.points or nil
    end
  end
  return nil
end

-- The rally page's additions. out: M.rallyBase's table, its `list` put into running order and each row given its
-- passes and Place.
--   season = { id, name, round } | nil      single = true | nil (one stage, no season: the page opens the stage)
--   dates = { from, to }, place, media = { cover, logo, photo } (urls, M.mediaUrl)
--   hasBoard (the Place column and the Results tab), anyCancelled (the legend)
--   list[i].passes = { { ss, run, km, cancelled }... }, list[i].notRun = true (in an itinerary that never runs
--   it), list[i].place = { pos, of, pass } | nil, list[i].placeWhy = 'noTime' | 'lineMismatch' | nil
--   results (with a board) = { complete, totalS, you = { pos, of, gapS }, winnerS, stages, driven,
--     chips = { { name, done } } (the comparable stages: the ones the result is over),
--     rows = top 10 and you, with the crews either side of you below it (boards.menuRows)
--       { pos, name, car, class, timeS, gapS, you, skipped },
--     crews = how many crews have a time on every comparable pass, counted / comparable (passes), kmTotal /
--     kmCovered, partial = true | nil (some counted pass left out: its stage is more than 5% off the official
--     distance), notRanked = true | nil (the comparable passes under 75% of the km: no place, no points),
--     mismatch = { the left-out stages' names } | nil, points = yours for this round in its season }
--   rules = { { label, value, inGame }... } | nil
function M.addRallyFiles(out, e)
  if not e then return out end
  local season = seasonOfEvent(e)
  local board = boardOf(e)
  local data = rallyData(e, board)
  out.season = seasonRef(season, e)
  out.single = isSingle(e) or nil
  out.dates, out.place, out.media = datesOf(e.dates), e.place, mediaOf(e)
  out.hasBoard = board ~= nil or nil
  local rank = {}
  for k, id in ipairs(data.order) do rank[id] = k end
  local list = out.list or {}
  for _, row in ipairs(list) do
    local d = data.byStage[row.id] or {}
    row.passes = d.passes or {}
    row.notRun = d.notRun
    row.place, row.placeWhy = d.place, d.why
    for _, p in ipairs(row.passes) do if p.cancelled then out.anyCancelled = true end end
  end
  table.sort(list, function(a, b) return (rank[a.id] or a.ss) < (rank[b.id] or b.ss) end)

  local res = data.result
  if res then
    local chips, seen, driven, byId = {}, {}, 0, {}
    for _, s in ipairs(e.stages or {}) do byId[s.id] = s end
    for _, p in ipairs(res.passes) do
      if p.comparable and not seen[p.stageId] then
        seen[p.stageId] = true
        local done = data.bests[p.stageId] ~= nil
        if done then driven = driven + 1 end
        chips[#chips + 1] = { name = byId[p.stageId] and byId[p.stageId].name or p.stageId, done = done }
      end
    end
    local winner, crews = nil, 0
    for _, r in ipairs(res.ranked) do
      if not r.you then
        winner = winner or r.totalS
        crews = crews + 1
      end
    end
    local mismatch = nil
    for _, id in ipairs(res.lineMismatch or {}) do
      mismatch = mismatch or {}
      mismatch[#mismatch + 1] = byId[id] and byId[id].name or id
    end
    out.results = { complete = res.complete, totalS = res.totalS,
      you = res.you and { pos = res.you.pos, of = res.you.of, gapS = res.you.gapS } or nil,
      winnerS = winner, stages = #chips, driven = driven, chips = chips, crews = crews,
      counted = res.counted, comparable = res.comparable, kmTotal = res.kmTotal, kmCovered = res.kmCovered,
      partial = res.partial, notRanked = res.notRanked, mismatch = mismatch,
      rows = boards.topRows(res.ranked, M.RESULTS_TOP),
      points = (season and res.complete) and roundPoints(season, e.id) or nil }
  end
  out.rules = M.rulesLines(e.rules)
  return out
end

-- The stage page's additions:
--   season, single, media (as the rally's), passes = { { ss, run, km, cancelled }... }, notRun = true | nil
--   board = nil (no results for this stage: no Leaderboard card) | { passes = { { ss, run, km, cancelled }... },
--     pass = the shown pass's ss, km, lineKm (the map line's), field (crews on it), fastestS,
--     rows = top 10 and you, with the crews either side of you below it (boards.menuRows)
--       { pos, name, car, class, timeS, gapS, you, skipped }, you = { pos, of, gapS... } | nil,
--     reason = nil | 'cancelled' | 'noTime' | 'lineMismatch', lineKm = the stage's length start to flying finish on
--     the line you are timed on ('recce' / 'matched' in lineOf), else the map's ('map'), bestS = your best on that
--     line (the one placed), oldLine = true when your times were all driven on an earlier line }
-- The pass shown is `pass` when it is one of this stage's, else the one you place best on, else the first counted.
function M.addStageRallyFiles(out, e, s, i, pass)
  local season = seasonOfEvent(e)
  out.season = seasonRef(season, e)
  out.single = isSingle(e) or nil
  out.media = mediaOf(e)
  local passes, _, notRun = passesOf(e)
  out.passes = passes[s.id] or {}
  out.notRun = notRun[s.id]
  local board = boardOf(e)
  if board then
    -- (your best on the line the stage runs on now, and that line's start to flying finish: Your runs' BEST box
    -- keeps out.best, every time you have; a time from an earlier line is not placed here)
    local bestS = events.bestPlaceable(e.id, s.id, s)
    local info = events.stageLineInfo(e.id, s.id, s)
    local lineM = info and info.lengthM or boards.stageLengthM(s)
    local place = M.stagePlace(board, s, bestS, lineM)
    local sb = boards.stageBoard(board, s, { pass = pass or (place and place.pass), bestS = bestS, lineM = lineM })
    if sb.reason ~= 'noBoard' and sb.reason ~= 'noPasses' then
      out.board = { passes = sb.passes, pass = sb.pass, km = sb.km, field = sb.field, fastestS = sb.fastestS,
        rows = sb.rows, you = sb.you, reason = sb.reason, lineKm = lineM and lineM / 1000 or nil,
        lineOf = info and info.kind or 'map', bestS = bestS,
        oldLine = (out.best ~= nil and bestS == nil) or nil }
    end
  end
  return out
end

-- A season's card on the Rallies page, or nil when none of its rounds is on this computer:
--   { kind = 'season', id, name, championship, rallies, stages, driven, dates = { from, to },
--     covers = { { round, name, url }... } (the first eight rounds'), you = { pos, points, of } | nil }
function M.seasonCard(s)
  local rallies, stages, driven, covers, dates = 0, 0, 0, {}, {}
  for _, id in ipairs(s.rounds or {}) do
    local e = findEvent(id)
    if e then
      rallies = rallies + 1
      for _, st in ipairs(e.stages or {}) do
        stages = stages + 1
        if events.bestPlaceable(e.id, st.id, st) then driven = driven + 1 end
      end
      if #covers < 8 then
        local m = mediaOf(e)
        covers[#covers + 1] = { round = type(e.season) == 'table' and e.season.round or (#covers + 1), name = e.name,
          url = m and m.cover or nil }
      end
      span(dates, datesOf(e.dates))
    end
  end
  if rallies == 0 then return nil end
  local st = seasonData(s).standings
  return { kind = 'season', id = s.id, name = s.name, championship = s.championship, rallies = rallies,
    stages = stages, driven = driven, covers = covers, dates = dates.from and dates or nil,
    you = st.you and { pos = st.you.pos, points = st.you.points, of = st.entries } or nil }
end

-- The Rallies page: { seasons = { M.seasonCard... }, rallies = { card... } }. rallies: every event that is not a
-- round of a season on this computer (nor a retired one: pack.lua), as M.rallyCard plus kind ('rally' | 'stage': one stage, no season), media,
-- dates, place, and for a stage its stageId and best.
function M.home(reports)
  local out, inSeason = { seasons = {}, rallies = {} }, {}
  for _, s in ipairs(events.seasons()) do
    local card = M.seasonCard(s)
    if card then
      out.seasons[#out.seasons + 1] = card
      for _, id in ipairs(s.rounds) do inSeason[id] = true end
    end
  end
  for _, e in ipairs(events.list()) do
    -- (a round its season no longer lists is retired by pack.lua: its times are kept, but it is not a rally of its
    -- own to show)
    if not (inSeason[e.id] and seasonOfEvent(e)) and type(e.retired) ~= 'table' then
      local c = M.rallyCard(e, reports and reports[e.id])
      c.kind = isSingle(e) and 'stage' or 'rally'
      c.media, c.dates, c.place = mediaOf(e), datesOf(e.dates), e.place
      if c.kind == 'stage' then
        c.stageId = e.stages[1].id
        c.best = events.best(e.id, e.stages[1].id)
      end
      out.rallies[#out.rallies + 1] = c
    end
  end
  return out
end

-- A season's page, or nil:
--   { id, name, championship, dates, rallies, finished (rounds with your rally result),
--     rounds = { { id, round, name, dates, place, stages, driven, media, complete, you = { pos, of } | nil,
--       notRanked = true | nil (too few stages match the official distance: you are not placed and score nothing; the crews score as usual),
--       partial = true | nil (you are ranked over the stages that match, not all of them), points } },
--     standings = { rows = top 10 { pos, name, points, wins, you, perRound = { { pos, points, partial } | { points = 0 } |
--       { noBoard = true, points = 0 } | { notRanked = true, points = 0 } } }, you = your row | nil,
--       youShown (you among rows), entries, points = the scale, best = only the best N count | nil,
--       rounds = { { round, name, notRanked } } },
--     next = the round to finish next (the first you have started, else the first) }
function M.season(seasonId)
  local s = events.season(seasonId)
  if not s then return nil end
  local sd = seasonData(s)
  local out = { id = s.id or seasonId, name = s.name, championship = s.championship, rounds = {}, finished = 0 }
  local dates, started, first, labels = {}, nil, nil, {}
  local you = sd.standings.you
  for ri, rd in ipairs(sd.rounds) do
    local e = rd.event
    local round = type(e.season) == 'table' and e.season.round or ri
    local sr = sd.standings.rounds[ri]
    labels[ri] = { round = round, name = e.name, notRanked = sr and sr.notRanked or nil }
    if rd.found then
      local driven = 0
      for _, st in ipairs(e.stages or {}) do if rd.bestByStage[st.id] then driven = driven + 1 end end
      local res = sd.results[ri]
      local pr = you and you.perRound and you.perRound[ri]
      local r = { id = e.id, round = round, name = e.name, dates = datesOf(e.dates), place = e.place,
        stages = #(e.stages or {}), driven = driven, media = mediaOf(e), complete = (res and res.complete) == true,
        you = res and res.you and { pos = res.you.pos, of = res.you.of } or nil,
        notRanked = res and res.notRanked or nil, partial = (res and res.partial and not res.notRanked) or nil,
        points = pr and pr.pos and pr.points or nil }
      out.rounds[#out.rounds + 1] = r
      if r.complete then
        out.finished = out.finished + 1
      else
        if not started and driven > 0 then started = e.name end
        first = first or e.name
      end
      span(dates, r.dates)
    end
  end
  out.rallies = #out.rounds
  out.dates = dates.from and dates or nil
  out.next = started or first
  local st = sd.standings
  local shown = false
  for _, r in ipairs(st.rows) do if r.you then shown = true end end
  out.standings = { rows = st.rows, you = st.you, youShown = shown, entries = st.entries,
    points = st.rules.points, best = st.rules.best, rounds = labels }
  return out
end

return M
