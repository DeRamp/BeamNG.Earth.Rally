-- The auto recce (earthRally/autoRecce) against a stand-in BeamNG.Earth that hands out road-graph windows, with no
-- BeamNG and no BeamNG.Earth: a stage matched across two windows, a stretch with no road filled from the
-- organisers' line and flagged, a window whose map cells are not on this computer writing nothing at all, the same
-- node names in two overlapping windows adding no geometry twice, and the world's origin moving part way through.
local T = dofile(TESTS .. '/testlib.lua')

------------------------------------------------------------------------------------------ the stand-in game

local files = {}
function jsonWriteFile(path, data) files[path] = data return true end
function jsonReadFile(path) return files[path] end
FS = {
  fileExists = function(_, path) return files[path] ~= nil end,
  findFiles = function() return {} end,
}
local logs = {}
function log(level, _, msg) logs[#logs + 1] = tostring(level) .. ' ' .. tostring(msg) end

-- BeamNG.Earth: a flat world round an origin (the anchor) that can move, and a road graph handed out a window at a
-- time. The windows are built from `road`, a list of lat / lon polylines, each a chain of named nodes -- the names
-- being what stitches the windows together, as BeamNG.Earth's own are (navgraph.short_ids).
local R = 6371008.8
local anchor = { lat = 47.0, lon = -123.0 }
local function toGame(lat, lon, h)
  local kx = math.rad(1) * R * math.cos(math.rad(anchor.lat))
  return (lon - anchor.lon) * kx, (lat - anchor.lat) * math.rad(1) * R, h or 0
end
local function toGeo(x, y, z)
  local kx = math.rad(1) * R * math.cos(math.rad(anchor.lat))
  return anchor.lat + y / (math.rad(1) * R), anchor.lon + x / kx, z or 0
end

local world = { roads = {}, complete = true, incompleteAt = nil, arrays = false,
                rebaseAt = nil, calls = 0 }

-- A road as a chain of nodes: { name = 'a', pts = { {lat, lon, alt}... } }. Node i of road r is named r.name .. i,
-- so two windows covering the same stretch hand out the same names. `names` overrides them one by one, which is how
-- a side road is given the main road's own node where it joins it -- the only thing that makes a junction a
-- junction, here as in BeamNG.Earth's graph.
local function nodeName(road, i) return (road.names and road.names[i]) or (road.name .. i) end

local function graphWindow(lat, lon, radius)
  local nodes, edges = {}, {}
  local cx, cy = toGame(lat, lon, 0)
  for _, road in ipairs(world.roads) do
    local prev = nil
    for i, p in ipairs(road.pts) do
      local x, y = toGame(p[1], p[2], 0)
      local inside = math.abs(x - cx) <= radius and math.abs(y - cy) <= radius
      local name = nodeName(road, i)
      if inside then
        if world.arrays then nodes[name] = { x, y, p[3] or 100, 4.0 }
        else nodes[name] = { x = x, y = y, z = p[3] or 100, radius = 4.0 } end
      end
      -- (an edge is handed out when either end is in the window, as a real one clipped at the window's edge is)
      if prev and (inside or prev.inside) then
        if world.arrays then edges[#edges + 1] = { prev.name, name, false, 1, 1, 20.0, 1.0, 4.0 }
        else edges[#edges + 1] = { inNode = prev.name, outNode = name, oneWay = false, lanesOut = 1, lanesIn = 1,
                                   speedMs = 20.0, drivability = 1.0, radius = 4.0 } end
        if not nodes[prev.name] then
          local px, py = toGame(road.pts[i - 1][1], road.pts[i - 1][2], 0)
          if world.arrays then nodes[prev.name] = { px, py, road.pts[i - 1][3] or 100, 4.0 }
          else nodes[prev.name] = { x = px, y = py, z = road.pts[i - 1][3] or 100, radius = 4.0 } end
        end
        if not nodes[name] then
          if world.arrays then nodes[name] = { x, y, p[3] or 100, 4.0 }
          else nodes[name] = { x = x, y = y, z = p[3] or 100, radius = 4.0 } end
        end
      end
      prev = { name = name, inside = inside }
    end
  end
  return nodes, edges
end

local pending = {}      -- the answers, delivered when the test says so (as the real call is answered later)

beamngEarth_api = {
  version = function() return 1, 9 end,
  has = function(n) return n == 'transform' or n == 'rebase' or n == 'roadGraph' end,
  inWorld = function() return true end,
  ready = function() return true end,
  rebasing = function() return false end,
  pose = function() return { lat = 47, lon = -123, anchorLat = anchor.lat, anchorLon = anchor.lon } end,
  toGame = toGame, toGeo = toGeo,
  on = function() return 1 end, off = function() end,
  roadGraph = function(lat, lon, opts, cb)
    world.calls = world.calls + 1
    local i = world.calls
    -- the window is built in the frame current NOW ...
    local nodes, edges = graphWindow(lat, lon, opts.radius)
    local complete = world.complete and (world.incompleteAt ~= i)
    -- (1.7.3) BeamNG.Earth's own failures: the call timed out or the build threw, an answer with an error and no rows
    if world.errorCalls and world.errorCalls[i] then
      pending[#pending + 1] = function() cb({ complete = false, error = world.errorCalls[i] }) end
      return true
    end
    -- ... and the world's origin may move before the answer is delivered, which is what makes those x, y stale:
    -- read in the frame that replaced it they are tens of kilometres out
    if world.rebaseAt == i then
      world.rebaseAt = nil
      anchor = { lat = 47.3, lon = -122.6 }
    end
    pending[#pending + 1] = function() cb({ nodes = nodes, edges = edges, complete = complete }) end
    -- the same request answered twice (a server that sent its answer again, a retried request that both landed)
    if world.answerTwice == i then
      world.answerTwice = nil
      pending[#pending + 1] = function() cb({ nodes = nodes, edges = edges, complete = complete }) end
    end
    return true
  end,
}

local auto = require('earthRally/autoRecce')
local events = require('earthRally/events')
local geo = require('earthRally/geo')
auto.clock = function() return 0 end        -- (`seconds` deterministic in the tests)

-- Run the whole auto recce to its end, delivering each window's answer as it is asked for.
local function run(event, stage)
  local res = { called = 0 }
  local ok, why = auto.start(event, stage, function(o, m, w) res.called = res.called + 1 res.ok, res.m, res.why = o, m, w end)
  res.started, res.startWhy = ok, why
  local guard = 0
  while #pending > 0 do
    local f = table.remove(pending, 1)
    f()
    guard = guard + 1
    if guard > 200 then error('the auto recce did not finish') end
  end
  res.windows = world.calls
  return res
end

local function reset()
  files = {}
  logs = {}
  pending = {}
  anchor = { lat = 47.0, lon = -123.0 }
  world.roads, world.complete, world.incompleteAt, world.arrays, world.rebaseAt, world.calls = {}, true, nil, false, nil, 0
  world.answerTwice, world.errorCalls = nil, nil
  events.forget()
  auto.cancel()
end

------------------------------------------------------------------------------------------ the fixtures

local LAT, LON = 47.0, -123.0
local MPD_LAT = math.rad(1) * R                                 -- metres per degree of latitude
local MPD_LON = MPD_LAT * math.cos(math.rad(LAT))

local function at(east, north, alt) return { LAT + north / MPD_LAT, LON + east / MPD_LON, alt } end

-- A road east from `from` to `to` m with a node every `step` m, offset `off` m north of the organisers' line.
local function eastRoadFrom(name, from, to, step, off, alt)
  local pts = {}
  for d = from, to, step do pts[#pts + 1] = at(d, off or 0, (alt or 100) + d * 0.01) end
  return { name = name, pts = pts }
end

local function eastRoad(name, len, step, off, alt) return eastRoadFrom(name, 0, len, step, off, alt) end

-- The organisers' line: a lat / lon list, as an event file's stage.line is.
local function lineEast(len, step, off)
  local out = {}
  for d = 0, len, step do
    local p = at(d, off or 0)
    out[#out + 1] = { p[1], p[2] }
  end
  return out
end

local function stageOf(line, id) return { id = id or 'test-stage', name = 'Test Stage', line = line } end
local EVENT = { id = 'test-event', name = 'Test Rally' }

local function matchedFile() return files[events.MATCHED_DIR .. 'test-event__test-stage.json'] end

------------------------------------------------------------------------------------------ the frame maths

do
  local fr = auto.frame(LAT, LON)
  local p = fr.xy(LAT + 0.01, LON + 0.01)
  T.near(p.y, geo.metres(LAT, LON, LAT + 0.01, LON), 0.5, 'the frame north agrees with geo.metres')
  T.near(p.x, geo.metres(LAT, LON, LAT, LON + 0.01), 0.5, 'the frame east agrees with geo.metres')
  local la, lo = fr.latlon(p.x, p.y)
  T.near(la, LAT + 0.01, 1e-9, 'the frame round trips (lat)')
  T.near(lo, LON + 0.01, 1e-9, 'the frame round trips (lon)')
end

do  -- the resample keeps the line's own end, at an even step before it (the output file's ll() reads points by index)
  local pts = { { x = 0, y = 0 }, { x = 10.5, y = 0 } }
  local out, along = auto.resample(pts, 4)
  T.check(#out == 4, 'resampled 10.5 m every 4 m: 4 points (' .. #out .. ')')
  T.near(along[2], 4, 1e-9, 'the second point 4 m along')
  T.near(out[#out].x, 10.5, 1e-9, "the line's own end kept")
end

------------------------------------------------------------------------------------------ 1: two windows stitched

do
  reset()
  -- 3 km of stage: more than one 1000 m window (its trusted inner part is 700 m), so this needs several
  world.roads = { eastRoad('r', 3200, 20, 0) }
  local stage = stageOf(lineEast(3000, 200))
  local res = run(EVENT, stage)
  T.check(res.started == true, 'the auto recce started (' .. tostring(res.startWhy) .. ')')
  T.check(world.calls >= 2, 'more than one window asked for (' .. world.calls .. ')')
  T.check(res.ok == true and res.called == 1, 'it finished once, with a line (' .. tostring(res.why) .. ')')
  local m = matchedFile()
  T.check(m ~= nil, 'the matched file written where events.matched reads it')
  T.check(m and m.format == 2 and m.stage == 'test-stage', 'format 2 (the junctions keep their roads), the stage named')
  T.check(m and m.source == auto.SOURCE and m.source:find('auto recce'), 'the source says the in-game auto recce')
  T.check(m and m.mapKey == events.mapKey(stage.line), 'the mapKey is the one events.mapKey makes')
  T.near(m and m.lengthM or 0, 3000, 30, 'the matched line is the stage\'s length')
  T.near(m and m.mapLineM or 0, 3000, 5, 'the map line\'s length')
  T.check(m and #m.gaps == 0 and m.gapM == 0, 'no gaps: there is road all the way (' .. #(m and m.gaps or {}) .. ')')
  T.check(m and m.maxOffMapLineM < 2, 'the line stays on the organisers\' line (' .. tostring(m and m.maxOffMapLineM) .. ')')
  -- the points: every OUT_STEP_M, lat / lon / alt, none flagged, and the stitch across the windows has no jump
  local pts = m and m.points or {}
  T.near(#pts, 3000 / 4 + 1, 3, 'a point every 4 m (' .. #pts .. ')')
  local maxStep, flagged = 0, 0
  for i = 2, #pts do
    local d = geo.metres(pts[i - 1][1], pts[i - 1][2], pts[i][1], pts[i][2])
    if d > maxStep then maxStep = d end
  end
  for _, p in ipairs(pts) do if p[4] == 1 then flagged = flagged + 1 end end
  T.near(maxStep, 4, 1.5, 'no jump anywhere along the stitched line (' .. string.format('%.1f', maxStep) .. ' m)')
  T.check(flagged == 0, 'no point flagged as having no road (' .. flagged .. ')')
  T.check(pts[1] and pts[1][3] > 100 and pts[1][3] < 101, 'the heights come from the graph (' .. tostring(pts[1] and pts[1][3]) .. ')')
  T.check(m and #m.bridges == 0, 'bridges empty: the in-game graph has no bridge flag')
  -- what the line says about itself, written with it (lineStats.lua): the stage page reads these rather than
  -- measuring the line again every time it is looked at. This road is straight and climbs 1 m in 100 all the way.
  T.check(m and m.corners == 0, 'a straight road: no corners kept with the line (' .. tostring(m and m.corners) .. ')')
  T.near(m and m.gainM or -1, 30, 3, 'the height the line gains, kept with it')
  T.check(m and m.lossM == 0, 'and the height it loses (' .. tostring(m and m.lossM) .. ')')
  T.check(m and m.cells == 0 and m.roadEdges > 0 and m.seconds == 0, 'cells 0 (not known in the game), roadEdges counted')
end

------------------------------------------------------------------------------------------ 2: a stretch with no road

do
  reset()
  -- Road for the first 1.2 km and the last 1.2 km of a 3 km stage; nothing in the middle 600 m. The road runs 25 m
  -- north of the organisers' line all the way (OpenStreetMap and a hand-drawn rally map do not agree to the metre),
  -- so where the matched line leaves the road for the organisers' line there is a 25 m step to be eased away: with
  -- the two on top of each other a missing ease would not show.
  world.roads = { eastRoadFrom('a', 0, 1200, 20, 25), eastRoadFrom('b', 1800, 3000, 20, 25) }
  local stage = stageOf(lineEast(3000, 100))
  local res = run(EVENT, stage)
  local m = matchedFile()
  T.check(res.ok == true and m ~= nil, 'a stage with a stretch of no road still writes a line (' .. tostring(res.why) .. ')')
  T.check(m and #m.gaps >= 1 and m.gapM > 300, 'the stretch with no road is recorded as a gap (' ..
    tostring(m and m.gapM) .. ' m in ' .. #(m and m.gaps or {}) .. ')')
  local flagged, total = 0, 0
  for _, p in ipairs(m and m.points or {}) do
    total = total + 1
    if p[4] == 1 then flagged = flagged + 1 end
  end
  T.check(flagged > 50, 'the points on it are flagged, so the co-driver calls no notes there (' .. flagged .. ')')
  T.check(flagged < total, 'and only those points (' .. flagged .. ' of ' .. total .. ')')
  -- filled from the organisers' line, eased in: no kink, and never further off than the road itself is
  T.check(m and m.maxOffMapLineM > 20 and m.maxOffMapLineM < 30, 'the road is 25 m off the organisers\' line (' ..
    tostring(m and m.maxOffMapLineM) .. ' m at most)')
  -- the middle of the gap is back on the organisers' line itself: the ease is over BLEND_M, not the whole stretch
  local fr0 = auto.frame(LAT, LON)
  local mid = fr0.xy(m.points[math.floor(1500 / 4)][1], m.points[math.floor(1500 / 4)][2])
  T.check(math.abs(mid.y) < 3, 'the middle of the gap is on the organisers\' own line (' ..
    string.format('%.1f', mid.y) .. ' m off)')
  local worst = 0
  local pts = m.points
  for i = 3, #pts do
    local fr = auto.frame(LAT, LON)
    local a = fr.xy(pts[i - 2][1], pts[i - 2][2])
    local b = fr.xy(pts[i - 1][1], pts[i - 1][2])
    local c = fr.xy(pts[i][1], pts[i][2])
    local turn = math.abs(auto.angle({ x = b.x - a.x, y = b.y - a.y }, { x = c.x - b.x, y = c.y - b.y }))
    if turn > worst then worst = turn end
  end
  T.check(worst < 30, 'eased in and out: no kink where the line meets the road (worst turn ' ..
    string.format('%.0f', worst) .. ' deg over 4 m)')
  -- the heights across the gap are carried between the road at each end, not left at zero
  local lowest = math.huge
  for _, p in ipairs(pts) do if p[3] < lowest then lowest = p[3] end end
  T.check(lowest > 90, 'the gap has heights, interpolated between the roads (lowest ' ..
    string.format('%.1f', lowest) .. ')')
end

------------------------------------------------------------------------------------------ 3: coverage incomplete

do
  reset()
  world.roads = { eastRoad('r', 3200, 20, 0) }
  world.incompleteAt = 2               -- the second window's map cells are not on this computer
  local stage = stageOf(lineEast(3000, 200))
  local res = run(EVENT, stage)
  T.check(res.called == 1 and res.ok == false, 'an incomplete window: the auto recce says no (' .. tostring(res.why) .. ')')
  T.check(matchedFile() == nil, 'and NOTHING is written: a partial line would read as runnable')
  T.check(res.why and res.why:find('no map data'), 'the reason names the missing map data (' .. tostring(res.why) .. ')')
  T.check(events.matched('test-event', 'test-stage') == nil, 'events.matched still sees no line')
end

do  -- every window complete but one point of the corridor outside them all: still nothing
  reset()
  local line = lineEast(1000, 100)
  local plan, _, _, inner = auto.plan(line, auto.RADIUS_M)
  local windows = {}
  for i, w in ipairs(plan) do windows[i] = { x = w.x, y = w.y, complete = true } end
  local ok, shortM = auto.coverage(line, windows, inner)
  T.check(ok == true and shortM == 0, 'the planned windows cover the corridor they were planned for')
  windows[1].complete = false
  local ok2, short2 = auto.coverage(line, windows, inner)
  T.check(ok2 == false and short2 > 0, 'one window not complete: the stage is not covered (' ..
    string.format('%.0f', short2) .. ' m)')
end

------------------------------------------------------------------------- 3b: the stage as a downloadable corridor

-- M.corridor is the shape a downloader would be handed (1.3.1). It downloads nothing and must not: these check the
-- geometry only, which is all it is.
do
  local line = lineEast(1000, 10)                 -- 101 points, a point every 10 m
  local cor = auto.corridor(line, 30)
  T.check(cor ~= nil and #cor > 0, 'a line becomes a corridor of points')
  -- decimated: a 1000 m line at 30 m is 34 points plus its own end, not the 101 it came in as. The point of the
  -- whole function is that areas.json does not carry the dense line, so the count is the assertion.
  T.check(#cor < #line / 2, 'and far fewer points than the line (' .. #cor .. ' from ' .. #line .. ')')
  T.near(#cor, 35, 2, 'about one point every 30 m along 1000 m')

  -- Pairs, not { lat = , lon = }: the shape BeamNG.Earth's api.areaPlan documents ("points: { { lat, lon }, ... }")
  -- and the shape a stage's own line already has, so the corridor crosses no boundary needing a conversion.
  T.check(type(cor[1]) == 'table' and #cor[1] == 2 and cor[1].lat == nil,
    'a corridor point is a { lat, lon } pair, as the call it feeds wants')

  -- the ends are the line's own, to the centimetre: a corridor that stopped short would leave the flying finish
  -- uncached, which is the one stretch a player would notice.
  --
  -- On a DIAGONAL line, deliberately. lineEast runs due east, so its latitude never changes and a `.lat` check
  -- against it cannot fail however the function is broken -- an assertion that looks like coverage and is not. A
  -- mutation that dropped the line's last point was caught by one check out of four here for exactly that reason.
  local diag = {}
  for i = 0, 100 do diag[#diag + 1] = { 45.0 + i * 0.00009, -120.0 + i * 0.00013 } end   -- ~1.4 km northeast
  local dcor = auto.corridor(diag, 30)
  T.near(dcor[1][1], diag[1][1], 1e-7, "the corridor starts at the line's own first point")
  T.near(dcor[1][2], diag[1][2], 1e-7, '... and its longitude')
  T.near(dcor[#dcor][1], diag[#diag][1], 1e-7, "and ends at the line's own last point")
  T.near(dcor[#dcor][2], diag[#diag][2], 1e-7, '... and its longitude')
  T.check(#dcor < #diag, 'the diagonal line is decimated too (' .. #dcor .. ' from ' .. #diag .. ')')

  -- spacing: every gap is one step, bar the last, which is whatever was left over
  local fr = auto.frame(line[1][1], line[1][2])
  local worst, lastGap = 0, 0
  for i = 1, #cor - 1 do
    local a, b = fr.xy(cor[i][1], cor[i][2]), fr.xy(cor[i + 1][1], cor[i + 1][2])
    local d = math.sqrt((a.x - b.x) ^ 2 + (a.y - b.y) ^ 2)
    if i < #cor - 1 then worst = math.max(worst, math.abs(d - 30)) else lastGap = d end
  end
  T.check(worst < 0.5, 'the points are one step apart (worst ' .. string.format('%.2f', worst) .. ' m off 30 m)')
  T.check(lastGap <= 30 + 0.5, 'and the last gap is no longer than a step (' ..
    string.format('%.1f', lastGap) .. ' m)')

  -- the default step is used when none is given, and is coarser than the matched line's own 4 m spacing
  local deflt = auto.corridor(line)
  T.check(#deflt > 0 and auto.CORRIDOR_STEP_M > auto.OUT_STEP_M,
    'a corridor with no step given uses CORRIDOR_STEP_M, coarser than the matched line (' ..
    auto.CORRIDOR_STEP_M .. ' m vs ' .. auto.OUT_STEP_M .. ' m)')
end

do  -- what it refuses, rather than returning something a downloader would act on
  local one = { { 45.0, -120.0 } }
  local cor, why = auto.corridor(one, 30)
  T.check(cor == nil and why ~= nil, 'a line of one point: refused (' .. tostring(why) .. ')')
  local cor2, why2 = auto.corridor(lineEast(1000, 10), 0)
  T.check(cor2 == nil and why2 ~= nil, 'a step of zero: refused rather than looping (' .. tostring(why2) .. ')')
  local cor3 = auto.corridor(nil, 30)
  T.check(cor3 == nil, 'no line at all: refused')
end

------------------------------------------------------------------------------------------ 4: shared node names

do
  reset()
  world.roads = { eastRoad('r', 3200, 20, 0) }
  local stage = stageOf(lineEast(3000, 200))
  -- how many node names the windows handed out in all, and how many of them were distinct
  local handed, distinct = 0, {}
  local inner = beamngEarth_api.roadGraph
  beamngEarth_api.roadGraph = function(lat, lon, opts, cb)
    return inner(lat, lon, opts, function(r)
      for name in pairs(r.nodes) do handed = handed + 1 distinct[name] = true end
      cb(r)
    end)
  end
  local res = run(EVENT, stage)
  beamngEarth_api.roadGraph = inner
  local nd = 0
  for _ in pairs(distinct) do nd = nd + 1 end
  T.check(handed > nd, 'the windows overlap: some node names came back more than once (' .. handed .. ' rows, ' ..
    nd .. ' names)')
  local m = matchedFile()
  T.check(m ~= nil, 'the overlapping windows still match the stage')
  -- the overlap adds no geometry: the same road, matched, is the stage's own length and not a metre more
  T.near(m and m.lengthM or 0, 3000, 30, 'no duplicated geometry: the line is still 3 km (' ..
    tostring(m and m.lengthM) .. ')')
  T.check(m and m.roadEdges <= nd, 'one edge per pair of nodes, however many windows saw it (' ..
    tostring(m and m.roadEdges) .. ' edges, ' .. nd .. ' nodes)')
  -- and the line does not double back on itself anywhere (a duplicated node would show as a reversal)
  local back = 0
  local fr = auto.frame(LAT, LON)
  local pts = m.points
  for i = 2, #pts do
    local a = fr.xy(pts[i - 1][1], pts[i - 1][2])
    local b = fr.xy(pts[i][1], pts[i][2])
    if b.x < a.x - 0.5 then back = back + 1 end
  end
  T.check(back == 0, 'the line never doubles back (' .. back .. ' point(s) going the wrong way)')
end

------------------------------------------------------------------------------------------ 5: a rebase part way

do
  -- (the road 25 m north of the organisers' line, as in test 2: with the two on top of each other a window lost to
  --  the rebase would be replaced by the organisers' line in the same place, and nothing would show)
  reset()
  world.roads = { eastRoad('r', 3200, 20, 25) }
  local stage = stageOf(lineEast(3000, 200))
  local plain = run(EVENT, stage)
  local before = matchedFile()
  T.check(before ~= nil and #before.gaps == 0, 'the line without a rebase, to compare against')

  reset()
  world.roads = { eastRoad('r', 3200, 20, 25) }
  -- the world's origin moves after the second window was built: its x, y arrive in a frame that is gone
  world.rebaseAt = 2
  local res = run(EVENT, stage)
  local after = matchedFile()
  T.check(res.ok == true and after ~= nil, 'a rebase part way through still produces a line (' .. tostring(res.why) .. ')')
  T.check(world.calls == plain.windows + 1, 'one window more was asked for than without the rebase (' ..
    world.calls .. ' vs ' .. tostring(plain.windows) .. ')')
  local asked = 0
  for _, l in ipairs(logs) do if l:find('origin moved under window') then asked = asked + 1 end end
  T.check(asked == 1, 'exactly one window thrown away and re-asked (' .. asked .. ')')
  -- the line is the same line: every point of it, not merely its length
  T.check(after and #after.points == #before.points, 'the same number of points (' .. #(after and after.points or {}) ..
    ' vs ' .. #before.points .. ')')
  local worst = 0
  for i = 1, math.min(#before.points, #(after and after.points or {})) do
    local a, b = before.points[i], after.points[i]
    local d = geo.metres(a[1], a[2], b[1], b[2])
    if d > worst then worst = d end
  end
  T.check(worst < 0.5, 'the rebase did not corrupt the line (worst point ' .. string.format('%.2f', worst) .. ' m off)')
  T.near(after and after.lengthM or 0, before.lengthM, 1, 'and its length is unchanged')
  T.check(after and #after.gaps == 0, 'and the stretch the thrown-away window covered is still on the road (' ..
    #(after and after.gaps or {}) .. ' gap(s))')
end

------------------------------------------------------------------------------------------ 6: junctions, arrays

do
  reset()
  -- a stage straight east with a side road leaving north at 1500 m: a junction the stage goes straight past.
  -- The side road's first node IS the main road's node there (shared, as BeamNG.Earth's junction connectors are):
  -- that is what gives it degree 3.
  local main = eastRoad('m', 3200, 20, 0)
  local joinI = 1 + 1500 / 20
  local side = { name = 's', names = { [1] = nodeName(main, joinI) }, pts = { main.pts[joinI] } }
  for d = 20, 200, 20 do side.pts[#side.pts + 1] = at(1500, d, 100) end
  world.roads = { main, side }
  world.arrays = true                               -- navgraph.py's own row shape: [x, y, z, radius] / [in, out, ...]
  local stage = stageOf(lineEast(3000, 200))
  local res = run(EVENT, stage)
  local m = matchedFile()
  T.check(res.ok == true and m ~= nil, 'the array row shape is read too (navgraph.py writes arrays)')
  T.check(m and m.roadEdges > 100, 'the arrays gave real edges (' .. tostring(m and m.roadEdges) .. ')')
  T.near(m and m.lengthM or 0, 3000, 30, 'and the same 3 km line')
  -- the junction landmark: one, of the kind that says the stage carries straight on past a side road
  local js = m and m.junctions or {}
  T.check(#js == 1, 'the side road is one junction (' .. #js .. ')')
  T.check(js[1] and js[1][3] == 'straight', 'the stage goes straight past it (' .. tostring(js[1] and js[1][3]) .. ')')
  T.check(js[1] and js[1][4] == '', 'with no side named (' .. tostring(js[1] and js[1][4]) .. ')')
  if js[1] then
    local d = geo.metres(js[1][1], js[1][2], LAT, LON)
    T.near(d, 1500, 10, 'and it is where the side road leaves (' .. string.format('%.0f', d) .. ' m along)')
  end
  -- format 2: the way in, the way out and the side road, as compass bearings, and the side road's half width
  local e = js[1] or {}
  T.near(e[5], 90, 1, 'the stage comes in heading east (inDeg ' .. tostring(e[5]) .. ')')
  T.near(e[6], 90, 1, 'and leaves heading east (outDeg ' .. tostring(e[6]) .. ')')
  T.check(type(e[7]) == 'table' and #e[7] == 1, 'one side road kept (' .. tostring(e[7] and #e[7]) .. ')')
  local sr = e[7] and e[7][1] or {}
  T.near(sr[1], 0, 1, 'the side road leaves north (' .. tostring(sr[1]) .. ')')
  T.near(sr[2], 4.0, 0.01, "its half width from the graph node's radius (" .. tostring(sr[2]) .. ')')
  T.near(e[8], 4.0, 0.01, "the stage road's own half width there, the eighth entry (" .. tostring(e[8]) .. ')')
  local ej = events.junctions('test-event', 'test-stage', stage)
  T.check(ej and #ej == 1 and ej[1].kind == 'straight' and ej[1].sides and #ej[1].sides == 1 and
    ej[1].sides[1].halfW == 4.0, 'events.junctions reads it back with its side road')
  -- events.landmarks turns it into the pacenote landmark the co-driver calls
  local lm = events.landmarks('test-event', 'test-stage', stage)
  T.check(#lm == 1 and lm[1].type == 'pastJunction', 'events.landmarks makes it "pastJunction" (' ..
    #lm .. ', ' .. tostring(lm[1] and lm[1].type) .. ')')
end

------------------------------------------------------------------------------------------ 7: no roads at all

-- A stage whose corridor was all read but holds no road at all writes NOTHING.
--
-- This test asserted the opposite until 2026-11-13 -- that such a stage is written as the organisers' line the whole
-- way, flagged end to end, as tools/auto_recce.py writes it. In game that turned out to be the wrong behaviour to
-- copy: three complete windows came back with no nodes in them (a server bug, since fixed) and 4106 m of a 4.1 km
-- stage was written as one gap. The file is then the organisers' own line with no notes anywhere, and the stage
-- shows amber "recce recommended" rather than red -- it looks as though the auto recce achieved something, and the
-- player drives a hand-drawn line believing the roads were matched. Writing nothing is the honest answer, and the
-- red tag is the one that tells the truth.
--
-- The Python tool keeps its own behaviour: it is run by hand, over data known to be there, by someone reading its
-- report. Nothing here changes it.
do
  reset()
  world.roads = {}                                  -- complete windows, but no road anywhere near the line
  local stage = stageOf(lineEast(1000, 100))
  local res = run(EVENT, stage)
  T.check(res.ok == false and matchedFile() == nil,
    'a covered stage with no road at all writes nothing (' .. tostring(res.why) .. ')')
  T.check(res.why and res.why:find('no roads'), 'and says why in words a player can act on (' ..
    tostring(res.why) .. ')')
  local menu = require('earthRally/menu')
  local st = menu.stageStatus('test-event', stage)
  T.check(st.status == 'none', 'the stage stays "recce needed", not amber (' .. tostring(st.status) .. ')')
end

-- the same refusal one step later: roads arrived, but every one of them too far from the line to be used
do
  reset()
  world.roads = { { { x = 0, y = 4000 }, { x = 1000, y = 4000 } } }    -- a road 4 km off the line
  local stage = stageOf(lineEast(1000, 100))
  local res = run(EVENT, stage)
  T.check(res.ok == false and matchedFile() == nil,
    'roads present but none near the line: still nothing written (' .. tostring(res.why) .. ')')
end

------------------------------------------------------------------------------------------ 8: the capability gate

do
  reset()
  local had = beamngEarth_api.has
  beamngEarth_api.has = function(n) return n == 'transform' or n == 'rebase' end     -- an older BeamNG.Earth
  local ok, why = auto.start(EVENT, stageOf(lineEast(1000, 100)), function() end)
  beamngEarth_api.has = had
  T.check(ok == false and why and why:find('road graph'), 'without the capability the auto recce refuses (' ..
    tostring(why) .. ')')
  T.check(world.calls == 0 and matchedFile() == nil, 'and asks BeamNG.Earth for nothing')
  local earth = require('earthRally/earthAdapter')
  beamngEarth_api.has = function() return false end
  T.check(earth.hasRoadGraph() == false, 'earthAdapter.hasRoadGraph is the gate')
  beamngEarth_api.has = had
  T.check(earth.hasRoadGraph() == true, 'and it answers true with the capability there')
end

------------------------------------------------------------------------------------------ 8b: one at a time

-- The module's own guard. The menu refuses a second Auto recce before it ever gets here (main.lua, so that the
-- refusal cannot disturb the record of the one already running), which leaves this the guard for every other
-- caller -- the console, and whatever runs several stages one after another later.
do
  reset()
  world.roads = { eastRoad('r', 3200, 20, 0) }
  local stage = stageOf(lineEast(3000, 200))
  local ends = 0
  local ok = auto.start(EVENT, stage, function() ends = ends + 1 end)
  T.check(ok and auto.active(), 'one auto recce running')
  local asked = world.calls
  local ok2, why2 = auto.start(EVENT, stageOf(lineEast(1000, 100)), function() ends = ends + 1 end)
  T.check(ok2 == false and why2 and why2:find('already running'), 'a second one is refused (' ..
    tostring(why2) .. ')')
  T.check(world.calls == asked, 'and nothing is asked of BeamNG.Earth for it (' .. world.calls .. ')')
  local p = auto.progress()
  T.check(p and p.stage == 'test-stage', 'the first one is still the one running')
  while #pending > 0 do table.remove(pending, 1)() end
  T.check(ends == 1 and auto.progress() == nil, 'and it finishes once, on its own (' .. ends .. ')')
end

------------------------------------------------------------------------------------------ 9: written whole

-- events.saveMatched replaces a matched line whole where the game's file system can rename a file, so a write
-- interrupted part way cannot leave a shorter line behind that still passes events.lineValid.
do
  reset()
  world.roads = { eastRoad('r', 1600, 20, 0) }
  local renamed = {}
  FS.renameFile = function(_, from, to)
    renamed[#renamed + 1] = { from, to }
    files[to] = files[from]
    files[from] = nil
    return true
  end
  local stage = stageOf(lineEast(1400, 100))
  -- asked for first, as the menu does every time it draws the stage: events.lua keeps "there is no such file", so
  -- a write that does not replace that answer leaves the stage looking unmatched until the next Reload
  T.check(events.matched('test-event', 'test-stage') == nil, 'no matched line before the auto recce runs')
  local res = run(EVENT, stage)
  local path = events.MATCHED_DIR .. 'test-event__test-stage.json'
  T.check(res.ok == true and files[path] ~= nil, 'the matched line is at the path events.matched reads')
  T.check(#renamed == 1 and renamed[1][2] == path, 'it was renamed into place (' .. #renamed .. ')')
  T.check(files[path .. '.part'] == nil, 'and no part file is left behind')
  T.check(events.matched('test-event', 'test-stage') ~= nil, 'events.matched sees it with no Reload')
  FS.renameFile = nil
  -- bridges added by tools/auto_recce.py --bridges-only are kept when the game's recce (which cannot see them)
  -- matches the stage again
  local m = events.matched('test-event', 'test-stage')
  m.bridges = { { 1.0, 2.0, 1.0, 2.001 } }
  m.bridgesSource = 'test'
  events.saveMatched('test-event', 'test-stage', m)
  local again = run(EVENT, stage)
  local kept = matchedFile()
  T.check(again.ok == true and kept and type(kept.bridges) == 'table' and #kept.bridges == 1 and
          kept.bridgesSource == 'test', 'a second auto recce keeps the bridges added to the line before')
end

------------------------------------------------------------------------------------------ 10: answered twice

-- One answer per request. The case that bites is a duplicate answer arriving after that same window was thrown away
-- and asked for again (the rebase path): the plan is still waiting on window 2, so a second copy of the answer the
-- rebase invalidated would be taken -- with the stale coordinates -- and would advance the plan past the window
-- after it, which is then never asked for at all.
do
  reset()
  world.roads = { eastRoad('r', 3200, 20, 25) }
  local stage = stageOf(lineEast(3000, 200))
  local plain = run(EVENT, stage)
  local before = matchedFile()

  reset()
  world.roads = { eastRoad('r', 3200, 20, 25) }
  world.rebaseAt = 2
  world.answerTwice = 2
  local res = run(EVENT, stage)
  local after = matchedFile()
  T.check(res.ok == true and after ~= nil, 'a window answered twice still matches the stage (' ..
    tostring(res.why) .. ')')
  T.check(res.called == 1, 'and the auto recce finishes exactly once (' .. res.called .. ')')
  T.check(world.calls == plain.windows + 1, 'every window of the plan was still asked for, plus the re-ask (' ..
    world.calls .. ' vs ' .. tostring(plain.windows) .. ')')
  T.check(after and #after.gaps == 0, 'no stretch left unmatched (' .. #(after and after.gaps or {}) .. ' gap(s))')
  T.near(after and after.lengthM or 0, before.lengthM, 0.2, 'and the same line as without the double answer')
end

------------------------------------------------------------------------------------------ narrows: the road's widths
do
  -- a straight sampled every OUT_STEP_M, two lanes (3.3 m half width) for 600 m, then one lane (1.65 m)
  local res, along, flags = {}, {}, {}
  for k = 1, 300 do
    local s = (k - 1) * auto.OUT_STEP_M
    res[k] = { x = 0, y = s, w = s < 600 and 3.3 or 1.65 }
    along[k], flags[k] = s, 0
  end
  local nw = auto.narrows(res, along, flags)
  T.check(#nw == 1 and math.abs(nw[1] - 600) <= auto.OUT_STEP_M, 'two lanes to one: one narrowing, where it starts (' ..
    table.concat(nw, ', ') .. ')')
  for k = 1, 300 do res[k].w = 3.3 end
  T.check(#auto.narrows(res, along, flags) == 0, 'the same width all the way: none')
  for k = 1, 300 do res[k].w = (along[k] < 600) and 3.3 or 1.65 end
  for k = 140, 160 do flags[k] = 1 end
  T.check(#auto.narrows(res, along, flags) == 0, 'not across a stretch with no road on the map')
  for k = 1, 300 do flags[k], res[k].w = 0, nil end
  T.check(#auto.narrows(res, along, flags) == 0, 'no widths (a graph without them): none')
  -- the width rides through the snap, the route and the resample from the graph's node radius
  local g = { xy = { a = { x = 0, y = 0, w = 3 }, b = { x = 0, y = 100, w = 1 } }, ea = { 'a' }, eb = { 'b' }, edges = 1,
              nbr = { a = { b = { w = 100, len = 100 } }, b = { a = { w = 100, len = 100 } } } }
  local sn = auto.snap(g, { x = 1, y = 50 }, { x = 0, y = 1 })
  T.near(sn and sn.w or -1, 2, 1e-9, 'a snap halfway along an edge: the width halfway between its ends')
  local rs = auto.resample({ { x = 0, y = 0, w = 3 }, { x = 0, y = 8, w = 1 } }, 4)
  T.near(rs[2].w, 2, 1e-9, 'resampled: the width interpolated')
end

------------------------------------------------------------------------------------------ 1.6.2, issue #5

-- The time controls put on the road beside them when the stage is made, and kept with the line: an ATC 12 m off a
-- road leading north to the start, a stop 8 m off the stage road past the finish; a control 45 m from any road is
-- left as it is (the game's road map puts it down then); a stage without controls writes none.
do
  reset()
  -- (the stage east along y = 0; the ATC's road north to the start, x = -10 .. 0 at y from -300; the stage road on past
  -- the finish to 1500 m)
  local access = { name = 'atc', pts = {}, names = {} }
  for k = 0, 15 do access.pts[#access.pts + 1] = at(-10 + k * 10 / 15, -300 + k * 20, 100) end
  world.roads = { eastRoad('r', 1500, 20, 0), access }
  local stage = stageOf(lineEast(1200, 100))
  local atcLat, atcLon = at(-10 + 12, -150, 0)[1], at(-10 + 12, -150, 0)[2]      -- (12 m east of the access road)
  local stopP = at(1400, -8, 0)
  stage.controls = { atc = { lat = atcLat, lon = atcLon, name = 'ATC' }, stop = { lat = stopP[1], lon = stopP[2] } }
  local res = run(EVENT, stage)
  local m = matchedFile()
  local c = m and m.controls
  T.check(res.ok == true and c and c.atc and c.stop, 'controls: the ATC and the stop kept with the line')
  if c and c.atc and c.stop then
    -- (the access road at y = -150 is at x = -10 + 150 / 300 * 10 = -5: the ATC 7 m east of it, square to it near enough)
    local ax, ay = (c.atc.roadLon - LON) * MPD_LON, (c.atc.roadLat - LAT) * MPD_LAT
    T.check(math.abs(ax + 5) < 0.3 and math.abs(ay + 150) < 0.5,
      string.format('controls: the ATC on its own road (%.1f, %.1f)', ax, ay))
    T.check(math.abs(c.atc.offM - 7) < 0.3, 'controls: how far off the road it was (' .. tostring(c.atc.offM) .. ')')
    T.check(math.abs(((c.atc.deg + 90) % 180) - 90 - 1.9) < 1, 'controls: its road\'s bearing (' .. tostring(c.atc.deg) .. ')')
    T.check(c.atc.lat == atcLat and c.atc.lon == atcLon, 'controls: the organisers\' point it was made from')
    local sx, sy = (c.stop.roadLon - LON) * MPD_LON, (c.stop.roadLat - LAT) * MPD_LAT
    T.check(math.abs(sx - 1400) < 0.5 and math.abs(sy) < 0.3 and math.abs(c.stop.offM - 8) < 0.3,
      string.format('controls: the stop on the stage road past the finish (%.1f, %.1f)', sx, sy))
  end
  -- (events.controlOnRoad: the road point, for the same organisers' point only)
  local on = events.controlOnRoad('test-event', 'test-stage', 'atc', stage.controls.atc)
  T.check(on and on.lat == c.atc.roadLat and on.deg == c.atc.deg, 'controls: events hands the road point to the runner')
  local moved = { lat = atcLat + 0.001, lon = atcLon }
  T.check(events.controlOnRoad('test-event', 'test-stage', 'atc', moved) == nil,
    'controls: none when the map\'s control has moved since the auto recce')

  reset()
  world.roads = { eastRoad('r', 1500, 20, 0) }
  stage = stageOf(lineEast(1200, 100))
  local far = at(600, 45, 0)
  stage.controls = { atc = { lat = far[1], lon = far[2] } }
  run(EVENT, stage)
  T.check(matchedFile() and matchedFile().controls == nil, 'controls: one 45 m from any road is left out')
  reset()
  world.roads = { eastRoad('r', 1500, 20, 0) }
  run(EVENT, stageOf(lineEast(1200, 100)))
  T.check(matchedFile() and matchedFile().controls == nil, 'controls: no controls, none written')
end

------------------------------------------------------------------------------------------ a window that fails (1.7.3)

-- A window that times out or errors is asked again (ERROR_RETRIES), and one that never answers ends FAILED, saying
-- BeamNG.Earth did not answer -- never "no map data", which sent the player off to drive ground already there.
-- (1.7.3) Each is asked again only after a wait, on auto.update: TIMEOUT_RETRY_DELAY_S after 'timed out' (the
-- server is still building that window), RETRY_DELAY_S after another error; an error that cannot change ends at once.
do
  local hadWall = auto.wall
  local now = 0
  auto.wall = function() return now end
  -- every answer delivered; a window waiting to be asked again is asked once its delay is over, and not before
  local function drain(maxSteps)
    local guard = 0
    while guard < (maxSteps or 200) do
      guard = guard + 1
      if #pending > 0 then table.remove(pending, 1)()
      elseif auto.active() then
        now = now + 1
        auto.update()
      else break end
    end
  end

  reset()
  world.roads = { eastRoad('r', 3200, 20, 0) }
  world.errorCalls = { [2] = 'timed out', [3] = 'RuntimeError' }      -- the second window fails twice, then answers
  local res = { }
  auto.start(EVENT, stageOf(lineEast(3000, 200)), function(o, m, w) res.ok, res.why = o, w end)
  table.remove(pending, 1)()           -- window 1 answers
  table.remove(pending, 1)()           -- window 2 times out
  local calls = world.calls
  T.check(#pending == 0 and calls == 2, 'a window that timed out is not asked again at once (' .. world.calls .. ')')
  T.check(auto.TIMEOUT_RETRY_DELAY_S >= 10 and auto.RETRY_DELAY_S < auto.TIMEOUT_RETRY_DELAY_S,
    'a timeout waits longer than another error (' .. auto.TIMEOUT_RETRY_DELAY_S .. ' s)')
  now = now + auto.TIMEOUT_RETRY_DELAY_S - 0.5
  auto.update()
  T.check(world.calls == 2, 'nor before TIMEOUT_RETRY_DELAY_S (' .. world.calls .. ')')
  now = now + 0.5
  auto.update()
  T.check(world.calls == 3, 'but once it is over (' .. world.calls .. ')')
  table.remove(pending, 1)()           -- window 2 again: RuntimeError
  T.check(#pending == 0 and world.calls == 3, 'an exception is not asked again at once either')
  now = now + auto.RETRY_DELAY_S - 0.5
  auto.update()
  T.check(world.calls == 3, 'nor before RETRY_DELAY_S (' .. world.calls .. ')')
  now = now + 0.5
  auto.update()
  T.check(world.calls == 4, 'but after RETRY_DELAY_S, not the wait after a timeout (' .. world.calls .. ')')
  drain()
  T.check(res.ok == true and matchedFile() ~= nil, 'a window that failed twice and then answered: matched (' ..
    tostring(res.why) .. ')')
  local asked = 0
  for _, l in ipairs(logs) do if l:find('asking again in') then asked = asked + 1 end end
  T.check(asked == 2, 'and it was asked again twice (' .. asked .. ')')

  reset()
  world.roads = { eastRoad('r', 3200, 20, 0) }
  world.errorCalls = { [2] = 'timed out', [3] = 'timed out', [4] = 'timed out' }
  local how
  auto.start(EVENT, stageOf(lineEast(3000, 200)), function(o, m, w, h) how = { ok = o, why = w, how = h } end)
  drain()
  T.check(how and how.ok == false and how.how.kind == auto.FAILED,
    'a window that never answers: FAILED (' .. tostring(how and how.how and how.how.kind) .. ')')
  T.check(how and how.why:find('did not answer') and how.why:find('try') and not how.why:find('map data'),
    'saying BeamNG.Earth did not answer and to try again, not "no map data" (' .. tostring(how and how.why) .. ')')
  T.check(how and how.how.done == 1, 'at the window that failed (' .. tostring(how and how.how.done) .. ' done)')
  T.check(world.calls == 4 and matchedFile() == nil, 'asked 1 + 2 times, then nothing written (' .. world.calls .. ')')

  -- an answer that could not be read back is asked again too
  reset()
  world.roads = { eastRoad('r', 3200, 20, 0) }
  world.errorCalls = { [2] = 'the graph was built but could not be read back from x.json' }
  res = {}
  auto.start(EVENT, stageOf(lineEast(3000, 200)), function(o, m, w) res.ok, res.why = o, w end)
  drain()
  asked = 0
  for _, l in ipairs(logs) do if l:find('could not be read back from x.json: asking again in') then asked = asked + 1 end end
  T.check(res.ok == true and asked == 1, 'an answer that could not be read back: asked again, matched (' ..
    asked .. ')')

  -- errors that asking again cannot change (the fork's earthd.py road_graph): at once, with their own reason
  for _, c in ipairs({
    { "no map data (BeamNG.Earth's roads are off)", 'roads are off' },
    { 'the app was started without roads (--traffic off): there is no road graph', 'started without roads' },
    { 'no world yet (no anchor): ask once api.ready()', 'no world loaded yet' },
    { 'bad coordinates', 'bad coordinates' } }) do
    reset()
    world.roads = { eastRoad('r', 3200, 20, 0) }
    world.errorCalls = { [2] = c[1] }
    how = nil
    auto.start(EVENT, stageOf(lineEast(3000, 200)), function(o, m, w, h) how = { ok = o, why = w, how = h } end)
    drain()
    T.check(how and how.ok == false and how.how.kind == auto.FAILED and world.calls == 2,
      'a window answered "' .. c[1] .. '": not asked again (' .. world.calls .. ' calls)')
    T.check(how and how.why:find(c[2], 1, true) and not how.why:find('did not answer'),
      'and it says its own reason, not "did not answer" (' .. tostring(how and how.why) .. ')')
  end
  T.check(auto.windowErrorWhy('timed out') == nil and auto.windowErrorWhy('OSError') == nil
    and auto.windowErrorWhy('RuntimeError') == nil and auto.windowErrorWhy('no answer') == nil,
    'timeouts, exceptions and no answer are the ones asked again')
  T.check(auto.windowErrorWhy('IncompleteRead') == nil and auto.windowErrorWhy('BrokenProcessPool') == nil
    and auto.windowErrorWhy('ConnectionResetError') == nil,
    'any bare exception class name, one CamelCase word, is asked again')
  T.check(auto.windowErrorWhy('Broken pool') ~= nil and auto.windowErrorWhy('Nothing') ~= nil,
    'but not words with a space, nor a plain capitalised word')
  T.check(auto.windowErrorWhy('something new') ~= nil, 'an error not known is said as it came, not asked again')

  -- cancelled while waiting to ask again: nothing is asked
  reset()
  world.roads = { eastRoad('r', 3200, 20, 0) }
  world.errorCalls = { [2] = 'timed out' }
  auto.start(EVENT, stageOf(lineEast(3000, 200)), function() end)
  table.remove(pending, 1)()
  table.remove(pending, 1)()
  auto.cancel()
  now = now + 10
  auto.update()
  T.check(world.calls == 2, 'stopped while waiting to ask again: not asked (' .. world.calls .. ')')

  -- a window with cells missing is not an error: no retry, the coverage ending as before
  reset()
  world.roads = { eastRoad('r', 3200, 20, 0) }
  world.incompleteAt, world.errorCalls = 2, nil
  local res3 = run(EVENT, stageOf(lineEast(3000, 200)))
  local again = 0
  for _, l in ipairs(logs) do if l:find('asking again') then again = again + 1 end end
  T.check(res3.ok == false and again == 0 and tostring(res3.why):find('no map data'),
    'a window with cells missing is not asked again, and still says no map data (' .. tostring(res3.why) .. ')')
  auto.wall = hadWall
end

------------------------------------------------------------------------------------------ the grid (1.7.3, item 6)

-- build's distance of each node to the organisers' line, and match's maxOff, now come off a grid of the line's
-- segments (M.NEAR_GRID) instead of every node against every segment. The same file, figure for figure: a stage that
-- wanders, the road on it, a parallel road 20 m off, side roads, roads either side of the corridor's edge, one far
-- out at 2 km, and long straights whose middles are what decide them.
do
  local function deepEq(a, b, path)
    if type(a) ~= type(b) then return false, path end
    if type(a) ~= 'table' then
      if a == b then return true end
      return false, path .. ' (' .. tostring(a) .. ' vs ' .. tostring(b) .. ')'
    end
    for k, v in pairs(a) do
      local ok, at_ = deepEq(v, b[k], path .. '.' .. tostring(k))
      if not ok then return false, at_ end
    end
    for k in pairs(b) do if a[k] == nil then return false, path .. '.' .. tostring(k) .. ' (missing)' end end
    return true
  end
  local graph = { nodes = {}, edges = {} }
  local seq = 0
  local function road(pts, link)
    local prev = link
    for _, q in ipairs(pts) do
      seq = seq + 1
      local name = 'g' .. seq
      local ll = at(q[1], q[2], 100 + q[1] * 0.005)
      graph.nodes[name] = { lat = ll[1], lon = ll[2], alt = ll[3], radius = q[3] or 3.5 }
      if prev then graph.edges[#graph.edges + 1] = { prev, name } end
      prev = name
    end
    return prev
  end
  -- the organisers' line: 6 km wandering north and south of y = 0, a point every ~25 m
  local line, wob = {}, function(x) return 120 * math.sin(x / 700) + 15 * math.sin(x / 90) end
  for x = 0, 6000, 25 do local p = at(x, wob(x)) line[#line + 1] = { p[1], p[2] } end
  -- the road on it (2-6 m off it), every 10 m
  local main = {}
  for x = -40, 6040, 10 do main[#main + 1] = { x, wob(x) + 2 + 4 * math.sin(x / 33) } end
  road(main)
  -- a parallel road 20 m north, every 15 m; a narrower one (for the narrows) on part of it
  local par = {}
  for x = 500, 4500, 15 do par[#par + 1] = { x, wob(x) + 20, x > 2500 and 1.5 or 3.5 } end
  road(par)
  -- side roads off the main road's nodes, out to 250, 310, 880, 920 and 2000 m: long straights of one edge each
  local function mainNode(x) return 'g' .. (math.floor((x + 40) / 10) + 1) end
  for _, sd in ipairs({ { 800, 250 }, { 1600, 310 }, { 2400, 880 }, { 3200, 920 }, { 4000, 2000 } }) do
    local x0, off = sd[1], sd[2]
    road({ { x0 + 30, wob(x0) + off / 2 }, { x0 + 60, wob(x0) + off } }, mainNode(x0))
    road({ { x0 - 30, wob(x0) - off / 2 }, { x0 - 60, wob(x0) - off } }, mainNode(x0))
  end
  -- roads lying along the corridor's edge, 290 to 310 m off and 880 to 920 m off, and one crossing the line
  -- diagonally from 1.5 km away
  for _, off in ipairs({ 290, 300, 310, 880, 900, 920, -295, -905 }) do
    local pts = {}
    for x = 1000, 5000, 40 do pts[#pts + 1] = { x, wob(x) + off } end
    road(pts)
  end
  local diag = {}
  for k = 0, 60 do diag[#diag + 1] = { 2000 + k * 50, -1500 + k * 50 } end
  road(diag)
  -- a long straight whose ends are near the line and whose middle is not (a chord across the line's big bend)
  road({ { 300, wob(300) + 3 }, { 2000, wob(2000) + 3 } })
  -- an edge from the line out past its end, as far again: its far node is ~800 m off (past 2 x CORRIDOR_M) and the
  -- edge is still kept, because its other end and its middle are both on the line -- the case the reach must cover
  local endX, endY = 6000, wob(6000)
  local fromX, fromY = 5200, wob(5200)
  local farName = road({ { fromX, fromY }, { 2 * endX - fromX, 2 * endY - fromY } })
  local stage = { id = 'grid-stage', name = 'Grid', line = line,
    controls = { atc = { lat = at(-30, 5)[1], lon = at(-30, 5)[2] } } }

  local was = auto.NEAR_GRID
  auto.NEAR_GRID = false
  local old = auto.match(stage, graph)
  local fr = auto.frame(line[1][1], line[1][2])
  local kml = {}
  for i, q in ipairs(line) do kml[i] = fr.xy(q[1], q[2]) end
  local gOld = auto.build(graph, kml, fr)
  auto.NEAR_GRID = true
  local new = auto.match(stage, graph)
  local gNew = auto.build(graph, kml, fr)
  auto.NEAR_GRID = was
  T.check(old and new and #old.points > 1000 and old.roadEdges > 100,
    'grid: the stage matches (' .. tostring(old and #old.points) .. ' points, ' .. tostring(old and old.roadEdges) ..
    ' edges)')
  old.date, new.date, old.seconds, new.seconds = nil, nil, nil, nil
  local same, where = deepEq(old, new, 'file')
  T.check(same, 'grid: the matched file is the same as measuring every segment' .. (where and (': ' .. where) or ''))
  T.check(old and old.maxOffMapLineM > 0 and old.maxOffMapLineM == new.maxOffMapLineM,
    'grid: maxOffMapLineM the same (' .. tostring(old and old.maxOffMapLineM) .. ')')
  -- and the graph under it: every edge kept or dropped, and every weight, the same
  local sameEdges, edgeWhere = deepEq(gOld.nbr, gNew.nbr, 'nbr')
  T.check(sameEdges and gOld.edges == gNew.edges,
    'grid: every edge and every weight the same (' .. gOld.edges .. ' / ' .. gNew.edges .. ')' ..
    (edgeWhere and (': ' .. edgeWhere) or ''))
  T.check(next(gNew.nbr[farName]) ~= nil and gOld.near[farName] > 2 * auto.CORRIDOR_M,
    string.format('grid: the edge out to a node %.0f m off is kept', gOld.near[farName]))
  local exact, far, wrong, all = 0, 0, 0, 0
  for name, d in pairs(gNew.near) do
    all = all + 1
    if d == math.huge and gOld.near[name] > auto.NEAR_REACH_M then far = far + 1
    elseif d == gOld.near[name] then exact = exact + 1
    else wrong = wrong + 1 end
  end
  T.check(far > 0 and wrong == 0 and exact + far == all,
    'grid: every node within the reach measured exactly, only those past it "too far" (' .. exact .. ' exact, ' ..
    far .. ' far, ' .. wrong .. ' wrong)')
end

T.done('test_autorecce')
