-- roadWalk (upstream-earth): the road graph on an official BeamNG.Earth, read by teleporting the car to each window and
-- taking BeamNG.Earth's own traffic graph round it. Against a fake BeamNG.Earth: api, core._state and navgraph.
local T = dofile(TESTS .. '/testlib.lua')
function log() end

local now = 0
local st = { anchorId = 1 }
local pose = { lat = -34.0, lon = 117.0, anchorLat = -34.0, anchorLon = 117.0 }
local ready = true
local teleports = {}
local g = { anchor = 1, serial = 1, nodes = { a = { 0, 0, 0, 3 } }, edges = { { 'a', 'b' } } }
package.loaded['beamngEarth/navgraph'] = { currentGraph = function() return g end }
_G.beamngEarth_core = { _state = function() return st end }
_G.beamngEarth_api = {
  version = function() return 1, 8 end,
  earthVersion = function() return '1.10.1-beta' end,
  has = function(n) return n == 'transform' end,
  ready = function() return ready end,
  rebasing = function() return false end,
  pose = function() return pose end,
  teleport = function(lat, lon) teleports[#teleports + 1] = { lat, lon } ready = false return true end,
  toGeo = function(x, y, z) return pose.anchorLat + y / 111000, pose.anchorLon + x / 92000, z end,
}

local walk = require('earthRally/roadWalk')
local earth = require('earthRally/earthAdapter')
-- (a fake clock: roadWalk reads os.clock through its local; replace it)
os.clock = function() return now end

T.check(earth.roadGraphMode() == 'walk' and earth.hasRoadGraph(), 'no api.roadGraph: the walk is the road graph')
T.check(earth.roadGraphRadius() == walk.RADIUS_M, 'the walk plans smaller windows')

-- a window far away: teleported, and not answered from the graph that was there before
local got = nil
local ok = earth.roadGraph(-34.05, 117.0, { radius = 800 }, function(r) got = r end)
T.check(#teleports == 0, 'no teleport until the frame after, with the world ready')
walk.update()
T.check(ok and #teleports == 1, 'a far window: the car teleported there')
ready = true
walk.update(); now = now + 5; walk.update()
T.check(got == nil, 'the old frame\'s graph is not taken')
-- arrived: new anchor, new graph
st.anchorId = 2
pose = { lat = -34.05, lon = 117.0, anchorLat = -34.05, anchorLon = 117.0 }
g = { anchor = 2, serial = 7, nodes = { b = { 10, 10, 0, 4 } }, edges = { { 'a', 'b' } } }
walk.update()
T.check(got == nil, 'held SETTLE_S on a fresh graph first')
now = now + 2; walk.update()
T.check(got and got.geoNodes and got.geoNodes.b and got.complete, 'the fresh graph handed over, in lat / lon')

-- the last window: the car goes home before it is answered, the nodes already lat / lon
got = nil
ok = earth.roadGraph(-34.1, 117.0, { radius = 800, home = true }, function(r) got = r end)
walk.update()
T.check(ok and #teleports == 2, 'the last window: teleported')
ready = true; st.anchorId = 3
pose = { lat = -34.1, lon = 117.0, anchorLat = -34.1, anchorLon = 117.0 }
g = { anchor = 3, serial = 9, nodes = { c = { 0, 111, 0, 2 } }, edges = {} }
walk.update(); now = now + 2; walk.update()
T.check(#teleports == 3 and teleports[3][1] == -34.0, 'the car taken back to where the walk began')
T.check(got == nil, 'not answered until the world is ready at home')
now = now + 3; ready = true; walk.update()
T.check(got and got.geoNodes and got.geoNodes.c and math.abs(got.geoNodes.c.lat - (-34.099)) < 1e-6,
  'the last window answered in lat / lon, converted before the car left')
T.check(not earth.roadGraphHome(), 'home already: nothing more to do')

-- set down too far from the window: an error, which the auto recce asks again for
got = nil
pose = { lat = -34.1, lon = 117.0, anchorLat = -34.1, anchorLon = 117.0 }
earth.roadGraph(-34.3, 117.0, {}, function(r) got = r end)
walk.update()
ready = true; st.anchorId = 4; g = { anchor = 4, serial = 11, nodes = {}, edges = {} }
now = now + 25; walk.update()
T.check(got and got.error and got.error:find('set down'), 'set down far off: an error, not a window')

-- a stop mid-walk: home
earth.roadGraph(-34.5, 117.0, {}, function() end)
local before = #teleports
T.check(earth.roadGraphHome() and #teleports == before + 1 and not walk.busy(), 'a stop takes the car back')

-- timed out
got = nil
earth.roadGraph(-34.6, 117.0, {}, function(r) got = r end)
ready = false
now = now + walk.TIMEOUT_S + 1; walk.update()
T.check(got and got.error == 'timed out', 'no graph in TIMEOUT_S: timed out (the auto recce waits and asks again)')

-- walkCache: the first window again is read from the cache, the car not moved
got = nil
local tp = #teleports
earth.roadGraph(-34.05, 117.0, { radius = 1000 }, function(r) got = r end)
ready = true; walk.update()
T.check(got and got.geoNodes and got.geoNodes.b and #teleports == tp, 'read before: from the cache, no teleport')
T.check(walk._cache.covered(-34.05, 117.0, 1000) and not walk._cache.covered(-34.05, 117.0, 1100),
  'covered: the kept square, not past it')
T.check(not walk._cache.covered(-34.2, 117.0, 500), 'ground never read is not covered')
-- too old: not trusted
local realNow = os.time
os.time = function() return realNow() + 31 * 86400 end
T.check(not walk._cache.covered(-34.05, 117.0, 1000), 'older than MAX_AGE_DAYS: walked again')
os.time = realNow
-- another BeamNG.Earth: thrown away
_G.beamngEarth_api.earthVersion = function() return '1.10.2-beta' end
T.check(not walk._cache.covered(-34.05, 117.0, 1000), 'another BeamNG.Earth version: walked again')
_G.beamngEarth_api.earthVersion = function() return '1.10.1-beta' end

-- a later read overlapping an earlier one: an edge across the later read's edge (one node inside its square, the
-- other past its graph) stays, since that read could not have it; an edge the read has both nodes of and not the
-- edge is gone. (Bolster Hollow: a 44 m link of the stage's road lost this way, the road cut in two)
do
  local C = walk._cache
  local K = 111320
  local function at(n, e) return { lat = 10 + n / K, lon = 20 + e / (K * math.cos(math.rad(10))) } end
  C.forget()
  -- first read round (0, 0): a chain p - q - r along the north, at 900, 1050, 1200 m east; and s - t
  local n1 = { p = at(0, 900), q = at(0, 1050), r = at(0, 1200), s = at(0, 0), t = at(10, 0) }
  T.check(C.store(n1, { { 'p', 'q' }, { 'q', 'r' }, { 's', 't' } }, 10, 20, 1500), 'first read kept')
  -- second read round 2150 m east (square 1075): q (1100 m west of it) is past its graph, r (950 m) inside it;
  -- it has s? no. It has r, and a road u near the car. s - t untouched. Then a read that has p and q but no p - q.
  local c2 = at(0, 2150)
  T.check(C.store({ r = at(0, 1200), u = at(0, 2150) }, {}, c2.lat, c2.lon, 1075), 'second read kept')
  local r = C.read(10, 20, 1500, 0)
  local has = {}
  for _, e in ipairs(r.edges) do has[e[1] .. e[2]] = true end
  T.check(has.qr, 'an edge across the new read edge is kept (q - r)')
  T.check(has.pq and has.st, 'edges away from it untouched')
  local c3 = at(0, 975)
  T.check(C.store({ p = at(0, 900), q = at(0, 1050), v = at(0, 975) }, {}, c3.lat, c3.lon, 1075), 'third read kept')
  r = C.read(10, 20, 1500, 0)
  has = {}
  for _, e in ipairs(r.edges) do has[e[1] .. e[2]] = true end
  T.check(not has.pq, 'a read with both nodes and not the edge: the edge is gone')
  C.forget()
end

-- a level teardown: forgotten, the car not moved
earth.roadGraph(-34.7, 117.0, {}, function() end)
walk.reset()
before = #teleports
T.check(not walk.busy() and not earth.roadGraphHome() and #teleports == before, 'reset: no teleport')

-- the fork's call wins where it is there
_G.beamngEarth_api.has = function(n) return n == 'transform' or n == 'roadGraph' end
_G.beamngEarth_api.roadGraph = function() return true end
T.check(earth.roadGraphMode() == 'api' and earth.roadGraphRadius() == nil, 'api.roadGraph there: the fork\'s path')

T.done('test_roadwalk')
