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
M.SETTLE_S = 1.0        -- once a fresh graph is there, held this long (a second one may follow the first)
M.NEAR_M = 300          -- the car set down farther than this from the window's centre: the window is not trusted
M.SKIP_M = 150          -- the car already this near the window's centre, with a graph round it: no teleport
M.RADIUS_M = 800        -- the window the auto recce plans with: the graph reaches ~1100 m, less NEAR_M of slack
M.NAME = 'Earth Rally auto recce'

local function api() return rawget(_G, 'beamngEarth_api') end
local function core() return rawget(_G, 'beamngEarth_core') end
local function wall() return os.clock() end
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
  local p = where()
  local g = graph()
  local aid = anchorId()
  req = { lat = lat, lon = lon, callback = callback, t0 = wall(), home = opts.home == true,
          serial = g and g.serial, anchor = g and g.anchor }
  -- already there, with a graph built in this frame: read it as it is
  if p and settled() and g and g.anchor == aid and metres(p.lat, p.lon, lat, lon) <= M.SKIP_M then
    req.teleported, req.fresh = true, true
    return true
  end
  if not home and p then home = { lat = p.lat, lon = p.lon } end
  local okT, ok, why = pcall(api().teleport, lat, lon, M.NAME)
  if not okT or ok == false then
    req = nil
    return false, 'BeamNG.Earth would not teleport the car there (' .. tostring(okT and why or ok) .. ')'
  end
  req.teleported = true
  log('I', 'earthRally', string.format('auto recce walk: to %.5f, %.5f', lat, lon))
  return true
end

-- The car back where it was before the walk (a stop, a failure, the end). No wait: Earth's teleport runs on.
function M.goHome()
  local h = home
  home = nil
  req = nil
  if not h then return false end
  local a = api()
  if a and type(a.teleport) == 'function' then
    pcall(a.teleport, h.lat, h.lon, M.NAME)
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
  if wall() - q.t0 > M.TIMEOUT_S then
    log('W', 'earthRally', 'auto recce walk: no road graph round the car in ' .. M.TIMEOUT_S .. ' s')
    return answer({ error = 'timed out' })
  end
  if q.homing then
    -- (the last window's graph is kept; the car on its way back. Answered once the world is ready there, so the
    --  stage's own placing after the match does not race the teleport)
    if wall() - q.homedAt < 2.0 or not settled() then return end
    -- (the nodes were converted to lat / lon before the car went home: see below)
    return answer(q.result)
  end
  if not settled() then q.seenAt = nil return end
  local g = graph()
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
  local r = { nodes = g.nodes, edges = g.edges, complete = true, anchorLat = p.anchorLat, anchorLon = p.anchorLon }
  log('I', 'earthRally', string.format('auto recce walk: graph %s read, %.0f m from the window\'s centre',
    tostring(g.serial), off))
  if q.home and home then
    -- the last window: its nodes to lat / lon now, in this frame, before the car leaves it
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
    r = { geoNodes = geo, edges = g.edges, complete = true }
    local h = home
    home = nil
    pcall(a.teleport, h.lat, h.lon, M.NAME)
    log('I', 'earthRally', 'auto recce walk: last window read; the car taken back to where it was')
    q.homing, q.homedAt, q.result = true, wall(), r
    return
  end
  return answer(r)
end

M._req = function() return req end
M._home = function() return home end
return M
