-- earthRally/roadWalk: the road graph on an official BeamNG.Earth, which has no api.roadGraph (modding API 1.8).
--
-- The fork's api.roadGraph builds a window with server/navgraph.py's `build`. An official BeamNG.Earth runs the same
-- builder already, for its own traffic: the AI road graph round the player (about 1100 m each way), sent after every
-- move and kept raw by its navgraph module (require('beamngEarth/navgraph').currentGraph(): the same nodes, the same
-- edges, the same node names). So a window is had by putting the car there and reading that graph: teleport, wait
-- for the world to be ready and for a graph built in the new frame round the car, hand it over.
--
-- Slower than the fork (every window is a teleport and a world load, with everything downloaded, not just the
-- roads) and it moves the car, which is put back where it was when the walk ends (`home`).
--
-- Only earthAdapter calls this, behind earthAdapter.roadGraph, with the same answer table the fork gives:
-- { nodes, edges, complete, error, anchorLat, anchorLon } (anchorLat / lon: the frame the nodes are in, current
-- when the answer is handed over).
local M = {}

M.TIMEOUT_S = 180       -- a teleport, the world loaded and a graph built round the car, at most this long
M.NO_GRAPH_S = 60      -- the world ready this long and no traffic graph at all: traffic or roads are off
M.SETTLE_S = 0.5        -- once a fresh graph is there, held this long (a second one may follow the first)
M.NEAR_M = 75           -- the car set down farther than this from the window's centre: the window is not trusted
                        -- (the graph, GRAPH_M round the car, must hold the window, RADIUS_M round its centre, with
                        --  a margin: 1100 - 1000 - 25. BeamNG.Earth's teleport landed 0 m off in the first walks)
M.GRAPH_M = 1100        -- BeamNG.Earth's traffic graph: a square this half size round the car (navgraph.WINDOW_M)
M.KEEP_MARGIN_M = 25    -- a read is kept as covering GRAPH_M less this round the car
M.RADIUS_M = 1000       -- the window the auto recce plans with: inside KEEP_M, so a window walked once is a cache hit
M.NAME = 'Earth Rally auto recce'

local walkCache = require('earthRally/walkCache')
M._cache = walkCache
local function api() return rawget(_G, 'beamngEarth_api') end
local function core() return rawget(_G, 'beamngEarth_core') end
local function wall() return os.clock() end

-- A teleport kept out of BeamNG.Earth's recent places and its saved spawn points (core.teleport's 'tool' kind,
-- { record = false }); api.teleport where that is not there.
local function teleport(lat, lon)
  local c = core()
  if type(c) == 'table' and type(c.teleport) == 'function' then return c.teleport(lat, lon, M.NAME, { record = false }) end
  return api().teleport(lat, lon, M.NAME)
end
M._wall = wall

local function navgraph()
  local ok, n = pcall(require, 'beamngEarth/navgraph')
  if ok and type(n) == 'table' and type(n.currentGraph) == 'function' then return n end
  return nil
end
M._navgraph = navgraph

-- Can this BeamNG.Earth be walked? Its teleport, its pose and the raw traffic graph, all there.
function M.available()
  local a, c = api(), core()
  return a ~= nil and type(a.teleport) == 'function' and type(a.pose) == 'function' and type(a.ready) == 'function'
     and type(c) == 'table' and type(c._state) == 'function' and navgraph() ~= nil
end

local function anchorId()
  local c = core()
  local ok, st = pcall(function() return c._state() end)
  if ok and type(st) == 'table' then return st.anchorId end
  return nil
end

local function graph()
  local n = navgraph()
  if not n then return nil end
  local ok, g = pcall(n.currentGraph)
  if ok and type(g) == 'table' and type(g.nodes) == 'table' and type(g.edges) == 'table' then return g end
  return nil
end

local function metres(lat1, lon1, lat2, lon2)
  local r = 6371000
  local p = math.pi / 180
  local x = (lon2 - lon1) * p * math.cos((lat1 + lat2) / 2 * p)
  local y = (lat2 - lat1) * p
  return math.sqrt(x * x + y * y) * r
end
M._metres = metres

local function where()
  local a = api()
  local ok, p = pcall(a.pose)
  if ok and type(p) == 'table' and p.lat and p.lon then return p end
  return nil
end

local function settled()
  local a = api()
  local ok, r = pcall(a.ready)
  if not (ok and r) then return false end
  if type(a.rebasing) == 'function' then
    local okR, rb = pcall(a.rebasing)
    if okR and rb then return false end
  end
  return true
end

local req = nil        -- { lat, lon, callback, t0, teleported, serial, anchor, seenAt, home }
local home = nil       -- { lat, lon } where the car was before the walk's first teleport

function M.busy() return req ~= nil end

local function answer(r)
  local q = req
  req = nil
  if q and q.callback then
    local ok, err = pcall(q.callback, r)
    if not ok then log('E', 'earthRally', 'auto recce walk: the window callback failed: ' .. tostring(err)) end
  end
end

-- One window round (lat, lon): true once asked, false and why if not. opts.home: put the car back where it was
-- before the walk began, once this window is read and before it is answered (the walk's last window).
function M.request(lat, lon, opts, callback)
  if req then return false, 'a window is already being walked to' end
  if not M.available() then return false, 'this BeamNG.Earth cannot be walked for its roads' end
  opts = opts or {}
  local g = graph()
  req = { lat = lat, lon = lon, callback = callback, t0 = wall(), home = opts.home == true,
          serial = g and g.serial, anchor = g and g.anchor, waiting = true }
  -- read before: answered from the cache next frame, the car not moved
  local okC, hit = pcall(walkCache.covered, lat, lon, opts.radius or M.RADIUS_M)
  if okC and hit then
    req.cached, req.waiting = true, false
    req.radius = opts.radius or M.RADIUS_M
  end
  -- (always a teleport: the graph round a car that is already there may be centred up to 500 m from it, and the
  --  client does not keep its centre, so it cannot be trusted to cover the window. The teleport itself waits in
  --  M.update until the world is ready, so `home` is never read from a car still on its way somewhere)
  return true
end

local function go(q)
  local p = where()
  local g = graph()
  q.serial, q.anchor = g and g.serial, g and g.anchor
  if not home and p then home = { lat = p.lat, lon = p.lon } end
  local okT, ok, why = pcall(teleport, q.lat, q.lon)
  if not okT or ok == false then
    return answer({ error = 'BeamNG.Earth would not teleport the car there (' .. tostring(okT and why or ok) .. ')' })
  end
  q.waiting, q.t0 = false, wall()
  log('I', 'earthRally', string.format('auto recce walk: to %.5f, %.5f', q.lat, q.lon))
end

-- The car back where it was before the walk (a stop, a failure, the end). No wait: Earth's teleport runs on.
function M.goHome()
  local h = home
  home = nil
  req = nil
  if not h then return false end
  local a = api()
  if a and type(a.teleport) == 'function' then
    pcall(teleport, h.lat, h.lon)
    log('I', 'earthRally', 'auto recce walk: the car taken back to where it was')
    return true
  end
  return false
end

-- Forget a walk without moving the car (the auto recce cancelled by something that moves it itself).
function M.reset() req, home = nil, nil end

-- Every frame, while a window is out.
function M.update()
  local q = req
  if not q then return end
  if q.cached and not q.homing then
    local okR, r = pcall(walkCache.read, q.lat, q.lon, q.radius, 200)
    if not okR then
      -- (a cache that cannot be read: walked instead)
      q.cached, q.waiting = false, true
      return
    end
    log('I', 'earthRally', 'auto recce walk: read from the cache, the car not moved')
    if q.home and home then
      local h = home
      home = nil
      pcall(teleport, h.lat, h.lon)
      log('I', 'earthRally', 'auto recce walk: last window from the cache; the car taken back to where it was')
      q.homing, q.homedAt, q.result = true, wall(), r
      return
    end
    return answer(r)
  end
  if q.waiting then
    if settled() then go(q) elseif wall() - q.t0 > M.TIMEOUT_S then return answer({ error = 'timed out' }) end
    return
  end
  if q.homing then
    -- (the last window's graph is kept; the car on its way back. Answered once the world is ready there, so the
    --  stage's own placing after the match does not race the teleport; its own deadline, and the window's data
    --  answered even if the trip home is slow)
    if wall() - q.homedAt > M.TIMEOUT_S then return answer(q.result) end
    if wall() - q.homedAt < 2.0 or not settled() then return end
    -- (the nodes were converted to lat / lon before the car went home: see below)
    return answer(q.result)
  end
  if wall() - q.t0 > M.TIMEOUT_S then
    log('W', 'earthRally', 'auto recce walk: no road graph round the car in ' .. M.TIMEOUT_S .. ' s')
    return answer({ error = 'timed out' })
  end
  if not settled() then q.seenAt = nil q.readyAt = nil return end
  q.readyAt = q.readyAt or wall()
  local g = graph()
  if not g and wall() - q.readyAt > M.NO_GRAPH_S then
    -- (BeamNG.Earth builds this graph only with its traffic and roads on: none at all, a minute after the world is
    --  ready, is that, not a slow build)
    return answer({ error = 'BeamNG.Earth sent no road graph: its traffic or roads are off' })
  end
  local aid = anchorId()
  if not (g and aid and g.anchor == aid) then q.seenAt = nil return end
  if not q.fresh and g.anchor == q.anchor and g.serial == q.serial then return end   -- the graph from before
  local p = where()
  if not p then return end
  local off = metres(p.lat, p.lon, q.lat, q.lon)
  if off > M.NEAR_M then
    if wall() - q.t0 > 20 then
      return answer({ error = string.format('the car was set down %.0f m from the window', off) })
    end
    return
  end
  -- held SETTLE_S on the same graph, so a second build right behind the first is the one read
  if q.seenSerial ~= g.serial then q.seenSerial, q.seenAt = g.serial, wall() return end
  if wall() - q.seenAt < M.SETTLE_S then return end
  log('I', 'earthRally', string.format('auto recce walk: graph %s read, %.0f m from the window centre',
    tostring(g.serial), off))
  -- its nodes to lat / lon now, in this frame (before the car can leave it), and kept for next time
  local a = api()
  local geo = {}
  for name, n in pairs(g.nodes) do
    local x, y, z, rad
    if type(n) == 'table' then x, y, z, rad = n[1] or n.x, n[2] or n.y, n[3] or n.z, n[4] or n.radius end
    if x then
      local ok, la, lo, al = pcall(a.toGeo, x, y, z or 0)
      if ok and la then geo[name] = { lat = la, lon = lo, alt = al, radius = rad } end
    end
  end
  local edges = {}
  for _, e in ipairs(g.edges) do if type(e) == 'table' then edges[#edges + 1] = { e[1], e[2] } end end
  local okS, err = pcall(walkCache.store, geo, edges, p.lat, p.lon, M.GRAPH_M - M.KEEP_MARGIN_M)
  if not okS then log('W', 'earthRally', 'auto recce walk: not kept in the cache: ' .. tostring(err)) end
  local r = { geoNodes = geo, edges = edges, complete = true }
  if q.home and home then
    local h = home
    home = nil
    pcall(teleport, h.lat, h.lon)
    log('I', 'earthRally', 'auto recce walk: last window read; the car taken back to where it was')
    q.homing, q.homedAt, q.result = true, wall(), r
    return
  end
  return answer(r)
end

M._req = function() return req end
M._home = function() return home end
return M
