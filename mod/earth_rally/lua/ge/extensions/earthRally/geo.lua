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

-- (the first segment i whose end is at or past s along the line)
local function segAt(cum, s)
  local lo, hi = 1, #cum
  while hi - lo > 1 do
    local mid = floor((lo + hi) / 2)
    if cum[mid] <= s then lo = mid else hi = mid end
  end
  return lo
end
M.segAt = segAt

-- A point's distance along the line looked for only between fromM and toM (a stop control after the flying finish, an
-- ATC before the start: never on another pass of the line), and its distance off the line. A point beyond either end
-- of that stretch reads as that end: so a control the line does not reach is clamped to what it covers.
function M.alongBetween(pts, cum, p, fromM, toM)
  local lo = segAt(cum, math.max(0, fromM or 0))
  local hi = segAt(cum, math.min(cum[#cum], toM or cum[#cum]))
  local _, _, s, off = M.locate(pts, cum, p, lo, hi)
  return math.max(fromM or 0, math.min(toM or cum[#cum], s)), off
end

-- Progress along a line, followed from where it was (prevAlong, m along the line; nil: not known yet), so it does not
-- jump to another part of the line where the line passes close to itself (a super special crossing itself, a road
-- back down a valley). The stretch from backM behind to aheadM ahead of prevAlong first; when the point is more than
-- maxOff from that stretch (or no prevAlong), the whole line, and among the parts of it within reach of the point
-- (maxOff, or 20 m more than the nearest) the one nearest prevAlong along the line. Returns along, off, i.
function M.follow(pts, cum, p, prevAlong, backM, aheadM, maxOff)
  local n = #pts
  if prevAlong then
    local lo = segAt(cum, math.max(0, prevAlong - backM))
    local hi = math.min(n - 1, segAt(cum, prevAlong + aheadM))
    local i, _, along, off = M.locate(pts, cum, p, lo, hi)
    if off <= maxOff then return along, off, i end
  end
  -- the whole line (two passes, nothing kept: this can run every frame)
  local nearI, _, nearAlong, nearOff = M.locate(pts, cum, p)
  if not prevAlong then return nearAlong, nearOff, nearI end
  local reach = math.max(maxOff, nearOff + 20)
  local bAlong, bScore = nearAlong, abs(nearAlong - prevAlong)
  for i = 1, n - 1 do
    local _, _, along, off = M.locate(pts, cum, p, i, i)
    if off <= reach then
      local score = abs(along - prevAlong)
      if score < bScore then bAlong, bScore = along, score end
    end
  end
  -- (that part of the line chosen, the point on it nearest p: not the end of the segment nearest prevAlong)
  local lo = segAt(cum, math.max(0, bAlong - reach - 50))
  local hi = math.min(n - 1, segAt(cum, bAlong + reach + 50))
  local i, _, along, off = M.locate(pts, cum, p, lo, hi)
  return along, off, i
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

M.RISE_THRESHOLD_M = 2      -- a height move counts once it has gone this far from the last one counted

-- The height a line gains and loses (m, both positive), from the heights its own points carry.
--
-- Counted with a hysteresis: a move counts only once the height has gone `thresholdM` from the last height
-- counted, and then the whole of it counts. Summing every step instead adds the height data's own wobble to the
-- road's real rise -- a metre of shiver, a thousand points of it, reads as tens of metres of climb on ground that
-- is flat. A threshold drops the small moves and leaves the big ones whole, where smoothing the heights first
-- would shrink the real climbs along with the noise. 2 m is where the wobble ends and the road begins, measured
-- over the user's own 116 lines: docs/mockups-1.3.1/stage-tiles.html, section 6, which also shows that the figure
-- does not change when the same line is measured again at a different point spacing, so the line's own points are
-- what this reads and there is nothing to resample first.
--
-- Returns nil when the line carries no height to measure: no z at all, or every z the same -- a road whose every
-- point is at one height is not a flat road, it is a line that was given no heights (autoRecce.lua's fillHeights
-- finds none, and the file is then written with one offset as every point's height). A stage that really is flat
-- still moves by centimetres and reads 0, which is a different answer from "not known".
function M.rise(pts, thresholdM)
  local thr = thresholdM or M.RISE_THRESHOLD_M
  local first, mark, gain, loss, varied = nil, nil, 0, 0, false
  for i = 1, #pts do
    local z = pts[i].z
    if z then
      if not mark then first, mark = z, z
      else
        if z ~= first then varied = true end
        local d = z - mark
        if d >= thr then gain, mark = gain + d, z
        elseif d <= -thr then loss, mark = loss - d, z end
      end
    end
  end
  if not mark or not varied then return nil end
  return gain, loss
end

-- Corners along a line sampled evenly every `step` m (M.resample): where the road turns tighter than
-- opts.maxRadius (default 200 m) for at least opts.minAngleDeg (default 12 degrees) in all. The turn is measured per
-- metre and smoothed over opts.smoothM (default 15 m), so the result does not depend on how the line was sampled.
-- Same-direction corners closer than opts.mergeM (default 20 m) are one corner. Each corner:
--   { i0, i1 (sample indices of its start and end), dir = 'left' | 'right', angleDeg, minRadius (m) }.
-- The game measures each corner's severity itself from the driveline; this only finds where they are.
-- The turn at each sample of a line sampled evenly every `step` m (radians, positive left, from the headings of the
-- segments either side) and the curvature smoothed over smoothM (1 / m, signed the same way). M.corners reads its
-- corners off these, and pacenotes.lua reads a corner's shape and the speed along the road off the same numbers, so
-- the two never disagree about where a corner is tighter.
function M.curvature(pts, step, smoothM)
  local half = math.max(1, floor((smoothM or 15) / step / 2 + 0.5))
  local n = #pts
  local turn = {}
  for i = 1, n do turn[i] = 0 end
  for i = 2, n - 1 do
    local h1 = atan2(pts[i].y - pts[i - 1].y, pts[i].x - pts[i - 1].x)
    local h2 = atan2(pts[i + 1].y - pts[i].y, pts[i + 1].x - pts[i].x)
    turn[i] = wrap(h2 - h1)
  end
  local k = {}
  for i = 1, n do
    local s, c = 0, 0
    for j = i - half, i + half do
      if j >= 1 and j <= n then s, c = s + turn[j], c + 1 end
    end
    k[i] = s / (c * step)
  end
  return turn, k
end

function M.corners(pts, step, opts)
  opts = opts or {}
  local maxRadius = opts.maxRadius or 200
  local minAngle = math.rad(opts.minAngleDeg or 12)
  local mergeN = math.max(1, floor((opts.mergeM or 20) / step + 0.5))
  local n = #pts
  if n < 3 then return {} end

  local turn, k = M.curvature(pts, step, opts.smoothM)

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

-- A matched line doubling back on itself: the auto recce routes from each waypoint's road point to the next one's, and
-- a waypoint put on a spur beside the stage's road (or a few metres past a junction, or behind the one before it)
-- makes the route go out to it and back along the same road. On the owner's lines: out and back along a dead end of
-- 280 m, stubs of 4 to 25 m at junctions. The co-driver hears each fold as a hairpin and the bends either side as
-- corners that are not there. FOLD_DEG at one point is a fold (no road turns that much in one point of a line); the
-- out-and-back round it is dropped: from the last point before it that the line comes back to (within FOLD_TOL_M,
-- FOLD_MAX_M or less either side of the fold), the way back retracing the way out (each of its points within
-- FOLD_RETRACE_M of it), to that point of return. A sharp turn at a junction that does not retrace keeps its road;
-- only the one point of its apex can go.
M.FOLD_DEG = 150
M.FOLD_TOL_M = 4
M.FOLD_RETRACE_M = 8
M.FOLD_MAX_M = 600

local function segDist(p, a, b)
  local dx, dy = b.x - a.x, b.y - a.y
  local l2 = dx * dx + dy * dy
  local t = l2 > 1e-12 and ((p.x - a.x) * dx + (p.y - a.y) * dy) / l2 or 0
  if t < 0 then t = 0 elseif t > 1 then t = 1 end
  local qx, qy = a.x + dx * t - p.x, a.y + dy * t - p.y
  return sqrt(qx * qx + qy * qy)
end

-- pts: { {x, y}... }. Returns the indices of the points kept, in order, and how many were dropped.
function M.foldBacks(pts)
  local n = #pts
  local out = {}
  if n < 3 then
    for k = 1, n do out[k] = k end
    return out, 0
  end
  out[1] = 1
  local cum = M.cumulative(pts)
  local cosF = math.cos(math.rad(M.FOLD_DEG))
  -- (the way back, k0..k1, within FOLD_RETRACE_M of the way out, out[oi]..i)
  local function retraces(oi, i, k0, k1)
    for k = k0, k1 do
      local best = math.huge
      local prev = pts[out[oi]]
      for m = oi + 1, #out + 1 do
        local q = m <= #out and pts[out[m]] or pts[i]
        local d = segDist(pts[k], prev, q)
        if d < best then best = d end
        prev = q
      end
      if best > M.FOLD_RETRACE_M then return false end
    end
    return true
  end
  local i = 2
  while i <= n do
    local jumped = false
    if i < n then
      -- (from the last point kept that is not on top of this one)
      local p = pts[out[#out]]
      for oi = #out, 1, -1 do
        if d2(pts[out[oi]], pts[i]) > 0.05 then p = pts[out[oi]] break end
      end
      local ax, ay = pts[i].x - p.x, pts[i].y - p.y
      local bx, by = pts[i + 1].x - pts[i].x, pts[i + 1].y - pts[i].y
      local la, lb = sqrt(ax * ax + ay * ay), sqrt(bx * bx + by * by)
      if la > 0.05 and lb > 0.05 and (ax * bx + ay * by) / (la * lb) <= cosF then
        local bi, bj = nil, nil
        for oi = #out, 1, -1 do
          local a = out[oi]
          if cum[i] - cum[a] > M.FOLD_MAX_M then break end
          local bestD, bestJ = M.FOLD_TOL_M, nil
          for j = i + 1, n do
            if cum[j] - cum[i] > M.FOLD_MAX_M then break end
            local d = d2(pts[a], pts[j])
            if d <= bestD then bestD, bestJ = d, j end
          end
          if bestJ and retraces(oi, i, i + 1, bestJ - 1) then bi, bj = oi, bestJ end
        end
        if bi then
          for k = #out, bi + 1, -1 do out[k] = nil end
          i = bj
          jumped = true
        end
      end
    end
    if not jumped then
      out[#out + 1] = i
      i = i + 1
    end
  end
  return out, n - #out
end

-- The same over a line of { lat, lon, ... } points (a matched or recce file's own shape): the points kept (the same
-- tables), and how many were dropped.
function M.dropFoldBacks(points)
  if type(points) ~= 'table' or #points < 3 then return points, 0 end
  local o = points[1]
  local xy = {}
  for i, p in ipairs(points) do
    xy[i] = { x = M.metres(o[1], o[2], o[1], p[2]) * (p[2] < o[2] and -1 or 1),
              y = M.metres(o[1], o[2], p[1], o[2]) * (p[1] < o[1] and -1 or 1) }
  end
  local keep, dropped = M.foldBacks(xy)
  if dropped == 0 then return points, 0 end
  local out = {}
  for k, i in ipairs(keep) do out[k] = points[i] end
  return out, dropped
end

return M
