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

-- The line a stage runs on: its recce (what the player drove) first, else the matched map line. Returns the line and
-- 'recce' / 'matched', or nil.
function M.stageLine(eventId, stageId)
  local r = M.recce(eventId, stageId)
  if r then return r, 'recce' end
  local m = M.matched(eventId, stageId)
  if m then return m, 'matched' end
  return nil
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
