-- earthRally/pacenotes: what the co-driver says about the road besides a corner's number and its length, which the
-- game measures itself off the driveline between a note's two waypoints. Pure: plain tables in and out, nothing from
-- the game (tests/test_pacenotes.lua). stageWriter.lua puts what this finds into the notes' slots.
--
-- Everything here reads a stage's own stretch of line, sampled evenly every `step` m (stageWriter.NOTE_STEP_M), and
-- the curvature geo.curvature gives over it -- the same numbers geo.corners finds the corners with.
--
-- The calls are the game's own (gameplay/rally/compositors/styles/english/modifiers.lua and enthusiast.lua's corner
-- descriptors and shapes), so every voice pack that speaks the detailed style has the audio for them. The casual
-- style speaks only some of them (its casualModifiers and casualModifierAliases) and says nothing at all for the
-- rest, so stageWriter.build leaves out what the player's voice cannot say (opts.speaks, rallyAdapter.speaks).
--
-- Tuned against the game's own hand-made stages with tools/pacenote_benchmark.py (recall and precision per kind of
-- call) and over the user's matched lines with tools/pacenote_survey.py (rates per km).
local M = {}

local abs, sqrt, floor, min, max, huge = math.abs, math.sqrt, math.floor, math.min, math.max, math.huge

------------------------------------------------------------------------------------------ the speed along the road

-- A quick, tidy driver in a rally car on a loose road: what the cautions and the jumps are judged against. Not a lap
-- time model -- it only has to say where the road is fast and where it is slow, and how much slower.
M.A_LAT_MS2 = 8.0        -- sideways grip
M.A_GO_MS2 = 3.0         -- gained on a straight, averaged over the gears
M.A_BRAKE_MS2 = 7.0      -- braking
M.V_MAX_MS = 40.0        -- 144 km/h: a stage's top speed

-- The speed at each sample (m/s), from a standing start at the first (a stage starts from the line). k: the
-- smoothed curvature (geo.curvature).
function M.speeds(k, step)
  local n = #k
  local v = {}
  for i = 1, n do
    local kk = abs(k[i])
    v[i] = kk > 1e-9 and min(M.V_MAX_MS, sqrt(M.A_LAT_MS2 / kk)) or M.V_MAX_MS
  end
  if n == 0 then return v end
  v[1] = 0
  for i = 2, n do v[i] = min(v[i], sqrt(v[i - 1] * v[i - 1] + 2 * M.A_GO_MS2 * step)) end
  for i = n - 1, 1, -1 do v[i] = min(v[i], sqrt(v[i + 1] * v[i + 1] + 2 * M.A_BRAKE_MS2 * step)) end
  return v
end

------------------------------------------------------------------------------------------ what kind of corner

-- A descriptor replaces the corner's number in the call ("hairpin left", "square right": compositorUtil's
-- getCornerCall, "descriptor wins over intensity name"), so it is given only where it is plainly true. The hairpin
-- limits follow the game's own hairpin test (geoPacenotes.buildHairpinCandidate: a diameter of 35 m or less, at least
-- 135 degrees); minRadius is the tightest point of the smoothed curvature, which reads a few metres wider than the
-- road's own radius on a corner this tight. No "open hairpin": a wider turn is left to the game's number, which
-- also keeps its length call (a descriptor drops it).
M.HAIRPIN_DEG = 135
M.HAIRPIN_R = 20         -- m, at most: a hairpin
M.TIGHT_HAIRPIN_R = 11   -- m, at most: a tight one
M.SQUARE_DEG = { 70, 115 }
M.SQUARE_R = 18          -- m, at most
M.SQUARE_ARC_M = 45      -- m, at most, start to end: a square corner is a short one

function M.descriptor(c, step)
  local a, r = c.angleDeg, c.minRadius
  if a >= M.HAIRPIN_DEG then
    if r <= M.TIGHT_HAIRPIN_R then return 'tightHairpin' end
    if r <= M.HAIRPIN_R then return 'hairpin' end
    return nil
  end
  if a >= M.SQUARE_DEG[1] and a <= M.SQUARE_DEG[2] and r <= M.SQUARE_R and (c.i1 - c.i0) * step <= M.SQUARE_ARC_M then
    return 'square'
  end
  return nil
end

-- The corner's shape: tighter at its end than its start, or the other way, or easing off in the middle. Read over the
-- corner's core -- where it turns at least SHAPE_CORE of its tightest -- because the smoothing makes every corner's
-- curvature rise and fall at its two ends, which is not the road tightening or opening. A corner has to be
-- SHAPE_MIN_M long in its core to have a shape: a short one is over before it could change.
-- (The corner is still measured in one piece, as the game's own stages do: its split measurements cut the waypoint
-- span in equal parts, not where this found the change, and would call a gentle lead-in's number.)
M.SHAPE_CORE = 0.25
M.SHAPE_MIN_M = 30
M.SHAPE_RATIO = 1.6      -- one part this much tighter than the other
M.SHAPE_RATIO_MIDDLE = 2.0 -- "opens and tightens": both ends this much tighter than the middle

local function meanK(k, a, b)
  local s = 0
  for i = a, b do s = s + abs(k[i]) end
  return s / (b - a + 1)
end

function M.shape(c, k, step)
  local kMax = 0
  for i = c.i0, c.i1 do if abs(k[i]) > kMax then kMax = abs(k[i]) end end
  if kMax <= 0 then return nil end
  local a, b
  for i = c.i0, c.i1 do
    if abs(k[i]) >= M.SHAPE_CORE * kMax then a = a or i b = i end
  end
  if not a or (b - a) * step < M.SHAPE_MIN_M then return nil end
  local n = b - a + 1
  local t1, t2 = a + floor(n / 3), a + floor(2 * n / 3)
  local e, m, x = meanK(k, a, t1 - 1), meanK(k, t1, t2 - 1), meanK(k, t2, b)
  if m * M.SHAPE_RATIO_MIDDLE <= min(e, x) then return 'opensAndTightens' end
  local h = a + floor(n / 2)
  local e2, x2 = meanK(k, a, h - 1), meanK(k, h, b)
  if x2 >= e2 * M.SHAPE_RATIO then return 'tightens' end
  if e2 >= x2 * M.SHAPE_RATIO then return 'opens' end
  return nil
end

------------------------------------------------------------------------------------------ chicanes and twisty bits

-- Two tight corners either way, close together and on their own: one note, "chicane left entry" (the game's own
-- stages write it as a note with no corner in it), spanning both, so the next note's distance is from its end. A run
-- of TWISTY_MIN or more fast corners flicking either way: "twisty" on the first of them, every corner still called
-- (as the game's own stages mostly do it -- and a voice that cannot say "twisty" still calls the corners).
M.CHICANE_GAP_M = 15     -- m, at most, between the two corners
M.CHICANE_R = 35         -- m, at most, each corner's tightest
M.CHICANE_DEG = { 25, 100 }
M.CHICANE_LEN_M = 90     -- m, at most, the whole chicane
M.TWISTY_MIN = 4
M.TWISTY_GAP_M = 40      -- m, at most, between one and the next
M.TWISTY_R = 60          -- m, at least, each corner's tightest (a four or faster)
M.TWISTY_DEG = 60        -- degrees, at most, each

local function mild(c) return c.minRadius >= M.TWISTY_R and c.angleDeg <= M.TWISTY_DEG end
local function tightish(c)
  return c.minRadius <= M.CHICANE_R and c.angleDeg >= M.CHICANE_DEG[1] and c.angleDeg <= M.CHICANE_DEG[2]
end

local function merged(cs, a, b, group)
  local r, ang = huge, 0
  for k = a, b do r = min(r, cs[k].minRadius) ang = max(ang, cs[k].angleDeg) end
  return { i0 = cs[a].i0, i1 = cs[b].i1, dir = cs[a].dir, angleDeg = ang, minRadius = r, group = group,
           count = b - a + 1 }
end

-- corners: geo.corners' list in order. Returns the list with each chicane made one entry ({ ..., group = 'chicane',
-- count = 2 }) and the first corner of each twisty run marked (twisty = how many corners the run has).
function M.group(corners, step)
  local out, n, i = {}, #corners, 1
  local function gap(a, b) return (b.i0 - a.i1) * step end
  while i <= n do
    local c = corners[i]
    local j = i
    if mild(c) then
      while j + 1 <= n and corners[j + 1].dir ~= corners[j].dir and gap(corners[j], corners[j + 1]) <= M.TWISTY_GAP_M
            and mild(corners[j + 1]) do
        j = j + 1
      end
    end
    if j - i + 1 >= M.TWISTY_MIN then
      for k = i, j do
        local cc = {}
        for key, val in pairs(corners[k]) do cc[key] = val end
        if k == i then cc.twisty = j - i + 1 end
        out[#out + 1] = cc
      end
      i = j + 1
    else
      local d, e, p = corners[i + 1], corners[i + 2], corners[i - 1]
      if d and d.dir ~= c.dir and tightish(c) and tightish(d) and gap(c, d) <= M.CHICANE_GAP_M
         and (d.i1 - c.i0) * step <= M.CHICANE_LEN_M
         and not (e and gap(d, e) <= M.CHICANE_GAP_M) and not (p and gap(p, c) <= M.CHICANE_GAP_M) then
        out[#out + 1] = merged(corners, i, i + 1, 'chicane')
        i = i + 2
      else
        out[#out + 1] = c
        i = i + 1
      end
    end
  end
  return out
end

------------------------------------------------------------------------------------------ cautions

-- A corner a lot slower than the road leading into it: the speed through it against the fastest the car got in the
-- CAUTION_LOOK_M before it, and not before the end of the corner before it (prevI1, a sample index, or nil): the
-- approach is the road since the last corner. Only where that approach is fast at all -- a slow corner after a slow
-- one is no surprise. Levels: 1 care, 2 caution, 3 double caution. And a corner that tightens on a fast approach
-- (shape 'tightens', 'tightensDown' or 'tightensOverCrest'): at least a care, one more over a crest -- where the
-- game's own stages put most of theirs.
M.CAUTION_LOOK_M = 250
M.CAUTION_V_MS = 25      -- 90 km/h: the approach at least this fast
M.CAUTION = { 0.40, 0.30, 0.22 }   -- corner speed / approach speed at or under these
M.CAUTION_TIGHTENS_V_MS = 20       -- 72 km/h: a tightening corner on an approach this fast is a care

function M.caution(c, v, step, prevI1, shape)
  local vc = huge
  for i = c.i0, c.i1 do if v[i] and v[i] < vc then vc = v[i] end end
  local va = 0
  for i = max(1, prevI1 or 1, c.i0 - floor(M.CAUTION_LOOK_M / step)), c.i0 do if v[i] > va then va = v[i] end end
  if vc == huge then return nil end
  local level = nil
  if va >= M.CAUTION_V_MS then
    local r = vc / va
    for l, t in ipairs(M.CAUTION) do if r <= t then level = l end end
  end
  if (shape == 'tightens' or shape == 'tightensDown' or shape == 'tightensOverCrest') and va >= M.CAUTION_TIGHTENS_V_MS then
    level = math.min(3, math.max(level or 0, shape == 'tightensOverCrest' and 2 or 1))
  end
  return level
end

------------------------------------------------------------------------------------------ the height profile

-- Crests and dips are where the grade changes: the grade over the GRADE_OVER_M after a point against the one before
-- it (dg, a fraction: -0.1 is a road going from level to 10 % down). Heights are smoothed over three samples first.
-- The strongest first, and nothing of the same kind within EVENT_M of one already taken, nor of the other kind
-- within OPPOSITE_M of one RIM_RATIO times as strong: the two rims of a hollow read as crests of about half its
-- strength, and are not. A jump is a crest the car cannot follow at the speed it gets there: the sharper grade
-- change over JUMP_OVER_M gives the crest's vertical radius, and v^2 / radius over g is how much of the car's weight
-- it would take to stay on the road (1 = the tyres just go light); a big jump is a big crest as well.
-- Nothing is read where the heights themselves are not a road's: a step between two samples steeper than BAD_GRADE
-- within GRADE_OVER_M (elevation data does that -- a matched line's 6 m drop in 4 m -- roads do not).
M.GRADE_OVER_M = 20
M.EVENT_M = 40
M.OPPOSITE_M = 60
M.RIM_RATIO = 1.3
M.BAD_GRADE = 0.25
M.CREST_DG = 0.06        -- a crest
M.SMALL_CREST_DG = 0.08  -- weaker than this: a small one
M.BIG_CREST_DG = 0.14    -- this or more: a big one
M.ALONE_CREST_DG = 0.08  -- a crest on its own (not on a corner) is called from this
M.DIP_DG = 0.14
M.BAD_DIP_DG = 0.22
M.ALONE_DIP_DG = 0.18
M.JUMP_OVER_M = 10
M.JUMP_LIFT = 1.4
M.BIG_JUMP_LIFT = 2.4
M.JUMP_MIN_V_MS = 15
M.HILL_GRADE = 0.08      -- "up" / "down": at least this steep ...
M.HILL_M = 100           -- ... for at least this far
M.G = 9.81

local function heightsOf(pts)
  local zs, first, varied = {}, nil, false
  for i, p in ipairs(pts) do
    if type(p.z) ~= 'number' then return nil end
    first = first or p.z
    if p.z ~= first then varied = true end
    zs[i] = p.z
  end
  if not varied then return nil end
  local n, sm = #zs, {}
  for i = 1, n do
    local a, b = max(1, i - 1), min(n, i + 1)
    local s = 0
    for j = a, b do s = s + zs[j] end
    sm[i] = s / (b - a + 1)
  end
  return sm, zs
end

-- pts: the stage's samples (with z), v: M.speeds over them. Returns
--   events  { { i, kind = 'crest' | 'jump' | 'dip', size = 'small' | 'big' | nil, alone = true when strong enough
--             to be called on its own }... } in order
--   hills   { { i0, i1, kind = 'up' | 'down' }... }
--   grade   the grade at each sample (fraction, over GRADE_OVER_M either side), or nil
-- Both lists are empty when the line has no heights (geo.rise's rule: none, or every one the same).
function M.heights(pts, step, v)
  local z, raw = heightsOf(pts)
  if not z then return {}, {}, nil end
  local n = #z
  local w = max(1, floor(M.GRADE_OVER_M / step + 0.5))
  local w2 = max(1, floor(M.JUMP_OVER_M / step + 0.5))
  local e = max(1, floor(M.EVENT_M / step + 0.5))
  local dg, grade = {}, {}
  for i = 1, n do
    if i > w and i <= n - w then
      dg[i] = (z[i + w] - z[i]) / (w * step) - (z[i] - z[i - w]) / (w * step)
      grade[i] = (z[i + w] - z[i - w]) / (2 * w * step)
    else
      dg[i] = 0
      grade[i] = (z[min(n, i + 1)] - z[max(1, i - 1)]) / (step * (min(n, i + 1) - max(1, i - 1)))
    end
  end
  -- (a step between two raw samples steeper than BAD_GRADE: bad heights round it)
  local bad = {}
  for i = 1, n - 1 do bad[i] = abs(raw[i + 1] - raw[i]) / step > M.BAD_GRADE end
  local function clean(i)
    for j = max(1, i - w), min(n - 1, i + w) do if bad[j] then return false end end
    return true
  end
  local cands = {}
  for i = w + 1, n - w do
    local d = dg[i]
    if (d <= -M.CREST_DG or d >= M.DIP_DG) and clean(i) then cands[#cands + 1] = i end
  end
  table.sort(cands, function(x, y)
    if abs(dg[x]) ~= abs(dg[y]) then return abs(dg[x]) > abs(dg[y]) end
    return x < y
  end)
  local eo = max(1, floor(M.OPPOSITE_M / step + 0.5))
  local taken = {}
  for _, i in ipairs(cands) do
    local d, ok = dg[i], true
    for _, j in ipairs(taken) do
      local same = (dg[j] < 0) == (d < 0)
      if (same and abs(j - i) <= e) or (not same and abs(j - i) <= eo and abs(dg[j]) >= abs(d) * M.RIM_RATIO) then
        ok = false
        break
      end
    end
    if ok then taken[#taken + 1] = i end
  end
  table.sort(taken)
  local events = {}
  for _, i in ipairs(taken) do
    local d = dg[i]
    if d < 0 then
      -- (the sharpest grade change over JUMP_OVER_M near the crest's middle)
      local sharp = 0
      for j = max(w2 + 1, i - 2), min(n - w2, i + 2) do
        local d2 = (z[j + w2] - z[j]) / (w2 * step) - (z[j] - z[j - w2]) / (w2 * step)
        if d2 < sharp then sharp = d2 end
      end
      local lift = 0
      if sharp < 0 and v[i] then
        local radius = (w2 * step) / -sharp
        lift = v[i] * v[i] / radius / M.G
      end
      if lift >= M.JUMP_LIFT and (v[i] or 0) >= M.JUMP_MIN_V_MS then
        events[#events + 1] = { i = i, kind = 'jump', alone = true, lift = lift, dg = d,
                                size = (lift >= M.BIG_JUMP_LIFT and d <= -M.BIG_CREST_DG) and 'big' or nil }
      else
        local size = d <= -M.BIG_CREST_DG and 'big' or (d > -M.SMALL_CREST_DG and 'small' or nil)
        events[#events + 1] = { i = i, kind = 'crest', size = size, alone = d <= -M.ALONE_CREST_DG, dg = d }
      end
    else
      events[#events + 1] = { i = i, kind = 'dip', size = d >= M.BAD_DIP_DG and 'big' or nil,
                              alone = d >= M.ALONE_DIP_DG, dg = d }
    end
  end
  local hills, i = {}, 1
  local need = floor(M.HILL_M / step + 0.5)
  while i <= n do
    local g = grade[i]
    if abs(g) >= M.HILL_GRADE then
      local sign = g > 0 and 1 or -1
      local j = i
      while j + 1 <= n and grade[j + 1] * sign >= M.HILL_GRADE do j = j + 1 end
      if j - i >= need then hills[#hills + 1] = { i0 = i, i1 = j, kind = sign > 0 and 'up' or 'down' } end
      i = j + 1
    else
      i = i + 1
    end
  end
  return events, hills, grade
end

return M
