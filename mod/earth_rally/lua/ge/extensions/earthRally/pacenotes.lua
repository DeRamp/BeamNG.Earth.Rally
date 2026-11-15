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
------------------------------------------------------------------------------------------ long sweepers

-- A long sweeping bend too open for geo.corners (which keeps a radius of maxRadius, 200 m, or less): a run of one
-- direction gentler than that but tighter than SWEEP_R, over SWEEP_MIN_M or more and SWEEP_DEG or more in all, on
-- curvature smoothed over SWEEP_SMOOTH_M (geo.curvature's turn, k at that smoothing), with gaps of SWEEP_GAP_M joined.
-- Only where no corner was found: a sweeper is a note of its own, never laid over a corner. The game measures its
-- number and length as for any corner ("six long"). (The user, 2026-11-14: the long sweeper at the start of
-- otr24 shadow buck -- 45 degrees over 500 m at 300 to 900 m radius -- was not in the notes.)
M.SWEEP_R = 1000
M.SWEEP_DEG = 30
M.SWEEP_MIN_M = 100
M.SWEEP_GAP_M = 30
M.SWEEP_SMOOTH_M = 40

-- turn, k: geo.curvature at SWEEP_SMOOTH_M; corners: geo.corners' list. Returns the corners and the sweepers in one
-- list in order (a sweeper: { i0, i1, dir, angleDeg, minRadius, sweeper = true }).
function M.sweepers(turn, k, step, corners)
  local n = #k
  local covered = {}
  for _, c in ipairs(corners) do for i = c.i0, c.i1 do covered[i] = true end end
  local kMin, gapN = 1 / M.SWEEP_R, max(1, floor(M.SWEEP_GAP_M / step + 0.5))
  local runs, i = {}, 1
  while i <= n do
    if abs(k[i]) >= kMin then
      local sign = k[i] > 0 and 1 or -1
      local j = i
      while j + 1 <= n and k[j + 1] * sign >= kMin do j = j + 1 end
      local last = runs[#runs]
      if last and last.sign == sign and i - last.i1 <= gapN then last.i1 = j
      else runs[#runs + 1] = { i0 = i, i1 = j, sign = sign } end
      i = j + 1
    else
      i = i + 1
    end
  end
  local out = {}
  for _, c in ipairs(corners) do out[#out + 1] = c end
  for _, r in ipairs(runs) do
    if (r.i1 - r.i0) * step >= M.SWEEP_MIN_M then
      local angle, kMax, hit = 0, 0, false
      for j = r.i0, r.i1 do
        angle = angle + turn[j]
        if abs(k[j]) > kMax then kMax = abs(k[j]) end
        if covered[j] then hit = true end
      end
      if not hit and abs(math.deg(angle)) >= M.SWEEP_DEG then
        out[#out + 1] = { i0 = r.i0, i1 = r.i1, dir = r.sign > 0 and 'left' or 'right', angleDeg = abs(math.deg(angle)),
                          minRadius = kMax > 0 and 1 / kMax or huge, sweeper = true }
      end
    end
  end
  table.sort(out, function(a, b) return a.i0 < b.i0 end)
  return out
end

local function tightish(c)
  return c.minRadius <= M.CHICANE_R and c.angleDeg >= M.CHICANE_DEG[1] and c.angleDeg <= M.CHICANE_DEG[2]
end

local function merged(cs, a, b, group)
  local r, ang = huge, 0
  for k = a, b do r = min(r, cs[k].minRadius) ang = max(ang, cs[k].angleDeg) end
  local parts = {}
  for k = a, b do parts[#parts + 1] = cs[k] end
  return { i0 = cs[a].i0, i1 = cs[b].i1, dir = cs[a].dir, angleDeg = ang, minRadius = r, group = group,
           count = b - a + 1, parts = parts }
end

-- corners: geo.corners' list in order. Returns the list with each chicane made one entry ({ ..., group = 'chicane',
-- count = 2, parts = its two corners }) and the first corner of each twisty run marked (twisty = how many corners the run has).
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
-- one is no surprise. Levels: 1 care, 2 caution, 3 double caution. And a corner that tightens over a crest on a
-- fast approach (shape 'tightensOverCrest': blind, and tighter than it starts) is at least a caution. (A plain
-- tightening corner is not: its shape says it, and the game's own stages put a caution on only a fifth of theirs.)
M.CAUTION_LOOK_M = 250
M.CAUTION_V_MS = 25      -- 90 km/h: the approach at least this fast
M.CAUTION = { 0.40, 0.30, 0.22 }   -- corner speed / approach speed at or under these
M.CAUTION_TIGHTENS_V_MS = 20       -- 72 km/h: a corner tightening over a crest on an approach this fast

M.CARE_DEG = 60                    -- a corner this sharp ...
M.CARE_STRAIGHT_M = 120            -- ... after this far with no corner: a care
function M.caution(c, v, step, prevI1, shape, unsaidTightens)
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
  if shape == 'tightensOverCrest' and va >= M.CAUTION_TIGHTENS_V_MS then level = max(level or 0, 2) end
  -- (a corner of CARE_DEG or more after CARE_STRAIGHT_M with no corner: a care -- where the game's own stages put
  --  theirs most, against how long the straight before was)
  if M.CARE_DEG and c.angleDeg >= M.CARE_DEG and prevI1 and (c.i0 - prevI1) * step >= M.CARE_STRAIGHT_M then
    level = max(level or 0, 1)
  end
  -- (a corner that tightens, for a voice that cannot say so: a care, on a fast approach)
  if unsaidTightens and va >= M.CAUTION_TIGHTENS_V_MS then level = max(level or 0, 1) end
  return level
end

------------------------------------------------------------------------------------------ the height profile

-- Jumps and dips are where the grade changes (crests are where the driver cannot see over: M.blind): the grade over the GRADE_OVER_M after a point against the one before
-- it (dg, a fraction: -0.1 is a road going from level to 10 % down). Heights are smoothed over three samples first.
-- The strongest first, and nothing of the same kind within EVENT_M of one already taken, nor of the other kind
-- within OPPOSITE_M of any stronger one RIM_RATIO times as strong, taken or not (peaks only, both): the two rims of a hollow read as
-- crests of about half its strength, and are not (nor are they when the hollow itself gave way to a stronger crest).
-- A jump is a big crest (JUMP_CREST_DG) the car cannot follow at the speed it gets there: the sharper grade change
-- over JUMP_OVER_M gives the crest's vertical radius, and v^2 / radius over g is how much of the car's weight it
-- would take to stay on the road (1 = the tyres just go light). (Only a big crest: most lifts over JUMP_LIFT are at
-- the speed model's top speed, where a few centimetres of elevation data make the difference.)
-- Nothing is read where the heights themselves are not a road's: a step between two samples steeper than BAD_GRADE
-- within GRADE_OVER_M (elevation data does that -- a matched line's 6 m drop in 4 m -- roads do not).
M.GRADE_OVER_M = 20
M.EVENT_M = 40
M.OPPOSITE_M = 60
M.RIM_RATIO = 1.3
M.BAD_GRADE = 0.4       -- (40 % over 5 m: no road; the matched line's 6 m in 4 m is 150 %)
M.CREST_DG = 0.06        -- a grade change read as a crest: a jump if big enough, and the rim test's (no call itself)
M.DIP_DG = 0.14
M.BAD_DIP_DG = 0.22
M.ALONE_DIP_DG = 0.18
M.JUMP_OVER_M = 10
M.JUMP_LIFT = 1.4
M.JUMP_CREST_DG = 0.14   -- a jump is a crest this big at least ...
M.BIG_JUMP_LIFT = 2.4
M.BIG_JUMP_DG = 0.22     -- ... a big one this big, and BIG_JUMP_LIFT
M.JUMP_MIN_V_MS = 15
-- Crests are the driver's sight, not the grade (M.blind; the user's second drive, 2026-11-14: the grade changes of a
-- steep climb or descent read as crests the driver sees right over). From an eye SIGHT_EYE_M over the road, a crest
-- is where the road SIGHT_S seconds ahead at the modelled speed (SIGHT_MAX_M at most) is hidden behind a rise, by
-- SIGHT_TARGET_M at least, and stays hidden for SIGHT_BACK_S more (a road that comes back into view just past it --
-- a hollow, a short dip -- the driver sees over); big where it is hidden from under SIGHT_BIG_S on, small from
-- SIGHT_SMALL_S on. The crest is the summit that hides it, one per BLIND_EVENT_M. (The grade change still gives
-- jumps and dips.)
M.SIGHT_EYE_M = 1.1
M.SIGHT_TARGET_M = 0.6   -- hidden by this much (the object height of a road's stopping sight distance), not the
                         -- last few centimetres of its surface
-- (the two figures, on the 26 lines the user had matched in the game then, before the review fixes, crest calls / km, and against the game's own stages
--  found / agreeing: 0.3 m and any grade 1.45, 59 / 48 %; 0.6 m and any grade 0.96, 46 / 50 %; 0.6 m and 2 %
--  0.84, 42 / 49 %; 0.8 m and 2 % 0.63, 36 / 49 %. The build of the second drive: 1.5 / km. With the reviews'
--  fixes -- back in view, the grade where it is hidden, the descent rule -- on 28 lines: 0.78, 40 / 48 %)
M.SIGHT_S = 2.0
M.SIGHT_BIG_S = 1.0
M.SIGHT_ON_GRADE = 0.02  -- over the top: the road from the summit that hides it to there climbs no more than this
M.SIGHT_BACK_S = 1.0     -- ... and stays hidden this much further on
M.SIGHT_DOWN_GRADE = 0.04 -- no crest where the car's road already falls more than this ...
M.SIGHT_DOWN_M = 20      -- ... over this far behind it
M.SIGHT_GRADE_M = 10     -- the grade where the road is hidden (SIGHT_ON_GRADE), over this far
M.SIGHT_SMALL_S = 1.5    -- a sight this long or more (but under SIGHT_S): a small crest, only just blind
M.SIGHT_MAX_M = 150      -- (binds only over 75 m/s: the speed model's top is 40)
M.SIGHT_MIN_V_MS = 12    -- slower than this, a hidden road ahead is no surprise
M.BLIND_EVENT_M = 100    -- one blind crest per this far
M.BLIND_JOIN_M = 20      -- points that hide the road this close together are one crest (it moves over a long top)
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

-- The blind crests over heights z (smoothed, every `step` m) at speeds v: { { i (the summit), size = 'big' | 'small' | nil,
-- sight (m: the shortest sight it leaves) }... }, worst first and one per BLIND_EVENT_M. clean(i): the heights round i
-- are a road's (heights' BAD_GRADE test); nil: all are.
function M.blind(z, step, v, clean)
  local n = #z
  local hits = {}
  for i = 1, n - 1 do
    local vi = v[i] or 0
    if vi >= M.SIGHT_MIN_V_MS then
      local need = min(M.SIGHT_MAX_M, vi * M.SIGHT_S)
      local jn = min(n, i + floor(need / step))
      if (jn - i) * step >= need - step then
        -- (from the eye: the road at j is seen when it, SIGHT_TARGET_M over it, is over the highest of the road
        --  between; the sight is from the last one seen on, where the road stays hidden up to the need)
        local eye = z[i] + M.SIGHT_EYE_M
        local maxS, arg, seen = -huge, nil, i
        for j = i + 1, jn do
          local d = (j - i) * step
          if not arg or (z[j] + M.SIGHT_TARGET_M - eye) / d >= maxS then seen = j end
          local s = (z[j] - eye) / d
          if s > maxS then maxS, arg = s, j end
        end
        -- blind: the road where the car needs to see it is hidden (the driver sees right over a rise that
        -- leaves it in view, however much the grade changes), and it is over a top: the road there level or going
        -- down (SIGHT_ON_GRADE at most, over the SIGHT_GRADE_M before it -- not one sample, so a few centimetres of
        -- heights do not decide it; nor from arg, the point the sightline grazes, which on a climb is short of the
        -- top). A steep climb easing off hides the road beyond as it goes on up, and is no crest. (A road hidden is
        -- lower than the line to the highest point before it, so arg < jn.)
        local kg = max(arg or i, jn - max(1, floor(M.SIGHT_GRADE_M / step + 0.5)))
        local blind = seen < jn and arg and z[jn] - z[kg] < M.SIGHT_ON_GRADE * (jn - kg) * step
        -- ... and the same going down: where the car is on a descent steeper than SIGHT_DOWN_GRADE (over the
        -- SIGHT_DOWN_M behind it), the road beyond getting a little steeper is one the driver looks down onto --
        -- only where it is only just hidden (SIGHT_SMALL_S or more of sight): a sharp drop-off on a descent hides
        -- the road sooner, and is a crest
        local kb = max(1, i - max(1, floor(M.SIGHT_DOWN_M / step + 0.5)))
        if blind and kb < i and (seen + 1 - i) * step / vi >= M.SIGHT_SMALL_S and
           z[i] - z[kb] < -M.SIGHT_DOWN_GRADE * (i - kb) * step then
          blind = false
        end
        -- ... and it stays hidden a while on: a road back in view just past it is one the driver sees over
        if blind then
          for j = jn + 1, min(n, jn + floor(vi * M.SIGHT_BACK_S / step)) do
            if (z[j] + M.SIGHT_TARGET_M - eye) / ((j - i) * step) >= maxS then blind = false break end
          end
        end
        if blind then
          local d = (seen + 1 - i) * step
          local t = d / vi
          if not hits[arg] or t < hits[arg].t then hits[arg] = { t = t, sight = d } end
        end
      end
    end
  end
  -- (the point that hides the road moves along a long top as the car comes up it: the points next to each other
  --  are one crest, called once, at its highest, as blind as the worst of them)
  local at = {}
  for i in pairs(hits) do at[#at + 1] = i end
  table.sort(at)
  local gap = max(1, floor(M.BLIND_JOIN_M / step + 0.5))
  local list, k = {}, 1
  while k <= #at do
    local top, best, last = at[k], hits[at[k]], at[k]
    local m = k + 1
    while m <= #at and at[m] - last <= gap do
      local h = hits[at[m]]
      if h.t < best.t then best = h end
      last = at[m]
      m = m + 1
    end
    for j = at[k], last do if z[j] > z[top] then top = j end end
    if not clean or clean(top) then list[#list + 1] = { i = top, t = best.t, sight = best.sight } end
    k = m
  end
  table.sort(list, function(a, b)
    if a.t ~= b.t then return a.t < b.t end
    return a.i < b.i
  end)
  local e = max(1, floor(M.BLIND_EVENT_M / step + 0.5))
  local out = {}
  for _, h in ipairs(list) do
    local ok = true
    for _, o in ipairs(out) do if abs(o.i - h.i) <= e then ok = false break end end
    if ok then
      local size = h.t < M.SIGHT_BIG_S and 'big' or (h.t >= M.SIGHT_SMALL_S and 'small' or nil)
      out[#out + 1] = { i = h.i, size = size, sight = h.sight }
    end
  end
  return out
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
    -- (a peak only: a crest's or a hollow's shoulder samples are not events, nor do they put one out)
    local peak = abs(d) >= abs(dg[i - 1]) and abs(d) >= abs(dg[i + 1]) and
                 (dg[i - 1] == 0 or (dg[i - 1] < 0) == (d < 0)) and (dg[i + 1] == 0 or (dg[i + 1] < 0) == (d < 0))
    if (d <= -M.CREST_DG or d >= M.DIP_DG) and peak and clean(i) then cands[#cands + 1] = i end
  end
  table.sort(cands, function(x, y)
    if abs(dg[x]) ~= abs(dg[y]) then return abs(dg[x]) > abs(dg[y]) end
    return x < y
  end)
  local eo = max(1, floor(M.OPPOSITE_M / step + 0.5))
  local taken = {}
  for ci, i in ipairs(cands) do
    local d, ok = dg[i], true
    for _, j in ipairs(taken) do
      if (dg[j] < 0) == (d < 0) and abs(j - i) <= e then ok = false break end
    end
    -- (a rim: any stronger candidate of the other kind close by, whether it was taken or not)
    for cj = 1, ci - 1 do
      if not ok then break end
      local j = cands[cj]
      if (dg[j] < 0) ~= (d < 0) and abs(j - i) <= eo and abs(dg[j]) >= abs(d) * M.RIM_RATIO then ok = false end
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
      if lift >= M.JUMP_LIFT and (v[i] or 0) >= M.JUMP_MIN_V_MS and d <= -M.JUMP_CREST_DG then
        events[#events + 1] = { i = i, kind = 'jump', alone = true, lift = lift, dg = d, v = v[i],
                                size = (lift >= M.BIG_JUMP_LIFT and d <= -M.BIG_JUMP_DG) and 'big' or nil }
      end
      -- (a grade change that is no jump is no call: a crest is only where the driver cannot see over it, below)
    else
      events[#events + 1] = { i = i, kind = 'dip', size = d >= M.BAD_DIP_DG and 'big' or nil,
                              alone = d >= M.ALONE_DIP_DG, dg = d }
    end
  end
  -- the crests, from the sightline: the road where the car needs to see it hidden behind a rise
  -- (not the rim of a dip called on its own within OPPOSITE_M, RIM_RATIO times as sharp as the crest at its
  --  sharpest near the summit: the dip's call says it -- `rimOf` lists those dips, and the writer leaves the crest
  --  out only where one of them is said; a dip not called, the crest is. A hollow the road comes back out of in view is
  --  no crest at all, M.blind. Nor a jump's summit, within EVENT_M: called as the jump)
  local ej = max(1, floor(M.BLIND_JOIN_M / step + 0.5))
  for _, sc in ipairs(M.blind(z, step, v, clean)) do
    local near, rimOf, sharp = false, {}, 0
    for j = max(1, sc.i - ej), min(n, sc.i + ej) do if dg[j] < sharp then sharp = dg[j] end end
    for _, ev in ipairs(events) do
      if ev.kind == 'jump' and abs(ev.i - sc.i) <= e then near = true break end
      if ev.kind == 'dip' and ev.alone and abs(ev.i - sc.i) <= eo and ev.dg >= -sharp * M.RIM_RATIO then
        rimOf[#rimOf + 1] = ev
      end
    end
    if not near then
      events[#events + 1] = { i = sc.i, kind = 'crest', size = sc.size, alone = true, dg = dg[sc.i], sight = sc.sight,
                              rimOf = #rimOf > 0 and rimOf or nil }
    end
  end
  table.sort(events, function(a, b) return a.i < b.i end)
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
