-- earthRally/events: the rallies on this computer, all in the game's user folder (<user folder>/current/...):
--   earthRally/events/<event>.json            a rally (imported from its map: importer.lua, or tools/import_kml.py)
--   earthRally/recce/<event>__<stage>.json    the line driven on the recce (lat / lon / alt every few metres)
--   earthRally/matched/<event>__<stage>.json  the stage's map line matched to BeamNG.Earth's roads, with heights
--                                             (tools/match_roads.py): a stage runs on it without a recce
--   earthRally/results/<event>__<stage>.json  the stage times
-- Files are read once and kept (the window asks for them every frame); what this module writes updates its copy.
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

-- A stage's map line in short (its points, first and last): a matched line made from another version of the map
-- (the map changed and was imported again since) is not used. tools/match_roads.py writes the same as mapKey.
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

-- How far a stage's recce stops short of its flying finish (m; 0 when it reaches it, or the stage has none), worked out
-- once per recce.
function M.recceShortM(r, stage)
  local ff = stage and stage.controls and stage.controls.ff
  if not (r and ff and r.points) then return 0 end
  if not r._shortM then r._shortM = nearestM(r.points, ff.lat, ff.lon) end
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
  local short = r and ((type(r.share) == 'number' and r.share < 0.9) or M.recceShortM(r, stage) >= M.RECCE_SHORT_OF_FF_M)
  if r and (not m or not short) then return r, 'recce' end
  if m then return m, 'matched' end
  return nil
end

-- The junctions and bridges along a stage (found by tools/match_roads.py on the map's roads, kept with its matched
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
