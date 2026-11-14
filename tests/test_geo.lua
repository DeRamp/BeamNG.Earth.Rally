-- geo.lua: distances, resampling, locating a point along a line, slicing, and corner detection on known shapes.
local T = dofile(TESTS .. '/testlib.lua')
local geo = require('earthRally/geo')

-- metres between lat / lon points
T.near(geo.metres(47, -123, 47.01, -123), 1111.95, 1, '0.01 deg of latitude')
T.near(geo.metres(47, -123, 47, -122.99), 758.4, 1.5, '0.01 deg of longitude at 47 N')

-- resample: a 100 m straight every 10 m
local line = { { x = 0, y = 0, z = 0 }, { x = 0, y = 100, z = 10 } }
local r = geo.resample(line, 10)
T.check(#r == 11, 'resample: 11 points (' .. #r .. ')')
T.near(r[6].y, 50, 1e-9, 'resample: the middle point')
T.near(r[6].z, 5, 1e-9, 'resample: z interpolated')
T.near(r[#r].y, 100, 1e-9, 'resample: the last point kept')

-- a corner-free line with points unevenly spaced: resampled evenly
local zig = { { x = 0, y = 0 }, { x = 0, y = 3 }, { x = 0, y = 40 }, { x = 0, y = 41 }, { x = 0, y = 95 } }
local rz = geo.resample(zig, 5)
local cz = geo.cumulative(rz)
local even = true
for i = 2, #rz - 1 do if math.abs(cz[i] - cz[i - 1] - 5) > 1e-6 then even = false end end
T.check(even, 'resample: even spacing over uneven input')

-- locate and pointAt
local cum = geo.cumulative(r)
local i, t, along, off = geo.locate(r, cum, { x = 3, y = 42 })
T.near(along, 42, 1e-9, 'locate: distance along')
T.near(off, 3, 1e-9, 'locate: distance off')
local p, dir = geo.pointAt(r, cum, 25)
T.near(p.y, 25, 1e-9, 'pointAt: position')
T.near(dir.y, 1, 1e-9, 'pointAt: direction')
local sl = geo.slice(r, cum, 12, 57)
T.near(sl[1].y, 12, 1e-9, 'slice: start')
T.near(sl[#sl].y, 57, 1e-9, 'slice: end')

-- corners: straight 200 m, a 90 degree left of radius 40 m, straight 200 m, a 120 degree right of radius 25 m,
-- straight 200 m
local function road()
  local pts, x, y, h = {}, 0, 0, math.pi / 2
  local function add() pts[#pts + 1] = { x = x, y = y, z = 0 } end
  local function straight(len) for _ = 1, len do x, y = x + math.cos(h), y + math.sin(h) add() end end
  local function arc(radius, deg, left)
    local n = math.floor(radius * math.rad(deg))
    local dh = math.rad(deg) / n * (left and 1 or -1)
    for _ = 1, n do h = h + dh x, y = x + math.cos(h), y + math.sin(h) add() end
  end
  add()
  straight(200) arc(40, 90, true) straight(200) arc(25, 120, false) straight(200)
  return pts
end
local pts = geo.resample(road(), 5)
local cs = geo.corners(pts, 5)
T.check(#cs == 2, 'corners: two found (' .. #cs .. ')')
if #cs == 2 then
  T.check(cs[1].dir == 'left' and cs[2].dir == 'right', 'corners: left, then right')
  T.near(cs[1].angleDeg, 90, 8, 'corners: the first turns ~90 degrees')
  T.near(cs[2].angleDeg, 120, 8, 'corners: the second turns ~120 degrees')
  T.near(cs[1].minRadius, 40, 8, 'corners: the first ~40 m radius')
  T.near(cs[2].minRadius, 25, 6, 'corners: the second ~25 m radius')
  local c1 = geo.cumulative(pts)
  T.near(c1[cs[1].i0], 200, 15, 'corners: the first starts where the arc does')
end
-- the same road sampled every 2 m finds the same corners (the measure is per metre)
local cs2 = geo.corners(geo.resample(road(), 2), 2)
T.check(#cs2 == 2, 'corners: the same two at 2 m sampling (' .. #cs2 .. ')')
-- a gentle bend (radius 600 m) is no corner
local function gentle()
  local out, h, x, y = { { x = 0, y = 0 } }, 0, 0, 0
  for _ = 1, 400 do h = h + 1 / 600 x, y = x + math.cos(h), y + math.sin(h) out[#out + 1] = { x = x, y = y } end
  return out
end
T.check(#geo.corners(geo.resample(gentle(), 5), 5) == 0, 'corners: a 600 m bend is not called')

-- rise: the height a line gains and loses, counted once a move has gone 2 m from the last one counted
local function zline(zs)
  local out = {}
  for i, z in ipairs(zs) do out[i] = { x = 0, y = (i - 1) * 4, z = z } end
  return out
end

-- flat ground carrying the height data's own wobble, 0.8 m either way point to point (1.6 m peak to peak, under
-- the threshold): no climb at all. The same wobble summed every step is where the false hundreds of metres come
-- from, and the second check is what that looks like.
local wob = {}
for i = 1, 300 do wob[i] = 100 + ((i % 2 == 0) and 0.8 or -0.8) end
local g, l = geo.rise(zline(wob))
T.check(g == 0 and l == 0, 'rise: a wobble under the threshold is not climb (' .. tostring(g) .. ' / ' .. tostring(l) .. ')')
T.check((geo.rise(zline(wob), 0)) > 200, 'rise: the same wobble summed every step reads hundreds of metres (' ..
  tostring((geo.rise(zline(wob), 0))) .. ')')

-- a 100 m climb with that same wobble on top of it: the climb, and not the climb plus the wobble
local climb = {}
for i = 1, 300 do climb[i] = 100 + (i - 1) * (100 / 299) + ((i % 2 == 0) and 0.8 or -0.8) end
local gc, lc = geo.rise(zline(climb))
T.near(gc, 100, 3, 'rise: a 100 m climb under a wobble is a 100 m climb')
T.check(lc < 2, 'rise: and nothing worth calling a drop (' .. tostring(lc) .. ')')

-- the same road measured again at 20 m spacing instead of 4: the same figure. A rule reading the road gives the
-- same answer at either spacing; a rule reading the wobble does not.
T.near((geo.rise(geo.resample(zline(climb), 20))), gc, 3, 'rise: the same at 20 m spacing as at 4 m')

-- hills both ways: gain less loss is the line's own end-to-start height change, within the threshold, so the two
-- tiles can never contradict each other
local hills = {}
for i = 1, 400 do hills[i] = 100 + 40 * math.sin(i / 25) + (i - 1) * 0.05 end
local gh, lh = geo.rise(zline(hills))
T.check(gh > 150 and lh > 100, 'rise: the hills counted both ways (' .. tostring(gh) .. ' / ' .. tostring(lh) .. ')')
T.near(gh - lh, hills[#hills] - hills[1], 2.5, 'rise: gain less loss is the line\'s own height change')

-- no height to read: no figure. Every point at one height is a line that was given no heights, not a flat road --
-- flat ground still moves by centimetres and reads 0.
T.check(geo.rise({ { x = 0, y = 0 }, { x = 0, y = 10 } }) == nil, 'rise: no heights at all is not a figure')
T.check(geo.rise(zline({ 50, 50, 50, 50, 50 })) == nil, 'rise: one height at every point is no height data')
T.check((geo.rise(zline({ 50, 50.02, 49.99, 50.01 }))) == 0, 'rise: ... while ground that really is flat reads 0')

T.done('test_geo')
