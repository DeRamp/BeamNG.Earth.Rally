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
  local ok, r, why = pcall(a.gpsSet, lat, lon, name) if not ok then return false, tostring(r) end
  if not r then return false, why or 'BeamNG.Earth\'s GPS did not take the place' end
  return true end

------------------------------------------------------------------------------------------
-- the road graph (the auto recce's one dependency on BeamNG.Earth beyond the pose)

-- Can this BeamNG.Earth hand out a window of its AI road graph at a point we name (api.roadGraph)?
--
-- Nothing else in Earth Rally may ask: this is the capability gate the auto recce is built behind. With a
-- BeamNG.Earth that has no such call the auto recce is simply unavailable and everything else behaves exactly as it
-- did -- there is no fallback path that drives the corridor itself, because that is the recce 1.3.0 exists to
-- remove (docs/plan-1.3.0.md, the spike's verdict).
function M.hasRoadGraph()
  local a = api()
  return (a ~= nil and type(a.has) == 'function' and a.has('roadGraph') == true and type(a.roadGraph) == 'function')
end

-- One window of BeamNG.Earth's AI road graph round (lat, lon): true once asked, or false and why. The callback is
-- given BeamNG.Earth's own answer table, which the auto recce reads:
--   { nodes = { [name] = { x, y, z, radius } },    the current anchor frame; z the drivable surface, radius the half
--                                                  width. Names are stable across windows and across anchors.
--     edges = { { inNode, outNode, oneWay, lanesOut, lanesIn, speedMs, drivability, radius, ... } },
--     complete,                                    false where map cells were not on disk (nothing is downloaded)
--     error }                                      a reason instead of a graph (a timed-out request answers this)
--
-- opts: { radius = m (the window is a square of this half size), cachedOnly = true }. The positions are game
-- coordinates in the frame current when the window was built, so a caller converts them with M.toGeo as they
-- arrive and keeps nothing in game coordinates: a rebase stales every one of them.
function M.roadGraph(lat, lon, opts, callback)
  local a = api()
  if not M.hasRoadGraph() then return false, 'this BeamNG.Earth cannot hand out its road graph' end
  local ok, res, why = pcall(a.roadGraph, lat, lon, opts, callback)
  if not ok then return false, tostring(res) end
  if res == false then return false, why or 'BeamNG.Earth refused the road graph request' end
  return true
end

-- Can BeamNG.Earth pre-cache the ground along a route? (1.3.1, has('areaRoute').) The same gate as the road
-- graph: without it the auto recce works exactly as 1.3.0 did -- only where the player has already been -- and
-- offers no download. Nothing else in Earth Rally may ask.
function M.hasAreaRoute()
  local a = api()
  return (a ~= nil and type(a.has) == 'function' and a.has('areaRoute') == true
          and type(a.areaPlan) == 'function' and type(a.areaAdd) == 'function')
end

-- The LAYERS an auto recce needs, and only those. Measured in a game 2026-11-14 on a 1.26 km stage: the whole
-- ground is 308 MB over a 10 km line, `{'roads'}` is 18 MB over 1.26 km -- about a tenth of the bytes and a
-- fifteenth of the items. The pinned disk does NOT fall in step (36.8 MB against 18 MB downloaded) because a
-- cell's raw source blocks are shared between its layers and arrive whichever layer asked for them.
M.AREA_LAYERS = { 'roads' }

-- The corridor's half width. 300 m each side of the line: wide enough that a stage which leaves the organisers'
-- line is still covered, and the figure every cost in docs/plan-1.3.1.md was measured at.
M.AREA_HALF_M = 300

-- What a corridor along `points` ({ { lat, lon } ... }) would cost, without downloading or saving anything.
-- callback is given BeamNG.Earth's own answer: { ok, km, km2, items, missing, downloadBytes, diskBytes, seconds,
-- days, hosts, excluded, layers, error }.
--
-- Show the player `downloadBytes` and nothing else, which is what BeamNG.Earth's own documentation asks for:
-- `seconds` is a serial-request model with no bandwidth in it (it said 132 s for a download that took 43),
-- `days` is 0 nearly everywhere, and `km2` is the corridor's geometry, far smaller than the ground actually
-- fetched -- the plan dilates it by two map cells all round.
function M.areaPlan(points, callback)
  local a = api()
  if not M.hasAreaRoute() then return false, 'this BeamNG.Earth cannot pre-cache the ground along a route' end
  local ok, res, why = pcall(a.areaPlan, points, { half = M.AREA_HALF_M, layers = M.AREA_LAYERS }, callback)
  if not ok then return false, tostring(res) end
  if not res then return false, why or 'BeamNG.Earth refused the estimate' end
  return true
end

-- Add a saved area along `points`: callback gets { ok, id, error }. **This is not a function call with a side
-- effect.** It puts a persistent, pinned object in the player's world -- visible in their area list, surviving a
-- restart, one of ten slots, and never evicted by "Clear cache" -- so it is only ever called after the player has
-- been shown the figure and said yes.
--
-- `fast` is never passed and BeamNG.Earth's call takes no argument for it. In fast mode BeamNG.Earth's own
-- core.lua pauses the player's game for any client on any fast area, which mid-stage would stop the physics under
-- a run with Earth Rally getting no say.
function M.areaAdd(points, name, callback)
  local a = api()
  if not M.hasAreaRoute() then return false, 'this BeamNG.Earth cannot pre-cache the ground along a route' end
  local ok, res, why = pcall(a.areaAdd, points,
    { half = M.AREA_HALF_M, layers = M.AREA_LAYERS, name = name }, callback)
  if not ok then return false, tostring(res) end
  if not res then return false, why or 'BeamNG.Earth refused the area' end
  return true
end

-- How a saved area is getting on: { id, name, state, done, total, unavailable, msg, mode, half, layers }, or nil.
-- Read from the area list BeamNG.Earth already broadcasts, so it is cheap to poll every frame.
--
-- `state == 'done'` does NOT mean every tile arrived. After enough failed passes the items still failing are
-- counted in `unavailable`, the area is marked done and `msg` carries words only the player can act on ("Resume
-- tries again"). Measured on this machine: an area finished done with 122 of 1079 items unavailable. So a caller
-- re-checks the ground rather than trusting `done`, and surfaces `msg` rather than swallowing it.
function M.areaStatus(id)
  local a = api()
  if not (M.hasAreaRoute() and type(a.areaStatus) == 'function') then return nil end
  local ok, res = pcall(a.areaStatus, id)
  if not ok then return nil end
  return res
end

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

-- BeamNG.Earth's place-name strip and connection banner, off screen while a stage runs: Earth Rally shows the same
-- things in its own panel, and three boxes at three widths was a mess (the user, 2026-11-13).
--
-- Not by switching them off. `statusbar.enabled = false` also stops the 'where' request that fills the place
-- (statusbar.lua: `function M.request(...) if not M.enabled ... then return nil end`), so the road name we want to
-- show would freeze and the game's minimap would lose its label with it; and that flag is the player's own
-- `statusBar` setting.
--
-- Instead the two apps are simply not in our stage layout, so nothing draws them -- and we tell BeamNG.Earth they
-- are on screen, because otherwise it draws each with ImGui itself (its core.lua: `if not hudapps.mounted('status')
-- then statusbar.draw(...)`), which would be worse than leaving them alone.
--
-- `core.hudApp` is an internal, not a published entry point. It is not in BeamNG.Earth's docs/ADDONS.md, which is
-- the surface it does publish; it is the call its own apps make every three seconds to announce themselves, and what
-- we tell it is not true -- that its apps are on screen, when we have taken them out of the layout. That is our risk
-- to carry. What makes it a small one:
--
--   * The state we assert is BeamNG.Earth's own default. All three of its apps are in both layouts it ships
--     (beamngEarth.uilayout.json, beamngEarthMP.uilayout.json), so "status and banner mounted" is what almost every
--     player is in, every session, and the code that reads it runs constantly upstream. We are not pushing another
--     project's bookkeeping into a corner nobody exercises.
--   * Only the three imgui draw gates read mount state at all (its core.lua, ~2270). The place request, the payload,
--     the minimap label and api.place() do not, so a held strip costs no data -- which is why M.place() below keeps
--     working through a stage.
--   * It fails cheaply. If the call is gone, holdStrips returns false; if a strip is renamed it returns false too
--     (the check above). Either way the strips stay on screen for a stage: ugly for one run, nothing lost or stuck.
--
-- What none of that covers: if BeamNG.Earth ever gates its place request on `mounted` -- an ordinary optimisation,
-- and `mounted` already gates its payload sends -- our assertion would quietly stop the road name feeding M.place()
-- and the HUD's own row, with no error anywhere. That is the one to watch for, and the one a version check cannot
-- catch, because core.hudApp is not part of the versioned API surface: a change to it need not bump the minor.
--
-- An API for this was drafted and deliberately not sent (docs/plan-1.3.0.md, "The strips: no pull request"): the
-- shape that reads well for a third-party mod would also let any mod take BeamNG.Earth's data credits down, and a
-- CC BY attribution strip is the one thing that must not have a one-call off switch. Earth Rally never touches
-- credits by either route -- EARTH_STRIPS is status and banner, and our own stage layout keeps `beamngEarthCredits`
-- on screen (earthRallyStage.uilayout.json), so the attribution stays up, drawn by its own app, all through a stage.
--
-- Held, not set once: those apps fire `hudApp(name, false)` as they are destroyed in the layout swap, so the runner
-- asserts this every frame while the stage layout is on. Given back on every way out -- runner's layoutOff, and
-- main.onExtensionUnloaded for the mod being switched off part way through a stage -- because while BeamNG.Earth
-- believes an app has a strip it leaves its own drawing of it out, and the banner is where "BeamNG.Earth server not
-- running" and "the car is held in place" are said.
M.EARTH_STRIPS = { 'status', 'banner' }
function M.holdStrips(on)
  local c = core()
  if not (c and c.hudApp) then return false end
  local want = on and true or false
  local ok = true
  for _, n in ipairs(M.EARTH_STRIPS) do
    -- What it answers matters, not only that it did not throw: BeamNG.Earth's setMounted returns false for a strip
    -- name it does not know, with no error, so a renamed strip would otherwise look held to us while it was still
    -- on screen. (Releasing answers false for both the real case and the unknown name, which is harmless: giving
    -- back a strip nobody holds does nothing.)
    local okCall, res = pcall(c.hudApp, n, want)
    if not okCall or res ~= want then ok = false end
  end
  return ok
end

-- Where the car is, from BeamNG.Earth's public API: { street, place, region, country }, each only when it has one.
function M.place()
  local a = api()
  if not (a and a.has and a.has('place') and a.place) then return nil end
  local ok, p = pcall(a.place)
  return (ok and type(p) == 'table') and p or nil
end

-- What BeamNG.Earth's connection banner is saying: { id, level, text, visible }. The id is the stable part
-- ('noserver', 'lost', 'edge', 'drophold', 'starting'); the HUD shows a word of its own for it rather than the
-- sentence, which is far too long for a stage. nil when it cannot be read.
function M.earthBanner()
  local ok, bn = pcall(require, 'beamngEarth/banner')
  if not (ok and type(bn) == 'table' and bn.current) then return nil end
  local okC, c = pcall(bn.current)
  if not (okC and type(c) == 'table') then return nil end
  return { id = c.id, level = c.level, text = c.text, visible = c.visible }
end

-- How much of the world round the car is still arriving: { done, total }, nil once it is all there.
--
-- No API for this: BeamNG.Earth's status text carries `loading: done/total` (its statusbar.loadingLine reads the
-- same thing), and that text is in core's state. It is a queue depth, not a share of the world -- the total grows
-- as more is queued -- so it is shown as the fraction BeamNG.Earth itself shows, never as a percentage, which would
-- appear to count backwards.
function M.loading()
  local c = core()
  local ok, st = pcall(function() return c and c._state and c._state() end)
  if not (ok and type(st) == 'table' and type(st.status) == 'string') then return nil end
  local done, total = st.status:match('loading:%s*(%d+)/(%d+)')
  done, total = tonumber(done), tonumber(total)
  if not (done and total and total > 0 and done < total) then return nil end
  return { done = done, total = total }
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
