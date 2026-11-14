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
-- boards, without it, as they always were: up to ~6 m above).
local TIERS = { { 4, 12 }, { 8, 40 }, { 25, 80 } }
local function ground(x, y, z0, maxAbove)
  local ray = rawget(_G, 'castRayStatic')
  if not ray then return z0 end
  for k, t in ipairs(TIERS) do
    local up = (maxAbove and k == 1) and maxAbove or t[1]
    local top = z0 + up
    local d = ray(vec3(x, y, top), vec3(0, 0, -1), t[2])
    if d and d < t[2] then
      local z = top - d
      if math.abs(z - z0) <= up + 2 and not (maxAbove and z - z0 > maxAbove) then return z end
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
function M.roadAt(x, y, dir, snap)
  snap = snap or M.SNAP_M
  local nodes = mapNodes()
  if not nodes then return nil end
  local best, bestScore = nil, math.huge
  local r2 = (snap + 40) ^ 2
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
  local how = ''
  if s.path then
    local p = s.path(0)
    local r = p and M.roadAt(p.x, p.y, { x = p.dx, y = p.dy })
    how = string.format(', along the stage line (%s)', r and string.format('road map centre %.1f m off, heading %.0f deg',
      r.d, math.deg(math.atan2(p.dx, p.dy)) % 360) or 'no road map there')
  elseif s.edge then
    how = string.format(', road map %.1f m from the control, heading %.0f deg', s.edge.d or 0,
      math.deg(math.atan2(s.edge.dx, s.edge.dy)) % 360)
  else
    how = ', no road on the map there: straight from the control'
  end
  log('I', 'earthRally', string.format('props: %s put down (%d objects, %d placed by the road map%s)', s.kind, n, onRoad, how))
end

local updateDressing        -- (the stage dressing, below)

-- Every frame of a run: sites near enough the car put down (once). carPos in game coordinates; carAlong (optional):
-- the car's distance along the stage line, which the stage dressing is put down and taken away by.
function M.update(carPos, toGame, carAlong)
  if not carPos then return end
  updateDressing(carPos, toGame, carAlong)
  for _, s in ipairs(sites) do
    if not s.objs and not s.failed then
      local x, y = toGame(s.lat, s.lon, 0)
      local d2 = x and (x - carPos.x) ^ 2 + (y - carPos.y) ^ 2
      if d2 and d2 <= M.SPAWN_M ^ 2 then
        s.x0, s.y0 = x, y
        -- the road under the control, aligned with the driving direction (sites not on the stage line)
        s.edge = nil
        if not s.path then
          -- (a control's point can be well off the road: looked for further out when nothing is near)
          local e = M.roadAt(x, y, s.dir) or M.roadAt(x, y, s.dir, M.SNAP_FAR_M)
          if e then
            local tw = s.toward and { x = select(1, toGame(s.toward.lat, s.toward.lon, 0)), y = select(2, toGame(s.toward.lat, s.toward.lon, 0)) }
            local aw = s.away and { x = select(1, toGame(s.away.lat, s.away.lon, 0)), y = select(2, toGame(s.away.lat, s.away.lon, 0)) }
            s.edge = M.orient(e, tw and tw.x and tw, aw and aw.x and aw)
          end
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
  M.resetDressing()
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
M.DRESS_GROUND_ABOVE_M = 2   -- a dressing object's ground: a hit at most this above its planned height (not a roof)
-- An object set from the road's edge (dressing.lua's edged) moved out by the road's half width where it stands less
-- the one it was planned against: the road map's road looked for at the object's planned road centre, within
-- DRESS_EDGE_SNAP_M and aligned with the road, once per DRESS_EDGE_REUSE_M of a site; the move held to
-- DRESS_EDGE_SHIFT_MIN_M .. DRESS_EDGE_SHIFT_MAX_M.
M.DRESS_EDGE_SNAP_M = 8
M.DRESS_EDGE_REUSE_M = 20
M.DRESS_EDGE_SHIFT_MIN_M, M.DRESS_EDGE_SHIFT_MAX_M = -2, 6
local HEAD_M = 10

-- { kind, along, from, to, name, key, objs (ids, when down or going down), at (the next item to put down),
--   items = { { shape, lat, lon, h, hlat, hlon, [nlat, nlon, eo, eh] } or the same in x / y } }
local dress = {}

local function removeDress(s)
  for _, id in ipairs(s.objs or {}) do
    local o = scenetree.findObjectById(id)
    if o then o:delete() end
  end
  s.objs, s.at, s.probe = nil, nil, nil
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

-- A dressing site's key: its kind and where it is along the line, to the metre. Two plans of the same junction (the
-- file's at the stage's start, the live road map's later) give the same key, so the second is not put down twice.
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
    local it = { shape = o.shape, eo = edge and o.eo or nil, eh = edge and o.eh or nil }
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
-- and a world shift is not followed. A site whose key (kind and along) is already there is left out, as addDressing
-- does: two sites at one key would both be taken away by one removeDressing.
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

-- The sites with these keys (dressKey: as M.siteKey gives them) taken away, objects and all: a junction judged again
-- on more of the road map than it was first (runner.lua) has its sites replaced. Returns the number taken.
function M.removeDressing(keys)
  local drop = {}
  for _, k in ipairs(keys or {}) do drop[k] = true end
  local kept, n = {}, 0
  for _, s in ipairs(dress) do
    if drop[s.key] then removeDress(s) n = n + 1 else kept[#kept + 1] = s end
  end
  dress = kept
  return n
end
M.siteKey = dressKey

-- More dressing for the stage, beside what there is: the sites of junctions the live road map has shown since the
-- stage was planned (runner.lua). Nothing already there is taken away or put down again (setDressing would take the
-- whole stage away and put it back, a flicker of every object near the car), and a site whose key (kind and along)
-- is already there is left out. The new ones go down by the next update, by the same window as the rest. Returns the
-- number added.
function M.addDressing(list, toGeo)
  local have, lost = {}, { n = 0 }
  for _, s in ipairs(dress) do have[s.key or dressKey(s.kind, s.along)] = true end
  local n = 0
  for _, site in ipairs(list or {}) do
    local k = dressKey(site.kind, site.along)
    if not have[k] then
      local d = keepDress(site, toGeo, lost)
      if d then
        dress[#dress + 1] = d
        have[k] = true
        n = n + 1
      end
    end
  end
  sayLost(lost, 'added from the live road map')
  return n
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

-- (the move out for an object set from the road's edge, at (x, y) with the way out (nx, ny): the road map's half
-- width at its planned road centre less the one it was planned against; 0 where the road map has no road there.
-- One look serves a site's objects within DRESS_EDGE_REUSE_M of it: a spectator area is 64 objects)
local function edgeShift(s, it, x, y, nx, ny)
  local cx, cy = x - nx * it.eo, y - ny * it.eo
  local p = s.probe
  if p and (p.x - cx) ^ 2 + (p.y - cy) ^ 2 <= M.DRESS_EDGE_REUSE_M ^ 2 and p.eh == it.eh then return p.shift end
  local shift = 0
  local r = M.roadAt(cx, cy, { x = -ny, y = nx }, M.DRESS_EDGE_SNAP_M)
  if r and type(r.half) == 'number' and r.half > 0 then
    shift = math.max(M.DRESS_EDGE_SHIFT_MIN_M, math.min(M.DRESS_EDGE_SHIFT_MAX_M, r.half - it.eh))
  end
  s.probe = { x = cx, y = cy, eh = it.eh, shift = shift }
  return shift
end

-- One object of a dressing site put down (or left out: a shape the game has not, a place with no game position).
-- Returns false when the game would not make it.
local function spawnItem(s, it, toGame, carZ)
  if not shapeOk(it.shape) then return true end
  local x, y, z, hx, hy = itemNow(it, toGame)
  if not x then return true end
  local dx, dy = hx - x, hy - y
  if dx * dx + dy * dy < 1e-9 then dx, dy = 0, 1 end
  if it.eo then
    local nx, ny
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
    end
  end
  local ok, id = pcall(makeObj, it.shape, x, y, ground(x, y, z or carZ, M.DRESS_GROUND_ABOVE_M), yawQuat(dx, dy))
  if ok then s.objs[#s.objs + 1] = id return true end
  log('W', 'earthRally', 'a dressing prop could not be put down (' .. tostring(id) .. ')')
  return false
end

-- A site's objects put down from where it got to, up to `budget` of them. Returns the budget left.
local function spawnDress(s, toGame, carZ, budget)
  s.objs = s.objs or {}
  s.at = s.at or 1
  while s.at <= #s.items and budget > 0 do
    local it = s.items[s.at]
    s.at = s.at + 1
    if not spawnItem(s, it, toGame, carZ) then s.at = #s.items + 1 break end
    budget = budget - 1
  end
  return budget
end
M._spawnDress = spawnDress

-- Dressing sites in the window round the car put down, those left behind taken away (props.update calls it). At most
-- DRESS_OBJS_PER_UPDATE objects a frame; a site part way down goes on next frame.
function updateDressing(carPos, toGame, carAlong)
  local budget = M.DRESS_OBJS_PER_UPDATE
  for _, s in ipairs(dress) do
    local going = s.objs ~= nil and (s.at or 1) <= #s.items
    if carAlong then
      local want = carAlong >= s.from - M.DRESS_AHEAD_M and carAlong <= s.to + M.DRESS_BEHIND_M
      if s.objs and not want then removeDress(s)
      elseif want and (going or not s.objs) and budget > 0 then
        budget = spawnDress(s, toGame, carPos.z, budget)
      end
    elseif budget > 0 and (going or not s.objs) then
      local x, y = itemNow(s.items[1], toGame)
      if going or (x and (x - carPos.x) ^ 2 + (y - carPos.y) ^ 2 <= M.DRESS_AHEAD_M ^ 2) then
        budget = spawnDress(s, toGame, carPos.z, budget)
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
