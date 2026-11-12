-- earthRally/props: the roadside of a stage's controls, from the game's own rally assets (art/shapes/race/rally/
-- rally_assets, in the game's common art: there on every level): the yellow warning boards before the time control
-- and the flying finish, the red boards at the time control, start, finish and stop, and at the controls where cars
-- stop a gazebo with a table and a chair.
--
-- A site is a control's place (lat / lon), the road's direction there (game coordinates, for the moment it is put
-- down) and its height when known. Each site's props are put down when the car comes within SPAWN_M (where
-- BeamNG.Earth has the ground loaded, so they stand on it), and all are taken away with the run. A world shift moves
-- none of them, so they are put down again after one.
--
-- Placement as the game's own rallies (gameplay/missions/*/rallyLoop/*/mainPrefab): the model's +Y along the
-- driving direction, on the right of the road, just off its edge.
local M = {}

local A = '/art/shapes/race/rally/rally_assets/'
M.SPAWN_M = 350
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
  clock = A .. 's_rally_start_clock_display.dae',
}

-- each kind of control: { shape, fwd (m along the road), out (m beyond the road's right edge), yaw (degrees from the
-- road's way) }. The edge is the road's own (BeamNG.Earth's road map: its half width where the site is), so the boards
-- stand just off the road on a wide one as on a forest track.
M.BOARD_OUT_M = 1.0
M.TENT_OUT_M = 2.2          -- the gazebo's centre (it is 3 m square: its near side 0.7 m off the road)
M.DEFAULT_HALF_WIDTH_M = 3.0
M.SNAP_M = 30               -- a site this close to a road is put on it
local TENT = function(fwd)
  local o = M.TENT_OUT_M
  return {
    { 'gazeboFrame', fwd, o, 0 }, { 'gazeboCover', fwd, o, 0 },
    { 'table', fwd - 0.3, o - 0.6, 90 }, { 'chair', fwd - 0.3, o + 0.3, 90 },
  }
end
local function join(a, b) for _, x in ipairs(b) do a[#a + 1] = x end return a end
local B = M.BOARD_OUT_M
M.LAYOUTS = {
  atc = join({ { 'tcEntry', -50, B, 0 }, { 'tc', 0, B, 0 } }, TENT(4)),
  start = join({ { 'start', 0, B, 0 }, { 'clock', 1.5, B + 0.5, 0 } }, TENT(-6)),
  ff = join({ { 'finishEntry', -150, B, 0 }, { 'finish', 0, B, 0 } }, TENT(6)),
  stop = join({ { 'stop', 0, B, 0 } }, TENT(4)),
}

local sites = {}          -- { kind, lat, lon, z (nil: not known), dir = {x, y} (game coordinates), objs, failed }
local serial = 0

-- dir: the road's direction at the site in game coordinates (re-given after a world shift via M.setSite)
function M.setSite(kind, lat, lon, dir, z)
  for _, s in ipairs(sites) do
    if s.kind == kind then
      M.removeSite(s)
      s.lat, s.lon, s.dir, s.z = lat, lon, dir, z
      return s
    end
  end
  local s = { kind = kind, lat = lat, lon = lon, dir = dir, z = z }
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

-- (a yaw-only rotation turning +Y to (dx, dy): as quatFromDir(dir, up))
local function yawQuat(dx, dy)
  local h = math.atan2(dx, dy)          -- clockwise from +Y
  return { 0, 0, -math.sin(h / 2), math.cos(h / 2) }
end

-- The ground under (x, y) near the height z0: looked for a few metres above first, so a tree over the spot is not
-- taken for the ground.
local function ground(x, y, z0)
  local ray = rawget(_G, 'castRayStatic')
  if not ray then return z0 end
  for _, t in ipairs({ { 8, 40 }, { 25, 80 } }) do
    local top = z0 + t[1]
    local d = ray(vec3(x, y, top), vec3(0, 0, -1), t[2])
    if d and d < t[2] then
      local z = top - d
      if math.abs(z - z0) <= t[1] + 2 then return z end
    end
  end
  return z0
end

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
  o:registerObject('earthRally_prop_' .. serial)
  scenetree.MissionGroup:addObject(o)
  return o:getID()
end

-- The road under a spot (the game's road map, which BeamNG.Earth fills with the roads round the car): the nearest
-- point on its centre line, its half width there, and its direction; nil when no road is within SNAP_M.
function M.roadAt(x, y, z)
  local mp = rawget(_G, 'map')
  if not (mp and mp.findClosestRoad and mp.getMap) then return nil end
  local okM, m = pcall(mp.getMap)
  if not okM or not (m and m.nodes) then return nil end
  local ok, n1, n2, d = pcall(mp.findClosestRoad, vec3(x, y, z or 0), M.SNAP_M)
  if not ok or not n1 or not n2 or not d or d > M.SNAP_M then return nil end
  local a, b = m.nodes[n1], m.nodes[n2]
  if not (a and b and a.pos and b.pos) then return nil end
  local dx, dy = b.pos.x - a.pos.x, b.pos.y - a.pos.y
  local l2 = dx * dx + dy * dy
  if l2 < 1e-6 then return nil end
  local t = math.max(0, math.min(1, ((x - a.pos.x) * dx + (y - a.pos.y) * dy) / l2))
  local half = (a.radius or M.DEFAULT_HALF_WIDTH_M) * (1 - t) + (b.radius or M.DEFAULT_HALF_WIDTH_M) * t
  local l = math.sqrt(l2)
  return { x = a.pos.x + dx * t, y = a.pos.y + dy * t, half = half, dx = dx / l, dy = dy / l }
end

local function spawn(s, toGame, carZ)
  local layout = M.LAYOUTS[s.kind]
  if not layout then return end
  local x0, y0 = toGame(s.lat, s.lon, 0)
  if not x0 then return end
  local l = math.sqrt(s.dir.x * s.dir.x + s.dir.y * s.dir.y)
  if l < 1e-6 then return end
  local fx, fy = s.dir.x / l, s.dir.y / l
  -- on the road the site is on (the map's controls can be a few metres off it), along it, the edge from its width
  local half = M.DEFAULT_HALF_WIDTH_M
  local road = M.roadAt(x0, y0, s.z or carZ)
  if road then
    x0, y0, half = road.x, road.y, road.half
    local sgn = (road.dx * fx + road.dy * fy) >= 0 and 1 or -1
    fx, fy = road.dx * sgn, road.dy * sgn
  end
  s.half = half
  local rx, ry = fy, -fx
  local z0 = s.z or carZ
  s.objs = {}
  for _, it in ipairs(layout) do
    local shape = M.SHAPES[it[1]]
    local out = half + it[3]
    local x, y = x0 + fx * it[2] + rx * out, y0 + fy * it[2] + ry * out
    local yaw = math.rad(it[4])
    local dx, dy = fx * math.cos(yaw) + rx * math.sin(yaw), fy * math.cos(yaw) + ry * math.sin(yaw)
    local ok, id = pcall(makeObj, shape, x, y, ground(x, y, z0), yawQuat(dx, dy))
    if ok then s.objs[#s.objs + 1] = id
    else
      log('W', 'earthRally', 'a rally prop could not be put down (' .. tostring(id) .. ')')
      s.failed = true
      break
    end
  end
end

-- Every frame of a run: sites within SPAWN_M of the car put down (once). carPos in game coordinates.
function M.update(carPos, toGame)
  if not carPos then return end
  for _, s in ipairs(sites) do
    if not s.objs and not s.failed then
      local x, y = toGame(s.lat, s.lon, 0)
      if x and (x - carPos.x) ^ 2 + (y - carPos.y) ^ 2 <= M.SPAWN_M ^ 2 then spawn(s, toGame, carPos.z) end
    end
  end
end

-- After a world shift: everything put down again where it belongs (directions re-given by the caller).
function M.reset()
  for _, s in ipairs(sites) do M.removeSite(s) end
end

function M.count()
  local n = 0
  for _, s in ipairs(sites) do n = n + #(s.objs or {}) end
  return n
end

return M
