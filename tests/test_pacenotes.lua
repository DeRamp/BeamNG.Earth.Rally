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
  T.check(has(op, '4:corner/openHairpin'), 'a 170 of 24 m: an open hairpin (' .. show(op) .. ')')
  local sq = notes(build(road({ { 'straight', 300 }, { 'arc', 9, 90 }, { 'straight', 300 } })))
  T.check(has(sq, '4:corner/square'), 'a 90 of 9 m: square (' .. show(sq) .. ')')
  local plain = notes(build(road({ { 'straight', 300 }, { 'arc', 60, 90 }, { 'straight', 300 } })))
  T.check(has(plain, '4:corner') and not has(plain, '4:corner/'), 'a 90 of 60 m: a plain corner, the game numbers it (' ..
    show(plain) .. ')')
end

------------------------------------------------------------------------------------------ shapes
do
  local tl = notes(build(road({ { 'straight', 300 }, { 'arcs', { { 90, 50 }, { 30, 50 } } }, { 'straight', 300 } })))
  T.check(has(tl, '4:corner/tightens'), 'radius 90 then 30: tightens (' .. show(tl) .. ')')
  local op = notes(build(road({ { 'straight', 300 }, { 'arcs', { { 30, -50 }, { 90, -50 } } }, { 'straight', 300 } })))
  T.check(has(op, '4:corner/opens'), 'radius 30 then 90: opens (' .. show(op) .. ')')
  local built = build(road({ { 'straight', 300 }, { 'arcs', { { 90, 50 }, { 30, 50 } } }, { 'straight', 300 } }))
  local mt
  for _, p in ipairs(built.notebook.pacenotes) do
    local c = p.structured.items['4']
    if c.type == 'corner' and c.shape then mt = c.measurementType end
  end
  T.check(mt == 'split2', 'a corner that tightens is measured in two parts, so its number is its entry (' ..
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
  local sw = {}
  sw[#sw + 1] = { 'straight', 300 }
  for k = 1, 6 do
    sw[#sw + 1] = { 'arc', 90, (k % 2 == 0) and 35 or -35 }
    sw[#sw + 1] = { 'straight', 15 }
  end
  sw[#sw + 1] = { 'straight', 300 }
  local tw = build(road(sw))
  local tn = notes(tw)
  T.check(has(tn, '^2:twisty$') and tw.corners == 1, 'six fast flicks: "twisty", one note for them (' .. show(tn) .. ')')
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
  local second = slow[#slow - 2]
  T.check(not second:find('caution'), 'a slow corner straight after another slow one: no caution (' .. show(slow) .. ')')
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
  T.check(show(flat) == '2:finish | 5:toStop', 'a flat straight: the finish and "to stop" only (' .. show(flat) .. ')')
  local none = road({ { 'straight', 1200 } }, hump(600, 30, 2))
  for _, p in ipairs(none) do p.z = nil end
  T.check(show(notes(build(none))) == '2:finish | 5:toStop', 'a line with no heights: nothing read off them')
  -- a crest in a corner is its shape; one just before it comes before the corner
  local oc = notes(build(road({ { 'straight', 500 }, { 'arc', 60, 90 }, { 'straight', 500 } }, hump(547, 60, 2))))
  T.check(has(oc, '4:corner/overCrest'), 'a crest in the middle of a corner: "over crest" (' .. show(oc) .. ')')
  local bc = notes(build(road({ { 'straight', 500 }, { 'arc', 60, 90 }, { 'straight', 500 } }, hump(470, 50, 1.5))))
  T.check(has(bc, '2:crest,4:corner') or has(bc, '2:smallCrest,4:corner') or has(bc, '2:brakeOverCrest'),
    'a crest just before a corner: called before it (' .. show(bc) .. ')')
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
  local b = build(line, { { s = 578, type = 'overBridge' }, { s = 586, type = 'pastJunction' } })
  local ns = notes(b)
  local hit
  for _, s in ipairs(ns) do if s:find('4:corner') then hit = s end end
  T.check(hit and (hit:find('jump') or hit:find('Jump')) and not hit:find('pastJunction'),
    'a jump, a bridge and a side road before a corner: the jump and the bridge are called, the side road is not (' ..
    tostring(hit) .. ')')
  local n2 = 0
  for _ in (hit or ''):gmatch('[23]:') do n2 = n2 + 1 end
  T.check(n2 <= 2, 'at most two calls before the corner')
  -- the finish on the last corner when it is close, and "to stop" after it, on the run-out
  local fin = build(road({ { 'straight', 400 }, { 'arc', 60, 90 }, { 'straight', 80 } }))
  local fn = notes(fin)
  T.check(fn[#fn - 1]:find('4:corner') and fn[#fn - 1]:find('finish') and fn[#fn] == '5:toStop',
    'a corner just before the finish: "... over finish", then "to stop" (' .. show(fn) .. ')')
  local stopPos = fin.notebook.pacenotes[#fin.notebook.pacenotes].pacenoteWaypoints[1].pos
  local fcum = geo.cumulative(road({ { 'straight', 400 }, { 'arc', 60, 90 }, { 'straight', 80 } }))
  local finishPt = geo.pointAt(road({ { 'straight', 400 }, { 'arc', 60, 90 }, { 'straight', 80 } }), fcum,
                               fcum[#fcum])
  local d = math.sqrt((stopPos[1] - finishPt.x) ^ 2 + (stopPos[2] - finishPt.y) ^ 2)
  T.near(d, writer.TO_STOP_AFTER_M, 1.5, '"to stop" sits on the run-out past the finish')
  -- keep left on a crest
  local kc = notes(build(road({ { 'straight', 1200 } }, hump(600, 100, 4)), { { s = 600, type = 'keepLeft' } }))
  T.check(has(kc, '^2:keepLeftOverCrest$'), 'a fork on a crest: "keep left over crest", one call (' .. show(kc) .. ')')
  -- narrows: a landmark like a junction
  local nr = notes(build(road({ { 'straight', 1200 } }), { { s = 600, type = 'narrows' } }))
  T.check(has(nr, '^5:narrows$'), 'a narrowing on a straight: a note of its own (' .. show(nr) .. ')')
  -- every call written is one the game's english style knows
  local mods = {
    crest = 1, bigCrest = 1, smallCrest = 1, intoCrest = 1, jump = 1, bigJump = 1, overJump = 1, dip = 1, badDip = 1,
    throughDip = 1, up = 1, down = 1, brakeOverCrest = 1, keepLeft = 1, keepRight = 1, keepLeftOverCrest = 1,
    keepRightOverCrest = 1, atJunction = 1, pastJunction = 1, overBridge = 1, narrows = 1, finish = 1, toStop = 1,
    chicaneLeftEntry = 1, chicaneRightEntry = 1, twisty = 1,
  }
  local shapes = { opens = 1, tightens = 1, opensAndTightens = 1, overCrest = 1, opensOverCrest = 1,
                   tightensOverCrest = 1, tightensDown = 1 }
  local descs = { hairpin = 1, openHairpin = 1, tightHairpin = 1, square = 1 }
  local known = true
  for _, built in ipairs({ b, fin }) do
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

T.done('test_pacenotes')
