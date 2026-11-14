-- earthRally/junctions: the junctions along a stage -- where the stage meets another road, which way it comes in and
-- leaves by, and the side roads it does not take -- from either of two places, judged by one rule:
--
--   * the matched file (autoRecce.lua in the game, tools/auto_recce.py offline), which finds them on the road graph
--     when the stage is matched and keeps them as lat / lon;
--   * BeamNG.Earth's live road map (map.getMap(), as props.lua reads it), for a stage with only a driven recce or a
--     matched file older than format 2, which kept no side roads. Only the roads round the car are loaded, so this
--     is asked a stretch of the line at a time, as the car comes near it.
--
-- Both go through M.branch and M.judge below, so a junction found one way and the same junction found the other
-- come out the same. Pure and offline (tests/test_junctions.lua): nothing from the game.
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
--   from a file, also lat, lon; from the live map, also x, y, z (the junction node, game coordinates) and node.
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
--   [lat, lon, kind, side, inDeg, outDeg, [[sideDeg, halfW], ...]]
-- bearings to 0.1 degree, halfW to 0.1 m and 0 where it is not known (never null: the game's JSON reader turns a
-- null into a hole in the array, and a hole stops ipairs). M.encode / M.decode write and read it; a format 1 entry
-- decodes with no inDeg, outDeg or sides.
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
-- The stage's own way in and out, measured this far back and on along the line. The auto recce takes it three
-- points of its 4 m line either side (floor(JUNCTION_LOOK_M / OUT_STEP_M) = 3), which is 12 m; the live finder
-- measures the same 12 m on whatever line it is given, so the two agree on a junction's turn.
M.WAY_ALONG_M = 12.0
M.MERGE_M = 15.0            -- a file's junction and a live one this close along the line: the same junction
M.LIVE_PAD_M = 300.0        -- the live map read this far round the stretch asked about (the side roads' walks)

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
  return { lat, lon, j.kind, j.side or '', deg(j.inDeg or 0), deg(j.outDeg or 0), sides }
end

-- A matched file's junction entry (format 1 or 2) as a junction: { lat, lon, kind, side, inDeg, outDeg, sides },
-- the last three nil when the file did not keep them. nil for an entry that is not one.
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
  end
  return j
end

------------------------------------------------------------------------------------------ the live road map

-- The junctions on a stretch of a line, from the game's live road map.
--   nodes  map.getMap().nodes: { [name] = { pos = { x, y, z }, radius = half width, links = { [name] = ... } } }
--   line   the line the stage runs on, game coordinates ({ x, y, z, gap }... as runner.lua's run.line)
--   fromAlong, toAlong   the stretch, m along the line (default all of it)
--   cum    the line's cumulative distances (geo.cumulative), when the caller has them already
-- Returns junctions in order along the line ({ along, x, y, z, node, kind, side, inDeg, outDeg, sides }), one per
-- JUNCTION_GAP_M, as autoRecce.junctions finds them on the road graph: a node of three roads or more within
-- ON_LINE_M of the line, not on a stretch of it with no road (gap), with a side road 40 m+ long.
--
-- The links are read both ways (a node's neighbour is any node it links to or that links to it), so a one-way link
-- written on one end only still makes a junction. Only the nodes within LIVE_PAD_M of the stretch are looked at.
function M.live(nodes, line, fromAlong, toAlong, cum)
  local out = {}
  if type(nodes) ~= 'table' or type(line) ~= 'table' or #line < 3 then return out end
  cum = cum or geo.cumulative(line)
  local total = cum[#cum]
  fromAlong = math.max(0, fromAlong or 0)
  toAlong = math.min(total, toAlong or total)
  if toAlong < fromAlong then return out end
  -- the stretch's segments, a little beyond it at each end (a junction at its very edge is still found whole)
  local lo = geo.segAt(cum, math.max(0, fromAlong - M.ON_LINE_M))
  local hi = math.min(#line - 1, geo.segAt(cum, math.min(total, toAlong + M.ON_LINE_M)) + 1)
  local x0, y0, x1, y1 = huge, huge, -huge, -huge
  for i = lo, hi + 1 do
    local p = line[i]
    if p.x < x0 then x0 = p.x end
    if p.x > x1 then x1 = p.x end
    if p.y < y0 then y0 = p.y end
    if p.y > y1 then y1 = p.y end
  end
  local function inBox(p, pad)
    return p.x >= x0 - pad and p.x <= x1 + pad and p.y >= y0 - pad and p.y <= y1 + pad
  end
  -- the road map round the stretch, its links both ways
  local xy, nbr, half = {}, {}, {}
  local function put(a, pa, ra)
    if not xy[a] then
      xy[a] = { x = pa.x, y = pa.y, z = pa.z }
      half[a] = ra
      nbr[a] = {}
    end
  end
  for na, a in pairs(nodes) do
    local pa = type(a) == 'table' and a.pos
    if pa and inBox(pa, M.LIVE_PAD_M) then
      put(na, pa, a.radius)
      for nb in pairs(a.links or {}) do
        local b = nodes[nb]
        local pb = type(b) == 'table' and b.pos
        if pb and nb ~= na then
          put(nb, pb, b.radius)
          nbr[na][nb] = true
          nbr[nb][na] = true
        end
      end
    end
  end
  -- the candidates: three roads or more, on the line
  local cand = {}
  for n, ns in pairs(nbr) do
    local deg = 0
    for _ in pairs(ns) do deg = deg + 1 end
    local p = xy[n]
    if deg >= 3 and inBox(p, M.ON_LINE_M) then
      local i, t, s, off = geo.locate(line, cum, p, lo, hi)
      local near = (t < 0.5) and line[i] or line[i + 1]
      if off <= M.ON_LINE_M and s >= fromAlong and s <= toAlong and s > 1 and s < total - 1 and not near.gap then
        cand[#cand + 1] = { s = s, n = n }
      end
    end
  end
  table.sort(cand, function(p, q) if p.s ~= q.s then return p.s < q.s end return tostring(p.n) < tostring(q.n) end)
  local last = -huge
  for _, c in ipairs(cand) do
    if c.s - last >= M.JUNCTION_GAP_M then
      local p = xy[c.n]
      local a = geo.pointAt(line, cum, c.s - M.WAY_ALONG_M)
      local b = geo.pointAt(line, cum, c.s + M.WAY_ALONG_M)
      local wIn = { x = p.x - a.x, y = p.y - a.y }
      local wOut = { x = b.x - p.x, y = b.y - p.y }
      local ways = {}
      for m in pairs(nbr[c.n]) do
        local way, len, w = M.branch(xy, nbr, half, c.n, m)
        ways[#ways + 1] = { m = m, way = way, len = len, halfW = w }
      end
      local j = M.judge(wIn, wOut, ways)
      if j then
        last = c.s
        j.along, j.x, j.y, j.z, j.node = c.s, p.x, p.y, p.z, c.n
        out[#out + 1] = j
      end
    end
  end
  return out
end

------------------------------------------------------------------------------------------ the two together

-- The file's junctions and the live map's, as one list in order along the line. Both lists carry `along` on the
-- same line (a file's junction placed on it by the caller: one it could not place, with no along, is left out).
-- Where both have a junction within tolM (default MERGE_M) along, the file's wins: it was judged on the whole road
-- graph, the live map only on what was loaded round the car. The live map adds the junctions the file does not have,
-- and fills in the way in, the way out and the side roads of a file junction that has none (format 1), keeping the
-- file's kind and side. Each result is a new table, with `from` = 'file', 'live' or 'file+live'.
function M.merge(fromFile, fromLive, tolM)
  tolM = tolM or M.MERGE_M
  local live = {}
  for _, j in ipairs(fromLive or {}) do
    if type(j.along) == 'number' then live[#live + 1] = { j = j, used = false } end
  end
  local out = {}
  local function copy(j, from)
    local c = {}
    for k, v in pairs(j) do c[k] = v end
    c.from = from
    return c
  end
  for _, f in ipairs(fromFile or {}) do
    if type(f.along) == 'number' then
      local best, bd = nil, huge
      for _, l in ipairs(live) do
        local d = abs(l.j.along - f.along)
        if not l.used and d <= tolM and d < bd then best, bd = l, d end
      end
      local c = copy(f, 'file')
      if best then
        best.used = true
        if not (type(f.sides) == 'table' and #f.sides > 0) then
          c.inDeg, c.outDeg, c.sides = best.j.inDeg, best.j.outDeg, best.j.sides
          c.from = 'file+live'
        end
        if c.x == nil then c.x, c.y, c.z, c.node = best.j.x, best.j.y, best.j.z, best.j.node end
      end
      out[#out + 1] = c
    end
  end
  for _, l in ipairs(live) do
    if not l.used then out[#out + 1] = copy(l.j, 'live') end
  end
  table.sort(out, function(p, q) return p.along < q.along end)
  return out
end

return M
