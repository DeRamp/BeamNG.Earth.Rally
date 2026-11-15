-- earthRally/junctions: the junctions along a stage -- where the stage meets another road, which way it comes in and
-- leaves by, and the side roads it does not take -- from the matched file (autoRecce.lua in the game,
-- tools/auto_recce.py offline), which finds them on the road graph when the stage is matched and keeps them as lat /
-- lon. (1.4.0 also read them off BeamNG.Earth's live road map as the car went, for a stage without side roads in its
-- file; dropped, the user, 2026-11-14: the stage dressing comes from the auto recce only.) M.branch and M.judge below
-- are the rule both auto recces share. Pure and offline (tests/test_junctions.lua): nothing from the game.
--
-- A junction, in memory:
--   { along, kind, side, inDeg, outDeg, sides = { { deg, halfW }... } }
--     along   m along the line it was found on (the file's are placed on the line by the caller, as runner.lua
--             places the landmarks)
--     kind    'turn' (the stage turns there), 'straight' (on past a side road) or 'fork' (side 'left' / 'right':
--             the way the stage keeps); side is '' for the other two
--     inDeg   the way the stage comes in, as a bearing: the direction of travel arriving, not the road behind
--     outDeg  the way it leaves, the direction of travel
--     sides   each side road the stage does not take (40 m+ long), its bearing out from the junction, and its half
--             width in m where the road map gives one (nil where it does not: tools/auto_recce.py has no widths).
--             On a 'turn' the road straight on is one of these: it is not taken either.
--   half    the stage road's own half width at the junction (the junction node's radius), where it is known
--   from a file, also lat, lon.
--
-- **Bearings** are degrees clockwise from north, 0 up to 360, as a compass reads. North is +y in both frames these
-- are worked out in: the auto recce's stage frame (autoRecce.frame: x east, y north of the stage's first point) and
-- the game's own (BeamNG.Earth's anchor frame is east / north / up: its geodesy.lua, Anchor:geodeticToWorld is
-- geodeticToEnu). The game's +y is true north only at the anchor -- the meridians turn by about d x tan(lat) / R
-- away from it, 0.1 degree at 15 km and 39 degrees north (Anchor:northAt) -- which is well inside what a bearing
-- here is good for, since a road's way is itself measured over 15 m. M.dirToBearing / M.bearingToDir are the one
-- place the convention lives; nothing else converts.
--
-- The matched file's junction entry, format 2 (format 1 had the first four only):
--   [lat, lon, kind, side, inDeg, outDeg, [[sideDeg, halfW], ...], half]
-- bearings to 0.1 degree, halfW to 0.1 m and 0 where it is not known (never null: the game's JSON reader turns a
-- null into a hole in the array, and a hole stops ipairs). The eighth, the stage road's own half width at the
-- junction, came after the first format 2 files and is optional: a seven-entry one reads with no half, and an older
-- build reads the first four (events.landmarks) or seven (junctions.decode) and passes over it. M.encode / M.decode
-- write and read it; a format 1 entry decodes with no inDeg, outDeg or sides.
local geo = require('earthRally/geo')

local M = {}

local sqrt, abs, floor, huge = math.sqrt, math.abs, math.floor, math.huge

-- (tools/auto_recce.py's and autoRecce.lua's own, at the same values: autoRecce takes them from here)
M.JUNCTION_LOOK_M = 15.0    -- a junction's roads: their way this far from it
M.SIDE_ROAD_MIN_M = 40.0    -- a side road shorter than this (a driveway, a stub of track) is no junction
M.TURN_DEG = 30.0           -- the stage turning more than this at a junction: a turn there ("at junction")
M.FORK_DEG = 35.0           -- a side road within this of the stage's way on: a fork ("keep left / right")
M.JUNCTION_GAP_M = 25.0     -- junctions closer than this along the stage: one
M.ON_LINE_M = 1.5           -- a junction node this close to the line is on it

------------------------------------------------------------------------------------------ bearings

local function wrap360(d)
  d = d % 360
  if d < 0 then d = d + 360 end
  if d >= 360 then d = d - 360 end
  return d
end

-- A direction (dx east, dy north: game coordinates or the stage frame) as a bearing, degrees clockwise from north,
-- 0 up to 360. nil for no direction at all.
function M.dirToBearing(dx, dy)
  if not dx or not dy or (abs(dx) < 1e-12 and abs(dy) < 1e-12) then return nil end
  return wrap360(math.deg(math.atan2(dx, dy)))
end

-- A bearing (degrees clockwise from north) as a unit direction dx (east), dy (north).
function M.bearingToDir(deg)
  local r = math.rad(deg)
  return math.sin(r), math.cos(r)
end

-- The signed angle from u to v (degrees, + to the left). tools/auto_recce.py's _angle.
function M.angle(u, v)
  return math.deg(math.atan2(u.x * v.y - u.y * v.x, u.x * v.x + u.y * v.y))
end

-- How far bearing b is turned from bearing a, -180..180, + to the right (clockwise, as bearings run).
function M.turnDeg(a, b)
  local d = (b - a) % 360
  if d > 180 then d = d - 360 end
  return d
end

local function round(v, n) local m = 10 ^ n return floor(v * m + 0.5) / m end

------------------------------------------------------------------------------------------ the rule

local function dist(a, b)
  local dx, dy = b.x - a.x, b.y - a.y
  return sqrt(dx * dx + dy * dy)
end

-- Walking from node n through m, the road turning least at each node: its way at JUNCTION_LOOK_M from n, how far
-- it goes (up to SIDE_ROAD_MIN_M; less at a dead end), and its half width where the way was taken (the junction
-- node's own is the main road's, so the side road's is read a little way into it). tools/auto_recce.py's
-- Roads.branch.
--   xy: { [name] = { x, y } }   nbr: { [name] = { [name] = anything } }   half: { [name] = m } or nil
function M.branch(xy, nbr, half, n, m)
  local prev, cur = n, m
  local d = dist(xy[n], xy[m])
  local o = xy[n]
  local way, w = nil, nil
  while true do
    if way == nil and d >= M.JUNCTION_LOOK_M then
      local p = xy[cur]
      way = { x = p.x - o.x, y = p.y - o.y }
      w = half and half[cur]
    end
    if d >= M.SIDE_ROAD_MIN_M then break end
    local pc, pp = xy[cur], xy[prev]
    local head = { x = pc.x - pp.x, y = pc.y - pp.y }
    local bestK, bestA = nil, huge
    for k in pairs(nbr[cur] or {}) do
      local pk = k ~= prev and xy[k]
      if pk then
        local a = abs(M.angle(head, { x = pk.x - pc.x, y = pk.y - pc.y }))
        -- (a stable order: pairs() is not ordered, and two roads can leave at the same angle)
        if a < bestA or (a == bestA and bestK and tostring(k) < tostring(bestK)) then bestK, bestA = k, a end
      end
    end
    if not bestK then break end
    prev, cur = cur, bestK
    d = d + dist(xy[prev], xy[cur])
  end
  if way == nil then
    local p = xy[cur]
    way = { x = p.x - o.x, y = p.y - o.y }
    w = half and half[cur]
  end
  return way, d, w
end

-- One junction judged: wIn and wOut the stage's own way in and out (directions of travel, { x, y }), ways each road
-- leaving the node { m = its next node, way, len, halfW } (M.branch). Returns the junction without its place
-- ({ kind, side, inDeg, outDeg, sides }), or nil when no road but the stage's own is 40 m+ long: no junction.
-- tools/auto_recce.py's landmarks(), the part of it inside the loop.
function M.judge(wIn, wOut, ways)
  local list = {}
  for i, w in ipairs(ways) do list[i] = w end
  table.sort(list, function(u, v) return tostring(u.m) < tostring(v.m) end)
  -- the stage's own two roads: the one it comes in on and the one it leaves by
  local back = { x = -wIn.x, y = -wIn.y }
  local mIn, bestA = nil, huge
  for _, w in ipairs(list) do
    local d = abs(M.angle(back, w.way))
    if d < bestA then mIn, bestA = w.m, d end
  end
  local mOut, bestB = nil, huge
  for _, w in ipairs(list) do
    if w.m ~= mIn then
      local d = abs(M.angle(wOut, w.way))
      if d < bestB then mOut, bestB = w.m, d end
    end
  end
  local sides = {}
  for _, w in ipairs(list) do
    if w.m ~= mIn and w.m ~= mOut and w.len >= M.SIDE_ROAD_MIN_M then sides[#sides + 1] = w end
  end
  if #sides == 0 then return nil end
  local kind, side = 'straight', ''
  if abs(M.angle(wIn, wOut)) >= M.TURN_DEG then
    kind = 'turn'
  else
    local close = nil
    for _, w in ipairs(sides) do
      if abs(M.angle(wOut, w.way)) < M.FORK_DEG then close = w.way break end
    end
    if close then
      -- (our way to the left of the other road: keep left)
      kind, side = 'fork', (M.angle(close, wOut) > 0) and 'left' or 'right'
    end
  end
  local out = {}
  for i, w in ipairs(sides) do
    out[i] = { deg = M.dirToBearing(w.way.x, w.way.y),
               halfW = (type(w.halfW) == 'number' and w.halfW > 0) and w.halfW or nil }
  end
  return { kind = kind, side = side, inDeg = M.dirToBearing(wIn.x, wIn.y), outDeg = M.dirToBearing(wOut.x, wOut.y),
           sides = out }
end

------------------------------------------------------------------------------------------ the file

-- A junction as the matched file's entry (format 2), at lat / lon.
function M.encode(j, lat, lon)
  -- (to 0.1 degree; 359.96 rounds to 360, written as 0)
  local function deg(d) return wrap360(round(d, 1)) end
  local sides = {}
  for i, s in ipairs(j.sides or {}) do
    sides[i] = { deg(s.deg), (type(s.halfW) == 'number' and s.halfW > 0) and round(s.halfW, 1) or 0 }
  end
  local half = (type(j.half) == 'number' and j.half > 0) and round(j.half, 1) or 0
  return { lat, lon, j.kind, j.side or '', deg(j.inDeg or 0), deg(j.outDeg or 0), sides, half }
end

-- A matched file's junction entry (format 1 or 2) as a junction: { lat, lon, kind, side, inDeg, outDeg, sides, half },
-- the last four nil when the file did not keep them (half: an entry of seven, or 0). nil for an entry that is not one.
function M.decode(e)
  if type(e) ~= 'table' or type(e[1]) ~= 'number' or type(e[2]) ~= 'number' or type(e[3]) ~= 'string' then
    return nil
  end
  local j = { lat = e[1], lon = e[2], kind = e[3], side = type(e[4]) == 'string' and e[4] or '' }
  if type(e[5]) == 'number' and type(e[6]) == 'number' and type(e[7]) == 'table' then
    j.inDeg, j.outDeg = wrap360(e[5]), wrap360(e[6])
    local sides = {}
    for _, s in ipairs(e[7]) do
      if type(s) == 'table' and type(s[1]) == 'number' then
        sides[#sides + 1] = { deg = wrap360(s[1]), halfW = (type(s[2]) == 'number' and s[2] > 0) and s[2] or nil }
      end
    end
    j.sides = sides
    if type(e[8]) == 'number' and e[8] > 0 then j.half = e[8] end
  end
  return j
end

------------------------------------------------------------------------------------------ placing a file's points

-- Points kept in order along a stage (the matched file's junctions, its bridges: the auto recce wrote them in the
-- order it met them) placed on the line the stage runs on, each on its own pass of it. A whole-line nearest search
-- puts both passes of a junction the stage goes through twice (a super special, a stage that crosses itself) on
-- whichever pass is nearer; here each point is looked for from the last one placed on (from NEXT_M past it), and
-- of the passes of the line within maxOff of it the first that comes within PASS_SLACK_M of the nearest is taken
-- (not merely the first: the line running past a few metres off before it reaches the point).
--   pts  { { x, y }... } in order (game coordinates), nil entries allowed (a point that could not be converted)
-- Returns { [k] = { along, off } } for the points placed, nil at the others.
M.NEXT_M = 10.0
M.PASS_SLACK_M = 5.0
function M.placeInOrder(line, cum, pts, maxOff)
  local out = {}
  local n = #line
  if n < 2 then return out end
  local from = 0
  for k = 1, #pts do
    local p = pts[k]
    if p and p.x then
      local lo = geo.segAt(cum, math.min(cum[n], from))
      -- every pass of the line within maxOff from `lo` on: { along, off } the nearest point of each
      local passes, cur = {}, nil
      for i = lo, n - 1 do
        local _, _, s, off = geo.locate(line, cum, p, i, i)
        if s >= from and off <= maxOff then
          if not cur then cur = { along = s, off = off } passes[#passes + 1] = cur
          elseif off < cur.off then cur.along, cur.off = s, off end
        elseif off > maxOff then
          cur = nil
        end
      end
      local best = huge
      for _, ps in ipairs(passes) do if ps.off < best then best = ps.off end end
      for _, ps in ipairs(passes) do
        if ps.off <= best + M.PASS_SLACK_M then
          out[k] = { along = ps.along, off = ps.off }
          from = ps.along + M.NEXT_M
          break
        end
      end
    end
  end
  return out
end

return M
