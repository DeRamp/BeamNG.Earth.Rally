-- earthRally/autoRecce: the auto recce -- a stage's map line matched onto BeamNG.Earth's own roads here in the
-- running game, so a map dropped into the import folder drives with no recce and no Python.
--
-- The line a stage is timed on has until now come from one of two places: a recce the player drove, or
-- tools/auto_recce.py, a developer tool needing BeamNG.Earth's source and its Python environment. This is the same
-- matching, in the mod's own Lua: ask BeamNG.Earth for a window of its AI road graph at each point along the stage
-- corridor (earthAdapter.roadGraph), stitch the windows by node name, route along the roads from point to point of
-- the organisers' line, and write the same file tools/auto_recce.py writes -- earthRally/matched/<event>__<stage>.json,
-- which events.stageLine already prefers when there is no recce.
--
-- What is ported from tools/auto_recce.py and what is not
--
--   Ported, at the same constants, so the two produce comparable lines: resample, the waypoint snap, the A* between
--   consecutive snaps, the detour test, the gap stretches kept on the organisers' line and eased in and out over
--   BLEND_M, the junction landmarks (branch / angle), and the output file's every key.
--
--   Not ported, and not needed: the Python's whole road-graph build. It read the map cells itself, merged vertices
--   within MERGE_M, cut roads into PIECE_M pieces and bridged dead ends within BRIDGE_M / BRIDGE_ON_LINE_M, all to
--   recover a connected graph from per-cell road geometry. The road graph arrives already simplified, with junction
--   connectors shared and one node per junction, so MERGE_M, PIECE_M, BRIDGE_M, BRIDGE_ON_LINE_M, ON_LINE_M and the
--   NOT_ROADS filter (the graph is the AI's: it holds drivable roads only) all have nothing left to do here.
--
--   Not available, and no substitute invented: the bridges. See M.BRIDGES_NOT_AVAILABLE below.
--
-- Heights come from the graph's own z, which is the drivable surface with bridge decks and tunnel floors already
-- baked in -- better than the Python's DEM sample, which reads the bare ground and so sits under a bridge deck.
-- Across a gap stretch, where there is no road to take a height from, the height is interpolated between the road
-- at each end of the gap; the Python sampled the DEM there. That is the one place this produces a worse height than
-- the tool, and it is in a stretch already flagged so the co-driver calls no notes.
--
-- Everything from the frame maths down is pure and offline (tests/test_autorecce.lua): the accumulation takes
-- lat / lon, never game coordinates, because BeamNG.Earth rebases the world origin and every game coordinate kept
-- across a rebase is stale.
-- (not geo.lua: its resample, cumulative and locate all work on a line the car is driving along and keep the
-- game's own frame. What is needed here is the Python tool's own frame and resample, point for point, or a line
-- matched in the game and one matched by the tool would not agree. geo.metres uses the same approximation as
-- M.frame below, and the two can be checked against each other -- tests/test_autorecce.lua does.)
local earth = require('earthRally/earthAdapter')
local events = require('earthRally/events')

local M = {}

local floor, sqrt, abs, huge = math.floor, math.sqrt, math.abs, math.huge
local R_EARTH = 6371008.8

------------------------------------------------------------------------------------------ constants

-- (tools/auto_recce.py's own, at the same values: a line matched here and one matched there should agree)
M.WAYPOINT_M = 400.0        -- the organisers' line is followed through a point every this many metres
M.SNAP_M = 60.0             -- a waypoint this close to a road is on it (else that stretch has no road on the map)
M.NEAR_M = 15.0             -- a road this far from the organisers' line costs double per metre (quadratic beyond)
M.CORRIDOR_M = 300.0        -- roads further than this from the line are not used
M.DETOUR_MAX = 1.4          -- a route between two waypoints longer than this times their distance along the line
                            -- + 100 m is a detour: that stretch is kept as the organisers' line
M.BLEND_M = 120.0           -- a stretch on the organisers' line eased into the road over this at each end
M.OUT_STEP_M = 4.0          -- the matched line's point spacing (as a recce's)
M.HEIGHT_OFFSET_M = 0.2     -- a recce's heights (the car's position) sit this far above the surface
M.JUNCTION_LOOK_M = 15.0    -- a junction's roads: their way this far from it
M.SIDE_ROAD_MIN_M = 40.0    -- a side road shorter than this (a driveway, a stub of track) is no junction
M.TURN_DEG = 30.0           -- the stage turning more than this at a junction: a turn there ("at junction")
M.FORK_DEG = 35.0           -- a side road within this of the stage's way on: a fork ("keep left / right")
M.JUNCTION_GAP_M = 25.0     -- junctions closer than this along the stage: one
M.ON_LINE_M = 1.5           -- a junction node this close to the matched line is on it

-- the windows
M.RADIUS_M = 1000.0         -- each window is a square of this half size round the point we name
M.MAX_RADIUS_M = 2000.0     -- BeamNG.Earth's own cap on it (assumed: see the note on the API at the foot of this file)
M.COVER_SAMPLE_M = 20.0     -- the stage corridor is checked for coverage at a point every this far along it
M.RETRIES = 2               -- a window re-asked for this many times when the world's origin moved under it

-- There is no bridge flag in the road graph. Nodes on a bridge carry the deck height, which is the right height,
-- but nothing in the nodes or the edges says "this stretch is a bridge", and it cannot be recovered from the
-- heights (a road in a cutting looks the same). So `bridges` is written empty -- NOT because the stage has no
-- bridges, but because this recce cannot see them. The 'overBridge' landmark (stageWriter.LANDMARKS, read through
-- events.landmarks) is therefore never called on a stage matched in the game, and is called on the same stage
-- matched by tools/auto_recce.py, which reads BeamNG.Earth's level ranges and does know. Nobody should read an
-- empty list here as a statement about the road.
M.BRIDGES_NOT_AVAILABLE = 'the in-game road graph has no bridge flag'

M.SOURCE = "BeamNG.Earth's roads (the in-game auto recce)"

-- How an auto recce ended, which the menu needs apart from the sentence because the four endings are four
-- colours (docs/mockups-1.3.0/auto-recce-button.html section 5, main.lua's autoDone). The sentence alone will not
-- do: the page would have to match on its wording, and the wording is the part that changes.
--   DONE     the file is written; the stage's own status says the rest
--   PARTIAL  part of the stage has no map data on this computer: nothing written, and running it again after
--            driving that ground is what helps
--   NODATA   there was nothing to match to anywhere on the stage: nothing written. A normal outcome for ground
--            the player has never been over -- not an error, and not shown as one
--   FAILED   it stopped part way: nothing written
M.DONE, M.PARTIAL, M.NODATA, M.FAILED = 'done', 'partial', 'nodata', 'failed'

-- Overridable for the tests: wall seconds (`seconds` in the file is how long the whole auto recce took, most of it
-- spent waiting on BeamNG.Earth between windows, so this is wall time and not os.clock's CPU time).
function M.clock() return os.time() end

------------------------------------------------------------------------------------------ pure geometry

local function round(v, n) local m = 10 ^ n return floor(v * m + 0.5) / m end

local function dist(a, b)
  local dx, dy = b.x - a.x, b.y - a.y
  return sqrt(dx * dx + dy * dy)
end

-- A flat frame in metres east / north of (lat0, lon0) -- the same equirectangular approximation as geo.metres and
-- as the Python tool's Frame. The stage's own frame, not the game's: it does not move when the world's origin does.
function M.frame(lat0, lon0)
  local ky = math.rad(1) * R_EARTH
  local kx = ky * math.cos(math.rad(lat0))
  return {
    xy = function(lat, lon) return { x = (lon - lon0) * kx, y = (lat - lat0) * ky } end,
    latlon = function(x, y) return lat0 + y / ky, lon0 + x / kx end,
  }
end

-- The polyline every `step` m along it (the first and the last point kept), and the distance along it of each.
-- z is carried through where both ends of a segment have one.
--
-- (Not geo.resample: that one replaces the last sample when the line's end is within a quarter step of it, and the
-- output file's `ll(s)` reads a point back by index as round(s / OUT_STEP_M), which wants the spacing exactly even
-- all the way and the end simply added. This is the Python tool's resample, which is also what produced the 116
-- matched files on this machine.)
function M.resample(pts, step)
  local n = #pts
  if n == 0 then return {}, {} end
  local out = { { x = pts[1].x, y = pts[1].y, z = pts[1].z } }
  local along = { 0 }
  local acc, carry = 0.0, 0.0
  for i = 1, n - 1 do
    local a, b = pts[i], pts[i + 1]
    local seg = dist(a, b)
    local pos = step - carry
    while pos <= seg do
      local t = pos / seg
      out[#out + 1] = { x = a.x + (b.x - a.x) * t, y = a.y + (b.y - a.y) * t,
                        z = (a.z and b.z) and (a.z + (b.z - a.z) * t) or nil }
      along[#along + 1] = acc + pos
      pos = pos + step
    end
    carry = seg - (pos - step)
    acc = acc + seg
  end
  -- (the line's own end always: dropping it when near the last point cut matched lines up to a quarter step short
  -- of the flying finish -- tools/auto_recce.py's own note, review 2026-11-12)
  if dist(out[#out], pts[n]) > 0.5 then
    out[#out + 1] = { x = pts[n].x, y = pts[n].y, z = pts[n].z }
    along[#along + 1] = acc
  end
  return out, along
end

-- The signed angle from u to v (degrees, + to the left). tools/auto_recce.py's _angle.
function M.angle(u, v)
  return math.deg(math.atan2(u.x * v.y - u.y * v.x, u.x * v.x + u.y * v.y))
end

-- Distance from p to the segment a -> b.
local function segDist(p, a, b)
  local dx, dy = b.x - a.x, b.y - a.y
  local l2 = dx * dx + dy * dy
  local t = 0
  if l2 > 1e-12 then
    t = ((p.x - a.x) * dx + (p.y - a.y) * dy) / l2
    if t < 0 then t = 0 elseif t > 1 then t = 1 end
  end
  local ex, ey = a.x + dx * t - p.x, a.y + dy * t - p.y
  return sqrt(ex * ex + ey * ey)
end
M.segDist = segDist

-- Distance from p to a polyline (the Python's seg_dist for one point).
local function polyDist(p, pts)
  local best = huge
  for i = 1, #pts - 1 do
    local d = segDist(p, pts[i], pts[i + 1])
    if d < best then best = d end
  end
  return best
end
M.polyDist = polyDist

-- A grid of a polyline's segments, so "is this node on the matched line?" is not every node against every segment
-- (a 12 km stage: ~3,000 segments against a few thousand junction candidates, which the Python did in numpy and
-- Lua should not do at all). cell: the bucket size in metres.
local function segGrid(pts, cell)
  local b = {}
  local function key(cx, cy) return cx .. ':' .. cy end
  for i = 1, #pts - 1 do
    local a, c = pts[i], pts[i + 1]
    local x0, x1 = floor(math.min(a.x, c.x) / cell), floor(math.max(a.x, c.x) / cell)
    local y0, y1 = floor(math.min(a.y, c.y) / cell), floor(math.max(a.y, c.y) / cell)
    for cx = x0, x1 do
      for cy = y0, y1 do
        local k = key(cx, cy)
        local t = b[k]
        if not t then t = {} b[k] = t end
        t[#t + 1] = i
      end
    end
  end
  -- The nearest point of the line to p within `reach`: the distance and the index of the nearer end of the nearest
  -- segment, or nil when nothing is in reach.
  return function(p, reach)
    local rings = floor(reach / cell) + 1
    local cx, cy = floor(p.x / cell), floor(p.y / cell)
    local bd, bi = huge, nil
    for ix = cx - rings, cx + rings do
      for iy = cy - rings, cy + rings do
        for _, i in ipairs(b[key(ix, iy)] or {}) do
          local d = segDist(p, pts[i], pts[i + 1])
          if d < bd then
            bd = d
            bi = (dist(p, pts[i]) <= dist(p, pts[i + 1])) and i or (i + 1)
          end
        end
      end
    end
    if bd > reach then return nil end
    return bd, bi
  end
end

------------------------------------------------------------------------------------------ the graph

-- A min-heap for the A*, keyed by f.
local function heapPush(h, f, g, n)
  h[#h + 1] = { f = f, g = g, n = n }
  local i = #h
  while i > 1 do
    local p = floor(i / 2)
    if h[p].f <= h[i].f then break end
    h[p], h[i] = h[i], h[p]
    i = p
  end
end

local function heapPop(h)
  local top = h[1]
  local last = #h
  h[1] = h[last]
  h[last] = nil
  local i, n = 1, last - 1
  while true do
    local l, r, best = i * 2, i * 2 + 1, i
    if l <= n and h[l].f < h[best].f then best = l end
    if r <= n and h[r].f < h[best].f then best = r end
    if best == i then break end
    h[i], h[best] = h[best], h[i]
    i = best
  end
  return top
end

-- The window's node and edge rows, read tolerantly.
--
-- navgraph.py writes a node as the array [x, y, z, radius] and an edge as [inNode, outNode, oneWay, lanesOut,
-- lanesIn, speedMs, drivability, radius, ...] (its `build` docstring, verified on the branch). docs/ADDONS.md
-- describes the modding API's tables by name. Which of the two shapes api.roadGraph hands an add-on is not settled
-- upstream, so both are read: an array row by index, a table row by name. If the field layout changes, this is the
-- one place that has to follow it.
local function nodePos(n)
  if type(n) ~= 'table' then return nil end
  if n.x ~= nil then return n.x, n.y, n.z, n.radius end
  return n[1], n[2], n[3], n[4]
end

local function edgeEnds(e)
  if type(e) ~= 'table' then return nil end
  if e.inNode ~= nil then return e.inNode, e.outNode end
  return e[1], e[2]
end

-- The accumulated graph (nodes in lat / lon, edges as pairs of node names) weighted against the organisers' line
-- `kml` in the stage's frame:
--   { xy = { [name] = {x, y, z} }, nbr = { [name] = { [name] = {w, len} } }, near = { [name] = m off the line },
--     ea, eb = the edges once each, for snapping; edges = how many }
-- fr: the stage's frame (M.frame), which places the lat / lon nodes.
--
-- The weighting is the Python's: a metre of road costs 1 + (d / NEAR_M)^2 metres, d being how far from the
-- organisers' line it lies, so the route prefers the road the organisers drew over a parallel one. An edge is
-- judged by its two ends and its middle (the Python cut every road into PIECE_M pieces to the same end: the graph's
-- nodes already sit every few metres along each smoothed arc, but a long straight is one edge, and its middle is
-- what says whether it runs away from the line). Direction is ignored, as in the tool: a rally stage is a closed
-- road, and the one-way field describes normal traffic.
function M.build(graph, kml, fr)
  local g = { xy = {}, nbr = {}, near = {}, ea = {}, eb = {}, edges = 0 }
  for name, n in pairs(graph.nodes or {}) do
    local lat, lon, alt = n.lat, n.lon, n.alt
    if lat ~= nil then
      local p = fr.xy(lat, lon)
      g.xy[name] = { x = p.x, y = p.y, z = alt }
      g.near[name] = polyDist(p, kml)
      g.nbr[name] = {}
    end
  end
  local seen = {}
  for _, e in ipairs(graph.edges or {}) do
    local a, b = edgeEnds(e)
    local pa, pb = a and g.xy[a], b and g.xy[b]
    -- (an edge clipped at a window's edge can name a node that window did not hand out; the windows overlap by
    --  twice the corridor, so the neighbouring one supplies it, and by here every window has been read. An edge
    --  whose node never arrived at all is dropped rather than guessed at.)
    if pa and pb and a ~= b then
      local k = (a < b) and (a .. '|' .. b) or (b .. '|' .. a)
      if not seen[k] then
        seen[k] = true
        local mid = { x = (pa.x + pb.x) / 2, y = (pa.y + pb.y) / 2 }
        local dm = (g.near[a] + g.near[b] + polyDist(mid, kml)) / 3
        if dm <= M.CORRIDOR_M then
          local len = dist(pa, pb)
          local w = len * (1 + (dm / M.NEAR_M) ^ 2)
          g.nbr[a][b] = { w = w, len = len }
          g.nbr[b][a] = { w = w, len = len }
          g.edges = g.edges + 1
          g.ea[#g.ea + 1] = a
          g.eb[#g.eb + 1] = b
        end
      end
    end
  end
  return g
end

-- The road point nearest p within SNAP_M on an edge not across `direction` (more than ~60 degrees off):
-- { a, b, t, x, y, z } or nil. tools/auto_recce.py's Roads.snap.
function M.snap(g, p, direction)
  if g.edges == 0 then return nil end
  local dl = sqrt(direction.x * direction.x + direction.y * direction.y)
  if dl < 1e-9 then dl = 1e-9 end
  local bd, bi, bt = huge, nil, 0
  for i = 1, #g.ea do
    local a, b = g.xy[g.ea[i]], g.xy[g.eb[i]]
    local dx, dy = b.x - a.x, b.y - a.y
    local l2 = dx * dx + dy * dy
    if l2 < 1e-12 then l2 = 1e-12 end
    local t = ((p.x - a.x) * dx + (p.y - a.y) * dy) / l2
    if t < 0 then t = 0 elseif t > 1 then t = 1 end
    local qx, qy = a.x + dx * t, a.y + dy * t
    local d = sqrt((qx - p.x) ^ 2 + (qy - p.y) ^ 2)
    -- (any road very close; further out only one running the line's way)
    local cos = abs(dx * direction.x + dy * direction.y) / sqrt(l2) / dl
    if cos >= 0.5 or d <= 8.0 then
      if d < bd then bd, bi, bt = d, i, t end
    end
  end
  if not bi or bd > M.SNAP_M then return nil end
  local a, b = g.xy[g.ea[bi]], g.xy[g.eb[bi]]
  return { a = g.ea[bi], b = g.eb[bi], t = bt,
           x = a.x + (b.x - a.x) * bt, y = a.y + (b.y - a.y) * bt,
           z = (a.z and b.z) and (a.z + (b.z - a.z) * bt) or a.z or b.z }
end

-- Cheapest way from snap s to snap g (A*): the polyline (with heights) and its length, or nil.
-- tools/auto_recce.py's Roads.route, including its two virtual nodes at the snap points.
function M.route(gr, s, t)
  if (s.a == t.a and s.b == t.b) or (s.a == t.b and s.b == t.a) then
    local p0 = { x = s.x, y = s.y, z = s.z }
    local p1 = { x = t.x, y = t.y, z = t.z }
    return { p0, p1 }, dist(p0, p1)
  end
  local START, GOAL = '\1start', '\1goal'
  local p0 = { x = s.x, y = s.y }
  local p1 = { x = t.x, y = t.y }
  -- the cost per metre of the edge each snap sits on, so stepping onto the road costs what that road costs
  local function perM(a, b)
    local e = gr.nbr[a] and gr.nbr[a][b]
    if e and e.len > 1e-9 then return e.w / e.len end
    return 1.0
  end
  local k0 = perM(s.a, s.b)
  local fromStart = { { s.a, k0 * dist(p0, gr.xy[s.a]) }, { s.b, k0 * dist(p0, gr.xy[s.b]) } }
  local k1 = perM(t.a, t.b)
  local intoGoal = { [t.a] = k1 * dist(p1, gr.xy[t.a]), [t.b] = k1 * dist(p1, gr.xy[t.b]) }

  local function h(n)
    local q = gr.xy[n]
    return sqrt((q.x - p1.x) ^ 2 + (q.y - p1.y) ^ 2)
  end

  local best = { [START] = 0.0 }
  local came = {}
  local heap = {}
  heapPush(heap, 0.0, 0.0, START)
  while #heap > 0 do
    local top = heapPop(heap)
    local n, gn = top.n, top.g
    if n == GOAL then break end
    if gn <= (best[n] or huge) then
      if n == START then
        for _, it in ipairs(fromStart) do
          local m, w = it[1], it[2]
          local ng = gn + w
          if ng < (best[m] or huge) then
            best[m], came[m] = ng, START
            heapPush(heap, ng + h(m), ng, m)
          end
        end
      else
        for m, e in pairs(gr.nbr[n] or {}) do
          local ng = gn + e.w
          if ng < (best[m] or huge) then
            best[m], came[m] = ng, n
            heapPush(heap, ng + h(m), ng, m)
          end
        end
        local into = intoGoal[n]
        if into then
          local ng = gn + into
          if ng < (best[GOAL] or huge) then
            best[GOAL], came[GOAL] = ng, n
            heapPush(heap, ng, ng, GOAL)
          end
        end
      end
    end
  end
  if came[GOAL] == nil then return nil, nil end
  local path, n = {}, GOAL
  while n ~= START do
    n = came[n]
    if n ~= START then path[#path + 1] = n end
  end
  local pts = { { x = s.x, y = s.y, z = s.z } }
  for i = #path, 1, -1 do
    local q = gr.xy[path[i]]
    pts[#pts + 1] = { x = q.x, y = q.y, z = q.z }
  end
  pts[#pts + 1] = { x = t.x, y = t.y, z = t.z }
  local total = 0
  for i = 1, #pts - 1 do total = total + dist(pts[i], pts[i + 1]) end
  return pts, total
end

-- Walking from node n through m, the road turning least at each node: its way at JUNCTION_LOOK_M from n, and how
-- far it goes (up to SIDE_ROAD_MIN_M; less at a dead end). tools/auto_recce.py's Roads.branch.
function M.branch(gr, n, m)
  local prev, cur = n, m
  local d = dist(gr.xy[n], gr.xy[m])
  local o = gr.xy[n]
  local way = nil
  while true do
    if way == nil and d >= M.JUNCTION_LOOK_M then
      local p = gr.xy[cur]
      way = { x = p.x - o.x, y = p.y - o.y }
    end
    if d >= M.SIDE_ROAD_MIN_M then break end
    local pc, pp = gr.xy[cur], gr.xy[prev]
    local head = { x = pc.x - pp.x, y = pc.y - pp.y }
    local bestK, bestA = nil, huge
    for k in pairs(gr.nbr[cur] or {}) do
      if k ~= prev then
        local pk = gr.xy[k]
        local a = abs(M.angle(head, { x = pk.x - pc.x, y = pk.y - pc.y }))
        -- (a stable order: pairs() is not ordered, and two roads can leave at the same angle)
        if a < bestA or (a == bestA and bestK and k < bestK) then bestK, bestA = k, a end
      end
    end
    if not bestK then break end
    prev, cur = cur, bestK
    d = d + dist(gr.xy[prev], gr.xy[cur])
  end
  if way == nil then
    local p = gr.xy[cur]
    way = { x = p.x - o.x, y = p.y - o.y }
  end
  return way, d
end

-- The junctions along the matched line (res, every OUT_STEP_M; flags: 1 on a stretch with no road), as
-- { { along, kind, side } } with kind 'turn' (the stage turns there), 'straight' (on past a side road) or 'fork'
-- (side 'left' / 'right', the way the stage keeps). tools/auto_recce.py's landmarks(), its bridge half left out
-- (M.BRIDGES_NOT_AVAILABLE).
function M.junctions(gr, res, resAlong, flags)
  local out = {}
  if gr.edges == 0 or #res < 3 then return out end
  local nearLine = segGrid(res, 25.0)
  -- nodes with three or more roads, on the line itself (not merely near one of its points)
  local cand = {}
  for n, nbrs in pairs(gr.nbr) do
    local deg = 0
    for _ in pairs(nbrs) do deg = deg + 1 end
    if deg >= 3 then
      local d, k = nearLine(gr.xy[n], M.ON_LINE_M)
      -- (flags[k] ~= 1, not `not flags[k]`: the flag is 0 or 1 as the file carries it, and 0 is true in Lua -- the
      --  Python's `if flags[k]: continue` does not port across as it stands, and written that way this rejected
      --  every junction on every stage)
      if d and k and flags[k] ~= 1 and k > 1 and k < #res then
        cand[#cand + 1] = { s = resAlong[k], n = n, k = k }
      end
    end
  end
  table.sort(cand, function(p, q) if p.s ~= q.s then return p.s < q.s end return p.n < q.n end)
  local last = -huge
  local look = math.max(1, floor(M.JUNCTION_LOOK_M / M.OUT_STEP_M))
  for _, c in ipairs(cand) do
    local p = gr.xy[c.n]
    local a = res[math.max(1, c.k - look)]
    local b = res[math.min(#res, c.k + look)]
    local wIn = { x = p.x - a.x, y = p.y - a.y }
    local wOut = { x = b.x - p.x, y = b.y - p.y }
    local ways = {}
    for m in pairs(gr.nbr[c.n]) do
      local way, len = M.branch(gr, c.n, m)
      ways[#ways + 1] = { m = m, way = way, len = len }
    end
    table.sort(ways, function(u, v) return u.m < v.m end)
    -- the stage's own two roads: the one it comes in on and the one it leaves by
    local back = { x = -wIn.x, y = -wIn.y }
    local mIn, bestA = nil, huge
    for _, w in ipairs(ways) do
      local d = abs(M.angle(back, w.way))
      if d < bestA then mIn, bestA = w.m, d end
    end
    local mOut, bestB = nil, huge
    for _, w in ipairs(ways) do
      if w.m ~= mIn then
        local d = abs(M.angle(wOut, w.way))
        if d < bestB then mOut, bestB = w.m, d end
      end
    end
    local sides = {}
    for _, w in ipairs(ways) do
      if w.m ~= mIn and w.m ~= mOut and w.len >= M.SIDE_ROAD_MIN_M then sides[#sides + 1] = w.way end
    end
    if #sides > 0 and c.s - last >= M.JUNCTION_GAP_M then
      local kind, side = 'straight', ''
      local turn = M.angle(wIn, wOut)
      if abs(turn) >= M.TURN_DEG then
        kind, side = 'turn', ''
      else
        local close = nil
        for _, w in ipairs(sides) do
          if abs(M.angle(wOut, w)) < M.FORK_DEG then close = w break end
        end
        if close then
          -- (our way to the left of the other road: keep left)
          kind, side = 'fork', (M.angle(close, wOut) > 0) and 'left' or 'right'
        end
      end
      last = c.s
      out[#out + 1] = { c.s, kind, side }
    end
  end
  return out
end

------------------------------------------------------------------------------------------ the matching

-- Fill in the heights of points that have none (the stretches taken from the organisers' line, which no road gave a
-- height): interpolated along the line between the road height at each end, and held level past the last road
-- height at either end of the stage. The Python sampled BeamNG.Earth's DEM here; this is the one height this recce
-- makes up, inside a stretch already flagged so no notes are called on it.
local function fillHeights(pts)
  local n = #pts
  local first = nil
  for i = 1, n do if pts[i].z then first = i break end end
  if not first then return end           -- (no height anywhere: the file is written without them, as z nil -> 0)
  for i = 1, first - 1 do pts[i].z = pts[first].z end
  local i = first
  while i <= n do
    if pts[i].z then
      local j = i + 1
      while j <= n and not pts[j].z do j = j + 1 end
      if j > n then
        for k = i + 1, n do pts[k].z = pts[i].z end
        break
      end
      local span, z0, z1 = 0, pts[i].z, pts[j].z
      for k = i, j - 1 do span = span + dist(pts[k], pts[k + 1]) end
      if span > 1e-9 then
        local acc = 0
        for k = i + 1, j - 1 do
          acc = acc + dist(pts[k - 1], pts[k])
          pts[k].z = z0 + (z1 - z0) * (acc / span)
        end
      else
        for k = i + 1, j - 1 do pts[k].z = z0 end
      end
      i = j
    else
      i = i + 1
    end
  end
end

-- Match a stage's map line onto an accumulated road graph. Pure: no game, no files.
--   stage: the event's stage ({ id, line = { { lat, lon }... } })
--   graph: { nodes = { [name] = { lat, lon, alt, radius } }, edges = { { a, b } | { inNode =, outNode = } ... } }
-- Returns the matched file's table (the same keys tools/auto_recce.py writes), or nil and why.
function M.match(stage, graph, info)
  info = info or {}
  local line = stage.line
  if type(line) ~= 'table' or #line < 2 then return nil, 'the stage has no map line' end
  local t0 = M.clock()
  local fr = M.frame(line[1][1], line[1][2])
  local kml = {}
  for i, p in ipairs(line) do kml[i] = fr.xy(p[1], p[2]) end
  local kmlCum = 0
  for i = 1, #kml - 1 do kmlCum = kmlCum + dist(kml[i], kml[i + 1]) end

  local gr = M.build(graph, kml, fr)
  local wps, along = M.resample(kml, M.WAYPOINT_M)
  local fine, fineAlong = M.resample(kml, 5.0)

  -- the line's direction at s (over 20 m: its own points can be hundreds of metres apart)
  local function tangent(s)
    local function nearest(target)
      local bi, bd = 1, huge
      for k = 1, #fineAlong do
        local d = abs(fineAlong[k] - target)
        if d < bd then bi, bd = k, d end
      end
      return bi
    end
    local i0, i1 = nearest(s - 10), nearest(s + 10)
    if i1 == i0 then
      i1 = math.min(#fine, i0 + 1)
      i0 = math.max(1, i1 - 1)
    end
    return { x = fine[i1].x - fine[i0].x, y = fine[i1].y - fine[i0].y }
  end

  -- each waypoint on a road beside it, aligned with the line there
  local snaps = {}
  for i, p in ipairs(wps) do snaps[i] = M.snap(gr, p, tangent(along[i])) end

  local out, gaps, gapIdx = {}, {}, {}

  local function add(pts)
    for _, p in ipairs(pts) do
      if #out == 0 or dist(out[#out], p) > 0.05 then
        out[#out + 1] = { x = p.x, y = p.y, z = p.z }
      end
    end
  end

  local function kmlBetween(s0, s1)
    local pts = {}
    for k = 1, #fine do
      if fineAlong[k] >= s0 and fineAlong[k] <= s1 then pts[#pts + 1] = fine[k] end
    end
    return pts
  end

  -- the organisers' line from s0 to s1, eased in from the road point before it and out to the road point after it
  -- over BLEND_M (no sudden kink where a hand-drawn line meets the road: that would be a phantom hairpin)
  local function addGap(s0, s1, fromPt, toPt)
    local pts = kmlBetween(s0, s1)
    if #pts == 0 then return end
    local o0 = fromPt and { x = fromPt.x - pts[1].x, y = fromPt.y - pts[1].y } or { x = 0, y = 0 }
    local o1 = toPt and { x = toPt.x - pts[#pts].x, y = toPt.y - pts[#pts].y } or { x = 0, y = 0 }
    local total = 0
    for k = 1, #pts - 1 do total = total + dist(pts[k], pts[k + 1]) end
    local eased, acc = {}, 0
    for k = 1, #pts do
      if k > 1 then acc = acc + dist(pts[k - 1], pts[k]) end
      local w0 = math.max(0.0, 1 - acc / M.BLEND_M)
      local w1 = math.max(0.0, 1 - (total - acc) / M.BLEND_M)
      eased[k] = { x = pts[k].x + o0.x * w0 + o1.x * w1, y = pts[k].y + o0.y * w0 + o1.y * w1 }
    end
    local first = #out + 1
    add(eased)
    gapIdx[#gapIdx + 1] = { first, #out }
  end

  local i, n = 1, #wps
  while i < n do
    if snaps[i] == nil then
      -- no road near this waypoint: the organisers' line up to the next waypoint on a road
      local j = i + 1
      while j < n and snaps[j] == nil do j = j + 1 end
      gaps[#gaps + 1] = { along[i], along[j] }
      addGap(along[i], along[j], out[#out], snaps[j])
      i = j
    elseif snaps[i + 1] == nil then
      -- (the next one has no road: go straight on along the organisers' line from here)
      local k = i + 1
      while k < n and snaps[k] == nil do k = k + 1 end
      gaps[#gaps + 1] = { along[i], along[k] }
      add({ snaps[i] })
      addGap(along[i], along[k], snaps[i], snaps[k])
      i = k
    else
      local j = i + 1
      local pts, length = M.route(gr, snaps[i], snaps[j])
      local span = along[j] - along[i]
      if pts == nil or length > M.DETOUR_MAX * span + 100 then
        gaps[#gaps + 1] = { along[i], along[j] }
        add({ snaps[i] })
        addGap(along[i], along[j], snaps[i], snaps[j])
      else
        add(pts)
      end
      i = j
    end
  end
  if #out < 2 then return nil, 'no roads found near the stage' end

  local outCum = { 0 }
  for k = 1, #out - 1 do outCum[k + 1] = outCum[k] + dist(out[k], out[k + 1]) end
  local gapRanges = {}
  for _, gi in ipairs(gapIdx) do gapRanges[#gapRanges + 1] = { outCum[gi[1]], outCum[gi[2]] } end
  fillHeights(out)

  local res, resAlong = M.resample(out, M.OUT_STEP_M)
  local flags = {}
  for k = 1, #res do
    flags[k] = 0
    for _, gp in ipairs(gapRanges) do
      if resAlong[k] >= gp[1] and resAlong[k] <= gp[2] then flags[k] = 1 break end
    end
  end
  local latLon = {}
  for k = 1, #res do
    local la, lo = fr.latlon(res[k].x, res[k].y)
    latLon[k] = { la, lo }
  end
  local juncs = M.junctions(gr, res, resAlong, flags)

  -- (a landmark's place on the matched line, as lat / lon: the mod finds it on whichever line the stage runs on)
  local function ll(s)
    local k = math.min(#resAlong, math.max(1, floor(s / M.OUT_STEP_M + 0.5) + 1))
    return round(latLon[k][1], 7), round(latLon[k][2], 7)
  end

  local total, gapM = 0, 0
  for k = 1, #res - 1 do total = total + dist(res[k], res[k + 1]) end
  for _, gp in ipairs(gaps) do gapM = gapM + (gp[2] - gp[1]) end
  local maxOff = 0
  for k = 1, #res do
    local d = polyDist(res[k], kml)
    if d > maxOff then maxOff = d end
  end

  local points = {}
  for k = 1, #res do
    local p = { round(latLon[k][1], 7), round(latLon[k][2], 7),
                round((res[k].z or 0) + M.HEIGHT_OFFSET_M, 2) }
    if flags[k] == 1 then p[4] = 1 end           -- (runner.lua reads p[4] == 1 as "no notes along here")
    points[k] = p
  end
  local gapsOut = {}
  for k, gp in ipairs(gaps) do gapsOut[k] = { round(gp[1], 1), round(gp[2], 1) } end
  local juncOut = {}
  for k, j in ipairs(juncs) do
    local la, lo = ll(j[1])
    juncOut[k] = { la, lo, j[2], j[3] }
  end

  return {
    format = 1,
    stage = stage.id,
    source = M.SOURCE,
    date = os.date('!%Y-%m-%dT%H:%M:%SZ'),
    mapKey = events.mapKey(line),
    lengthM = round(total, 1),
    mapLineM = round(kmlCum, 1),
    gaps = gapsOut,
    gapM = round(gapM, 1),
    maxOffMapLineM = round(maxOff, 1),
    -- `cells` is how many map cells tools/auto_recce.py read off disk to build its own graph. Nothing in the
    -- road-graph window says how many cells went into it, and this recce never reads a cell itself, so there is no
    -- honest number to put here: 0 means "not known from in the game", and `source` says which recce wrote the
    -- file. It is kept rather than dropped so a matched file has one shape whichever recce made it.
    cells = 0,
    roadEdges = gr.edges,
    seconds = round(M.clock() - t0, 1),
    junctions = juncOut,
    bridges = {},                      -- M.BRIDGES_NOT_AVAILABLE: not "no bridges on this stage"
    points = points,
  }
end

------------------------------------------------------------------------------------------ the windows

-- The windows that cover a stage's corridor: { { lat, lon } ... }, as few as will do. Each window is a square of
-- `radius` half size, and only its inner part is trusted -- a road CORRIDOR_M off the line has to be inside the
-- window too, or the route round that stretch would be matched against roads that were merely cut off by the
-- window's edge. So the step along the line is (radius - CORRIDOR_M), walked greedily.
function M.plan(line, radius)
  radius = math.min(radius or M.RADIUS_M, M.MAX_RADIUS_M)
  local inner = radius - M.CORRIDOR_M
  if inner < M.COVER_SAMPLE_M then return nil, 'the window radius leaves no room for the corridor' end
  local fr = M.frame(line[1][1], line[1][2])
  local pts = {}
  for i, p in ipairs(line) do pts[i] = fr.xy(p[1], p[2]) end
  local walk = M.resample(pts, M.COVER_SAMPLE_M)
  local out = {}
  local centre = nil
  for _, p in ipairs(walk) do
    if centre == nil or abs(p.x - centre.x) > inner or abs(p.y - centre.y) > inner then
      centre = { x = p.x, y = p.y }
      local la, lo = fr.latlon(p.x, p.y)
      out[#out + 1] = { lat = la, lon = lo, x = p.x, y = p.y }
    end
  end
  return out, nil, radius, inner
end

-- Is the whole stage inside a window that came back complete? true, or false and how many metres of it are not.
-- The third return is the length walked, so a caller can tell "a stretch of it" from "none of it".
--
-- This is the record requirement 3 of the 1.3.0 plan asks for, and the only thing standing between a half-covered
-- stage and a file that looks runnable: events.lineValid checks a line has two points and nothing more, the mod
-- reads `gapM` for the menu's wording but never `gaps`, and the runner would happily drive the car off the end of a
-- line that stopped at the edge of the last window it managed to read. A stretch with no road is a different thing
-- and is allowed -- it is filled from the organisers' line and flagged. A stretch never looked at is not.
function M.coverage(line, windows, inner)
  local fr = M.frame(line[1][1], line[1][2])
  local pts = {}
  for i, p in ipairs(line) do pts[i] = fr.xy(p[1], p[2]) end
  local walk, walkAlong = M.resample(pts, M.COVER_SAMPLE_M)
  local total = walkAlong[#walkAlong] or 0
  local uncovered = 0
  for k, p in ipairs(walk) do
    local ok = false
    for _, w in ipairs(windows) do
      if w.complete and abs(p.x - w.x) <= inner and abs(p.y - w.y) <= inner then ok = true break end
    end
    if not ok then
      local a = (k > 1) and (walkAlong[k] - walkAlong[k - 1]) or 0
      local b = (k < #walk) and (walkAlong[k + 1] - walkAlong[k]) or 0
      uncovered = uncovered + (a + b) / 2
    end
  end
  if uncovered <= 0 then return true, 0, total end
  return false, uncovered, total
end

------------------------------------------------------------------------------------------ running one

local job = nil        -- { event, stage, plan, windows, graph, i, done, radius, inner, tries, gen }
local gen = 0

function M.active() return job ~= nil end

-- How far along the auto recce is: { windows, done, stage, event }, or nil.
function M.progress()
  if not job then return nil end
  return { windows = #job.plan, done = job.i - 1, stage = job.stage.id, event = job.event.id }
end

function M.cancel()
  if not job then return false end
  gen = gen + 1                      -- (a window still in flight answers into nothing)
  job = nil
  return true
end

-- done(ok, matched, why, how). `how` is the ending in figures, for the page that has to colour and word it:
-- { kind = M.DONE / PARTIAL / NODATA / FAILED, windows, done, withData, shortM, event, stage }. `extra` is merged
-- into it, so each ending adds only the numbers it knows (the metres with no data, the windows that had any).
local function finish(ok, result, why, kind, extra)
  local j = job
  job = nil
  gen = gen + 1
  local how = nil
  if j then
    local withData = 0
    for _, w in ipairs(j.plan) do if w.complete then withData = withData + 1 end end
    how = { kind = kind or (ok and M.DONE or M.FAILED), windows = #j.plan,
            done = math.min((j.i or 1) - 1, #j.plan), withData = withData,
            event = j.event and j.event.id, stage = j.stage and j.stage.id }
    for k, v in pairs(extra or {}) do how[k] = v end
  end
  if j and j.done then
    local okCall, err = pcall(j.done, ok, result, why, how)
    if not okCall then log('E', 'earthRally', 'auto recce: the callback failed: ' .. tostring(err)) end
  end
  return ok
end

-- Write the matched file, once, whole. Through events.saveMatched so the read cache in events.lua is updated with
-- it: without that the menu and the runner would go on seeing "no matched line" until the next Reload.
local function write(j, m)
  local okWrite, err = pcall(events.saveMatched, j.event.id, j.stage.id, m)
  if not okWrite then
    return finish(false, nil, 'the matched line could not be written: ' .. tostring(err), M.FAILED)
  end
  log('I', 'earthRally', string.format(
    'auto recce: %s matched, %.1f km (map line %.1f km), %.0f m with no road in %d stretch(es), %d junction(s), %d window(s)',
    j.stage.id, m.lengthM / 1000, m.mapLineM / 1000, m.gapM, #m.gaps, #m.junctions, #j.plan))
  return finish(true, m, nil, M.DONE)
end

local function matchAndWrite(j)
  local covered, shortM, totalM = M.coverage(j.stage.line, j.plan, j.inner)
  if not covered then
    -- (never a partial line: BeamNG.Earth downloads nothing for a road-graph window, so the cells for this stretch
    --  are simply not on this computer yet -- driving near them, or a recce, is what fixes it)
    -- None of it covered at all is a different sentence and a different colour to a stretch of it: the player has
    -- simply never been over this ground, which is ordinary and not a fault (M.NODATA, a grey line in the menu).
    local whole = shortM >= (totalM or 0) - M.COVER_SAMPLE_M
    return finish(false, nil, string.format(
      '%.0f m of the stage has no map data on this computer yet: nothing written', shortM),
      whole and M.NODATA or M.PARTIAL, { shortM = shortM, totalM = totalM })
  end
  -- Covered by windows, but no roads came in them: nothing to match against. A line matched off an empty graph is
  -- the organisers' own line end to end with every point flagged, which is worse than writing nothing -- the stage
  -- would show amber ("recce recommended") instead of red, as though an auto recce had achieved something, and it
  -- would be driven with no notes anywhere. (In game, 2026-11-13: three complete windows, 0 nodes in each, 4106 m
  -- of a 4.1 km stage written as one gap.)
  if next(j.graph.nodes) == nil then
    return finish(false, nil, 'BeamNG.Earth gave no roads for this stage: nothing written', M.NODATA)
  end
  local m, why = M.match(j.stage, j.graph)
  if not m then return finish(false, nil, why or 'the stage could not be matched', M.FAILED) end
  -- the same thing one step later: roads arrived, but none of them near enough the organisers' line to be used
  if (m.gapM or 0) >= (m.lengthM or 0) - M.OUT_STEP_M then
    return finish(false, nil, string.format(
      'no part of the stage ran on a road (%.0f m of %.0f m is gap): nothing written', m.gapM or 0, m.lengthM or 0),
      M.NODATA)
  end
  return write(j, m)
end

-- One window's answer: its nodes into the accumulation as lat / lon, then the next window.
local function onWindow(myGen, token, i, r)
  -- (cancelled, superseded, or a second answer to a request already dealt with: a window asked for again after a
  --  rebase would otherwise be counted twice, and the plan would skip the one after it)
  if not job or myGen ~= gen or job.i ~= i or job.token ~= token then return end
  local j = job
  local w = j.plan[i]
  -- The origin may have moved while the window was being built, and then its x, y are in a frame that is gone and
  -- toGeo would read them in the new one. The window is thrown away and asked for again (it is named by lat / lon,
  -- so the same ground comes back), rather than converted with the wrong frame.
  local la, lo = earth.anchor()
  if earth.rebasing() or la ~= j.askLat or lo ~= j.askLon then
    j.tries = (j.tries or 0) + 1
    if j.tries <= M.RETRIES then
      log('I', 'earthRally', 'auto recce: the world\'s origin moved under window ' .. i .. ': asking again')
      return M.ask(i)
    end
    return finish(false, nil, 'the world\'s origin kept moving while the roads were read', M.FAILED)
  end
  j.tries = 0
  if type(r) ~= 'table' or r.error ~= nil or type(r.nodes) ~= 'table' then
    -- not fatal in itself: the coverage record decides, and an incomplete window means no file
    log('W', 'earthRally', string.format('auto recce: window %d of %d: %s', i, #j.plan,
      type(r) == 'table' and tostring(r.error) or 'no answer'))
    w.complete = false
  else
    local added = 0
    for name, node in pairs(r.nodes) do
      -- (a node seen in an earlier window is the same node -- the names are stable across windows and across
      --  anchors -- so it is not converted or stored twice, and the overlap adds no geometry)
      if j.graph.nodes[name] == nil then
        local x, y, z, radius = nodePos(node)
        if x ~= nil then
          local lat, lon, alt = earth.toGeo(x, y, z or 0)
          if lat ~= nil then
            -- (radius is the road's half width, kept but not yet used: the Python tool has no width at all, and
            --  what to do with it -- a line down the middle of a wide road, a note for a narrowing -- is 1.4.0's
            --  question, not this change's)
            j.graph.nodes[name] = { lat = lat, lon = lon, alt = alt, radius = radius }
            added = added + 1
          end
        end
      end
    end
    for _, e in ipairs(r.edges or {}) do
      local a, b = edgeEnds(e)
      if a ~= nil and b ~= nil and a ~= b then
        local k = (a < b) and (a .. '|' .. b) or (b .. '|' .. a)
        if not j.seen[k] then
          j.seen[k] = true
          j.graph.edges[#j.graph.edges + 1] = { a, b }
        end
      end
    end
    w.complete = (r.complete ~= false)
    log('I', 'earthRally', string.format('auto recce: window %d of %d: %d new node(s)%s', i, #j.plan, added,
      w.complete and '' or ', incomplete (map cells not on this computer)'))
  end
  j.i = i + 1
  if j.i > #j.plan then return matchAndWrite(j) end
  return M.ask(j.i)
end

-- Ask BeamNG.Earth for window i.
function M.ask(i)
  local j = job
  if not j then return false end
  local w = j.plan[i]
  j.i = i
  j.askLat, j.askLon = earth.anchor()
  j.token = (j.token or 0) + 1
  local myGen, token = gen, j.token
  local ok, why = earth.roadGraph(w.lat, w.lon, { radius = j.radius, cachedOnly = true },
    function(r) onWindow(myGen, token, i, r) end)
  if not ok then return finish(false, nil, why or 'BeamNG.Earth refused the road graph request', M.FAILED) end
  return true
end

-- Start the auto recce of one stage. done(ok, matched, why, how) is called once, when the file has been written or
-- when it has been decided that none will be; `how` is the ending in figures (see finish). Returns false and why if
-- it cannot even start -- including when one is already running: it is one window at a time. (The menu refuses a
-- second one before it reaches here, so that the refusal cannot disturb the record of the one already going; this
-- is the guard for every other caller.)
--
-- The menu's button is wired to this through main.lua's uiAction ('autoRecce' / 'autoRecceStop'). It is also
-- callable on its own -- `require('earthRally/autoRecce').start(event, stage, print)` in the console runs one.
function M.start(event, stage, done)
  if job then return false, 'an auto recce is already running' end
  if not earth.hasRoadGraph() then
    return false, 'this BeamNG.Earth cannot hand out its road graph: drive the stage\'s recce instead'
  end
  if type(stage) ~= 'table' or type(stage.line) ~= 'table' or #stage.line < 2 then
    return false, 'the stage has no map line'
  end
  -- (where the world's origin is has to be known before a window's game coordinates can be converted at all, and
  --  it is what tells us the origin moved under one)
  if select(1, earth.anchor()) == nil then
    return false, 'BeamNG.Earth has not placed the world yet: wait until it is loaded'
  end
  local plan, why, radius, inner = M.plan(stage.line, M.RADIUS_M)
  if not plan then return false, why end
  gen = gen + 1
  job = { event = event, stage = stage, plan = plan, radius = radius, inner = inner,
          graph = { nodes = {}, edges = {} }, seen = {}, i = 1, tries = 0, done = done }
  log('I', 'earthRally', string.format('auto recce: %s, %d window(s) of %.0f m', stage.id, #plan, radius))
  return M.ask(1)
end

------------------------------------------------------------------------------------------
-- What this module assumes about BeamNG.Earth's api.roadGraph, which is not merged (and, as of today, not written:
-- the server-side helper `Server.road_graph_data` exists on the addon-api-road-graph branch as an uncommitted
-- working-tree change, but there is no api.lua wrapper, no capability name and no docs/ADDONS.md entry -- the draft
-- in docs/upstream-roadgraph.md says as much itself). Every one of these is read in exactly one place, named here,
-- so that correcting it is a small edit rather than a rewrite:
--
--   * `api.has('roadGraph')` is the capability name          -> earthAdapter.hasRoadGraph
--   * `api.roadGraph(lat, lon, opts, callback)`, one window per call, the callback given one table
--                                                            -> earthAdapter.roadGraph
--   * opts = { radius = m, cachedOnly = true }                -> M.ask
--   * the answer carries nodes, edges, complete, error        -> onWindow
--   * a node is [x, y, z, radius] or { x =, y =, z =, radius = }, in the current anchor frame
--                                                            -> nodePos
--   * an edge names its two nodes first                       -> edgeEnds
--   * node names are stable across windows and anchors        -> onWindow (the whole stitch rests on this; it is
--     the one assumption that is actually verified upstream -- navgraph.short_ids hashes the Overture id, so the
--     same node keeps the same name in every graph)
--   * the radius cap is 2000 m                                -> M.MAX_RADIUS_M
--
-- If the shape turns out different, the auto recce is unavailable rather than wrong: hasRoadGraph answers false for
-- a missing call or a renamed capability, and a window whose rows cannot be read adds no nodes, which leaves the
-- stage uncovered, which writes nothing.
return M
