-- earthRally/stageWriter: the three files the game's rally engine reads for a stage, from a stage line in game
-- coordinates (made at the start of each run, in the world's frame of that moment):
--   race.race.json                       start line, stop control, a pathnode every ~1 km and one at the finish
--   rally/drivelineSpline.json           the line the co-driver measures along (with our heights)
--   rally/notebooks/structured.notebook.json   one pacenote per corner (pacenotes.findCorners) with what pacenotes.lua reads
--                                        off the line about it (hairpin, tightens, over crest, caution...), and
--                                        notes of their own for crests, jumps, dips and landmarks between corners,
--                                        and the finish; the game works out each corner's severity, direction,
--                                        length and the distance calls, and voices them
-- The layout follows the game's own stages (gameplay/missions/italy/rallyStage/*). build() is pure (tests); write()
-- saves with the game's jsonWriteFile.
local geo = require('earthRally/geo')
local pacenotes = require('earthRally/pacenotes')

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

-- Junctions, bridges and narrowings (opts.landmarks) as the game's structured notes carry them (its own stages: the
-- english style's modifiers): on the corner they are part of, else a note of their own. keep: always a note of its
-- own, its call before where the corner would be (slot 2), and "keep left over crest" on a crest.
M.LANDMARKS = {
  atJunction = {}, pastJunction = {}, overBridge = {}, narrows = {},
  keepLeft = { keep = true }, keepRight = { keep = true },
}
M.LANDMARK_BEFORE_M = 20    -- a landmark this far before a corner's start, or in it, or ...
M.LANDMARK_AFTER_M = 10     -- ... this far past its end, is called with the corner
M.HEIGHT_BEFORE_M = 40      -- a crest, a jump or a dip this far before a corner's start ("crest, left 4") ...
M.CREST_INTO_M = 60         -- (and a crest or a jump this far before it, or with the corner's start out of sight
M.CREST_HIDDEN_M = 100      --  behind it -- pacenotes.hiddenAfter -- up to this far: "crest three left", the pro's
                            --  "crest into 3 left"; a corner hidden behind a crest is never a call of its own)
M.HEIGHT_AFTER_M = 30       -- ... or this far past its end ("left 4 into crest"), or a hill starting there, is
                            -- called with the corner; else on a note of its own, if it is big enough to be
M.HILL_AHEAD_M = 60         -- "up" / "down" on a corner only with this much of the hill still ahead of its end
M.ALONE_MERGE_M = 15       -- calls this close together that have no corner share one note
M.TIGHTENS_DOWN_GRADE = 0.06 -- a tightening corner this steep downhill on average: "tightens down"
M.FINISH_ON_NOTE_M = 100    -- the last note ending this close to the finish says "over finish" too
M.BRIDGE_HEIGHTS_M = 60     -- no crest, jump or dip read this close to a bridge (the heights are the valley's)
-- Which calls are spoken when a note has more than its two slots before (or after) the corner can hold: the highest
-- here first, then the nearest. A jump or a blind crest can hurt; a side road cannot.
M.PRIORITY = {
  finish = 100, jump = 90, group = 80, crest = 70, keepLeft = 65, keepRight = 65, dip = 60, narrows = 55,
  overBridge = 50, atJunction = 45, pastJunction = 40, landmark = 40, twisty = 35, hill = 30,
}

-- The corners the stage's notebook gets, in order, and the samples they index into (the stage's own stretch of the
-- line, every M.NOTE_STEP_M): pacenotes.findCorners over that stretch, less the ones too close to either end of the stage to
-- be called and the ones on a stretch with no road on the map, with chicanes and twisty runs made one each
-- (pacenotes.group). build() writes one pacenote per entry this returns and reports their number, and lineStats.lua
-- calls this over a line as it is saved -- so the number the menu's Corners tile shows is the co-driver's own count
-- of corner notes and not a second opinion about it. (The notebook also has notes with no corner in them -- a crest
-- on a straight, the finish -- which that tile does not count.)
--   o.startM, o.finishM   the stage along `line`
--   o.stopM               notes on past the finish to here (the stop control; issue #47), or nil: to the finish.
--                         A corner across the finish line is left out, as before, and so is one starting within
--                         NOTE_CLEAR_M past it
--   o.lead                of line extended in before startM, if any: mute is read in the coordinates of the line
--                         as it came, which is where its gaps were measured
--   o.mute                { { fromM, toM }... }: no notes along there
--   o.corners             { smoothM }: geo.curvature's smoothing
-- Also returns muted(i), the test it used, for the landmarks that go on these notes, and iF, the finish's sample.
function M.stageCorners(line, cum, o)
  local endM = math.max(o.finishM, o.stopM or o.finishM)
  local stagePts = geo.resample(geo.slice(line, cum, o.startM, endM), M.NOTE_STEP_M)
  local clear = math.ceil(M.NOTE_CLEAR_M / M.NOTE_STEP_M)
  -- (the finish's sample: the last one when the notes end there)
  local iF = #stagePts
  if endM > o.finishM then iF = math.min(#stagePts, math.floor((o.finishM - o.startM) / M.NOTE_STEP_M + 0.5) + 1) end
  local function muted(i)
    local s = o.startM + (i - 1) * M.NOTE_STEP_M - (o.lead or 0)
    for _, r in ipairs(o.mute or {}) do if s >= r[1] and s <= r[2] then return true end end
    return false
  end
  local corners = {}
  -- (one corner finder over the fitted curvature: pacenotes.findCorners)
  local turn, k = geo.curvature(stagePts, M.NOTE_STEP_M, o.corners and o.corners.smoothM)
  local found = pacenotes.findCorners(turn, k, M.NOTE_STEP_M)
  -- (a corner the stage starts in -- a hairpin off the line -- is called from just past the clear stretch when
  --  NOTE_CLEAR_M of it or more is still to come, measured from there; only a corner over by then is left out)
  do
    local minAngle = pacenotes.FIND_CALL_DEG
    for ci, c in ipairs(found) do
      if c.i0 <= clear and c.i1 >= 2 * clear + 1 then
        local a, kMax = 0, 0
        for j = clear + 1, c.i1 do
          a = a + turn[j]
          if math.abs(k[j]) > kMax then kMax = math.abs(k[j]) end
        end
        if math.abs(math.deg(a)) >= minAngle then
          found[ci] = { i0 = clear + 1, i1 = c.i1, dir = c.dir, angleDeg = math.abs(math.deg(a)),
                        minRadius = kMax > 0 and 1 / kMax or math.huge, fromStart = true, sweeper = c.sweeper }
        end
      end
    end
  end
  for _, c in ipairs(found) do
    if c.i0 > clear and c.i1 < #stagePts and (c.i1 < iF or c.i0 > iF + clear) and not muted(c.i0) and
       not muted(c.i1) then
      corners[#corners + 1] = c
    end
  end
  -- (a chicane, or a twisty run of fast corners, is one note: one entry here, so the count is still one per note)
  return pacenotes.group(corners, M.NOTE_STEP_M), stagePts, muted, iF
end

-- The opening distance (the owner, 2026-11-19: "caution two right" with the corner 600 m away). The first note
-- plays at the start line (triggerType 15, when the car first moves) and the game says a distance only after a note
-- (path.autofillDistanceCalls, which also clears every note's `before` field when the rally engine loads the
-- notebook), so the straight up to the first note is never told. A pro opens with it: "80 4 left". So the first
-- note's `before` field gets the distance from the start line to its corner start, set after the engine's own
-- autofill (rallyAdapter.setOpening) -- spoken from the voice pack's audio for that distance, as one after a note is.
-- Only past OPENING_MIN_M: a corner closer than that is in sight off the line.
M.OPENING_MIN_M = 80
-- the english styles' distance rules (gameplay/rally/compositors/styles/english/distance.lua), for when the game's
-- own cannot be read
M.DISTANCE_RULES = {
  units = { base = 'm', large = 'km', point = 'point' },
  rounding = { small = 10, medium = 50, mediumThreshold = 100, large = 250, largeThreshold = 1000 },
  max = 2000,
}

local function customRound(d, to) return math.floor(d / to + 0.5) * to end

-- A distance (m) as the game's textCompositor:distanceToString says it, by a style's distance rules (its `distance`
-- table; M.DISTANCE_RULES when nil): 10 m steps under 100 m, 50 m steps to 1000 m, then km in 250 m steps with
-- "point" ("1 point 2 5 km").
function M.distanceString(dist, rules)
  rules = rules or M.DISTANCE_RULES
  local r, u = rules.rounding or M.DISTANCE_RULES.rounding, rules.units or M.DISTANCE_RULES.units
  dist = math.floor(dist)
  local v, unit
  if dist >= r.largeThreshold then
    v, unit = customRound(dist, r.large) / r.largeThreshold, u.large
  elseif dist >= r.mediumThreshold then
    v, unit = customRound(dist, r.medium), u.base
    if v == r.largeThreshold then v, unit = customRound(dist, r.large) / r.largeThreshold, u.large end
  else
    v, unit = customRound(dist, r.small), u.base
  end
  local s = tostring(v)
  if unit == u.large then
    local a, b = s:match('(%d+)%.(%d+)')
    if a and b then s = a .. ' ' .. u.point .. ' ' .. (b:gsub('%d', '%0 '):gsub(' $', '')) end
    s = s .. ' ' .. unit
  end
  return s
end

-- built: M.build's result. The first note's opening call: its words (rules: as M.distanceString) and the metres,
-- or nil when its corner start is under OPENING_MIN_M from the start line (a corner on it is said with its 80), or further than the style's `max`
-- (the voice packs have distance clips up to that only: textCompositor.enumerateDistanceEntries).
function M.openingCall(built, rules)
  local m = built and built.openingM
  if not m or m < M.OPENING_MIN_M then return nil end
  if m > ((rules and rules.max) or M.DISTANCE_RULES.max) then return nil end
  return M.distanceString(m, rules), m
end

-- line: { {x, y, z}... } in game coordinates, the stage from (about) its start to (about) its finish.
-- opts: startM, finishM (distances along the line), stop ({ x, y }: the stop control, or nil -- the notes go on past
-- the finish to it, issue #47: the co-driver reads the road to the stop; the stage's length, race distance and
-- pathnodes stay start to finish), name, quatFn, mute, landmarks ({ { s (along the line as given),
-- type (a key of M.LANDMARKS) }... }), speaks ({ [call] = true }: the calls the player's voice can say, or nil for
-- all of them -- rallyAdapter.speaks; a call it cannot say is left out, and a note with nothing it can say is not
-- written).
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

  -- notebook: corners between the start and the finish -- and on to the stop control (opts.stop), placed on the line
  -- past the finish and clamped to what it covers, short of its end -- (opts.mute: { {fromM, toM}... } along the line
  -- as given), with what pacenotes.lua reads off the line round them, and the junctions and bridges (opts.landmarks)
  local step = M.NOTE_STEP_M
  local stopM = nil
  if opts.stop then
    stopM = math.min(geo.alongBetween(line, cum, opts.stop, finishM, total), total - M.NOTE_CLEAR_M)
    if stopM <= finishM + M.NOTE_CLEAR_M then stopM = nil end
  end
  local corners, stagePts, muted, iF = M.stageCorners(line, cum, { startM = startM, finishM = finishM,
    stopM = stopM, lead = lead, mute = opts.mute, corners = opts.corners })
  local np = #stagePts
  local clear = math.ceil(M.NOTE_CLEAR_M / step)
  -- (#47: notes go on past the finish to the stop control, but nothing is called on the finish itself or just
  -- past it, as corners there are not)
  local function callable(i) return i > clear and i < np and not (np > iF and i >= iF and i <= iF + clear)
    and not muted(i) end
  local _, k = geo.curvature(stagePts, step, opts.corners and opts.corners.smoothM)
  local v = pacenotes.speeds(k, step)
  local events, hills, grade = pacenotes.heights(stagePts, step, v)
  -- (no crest, jump or dip read round a bridge: the line's heights there are the valley under the deck; before
  --  anything reads them, a corner's shape and its caution among them)
  local bridgeN = math.ceil(M.BRIDGE_HEIGHTS_M / step)
  for _, lm in ipairs(opts.landmarks or {}) do
    if lm.type == 'overBridge' then
      -- (from its start to its far end, lm.sEnd, when the recce gave one: a long bridge is all valley)
      local a = math.floor((math.min(lm.s, lm.sEnd or lm.s) + lead - startM) / step + 0.5) + 1
      local b = math.floor((math.max(lm.s, lm.sEnd or lm.s) + lead - startM) / step + 0.5) + 1
      for _, ev in ipairs(events) do
        if ev.i >= a - bridgeN and ev.i <= b + bridgeN then ev.used, ev.bridged = true, true end
      end
    end
  end

  local nid = 0
  local function wp(name, kind, i)
    local a, b = stagePts[math.max(1, i - 1)], stagePts[math.min(np, i + 1)]
    local dx, dy = b.x - a.x, b.y - a.y
    local l = math.sqrt(dx * dx + dy * dy)
    nid = nid + 1
    return { name = name, normal = l > 1e-9 and { dx / l, dy / l, 0 } or { 0, 1, 0 }, oldId = nid,
             pos = arr(stagePts[i]), radius = 8, waypointType = kind }
  end

  -- one entry per corner (a chicane is one); pre / post: the calls before and after its corner, of which the two of
  -- highest M.PRIORITY are spoken (slots 2, 3 and 5, 6)
  local speaks = opts.speaks
  local function said(t) return t and (not speaks or speaks[t]) and t or nil end
  local function saidShape(t) return t and (not speaks or speaks['shape:' .. t]) and t or nil end
  -- (a crest at the rim of a dip called on its own is left to the dip -- where one of them is said: not on a bridge,
  --  callable, and in the voice -- in a corner's shape, on a fork and on its own alike)
  -- (a crest at the top of a downhill from flat road is "down" where the voice says it: not a crest, nor a corner's
  --  crest shape, nor a keep over crest; a voice with no "down" hears the crest)
  local function asDown(ev) return ev.down and said('down') ~= nil end
  local function rimSaid(ev)
    for _, d in ipairs(ev.rimOf or {}) do
      if not d.bridged and callable(d.i) and said(d.size == 'big' and 'badDip' or 'dip') then return true end
    end
    return false
  end
  -- (a chicane the voice cannot call is its two corners again)
  do
    local out = {}
    for _, c in ipairs(corners) do
      if c.group == 'chicane' and c.parts and not said(c.dir == 'left' and 'chicaneLeftEntry' or 'chicaneRightEntry') then
        for _, part in ipairs(c.parts) do out[#out + 1] = part end
      else
        out[#out + 1] = c
      end
    end
    corners = out
  end
  -- (each corner's call, ahead of the notes: its grade, our own -- pacenotes.fitRadius, the road's radius where it is
  --  tightest -- and the note's ends and step that make the game say it, pacenotes.placeForGrade; and whether it is
  --  called tighter than a six. A corner the driver hears as a six is taken flat: the straight before a caution runs
  --  back past it, as past a sweeper)
  local placed, slows = {}, {}
  do
    for ci, c in ipairs(corners) do
      local G
      if c.group ~= 'chicane' then
        local r = pacenotes.fitRadius(c, k, step)
        G = pacenotes.fitGrade(r)
        c.fitR = r ~= math.huge and r or nil
        local cr = pacenotes.measuredRadius(c, stagePts)
        c.circleR = cr ~= math.huge and cr or nil
        if not pacenotes.descriptor(c, step) then
          local i0, i1, risk, g = pacenotes.placeForGrade(c, stagePts, G)
          placed[ci] = { i0 = i0, i1 = i1, risk = risk,
                         length = pacenotes.lengthMode(G, (c.i1 - c.i0) * step, g, (i1 - i0) * step) }
        end
      end
      slows[ci] = not c.sweeper and (c.group == 'chicane' or (G or 1) < #pacenotes.GRADE_FIT_DIAMETERS + 1)
      c.grade = G
    end
  end
  local entries = {}
  for ci, c in ipairs(corners) do
    local e = { i0 = placed[ci] and placed[ci].i0 or c.i0, i1 = placed[ci] and placed[ci].i1 or c.i1, corner = c,
                pre = {}, post = {} }
    if c.group == 'chicane' then
      e.pre[1] = { type = c.dir == 'left' and 'chicaneLeftEntry' or 'chicaneRightEntry', i = c.i0, prio = M.PRIORITY.group }
    else
      local item = { type = 'corner' }
      item.descriptor = pacenotes.descriptor(c, step)
      -- (the step that makes the game's circle say our grade: pacenotes.placeForGrade)
      if placed[ci] then item.riskIntensity, item.lengthMode = placed[ci].risk, placed[ci].length end
      local shape = pacenotes.shape(c, k, step)
      -- (a crest inside the corner is part of its shape: "over crest", "tightens over crest", "opens over crest" --
      --  when the voice says corner shapes; one that does not (the casual ones) hears "over crest" after the corner)
      local over, downIn = nil, nil
      for _, ev in ipairs(events) do
        if not ev.used and ev.kind == 'crest' and ev.i >= c.i0 and ev.i <= c.i1 and not rimSaid(ev) then
          if asDown(ev) then
            downIn = downIn or ev
          else
            over = shape == nil and 'overCrest' or shape == 'tightens' and 'tightensOverCrest' or
                   shape == 'opens' and 'opensOverCrest' or nil
            if over and saidShape(over) then shape, ev.used = over, true end
            break
          end
        end
      end
      -- (a corner that tightens over the top of a downhill from flat road: "tightens down", that descent's "down"
      --  said in it; and its caution as for one that tightens over a crest -- the top is as blind)
      if shape == 'tightens' and downIn then
        over = 'tightensOverCrest'
        if saidShape('tightensDown') then shape, downIn.used, downIn.downSaid = 'tightensDown', true, true end
      end
      if shape == 'tightens' and grade and saidShape('tightensDown') then
        local g = 0
        for i = c.i0, c.i1 do g = g + grade[i] end
        if g / (c.i1 - c.i0 + 1) <= -M.TIGHTENS_DOWN_GRADE then shape = 'tightensDown' end
      end
      item.shape = saidShape(shape)
      e.item = item
      -- (the caution reads the corner as it is, said in its shape or not; the straight before it runs back to the
      --  last corner called tighter than a six, not to a six or a long sweeper, which the car takes at speed -- and a
      --  sweeper has none of its own)
      local prev = nil
      for pj = ci - 1, 1, -1 do
        if slows[pj] then prev = corners[pj] break end
      end
      e.caution = (not c.sweeper) and pacenotes.caution(c, v, step, prev and prev.i1,
                                    over == 'tightensOverCrest' and over or shape,
                                    (shape == 'tightens' or shape == 'tightensDown') and not item.shape)
      if c.twisty and said('twisty') then e.post[1] = { type = 'twisty', i = c.i1, prio = M.PRIORITY.twisty } end
    end
    entries[#entries + 1] = e
  end

  -- the nearest corner note whose stretch (less `before` samples, plus `after`) holds sample i
  local function host(i, before, after)
    local best, bd = nil, nil
    for _, e in ipairs(entries) do
      if e.corner and i >= e.i0 - before and i <= e.i1 + after then
        local d = i < e.i0 and e.i0 - i or (i > e.i1 and i - e.i1 or 0)
        if not bd or d < bd then best, bd = e, d end
      end
    end
    return best
  end
  local mergeN = math.ceil(M.ALONE_MERGE_M / step)
  -- f: { i, pre, within, post, alone (the call on a note of its own, or nil: none), aloneSlot ('pre' | 'post'),
  --      prio, before, after (samples), keep (a note of its own unless it is inside a corner), landmark }
  local function place(f)
    if not callable(f.i) then return false end
    local e = host(f.i, f.keep and 0 or f.before, f.keep and 0 or f.after)
    if e then
      local where = f.i < e.i0 and 'pre' or (f.i > e.i1 and 'post' or 'within')
      local t, base = nil, nil
      if f.keep then where, t, base = 'pre', f.alone, f.keepBase   -- (inside a corner: "keep left, 4 right")
      elseif where == 'within' then where, t = 'post', f.within or f.post
      else t = f[where] end
      t = said(t)
      if t then
        table.insert(e[where], { type = t, base = base, i = f.i, prio = f.prio, landmark = f.landmark })
        return true
      end
    end
    local alone = said(f.alone)
    if not alone then return false end
    local item = { type = alone, i = f.i, prio = f.prio, landmark = f.landmark }
    -- (calls this close share a note, but a keep note is its own: nothing joins it and it joins nothing)
    if not f.keep then
      for _, a in ipairs(entries) do
        if not a.corner and a.at and not a.keep and math.abs(f.i - a.at) <= mergeN then
          table.insert(a[f.aloneSlot], item)
          return true
        end
      end
    end
    local a = { i0 = math.max(clear + 1, f.i - 1), i1 = math.min(np, f.i + 1), at = f.i, keep = f.keep, pre = {},
                post = {} }
    table.insert(a[f.aloneSlot], item)
    entries[#entries + 1] = a
    return true
  end

  local hb, ha = math.ceil(M.HEIGHT_BEFORE_M / step), math.ceil(M.HEIGHT_AFTER_M / step)
  -- (keep left / right: a note of its own, as the game's stages always have it; on a crest, "keep left over crest")
  local lmb, lma = math.ceil(M.LANDMARK_BEFORE_M / step), math.ceil(M.LANDMARK_AFTER_M / step)
  local features = {}
  for _, lm in ipairs(opts.landmarks or {}) do
    local def = M.LANDMARKS[lm.type]
    if def then
      local i = math.floor((lm.s + lead - startM) / step + 0.5) + 1
      local f = { i = i, prio = M.PRIORITY[lm.type] or M.PRIORITY.landmark, before = lmb, after = lma, landmark = true }
      if def.keep then
        local t = lm.type
        for _, ev in ipairs(events) do
          if not ev.used and ev.kind == 'crest' and not rimSaid(ev) and not asDown(ev) and
             math.abs(ev.i - i) <= mergeN and callable(i) and
             said(t .. 'OverCrest') then
            f.keepBase, t, ev.used = t, t .. 'OverCrest', true
            break
          end
        end
        f.keep, f.alone, f.aloneSlot = true, t, 'pre'
      else
        f.pre, f.post, f.alone, f.aloneSlot = lm.type, lm.type, lm.type, 'post'
      end
      features[#features + 1] = f
    end
  end
  local intoN, hiddenN = math.ceil(M.CREST_INTO_M / step), math.ceil(M.CREST_HIDDEN_M / step)
  for _, ev in ipairs(events) do
    if not ev.used and not rimSaid(ev) then
      local big = ev.size == 'big'
      local f = { i = ev.i, before = hb, after = ha, aloneSlot = 'pre' }
      -- (a crest: on the corner that starts within CREST_INTO_M past it, or out of sight behind it up to
      --  CREST_HIDDEN_M. A jump stays within HEIGHT_BEFORE_M: its note plays before the corner's start, and a jump
      --  further back than that could come before the call does)
      if ev.kind == 'crest' then
        f.before = math.max(hb, intoN, math.min(hiddenN, ev.hiddenTo and ev.hiddenTo - ev.i or 0))
      end
      if ev.kind == 'jump' then
        f.prio = M.PRIORITY.jump
        f.pre = big and 'bigJump' or 'jump'
        f.post = big and 'bigJump' or 'overJump'
        f.alone = f.pre
      elseif ev.kind == 'crest' and asDown(ev) then
        f.prio = M.PRIORITY.crest
        f.pre, f.within, f.post, f.alone, f.descent = 'down', 'down', 'down', 'down', ev
      elseif ev.kind == 'crest' then
        f.prio = M.PRIORITY.crest
        f.pre = big and 'bigCrest' or (ev.size == 'small' and 'smallCrest' or 'crest')
        f.within = 'overCrest'
        f.post = 'intoCrest'
        -- (every crest is the driver's sight, and called on its own as well as on a corner)
        f.alone = f.pre
      else
        f.prio = M.PRIORITY.dip
        f.pre = big and 'badDip' or 'dip'
        f.within = 'throughDip'
        f.post = f.pre
        f.alone = ev.alone and f.pre or nil
      end
      features[#features + 1] = f
    end
  end
  -- (a hill on the first corner that ends on it with HILL_AHEAD_M of it still to come -- one that starts at a
  --  corner's end, and one the stage starts on or that begins in a stretch with no road, alike)
  local ahead = math.ceil(M.HILL_AHEAD_M / step)
  for _, h in ipairs(hills) do
    -- (a descent that has a "down" at its top too: one of the two said, whichever comes first -- `descent`)
    local descent = h.fromCrest and asDown(h.fromCrest) and h.fromCrest or nil
    for _, c in ipairs(corners) do
      local i = math.min(math.max(c.i0, h.i0), c.i1)
      if c.i1 + ha >= h.i0 and c.i1 <= h.i1 - ahead and callable(i) then
        features[#features + 1] = { i = i, post = h.kind, within = h.kind, prio = M.PRIORITY.hill,
                                    before = 0, after = ha, descent = descent }
        break
      end
    end
  end
  table.sort(features, function(a, b)
    if a.i ~= b.i then return a.i < b.i end
    if a.prio ~= b.prio then return a.prio > b.prio end
    return tostring(a.alone or a.pre or a.post) < tostring(b.alone or b.pre or b.post)
  end)
  for _, f in ipairs(features) do
    if not (f.descent and f.descent.downSaid) and place(f) and f.descent then f.descent.downSaid = true end
  end

  table.sort(entries, function(a, b)
    if a.i0 ~= b.i0 then return a.i0 < b.i0 end
    return a.i1 < b.i1
  end)
  -- the finish: on the note before it that ends last when that is close to it, else a note of its own on the line
  -- ("over finish", as the game's own stages have it; no "to stop" after it). With a stop control the notes past the
  -- finish follow it (issue #47)
  local last = nil
  for _, e in ipairs(entries) do if e.i0 < iF and (not last or e.i1 > last.i1) then last = e end end
  -- (not on a keep note: that is a note of its own; the finish then has one of its own after it)
  if last and not last.keep and (iF - last.i1) * step <= M.FINISH_ON_NOTE_M then
    table.insert(last.post, { type = 'finish', i = iF, prio = M.PRIORITY.finish })
  else
    entries[#entries + 1] = { i0 = math.max(1, iF - 2), i1 = iF, at = iF, pre = { { type = 'finish', i = iF,
      prio = M.PRIORITY.finish } }, post = {} }
    table.sort(entries, function(a, b)
      if a.i0 ~= b.i0 then return a.i0 < b.i0 end
      return a.i1 < b.i1
    end)
  end

  -- calls of one family say the same thing: one of them per note
  local FAMILY = { jump = 'jump', bigJump = 'jump', overJump = 'jump', crest = 'crest', bigCrest = 'crest',
                   smallCrest = 'crest', intoCrest = 'crest', overCrest = 'crest', brakeOverCrest = 'crest',
                   keepLeftOverCrest = 'crest', keepRightOverCrest = 'crest', keepMiddleOverCrest = 'crest',
                   dip = 'dip', badDip = 'dip', throughDip = 'dip' }
  local landmarks = 0
  local calls = {}
  local function count(t) calls[t] = (calls[t] or 0) + 1 end
  local function pick(list, seen)
    table.sort(list, function(a, b)
      if a.prio ~= b.prio then return a.prio > b.prio end
      if a.i ~= b.i then return a.i < b.i end
      return a.type < b.type
    end)
    local out = {}
    for _, it in ipairs(list) do
      local fam = FAMILY[it.type] or it.type
      -- (a keep over a crest where the note says the crest already: the keep alone)
      if seen[fam] and it.base and said(it.base) then it.type, fam = it.base, FAMILY[it.base] or it.base end
      if #out < 2 and not seen[fam] then seen[fam] = true out[#out + 1] = it end
    end
    table.sort(out, function(a, b)
      if a.i ~= b.i then return a.i < b.i end
      if a.prio ~= b.prio then return a.prio > b.prio end
      return a.type < b.type
    end)
    return out
  end

  local pacenotes_ = {}
  for n, e in ipairs(entries) do
    nid = nid + 1
    local noteId = nid
    local c = e.corner
    local items = { ['1'] = {}, ['2'] = {}, ['3'] = {}, ['4'] = {}, ['5'] = {}, ['6'] = {} }
    -- ("tightens down" says the hill already; a crest in the shape says the crest)
    local seen = {}
    if e.item and e.item.shape == 'tightensDown' then seen.down = true end
    if e.item and e.item.shape and e.item.shape:find('Crest') then seen.crest = true end
    local pre = pick(e.pre, seen)
    local post = pick(e.post, seen)
    -- a crest just before a corner with a caution on it: "brake over crest", and one caution more (it is blind) --
    -- a caution, not a care: a care for the straight before it is not a reason to brake
    if e.caution and e.caution >= 2 then
      for _, it in ipairs(pre) do
        if (it.type == 'crest' or it.type == 'bigCrest' or it.type == 'smallCrest') and said('brakeOverCrest') then
          it.type = 'brakeOverCrest'
          e.caution = math.min(3, e.caution + 1)
          break
        end
      end
    end
    for _, it in ipairs(pre) do count(it.type) if it.landmark then landmarks = landmarks + 1 end end
    for _, it in ipairs(post) do count(it.type) if it.landmark then landmarks = landmarks + 1 end end
    if e.caution then items['1'] = { type = 'caution', level = e.caution } count('caution' .. e.caution) end
    for j, it in ipairs(pre) do items[tostring(1 + j)] = { type = it.type } end
    for j, it in ipairs(post) do items[tostring(4 + j)] = { type = it.type } end
    if e.item then
      items['4'] = e.item
      count('corner')
      if e.item.descriptor then count(e.item.descriptor) end
      if e.item.shape then count('shape:' .. e.item.shape) end
    end
    pacenotes_[n] = {
      audioMode = 1, distanceBeforeModifier = false, ignoreDistanceCalls = false, includeLinkWord = e.item ~= nil,
      isolate = false,
      metadata = { earthRally = c and { dir = c.dir, angleDeg = c.angleDeg, minRadius = c.minRadius, group = c.group,
                                        sweeper = c.sweeper, fitR = c.fitR, grade = c.grade,
                                        circleR = c.circleR }
                   or { landmark = true } },
      name = 'Pacenote ' .. n, oldId = noteId,
      pacenoteWaypoints = { wp('corner start', 'cornerStart', e.i0), wp('corner end', 'cornerEnd', e.i1) },
      pk = string.format('%08x', (n * 2654435761) % 4294967296), slowCorner = false, slowCornerReleaseType = 30,
      structured = { items = items, schemaVersion = 3 },
      todo = false, triggerType = n == 1 and 15 or 1,
    }
  end
  local notebook = { audioMode = 4, authors = 'Earth Rally', created_at = 0, description = '', metadata = {},
                     name = 'structured', pacenotes = pacenotes_, updated_at = 0, version = '4' }

  -- (corners: the stage's own, start to finish -- the menu's Corners tile; those past the finish counted apart)
  local afterFinish = 0
  for _, c in ipairs(corners) do if c.i0 > iF then afterFinish = afterFinish + 1 end end
  -- (the first note's corner start, from the start line: M.openingCall)
  local openingM = entries[1] and (entries[1].i0 - 1) * step or nil
  return { race = race, driveline = driveline, notebook = notebook, nodes = nodes, corners = #corners - afterFinish,
           cornersAfterFinish = afterFinish, landmarks = landmarks, notes = #pacenotes_, calls = calls, startM = startM,
           finishM = finishM, stopM = stopM, lengthM = finishM - startM, leadM = lead, openingM = openingM }
end

function M.write(dir, built)
  jsonWriteFile(dir .. '/race.race.json', built.race, true)
  jsonWriteFile(dir .. '/rally/drivelineSpline.json', built.driveline, true)
  jsonWriteFile(dir .. '/rally/notebooks/structured.notebook.json', built.notebook, true)
end

return M
