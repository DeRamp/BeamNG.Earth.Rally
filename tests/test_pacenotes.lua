-- pacenotes.lua and the notes stageWriter.build makes of it: every call on a road drawn to have it, and none on a
-- road drawn not to.
local T = dofile(TESTS .. '/testlib.lua')
local geo = require('earthRally/geo')
local pn = require('earthRally/pacenotes')
local writer = require('earthRally/stageWriter')

-- A road from pieces, a point every metre: { 'straight', m } | { 'arc', radius, degrees (+ left) } |
-- { 'arcs', { { radius, degrees }... } } (one corner whose radius changes), with z = height(s) along it.
local function road(pieces, height)
  local pts, x, y, h, s = {}, 0, 0, math.pi / 2, 0
  height = height or function() return 0 end
  local function put() pts[#pts + 1] = { x = x, y = y, z = height(s) } end
  local function go(turn)
    h = h + turn
    x, y, s = x + math.cos(h), y + math.sin(h), s + 1
    put()
  end
  put()
  for _, p in ipairs(pieces) do
    if p[1] == 'straight' then
      for _ = 1, p[2] do go(0) end
    else
      local parts = p[1] == 'arc' and { { p[2], p[3] } } or p[2]
      for _, a in ipairs(parts) do
        local len = math.floor(math.abs(math.rad(a[2])) * a[1] + 0.5)
        for _ = 1, len do go(math.rad(a[2]) / len) end
      end
    end
  end
  return pts
end

local qf = function() return 0, 0, 0, 1 end
local function build(line, landmarks)
  local cum = geo.cumulative(line)
  return writer.build(line, { startM = 0, finishM = cum[#cum], quatFn = qf, landmarks = landmarks })
end
-- each note as "slot:type" pieces, the corner with its descriptor / shape: "1:caution2,4:corner/hairpin,5:finish"
local function notes(built)
  local out = {}
  for _, p in ipairs(built.notebook.pacenotes) do
    local it, parts = p.structured.items, {}
    for k = 1, 6 do
      local x = it[tostring(k)]
      if x.type then
        local w = x.type
        if x.type == 'caution' then w = 'caution' .. x.level end
        if x.type == 'corner' then
          w = 'corner' .. (x.descriptor and ('/' .. x.descriptor) or '') .. (x.shape and ('/' .. x.shape) or '')
        end
        parts[#parts + 1] = k .. ':' .. w
      end
    end
    out[#out + 1] = table.concat(parts, ',')
  end
  return out
end
local function has(list, pattern)
  for _, s in ipairs(list) do if s:find(pattern) then return true end end
  return false
end
local function show(list) return table.concat(list, ' | ') end

------------------------------------------------------------------------------------------ the speed model
do
  local k = {}
  for i = 1, 200 do k[i] = 0 end
  for i = 120, 130 do k[i] = 1 / 20 end
  local v = pn.speeds(k, 5)
  T.check(v[1] == 0, 'a stage starts from standing')
  T.near(v[125], math.sqrt(pn.A_LAT_MS2 * 20), 1e-6, 'through a corner: as fast as the grip allows')
  T.check(v[100] > v[118] and v[118] > v[125], 'braking before it')
  T.check(v[60] <= pn.V_MAX_MS and v[60] > 30, 'flat out on the straight before it (' .. v[60] .. ')')
end

------------------------------------------------------------------------------------------ descriptors
do
  local hp = notes(build(road({ { 'straight', 300 }, { 'arc', 10, 180 }, { 'straight', 300 } })))
  T.check(has(hp, '4:corner/hairpin') or has(hp, '4:corner/tightHairpin'), 'a 180 of 10 m: a hairpin (' .. show(hp) .. ')')
  local op = notes(build(road({ { 'straight', 300 }, { 'arc', 24, -170 }, { 'straight', 300 } })))
  T.check(has(op, '4:corner') and not has(op, 'airpin'), 'a 170 of 24 m: no hairpin, the game numbers it and gives ' ..
    'its length (' .. show(op) .. ')')
  local sq = notes(build(road({ { 'straight', 300 }, { 'arc', 9, 90 }, { 'straight', 300 } })))
  T.check(has(sq, '4:corner/square'), 'a 90 of 9 m: square (' .. show(sq) .. ')')
  local plain = notes(build(road({ { 'straight', 300 }, { 'arc', 60, 90 }, { 'straight', 300 } })))
  T.check(has(plain, '4:corner') and not has(plain, '4:corner/'), 'a 90 of 60 m: a plain corner, the game numbers it (' ..
    show(plain) .. ')')
end

------------------------------------------------------------------------------------------ shapes
do
  -- (within a grade: one corner, its shape says the change; two grades or more apart it is two, "four into two")
  local tl = notes(build(road({ { 'straight', 300 }, { 'arcs', { { 120, 40 }, { 60, 50 } } }, { 'straight', 300 } })))
  T.check(has(tl, '4:corner/tightens'), 'radius 120 then 60: tightens (' .. show(tl) .. ')')
  local op = notes(build(road({ { 'straight', 300 }, { 'arcs', { { 60, -50 }, { 120, -40 } } }, { 'straight', 300 } })))
  T.check(has(op, '4:corner/opens'), 'radius 60 then 120: opens (' .. show(op) .. ')')
  local t2 = build(road({ { 'straight', 300 }, { 'arcs', { { 90, 50 }, { 30, 50 } } }, { 'straight', 300 } }))
  T.check(t2.corners == 2, 'radius 90 then 30: two corners, "four into two" (' .. show(notes(t2)) .. ')')
  local built = build(road({ { 'straight', 300 }, { 'arcs', { { 90, 50 }, { 30, 50 } } }, { 'straight', 300 } }))
  local mt
  for _, p in ipairs(built.notebook.pacenotes) do
    local c = p.structured.items['4']
    if c.type == 'corner' and c.shape then mt = c.measurementType end
  end
  T.check(mt == nil, 'a corner that tightens is measured in one piece, as the game\'s own stages do (' ..
    tostring(mt) .. ')')
  local even = notes(build(road({ { 'straight', 300 }, { 'arc', 50, 100 }, { 'straight', 300 } })))
  T.check(not has(even, '4:corner/'), 'one radius all the way: no shape (' .. show(even) .. ')')
end

------------------------------------------------------------------------------------------ chicanes and twisty runs
do
  local ch = build(road({ { 'straight', 300 }, { 'arc', 20, 60 }, { 'straight', 5 }, { 'arc', 20, -60 },
                          { 'straight', 300 } }))
  local cn = notes(ch)
  T.check(has(cn, '^2:chicaneLeftEntry$'), 'a left then a right, tight and close: "chicane left entry", one note (' ..
    show(cn) .. ')')
  T.check(ch.corners == 1, 'a chicane counts as one corner note (' .. ch.corners .. ')')
  -- (the same chicane as a map draws it: a point every 7 m in its corners, one edge along each straight, rounded
  --  to 1 cm -- the fitted curvature reads it a little more open, and it is still one chicane)
  local full = road({ { 'straight', 300 }, { 'arc', 20, 60 }, { 'straight', 5 }, { 'arc', 20, -60 }, { 'straight', 300 } })
  local mapped = { full[1] }
  for i = 300, #full - 300, 7 do mapped[#mapped + 1] = { x = math.floor(full[i].x * 100 + 0.5) / 100,
                                                        y = math.floor(full[i].y * 100 + 0.5) / 100, z = 0 } end
  mapped[#mapped + 1] = full[#full]
  local mcn = notes(build(geo.resample(mapped, 4)))
  T.check(has(mcn, '^2:chicaneLeftEntry$'), 'a map-drawn chicane: still one chicane (' .. show(mcn) .. ')')
  local sw = {}
  sw[#sw + 1] = { 'straight', 300 }
  for k = 1, 6 do
    sw[#sw + 1] = { 'arc', 90, (k % 2 == 0) and 35 or -35 }
    sw[#sw + 1] = { 'straight', 15 }
  end
  sw[#sw + 1] = { 'straight', 300 }
  local tw = build(road(sw))
  local tn = notes(tw)
  T.check(tn[1] == '4:corner,5:twisty' and tw.corners == 6, 'six fast flicks: "twisty" on the first, every one still ' ..
    'called (' .. show(tn) .. ')')
  local twCasual = notes(writer.build(road(sw), { startM = 0, finishM = 1e9, quatFn = qf, speaks = { finish = true } }))
  T.check(twCasual[1] == '4:corner' and #twCasual == 7, 'a voice with no "twisty": the corners all the same (' ..
    show(twCasual) .. ')')
  local apart = notes(build(road({ { 'straight', 300 }, { 'arc', 20, 60 }, { 'straight', 120 }, { 'arc', 20, -60 },
                                   { 'straight', 300 } })))
  T.check(not has(apart, 'chicane'), 'the same two corners 120 m apart: two corners (' .. show(apart) .. ')')
end

------------------------------------------------------------------------------------------ cautions
do
  local fast = notes(build(road({ { 'straight', 1000 }, { 'arc', 12, 90 }, { 'straight', 300 } })))
  T.check(has(fast, '1:caution[23]'), 'a 12 m right angle after a kilometre flat out: caution (' .. show(fast) .. ')')
  local slow = notes(build(road({ { 'straight', 300 }, { 'arc', 15, 120 }, { 'straight', 40 }, { 'arc', 15, -120 },
                                  { 'straight', 300 } })))
  local second = slow[#slow - 1]
  T.check(not second:find('caution'), 'a slow corner straight after another slow one: no caution (' .. show(slow) .. ')')
  -- 1.6.2, issue #11: a corner half the top speed at the end of a long straight is a care; the same corner after a
  -- short one is not (a hairpin first, so both approaches start from the same slow corner)
  local function after(straightM)
    return notes(build(road({ { 'straight', 200 }, { 'arc', 12, 150 }, { 'straight', straightM }, { 'arc', 45, 50 },
                              { 'straight', 300 } })))
  end
  local long, short = after(800), after(150)
  T.check(long[2] and long[2]:find('^1:caution1,4:corner'), 'a 45 m radius bend after 800 m flat out: a care (' ..
    show(long) .. ')')
  T.check(short[2] and not short[2]:find('caution'), 'the same bend after 150 m: no caution (' .. show(short) .. ')')
  local tight = notes(build(road({ { 'straight', 200 }, { 'arc', 12, 150 }, { 'straight', 800 }, { 'arc', 25, 50 },
                                   { 'straight', 300 } })))
  T.check(tight[2] and tight[2]:find('^1:caution2'), 'a 25 m radius bend after 800 m flat out: a caution (' ..
    show(tight) .. ')')
  -- (review: the straight runs back to the last corner called tighter than a six -- a six taken flat on the way
  --  does not start it again; a four does)
  local function via(radius)
    return notes(build(road({ { 'straight', 200 }, { 'arc', 12, 150 }, { 'straight', 250 }, { 'arc', radius, 30 },
                              { 'straight', 200 }, { 'arc', 45, 50 }, { 'straight', 300 } })))
  end
  local viaSix, viaFour = via(150), via(50)
  T.check(#viaSix == 4 and viaSix[3]:find('^1:caution1,4:corner'), 'a six 250 m into a 530 m straight: the bend ' ..
    'after it still a care (' .. show(viaSix) .. ')')
  T.check(#viaFour == 4 and not viaFour[3]:find('caution'), 'a four there: the straight starts again, no care (' ..
    show(viaFour) .. ')')
end

------------------------------------------------------------------------------------------ the height profile
-- (a hump: up h over len/2 and down again, a smooth bump centred at s0)
local function hump(s0, len, h)
  return function(s)
    local d = math.abs(s - s0)
    if d >= len / 2 then return 0 end
    return h * (0.5 + 0.5 * math.cos(math.pi * d / (len / 2)))
  end
end
do
  local cr = notes(build(road({ { 'straight', 1200 } }, hump(600, 100, 4))))
  T.check(has(cr, '^2:crest$') or has(cr, '^2:bigCrest$'), 'a 4 m hump over 100 m on a straight: a crest (' ..
    show(cr) .. ')')
  local jp = notes(build(road({ { 'straight', 1200 } }, hump(600, 30, 2))))
  T.check(has(jp, '^2:jump$') or has(jp, '^2:bigJump$'), 'a 2 m hump over 30 m, flat out: a jump (' .. show(jp) .. ')')
  local slowJ = notes(build(road({ { 'straight', 300 }, { 'arc', 10, 180 }, { 'straight', 20 } , { 'arc', 10, -180 },
                                   { 'straight', 400 } }, hump(400, 30, 0.6))))
  T.check(not has(slowJ, 'ump'), 'a low hump between two hairpins, slow: no jump (' .. show(slowJ) .. ')')
  local dp = notes(build(road({ { 'straight', 1200 } }, function(s) return -hump(600, 80, 4)(s) end)))
  T.check(has(dp, '^2:dip$') or has(dp, '^2:badDip$'), 'a 4 m hollow over 80 m: a dip (' .. show(dp) .. ')')
  local flat = notes(build(road({ { 'straight', 1200 } })))
  T.check(show(flat) == '2:finish', 'a flat straight: the finish only (' .. show(flat) .. ')')
  local none = road({ { 'straight', 1200 } }, hump(600, 30, 2))
  for _, p in ipairs(none) do p.z = nil end
  T.check(show(notes(build(none))) == '2:finish', 'a line with no heights: nothing read off them')
  -- a crest in a corner is its shape; one just before it comes before the corner
  local oc = notes(build(road({ { 'straight', 500 }, { 'arc', 60, 90 }, { 'straight', 500 } }, hump(547, 60, 2))))
  T.check(has(oc, '4:corner/overCrest'), 'a crest in the middle of a corner: "over crest" (' .. show(oc) .. ')')
  local bc = notes(build(road({ { 'straight', 500 }, { 'arc', 60, 90 }, { 'straight', 500 } }, hump(470, 50, 1.5))))
  T.check(has(bc, '2:crest,4:corner') or has(bc, '2:smallCrest,4:corner') or has(bc, '2:bigCrest,4:corner') or
          has(bc, '2:brakeOverCrest'),
    'a crest just before a corner: called before it (' .. show(bc) .. ')')
  -- a crest 50 m before a corner that it hides: one breath, "crest three left" (2026-11-19: it was "crest 40",
  -- then the corner); one 150 m before a corner the road climbs to in plain sight is a call of its own
  local hid = build(road({ { 'straight', 520 }, { 'arc', 40, 80 }, { 'straight', 400 } }, hump(470, 120, 3)))
  local hn = notes(hid)
  local function crestOrJump(x) return x:find('[Cc]rest') or x:find('[Jj]ump') end
  T.check(#hn == 2 and crestOrJump(hn[1]) and hn[1]:find('4:corner'), 'a corner 50 m behind a crest that hides ' ..
    'it: the crest and the corner in one note (' .. show(hn) .. ')')
  local far = notes(build(road({ { 'straight', 620 }, { 'arc', 40, 80 }, { 'straight', 400 } }, hump(470, 120, 3))))
  T.check(#far == 3 and crestOrJump(far[1]) and not far[1]:find('corner'), 'a crest 150 m before a corner: ' ..
    'a note of its own (' .. show(far) .. ')')
  local zs = {}
  for i = 1, 100 do zs[i] = hump(250, 60, 3)((i - 1) * 5) end
  local ht = pn.hiddenAfter(zs, 5, 51)
  T.check(ht and ht > 51 and ht <= 51 + pn.HIDDEN_AHEAD_M / 5, 'hiddenAfter: the road past a 3 m crest out of sight (' ..
    tostring(ht) .. ')')
  local flatZ = {}
  for i = 1, 100 do flatZ[i] = 0 end
  T.check(pn.hiddenAfter(flatZ, 5, 51) == nil, 'hiddenAfter: nothing hidden on flat road')
  -- up and down: a long steep hill after a corner
  local hill = notes(build(road({ { 'straight', 400 }, { 'arc', 60, 60 }, { 'straight', 600 } }, function(s)
    return s > 470 and (s - 470) * 0.12 or 0 end)))
  T.check(has(hill, '5:up') or has(hill, '6:up'), 'a 12 % climb starting after a corner: "up" (' .. show(hill) .. ')')
end

------------------------------------------------------------------------------------------ the slots
do
  -- more calls before a corner than its two slots: the jump and the crest beat the side road
  local line = road({ { 'straight', 600 }, { 'arc', 60, 90 }, { 'straight', 500 } }, hump(565, 30, 2))
  local cum = geo.cumulative(line)
  local b = build(line, { { s = 578, type = 'atJunction' }, { s = 586, type = 'pastJunction' } })
  local ns = notes(b)
  local hit
  for _, s in ipairs(ns) do if s:find('4:corner') then hit = s end end
  T.check(hit and (hit:find('jump') or hit:find('Jump')) and not hit:find('pastJunction'),
    'a jump, a turning and a side road before a corner: the jump and the turning are called, the side road is not (' ..
    tostring(hit) .. ')')
  local n2 = 0
  for _ in (hit or ''):gmatch('[23]:') do n2 = n2 + 1 end
  T.check(n2 <= 2, 'at most two calls before the corner')
  -- the finish on the last corner when it is close; no "to stop" (the co-driver is off past the finish)
  local fin = build(road({ { 'straight', 400 }, { 'arc', 60, 90 }, { 'straight', 80 } }))
  local fn = notes(fin)
  T.check(fn[#fn]:find('4:corner') and fn[#fn]:find('finish') and not show(fn):find('toStop'),
    'a corner just before the finish: "... over finish", and nothing after it (' .. show(fn) .. ')')
  -- (a keep call inside that corner goes before it, and the finish still goes on the corner: the note ending last)
  local fk = notes(build(road({ { 'straight', 400 }, { 'arc', 60, 120 }, { 'straight', 60 } }),
                         { { s = 440, type = 'keepLeft' } }))
  T.check(#fk == 1 and fk[1]:find('2:keepLeft') and fk[1]:find('4:corner') and fk[1]:find('finish'),
    'a fork inside the last corner: "keep left", the corner, "over finish", one note (' .. show(fk) .. ')')
  -- keep left on a crest
  local kc = notes(build(road({ { 'straight', 1200 } }, hump(600, 100, 4)), { { s = 600, type = 'keepLeft' } }))
  T.check(has(kc, '^2:keepLeftOverCrest$'), 'a fork on a crest: "keep left over crest", one call (' .. show(kc) .. ')')
  -- narrows: a landmark like a junction
  local nr = notes(build(road({ { 'straight', 1200 } }), { { s = 600, type = 'narrows' } }))
  T.check(has(nr, '^5:narrows$'), 'a narrowing on a straight: a note of its own (' .. show(nr) .. ')')
  -- the reviews' cases (2026-11-14)
  -- a hollow is a dip, and its two rims are not crests
  local hollow = notes(build(road({ { 'straight', 1200 } }, function(x) return -hump(600, 80, 4)(x) end)))
  T.check(not has(hollow, 'rest'), 'a 4 m hollow: no crests at its rims (' .. show(hollow) .. ')')
  -- heights no road has (a 6 m step in 5 m): nothing read there
  local cliff = notes(build(road({ { 'straight', 1200 } }, function(x) return x > 600 and -6 or 0 end)))
  T.check(show(cliff) == '2:finish', 'a 6 m step in the heights: no jump, no crest, no dip (' .. show(cliff) .. ')')
  -- a crest inside a chicane is "over crest", not "into crest"
  local cc = notes(build(road({ { 'straight', 300 }, { 'arc', 20, 60 }, { 'straight', 5 }, { 'arc', 20, -60 },
                               { 'straight', 300 } }, hump(326, 40, 1.5))))
  T.check(not has(cc, 'intoCrest'), 'a crest in a chicane: not "into crest" (' .. show(cc) .. ')')
  -- one jump call per note, however many humps it has
  local two = notes(build(road({ { 'straight', 600 }, { 'arc', 60, 60 }, { 'straight', 500 } },
    function(x) return hump(570, 30, 2)(x) + hump(675, 30, 2)(x) end)))
  local dup = false
  for _, n in ipairs(two) do
    local c = 0
    for _ in n:gmatch('[Jj]ump') do c = c + 1 end
    if c > 1 then dup = true end
  end
  T.check(not dup, 'a jump before a corner and one after it: one jump call on the note (' .. show(two) .. ')')
  -- a voice that cannot say a call: left out, and a note with nothing to say not written
  local casual = { finish = true, crest = true, overJump = true }
  local dc = notes(writer.build(road({ { 'straight', 1200 } }, function(x) return -hump(600, 60, 4)(x) end),
                                { startM = 0, finishM = 1200, quatFn = qf, speaks = casual }))
  T.check(show(dc) == '2:finish', 'a dip, for a voice with no "dip": no note at all (' .. show(dc) .. ')')
  -- a stage that starts on a climb still says "up" after its first corner
  local climb = notes(build(road({ { 'straight', 100 }, { 'arc', 60, 60 }, { 'straight', 600 } }, function(x)
    return x * 0.12 end)))
  T.check(has(climb, 'up'), 'a stage that starts on a 12 % climb: "up" after the corner (' .. show(climb) .. ')')
  -- the second reviews' cases (2026-11-14)
  -- a hump at a bridge is the valley under it: no jump, the bridge called
  local br = notes(build(road({ { 'straight', 1200 } }, hump(600, 30, 2)), { { s = 610, type = 'overBridge' } }))
  T.check(has(br, 'overBridge') and not has(br, '[Jj]ump') and not has(br, 'rest'),
    'a hump at a bridge: "over bridge", no jump or crest (' .. show(br) .. ')')
  -- ... the whole of a long bridge, start to far end
  local lb = notes(build(road({ { 'straight', 1400 } }, hump(800, 30, 2)),
    { { s = 600, sEnd = 900, type = 'overBridge' } }))
  T.check(has(lb, 'overBridge') and not has(lb, '[Jj]ump'), 'a hump 200 m into a 300 m bridge: no jump (' ..
    show(lb) .. ')')
  -- ... nor inside a corner: not its shape, not its caution
  local brc = notes(build(road({ { 'straight', 600 }, { 'arcs', { { 120, 40 }, { 60, 50 } } }, { 'straight', 400 } },
    hump(690, 40, 1.5)), { { s = 690, type = 'overBridge' } }))
  T.check(has(brc, '4:corner/tightens,') and not has(brc, 'Crest') and not has(brc, 'caution2'),
    'a hump at a bridge inside a tightening corner: "tightens", no crest, no caution (' .. show(brc) .. ')')
  -- a corner that tightens, for a voice that cannot say "tightens", on a fast approach: a care
  local ttc = notes(writer.build(road({ { 'straight', 500 }, { 'arcs', { { 120, 40 }, { 60, 50 } } },
    { 'straight', 400 } }), { startM = 0, finishM = 1e9, quatFn = qf, speaks = { finish = true } }))
  T.check(has(ttc, '1:caution1,4:corner$'), 'a fast tightening corner, a voice with no shapes: a care (' ..
    show(ttc) .. ')')
  -- the user's test drive (2026-11-14): a long crest the grade change over 20 m is too short to see is blind, so
  -- called (from the sightline); and a long sweeper too open for a corner is one
  local longCrest = notes(build(road({ { 'straight', 1500 } }, hump(750, 240, 6))))
  local nCrest = 0
  for _, n in ipairs(longCrest) do for _ in n:gmatch('rest') do nCrest = nCrest + 1 end end
  T.check(nCrest == 1, 'a 6 m crest over 240 m, flat out: one crest (' .. show(longCrest) .. ')')
  local gentle = notes(build(road({ { 'straight', 1500 } }, hump(750, 600, 3))))
  T.check(not has(gentle, 'rest'), 'a 3 m rise over 600 m: not blind, no crest (' .. show(gentle) .. ')')
  local sweep = build(road({ { 'straight', 400 }, { 'arc', 500, 50 }, { 'straight', 400 } }))
  local sw = notes(sweep)
  T.check(has(sw, '4:corner') and sweep.corners == 1, 'a 50 degree sweeper at 500 m radius: a corner (' ..
    show(sw) .. ')')
  local wobble = build(road({ { 'straight', 400 }, { 'arc', 900, 10 }, { 'straight', 400 } }))
  -- (the owner's rule, 2026-11-19: every bend the driver can see is called, whatever its radius)
  T.check(wobble.corners == 1, 'a 10 degree bend at 900 m: a corner (' .. show(notes(wobble)) .. ')')
  -- (the second review of it: one call for one long top; a crest too weak for a call of its own is called once it
  --  is blind; a sweeper is not the corner before for the next one's caution)
  local function summit(g, s0, len)
    return function(s)
      if s < s0 then return g * s end
      local d = math.min(s - s0, len)
      local z = g * s0 + g * d - g / len * d * d
      return z - g * math.max(0, s - s0 - len)
    end
  end
  local top = notes(build(road({ { 'straight', 1600 } }, summit(0.15, 650, 150))))
  local nTop = 0
  for _, n in ipairs(top) do for _ in n:gmatch('rest') do nTop = nTop + 1 end end
  T.check(nTop == 1, '+15 % to -15 % over a 150 m top: one crest (' .. show(top) .. ')')
  -- (the second drive: crests from the sight, not the grade -- a steep climb easing off, or a descent getting
  --  steeper, that the driver sees right over, is none)
  local function ease(g1, g2, s0, len)
    return function(s)
      if s < s0 then return g1 * s end
      local d = math.min(s - s0, len)
      return g1 * s0 + g1 * d + (g2 - g1) / (2 * len) * d * d + g2 * math.max(0, s - s0 - len)
    end
  end
  local easing = notes(build(road({ { 'straight', 1600 } }, ease(0.14, 0.06, 700, 60))))
  T.check(not has(easing, 'rest'), 'a 14 % climb easing to 6 % over 60 m, the road still in sight: no crest (' ..
    show(easing) .. ')')
  -- (the review of it: the same climb easing off with heights a little rough is still none; a hollow the road
  --  comes back out of in view is none; a blind top with a dip after it too weak to call is still a crest)
  local seed = 12345
  local function rough(f)
    local nz = {}
    return function(s)
      local k = math.floor(s)
      if not nz[k] then seed = (seed * 1103515245 + 12345) % 2147483648; nz[k] = (seed / 2147483648 - 0.5) * 0.4 end
      return f(s) + nz[k]
    end
  end
  local roughEase = notes(build(road({ { 'straight', 1600 } }, rough(ease(0.12, 0.03, 700, 30)))))
  T.check(not has(roughEase, 'rest'), 'a 12 % climb easing to 3 %, heights rough by 0.2 m: no crest (' ..
    show(roughEase) .. ')')
  local hollow = notes(build(road({ { 'straight', 1600 } }, hump(800, 40, -1.5))))
  T.check(not has(hollow, 'rest'), 'a 1.5 m hollow in a level road: no crest at its rim (' .. show(hollow) .. ')')
  local s2, h2 = summit(0.12, 650, 100), hump(735, 40, -2.5)
  local topDip = notes(build(road({ { 'straight', 1600 } }, function(s) return s2(s) + h2(s) end)))
  T.check(has(topDip, 'rest') or has(topDip, 'ump'), 'a blind top with a dip after it: still called (' ..
    show(topDip) .. ')')
  local steep30 = notes(build(road({ { 'straight', 1600 } }, ease(-0.06, -0.14, 700, 30))))
  T.check(not has(steep30, 'rest'), 'a descent from 6 % to 14 % over 30 m, the road below in sight: no crest (' ..
    show(steep30) .. ')')
  local brow = notes(build(road({ { 'straight', 1600 } }, ease(0, -0.12, 700, 30))))
  T.check(has(brow, '2:down') or has(brow, 'bigCrest'),
    'a level road dropping away to 12 % over 30 m: called, "down" (the third drive) or a big crest (' ..
    show(brow) .. ')')
  -- (the review of those: a sharp drop-off on a descent is still a crest; a rounded top levelling out where the road
  --  is hidden is one too)
  local drop = notes(build(road({ { 'straight', 1600 } }, ease(-0.05, -0.17, 700, 30))))
  T.check(has(drop, 'rest') or has(drop, 'ump'), 'a descent from 5 % dropping to 17 % over 30 m: called (' ..
    show(drop) .. ')')
  local plateau = notes(build(road({ { 'straight', 1600 } }, ease(0.2, -0.02, 700, 50))))
  T.check(has(plateau, 'rest') or has(plateau, 'ump'), 'a 20 % climb rounding over to level: called (' ..
    show(plateau) .. ')')
  -- (the third drive: a downhill from flat road is "down", not a crest -- on a straight and in a corner -- and a
  --  voice with no "down" hears the crest; a climb over the top into the same descent is still a crest)
  local flatDown = build(road({ { 'straight', 1600 } }, ease(0, -0.10, 700, 40)))
  local fd = notes(flatDown)
  T.check(has(fd, 'down') and not has(fd, 'rest'), 'flat road into a 10 % downhill: "down", no crest (' ..
    show(fd) .. ')')
  local fdc = notes(build(road({ { 'straight', 600 }, { 'arc', 150, 40 }, { 'straight', 1000 } },
    ease(0, -0.10, 700, 40))))
  T.check(has(fdc, 'down') and not has(fdc, 'rest'), 'flat road into a downhill in a corner: "down", no crest (' ..
    show(fdc) .. ')')
  local fdLine = road({ { 'straight', 1600 } }, ease(0, -0.10, 700, 40))
  local fdCas = notes(writer.build(fdLine, { startM = 0, finishM = 1e9, quatFn = qf, speaks = { finish = true, crest = true, smallCrest = true, bigCrest = true, overCrest = true, intoCrest = true } }))
  T.check(not has(fdCas, 'down') and has(fdCas, 'rest'), 'the same, a voice with no "down": the crest (' ..
    show(fdCas) .. ')')
  -- (its review: a corner that tightens over such a top keeps the caution it had over a crest, and says the
  --  descent once)
  local tdLine = road({ { 'straight', 650 }, { 'curve', { { 120, 25 }, { 40, 45 } } }, { 'straight', 900 } },
    ease(0, -0.10, 690, 40))
  local tdc = notes(build(tdLine))
  local nDown = 0
  for _, n in ipairs(tdc) do for _ in n:gmatch('[Dd]own') do nDown = nDown + 1 end end
  T.check(not has(tdc, 'rest') and nDown == 1, 'a corner tightening over the top of a downhill from flat: "down" ' ..
    'once, no crest (' .. show(tdc) .. ')')
  T.check(has(tdc, 'caution[123]') and has(tdc, 'tightens'), 'and a caution as over a crest (' .. show(tdc) .. ')')
  local upDown = notes(build(road({ { 'straight', 1600 } }, ease(0.10, -0.10, 700, 80))))
  T.check(has(upDown, 'rest') or has(upDown, 'ump'), 'a 10 % climb over the top into a 10 % downhill: a crest (' ..
    show(upDown) .. ')')
  local steeper = notes(build(road({ { 'straight', 1600 } }, ease(-0.04, -0.10, 700, 60))))
  T.check(not has(steeper, 'rest'), 'a descent from 4 % to 10 % over 60 m, the road still in sight: no crest (' ..
    show(steeper) .. ')')
  local s1, h1 = summit(0.10, 700, 200), hump(800, 40, 0.5)
  local weak = notes(build(road({ { 'straight', 2000 } }, function(s) return s1(s) + h1(s) end)))
  T.check(has(weak, 'rest'), 'a blind top with a small bump on it: a crest (' .. show(weak) .. ')')
  local afterSw = notes(build(road({ { 'straight', 600 }, { 'arc', 400, -40 }, { 'straight', 60 }, { 'arc', 15, 90 },
                                    { 'straight', 400 } })))
  T.check(has(afterSw, '^1:caution[23],4:corner/square'), 'a square after a sweeper: its caution as after a straight (' ..
    show(afterSw) .. ')')
  -- a casual voice says no corner shape: a crest inside a corner is "over crest" after it, not a silent shape
  local casualSet = { finish = true, crest = true, overJump = true, overCrest = true, intoCrest = true,
                      bigCrest = true, smallCrest = true, brakeOverCrest = true, keepLeftOverCrest = true,
                      keepRightOverCrest = true, jump = true, bigJump = true, chicaneLeftEntry = true,
                      chicaneRightEntry = true, ['descriptor:hairpin'] = true }
  local ocLine = road({ { 'straight', 500 }, { 'arc', 60, 90 }, { 'straight', 500 } }, hump(547, 60, 2))
  local occ = notes(writer.build(ocLine, { startM = 0, finishM = 1e9, quatFn = qf, speaks = casualSet }))
  T.check(has(occ, '4:corner,5:overCrest') and not has(occ, 'corner/'),
    'a crest inside a corner, casual voice: "over crest" after the corner, no shape (' .. show(occ) .. ')')
  -- a dip given way to a stronger crest leaves no crest at its far rim
  do
    local function bump(s0, len, h) return hump(s0, len, h) end
    local A, B = bump(600, 40, 3), bump(645, 50, 2)
    local pts, vv = {}, {}
    for i = 1, 240 do local s = (i - 1) * 5 pts[i] = { x = 0, y = s, z = A(s) - B(s) } vv[i] = 20 end
    local ev = pn.heights(pts, 5, vv)
    local rim = false
    for _, e in ipairs(ev) do if e.kind == 'crest' and (e.i - 1) * 5 > 640 then rim = true end end
    T.check(#ev == 1 and not rim, 'a crest, a weaker hollow just after it: the crest alone, not the hollow\'s rim (' ..
      #ev .. ' events)')
  end
  -- (the review of the sight's crests: a blind top with a dip after it too weak to be called on its own, at 25 m/s:
  --  the crest is not given way to that dip, or nothing would be said)
  do
    local g, s0, len = 0.12, 650, 100
    local B = hump(735, 40, -2.5)
    local pts, vv = {}, {}
    for i = 1, 320 do
      local s = (i - 1) * 5
      local d = math.min(math.max(0, s - s0), len)
      local z = (s < s0 and g * s or g * s0 + g * d - g / len * d * d - g * math.max(0, s - s0 - len)) + B(s)
      pts[i] = { x = 0, y = s, z = z }
      vv[i] = 25
    end
    local ev, crest, loneDip = pn.heights(pts, 5, vv), false, false
    for _, e in ipairs(ev) do
      if e.kind == 'crest' then crest = true end
      if e.kind == 'dip' and e.alone then loneDip = true end
    end
    T.check(crest or loneDip, 'a blind top, a dip too weak to call after it: the crest kept (' .. #ev .. ' events)')
  end
  -- a sharp hump a road can have (3.5 m over 30 m, 37 % at its steepest) is a jump, not bad heights
  local kick = notes(build(road({ { 'straight', 1200 } }, hump(600, 30, 3.5))))
  T.check(has(kick, '[Jj]ump'), 'a 3.5 m hump over 30 m, flat out: a jump (' .. show(kick) .. ')')
  -- a fork on a second crest inside a corner that says its own crest: "keep left", one crest call on the note
  local kk = notes(build(road({ { 'straight', 500 }, { 'arc', 90, 150 }, { 'straight', 400 } },
    function(x) return hump(540, 50, 2)(x) + hump(620, 50, 2)(x) end), { { s = 620, type = 'keepLeft' } }))
  local crests = 0
  for _, n in ipairs(kk) do if n:find('4:corner') then for _ in n:gmatch('Crest') do crests = crests + 1 end end end
  T.check(has(kk, '2:keepLeft,') and crests == 1,
    'a fork on a crest in a corner over a crest: "keep left", "over crest" once (' .. show(kk) .. ')')
  -- a voice with no chicane call hears the chicane's two corners
  local chLine = road({ { 'straight', 300 }, { 'arc', 20, 60 }, { 'straight', 5 }, { 'arc', 20, -60 },
                        { 'straight', 300 } })
  local chNo = writer.build(chLine, { startM = 0, finishM = 1e9, quatFn = qf, speaks = { finish = true } })
  local cn2 = notes(chNo)
  local corners2 = 0
  for _, n in ipairs(cn2) do if n:find('4:corner') then corners2 = corners2 + 1 end end
  T.check(corners2 == 2 and not has(cn2, 'chicane'), 'a chicane, a voice with no chicane call: two corners (' ..
    show(cn2) .. ')')
  -- a corner that only tightens, on a fast approach: its shape says it, no caution for that alone (200 m: under
  -- LONG_STRAIGHT_M, where a corner this much slower than the top speed is a care, below)
  local tt = notes(build(road({ { 'straight', 200 }, { 'arcs', { { 120, 40 }, { 60, 50 } } }, { 'straight', 400 } })))
  T.check(has(tt, 'tightens') and not has(tt, 'caution'), 'a fast corner that tightens: "tightens", no caution (' ..
    show(tt) .. ')')
  -- rallyAdapter.speaks: the style's modifiers, aliases, shapes and descriptors; and the voice settings untouched
  do
    local ra = require('earthRally/rallyAdapter')
    local seenOpts
    package.loaded[ra.VOICEPACK] = { resolveEffectiveEntry = function(_, _, o)
      seenOpts = o
      return 'x', { compositorStyle = 'english/casualtest' }, {} end }
    package.loaded[ra.STYLES .. 'english/casualtest'] = { componentTypes = {
      corner = { descriptors = { hairpin = {} }, descriptorAliases = { tightHairpin = 'hairpin' } },
      modifiers = { crest = {} }, modifierAliases = { overCrest = 'crest' } } }
    local sp, style = ra.speaks()
    T.check(style == 'english/casualtest' and sp.crest and sp.overCrest and sp['descriptor:tightHairpin'] and
            not sp['shape:overCrest'], 'speaks: modifiers, aliases and descriptors; no shape for a style with none')
    T.check(seenOpts and seenOpts.writeSettings == false, 'speaks: the voice pack asked not to write settings')
    package.loaded[ra.STYLES .. 'english/shapetest'] = { componentTypes = {
      corner = { shapes = { overCrest = {} } }, modifiers = {} } }
    package.loaded[ra.VOICEPACK] = { resolveEffectiveEntry = function()
      return 'x', { compositorStyle = 'english/shapetest' }, {} end }
    local sp2 = ra.speaks()
    T.check(sp2 and sp2['shape:overCrest'], 'speaks: a style\'s corner shapes')
    package.loaded[ra.VOICEPACK] = nil
  end
  -- every call written is one the game's english style knows
  local mods = {
    crest = 1, bigCrest = 1, smallCrest = 1, intoCrest = 1, jump = 1, bigJump = 1, overJump = 1, dip = 1, badDip = 1,
    throughDip = 1, up = 1, down = 1, brakeOverCrest = 1, keepLeft = 1, keepRight = 1, keepLeftOverCrest = 1,
    keepRightOverCrest = 1, atJunction = 1, pastJunction = 1, overBridge = 1, narrows = 1, finish = 1,
    chicaneLeftEntry = 1, chicaneRightEntry = 1, twisty = 1,
  }
  local shapes = { opens = 1, tightens = 1, opensAndTightens = 1, overCrest = 1, opensOverCrest = 1,
                   tightensOverCrest = 1, tightensDown = 1 }
  local descs = { hairpin = 1, openHairpin = 1, tightHairpin = 1, square = 1 }
  local known = true
  for _, built in ipairs({ b, fin, tw }) do
    for _, p in ipairs(built.notebook.pacenotes) do
      for k = 1, 6 do
        local x = p.structured.items[tostring(k)]
        if x.type and x.type ~= 'caution' and x.type ~= 'corner' and not mods[x.type] then known = false end
        if x.type == 'corner' and ((x.shape and not shapes[x.shape]) or (x.descriptor and not descs[x.descriptor])) then
          known = false
        end
      end
    end
  end
  T.check(known, 'only the game\'s own calls')
end

------------------------------------------------------------------------------------------ 1.6.2: open and short corners
do
  local function cornerItems(built)
    local out = {}
    for _, p in ipairs(built.notebook.pacenotes) do
      local c = p.structured.items['4']
      if c.type == 'corner' then out[#out + 1] = { item = c, meta = p.metadata.earthRally } end
    end
    return out
  end
  -- issue #6: an open six (22 degrees at 200 m: too open for geo.corners, too short a turn for a 30 degree sweeper)
  local six = build(road({ { 'straight', 500 }, { 'arc', 200, 22 }, { 'straight', 500 } }))
  T.check(six.corners == 1, 'a 22 degree bend at 200 m: a corner note, a six (' .. show(notes(six)) .. ')')
  local wide = build(road({ { 'straight', 500 }, { 'arc', 600, 22 }, { 'straight', 500 } }))
  -- (the owner's rule, 2026-11-19: every bend the driver can see is called, smooth or drawn as kinks)
  local wideItems = cornerItems(wide)
  T.check(wide.corners == 1 and wideItems[1] and wideItems[1].meta.sweeper, 'a 22 degree bend at 600 m: a sweeper (' ..
    show(notes(wide)) .. ')')
  -- a bend as a map draws it: straight pieces of 120 m meeting at three kinks of 11 degrees (33 in all): one
  -- sweeper, from half an edge before the first kink to half an edge past the last (the road bends round each
  -- point: geo.curvature's fit); 20 and 15 degrees in three kinks over 400 m too; kinks either way, each one a bend
  -- the driver sees, are each called (the owner's rule)
  local function kinks(deg, nodes, length)
    local pieces = { { 'straight', 300 } }
    local piece = length / (nodes + 1)
    for k = 1, nodes do
      pieces[#pieces + 1] = { 'straight', math.floor(piece) }
      pieces[#pieces + 1] = { 'arc', 3 / math.rad(math.abs(deg / nodes)), deg / nodes }
    end
    pieces[#pieces + 1] = { 'straight', 300 + math.floor(piece) }
    return road(pieces)
  end
  local function sweeperNotes(b)
    local n = 0
    for _, c in ipairs(cornerItems(b)) do if c.meta.sweeper then n = n + 1 end end
    return n
  end
  local k36 = build(kinks(-33, 3, 480))
  local k36i = cornerItems(k36)
  T.check(#k36i == 1 and k36i[1].meta.sweeper and k36i[1].meta.dir == 'right' and
    math.abs(k36i[1].meta.angleDeg - 33) < 3, 'a map-drawn bend, 33 degrees in kinks 120 m apart: one sweeper (' ..
    show(notes(k36)) .. ')')
  local k36n = k36.notebook.pacenotes
  local w0, w1 = k36n[1].pacenoteWaypoints[1].pos, k36n[1].pacenoteWaypoints[2].pos
  T.near(math.sqrt((w1[1] - w0[1]) ^ 2 + (w1[2] - w0[2]) ^ 2), 360, 25, 'the sweeper runs round its kinks')
  T.check(sweeperNotes(build(kinks(20, 3, 400))) == 1, 'a map-drawn bend, 20 degrees in three kinks over 400 m: one')
  T.check(sweeperNotes(build(kinks(15, 3, 400))) == 1, '15 degrees over 400 m: one')
  local function kink(deg) return { 'arc', 3 / math.rad(math.abs(deg)), deg } end
  local wig = build(road({ { 'straight', 300 }, kink(8), { 'straight', 100 }, kink(-7), { 'straight', 100 },
                           kink(8), { 'straight', 100 }, kink(-7), { 'straight', 300 } }))
  T.check(#cornerItems(wig) == 4, 'kinks of 7 - 8 degrees either way: each called (' .. show(notes(wig)) .. ')')
  local far = build(road({ { 'straight', 300 }, kink(10), { 'straight', 400 }, kink(10), { 'straight', 300 } }))
  T.check(#cornerItems(far) == 2, 'two kinks of 10 degrees 400 m apart: two calls (' ..
    show(notes(far)) .. ')')
  -- ... and a long bend with a tighter corner in it: the bend either side is called too, not just its tight middle
  local lb = build(road({ { 'straight', 400 }, { 'arcs', { { 300, 40 }, { 40, 60 }, { 300, 40 } } },
                         { 'straight', 400 } }))
  local ci = cornerItems(lb)
  local sweepers, core = 0, nil
  for _, c in ipairs(ci) do
    if c.meta.sweeper then sweepers = sweepers + 1 elseif c.meta.minRadius < 60 then core = c end
  end
  T.check(#ci == 3 and sweepers == 2 and core, 'a long bend with a tight middle: in, the middle, out -- three notes (' ..
    show(notes(lb)) .. ')')
  local seq = true
  for k = 2, #ci do if ci[k].meta.dir ~= ci[1].meta.dir then seq = false end end
  T.check(seq, '(all three the same way)')
  -- issue #7: a crest on such a bend goes on its corner, not on a note of its own
  local crestBend = notes(build(road({ { 'straight', 500 }, { 'arc', 200, 22 }, { 'straight', 500 } },
                                     hump(540, 120, 4))))
  local alone = false
  for _, n in ipairs(crestBend) do if n:find('rest') and not n:find('4:corner') then alone = true end end
  T.check(has(crestBend, 'rest') and not alone, 'a crest on an open six: on the corner\'s note (' .. show(crestBend) .. ')')
  -- (the pacenote rebuild, 2026-11-20) the grade is the road's own -- its radius where tightest, pacenotes.fitRadius
  -- -- and the note carries the step (riskIntensity) that makes the game's circle say it: a short kink, which the
  -- circle through its ends reads tighter than it is, is stepped one more open; a corner the circle reads right is not
  for _, case in ipairs({ { 60, 20 }, { 60, 90 }, { 15, 60 }, { 200, 40 }, { 30, 120 } }) do
    local it = cornerItems(build(road({ { 'straight', 300 }, { 'arc', case[1], case[2] }, { 'straight', 300 } })))
    local m = it[1] and it[1].meta
    local said = m and m.circleR and pn.gradeOf(2 * m.circleR) - (it[1].item.riskIntensity or 0)
    T.check(#it == 1 and m.grade and said and (said == m.grade or math.abs(said - m.grade) == 1 and
      it[1].item.riskIntensity ~= nil), string.format('%d degrees at %d m: the game says our grade, %s (circle %s, step %s)',
      case[2], case[1], tostring(m and m.grade), tostring(said), tostring(it[1] and it[1].item.riskIntensity)))
  end
  -- (the casual voices step their own hard / medium / easy ladder, by index: the step is worked out on that one)
  local function bucket(d) return d < 65 and 1 or (d < 190 and 2 or 3) end
  local function want(G) return bucket(pn.GRADE_MID_D[G]) end
  local okAll, seen = true, 0
  for _, case in ipairs({ { 60, 20 }, { 60, 90 }, { 15, 60 }, { 200, 40 }, { 30, 120 }, { 100, 60 }, { 45, 80 } }) do
    local line = road({ { 'straight', 300 }, { 'arc', case[1], case[2] }, { 'straight', 300 } })
    local cum = geo.cumulative(line)
    local b = writer.build(line, { startM = 0, finishM = cum[#cum], quatFn = qf, ladder = { 65, 190 } })
    for _, p in ipairs(b.notebook.pacenotes) do
      local m, it = p.metadata.earthRally, p.structured.items['4']
      if m and m.circleR and it and it.type == 'corner' and not it.descriptor then
        seen = seen + 1
        local said = math.max(1, math.min(3, bucket(2 * m.circleR) - (it.riskIntensity or 0)))
        if said ~= want(m.grade) then okAll = false end
      end
    end
  end
  T.check(okAll and seen >= 5, 'casual ladder: each corner said in the casual grade of ours (' .. seen .. ')')
  -- (two fours of one direction 40 m apart: one corner, still a four -- the straight between does not open it)
  local two4 = cornerItems(build(road({ { 'straight', 300 }, { 'arc', 70, 40 }, { 'straight', 40 }, { 'arc', 70, 40 },
                                       { 'straight', 300 } })))
  T.check(#two4 == 1 and two4[1].meta.grade == pn.fitGrade(70), 'two fours 40 m apart: one corner, a four (' ..
    #two4 .. ', grade ' .. tostring(two4[1] and two4[1].meta.grade) .. ' vs ' .. pn.fitGrade(70) .. ')')
  T.check(pn.fitGrade(30) < pn.fitGrade(60) and pn.fitGrade(60) < pn.fitGrade(200) and pn.fitGrade(math.huge) == #pn.GRADE_FIT_DIAMETERS + 1,
    'fitGrade: tighter is a lower number, a straight a six or more open')
  -- (the grade the game measures: the circle through the waypoints and the middle, on its one to six ladder)
  local ring = geo.resample(road({ { 'straight', 50 }, { 'arc', 100, 60 }, { 'straight', 50 } }), 5)
  local rc = geo.corners(ring, 5)[1]
  T.check(rc and pn.measuredGrade(rc, ring) == 5, 'measuredGrade: a 100 m radius is a five (' ..
    tostring(rc and pn.measuredGrade(rc, ring)) .. ')')
end

------------------------------------------------------------------------------------------ issue #47: on to the stop
do
  -- a stage: a corner, the finish at 600 m; then on past it a corner and the stop control at the line's end
  local line = road({ { 'straight', 300 }, { 'arc', 60, 90 }, { 'straight', 306 }, { 'arc', 40, -90 },
                      { 'straight', 300 } })
  local cum = geo.cumulative(line)
  local finishM = 600
  local plain = writer.build(line, { startM = 0, finishM = finishM, quatFn = qf })
  local pn0 = notes(plain)
  T.check(pn0[#pn0]:find('finish') and plain.corners == 1, 'no stop control: notes end at the finish (' ..
    show(pn0) .. ')')
  local stop = line[#line]
  local b = writer.build(line, { startM = 0, finishM = finishM, quatFn = qf, stop = { x = stop.x, y = stop.y } })
  local ns = notes(b)
  local fi
  for k, s in ipairs(ns) do if s:find('finish') then fi = k end end
  T.check(fi and fi < #ns and ns[#ns]:find('4:corner'), 'a stop control: the corner past the finish called after ' ..
    '"finish" (' .. show(ns) .. ')')
  T.check(b.corners == 1 and b.cornersAfterFinish == 1, 'the stage counts its own corner; the one past it apart')
  T.near(b.lengthM, plain.lengthM, 1e-6, 'the stage length stays start to finish')
  T.near(b.driveline.stats.raceDistanceKms, plain.driveline.stats.raceDistanceKms, 1e-9,
    'the race distance stays start to finish')
  local pns = b.race.pathnodes
  local fp = geo.pointAt(line, cum, finishM)
  T.check(#pns == #plain.race.pathnodes and math.abs(pns[#pns].pos[1] - fp.x) < 1e-6 and
    math.abs(pns[#pns].pos[2] - fp.y) < 1e-6, 'the last pathnode stays on the finish')
  -- (each note's corner waypoints in order: the game plays them along the route in the notebook's order)
  local okO, prev = true, -1
  for _, p in ipairs(b.notebook.pacenotes) do
    local w = p.pacenoteWaypoints[1].pos
    local _, _, s = geo.locate(line, cum, { x = w[1], y = w[2] })
    if s < prev - 1e-6 then okO = false end
    prev = s
  end
  T.check(okO, 'the notes in order along the line, the finish among them')
  -- a stop right by the finish: nothing past it
  local fp2 = geo.pointAt(line, cum, finishM + 10)
  local near = notes(writer.build(line, { startM = 0, finishM = finishM, quatFn = qf, stop = { x = fp2.x, y = fp2.y } }))
  T.check(show(near) == show(pn0), 'a stop just past the finish: the notes as without one')
end

------------------------------------------------------------------------------------------ the opening distance
do
  -- the game's textCompositor:distanceToString, english rules
  local ds = writer.distanceString
  T.check(ds(83) == '80' and ds(86) == '90' and ds(124) == '100' and ds(594) == '600' and ds(976) == '1 km' and
          ds(1000) == '1 km' and ds(1100) == '1 km' and ds(1260) == '1 point 2 5 km' and ds(1400) == '1 point 5 km',
          'distanceString: 10 m, 50 m, then km in quarters with "point" (' .. ds(83) .. ', ' .. ds(594) .. ', ' ..
          ds(976) .. ', ' .. ds(1260) .. ')')
  T.check(ds(130, { units = { base = 'm', large = 'km', point = 'point' }, rounding = { small = 5, medium = 25,
          mediumThreshold = 100, large = 500, largeThreshold = 1000 } }) == '125', 'distanceString: a style\'s own rules')
  -- the first corner 600 m from the line: its distance first; 50 m: none
  local far = build(road({ { 'straight', 600 }, { 'arc', 60, 60 }, { 'straight', 250 } }))
  local str, m = writer.openingCall(far)
  T.check(str == '600' and m and math.abs(m - 600) < 30, 'openingCall: a first corner 600 m in (' .. tostring(str) ..
    ', ' .. tostring(m) .. ')')
  local close = build(road({ { 'straight', 50 }, { 'arc', 60, 60 }, { 'straight', 250 } }))
  T.check(writer.openingCall(close) == nil, 'openingCall: none for a first corner 50 m in (' ..
    tostring(close.openingM) .. ')')
  T.check(writer.openingCall({ openingM = 1300 }) == '1 point 2 5 km', 'openingCall: in km past 1000 m')
  T.check(writer.openingCall({ openingM = 2600 }) == nil, 'openingCall: none past the style max, 2 km (no clip for it)')
  -- a stage that starts in a hairpin: called from just past the clear stretch, not left out; one over by then is
  local hp = build(road({ { 'straight', 5 }, { 'arc', 15, 170 }, { 'straight', 400 } }))
  local hpn = notes(hp)
  T.check(hp.corners == 1 and hpn[1]:find('4:corner') and writer.openingCall(hp) == nil,
    'a hairpin off the start line: called first, with no opening distance (' .. show(hpn) .. ')')
  local kink = build(road({ { 'straight', 3 }, { 'arc', 20, 40 }, { 'straight', 400 } }))
  T.check(kink.corners == 0, 'a kink over within the clear stretch off the line: none (' .. show(notes(kink)) .. ')')

  -- rallyAdapter: put on the loaded notebook's first note after the game's autofill, again on a resync and at GO,
  -- the note compiled again; left alone where the author blocked it or the voice says no distances
  local ra = require('earthRally/rallyAdapter')
  local function fakeNote()
    local n = { before = '', compiled = 0, cleared = 0 }
    function n:getNoteFieldBefore() return self.before end
    function n:setNoteFieldBefore(v, meters) self.before, self.beforeM = v, meters end
    function n:clearCachedFgData() self.cleared = self.cleared + 1 end
    function n:asCompiled() self.compiled = self.compiled + 1 end
    return n
  end
  local first, second = fakeNote(), fakeNote()
  local callsOn = true
  local comp = { distanceCallsEnabled = function() return callsOn end,
                 getConfig = function() return { distance = writer.DISTANCE_RULES } end }
  local rm = { notebook = { pacenotes = { sorted = { first, second } },
                            getTextCompositor = function() return comp end },
               resyncAfterTeleport = function() end, setPacenoteProcessingEnabled = function() end }
  local savedRally = rawget(_G, 'gameplay_rally')
  local savedLog = rawget(_G, 'log')
  _G.log = _G.log or function() end
  _G.gameplay_rally = { getRallyManager = function() return rm end }
  T.check(ra.setOpening(612) and first.before == '600' and first.beforeM == 612 and first.compiled == 1 and
          first.cleared == 1 and second.before == '', 'rallyAdapter: the first note opens with its distance, compiled again')
  ra.resync()
  T.check(first.compiled == 1, 'rallyAdapter: a resync with the distance still there leaves it')
  first.before = ''   -- (the engine's autofill ran again: a voice pack change)
  ra.resync()
  T.check(first.before == '600' and first.compiled == 2, 'rallyAdapter: set again on a resync after an autofill')
  first.before = ''
  ra.notesOn(true)
  T.check(first.before == '600', 'rallyAdapter: set again at GO')
  first.before = '#'
  ra.resync()
  T.check(first.before == '#', 'rallyAdapter: a blocked field is left alone')
  first.before = ''
  callsOn = false
  ra.resync()
  T.check(first.before == '', 'rallyAdapter: a voice with no distance calls gets none')
  callsOn = true
  ra.setOpening(50)
  T.check(first.before == '', 'rallyAdapter: none for a first corner in sight of the line')
  ra.setOpening(nil)
  -- (step 6 of the rebuild: each corner's measurement read back from the engine, graded as we graded the circle)
  local function graded(circleR, diameter)
    return { metadata = { earthRally = { circleR = circleR, grade = 3 } },
             structuredForProjection = function() return { items = { ['4'] = { type = 'corner', intensity = diameter } } } end }
  end
  local notesList = {}
  for k = 1, 6 do notesList[k] = graded(50, 100) end      -- (a 100 m diameter, a three, both ways)
  notesList[7] = { metadata = { earthRally = { landmark = true } } }
  rm.notebook.pacenotes.sorted = notesList
  local gc = ra.gradeCheck()
  T.check(gc and gc.checked == 6 and gc.same == 6 and not gc.mismatch, 'gradeCheck: the game measures our corners ' ..
    'as we did')
  for k = 1, 4 do notesList[k] = graded(50, 200) end      -- (measured a five)
  gc = ra.gradeCheck()
  T.check(gc and gc.same == 2 and gc.mismatch, 'gradeCheck: measured differently: a mismatch')
  T.check(#gc.far == 4 and gc.far[1][2] == 3 and gc.far[1][3] == 5, 'gradeCheck: the corners two grades out listed')
  for k = 1, 6 do notesList[k] = graded(50, nil) end
  gc = ra.gradeCheck()
  T.check(gc and gc.checked == 0 and not gc.mismatch, 'gradeCheck: nothing measured, nothing said')
  _G.gameplay_rally = savedRally
  _G.log = savedLog
end

T.done('test_pacenotes')
