-- earthRally/geo: plain geometry on stage lines, with nothing from the game (tests/test_geo.lua runs it offline).
-- Points are { x, y, z } tables in metres (z optional), or { lat, lon } pairs where it says so.
local M = {}

local sqrt, atan2, abs, floor, pi = math.sqrt, math.atan2, math.abs, math.floor, math.pi
local R_EARTH = 6371008.8

-- Metres between two lat / lon points (an equirectangular approximation: well under 0.1 % off over a few km).
function M.metres(lat1, lon1, lat2, lon2)
  local kx = math.rad(1) * R_EARTH * math.cos(math.rad((lat1 + lat2) / 2))
  local ky = math.rad(1) * R_EARTH
  local dx, dy = (lon2 - lon1) * kx, (lat2 - lat1) * ky
  return sqrt(dx * dx + dy * dy)
end

local function d2(a, b)
  local dx, dy = b.x - a.x, b.y - a.y
  return sqrt(dx * dx + dy * dy)
end
M.dist2d = d2

-- Distance along the line at each point (cum[1] = 0), in plan (x, y).
function M.cumulative(pts)
  local cum = { 0 }
  for i = 2, #pts do cum[i] = cum[i - 1] + d2(pts[i - 1], pts[i]) end
  return cum
end

-- The line resampled every `step` m along it (the first and the last point kept); z interpolated when present.
function M.resample(pts, step)
  local n = #pts
  if n < 2 then return { pts[1] } end
  local out = { { x = pts[1].x, y = pts[1].y, z = pts[1].z } }
  local carry = 0          -- distance walked since the last point written
  for i = 1, n - 1 do
    local a, b = pts[i], pts[i + 1]
    local seg = d2(a, b)
    local pos = step - carry
    while pos <= seg do
      local t = pos / seg
      out[#out + 1] = { x = a.x + (b.x - a.x) * t, y = a.y + (b.y - a.y) * t,
                        z = a.z and b.z and (a.z + (b.z - a.z) * t) or nil }
      pos = pos + step
    end
    carry = seg - (pos - step)
  end
  local last, tail = pts[n], out[#out]
  if d2(tail, last) > step * 0.25 then out[#out + 1] = { x = last.x, y = last.y, z = last.z }
  else out[#out] = { x = last.x, y = last.y, z = last.z } end
  return out
end

-- The point nearest p on the line: index i of the segment (i, i + 1), t along it, the distance along the line, and the
-- distance off it. Searches segments lo..hi only (default all): a car's progress looks near where it was.
function M.locate(pts, cum, p, lo, hi)
  lo, hi = math.max(1, lo or 1), math.min(#pts - 1, hi or #pts - 1)
  local bi, bt, bd = lo, 0, math.huge
  for i = lo, hi do
    local a, b = pts[i], pts[i + 1]
    local dx, dy = b.x - a.x, b.y - a.y
    local l2 = dx * dx + dy * dy
    local t = l2 > 1e-12 and ((p.x - a.x) * dx + (p.y - a.y) * dy) / l2 or 0
    if t < 0 then t = 0 elseif t > 1 then t = 1 end
    local ex, ey = a.x + dx * t - p.x, a.y + dy * t - p.y
    local d = ex * ex + ey * ey
    if d < bd then bi, bt, bd = i, t, d end
  end
  return bi, bt, cum[bi] + (cum[bi + 1] - cum[bi]) * bt, sqrt(bd)
end

-- The point at distance s along the line (clamped), and the unit direction of travel there (in plan).
function M.pointAt(pts, cum, s)
  local n = #pts
  if s <= 0 then s = 0 elseif s >= cum[n] then s = cum[n] end
  local lo, hi = 1, n
  while hi - lo > 1 do
    local mid = floor((lo + hi) / 2)
    if cum[mid] <= s then lo = mid else hi = mid end
  end
  local a, b = pts[lo], pts[hi]
  local seg = cum[hi] - cum[lo]
  local t = seg > 1e-9 and (s - cum[lo]) / seg or 0
  local dx, dy = b.x - a.x, b.y - a.y
  local l = sqrt(dx * dx + dy * dy)
  local dir = l > 1e-9 and { x = dx / l, y = dy / l, z = 0 } or { x = 0, y = 1, z = 0 }
  return { x = a.x + dx * t, y = a.y + dy * t, z = a.z and b.z and (a.z + (b.z - a.z) * t) or nil }, dir
end

-- The line cut to [s0, s1] along it (both ends interpolated in).
function M.slice(pts, cum, s0, s1)
  local out = {}
  out[1] = (M.pointAt(pts, cum, s0))
  for i = 1, #pts do
    if cum[i] > s0 and cum[i] < s1 then out[#out + 1] = { x = pts[i].x, y = pts[i].y, z = pts[i].z } end
  end
  out[#out + 1] = (M.pointAt(pts, cum, s1))
  return out
end

-- The line carried on straight for `len` m past its start (back) or end (forward): the rally engine drops a start
-- line, a pathnode or a note sitting on the very end of its route (it found no route point there), and a recce often
-- starts on the start line and stops at the finish.
function M.extend(line, len, atStart)
  local n = #line
  local a, b = atStart and line[1] or line[n], nil
  -- the direction over the last ~10 m
  local cum = 0
  for k = 2, n do
    b = atStart and line[k] or line[n - k + 1]
    cum = cum + d2(line[atStart and k - 1 or n - k + 2], b)
    if cum >= 10 then break end
  end
  local dx, dy = a.x - b.x, a.y - b.y
  local l = math.sqrt(dx * dx + dy * dy)
  if l < 1e-6 then return line end
  dx, dy = dx / l, dy / l
  local out = {}
  local steps = math.ceil(len / 5)
  if atStart then
    for k = steps, 1, -1 do out[#out + 1] = { x = a.x + dx * 5 * k, y = a.y + dy * 5 * k, z = a.z } end
    for _, p in ipairs(line) do out[#out + 1] = p end
  else
    for _, p in ipairs(line) do out[#out + 1] = p end
    for k = 1, steps do out[#out + 1] = { x = a.x + dx * 5 * k, y = a.y + dy * 5 * k, z = a.z } end
  end
  return out
end

local function wrap(a)
  while a > pi do a = a - 2 * pi end
  while a < -pi do a = a + 2 * pi end
  return a
end

-- Corners along a line sampled evenly every `step` m (M.resample): where the road turns tighter than
-- opts.maxRadius (default 200 m) for at least opts.minAngleDeg (default 12 degrees) in all. The turn is measured per
-- metre and smoothed over opts.smoothM (default 15 m), so the result does not depend on how the line was sampled.
-- Same-direction corners closer than opts.mergeM (default 20 m) are one corner. Each corner:
--   { i0, i1 (sample indices of its start and end), dir = 'left' | 'right', angleDeg, minRadius (m) }.
-- The game measures each corner's severity itself from the driveline; this only finds where they are.
function M.corners(pts, step, opts)
  opts = opts or {}
  local maxRadius = opts.maxRadius or 200
  local minAngle = math.rad(opts.minAngleDeg or 12)
  local mergeN = math.max(1, floor((opts.mergeM or 20) / step + 0.5))
  local half = math.max(1, floor((opts.smoothM or 15) / step / 2 + 0.5))
  local n = #pts
  if n < 3 then return {} end

  -- turn at each sample (radians, positive left), from the headings of the segments either side
  local turn = {}
  for i = 1, n do turn[i] = 0 end
  for i = 2, n - 1 do
    local h1 = atan2(pts[i].y - pts[i - 1].y, pts[i].x - pts[i - 1].x)
    local h2 = atan2(pts[i + 1].y - pts[i].y, pts[i + 1].x - pts[i].x)
    turn[i] = wrap(h2 - h1)
  end
  -- smoothed curvature (1 / m)
  local k = {}
  for i = 1, n do
    local s, c = 0, 0
    for j = i - half, i + half do
      if j >= 1 and j <= n then s, c = s + turn[j], c + 1 end
    end
    k[i] = s / (c * step)
  end

  local kMin = 1 / maxRadius
  local runs = {}
  local i = 1
  while i <= n do
    if abs(k[i]) >= kMin then
      local sign = k[i] > 0 and 1 or -1
      local j = i
      while j + 1 <= n and k[j + 1] * sign >= kMin do j = j + 1 end
      local last = runs[#runs]
      if last and last.sign == sign and i - last.i1 <= mergeN then last.i1 = j
      else runs[#runs + 1] = { i0 = i, i1 = j, sign = sign } end
      i = j + 1
    else
      i = i + 1
    end
  end

  local out = {}
  for _, r in ipairs(runs) do
    local angle, kMax = 0, 0
    for j = r.i0, r.i1 do
      angle = angle + turn[j]
      if abs(k[j]) > kMax then kMax = abs(k[j]) end
    end
    if abs(angle) >= minAngle then
      out[#out + 1] = { i0 = r.i0, i1 = math.max(r.i1, r.i0 + 1), dir = r.sign > 0 and 'left' or 'right',
                        angleDeg = abs(math.deg(angle)), minRadius = kMax > 0 and 1 / kMax or math.huge }
    end
  end
  return out
end

return M
