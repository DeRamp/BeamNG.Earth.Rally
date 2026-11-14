-- earthRally/pack: seasons, rallies and stages from a pack (docs/rally-file.md). A pack is a folder in
--   <BeamNG user folder>/current/earthRally/import/
-- or a .zip of one, with a manifest at its root (season.json / rally.json / stage.json, or any root JSON whose `kind`
-- says which). Its maps become rallies exactly as a loose map would (importer.parse / importer.build), with what the
-- manifest adds beside them: the season, dates, place, itinerary, rules, images and the results as leaderboards.
--
-- importer.scan calls M.scan with its index, so packs are fingerprinted, skipped while unchanged and keep their ids
-- the same way loose maps do. The game is reached only through FS, readFile, jsonDecode, jsonWriteFile and
-- ZipArchive (tests/test_pack.lua stands them in).
local importer = require('earthRally/importer')

local M = {}

M.FORMAT = 1                 -- the newest rally-file format this reader knows
M.SEASONS_DIR = '/earthRally/seasons/'
M.BOARDS_DIR = '/earthRally/boards/'
-- Where a pack's images are copied to, one folder per rally. Where the menu can load images from is still to be
-- checked in game: this is the one place to change if it has to move.
M.MEDIA_DIR = '/earthRally/media/'
M.MEDIA = { 'cover', 'logo', 'photo' }
M.KINDS = { season = true, rally = true, stage = true }

local RULES = { falseStartS = 'list', lateSPerMin = 'n', earlySPerMin = 'n', maxLatenessMin = 'n',
                startIntervalMin = 'n' }
local DEFAULT_POINTS = { 25, 20, 16, 13, 11, 10, 9, 8, 7, 6, 5, 4, 3, 2, 1 }

------------------------------------------------------------------------------------------ paths

-- A path inside the pack, tidied: `\` as `/`, no `.` parts, `..` taken back. nil for one that leaves the pack.
local function norm(rel)
  if type(rel) ~= 'string' then return nil end
  local out = {}
  for part in rel:gsub('\\', '/'):gmatch('[^/]+') do
    if part == '..' then
      if #out == 0 then return nil end
      out[#out] = nil
    elseif part ~= '.' then
      out[#out + 1] = part
    end
  end
  return #out > 0 and table.concat(out, '/') or nil
end
M._norm = norm

-- (rel as the manifest wrote it, relative to the folder `base` the manifest sits in: '' at the pack root)
local function join(base, rel)
  if type(rel) ~= 'string' or rel == '' then return nil end
  return norm(base ~= '' and (base .. '/' .. rel) or rel)
end
local function dirOf(rel) return rel:match('^(.*)/[^/]*$') or '' end
local function baseName(rel) return rel:match('([^/]+)$') or rel end

local function ensureDir(dir)
  if FS.directoryExists and FS:directoryExists(dir) then return end
  if FS.directoryCreate then pcall(function() FS:directoryCreate(dir, true) end) end
end

-- (a file's bytes as they are on disk: a zip's fingerprint is its bytes, and text mode could stop at a ^Z in one)
local function readBytes(path)
  if io and io.open then
    local ok, f = pcall(io.open, path, 'rb')
    if ok and f then
      local s = f:read('*a')
      f:close()
      if s then return s end
    end
  end
  return readFile(path)
end

------------------------------------------------------------------------------------------ the two kinds of pack

-- A folder pack: its files read straight from disk.
local function folderSource(dir, name)
  local root = dir:gsub('/+$', '') .. '/'
  return {
    name = name,
    read = function(rel) return readFile(root .. rel) end,
    readBytes = function(rel) return readBytes(root .. rel) end,
    path = function(rel) return root .. rel end,
    copy = function(rel, dest)
      if not FS:fileExists(root .. rel) then return false end
      local ok, r = pcall(FS.copyFile, FS, root .. rel, dest)
      return ok and r ~= false
    end,
    rootJson = function()
      local out = {}
      for _, f in ipairs(FS:findFiles(root, '*.json', 0, false, false) or {}) do
        local rel = f:sub(1, #root):lower() == root:lower() and f:sub(#root + 1) or baseName(f)
        if not rel:find('/') then out[#out + 1] = rel end
      end
      table.sort(out)
      return out
    end,
    close = function() end,
  }
end

-- A zip pack: the manifest at its root, or inside its one top-level folder (a zip made of a folder, as the ARA pack
-- is). Text read with readFileToMemory as importer.lua reads a .kmz; images copied out with extractFile, which writes
-- the entry's bytes straight to disk (core/modmanager.lua unpacks mods with it), so no binary passes through Lua.
local function zipSource(path, name)
  if not ZipArchive then return nil, 'this game cannot open .zip files' end
  local zip = ZipArchive()
  if not zip:openArchiveName(path, 'r') then return nil, 'not a .zip the game can open' end
  local entries, lower, tops, rootJson = {}, {}, {}, {}
  for _, f in ipairs(zip:getFileList() or {}) do
    local n = norm(f)
    if n and not f:match('[/\\]$') then
      entries[n], lower[n:lower()] = f, f
      tops[n:match('^([^/]+)/') or ''] = true
    end
  end
  -- (one top-level folder holding everything, and nothing loose beside it: that folder is the pack's root)
  local prefix = ''
  local top, count = nil, 0
  for t in pairs(tops) do top, count = t, count + 1 end
  if count == 1 and top ~= '' then prefix = top .. '/' end
  for n in pairs(entries) do
    local rel = n:sub(#prefix + 1)
    if n:sub(1, #prefix) == prefix and not rel:find('/') and rel:lower():match('%.json$') then
      rootJson[#rootJson + 1] = rel
    end
  end
  table.sort(rootJson)
  local function entry(rel)
    return entries[prefix .. rel] or lower[(prefix .. rel):lower()]
  end
  return {
    name = name, zip = true,
    read = function(rel)
      local e = entry(rel)
      return e and zip:readFileToMemory(e) or nil
    end,
    copy = function(rel, dest)
      local e = entry(rel)
      if not e then return false end
      local ok, r = pcall(zip.extractFile, zip, e, dest)
      return ok and r ~= false
    end,
    rootJson = function() return rootJson end,
    close = function() zip:close() end,
  }
end

-- Every pack in the import folder: { { name, kind = 'folder' | 'zip', path }... }. A sub-folder is looked at
-- whatever is in it (one with no manifest is reported, once: someone put it there to be imported).
function M.find(dir)
  dir = dir or importer.IMPORT_DIR
  local out, seen = {}, {}
  if FS.directoryList then
    for _, d in ipairs(FS:directoryList(dir, false, true) or {}) do
      local name = d:gsub('/+$', ''):match('([^/]+)$')
      if name and not seen[name] then
        seen[name] = true
        out[#out + 1] = { name = name, kind = 'folder', path = dir .. name }
      end
    end
  end
  for _, pat in ipairs({ '*.zip', '*.ZIP' }) do
    for _, f in ipairs(FS:findFiles(dir, pat, 0, false, false) or {}) do
      local name = baseName(f)
      local rel = f:sub(1, #dir):lower() == dir:lower() and f:sub(#dir + 1) or name
      if not seen[name] and not rel:find('/') then
        seen[name] = true
        out[#out + 1] = { name = name, kind = 'zip', path = f }
      end
    end
  end
  table.sort(out, function(a, b) return a.name < b.name end)
  return out
end

------------------------------------------------------------------------------------------ reading the manifest

local function decode(s)
  if type(s) ~= 'string' then return nil end
  local ok, r = pcall(jsonDecode, s)
  return ok and type(r) == 'table' and r or nil
end

-- The pack's manifest: its data, its kind and its file, or nil and why.
function M.manifest(src)
  local found = {}
  for _, rel in ipairs(src.rootJson()) do
    local data = decode(src.read(rel))
    if data then
      local kind = data.kind
      if kind == nil then kind = rel:lower():match('^(%a+)%.json$') end
      if M.KINDS[kind] then found[#found + 1] = { data = data, kind = kind, file = rel } end
    end
  end
  if #found == 0 then return nil, 'not a rally pack (no season.json, rally.json or stage.json at its top)' end
  if #found > 1 then
    local names = {}
    for i, f in ipairs(found) do names[i] = f.file end
    return nil, 'more than one manifest at its top: ' .. table.concat(names, ', ')
  end
  local m = found[1]
  local fmt = tonumber(m.data.format) or 1
  if fmt > M.FORMAT then
    return nil, string.format('%s is format %d; this version of Earth Rally reads format %d', m.file, fmt, M.FORMAT)
  end
  return m
end

-- (each rally a manifest describes: { spec, base, round }, a round's own rally manifest read in its place)
local function rallySpecs(src, m)
  if m.kind ~= 'season' then return { { spec = m.data, base = '' } } end
  local out = {}
  for i, r in ipairs(type(m.data.rounds) == 'table' and m.data.rounds or {}) do
    local one = { spec = r, base = '', round = tonumber(r.round) or i }
    if type(r) == 'table' and r.rally then
      local rel = join('', r.rally)
      local data = rel and decode(src.read(rel))
      if data then
        -- (the round's own name and dates where the rally manifest leaves them out)
        for _, k in ipairs({ 'name', 'dates' }) do if data[k] == nil then data[k] = r[k] end end
        one.spec, one.base, one.manifest = data, dirOf(rel), rel
        local fmt = tonumber(data.format) or 1
        if fmt > M.FORMAT then
          one.why = string.format('%s is format %d; this version reads format %d', rel, fmt, M.FORMAT)
        end
      else
        one.why = "can't read " .. tostring(r.rally)
      end
    end
    out[#out + 1] = one
  end
  return out
end

-- The files a manifest names, as pack paths (what a folder pack's fingerprint is made of).
local function namedFiles(src, m)
  local out = { m.file }
  for _, r in ipairs(rallySpecs(src, m)) do
    if r.manifest then out[#out + 1] = r.manifest end
    if type(r.spec) == 'table' then
      for _, k in ipairs({ 'map', 'event', 'results', 'cover', 'logo', 'photo' }) do
        local rel = join(r.base, r.spec[k])
        if rel then out[#out + 1] = rel end
      end
    end
  end
  return out
end

-- A folder pack's fingerprint: its manifest and every file it names, each to the byte.
local function folderFingerprint(src, m)
  local parts = {}
  for _, rel in ipairs(namedFiles(src, m)) do
    local s = src.readBytes(rel)
    parts[#parts + 1] = rel .. '=' .. (s and importer._fingerprint(s) or 'missing')
  end
  return importer._fingerprint(table.concat(parts, '\n'))
end

------------------------------------------------------------------------------------------ one rally

-- (the rules: only the numbers this version knows, each later table overriding the one before)
local function rulesOf(...)
  local out, any = {}, false
  for i = 1, select('#', ...) do
    local t = select(i, ...)
    if type(t) == 'table' then
      for k, kind in pairs(RULES) do
        local v = t[k]
        if kind == 'n' and type(v) == 'number' then out[k], any = v, true end
        if kind == 'list' and type(v) == 'table' and type(v[1]) == 'number' then
          local l = {}
          for j, x in ipairs(v) do if type(x) == 'number' then l[j] = x else break end end
          out[k], any = l, true
        end
      end
    end
  end
  return any and out or nil
end

local function str(v) return v == nil and '' or tostring(v) end
local function round2(v) return math.floor(v * 100 + 0.5) / 100 end

-- The running order: { { ss, stage (stage id), run, km, cancelled, day, powerStage }... }. From the event file's SS
-- rows (one per control: a pass run separately by two classes is listed twice there), else the map in order.
local function itineraryOf(evFile, stages, lineId, warn)
  local out, seen = {}, {}
  if evFile and type(evFile.itinerary) == 'table' then
    for _, row in ipairs(evFile.itinerary) do
      if type(row) == 'table' and row.type == 'SS' and row.control and not seen[row.control] then
        seen[row.control] = true
        local sid = lineId[row.stage]
        if sid then
          out[#out + 1] = { ss = tostring(row.control), stage = sid, run = tonumber(row.run) or 1,
                            km = tonumber(row.ss_km), cancelled = false, day = tonumber(row.day),
                            powerStage = row.power_stage == true or nil }
        else
          warn(string.format('itinerary %s "%s": no line of that name in the map', tostring(row.control),
            str(row.stage)))
        end
      end
    end
    if #out > 0 then return out end
  end
  for i, s in ipairs(stages) do
    out[i] = { ss = 'SS' .. i, stage = s.id, run = 1, km = round2(s.lengthM / 1000), cancelled = false }
  end
  return out
end

-- The results trimmed to what the leaderboards need, fastest first. Rows with no time are left out: there is
-- nothing to place them by, and a hole would break the row arrays.
local function boardsOf(results, lineId, itinerary, fp, warn)
  local byControl, byPass = {}, {}
  for _, r in ipairs(itinerary) do
    byControl[r.ss] = r
    byPass[r.stage .. '#' .. r.run] = r
  end
  local passes = {}
  for i, st in ipairs(type(results.stages) == 'table' and results.stages or {}) do
    local sid = type(st) == 'table' and lineId[st.stage]
    if not sid then
      warn(string.format('results %s "%s": no line of that name in the map', str(st.control or ('SS' .. i)),
        str(type(st) == 'table' and st.stage)))
    else
      local run = tonumber(st.run) or 1
      local it = byControl[st.control] or byPass[sid .. '#' .. run]
      local field = {}
      for _, t in ipairs(type(st.times) == 'table' and st.times or {}) do
        if type(t) == 'table' and type(t.seconds) == 'number' then
          field[#field + 1] = { t.seconds, str(t.driver), str(t.car), str(t.class), str(t.championship),
                                t.notional == true }
        end
      end
      table.sort(field, function(a, b) return a[1] < b[1] end)
      local pass = { ss = tostring(st.control or (it and it.ss) or ('SS' .. i)), stage = sid, run = run,
                     km = tonumber(st.km) or (it and it.km), cancelled = st.cancelled == true, field = field }
      if it and pass.cancelled then it.cancelled = true end
      if it and not it.km then it.km = pass.km end
      passes[#passes + 1] = pass
    end
  end
  local overall = {}
  for _, o in ipairs(type(results.overall) == 'table' and results.overall or {}) do
    if type(o) == 'table' and type(o.seconds) == 'number' then
      overall[#overall + 1] = { o.seconds, str(o.driver), str(o.car), str(o.class), str(o.championship),
                                o.result == nil or o.result == 'classified' }
    end
  end
  -- (the classified first, each part fastest first: a crew out of the rally is not ahead of one that finished)
  table.sort(overall, function(a, b)
    if a[6] ~= b[6] then return a[6] end
    return a[1] < b[1]
  end)
  return { format = 1, fingerprint = fp, passes = passes, overall = overall }
end

-- (a map's text and its kind, or nil and why)
local function readMap(src, rel)
  local lower = rel:lower()
  if lower:match('%.kmz$') then
    if src.zip then return nil, 'a .kmz inside a .zip: put the .kml in the pack instead' end
    local s, why = importer.readKmz(src.path(rel))
    return s, why, 'kml'
  end
  local s = src.read(rel)
  if not s then return nil, "can't find " .. rel end
  return s, nil, lower:match('%.gpx$') and 'gpx' or 'kml'
end

-- One rally from its spec (a rally manifest, or a season's round): the event, boards and images written. ctx:
-- { id = rallyId, or idFor(name); season = { id, name, round }?; rules = the season's?; fp }. Returns the event and
-- its report, or nil and why.
local function makeRally(src, spec, base, ctx, kind)
  if type(spec) ~= 'table' then return nil, 'not a rally' end
  local mapRel = join(base, spec.map)
  if not mapRel then return nil, 'no map named' end
  local s, why, mapKind = readMap(src, mapRel)
  if not s then return nil, why end
  local okP, parsed = pcall(importer.parse, s, mapKind)
  if not okP then return nil, baseName(mapRel) .. ': ' .. tostring(parsed) end
  local name = type(spec.name) == 'string' and spec.name ~= '' and spec.name or importer.eventName(parsed.name, mapRel)
  local id = ctx.id or ctx.idFor(name)
  local okB, event, report = pcall(importer.build, parsed, id, name, src.name .. '/' .. mapRel)
  if not okB then return nil, tostring(event) end
  if not event then return nil, table.concat(importer.reportLines(report or {}), '; ') end
  local function warn(w) report.warnings[#report.warnings + 1] = w end

  if kind == 'stage' and #event.stages > 1 then
    warn(string.format('the map has %d lines; a stage uses the first, %s', #event.stages, event.stages[1].name))
    event.stages = { event.stages[1] }
    report.stages = { report.stages[1] }
  end
  local lineId = {}
  for _, st in ipairs(event.stages) do if lineId[st.name] == nil then lineId[st.name] = st.id end end

  local evFile = nil
  local evRel = join(base, spec.event)
  if evRel then
    evFile = decode(src.read(evRel))
    if not evFile then warn("can't read the event file " .. evRel) end
  end
  local info = evFile and type(evFile.event) == 'table' and evFile.event or {}
  event.itinerary = itineraryOf(evFile, event.stages, lineId, warn)
  event.dates = type(spec.dates) == 'table' and spec.dates or type(info.dates) == 'table' and info.dates or nil
  local hq = type(info.hq) == 'table' and info.hq or {}
  local place = {}
  for _, k in ipairs({ 'town', 'state' }) do if type(hq[k]) == 'string' and hq[k] ~= '' then place[#place + 1] = hq[k] end end
  event.place = #place > 0 and table.concat(place, ', ') or nil
  event.rules = rulesOf(ctx.rules, evFile and evFile.rules, spec.rules)
  event.season = ctx.season

  local boardsPath = M.BOARDS_DIR .. id .. '.json'
  local resRel = join(base, spec.results)
  local results = resRel and decode(src.read(resRel))
  if resRel and not results then warn("can't read the results file " .. resRel) end
  if results then
    local b = boardsOf(results, lineId, event.itinerary, importer._fingerprint(src.read(resRel)), warn)
    ensureDir(M.BOARDS_DIR)
    jsonWriteFile(boardsPath, b, true)
    event.boards = id .. '.json'
  elseif FS:fileExists(boardsPath) then
    pcall(FS.removeFile, FS, boardsPath)      -- (the results taken out of the pack: no leaderboards left behind)
  end

  local media = {}
  for _, k in ipairs(M.MEDIA) do
    local rel = join(base, spec[k])
    if rel then
      local ext = (rel:match('%.([%w]+)$') or 'png'):lower()
      local dir = M.MEDIA_DIR .. id .. '/'
      ensureDir(dir)
      if src.copy(rel, dir .. k .. '.' .. ext) then media[k] = dir .. k .. '.' .. ext
      else warn(string.format("can't find the %s image %s", k, rel)) end
    end
  end
  event.media = next(media) and media or nil
  event.pack = { file = src.name, fingerprint = ctx.fp }
  jsonWriteFile(importer.EVENTS_DIR .. id .. '.json', event, true)
  return event, report
end

------------------------------------------------------------------------------------------ the folder

-- (an id no other import has: loose maps' and other packs')
local function freeId(index, packName, cand, field)
  local function taken(c)
    if field == 'seasonId' then
      for other, e in pairs(index.packs) do if other ~= packName and e.seasonId == c then return true end end
      return false
    end
    return importer.idTaken(index, c, nil, packName)
  end
  if not taken(cand) then return cand end
  local k = 2
  while taken(cand .. '-' .. k) do k = k + 1 end
  return cand .. '-' .. k
end

local function idOr(s, fallback)
  local id = type(s) == 'string' and importer.idFrom(s) or ''
  return id ~= '' and id or fallback
end

-- (a season's rounds made, its file written)
local function importSeason(src, m, index, entry, fp, out)
  local d = m.data
  if type(d.name) ~= 'string' or d.name == '' then return nil, m.file .. ' has no name' end
  if type(d.rounds) ~= 'table' or #d.rounds == 0 then return nil, m.file .. ' has no rounds' end
  local sid = (type(d.id) == 'string' and d.id ~= '' and importer.idFrom(d.id)) or (entry and entry.seasonId)
    or freeId(index, src.name, idOr(d.name, 'season'), 'seasonId')
  local season = { format = 1, id = sid, name = d.name, championship = d.championship, rounds = {} }
  local st = type(d.standings) == 'table' and d.standings or {}
  -- (false: every crew scores. A JSON null reads as missing, so "all" or false is how a manifest says it.)
  local champ = st.championship
  if champ == nil then champ = 'national' elseif champ == false or champ == 'all' or champ == '' then champ = false end
  season.standings = { championship = champ, points = type(st.points) == 'table' and #st.points > 0 and st.points
    or DEFAULT_POINTS, best = tonumber(st.best) }
  local used = {}
  for _, r in ipairs(rallySpecs(src, m)) do
    local label = 'round ' .. r.round
    if used[r.round] then
      out.warnings[#out.warnings + 1] = label .. ' is listed twice: the second left out'
    elseif r.why then
      out.warnings[#out.warnings + 1] = label .. ': ' .. r.why
    else
      used[r.round] = true
      local id = sid .. '-r' .. r.round
      local ev, rep = makeRally(src, r.spec, r.base,
        { id = id, season = { id = sid, name = d.name, round = r.round }, rules = d.rules, fp = fp }, 'rally')
      if ev then
        season.rounds[#season.rounds + 1] = id
        out.rallies[#out.rallies + 1] = { id = id, name = ev.name, stages = #ev.stages, report = rep }
      else
        out.warnings[#out.warnings + 1] = label .. ': ' .. tostring(rep)
      end
    end
  end
  if #season.rounds == 0 then return nil, out.warnings[1] or 'no rounds could be read' end
  ensureDir(M.SEASONS_DIR)
  jsonWriteFile(M.SEASONS_DIR .. sid .. '.json', season, true)
  out.seasonId, out.name = sid, d.name
  return true
end

-- (one pack looked at: nil when it is unchanged, else what happened)
local function importPack(p, index, force)
  local entry = index.packs[p.name]
  local fp = nil
  if p.kind == 'zip' then
    local bytes = readBytes(p.path)
    if not bytes then return nil end
    fp = importer._fingerprint(bytes)
    if not force and entry and entry.fingerprint == fp then return nil end
  end
  local src, why
  if p.kind == 'zip' then src, why = zipSource(p.path, p.name) else src = folderSource(p.path, p.name) end
  local function fail(w, f)
    index.packs[p.name] = { fingerprint = f or fp or ('failed:' .. w), failed = true }   -- (told once, until it changes)
    log('W', 'earthRally', 'import ' .. p.name .. ': ' .. w)
    return { file = p.name, ok = false, why = w }
  end
  if not src then return fail(why) end
  local ok, res = pcall(function()
    local m, mwhy = M.manifest(src)
    if p.kind == 'folder' then
      fp = m and folderFingerprint(src, m) or ('none:' .. table.concat(src.rootJson(), '|'))
      if not force and entry and entry.fingerprint == fp then return 'same' end
    end
    if not m then return fail(mwhy, fp) end
    local out = { rallies = {}, warnings = {} }
    if m.kind == 'season' then
      local okS, swhy = importSeason(src, m, index, entry, fp, out)
      if not okS then return fail(swhy, fp) end
    else
      if not m.data.map then return fail(m.file .. ' names no map', fp) end
      local fixed = type(m.data.id) == 'string' and m.data.id ~= '' and importer.idFrom(m.data.id) or nil
      local kept = entry and entry.eventIds and entry.eventIds[1]
      local ev, rep = makeRally(src, m.data, '', { fp = fp, id = fixed or kept,
        idFor = function(name) return freeId(index, p.name, idOr(name, 'rally')) end }, m.kind)
      if not ev then return fail(tostring(rep), fp) end
      out.rallies[1] = { id = ev.id, name = ev.name, stages = #ev.stages, report = rep }
      out.name = ev.name
    end
    return out
  end)
  src.close()
  if not ok then return fail(tostring(res), fp) end
  if res == 'same' then return nil end
  if res.ok == false then return res end

  local ids, stages = {}, 0
  for i, r in ipairs(res.rallies) do
    ids[i], stages = r.id, stages + r.stages
    importer.lastReports[r.id] = { file = p.name, lines = importer.reportLines(r.report) }
    for _, w in ipairs(r.report.warnings) do res.warnings[#res.warnings + 1] = r.name .. ': ' .. w end
  end
  index.packs[p.name] = { fingerprint = fp, seasonId = res.seasonId, eventIds = ids,
                          date = os.date('!%Y-%m-%dT%H:%M:%SZ') }
  log('I', 'earthRally', string.format('imported %s: %s, %d rall%s, %d stages', p.name, tostring(res.name), #ids,
    #ids == 1 and 'y' or 'ies', stages))
  for _, w in ipairs(res.warnings) do log('W', 'earthRally', '  ' .. w) end
  return { file = p.name, ok = true, name = res.name, eventId = ids[1], seasonId = res.seasonId, rallies = #ids,
           stages = stages, warnings = res.warnings }
end

-- Every pack in the import folder imported when new or changed (every one with force); packs taken out forgotten,
-- their rallies kept. index: importer's (its .packs kept here). Returns entries in importer.scan's shape, plus
-- rallies, seasonId and warnings.
function M.scan(index, force)
  index.packs = index.packs or {}
  local done, seen = {}, {}
  for _, p in ipairs(M.find()) do
    seen[p.name] = true
    local r = importPack(p, index, force)
    if r then done[#done + 1] = r end
  end
  for name, entry in pairs(index.packs) do
    if not seen[name] then
      index.packs[name] = nil
      if not entry.failed then
        done[#done + 1] = { file = name, eventId = entry.eventIds and entry.eventIds[1], removed = true, ok = true,
                            rallies = entry.eventIds and #entry.eventIds or 1 }
        log('I', 'earthRally', name .. ' taken out of the import folder: its rallies are kept')
      end
    end
  end
  return done
end

return M
