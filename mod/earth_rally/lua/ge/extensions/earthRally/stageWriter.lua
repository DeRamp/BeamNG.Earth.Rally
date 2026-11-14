-- earthRally/stageWriter: the three files the game's rally engine reads for a stage, from a stage line in game
-- coordinates (made at the start of each run, in the world's frame of that moment):
--   race.race.json                       start line, stop control, a pathnode every ~1 km and one at the finish
--   rally/drivelineSpline.json           the line the co-driver measures along (with our heights)
--   rally/notebooks/structured.notebook.json   one pacenote per corner (geo.corners); the game works out each one's
--                                        severity, direction and the distance calls, and voices them
-- The layout follows the game's own stages (gameplay/missions/italy/rallyStage/*). build() is pure (tests); write()
-- saves with the game's jsonWriteFile.
local geo = require('earthRally/geo')

local M = {}

M.NODE_STEP_M = 10          -- driveline node spacing
M.PATHNODE_EVERY_M = 1000
M.PATHNODE_RADIUS_M = 15    -- generous: a car within this of a pathnode counts as passing it
M.NOTE_STEP_M = 5           -- the sampling corner detection works on
M.ROAD_WIDTH_M = 8

local function arr(p) return { p.x, p.y, p.z or 0 } end

-- quatFn(dirX, dirY, dirZ) -> x, y, z, w: the game's quatFromDir(dir, up) (a car facing dir); injected for tests.
local function rotFor(quatFn, dir)
  local x, y, z, w = quatFn(dir.x, dir.y, 0)
  return { x, y, z, w }
end

M.LEAD_IN_M = 60            -- of route before the start line, at least
M.RUN_OUT_M = 150           -- of route past the finish, at least (the stop control at its end)
M.NOTE_CLEAR_M = 25         -- no note's corner starting this close to the start line or past the finish
M.MUTE_PAD_M = 30           -- no notes this far either side of a stretch with no road on the map (runner.lua
                            -- builds the ranges, lineStats.lua builds the same ones off a saved line)

-- Junctions and bridges (opts.landmarks) as the game's structured notes carry them (its own stages: the english
-- style's modifiers): on the corner they are part of, else a note of their own. slot: the note's item they go in
-- (2 before the corner, 5 after it).
M.LANDMARKS = {
  atJunction = { slot = 5 }, pastJunction = { slot = 5 }, overBridge = { slot = 5 },
  keepLeft = { slot = 2 }, keepRight = { slot = 2 },
}
M.LANDMARK_BEFORE_M = 20    -- a landmark this far before a corner's start, or in it, or ...
M.LANDMARK_AFTER_M = 10     -- ... this far past its end, is called with the corner

-- The corners the stage's notebook gets, in order, and the samples they index into (the stage's own stretch of the
-- line, every M.NOTE_STEP_M): geo.corners over that stretch, less the ones too close to either end of the stage to
-- be called and the ones on a stretch with no road on the map. build() writes one pacenote per corner this returns
-- and reports their number, and lineStats.lua calls this over a line as it is saved -- so the number the menu's
-- Corners tile shows is the co-driver's own count and not a second opinion about it.
--   o.startM, o.finishM   the stage along `line`
--   o.lead                of line extended in before startM, if any: mute is read in the coordinates of the line
--                         as it came, which is where its gaps were measured
--   o.mute                { { fromM, toM }... }: no notes along there
--   o.corners             geo.corners options
-- Also returns muted(i), the test it used, for the landmarks that go on these notes.
function M.stageCorners(line, cum, o)
  local stagePts = geo.resample(geo.slice(line, cum, o.startM, o.finishM), M.NOTE_STEP_M)
  local clear = math.ceil(M.NOTE_CLEAR_M / M.NOTE_STEP_M)
  local function muted(i)
    local s = o.startM + (i - 1) * M.NOTE_STEP_M - (o.lead or 0)
    for _, r in ipairs(o.mute or {}) do if s >= r[1] and s <= r[2] then return true end end
    return false
  end
  local corners = {}
  for _, c in ipairs(geo.corners(stagePts, M.NOTE_STEP_M, o.corners)) do
    if c.i0 > clear and c.i1 < #stagePts and not muted(c.i0) and not muted(c.i1) then corners[#corners + 1] = c end
  end
  return corners, stagePts, muted
end

-- line: { {x, y, z}... } in game coordinates, the stage from (about) its start to (about) its finish.
-- opts: startM, finishM (distances along the line), name, quatFn, mute, landmarks ({ { s (along the line as given),
-- type (a key of M.LANDMARKS) }... }).
function M.build(line, opts)
  local quatFn = opts.quatFn
  local cum0 = geo.cumulative(line)
  local total0 = cum0[#cum0]
  local startM = math.max(0, math.min(opts.startM or 0, total0 - 50))
  local finishM = math.max(startM + 50, math.min(opts.finishM or total0, total0))
  local lead = math.max(0, M.LEAD_IN_M - startM)
  if lead > 0 then line = geo.extend(line, lead, true) startM, finishM = startM + lead, finishM + lead end
  local tail = math.max(0, M.RUN_OUT_M - (total0 - (finishM - lead)))
  if tail > 0 then line = geo.extend(line, tail, false) end
  local cum = geo.cumulative(line)
  local total = cum[#cum]

  -- driveline: the whole line (the co-driver needs it to reach past the finish)
  local nodes = geo.resample(line, M.NODE_STEP_M)
  local ncum = geo.cumulative(nodes)
  local nmls, widths = {}, {}
  for i = 1, #nodes do
    local a, b = nodes[math.max(1, i - 1)], nodes[math.min(#nodes, i + 1)]
    local dx, dy, dz = b.x - a.x, b.y - a.y, (b.z or 0) - (a.z or 0)
    local l = math.sqrt(dx * dx + dy * dy + dz * dz)
    nmls[i] = l > 1e-9 and { dx / l, dy / l, dz / l } or { 0, 1, 0 }
    widths[i] = M.ROAD_WIDTH_M
  end
  local nodeArr = {}
  for i, p in ipairs(nodes) do nodeArr[i] = arr(p) end
  local driveline = {
    name = 'Earth Rally Driveline', version = 1, isLoop = false,
    nodes = nodeArr, nmls = nmls, widths = widths,
    properties = { liaisonAllocatedTimeMins = 5, useRaycast = false, speedLimitKph = 60, vertRayRaise = 2 },
    stats = { raceDistanceKms = math.floor((finishM - startM) / 10 + 0.5) / 100, surfacePercentages = {} },
  }

  -- race: ids as the game's files number them (oldId), start positions first
  local nextId = 0
  local function id() nextId = nextId + 1 return nextId end
  local startPos, startDir = geo.pointAt(line, cum, startM)
  local stopPos, stopDir = geo.pointAt(line, cum, total)
  local spStart, spStop = id(), id()
  local startPositions = {
    { group = 'start', name = 'SS_start_line', oldId = spStart, pos = arr(startPos), rot = rotFor(quatFn, startDir) },
    { group = 'start', name = 'SS_stop_control', oldId = spStop, pos = arr(stopPos), rot = rotFor(quatFn, stopDir) },
  }
  local marks = { startM }
  local s = startM + M.PATHNODE_EVERY_M
  while s < finishM - M.PATHNODE_EVERY_M * 0.5 do marks[#marks + 1] = s s = s + M.PATHNODE_EVERY_M end
  marks[#marks + 1] = finishM
  local pathnodes, ids = {}, {}
  for i, m in ipairs(marks) do
    local p, dir = geo.pointAt(line, cum, m)
    local nid = id()
    ids[i] = nid
    pathnodes[i] = {
      customFields = { names = {}, tags = {}, types = {}, values = {} },
      mode = 'manual', name = 'Pathnode ' .. i, navRadiusScale = 1,
      normal = { dir.x, dir.y, 0 }, oldId = nid, pos = arr(p), radius = M.PATHNODE_RADIUS_M,
      recovery = -1, reverseRecovery = -1, sidePadding = { 1, 3 }, useAsSplit = false, visible = true,
    }
  end
  local segments = {}
  for i = 1, #ids - 1 do
    segments[i] = { capsules = {}, from = ids[i], to = ids[i + 1], mode = 'waypoint',
                    name = string.format('Segment %d->%d', i, i + 1), oldId = id() }
  end
  local race = {
    authors = 'Earth Rally', classification = { allowRollingStart = false, branching = false, closed = false,
    reversible = false }, date = 0, defaultLaps = 1, defaultStartPosition = spStart, description = '',
    difficulty = 0, startNode = ids[1], endNode = ids[#ids], forwardPrefabs = {}, hideMission = true,
    name = opts.name or 'Earth Rally stage', pacenotes = {}, pathnodes = pathnodes, prefabs = {},
    reversePrefabs = {}, reverseStartPosition = -1, rollingReverseStartPosition = -1, rollingStartPosition = -1,
    segments = segments, startPositions = startPositions,
  }

  -- notebook: corners between the start and the finish (opts.mute: { {fromM, toM}... } along the line as given)
  local corners, stagePts, muted = M.stageCorners(line, cum, { startM = startM, finishM = finishM, lead = lead,
                                                               mute = opts.mute, corners = opts.corners })
  local clear = math.ceil(M.NOTE_CLEAR_M / M.NOTE_STEP_M)
  local pacenotes = {}
  local nid = 0
  local function wp(name, kind, i)
    local a, b = stagePts[math.max(1, i - 1)], stagePts[math.min(#stagePts, i + 1)]
    local dx, dy = b.x - a.x, b.y - a.y
    local l = math.sqrt(dx * dx + dy * dy)
    nid = nid + 1
    return { name = name, normal = l > 1e-9 and { dx / l, dy / l, 0 } or { 0, 1, 0 }, oldId = nid,
             pos = arr(stagePts[i]), radius = 8, waypointType = kind }
  end
  -- the notes: one per corner, with the junctions and bridges on it; those on no corner a note of their own
  local entries = {}
  for _, c in ipairs(corners) do
    entries[#entries + 1] = { i0 = c.i0, i1 = c.i1, corner = c,
      items = { ['1'] = {}, ['2'] = {}, ['3'] = {}, ['4'] = { type = 'corner' }, ['5'] = {}, ['6'] = {} } }
  end
  -- (keep left / right before the corner, slot 2; the rest where they lie: before its start slot 3, else 5 then 6)
  local function put(items, kind, beforeCorner)
    local slots = M.LANDMARKS[kind].slot == 2 and { '2' } or (beforeCorner and { '3' } or { '5', '6' })
    for _, k in ipairs(slots) do
      if not items[k].type then items[k].type = kind return true end
    end
    return false
  end
  local landmarks = 0
  local before = math.ceil(M.LANDMARK_BEFORE_M / M.NOTE_STEP_M)
  local after = math.ceil(M.LANDMARK_AFTER_M / M.NOTE_STEP_M)
  for _, lm in ipairs(opts.landmarks or {}) do
    local i = math.floor((lm.s + lead - startM) / M.NOTE_STEP_M + 0.5) + 1
    if M.LANDMARKS[lm.type] and i > clear and i < #stagePts and not muted(i) then
      local host = nil
      -- (keep left / right: a note of its own, as the game's stages always have it)
      local alone = M.LANDMARKS[lm.type].slot == 2
      for _, e in ipairs(entries) do
        if not alone and e.corner and i >= e.i0 - before and i <= e.i1 + after then host = e break end
      end
      -- (another junction or bridge note a step or two away: one note for both)
      if not host then
        for _, e in ipairs(entries) do
          if not e.corner and math.abs(i - (e.i0 + 1)) <= 2 then host = e break end
        end
      end
      if host then
        if put(host.items, lm.type, host.corner ~= nil and i < host.i0) then landmarks = landmarks + 1 end
      else
        local items = { ['1'] = {}, ['2'] = {}, ['3'] = {}, ['4'] = {}, ['5'] = {}, ['6'] = {} }
        put(items, lm.type, false)
        entries[#entries + 1] = { i0 = math.max(1, i - 1), i1 = math.min(#stagePts, i + 1), items = items }
        landmarks = landmarks + 1
      end
    end
  end
  table.sort(entries, function(a, b) return a.i0 < b.i0 end)
  for n, e in ipairs(entries) do
    nid = nid + 1
    local noteId = nid
    local c = e.corner
    pacenotes[n] = {
      audioMode = 1, distanceBeforeModifier = false, ignoreDistanceCalls = false, includeLinkWord = c ~= nil,
      isolate = false,
      metadata = { earthRally = c and { dir = c.dir, angleDeg = c.angleDeg, minRadius = c.minRadius } or { landmark = true } },
      name = 'Pacenote ' .. n, oldId = noteId,
      pacenoteWaypoints = { wp('corner start', 'cornerStart', e.i0), wp('corner end', 'cornerEnd', e.i1) },
      pk = string.format('%08x', (n * 2654435761) % 4294967296), slowCorner = false, slowCornerReleaseType = 30,
      structured = { items = e.items, schemaVersion = 3 },
      todo = false, triggerType = n == 1 and 15 or 1,
    }
  end
  local notebook = { audioMode = 4, authors = 'Earth Rally', created_at = 0, description = '', metadata = {},
                     name = 'structured', pacenotes = pacenotes, updated_at = 0, version = '4' }

  return { race = race, driveline = driveline, notebook = notebook, nodes = nodes, corners = #corners, landmarks = landmarks,
           startM = startM, finishM = finishM, lengthM = finishM - startM, leadM = lead }
end

function M.write(dir, built)
  jsonWriteFile(dir .. '/race.race.json', built.race, true)
  jsonWriteFile(dir .. '/rally/drivelineSpline.json', built.driveline, true)
  jsonWriteFile(dir .. '/rally/notebooks/structured.notebook.json', built.notebook, true)
end

return M
