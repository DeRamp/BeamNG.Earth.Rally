-- earthRally/events: the rallies on this computer, all in the game's user folder (<user folder>/current/...):
--   earthRally/events/<event>.json            from tools/import_kml.py (lat / lon only)
--   earthRally/recce/<event>__<stage>.json    the line driven on the recce (lat / lon / alt every few metres)
--   earthRally/results/<event>__<stage>.json  the stage times
local M = {}

M.EVENTS_DIR = '/earthRally/events/'
M.RECCE_DIR = '/earthRally/recce/'
M.RESULTS_DIR = '/earthRally/results/'

local cache = nil

-- Every event: { { id, name, stages = {...}, points = {...}, file }... }, sorted by name. Re-read when asked.
function M.list(reload)
  if cache and not reload then return cache end
  cache = {}
  local files = FS:findFiles(M.EVENTS_DIR, '*.json', 0, false, false) or {}
  for _, f in ipairs(files) do
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

local function key(eventId, stageId) return tostring(eventId) .. '__' .. tostring(stageId) .. '.json' end

-- The recce of a stage: { points = { { lat, lon, alt }... }, lengthM, date }, or nil.
function M.recce(eventId, stageId)
  local f = M.RECCE_DIR .. key(eventId, stageId)
  if not FS:fileExists(f) then return nil end
  local ok, r = pcall(jsonReadFile, f)
  return ok and type(r) == 'table' and type(r.points) == 'table' and #r.points >= 2 and r or nil
end

function M.saveRecce(eventId, stageId, recce)
  jsonWriteFile(M.RECCE_DIR .. key(eventId, stageId), recce, true)
end

function M.results(eventId, stageId)
  local f = M.RESULTS_DIR .. key(eventId, stageId)
  if not FS:fileExists(f) then return { runs = {} } end
  local ok, r = pcall(jsonReadFile, f)
  return ok and type(r) == 'table' and r or { runs = {} }
end

function M.addResult(eventId, stageId, run)
  local r = M.results(eventId, stageId)
  r.runs = r.runs or {}
  r.runs[#r.runs + 1] = run
  jsonWriteFile(M.RESULTS_DIR .. key(eventId, stageId), r, true)
  local best = nil
  for _, x in ipairs(r.runs) do
    if x.finished and (not best or x.timeS < best) then best = x.timeS end
  end
  return best
end

return M
