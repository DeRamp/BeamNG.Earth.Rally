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
-- driving direction, on the right of the road, 1-5 m off it.
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

-- each kind of control: { shape, fwd (m along the road), right (m to its right), yaw (degrees from the road's way) }
local TENT = function(fwd, right)
  return {
    { 'gazeboFrame', fwd, right, 0 }, { 'gazeboCover', fwd, right, 0 },
    { 'table', fwd - 0.3, right - 0.6, 90 }, { 'chair', fwd - 0.3, right + 0.3, 90 },
  }
end
local function join(a, b) for _, x in ipairs(b) do a[#a + 1] = x end return a end
M.LAYOUTS = {
  atc = join({ { 'tcEntry', -50, 4, 0 }, { 'tc', 0, 4, 0 } }, TENT(2, 8)),
  start = join({ { 'start', 0, 4, 0 }, { 'clock', 1.5, 3.5, 0 } }, TENT(-6, 8)),
  ff = { { 'finishEntry', -150, 4, 0 }, { 'finish', 0, 4, 0 } },
  stop = join({ { 'stop', 0, 4, 0 } }, TENT(3, 8)),
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

local function spawn(s, toGame, carZ)
  local layout = M.LAYOUTS[s.kind]
  if not layout then return end
  local x0, y0 = toGame(s.lat, s.lon, 0)
  if not x0 then return end
  local l = math.sqrt(s.dir.x * s.dir.x + s.dir.y * s.dir.y)
  if l < 1e-6 then return end
  local fx, fy = s.dir.x / l, s.dir.y / l
  local rx, ry = fy, -fx
  local z0 = s.z or carZ
  s.objs = {}
  for _, it in ipairs(layout) do
    local shape = M.SHAPES[it[1]]
    local x, y = x0 + fx * it[2] + rx * it[3], y0 + fy * it[2] + ry * it[3]
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
