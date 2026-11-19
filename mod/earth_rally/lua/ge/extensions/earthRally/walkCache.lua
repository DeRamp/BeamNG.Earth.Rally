-- earthRally/walkCache: the roads the walk has read, kept on disk, so ground read once is never walked again.
--
-- roadWalk reads BeamNG.Earth's traffic road map round the car at each stop. Each read is kept here in lat / lon:
-- its nodes and edges, and the square of ground it covered. A later window whose whole square lies inside squares
-- already read is answered from here, with no teleport. That covers a rally's second and third loops, a Reset and
-- a new auto recce, and stages that share roads.
--
-- Kept honest: everything is stamped with the BeamNG.Earth version that built it, and a tile written by another
-- version is thrown away whole (its roads may have changed); a square older than MAX_AGE_DAYS is not trusted.
--
-- Files: DIR .. '<tileLat>_<tileLon>.json', one per TILE_DEG square:
--   { v = 1, earth = '<version>', squares = { { lat, lon, half, t } ... },
--     nodes = { [name] = { lat, lon, alt, radius } }, edges = { { a, b } ... } }
-- A node or edge lives in the tile of its (first) node. A square in the tile of its centre.
local M = {}

M.DIR = '/earthRally/roadcache/'
M.TILE_DEG = 0.1
M.MAX_AGE_DAYS = 30
M.SAMPLE_M = 50          -- a window's square is checked for coverage at a point every this far

local tiles = {}         -- key -> tile table (loaded or new)
local dirty = {}

local function api() return rawget(_G, 'beamngEarth_api') end

-- BeamNG.Earth's own version, or its API version where that is all it says; nil: nothing is kept.
function M.stamp()
  local a = api()
  if not a then return nil end
  if type(a.earthVersion) == 'function' then
    local ok, v = pcall(a.earthVersion)
    if ok and v ~= nil then return tostring(v) end
  end
  if type(a.version) == 'function' then
    local ok, x, y = pcall(a.version)
    if ok and x then return 'api ' .. tostring(x) .. '.' .. tostring(y) end
  end
  return nil
end

local floor, cos, pi = math.floor, math.cos, math.pi
local function tileOf(lat, lon) return floor(lat / M.TILE_DEG), floor(lon / M.TILE_DEG) end
local function key(ti, tj) return ti .. '_' .. tj end
local function mLat() return 111320 end
local function mLon(lat) return 111320 * cos(lat * pi / 180) end

local function now() return os.time() end
local function edgeId(a, b)
  a, b = tostring(a), tostring(b)
  if a < b then return a .. '|' .. b end
  return b .. '|' .. a
end
M._now = now

local function load(ti, tj, stamp)
  local k = key(ti, tj)
  local t = tiles[k]
  if t == nil then
    local path = M.DIR .. k .. '.json'
    local ok, r = false, nil
    if FS and FS:fileExists(path) then ok, r = pcall(jsonReadFile, path) end
    t = (ok and type(r) == 'table' and r.v == 1) and r or false
    tiles[k] = t
  end
  if t and t.earth ~= stamp then t = false end          -- (another BeamNG.Earth's roads: not trusted, replaced)
  return t or nil
end

local function tileFor(lat, lon, stamp)
  local ti, tj = tileOf(lat, lon)
  local t = load(ti, tj, stamp)
  if not t then
    t = { v = 1, earth = stamp, squares = {}, nodes = {}, edges = {} }
    tiles[key(ti, tj)] = t
  end
  return t, key(ti, tj)
end

-- Keep one read: geo nodes { [name] = { lat, lon, alt, radius } }, edges { { a, b } ... }, the square it covered
-- (centre lat, lon, half size m). Written to disk at once.
function M.store(nodes, edges, cLat, cLon, half)
  local stamp = M.stamp()
  if not stamp or type(nodes) ~= 'table' then return false end
  local t, k = tileFor(cLat, cLon, stamp)
  t.squares[#t.squares + 1] = { cLat, cLon, half, now() }
  dirty[k] = true
  for name, n in pairs(nodes) do
    if type(n) == 'table' and n.lat then
      local nt, nk = tileFor(n.lat, n.lon, stamp)
      nt.nodes[name] = { n.lat, n.lon, n.alt or 0, n.radius or 0 }
      dirty[nk] = true
    end
  end
  for _, e in ipairs(edges or {}) do
    local a, b = e[1], e[2]
    local n = a and nodes[a]
    if n and b ~= nil and a ~= b then
      local et, ek = tileFor(n.lat, n.lon, stamp)
      if not et.seen then              -- (the tile's edges by id, built once: no scan per edge)
        et.seen = {}
        for _, x in ipairs(et.edges) do et.seen[edgeId(x[1], x[2])] = true end
      end
      local id = edgeId(a, b)
      if not et.seen[id] then
        et.edges[#et.edges + 1] = { a, b }
        et.seen[id] = true
      end
    end
  end
  M.flush()
  return true
end

function M.flush()
  if not jsonWriteFile then dirty = {} return end
  for k in pairs(dirty) do
    local t = tiles[k]
    if t then
      local out = { v = 1, earth = t.earth, squares = t.squares, nodes = t.nodes, edges = t.edges }
      pcall(jsonWriteFile, M.DIR .. k .. '.json', out, false)
    end
  end
  dirty = {}
end

-- The tiles a square touches.
local function tilesOver(lat, lon, half, stamp)
  local dLat, dLon = half / mLat(), half / mLon(lat)
  local i0, j0 = tileOf(lat - dLat, lon - dLon)
  local i1, j1 = tileOf(lat + dLat, lon + dLon)
  local out = {}
  for i = i0, i1 do for j = j0, j1 do
    local t = load(i, j, stamp)
    if t then out[#out + 1] = t end
  end end
  return out
end

-- Has the whole square (centre lat, lon, half size m) been read, by this BeamNG.Earth, within MAX_AGE_DAYS?
function M.covered(lat, lon, half)
  local stamp = M.stamp()
  if not stamp then return false end
  local oldest = now() - M.MAX_AGE_DAYS * 86400
  -- the squares that could cover any of it: those in the tiles round it, reach included (a square's centre can be
  -- in the next tile over)
  local sq = {}
  for _, t in ipairs(tilesOver(lat, lon, half + 1200, stamp)) do
    for _, s in ipairs(t.squares or {}) do
      if (s[4] or 0) >= oldest then sq[#sq + 1] = s end
    end
  end
  if #sq == 0 then return false end
  local kl, ko = mLat(), mLon(lat)
  local steps = math.ceil(2 * half / M.SAMPLE_M)
  for a = 0, steps do
    for b = 0, steps do
      local y = -half + 2 * half * a / steps
      local x = -half + 2 * half * b / steps
      local pLat, pLon = lat + y / kl, lon + x / ko
      local ok = false
      for _, s in ipairs(sq) do
        if math.abs((pLat - s[1]) * kl) <= s[3] and math.abs((pLon - s[2]) * mLon(s[1])) <= s[3] then ok = true break end
      end
      if not ok then return false end
    end
  end
  return true
end

-- The roads kept for a square: { geoNodes = { [name] = { lat, lon, alt, radius } }, edges = { { a, b } ... } }.
-- Nodes within the square plus `margin` m; the edges with a node among them.
function M.read(lat, lon, half, margin)
  local stamp = M.stamp()
  local reach = half + (margin or 0)
  local kl, ko = mLat(), mLon(lat)
  local nodes, edges = {}, {}
  local ts = tilesOver(lat, lon, reach, stamp)
  for _, t in ipairs(ts) do
    for name, n in pairs(t.nodes or {}) do
      if math.abs((n[1] - lat) * kl) <= reach and math.abs((n[2] - lon) * ko) <= reach then
        nodes[name] = { lat = n[1], lon = n[2], alt = n[3], radius = n[4] }
      end
    end
  end
  for _, t in ipairs(ts) do
    for _, e in ipairs(t.edges or {}) do
      if nodes[e[1]] or nodes[e[2]] then edges[#edges + 1] = { e[1], e[2] } end
    end
  end
  return { geoNodes = nodes, edges = edges, complete = true }
end

-- Everything forgotten from memory (a test; or after the files were removed).
function M.forget() tiles, dirty = {}, {} end
return M
