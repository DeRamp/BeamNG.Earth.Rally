-- tools/pacenote_check/gamevoice.lua: what the co-driver actually says for a notebook stageWriter.build wrote, worked
-- out the way the game does it, off the game's own Lua (read from the player's BeamNG.drive folder at run time,
-- never copied here):
--   - the road the notes are measured on: the driveline's nodes followed as a spline, a point every 2 m
--     (drivelineV3: DrivelineUtil.minSplineSpacing; the same spline tools/pacenote_benchmark.py follows);
--   - each corner's number: snaproad.updateHalfpoint + geoPacenotes.measurePartition (the circle through the
--     corner start, the route half way between, and the corner end), then pacenote.structuredForProjection;
--   - the distance calls: path.autofillDistanceCalls (corner end, or start with distanceMeasureWaypoint 'cs', to the
--     next non-isolated note's corner start, along the road either way round; "into" / "and" under 20 / 40 m, else
--     "<n>" after the note; '#' in a field blocks it);
--   - the words: compositorUtil.compositePhraseEntries with the style's config (english/enthusiast or casual).
-- Only the pieces of the game that need the engine are stood in for here (vec3, a log, the road architect's
-- circle through three points). Pure Lua otherwise: runs under lupa like the offline tests.
local M = {}

local GAME_LUA       -- '<BeamNG.drive>/lua'
local RALLY = '/lua/ge/extensions/gameplay/rally'

------------------------------------------------------------------------------------------ stand-ins for the engine

local V = {}
V.__index = V
local function vec3(x, y, z)
  if type(x) == 'table' then
    if x.x ~= nil then return setmetatable({ x = x.x, y = x.y, z = x.z or 0 }, V) end
    return setmetatable({ x = x[1] or 0, y = x[2] or 0, z = x[3] or 0 }, V)
  end
  return setmetatable({ x = x or 0, y = y or 0, z = z or 0 }, V)
end
V.__add = function(a, b) return vec3(a.x + b.x, a.y + b.y, a.z + b.z) end
V.__sub = function(a, b) return vec3(a.x - b.x, a.y - b.y, a.z - b.z) end
V.__mul = function(a, b)
  if type(a) == 'number' then return vec3(b.x * a, b.y * a, b.z * a) end
  if type(b) == 'number' then return vec3(a.x * b, a.y * b, a.z * b) end
  return vec3(a.x * b.x, a.y * b.y, a.z * b.z)
end
V.__div = function(a, b) return vec3(a.x / b, a.y / b, a.z / b) end
V.__unm = function(a) return vec3(-a.x, -a.y, -a.z) end
function V:distance(o) local dx, dy, dz = self.x - o.x, self.y - o.y, self.z - o.z return math.sqrt(dx * dx + dy * dy + dz * dz) end
function V:squaredDistance(o) local d = self:distance(o) return d * d end
function V:length() return math.sqrt(self.x * self.x + self.y * self.y + self.z * self.z) end
function V:squaredLength() return self.x * self.x + self.y * self.y + self.z * self.z end
function V:dot(o) return self.x * o.x + self.y * o.y + self.z * o.z end
function V:cross(o) return vec3(self.y * o.z - self.z * o.y, self.z * o.x - self.x * o.z, self.x * o.y - self.y * o.x) end
function V:normalized() local l = self:length() return l > 0 and self / l or vec3(0, 0, 0) end
function V:z0() return vec3(self.x, self.y, 0) end
function V:toTable() return { self.x, self.y, self.z } end

local function deepcopy(t, seen)
  if type(t) ~= 'table' then return t end
  seen = seen or {}
  if seen[t] then return seen[t] end
  local o = {}
  seen[t] = o
  for k, v in pairs(t) do o[deepcopy(k, seen)] = deepcopy(v, seen) end
  return setmetatable(o, getmetatable(t))
end

local logged = {}
local function install()
  _G.vec3 = _G.vec3 or vec3
  _G.deepcopy = _G.deepcopy or deepcopy
  _G.log = function(level, tag, msg) if level == 'E' then logged[#logged + 1] = tostring(msg) end end
  _G.ColorF = _G.ColorF or function(...) return { ... } end
  _G.color = _G.color or function(...) return { ... } end
  _G.split = _G.split or function(s, sep)
    local out = {}
    for piece in (s .. sep):gmatch('(.-)' .. sep:gsub('%p', '%%%0')) do out[#out + 1] = piece end
    return out
  end
  _G.jsonReadFile = _G.jsonReadFile or function() return nil end
  -- anything else the modules touch at load time (ui_imgui and the like): a stand-in that answers every index
  -- with itself and every call with nil, so a module loads; nothing the co-driver's words need goes through it
  local anything
  anything = setmetatable({}, { __index = function() return anything end, __call = function() return nil end })
  _G.ui_imgui = _G.ui_imgui or anything
  _G.FS = _G.FS or { fileExists = function() return false end, directoryExists = function() return false end }
  -- the road architect's circle through three points (x, y only) -- the one thing geoPacenotes takes from it
  package.preload['editor/roadArchitect/utilities'] = function()
    return { circle2DFrom3Points = function(p1, p2, p3)
      local p1x, p1y, p2x, p2y, p3x, p3y = p1.x, p1.y, p2.x, p2.y, p3.x, p3.y
      local dot22 = p2x * p2x + p2y * p2y
      local bc = (p1x * p1x + p1y * p1y - dot22) * 0.5
      local cd = (dot22 - p3x * p3x - p3y * p3y) * 0.5
      local det = (p1x - p2x) * (p2y - p3y) - (p2x - p3x) * (p1y - p2y)
      if math.abs(det) < 1e-12 then return nil end
      return vec3(((bc * (p2y - p3y) - cd * (p1y - p2y)) / det), (((p1x - p2x) * cd - (p2x - p3x) * bc) / det), 0)
    end }
  end
  -- '/lua/...' names: the game's own files
  local loaders = package.loaders or package.searchers
  table.insert(loaders, 2, function(name)
    if name:sub(1, 5) ~= '/lua/' then return nil end
    local path = GAME_LUA .. name:sub(5) .. '.lua'
    local f = io.open(path, 'rb')
    if not f then return '\n\tno game file ' .. path end
    local src = f:read('*a')
    f:close()
    local chunk, err = loadstring(src, '@' .. path)
    if not chunk then error(err) end
    return chunk
  end)
end

------------------------------------------------------------------------------------------ the driveline's spline

-- centripetal Catmull-Rom between p1 and p2 (x, y), Steffen cubic for the heights: as tools/pacenote_benchmark.py
local function cr(p0, p1, p2, p3, t)
  local function tj(ti, a, b) local d = math.sqrt((b[1] - a[1]) ^ 2 + (b[2] - a[2]) ^ 2) return ti + math.max(d, 1e-6) ^ 0.5 end
  local t0 = 0
  local t1 = tj(t0, p0, p1)
  local t2 = tj(t1, p1, p2)
  local t3 = tj(t2, p2, p3)
  local u = t1 + (t2 - t1) * t
  local function lerp(a, b, ta, tb) local w = (u - ta) / (tb - ta) return { a[1] + (b[1] - a[1]) * w, a[2] + (b[2] - a[2]) * w } end
  local a1, a2, a3 = lerp(p0, p1, t0, t1), lerp(p1, p2, t1, t2), lerp(p2, p3, t2, t3)
  local b1, b2 = lerp(a1, a2, t0, t2), lerp(a2, a3, t1, t3)
  return lerp(b1, b2, t1, t2)
end
local function steffen(z0, z1, z2, z3, t)
  local function slope(sa, sb)
    if sa * sb <= 0 then return 0 end
    local p = (sa + sb) / 2
    return (sa > 0 and 1 or -1) * math.min(math.abs(sa), math.abs(sb), math.abs(p) / 2) * 2
  end
  local s0, s1, s2 = z1 - z0, z2 - z1, z3 - z2
  local m1, m2 = slope(s0, s1), slope(s1, s2)
  local a, b = m1 + m2 - 2 * s1, 3 * s1 - 2 * m1 - m2
  return ((a * t + b) * t + m1) * t + z1
end

-- nodes: { {x, y, z}... } -> { { pos = vec3, s = along } ... }, a point about every `spacing` m
function M.spline(nodes, spacing)
  spacing = spacing or 2.0
  local n = #nodes
  local out = {}
  local function push(x, y, z)
    local p = vec3(x, y, z)
    local last = out[#out]
    out[#out + 1] = { pos = p, s = last and last.s + p:distance(last.pos) or 0 }
  end
  if n < 3 then
    for _, p in ipairs(nodes) do push(p[1], p[2], p[3] or 0) end
    return out
  end
  for j = 1, n - 1 do
    local i0, i3 = math.max(1, j - 1), math.min(n, j + 2)
    local p0, p1, p2, p3 = nodes[i0], nodes[j], nodes[j + 1], nodes[i3]
    if i0 == j then p0 = { 2 * p1[1] - p2[1], 2 * p1[2] - p2[2], 2 * (p1[3] or 0) - (p2[3] or 0) } end
    if i3 == j + 1 then p3 = { 2 * p2[1] - p1[1], 2 * p2[2] - p1[2], 2 * (p2[3] or 0) - (p1[3] or 0) } end
    local d = math.sqrt((p2[1] - p1[1]) ^ 2 + (p2[2] - p1[2]) ^ 2)
    local div = math.max(1, math.floor(d / spacing + 0.5))
    for k = (j == 1 and 0 or 1), div do
      local t = k / div
      local xy = cr(p0, p1, p2, p3, t)
      push(xy[1], xy[2], steffen(p0[3] or 0, p1[3] or 0, p2[3] or 0, p3[3] or 0, t))
    end
  end
  return out
end

-- the point of `pts` nearest p, searched from index `from` on (the notes run in order); its index and along
local function nearest(pts, p, from)
  local best, bi = math.huge, from or 1
  for i = from or 1, #pts do
    local d = (pts[i].pos.x - p.x) ^ 2 + (pts[i].pos.y - p.y) ^ 2
    if d < best then best, bi = d, i end
  end
  return bi, pts[bi].s, math.sqrt(best)
end
M.nearest = nearest

local function atAlong(pts, s)
  local lo, hi = 1, #pts
  while hi - lo > 1 do
    local mid = math.floor((lo + hi) / 2)
    if pts[mid].s <= s then lo = mid else hi = mid end
  end
  local a, b = pts[lo], pts[hi]
  local w = b.s > a.s and (s - a.s) / (b.s - a.s) or 0
  return a.pos + (b.pos - a.pos) * math.max(0, math.min(1, w)), lo
end

------------------------------------------------------------------------------------------ the co-driver

local loaded = {}
local function game()
  if loaded.util then return loaded end
  loaded.structured = require(RALLY .. '/notebook/structured')
  loaded.util = require(RALLY .. '/compositors/helpers/compositorUtil')
  loaded.geo = require(RALLY .. '/snaproad/geoPacenotes')
  loaded.rallyUtil = require(RALLY .. '/util')
  return loaded
end

function M.setup(gameLuaDir)
  GAME_LUA = gameLuaDir:gsub('[/\\]$', '')
  install()
  return game()
end

local function styleConfig(style)
  return deepcopy(require(RALLY .. '/compositors/styles/english/' .. (style or 'enthusiast')))
end

-- the style's distance helpers (textCompositor's, which also needs the voice pack modules)
local function distanceHelpers(cfg, rallyUtil)
  local d = cfg.distance
  local function roundDistance(dist)
    local r = d.rounding
    if dist >= r.largeThreshold then return rallyUtil.customRound(dist, r.large) / r.largeThreshold, d.units.large end
    if dist >= r.mediumThreshold then
      local val = rallyUtil.customRound(dist, r.medium)
      if val == r.largeThreshold then return rallyUtil.customRound(dist, r.large) / r.largeThreshold, d.units.large end
      return val, d.units.base
    end
    return rallyUtil.customRound(dist, r.small), d.units.base
  end
  local function toString(dist)
    local v, unit = roundDistance(math.floor(dist))
    local s = tostring(v)
    if unit == d.units.large then
      local a, b = s:match('(%d+)%.(%d+)')
      if a then s = a .. ' ' .. d.units.point .. ' ' .. b:gsub('%d', '%0 '):gsub(' $', '') end
      s = s .. ' ' .. unit
    end
    return s
  end
  local function shorthand(dist)
    for _, link in ipairs(d.links or {}) do
      if dist < link.threshold then return link.text, true end
    end
    return nil, false
  end
  return toString, shorthand
end

-- built: stageWriter.build's result (Lua tables). opts.style 'enthusiast' (default) or 'casual'.
-- Returns { notes = { { n, s0, s1 (along the driveline spline, corner start / end), sStart (the start line on the
-- same spline), text (the words, one string), phrases ({...}), grade (the corner's number, or nil), diameter,
-- dir, firstTrigger, distAfterM, nextN } ... }, spline = pts, startS, finishS, errors, overlaps = { { n, next, m } } }
function M.say(built, opts)
  opts = opts or {}
  local g = game()
  local cfg = styleConfig(opts.style)
  local nodes = {}
  for i, p in ipairs(built.driveline.nodes) do nodes[i] = { p[1], p[2], p[3] or 0 } end
  local pts = M.spline(nodes, 2.0)
  local cornerCfg = cfg.componentTypes and cfg.componentTypes.corner
  local intensities = g.util.cornerIntensityList(cornerCfg)
  local toString, shorthand = distanceHelpers(cfg, g.rallyUtil)
  local distanceCalls = g.util.distanceCallsEnabled(cfg)

  -- the start and finish lines: the race's start position and the last checkpoint, as the game reads them
  local startS, finishS
  local race = built.race
  if race and race.startPositions and race.startPositions[1] then
    local sp = race.startPositions[1].pos
    local _, s = nearest(pts, vec3(sp))
    startS = s
  end
  if race and race.pathnodes and #race.pathnodes > 0 then
    local fp = race.pathnodes[#race.pathnodes].pos
    local _, s = nearest(pts, vec3(fp))
    finishS = s
  end

  local list = {}
  local from = 1
  for n, pn in ipairs(built.notebook.pacenotes) do
    local cs, ce
    for _, w in ipairs(pn.pacenoteWaypoints) do
      if w.waypointType == 'cornerStart' then cs = vec3(w.pos) end
      if w.waypointType == 'cornerEnd' then ce = vec3(w.pos) end
    end
    local i0, s0 = nearest(pts, cs, math.max(1, from - 50))
    local i1, s1 = nearest(pts, ce, i0)
    from = i0
    local half = atAlong(pts, (s0 + s1) / 2)
    local st = g.structured()
    st:onDeserialized(pn.structured)
    local items = st:slotItems()
    local corner = g.structured.slotItem({ schemaVersion = 3, items = items }, 4)
    local entry = { n = n, s0 = s0, s1 = s1, items = items, firstTrigger = pn.triggerType == 15, meta = pn.metadata }
    if corner then
      local fake = {
        measurements = {},
        halfpointPos = half,
        getCornerStartWaypoint = function() return { pos = cs } end,
        getCornerEndWaypoint = function() return { pos = ce } end,
        notebook = { getTextCompositor = function() return { getConfig = function() return cfg end } end },
        corner = function() return corner end,
      }
      local focus = {}
      for i = math.max(1, i0 - 5), math.min(#pts, i1 + 5) do focus[#focus + 1] = pts[i] end
      g.geo.measurePartition(fake, focus)
      local ms = fake.measurements
      local v = ms.variants and (ms.variants[g.geo.normalizeMeasurementType(corner.measurementType)] or
                                 ms.variants[g.geo.defaultMeasurementType]) or ms.corner1
      if v then
        corner.direction = v.direction == 'left' and -1 or (v.direction == 'right' and 1 or v.direction)
        corner.intensity = v.diameter
        corner.arcDegrees = v.arcDegrees
        corner.arcMeters = v.arcMeters or v.pointsLength or v.arcDistance
        corner.chordMeters = v.chordMeters or v.straightLineDistance
        entry.diameter = v.diameter
        entry.dir = v.direction
        local hit = g.util.getRangeValue(intensities, v.diameter, 'diameter')
        entry.intensityName = type(hit) == 'table' and (hit.name or hit.text) or hit
      end
    end
    list[#list + 1] = entry
  end

  -- path.autofillDistanceCalls, step by step: clear the before / after fields (a '#' -- the autofill blocker -- is
  -- kept, and so is an isolated note's own link word), then from each note that is not isolated to the next note that
  -- is not (findNextNonIsolated; not a missing one), measured from its corner end (its corner start when
  -- distanceMeasureWaypoint is 'cs') to that note's corner start, as snaproad.distanceBetweenPositions does: the
  -- distance along the road, either way round (math.abs)
  local pns = built.notebook.pacenotes
  local level1 = g.rallyUtil.autodist_internal_level1
  local blocker = g.rallyUtil.autofill_blocker
  local function field(pn, key)
    -- the note's saved before / after field (any language: the co-driver's language is the only one written)
    for _, lang in pairs(pn.notes or {}) do
      if type(lang) == 'table' and lang[key] ~= nil then return lang[key] end
    end
    return ''
  end
  for i, e in ipairs(list) do
    local pn = pns[i]
    local b, a = field(pn, 'before'), field(pn, 'after')
    e.before = (b == blocker or (pn.isolate and b == level1)) and b or ''
    e.after = (a == blocker or (pn.isolate and a == level1)) and a or ''
  end
  local function nextNonIsolated(i)
    for j = i + 1, #pns do
      if not pns[j].isolate then return j end
    end
    return nil
  end
  if distanceCalls then
    for i = 1, #list do
      local e, pn = list[i], pns[i]
      local j = nextNonIsolated(i)
      local pnNext = j and pns[j]
      if not pn.isolate and not pn.ignoreDistanceCalls and pnNext and not pnNext.missing then
        local nx = list[j]
        local from = pn.distanceMeasureWaypoint == 'cs' and e.s0 or e.s1
        local dist = math.abs(nx.s0 - from)
        e.distAfterM = dist
        e.nextN = j
        local short, has = shorthand(dist)
        if has then
          if nx.before ~= blocker then
            nx.before = pnNext.includeLinkWord == false and level1 or (short or level1)
          end
        elseif e.after ~= blocker then
          e.after = toString(dist)
        end
      end
    end
  end
  -- notes whose corners overlap: the next note's corner start before this note's corner end (the game measures the
  -- gap the other way round and says it as a distance)
  local overlaps = {}
  for i = 1, #list - 1 do
    local e, nx = list[i], list[i + 1]
    if nx.s0 < e.s1 then overlaps[#overlaps + 1] = { n = i, next = i + 1, m = e.s1 - nx.s0 } end
  end

  for i, e in ipairs(list) do
    local ok, entries = pcall(g.util.compositePhraseEntries, cfg, { schemaVersion = 3, items = e.items }, e.before,
                              e.after, { distanceAfterBeforePostModifier =
                                         built.notebook.pacenotes[i].distanceBeforeModifier == true })
    local words = {}
    if ok then
      for _, en in ipairs(entries or {}) do words[#words + 1] = en.text end
    else
      words[1] = '<error: ' .. tostring(entries) .. '>'
    end
    e.phrases = words
    e.text = table.concat(words, ' ')
    e.items = nil
  end
  local errs = logged
  logged = {}
  return { notes = list, spline = pts, startS = startS, finishS = finishS, errors = errs, overlaps = overlaps }
end

return M
