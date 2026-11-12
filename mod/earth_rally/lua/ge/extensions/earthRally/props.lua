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
-- position, 1 m off the road's right edge, turned ~25 degrees towards the road so its clock faces the car
M.TREE_FWD_M, M.TREE_OUT_M, M.TREE_YAW = 1.5, 1.0, -25
M.DEFAULT_HALF_WIDTH_M = 3.0
M.SNAP_M = 30               -- a site this close to a road is on it
M.TURN_MAX_DEG = 60         -- walking the road map: at a junction, the road on that turns at most this much
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
-- taken for the ground; z0 when nothing is found near it.
local function ground(x, y, z0)
  local ray = rawget(_G, 'castRayStatic')
  if not ray then return z0 end
  for _, t in ipairs({ { 4, 12 }, { 8, 40 }, { 25, 80 } }) do
    local top = z0 + t[1]
    local d = ray(vec3(x, y, top), vec3(0, 0, -1), t[2])
    if d and d < t[2] then
      local z = top - d
      if math.abs(z - z0) <= t[1] + 2 then return z end
    end
  end
  return z0
end
M._ground = ground
M._yawQuat = yawQuat

local function makeObj(shape, x, y, z, q)
  local o = createObject('TSStatic')
  o:setField('shapeName', 0, shape)
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

-- The road-map edge beside (x, y) in plan (heights are not trusted: the car may be far above or below the spot), the
-- one best aligned with dir (dx, dy) when given among those within SNAP_M: { a, b (node names, oriented along dir),
-- t, x, y, z, half, dx, dy, d }, or nil.
function M.roadAt(x, y, dir)
  local nodes = mapNodes()
  if not nodes then return nil end
  local best, bestScore = nil, math.huge
  local r2 = (M.SNAP_M + 40) ^ 2
  local dl = dir and math.sqrt(dir.x * dir.x + dir.y * dir.y) or 0
  for na, a in pairs(nodes) do
    local pa = a.pos
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
            if d <= M.SNAP_M then
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
  local l = math.sqrt(s.dir.x * s.dir.x + s.dir.y * s.dir.y)
  local fx, fy = s.dir.x / l, s.dir.y / l
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
  log('I', 'earthRally', string.format('props: %s put down (%d objects, %d placed by the road map%s)', s.kind, n, onRoad,
    s.path and ', along the stage line' or (s.edge and '' or ', no road on the map there: straight from the control')))
end

-- Every frame of a run: sites near enough the car put down (once). carPos in game coordinates.
function M.update(carPos, toGame)
  if not carPos then return end
  for _, s in ipairs(sites) do
    if not s.objs and not s.failed then
      local x, y = toGame(s.lat, s.lon, 0)
      local d2 = x and (x - carPos.x) ^ 2 + (y - carPos.y) ^ 2
      if d2 and d2 <= M.SPAWN_M ^ 2 then
        s.x0, s.y0 = x, y
        -- the road under the control, aligned with the driving direction (sites not on the stage line)
        s.edge = nil
        if not s.path then
          local e = M.roadAt(x, y, s.dir)
          if e then s.edge = e end
        end
        -- nothing to tell the height (no stage line, no road map there): only once the car is close, its own height
        -- then near the ground's
        if s.path or s.edge or s.z or d2 <= M.NO_ROAD_SPAWN_M ^ 2 then spawn(s, carPos.z) end
      end
    end
  end
end

-- After a world shift: everything put down again where it belongs (directions re-given by the caller).
function M.reset()
  for _, s in ipairs(sites) do M.removeSite(s) s.edge = nil end
end

-- Where a site's boards stand on the road (game coordinates now: the road map's point beside the control), once its
-- props are down and the road map had the road; else nil (the caller uses the control's own spot).
function M.sitePoint(kind)
  for _, s in ipairs(sites) do
    if s.kind == kind and s.objs and #s.objs > 0 and s.edge then return { x = s.edge.x, y = s.edge.y } end
  end
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

return M
