-- The junctions along a stage (earthRally/junctions) with their side roads: the bearings, the one rule (M.branch,
-- M.judge) judged through the auto recce's road-graph finder (autoRecce.junctions) on roads running every way, the
-- matched file's format 1 and format 2 entries read back through events.lua, and a file's junctions placed in order
-- on the line. (The live road map's finder and its merge with the file were dropped in 1.4.0, the user, 2026-11-14.)
-- No BeamNG.
local T = dofile(TESTS .. '/testlib.lua')

local files = {}
function jsonWriteFile(path, data) files[path] = data return true end
function jsonReadFile(path) return files[path] end
FS = {
  fileExists = function(_, path) return files[path] ~= nil end,
  findFiles = function() return {} end,
}
function log() end

local J = require('earthRally/junctions')
local events = require('earthRally/events')
local auto = require('earthRally/autoRecce')
local geo = require('earthRally/geo')

-- (the test's own compass, not the module's: the module's is what is being checked)
local function dirOf(b) local r = math.rad(b) return math.sin(r), math.cos(r) end
local function angDiff(a, b) local d = math.abs((a - b) % 360) return math.min(d, 360 - d) end
local function nearDeg(a, b, eps, name)
  T.check(type(a) == 'number' and angDiff(a, b) <= eps, string.format('%s (%s vs %s)', name, tostring(a), tostring(b)))
end

------------------------------------------------------------------------------------------ 1: bearings

do
  local cases = { { 0, 1, 0, 'north' }, { 1, 0, 90, 'east' }, { 0, -1, 180, 'south' }, { -1, 0, 270, 'west' },
                  { 1, 1, 45, 'north-east' }, { 1, -1, 135, 'south-east' }, { -1, -1, 225, 'south-west' },
                  { -1, 1, 315, 'north-west' } }
  for _, c in ipairs(cases) do
    T.near(J.dirToBearing(c[1] * 7, c[2] * 7), c[3], 1e-9, 'a road heading ' .. c[4] .. ' is ' .. c[3] .. ' degrees')
    local dx, dy = J.bearingToDir(c[3])
    local l = math.sqrt(c[1] * c[1] + c[2] * c[2])
    T.check(math.abs(dx - c[1] / l) < 1e-9 and math.abs(dy - c[2] / l) < 1e-9,
      c[3] .. ' degrees back to a unit direction ' .. c[4])
  end
  local worst = 0
  for b = 0, 359.5, 7.5 do
    local dx, dy = J.bearingToDir(b)
    worst = math.max(worst, angDiff(J.dirToBearing(dx, dy), b))
  end
  T.check(worst < 1e-9, 'every bearing there and back (worst ' .. worst .. ')')
  T.check(J.dirToBearing(0, 0) == nil, 'no direction, no bearing')
  local b = J.dirToBearing(-1e-9, 1)
  T.check(b >= 0 and b < 360, 'just west of north is just under 360, never negative (' .. b .. ')')
  T.near(J.turnDeg(350, 10), 20, 1e-9, 'from 350 to 10 is 20 degrees right')
  T.near(J.turnDeg(10, 350), -20, 1e-9, 'and back is 20 left')
end

------------------------------------------------------------------------------------------ the stand-in road map

-- A road map as map.getMap().nodes: a node every STEP m along each road; roads meet at a shared node by name.
local STEP = 5
local function newMap() return {} end
local function node(nodes, name, x, y, radius)
  if not nodes[name] then nodes[name] = { pos = { x = x, y = y, z = 50 }, radius = radius, links = {} } end
  return name
end
local function link(nodes, a, b, oneWay)
  nodes[a].links[b] = { drivability = 1 }
  if not oneWay then nodes[b].links[a] = { drivability = 1 } end
end
-- a road from node `from` heading bearing b for len m (its first node `from`), half width radius
local function road(nodes, prefix, from, b, len, radius, oneWay)
  local p = nodes[from].pos
  local dx, dy = dirOf(b)
  local prev = from
  for d = STEP, len, STEP do
    local n = node(nodes, prefix .. d, p.x + dx * d, p.y + dy * d, radius)
    link(nodes, prev, n, oneWay)
    prev = n
  end
end

-- The stage's line, game coordinates, a point every 4 m: legs of { bearing, metres } from p0.
local function line(p0, legs)
  local out = { { x = p0.x, y = p0.y, z = 50 } }
  local x, y = p0.x, p0.y
  for _, leg in ipairs(legs) do
    local dx, dy = dirOf(leg[1])
    local n = math.floor(leg[2] / 4 + 0.5)
    for k = 1, n do out[#out + 1] = { x = x + dx * leg[2] * k / n, y = y + dy * leg[2] * k / n, z = 50 } end
    x, y = x + dx * leg[2], y + dy * leg[2]
  end
  return out
end

local J0 = { x = 1200, y = -800 }       -- (the junction away from the origin: nothing here is at 0, 0)

-- A junction scene at rotation rot (every bearing turned by rot): the junction node J, the stage's own roads in
-- and out, the side roads { bearing, len, radius }. Returns the map and the stage line through it (200 m in, 200 m
-- out).
local function scene(rot, inB, outB, sides, opts)
  opts = opts or {}
  local nodes = newMap()
  node(nodes, 'J', J0.x, J0.y, 4.0)
  -- the road the stage comes in on runs back from J, the opposite way to its travel
  road(nodes, 'in', 'J', (inB + 180 + rot) % 360, 250, 4.0)
  road(nodes, 'out', 'J', (outB + rot) % 360, 250, 4.0)
  for i, s in ipairs(sides) do road(nodes, 'side' .. i .. '_', 'J', (s[1] + rot) % 360, s[2], s[3], opts.oneWay) end
  local dx, dy = dirOf((inB + rot) % 360)
  local p0 = { x = J0.x - dx * 200, y = J0.y - dy * 200 }
  return nodes, line(p0, { { (inB + rot) % 360, 200 }, { (outB + rot) % 360, 200 } })
end

local function sideDegs(j)
  local out = {}
  for _, s in ipairs(j and j.sides or {}) do out[#out + 1] = s.deg end
  table.sort(out)
  return out
end
local function hasSide(j, b, eps)
  for _, s in ipairs(j and j.sides or {}) do if angDiff(s.deg, b) <= (eps or 2) then return s end end
  return nil
end

-- The junctions the auto recce finds on a scene's road map (made a road graph in lat / lon: BeamNG.Earth's frame is
-- east / north, so the game's x, y and the auto recce's stage frame are the same directions), along the line.
local function found(nodes, ln)
  local fr = auto.frame(47.0, -123.0)
  local graph = { nodes = {}, edges = {} }
  for name, n in pairs(nodes) do
    local la, lo = fr.latlon(n.pos.x, n.pos.y)
    graph.nodes[name] = { lat = la, lon = lo, alt = 50, radius = n.radius }
    for o in pairs(n.links) do if name < o then graph.edges[#graph.edges + 1] = { name, o } end end
  end
  local kml = {}
  for i, p in ipairs(ln) do kml[i] = { x = p.x, y = p.y } end
  local gr = auto.build(graph, kml, fr)
  local res, resAlong = auto.resample(kml, auto.OUT_STEP_M)
  local flags = {}
  for k = 1, #res do flags[k] = 0 end
  return auto.junctions(gr, res, resAlong, flags)
end

------------------------------------------------------------------------------------------ 2: the rule, every way

local bad = { cross = 0, fork = 0, straight = 0, tee = 0 }
for rot = 0, 315, 45 do
  local tag = ' (turned ' .. rot .. ')'
  -- a crossroads, the stage turning right: in heading north, out heading east; straight on and left are side roads
  do
    local nodes, ln = scene(rot, 0, 90, { { 0, 120, 3.0 }, { 270, 120, 2.5 } })
    local js = found(nodes, ln)
    local j = js[1]
    local ok = #js == 1 and j.kind == 'turn' and j.side == '' and angDiff(j.inDeg, rot) < 1 and
      angDiff(j.outDeg, 90 + rot) < 1 and #j.sides == 2 and hasSide(j, rot) and hasSide(j, 270 + rot)
    if not ok then bad.cross = bad.cross + 1 print('crossroads' .. tag, #js, j and j.kind, j and j.inDeg, j and j.outDeg,
      table.concat(sideDegs(j), ' ')) end
    if rot == 0 then
      T.near(j and j.along or 0, 200, 0.5, 'the crossroads 200 m along')
      T.near(hasSide(j, 0) and hasSide(j, 0).halfW or 0, 3.0, 1e-9, 'straight on: its half width from the node radius')
      T.near(hasSide(j, 270) and hasSide(j, 270).halfW or 0, 2.5, 1e-9, 'left: its own half width')
    end
  end
  -- a fork, keep left: in north, out at 350, the other road at 15
  do
    local nodes, ln = scene(rot, 0, 350, { { 15, 120, 3.0 } })
    local j = found(nodes, ln)[1]
    local ok = j and j.kind == 'fork' and j.side == 'left' and #j.sides == 1 and hasSide(j, 15 + rot)
    if not ok then bad.fork = bad.fork + 1 print('fork' .. tag, j and j.kind, j and j.side) end
  end
  -- straight on past a side road to the west
  do
    local nodes, ln = scene(rot, 0, 0, { { 270, 100, 2.0 } })
    local j = found(nodes, ln)[1]
    local ok = j and j.kind == 'straight' and j.side == '' and #j.sides == 1 and hasSide(j, 270 + rot) and
      angDiff(j.inDeg, rot) < 1 and angDiff(j.outDeg, rot) < 1
    if not ok then bad.straight = bad.straight + 1 print('straight' .. tag, j and j.kind) end
  end
  -- a T-junction, the stage turning left: the road it comes in on ends there; right is the one side road
  do
    local nodes, ln = scene(rot, 0, 270, { { 90, 150, 3.0 } })
    local j = found(nodes, ln)[1]
    local ok = j and j.kind == 'turn' and #j.sides == 1 and hasSide(j, 90 + rot) and angDiff(j.outDeg, 270 + rot) < 1
    if not ok then bad.tee = bad.tee + 1 print('tee' .. tag, j and j.kind) end
  end
end
T.check(bad.cross == 0, 'a crossroads turn right: turn, in / out, straight on and left taped, every way (' .. bad.cross .. ' wrong)')
T.check(bad.fork == 0, 'a fork, keep left, every way (' .. bad.fork .. ' wrong)')
T.check(bad.straight == 0, 'straight past a side road, every way (' .. bad.straight .. ' wrong)')
T.check(bad.tee == 0, 'a T-junction turn left, the one side road right, every way (' .. bad.tee .. ' wrong)')

-- the mirror: keep right
do
  local nodes, ln = scene(0, 0, 10, { { 345, 120, 3.0 } })
  local j = found(nodes, ln)[1]
  T.check(j and j.kind == 'fork' and j.side == 'right', 'a fork, keep right (' .. tostring(j and j.side) .. ')')
end

------------------------------------------------------------------------------------------ 3: what is no junction

do
  -- a 30 m stub (a driveway): no junction at all
  local nodes, ln = scene(0, 0, 0, { { 90, 30, 2.0 } })
  T.check(#found(nodes, ln) == 0, 'a side road under 40 m is no junction')
  -- a stub and a real side road: only the real one is a side road
  nodes, ln = scene(0, 0, 0, { { 90, 30, 2.0 }, { 270, 100, 2.0 } })
  local j = found(nodes, ln)[1]
  T.check(j and #j.sides == 1 and hasSide(j, 270), 'with a real side road too: the stub is left out (' ..
    table.concat(sideDegs(j), ' ') .. ')')
  -- the line 3 m off the junction node: not on it
  nodes = newMap()
  node(nodes, 'J', J0.x, J0.y, 4.0)
  road(nodes, 'a', 'J', 180, 250, 4.0)
  road(nodes, 'b', 'J', 0, 250, 4.0)
  road(nodes, 'c', 'J', 270, 100, 4.0)
  ln = line({ x = J0.x + 3, y = J0.y - 200 }, { { 0, 400 } })
  T.check(#found(nodes, ln) == 0, 'a node 3 m off the line is not on it')
end

-- two junctions 10 m apart along the stage: one (JUNCTION_GAP_M)
do
  local nodes = newMap()
  node(nodes, 'S', J0.x, J0.y - 300, 4.0)
  road(nodes, 'm', 'S', 0, 600, 4.0)
  road(nodes, 'x', 'm300', 270, 100, 3.0)
  road(nodes, 'y', 'm310', 90, 100, 3.0)
  road(nodes, 'z', 'm400', 90, 100, 3.0)
  local ln = line({ x = J0.x, y = J0.y - 300 }, { { 0, 600 } })
  local js = found(nodes, ln)
  T.check(#js == 2, 'side roads 10 m apart are one junction, one 90 m on another (' .. #js .. ')')
  T.near(js[1] and js[1].along or 0, 300, 0.5, 'the first where the first side road leaves')
  T.near(js[2] and js[2].along or 0, 400, 0.5, 'the second 100 m on')
end

------------------------------------------------------------------------------------------ 4: the file

do
  -- format 2, through encode and back
  local rec = { kind = 'turn', side = '', inDeg = 359.97, outDeg = 90.04,
                sides = { { deg = 0.0, halfW = 3.04 }, { deg = 270.0 } } }
  local e = J.encode(rec, 47.1, -123.2)
  T.check(#e == 8 and e[3] == 'turn' and e[4] == '' and e[8] == 0,
    'format 2: [lat, lon, kind, side, inDeg, outDeg, sides, half], the stage road\'s half width 0 when not known')
  rec.half = 3.46
  local e8 = J.encode(rec, 47.1, -123.2)
  T.check(e8[8] == 3.5 and J.decode(e8).half == 3.5, 'the stage road\'s half width to 0.1 m, read back')
  local e7 = { e8[1], e8[2], e8[3], e8[4], e8[5], e8[6], e8[7] }
  T.check(J.decode(e7) and J.decode(e7).half == nil and #J.decode(e7).sides == 2,
    'a seven-entry format 2 entry (before the eighth) still reads, with no half width')
  rec.half = nil
  T.check(e[5] == 0 and e[6] == 90, 'bearings to 0.1 degree, 359.97 written as 0 (' .. e[5] .. ', ' .. e[6] .. ')')
  T.check(e[7][1][2] == 3 and e[7][2][2] == 0, 'a half width to 0.1 m, an unknown one as 0 (never null)')
  local d = J.decode(e)
  T.check(d.lat == 47.1 and d.lon == -123.2 and d.kind == 'turn' and d.inDeg == 0 and #d.sides == 2,
    'read back as written')
  T.check(d.sides[1].halfW == 3 and d.sides[2].halfW == nil, 'a 0 half width reads back as not known')
  -- format 1
  local d1 = J.decode({ 47.0, -123.0, 'fork', 'left' })
  T.check(d1 and d1.kind == 'fork' and d1.side == 'left' and d1.inDeg == nil and d1.sides == nil,
    'format 1: kind and side, no roads')
  T.check(J.decode({ 'x' }) == nil and J.decode(nil) == nil, 'not a junction entry: nil')

  -- through events.lua, both formats
  local stage = { id = 'hill', line = { { 47.0, -123.0 }, { 47.01, -123.0 } } }
  files['/earthRally/matched/ev__hill.json'] = { format = 1, mapKey = events.mapKey(stage.line),
    points = { { 47.0, -123.0, 0 }, { 47.01, -123.0, 0 } },
    junctions = { { 47.001, -123.0, 'turn', '' }, { 47.002, -123.0, 'straight', '' } } }
  local js = events.junctions('ev', 'hill', stage)
  T.check(js and #js == 2 and js[1].kind == 'turn' and js[1].sides == nil, 'events.junctions reads a format 1 file')
  T.check(#events.landmarks('ev', 'hill', stage) == 2, 'and the landmarks are as they were')

  events.forget()
  files['/earthRally/matched/ev__hill.json'] = { format = 2, mapKey = events.mapKey(stage.line),
    points = { { 47.0, -123.0, 0 }, { 47.01, -123.0, 0 } },
    junctions = { { 47.001, -123.0, 'turn', '', 0, 90, { { 0, 3.5 }, { 270, 0 } } },
                  { 47.002, -123.0, 'fork', 'right', 0, 10, { { 345, 2 } } } } }
  js = events.junctions('ev', 'hill', stage)
  T.check(js and #js == 2 and js[1].outDeg == 90 and #js[1].sides == 2 and js[1].sides[1].halfW == 3.5 and
    js[1].sides[2].halfW == nil, 'events.junctions reads a format 2 file with its side roads')
  local lm = events.landmarks('ev', 'hill', stage)
  T.check(#lm == 2 and lm[1].type == 'atJunction' and lm[2].type == 'keepRight',
    'the landmarks read format 2 as format 1 (' .. tostring(lm[2] and lm[2].type) .. ')')
  T.check(events.junctions('ev', 'hill', { line = { { 46, -122 }, { 46.1, -122 } } }) == nil,
    'a matched line from another version of the map: none')
  T.check(events.junctions('ev', 'nothere') == nil, 'no matched line: none')
end

------------------------------------------------------------------------------------------ 7: 1.4.0's review

-- a junction carries the stage road's own half width (its node's radius)
do
  local nodes, ln = scene(0, 0, 90, { { 0, 120, 3.0 } })
  local j = found(nodes, ln)[1]
  T.check(j and j.half == 4.0, 'live: the stage road\'s half width at the junction from its node (' .. tostring(j and j.half) .. ')')
end

-- A stage through the same crossroads twice (a figure of eight): the file has the junction twice, in order; each is
-- placed on its own pass, not both on the nearer one
do
  -- north through (0, 0), a loop round to the east, then west through (0, 0) again, and away
  local ln = line({ x = 0, y = -300 }, { { 0, 400 }, { 90, 100 }, { 180, 100 }, { 270, 300 } })
  local cum = geo.cumulative(ln)
  local first, second = 300, 400 + 100 + 100 + 100
  local at = J.placeInOrder(ln, cum, { { x = 0, y = 0 }, { x = 0, y = 0 } }, 15)
  T.near(at[1] and at[1].along or -1, first, 0.5, 'twice through a crossroads: the first on the first pass')
  T.near(at[2] and at[2].along or -1, second, 0.5, 'and the second on the second (' .. tostring(at[2] and at[2].along) .. ')')
  -- a whole-line nearest search puts both on one pass: what this replaced
  local _, _, s1 = geo.locate(ln, cum, { x = 0, y = 0 })
  local _, _, s2 = geo.locate(ln, cum, { x = 0, y = 0 })
  T.check(s1 == s2, '(the whole-line search gives one along for both)')
  -- a point off every pass, and a nil in the list: left out, the rest still placed in order
  local at2 = J.placeInOrder(ln, cum, { { x = 0, y = -200 }, false, { x = 500, y = 500 }, { x = 0, y = 0 } }, 15)
  T.near(at2[1] and at2[1].along or -1, 100, 0.5, 'in order: the first')
  T.check(at2[2] == nil and at2[3] == nil, 'a point that could not be converted and one off the line: none')
  T.near(at2[4] and at2[4].along or -1, first, 0.5, 'the next after them still on its own first pass')
  -- the line passing a few metres off before it reaches the point: the pass that reaches it, not the first near one
  local ln2 = line({ x = 10, y = -100 }, { { 0, 200 }, { 270, 10 }, { 180, 200 } })
  local at3 = J.placeInOrder(ln2, geo.cumulative(ln2), { { x = 0, y = 0 } }, 15)
  T.check(at3[1] and at3[1].off < 1, 'a pass 10 m off first, then one through the point: the one through it (' ..
    tostring(at3[1] and at3[1].off) .. ')')
end

T.done('test_junctions')
