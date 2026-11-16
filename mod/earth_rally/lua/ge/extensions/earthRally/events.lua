-- earthRally/events: the rallies on this computer, all in the game's user folder (<user folder>/current/...):
--   earthRally/events/<event>.json            a rally (imported from its map: importer.lua, or tools/import_kml.py)
--   earthRally/recce/<event>__<stage>.json    the line driven on the recce (lat / lon / alt every few metres)
--   earthRally/matched/<event>__<stage>.json  the stage's map line matched to BeamNG.Earth's roads, with heights
--                                             (the auto recce: autoRecce.lua in the game, or tools/auto_recce.py):
--                                             a stage runs on it with no recce
--   earthRally/results/<event>__<stage>.json  the stage times
--   earthRally/seasons/<season>.json          a season: its rounds (event ids) and standings rules (pack.lua)
--   earthRally/boards/<event>.json            a rally's real results, trimmed to leaderboards (pack.lua)
-- Files are read once and kept (the window asks for them every frame); what this module writes updates its copy.
local lineStats = require('earthRally/lineStats')
local geo = require('earthRally/geo')

local M = {}

M.EVENTS_DIR = '/earthRally/events/'
M.RECCE_DIR = '/earthRally/recce/'
M.MATCHED_DIR = '/earthRally/matched/'
M.RESULTS_DIR = '/earthRally/results/'
M.SEASONS_DIR = '/earthRally/seasons/'
M.BOARDS_DIR = '/earthRally/boards/'
M.IMPORT_INDEX = '/earthRally/importIndex.json'   -- (importer.INDEX: the import folder's last scan)

local cache = nil
local seasonsCache = nil
local files = {}            -- path -> { data } (data nil: no such file, or not a valid one)

local function key(eventId, stageId) return tostring(eventId) .. '__' .. tostring(stageId) .. '.json' end

-- (a JSON file read once; valid(data) says whether it is usable)
local function readOnce(path, valid)
  local f = files[path]
  if f then return f.data end
  local data = nil
  if FS:fileExists(path) then
    local ok, r = pcall(jsonReadFile, path)
    if ok and type(r) == 'table' and (not valid or valid(r)) then data = r end
  end
  files[path] = { data = data }
  return data
end

-- Every file read again from disk next time it is asked for (Reload, an import).
function M.forget() files, seasonsCache = {}, nil end

-- (#50) Is an event's file still in the import folder, by the importer's last scan (index: importIndex.json, read
-- once per list)? Only the rallies whose file is there are shown; the rest stay on disk, times, lines and saves and
-- all, and come back when the file does.
--   - a pack's rally: while a pack in the index lists its id. A pack taken out, or updated so its rallies have new
--     ids, no longer lists the old one. (A round its season no longer lists is retired by pack.lua: kept to its pack
--     while the pack is here, off Home but its page still there, as before.)
--   - a loose map's rally: hidden once the importer has noted its file gone (index.gone), unless a file in the folder
--     has its id again.
--   - a rally the import folder never had (tools/import_kml.py's, the author's own): shown.
-- No index (nothing scanned yet, or unreadable): everything shown.
local function folderCheck(index)
  if type(index) ~= 'table' or type(index.files) ~= 'table' then return function() return true end end
  local packs = type(index.packs) == 'table' and index.packs or {}
  local gone = type(index.gone) == 'table' and index.gone or {}
  local packIds, fileIds = {}, {}
  for _, p in pairs(packs) do
    for _, id in ipairs(type(p) == 'table' and type(p.eventIds) == 'table' and p.eventIds or {}) do packIds[id] = true end
  end
  for _, f in pairs(index.files) do if type(f) == 'table' and f.eventId then fileIds[f.eventId] = true end end
  return function(e)
    if type(e.pack) == 'table' and e.pack.file then
      if packIds[e.id] then return true end
      return type(e.retired) == 'table' and packs[e.pack.file] ~= nil
    end
    return gone[e.id] == nil or fileIds[e.id] == true or packIds[e.id] == true
  end
end
M._folderCheck = folderCheck

-- Every event whose file is still in the import folder (folderCheck): { { id, name, stages = {...}, points = {...},
-- file }... }, sorted by name. Re-read when asked.
function M.list(reload)
  if cache and not reload then return cache end
  if reload then M.forget() end
  cache = {}
  local okI, index = pcall(function() return FS:fileExists(M.IMPORT_INDEX) and jsonReadFile(M.IMPORT_INDEX) or nil end)
  local shown = folderCheck(okI and index or nil)
  local found = FS:findFiles(M.EVENTS_DIR, '*.json', 0, false, false) or {}
  local hidden = 0
  for _, f in ipairs(found) do
    local ok, e = pcall(jsonReadFile, f)
    if ok and type(e) == 'table' and e.format == 1 and type(e.stages) == 'table' then
      e.file = f
      e.id = e.id or f:match('([^/]+)%.json$')
      if shown(e) then cache[#cache + 1] = e else hidden = hidden + 1 end
    else
      log('W', 'earthRally', 'not an Earth Rally event file: ' .. tostring(f))
    end
  end
  if hidden > 0 then
    log('I', 'earthRally', string.format('%d rall%s not shown: %s file is no longer in the import folder (kept on disk)',
      hidden, hidden == 1 and 'y' or 'ies', hidden == 1 and 'its' or 'their'))
  end
  table.sort(cache, function(a, b) return tostring(a.name) < tostring(b.name) end)
  return cache
end

local function seasonValid(r) return r.format == 1 and type(r.rounds) == 'table' end

-- A season: { id, name, championship, rounds = { eventId... }, standings = { championship, points, best } }, or nil.
function M.season(id) return readOnce(M.SEASONS_DIR .. tostring(id) .. '.json', seasonValid) end

-- Every season, sorted by name. Re-read after an import (M.list(true) or M.forget()).
function M.seasons()
  if seasonsCache then return seasonsCache end
  seasonsCache = {}
  for _, f in ipairs(FS:findFiles(M.SEASONS_DIR, '*.json', 0, false, false) or {}) do
    local s = readOnce(f, seasonValid)
    if s then
      s.id = s.id or f:match('([^/]+)%.json$')
      seasonsCache[#seasonsCache + 1] = s
    end
  end
  table.sort(seasonsCache, function(a, b) return tostring(a.name) < tostring(b.name) end)
  return seasonsCache
end

-- A rally's leaderboards from its real results: { passes = { { ss, stage, run, km, cancelled, field }... } }, or
-- nil when it has none.
function M.boards(rallyId)
  return readOnce(M.BOARDS_DIR .. tostring(rallyId) .. '.json', function(r) return type(r.passes) == 'table' end)
end

local function lineValid(r) return type(r.points) == 'table' and #r.points >= 2 end

-- The recce of a stage: { points = { { lat, lon, alt }... }, lengthM, date }, or nil.
function M.recce(eventId, stageId) return readOnce(M.RECCE_DIR .. key(eventId, stageId), lineValid) end

function M.saveRecce(eventId, stageId, recce)
  local path = M.RECCE_DIR .. key(eventId, stageId)
  jsonWriteFile(path, recce, true)
  files[path] = { data = recce }
end

-- The stage's map line matched to the roads: { points = { { lat, lon, alt }... }, gaps = { {fromM, toM}... }, ... }.
function M.matched(eventId, stageId) return readOnce(M.MATCHED_DIR .. key(eventId, stageId), lineValid) end

-- Remove a stage's line so the stage is as it was before it had one: { matched = true?, recce = true? } naming what
-- was there, or nil and why. The menu's Reset button (main.lua, 'reset').
--
-- **Both kinds, deliberately.** M.stageLine picks between a driven recce and a matched line when a stage has both
-- -- the driven one wins unless it is short -- so removing only the one in use would leave the other to answer it
-- and the stage would still have a line, its pill unchanged. The player would press Reset and watch nothing
-- happen. "Reset" has to mean there is no line at all.
--
-- A file that will not delete is reported rather than shrugged off: the caller has told the player their line is
-- gone, and on the next poll it would be back.
function M.resetLine(eventId, stageId)
  local out = {}
  for _, k in ipairs({ { 'recce', M.RECCE_DIR }, { 'matched', M.MATCHED_DIR } }) do
    local kind, path = k[1], k[2] .. key(eventId, stageId)
    if FS:fileExists(path) then
      pcall(FS.removeFile, FS, path)
      if FS:fileExists(path) then
        files[path] = nil
        return nil, "that line's file could not be removed (" .. path .. ')'
      end
      out[kind] = true
    end
    -- read from disk again next time, whether or not there was a file: readOnce caches the absence too, so
    -- without this a stage reset and then recced again would go on looking empty until the next Reload.
    files[path] = nil
  end
  return out
end

-- Save a matched line (the auto recce's, autoRecce.lua). Written whole and in one call, and only ever called with a
-- line that covers the whole stage: lineValid above checks a line has two points and no more than that, so a
-- half-covered file would read as runnable and the car would be driven off the end of it. The copy kept here is
-- updated with it, or the menu and the runner would go on seeing no matched line until the next Reload.
function M.saveMatched(eventId, stageId, matched)
  local path = M.MATCHED_DIR .. key(eventId, stageId)
  -- (the bridges added to the line matched before -- tools/auto_recce.py --bridges-only, from BeamNG.Earth's level
  --  ranges -- are kept when the game's recce, which cannot see bridges, matches it again: as lat / lon they hold
  --  the new line too). Read from disk, not the copy kept here: the tool may have added them after the game read
  --  the file. (A Reset removes the file, and its bridges with it: --bridges-only adds them again.)
  files[path] = nil
  local okOld, old = pcall(M.matched, eventId, stageId)
  if type(matched) == 'table' and type(matched.bridges) == 'table' and #matched.bridges == 0 and okOld and
     type(old) == 'table' and type(old.bridges) == 'table' and #old.bridges > 0 then
    matched.bridges, matched.bridgesSource = old.bridges, old.bridgesSource or 'kept from the line matched before'
  end
  -- (through a temporary file where the game's file system can rename one, so a matched line is replaced whole: a
  -- write interrupted part way through would otherwise leave a shorter line that still passes lineValid. Where it
  -- cannot, the single jsonWriteFile below is the write.)
  local tmp = path .. '.part'
  if type(FS.renameFile) == 'function' then
    jsonWriteFile(tmp, matched, true)
    local ok, done = pcall(FS.renameFile, FS, tmp, path)
    if not (ok and done ~= false) then
      pcall(FS.removeFile, FS, tmp)
      jsonWriteFile(path, matched, true)
    end
  else
    jsonWriteFile(path, matched, true)
  end
  files[path] = { data = matched }
  return path
end

-- A stage's map line in short (its points, first and last): a matched line made from another version of the map
-- (the map changed and was imported again since) is not used. tools/auto_recce.py writes the same as mapKey.
function M.mapKey(line)
  if type(line) ~= 'table' or #line == 0 then return nil end
  local a, b = line[1], line[#line]
  return string.format('%d:%.6f:%.6f:%.6f:%.6f', #line, a[1], a[2], b[1], b[2])
end

-- How far a line comes to a point at the nearest (m, flat): how close a recce gets to the flying finish.
local function nearestM(points, lat, lon)
  local best = math.huge
  local kx = 111195 * math.cos(math.rad(lat))
  for _, p in ipairs(points) do
    local d = ((p[1] - lat) * 111195) ^ 2 + ((p[2] - lon) * kx) ^ 2
    if d < best then best = d end
  end
  return math.sqrt(best)
end

-- A recce that never reaches the flying finish (stopped this far before it, or more) is short: e.g. one recorded by
-- 1.0, which saved where the recce ended, not where the stage did.
M.RECCE_SHORT_OF_FF_M = 25

-- How far a stage's recce stops short of its flying finish (m): how much further the flying finish's pin is from the
-- recce than from the matched line on the roads (a pin standing off the road is as far from both, and not "short").
-- 0 when it reaches it, or there is no matched line to tell by. Worked out once per recce.
function M.recceShortM(r, stage, m)
  local ff = stage and stage.controls and stage.controls.ff
  if not (r and ff and r.points and m and m.points) then return 0 end
  if not r._shortM or r._shortFor ~= m.points then
    r._shortM = math.max(0, nearestM(r.points, ff.lat, ff.lon) - nearestM(m.points, ff.lat, ff.lon))
    r._shortFor = m.points
  end
  return r._shortM
end

-- The line a stage runs on: its recce (what the player drove) first, unless it is short (saved before the end with
-- "Save anyway", or stopping before the flying finish) and a matched line covers the whole stage; else the matched map
-- line (when it was made from this map). stage: the event's stage (for the map check). Returns the line and
-- 'recce' / 'matched', or nil.
function M.stageLine(eventId, stageId, stage)
  local r = M.recce(eventId, stageId)
  local m = M.matched(eventId, stageId)
  if m and stage and m.mapKey and m.mapKey ~= M.mapKey(stage.line) then m = nil end
  local short = r and ((type(r.share) == 'number' and r.share < 0.9) or M.recceShortM(r, stage, m) >= M.RECCE_SHORT_OF_FF_M)
  if r and (not m or not short) then return r, 'recce' end
  if m then return m, 'matched' end
  return nil
end

-- What the stage's own line says about itself: { corners, gainM, lossM } (lineStats.lua), or nil when the stage has
-- no line at all -- the one state those numbers genuinely cannot be had in. gainM and lossM are absent on a line
-- with no heights.
--
-- A line saved by 1.3.1 or later carries its figures in its own file, written when it was saved (recce.lua,
-- autoRecce.lua). A line saved before that has none, and they are worked out here instead: once, kept on the line
-- table this module already holds, for as long as the file stays read -- never on each look, because the stage
-- page asks for a stage every two seconds while it is open and the longest line in the user's set resamples to
-- about 9,800 samples. (recceShortM above keeps its own figure the same way, and against the same points.) The
-- file is left exactly as it was written: looking at a page does not rewrite the player's lines.
function M.lineFigures(eventId, stageId, stage)
  local line = M.stageLine(eventId, stageId, stage)
  if not line then return nil end
  if type(line.corners) == 'number' and line.figures == lineStats.VERSION then
    return { corners = line.corners, gainM = line.gainM, lossM = line.lossM }
  end
  if not line._figures or line._figuresFor ~= line.points then
    local ok, fig = pcall(lineStats.of, line.points, stage)
    if not ok then
      log('W', 'earthRally', string.format('the line of %s could not be measured: %s', key(eventId, stageId),
        tostring(fig)))
      fig = nil
    end
    line._figures, line._figuresFor = fig or {}, line.points
  end
  return line._figures
end

-- The junctions, bridges and narrowings along a stage (found by an auto recce on the map's roads, kept with its matched
-- line, as lat / lon: they hold whichever line the stage runs on). Returns { { lat, lon, type }... } with type a key
-- of stageWriter.LANDMARKS (a bridge with endLat, endLon too, its far end, when the recce has it); empty without a
-- matched line made from this map.
function M.landmarks(eventId, stageId, stage)
  local m = M.matched(eventId, stageId)
  if not m or (stage and m.mapKey and m.mapKey ~= M.mapKey(stage.line)) then return {} end
  local out = {}
  local J = require('earthRally/junctions')
  for _, j in ipairs(m.junctions or {}) do
    local t = j[3] == 'turn' and 'atJunction' or j[3] == 'straight' and 'pastJunction' or
      (j[3] == 'fork' and (j[4] == 'left' and 'keepLeft' or 'keepRight')) or nil
    -- (only a side road a driver could take by mistake: junctions.obvious)
    if t and J.obvious(J.decode(j)) then out[#out + 1] = { lat = j[1], lon = j[2], type = t } end
  end
  for _, b in ipairs(m.bridges or {}) do
    out[#out + 1] = { lat = b[1], lon = b[2], type = 'overBridge',
                      endLat = tonumber(b[3]), endLon = tonumber(b[4]) }
  end
  for _, nw in ipairs(m.narrows or {}) do
    out[#out + 1] = { lat = nw[1], lon = nw[2], type = 'narrows' }
  end
  return out
end

-- The organisers' points on a stage (importer.build's `marks`: { { kind, name, lat, lon, distM, offLineM }... }, one
-- entry per kind) as they are stored; an empty list for a stage the map marks none on (or an event or stage not
-- here). stage: the stage's table, if the caller has it (else found by its ids).
function M.marks(eventId, stageId, stage)
  if not stage then
    for _, e in ipairs(M.list()) do
      if e.id == eventId then
        for _, s in ipairs(e.stages or {}) do if s.id == stageId then stage = s break end end
        break
      end
    end
  end
  local out = {}
  for _, m in ipairs(stage and type(stage.marks) == 'table' and stage.marks or {}) do
    if type(m) == 'table' and type(m.kind) == 'string' and type(m.lat) == 'number' and type(m.lon) == 'number' then
      out[#out + 1] = m
    end
  end
  return out
end

-- The kinds of organisers' point the rally's map marks on ANY of its stages -- { radio = bool, medical = bool,
-- spectator = bool, marshal = bool } -- counting only the marks some stage would use: within its span and its
-- off-line limit, stageMarks' own test (1.6.0's note 5: a kind marked anywhere in the rally is never filled in by
-- chance on a stage that has none of it; dressing.plan's mapKinds, and the stage page's None. Review round 4: a mark
-- no stage uses -- far off every line, past every finish -- turned the chance off for nothing). event: the event's
-- table, if the caller has it (else found by its id).
function M.markedKinds(eventId, event)
  local out = { radio = false, medical = false, spectator = false, marshal = false }
  if not event then
    for _, e in ipairs(M.list()) do if e.id == eventId then event = e break end end
  end
  for _, s in ipairs(event and type(event.stages) == 'table' and event.stages or {}) do
    for kind, n in pairs(M.stageMarks(eventId, s.id, s)) do
      if out[kind] ~= nil and n > 0 then out[kind] = true end
    end
  end
  return out
end

-- For the stage page: how many of each kind of organisers' point the map marks on a stage --
-- { radio = n, medical = n, spectator = n, marshal = n } (a kind it marks none of 0: the dressing fills it in, all but
-- medical, by chance -- unless the rally marks that kind on another stage: markedKinds). Counted with the dressing's
-- own tests, on the map's line: within MARKS_OFF_LINE_M of it
-- (runner.MARKS_OFF_LINE_M) and from MARKS_SPAN_PAD_M before the start control to as far past the flying finish
-- (dressing.plan's span; with no start / finish control on the line, its ends). The dressing measures on the line
-- driven, which can lie a few metres from the map's, so a point right at one of those limits can still count here
-- and not there.
M.MARKS_OFF_LINE_M = 100
M.MARKS_SPAN_PAD_M = 100
function M.stageMarks(eventId, stageId, stage)
  local n = { radio = 0, medical = 0, spectator = 0, marshal = 0 }
  local list = M.marks(eventId, stageId, stage)
  if #list == 0 then return n end
  if not stage then
    for _, e in ipairs(M.list()) do
      if e.id == eventId then
        for _, s in ipairs(e.stages or {}) do if s.id == stageId then stage = s break end end
        break
      end
    end
  end
  local ctl = stage and type(stage.controls) == 'table' and stage.controls or {}
  local total = stage and tonumber(stage.lengthM) or math.huge
  local function at(c, default)
    if type(c) ~= 'table' or type(c.distM) ~= 'number' then return default end
    if type(c.offLineM) == 'number' and c.offLineM > M.CONTROL_OFF_LINE_M then return default end
    return c.distM
  end
  local s0, s1 = at(ctl.start, 0), at(ctl.ff, total)
  if s1 <= s0 + 100 then s0, s1 = 0, total end
  for _, m in ipairs(list) do
    local d, off = tonumber(m.distM), tonumber(m.offLineM)
    local onLine = not off or off <= M.MARKS_OFF_LINE_M
    local inSpan = not d or (d >= s0 - M.MARKS_SPAN_PAD_M and d <= s1 + M.MARKS_SPAN_PAD_M)
    if n[m.kind] and onLine and inSpan then n[m.kind] = n[m.kind] + 1 end
  end
  return n
end

-- The junctions along a stage with their roads, for the stage dressing (course tape, direction boards): from the
-- matched line, as junctions.lua reads its entries -- { { lat, lon, kind, side, inDeg, outDeg, sides }... }, the
-- last three nil in a format 1 file, which kept no roads (an Auto recce run again writes them). nil without a
-- matched line made from this map.
function M.junctions(eventId, stageId, stage)
  local m = M.matched(eventId, stageId)
  if not m or (stage and m.mapKey and m.mapKey ~= M.mapKey(stage.line)) then return nil end
  local J = require('earthRally/junctions')
  local out = {}
  for _, e in ipairs(m.junctions or {}) do
    local j = J.decode(e)
    if j then out[#out + 1] = j end
  end
  return out
end

-- A time control (kind 'atc' / 'stop') put on the road beside it by the auto recce (autoRecce.controlOnRoad, kept in
-- the matched file's `controls`): { lat, lon (the road point), deg (the road's bearing there, either way), offM }, or
-- nil -- no matched file, an older one, or one made from where the map's control was before it moved (ctl: the
-- control as the map has it now; more than CONTROL_SAME_M from the point the recce had, and the road point is not
-- its).
M.CONTROL_SAME_M = 2
function M.controlOnRoad(eventId, stageId, kind, ctl)
  if type(ctl) ~= 'table' or type(ctl.lat) ~= 'number' or type(ctl.lon) ~= 'number' then return nil end
  local okM, m = pcall(M.matched, eventId, stageId)
  local c = okM and type(m) == 'table' and type(m.controls) == 'table' and m.controls[kind]
  if type(c) ~= 'table' or type(c.lat) ~= 'number' or type(c.lon) ~= 'number' or type(c.roadLat) ~= 'number' or
    type(c.roadLon) ~= 'number' then return nil end
  if geo.metres(c.lat, c.lon, ctl.lat, ctl.lon) > M.CONTROL_SAME_M then return nil end
  return { lat = c.roadLat, lon = c.roadLon, deg = tonumber(c.deg), offM = tonumber(c.offM) }
end

-- A driven line in short, kept with each time as a record (runner.lua, at the start of a run): its kind and its
-- points in short (how many, the first, the middle and the last, to about a metre). Only a record: whether a time is
-- on the current line is M.onLine's, by tolerance, as a line matched again a metre over is the same road. nil with
-- no line.
function M.lineKey(line, kind)
  local pts = type(line) == 'table' and line.points
  if type(pts) ~= 'table' or #pts == 0 then return nil end
  local a, m, b = pts[1], pts[math.floor((#pts + 1) / 2)], pts[#pts]
  return string.format('%s:%d:%.5f:%.5f:%.5f:%.5f:%.5f:%.5f', tostring(kind or 'line'), #pts, a[1], a[2], m[1], m[2],
    b[1], b[2])
end

-- How the runner finds the start and the flying finish on the line it times (runner.lua uses these, so the two
-- measure the same): a control more than CONTROL_OFF_LINE_M off the recce or matched line is not on it (the line's
-- own end is used); the line is then carried on TIMING_RUN_OUT_M past its end (a recce may stop short of the
-- finish), and a control within CONTROL_ON_LINE_M of that is where it is on it. Start and finish less than 100 m
-- apart: the whole line.
M.CONTROL_OFF_LINE_M = lineStats.CONTROL_OFF_LINE_M
M.TIMING_RUN_OUT_M = 300
M.CONTROL_ON_LINE_M = 60

-- Start to flying finish on a recce or matched line ({ points = { { lat, lon }... } }), as the runner times it
-- (runner.lua's stageLatLon and project, here in a flat frame of metres): { lengthM, start = { lat, lon }, finish =
-- { lat, lon } } (where the two are on the line; the finish may be on the run-out past its end), or nil with no
-- line. stage: the event's stage (its controls). Kept on the line (it is asked for every stage on every look at a
-- rally page), worked out again only when the points or the stage change.
function M.timedSpan(line, stage)
  local pts = type(line) == 'table' and line.points
  if type(pts) ~= 'table' or #pts < 2 then return nil end
  if line._span and line._spanFor == pts and line._spanStage == stage then return line._span end
  local o = pts[1]
  local mLat = geo.metres(o[1], o[2], o[1] + 0.01, o[2]) / 0.01
  local mLon = math.max(1e-6, geo.metres(o[1], o[2], o[1], o[2] + 0.01) / 0.01)
  local function flat(lat, lon)
    return { x = geo.metres(o[1], o[2], o[1], lon) * (lon < o[2] and -1 or 1),
             y = geo.metres(o[1], o[2], lat, o[2]) * (lat < o[1] and -1 or 1) }
  end
  local xy = {}
  for i, p in ipairs(pts) do xy[i] = flat(p[1], p[2]) end
  local cum = geo.cumulative(xy)
  local total = cum[#cum]
  local ctl = type(stage) == 'table' and type(stage.controls) == 'table' and stage.controls or {}
  local function ok(c) return type(c) == 'table' and type(c.lat) == 'number' and type(c.lon) == 'number' end
  -- (as stageLatLon: on the line itself)
  local function along(c, default)
    if not ok(c) then return default end
    local _, _, s, off = geo.locate(xy, cum, flat(c.lat, c.lon))
    if off > M.CONTROL_OFF_LINE_M then return default end
    return s
  end
  local s, f = along(ctl.start, 0), along(ctl.ff, total)
  if f <= s + 100 then s, f = 0, total end
  -- (as project: on the line carried on past its end)
  local ext = geo.extend(xy, M.TIMING_RUN_OUT_M, false)
  local cumE = geo.cumulative(ext)
  local function at(c)
    if not ok(c) then return nil end
    local _, _, sa, off = geo.locate(ext, cumE, flat(c.lat, c.lon))
    return off <= M.CONTROL_ON_LINE_M and sa or nil
  end
  s = at(ctl.start) or s
  local fa = at(ctl.ff)
  if fa and fa > s + 100 then f = fa end
  local function ll(d)
    local p = geo.pointAt(ext, cumE, d)
    return { o[1] + p.y / mLat, o[2] + p.x / mLon }
  end
  local span = { lengthM = f - s, start = ll(s), finish = ll(f) }
  line._span, line._spanFor, line._spanStage = span, pts, stage
  return span
end

-- Start to flying finish on a recce or matched line (m), as the runner times it (M.timedSpan), or nil.
function M.drivenLengthM(line, stage)
  local span = M.timedSpan(line, stage)
  return span and span.lengthM or nil
end

-- The line a stage is timed on now, in short: { kind = 'recce' | 'matched', key = M.lineKey, lengthM = start to
-- flying finish on it, start, finish = where those are on it ({ lat, lon }) }, or nil when it has none (then the
-- map's line is all there is to measure).
function M.stageLineInfo(eventId, stageId, stage)
  local line, kind = M.stageLine(eventId, stageId, stage)
  if not line then return nil end
  local span = M.timedSpan(line, stage) or {}
  return { kind = kind, key = M.lineKey(line, kind), lengthM = span.lengthM, start = span.start,
    finish = span.finish }
end

-- Whether a saved time is on the line the stage is timed on now (info: M.stageLineInfo): its recorded start to
-- flying finish (lineM) within LINE_SAME_SHARE of the current line's (LINE_SAME_MIN_M at least), and its recorded
-- start and finish (lineStart, lineFinish) each within LINE_SAME_END_M of the current ones. The same road matched
-- again, or driven again on a recce, keeps its times; another route between the same ends does not. A time that
-- recorded nothing (saved before times carried their line) is on it; one that recorded a line while the stage has
-- none now is not; one with a length but no ends (saved before ends were kept) is judged by its length.
M.LINE_SAME_SHARE = 0.01
M.LINE_SAME_MIN_M = 30
M.LINE_SAME_END_M = 25
local function nearLL(a, b)
  if type(a) ~= 'table' or type(b) ~= 'table' or type(a[1]) ~= 'number' or type(a[2]) ~= 'number' or
    type(b[1]) ~= 'number' or type(b[2]) ~= 'number' then
    return false
  end
  return geo.metres(a[1], a[2], b[1], b[2]) <= M.LINE_SAME_END_M
end
function M.onLine(x, info)
  if type(x) ~= 'table' then return false end
  if x.lineM == nil and x.lineStart == nil and x.lineFinish == nil and x.lineKey == nil then return true end
  if not info then return false end
  if x.lineM ~= nil then
    if type(x.lineM) ~= 'number' or type(info.lengthM) ~= 'number' then return false end
    local tol = math.max(M.LINE_SAME_MIN_M, M.LINE_SAME_SHARE * info.lengthM)
    if math.abs(x.lineM - info.lengthM) > tol then return false end
  end
  if x.lineStart ~= nil and not nearLL(x.lineStart, info.start) then return false end
  if x.lineFinish ~= nil and not nearLL(x.lineFinish, info.finish) then return false end
  return true
end

function M.results(eventId, stageId)
  return readOnce(M.RESULTS_DIR .. key(eventId, stageId)) or { runs = {} }
end

-- The best finished time of a stage, or nil.
function M.best(eventId, stageId)
  local best = nil
  for _, x in ipairs(M.results(eventId, stageId).runs or {}) do
    if x.finished and type(x.timeS) == 'number' and (not best or x.timeS < best) then best = x.timeS end
  end
  return best
end

-- Your best finished time on the line the stage runs on now (M.onLine): what is placed on leaderboards and counted
-- in rally results. A time driven on another line (another route, a stage with no line since a reset) still shows
-- in Your runs (M.best), but is not placed. stage: the event's stage (for M.stageLine's map check).
function M.bestPlaceable(eventId, stageId, stage)
  local info = M.stageLineInfo(eventId, stageId, stage)
  local best = nil
  for _, x in ipairs(M.results(eventId, stageId).runs or {}) do
    if x.finished and type(x.timeS) == 'number' and M.onLine(x, info) and
      (not best or x.timeS < best) then
      best = x.timeS
    end
  end
  return best
end

-- run: { finished, timeS, ..., line = 'recce' | 'matched', lineKey = M.lineKey of that line (a record only),
-- lineM = start to flying finish on it as timed, lineStart / lineFinish = where those were on it ({ lat, lon }) }.
-- Returns the best time (M.best).
function M.addResult(eventId, stageId, run)
  local path = M.RESULTS_DIR .. key(eventId, stageId)
  local r = M.results(eventId, stageId)
  r.runs = r.runs or {}
  r.runs[#r.runs + 1] = run
  jsonWriteFile(path, r, true)
  files[path] = { data = r }
  return M.best(eventId, stageId)
end

return M
