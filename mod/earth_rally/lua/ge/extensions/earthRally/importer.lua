-- earthRally/importer: rallies from their maps, in game. Drop a .kml, .kmz or .gpx into
--   <BeamNG user folder>/current/earthRally/import/
-- and it becomes a rally in earthRally/events/ (the same file tools/import_kml.py writes): each line a stage (pieces
-- joined in driving order), the named points beside it (start, flying finish, stop, ATC / TC) its controls. Files are
-- looked at when the mod loads and when one changes in the folder (the game's onFileChanged); only new or changed ones
-- are imported (importIndex.json); Re-scan imports every file again. A file taken out of the folder leaves its rally
-- (and its recces and times) where it is: nothing is deleted.
--
-- parse() and build() are plain Lua (tests/test_import.lua runs them offline); scan() uses the game.
local M = {}

M.IMPORT_DIR = '/earthRally/import/'
M.EVENTS_DIR = '/earthRally/events/'
M.INDEX = '/earthRally/importIndex.json'
M.FORMAT = 1
M.GAP_WARN_M = 50
M.FAR_CONTROL_M = 100
M.WIDE_M = 13000            -- a stage's enclosing circle wider than this (radius): the world would shift on it

local R_EARTH = 6371008.8
local sqrt, abs, floor = math.sqrt, math.abs, math.floor

------------------------------------------------------------------------------------------ reading

local ENT = { amp = '&', lt = '<', gt = '>', quot = '"', apos = "'" }
-- (a character code as UTF-8)
local function utf8(c)
  if not c or c < 0 then return '' end
  if c < 0x80 then return string.char(c) end
  if c < 0x800 then return string.char(0xC0 + floor(c / 64), 0x80 + c % 64) end
  if c < 0x10000 then return string.char(0xE0 + floor(c / 4096), 0x80 + floor(c / 64) % 64, 0x80 + c % 64) end
  return string.char(0xF0 + floor(c / 262144), 0x80 + floor(c / 4096) % 64, 0x80 + floor(c / 64) % 64, 0x80 + c % 64)
end
local function text(s)
  if not s then return '' end
  s = s:gsub('<!%[CDATA%[(.-)%]%]>', '%1')
  s = s:gsub('&(#?x?)(%w+);', function(kind, v)
    if kind == '#' then return utf8(tonumber(v))
    elseif kind == '#x' then return utf8(tonumber(v, 16)) end
    return ENT[v] or ('&' .. v .. ';')
  end)
  return (s:gsub('^%s+', ''):gsub('%s+$', ''))
end
M._text = text

-- "lon,lat[,alt] lon,lat ..." -> { {lat, lon}... }
local function coords(s)
  local out = {}
  for tok in (s or ''):gmatch('[^%s]+') do
    local lon, lat = tok:match('^([-%d%.eE+]+),([-%d%.eE+]+)')
    lon, lat = tonumber(lon), tonumber(lat)
    if lon and lat then out[#out + 1] = { lat, lon } end
  end
  return out
end

-- (each <pfx tag ...>...</pfx tag> block in s: its body)
local function blocks(s, pfx, tag)
  local out, pos = {}, 1
  local open = '<' .. pfx .. tag
  local close = '</' .. pfx .. tag .. '>'
  while true do
    local a, b = s:find(open, pos, true)
    if not a then break end
    local nextc = s:sub(b + 1, b + 1)
    if nextc == '>' or nextc:match('%s') then
      local gt = s:find('>', b, true)
      local c = gt and s:find(close, gt, true)
      if not c then break end
      out[#out + 1] = s:sub(gt + 1, c - 1)
      pos = c + #close
    else
      pos = b + 1
    end
  end
  return out
end

-- The first <pfx tag>text</pfx tag> in s (not a tag that merely starts with the same letters), or nil.
local function first(s, pfx, tag)
  local b = blocks(s, pfx, tag)
  return b[1] and text(b[1]) or nil
end

local function readKml(s)
  local pfx = s:match('<([%w_]*:?)Placemark[%s>]') or ''
  local lines, points = {}, {}
  -- the rally's name: the document's own, before any folder or placemark
  local head = s:sub(1, (s:find('<' .. pfx .. 'Folder', 1, true) or s:find('<' .. pfx .. 'Placemark', 1, true) or #s + 1) - 1)
  local docName = first(head, pfx, 'name')
  for _, pm in ipairs(blocks(s, pfx, 'Placemark')) do
    local name = first(pm, pfx, 'name') or ''
    local pieces = {}
    for _, ls in ipairs(blocks(pm, pfx, 'LineString')) do
      local c = coords(first(ls, pfx, 'coordinates'))
      if #c >= 2 then pieces[#pieces + 1] = c end
    end
    if #pieces > 0 then
      lines[#lines + 1] = { name = name, pieces = pieces }
    else
      local pt = blocks(pm, pfx, 'Point')[1]
      local c = pt and coords(first(pt, pfx, 'coordinates'))
      if c and c[1] then points[#points + 1] = { name = name, lat = c[1][1], lon = c[1][2] } end
    end
  end
  return { lines = lines, points = points, name = docName ~= '' and docName or nil }
end

local function attr(tagText, a)
  return tonumber(tagText:match('[%s]' .. a .. '%s*=%s*"([^"]*)"') or tagText:match('[%s]' .. a .. "%s*=%s*'([^']*)'"))
end

local function readGpx(s)
  local lines, points = {}, {}
  local meta = blocks(s, '', 'metadata')[1]
  local docName = meta and first(meta, '', 'name')
  -- (each element with its opening tag kept, for the lat / lon attributes; a self-closed one has no name: skipped)
  local function elements(body, tag)
    local out = {}
    for open, inner in body:gmatch('(<' .. tag .. '%s[^>]-[^/])>(.-)</' .. tag .. '>') do out[#out + 1] = { open, inner } end
    return out
  end
  for _, w in ipairs(elements(s, 'wpt')) do
    local lat, lon = attr(w[1], 'lat'), attr(w[1], 'lon')
    if lat and lon then points[#points + 1] = { name = first(w[2], '', 'name') or '', lat = lat, lon = lon } end
  end
  local function track(body, segTag, ptTag)
    local pieces = {}
    local segs = segTag and blocks(body, '', segTag) or { body }
    for _, seg in ipairs(segs) do
      local pts = {}
      for open in seg:gmatch('<' .. ptTag .. '(%s[^>]*)>') do
        local lat, lon = attr(open, 'lat'), attr(open, 'lon')
        if lat and lon then pts[#pts + 1] = { lat, lon } end
      end
      if #pts >= 2 then pieces[#pieces + 1] = pts end
    end
    return pieces
  end
  for _, t in ipairs(blocks(s, '', 'trk')) do
    local pieces = track(t, 'trkseg', 'trkpt')
    if #pieces > 0 then lines[#lines + 1] = { name = first((t:gsub('<trkseg.*', '')), '', 'name') or '', pieces = pieces } end
  end
  for _, r in ipairs(blocks(s, '', 'rte')) do
    local pieces = track(r, nil, 'rtept')
    if #pieces > 0 then lines[#lines + 1] = { name = first((r:gsub('<rtept.*', '')), '', 'name') or '', pieces = pieces } end
  end
  return { lines = lines, points = points, name = docName }
end

-- A map file's text: { lines = { { name, pieces = { { {lat, lon}... }... } }... }, points = { { name, lat, lon }... },
-- name (the document's, or nil) }. kind: 'kml' or 'gpx'.
function M.parse(s, kind)
  if kind == 'gpx' then return readGpx(s) end
  return readKml(s)
end

------------------------------------------------------------------------------------------ names (as import_kml.py)

local ROLE_WORDS = { start = 'start', ss = 'start', ff = 'ff', flying = 'ff', finish = 'ff', stop = 'stop',
                     atc = 'atc', tc = 'atc' }
local ROLE_SKIP = { control = true, ['end'] = true, ['in'] = true, out = true }
local OTHER_WORDS = { spectator = true, jump = true, vc = true, barricade = true, service = true, regroup = true,
                      mtc = true, parc = true, maybe = true, area = true, traffic = true, prohibited = true,
                      expose = true }

local function words(name)
  local s = (name or ''):lower():gsub('\226\128\153', "'"):gsub('\239\191\189', "'")
  s = s:gsub("'s%f[%W]", 's')
  local out = {}
  for w in s:gmatch('[a-z0-9]+') do out[#out + 1] = w end
  return out
end

-- (a stage's name words: role words, years, version tags and stage numbers like "SS1" left out)
local function stageKey(name)
  local out = {}
  for _, w in ipairs(words(name)) do
    if not (ROLE_WORDS[w] or ROLE_SKIP[w] or w:match('^%d%d$') or w:match('^%d%d%d%d$') or w:match('^v%d+$')
            or w:match('^ss%d+$')) then
      out[#out + 1] = w
    end
  end
  return out
end
M._stageKey = stageKey

function M.slug(name)
  local k = stageKey(name)
  return #k > 0 and table.concat(k, '-') or 'stage'
end

local function pointRole(name)
  local ws = words(name)
  for _, w in ipairs(ws) do if OTHER_WORDS[w] then return nil end end
  for _, w in ipairs(ws) do if w == 'flying' or w == 'ff' then return 'ff' end end
  for _, w in ipairs(ws) do if ROLE_WORDS[w] then return ROLE_WORDS[w] end end
  return nil
end
M._pointRole = pointRole

local function same(a, b)
  if #a ~= #b then return false end
  for i = 1, #a do if a[i] ~= b[i] then return false end end
  return true
end
local function startsWith(a, b)      -- a begins with all of b
  if #b > #a then return false end
  for i = 1, #b do if a[i] ~= b[i] then return false end end
  return true
end
local function has(list, v) for _, x in ipairs(list) do if x == v then return true end end return false end

-- (edit distance of two short strings)
local function lev(a, b)
  local prev = {}
  for j = 0, #b do prev[j] = j end
  for i = 1, #a do
    local cur = { [0] = i }
    for j = 1, #b do
      cur[j] = math.min(prev[j] + 1, cur[j - 1] + 1, prev[j - 1] + (a:sub(i, i) == b:sub(j, j) and 0 or 1))
    end
    prev = cur
  end
  return prev[#b]
end

-- Controls by name: a point whose remaining words are a stage's name, or the start of it when only one stage begins
-- that way ("Maryhill FF" for "Maryhill Up"). Unmatched ones are reported with the stage whose name is nearest.
local function matchControls(stageNames, points)
  local keys = {}
  for i, n in ipairs(stageNames) do keys[i] = stageKey(n) end
  local found, unmatched = {}, {}
  for i = 1, #stageNames do found[i] = {} end
  for _, pt in ipairs(points) do
    local role = pointRole(pt.name)
    if role then
      local k = stageKey(pt.name)
      local reverse = has(k, 'reverse')
      local hits = {}
      for i, sk in ipairs(keys) do if same(sk, k) then hits[#hits + 1] = i end end
      if #hits == 0 and #k > 0 then
        for i, sk in ipairs(keys) do
          if startsWith(sk, k) and has(sk, 'reverse') == reverse then hits[#hits + 1] = i end
        end
        if #hits > 1 then hits = {} end
      end
      if #hits == 1 then
        found[hits[1]][role] = found[hits[1]][role] or { name = pt.name, lat = pt.lat, lon = pt.lon }
      else
        -- the nearest stage name, for the report (never used without the player)
        local kj = table.concat(k, ' ')
        local bestI, bestD = nil, math.huge
        for i, sk in ipairs(keys) do
          local d = lev(kj, table.concat(sk, ' '))
          if d < bestD then bestI, bestD = i, d end
        end
        unmatched[#unmatched + 1] = { name = pt.name, role = role,
          suggest = bestI and bestD <= math.max(2, floor(#kj / 4)) and stageNames[bestI] or nil }
      end
    end
  end
  return found, unmatched
end

------------------------------------------------------------------------------------------ geometry

local function frame(lat0, lon0)
  local kx = math.rad(1) * R_EARTH * math.cos(math.rad(lat0))
  local ky = math.rad(1) * R_EARTH
  return {
    xy = function(lat, lon) return { (lon - lon0) * kx, (lat - lat0) * ky } end,
    latlon = function(x, y) return lat0 + y / ky, lon0 + x / kx end,
  }
end
local function dist(a, b) return sqrt((a[1] - b[1]) ^ 2 + (a[2] - b[2]) ^ 2) end
local function length(xy)
  local s = 0
  for i = 1, #xy - 1 do s = s + dist(xy[i], xy[i + 1]) end
  return s
end

-- distance along xy of its point nearest p, and how far p is from it
local function project(xy, p)
  local best, along, acc = math.huge, 0, 0
  for i = 1, #xy - 1 do
    local a, b = xy[i], xy[i + 1]
    local dx, dy = b[1] - a[1], b[2] - a[2]
    local seg = sqrt(dx * dx + dy * dy)
    local t = seg < 1e-9 and 0 or math.max(0, math.min(1, ((p[1] - a[1]) * dx + (p[2] - a[2]) * dy) / (seg * seg)))
    local d = sqrt((a[1] + t * dx - p[1]) ^ 2 + (a[2] + t * dy - p[2]) ^ 2)
    if d < best then best, along = d, acc + t * seg end
    acc = acc + seg
  end
  return along, best
end

-- Smallest circle round the points (Welzl, iterative, a fixed shuffle): the stage's centre for the world's anchor.
local function enclosingCircle(pts)
  local p = {}
  for i, v in ipairs(pts) do p[i] = v end
  local seed = 1
  for i = #p, 2, -1 do
    seed = (seed * 1103515245 + 12345) % 2147483648
    local j = seed % i + 1
    p[i], p[j] = p[j], p[i]
  end
  local function c2(a, b) local c = { (a[1] + b[1]) / 2, (a[2] + b[2]) / 2 } return { c, dist(a, c) } end
  local function c3(a, b, c)
    local ax, ay, bx, by, cx, cy = a[1], a[2], b[1], b[2], c[1], c[2]
    local d = 2 * (ax * (by - cy) + bx * (cy - ay) + cx * (ay - by))
    if abs(d) < 1e-12 then return nil end
    local ux = ((ax * ax + ay * ay) * (by - cy) + (bx * bx + by * by) * (cy - ay) + (cx * cx + cy * cy) * (ay - by)) / d
    local uy = ((ax * ax + ay * ay) * (cx - bx) + (bx * bx + by * by) * (ax - cx) + (cx * cx + cy * cy) * (bx - ax)) / d
    return { { ux, uy }, dist({ ux, uy }, a) }
  end
  local function inside(c, q) return c and dist(c[1], q) <= c[2] + 1e-7 end
  local c = nil
  for i = 1, #p do
    if not inside(c, p[i]) then
      c = { p[i], 0 }
      for j = 1, i - 1 do
        if not inside(c, p[j]) then
          c = c2(p[i], p[j])
          for k = 1, j - 1 do
            if not inside(c, p[k]) then c = c3(p[i], p[j], p[k]) or c end
          end
        end
      end
    end
  end
  return c
end

-- One line from the pieces in driving order: from the piece end nearest the start (else the longest piece), each next
-- piece the one with an end nearest the line's end, turned round as needed. Returns the line and the gaps (m).
local function stitch(pieces, startXy)
  local left = {}
  for i, pc in ipairs(pieces) do left[i] = pc end
  local i0, e0
  if startXy then
    local best = math.huge
    for i, pc in ipairs(left) do
      for _, e in ipairs({ 1, #pc }) do
        local d = dist(pc[e], startXy)
        if d < best then best, i0, e0 = d, i, e end
      end
    end
  else
    local best = -1
    for i, pc in ipairs(left) do local l = length(pc) if l > best then best, i0 = l, i end end
    e0 = 1
  end
  local line = {}
  local p0 = table.remove(left, i0)
  if e0 ~= 1 then for k = #p0, 1, -1 do line[#line + 1] = p0[k] end else for k = 1, #p0 do line[k] = p0[k] end end
  local gaps = {}
  while #left > 0 do
    local tail = line[#line]
    local best, bi, be = math.huge, nil, nil
    for i, pc in ipairs(left) do
      for _, e in ipairs({ 1, #pc }) do
        local d = dist(pc[e], tail)
        if d < best then best, bi, be = d, i, e end
      end
    end
    local nxt = table.remove(left, bi)
    gaps[#gaps + 1] = best
    local from, to, step = 1, #nxt, 1
    if be ~= 1 then from, to, step = #nxt, 1, -1 end
    if best <= 0.5 then from = from + step end
    for k = from, to, step do line[#line + 1] = nxt[k] end
  end
  return line, gaps
end

local function round(v, n) local m = 10 ^ n return floor(v * m + 0.5) / m end

-- The event (as tools/import_kml.py writes it) from a parsed map, and the import's report:
-- { stages = { { id, name, km, controls = 'atc start ff stop', warnings = {...} }... }, unmatched = {...},
--   warnings = {...} }.
function M.build(parsed, eventId, eventName, sourceFile)
  local report = { stages = {}, unmatched = {}, warnings = {} }
  if #parsed.lines == 0 then
    report.warnings[#report.warnings + 1] = 'no lines (tracks) in the file: nothing to make stages from'
    return nil, report
  end
  local sLat, sLon, n = 0, 0, 0
  for _, l in ipairs(parsed.lines) do
    for _, pc in ipairs(l.pieces) do for _, p in ipairs(pc) do sLat, sLon, n = sLat + p[1], sLon + p[2], n + 1 end end
  end
  local fr = frame(sLat / n, sLon / n)
  local names = {}
  for i, l in ipairs(parsed.lines) do names[i] = l.name end
  local controls, unmatched = matchControls(names, parsed.points)

  local stages, used = {}, {}
  for idx, l in ipairs(parsed.lines) do
    local ctl = controls[idx]
    local startXy = ctl.start and fr.xy(ctl.start.lat, ctl.start.lon) or nil
    local pieces = {}
    for i, pc in ipairs(l.pieces) do
      local xy = {}
      for k, p in ipairs(pc) do xy[k] = fr.xy(p[1], p[2]) end
      pieces[i] = xy
    end
    local line, gaps = stitch(pieces, startXy)
    if not startXy and ctl.ff then
      local ff = fr.xy(ctl.ff.lat, ctl.ff.lon)
      if dist(line[1], ff) < dist(line[#line], ff) then
        local r = {}
        for k = #line, 1, -1 do r[#r + 1] = line[k] end
        line = r
      end
    end
    local total = length(line)
    local outCtl, warn = {}, {}
    for role, c in pairs(ctl) do
      local along, off = project(line, fr.xy(c.lat, c.lon))
      outCtl[role] = { name = c.name, lat = round(c.lat, 7), lon = round(c.lon, 7), distM = round(along, 1),
                       offLineM = round(off, 1) }
      if (role == 'start' or role == 'ff') and off > M.FAR_CONTROL_M then
        warn[#warn + 1] = string.format('its %s control is %.0f m from the line', role == 'ff' and 'flying finish' or role, off)
      end
    end
    local circle = enclosingCircle(line)
    local cLat, cLon = fr.latlon(circle[1][1], circle[1][2])
    local sid = M.slug(l.name)
    local base, k = sid, 2
    while used[sid] do sid, k = base .. '-' .. k, k + 1 end
    used[sid] = true
    local biggest = 0
    for _, g in ipairs(gaps) do if g > biggest then biggest = g end end
    if biggest > M.GAP_WARN_M then
      warn[#warn + 1] = string.format('drawn in %d pieces with gaps up to %.0f m', #pieces, biggest)
    end
    if circle[2] > M.WIDE_M then
      warn[#warn + 1] = string.format('%.0f km across: too wide to run for now (the world would shift during it)',
        circle[2] * 2 / 1000)
    end
    local ll = {}
    for i, p in ipairs(line) do local la, lo = fr.latlon(p[1], p[2]) ll[i] = { round(la, 7), round(lo, 7) } end
    local gapsOut = {}
    for i, g in ipairs(gaps) do gapsOut[i] = round(g, 1) end
    stages[#stages + 1] = {
      id = sid, name = l.name, lengthM = round(total, 1),
      centre = { lat = round(cLat, 7), lon = round(cLon, 7) }, radiusM = round(circle[2], 1),
      pieces = #pieces, gapsM = gapsOut, controls = outCtl, line = ll,
    }
    local roles = {}
    for _, r in ipairs({ 'atc', 'start', 'ff', 'stop' }) do if outCtl[r] then roles[#roles + 1] = r end end
    report.stages[#report.stages + 1] = { id = sid, name = l.name, km = total / 1000, controls = roles, warnings = warn }
  end
  report.unmatched = unmatched
  local others = {}
  for i, p in ipairs(parsed.points) do others[i] = { name = p.name, lat = round(p.lat, 7), lon = round(p.lon, 7) } end
  return {
    format = M.FORMAT, id = eventId, name = eventName,
    source = { file = sourceFile, note = "The organisers' map: for your own use, not for sharing." },
    stages = stages, points = others,
  }, report
end

-- One line per thing worth telling about an import (the window and the log).
function M.reportLines(report)
  local out = {}
  for _, w in ipairs(report.warnings or {}) do out[#out + 1] = w end
  for _, s in ipairs(report.stages or {}) do
    local roles = #s.controls > 0 and table.concat(s.controls, ', ') or 'no controls found'
    out[#out + 1] = string.format('%s: %.1f km; controls: %s', s.name, s.km, roles)
    for _, w in ipairs(s.warnings) do out[#out + 1] = '    ' .. w end
  end
  for _, u in ipairs(report.unmatched or {}) do
    out[#out + 1] = string.format('"%s" matches no stage%s', u.name, u.suggest and (': did you mean ' .. u.suggest .. '?') or '')
  end
  return out
end

------------------------------------------------------------------------------------------ the folder (in game)

-- (a fingerprint of every byte of a file: changed or not, an edit that keeps its length too)
local function fingerprint(s)
  local h = 5381
  for i = 1, #s do h = (h * 33 + s:byte(i)) % 4294967291 end
  return string.format('%d:%08x', #s, h)
end
M._fingerprint = fingerprint

local function stem(path)
  local s = (path:match('([^/]+)$') or path):gsub('%.[xX][mM][lL]$', '')   -- (X.kml.xml: as some browsers save a KML)
  return (s:gsub('%.[^.]+$', ''))
end
local function idFrom(name) return ((name:lower():gsub('[^a-z0-9]+', '-'):gsub('^-+', ''):gsub('-+$', ''))) end

-- (a .kmz's KML: the zip's doc.kml, else its first .kml)
local function readKmz(path)
  if not ZipArchive then return nil, 'this game cannot open .kmz files' end
  local zip = ZipArchive()
  if not zip:openArchiveName(path, 'r') then return nil, 'not a .kmz the game can open' end
  local list = zip:getFileList() or {}
  local pick = nil
  for _, f in ipairs(list) do if f:lower():match('doc%.kml$') then pick = f break end end
  if not pick then for _, f in ipairs(list) do if f:lower():match('%.kml$') then pick = f break end end end
  local s = pick and zip:readFileToMemory(pick)
  zip:close()
  if not s then return nil, 'no KML inside the .kmz' end
  return s
end

local function readIndex()
  local ok, r = pcall(jsonReadFile, M.INDEX)
  return ok and type(r) == 'table' and type(r.files) == 'table' and r or { format = 1, files = {} }
end

-- An event already on this computer from the same map file (tools/import_kml.py's, before the import folder): its id
-- is kept, so its recces and times still belong to it.
local function existingId(fileName)
  for _, f in ipairs(FS:findFiles(M.EVENTS_DIR, '*.json', 0, false, false) or {}) do
    local ok, e = pcall(jsonReadFile, f)
    if ok and type(e) == 'table' and type(e.source) == 'table' and e.source.file == fileName then
      return e.id or f:match('([^/]+)%.json$')
    end
  end
end

M.lastReports = {}          -- event id -> { file, lines = {...}, date }

-- The folder made, its files imported when new or changed (every file with force), files taken out forgotten (their
-- rallies kept). Returns a list of { file, eventId, name, stages, ok, why, removed }.
function M.scan(force)
  local done = {}
  if not FS:directoryExists(M.IMPORT_DIR) then pcall(function() FS:directoryCreate(M.IMPORT_DIR, true) end) end
  local index = readIndex()
  local seen = {}
  local found = {}
  for _, pat in ipairs({ '*.kml', '*.kmz', '*.gpx', '*.KML', '*.KMZ', '*.GPX', '*.kml.xml', '*.KML.xml', '*.kml.XML' }) do
    for _, f in ipairs(FS:findFiles(M.IMPORT_DIR, pat, 0, false, false) or {}) do found[f] = true end
  end
  for path in pairs(found) do
    local fileName = path:match('([^/]+)$')
    local ext = fileName:lower():gsub('%.xml$', ''):match('%.(%a+)$')
    seen[fileName] = true
    local raw = readFile(path)
    if raw then
      local fp = fingerprint(raw)
      local entry = index.files[fileName]
      if force or not entry or entry.fingerprint ~= fp then
        local s, why = raw, nil
        if ext == 'kmz' then s, why = readKmz(path) end
        local okP, parsed = false, nil
        if s then okP, parsed = pcall(M.parse, s, ext == 'gpx' and 'gpx' or 'kml') end
        if not s or not okP then
          done[#done + 1] = { file = fileName, ok = false, why = why or tostring(parsed) }
          index.files[fileName] = { fingerprint = fp, failed = true }   -- (told once, until it changes)
          log('W', 'earthRally', 'import ' .. fileName .. ': ' .. tostring(why or parsed))
        else
          local id = (entry and entry.eventId) or existingId(fileName) or idFrom(stem(fileName))
          if id == '' then id = 'rally' end
          -- (another file of the folder has that id already, e.g. X.kml beside X.kmz: this one gets its own)
          local function taken(cand)
            for other, e in pairs(index.files) do if other ~= fileName and e.eventId == cand then return true end end
            return false
          end
          if taken(id) then
            local base, k = id, 2
            while taken(base .. '-' .. k) do k = k + 1 end
            id = base .. '-' .. k
          end
          local name = parsed.name or stem(fileName)
          local okB, event, report = pcall(M.build, parsed, id, name, fileName)
          if okB and event then
            jsonWriteFile(M.EVENTS_DIR .. id .. '.json', event, true)
            index.files[fileName] = { fingerprint = fp, eventId = id, date = os.date('!%Y-%m-%dT%H:%M:%SZ') }
            M.lastReports[id] = { file = fileName, lines = M.reportLines(report) }
            done[#done + 1] = { file = fileName, eventId = id, name = name, stages = #event.stages, ok = true }
            log('I', 'earthRally', string.format('imported %s: %s, %d stages', fileName, name, #event.stages))
            for _, l in ipairs(M.lastReports[id].lines) do log('I', 'earthRally', '  ' .. l) end
          else
            local why2 = okB and table.concat(M.reportLines(report or {}), '; ') or tostring(event)
            done[#done + 1] = { file = fileName, ok = false, why = why2 }
            index.files[fileName] = { fingerprint = fp, failed = true }
            log('W', 'earthRally', 'import ' .. fileName .. ': ' .. why2)
          end
        end
      end
    end
  end
  -- files taken out of the folder: forgotten, their rallies kept (a rally is only ever deleted by the player)
  for fileName, entry in pairs(index.files) do
    if not seen[fileName] and entry.failed then
      index.files[fileName] = nil
    elseif not seen[fileName] then
      index.files[fileName] = nil
      done[#done + 1] = { file = fileName, eventId = entry.eventId, removed = true, ok = true }
      log('I', 'earthRally', fileName .. ' taken out of the import folder: its rally ' .. tostring(entry.eventId) ..
        ' is kept (delete earthRally/events/' .. tostring(entry.eventId) .. '.json to remove it)')
    end
  end
  if #done > 0 then jsonWriteFile(M.INDEX, index, true) end
  return done
end

-- The import folder on disk, opened in the system's file browser.
function M.openFolder()
  if not FS:directoryExists(M.IMPORT_DIR) then pcall(function() FS:directoryCreate(M.IMPORT_DIR, true) end) end
  local plat = Engine and Engine.Platform
  if plat and plat.exploreFolder then pcall(plat.exploreFolder, M.IMPORT_DIR) return true end
  return false
end

-- Where the folder is on disk (for the window).
function M.folderPath()
  local real = FS.getFileRealPath and FS:getFileRealPath(M.IMPORT_DIR)
  return real or ('<BeamNG user folder>/current' .. M.IMPORT_DIR)
end

return M
