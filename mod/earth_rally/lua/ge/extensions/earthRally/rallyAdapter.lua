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
  M.openingM = nil           -- (the stage's own, set after the load: M.setOpening)
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
  -- (#65: said in the log, so a stage with no notes heard shows whether they were ever switched on)
  if rm and rm.setPacenoteProcessingEnabled then
    local ok = pcall(rm.setPacenoteProcessingEnabled, rm, on and true or false)
    log('I', logTag, 'co-driver: pacenotes ' .. (on and 'on' or 'off') .. (ok and '' or ' (the rally engine refused)'))
    if on then M.applyOpening() end
  else
    log('W', logTag, 'co-driver: pacenotes ' .. (on and 'on' or 'off') .. ' asked, but no rally engine is loaded')
  end
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

-- The calls the player's co-driver voice can say: { [call] = true } off the english style its voice pack is made for
-- (gameplay/rally/compositors/styles/<style>.lua: its modifiers and their aliases; its corner shapes as
-- 'shape:<name>' and descriptors as 'descriptor:<name>'), and that style's name. The casual voices (four of the
-- game's seven packs) say a dozen of the calls the detailed ones do, no corner shape at all, and nothing for the
-- rest, so stageWriter.build leaves those out rather than writing notes that are silent. nil when it cannot be told
-- (another game version, no voice pack): then every call is written, as before. Read from the player's chosen voice
-- (our missions carry none of their own) when the notes are built: a voice changed in Options during a run is used
-- from the next run (a retry rebuilds them).
M.VOICEPACK = '/lua/ge/extensions/gameplay/rally/voicepack'
M.STYLES = '/lua/ge/extensions/gameplay/rally/compositors/styles/'
function M.speaks()
  local okV, vp = pcall(require, M.VOICEPACK)
  if not okV or type(vp) ~= 'table' or type(vp.resolveEffectiveEntry) ~= 'function' then return nil end
  -- (a new profile's empty voice list: the game's default voice put in first, as the game does on a rally load)
  if type(vp.ensureSettingsInitialized) == 'function' then pcall(vp.ensureSettingsInitialized, {}) end
  local okE, _, entry = pcall(vp.resolveEffectiveEntry, nil, nil, { globalOnly = true, writeSettings = false })
  local style = okE and type(entry) == 'table' and entry.compositorStyle or nil
  if type(style) ~= 'string' or not style:match('^[%w_/]+$') then return nil end
  local okS, st = pcall(require, M.STYLES .. style)
  local ct = okS and type(st) == 'table' and st.componentTypes or nil
  if type(ct) ~= 'table' or type(ct.modifiers) ~= 'table' then return nil end
  local out = {}
  for name in pairs(ct.modifiers) do out[name] = true end
  for name in pairs(type(ct.modifierAliases) == 'table' and ct.modifierAliases or {}) do out[name] = true end
  local corner = type(ct.corner) == 'table' and ct.corner or {}
  -- (its ladder: the most diameter of each grade but the last -- the step a note carries moves along this one)
  local ladder = nil
  local num = type(corner.numbering) == 'table' and corner.numbering.intensity or nil
  if type(num) == 'table' then
    ladder = {}
    for _, e in ipairs(num) do
      if type(e) == 'table' and type(e.diameter) == 'table' and type(e.diameter.max) == 'number' then
        ladder[#ladder + 1] = e.diameter.max
      end
    end
    if #ladder == 0 or #ladder ~= #num - 1 then ladder = nil end
  end
  for _, key in ipairs({ 'shapes', 'shapeAliases', 'descriptors', 'descriptorAliases' }) do
    local prefix = key:find('^shape') and 'shape:' or 'descriptor:'
    for name in pairs(type(corner[key]) == 'table' and corner[key] or {}) do out[prefix .. name] = true end
  end
  return out, style, ladder
end

-- Stage the co-driver for a fresh run (after the car was put at the start line).
function M.resync()
  local rm = M.manager()
  if rm and rm.resyncAfterTeleport then
    local ok, err = pcall(rm.resyncAfterTeleport, rm)
    if not ok then log('W', logTag, 'rally resync failed: ' .. tostring(err)) end
  end
  M.applyOpening()
end

-- The first call says how far its corner is ("600 caution two right"): stageWriter.openingCall. The game clears
-- every note's `before` field and fills in the distance calls itself (path.autofillDistanceCalls) whenever the rally
-- engine builds its assets -- the stage's load, and a voice pack change (reloadVoicepackAssets); a resync after a
-- teleport, a settings change or a reset leaves the field alone, but recompiles the note's words from it. So it is
-- set after the load (M.setOpening) and set again on every resync and at GO (M.applyOpening: nothing done when it
-- is there already). Said from the voice pack's audio for that distance, the same clip as a distance after a note
-- (pacenote.audioItemsStructuredOffline: a phrase per word group, the distance one of them); a style with no distance
-- calls (the casual voices) says nothing for it, as for every distance.
M.BLOCKER = '#'           -- rallyUtil.autofill_blocker: a field the notebook's author fixed
M.openingM = nil

-- m: the metres from the start line to the first note's corner start (stageWriter's built.openingM), or nil: none.
function M.setOpening(m)
  M.openingM = m
  return M.applyOpening()
end

-- The opening distance put on the loaded notebook's first note, if it is not there. True when it is there.
function M.applyOpening()
  local m = M.openingM
  if not m then return false end
  local writer = require('earthRally/stageWriter')
  if not (m >= writer.OPENING_MIN_M) then return false end   -- (as openingCall: one at 80 m is said)
  local rm = M.manager()
  local nb = rm and rm.notebook
  local ok, pn = pcall(function() return nb.pacenotes.sorted[1] end)
  if not ok or type(pn) ~= 'table' or type(pn.setNoteFieldBefore) ~= 'function' or
     type(pn.getNoteFieldBefore) ~= 'function' then
    return false
  end
  -- (the voice's own distance rules, as autofill reads them: its text compositor's style)
  local rules = nil
  local okC, comp = pcall(nb.getTextCompositor, nb)
  if okC and type(comp) == 'table' then
    if type(comp.distanceCallsEnabled) == 'function' then
      local okE, on = pcall(comp.distanceCallsEnabled, comp)
      if okE and on == false then return false end
    end
    if type(comp.getConfig) == 'function' then
      local okG, cfg = pcall(comp.getConfig, comp)
      if okG and type(cfg) == 'table' and type(cfg.distance) == 'table' then rules = cfg.distance end
    end
  end
  local okS, str = pcall(writer.openingCall, { openingM = m }, rules)
  if not okS then str = writer.openingCall({ openingM = m }) end
  if not str then return false end
  -- (the words as the game's own compositor rounds them, where it can: the same as ours today, and not left behind
  --  if a game update changes them)
  if okC and type(comp) == 'table' and type(comp.distanceToString) == 'function' then
    local okD, s = pcall(comp.distanceToString, comp, m)
    if okD and type(s) == 'string' and s ~= '' then str = s end
  end
  local okB, cur = pcall(pn.getNoteFieldBefore, pn)
  if okB and cur == M.BLOCKER then return false end
  if okB and cur == str then return true end
  local okW, err = pcall(function()
    pn:setNoteFieldBefore(str, m)
    -- (the words and audio the queue plays are compiled once and cached: compiled again with the distance)
    if type(pn.clearCachedFgData) == 'function' then pn:clearCachedFgData() end
    if type(pn.asCompiled) == 'function' then pn:asCompiled() end
  end)
  if not okW then
    log('W', logTag, 'co-driver: opening distance not set: ' .. tostring(err))
    return false
  end
  log('I', logTag, string.format('co-driver: the first call opens with "%s" (%.0f m to its corner)', str, m))
  return true
end

-- The pacenote rebuild's self-check (2026-11-20, step 6). Each corner's grade is ours (pacenotes.fitRadius), and the
-- note carries the step that makes the game's own measurement say it -- worked out offline against the game's
-- rally Lua of 0.40.5 (the circle through the note's ends and the road half way, on its one to six ladder). If a
-- game update measures differently, every corner is called a grade or more out and nothing else shows it. So after
-- the load, each corner note's measurement is read back from the engine (its structuredForProjection, what its
-- compositors say the note from) and graded as we graded the circle: { checked, same, far }, or nil when the
-- engine's notes cannot be read. Fewer than GRADE_CHECK_SHARE the same, over GRADE_CHECK_MIN or more, is a mismatch.
-- far: the corners the game grades two or more from our grade ({ n, ours, game }), which the step cannot bring back.
-- Log only until it has been checked in game (it may never see a measurement at load, or flag near a ladder's edge).
M.GRADE_CHECK_MIN = 5
M.GRADE_CHECK_SHARE = 0.7
function M.gradeCheck()
  local rm = M.manager()
  local nb = rm and rm.notebook
  local ok, list = pcall(function() return nb.pacenotes.sorted end)
  if not ok or type(list) ~= 'table' then return nil end
  local pacenotes = require('earthRally/pacenotes')
  local checked, same, far = 0, 0, {}
  for n, note in ipairs(list) do
    local m = type(note) == 'table' and type(note.metadata) == 'table' and note.metadata.earthRally
    if type(m) == 'table' and type(m.circleR) == 'number' and m.grade and
       type(note.structuredForProjection) == 'function' then
      local okP, proj = pcall(note.structuredForProjection, note)
      local corner = nil
      if okP and type(proj) == 'table' and type(proj.items) == 'table' then
        for _, it in pairs(proj.items) do
          if type(it) == 'table' and it.type == 'corner' then corner = it break end
        end
      end
      if corner and type(corner.intensity) == 'number' then
        checked = checked + 1
        local g = pacenotes.gradeOf(corner.intensity)
        if g == pacenotes.gradeOf(2 * m.circleR) then same = same + 1 end
        if type(m.grade) == 'number' and math.abs(g - m.grade) >= 2 then far[#far + 1] = { n, m.grade, g } end
      end
    end
  end
  return { checked = checked, same = same, far = far,
           mismatch = checked >= M.GRADE_CHECK_MIN and same < M.GRADE_CHECK_SHARE * checked }
end

return M
