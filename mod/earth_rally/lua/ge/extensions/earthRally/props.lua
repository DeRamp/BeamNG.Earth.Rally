-- earthRally/props: the roadside of a stage's controls, from the game's own rally assets (art/shapes/race/rally/
-- rally_assets, in the game's common art: there on every level): the yellow warning boards before the time control
-- and the flying finish, the red boards at the time control, start, finish and stop, the start tree (its LED clock is
-- the game's own start clock: runner.lua feeds it), and at the controls where cars stop a gazebo with a table and a
-- chair.
--
-- A site is a control's place (lat / lon) and the driving direction there. Every object of a site is placed on its
-- own: walked `fwd` metres along the road from the control and set off the road's edge there, facing along the road
-- at that spot, so boards stand beside a winding road and not on a straight line through the trees:
--   - start and flying finish: along the stage line itself (site.path, from runner.lua);
--   - time control and stop: along the game's road map (BeamNG.Earth's roads round the car), from the road beside the
--     control best aligned with the driving direction (not merely the nearest: a side road at a junction);
--   - the road's half width from the road map where it has the road; heights from the road (the stage line's, the
--     road map's), the ground found by a ray near that height.
-- A site's props are put down when the car comes within SPAWN_M (where BeamNG.Earth has the ground and the road map
-- loaded), within NO_ROAD_SPAWN_M when nothing tells its height. A world shift moves none of them, so they are put
-- down again after one.
--
-- Placement as the game's own rallies (gameplay/missions/*/rallyStage/*/mainPrefab): the model's +Y along the
-- driving direction, on the right of the road, just off its edge.
local M = {}
-- (a compass bearing as a direction in game coordinates: junctions.lua's, as dressing.lua takes it; the same here
-- when it is not there)
local okJ, J = pcall(require, 'earthRally/junctions')
local bearingToDir = (okJ and type(J) == 'table' and J.bearingToDir) or function(deg)
  local h = math.rad(deg)
  return math.sin(h), math.cos(h)
end

local A = '/art/shapes/race/rally/rally_assets/'
M.SPAWN_M = 350
M.NO_ROAD_SPAWN_M = 80
M.SHAPES = {
  tcEntry = A .. 's_rally_signboard_time_control_entry.dae',
  tc = A .. 's_rally_signboard_time_control.dae',
  start = A .. 's_rally_signboard_start.dae',
  finishEntry = A .. 's_rally_signboard_finish_entry.dae',
  finish = A .. 's_rally_signboard_finish.dae',
  stop = A .. 's_rally_signboard_stop.dae',
  gazeboFrame = A .. 's_rally_gazebo_mod_frame_3x3.dae',
  gazeboCover = A .. 's_rally_gazebo_mod_cover_dkblue_3x3.dae',
  table = A .. 's_rally_fold_table_01.dae',
  chair = A .. 's_rally_fold_chair_01.dae',
  startTree = A .. 's_rally_start_tree.dae',
}

-- each kind of control: { shape, fwd (m along the road), out (m beyond the road's edge), yaw (degrees from the road's
-- way, + to the right), side (1 right, -1 left) }.
M.BOARD_OUT_M = -0.3        -- (a little inside the road's edge, as the boards stand on a rally road)
M.TENT_OUT_M = 1.5          -- the gazebo's centre (it is 3 m square: its near side at the road's edge)
M.FINISH_BOARD_OUT_M = 0.5  -- the flying finish's boards just outside the road (cars pass them at speed)
-- the start tree as the game's stages stand it (measured on its 8 stock stages): a metre or two past the start
-- position, 1 m off the road's right edge, turned ~25 degrees so its clock (on the model's -Y side) faces back
-- towards the car and the road. (-25 before 1.2.1: measured from the stock stages' matrices read the other way round,
-- so with the boards' rotation fixed the clock faced down the stage, away from the car, and the picture-in-picture
-- looked at its back: found at Maryhill Up, 2026-11-12.)
M.TREE_FWD_M, M.TREE_OUT_M, M.TREE_YAW = 1.5, 1.0, 25
M.DEFAULT_HALF_WIDTH_M = 3.0
M.SNAP_M = 30               -- a site this close to a road is on it ...
-- ... and this close when nothing was found at SNAP_M. A time control's own point is the organisers', dropped on a
-- map by hand, and can sit well off the road; with no road found, a site's props are set out along a straight line
-- from that point, so the whole row of boards stands off to one side of the road (Maryhill Up's ATC, the user,
-- 2026-11-13; the run's log said `no road on the map there: straight from the control`). The start and the flying
-- finish never have this trouble: they are set out along the stage line, which is on the road.
M.SNAP_FAR_M = 60
M.TURN_MAX_DEG = 60         -- walking the road map: at a junction, the road on that turns at most this much
-- A time control's or stop's props put down with no road map there (BeamNG.Earth loads the roads round the car after
-- it arrives: Black River-Camp's ATC, 1.6.2's issue #5, `0 placed by the road map`) are looked at again this often
-- while the car is within SPAWN_M, and put down again from the road map's road once it has one beside the control.
M.REDO_EVERY_S = 0.5
-- ... but not while the car is within REDO_HOLD_M of the control (the runner's check-in zones: CONTROL_RADIUS_M 12 m,
-- STOP_CONTROL_RADIUS_M 25 m -- the zone's point would move under a car stopped in it), nor when any of the new props
-- would stand within REDO_CLEAR_M of the car (a tent put down onto it); and given up after REDO_MAX_TRIES looks that
-- found no road (said once): a control the road map never covers is not looked at every half second for ever.
M.REDO_HOLD_M = 30
M.REDO_CLEAR_M = 5
M.REDO_MAX_TRIES = 240
local TENT = function(fwd)
  local o = M.TENT_OUT_M
  return {
    { 'gazeboFrame', fwd, o, 0 }, { 'gazeboCover', fwd, o, 0 },
    { 'table', fwd - 0.3, o - 0.6, 90 }, { 'chair', fwd - 0.3, o + 0.3, 90 },
  }
end
local function join(a, b) for _, x in ipairs(b) do a[#a + 1] = x end return a end
local B, F = M.BOARD_OUT_M, M.FINISH_BOARD_OUT_M
local function both(name, fwd, out)
  out = out or B
  return { { name, fwd, out, 0, 1 }, { name, fwd, out, 0, -1 } }
end
M.LAYOUTS = {
  atc = join(join(both('tcEntry', -50), both('tc', 0)), TENT(4)),
  start = join(join(both('start', 0), { { 'startTree', M.TREE_FWD_M, M.TREE_OUT_M, M.TREE_YAW, 1 } }), TENT(-6)),
  ff = join(both('finishEntry', -150, F), both('finish', 0, F)),
  stop = join(both('stop', 0), TENT(4)),
}

local sites = {}          -- { kind, lat, lon, z, dir = {x, y}, path, objs, failed }
local serial = 0
-- All of them in one group of the scene, found by its name: a Lua reload (Ctrl+L) forgets the objects this module put
-- down, so the next load takes the group away whole (M.sweep), and names stay unique across loads.
M.GROUP = 'earthRally_props'
local session = tostring(os.time())

local function group()
  local g = scenetree.findObject and scenetree.findObject(M.GROUP)
  if g then return g end
  local ok, made = pcall(function()
    local o = createObject('SimGroup')
    o.canSave = false
    o:registerObject(M.GROUP)
    scenetree.MissionGroup:addObject(o)
    return o
  end)
  return ok and made or nil
end

-- Take away whatever an earlier load of the mod left in the scene.
function M.sweep()
  local g = scenetree.findObject and scenetree.findObject(M.GROUP)
  if g then pcall(function() g:delete() end) end
end

-- A control's site. dir: the driving direction there (game coordinates, re-given after a world shift); z: its height
-- when known; path(fwd) -> { x, y, z, dx, dy } the point `fwd` m along the stage line from the site and the driving
-- direction there (start and flying finish), in game coordinates of the moment.
function M.setSite(kind, lat, lon, dir, z, path)
  for _, s in ipairs(sites) do
    if s.kind == kind then
      M.removeSite(s)
      s.lat, s.lon, s.dir, s.z, s.path, s.failed = lat, lon, dir, z, path, nil
      return s
    end
  end
  local s = { kind = kind, lat = lat, lon = lon, dir = dir, z = z, path = path }
  sites[#sites + 1] = s
  return s
end

function M.removeSite(s)
  for _, id in ipairs(s.objs or {}) do
    local o = scenetree.findObjectById(id)
    if o then o:delete() end
  end
  s.objs = nil
end

function M.clear()
  for _, s in ipairs(sites) do M.removeSite(s) end
  sites = {}
  M.clearDressing()
end

-- (a yaw-only rotation turning +Y to (dx, dy), as the game's quatFromDir(dir, up) makes it: its axes go in as the rows
-- of the matrix, so the turn's sign is the opposite of a textbook rotation about +Z. Mirrored, a board on a road
-- running north looked right and one on a road running east faced nearly backwards: test_props checks it against a
-- copy of the game's own math.)
local function yawQuat(dx, dy)
  local h = math.atan2(dx, dy)          -- clockwise from +Y
  return { 0, 0, math.sin(h / 2), math.cos(h / 2) }
end

-- The ground under (x, y) near the height z0: looked for a few metres above first, so a tree over the spot is not
-- taken for the ground; z0 when nothing is found near it. maxAbove (the stage dressing's): a hit more than this above
-- z0 is not the ground either -- a roof, a bus shelter -- and the first look starts that high only (a control's
-- boards, without it, as they always were: up to ~6 m above). The first look reaches up + 2 below z0 whatever up is
-- (a dressing object moved off its planned spot looks higher and lower: spawnItem scales maxAbove with the move).
-- Returns the height and whether ground was found (true without a ray to cast: nothing to tell).
local TIERS = { { 4, 12 }, { 8, 40 }, { 25, 80 } }
local function ground(x, y, z0, maxAbove)
  local ray = rawget(_G, 'castRayStatic')
  if not ray then return z0, true end
  for k, t in ipairs(TIERS) do
    local up = (maxAbove and k == 1) and maxAbove or t[1]
    local top = z0 + up
    local len = math.max(t[2], 2 * up + 2)
    local d = ray(vec3(x, y, top), vec3(0, 0, -1), len)
    if d and d < len then
      local z = top - d
      if math.abs(z - z0) <= up + 2 and not (maxAbove and z - z0 > maxAbove) then return z, true end
    end
  end
  return z0, false
end
M._ground = ground
M._yawQuat = yawQuat

-- (sy: the model stretched along its Y, a dressing tape longer than its model; nil or 1 at its own size. The scale is
-- about the model's origin, so a tape still starts where it is put and runs along its -Y, sy times as far)
local function makeObj(shape, x, y, z, q, sy)
  local o = createObject('TSStatic')
  o:setField('shapeName', 0, shape)
  if sy and math.abs(sy - 1) > 1e-6 then o:setField('scale', 0, string.format('1 %.4f 1', sy)) end
  -- (not solid: an object added at runtime only collides after the game rebuilds its collision, which BeamNG.Earth
  -- does at times of its own; one that turned solid part way through a run would be worse than none)
  o:setField('collisionType', 0, 'None')
  o:setField('decalType', 0, 'None')
  o:setField('dynamic', 0, 'true')      -- (as BeamNG.Earth's own: no redraw of the sun's cached shadows)
  o.canSave = false
  o:setPosRot(x, y, z, q[1], q[2], q[3], q[4])
  serial = serial + 1
  o:registerObject('earthRally_prop_' .. session .. '_' .. serial)
  local g = group()
  if g then g:addObject(o) else scenetree.MissionGroup:addObject(o) end
  return o:getID()
end

------------------------------------------------------------------------------------------ the road map

local function mapNodes()
  local mp = rawget(_G, 'map')
  if not (mp and mp.getMap) then return nil end
  local ok, m = pcall(mp.getMap)
  return ok and m and m.nodes or nil
end

-- The road map's nodes by grid cell (1.6.1's performance fix): roadAt, roadCovers and nearEdges looked at every node
-- of the map for each object, dozens of whole-map walks in one frame as a site went down -- the hitch on arriving
-- at a stretch of the stage. The cells only pick which nodes to look at: every test is still made on the node's own
-- position, so the answer is the one a whole-map walk gives. Built when first asked for, and again when the map is
-- another table, after onNavgraphReloaded or a world shift (M.mapChanged), or once it is IDX_MAX_AGE_S old (a node
-- moved in place, which nothing is known to do). A map of fewer than IDX_MIN_NODES nodes (BeamNG.Earth's navgraph
-- round the car: about 250-300 in the 1.6.1 baseline) is walked whole as before, in the same order: its walk costs
-- microseconds, and the index's lists would only add garbage.
local IDX_CELL_M = 64
local IDX_MAX_AGE_S = 10
local IDX_MIN_NODES = 2000
local clock = rawget(os, 'clockhp') or os.clock
local idx = nil      -- { nodes, at, small, cells = { [cell key] = { node name, ... } } }
local function cellKey(cx, cy) return (cx + 32768) * 65536 + (cy + 32768) end
local function nodeIndex(nodes)
  local now = clock()
  if idx and idx.nodes == nodes and now - idx.at <= IDX_MAX_AGE_S and now >= idx.at then return idx end
  local n = 0
  for _ in pairs(nodes) do
    n = n + 1
    if n >= IDX_MIN_NODES then break end
  end
  if n < IDX_MIN_NODES then
    idx = { nodes = nodes, at = now, small = true }
    return idx
  end
  local cells = {}
  for name, nd in pairs(nodes) do
    local p = nd.pos
    if p and p.x and p.y and p.x == p.x and p.y == p.y then      -- (NaN would be a NaN table key)
      local k = cellKey(math.floor(p.x / IDX_CELL_M), math.floor(p.y / IDX_CELL_M))
      local c = cells[k]
      if not c then c = {} cells[k] = c end
      c[#c + 1] = name
    end
  end
  idx = { nodes = nodes, at = now, cells = cells }
  return idx
end
-- (the names of the nodes to look at for a point (x, y) +- r, as `for name in candidates(...)`: on a small map
-- every node, in the map's own order; else those in the cells that (x, y) +- r touches, every node within r of it
-- among them)
local function candidates(nodes, x, y, r)
  local ix = nodeIndex(nodes)
  if ix.small then return next, nodes, nil end
  local cells, out = ix.cells, {}
  for cx = math.floor((x - r) / IDX_CELL_M), math.floor((x + r) / IDX_CELL_M) do
    for cy = math.floor((y - r) / IDX_CELL_M), math.floor((y + r) / IDX_CELL_M) do
      local c = cells[cellKey(cx, cy)]
      if c then for i = 1, #c do out[c[i]] = true end end
    end
  end
  return next, out, nil
end
M._IDX_MIN_NODES = IDX_MIN_NODES
-- The road map has changed under the index (main.lua's onNavgraphReloaded, M.reset after a world shift).
function M.mapChanged() idx = nil end

-- The road-map edge beside (x, y) in plan (heights are not trusted: the car may be far above or below the spot), the
-- one best aligned with dir (dx, dy) when given among those within SNAP_M: { a, b (node names, oriented along dir),
-- t, x, y, z, half, dx, dy, d }, or nil.
function M.roadAt(x, y, dir, snap)
  snap = snap or M.SNAP_M
  local nodes = mapNodes()
  if not nodes then return nil end
  local best, bestScore = nil, math.huge
  local r2 = (snap + 40) ^ 2
  local dl = dir and math.sqrt(dir.x * dir.x + dir.y * dir.y) or 0
  for na in candidates(nodes, x, y, snap + 40) do
    local a = nodes[na]
    local pa = a and a.pos
    if pa and (pa.x - x) ^ 2 + (pa.y - y) ^ 2 <= r2 and a.links then
      for nb in pairs(a.links) do
        local b = nodes[nb]
        local pb = b and b.pos
        if pb then
          local dx, dy = pb.x - pa.x, pb.y - pa.y
          local l2 = dx * dx + dy * dy
          if l2 > 1e-6 then
            local t = math.max(0, math.min(1, ((x - pa.x) * dx + (y - pa.y) * dy) / l2))
            local px, py = pa.x + dx * t, pa.y + dy * t
            local d = math.sqrt((px - x) ^ 2 + (py - y) ^ 2)
            if d <= snap then
              local l = math.sqrt(l2)
              local cos = dl > 0 and (dx * dir.x + dy * dir.y) / (l * dl) or 1
              -- (a road across the driving direction counts as 25 m further away)
              local score = d + (1 - math.abs(cos)) * 25
              if score < bestScore then
                bestScore = score
                local flip = cos < 0
                best = { a = flip and nb or na, b = flip and na or nb, t = flip and 1 - t or t, x = px, y = py,
                         z = (pa.z or 0) + ((pb.z or 0) - (pa.z or 0)) * t,
                         half = (a.radius or M.DEFAULT_HALF_WIDTH_M) * (1 - t) + (b.radius or M.DEFAULT_HALF_WIDTH_M) * t,
                         dx = (flip and -dx or dx) / l, dy = (flip and -dy or dy) / l, d = d }
              end
            end
          end
        end
      end
    end
  end
  return best
end

-- An edge (roadAt) turned to run the way that leads towards `toward` (or away from `away`), along the road: walked
-- ORIENT_M both ways, the end that comes nearer wins. A control's road often runs across the straight line to the
-- start, where the angle alone could not tell the way (review 2026-11-12). Returns the edge (a copy when turned).
M.ORIENT_M = 60
function M.orient(edge, toward, away)
  if not edge or not (toward or away) then return edge end
  local f, b = M.walkRoad(edge, M.ORIENT_M), M.walkRoad(edge, -M.ORIENT_M)
  local function d(p, q) return (p.x - q.x) ^ 2 + (p.y - q.y) ^ 2 end
  local turn
  if toward then turn = d(b, toward) < d(f, toward) else turn = d(f, away) < d(b, away) end
  if not turn then return edge end
  local e = {}
  for k, v in pairs(edge) do e[k] = v end
  e.a, e.b, e.t, e.dx, e.dy = edge.b, edge.a, 1 - (edge.t or 0), -edge.dx, -edge.dy
  return e
end

-- From a road-map edge (roadAt), the point `fwd` m along the road in the driving direction (back for fwd < 0): at a
-- junction the road that turns least, up to TURN_MAX_DEG; past the road map's end, straight on. Returns { x, y, z,
-- dx, dy (the driving direction there), half }.
function M.walkRoad(edge, fwd)
  local nodes = mapNodes()
  local back = fwd < 0
  -- walking forward: from the edge's point towards b; back: towards a (and the direction turned round at the end)
  local from, to = edge.a, edge.b
  if back then from, to = edge.b, edge.a end
  local left = math.abs(fwd)
  local px, py, pz = edge.x, edge.y, edge.z
  local hx, hy = edge.dx, edge.dy
  if back then hx, hy = -hx, -hy end
  local half = edge.half
  local cosMax = math.cos(math.rad(M.TURN_MAX_DEG))
  for _ = 1, 200 do
    local nt = nodes and nodes[to]
    if not (nt and nt.pos) then break end
    local tx, ty, tz = nt.pos.x, nt.pos.y, nt.pos.z or pz
    local seg = math.sqrt((tx - px) ^ 2 + (ty - py) ^ 2)
    if seg > 1e-6 then hx, hy = (tx - px) / seg, (ty - py) / seg end
    if seg >= left then
      local k = seg > 1e-6 and left / seg or 0
      px, py, pz = px + (tx - px) * k, py + (ty - py) * k, pz + (tz - pz) * k
      left = 0
      break
    end
    left = left - seg
    px, py, pz = tx, ty, tz
    half = nt.radius or half
    -- the next road from this node: the one turning least
    local nextName, bestCos = nil, cosMax
    for nn in pairs(nt.links or {}) do
      local q = nn ~= from and nodes[nn]
      if q and q.pos then
        local dx, dy = q.pos.x - tx, q.pos.y - ty
        local l = math.sqrt(dx * dx + dy * dy)
        if l > 1e-6 then
          local cos = (dx * hx + dy * hy) / l
          if cos > bestCos then nextName, bestCos = nn, cos end
        end
      end
    end
    if not nextName then break end
    from, to = to, nextName
  end
  if left > 0 then px, py = px + hx * left, py + hy * left end      -- (past the map's road: straight on)
  if back then hx, hy = -hx, -hy end
  return { x = px, y = py, z = pz, dx = hx, dy = hy, half = half or M.DEFAULT_HALF_WIDTH_M }
end

------------------------------------------------------------------------------------------ putting a site down

-- Where along the road an object `fwd` m from the site stands: { x, y, z (or nil), dx, dy, half, road (true when the
-- road map has the road there) }.
local function placeAlong(s, fwd)
  if s.path then
    local p = s.path(fwd)
    if p then
      local road = M.roadAt(p.x, p.y, { x = p.dx, y = p.dy })
      return { x = p.x, y = p.y, z = p.z or (road and road.z), dx = p.dx, dy = p.dy,
               half = road and road.half or M.DEFAULT_HALF_WIDTH_M, road = road ~= nil }
    end
  end
  if s.edge then
    local w = M.walkRoad(s.edge, fwd)
    w.road = true
    return w
  end
  -- (no road map: straight from the control -- from the auto recce's road point, along its road, when the matched
  -- file has one: s.onRoad)
  local d = s.onRoad or s.dir
  local l = math.sqrt(d.x * d.x + d.y * d.y)
  local fx, fy = d.x / l, d.y / l
  return { x = s.x0 + fx * fwd, y = s.y0 + fy * fwd, z = s.z, dx = fx, dy = fy, half = M.DEFAULT_HALF_WIDTH_M }
end

local function spawn(s, carZ)
  local layout = M.LAYOUTS[s.kind]
  if not layout then return end
  s.objs = {}
  local n, onRoad = 0, 0
  for _, it in ipairs(layout) do
    local at = placeAlong(s, it[2])
    local l = math.sqrt(at.dx * at.dx + at.dy * at.dy)
    if l < 1e-6 then at.dx, at.dy, l = 0, 1, 1 end
    local fx, fy = at.dx / l, at.dy / l
    local rx, ry = fy, -fx
    local out = (at.half + it[3]) * (it[5] or 1)
    local x, y = at.x + rx * out, at.y + ry * out
    local yaw = math.rad(it[4])
    local dx, dy = fx * math.cos(yaw) + rx * math.sin(yaw), fy * math.cos(yaw) + ry * math.sin(yaw)
    local z = ground(x, y, at.z or carZ)
    local ok, id = pcall(makeObj, M.SHAPES[it[1]], x, y, z, yawQuat(dx, dy))
    if ok then
      s.objs[#s.objs + 1] = id
      n = n + 1
      if at.road then onRoad = onRoad + 1 end
    else
      log('W', 'earthRally', 'a rally prop could not be put down (' .. tostring(id) .. ')')
      s.failed = true
      break
    end
  end
  local how = ''
  if s.path then
    local p = s.path(0)
    local r = p and M.roadAt(p.x, p.y, { x = p.dx, y = p.dy })
    how = string.format(', along the stage line (%s)', r and string.format('road map centre %.1f m off, heading %.0f deg',
      r.d, math.deg(math.atan2(p.dx, p.dy)) % 360) or 'no road map there')
  elseif s.edge then
    how = string.format(', road map %.1f m from the %s, heading %.0f deg', s.edge.d or 0,
      s.onRoad and "auto recce's road point" or 'control', math.deg(math.atan2(s.edge.dx, s.edge.dy)) % 360)
  elseif s.onRoad then
    how = string.format(", no road map there yet: along the auto recce's road (the control %.1f m off it)",
      s.road and s.road.offM or 0)
  else
    how = ', no road on the map there: straight from the control'
  end
  log('I', 'earthRally', string.format('props: %s put down (%d objects, %d placed by the road map%s)', s.kind, n, onRoad, how))
end

local updateDressing        -- (the stage dressing, below)

-- Every frame of a run: sites near enough the car put down (once). carPos in game coordinates; carAlong (optional):
-- the car's distance along the stage line, which the stage dressing is put down and taken away by.
-- (a control's road on the road map, aligned with the driving direction and turned the way that leads on: looked for
-- from (x, y) -- the control's point, or the auto recce's road point beside it -- further out when nothing is near:
-- a control's point can be well off the road)
-- With the auto recce's road point (s.onRoad: its road's way) only within SNAP_M of that point, aligned with its road:
-- the point is on the stage's road, and SNAP_FAR_M along the line to the start could take a neighbouring road
-- (review of #5); without a road map's road there the props stay along the recce's road.
local function controlEdge(s, x, y, toGame)
  local e
  if s.onRoad then e = M.roadAt(x, y, s.onRoad)
  else e = M.roadAt(x, y, s.dir) or M.roadAt(x, y, s.dir, M.SNAP_FAR_M) end
  if not e then return nil end
  local function at(p)
    if not p then return nil end
    local px, py = toGame(p.lat, p.lon, 0)
    return px and { x = px, y = py } or nil
  end
  return M.orient(e, at(s.toward), at(s.away))
end

-- (the auto recce's road point beside the control (s.road: { lat, lon, deg }, events.controlOnRoad) in game
-- coordinates now, and its road's way turned to the driving direction s.dir; nil without one)
local function roadPoint(s, toGame)
  local r = s.road
  if type(r) ~= 'table' or type(r.lat) ~= 'number' or type(r.lon) ~= 'number' then return nil end
  local x, y = toGame(r.lat, r.lon, 0)
  if not x then return nil end
  local dx, dy = s.dir.x, s.dir.y
  if type(r.deg) == 'number' then
    dx, dy = bearingToDir(r.deg)
    if dx * s.dir.x + dy * s.dir.y < 0 then dx, dy = -dx, -dy end
  end
  return x, y, { x = dx, y = dy }
end

-- (a site's props, were they put down from edge e, all further than REDO_CLEAR_M from the car)
local function clearOfCar(s, e, carPos)
  local keep = s.edge
  s.edge = e
  local ok = true
  for _, it in ipairs(M.LAYOUTS[s.kind] or {}) do
    local at = placeAlong(s, it[2])
    local l = math.sqrt(at.dx * at.dx + at.dy * at.dy)
    local fx, fy = l > 1e-6 and at.dx / l or 0, l > 1e-6 and at.dy / l or 1
    local side = it[5] or 1
    local off = (at.half or M.DEFAULT_HALF_WIDTH_M) + it[3]
    local x, y = at.x + fy * off * side, at.y - fx * off * side
    if (x - carPos.x) ^ 2 + (y - carPos.y) ^ 2 <= M.REDO_CLEAR_M ^ 2 then ok = false break end
  end
  s.edge = keep
  return ok
end

local redoAt = -math.huge
function M.update(carPos, toGame, carAlong)
  if not carPos then return end
  updateDressing(carPos, toGame, carAlong)
  local now = clock()
  local redo = now - redoAt >= M.REDO_EVERY_S or now < redoAt
  if redo then redoAt = now end
  for _, s in ipairs(sites) do
    if not s.objs and not s.failed then
      local x, y = toGame(s.lat, s.lon, 0)
      local d2 = x and (x - carPos.x) ^ 2 + (y - carPos.y) ^ 2
      if d2 and d2 <= M.SPAWN_M ^ 2 then
        s.x0, s.y0, s.onRoad, s.redoTries = x, y, nil, 0
        -- the road under the control, aligned with the driving direction (sites not on the stage line)
        s.edge = nil
        if not s.path then
          -- (from the auto recce's road point beside the control when the matched file has one: issue #5)
          local rx, ry, rdir = roadPoint(s, toGame)
          if rx then s.x0, s.y0, s.onRoad = rx, ry, rdir end
          s.edge = controlEdge(s, s.x0, s.y0, toGame)
        end
        -- nothing to tell the height (no stage line, no road map there): only once the car is close, its own height
        -- then near the ground's
        if s.path or s.edge or s.z or d2 <= M.NO_ROAD_SPAWN_M ^ 2 then spawn(s, carPos.z) end
      end
    elseif redo and s.objs and not s.failed and not s.path and not s.edge and s.x0
      and (s.redoTries or 0) < M.REDO_MAX_TRIES then
      -- (put down with no road map there: put down again from the road map's road once it has one beside the
      -- control -- issue #5: the road map comes in after the car arrives, and the props stood where they first went)
      local d2 = (s.x0 - carPos.x) ^ 2 + (s.y0 - carPos.y) ^ 2
      if d2 <= M.SPAWN_M ^ 2 and d2 > M.REDO_HOLD_M ^ 2 then
        local e = controlEdge(s, s.x0, s.y0, toGame)
        if e and (e.x - carPos.x) ^ 2 + (e.y - carPos.y) ^ 2 > M.REDO_HOLD_M ^ 2 and clearOfCar(s, e, carPos) then
          M.removeSite(s)
          s.edge = e
          log('I', 'earthRally', string.format('props: %s put down again: the road map came in after it went down',
            s.kind))
          spawn(s, carPos.z)
        elseif not e then
          s.redoTries = (s.redoTries or 0) + 1
          if s.redoTries >= M.REDO_MAX_TRIES then
            log('I', 'earthRally', string.format('props: %s left where it went down: no road map road beside it after '
              .. '%d looks', s.kind, s.redoTries))
          end
        end
      end
    end
  end
end

-- After a world shift: everything put down again where it belongs (directions re-given by the caller).
function M.reset()
  M.mapChanged()
  for _, s in ipairs(sites) do M.removeSite(s) s.edge, s.onRoad = nil, nil end
  M.resetDressing()
end

-- Where a site's boards stand on the road (game coordinates now: the road map's point beside the control), once its
-- props are down and the road map had the road; else nil (the caller uses the control's own spot).
function M.sitePoint(kind)
  for _, s in ipairs(sites) do
    if s.kind == kind and s.objs and #s.objs > 0 then
      if s.edge then return { x = s.edge.x, y = s.edge.y } end
      -- (no road map there yet: the auto recce's road point it was set out from)
      if s.onRoad then return { x = s.x0, y = s.y0 } end
    end
  end
end

-- A site is set for this kind (its props down or not yet).
function M.hasSite(kind)
  for _, s in ipairs(sites) do if s.kind == kind then return true end end
  return false
end

-- A site's props are down.
function M.placed(kind)
  for _, s in ipairs(sites) do if s.kind == kind and s.objs and #s.objs > 0 then return true end end
  return false
end

function M.count()
  local n = 0
  for _, s in ipairs(sites) do n = n + #(s.objs or {}) end
  return n
end

------------------------------------------------------------------------------------------ the stage dressing

-- The tape, boards, posts and spectator areas along a stage (1.4.0): sites worked out up front by dressing.plan,
-- every object's place and heading already decided (a tape across a side road runs square to that road, which the
-- walk along the stage above cannot say). Unlike a control's site, a dressing site is put down by where the car is
-- ALONG the stage line (DRESS_AHEAD_M before the first of its objects) and taken away again once the car is
-- DRESS_BEHIND_M past the last: a 25 km stage has tape at dozens of junctions, and all of it standing at once by the
-- finish would be hundreds of objects. With no distance along given (the car not on the stage yet), by the straight
-- distance to the site's first object, as the controls, and nothing is taken away.
--
-- A world shift (props.reset) moves the game's coordinates under the objects, so a site keeps its objects as lat /
-- lon, not as x / y: each object's spot, and a second spot 10 m along its heading (so its heading survives whatever
-- the shift does), turned back into game coordinates (toGame) each time it is put down. Distances along the line do
-- not change with a shift (runner.lua's line follows it), so the window needs nothing.
M.DRESS_AHEAD_M = M.SPAWN_M
M.DRESS_BEHIND_M = 600
M.DRESS_MAX_OBJS = 64        -- every dressing site's budget, whatever it asks for
-- (objects put down a frame, a site carried on into the next: a whole window at once, after a shift, is a hitch, and
-- one spectator area alone is 64 objects)
M.DRESS_OBJS_PER_UPDATE = 24
-- ... and no more objects in a frame once this much of it has gone on them (1.6.1: each object casts rays and makes
-- a scene object, whose cost the count alone does not hold down). The first object of a frame always goes down.
M.DRESS_SPAWN_MS = 3
M.DRESS_GROUND_ABOVE_M = 2   -- a dressing object's ground: a hit at most this above its planned height (not a roof)
-- ... and, for an object moved off its planned spot (the edge shift, the push, the slide below), this much more for
-- each metre it moved (review round 4: pushed 6 m up a bank, its ground is well above the planned height); one moved
-- at least DRESS_GROUND_MOVED_M with no ground found within that is left out, not stood at the planned height
M.DRESS_GROUND_PER_M = 0.7
M.DRESS_GROUND_MOVED_M = 0.5
-- An object set from the road's edge (dressing.lua's edged) moved to the same distance from the edge of the road the
-- game has there as it was planned from the edge it assumed: the road map's road looked for at the object's planned
-- road centre, aligned with the road, once per DRESS_EDGE_REUSE_M of a site, and the object moved by that road's half
-- width less the planned one AND by how far the stage line runs off that road's centre (1.6.0's note 6: until then
-- only the width was taken, so where the auto-recce line ran off the road's middle towards a post, the post stood on
-- the tarmac); the move held to DRESS_EDGE_SHIFT_MIN_M .. DRESS_EDGE_SHIFT_MAX_M.
M.DRESS_EDGE_SNAP_M = 8
M.DRESS_EDGE_REUSE_M = 20
M.DRESS_EDGE_SHIFT_MIN_M, M.DRESS_EDGE_SHIFT_MAX_M = -2, 6
-- ... and not moved at all unless the road found is the stage's own: its centre line within DRESS_EDGE_NEAR_M of the
-- planned stage-line point the object was set from (its eo back along the way out), and running at most
-- DRESS_EDGE_MAX_DEG off the object's road. A Y-shaped hairpin's other branch, a road crossing it, says nothing of
-- the stage's width (the user, 2026-11-14: hay bales in the street); the angle alone could not tell a branch a few
-- degrees off from the stage road, and at a tight apex the map's coarse segment runs well off the tangent (review
-- round 2). (2 m and 45 degrees until note 6: at Weaver Bend's bend the road map's chord lay further off the line
-- than that, nothing was found, and the post stayed where the stage's one width put it.) A tape of unknown width
-- (dressing.lua's refit) reads its side road by the angle, within DRESS_EDGE_SNAP_M, else takes DEFAULT_HALF_WIDTH_M.
M.DRESS_EDGE_NEAR_M = 4
M.DRESS_EDGE_MAX_DEG = 60
-- Then every object set from the edge (but those flagged offRoad, below) held clear of every road the road map has
-- there, whichever way it runs (the stage's own, a side road, a hairpin's other leg): nearer none of their centre
-- lines than the road's half width + DRESS_CLEAR_MARGIN_M + the object's own reach (dressing.FOOT). Where one is
-- not, its whole group (dressing.lua's grp: a post's gazebo, table, chair and flag; a roadside marshal's table,
-- chair and flag; the spectators' camp; the spectators' bales; else the object alone) is pushed in DRESS_PUSH_STEP_M
-- steps up to DRESS_PUSH_MAX_M until all of it is clear: away from the nearest point of the road that covers it
-- first (review round 4: a road ending under it, or running across, is not cleared by going further out), then
-- straight out. Where no push clears it, the group is slid DRESS_SLIDES_M along the stage (each tried with the
-- pushes again), and left out (said once in the log, a warning) where none of that clears it (the user,
-- 2026-11-15: a marshal "should be OFF the road"). The roads looked at: those within DRESS_PUSH_LOOK_M of the
-- group's objects.
M.DRESS_CLEAR_MARGIN_M = 0.3
M.DRESS_PUSH_STEP_M, M.DRESS_PUSH_MAX_M = 0.5, 6
M.DRESS_SLIDES_M = { 5, -5, 10, -10, 15, -15 }
M.DRESS_PUSH_LOOK_M = 40
-- An object flagged off the road (dressing.lua: the spectators' tape and fence, laid in runs, so not pushed one by
-- one) left out where the road map has any road, whichever way it runs, whose surface covers its spot: nearer its
-- centre line than its half width plus this (a Y-hairpin's branch the plan never knew of). No road map there: put
-- down.
M.DRESS_OFFROAD_MARGIN_M = 0.5
-- A tape stretched along its length by at most this; beyond it, two overlapping pieces (dressing.TAPE_SY_MAX)
M.DRESS_TAPE_SY_MAX, M.DRESS_TAPE_OVERLAP_M = 1.25, 0.5
-- A tape of unknown width re-centred on the side road the road map has there, when that road's centre line is within
-- this of the planned middle (1.6.0's note 8: off-centre tapes, past one edge and short of the other). Its side road
-- is one running at most DRESS_TAPE_MAX_DEG off square to the tape (the 45 the edge shift used until note 6: a
-- wider window there could take the stage's own road at a fork for the side road)
M.DRESS_TAPE_CENTRE_M = 2
M.DRESS_TAPE_MAX_DEG = 45
-- A tape laid parallel with the stage at an acute junction (dressing.TAPE_PARALLEL_DEG, refit.sin: issue #9) crosses
-- its side road at that angle, 90 - its degrees off square: the side road looked for up to DRESS_TAPE_SLACK_DEG
-- beyond that, and never more than DRESS_TAPE_OBLIQUE_MAX_DEG off square (the stage road, running along the tape, is
-- 90 off); the centring window and the length taken along the tape, over the sine of the angle it crosses at. (75:
-- 90 less dressing.TAPE_PARALLEL_MIN_DEG, the shallowest angle the plan lays a parallel tape at; 80 until its review)
M.DRESS_TAPE_SLACK_DEG = 15
M.DRESS_TAPE_OBLIQUE_MAX_DEG = 75
local HEAD_M = 10

-- { kind, along, from, to, name, key, objs (ids, when down or going down), at (the next item to put down),
--   items = { { shape, lat, lon, h, hlat, hlon, [nlat, nlon, eo, eh] } or the same in x / y } }
local dress = {}

local function removeDress(s)
  for _, id in ipairs(s.objs or {}) do
    local o = scenetree.findObjectById(id)
    if o then o:delete() end
  end
  s.objs, s.at, s.probe, s.push = nil, nil, nil, nil
end

-- A shape the game has: looked for once per shape (FS:fileExists, the .dae or the .cdae the game makes of it), one
-- warning naming a missing one, and its objects left out. Without FS (the tests) every shape is taken as there.
local shapeHas = {}
local function shapeOk(shape)
  local h = shapeHas[shape]
  if h ~= nil then return h end
  h = true
  local fs = rawget(_G, 'FS')
  if type(shape) ~= 'string' then h = false
  elseif fs and fs.fileExists then
    local ok, a = pcall(fs.fileExists, fs, shape)
    local okC, c = pcall(fs.fileExists, fs, (shape:gsub('%.dae$', '.cdae')))
    h = (ok and a == true) or (okC and c == true) or not (ok or okC)
  end
  shapeHas[shape] = h
  if not h then log('W', 'earthRally', 'stage dressing: the shape ' .. tostring(shape) .. ' is not in the game: left out') end
  return h
end
M._shapeHas = shapeHas

-- A dressing site's key: its kind and where it is along the line, to the metre: two sites at one key are one, and
-- the second is not put down twice.
local function dressKey(kind, along) return tostring(kind) .. '@' .. tostring(math.floor((along or 0) + 0.5)) end
M._dressKey = dressKey

-- (one of dressing.plan's sites as kept here: its objects as lat / lon, or nil when none could be kept; lost counts
-- the objects toGeo could not turn into lat / lon, which the caller says in the log)
local function keepDress(site, toGeo, lost)
  local items = {}
  for _, o in ipairs(site.objects or {}) do
    if #items >= M.DRESS_MAX_OBJS then break end
    local hx, hy = o.x + (o.dx or 0) * HEAD_M, o.y + (o.dy or 1) * HEAD_M
    local edge = type(o.ex) == 'number' and type(o.eo) == 'number' and type(o.eh) == 'number'
    -- (the way out from the road kept as a second spot, as the heading is: whatever a shift does, it survives)
    local nx, ny = edge and o.x + o.ex * HEAD_M, edge and o.y + o.ey * HEAD_M
    local it = { shape = o.shape, eo = edge and o.eo or nil, eh = edge and o.eh or nil, sy = o.sy, refit = o.refit,
                 maxLen = o.maxLen, offRoad = o.offRoad, foot = o.foot, grp = o.grp }
    if toGeo then
      local la, lo, h = toGeo(o.x, o.y, o.z or 0)
      local hla, hlo = toGeo(hx, hy, o.z or 0)
      local nla, nlo
      if edge then nla, nlo = toGeo(nx, ny, o.z or 0) end
      if la and hla then
        it.lat, it.lon, it.h, it.hlat, it.hlon = la, lo, type(h) == 'number' and o.z and h or nil, hla, hlo
        if not nla then it.eo, it.eh = nil, nil end
        it.nlat, it.nlon = nla, nlo
      end
    else
      it.x, it.y, it.z, it.hx, it.hy, it.nx, it.ny = o.x, o.y, o.z, hx, hy, nx, ny
    end
    if it.lat or it.x then items[#items + 1] = it
    elseif lost then lost.n = lost.n + 1 end
  end
  if #items == 0 then return nil end
  return { kind = site.kind, along = site.along, from = site.from or site.along, to = site.to or site.along,
           name = site.name, items = items, key = dressKey(site.kind, site.along) }
end

local function sayLost(lost, how)
  if lost.n > 0 then
    log('W', 'earthRally', string.format('stage dressing: %d object(s) %s left out: no lat / lon for their place',
      lost.n, how))
  end
end

-- The stage's dressing (dressing.plan's sites, in game coordinates of the moment), replacing any there was. toGeo
-- (x, y, z) -> lat, lon, h: earthAdapter.toGeo. Without one (the tests), the game coordinates are kept as they are
-- and a world shift is not followed. A site whose key (kind and along) is already there is left out (one plan of the
-- same junction twice).
function M.setDressing(list, toGeo)
  M.clearDressing()
  local have, lost = {}, { n = 0 }
  for _, site in ipairs(list or {}) do
    local k = dressKey(site.kind, site.along)
    if not have[k] then
      local d = keepDress(site, toGeo, lost)
      if d then dress[#dress + 1] = d have[k] = true end
    end
  end
  sayLost(lost, 'of the stage')
  return #dress
end

-- The dressing sites kept (down or not), by kind: { [kind] = n }, and their number.
function M.dressingSites()
  local by, n = {}, 0
  for _, s in ipairs(dress) do by[s.kind] = (by[s.kind] or 0) + 1 n = n + 1 end
  return by, n
end

-- (after a world shift: taken away, put down again by the next update from their lat / lon)
function M.resetDressing()
  for _, s in ipairs(dress) do removeDress(s) end
end

function M.clearDressing()
  for _, s in ipairs(dress) do removeDress(s) end
  dress = {}
end

-- (an item's spot and heading in game coordinates now)
local function itemNow(it, toGame)
  if it.x then return it.x, it.y, it.z, it.hx, it.hy end
  local x, y, z = toGame(it.lat, it.lon, it.h or 0)
  local hx, hy = toGame(it.hlat, it.hlon, it.h or 0)
  if not (x and hx) then return nil end
  return x, y, it.h and z or nil, hx, hy
end

-- (the road map's road at (x, y) running the way (dx, dy) (a unit direction, either sense), within snap (default
-- DRESS_EDGE_SNAP_M) and DRESS_EDGE_MAX_DEG of it; nil when there is none, or the nearest runs another way)
local function alignedRoad(x, y, dx, dy, snap, maxDeg)
  local r = M.roadAt(x, y, { x = dx, y = dy }, snap or M.DRESS_EDGE_SNAP_M)
  if not (r and r.dx and r.dy) then return nil end
  if math.abs(r.dx * dx + r.dy * dy) < math.cos(math.rad(maxDeg or M.DRESS_EDGE_MAX_DEG)) then return nil end
  return r
end
M._alignedRoad = alignedRoad

-- Any road-map road whose surface covers (x, y): nearer its centre line than its half width (there) + margin,
-- whichever way it runs. Returns that edge's distance and half width, or nil (no road there, or no road map).
function M.roadCovers(x, y, margin)
  local nodes = mapNodes()
  if not nodes then return nil end
  margin = margin or 0
  for na in candidates(nodes, x, y, 250) do
    local a = nodes[na]
    local pa = a and a.pos
    if pa and a.links and (pa.x - x) ^ 2 + (pa.y - y) ^ 2 <= 250 ^ 2 then
      for nb in pairs(a.links) do
        local b = nodes[nb]
        local pb = b and b.pos
        if pb then
          local dx, dy = pb.x - pa.x, pb.y - pa.y
          local l2 = dx * dx + dy * dy
          local t = l2 > 1e-6 and math.max(0, math.min(1, ((x - pa.x) * dx + (y - pa.y) * dy) / l2)) or 0
          local d = math.sqrt((pa.x + dx * t - x) ^ 2 + (pa.y + dy * t - y) ^ 2)
          local h = (a.radius or M.DEFAULT_HALF_WIDTH_M) * (1 - t) + (b.radius or M.DEFAULT_HALF_WIDTH_M) * t
          if d < h + margin then return d, h end
        end
      end
    end
  end
  return nil
end

-- (a tape across a side road of unknown width fitted to the road there: its middle kept, the side road -- square to
-- the tape -- looked for on the road map, else DEFAULT_HALF_WIDTH_M, and the shortest model reaching refit.past past
-- each edge, else the longest stretched -- by at most DRESS_TAPE_SY_MAX, beyond that two overlapping pieces from the
-- two ends. Never reaching further from the planned middle than the plan's maxLen / 2 either way, the longest there
-- that clears the stage's road (dressing.lua's solveJunction): at a fork a wider side road than planned would
-- otherwise take the tape onto the stage. Its origin is its end at +Y (the tape runs along -Y). The plan gives the
-- WHOLE tape as one object (its length rf.len), so it is refit once about its true middle and split into pieces here.
-- Its middle is moved onto the side road's centre line -- where the tape's line crosses it -- when that is within
-- DRESS_TAPE_CENTRE_M along the tape (1.6.0's note 8); then only the end that the move takes beyond the plan's
-- maxLen is cut back to it (review round 4: until then the cap was shortened by twice the move, both ends). Returns
-- a list of pieces { x, y, shape, sy })
local function refitTape(it, x, y, dx, dy)
  local rf = it.refit
  local l = math.sqrt(dx * dx + dy * dy)
  if l < 1e-9 or type(rf.models) ~= 'table' or #rf.models == 0 then return { { x, y, it.shape, it.sy } } end
  dx, dy = dx / l, dy / l
  local cx, cy = x - dx * rf.len / 2, y - dy * rf.len / 2
  -- (a parallel tape: the sine of the angle it crosses its side road at, as planned; 1 for a square one)
  local sin0 = (type(rf.sin) == 'number' and rf.sin > 0 and rf.sin < 1) and rf.sin or nil
  local maxDeg = M.DRESS_TAPE_MAX_DEG
  if sin0 then
    maxDeg = math.min(M.DRESS_TAPE_OBLIQUE_MAX_DEG, math.deg(math.acos(sin0)) + M.DRESS_TAPE_SLACK_DEG)
  end
  local r = alignedRoad(cx, cy, -dy, dx, nil, maxDeg)
  local h = (r and type(r.half) == 'number' and r.half > 0) and r.half or M.DEFAULT_HALF_WIDTH_M
  local sinA = sin0 or 1
  -- (positions along the tape from the planned middle: the plan allows -A .. A)
  local A = type(it.maxLen) == 'number' and it.maxLen > 0 and it.maxLen / 2 or math.huge
  local s = 0
  if r and r.x and r.y and r.dx and r.dy then
    -- (the side road's line through r, its normal (r.dy, -r.dx): where the tape's line c + s d meets it)
    local nrx, nry = r.dy, -r.dx
    local dn = dx * nrx + dy * nry
    if sin0 then sinA = math.max(math.cos(math.rad(M.DRESS_TAPE_OBLIQUE_MAX_DEG)), math.abs(dn)) end
    if math.abs(dn) > 1e-6 then
      local t = ((r.x - cx) * nrx + (r.y - cy) * nry) / dn
      if math.abs(t) <= M.DRESS_TAPE_CENTRE_M / sinA + 1e-9 then s = t end
    end
  end
  local want = 2 * h / sinA + 2 * (rf.past or 0)
  local lo, hi = math.max(-A, s - want / 2), math.min(A, s + want / 2)
  local len = hi - lo
  local function piece(top, sy, shape) return { cx + dx * top, cy + dy * top, shape, sy } end
  -- (the shortest model covering lo .. hi that fits in -A .. A: lengthened at whichever end has room)
  for _, m in ipairs(rf.models) do
    if m[1] >= len - 1e-9 and m[1] <= 2 * A + 1e-9 then
      local a0 = math.max(-A, math.min(A - m[1], (lo + hi) / 2 - m[1] / 2))
      return { piece(a0 + m[1], 1, m[2]) }
    end
  end
  -- (else the longest model no longer than len, stretched to it: the smallest when none is)
  local top = rf.models[1]
  for _, m in ipairs(rf.models) do if m[1] <= len + 1e-9 and m[1] >= top[1] then top = m end end
  local most = 2 * top[1] * M.DRESS_TAPE_SY_MAX - M.DRESS_TAPE_OVERLAP_M
  if len > most then
    local mid = (lo + hi) / 2
    lo, hi, len = mid - most / 2, mid + most / 2, most
  end
  if len / top[1] <= M.DRESS_TAPE_SY_MAX + 1e-9 then return { piece(hi, len / top[1], top[2]) } end
  local p = math.min(top[1] * M.DRESS_TAPE_SY_MAX, math.max(top[1], (len + M.DRESS_TAPE_OVERLAP_M) / 2))
  return { piece(hi, p / top[1], top[2]), piece(lo + p, p / top[1], top[2]) }
end

-- (the move out for an object set from the road's edge, at (x, y) with the way out (nx, ny), to stand as far from the
-- edge of the road map's road as it was planned from the assumed one: that road's half width less the planned one,
-- less how far the planned stage-line point lies off that road's centre towards the object, over how square the way
-- out is to that road -- but never less than the width alone moves it; 0 where the road map has no road there. One look serves a site's objects on the same side
-- within DRESS_EDGE_REUSE_M of it -- a spectator area is 64 objects -- the stage line's offset from the road's centre
-- kept, not the road's line, which bends away on a bend)
local function edgeShift(s, it, x, y, nx, ny)
  local cx, cy = x - nx * it.eo, y - ny * it.eo
  local p = s.probe
  if not (p and (p.x - cx) ^ 2 + (p.y - cy) ^ 2 <= M.DRESS_EDGE_REUSE_M ^ 2 and p.nx * nx + p.ny * ny > 0.5) then
    p = { x = cx, y = cy, nx = nx, ny = ny }
    -- (the stage's own road: found within DRESS_EDGE_NEAR_M of the planned stage-line point)
    local r = alignedRoad(cx, cy, -ny, nx, M.DRESS_EDGE_NEAR_M)
    if r and type(r.half) == 'number' and r.half > 0 then
      -- (the road's normal on the object's side; the stage-line point's distance from its centre that way)
      local px, py = r.dy, -r.dx
      if px * nx + py * ny < 0 then px, py = -px, -py end
      p.half, p.cos = r.half, px * nx + py * ny
      p.off = (cx - r.x) * px + (cy - r.y) * py
    end
    s.probe = p
  end
  if not p.half or p.cos < 1e-3 then return 0 end
  local want = p.half + (it.eo - it.eh)
  -- (the line's offset taken only to move an object further out, never in: on a bend the road map's chord runs
  -- inside the curve the road and the line follow, so an object on the outside would be pulled in by the chord's
  -- sag -- review round 4. The width alone, as before note 6, is the least move)
  local shift = math.max(p.half - it.eh, (want - p.off) / p.cos - it.eo)
  return math.max(M.DRESS_EDGE_SHIFT_MIN_M, math.min(M.DRESS_EDGE_SHIFT_MAX_M, shift))
end

-- (the road map's roads near (x, y): every edge whose centre line comes within `within` of it, as
-- { ax, ay, dx, dy, l2, ha, hb }; nil without a road map)
local function nearEdges(x, y, within)
  local nodes = mapNodes()
  if not nodes then return nil end
  local out = {}
  for na in candidates(nodes, x, y, 250) do
    local a = nodes[na]
    local pa = a and a.pos
    if pa and a.links and (pa.x - x) ^ 2 + (pa.y - y) ^ 2 <= 250 ^ 2 then
      for nb in pairs(a.links) do
        local b = nodes[nb]
        local pb = b and b.pos
        if pb then
          local dx, dy = pb.x - pa.x, pb.y - pa.y
          local l2 = dx * dx + dy * dy
          local t = l2 > 1e-6 and math.max(0, math.min(1, ((x - pa.x) * dx + (y - pa.y) * dy) / l2)) or 0
          if (pa.x + dx * t - x) ^ 2 + (pa.y + dy * t - y) ^ 2 <= within * within then
            out[#out + 1] = { pa.x, pa.y, dx, dy, l2, a.radius or M.DEFAULT_HALF_WIDTH_M,
                              b.radius or M.DEFAULT_HALF_WIDTH_M }
          end
        end
      end
    end
  end
  return out
end
-- (whether any of those roads' surface, plus margin, covers (x, y): how deep the deepest does (its reach less the
-- distance) and its centre line's nearest point to (x, y); nil when none does)
local function covered(edges, x, y, margin)
  local deep, bx, by = nil
  for _, e in ipairs(edges) do
    local t = e[5] > 1e-6 and math.max(0, math.min(1, ((x - e[1]) * e[3] + (y - e[2]) * e[4]) / e[5])) or 0
    local px, py = e[1] + e[3] * t, e[2] + e[4] * t
    local d = math.sqrt((px - x) ^ 2 + (py - y) ^ 2)
    local reach = e[6] * (1 - t) + e[7] * t + margin
    if d < reach and (not deep or reach - d > deep) then deep, bx, by = reach - d, px, py end
  end
  return deep, bx, by
end
M._nearEdges, M._covered = nearEdges, covered

-- (an object's place now: x, y, z, its heading dx, dy, and -- set from the road's edge -- its way out nx, ny and the
-- edge shift already made)
local function placeOf(s, it, toGame)
  local x, y, z, hx, hy = itemNow(it, toGame)
  if not x then return nil end
  local dx, dy = hx - x, hy - y
  if dx * dx + dy * dy < 1e-9 then dx, dy = 0, 1 end
  local nx, ny
  if it.eo then
    if it.nx then nx, ny = it.nx - it.x, it.ny - it.y
    else
      local ex, ey = toGame(it.nlat, it.nlon, it.h or 0)
      if ex then nx, ny = ex - x, ey - y end
    end
    local l = nx and math.sqrt(nx * nx + ny * ny) or 0
    if l > 1e-6 then
      nx, ny = nx / l, ny / l
      local sh = edgeShift(s, it, x, y, nx, ny)
      x, y = x + nx * sh, y + ny * sh
    else
      nx, ny = nil, nil
    end
  end
  return x, y, z, dx, dy, nx, ny
end

-- (how far an object's group moves to be clear of every road there: { x, y }, (0, 0) when it already is, or without
-- a road map; false when nothing clears it. Pushed DRESS_PUSH_STEP_M at a time up to DRESS_PUSH_MAX_M: first away
-- from the nearest point of the road covering it most (the centre line's; straight out when that is right under
-- it), then straight out (nx, ny); where neither clears it, slid DRESS_SLIDES_M along the stage first, each slide
-- with the pushes again. The whole group by one move, every object of it checked. Worked out once per group, at its
-- first object down)
local pushSaid = {}
local function groupPush(s, it, toGame)
  s.push = s.push or {}
  local key = it.grp or it
  if s.push[key] ~= nil then return s.push[key] end
  local members = {}
  local cx, cy, reach = 0, 0, 0
  for _, o in ipairs(s.items) do
    if o == it or (it.grp and o.grp == it.grp and not o.offRoad) then
      local x, y, _, _, _, nx, ny = placeOf(s, o, toGame)
      if x and nx then
        members[#members + 1] = { x, y, nx, ny, M.DRESS_CLEAR_MARGIN_M + (o.foot or 0) }
        cx, cy = cx + x, cy + y
      end
    end
  end
  local push = { 0, 0 }
  if #members == 0 then s.push[key] = push return push end
  cx, cy = cx / #members, cy / #members
  for _, m in ipairs(members) do reach = math.max(reach, math.sqrt((m[1] - cx) ^ 2 + (m[2] - cy) ^ 2)) end
  local slideMax = 0
  for _, d in ipairs(M.DRESS_SLIDES_M) do slideMax = math.max(slideMax, math.abs(d)) end
  local edges = nearEdges(cx, cy, M.DRESS_PUSH_LOOK_M + reach + slideMax)
  if edges and #edges > 0 then
    local m1 = members[1]
    local nx, ny = m1[3], m1[4]
    local tx, ty = -ny, nx
    -- (the deepest cover of the group moved by (ox, oy): how deep, and the road's nearest point to that object)
    local function worst(ox, oy)
      local deep, wx, wy, px, py = nil
      for _, m in ipairs(members) do
        local x, y = m[1] + ox, m[2] + oy
        local dd, qx, qy = covered(edges, x, y, m[5])
        if dd and (not deep or dd > deep) then deep, wx, wy, px, py = dd, x, y, qx, qy end
      end
      return deep, wx, wy, px, py
    end
    local steps = math.floor(M.DRESS_PUSH_MAX_M / M.DRESS_PUSH_STEP_M + 1e-9)
    local function tryFrom(ox, oy)
      local deep, wx, wy, px, py = worst(ox, oy)
      if not deep then return { ox, oy } end
      local dirs = {}
      local ax, ay = wx - px, wy - py
      local al = math.sqrt(ax * ax + ay * ay)
      if al > 0.05 then dirs[#dirs + 1] = { ax / al, ay / al } end
      if not dirs[1] or dirs[1][1] * nx + dirs[1][2] * ny < 0.985 then dirs[#dirs + 1] = { nx, ny } end
      for _, dv in ipairs(dirs) do
        for k = 1, steps do
          local p = k * M.DRESS_PUSH_STEP_M
          local qx, qy = ox + dv[1] * p, oy + dv[2] * p
          if not worst(qx, qy) then return { qx, qy } end
        end
      end
      return nil
    end
    push = tryFrom(0, 0)
    for _, d in ipairs(M.DRESS_SLIDES_M) do
      if push then break end
      push = tryFrom(tx * d, ty * d)
    end
    if not push then
      push = false
      local said = string.format('%s/%s', tostring(s.key), tostring(it.grp or it.shape))
      if not pushSaid[said] then
        pushSaid[said] = true
        log('W', 'earthRally', string.format('stage dressing: the %s at %.0f m (%s) left out: on the road, and %.1f m'
          .. ' out or %.0f m along does not clear it', tostring(s.kind), s.along or 0, tostring(it.grp or it.shape),
          M.DRESS_PUSH_MAX_M, slideMax))
      end
    end
  end
  s.push[key] = push
  return push
end

-- One object of a dressing site put down (or left out: a shape the game has not, a place with no game position, a
-- group on a road it cannot be pushed off). Returns false when the game would not make it.
local function spawnItem(s, it, toGame, carZ)
  local x, y, z, dx, dy, nx, ny = placeOf(s, it, toGame)
  if not x then return true end
  local pieces = it.refit and refitTape(it, x, y, dx, dy) or { { x, y, it.shape, it.sy } }
  if not shapeOk(pieces[1][3]) then return true end
  -- (set from the edge: pushed out with its group until clear of every road there, or left out)
  if nx and not it.offRoad then
    local p = groupPush(s, it, toGame)
    if not p then return true end
    x, y = x + p[1], y + p[2]
    pieces[1][1], pieces[1][2] = x, y
  end
  -- (off the road, and a road there the plan did not know of: left out)
  if it.offRoad and M.roadCovers(x, y, M.DRESS_OFFROAD_MARGIN_M + (it.foot or 0)) then return true end
  -- (its ground: looked for higher and lower the further it was moved off its planned spot -- the edge shift, the
  -- push -- and left out when a moved one finds none: it would hang in the air or stand in the bank)
  local x0, y0 = itemNow(it, toGame)
  local moved = x0 and math.sqrt((x - x0) ^ 2 + (y - y0) ^ 2) or 0
  local above = M.DRESS_GROUND_ABOVE_M + M.DRESS_GROUND_PER_M * moved
  local zs = {}
  for i, pc in ipairs(pieces) do
    local gz, found = ground(pc[1], pc[2], z or carZ, above)
    if not found and moved >= M.DRESS_GROUND_MOVED_M then return true end
    zs[i] = gz
  end
  for i, pc in ipairs(pieces) do
    local px, py = pc[1], pc[2]
    local ok, id = pcall(makeObj, pc[3], px, py, zs[i], yawQuat(dx, dy),
      pc[4])
    if not ok then
      log('W', 'earthRally', 'a dressing prop could not be put down (' .. tostring(id) .. ')')
      return false
    end
    s.objs[#s.objs + 1] = id
  end
  return true
end

-- A site's objects put down from where it got to, up to `budget` of them, and (deadline, a clock() time: optional)
-- none once that time has passed. Returns the budget left (0 once the deadline has passed).
local function spawnDress(s, toGame, carZ, budget, deadline)
  s.objs = s.objs or {}
  s.at = s.at or 1
  while s.at <= #s.items and budget > 0 do
    local it = s.items[s.at]
    s.at = s.at + 1
    if not spawnItem(s, it, toGame, carZ) then s.at = #s.items + 1 break end
    budget = budget - 1
    if deadline and clock() >= deadline then return 0 end
  end
  return budget
end
M._spawnDress = spawnDress

-- Dressing sites in the window round the car put down, those left behind taken away (props.update calls it). At most
-- DRESS_OBJS_PER_UPDATE objects a frame; a site part way down goes on next frame.
function updateDressing(carPos, toGame, carAlong)
  local budget = M.DRESS_OBJS_PER_UPDATE
  local deadline = M.DRESS_SPAWN_MS and clock() + M.DRESS_SPAWN_MS / 1000 or nil
  if carAlong then
    -- (the sites the car has not passed first, then those behind it: with the time budget a whole window -- after a
    -- world shift -- goes down over several frames, and what is ahead is what the player sees)
    for pass = 1, 2 do
      for _, s in ipairs(dress) do
        local going = s.objs ~= nil and (s.at or 1) <= #s.items
        local want = carAlong >= s.from - M.DRESS_AHEAD_M and carAlong <= s.to + M.DRESS_BEHIND_M
        if pass == 1 and s.objs and not want then removeDress(s)
        elseif want and (going or not s.objs) and budget > 0 and (pass == 1) == (s.to >= carAlong) then
          budget = spawnDress(s, toGame, carPos.z, budget, deadline)
        end
      end
    end
    return
  end
  for _, s in ipairs(dress) do
    local going = s.objs ~= nil and (s.at or 1) <= #s.items
    if budget > 0 and (going or not s.objs) then
      local x, y = itemNow(s.items[1], toGame)
      if going or (x and (x - carPos.x) ^ 2 + (y - carPos.y) ^ 2 <= M.DRESS_AHEAD_M ^ 2) then
        budget = spawnDress(s, toGame, carPos.z, budget, deadline)
      end
    end
  end
end

------------------------------------------------------------------------------------------ the showcase

-- A developer's look at every dressing shape (runner.dressShowcase: dressing.showcase's row in front of the car),
-- put down at once through the same code as a real site's objects (keepDress, spawnItem: the same heading, the same
-- turn, the same ground), in the same scene group (a Lua reload sweeps it). One at a time: a new one takes the old
-- away. Returns the number of objects put down.
local showcase = nil
function M.showcase(rows, carZ)
  M.clearShowcase()
  local objs = {}
  for _, r in ipairs(rows or {}) do objs[#objs + 1] = r.object end
  showcase = keepDress({ kind = 'showcase', along = 0, objects = objs })
  if not showcase then return 0 end
  spawnDress(showcase, nil, carZ or 0, math.huge)
  return #showcase.objs
end
function M.clearShowcase()
  if showcase then removeDress(showcase) end
  showcase = nil
end

-- The dressing objects standing now, and the sites they belong to.
function M.dressingCount()
  local n, k = 0, 0
  for _, s in ipairs(dress) do
    if s.objs then n, k = n + #s.objs, k + 1 end
  end
  return n, k
end

return M
