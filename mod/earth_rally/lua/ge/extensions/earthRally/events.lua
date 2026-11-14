-- earthRally/events: the rallies on this computer, all in the game's user folder (<user folder>/current/...):
--   earthRally/events/<event>.json            a rally (imported from its map: importer.lua, or tools/import_kml.py)
--   earthRally/recce/<event>__<stage>.json    the line driven on the recce (lat / lon / alt every few metres)
--   earthRally/matched/<event>__<stage>.json  the stage's map line matched to BeamNG.Earth's roads, with heights
--                                             (the auto recce: autoRecce.lua in the game, or tools/auto_recce.py):
--                                             a stage runs on it with no recce
--   earthRally/results/<event>__<stage>.json  the stage times
-- Files are read once and kept (the window asks for them every frame); what this module writes updates its copy.
local lineStats = require('earthRally/lineStats')

local M = {}

M.EVENTS_DIR = '/earthRally/events/'
M.RECCE_DIR = '/earthRally/recce/'
M.MATCHED_DIR = '/earthRally/matched/'
M.RESULTS_DIR = '/earthRally/results/'

local cache = nil
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
function M.forget() files = {} end

-- Every event: { { id, name, stages = {...}, points = {...}, file }... }, sorted by name. Re-read when asked.
function M.list(reload)
  if cache and not reload then return cache end
  if reload then M.forget() end
  cache = {}
  local found = FS:findFiles(M.EVENTS_DIR, '*.json', 0, false, false) or {}
  for _, f in ipairs(found) do
    local ok, e = pcall(jsonReadFile, f)
    if ok and type(e) == 'table' and e.format == 1 and type(e.stages) == 'table' then
      e.file = f
      e.id = e.id or f:match('([^/]+)%.json$')
      cache[#cache + 1] = e
    else
      log('W', 'earthRally', 'not an Earth Rally event file: ' .. tostring(f))
    end
  end
  table.sort(cache, function(a, b) return tostring(a.name) < tostring(b.name) end)
  return cache
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
  if type(line.corners) == 'number' then
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

-- The junctions and bridges along a stage (found by tools/auto_recce.py on the map's roads, kept with its matched
-- line, as lat / lon: they hold whichever line the stage runs on). Returns { { lat, lon, type }... } with type a key
-- of stageWriter.LANDMARKS; empty without a matched line made from this map.
function M.landmarks(eventId, stageId, stage)
  local m = M.matched(eventId, stageId)
  if not m or (stage and m.mapKey and m.mapKey ~= M.mapKey(stage.line)) then return {} end
  local out = {}
  for _, j in ipairs(m.junctions or {}) do
    local t = j[3] == 'turn' and 'atJunction' or j[3] == 'straight' and 'pastJunction' or
      (j[3] == 'fork' and (j[4] == 'left' and 'keepLeft' or 'keepRight')) or nil
    if t then out[#out + 1] = { lat = j[1], lon = j[2], type = t } end
  end
  for _, b in ipairs(m.bridges or {}) do
    out[#out + 1] = { lat = b[1], lon = b[2], type = 'overBridge' }
  end
  return out
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
