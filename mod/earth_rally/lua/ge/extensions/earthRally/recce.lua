-- earthRally/recce: drive a stage once, untimed, and keep the line the car took (lat / lon / height every few
-- metres). Stages are timed and their pacenotes made on that line, not on the organisers' map: a hand-drawn map
-- cuts corners and has no heights, and BeamNG.Earth's roads come from OpenStreetMap, which may differ a little.
--
-- The way is shown by the stage's map line drawn on the ground ahead of the car (the next ~400 m). Not the GPS:
-- its route planner (OSRM) does not take cars on forest roads, so on such a stage it planned 25 km detours.
local geo = require('earthRally/geo')
local earth = require('earthRally/earthAdapter')
local events = require('earthRally/events')

local M = {}

M.RECORD_EVERY_M = 4
M.END_RADIUS_M = 12         -- this close to the stage's end, or level with it (after most of it): the recce is done
M.END_SHARE = 0.9
M.GUIDE_AHEAD_M = 400       -- of the map line drawn ahead of the car
M.GUIDE_BEHIND_M = 40
M.GUIDE_LIFT_M = 1.0        -- over the ground
M.GUIDE_WIDTH = 6
M.GUIDE_STEP_M = 15

local rec = nil             -- { event, stage, points, lastLat, lastLon, lengthM, mapPts, mapCum, origin, best, ... }
local guideColor, endColor = nil, nil

function M.active() return rec ~= nil end

-- (a flat frame round the map line's first point, metres east / north: progress along the line)
local function toFlat(o, lat, lon)
  return { x = geo.metres(o[1], o[2], o[1], lon) * (lon < o[2] and -1 or 1),
           y = geo.metres(o[1], o[2], lat, o[2]) * (lat < o[1] and -1 or 1) }
end

function M.start(event, stage)
  local o = stage.line[1]
  local pts = {}
  for i, p in ipairs(stage.line) do pts[i] = toFlat(o, p[1], p[2]) end
  rec = { event = event, stage = stage, points = {}, lengthM = 0, mapPts = pts, mapCum = geo.cumulative(pts),
          origin = o, best = 0, ground = {} }
  -- the line drawn: the map line every M.GUIDE_STEP_M (its points can be hundreds of metres apart), as lat / lon
  local ky = math.rad(1) * 6371008.8
  local kx = ky * math.cos(math.rad(o[1]))
  rec.guide = {}
  for i, q in ipairs(geo.resample(pts, M.GUIDE_STEP_M)) do rec.guide[i] = { o[1] + q.y / ky, o[2] + q.x / kx } end
  rec.guideCum = geo.cumulative(geo.resample(pts, M.GUIDE_STEP_M))
  earth.gpsClear()
  log('I', 'earthRally', 'recce started: ' .. stage.name)
end

-- Every frame while recording. Returns 'done' when the stage's end is reached.
function M.update()
  if not rec then return end
  if earth.rebasing() then return end
  local p = earth.pose()
  if not p or p.camera then return end
  local q = toFlat(rec.origin, p.lat, p.lon)
  local _, _, along, off = geo.locate(rec.mapPts, rec.mapCum, q)
  rec.here, rec.off = along, off
  if rec.lastLat then
    local d = geo.metres(rec.lastLat, rec.lastLon, p.lat, p.lon)
    if d < M.RECORD_EVERY_M then return end
    rec.lengthM = rec.lengthM + d
  end
  rec.points[#rec.points + 1] = { p.lat, p.lon, p.alt }
  rec.lastLat, rec.lastLon = p.lat, p.lon
  -- progress along the map line (never backwards), and the end
  if off < 150 and along > rec.best then rec.best = along end
  local total = rec.mapCum[#rec.mapCum]
  -- (level with the end: the car has come as far along the line as it goes, beside it)
  if rec.best >= total * M.END_SHARE and (geo.dist2d(q, rec.mapPts[#rec.mapPts]) <= M.END_RADIUS_M
      or (along >= total - 1 and off < 40)) then return 'done' end
end

-- The ground under a map point (game coordinates now), found once per world origin: a ray down from above the car.
local function groundZ(i, x, y, carZ)
  local key = i
  local g = rec.ground[key]
  if g ~= nil then return g or nil end
  local ray = rawget(_G, 'castRayStatic')
  if not ray then return nil end
  local top = carZ + 300
  local d = ray(vec3(x, y, top), vec3(0, 0, -1), 700)
  local z = d and d < 700 and top - d or false
  if z then rec.ground[key] = z end       -- (not found: asked again later, the ground may not be loaded yet)
  return z or nil
end

-- Draw the next stretch of the map line on the ground (every frame while recording).
function M.draw()
  if not rec or not rec.here or not debugDrawer then return end
  local la, lo = earth.anchor()
  if la ~= rec.groundLat or lo ~= rec.groundLon then rec.ground, rec.groundLat, rec.groundLon = {}, la, lo end
  local p = earth.pose()
  if not p then return end
  guideColor = guideColor or ColorF(1, 0.55, 0.1, 0.9)
  endColor = endColor or ColorF(0.2, 1, 0.3, 0.9)
  local s0, s1 = rec.here - M.GUIDE_BEHIND_M, rec.here + M.GUIDE_AHEAD_M
  local line, cum = rec.guide, rec.guideCum
  local prev = nil
  for i = 1, #line do
    local s = cum[i]
    if s >= s0 - 200 and s <= s1 + 200 then
      local x, y = earth.toGame(line[i][1], line[i][2], 0)
      if x then
        local z = groundZ(i, x, y, p.z)
        local pt = z and vec3(x, y, z + M.GUIDE_LIFT_M) or nil
        if pt and prev and s >= s0 then
          debugDrawer:drawLineInstance(prev, pt, M.GUIDE_WIDTH, guideColor)
        end
        prev = pt
        if i == #line and pt then debugDrawer:drawSphere(pt + vec3(0, 0, 3), 3, endColor) end
      end
    elseif s > s1 + 200 then
      break
    end
  end
end

function M.progress()
  if not rec then return nil end
  return rec.best / rec.mapCum[#rec.mapCum], rec.lengthM, #rec.points, rec.off
end

-- Stop; keep: save what was recorded (only when it covers most of the stage, unless forced).
function M.stop(keep, force)
  if not rec then return false end
  local r = rec
  rec = nil
  if not keep then log('I', 'earthRally', 'recce cancelled') return false, 'cancelled' end
  local share = r.best / r.mapCum[#r.mapCum]
  if share < M.END_SHARE and not force then
    return false, string.format('only %.0f %% of the stage was driven: not saved', share * 100)
  end
  events.saveRecce(r.event.id, r.stage.id, { format = 1, stage = r.stage.id, lengthM = r.lengthM,
    date = os.date('!%Y-%m-%dT%H:%M:%SZ'), points = r.points })
  log('I', 'earthRally', string.format('recce saved: %s, %.0f m, %d points', r.stage.name, r.lengthM, #r.points))
  return true
end

return M
