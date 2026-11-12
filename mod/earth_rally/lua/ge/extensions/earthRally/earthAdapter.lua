-- earthRally/earthAdapter: everything Earth Rally asks of BeamNG.Earth, in one place. Its public modding API
-- (beamngEarth_api, docs/ADDONS.md in BeamNG.Earth) first; the few internals it has no API for yet (moving the
-- world's origin to a chosen spot, the rebase distance) behind feature checks, so a BeamNG.Earth update that changes
-- them shows a clear message here instead of breaking the stage code.
local M = {}

M.MIN_API_MINOR = 6        -- toGame / toGeo (BeamNG.Earth API 1.6)

local function api() return rawget(_G, 'beamngEarth_api') end
local function core() return rawget(_G, 'beamngEarth_core') end

-- BeamNG.Earth there and new enough? true, or false and why (shown in the window).
function M.check()
  local a = api()
  if not a then return false, 'BeamNG.Earth is not installed (or not loaded)' end
  local major, minor = a.version()
  if major ~= 1 or (minor or 0) < M.MIN_API_MINOR or not a.has('transform') then
    return false, string.format('BeamNG.Earth is too old (its modding API is %s.%s; Earth Rally needs 1.%d)',
      tostring(major), tostring(minor), M.MIN_API_MINOR)
  end
  if not a.inWorld() then return false, 'Load the BeamNG.Earth level (Freeroam > BeamNG.Earth)' end
  return true
end

function M.ready() local a = api() return a ~= nil and a.ready() end
function M.pose() local a = api() return a and a.pose() end
function M.toGame(lat, lon, h) local a = api() if a then return a.toGame(lat, lon, h) end end
function M.toGeo(x, y, z) local a = api() if a then return a.toGeo(x, y, z) end end
function M.teleport(lat, lon, name) local a = api() if not a then return false, 'no BeamNG.Earth' end return a.teleport(lat, lon, name) end
function M.notify(text, s) local a = api() if a then a.notify(text, s) end end
function M.gpsRoute(points) local a = api() if a and a.has('gpsRoute') then return a.gpsSetRoute(points) end return false, 'no GPS routes' end
function M.gpsClear() local a = api() if a then a.gpsClear() end end
-- (BeamNG.Earth's GPS to one place: the route planned on its roads, on the map and with arrows on the road)
function M.gpsSet(lat, lon, name) local a = api() if not (a and a.gpsSet) then return false, 'no BeamNG.Earth GPS' end
  local ok, r, why = pcall(a.gpsSet, lat, lon, name) if not ok then return false, tostring(r) end return r, why end

-- The world's origin now (lat, lon), or nil.
function M.anchor()
  local p = M.pose()
  if p then return p.anchorLat, p.anchorLon end
end

-- A rebase half done (the vehicles moved, the rest not yet): positions are not to be trusted this frame.
function M.rebasing()
  local a = api()
  if a and a.has('rebase') then return a.rebasing() end
  local c = core()
  local ok, st = pcall(function() return c and c._state and c._state() end)
  return ok and type(st) == 'table' and st.rebasing ~= nil or false
end

------------------------------------------------------------------------------------------
-- origin moves: BeamNG.Earth's rebased event (API 1.7) where it has it, else noticed by watching the origin

local listeners, nextId = {}, 0
local lastLat, lastLon = nil, nil
local apiHandle = nil

function M.onMoved(fn)
  nextId = nextId + 1
  listeners[nextId] = fn
  return nextId
end
function M.offMoved(id) listeners[id] = nil end

local function fire(info)
  lastLat, lastLon = info.lat, info.lon
  for _, fn in pairs(listeners) do
    local ok, err = pcall(fn, info)
    if not ok then log('E', 'earthRally', 'origin moved: a listener failed: ' .. tostring(err)) end
  end
end

-- Which way origin moves are heard: 'event' (BeamNG.Earth tells us) or 'watch' (we compare every frame).
function M.moveSource() return apiHandle and 'event' or 'watch' end

function M.update()
  local a = api()
  if not a then return end
  if not apiHandle and a.has('rebase') then
    apiHandle = a.on('rebased', function(info) fire({ lat = info.lat, lon = info.lon, oldLat = info.oldLat,
      oldLon = info.oldLon, purpose = info.purpose, source = 'event' }) end)
  end
  if apiHandle then return end
  if M.rebasing() then return end
  local la, lo = M.anchor()
  if la and (la ~= lastLat or lo ~= lastLon) then
    local old = lastLat and { lastLat, lastLon }
    if old then fire({ lat = la, lon = lo, oldLat = old[1], oldLon = old[2], purpose = 'unknown', source = 'watch' })
    else lastLat, lastLon = la, lo end
  end
end

function M.reset()
  local a = api()
  if a and apiHandle then a.off(apiHandle) end
  apiHandle, lastLat, lastLon = nil, nil, nil
end

------------------------------------------------------------------------------------------
-- internals (no API yet)

-- Move the world's origin to lat, lon without moving the car (BeamNG.Earth's core.rebaseTo, as its BeamMP shared
-- origin does). true once asked, or false and why. It happens a few frames later, or not at all if BeamNG.Earth
-- drops it: the caller watches M.anchor().
--
-- The camera: at a rebase BeamNG.Earth moves every camera vector it takes for a world position, those within
-- RADIUS_MIN..MAX (1-5 km) of the player (camshift.lua), the rest being offsets and rotations near (0, 0, 0). Its own
-- rebases happen 15 km out, where the two never mix; this one comes right after a teleport, with the player within a
-- kilometre of the origin, so the chase camera's offsets were moved too: the camera went off to the origin, far from
-- the car. For this move only, positions are those within CAMERA_NEAR_M of the player (the camera trails the car
-- by a few metres); M.originMoved() puts BeamNG.Earth's radius back.
M.CAMERA_NEAR_M = 30
local camRadius = nil
local function camshift()
  local ok, cs = pcall(require, 'beamngEarth/camshift')
  return ok and type(cs) == 'table' and cs.RADIUS_MIN and cs or nil
end
function M.originMoved()
  local cs = camshift()
  if cs and camRadius then cs.RADIUS_MIN, cs.RADIUS_MAX = camRadius[1], camRadius[2] end
  camRadius = nil
end

function M.moveOriginTo(lat, lon)
  local c = core()
  if not (c and type(c.rebaseTo) == 'function') then return false, 'this BeamNG.Earth cannot move its origin on request' end
  local cs = camshift()
  if cs and not camRadius then
    camRadius = { cs.RADIUS_MIN, cs.RADIUS_MAX }
    cs.RADIUS_MIN, cs.RADIUS_MAX = M.CAMERA_NEAR_M, M.CAMERA_NEAR_M
  end
  local ok, res, why = pcall(c.rebaseTo, lat, lon)
  if not ok or res ~= true then M.originMoved() end
  if not ok then return false, tostring(res) end
  return res == true, why
end

-- BeamNG.Earth's rebase distance (m from the origin before it moves the world), and setting it (clamped by it to
-- 2000..16000). nil when it cannot be read.
function M.rebaseDistance()
  local ok, rb = pcall(require, 'beamngEarth/rebase')
  return ok and type(rb) == 'table' and tonumber(rb.distance) or nil
end
function M.setRebaseDistance(m)
  local c = core()
  if c and type(c.setRebaseDistance) == 'function' then
    local ok, d = pcall(c.setRebaseDistance, m)
    return ok and d or nil
  end
end

return M
