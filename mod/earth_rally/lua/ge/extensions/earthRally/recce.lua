-- earthRally/recce: drive a stage once, untimed, and keep the line the car took (lat / lon / height every few
-- metres). Stages are timed and their pacenotes made on that line, not on the organisers' map: a hand-drawn map
-- cuts corners and has no heights, and BeamNG.Earth's roads come from OpenStreetMap, which may differ a little.
-- The GPS guides the recce along the stage's map line.
local geo = require('earthRally/geo')
local earth = require('earthRally/earthAdapter')
local events = require('earthRally/events')

local M = {}

M.RECORD_EVERY_M = 4
M.GPS_POINTS = 11           -- BeamNG.Earth's GPS route takes at most 11 points
M.END_RADIUS_M = 40         -- this close to the stage's end (after most of it): the recce is done
M.END_SHARE = 0.9

local rec = nil             -- { event, stage, points, lastLat, lastLon, lengthM, mapPts, mapCum, best }

function M.active() return rec ~= nil end

local function mapLine(stage)
  -- the map line in a flat frame round its first point (metres), for progress along it
  local o = stage.line[1]
  local pts = {}
  for i, p in ipairs(stage.line) do
    pts[i] = { x = geo.metres(o[1], o[2], o[1], p[2]) * (p[2] < o[2] and -1 or 1),
               y = geo.metres(o[1], o[2], p[1], o[2]) * (p[1] < o[1] and -1 or 1) }
  end
  return pts, o
end

local function toFlat(o, lat, lon)
  return { x = geo.metres(o[1], o[2], o[1], lon) * (lon < o[2] and -1 or 1),
           y = geo.metres(o[1], o[2], lat, o[2]) * (lat < o[1] and -1 or 1) }
end

function M.start(event, stage)
  local pts, o = mapLine(stage)
  rec = { event = event, stage = stage, points = {}, lengthM = 0, mapPts = pts, mapCum = geo.cumulative(pts),
          origin = o, best = 0 }
  -- the GPS through the stage, points spread evenly along its map line
  local route = {}
  local n = math.min(M.GPS_POINTS, #stage.line)
  local total = rec.mapCum[#rec.mapCum]
  for k = 1, n do
    local s = total * k / n
    local i = 1
    for j = 1, #rec.mapCum do if rec.mapCum[j] <= s then i = j end end
    local p = stage.line[i]
    route[#route + 1] = { lat = p[1], lon = p[2], name = k == n and (stage.name .. ' finish') or nil }
  end
  local ok, why = earth.gpsRoute(route)
  if not ok then log('W', 'earthRally', 'recce: no GPS route (' .. tostring(why) .. '): follow the map') end
  log('I', 'earthRally', 'recce started: ' .. stage.name)
end

-- Every frame while recording. Returns 'done' when the stage's end is reached.
function M.update()
  if not rec then return end
  if earth.rebasing() then return end
  local p = earth.pose()
  if not p or p.camera then return end
  if rec.lastLat then
    local d = geo.metres(rec.lastLat, rec.lastLon, p.lat, p.lon)
    if d < M.RECORD_EVERY_M then return end
    rec.lengthM = rec.lengthM + d
  end
  rec.points[#rec.points + 1] = { p.lat, p.lon, p.alt }
  rec.lastLat, rec.lastLon = p.lat, p.lon
  -- progress along the map line (never backwards), and the end
  local q = toFlat(rec.origin, p.lat, p.lon)
  local _, _, along, off = geo.locate(rec.mapPts, rec.mapCum, q)
  if off < 150 and along > rec.best then rec.best = along end
  local total = rec.mapCum[#rec.mapCum]
  local last = rec.mapPts[#rec.mapPts]
  if rec.best >= total * M.END_SHARE and geo.dist2d(q, last) <= M.END_RADIUS_M then return 'done' end
end

function M.progress()
  if not rec then return nil end
  return rec.best / rec.mapCum[#rec.mapCum], rec.lengthM, #rec.points
end

-- Stop; keep: save what was recorded (only when it covers most of the stage, unless forced).
function M.stop(keep, force)
  if not rec then return false end
  local r = rec
  rec = nil
  earth.gpsClear()
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
