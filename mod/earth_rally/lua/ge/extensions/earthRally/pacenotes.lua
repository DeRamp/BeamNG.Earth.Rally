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

------------------------------------------------------------------------------------------ the game's measurement

-- The game grades a corner by the circle through its note's two waypoints and the route half way between
-- (geoPacenotes buildSingleFit), on its own one to six ladder by diameter. (Until the rebuild, 2026-11-20, a short
-- kink was called a grade more open than that -- racingOpen -- for the driven line; our own grade replaces it.)
M.GRADE_DIAMETERS = { 35, 65, 116, 190, 260 }   -- the game's one to six (english/numbering/one_to_six.lua)

local function gradeOf(d)
  for g, lim in ipairs(M.GRADE_DIAMETERS) do if d < lim then return g end end
  return #M.GRADE_DIAMETERS + 1
end
M.gradeOf = gradeOf

-- the radius of the circle through three points (huge for three in a line)
local function circleRadius(a, b, c)
  local d = 2 * (a.x * (b.y - c.y) + b.x * (c.y - a.y) + c.x * (a.y - b.y))
  if abs(d) < 1e-9 then return huge end
  local a2, b2, c2 = a.x * a.x + a.y * a.y, b.x * b.x + b.y * b.y, c.x * c.x + c.y * c.y
  local ux = (a2 * (b.y - c.y) + b2 * (c.y - a.y) + c2 * (a.y - b.y)) / d
  local uy = (a2 * (c.x - b.x) + b2 * (a.x - c.x) + c2 * (b.x - a.x)) / d
  return sqrt((a.x - ux) ^ 2 + (a.y - uy) ^ 2)
end

-- The radius the game measures a corner at: the circle through its note's two waypoints (c.i0, c.i1 over pts) and
-- the road half way between (geoPacenotes buildSingleFit). huge for a corner with no turn.
local function measuredRadius(c, pts)
  local mid = floor((c.i0 + c.i1) / 2 + 0.5)
  if not (pts[c.i0] and pts[mid] and pts[c.i1]) then return huge end
  return circleRadius(pts[c.i0], pts[mid], pts[c.i1])
end

M.measuredRadius = measuredRadius

-- The grade (1 one .. 6 six) the game will call a corner, before any riskIntensity.
function M.measuredGrade(c, pts)
  return gradeOf(2 * measuredRadius(c, pts))
end

-- The length word ("short", -, "half long", "long", "extra long") the game picks by the note's measured grade (not the
-- stepped one) and its length (english/numbering/one_to_six.lua lengthsByIntensity: the upper ends, m, of short,
-- plain, half long and long per grade). A note can move it one word either way (lengthMode 'shorter' / 'longer').
M.LENGTH_BOUNDS = { { 6, 35, 47, 60 }, { 6, 55, 65, 75 }, { 28, 60, 77, 95 }, { 37, 85, 107, 130 },
                    { 42, 100, 125, 150 }, { 50, 100, 140, 180 } }
local function lengthWord(g, arcM)
  local b = M.LENGTH_BOUNDS[math.max(1, math.min(6, g))]
  for w, lim in ipairs(b) do if arcM < lim then return w end end
  return #b + 1
end
M.lengthWord = lengthWord

-- The lengthMode that makes the game say the length word of our grade G over the corner's own length arcM, when the
-- note is measured at grade g over placedM; nil when it says it already. ("skip" where it would be more than one off
-- and ours is the plain word.)
function M.lengthMode(G, arcM, g, placedM)
  local want, got = lengthWord(G, arcM), lengthWord(g, placedM)
  if want == got then return nil end
  if want == got + 1 then return 'longer' end
  if want == got - 1 then return 'shorter' end
  if want == 2 then return 'skip' end
  return want > got and 'longer' or 'shorter'
end

-- ladder: the player's voice's own ladder (the most diameter of each of its grades but the last, m; rallyAdapter.speaks),
-- which the step moves along by one: the casual voices' hard / medium / easy is { 65, 190 }. Our grade G is placed on
-- it by the middle of the game's one to six range it is (GRADE_MID_D). nil: the one to six ladder itself.
M.GRADE_MID_D = { 17.5, 50, 90.5, 153, 225, 300 }

-- A style's corner ladder (its numbering.intensity: { { diameter = { min, max } }... }, tightest first) as the most
-- diameter of each grade but the last; nil when it is not one: fewer than two grades, a grade with no max before the
-- last, or not ascending. The last grade's max, if it has one, is its end, not a step.
function M.ladderOf(intensity)
  if type(intensity) ~= 'table' or #intensity < 2 then return nil end
  local out = {}
  for i = 1, #intensity - 1 do
    local e = intensity[i]
    local mx = type(e) == 'table' and type(e.diameter) == 'table' and e.diameter.max
    if type(mx) ~= 'number' or (out[#out] and mx <= out[#out]) then return nil end
    out[#out + 1] = mx
  end
  return out
end
local function ladderIndex(d, ladder)
  for i, lim in ipairs(ladder) do if d < lim then return i end end
  return #ladder + 1
end
function M.placeForGrade(c, pts, G, ladder)
  local d = 2 * measuredRadius(c, pts)
  local g = gradeOf(d)
  local i0, i1 = c.i0, c.i1
  local want, got = G, g
  if type(ladder) == 'table' and #ladder > 0 then
    want, got = ladderIndex(M.GRADE_MID_D[math.max(1, math.min(6, G))], ladder), ladderIndex(d, ladder)
  end
  local risk = nil
  if got > want then risk = 1 elseif got < want then risk = -1 end
  return i0, i1, risk, g
end

------------------------------------------------------------------------------------------ the corner's own grade

-- (the pacenote rebuild, 2026-11-20, step 2) The road's radius where the corner is tightest, held over GRADE_HOLD_M
-- (or the whole corner, when shorter): the most of the fitted curvature k (geo.curvature) over any stretch that long
-- inside the corner, as a radius. Not the circle through the note's ends, which reads where the ends fall.
-- The ladder over that radius (as a diameter, m: one under the first, six from the last) is set from the game's own
-- stages (tools/pacenote_check, 2026-11-20: the pro's grades and the game's written notes on their clean lines, 1126
-- corners): close to the game's own ladder for its circle (GRADE_DIAMETERS), a little tighter in the middle.
M.GRADE_HOLD_M = 30
M.GRADE_FIT_DIAMETERS = { 35, 58, 111, 178, 262 }

-- returns the radius, and the samples a, b of the stretch it was read over
function M.fitRadius(c, k, step)
  if c.avgR then return c.avgR, c.i0, c.i1 end
  local w = math.max(1, math.min(c.i1 - c.i0 + 1, floor(M.GRADE_HOLD_M / step + 0.5)))
  local best, ba = 0, c.i0
  for a = c.i0, c.i1 - w + 1 do
    local s = 0
    for i = a, a + w - 1 do s = s + abs(k[i] or 0) end
    if s / w > best then best, ba = s / w, a end
  end
  return best > 0 and 1 / best or huge, ba, ba + w - 1
end

-- The grade (1 .. 6) of a fitted radius.
function M.fitGrade(r)
  if r == huge then return #M.GRADE_FIT_DIAMETERS + 1 end
  for g, lim in ipairs(M.GRADE_FIT_DIAMETERS) do if 2 * r < lim then return g end end
  return #M.GRADE_FIT_DIAMETERS + 1
end

-- Making the game say our grade. The game grades a note by the circle through its two waypoints and the road half way
-- between (measuredRadius below) and lets a note move that one step either way (the corner's riskIntensity: +1 one
-- tighter, -1 one more open; compositorUtil.lookupRiskAdjustedIntensityEntry, checked offline with
-- tools/pacenote_check/gamevoice.lua). So the step makes up the difference, one grade at most. (Moving the note's ends
-- in towards the tight part as well, where the circle is two or more out, was tried: a little more of the grades
-- right, but the notes then cover a part of their bend only -- missed bends on the pro stages 0.26 -> 0.38 / km.)
-- Returns the note's ends (the corner's own), riskIntensity (or nil) and the grade the game measures.

------------------------------------------------------------------------------------------ the corner finder

-- (the pacenote rebuild, 2026-11-20, step 3) One finder over the fitted curvature (geo.curvature), in place of the
-- four stacked before it (geo.corners, the sweepers, the open sixes, the map-drawn kinks), each with its own hard
-- cut-off. A bend is a run of one direction: it starts where the curvature reaches FIND_K_IN and goes on while it
-- stays over FIND_K_OUT (the hysteresis: a bend that opens out for a moment is not ended by it), and a dip under that
-- of FIND_JOIN_M or less, still turning its way, does not end it either. What gets called is the owner's rule
-- (2026-11-19): every bend the driver can see -- turning FIND_CALL_DEG or more -- whatever its radius.
-- Its ends: where the curvature is FIND_TRIM of its tightest or more (the smoothing's tails are the approach, not the
-- corner). A run is split where its curvature dips (under FIND_VALLEY of the parts either side), or steps (FIND_STEP_M
-- either side, FIND_STEP_RATIO times tighter on one, both bends -- FIND_STEP_K), between two parts
-- two grades or more apart, each FIND_CALL_DEG or more: "six long into four". Parts closer than that are one corner
-- (the owner's drive, 2026-11-19: "a 5 right, a 5 right, a 5 right short, when really it's like a 5 right long").
M.FIND_K_IN = 1 / 1500
M.FIND_K_OUT = 1 / 2500
M.FIND_JOIN_M = 25
M.FIND_CALL_DEG = 6
M.FIND_TRIM = 0.2
M.FIND_VALLEY = 0.3
M.FIND_JOIN_GAP_M = 50
M.FIND_STEP_M = 30
M.FIND_STEP_RATIO = 2.5
M.FIND_STEP_K = 1 / 600
M.FIND_PIECE_M = 60
M.FIND_BACK_DEG = 1

local function bendOf(turn, k, i0, i1, sign)
  local a, kMax = 0, 0
  for j = i0, i1 do
    a = a + (turn[j] or 0)
    if abs(k[j]) > kMax then kMax = abs(k[j]) end
  end
  return { i0 = i0, i1 = i1, dir = sign > 0 and 'left' or 'right', angleDeg = abs(math.deg(a)),
           minRadius = kMax > 0 and 1 / kMax or huge }
end

-- turn, k: geo.curvature's; returns the corners in order ({ i0, i1, dir, angleDeg, minRadius, sweeper }).
function M.findCorners(turn, k, step)
  local n = #k
  local joinN = max(1, floor(M.FIND_JOIN_M / step + 0.5))
  local runs, i = {}, 1
  while i <= n do
    if abs(k[i]) >= M.FIND_K_IN then
      local sign = k[i] > 0 and 1 or -1
      local a, b = i, i
      while a > 1 and k[a - 1] * sign >= M.FIND_K_OUT do a = a - 1 end
      local j = i
      while true do
        while j + 1 <= n and k[j + 1] * sign >= M.FIND_K_OUT do j = j + 1 end
        b = j
        -- (a short dip under K_OUT, still turning this way, and the bend going on past it)
        local m = j + 1
        while m <= n and m - j <= joinN and k[m] * sign >= 0 and k[m] * sign < M.FIND_K_OUT do m = m + 1 end
        if m <= n and m - j <= joinN + 1 and k[m] * sign >= M.FIND_K_OUT then j = m else break end
      end
      local last = runs[#runs]
      if last and last.sign == sign and a <= last.i1 + 1 then last.i1 = b
      else runs[#runs + 1] = { i0 = a, i1 = b, sign = sign } end
      i = b + 1
    else
      i = i + 1
    end
  end
  local out = {}
  local function gradeOver(x0, x1, sign)
    return M.fitGrade((M.fitRadius(bendOf(turn, k, x0, x1, sign), k, step)))
  end
  -- (a run split where its curvature dips -- under FIND_VALLEY of the parts either side -- into parts; then the
  --  neighbouring parts within a grade of each other joined again, the closest first, and a part turning less than
  --  FIND_CALL_DEG joined to its neighbour nearer its grade: what is left are corners two grades or more apart,
  --  "six long into four". Parts within a grade are one corner -- its shape says the change)
  local function emit(c0, c1, sign, trimL, trimR)
    local kMax = 0
    for j = c0, c1 do if abs(k[j]) > kMax then kMax = abs(k[j]) end end
    if kMax <= 0 then return end
    -- (the corner proper: where it turns FIND_TRIM of its tightest or more; the run's own ends only)
    local lim = max(M.FIND_K_OUT, M.FIND_TRIM * kMax)
    if trimL then while c0 < c1 and abs(k[c0]) < lim do c0 = c0 + 1 end end
    if trimR then while c1 > c0 and abs(k[c1]) < lim do c1 = c1 - 1 end end
    local c = bendOf(turn, k, c0, c1, sign)
    if c.angleDeg >= M.FIND_CALL_DEG and c1 > c0 then
      c.sweeper = M.fitGrade((M.fitRadius(c, k, step))) > #M.GRADE_FIT_DIAMETERS or nil
      out[#out + 1] = c
    end
  end
  local function add(i0, i1, sign)
    if i1 <= i0 then return end
    -- the cuts: every dip in the curvature, kept while it is deep against the parts either side
    local cuts = {}
    for v = i0 + 1, i1 - 1 do
      local kv = abs(k[v])
      if kv < abs(k[v - 1]) and kv <= abs(k[v + 1]) then cuts[#cuts + 1] = v end
    end
    local function peak(x0, x1)
      local m = 0
      for j = x0, x1 do if abs(k[j]) > m then m = abs(k[j]) end end
      return m
    end
    local changed = true
    while changed and #cuts > 0 do
      changed = false
      local worst, wr = nil, -1
      for ci, v in ipairs(cuts) do
        local l0, r1 = cuts[ci - 1] or i0, cuts[ci + 1] or i1
        local r = abs(k[v]) / math.max(1e-12, min(peak(l0, v), peak(v, r1)))
        if r >= M.FIND_VALLEY and r > wr then worst, wr = ci, r end
      end
      if worst then table.remove(cuts, worst) changed = true end
    end
    -- (and where it steps from open to tight or back with no dip between: the curvature over FIND_STEP_M either
    --  side FIND_STEP_RATIO times the other, at the sharpest step)
    local w = max(2, floor(M.FIND_STEP_M / step + 0.5))
    local ratio, stepCut = {}, {}
    for v = i0 + w, i1 - w do
      local A, B = 0, 0
      for j = v - w, v - 1 do A = A + abs(k[j]) end
      for j = v + 1, v + w do B = B + abs(k[j]) end
      -- (both sides a bend of their own -- FIND_STEP_K at least -- not a corner's run-in off the straight)
      ratio[v] = min(A, B) / w >= M.FIND_STEP_K and max(A, B) / min(A, B) or 0
    end
    for v = i0 + w, i1 - w do
      local r = ratio[v]
      if r >= M.FIND_STEP_RATIO then
        local top = true
        for d = -floor(w / 2), floor(w / 2) do
          local o = ratio[v + d]
          if d ~= 0 and o and (o > r or (o == r and d < 0)) then top = false break end
        end
        if top then
          local near = false
          for _, c in ipairs(cuts) do if abs(c - v) <= 2 then near = true break end end
          if not near then cuts[#cuts + 1] = v stepCut[v] = true end
        end
      end
    end
    table.sort(cuts)
    -- the parts, then joined back while two next to each other are within a grade (or one is too small to call)
    local parts = {}
    local from = i0
    local prevStep = false
    for _, v in ipairs(cuts) do
      parts[#parts + 1] = { a = from, b = v, stepL = prevStep, stepR = stepCut[v] }
      prevStep = stepCut[v]
      from = v + 1
    end
    parts[#parts + 1] = { a = from, b = i1, stepL = prevStep }
    local pieceN = floor(M.FIND_PIECE_M / step + 0.5)
    local function info(p)
      local c = bendOf(turn, k, p.a, p.b, sign)
      p.deg, p.g = c.angleDeg, M.fitGrade((M.fitRadius(c, k, step)))
    end
    for _, p in ipairs(parts) do info(p) end
    -- (a part too small to call: under FIND_CALL_DEG; or short and cut off by a step on its tight side -- the open
    --  flanks every corner's smoothed curvature has are its run-in and run-out. A short tight part is a corner of its
    --  own, "four into two", and the tight middle of a long bend too, with the bend either side: issue #6. Joining a
    --  short tight end into its corner as "tightens" instead lost on the check, 2026-11-20: same grade 0.557 -> 0.545
    --  and missed bends 0.03 -> 0.08 / km on the pro stages)
    local function small(pi)
      local p, l, r = parts[pi], parts[pi - 1], parts[pi + 1]
      if p.deg < M.FIND_CALL_DEG then return true end
      if p.b - p.a >= pieceN then return false end
      return (p.stepL and l and p.g > l.g) or (p.stepR and r and p.g > r.g) or false
    end
    while #parts > 1 do
      local bi, bc = nil, nil
      for pi = 1, #parts - 1 do
        local x, y = parts[pi], parts[pi + 1]
        local d = abs(x.g - y.g)
        local sm = small(pi) or small(pi + 1)
        if d <= 1 or sm then
          local cost = (sm and 0 or 10) + d
          if not bc or cost < bc then bi, bc = pi, cost end
        end
      end
      if not bi then break end
      parts[bi] = { a = parts[bi].a, b = parts[bi + 1].b, stepL = parts[bi].stepL, stepR = parts[bi + 1].stepR }
      table.remove(parts, bi + 1)
      info(parts[bi])
    end
    for pi, p in ipairs(parts) do emit(p.a, p.b, sign, pi == 1, pi == #parts) end
  end
  for _, r in ipairs(runs) do add(r.i0, r.i1, r.sign) end
  table.sort(out, function(x, y) return x.i0 < y.i0 end)
  -- (one bend a map draws as pieces with short straight edges between them -- the owner's Cathedral Westbound,
  --  "a 5 right, a 5 right, a 5 right short": pieces of one direction FIND_JOIN_GAP_M or less apart, within a grade
  --  of each other, the road between not turning back, are one corner, graded at the radius it averages over the
  --  whole -- what the driver takes it as)
  local gapN = floor(M.FIND_JOIN_GAP_M / step + 0.5)
  local joined = {}
  for _, c in ipairs(out) do
    local p = joined[#joined]
    local ok = false
    if p and p.dir == c.dir and c.i0 - p.i1 <= gapN then
      local between = 0
      for j = p.i1 + 1, c.i0 - 1 do between = between + (turn[j] or 0) end
      local sign = c.dir == 'left' and 1 or -1
      -- (turning back by FIND_BACK_DEG at most: a straight's rounding is not a turn back)
      ok = between * sign >= -math.rad(M.FIND_BACK_DEG) and abs(M.fitGrade((M.fitRadius(p, k, step))) -
                                       M.fitGrade((M.fitRadius(c, k, step)))) <= 1
    end
    if ok then
      local m = bendOf(turn, k, p.i0, c.i1, p.dir == 'left' and 1 or -1)
      local rad = math.rad(m.angleDeg)
      -- (the pieces' own radii, kept down a chain: a joined corner is never more open than its tightest piece -- the
      --  straight between two fours does not make them a five. Clamped to the most open piece instead: no change on
      --  the check; to the tightest: same grade +0.1 point)
      local rp, rc = p.pieceR or { M.fitRadius(p, k, step) }, c.pieceR or { M.fitRadius(c, k, step) }
      m.pieceR = {}
      for _, r in ipairs(rp) do m.pieceR[#m.pieceR + 1] = r end
      for _, r in ipairs(rc) do m.pieceR[#m.pieceR + 1] = r end
      local lim = huge
      for _, r in ipairs(m.pieceR) do lim = math.min(lim, r) end
      local avg = rad > 0 and (m.i1 - m.i0) * step / rad or huge
      m.avgR = math.min(avg, lim)
      m.joinedFrom = (p.joinedFrom or 1) + 1
      m.sweeper = M.fitGrade((M.fitRadius(m, k, step))) > #M.GRADE_FIT_DIAMETERS or nil
      joined[#joined] = m
    else
      joined[#joined + 1] = c
    end
  end
  return joined
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
  local parts = {}
  for k = a, b do parts[#parts + 1] = cs[k] end
  return { i0 = cs[a].i0, i1 = cs[b].i1, dir = cs[a].dir, angleDeg = ang, minRadius = r, group = group,
           count = b - a + 1, parts = parts }
end

-- corners: the corners in order (findCorners). Returns the list with each chicane made one entry ({ ..., group = 'chicane',
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
-- (1.6.2, issue #11: "on long straights you build up a lot of speed, and often there isn't enough warning or a
--  caution coming into a tight set of corners") After LONG_STRAIGHT_M or more with no corner, at LONG_V_MS or more,
--  the levels are read off CAUTION_LONG: a corner the car has to lose half its speed for is a care (at the top speed,
--  a tightest radius of 60 m or less, about a four), a caution at 40 % (32 m), a double caution at 28 % (16 m). On a short
--  approach CAUTION's levels stand: there 40 % of the speed is a care.
M.LONG_STRAIGHT_M = 300
M.LONG_V_MS = 30                   -- 108 km/h
M.CAUTION_LONG = { 0.55, 0.40, 0.28 }
function M.caution(c, v, step, prevI1, shape, unsaidTightens)
  local vc = huge
  for i = c.i0, c.i1 do if v[i] and v[i] < vc then vc = v[i] end end
  local va = 0
  for i = max(1, prevI1 or 1, c.i0 - floor(M.CAUTION_LOOK_M / step)), c.i0 do if v[i] > va then va = v[i] end end
  if vc == huge then return nil end
  local level = nil
  local long = (c.i0 - (prevI1 or 1)) * step >= M.LONG_STRAIGHT_M and va >= M.LONG_V_MS
  if va >= M.CAUTION_V_MS then
    local r = vc / va
    for l, t in ipairs(long and M.CAUTION_LONG or M.CAUTION) do if r <= t then level = l end end
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
-- A crest that is the top of a downhill from flat road is "down", not a crest (the user's third drive, 2026-11-14):
-- the road before it within FLAT_GRADE either way over FLAT_M, the road after it falling DOWN_FROM_FLAT_GRADE on
-- average over HILL_M. Not a big crest (hidden from under SIGHT_BIG_S): that one is a crest to be warned of.
M.FLAT_GRADE = 0.04
M.FLAT_M = 60
M.DOWN_FROM_FLAT_GRADE = 0.06
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

-- What a crest hides: from the driver's eye (SIGHT_EYE_M up) HIDDEN_EYE_BACK_M before its top, the road just past it
-- that cannot be seen (SIGHT_TARGET_M of it), up to HIDDEN_AHEAD_M on. z: the heights (every `step` m); top: the
-- crest's sample. Returns the last sample of that hidden stretch, or nil when nothing past the top is hidden.
M.HIDDEN_EYE_BACK_M = 30
M.HIDDEN_AHEAD_M = 150
function M.hiddenAfter(z, step, top)
  local n = #z
  local ie = max(1, top - floor(M.HIDDEN_EYE_BACK_M / step + 0.5))
  local eye = z[ie] + M.SIGHT_EYE_M
  local best, last = -huge, nil
  for j = ie + 1, min(n, top + floor(M.HIDDEN_AHEAD_M / step + 0.5)) do
    local d = (j - ie) * step
    local seen = (z[j] + M.SIGHT_TARGET_M - eye) / d >= best
    if (z[j] - eye) / d > best then best = (z[j] - eye) / d end
    if j > top and not seen then last = j
    elseif last and seen then break end
  end
  return last
end

-- pts: the stage's samples (with z), v: M.speeds over them. Returns
--   events  { { i, kind = 'crest' | 'jump' | 'dip', size = 'small' | 'big' | nil, alone = true when strong enough
--             to be called on its own, hiddenTo (a crest's or a jump's: M.hiddenAfter) }... } in order
--           (a crest at the top of a downhill from flat road has down = true: "down" where the voice says it)
--   hills   { { i0, i1, kind = 'up' | 'down', fromCrest = that crest's event when it is one's descent }... }
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
  -- (how far past each crest and jump the road is out of sight: a corner starting there is called with it)
  for _, ev in ipairs(events) do
    if ev.kind ~= 'dip' then ev.hiddenTo = M.hiddenAfter(z, step, ev.i) end
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
  -- (a crest at the top of a downhill from flat road: "down")
  -- (the grades straight off the heights each side of the top: the centred grade would take some of the descent
  --  into the road before it)
  local fb, fa = max(1, floor(M.FLAT_M / step + 0.5)), max(1, floor(M.HILL_M / step + 0.5))
  for _, ev in ipairs(events) do
    if ev.kind == 'crest' and ev.size ~= 'big' and ev.i - fb >= 1 and ev.i + fa <= n then
      local before = (z[ev.i] - z[ev.i - fb]) / (fb * step)
      local after = (z[ev.i + fa] - z[ev.i]) / (fa * step)
      if abs(before) <= M.FLAT_GRADE and after <= -M.DOWN_FROM_FLAT_GRADE then
        ev.down = true
        for _, h in ipairs(hills) do
          if h.kind == 'down' and h.i1 >= ev.i and h.i0 <= ev.i + fa then h.fromCrest = ev end
        end
      end
    end
  end
  return events, hills, grade
end

return M
