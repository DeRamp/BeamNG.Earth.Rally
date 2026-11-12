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
M.START_NEAR_M = 60         -- recording begins once the car is this close to the stage line ...
M.START_WITHIN_M = 300      -- ... within this far of its start (the drive there is not the stage)
M.JUMP_M = 40               -- moved further than this between two points (a reset, a recovery): not driven
M.OFF_LINE_M = 150          -- progress counts only this close to the map line

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
  -- (followed from where it was: a stage passing close to itself does not make it jump ahead)
  local along, off = geo.follow(rec.mapPts, rec.mapCum, q, rec.here, 300, 1500, M.OFF_LINE_M)
  rec.here, rec.off = along, off
  if not rec.started then
    -- not recording until the car is at the stage: the drive to it is not the stage
    if off > M.START_NEAR_M or along > M.START_WITHIN_M then return end
    rec.started = true
    log('I', 'earthRally', 'recce: recording from here')
  end
  if rec.lastLat then
    local d = geo.metres(rec.lastLat, rec.lastLon, p.lat, p.lon)
    if d < M.RECORD_EVERY_M then return end
    if d > M.JUMP_M then
      rec.jumps = (rec.jumps or 0) + 1     -- (a reset or a recovery: the line goes on from here, not driven between)
    else
      rec.lengthM = rec.lengthM + d
    end
  end
  rec.points[#rec.points + 1] = { p.lat, p.lon, p.alt }
  rec.lastLat, rec.lastLon = p.lat, p.lon
  -- progress along the map line (never backwards), and the end
  if off < M.OFF_LINE_M and along > rec.best then rec.best = along end
  local total = rec.mapCum[#rec.mapCum]
  -- (level with the end: the car has come as far along the line as it goes, beside it)
  if rec.best >= total * M.END_SHARE and (geo.dist2d(q, rec.mapPts[#rec.mapPts]) <= M.END_RADIUS_M
      or (along >= total - 1 and off < 40)) then return 'done' end
end

-- The guide's heights, walked out from the car along the line (every GUIDE_REFRESH_S, not every frame). Each point's
-- ground is looked for only a few metres above and below the one before it, starting from the car's own height: a
-- ray from high up lands on the treetops of a forest stage, and the ground past what BeamNG.Earth has loaded round
-- the car has no collision at all. Where nothing is found the line carries on level with the last point found, so
-- it never breaks up.
M.GUIDE_REFRESH_S = 0.25
M.RAY_ABOVE_M = 6           -- how far above the last point's ground a ray starts
M.RAY_DOWN_M = 30
M.MAX_STEP_M = 5            -- a ground found more than this above or below the last point is not the road's

local function rayGround(x, y, zPrev)
  local ray = rawget(_G, 'castRayStatic')
  if not ray then return nil end
  for _, above in ipairs({ M.RAY_ABOVE_M, 2 }) do      -- (again from lower down: a branch over the road)
    local top = zPrev + above
    local d = ray(vec3(x, y, top), vec3(0, 0, -1), M.RAY_DOWN_M)
    if d and d < M.RAY_DOWN_M then
      local z = top - d
      if math.abs(z - zPrev) <= M.MAX_STEP_M then return z end
    end
  end
  return nil
end

local function buildGuide(p)
  local line, cum = rec.guide, rec.guideCum
  local s0, s1 = rec.here - M.GUIDE_BEHIND_M, rec.here + M.GUIDE_AHEAD_M
  -- the guide point nearest the car, then outwards both ways from the car's height
  local iCar, best = 1, math.huge
  for i = 1, #line do
    local d = math.abs(cum[i] - rec.here)
    if d < best then iCar, best = i, d end
  end
  local pts = {}
  local function walk(from, to, step)
    local z = p.z - 0.5
    for i = from, to, step do
      if cum[i] < s0 or cum[i] > s1 then break end
      local x, y = earth.toGame(line[i][1], line[i][2], 0)
      if not x then return end
      z = rayGround(x, y, z) or z
      pts[i] = vec3(x, y, z + M.GUIDE_LIFT_M)
    end
  end
  walk(iCar, #line, 1)
  walk(iCar - 1, 1, -1)
  rec.drawn = pts
  local lo, hi = iCar, iCar
  while pts[lo - 1] do lo = lo - 1 end
  while pts[hi + 1] do hi = hi + 1 end
  rec.drawnLo, rec.drawnHi = lo, hi
end

-- Draw the next stretch of the map line on the ground (every frame while recording).
function M.draw(dt)
  if not rec or not rec.here or not debugDrawer then return end
  local p = earth.pose()
  if not p then return end
  local la, lo = earth.anchor()
  rec.guideT = (rec.guideT or 0) - (dt or 0)
  if rec.guideT <= 0 or la ~= rec.guideLat or lo ~= rec.guideLon or earth.rebasing() then
    if earth.rebasing() then rec.drawn = nil return end
    buildGuide(p)
    rec.guideT, rec.guideLat, rec.guideLon = M.GUIDE_REFRESH_S, la, lo
  end
  guideColor = guideColor or ColorF(1, 0.55, 0.1, 0.9)
  endColor = endColor or ColorF(0.2, 1, 0.3, 0.9)
  local pts = rec.drawn
  if not pts then return end
  local prev = nil
  for i = rec.drawnLo, rec.drawnHi do
    local pt = pts[i]
    if pt and prev then debugDrawer:drawLineInstance(prev, pt, M.GUIDE_WIDTH, guideColor) end
    prev = pt
    if pt and i == #rec.guide then debugDrawer:drawSphere(pt + vec3(0, 0, 3), 3, endColor) end
  end
end

function M.progress()
  if not rec then return nil end
  return rec.best / rec.mapCum[#rec.mapCum], rec.lengthM, #rec.points, rec.off, rec.started == true
end

-- Stop; keep: save what was recorded (only when it covers most of the stage, unless forced). When it does not, the
-- recce goes on (nothing is lost): false and why.
function M.stop(keep, force)
  if not rec then return false end
  local r = rec
  if not keep then rec = nil log('I', 'earthRally', 'recce cancelled') return false, 'cancelled' end
  local share = r.best / r.mapCum[#r.mapCum]
  if share < M.END_SHARE and not force then
    return false, string.format('only %.0f %% of the stage driven so far: drive on, or Save anyway', share * 100)
  end
  if #r.points < 2 then
    return false, 'nothing recorded yet: drive to the start of the stage'
  end
  rec = nil
  events.saveRecce(r.event.id, r.stage.id, { format = 1, stage = r.stage.id, lengthM = r.lengthM,
    date = os.date('!%Y-%m-%dT%H:%M:%SZ'), points = r.points, jumps = r.jumps })
  log('I', 'earthRally', string.format('recce saved: %s, %.0f m, %d points', r.stage.name, r.lengthM, #r.points))
  return true
end

return M
