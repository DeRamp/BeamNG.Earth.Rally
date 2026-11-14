-- dressing.lua: the mock-up's scenes (docs/mockups-1.4.0/stage.html) put through the Lua, and the automatic fill along
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
-- a tape's two ends: the origin, and its length back along -Y
local function ends(o)
  local L = D.LINEAR_M[o.key]
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
    T.check(o.key == 'tape6' and o.shape:find('s_tape_road_closure_6m', 1, true), 'crossroads: 6 m tape for a 6 m road')
    if cy > 4 then north = { cx, cy, ax, ay, bx, by } else west = { cx, cy, ax, ay, bx, by } end
  end
  T.check(north and math.abs(north[1]) < 1e-6 and math.abs(north[2] - 8) < 1e-6, 'crossroads: tape 8 m up the road straight on')
  T.check(west and math.abs(west[1] + 8) < 1e-6 and math.abs(west[2]) < 1e-6, 'crossroads: tape 8 m into the left road')
  -- square to its road: the north tape runs east-west
  T.check(north and math.abs(north[4] - north[6]) < 1e-6 and math.abs(math.abs(north[3] - north[5]) - 6) < 1e-6,
    'crossroads: tape square across its road')
  local board = ofKind(sites, 'board')[1]
  local b = board and board.objects[1]
  T.check(b and b.key == 'dirRight', 'crossroads: s_corner_dir_right')
  T.check(b and math.abs(b.y + 75) < 1e-6 and math.abs(b.x - 2.7) < 1e-6, 'crossroads: board 75 m before, on the right')
  -- its face (-X of the model) towards the car: +X (the right of +Y) along the way in
  T.check(b and math.abs(b.dy) < 1e-6 and b.dx < -0.99, 'crossroads: board turned to face the car (+X along the road)')
  local m = ofKind(sites, 'marshal')[1]
  T.check(m and #m.objects == 3, 'crossroads: a junction marshal (table, chair, flag)')
  local tbl = m and find(m.objects, 'table')[1]
  T.check(tbl and math.abs(tbl.x + 13) < 1e-6 and math.abs(tbl.y - 1.5) < 1e-6,
    'crossroads: marshal on the LEFT road, 5 m behind its tape, 1.5 m off its centre')
  T.check(tbl and tbl.dx > 0.99, 'crossroads: marshal facing back to the junction')
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
  T.check(b and math.abs(b.objects[1].x + 2.7) < 1e-6 and math.abs(b.objects[1].y + 75) < 1e-6,
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
  T.check(o and o.key == 'tape6', 'straight on: a 5 m road takes the 6 m tape')
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
  for _, s in ipairs(ofKind(sites, 'tape')) do for _, o in ipairs(s.objects) do if o.key == 'tape8' then w8 = w8 + 1 end end end
  T.check(w8 == #js, 'auto: an 8 m road takes the 8 m tape')
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

T.done('test_dressing')
