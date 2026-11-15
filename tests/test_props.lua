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
  -- a board on the right of a road running north, planned 4 m out (1 m past the edge) against a half width of 3
  local function board(along) return one('board', along, 4, { ex = 1, ey = 0, eo = 4, eh = 3 }) end
  props.setDressing({ board(100), one('tape', 120, 2.7) })
  props.update({ x = 0, y = 0, z = 0 }, toGame, 0)
  local b, t = shapesLive('board.dae')[1], shapesLive('tape.dae')[1]
  T.check(b and math.abs(b.pos[1] - 6) < 1e-6 and math.abs(b.pos[2] - 100) < 1e-6,
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
  T.check(b and math.abs(b.pos[1] - (6 - 500)) < 1e-6,
    'edge: kept as lat / lon, the way out follows the shift too (' .. tostring(b and b.pos[1]) .. ')')
  props.clear()
  ox = 0
  -- no road there: where it was planned
  map = nil
  props.setDressing({ board(100) })
  props.update({ x = 0, y = 0, z = 0 }, toGame, 0)
  b = shapesLive('board.dae')[1]
  T.check(b and math.abs(b.pos[1] - 4) < 1e-6, 'edge: no road map there: as planned')
  props.clear()
end

-- 1.4.0 in game (the user, 2026-11-14). 1: an object set from the edge is not moved by a road found there that runs
-- another way (a Y-shaped hairpin's other branch): a road running east, 7 m half wide, under a board on a road running
-- north. (1.6.0, review round 4: not moved out by its width; then, as it stands on that road and no push clears a road
-- running across, slid along the stage: 5 m, then pushed on 2.5 m away from that road's centre, 7.5 m off it clearing
-- its 7 + 0.3 m)
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
  props.setDressing({ one('board', 100, 4, { ex = 1, ey = 0, eo = 4, eh = 3 }) })
  props.update({ x = 0, y = 0, z = 0 }, toGame, 0)
  local b = shapesLive('board.dae')[1]
  T.check(b and math.abs(b.pos[1] - 4) < 1e-6 and math.abs(b.pos[2] - 107.5) < 1e-6,
    'edge: a road across the object\'s road there (90 degrees off): not moved by its width, slid off it along the ' ..
    'stage (' .. tostring(b and b.pos[1]) .. ', ' .. tostring(b and b.pos[2]) .. ')')
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
  props.setDressing({ one('board', 100, 4, { ex = 1, ey = 0, eo = 4, eh = 3 }) })
  props.update({ x = 0, y = 0, z = 0 }, toGame, 0)
  b = shapesLive('board.dae')[1]
  -- (1 m past that road's edge, square to it: 6 m from its centre line)
  T.check(b and math.abs(b.pos[1] - 6 / math.cos(math.rad(25))) < 1e-6,
    'edge: a road 25 degrees off still counts: moved out to 1 m past its edge (' .. tostring(b and b.pos[1]) .. ')')
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

------------------------------------------------------------------------------------------ review round 2
-- (a straight road-map road through (px, py) running at `deg` (clockwise from north), its nodes in game coordinates
-- of the moment: they move with a world shift)
local function straightRoad(px, py, deg, radius)
  local dx, dy = math.sin(math.rad(deg)), math.cos(math.rad(deg))
  return function()
    local nodes = {}
    for k = 0, 20 do
      local d = k * 20 - 200
      nodes['s' .. k] = { pos = { x = px + dx * d - ox, y = py + dy * d - oy, z = 0 }, radius = radius, links = {} }
      if k > 0 then nodes['s' .. k].links['s' .. (k - 1)] = {} end
    end
    return nodes
  end
end
local function mapOf(...)
  local fs = { ... }
  map = { getMap = function()
    -- (node names made unique per road; links follow)
    local out = {}
    for _, f in ipairs(fs) do
      local tag = tostring(f)
      for k, v in pairs(f()) do
        local links = {}
        for l in pairs(v.links) do links[l .. '/' .. tag] = {} end
        out[k .. '/' .. tag] = { pos = v.pos, radius = v.radius, links = links }
      end
    end
    return { nodes = out }
  end }
end
local models = { { 6, 'tape6.dae' }, { 8, 'tape8.dae' }, { 10, 'tape10.dae' } }
-- (an 8 m tape of unknown width across a side road running north at x = 0, centred on it: origin at x = 4, +Y east)
local function unknownTape(extra)
  local o = { dx = 1, dy = 0, refit = { len = 8, past = 0.75, models = models } }
  for k, v in pairs(extra or {}) do o[k] = v end
  return one('tape8', 100, 4, o)
end

-- 1. refitTape held to the plan's maxLen: a 10 m side road would take 11.5 m, the stage road 9 m allows: the 8 m
-- model stretched to 9 m, still centred
do
  ox, oy = 0, 0
  mapOf(straightRoad(0, 100, 0, 5))
  props.setDressing({ unknownTape({ maxLen = 9 }) })
  props.update({ x = 0, y = 0, z = 0 }, toGame, 0)
  local t = shapesLive('tape8.dae')[1]
  T.check(t and #shapesLive('tape10.dae') == 0 and t.fields.scale == '1 1.1250 1' and math.abs(t.pos[1] - 4.5) < 1e-6,
    'refit: held to maxLen 9 m, the 8 m model stretched to it, centred (' .. tostring(t and t.fields.scale) .. ', ' ..
    tostring(t and t.pos[1]) .. ')')
  props.clear()
  map = nil
end

-- 2. refitTape on a 19 m road: 20.5 m of tape, two overlapping 10 m pieces stretched 1.05 (not one stretched 2.05),
-- both put down again with their scale after a world shift
do
  ox, oy = 0, 0
  mapOf(straightRoad(0, 100, 0, 9.5))
  props.setDressing({ unknownTape() }, toGeo)
  props.update({ x = 0, y = 0, z = 0 }, toGame, 0)
  local function check(how, shift)
    local ts = shapesLive('tape10.dae')
    table.sort(ts, function(a, b) return a.pos[1] < b.pos[1] end)
    T.check(#ts == 2 and ts[1].fields.scale == '1 1.0500 1' and ts[2].fields.scale == '1 1.0500 1' and
      math.abs(ts[1].pos[1] - (0.25 - shift)) < 1e-6 and math.abs(ts[2].pos[1] - (10.25 - shift)) < 1e-6,
      how .. ': two pieces of the 10 m tape, each stretched 1.05, from either end (' .. #ts .. ', ' ..
      tostring(ts[1] and ts[1].fields.scale) .. ')')
  end
  check('refit on a 19 m road', 0)
  ox = 500
  props.reset()
  props.update({ x = -500, y = 0, z = 0 }, toGame, 0)
  check('after a world shift', 500)
  props.clear()
  ox = 0
  map = nil
end

-- 3. An object flagged offRoad (a bale, spectator tape, fence) left out where the road map has a road under it,
-- whichever way it runs; kept beside it, with nothing flagged, and with no road map
do
  ox, oy = 0, 0
  mapOf(straightRoad(0, 100, 90, 3))      -- (a road running east along y = 100, 3 m half wide)
  props.setDressing({ one('bale', 101, 10, { offRoad = true }), one('fence', 105, 10, { offRoad = true }),
    one('table', 101, 20) })
  props.update({ x = 0, y = 0, z = 0 }, toGame, 0)
  T.check(#shapesLive('bale.dae') == 0, 'offRoad: a bale on a road the plan did not know: left out')
  T.check(#shapesLive('fence.dae') == 1, 'offRoad: 5 m off a 3 m half wide road: put down')
  T.check(#shapesLive('table.dae') == 1, 'offRoad: an object not flagged: put down')
  props.clear()
  map = nil
  props.setDressing({ one('bale', 101, 10, { offRoad = true }) })
  props.update({ x = 0, y = 0, z = 0 }, toGame, 0)
  T.check(#shapesLive('bale.dae') == 1, 'offRoad: no road map: put down')
  props.clear()
end

-- 4. The edge shift only from the stage's own road, found by position: a Y branch 15 degrees off whose centre line
-- is 6 m from the planned stage-line point moves nothing; the stage road at a tight apex, 40 degrees off the
-- tangent but through the point, does. (1.6.0, review round 4: the branch, 5 m half wide, covers the board, so it is
-- then pushed off it -- away from the branch's nearest point, not out along the way out, which crosses the branch;
-- with the stage road there too, that push meets the stage road, and the board is slid along the stage instead)
do
  ox, oy = 0, 0
  local function board() return one('board', 100, 4, { ex = 1, ey = 0, eo = 4, eh = 3 }) end
  local c15, s15 = math.cos(math.rad(15)), math.sin(math.rad(15))
  local bx0 = 6 / c15                     -- (the branch's centre line crosses y = 100 here)
  -- (how far (x, y) is from the branch's centre line)
  local function offBranch(x, y) return math.abs((x - (bx0 + (y - 100) * s15 / c15)) * c15) end
  mapOf(straightRoad(bx0, 100, 15, 5))
  props.setDressing({ board() })
  props.update({ x = 0, y = 0, z = 0 }, toGame, 0)
  local b = shapesLive('board.dae')[1]
  -- (2.13 m from the branch's line, 5.3 needed: 3.5 m in 0.5 m steps square to the branch, away from it)
  local ex, ey = 4 - 3.5 * c15, 100 + 3.5 * s15
  T.check(b and math.abs(b.pos[1] - ex) < 1e-6 and math.abs(b.pos[2] - ey) < 1e-6,
    'edge: a Y branch 15 degrees off, 6 m away: not moved by its width, pushed off it away from it (' ..
    tostring(b and b.pos[1]) .. ', ' .. tostring(b and b.pos[2]) .. ')')
  props.clear()
  mapOf(straightRoad(0, 100, 0, 3), straightRoad(bx0, 100, 15, 5))
  props.setDressing({ board() })
  props.update({ x = 0, y = 0, z = 0 }, toGame, 0)
  b = shapesLive('board.dae')[1]
  T.check(b and math.abs(b.pos[1]) >= 3.3 - 1e-6 and offBranch(b.pos[1], b.pos[2]) >= 5.3 - 1e-6 and
    math.abs(b.pos[2] - 100) > 4.9, 'edge: the same with the stage road there: slid along the stage until clear of ' ..
    'both (' .. tostring(b and b.pos[1]) .. ', ' .. tostring(b and b.pos[2]) .. ')')
  props.clear()
  mapOf(straightRoad(0, 100, 40, 5))
  props.setDressing({ board() })
  props.update({ x = 0, y = 0, z = 0 }, toGame, 0)
  b = shapesLive('board.dae')[1]
  T.check(b and math.abs(b.pos[1] - 6 / math.cos(math.rad(40))) < 1e-6,
    'edge: the stage road at a tight apex, 40 degrees off: moved out to 1 m past its edge (' ..
    tostring(b and b.pos[1]) .. ')')
  props.clear()
  map = nil
end

-- 5. 1.6.0's note 6 (a roadside marshal on the road at Weaver Bend): the stage line off the road map's centre is
-- allowed for, not only the road's width -- the road's centre 1.5 m right of the line (towards the board), and 3 m
-- (beyond the 2 m looked within until then); a road 70 degrees off is not the stage's
do
  ox, oy = 0, 0
  local function board() return one('board', 100, 4, { ex = 1, ey = 0, eo = 4, eh = 3 }) end
  mapOf(straightRoad(1.5, 100, 0, 3))
  props.setDressing({ board() })
  props.update({ x = 0, y = 0, z = 0 }, toGame, 0)
  local b = shapesLive('board.dae')[1]
  T.check(b and math.abs(b.pos[1] - 5.5) < 1e-6, 'edge: the line 1.5 m off the road\'s centre towards the board: ' ..
    'the board still 1 m past the real edge (' .. tostring(b and b.pos[1]) .. ')')
  props.clear()
  mapOf(straightRoad(-1.5, 100, 0, 3))
  props.setDressing({ board() })
  props.update({ x = 0, y = 0, z = 0 }, toGame, 0)
  b = shapesLive('board.dae')[1]
  -- (review round 4: the line's offset only ever moves an object out -- on a bend the road map's chord lies inside the
  -- road -- so here the width alone: 3 against 3, not moved)
  T.check(b and math.abs(b.pos[1] - 4) < 1e-6, 'edge: the line 1.5 m off the other way: not brought in (' ..
    tostring(b and b.pos[1]) .. ')')
  props.clear()
  mapOf(straightRoad(3, 100, 0, 3))
  props.setDressing({ board() })
  props.update({ x = 0, y = 0, z = 0 }, toGame, 0)
  b = shapesLive('board.dae')[1]
  T.check(b and math.abs(b.pos[1] - 7) < 1e-6, 'edge: the road\'s centre 3 m off the line: still found, the board ' ..
    '1 m past its edge (' .. tostring(b and b.pos[1]) .. ')')
  props.clear()
  T.check(props.DRESS_EDGE_NEAR_M == 4 and props.DRESS_EDGE_MAX_DEG == 60, 'edge: looked for within 4 m, 60 degrees')
  map = nil
end

-- 6. The push off the road: a roadside marshal's table, chair and flag (one group) where a short road ends under the
-- table go out together until all three clear it; a group a wide road covers whatever the push is left out, said
-- once in the log; with no road map, as planned
do
  ox, oy = 0, 0
  logs = {}
  local function marshal()
    local site = { kind = 'marshal', along = 100, from = 100, to = 100, objects = {} }
    local function o(shape, x, y, eo, foot)
      site.objects[#site.objects + 1] = { shape = shape, x = x, y = y, dx = 1, dy = 0, ex = 1, ey = 0, eo = eo, eh = 3,
                                          grp = 'marshal', foot = foot }
    end
    o('table.dae', 3.9, 100, 3.9, 0.5)
    o('chair.dae', 4.8, 100, 4.8, 0.3)
    o('flag.dae', 3.9, 101.6, 3.9, 0.2)
    return site
  end
  -- (the stage road north at x = 0, 3 m half wide, and a driveway's end from x = 2 to 5.95 along y = 100, 0.6 m)
  local function drive()
    return { d1 = { pos = { x = 2, y = 100, z = 0 }, radius = 0.6, links = { d2 = {} } },
             d2 = { pos = { x = 5.95, y = 100, z = 0 }, radius = 0.6, links = {} } }
  end
  mapOf(straightRoad(0, 100, 0, 3), drive)
  props.setDressing({ marshal() })
  props.update({ x = 0, y = 0, z = 0 }, toGame, 0)
  local t, c, f = shapesLive('table.dae')[1], shapesLive('chair.dae')[1], shapesLive('flag.dae')[1]
  -- (the table 0.6 + 0.3 + 0.5 = 1.4 m clear of the driveway's end at x = 5.95: at 7.4, a 3.5 m push in 0.5 m steps)
  T.check(t and c and f and math.abs(t.pos[1] - 7.4) < 1e-6 and math.abs(c.pos[1] - 8.3) < 1e-6 and
    math.abs(f.pos[1] - 7.4) < 1e-6, 'push: the whole group out together until the table clears the road (' ..
    tostring(t and t.pos[1]) .. ', ' .. tostring(c and c.pos[1]) .. ', ' .. tostring(f and f.pos[1]) .. ')')
  props.clear()
  -- clear already: not moved
  mapOf(straightRoad(0, 100, 0, 3))
  props.setDressing({ marshal() })
  props.update({ x = 0, y = 0, z = 0 }, toGame, 0)
  t = shapesLive('table.dae')[1]
  T.check(t and math.abs(t.pos[1] - 3.9) < 1e-6, 'push: a group already clear of the road stays where it is')
  props.clear()
  -- a wide road beside the stage covering it however far it goes: the group left out, said once
  mapOf(straightRoad(0, 100, 0, 3), straightRoad(9, 100, 0, 6))
  props.setDressing({ marshal() })
  props.update({ x = 0, y = 0, z = 0 }, toGame, 0)
  T.check(#shapesLive('table.dae') == 0 and #shapesLive('chair.dae') == 0 and #shapesLive('flag.dae') == 0,
    'push: a group no push of 6 m clears: all of it left out')
  T.check(logged('left out: on the road') == 1, 'push: said once in the log (' .. logged('left out: on the road') .. ')')
  props.clear()
  map = nil
  props.setDressing({ marshal() })
  props.update({ x = 0, y = 0, z = 0 }, toGame, 0)
  t = shapesLive('table.dae')[1]
  T.check(t and math.abs(t.pos[1] - 3.9) < 1e-6, 'push: no road map: as planned')
  props.clear()
end

-- 7. 1.6.0's note 8: a junction tape of unknown width planned, then refit at spawn as ONE tape about its true middle
-- and split into pieces there -- on a 19 m side road centred on the plan, two pieces symmetric about the road; on one
-- whose centre is 1.5 m off the plan's middle, re-centred on it
do
  ox, oy = 0, 0
  local D = require('earthRally/dressing')
  -- (the stage north along x = 0; a side road west from (0, 0), of unknown width)
  local pl = D.plan({ line = { { x = 0, y = -100, z = 0 }, { x = 0, y = 100, z = 0 } }, startM = 0, finishM = 200,
    junctions = { { along = 100, x = 0, y = 0, kind = 'straight', inDeg = 0, outDeg = 0, sides = { { deg = 270 } } } } })
  local tapeSite
  for _, s in ipairs(pl) do if s.kind == 'tape' then tapeSite = s end end
  T.check(tapeSite and #tapeSite.objects == 1 and tapeSite.objects[1].refit, 'note 8: the plan gives the tape as one object')
  local function span(sideY)
    mapOf(straightRoad(-50, sideY, 270, 9.5))
    props.setDressing({ tapeSite })
    props.update({ x = 0, y = 0, z = 0 }, toGame, 0)
    local lo, hi, n = math.huge, -math.huge, 0
    for _, o in ipairs(shapesLive(D.SHAPES.tape10)) do
      -- (the tape runs along -Y from its origin; +Y south here, so from the origin north, 10 m x its scale)
      local sy = tonumber((o.fields.scale or '1 1 1'):match('^%S+ (%S+)')) or 1
      lo, hi, n = math.min(lo, o.pos[2]), math.max(hi, o.pos[2] + 10 * sy), n + 1
      T.check(math.abs(o.pos[1] + 8) < 1e-6, 'note 8: each piece across the side road 8 m in')
    end
    props.clear()
    return lo, hi, n
  end
  local lo, hi, n = span(0)
  T.check(n == 2 and math.abs(lo + hi) < 1e-6 and math.abs((hi - lo) - 20.5) < 1e-6,
    'note 8: a two-piece tape on a 19 m side road centred on the plan: symmetric about it, 20.5 m (' ..
    tostring(lo) .. ' .. ' .. tostring(hi) .. ')')
  lo, hi, n = span(1.5)
  T.check(n == 2 and math.abs((lo + hi) / 2 - 1.5) < 1e-6 and math.abs((hi - lo) - 20.5) < 1e-6,
    'note 8: the side road\'s centre 1.5 m off the plan\'s middle: the tape re-centred on it (' ..
    tostring(lo) .. ' .. ' .. tostring(hi) .. ')')
  lo, hi, n = span(3)
  T.check(n == 2 and math.abs(lo + hi) < 1e-6, 'note 8: 3 m off (beyond DRESS_TAPE_CENTRE_M): left about the plan\'s middle')
  map = nil
end

------------------------------------------------------------------------------------------ review round 4

-- 1. The edge shift on a bend: the road map's 30 m chords lie inside the curve the road and the line follow, so the
-- line's offset from a chord must not pull an object on the outside in -- the width alone (3 against 3) leaves it
do
  ox, oy = 0, 0
  local R = 60
  local th = 2 * math.asin(15 / R)                -- (the angle one 30 m chord spans)
  map = { getMap = function()
    local nodes = {}
    for k = -4, 4 do
      nodes['a' .. k] = { pos = { x = R * math.cos(k * th), y = R * math.sin(k * th), z = 0 }, radius = 3, links = {} }
      if k > -4 then nodes['a' .. k].links['a' .. (k - 1)] = {} end
    end
    return { nodes = nodes }
  end }
  -- (midway along a chord, where its sag is deepest: 1.9 m; a board 4 m out from the arc, on the outside)
  local a = th / 2
  local ca, sa = math.cos(a), math.sin(a)
  local site = { kind = 'board', along = 100, from = 100, to = 100, objects = { { shape = 'board.dae',
    x = (R + 4) * ca, y = (R + 4) * sa, dx = -sa, dy = ca, ex = ca, ey = sa, eo = 4, eh = 3 } } }
  props.setDressing({ site })
  props.update({ x = 0, y = 0, z = 0 }, toGame, 0)
  local b = shapesLive('board.dae')[1]
  local r = b and math.sqrt(b.pos[1] ^ 2 + b.pos[2] ^ 2)
  T.check(r and math.abs(r - (R + 4)) < 1e-6, 'bend: an object on the outside of an arc of 30 m chords not pulled ' ..
    'in by the chord\'s sag (' .. tostring(r) .. ')')
  props.clear()
  map = nil
end

-- 2. The push away from the road that covers the group: a side road running east across a roadside marshal's table
-- and flag (straight out along it would never clear it) -- the group pushed north, away from its centre line from
-- the flag, the object it covers most; with the stage road and a wide road beside it as well, nothing clears it and
-- it is left out, said as a warning
do
  ox, oy = 0, 0
  logs = {}
  local function marshal()
    local site = { kind = 'marshal', along = 300, from = 100, to = 100, objects = {} }
    local function o(shape, x, y, eo, foot)
      site.objects[#site.objects + 1] = { shape = shape, x = x, y = y, dx = 0, dy = 1, ex = 1, ey = 0, eo = eo, eh = 3,
                                          grp = 'marshal', foot = foot }
    end
    o('table.dae', 4.5, 100, 4.5, 0.5)
    o('chair.dae', 5.4, 100, 5.4, 0.3)
    o('flag.dae', 4.5, 101.6, 4.5, 0.2)
    return site
  end
  -- (the stage road north at x = 0, 3 m half wide; a side road from it east along y = 101, 2 m half wide)
  local function side()
    local n = {}
    for k = 0, 5 do
      n['w' .. k] = { pos = { x = k * 20, y = 101, z = 0 }, radius = 2, links = {} }
      if k > 0 then n['w' .. k].links['w' .. (k - 1)] = {} end
    end
    return n
  end
  mapOf(straightRoad(0, 100, 0, 3), side)
  props.setDressing({ marshal() })
  props.update({ x = 0, y = 0, z = 0 }, toGame, 0)
  local t, c, f = shapesLive('table.dae')[1], shapesLive('chair.dae')[1], shapesLive('flag.dae')[1]
  -- (the flag 0.6 m north of the side road's line, the table 1 m south of it needing 2.8: 4 m north in 0.5 m
  -- steps, the group with it)
  T.check(t and c and f and math.abs(t.pos[1] - 4.5) < 1e-6 and math.abs(t.pos[2] - 104) < 1e-6 and
    math.abs(c.pos[2] - 104) < 1e-6 and math.abs(f.pos[2] - 105.6) < 1e-6,
    'push: a side road across the group: pushed away from its centre line, not out along it (' ..
    tostring(t and t.pos[1]) .. ', ' .. tostring(t and t.pos[2]) .. ')')
  props.clear()
  mapOf(straightRoad(0, 100, 0, 3), straightRoad(9, 100, 0, 6))
  props.setDressing({ marshal() })
  props.update({ x = 0, y = 0, z = 0 }, toGame, 0)
  T.check(#shapesLive('table.dae') == 0 and logged('W stage dressing: the marshal at 300 m') == 1,
    'push: nothing clears it, slides too: left out, said once as a warning')
  props.clear()
  map = nil
end

-- 3. The ground of an object moved off its planned spot: looked for higher the further it moved (an edge shift of
-- 2 m onto a bank 3 m up: found, where 2 m above was the limit); one moved with no ground found is left out, one not
-- moved is still put down at its planned height
do
  ox, oy = 0, 0
  castRayStatic = function(o, _, maxd)
    local surf = o.x > 5 and 103 or 100              -- (a bank 3 m up beyond x = 5)
    local d = o.z - surf
    if d >= 0 and d <= maxd then return d end
  end
  mapOf(straightRoad(0, 100, 0, 5))
  props.setDressing({ one('board', 100, 4, { ex = 1, ey = 0, eo = 4, eh = 3, z = 100 }) })
  props.update({ x = 0, y = 0, z = 100 }, toGame, 0)
  local b = shapesLive('board.dae')[1]
  T.check(b and math.abs(b.pos[1] - 6) < 1e-6 and math.abs(b.pos[3] - 103) < 1e-9,
    'ground: moved 2 m out onto a bank 3 m up: stood on it (' .. tostring(b and b.pos[3]) .. ')')
  props.clear()
  map = nil
  -- (not moved: the bank 3 m up is still not its ground, as before -- the planned height kept)
  props.setDressing({ one('board', 100, 6, { ex = 1, ey = 0, eo = 6, eh = 3, z = 100 }) })
  props.update({ x = 0, y = 0, z = 100 }, toGame, 0)
  b = shapesLive('board.dae')[1]
  T.check(b and math.abs(b.pos[3] - 100) < 1e-9, 'ground: not moved, the bank above its limit: at the planned height')
  props.clear()
  castRayStatic = function() return nil end
  mapOf(straightRoad(0, 100, 0, 5))
  props.setDressing({ one('board', 100, 4, { ex = 1, ey = 0, eo = 4, eh = 3, z = 100 }), one('table', 120, 4) })
  props.update({ x = 0, y = 0, z = 100 }, toGame, 0)
  T.check(#shapesLive('board.dae') == 0, 'ground: moved, and no ground found: left out, not hung at the planned height')
  T.check(#shapesLive('table.dae') == 1, 'ground: not moved, no ground found: at the planned height, as before')
  props.clear()
  map = nil
  castRayStatic = nil
end

-- 4. The tape re-centred: only the end the move takes past the plan's maxLen cut back (a side road 3 m half wide,
-- its centre 1.5 m off the plan's middle, maxLen 9: the 8 m model from 3.5 m on one side of the plan's middle to
-- 4.5 m on the other, 0.75 m past the far edge, where shortening both ends by twice the move left the 6 m model,
-- ending right at the far edge); and the crossing found along the side road's own way, not square to it (a side road
-- 30 degrees off square, crossing the tape's line 1 m from the middle)
do
  ox, oy = 0, 0
  mapOf(straightRoad(1.5, 100, 0, 3))
  props.setDressing({ unknownTape({ maxLen = 9 }) })
  props.update({ x = 0, y = 0, z = 0 }, toGame, 0)
  local t = shapesLive('tape8.dae')[1]
  T.check(t and #shapesLive('tape6.dae') == 0 and t.fields.scale == nil and math.abs(t.pos[1] - 4.5) < 1e-6,
    'refit: re-centred against maxLen, only the end beyond it cut back: the 8 m model to 4.5 m (' ..
    tostring(t and t.pos[1]) .. ')')
  props.clear()
  mapOf(straightRoad(1, 100, 30, 3))
  props.setDressing({ unknownTape() })
  props.update({ x = 0, y = 0, z = 0 }, toGame, 0)
  t = shapesLive('tape8.dae')[1]
  T.check(t and math.abs(t.pos[1] - 5) < 1e-6, 'refit: a side road 30 degrees off square: centred where it crosses ' ..
    'the tape (' .. tostring(t and t.pos[1]) .. ')')
  props.clear()
  map = nil
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
