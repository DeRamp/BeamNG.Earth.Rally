-- dressing.lua: the mock-up's scenes (docs/mockups-1.5.0/stage.html) put through the Lua, and the automatic fill along
-- a whole stage. Game coordinates: +x east, +y north; bearings clockwise from north.
local T = dofile(TESTS .. '/testlib.lua')
local geo = require('earthRally/geo')
local D = require('earthRally/dressing')

local function V(x, y) return { x = x, y = y, z = 0 } end
local function bearing(x, y) return math.deg(math.atan2(x, y)) % 360 end
local function len(x, y) return math.sqrt(x * x + y * y) end
local function ofKind(sites, kind)
  local out = {}
  for _, s in ipairs(sites) do if s.kind == kind then out[#out + 1] = s end end
  return out
end
local function find(objs, key)
  local out = {}
  for _, o in ipairs(objs) do if o.key == key then out[#out + 1] = o end end
  return out
end
-- a tape's two ends: the origin, and its length (its model's, times its Y scale) back along -Y
local function ends(o)
  local L = D.LINEAR_M[o.key] * (o.sy or 1)
  return o.x - o.dx * L, o.y - o.dy * L, o.x, o.y
end
-- distance from (x, y) to a polyline
local function distTo(pts, x, y)
  local best = math.huge
  for i = 1, #pts - 1 do
    local a, b = pts[i], pts[i + 1]
    local abx, aby = b.x - a.x, b.y - a.y
    local k = math.max(0, math.min(1, ((x - a.x) * abx + (y - a.y) * aby) / (abx * abx + aby * aby)))
    best = math.min(best, len(x - a.x - abx * k, y - a.y - aby * k))
  end
  return best
end

T.check(math.abs(select(1, D._bearingToDir(90)) - 1) < 1e-9 and math.abs(select(2, D._bearingToDir(0)) - 1) < 1e-9,
  'bearings: 90 is +x (east), 0 is +y (north)')

------------------------------------------------------------------------------------------ 1. a turn at a crossroads

do
  local S = { V(0, -92), V(0, -7), V(1.5, -2.2), V(4, -0.4), V(8, 0), V(50, 0) }
  local sites = D.plan({ line = S, startM = 0, finishM = 150,
    junctions = { { along = 92, x = 0, y = 0, kind = 'turn', inDeg = 0, outDeg = 90,
                    sides = { { deg = 0, halfW = 3 }, { deg = 270, halfW = 3 } } } } })
  local tape = ofKind(sites, 'tape')[1]
  T.check(tape and #tape.objects == 2, 'crossroads: two tapes')
  local north, west
  for _, o in ipairs(tape and tape.objects or {}) do
    local ax, ay, bx, by = ends(o)
    local cx, cy = (ax + bx) / 2, (ay + by) / 2
    T.check(o.key == 'tape8' and o.shape:find('s_tape_road_closure_8m', 1, true) and o.sy == nil and o.refit == nil,
      'crossroads: 8 m tape for a 6 m road (each end 0.75 m past its edge), at its own size')
    if cy > 4 then north = { cx, cy, ax, ay, bx, by } else west = { cx, cy, ax, ay, bx, by } end
  end
  T.check(north and math.abs(north[1]) < 1e-6 and math.abs(north[2] - 8) < 1e-6, 'crossroads: tape 8 m up the road straight on')
  T.check(west and math.abs(west[1] + 8) < 1e-6 and math.abs(west[2]) < 1e-6, 'crossroads: tape 8 m into the left road')
  -- square to its road: the north tape runs east-west
  T.check(north and math.abs(north[4] - north[6]) < 1e-6 and math.abs(math.abs(north[3] - north[5]) - 8) < 1e-6,
    'crossroads: tape square across its road')
  local board = ofKind(sites, 'board')[1]
  local b = board and board.objects[1]
  T.check(b and b.key == 'dirRight', 'crossroads: s_corner_dir_right')
  T.check(b and math.abs(b.y + 75) < 1e-6 and math.abs(b.x - 4) < 1e-6,
    'crossroads: board 75 m before, on the right, 1 m beyond the road\'s edge (' .. tostring(b and b.x) .. ')')
  -- its face (-X of the model) towards the car: +X (the right of +Y) along the way in
  T.check(b and math.abs(b.dy) < 1e-6 and b.dx < -0.99, 'crossroads: board turned to face the car (+X along the road)')
  local m = ofKind(sites, 'marshal')[1]
  T.check(m and #m.objects == 3, 'crossroads: a junction marshal (table, chair, flag)')
  local tbl = m and find(m.objects, 'table')[1]
  T.check(tbl and math.abs(tbl.x + 13) < 1e-6 and math.abs(tbl.y - 1.5) < 1e-6,
    'crossroads: marshal on the LEFT road, 5 m behind its tape, 1.5 m off its centre')
  -- (the marshal faces back to the junction, +x; table and chair turned 90 degrees to the right of that, as props.lua's
  -- TENT: their +Y to -y)
  T.check(tbl and tbl.dy < -0.99, 'crossroads: marshal\'s table a quarter turn right of facing back to the junction')
  local chr, flg = m and find(m.objects, 'chair')[1], m and find(m.objects, 'flag')[1]
  T.check(chr and chr.dy < -0.99 and flg and flg.dx > 0.99, 'crossroads: the chair turned as the table, the flag not')
  T.check(#find(m and m.objects or {}, 'flag') == 1 and #find(m and m.objects or {}, 'chair') == 1, 'crossroads: chair and flag')
end

-- without bearings for the way in / out: from the line (and one given the wrong way round is turned)
do
  local S = { V(0, -92), V(0, -7), V(1.5, -2.2), V(4, -0.4), V(8, 0), V(50, 0) }
  local a = D.plan({ line = S, junctions = { { along = 92, x = 0, y = 0, kind = 'turn', sides = { { deg = 0 } } } } })
  local b = D.plan({ line = S, junctions = { { along = 92, x = 0, y = 0, kind = 'turn', inDeg = 180, outDeg = 270,
                                               sides = { { deg = 0 } } } } })
  local ba, bb = ofKind(a, 'board')[1], ofKind(b, 'board')[1]
  T.check(ba and ba.objects[1].key == 'dirRight' and bb and bb.objects[1].key == 'dirRight',
    'a turn with no bearings, or bearings reversed: still a right board')
end

------------------------------------------------------------------------------------------ 2. a fork, keep left

do
  local function unit(x, y) local l = len(x, y) return x / l, y / l end
  local lx, ly = unit(-0.34, 0.94)
  local rx, ry = unit(0.36, 0.93)
  local S = { V(0, -92), V(0, 0), V(lx * 60, ly * 60) }
  local sites = D.plan({ line = S, junctions = { { along = 92, x = 0, y = 0, kind = 'fork', side = 'left',
    sides = { { deg = bearing(rx, ry), halfW = 3 } } } } })
  local b = ofKind(sites, 'board')[1]
  T.check(b and b.objects[1].key == 'dir45Left', 'fork: s_corner_dir45_left')
  T.check(b and math.abs(b.objects[1].x + 4) < 1e-6 and math.abs(b.objects[1].y + 75) < 1e-6,
    'fork: board 75 m before, on the left')
  local tape = ofKind(sites, 'tape')[1]
  local o = tape and tape.objects[1]
  local ax, ay, bx, by = ends(o)
  local cx, cy = (ax + bx) / 2, (ay + by) / 2
  local s = len(cx, cy)
  T.check(s > D.TAPE_IN + 0.4, string.format('fork: tape pushed in past 8 m (%.1f m)', s))
  T.check(s >= 9 and s <= 12, string.format('fork: about 10 m in, as the mock-up (%.1f m)', s))
  local ca, cb = distTo(S, ax, ay) - 3, distTo(S, bx, by) - 3
  T.check(ca >= 1 - 1e-6 and cb >= 1 - 1e-6, string.format('fork: both ends 1 m clear of the kept road (%.2f, %.2f)', ca, cb))
  -- (and half a metre less in would not have been)
  local okLess = (distTo(S, ax - rx * 0.5, ay - ry * 0.5) - 3 >= 1) and (distTo(S, bx - rx * 0.5, by - ry * 0.5) - 3 >= 1)
  T.check(not okLess, 'fork: the first spot that clears, not farther')
  T.check(#ofKind(sites, 'marshal') == 0, 'fork: no marshal')
end

------------------------------------------------------------------------------------------ 3. straight on past a side road

do
  local S = { V(0, -60), V(0, 40) }
  local sx, sy = -0.94, 0.34
  local sites = D.plan({ line = S, junctions = { { along = 60, x = 0, y = 0, kind = 'straight', inDeg = 0, outDeg = 0,
    sides = { { deg = bearing(sx, sy), halfW = 2.5 } } } } })
  T.check(#sites == 1 and sites[1].kind == 'tape', 'straight on: tape only (no board, no marshal)')
  local o = sites[1] and sites[1].objects[1]
  T.check(o and o.key == 'tape8', 'straight on: a 5 m road takes the 8 m tape (6.5 m wanted)')
  local ax, ay, bx, by = ends(o)
  T.near(len((ax + bx) / 2, (ay + by) / 2), 8, 1e-6, 'straight on: 8 m in')
end

------------------------------------------------------------------------------------------ 4, 5. radio and medical

local function arc(cx, cy, r, a0, a1, n)
  local out = {}
  for k = 0, n do
    local a = math.rad(a0 + (a1 - a0) * k / n)
    out[#out + 1] = V(cx + r * math.cos(a), cy + r * math.sin(a))
  end
  return out
end
local function bend()
  local pts = { V(0, -125) }
  for _, p in ipairs(arc(60, -60, 60, 180, 150, 10)) do pts[#pts + 1] = p end
  local e = pts[#pts]
  pts[#pts + 1] = V(e.x + 0.5 * 45, e.y + 0.866 * 45)
  return pts
end

do
  local S = bend()
  local sites = D.plan({ line = S, marks = { { kind = 'radio', along = 128, name = 'Radio 1' } } })
  local r = ofKind(sites, 'radio')
  T.check(#r == 1 and r[1].source == 'map' and #r[1].objects == 7, 'radio: one point from the map, 7 objects')
  local o = r[1] and r[1].objects or {}
  local w, b = find(o, 'radioWarn')[1], find(o, 'radio')[1]
  T.check(w and math.abs(w.x - 2.7) < 1e-6 and math.abs(w.y - (-125 + 28)) < 1e-6 and w.dy > 0.99,
    'radio: warning 100 m before, on the right, +Y along the road')
  local cum = geo.cumulative(S)
  local p, dir = geo.pointAt(S, cum, 128)
  T.check(b and math.abs((b.x - p.x) * dir.x + (b.y - p.y) * dir.y) < 1e-6
    and math.abs((b.x - p.x) * dir.y - (b.y - p.y) * dir.x - 2.7) < 1e-6, 'radio: the board at the point, beside the bend')
  local g = find(o, 'gazeboFrame')[1]
  local pg = geo.pointAt(S, cum, 134)
  T.near(g and len(g.x - pg.x, g.y - pg.y), 4.5, 1e-6, 'radio: the post 6 m after, its centre 1.5 m off the edge')
  T.check(#find(o, 'table') == 1 and #find(o, 'chair') == 1 and #find(o, 'flag') == 1, 'radio: table, chair, flag')
  T.check(#ofKind(sites, 'medical') == 0, 'radio: no medical point made up')

  local shared = D.plan({ line = S, marks = { { kind = 'radio', along = 128 }, { kind = 'medical', along = 140 } } })
  local rs = ofKind(shared, 'radio')
  T.check(#rs == 1 and rs[1].shared and #ofKind(shared, 'medical') == 0, 'radio + medical within 50 m: one shared post')
  local so = rs[1] and rs[1].objects or {}
  T.check(#so == 9 and #find(so, 'gazeboFrame') == 1, 'shared: both pairs of boards, one gazebo')
  local mw, mb = find(so, 'medicalWarn')[1], find(so, 'medical')[1]
  T.check(mw and math.abs(mw.y - (-125 + 36)) < 1e-6, 'shared: medical warning 8 m after the radio warning')
  local pm = geo.pointAt(S, cum, 136)
  T.check(mb and len(mb.x - pm.x, mb.y - pm.y) < 3.2, 'shared: medical board 8 m after the radio board')
  local gs = find(so, 'gazeboFrame')[1]
  local pp = geo.pointAt(S, cum, 142)
  T.near(gs and len(gs.x - pp.x, gs.y - pp.y), 4.5, 1e-6, 'shared: the post after the medical board')
end

------------------------------------------------------------------------------------------ 6. spectators at a hairpin

local function hairpin(lead)
  local r = 20
  local S = { V(0, -70 - lead), V(0, 0) }
  local a = arc(-r, 0, r, 0, 180, 30)
  for k = 2, #a do S[#S + 1] = a[k] end
  S[#S + 1] = V(-2 * r, -70 - lead)
  return S
end

do
  local S = hairpin(600)
  local cum = geo.cumulative(S)
  local stagePts = geo.resample(S, 5)
  local corners = geo.corners(stagePts, 5)
  T.check(#corners >= 1, 'hairpin: geo.corners finds it')
  local sites = D.plan({ line = S, cum = cum, startM = 0, finishM = cum[#cum], corners = corners })
  local sp = ofKind(sites, 'spectators')
  T.check(#sp == 1 and sp[1].source == 'rule', 'hairpin: one spectator area by rule')
  local o = sp[1] and sp[1].objects or {}
  local tapes, fences = find(o, 'specTape'), find(o, 'fence')
  T.check(#tapes >= 6 and #fences >= 10, string.format('hairpin: a run of tape and fence (%d, %d)', #tapes, #fences))
  T.check(#o <= D.BUDGET.spectators, 'hairpin: within its budget')
  local inside, clear = true, true
  for _, t in ipairs(tapes) do
    local ax, ay, bx, by = ends(t)
    for _, q in ipairs({ { ax, ay }, { bx, by } }) do
      if not (q[1] < -3 and q[1] > -37) then inside = false end      -- (between the two legs: the inside)
      if distTo(S, q[1], q[2]) - 3 < 4 - 1e-6 then clear = false end
    end
  end
  T.check(inside, 'hairpin: the tape on the inside of the corner')
  T.check(clear, 'hairpin: the tape off the road\'s edge')
  local g = find(o, 'gazeboFrame')[1]
  T.check(g and g.x < -3 and g.x > -37 and distTo(S, g.x, g.y) - 3 >= D.SPEC_OFF + D.FENCE_BEHIND + 2 - 1e-6,
    'hairpin: the gazebo inside, behind the fence')
  T.check(#find(o, 'chair') == 4 and #find(o, 'tarp') == 2 and #find(o, 'bale') == 3, 'hairpin: chairs, tarps, bales')

  -- the map's own spectator point: no automatic one
  local m = D.plan({ line = S, cum = cum, corners = corners, marks = { { kind = 'spectator', along = 300, name = 'Spectator 10' } } })
  local ms = ofKind(m, 'spectators')
  T.check(#ms == 1 and ms[1].source == 'map' and ms[1].along == 300, 'spectators: the map\'s point replaces the rule')

  -- the same hairpin in the first 500 m: none
  local S2 = hairpin(0)
  local c2 = geo.corners(geo.resample(S2, 5), 5)
  T.check(#ofKind(D.plan({ line = S2, corners = c2 }), 'spectators') == 0, 'spectators: none in the first 500 m')
end

------------------------------------------------------------------------------------------ 7. a whole stage, automatic

local function straightStage(km)
  local S = {}
  for k = 0, km * 10 do S[#S + 1] = V(0, k * 100) end
  return S
end

do
  local S = straightStage(20)
  local js, corners = {}, {}
  for s = 300, 19800, 300 do
    js[#js + 1] = { along = s, x = 0, y = s, kind = 'turn', inDeg = 0, outDeg = 90,
                    sides = { { deg = 0, halfW = 3 }, { deg = 270, halfW = 4 } } }
  end
  for s = 200, 19200, 1000 do
    corners[#corners + 1] = { from = s, to = s + 40, dir = 'left', angleDeg = 150 + (s % 3000) / 100, minRadius = 15 }
  end
  local input = { line = S, startM = 0, finishM = 20000, junctions = js, corners = corners }
  local sites = D.plan(input)
  local radios = ofKind(sites, 'radio')
  T.check(#radios == 3, 'auto: a radio point every 5 km of 20 (' .. #radios .. ')')
  local okR = true
  for k, r in ipairs(radios) do
    if math.abs(r.along - k * 5000) > 150 or r.along > 19000 or r.source ~= 'rule' then okR = false end
  end
  T.check(okR, 'auto: radio near 5 / 10 / 15 km, none in the last 1 km')
  local clearR = true
  for _, r in ipairs(radios) do
    for _, j in ipairs(js) do if j.along >= r.along - 40 and j.along <= r.along + 54 then clearR = false end end
  end
  T.check(clearR, 'auto: radio posts moved clear of the junctions')
  local sp = ofKind(sites, 'spectators')
  local okS = #sp >= 3 and #sp <= 5
  for i, a in ipairs(sp) do
    if a.along < 500 then okS = false end
    for k = i + 1, #sp do if math.abs(sp[k].along - a.along) < 4000 then okS = false end end
  end
  T.check(okS, 'auto: spectators at most one per 4 km, none in the first 500 m (' .. #sp .. ')')
  local ms = ofKind(sites, 'marshal')
  local okM = #ms >= 12
  table.sort(ms, function(a, b) return a.along < b.along end)
  for i = 2, #ms do if ms[i].along - ms[i - 1].along < 1000 then okM = false end end
  T.check(okM, 'auto: junction marshals at most one per km (' .. #ms .. ')')
  T.check(#ofKind(sites, 'tape') == #js and #ofKind(sites, 'board') == #js, 'auto: tape and a board at every junction')
  local w8 = 0
  for _, s in ipairs(ofKind(sites, 'tape')) do for _, o in ipairs(s.objects) do if o.key == 'tape10' then w8 = w8 + 1 end end end
  T.check(w8 == #js, 'auto: an 8 m road takes the 10 m tape (9.5 m wanted)')
  T.check(#ofKind(sites, 'medical') == 0, 'auto: no medical point made up')
  local sorted = true
  for i = 2, #sites do if sites[i].from < sites[i - 1].from then sorted = false end end
  T.check(sorted, 'auto: sites in order along the stage')
  local overBudget = false
  for _, s in ipairs(sites) do if #s.objects > (D.BUDGET[s.kind] or 0) then overBudget = true end end
  T.check(not overBudget, 'auto: every site within its budget')

  -- the map marks radio points: none by rule, the rest still filled
  input.marks = { { kind = 'radio', along = 7000 } }
  local m1 = D.plan(input)
  local r1 = ofKind(m1, 'radio')
  T.check(#r1 == 1 and r1[1].source == 'map' and r1[1].along == 7000, 'map radio: replaces the rule')
  T.check(#ofKind(m1, 'marshal') == #ms and #ofKind(m1, 'spectators') == #sp, 'map radio: marshals and spectators still by rule')
  -- the map marks marshals: none by rule (one near a turn stands behind its tape, one away from any on the roadside)
  input.marks = { { kind = 'marshal', along = 2110 }, { kind = 'marshal', along = 2250, offLineM = -12 } }
  local m2 = D.plan(input)
  local ma = ofKind(m2, 'marshal')
  T.check(#ma == 2 and ma[1].source == 'map' and ma[2].source == 'map', 'map marshals: replace the rule')
  T.check(#ofKind(m2, 'radio') == 3, 'map marshals: radio still by rule')
  local t1 = ma[1] and find(ma[1].objects, 'table')[1]
  T.check(t1 and t1.x < -10, 'map marshal near a turn: behind the closed road\'s tape (the left road)')
  local t2 = ma[2] and find(ma[2].objects, 'table')[1]
  T.check(t2 and math.abs(t2.x + 4.5) < 1e-6 and math.abs(t2.y - 2250) < 1e-6, 'map marshal on the road: off the edge, left as marked')
  -- the map's medical point far from any radio point: alone, after its own warning
  input.marks = { { kind = 'medical', along = 8000, name = 'MIV' } }
  local m3 = D.plan(input)
  local md = ofKind(m3, 'medical')
  T.check(#md == 1 and #md[1].objects == 6 and #find(md[1].objects, 'radio') == 0, 'map medical alone: its own boards and gazebo')
end

------------------------------------------------------------------------------------------ the whole stage at once
-- runner.lua plans the whole stage once, at its start (review round 2: plan's `only` and `existingMarshals` are gone)
do
  local line = {}
  for k = 0, 120 do line[#line + 1] = V(0, k * 100) end
  local js = {}
  for _, s in ipairs({ 1000, 1500, 3000 }) do
    js[#js + 1] = { along = s, x = 0, y = s, kind = 'turn', inDeg = 0, outDeg = 90, sides = { { deg = 0 }, { deg = 270 } } }
  end
  local all = D.plan({ line = line, startM = 0, finishM = 12000, junctions = js })
  T.check(#ofKind(all, 'radio') == 2 and #ofKind(all, 'spectators') == 1,
    'whole stage: radio points and a spectator area (' .. #ofKind(all, 'radio') .. ', ' .. #ofKind(all, 'spectators') .. ')')
  T.check(#ofKind(all, 'marshal') == 2 and ofKind(all, 'marshal')[1].along == 1000 and ofKind(all, 'marshal')[2].along == 3000,
    'whole stage: marshals at 1 km and 3 km, none at 1.5 km')
  -- (the options gone: passing them changes nothing)
  local o = D.plan({ line = line, startM = 0, finishM = 12000, junctions = { js[2] }, only = { tape = true },
    existingMarshals = { 1000 } })
  T.check(#ofKind(o, 'marshal') == 1 and #ofKind(o, 'radio') == 2, 'only / existingMarshals: no longer read by plan')
end

------------------------------------------------------------------------------------------ 1.5.0's review

-- A stage that comes back through the same crossroads: north through it (straight on, side roads east and west),
-- round a loop, then west to east through it. On the first pass the road east is the stage's later pass, the road
-- west its way in to it; on the second, north and south are. None of those gets tape; nothing else is a side road.
do
  local S = { V(0, -300), V(0, 0), V(0, 200), V(-200, 200), V(-200, 0), V(0, 0), V(300, 0) }
  local cum = geo.cumulative(S)
  local js = {
    { along = 300, x = 0, y = 0, kind = 'straight', inDeg = 0, outDeg = 0, sides = { { deg = 90 }, { deg = 270 } } },
    { along = cum[6], x = 0, y = 0, kind = 'straight', inDeg = 90, outDeg = 90,
      sides = { { deg = 0 }, { deg = 180 } } },
  }
  local logs = {}
  local plainLog = rawget(_G, 'log')
  log = function(_, _, m) logs[#logs + 1] = m end
  local sites = D.plan({ line = S, cum = cum, startM = 0, finishM = cum[#cum], junctions = js })
  local tapes = 0
  for _, s in ipairs(ofKind(sites, 'tape')) do tapes = tapes + #s.objects end
  T.check(tapes == 0, 'a stage back through its own crossroads: no tape across its own later (or earlier) pass (' ..
    tapes .. ')')
  T.check(#logs == 4, 'and each one left out said once in the log (' .. #logs .. ')')
  D.plan({ line = S, cum = cum, startM = 0, finishM = cum[#cum], junctions = js })
  T.check(#logs == 4, 'planned again: not said again')
  log = plainLog
  -- the same crossroads passed once, its side roads real: taped (the clearance looks along the whole line, and finds
  -- nothing in the way)
  local S1 = { V(0, -300), V(0, 300) }
  local s1 = D.plan({ line = S1, startM = 0, finishM = 600, junctions = { js[1] } })
  local t1 = ofKind(s1, 'tape')[1]
  T.check(t1 and #t1.objects == 2, 'passed once: both side roads taped')
end

-- A junction marshal never in the overrun: the stage turns right off a through road whose only closed road is straight
-- on -- no marshal; with a road to the left as well, the marshal goes behind that one's tape.
do
  local S = { V(0, -300), V(0, 0), V(300, 0) }
  local only = D.plan({ line = S, startM = 0, finishM = 600,
    junctions = { { along = 300, x = 0, y = 0, kind = 'turn', inDeg = 0, outDeg = 90, sides = { { deg = 0 } } } } })
  T.check(#ofKind(only, 'tape') == 1 and #ofKind(only, 'marshal') == 0,
    'turning off a through road, straight on the only closed road: taped, no marshal there')
  local two = D.plan({ line = S, startM = 0, finishM = 600,
    junctions = { { along = 300, x = 0, y = 0, kind = 'turn', inDeg = 0, outDeg = 90,
                    sides = { { deg = 0 }, { deg = 270 } } } } })
  local m = ofKind(two, 'marshal')[1]
  T.check(m and m.objects[1].x < -5 and math.abs(m.objects[1].y) < 3,
    'with a road to the left too: the marshal behind the left road\'s tape (' .. tostring(m and m.objects[1].x) .. ')')
  -- 50 degrees off the way in is not the overrun
  local wide = D.plan({ line = S, startM = 0, finishM = 600,
    junctions = { { along = 300, x = 0, y = 0, kind = 'turn', inDeg = 0, outDeg = 90, sides = { { deg = 310 } } } } })
  T.check(#ofKind(wide, 'marshal') == 1, 'a closed road 50 degrees off the way in: a marshal')
end

-- The stage road's half width at a junction (the file's eighth entry): the tape cleared and
-- the board set against it, not against 3 m; the objects away from the junctions carry their way out for props.lua
do
  local S = { V(0, -300), V(0, 0), V(300, 0) }
  local function plan6(half)
    return D.plan({ line = S, startM = 0, finishM = 600,
      junctions = { { along = 300, x = 0, y = 0, kind = 'turn', inDeg = 0, outDeg = 90, half = half,
                      sides = { { deg = 270 } } } } })
  end
  local b3, b6 = ofKind(plan6(nil), 'board')[1].objects[1], ofKind(plan6(6), 'board')[1].objects[1]
  T.near(b3.x, 3 + D.DIR_BOARD_OUT, 1e-6, 'a board before the turn: 4 m off the centre against the default 3 m')
  T.near(b6.x, 6 + D.DIR_BOARD_OUT, 1e-6, 'against the junction\'s own 6 m: 7 m off')
  T.check(b6.eh == 6 and b6.ex == 1 and math.abs(b6.ey) < 1e-9 and math.abs(b6.eo - 7) < 1e-9,
    'and it carries its way out and the width it was set against')
  local t3, t8 = ofKind(plan6(nil), 'tape')[1].objects[1], ofKind(plan6(8), 'tape')[1].objects[1]
  T.check(math.abs(t3.x + 8) < 1e-6 and math.abs(t8.x + 9) < 1e-6,
    'the tape across the left road moved in to clear an 8 m half width by its 1 m (' ..
    string.format('%.1f / %.1f', t3.x, t8.x) .. ')')
  local t6 = t8
  T.check(t6.ex == nil, 'junction tape is set from the junction, not the edge')
  -- a radio point's boards and post: every object set from the edge
  local long = { V(0, 0), V(0, 7000) }
  local r = ofKind(D.plan({ line = long, startM = 0, finishM = 7000 }), 'radio')[1]
  local all = r and #r.objects > 0
  for _, o in ipairs(r and r.objects or {}) do if not (o.ex and o.eo and o.eh == 3) then all = false end end
  T.check(all, 'a radio point: every object carries its way out from the edge')
end

------------------------------------------------------------------------------------------ 1.5.0 in game (the user, 2026-11-14)

-- 1. A hairpin whose two legs run close (a Y-shaped one): no hay bale on the other leg's road; a wide one keeps all
-- three. (Before the fix the bales took a fixed offset with no look at the road.)
local function hairpin(gap)
  local r = gap / 2
  local S = { V(0, -800), V(0, 0) }
  for k = 1, 17 do
    local a = math.pi - k * math.pi / 18
    S[#S + 1] = V(r + r * math.cos(a), r * math.sin(a))
  end
  S[#S + 1] = V(gap, 0)
  S[#S + 1] = V(gap, -400)
  local cum = geo.cumulative(S)
  local from, to = 800, 800 + math.pi * r
  return D.plan({ line = S, cum = cum, startM = 0, finishM = cum[#cum],
    corners = { { from = from, to = to, dir = 'right', angleDeg = 180, minRadius = r } } }), S
end
do
  local tight, S = hairpin(7)
  local sp = ofKind(tight, 'spectators')[1]
  local bales = sp and find(sp.objects, 'bale') or {}
  local onRoad = 0
  for _, b in ipairs(bales) do if distTo(S, b.x, b.y) < 3 + 0.5 then onRoad = onRoad + 1 end end
  T.check(onRoad == 0, 'Y hairpin: no hay bale on the road (' .. onRoad .. ' of ' .. #bales .. ')')
  local wide, SW = hairpin(60)
  local ws = ofKind(wide, 'spectators')[1]
  T.check(ws and #find(ws.objects, 'bale') == 3, 'a wide hairpin: its three bales (' ..
    (ws and #find(ws.objects, 'bale') or 0) .. ')')
  -- spectator tape and fence: none on the road either
  local runs = 0
  for _, o in ipairs(sp and sp.objects or {}) do
    if o.key == 'specTape' or o.key == 'fence' then
      local ax, ay, bx, by = ends(o)
      if distTo(S, ax, ay) < 3 or distTo(S, bx, by) < 3 or distTo(S, (ax + bx) / 2, (ay + by) / 2) < 3 then
        runs = runs + 1
      end
    end
  end
  T.check(runs == 0, 'Y hairpin: no spectator tape or fence on the road (' .. runs .. ')')
  -- 2. the spectators' chairs a quarter turn right of the way the camp faces (as props.lua's TENT)
  local gz = ws and find(ws.objects, 'gazeboFrame')[1]
  local chairs = ws and find(ws.objects, 'chair') or {}
  local turned = gz and #chairs == 4
  for _, c in ipairs(chairs) do
    if not (math.abs(c.dx - gz.dy) < 1e-6 and math.abs(c.dy + gz.dx) < 1e-6) then turned = false end
  end
  T.check(turned, 'spectator chairs: turned 90 degrees to the right of the way the camp faces')
end

-- 2. A marshal post from the map by the road: table and chair turned 90 degrees right of the road's way (as TENT)
do
  local S = { V(0, 0), V(0, 600) }
  local m = ofKind(D.plan({ line = S, startM = 0, finishM = 600,
    marks = { { kind = 'marshal', along = 300, offLineM = 5 } } }), 'marshal')[1]
  local tbl, chr = m and find(m.objects, 'table')[1], m and find(m.objects, 'chair')[1]
  T.check(tbl and tbl.dx > 0.99 and chr and chr.dx > 0.99, 'roadside marshal: table and chair a quarter turn right of north')
  local flg = m and find(m.objects, 'flag')[1]
  T.check(flg and flg.dy > 0.99, 'roadside marshal: the flag along the road as before')
end

-- 3. The tape just past both edges: the next model up from the road's width + 1.5 m, stretched beyond 10 m; a side
-- road of unknown width (0 or nil) planned as 6 m and carrying what props.lua needs to fit it to the road it finds
do
  local function tf(h) return table.concat({ D.tapeFor(h) }, ' ') end
  T.check(tf(2.25) == 'tape6 6 1' and tf(2.5) == 'tape8 8 1' and tf(3) == 'tape8 8 1' and tf(3.25) == 'tape8 8 1' and
    tf(3.5) == 'tape10 10 1' and tf(4.25) == 'tape10 10 1', 'tapeFor: the shortest model each end 0.75 m past the edge')
  local k, l, sy = D.tapeFor(5)
  T.check(k == 'tape10' and math.abs(l - 11.5) < 1e-9 and math.abs(sy - 1.15) < 1e-9,
    'tapeFor: a 10 m road takes the 10 m tape stretched to 11.5 m (' .. tf(5) .. ')')
  T.check(tf(nil) == 'tape8 8 1' and tf(0) == 'tape8 8 1', 'tapeFor: unknown width taken as 6 m')
  local S = { V(0, -100), V(0, 100) }
  local function tapeOf(halfW)
    local t = ofKind(D.plan({ line = S, startM = 0, finishM = 200, junctions = { { along = 100, x = 0, y = 0,
      kind = 'straight', inDeg = 0, outDeg = 0, sides = { { deg = 270, halfW = halfW } } } } }), 'tape')[1]
    return t and t.objects[1]
  end
  local w = tapeOf(5)
  local ax, ay, bx, by = ends(w)
  T.check(w and w.sy and math.abs(w.sy - 1.15) < 1e-9 and math.abs(math.abs(ay - by) - 11.5) < 1e-6 and
    math.abs((ay + by) / 2) < 1e-6, 'a wide side road: the stretched tape centred across it, 5.75 m either side')
  local u0, un = tapeOf(0), tapeOf(nil)
  T.check(u0 and u0.refit and un and un.refit and u0.refit.len == 8 and #u0.refit.models == 3 and
    u0.refit.past == D.TAPE_PAST and u0.refit.models[3][2] == D.SHAPES.tape10,
    'unknown width: a tape that props.lua fits to the road there')
  T.check(tapeOf(3).refit == nil, 'a known width: no fitting at spawn')
end

-- 4. The direction boards 1 m beyond the road's edge; the radio / medical boards where they were
do
  local long = { V(0, 0), V(0, 7000) }
  local r = ofKind(D.plan({ line = long, startM = 0, finishM = 7000 }), 'radio')[1]
  local rb = r and find(r.objects, 'radio')[1]
  T.check(rb and math.abs(rb.x - (3 + D.BOARD_OUT)) < 1e-6, 'a radio board still just inside the edge (' ..
    tostring(rb and rb.x) .. ')')
  T.check(D.DIR_BOARD_OUT == 1.0 and D.BOARD_OUT == -0.3, 'DIR_BOARD_OUT 1 m; BOARD_OUT unchanged')
end

------------------------------------------------------------------------------------------ review round 2

-- 1. A tape of unknown width carries maxLen: the longest that still clears the stage road at the chosen position.
-- A fork: the stage north along x = 0, a side road leaving at the junction 20 degrees off it (bearing 20): its tape
-- 8 m in can grow only until an end reaches the stage road; on a lone side road square to the stage, much longer.
do
  local S = { V(0, -200), V(0, 200) }
  local function tapeAt(deg)
    local t = ofKind(D.plan({ line = S, startM = 0, finishM = 400, junctions = { { along = 200, x = 0, y = 0,
      kind = 'fork', side = 'left', inDeg = 0, outDeg = 0, sides = { { deg = deg } } } } }), 'tape')[1]
    return t and t.objects[1]
  end
  local f = tapeAt(20)
  T.check(f and type(f.maxLen) == 'number' and f.maxLen >= 8 - 1e-9, 'fork, unknown width: the tape carries maxLen (' ..
    tostring(f and f.maxLen) .. ')')
  if f and f.maxLen then
    -- (the tape's middle and its way across, from its origin and heading; both ends at maxLen clear the stage road)
    local ax, ay, bx, by = ends(f)
    local cx, cy = (ax + bx) / 2, (ay + by) / 2
    local h = f.maxLen / 2
    local e1 = distTo(S, cx + f.dx * h, cy + f.dy * h) - D.HALF
    local e2 = distTo(S, cx - f.dx * h, cy - f.dy * h) - D.HALF
    T.check(e1 >= D.TAPE_CLEAR - 1e-6 and e2 >= D.TAPE_CLEAR - 1e-6, string.format(
      'fork: at maxLen both ends still clear the stage road (%.2f, %.2f)', e1, e2))
    local g = f.maxLen / 2 + D.TAPE_GROW_STEP
    local n1 = math.min(distTo(S, cx + f.dx * g, cy + f.dy * g), distTo(S, cx - f.dx * g, cy - f.dy * g)) - D.HALF
    T.check(f.maxLen >= D.TAPE_LEN_MAX - 1e-9 or n1 < D.TAPE_CLEAR, 'fork: and a step longer would not')
  end
  local sq = tapeAt(270)
  T.check(sq and sq.maxLen and f and f.maxLen and sq.maxLen > f.maxLen,
    'a side road square to the stage: a longer maxLen than the fork\'s (' .. tostring(sq and sq.maxLen) .. ')')
  local k = ofKind(D.plan({ line = S, startM = 0, finishM = 400, junctions = { { along = 200, x = 0, y = 0,
    kind = 'straight', inDeg = 0, outDeg = 0, sides = { { deg = 270, halfW = 3 } } } } }), 'tape')[1]
  T.check(k and k.objects[1].maxLen == nil, 'a known width: no maxLen (nothing refitted)')
end

-- 2. A tape beyond 1.25 x its model laid as two overlapping pieces, each at most 1.25 x 10 m, spanning the whole
-- width; at 11.5 m still one
do
  local S = { V(0, -100), V(0, 100) }
  local t = ofKind(D.plan({ line = S, startM = 0, finishM = 200, junctions = { { along = 100, x = 0, y = 0,
    kind = 'straight', inDeg = 0, outDeg = 0, sides = { { deg = 270, halfW = 7 } } } } }), 'tape')[1]
  T.check(t and #t.objects == 2, 'a 14 m road: two tape pieces (' .. tostring(t and #t.objects) .. ')')
  if t and #t.objects == 2 then
    local lo, hi, ok = math.huge, -math.huge, true
    for _, o in ipairs(t.objects) do
      if not (o.key == 'tape10' and (o.sy or 1) <= D.TAPE_SY_MAX + 1e-9 and (o.sy or 1) >= 1) then ok = false end
      local ax, ay, bx, by = ends(o)
      lo, hi = math.min(lo, ay, by), math.max(hi, ay, by)
    end
    T.check(ok, 'each piece the 10 m model, stretched by at most 1.25')
    T.check(math.abs(hi - lo - 15.5) < 1e-6, string.format('together 15.5 m across (%.2f)', hi - lo))
    local a1, b1 = select(2, ends(t.objects[1])), t.objects[1].y
    local a2, b2 = select(2, ends(t.objects[2])), t.objects[2].y
    local overlap = math.min(math.max(a1, b1), math.max(a2, b2)) - math.max(math.min(a1, b1), math.min(a2, b2))
    T.check(overlap >= D.TAPE_OVERLAP - 1e-6, string.format('overlapping (%.2f m)', overlap))
  end
  T.check(#D.tapePieces(0, 0, 11.5, 0, 11.5, 10) == 1 and #D.tapePieces(0, 0, 13, 0, 13, 10) == 2,
    'tapePieces: one to 12.5 m, two beyond')
end

-- 3. Hay bales, spectator tape and fence carry offRoad (props.lua drops one standing on a road it finds there);
-- nothing else does
do
  local S = {}
  for k = 0, 36 do local a = math.rad(k * 5) S[#S + 1] = V(30 * math.cos(a), 30 * math.sin(a)) end
  table.insert(S, 1, V(30, -200))
  S[#S + 1] = V(-30, -200)
  local cum = geo.cumulative(S)
  local sp = ofKind(D.plan({ line = S, cum = cum, startM = 0, finishM = cum[#cum],
    marks = { { kind = 'spectator', along = cum[#cum] / 2, offLineM = -5 } } }), 'spectators')[1]
  local flagged, wrong = {}, 0
  for _, o in ipairs(sp and sp.objects or {}) do
    if o.offRoad then flagged[o.key] = (flagged[o.key] or 0) + 1 end
    if o.offRoad and not (o.key == 'bale' or o.key == 'specTape' or o.key == 'fence') then wrong = wrong + 1 end
    if not o.offRoad and (o.key == 'bale' or o.key == 'specTape' or o.key == 'fence') then wrong = wrong + 1 end
  end
  T.check(sp and (flagged.bale or 0) > 0 and (flagged.specTape or 0) > 0 and (flagged.fence or 0) > 0 and wrong == 0,
    'spectators: bales, tape and fence flagged offRoad, nothing else (' .. wrong .. ')')
end

T.done('test_dressing')
