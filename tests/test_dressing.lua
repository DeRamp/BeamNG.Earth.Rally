-- dressing.lua: the mock-up's scenes (docs/mockups-1.6.0/stage.html) put through the Lua, and the automatic fill along
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
  -- (1.6.2, issue #9: the branches 41 degrees apart, an acute junction: the tape runs parallel with the kept road,
  -- across the closed branch's mouth, no longer square to that branch)
  local tape = ofKind(sites, 'tape')[1]
  local o = tape and tape.objects[1]
  local ax, ay, bx, by = ends(o)
  local cx, cy = (ax + bx) / 2, (ay + by) / 2
  T.check(o and math.abs(o.dx * lx + o.dy * ly) > 1 - 1e-6, 'fork: tape parallel with the kept road')
  T.check(math.abs(cx * ry - cy * rx) < 1e-6, 'fork: its middle on the closed branch centre line')
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
  T.check(w and math.abs(w.x - (3 + D.BOARD_OUT)) < 1e-6 and math.abs(w.y - (-125 + 28)) < 1e-6 and w.dy > 0.99,
    'radio: warning 100 m before, on the right 1 m past the edge, +Y along the road')
  local cum = geo.cumulative(S)
  local p, dir = geo.pointAt(S, cum, 128)
  T.check(b and math.abs((b.x - p.x) * dir.x + (b.y - p.y) * dir.y) < 1e-6
    and math.abs((b.x - p.x) * dir.y - (b.y - p.y) * dir.x - (3 + D.BOARD_OUT)) < 1e-6, 'radio: the board at the point, beside the bend')
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
  T.check(mb and len(mb.x - pm.x, mb.y - pm.y) < 3 + D.BOARD_OUT + 0.2, 'shared: medical board 8 m after the radio board')
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
  T.check(#radios >= 3 and #radios <= 4, 'auto: a radio point every 4-6 km of 20 (' .. #radios .. ')')
  local okR, prevR = true, 0
  for _, r in ipairs(radios) do
    local gap = r.along - prevR
    if gap < 4000 - 300 or gap > 6000 + 300 or r.along > 19000 or r.source ~= 'rule' then okR = false end
    prevR = r.along
  end
  T.check(okR, 'auto: radio 4-6 km apart (give or take moving clear of a junction), none in the last 1 km')
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
  local okM = #ms >= 8
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
  -- the map marks marshals: none by rule (one near a turn stands behind its tape, one 100 m from any on the roadside)
  input.marks = { { kind = 'marshal', along = 2110 }, { kind = 'marshal', along = 2200, offLineM = -12 } }
  local m2 = D.plan(input)
  local ma = ofKind(m2, 'marshal')
  T.check(#ma == 2 and ma[1].source == 'map' and ma[2].source == 'map', 'map marshals: replace the rule')
  T.check(#ofKind(m2, 'radio') == 3, 'map marshals: radio still by rule')
  local t1 = ma[1] and find(ma[1].objects, 'table')[1]
  T.check(t1 and t1.x < -10, 'map marshal near a turn: behind the closed road\'s tape (the left road)')
  local t2 = ma[2] and find(ma[2].objects, 'table')[1]
  T.check(t2 and math.abs(t2.x + 3 + D.ROADSIDE_MARSHAL_OUT) < 1e-6 and math.abs(t2.y - 2200) < 1e-6,
    'map marshal on the road: off the edge, left as marked')
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
  local nR = #ofKind(all, 'radio')
  T.check(nR >= 1 and nR <= 2 and #ofKind(all, 'spectators') == 1,
    'whole stage: radio points and a spectator area (' .. nR .. ', ' .. #ofKind(all, 'spectators') .. ')')
  local wm = ofKind(all, 'marshal')
  local okW = #wm <= 2
  for i = 2, #wm do if wm[i].along - wm[i - 1].along < 1000 then okW = false end end
  T.check(okW, 'whole stage: marshals at junction turns, never two within 1 km (1 km and 1.5 km not both)')
  -- (the options gone: passing them changes nothing)
  local o = D.plan({ line = line, startM = 0, finishM = 12000, junctions = { js[2] }, only = { tape = true },
    existingMarshals = { 1000 } })
  local o2 = D.plan({ line = line, startM = 0, finishM = 12000, junctions = { js[2] } })
  T.check(#ofKind(o, 'marshal') == #ofKind(o2, 'marshal') and #ofKind(o, 'radio') == #ofKind(o2, 'radio'),
    'only / existingMarshals: no longer read by plan')
end

------------------------------------------------------------------------------------------ 1.6.0's review

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

-- 1.6.0's note 11: a map marshal by any taped junction stands behind its tape -- at a straight or a fork the closed
-- road furthest from the way out; at a turn whose only closed road is the overrun, behind that road's tape all the same,
-- MARSHAL_BEHIND back and MARSHAL_OVERRUN_SIDE past its edge away from the way out (the rule's marshals: still none
-- there, above); at a straight or fork MARSHAL_SIDE past the closed road's edge (lite review)
do
  local mark = { { kind = 'marshal', along = 300, offLineM = 8 } }
  local St = { V(0, -300), V(0, 300) }
  local st = ofKind(D.plan({ line = St, startM = 0, finishM = 600, marks = mark,
    junctions = { { along = 300, x = 0, y = 0, kind = 'straight', inDeg = 0, outDeg = 0,
                    sides = { { deg = 315 }, { deg = 250 } } } } }), 'marshal')
  local t = st[1] and find(st[1].objects, 'table')[1]
  T.check(#st == 1 and st[1].along == 300 and t and len(t.x, t.y) > 10 and math.abs(bearing(t.x, t.y) - 250) < 25 and
    distTo({ V(0, 0), V(-60 * math.sin(math.rad(70)), -60 * math.cos(math.rad(70))) }, t.x, t.y) - 3 > 1,
    'map marshal at a straight: behind the tape of the side road furthest from the way out (' ..
    tostring(t and bearing(t.x, t.y)) .. ')')

  local function unit(x, y) local l = len(x, y) return x / l, y / l end
  local lx, ly = unit(-0.34, 0.94)
  local rx, ry = unit(0.36, 0.93)
  local Sf = { V(0, -92), V(0, 0), V(lx * 60, ly * 60) }
  local fk = ofKind(D.plan({ line = Sf, marks = { { kind = 'marshal', along = 92, offLineM = 8 } },
    junctions = { { along = 92, x = 0, y = 0, kind = 'fork', side = 'left',
                    sides = { { deg = bearing(rx, ry), halfW = 3 } } } } }), 'marshal')
  local f = fk[1] and find(fk[1].objects, 'table')[1]
  local Sc = { V(0, 0), V(rx * 60, ry * 60) }
  T.check(#fk == 1 and f and math.abs(bearing(f.x, f.y) - bearing(rx, ry)) < 20 and distTo(Sf, f.x, f.y) - 3 > 1,
    'map marshal at a fork: behind the closed branch\'s tape, off the kept road')
  T.check(f and distTo(Sc, f.x, f.y) - 3 > 1,
    'map marshal at a fork: clear of the closed branch\'s surface too (' .. tostring(f and distTo(Sc, f.x, f.y)) .. ')')

  local Sr = { V(0, -300), V(0, 0), V(300, 0) }
  local ov = ofKind(D.plan({ line = Sr, startM = 0, finishM = 600, marks = mark,
    junctions = { { along = 300, x = 0, y = 0, kind = 'turn', inDeg = 0, outDeg = 90, sides = { { deg = 0 } } } } }),
    'marshal')
  local o = ov[1] and find(ov[1].objects, 'table')[1]
  T.check(#ov == 1 and ov[1].along == 300 and o and math.abs(o.x + (3 + D.MARSHAL_OVERRUN_SIDE)) < 1e-6 and
    math.abs(o.y - (D.TAPE_IN + D.MARSHAL_BEHIND)) < 1e-6,
    'map marshal at a turn, the only closed road the overrun: behind its tape 5 m, 4 m past its edge away from the ' ..
    'way out (' ..
    tostring(o and o.x) .. ', ' .. tostring(o and o.y) .. ')')
  T.check(D.MARSHAL_AT_JUNCTION_M == 40 and D.MARSHAL_OVERRUN_SIDE == 4,
    'map marshals: 40 m from a junction on the ground; 4 m past the edge in the overrun')
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

------------------------------------------------------------------------------------------ 1.6.0 in game (the user, 2026-11-14)

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
-- 1.6.0's note 6, then review round 4 (the user: the +Y-out-from-the-road set-up "must rotate"): the table's +Y along
-- the road on either side, TENT_OUT past the edge; the chair 0.9 m behind it on the far side from the road, facing the
-- road with its -X -- +Y along the road on the right, against it on the left; one group. Note 10: the table
-- ROADSIDE_MARSHAL_OUT (2.5 m) past the edge, the chair turned 180 on both sides (its +X to the road)
do
  local S = { V(0, 0), V(0, 600) }
  local function marshalAt(off)
    return ofKind(D.plan({ line = S, startM = 0, finishM = 600,
      marks = { { kind = 'marshal', along = 300, offLineM = off } } }), 'marshal')[1]
  end
  local m = marshalAt(5)
  local tbl, chr = m and find(m.objects, 'table')[1], m and find(m.objects, 'chair')[1]
  T.check(tbl and tbl.dy > 0.99 and chr and chr.dy < -0.99,
    'roadside marshal on the right: table +Y along the road (north), the chair turned round, +X to the road')
  T.check(D.ROADSIDE_MARSHAL_OUT == 2.5 and D.TENT_OUT == 1.5, 'roadside marshal 2.5 m past the edge; posts\' TENT_OUT kept')
  T.check(tbl and math.abs(tbl.eo - (3 + D.ROADSIDE_MARSHAL_OUT)) < 1e-6 and chr and
    math.abs(chr.eo - (3 + D.ROADSIDE_MARSHAL_OUT + 0.9)) < 1e-6 and tbl.eh == 3,
    'roadside marshal: props.lua\'s push data (eo) from the new offset')
  T.check(tbl and math.abs(tbl.x - (3 + D.ROADSIDE_MARSHAL_OUT)) < 1e-6 and chr and math.abs(chr.x - (tbl.x + 0.9)) < 1e-6 and
    math.abs(chr.y - tbl.y) < 1e-6, 'roadside marshal on the right: the table 2.5 m past the edge, the chair ' ..
    'behind it, away from the road')
  local flg = m and find(m.objects, 'flag')[1]
  T.check(flg and flg.dy > 0.99, 'roadside marshal: the flag along the road as before')
  local L = marshalAt(-5)
  local lt, lc = L and find(L.objects, 'table')[1], L and find(L.objects, 'chair')[1]
  T.check(lt and lt.dy > 0.99 and lc and lc.dy > 0.99 and math.abs(lt.x + (3 + D.ROADSIDE_MARSHAL_OUT)) < 1e-6 and
    math.abs(lc.x - (lt.x - 0.9)) < 1e-6, 'roadside marshal on the left: the table along the road, the chair behind ' ..
    'it on the far side, turned round to face the road (' .. tostring(lc and lc.dy) .. ', ' .. tostring(lc and lc.x) ..
    ')')
  -- (either side, the chair's +X -- rightOf(+Y) -- points at the road: towards the line, x = 0)
  local function facesRoad(c) return c and c.dy * (0 - c.x) > 0 end
  T.check(facesRoad(chr) and facesRoad(lc), 'roadside marshal: the chair faces the road on either side')
  local grouped = true
  for _, o in ipairs((m and m.objects or {})) do
    if o.grp ~= 'marshal' or not o.eo or not o.foot then grouped = false end
  end
  T.check(grouped, 'roadside marshal: one group, every object set from the edge with its reach (props.lua pushes it)')
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

-- 4. The direction boards 1 m beyond the road's edge; since 1.6.0's note 9 the radio / medical boards and their
-- warnings too (until then 0.3 m inside it, as props' control boards, which stay so)
do
  local long = { V(0, 0), V(0, 7000) }
  local r = ofKind(D.plan({ line = long, startM = 0, finishM = 7000, marks = { { kind = 'medical', along = 3000 } } }),
    'radio')
  local rb = r[1] and find(r[1].objects, 'radio')[1]
  local rw = r[1] and find(r[1].objects, 'radioWarn')[1]
  T.check(rb and math.abs(rb.x - 4) < 1e-6 and rw and math.abs(rw.x - 4) < 1e-6 and rb.eo == 4 and rb.eh == 3,
    'a radio board and its warning 1 m past the edge (' .. tostring(rb and rb.x) .. ')')
  local md = ofKind(D.plan({ line = long, startM = 0, finishM = 7000, mapKinds = { radio = true },
    marks = { { kind = 'medical', along = 3000 } } }), 'medical')[1]
  local mb, mw = md and find(md.objects, 'medical')[1], md and find(md.objects, 'medicalWarn')[1]
  T.check(mb and math.abs(mb.x - 4) < 1e-6 and mw and math.abs(mw.x - 4) < 1e-6, 'a medical board and its warning too')
  T.check(D.DIR_BOARD_OUT == 1.0 and D.BOARD_OUT == 1.0 and require('earthRally/props').BOARD_OUT_M == -0.3,
    'DIR_BOARD_OUT and BOARD_OUT 1 m; the control boards (props.BOARD_OUT_M) unchanged')
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
  -- (a side road 50 degrees off the stage: just past TAPE_PARALLEL_DEG, its tape square to it, at 40 degrees to the
  -- stage road, so its ends close on the stage as it grows)
  local f = tapeAt(50)
  T.check(f and type(f.maxLen) == 'number' and f.maxLen >= 8 - 1e-9, 'oblique, unknown width: the tape carries maxLen (' ..
    tostring(f and f.maxLen) .. ')')
  if f and f.maxLen then
    -- (the tape's middle and its way across, from its origin and heading; both ends at maxLen clear the stage road)
    local ax, ay, bx, by = ends(f)
    local cx, cy = (ax + bx) / 2, (ay + by) / 2
    local h = f.maxLen / 2
    local e1 = distTo(S, cx + f.dx * h, cy + f.dy * h) - D.HALF
    local e2 = distTo(S, cx - f.dx * h, cy - f.dy * h) - D.HALF
    T.check(e1 >= D.TAPE_CLEAR - 1e-6 and e2 >= D.TAPE_CLEAR - 1e-6, string.format(
      'oblique: at maxLen both ends still clear the stage road (%.2f, %.2f)', e1, e2))
    local g = f.maxLen / 2 + D.TAPE_GROW_STEP
    local n1 = math.min(distTo(S, cx + f.dx * g, cy + f.dy * g), distTo(S, cx - f.dx * g, cy - f.dy * g)) - D.HALF
    T.check(f.maxLen + D.TAPE_GROW_STEP > D.TAPE_LEN_MAX + 1e-9 or n1 < D.TAPE_CLEAR, 'oblique: and a step longer would not')
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

-- 3. Spectator tape and fence carry offRoad (props.lua drops one standing on a road it finds there); nothing else
-- does -- since 1.6.0's notes 6 / 7 the hay bales are pushed out from the road instead, as the posts are (review
-- round 4: the row together, one group)
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
    if o.offRoad and not (o.key == 'specTape' or o.key == 'fence') then wrong = wrong + 1 end
    if not o.offRoad and (o.key == 'specTape' or o.key == 'fence') then wrong = wrong + 1 end
    if o.key == 'bale' and not (o.eo and o.foot == D.FOOT.bale and o.grp == 'bales') then wrong = wrong + 1 end
    if (o.key == 'gazeboFrame' or o.key == 'chair' or o.key == 'tarp') and o.grp ~= 'camp' then wrong = wrong + 1 end
  end
  T.check(sp and (flagged.specTape or 0) > 0 and (flagged.fence or 0) > 0 and wrong == 0 and #find(sp.objects, 'bale') > 0,
    'spectators: tape and fence flagged offRoad; the bales one group, the camp another (' .. wrong .. ')')
  local b = sp and find(sp.objects, 'bale')[1]
  T.check(b and D.BALE_OFF - D.FOOT.bale >= 0.7 and b.eo == 3 + D.BALE_OFF,
    'bales: BALE_OFF past the edge, clear of it by their reach (' .. tostring(b and b.eo) .. ')')
end

------------------------------------------------------------------------------------------ 1.6.0: the organisers' points
-- The map's points first, per kind; the kinds it is silent about filled by chance, the chance seeded from the stage
-- (runner passes "<event>/<stage>"): the same stage dresses the same every run, two stages differ, all within bounds.
do
  -- the PRNG: its own, the same numbers for the same seed and stream, others for another
  local a, b, c = D.rng('ev/ss1', 'radio'), D.rng('ev/ss1', 'radio'), D.rng('ev/ss2', 'radio')
  local same, diff, inRange = true, false, true
  for _ = 1, 50 do
    local x, y, z = a(), b(), c()
    if x ~= y then same = false end
    if x ~= z then diff = true end
    if x < 0 or x >= 1 then inRange = false end
  end
  T.check(same and diff and inRange, 'rng: the same seed the same numbers, another seed others, in [0, 1)')
  math.randomseed(1)
  local r1 = D.rng('x', 'y')()
  math.randomseed(99)
  T.check(D.rng('x', 'y')() == r1, 'rng: not math.random\'s shared state')

  local function straight(km)
    local S = {}
    for k = 0, km * 10 do S[#S + 1] = V(0, k * 100) end
    return S
  end
  local S = straight(30)
  local js, corners = {}, {}
  for s = 250, 29750, 250 do
    js[#js + 1] = { along = s, x = 0, y = s, kind = 'turn', inDeg = 0, outDeg = 90,
                    sides = { { deg = 0, halfW = 3 }, { deg = 270, halfW = 3 } } }
  end
  for s = 100, 29500, 700 do
    corners[#corners + 1] = { from = s, to = s + 40, dir = 'right', angleDeg = 160, minRadius = 12 }
  end
  local function plan(seed, marks)
    return D.plan({ line = S, startM = 0, finishM = 30000, junctions = js, corners = corners, seed = seed,
                    marks = marks })
  end
  local function key(sites, kind)
    local out = {}
    for _, s in ipairs(ofKind(sites, kind)) do out[#out + 1] = string.format('%.0f', s.along) end
    return table.concat(out, ',')
  end
  local p1, p1b, p2 = plan('rally/ss1'), plan('rally/ss1'), plan('rally/ss2')
  local det = true
  for _, kind in ipairs({ 'radio', 'spectators', 'marshal' }) do if key(p1, kind) ~= key(p1b, kind) then det = false end end
  T.check(det, 'random fill: the same stage dresses the same every run')
  local differs = 0
  for _, kind in ipairs({ 'radio', 'spectators', 'marshal' }) do if key(p1, kind) ~= key(p2, kind) then differs = differs + 1 end end
  T.check(differs == 3, 'random fill: another stage, other radio / spectator / marshal places (' .. differs .. ' of 3)')

  -- within bounds, over many stages
  local okR, okS, okM, okMed, spread = true, true, true, true, {}
  for n = 1, 40 do
    local p = plan('rally/ss' .. n)
    local prev = 0
    for _, r in ipairs(ofKind(p, 'radio')) do
      local gap = r.along - prev
      if gap < 4000 - 300 or gap > 6000 + 300 or r.along > 29000 or r.source ~= 'rule' then okR = false end
      prev = r.along
    end
    if 30000 - 1000 - prev > 6000 + 300 then okR = false end      -- (no 6 km left without one)
    spread[string.format('%.0f', ofKind(p, 'radio')[1] and ofKind(p, 'radio')[1].along or -1)] = true
    local sp = ofKind(p, 'spectators')
    if #sp == 0 then okS = false end
    for i, s in ipairs(sp) do
      if s.along < 500 then okS = false end
      for k = i + 1, #sp do if math.abs(sp[k].along - s.along) < 4000 then okS = false end end
    end
    local ms = ofKind(p, 'marshal')
    table.sort(ms, function(x, y) return x.along < y.along end)
    if #ms == 0 then okM = false end
    for i = 2, #ms do if ms[i].along - ms[i - 1].along < 1000 then okM = false end end
    if #ofKind(p, 'medical') > 0 then okMed = false end
  end
  local nSpread = 0
  for _ in pairs(spread) do nSpread = nSpread + 1 end
  T.check(okR, 'random fill: radio every 4-6 km, none in the last 1 km, over 40 stages')
  T.check(nSpread >= 10, 'random fill: the first radio point not always in one place (' .. nSpread .. ' places)')
  T.check(okS, 'random fill: spectators at most one per 4 km, none in the first 500 m, over 40 stages')
  T.check(okM, 'random fill: junction marshals never two within 1 km, over 40 stages')
  T.check(okMed, 'random fill: never a medical point made up')

  -- the map's points per kind: a kind it marks is the map's alone, the others still by chance (and the same chance)
  local withMap = plan('rally/ss1', { { kind = 'spectator', along = 12000, offLineM = 30, name = 'Spec 1' } })
  T.check(#ofKind(withMap, 'spectators') == 1 and ofKind(withMap, 'spectators')[1].source == 'map',
    'map spectators: the map\'s only, none by chance')
  T.check(key(withMap, 'radio') == key(p1, 'radio') and key(withMap, 'marshal') == key(p1, 'marshal'),
    'map spectators: radio and marshals still by chance, the same as without it')
  local onlyMarshal = plan('rally/ss1', { { kind = 'marshal', along = 5000 } })
  local om = ofKind(onlyMarshal, 'marshal')
  T.check(#om == 1 and om[1].source == 'map' and key(onlyMarshal, 'spectators') == key(p1, 'spectators'),
    'map marshal: the map\'s only, spectators unchanged')

  -- "Gulf - Radio, Spectator": both kinds at one point -- a radio post and a spectator area there; a medical point
  -- 30 m on shares the radio post
  local gulf = plan('rally/ss1', {
    { kind = 'radio', along = 9000, offLineM = -20, name = 'Gulf - Radio, Spectator' },
    { kind = 'spectator', along = 9000, offLineM = -20, name = 'Gulf - Radio, Spectator' },
    { kind = 'medical', along = 9030, offLineM = 5, name = 'MIV 2' } })
  local gr, gs = ofKind(gulf, 'radio'), ofKind(gulf, 'spectators')
  T.check(#gr == 1 and gr[1].along == 9000 and gr[1].shared and #find(gr[1].objects, 'medical') == 1,
    'map radio + medical within 50 m: one shared post, the map\'s only radio')
  T.check(#gs == 1 and gs[1].along == 9000 and gs[1].source == 'map' and gs[1].name == 'Gulf - Radio, Spectator',
    'map spectator at the same point: its area there')
  local tp = gs[1] and find(gs[1].objects, 'specTape')[1]
  T.check(tp and tp.x < 0, 'map spectator left of the line (offLineM < 0): its tape on the left (' .. tostring(tp and tp.x) .. ')')
  T.check(#ofKind(gulf, 'medical') == 0, 'map medical sharing the radio post: no post of its own')

  -- (review round 3, 1.6.0's note 5, then review round 4) a kind whose every map point lies outside the stage's span
  -- is one no stage uses (events.markedKinds counts the same way): filled in by chance as with none; the junction
  -- marshals by rule all the same; medical never
  local outside = plan('rally/ss1', {
    { kind = 'radio', along = -500 }, { kind = 'spectator', along = 30500 }, { kind = 'marshal', along = -300 },
    { kind = 'medical', along = 31000 } })
  T.check(key(outside, 'radio') == key(p1, 'radio') and key(outside, 'spectators') == key(p1, 'spectators') and
    #ofKind(outside, 'radio') > 0, 'map radios / spectators all outside the stage: by chance, as with none')
  T.check(key(outside, 'marshal') == key(p1, 'marshal'), 'map marshals all outside the stage: the junction marshals as with none')
  T.check(#ofKind(outside, 'medical') == 0, 'a map medical point outside the stage: none, never one made up')

  -- 1.6.0's note 5: per kind, per rally. The rally's map marks radio points on another stage (mapKinds): none on this
  -- one; spectators it marks nowhere still by chance; the junction marshals at taped turns stay
  local elsewhere = D.plan({ line = S, startM = 0, finishM = 30000, junctions = js, corners = corners, seed = 'rally/ss1',
                             mapKinds = { radio = true, medical = true, spectator = false, marshal = true } })
  T.check(#ofKind(elsewhere, 'radio') == 0, 'rally marks radios elsewhere: none on this stage')
  T.check(key(elsewhere, 'spectators') == key(p1, 'spectators') and #ofKind(elsewhere, 'spectators') > 0,
    'rally marks no spectators anywhere: still by chance, the same as before')
  T.check(key(elsewhere, 'marshal') == key(p1, 'marshal') and #ofKind(elsewhere, 'marshal') > 0,
    'rally marks marshals elsewhere: the junction marshals at taped turns still go up')
  T.check(#ofKind(elsewhere, 'medical') == 0, 'and no medical point made up')
  local specElsewhere = D.plan({ line = S, startM = 0, finishM = 30000, junctions = js, corners = corners,
                                 seed = 'rally/ss1', mapKinds = { spectator = true } })
  T.check(#ofKind(specElsewhere, 'spectators') == 0 and key(specElsewhere, 'radio') == key(p1, 'radio'),
    'rally marks spectators elsewhere: none here; radio it marks nowhere still by chance')

  -- (review round 3) every turn that can have a marshal gets one, when none is within 1 km of another
  local sparse = {}
  for s = 1500, 28500, 1500 do
    sparse[#sparse + 1] = { along = s, x = 0, y = s, kind = 'turn', inDeg = 0, outDeg = 90,
                            sides = { { deg = 0, halfW = 3 }, { deg = 270, halfW = 3 } } }
  end
  local allOk = true
  for n = 1, 10 do
    local p = D.plan({ line = S, startM = 0, finishM = 30000, junctions = sparse, corners = corners,
                       seed = 'rally/ss' .. n })
    if #ofKind(p, 'marshal') ~= #sparse then allOk = false end
  end
  T.check(allOk, 'random fill: a marshal at every turn 1.5 km apart, on every stage (' .. #sparse .. ' turns)')
end

------------------------------------------------------------------------------------------ 1.6.0's notes 7 and 9: merging
-- Points of one kind within MERGE_M along the line (spectators and marshals: on one side) are one; a roadside marshal
-- post within MARSHAL_NEAR_POST_M of a radio / medical point is left out
do
  local S = { V(0, 0), V(0, 3000) }
  local function plan(marks, extra)
    local input = { line = S, startM = 0, finishM = 3000, marks = marks, mapKinds = { radio = true, spectator = true } }
    for k, v in pairs(extra or {}) do input[k] = v end
    return D.plan(input)
  end
  local function spec(along, off) return { kind = 'spectator', along = along, offLineM = off or 20, name = 'S' .. along } end
  T.check(D.MERGE_M == 100 and D.MARSHAL_NEAR_POST_M == 50, 'merging: 100 m of one kind, 50 m marshal to post')

  -- spectators: two points 60 m apart on one side, one area over both, its apex in the middle (Weaver Bend's pair)
  local two = ofKind(plan({ spec(1000), spec(1060) }), 'spectators')
  T.check(#two == 1 and math.abs(two[1].along - 1030) < 1e-6 and two[1].from <= 1000 - D.SPEC_POINT_M + 1e-6 and
    two[1].to >= 1060 + D.SPEC_POINT_M - 1e-6 and two[1].name == 'S1000',
    'spectators 60 m apart: one area from before the first to past the last, apex between (' .. #two .. ')')
  T.check(#find(two[1] and two[1].objects or {}, 'gazeboFrame') == 1, 'spectators merged: one gazebo')
  -- a chain within 100 m each (review round 4): stops growing at SPEC_SPAN_MAX_M first to last -- the first two one
  -- area, the third one of its own
  local chain = ofKind(plan({ spec(1000), spec(1090), spec(1180) }), 'spectators')
  T.check(#chain == 2 and math.abs(chain[1].along - 1045) < 1e-6 and math.abs(chain[2].along - 1180) < 1e-6,
    'spectators in a chain 90 m apart: the chain stops at SPEC_SPAN_MAX_M, a second area after (' .. #chain .. ')')
  T.check(#ofKind(plan({ spec(1000), spec(1250) }), 'spectators') == 2, 'spectators 250 m apart: two areas')
  T.check(#ofKind(plan({ spec(1000, 20), spec(1040, -20) }), 'spectators') == 2,
    'spectators 40 m apart on opposite sides: two areas')

  -- radio: two 80 m apart one post, at the first; 150 m apart two
  local r2 = ofKind(plan({ { kind = 'radio', along = 1000, name = 'R1' }, { kind = 'radio', along = 1080, name = 'R2' } }),
    'radio')
  T.check(#r2 == 1 and r2[1].along == 1000 and r2[1].name == 'R1', 'radio points 80 m apart: one post at the first')
  T.check(#ofKind(plan({ { kind = 'radio', along = 1000 }, { kind = 'radio', along = 1150 } }), 'radio') == 2,
    'radio points 150 m apart: two posts')
  -- medical alone: two 70 m apart one post at the first
  local m2 = ofKind(plan({ { kind = 'medical', along = 1500 }, { kind = 'medical', along = 1570 } }), 'medical')
  T.check(#m2 == 1 and m2[1].along == 1500, 'medical points 70 m apart: one post at the first')
  -- radio + medical: still one shared post within SHARE_M
  local sh = plan({ { kind = 'radio', along = 1000 }, { kind = 'medical', along = 1040 } })
  T.check(#ofKind(sh, 'radio') == 1 and ofKind(sh, 'radio')[1].shared and #ofKind(sh, 'medical') == 0,
    'radio + medical 40 m apart: one shared post, as before')

  -- marshals by the road: 50 m apart on one side one post at the first; on opposite sides two
  local function mar(along, off) return { kind = 'marshal', along = along, offLineM = off or 8 } end
  local mm = ofKind(plan({ mar(2000), mar(2050) }), 'marshal')
  T.check(#mm == 1 and mm[1].along == 2000, 'roadside marshals 50 m apart: one post at the first')
  T.check(#ofKind(plan({ mar(2000, 8), mar(2050, -8) }), 'marshal') == 2, 'roadside marshals on opposite sides: two')
  -- a roadside marshal within 50 m of a radio / medical point: left out; 80 m away: kept
  T.check(#ofKind(plan({ mar(1040), { kind = 'radio', along = 1000 } }), 'marshal') == 0,
    'a roadside marshal 40 m from a radio point: left out (the post has its table and chair)')
  T.check(#ofKind(plan({ mar(1530), { kind = 'medical', along = 1500 } }), 'marshal') == 0,
    'a roadside marshal 30 m from a medical point: left out')
  T.check(#ofKind(plan({ mar(1080), { kind = 'radio', along = 1000 } }), 'marshal') == 1,
    'a roadside marshal 80 m from a radio point: kept')
  -- the random radio points count too (the rally marks none anywhere: by chance)
  local rr = ofKind(D.plan({ line = { V(0, 0), V(0, 9000) }, startM = 0, finishM = 9000, seed = 'm' }), 'radio')
  local at = rr[1] and rr[1].along
  local nearRandom = at and D.plan({ line = { V(0, 0), V(0, 9000) }, startM = 0, finishM = 9000, seed = 'm',
    marks = { mar(at + 20) } })
  T.check(at and #ofKind(nearRandom, 'marshal') == 0, 'a roadside marshal 20 m from a random radio point: left out')

  -- merged() itself: the groups in order, each from its first to its last, sides apart
  local g = D._merged({ { along = 0 }, { along = 90, offLineM = -1 }, { along = 95 }, { along = 300 } },
    function(m) return (m.offLineM or 0) < 0 and -1 or 1 end)
  T.check(#g == 3 and g[1].first == 0 and g[1].last == 95 and g[1].n == 2 and g[2].side == -1 and g[3].along == 300,
    'merged: by side, within 100 m of the group\'s last point (' .. #g .. ')')

  -- review round 4. A radio post with a spectator area on its side (the right) within 50 m: its boards and flag, no
  -- gazebo, table or chair of its own; the area on the left, or 200 m off: the whole post
  local function tentOf(p)
    local r = ofKind(p, 'radio')[1]
    return r and #find(r.objects, 'gazeboFrame') + #find(r.objects, 'table') + #find(r.objects, 'chair'),
      r and #find(r.objects, 'radio'), r and #find(r.objects, 'flag')
  end
  local nt, nb, nf = tentOf(plan({ { kind = 'radio', along = 1000 }, spec(1060, 20) }))
  T.check(nt == 0 and nb == 1 and nf == 1, 'a radio post by a spectator area on its side: boards and flag, no tent (' ..
    tostring(nt) .. ')')
  T.check(tentOf(plan({ { kind = 'radio', along = 1000 }, spec(1060, -20) })) == 3,
    'the spectator area on the other side: the post\'s tent stays')
  T.check(tentOf(plan({ { kind = 'radio', along = 1000 }, spec(1300, 20) })) == 3,
    'the spectator area 200 m on: the post\'s tent stays')
  T.check(D.MERGE_GROUND_M == 50 and D.POST_NEAR_SPEC_M == 50, 'merging: 50 m on the ground, 50 m post to spectators')

  -- the map's marshals first to their turns, then the roadside ones merged: a mark 60 m before a turn and one by it --
  -- until now merged into the first, by the road, and the turn left with none -- are a roadside post and the turn's
  local turn = { { along = 2100, x = 0, y = 2100, kind = 'turn', inDeg = 0, outDeg = 90,
                   sides = { { deg = 0, halfW = 3 }, { deg = 270, halfW = 3 } } } }
  local mt = ofKind(plan({ mar(2040), mar(2110) }, { junctions = turn }), 'marshal')
  local mt1 = mt[1] and find(mt[1].objects, 'table')[1]
  T.check(#mt == 2 and mt[1].along == 2040 and mt[2].along == 2100 and mt1 and mt1.eo ~= nil,
    'a roadside marshal 60 m before a turn\'s: both stand, one by the road, the turn\'s behind its tape (' .. #mt .. ')')
  local m2t = ofKind(plan({ mar(2090), mar(2110) }, { junctions = turn }), 'marshal')
  T.check(#m2t == 1 and m2t[1].along == 2100, 'two map marshals by one turn: its one marshal (' .. #m2t .. ')')

  -- points right by each other on the ground, far apart along the line: a hairpin's two legs 20 m apart, the map's
  -- spectator points on its inside 250 m apart along -- one area
  local H = { V(0, 0), V(0, 1000) }
  for k = 1, 12 do local a = math.rad(k * 15) H[#H + 1] = V(15 - 15 * math.cos(a), 1000 + 15 * math.sin(a)) end
  H[#H + 1] = V(30, 0)
  local hcum = geo.cumulative(H)
  local leg2 = hcum[14] + 100                   -- (100 m down the second leg: y = 900)
  local hp = D.plan({ line = H, cum = hcum, startM = 0, finishM = hcum[#hcum], mapKinds = { spectator = true },
    marks = { { kind = 'spectator', along = 900, offLineM = 5 }, { kind = 'spectator', along = leg2, offLineM = 5 } } })
  T.check(#ofKind(hp, 'spectators') == 1, 'spectator points 20 m apart on the ground, 250 m along: one area (' ..
    #ofKind(hp, 'spectators') .. ')')
  local hm = D._merged({ { along = 900, offLineM = 5 }, { along = leg2, offLineM = 5 } })
  T.check(#hm == 2, 'merged: without their places, 250 m along is two')
end

------------------------------------------------------------------------------------------ 1.6.2, issue #9

-- Acute junctions (15 to 40 degrees between the side road and the stage road): the tape runs parallel with the stage
-- road, TAPE_CLEAR off its edge, its middle on the side road's centre line, long enough to reach TAPE_PAST beyond both
-- of the side road's edges along the stage's way; either side of the road, off the way on or the way back, known
-- width or not. Just past TAPE_PARALLEL_DEG a tape is square to its side road, as before.
do
  local S = { V(0, -300), V(0, 300) }
  local function tapeOf(deg, halfW)
    local t = ofKind(D.plan({ line = S, startM = 0, finishM = 600, junctions = { { along = 300, x = 0, y = 0,
      kind = 'straight', inDeg = 0, outDeg = 0, sides = { { deg = deg, halfW = halfW } } } } }), 'tape')[1]
    return t and t.objects or {}
  end
  -- (the whole run of tape a junction has: its two ends, from its one or two pieces, along the stage's way y)
  local function span(objs)
    local lo, hi, xs = math.huge, -math.huge, {}
    for _, o in ipairs(objs) do
      local ax, ay, bx, by = ends(o)
      lo, hi = math.min(lo, ay, by), math.max(hi, ay, by)
      xs[#xs + 1] = ax
      xs[#xs + 1] = bx
    end
    return lo, hi, xs
  end
  local worstClear, worstPar, worstCover, worstMid = math.huge, 0, math.huge, 0
  local n = 0
  for _, a in ipairs({ 15, 20, 25, 30, 35, 40 }) do
    -- (side roads off the way on to the right (bearing a) and left (360 - a), and off the way back (180 +- a))
    for _, deg in ipairs({ a, 360 - a, 180 - a, 180 + a }) do
      for _, hw in ipairs({ 3, 2, false }) do
        local objs = tapeOf(deg, hw or nil)
        local h = hw or D.HALF
        if #objs > 0 then
          n = n + 1
          local lo, hi, xs = span(objs)
          for _, o in ipairs(objs) do worstPar = math.max(worstPar, math.abs(o.dx)) end
          for _, x in ipairs(xs) do worstClear = math.min(worstClear, math.abs(x) - D.HALF) end
          -- (the side road's centre line x = y tan(a) (sign by side); its edges cross the tape's line h / sin a either
          -- side of where the centre does)
          local dx, dy = D._bearingToDir(deg)
          local x0 = xs[1]
          local yc = x0 * dy / dx
          local need = h / math.sin(math.rad(a)) + D.TAPE_PAST
          local cover = math.min(yc - lo, hi - yc) - need
          if (hi - lo) < D.TAPE_LEN_MAX - 1e-6 then worstCover = math.min(worstCover, cover) end
          worstMid = math.max(worstMid, math.abs((lo + hi) / 2 - yc))
        end
      end
    end
  end
  T.check(n == 6 * 4 * 3, 'acute: a tape at every one of 72 junctions, 15-40 degrees (' .. n .. ')')
  T.check(worstPar < 1e-6, string.format('acute: every tape parallel with the stage road (worst |dx| %.2g)', worstPar))
  T.check(worstClear >= D.TAPE_CLEAR - 1e-6 and worstClear <= D.TAPE_CLEAR + 0.5,
    string.format('acute: TAPE_CLEAR off the stage road\'s edge, no farther than a step more (%.2f)', worstClear))
  T.check(worstCover >= -1e-6, string.format('acute: past both edges of the side road by TAPE_PAST (%.2f)', worstCover))
  T.check(worstMid < 1e-6, string.format('acute: centred on the side road (%.2g)', worstMid))
  -- (at 15 degrees a 6 m road is 23.2 m wide along the stage: 24.7 m wanted, held to TAPE_LEN_MAX, two pieces)
  local lo, hi = span(tapeOf(15, 3))
  T.check(math.abs((hi - lo) - D.TAPE_LEN_MAX) < 1e-6 and #tapeOf(15, 3) == 2,
    string.format('acute: 15 degrees, a 6 m road: held to TAPE_LEN_MAX in two pieces (%.2f m)', hi - lo))
  -- (unknown width: one object refit at spawn, carrying the angle it crosses its side road at)
  local u = tapeOf(30)[1]
  T.check(u and u.refit and math.abs(u.refit.sin - 0.5) < 1e-6, 'acute: an unknown width\'s refit knows the angle (sin '
    .. tostring(u and u.refit and u.refit.sin) .. ')')
  -- just past TAPE_PARALLEL_DEG: square to the side road
  local sq = tapeOf(50, 3)[1]
  local sx, sy = D._bearingToDir(50)
  T.check(sq and math.abs(sq.dx * sx + sq.dy * sy) < 1e-6, 'acute: at 50 degrees still square to the side road')
  -- a square crossroads is untouched
  local cr = tapeOf(90, 3)[1]
  T.check(cr and math.abs(cr.dx) < 1e-6 and cr.key == 'tape8', 'acute: a side road square to the stage as before')
end

-- An acute side road off a bend that turns towards it: the tape still parallel with the stage road at the junction,
-- moved in until both ends clear the whole line by TAPE_CLEAR
do
  local S = { V(0, -200), V(0, 0) }
  for k = 1, 30 do
    local a = math.rad(k * 2)      -- (bending right, 2 degrees each 4 m)
    local p = S[#S]
    S[#S + 1] = V(p.x + 4 * math.sin(a), p.y + 4 * math.cos(a))
  end
  local t = ofKind(D.plan({ line = S, startM = 0, finishM = 300, junctions = { { along = 200, x = 0, y = 0,
    kind = 'straight', inDeg = 0, outDeg = 0, sides = { { deg = 25, halfW = 3 } } } } }), 'tape')[1]
  local ok, worst = t and #t.objects > 0, math.huge
  for _, o in ipairs(t and t.objects or {}) do
    local ax, ay, bx, by = ends(o)
    worst = math.min(worst, distTo(S, ax, ay) - D.HALF, distTo(S, bx, by) - D.HALF,
      distTo(S, (ax + bx) / 2, (ay + by) / 2) - D.HALF)
  end
  T.check(ok and worst >= D.TAPE_CLEAR - 1e-6, string.format('acute, on a bend towards it: ends and middle clear (%.2f)',
    worst))
end

-- A junction marshal behind a parallel tape (a side road 30 degrees off the way on, at a turn): farther along its
-- side road, MARSHAL_BEHIND square to the tape (at most twice that along it), on its far side from the stage
do
  local S = { V(0, -300), V(0, 0), V(300, 0) }
  local sites = D.plan({ line = S, startM = 0, finishM = 600, junctions = { { along = 300, x = 0, y = 0, kind = 'turn',
    inDeg = 0, outDeg = 90, sides = { { deg = 60, halfW = 3 } } } } })
  local tp = ofKind(sites, 'tape')[1]
  local m = ofKind(sites, 'marshal')[1]
  local tbl = m and find(m.objects, 'table')[1]
  T.check(tp and tp.objects[1] and math.abs(tp.objects[1].dy) < 1e-6, 'acute at a turn: the tape parallel with the way on')
  -- (the tape's line 4 m north of the way on; the marshal 30 degrees off it, 10 m farther along its side road: 5 m
  -- square to the tape, less MARSHAL_SIDE's share)
  T.check(tbl and tbl.y > 4 + D.MARSHAL_BEHIND - D.MARSHAL_SIDE and tbl.y - D.HALF > 1,
    'acute at a turn: the marshal behind the tape, clear of the stage (' .. tostring(tbl and tbl.y) .. ')')
end

T.done('test_dressing')
