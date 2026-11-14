-- The roadside boards' facing, against a copy of the game's own quatFromDir (lua/common/mathlib.lua,
-- LuaQuat:setFromDir), on roads running every way: a mirrored turn looks right only on a road running north-south.
local T = dofile(TESTS .. '/testlib.lua')
function log() end
local props = require('earthRally/props')

-- the game's setFromDir(dir, up = +Z), for a level direction
local function gameQuat(dx, dy)
  local l = math.sqrt(dx * dx + dy * dy)
  local d = { dx / l, dy / l, 0 }
  local u = { 0, 0, 1 }
  local function cross(a, b) return { a[2] * b[3] - a[3] * b[2], a[3] * b[1] - a[1] * b[3], a[1] * b[2] - a[2] * b[1] } end
  local m = {}
  m[1] = d
  m[0] = cross(d, u)
  m[2] = cross(m[0], d)
  local function at(i, j) return m[i][j + 1] end
  local tr = at(0, 0) + at(1, 1) + at(2, 2)
  if tr > 0 then
    local s = math.sqrt(tr + 1)
    local w = s * 0.5
    s = 0.5 / s
    return { (at(2, 1) - at(1, 2)) * s, (at(0, 2) - at(2, 0)) * s, (at(1, 0) - at(0, 1)) * s, w }
  end
  local i = 0
  if at(1, 1) > at(0, 0) then i = 1 end
  if at(2, 2) > at(i, i) then i = 2 end
  local j, k = (i + 1) % 3, (i + 2) % 3
  local q = { [0] = 0, 0, 0 }
  local s = math.sqrt((at(i, i) - at(j, j)) - (at(k, k) - 1))
  q[i] = s * 0.5
  s = 0.5 / s
  q[j] = (at(j, i) + at(i, j)) * s
  q[k] = (at(k, i) + at(i, k)) * s
  local w = (at(k, j) - at(j, k)) * s
  return { q[0], q[1], q[2], w }
end

local worst = 0
for deg = 0, 345, 15 do
  local h = math.rad(deg)
  local dx, dy = math.sin(h), math.cos(h)       -- (clockwise from north)
  local q, g = props._yawQuat(dx, dy), gameQuat(dx, dy)
  -- the same rotation: q and -q are one
  local dot = math.abs(q[1] * g[1] + q[2] * g[2] + q[3] * g[3] + q[4] * g[4])
  worst = math.max(worst, 1 - dot)
end
T.check(worst < 1e-6, 'a board turned as the game turns it, on roads running every way (worst ' .. string.format('%.2g', worst) .. ')')

-- a road running east: the board's front (+Y) turned to +X, not to -X
local q = props._yawQuat(1, 0)
local x, y, z, w = q[1], q[2], q[3], q[4]
-- +Y rotated by q (the game's convention, as gameQuat: rows): column of the rotation matrix, conjugated
local gx = gameQuat(1, 0)
T.check(math.abs(z - gx[3]) < 1e-9 and math.abs(w - gx[4]) < 1e-9, 'east: the same quaternion as the game\'s')

-- a control's road running across the straight line to the start: its way picked by walking along it
local nodes = {}
for k = -10, 10 do
  local n = 'e' .. k
  nodes[n] = { pos = { x = k * 10, y = 0, z = 0 }, radius = 3, links = {} }
  if k > -10 then nodes[n].links['e' .. (k - 1)] = {} nodes['e' .. (k - 1)].links[n] = {} end
end
map = { getMap = function() return { nodes = nodes } end }
local e = props.roadAt(2, 1, { x = 0.05, y = 1 })            -- (the start straight "north": the road runs east-west)
local east = props.orient(e, { x = 300, y = 40 })
local west = props.orient(e, { x = -300, y = 40 })
T.check(east and east.dx > 0.9 and west and west.dx < -0.9, 'a road across the way to the start: turned along the road towards it')
local fromEast = props.orient(e, nil, { x = 300, y = 0 })
T.check(fromEast.dx < -0.9, 'the stop control: the way leading on from the finish')
map = nil

-- The stage dressing: put down by the car's distance along the line, taken away 600 m behind it, put down again after
-- a world shift where it belongs. A stand-in for the game's scene: every object made, where it was put, and whether it
-- is still there.
local made, live, named = {}, {}, {}
local nextId = 0
function createObject()
  nextId = nextId + 1
  local o = { id = nextId, fields = {} }
  function o:setField(k, _, v) self.fields[k] = v end
  function o:setPosRot(x, y, z, a, b, c, d) self.pos = { x, y, z } self.q = { a, b, c, d } end
  function o:registerObject(name) live[self.id] = self if name then named[name] = self end end
  function o:getID() return self.id end
  function o:delete() live[self.id] = nil end
  function o:addObject() end
  made[#made + 1] = o
  return o
end
scenetree = { MissionGroup = { addObject = function() end }, findObjectById = function(id) return live[id] end,
              findObject = function(name) return named[name] end }
local function liveCount() local n = 0 for _, o in pairs(live) do if o.fields.shapeName then n = n + 1 end end return n end

local D = require('earthRally/dressing')
local line = {}
for k = 0, 50 do line[#line + 1] = { x = 0, y = k * 100, z = 0 } end
local js = {}
for s = 250, 4750, 250 do
  js[#js + 1] = { along = s, x = 0, y = s, kind = 'turn', inDeg = 0, outDeg = 90, sides = { { deg = 0 }, { deg = 270 } } }
end
local plan = D.plan({ line = line, startM = 0, finishM = 5000, junctions = js })
-- (lat / lon here: a frame of our own the game's moves against, as BeamNG.Earth's origin does)
local ox, oy = 0, 0
local function toGeo(x, y, z) return x + ox, y + oy, z end
local function toGame(la, lo, h) return la - ox, lo - oy, h end
local n = props.setDressing(plan, toGeo)
T.check(n == #plan and n > 0, 'dressing: every site taken')
local car = { x = 0, y = 0, z = 0 }
for _ = 1, 10 do props.update(car, toGame, 0) end
local objs, sitesDown = props.dressingCount()
T.check(sitesDown > 0 and objs == liveCount(), 'dressing: the sites within 350 m ahead put down (' .. sitesDown .. ')')
local expect = 0
for _, s in ipairs(plan) do if s.from <= 350 then expect = expect + 1 end end
T.check(sitesDown == expect, 'dressing: and only those (' .. sitesDown .. ' of ' .. expect .. ')')
T.check(#made <= 4 * 8 * 10, 'dressing: a few sites an update')
-- the controls' own count untouched by the dressing
T.check(props.count() == 0, 'dressing: not counted with the controls\' props')

-- 2 km on: everything behind 1400 m gone, everything to 2350 m down
car = { x = 0, y = 2000, z = 0 }
for _ = 1, 20 do props.update(car, toGame, 2000) end
local _, k = props.dressingCount()
local want = 0
for _, s in ipairs(plan) do if s.to >= 1400 and s.from <= 2350 then want = want + 1 end end
T.check(k == want, 'dressing: the window 600 m behind to 350 m ahead (' .. k .. ' of ' .. want .. ')')
T.check(select(1, props.dressingCount()) == liveCount(), 'dressing: those behind really taken away')
local early = 0
for _, o in pairs(live) do if o.pos and o.pos[2] < 1300 then early = early + 1 end end
T.check(early == 0, 'dressing: nothing left standing far behind')

-- a world shift: the origin moves 1000 m east; after reset the same objects stand 1000 m further west in game coordinates
local before = {}
for _, o in pairs(live) do if o.pos then before[#before + 1] = { o.fields.shapeName, o.pos[1], o.pos[2], o.q[3], o.q[4] } end end
table.sort(before, function(a, b) if a[3] ~= b[3] then return a[3] < b[3] end return a[2] < b[2] end)
ox = ox + 1000
props.reset()
T.check(liveCount() == 0, 'world shift: the dressing taken away')
for _ = 1, 20 do props.update({ x = -1000, y = 2000, z = 0 }, toGame, 2000) end
local after = {}
for _, o in pairs(live) do if o.pos then after[#after + 1] = { o.fields.shapeName, o.pos[1] + 1000, o.pos[2], o.q[3], o.q[4] } end end
table.sort(after, function(a, b) if a[3] ~= b[3] then return a[3] < b[3] end return a[2] < b[2] end)
local same = #after == #before and #after > 0
for i = 1, math.min(#after, #before) do
  local a, b = after[i], before[i]
  if a[1] ~= b[1] or math.abs(a[2] - b[2]) > 1e-6 or math.abs(a[3] - b[3]) > 1e-6 or math.abs(a[4] - b[4]) > 1e-6
    or math.abs(a[5] - b[5]) > 1e-6 then same = false end
end
T.check(same, 'world shift: put down again where it belongs, turned the same way')

-- a site asking for more than the budget gets the budget
local big = { kind = 'spectators', along = 0, from = 0, to = 0, objects = {} }
for i = 1, 100 do big.objects[i] = { shape = 'x.dae', x = i, y = 0, dx = 0, dy = 1 } end
props.setDressing({ big })
props.update({ x = 0, y = 0, z = 0 }, toGame, 0)
T.check(select(1, props.dressingCount()) == props.DRESS_MAX_OBJS, 'dressing: a site held to its budget')
props.clear()
T.check(liveCount() == 0 and select(2, props.dressingCount()) == 0, 'dressing: cleared with the stage')

-- The add-only path (the live road map's junctions, found as the car goes): new sites beside the ones there, nothing
-- standing taken away or put down again, a site already there (same kind, same metre along) left out.
do
  local function site(kind, along, x)
    return { kind = kind, along = along, from = along, to = along,
             objects = { { shape = kind .. '.dae', x = x or 0, y = along, dx = 1, dy = 0 } } }
  end
  props.setDressing({ site('tape', 100), site('board', 25) })
  props.update({ x = 0, y = 0, z = 0 }, toGame, 0)
  local before = {}
  for id, o in pairs(live) do if o.fields.shapeName then before[#before + 1] = id end end
  T.check(#before == 2, 'add-only: the stage\'s two sites down (' .. #before .. ')')
  local n2 = props.addDressing({ site('tape', 100), site('tape', 100.3, 5), site('board', 100), site('tape', 200),
                                 { kind = 'tape', along = 300, from = 300, to = 300, objects = {} } })
  T.check(n2 == 2, 'add-only: two new sites taken, the same kind at the same metre left out, an empty one too (' ..
    tostring(n2) .. ')')
  local by, n = props.dressingSites()
  T.check(n == 4 and by.tape == 2 and by.board == 2, 'add-only: beside the ones there (' .. n .. ')')
  for _ = 1, 3 do props.update({ x = 0, y = 0, z = 0 }, toGame, 0) end
  local kept = true
  for _, id in ipairs(before) do if not live[id] then kept = false end end
  T.check(kept, 'add-only: what stood is still standing, the same objects')
  T.check(liveCount() == 4 and select(2, props.dressingCount()) == 4, 'add-only: the new ones down by the next update ('
    .. liveCount() .. ')')
  local made0 = #made
  props.addDressing({ site('tape', 200), site('board', 100) })
  props.update({ x = 0, y = 0, z = 0 }, toGame, 0)
  T.check(#made == made0, 'add-only: the same sites again: nothing made')
  -- far behind the car: taken away by the window as any other
  props.update({ x = 0, y = 2000, z = 0 }, toGame, 2000)
  T.check(liveCount() == 0, 'add-only: an added site taken away behind the car as the rest')
  props.clear()
  T.check(select(2, props.dressingSites()) == 0, 'add-only: cleared with the stage')
end
T.done('test_props')
