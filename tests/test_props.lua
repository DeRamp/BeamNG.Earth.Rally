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
-- (never more than DRESS_OBJS_PER_UPDATE objects made in one update, however many sites are due)
local worstFrame = 0
for _ = 1, 10 do
  local m0 = #made
  props.update(car, toGame, 0)
  worstFrame = math.max(worstFrame, #made - m0)
end
local objs, sitesDown = props.dressingCount()
T.check(sitesDown > 0 and objs == liveCount(), 'dressing: the sites within 350 m ahead put down (' .. sitesDown .. ')')
local expect = 0
for _, s in ipairs(plan) do if s.from <= 350 then expect = expect + 1 end end
T.check(sitesDown == expect, 'dressing: and only those (' .. sitesDown .. ' of ' .. expect .. ')')
T.check(worstFrame > 0 and worstFrame <= props.DRESS_OBJS_PER_UPDATE,
  'dressing: at most ' .. props.DRESS_OBJS_PER_UPDATE .. ' objects an update (' .. worstFrame .. ')')
do
  -- a window of more objects than a frame takes: spread over frames, each frame at the cap, nothing lost
  local many = {}
  for k = 1, 10 do
    local s = { kind = 'spectators', along = k, from = k, to = k, objects = {} }
    for i = 1, 10 do s.objects[i] = { shape = 'm.dae', x = i, y = k, dx = 0, dy = 1 } end
    many[k] = s
  end
  props.setDressing(many)
  local per = {}
  for f = 1, 6 do
    local m0 = #made
    props.update({ x = 0, y = 0, z = 0 }, toGame, 0)
    per[f] = #made - m0
  end
  T.check(per[1] == 24 and per[2] == 24 and per[3] == 24 and per[4] == 24 and per[5] == 4 and per[6] == 0,
    'dressing: 100 objects due at once go down 24 a frame (' .. table.concat(per, ' ') .. ')')
  T.check(select(1, props.dressingCount()) == 100, 'dressing: every one of them down in the end')
  props.setDressing(plan, toGeo)
end
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
T.check(select(1, props.dressingCount()) == props.DRESS_OBJS_PER_UPDATE,
  'dressing: a site of more objects than a frame takes: the first ' .. props.DRESS_OBJS_PER_UPDATE .. ' this frame (' ..
  select(1, props.dressingCount()) .. ')')
for _ = 1, 5 do props.update({ x = 0, y = 0, z = 0 }, toGame, 0) end
T.check(select(1, props.dressingCount()) == props.DRESS_MAX_OBJS, 'dressing: the rest the next frames, the site held to its budget')
props.clear()
T.check(liveCount() == 0 and select(2, props.dressingCount()) == 0, 'dressing: cleared with the stage')

------------------------------------------------------------------------------------------ 1.4.0's review
local logs = {}
function log(level, _, msg) logs[#logs + 1] = level .. ' ' .. tostring(msg) end
local function logged(pat)
  local n = 0
  for _, l in ipairs(logs) do if l:find(pat, 1, true) then n = n + 1 end end
  return n
end
local function one(kind, along, x, extra)
  local o = { shape = kind .. '.dae', x = x or 0, y = along, dx = 0, dy = 1 }
  for k, v in pairs(extra or {}) do o[k] = v end
  return { kind = kind, along = along, from = along, to = along, objects = { o } }
end
local function shapesLive(shape)
  local out = {}
  for _, o in pairs(live) do if o.fields.shapeName == shape then out[#out + 1] = o end end
  return out
end

-- setDressing: one site per key
do
  local n = props.setDressing({ one('tape', 100), one('tape', 100.2, 5), one('board', 100) })
  T.check(n == 2, 'setDressing: the same kind at the same metre kept once (' .. n .. ')')
  props.update({ x = 0, y = 0, z = 0 }, toGame, 0)
  T.check(#shapesLive('tape.dae') == 1, 'setDressing: one tape down, not two')
  local by, k = props.dressingSites()
  T.check(k == 2 and by.tape == 1 and by.board == 1, 'dressingSites: by kind')
  props.clear()
end

-- an object set from the road's edge, moved out by the road map's half width there less the planned one
do
  ox, oy = 0, 0
  -- (the road map in game coordinates of the moment: it moves with a world shift as the game's does)
  map = { getMap = function()
    local nodes = {}
    for k = 0, 20 do
      nodes['n' .. k] = { pos = { x = -ox, y = k * 20 - oy, z = 0 }, radius = 5, links = {} }
      if k > 0 then nodes['n' .. k].links['n' .. (k - 1)] = {} end
    end
    return { nodes = nodes }
  end }
  -- a board on the right of a road running north, planned 2.7 m out against a half width of 3
  local function board(along) return one('board', along, 2.7, { ex = 1, ey = 0, eo = 2.7, eh = 3 }) end
  props.setDressing({ board(100), one('tape', 120, 2.7) })
  props.update({ x = 0, y = 0, z = 0 }, toGame, 0)
  local b, t = shapesLive('board.dae')[1], shapesLive('tape.dae')[1]
  T.check(b and math.abs(b.pos[1] - 4.7) < 1e-6 and math.abs(b.pos[2] - 100) < 1e-6,
    'edge: on a road 5 m half wide, a board planned against 3 m moved out 2 m (' .. tostring(b and b.pos[1]) .. ')')
  T.check(t and math.abs(t.pos[1] - 2.7) < 1e-6, 'edge: an object not set from the edge left where it was')
  props.clear()
  -- the same kept as lat / lon (toGeo), across a world shift
  ox = 0
  props.setDressing({ board(100) }, toGeo)
  ox = 500
  props.reset()
  props.update({ x = -500, y = 0, z = 0 }, toGame, 0)
  b = shapesLive('board.dae')[1]
  T.check(b and math.abs(b.pos[1] - (4.7 - 500)) < 1e-6,
    'edge: kept as lat / lon, the way out follows the shift too (' .. tostring(b and b.pos[1]) .. ')')
  props.clear()
  ox = 0
  -- no road there: where it was planned
  map = nil
  props.setDressing({ board(100) })
  props.update({ x = 0, y = 0, z = 0 }, toGame, 0)
  b = shapesLive('board.dae')[1]
  T.check(b and math.abs(b.pos[1] - 2.7) < 1e-6, 'edge: no road map there: as planned')
  props.clear()
end

-- 1.4.0 in game (the user, 2026-11-14). 1: an object set from the edge is not moved by a road found there that runs
-- another way (a Y-shaped hairpin's other branch): a road running east under a board on a road running north
do
  ox, oy = 0, 0
  map = { getMap = function()
    local nodes = {}
    for k = -5, 5 do
      nodes['e' .. k] = { pos = { x = k * 20, y = 100, z = 0 }, radius = 7, links = {} }
      if k > -5 then nodes['e' .. k].links['e' .. (k - 1)] = {} end
    end
    return { nodes = nodes }
  end }
  props.setDressing({ one('board', 100, 2.7, { ex = 1, ey = 0, eo = 2.7, eh = 3 }) })
  props.update({ x = 0, y = 0, z = 0 }, toGame, 0)
  local b = shapesLive('board.dae')[1]
  T.check(b and math.abs(b.pos[1] - 2.7) < 1e-6,
    'edge: a road across the object\'s road there (90 degrees off): not moved by its width (' .. tostring(b and b.pos[1]) .. ')')
  props.clear()
  -- 25 degrees off is still its road
  map = { getMap = function()
    local nodes = {}
    local dx, dy = math.sin(math.rad(25)), math.cos(math.rad(25))
    for k = 0, 20 do
      nodes['n' .. k] = { pos = { x = dx * (k * 20 - 200), y = 100 + dy * (k * 20 - 200), z = 0 }, radius = 5, links = {} }
      if k > 0 then nodes['n' .. k].links['n' .. (k - 1)] = {} end
    end
    return { nodes = nodes }
  end }
  props.setDressing({ one('board', 100, 2.7, { ex = 1, ey = 0, eo = 2.7, eh = 3 }) })
  props.update({ x = 0, y = 0, z = 0 }, toGame, 0)
  b = shapesLive('board.dae')[1]
  T.check(b and b.pos[1] > 3.5, 'edge: a road 25 degrees off still counts: moved out (' .. tostring(b and b.pos[1]) .. ')')
  props.clear()
  map = nil
end

-- 3: a stretched tape put down with its scale along Y, at the origin it was planned at; one of unknown width fitted
-- to the road there (the 8 m model planned, a 10 m road found: the 10 m model stretched to 11.5 m, still centred)
do
  ox, oy = 0, 0
  map = nil
  props.setDressing({ one('tape10', 100, 5.75, { dx = 1, dy = 0, sy = 1.15 }) })
  props.update({ x = 0, y = 0, z = 0 }, toGame, 0)
  local t = shapesLive('tape10.dae')[1]
  T.check(t and t.fields.scale == '1 1.1500 1' and math.abs(t.pos[1] - 5.75) < 1e-6 and math.abs(t.pos[2] - 100) < 1e-6,
    'tape: stretched along its Y, from the planned origin (' .. tostring(t and t.fields.scale) .. ')')
  props.clear()
  props.setDressing({ one('tape8', 100, 4) })
  props.update({ x = 0, y = 0, z = 0 }, toGame, 0)
  t = shapesLive('tape8.dae')[1]
  T.check(t and t.fields.scale == nil, 'tape: a model at its own length has no scale set')
  props.clear()
  local models = { { 6, 'tape6.dae' }, { 8, 'tape8.dae' }, { 10, 'tape10.dae' } }
  -- (an 8 m tape across a side road running north at x = 0, centred on it: origin at x = 4, +Y east)
  local function unknown() return one('tape8', 100, 4, { dx = 1, dy = 0, refit = { len = 8, past = 0.75, models = models } }) end
  local function northRoad(radius)
    map = { getMap = function()
      local nodes = {}
      for k = 0, 20 do
        nodes['n' .. k] = { pos = { x = 0, y = k * 20, z = 0 }, radius = radius, links = {} }
        if k > 0 then nodes['n' .. k].links['n' .. (k - 1)] = {} end
      end
      return { nodes = nodes }
    end }
  end
  northRoad(5)
  props.setDressing({ unknown() })
  props.update({ x = 0, y = 0, z = 0 }, toGame, 0)
  t = shapesLive('tape10.dae')[1]
  T.check(t and #shapesLive('tape8.dae') == 0 and t.fields.scale == '1 1.1500 1' and math.abs(t.pos[1] - 5.75) < 1e-6,
    'tape of unknown width on a 10 m road: the 10 m model stretched to 11.5 m, centred (' ..
    tostring(t and t.pos[1]) .. ')')
  props.clear()
  northRoad(2)
  props.setDressing({ unknown() })
  props.update({ x = 0, y = 0, z = 0 }, toGame, 0)
  t = shapesLive('tape6.dae')[1]
  T.check(t and t.fields.scale == nil and math.abs(t.pos[1] - 3) < 1e-6, 'on a 4 m road: the 6 m model, centred')
  props.clear()
  map = nil
  props.setDressing({ unknown() })
  props.update({ x = 0, y = 0, z = 0 }, toGame, 0)
  t = shapesLive('tape8.dae')[1]
  T.check(t and math.abs(t.pos[1] - 4) < 1e-6, 'no road map there: taken as 6 m, the 8 m model')
  props.clear()
end

-- the ground: a roof 3 m above a dressing object's planned height is not its ground; a control's boards as before
do
  vec3 = vec3 or function(x, y, z) return { x = x, y = y, z = z } end
  castRayStatic = function(o, _, maxd)
    local surf = (o.z > 103) and 103 or 100           -- (a roof at 103 over ground at 100)
    local d = o.z - surf
    if d >= 0 and d <= maxd then return d end
  end
  T.near(props._ground(0, 0, 100, props.DRESS_GROUND_ABOVE_M), 100, 1e-9, 'ground: a dressing object under a roof 3 m up: on the ground')
  T.near(props._ground(0, 0, 100), 103, 1e-9, 'ground: a control\'s board as it always was (up to ~6 m above)')
  T.near(props._ground(0, 0, 100.8, props.DRESS_GROUND_ABOVE_M), 100, 1e-9, 'ground: below the planned height still found')
  props.setDressing({ one('table', 100) })
  props.update({ x = 0, y = 0, z = 100 }, toGame, 0)
  local o = shapesLive('table.dae')[1]
  T.check(o and math.abs(o.pos[3] - 100) < 1e-9, 'ground: a dressing object put down under the roof (' ..
    tostring(o and o.pos[3]) .. ')')
  props.clear()
  castRayStatic = nil
end

-- a shape the game has not: one warning naming it, its objects left out, the rest put down
do
  local asked = {}
  FS = { fileExists = function(_, p) asked[p] = (asked[p] or 0) + 1 return p ~= 'gone.dae' and p ~= 'gone.cdae' end }
  props.setDressing({ one('gone', 100), one('gone', 110), one('here', 120) })
  for _ = 1, 3 do props.update({ x = 0, y = 0, z = 0 }, toGame, 0) end
  T.check(#shapesLive('gone.dae') == 0 and #shapesLive('here.dae') == 1, 'a missing shape: left out, the rest down')
  T.check(logged('gone.dae') == 1, 'a missing shape: one warning naming it (' .. logged('gone.dae') .. ')')
  T.check(asked['gone.dae'] == 1, 'a missing shape: looked for once')
  props.setDressing({ one('fine', 100) })
  FS = { fileExists = function(_, p) return p == 'fine.cdae' end }
  props.update({ x = 0, y = 0, z = 0 }, toGame, 0)
  T.check(#shapesLive('fine.dae') == 1, 'a shape the game has only as its .cdae: there')
  FS = nil
  props.clear()
end

-- toGeo giving no lat / lon for an object: said in the log, not dropped silently
do
  logs = {}
  local n = props.setDressing({ one('tape', 100), one('tape', 200) }, function(x, y, z)
    if y > 150 then return nil end
    return x, y, z
  end)
  T.check(n == 1 and logged('1 object(s) of the stage left out') == 1, 'toGeo nil: the object left out and said (' ..
    table.concat(logs, ' | ') .. ')')
  props.clear()
end

-- a Lua reload (Ctrl+L): the next load sweeps the group, the dressing's objects with it
do
  -- (the stand-in group keeps its objects and takes them with it, as a SimGroup's delete does)
  local plainCreate = createObject
  function createObject(class)
    local o = plainCreate(class)
    if class == 'SimGroup' then
      o.kids = {}
      function o:addObject(c) self.kids[#self.kids + 1] = c end
      function o:delete()
        for _, c in ipairs(self.kids) do c:delete() end
        live[self.id] = nil
        for k, v in pairs(named) do if v == self then named[k] = nil end end
      end
    end
    return o
  end
  local g = named[props.GROUP]
  if g then g:delete() end
  named[props.GROUP] = nil
  props.setDressing({ one('tape', 100), one('board', 120) })
  props.update({ x = 0, y = 0, z = 0 }, toGame, 0)
  T.check(liveCount() == 2, 'sweep: the dressing down')
  props.sweep()
  T.check(liveCount() == 0, 'sweep: a reload takes the dressing\'s objects away with the group')
  props.clear()
  createObject = plainCreate
end

-- the showcase: one of each dressing shape, in order, through the real sites' code; taken away again
do
  local D2 = require('earthRally/dressing')
  logs = {}
  local rows = D2.showcase(100, 200, 0, 0, 1)
  local seen, ok = {}, #rows == #D2.SHOWCASE
  for i, r in ipairs(rows) do
    if r.key ~= D2.SHOWCASE[i] or seen[r.key] or not r.label:find(r.key, 1, true) then ok = false end
    seen[r.key] = true
  end
  T.check(ok, 'showcase: one of each shape, in the listed order, each labelled (' .. #rows .. ')')
  local allShapes = true
  for k in pairs(D2.SHAPES) do if not seen[k] then allShapes = false print('showcase: no ' .. k) end end
  T.check(allShapes, 'showcase: every shape the dressing uses is in it')
  -- left to right as the car sees them (facing north: x rising), 15 m ahead
  local inOrder = true
  for i = 2, #rows do
    local a, b = rows[i - 1].object, rows[i].object
    if b.x < a.x - 1e-6 and rows[i].key ~= 'gazeboCover' then inOrder = false end
  end
  T.check(inOrder, 'showcase: left to right')
  T.near(rows[4].object.y, 215, 1e-6, 'showcase: 15 m ahead of the car')
  -- turned by the same code as a real site: an arrow board's +Y is the road's left, a signboard's along the road
  T.check(math.abs(rows[4].object.dx + 1) < 1e-9 and math.abs(rows[12].object.dy - 1) < 1e-9,
    'showcase: an arrow board and a signboard turned as on a stage driven north')
  local n = props.showcase(rows, 0)
  T.check(n == #rows and liveCount() == #rows, 'showcase: put down at once (' .. n .. ')')
  local q = props._yawQuat(rows[4].object.dx, rows[4].object.dy)
  local hit = false
  for _, o in pairs(live) do
    if o.fields.shapeName == rows[4].object.shape and math.abs(o.q[3] - q[3]) < 1e-6 and math.abs(o.q[4] - q[4]) < 1e-6 then
      hit = true
    end
  end
  T.check(hit, 'showcase: the arrow board\'s turn the one a site\'s gets')
  props.clear()
  T.check(liveCount() == #rows, 'showcase: not taken away with a stage')
  props.clearShowcase()
  T.check(liveCount() == 0, 'showcase: cleared')
end
T.done('test_props')
