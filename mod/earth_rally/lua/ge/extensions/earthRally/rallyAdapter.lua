-- earthRally/rallyAdapter: everything Earth Rally asks of the game's own rally engine (gameplay_rally, BeamNG.drive
-- 0.40.5), in one place. We use only its co-driver: pacenotes along a driveline, called and shown as in the game's
-- rally stages. Timing is ours (runner.lua), so the stock stage clock, splits and missions are never switched on.
local M = {}

local logTag = 'earthRally'
-- (the paths the game's own modules require them by: the same module tables, so a wrap here is the one they call)
local ZSNAP = '/lua/ge/extensions/editor/rallyEditor/zSnap'
local GEOM = 'editor/toolUtilities/geom'

local function rally()
  if not rawget(_G, 'gameplay_rally') and extensions and extensions.load then extensions.load('gameplay_rally') end
  return rawget(_G, 'gameplay_rally')
end

function M.check()
  local r = rally()
  if not (r and type(r.loadMission) == 'function' and type(r.getRallyManager) == 'function') then
    return false, "this BeamNG.drive's rally engine is not the one Earth Rally knows (0.40.5)"
  end
  local okZ, z = pcall(require, ZSNAP)
  local okG, g = pcall(require, GEOM)
  if not (okZ and type(z.conformSplineGeometry) == 'function' and okG and type(g.catmullRomFree) == 'function') then
    return false, "this BeamNG.drive's rally driveline code is not the one Earth Rally knows (0.40.5)"
  end
  return true
end

-- Load the stage written to `dir` (stageWriter.lua) into the rally engine. The game would set every driveline
-- point down on the terrain block when it loads (zSnap.conformSplineGeometry), and on BeamNG.Earth that block is only
-- the kilometre round the car: the heights we wrote (from the recce) are kept instead, for this load only.
function M.load(id, dir)
  local r = rally()
  if not r then return false, 'no rally engine' end
  local zSnap, geom = require(ZSNAP), require(GEOM)
  local original = zSnap.conformSplineGeometry
  zSnap.conformSplineGeometry = function(spline, _useRaycast, minNumDivisions)
    return geom.catmullRomFree(spline, minNumDivisions, nil, nil)
  end
  local ok, res, why = pcall(r.loadMission, id, dir, nil, nil, { owner = 'external' })
  zSnap.conformSplineGeometry = original
  if not ok then return false, tostring(res) end
  if not res then return false, tostring(why or 'the rally engine did not load it') end
  return true
end

function M.unload()
  local r = rawget(_G, 'gameplay_rally')
  if r and type(r.unloadMission) == 'function' then pcall(r.unloadMission, { owner = 'external' }) end
end

function M.manager()
  local r = rawget(_G, 'gameplay_rally')
  return r and r.getRallyManager and r.getRallyManager() or nil
end

-- What the co-driver is doing: { notes (how many it has), lastCalled (index of the last note called, or nil) }.
function M.status()
  local rm = M.manager()
  if not rm then return nil end
  local notes = 0
  local nb = rm.notebook
  if nb and nb.pacenotes then
    local ok, list = pcall(function() return nb.pacenotes.sorted or nb.pacenotes end)
    if ok and type(list) == 'table' then notes = #list end
  end
  return { notes = notes, lastCalled = rm.lastPlayedPacenoteIdx }
end

-- The heights the rally engine ended up with along its driveline, against ours: the largest difference (m), or nil
-- when it cannot be read. Milestone 0's height check: near 0 means our heights were kept.
function M.heightCheck(ourNodes)
  local rm = M.manager()
  local dl = rm and rm.drivelineV3
  local spline = dl and dl.spline
  local nodes = spline and spline.nodes
  if type(nodes) ~= 'table' or #nodes == 0 then return nil end
  local worst = 0
  for i = 1, math.min(#nodes, #ourNodes) do
    local d = math.abs((nodes[i].z or 0) - (ourNodes[i].z or 0))
    if d > worst then worst = d end
  end
  local div = spline.divPoints
  local lowest = math.huge
  if type(div) == 'table' then
    for _, p in ipairs(div) do if p.z < lowest then lowest = p.z end end
  end
  return worst, lowest
end

-- The stage's pacenotes called or not (the co-driver's own lines, such as the countdown, are not held back): off from
-- the load until GO, as the game's own rally countdown does, so nothing is called on the way to the start.
function M.notesOn(on)
  local rm = M.manager()
  if rm and rm.setPacenoteProcessingEnabled then pcall(rm.setPacenoteProcessingEnabled, rm, on and true or false) end
end

-- The stage's first pacenote called now (as a co-driver reads it before the start). markDone: the engine is told
-- it has been called, so its own call of the first note as the car pulls away (an 'immediate' note) does not repeat it.
function M.callFirstNote(markDone)
  local rm = M.manager()
  local list = rm and rm.notebook and rm.notebook.pacenotes and rm.notebook.pacenotes.sorted
  local pn = list and list[1]
  if not (pn and rm.triggerPacenote) then return false end
  local ok, err = pcall(rm.triggerPacenote, rm, pn)
  if not ok then log('W', logTag, 'first note: ' .. tostring(err)) return false end
  local route = markDone and rm.drivelineRoute
  if route and type(route.events) == 'table' and pn.id then
    local ev = route.events[pn.id] or { disabledByRecalc = false, csDynamicHit = false, csStaticHit = false,
      csMeterOffsetHit = { [-40] = false }, cornerPercentHit = { [0.5] = false }, ceStaticHit = false,
      ceMeterOffsetHit = { [-5] = false } }
    ev.csImmediateHit, ev.audioTriggerComplete = true, true
    route.events[pn.id] = ev
  end
  return true
end

-- One of the co-driver's own lines (the voice pack's system pacenotes: 'countdown5'..'countdown1', 'countdowngo',
-- 'falseStart'), as the game's rally countdown says them.
function M.systemNote(name)
  local rm = M.manager()
  if rm and rm.enqueueRandomSystemPacenote then
    local ok, err = pcall(rm.enqueueRandomSystemPacenote, rm, name)
    if not ok then log('W', logTag, 'co-driver line ' .. name .. ': ' .. tostring(err)) end
  end
end

-- Stage the co-driver for a fresh run (after the car was put at the start line).
function M.resync()
  local rm = M.manager()
  if rm and rm.resyncAfterTeleport then
    local ok, err = pcall(rm.resyncAfterTeleport, rm)
    if not ok then log('W', logTag, 'rally resync failed: ' .. tostring(err)) end
  end
end

return M
