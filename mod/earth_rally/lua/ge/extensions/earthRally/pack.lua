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
local events = require('earthRally/events')
local boards = require('earthRally/boards')

local M = {}

M.FORMAT = 1                 -- the newest rally-file format this reader knows
M.SEASONS_DIR = events.SEASONS_DIR
M.BOARDS_DIR = events.BOARDS_DIR
-- Where a pack's images are copied to, one folder per rally. Where the menu can load images from is still to be
-- checked in game: this is the one place to change if it has to move.
M.MEDIA_DIR = '/earthRally/media/'
M.MEDIA = { 'cover', 'logo', 'photo' }
M.KINDS = { season = true, rally = true, stage = true }

local RULES = { falseStartS = 'list', lateSPerMin = 'n', earlySPerMin = 'n', maxLatenessMin = 'n',
                startIntervalMin = 'n' }
-- (a stage's `controls` as the named points importer.build matches to its line: "Start - <stage>" and so on)
local CONTROL_WORDS = { atc = 'ATC', start = 'Start', ff = 'Flying finish', stop = 'Stop' }

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

-- (a file's bytes as they are on disk: a zip's fingerprint is its bytes, and text mode could stop at a ^Z in one.
-- io.open reaches the game's virtual file system: the game's own readFile is io.open(filename, "r")
-- (lua/common/utils.lua), so '/earthRally/import/x.zip' opens here as it does there, only as bytes.)
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

-- A file's size and modification time as one string ('1234@1731600000'), from FS:stat: the call the game's
-- modmanager makes to tell whether a mod zip changed (core/modmanager.lua, hasSameFileStat: filesize, modtime).
-- nil when the game cannot give both: then the file's bytes are the only test.
local function statOf(path)
  if not (FS and FS.stat) then return nil end
  local ok, st = pcall(FS.stat, FS, path)
  if not ok or type(st) ~= 'table' then return nil end
  local size, mt = tonumber(st.filesize), tonumber(st.modtime)
  if not size or not mt then return nil end
  return string.format('%d@%d', size, mt)
end

-- (not part of a pack when looking for its one top folder: a Mac's __MACOSX/, dot files like .DS_Store, and the
-- files Windows leaves in a folder of pictures, Thumbs.db and desktop.ini, whatever their case)
local IGNORED = { ['__macosx'] = true, ['thumbs.db'] = true, ['desktop.ini'] = true }
local function ignored(name) return IGNORED[name:lower()] == true or name:sub(1, 1) == '.' end
M._ignored = ignored

-- (dir's sub-folders by name: directoryList may list files as well, so only what is a folder)
local function subFolders(dir)
  local out = {}
  if not FS.directoryList then return out end
  for _, d in ipairs(FS:directoryList(dir, false, true) or {}) do
    local name = d:gsub('/+$', ''):match('([^/]+)$')
    if name and FS:directoryExists(dir .. name) then out[#out + 1] = name end
  end
  table.sort(out)
  return out
end

------------------------------------------------------------------------------------------ the two kinds of pack

-- A folder's pack root: the folder, or the one folder inside it when it holds nothing else (what Windows'
-- Extract All makes of a zip of a folder: X/X/season.json), as a zip's root is found.
local function folderRoot(dir)
  local root = dir:gsub('/+$', '') .. '/'
  for _, f in ipairs(FS:findFiles(root, '*', 0, false, false) or {}) do
    local rel = f:sub(1, #root):lower() == root:lower() and f:sub(#root + 1) or baseName(f)
    if not rel:find('/') and not ignored(rel) then return root end
  end
  local subs = {}
  for _, d in ipairs(subFolders(root)) do if not ignored(d) then subs[#subs + 1] = d end end
  return #subs == 1 and (root .. subs[1] .. '/') or root
end

-- A folder pack: its files read straight from disk.
local function folderSource(dir, name)
  local root = folderRoot(dir)
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
      local top = n:match('^([^/]+)/')
      if not ignored(top or n) then tops[top or ''] = true end
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

-- (a pack's name for telling copies apart: 'ARA-Nationals-2026.zip' and 'ARA Nationals 2026' are one pack)
local function packKey(name)
  local k = (name:gsub('%.[zZ][iI][pP]$', '')):lower():gsub('[^%w]', '')
  return k ~= '' and k or name
end
M._packKey = packKey

-- Every pack in the import folder: { { name, kind = 'folder' | 'zip', path }... }. A sub-folder is looked at
-- whatever is in it (one with no manifest is reported, once: someone put it there to be imported). Zips are
-- found first, and a folder is only what FS:directoryExists says is one, so a .zip is never taken for a folder.
-- The mod ships the ARA 2026 season as a folder in its zip (1.8.0); a player who also has that season's zip in
-- their own import folder has one pack twice. Two packs of the same name (packKey), or a folder and a zip whose
-- manifests have the same `id` (a renamed copy, 'ARA-Nationals-2026 (1).zip'), are one: the zip is kept (the
-- player's own copy, which their times and ids are already under), the folder left out.
local idCache = {}       -- (a zip's manifest id, by path and FS:stat: a zip is opened once until it changes)
local function manifestId(p)
  local key = p.kind == 'zip' and (p.path .. '@' .. tostring(statOf(p.path) or '')) or nil
  if key and idCache[key] ~= nil then return idCache[key] or nil end
  local id = false
  local ok = pcall(function()
    local src = p.kind == 'zip' and zipSource(p.path, p.name) or (p.kind == 'folder' and folderSource(p.path, p.name))
    if not src then return end
    local m = M.manifest(src)
    src.close()
    local v = m and type(m.data.id) == 'string' and importer.idFrom(m.data.id) or ''
    if v ~= '' then id = v end
  end)
  if not ok then id = false end
  if key then idCache[key] = id end
  return id or nil
end

function M.find(dir)
  dir = dir or importer.IMPORT_DIR
  local out, seen = {}, {}
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
  for _, name in ipairs(subFolders(dir)) do
    if not seen[name] and not ignored(name) then
      seen[name] = true
      out[#out + 1] = { name = name, kind = 'folder', path = dir .. name }
    end
  end
  table.sort(out, function(a, b) return a.name < b.name end)
  local keep, sameAs = {}, {}           -- (sameAs[p]: the pack p is left out for)
  for _, p in ipairs(out) do
    local k = packKey(p.name)
    if not keep[k] or (keep[k].kind == 'folder' and p.kind == 'zip') then keep[k] = p end
  end
  for _, p in ipairs(out) do
    local k = keep[packKey(p.name)]
    if k ~= p then sameAs[p] = k end
  end
  -- (then by manifest id, a folder against the zips: only when a folder has one, so a folder-less import folder
  -- opens no zip here)
  local folders = {}
  for _, p in ipairs(out) do
    if p.kind == 'folder' and not sameAs[p] then
      local id = manifestId(p)
      if id then folders[id] = p end
    end
  end
  if next(folders) then
    for _, p in ipairs(out) do
      if p.kind == 'zip' and not sameAs[p] then
        local f = folders[manifestId(p) or '']
        if f and not sameAs[f] then sameAs[f] = p end
      end
    end
  end
  local one = {}
  for _, p in ipairs(out) do
    if not sameAs[p] then one[#one + 1] = p
    else log('I', 'earthRally', 'import: ' .. p.name .. ' left out: the same pack as ' .. sameAs[p].name) end
  end
  return one
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

-- (each rally a manifest describes: { spec, base, round, roundRules }, a round's own rally manifest read in its
-- place: the round's id, name and dates fill what that manifest leaves out, and the round's rules sit between the
-- season's and the rally manifest's)
local function rallySpecs(src, m)
  if m.kind ~= 'season' then return { { spec = m.data, base = '' } } end
  local out = {}
  for i, r in ipairs(type(m.data.rounds) == 'table' and m.data.rounds or {}) do
    local one = { spec = r, base = '', round = tonumber(r.round) or i }
    if type(r) == 'table' and r.rally then
      local rel = join('', r.rally)
      local data = rel and decode(src.read(rel))
      if data then
        for _, k in ipairs({ 'id', 'name', 'dates' }) do if data[k] == nil then data[k] = r[k] end end
        one.spec, one.base, one.manifest, one.roundRules = data, dirOf(rel), rel, r.rules
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
        if rel and not (k == 'map' and m.kind == 'stage' and type(r.spec.line) == 'table') then out[#out + 1] = rel end
      end
    end
  end
  return out
end

-- A folder pack's fingerprint: its manifest and every file it names, each to the byte.
local function folderFingerprint(src, named)
  local parts = {}
  for _, rel in ipairs(named) do
    local s = src.readBytes(rel)
    parts[#parts + 1] = rel .. '=' .. (s and importer._fingerprint(s) or 'missing')
  end
  return importer._fingerprint(table.concat(parts, '\n'))
end

-- The cheap test before that: every named file's size and modification time (statOf), or nil when the game cannot
-- give them (then only the fingerprint can say).
local function folderStat(src, named)
  local parts = {}
  for _, rel in ipairs(named) do
    local p = src.path(rel)
    local st
    if FS:fileExists(p) then
      st = statOf(p)
      if not st then return nil end        -- (the game gives no stat for it: the bytes decide)
    else
      st = 'missing'
    end
    parts[#parts + 1] = rel .. '=' .. st
  end
  return table.concat(parts, '|')
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
-- Second answer (1.7.0, the full rally): the stops between passes, from the event file only, else nil --
--   { { after = n (the stop follows itinerary[n]), kind = 'service' | 'overnight', name, label }... }
-- A service sits where the itinerary has a SVC_IN / SVC_OUT row, or a row whose control is a `service` entry's (one
-- of "3B-3C"'s controls, or "RZ1" where the services are on refuel-zone controls); an overnight is a change of day
-- between two passes. Rows after a pass already listed (a class's own copy of the running order) add nothing.
local function stopsOf(evFile, rows)
  local svcControls = {}
  for _, e in ipairs(type(evFile.service) == 'table' and evFile.service or {}) do
    if type(e) == 'table' and e.type == 'service' and type(e.control) == 'string' then
      for c in e.control:gmatch('[^%-%s]+') do svcControls[c] = e end
    end
  end
  local places = {}
  for _, l in ipairs(type(evFile.locations) == 'table' and evFile.locations or {}) do
    if type(l) == 'table' and l.id then places[l.id] = l end
  end
  local function shortName(n)
    -- ("Big Park Service Area (Saturday), Town" -> "Big Park Service Area": the time card's row is short)
    n = n and (n:match('^([^,]+)') or n)
    n = n and (n:match('^(.-)%s+%(') or n)
    return n
  end
  local function placeName(row, entry)
    local id = (entry and entry.location) or row.location
    local l = id and places[id]
    return shortName(l and type(l.name) == 'string' and l.name or nil)
  end
  -- (1.7.0, the service on the map: where a stop is. Each row between two passes that names a place with a position
  -- is a candidate, ranked: the service area itself (a service entry's place, then Service Out / In), then the
  -- day's start (MTC out) and end (MTC in), then any other. An overnight takes the next morning's start first.)
  local RANK = { svcEntry = 1, SVC_OUT = 2, SVC_IN = 3, MTC_OUT = 4, PE_OUT = 4, MTC_IN = 5, PE_IN = 6 }
  local function located(id)
    local l = id and places[id]
    if l and type(l.lat) == 'number' and type(l.lon) == 'number' then return l end
    return nil
  end
  local function offer(bag, row, entry)
    if entry then
      local l = located(entry.location)
      if l then bag[#bag + 1] = { rank = RANK.svcEntry, l = l, type = 'svcEntry' } end
    end
    local l = located(row.location)
    if l then bag[#bag + 1] = { rank = RANK[row.type] or 7, l = l, type = row.type } end
  end
  local function best(bag, overnight)
    local pick = nil
    for _, c in ipairs(bag or {}) do
      local rank = c.rank
      if overnight and (c.type == 'MTC_OUT' or c.type == 'PE_OUT') then rank = 0 end
      if not pick or rank < pick.rank then pick = { rank = rank, l = c.l } end
    end
    if not pick then return nil end
    return { name = shortName(type(pick.l.name) == 'string' and pick.l.name or nil), lat = pick.l.lat,
      lon = pick.l.lon }
  end
  local stops, nSvc = {}, 0
  local count, lastDay, copy = 0, nil, false
  local bags = { [0] = {} }   -- (the candidate places after each pass, by its number; 0: before the first)
  local function lastStop() return stops[#stops] end
  for _, row in ipairs(rows) do
    if row.kind == 'SS' then
      if row.new then
        if lastDay and row.day and row.day ~= lastDay and count > 0 then
          local l = lastStop()
          if l and l.after == count then l.kind = 'overnight'
          else stops[#stops + 1] = { after = count, kind = 'overnight' } end
        end
        count, copy, lastDay = row.n, false, row.day or lastDay
        bags[count] = bags[count] or {}
      else
        copy = true
      end
    elseif not copy then
      local r = row.raw
      local entry = svcControls[tostring(r.control)]
      offer(bags[count], r, entry)
      if count > 0 and (r.type == 'SVC_IN' or r.type == 'SVC_OUT' or entry) then
        local l = lastStop()
        if not (l and l.after == count) then
          stops[#stops + 1] = { after = count, kind = 'service', name = placeName(r, entry) }
        elseif not l.name then
          l.name = placeName(r, entry)
        end
      end
    end
  end
  -- (a stop after the last pass is the finish, not a stop)
  if lastStop() and lastStop().after >= count then stops[#stops] = nil end
  for _, st in ipairs(stops) do
    st.place = best(bags[st.after], st.kind == 'overnight')
    if st.place and not st.name then st.name = st.place.name end
  end
  -- the rally's start: before the first pass, else the first service's place
  local start = best(bags[0], true)
  if not start then
    for _, st in ipairs(stops) do if st.place then start = st.place break end end
  end
  for _, st in ipairs(stops) do
    if st.kind == 'service' then
      nSvc = nSvc + 1
      st.label = 'Service ' .. string.char(64 + math.min(nSvc, 26))
    else
      st.label = 'Overnight'
    end
  end
  return stops, start
end
M._stopsOf = stopsOf

-- (the rally-loop plan: timed road sections) The rows a time-control clock starts again from: the scheduled out times
-- of a service, a regroup or a day's start. Only one standing where the full rally has a stop counts (rally.lua).
local RESET = { MTC_OUT = true, SVC_OUT = true, RGC_OUT = true, PE_OUT = true }
-- (additions 2026-11-19, B) The rows a stop is checked in at: the first of them after a pass is the stop's time control.
local CHECK_IN = { SVC_IN = true, RGC_IN = true, MTC_IN = true, PF_IN = true }

-- The itinerary's passes. With an event file, each pass also carries its schedule (nil where the file gives none):
--   date, firstCar ('YYYY-MM-DD', 'HH:MM': the first car's start of the stage, printed), latenessMin (the stage's
--   lateness time, "bogey"), targetMin (the target times of the rows from the pass before to this pass's time
--   control, added up: the road section(s) driven to it), and when a row in that stretch is a scheduled out time
--   (RESET), the last one: outDate, outAt and outTargetMin (the targets from it on). Before the first pass, the
--   first timed row stands in when no out row does: the rally's start. inType, inTargetMin: the first "in" row
--   (CHECK_IN) in the stretch before it, and the targets from the pass before up to and including it: where a stop
--   between the two is checked in, and when. startGapMin: the minutes from the time control's first car to the
--   stage's (ARA: 3), so a pass left out carries the whole of its time (rally.lua orderOf / holdOut). weather: the
--   row's stored weather (docs/rally-file.md; BeamNG.Earth's weather message), nil when the pack has none.
-- Returns the passes, the stops (stopsOf, each with the inType / inTargetMin of the stretch it is in), the start place,
-- and the timing { timezone, start = { date, time }, finish = { inType, inTargetMin } (the stretch after the last
-- pass), earlyFree = { [inType] = true } (time_rules.early_checkin_allowed) } (nil: an untimed rally, no target time
-- anywhere).
local function itineraryOf(evFile, stages, lineId, warn)
  local out, seen, rows = {}, {}, {}
  if evFile and type(evFile.itinerary) == 'table' then
    -- (the stretch since the last pass: targets added up in all, and since its last out row)
    local acc, accOut, hasT, reset, first, copy, timed = 0, 0, false, nil, nil, false, false
    local inRow = nil     -- (the stretch's check-in row: { type, min })
    local lastFc = nil    -- (the stretch's last row with a first car: { date, time } -- the stage's time control)
    local function str0(v) return type(v) == 'string' and v ~= '' and v or nil end
    local function hmMin(s)
      local h, m = tostring(s):match('^(%d+):(%d+)')
      return h and tonumber(h) * 60 + tonumber(m) or nil
    end
    -- (the time control's first car to the stage's, on the same day: a few minutes, else none)
    local function gapOf(row)
      local fc, dt = str0(row.first_car), str0(row.date)
      if not (lastFc and fc and (dt == nil or dt == lastFc.date)) then return nil end
      local a, b = hmMin(lastFc.time), hmMin(fc)
      local g = a and b and b - a
      return g and g >= 0 and g <= 15 and g or nil
    end
    -- (a row for other classes only -- a regional crew's own MTC IN beside the National regroup -- is not on our road.
    -- 'National', 'ARC National', 'national 2WD': any entry naming National keeps it)
    local function forUs(row)
      if type(row.classes) ~= 'table' or #row.classes == 0 then return true end
      for _, c in ipairs(row.classes) do
        if type(c) == 'string' and c:lower():find('%f[%a]national%f[%A]') then return true end
      end
      local names = {}
      for _, c in ipairs(row.classes) do names[#names + 1] = tostring(c) end
      warn(string.format('itinerary %s %s: for %s only, not on the National road: left out', str(row.control),
        str(row.type), table.concat(names, ', ')))
      return false
    end
    for _, row in ipairs(evFile.itinerary) do
      if type(row) == 'table' and row.type == 'SS' and row.control then
        local new = not seen[row.control]
        seen[row.control] = true
        local sid = new and lineId[row.stage]
        local lat = tonumber(row.lateness_min)
        local gap = new and gapOf(row) or nil
        if sid then
          local p = { ss = tostring(row.control), stage = sid, run = tonumber(row.run) or 1,
                      km = tonumber(row.ss_km), cancelled = false, day = tonumber(row.day),
                      powerStage = row.power_stage == true or nil,
                      date = str0(row.date), firstCar = str0(row.first_car), latenessMin = lat,
                      targetMin = hasT and acc or nil, inType = inRow and inRow.type or nil,
                      inTargetMin = inRow and inRow.min or nil, startGapMin = gap,
                      -- (E: the hour's real weather at the stage's start, tools/pack_weather.py)
                      weather = type(row.weather) == 'table' and next(row.weather) ~= nil and row.weather or nil }
          -- (before the first pass, no out row: the first timed row is the start)
          local o = reset or (#out == 0 and first) or nil
          if o then
            p.outDate, p.outAt, p.outTargetMin = o.date, o.time, o.acc
            timed = timed or o.acc ~= nil
          end
          timed = timed or p.targetMin ~= nil
          out[#out + 1] = p
          acc, accOut, hasT, reset, first, copy, inRow, lastFc = 0, 0, false, nil, nil, false, nil, nil
        elseif new then
          warn(string.format('itinerary %s "%s": no line of that name in the map', tostring(row.control),
            str(row.stage)))
          -- (its time carried to the next pass's road section: the chain goes on through it, from the last out row too;
          -- its start's gap after its time control as well)
          local add = (lat or 0) + (gap or 0)
          acc = acc + add
          -- (only onto a target already begun: a lateness alone is not a road section's time)
          if reset and add > 0 and reset.acc then reset.acc = reset.acc + add end
          if first and add > 0 and first ~= reset and first.acc then first.acc = first.acc + add end
          copy, lastFc = false, nil
        else
          copy = true
        end
        rows[#rows + 1] = { kind = 'SS', new = new, n = #out, day = tonumber(row.day) }
      elseif type(row) == 'table' then
        rows[#rows + 1] = { kind = 'other', raw = row }
        if not copy and forUs(row) then
          local t = tonumber(row.target_min)
          local fc, dt = str0(row.first_car), str0(row.date)
          if t then acc, hasT = acc + t, true end
          if reset and t then reset.acc = (reset.acc or 0) + t end
          if first and t and first ~= reset then first.acc = (first.acc or 0) + t end
          if fc and dt and RESET[row.type] then reset = { date = dt, time = fc } end
          if fc and dt and not first and #out == 0 then first = { date = dt, time = fc } end
          if fc then lastFc = { date = dt or (lastFc and lastFc.date), time = fc } end
          -- (after a pass: its first "in" row, the targets up to it -- a regroup before a service is the one checked)
          if #out > 0 and not inRow and CHECK_IN[row.type] then
            inRow = { type = row.type, min = hasT and acc or nil }
          end
        end
      end
    end
    if #out > 0 then
      local stops, start = stopsOf(evFile, rows)
      -- (a stop's out time: the out row of the stretch after it, which the pass after it carries)
      for _, st in ipairs(stops) do
        local nx = out[st.after + 1]
        if nx and nx.outAt then st.outDate, st.outAt = nx.outDate, nx.outAt end
        if nx then st.inType, st.inTargetMin = nx.inType, nx.inTargetMin end
      end
      local info = type(evFile.event) == 'table' and evFile.event or {}
      local timing = nil
      if timed and out[1].outAt then
        timing = { timezone = str0(info.timezone), start = { date = out[1].outDate, time = out[1].outAt } }
        -- (the stretch after the last pass: the finish's check-in)
        if inRow then timing.finish = { inType = inRow.type, inTargetMin = inRow.min } end
        -- (the "in" controls where early is free whatever the setting: a list of strings, beside rulesOf's numbers)
        local tr = type(evFile.time_rules) == 'table' and evFile.time_rules or {}
        if type(tr.early_checkin_allowed) == 'table' then
          for _, c in ipairs(tr.early_checkin_allowed) do
            if type(c) == 'string' then
              timing.earlyFree = timing.earlyFree or {}
              timing.earlyFree[c] = true
            end
          end
        end
      end
      return out, stops, start, timing
    end
  end
  for i, s in ipairs(stages) do
    out[i] = { ss = 'SS' .. i, stage = s.id, run = 1, km = round2(s.lengthM / 1000), cancelled = false }
  end
  return out, nil
end
M._itineraryOf = itineraryOf

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
  return { format = 1, fingerprint = fp, passes = passes }
end

-- (a stage given as points instead of a map (docs/rally-file.md, Stage): `line` [[lat, lon, alt?]...] in driving
-- order, `controls` { atc, start, ff, stop = { lat, lon } }, as importer.parse gives a map: the line one piece, each
-- control a point named for its role and the stage, which importer.build matches to the line by name)
local function lineParsed(spec, name)
  local pts = {}
  for i, p in ipairs(spec.line) do
    if type(p) ~= 'table' or type(p[1]) ~= 'number' or type(p[2]) ~= 'number' then
      return nil, string.format('line: point %d is not [lat, lon]', i)
    end
    pts[i] = { p[1], p[2] }
  end
  if #pts < 2 then return nil, 'line: fewer than two points' end
  local points, c = {}, type(spec.controls) == 'table' and spec.controls or {}
  for _, role in ipairs({ 'atc', 'start', 'ff', 'stop' }) do
    local q = c[role]
    if type(q) == 'table' and type(q.lat) == 'number' and type(q.lon) == 'number' then
      points[#points + 1] = { name = CONTROL_WORDS[role] .. ' - ' .. name, lat = q.lat, lon = q.lon }
    end
  end
  return { name = name, lines = { { name = name, pieces = { pts } } }, points = points }
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
-- { idFor(name, mapFile) -> rallyId; season = { id, name, round }?; rules = { the season's, the round's }?; fp;
-- manifest = the manifest's file }. Returns the event and its report, or nil and why.
local function makeRally(src, spec, base, ctx, kind)
  if type(spec) ~= 'table' then return nil, 'not a rally' end
  local given = type(spec.name) == 'string' and spec.name ~= '' and spec.name or nil
  local parsed, mapRel, srcFile
  if kind == 'stage' and type(spec.line) == 'table' then
    local why
    parsed, why = lineParsed(spec, given or 'Stage')
    if not parsed then return nil, why end
    srcFile = src.name .. '/' .. (ctx.manifest or 'stage.json')
  else
    mapRel = join(base, spec.map)
    if not mapRel then return nil, 'no map named' end
    local s, why, mapKind = readMap(src, mapRel)
    if not s then return nil, why end
    local okP
    okP, parsed = pcall(importer.parse, s, mapKind)
    if not okP then return nil, baseName(mapRel) .. ': ' .. tostring(parsed) end
    srcFile = src.name .. '/' .. mapRel
  end
  local name = given or importer.eventName(parsed.name, mapRel or 'Stage')
  local id = ctx.idFor(name, mapRel and baseName(mapRel))
  local okB, event, report = pcall(importer.build, parsed, id, name, srcFile)
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
  -- (rallyStops: the full rally's services and overnights, 1.7.0; nil without an event file: no full rally)
  -- (rallyStart, 1.7.0 service on the map: where the full rally starts, { name, lat, lon }, or nil)
  -- (timing, the rally-loop plan: the schedule's time zone and start, nil for an untimed rally)
  event.itinerary, event.rallyStops, event.rallyStart, event.timing = itineraryOf(evFile, event.stages, lineId, warn)
  event.dates = type(spec.dates) == 'table' and spec.dates or type(info.dates) == 'table' and info.dates or nil
  local hq = type(info.hq) == 'table' and info.hq or {}
  local place = {}
  for _, k in ipairs({ 'town', 'state' }) do if type(hq[k]) == 'string' and hq[k] ~= '' then place[#place + 1] = hq[k] end end
  event.place = #place > 0 and table.concat(place, ', ') or nil
  -- (rules from the manifests only: the season's, then the round's, then the rally's own)
  local rl = ctx.rules or {}
  event.rules = rulesOf(rl[1], rl[2], spec.rules)
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

  -- (the images the last import copied taken away first: a cover.png replaced by a cover.jpg leaves nothing behind)
  local dir = M.MEDIA_DIR .. id .. '/'
  local evPath = importer.EVENTS_DIR .. id .. '.json'
  local okO, old = pcall(function() return FS:fileExists(evPath) and jsonReadFile(evPath) or nil end)
  if okO and type(old) == 'table' and type(old.media) == 'table' then
    for _, k in ipairs(M.MEDIA) do
      local f = old.media[k]
      if type(f) == 'string' and f:sub(1, #dir) == dir and FS:fileExists(f) then pcall(FS.removeFile, FS, f) end
    end
  end
  local media = {}
  for _, k in ipairs(M.MEDIA) do
    local rel = join(base, spec[k])
    if rel then
      local ext = (rel:match('%.([%w]+)$') or 'png'):lower()
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

------------------------------------------------------------------------------------------ ids
-- Ids key the player's times (results/<rally>__<stage>.json), so an organiser's edit to a pack must not move them:
-- no id depends on a round's position, on the pack's file name alone, or on the order the folder is read in.
--   season  its manifest's `id` (when free); else the id the index has for this pack; else, for a pack gone from
--           the folder in this same scan with this season's name, that pack's (a renamed zip or folder); else a slug
--           of its name.
--   round   its own `id` (when free); else the id recorded for it: by its map's file name, else by its name (a round
--           of the last import whose map is in no round now: renamed map); else <seasonId>-<slug of its name>,
--           never an id this season gave another rally before (rounds taken out are remembered for that).
--   rally / stage pack: its `id` (when free); else the one recorded for the pack (or a renamed one); else a slug.
-- An id another import already has is warned about and replaced by a free one (x-2, x-3...).

local function slugOf(s) return type(s) == 'string' and importer.idFrom(s) or '' end
local function idOr(s, fallback)
  local id = slugOf(s)
  return id ~= '' and id or fallback
end

-- (cand, or cand-2, cand-3...: the first that taken() says is free)
local function firstFree(cand, taken)
  if not taken(cand) then return cand end
  local k = 2
  while taken(cand .. '-' .. k) do k = k + 1 end
  return cand .. '-' .. k
end

-- (a manifest's own id: itself when free; a warning and the first free id after it when not; nil when it has none,
-- or one that slugs to nothing like "!!!")
local function ownId(v, taken, what, warn)
  local id = slugOf(v)
  if id == '' then return nil end
  if not taken(id) then return id end
  local other = firstFree(id, taken)
  warn(string.format('%s id "%s" is already used by another import: this one is "%s"', what, id, other))
  return other
end

-- (the entry of a pack gone from the folder this scan that matches: the same pack under another file name. Each is
-- taken once.)
local function adopt(gone, match)
  local names = {}
  for name in pairs(gone) do names[#names + 1] = name end
  table.sort(names)
  for _, name in ipairs(names) do
    local e = gone[name]
    if not e.adopted and match(e) then
      e.adopted, e.packName = true, name
      return e
    end
  end
  return nil
end

------------------------------------------------------------------------------------------ the folder

-- (a season's rounds made, its file written. ids: importPack's { adopt(match) -> a gone pack's entry, taken(id) ->
-- whether an event file of that id is another pack's, mine(file) -> whether an event file's pack.file is this pack })
local function importSeason(src, m, index, entry, ids, fp, out)
  local d = m.data
  if type(d.name) ~= 'string' or d.name == '' then return nil, m.file .. ' has no name' end
  if type(d.rounds) ~= 'table' or #d.rounds == 0 then return nil, m.file .. ' has no rounds' end
  local function warn(w) out.warnings[#out.warnings + 1] = w end
  local nameSlug = idOr(d.name, 'season')
  local function seasonTaken(c)
    for other, e in pairs(index.packs) do if other ~= src.name and e.seasonId == c then return true end end
    return false
  end
  local sid, prev
  if slugOf(d.id) ~= '' then
    local own = slugOf(d.id)
    prev = (entry and entry.seasonId == own) and entry
      or ids.adopt(function(e) return e.seasonId == own end) or entry
    sid = ownId(d.id, seasonTaken, 'season', warn)
  else
    prev = (entry and entry.seasonId) and entry
      or ids.adopt(function(e) return e.seasonId ~= nil and e.nameSlug == nameSlug end)
    sid = prev and prev.seasonId
    if not sid or seasonTaken(sid) then sid = firstFree(nameSlug, seasonTaken) end
  end
  local season = { format = 1, id = sid, name = d.name, championship = d.championship, rounds = {},
    standings = boards.standingsRules({ standings = d.standings }) }

  -- round ids: recorded ones by map first (for every round, before any is given out), then by name. A round's map
  -- is its path inside the pack, lower case ('rounds/01/map.kml'): a bare file name is the same for a pack with a
  -- map.kml in every round's folder, and would hand the ids out by position. A round recorded before paths were (a
  -- bare file name) is matched by its file name when only one round now has that file name.
  local specs = rallySpecs(src, m)
  local prevRounds = prev and type(prev.rounds) == 'table' and prev.rounds or {}
  local used, claimed, byMap, mapsNow, baseCount = {}, {}, {}, {}, {}
  local function mapOf(r)
    local rel = type(r.spec) == 'table' and join(r.base, r.spec.map)
    return rel and rel:lower() or nil
  end
  for _, r in ipairs(specs) do
    local mf = mapOf(r)
    if mf then
      mapsNow[mf] = true
      baseCount[baseName(mf)] = (baseCount[baseName(mf)] or 0) + 1
    end
  end
  local function sameMap(pr, mf)
    if not (pr.map and mf) then return false end
    if pr.map == mf then return true end
    return not pr.map:find('/', 1, true) and pr.map == baseName(mf) and baseCount[pr.map] == 1
  end
  -- (two passes: the map and the name's slug both, then the map alone: two rounds on one map each keep their own)
  for pass = 1, 2 do
    for i, r in ipairs(specs) do
      local mf, want = mapOf(r), type(r.spec) == 'table' and slugOf(r.spec.name) or ''
      if not byMap[i] then
        for _, pr in ipairs(prevRounds) do
          if not claimed[pr.id] and sameMap(pr, mf) and (pass == 2 or (want ~= '' and pr.slug == want)) then
            claimed[pr.id], byMap[i] = true, pr
            break
          end
        end
      end
    end
  end
  local function roundTaken(c) return used[c] or importer.idTaken(index, c, nil, src.name) or ids.taken(c) end
  local function everGiven(c)
    for _, pr in ipairs(prevRounds) do if pr.id == c then return true end end
    return false
  end
  local function roundId(i, r, name)
    local id = ownId(r.spec.id, roundTaken, 'round ' .. r.round, warn)
    if id then return id end
    local slug = slugOf(name)
    local hit = byMap[i]
    if not hit and slug ~= '' then
      for _, pr in ipairs(prevRounds) do
        if pr.slug == slug and not claimed[pr.id] and not pr.gone and not (pr.map and mapsNow[pr.map]) then
          hit = pr
          break
        end
      end
    end
    if hit and not roundTaken(hit.id) then
      claimed[hit.id] = true
      return hit.id
    end
    return firstFree(sid .. '-' .. (slug ~= '' and slug or 'round'),
      function(c) return roundTaken(c) or everGiven(c) end)
  end

  local roundsOut, seenRound = {}, {}
  for i, r in ipairs(specs) do
    local label = 'round ' .. r.round
    if seenRound[r.round] then
      warn(label .. ' is listed twice: the second left out')
    elseif r.why then
      warn(label .. ': ' .. r.why)
    else
      seenRound[r.round] = true
      local given
      local ev, rep = makeRally(src, r.spec, r.base, {
        idFor = function(name)
          local id = roundId(i, r, name)
          used[id] = true
          given = { id = id, map = mapOf(r), slug = slugOf(name) }
          return id
        end,
        season = { id = sid, name = d.name, round = r.round }, rules = { d.rules, r.roundRules }, fp = fp,
        manifest = r.manifest }, 'rally')
      if given then roundsOut[#roundsOut + 1] = given end
      if ev then
        season.rounds[#season.rounds + 1] = ev.id
        out.rallies[#out.rallies + 1] = { id = ev.id, name = ev.name, stages = #ev.stages, report = rep }
      else
        warn(label .. ': ' .. tostring(rep))
      end
    end
  end
  -- (every id this season has given, kept: one whose round has gone is never handed to another rally)
  for _, pr in ipairs(prevRounds) do
    if not used[pr.id] then roundsOut[#roundsOut + 1] = { id = pr.id, map = pr.map, slug = pr.slug, gone = true } end
  end
  out.rounds = roundsOut
  if #season.rounds == 0 then return nil, out.warnings[1] or 'no rounds could be read' end
  ensureDir(M.SEASONS_DIR)
  jsonWriteFile(M.SEASONS_DIR .. sid .. '.json', season, true)
  -- the season's id changed (its manifest given one, or another): the old season file goes, or Home would show a
  -- second season of the same rallies. Not while another pack has that id.
  for _, old in ipairs({ entry or false, prev or false }) do
    local oid = old and old.seasonId or nil
    if oid and oid ~= sid and not seasonTaken(oid) then
      local f = M.SEASONS_DIR .. oid .. '.json'
      if FS:fileExists(f) then pcall(FS.removeFile, FS, f) end
    end
  end
  -- the rallies the season had at its last import that it no longer has (a round taken out, one that could not be
  -- read this time, or every round's id changed with the season's): retired, so Home does not show them as rallies
  -- of their own. The event file and the times driven on it stay; a round put back under its id is written afresh,
  -- not retired. Only this pack's own files (or those of the pack it was found to be under its old name): an event
  -- file another pack or a loose map has written since is theirs, and left alone.
  local now, retired = {}, {}
  for _, id in ipairs(season.rounds) do now[id] = true end
  for _, old in ipairs({ entry or false, prev or false }) do
    for _, id in ipairs(old and old.eventIds or {}) do
      if not now[id] and not retired[id] then
        retired[id] = true
        local f = importer.EVENTS_DIR .. id .. '.json'
        local okR, ev = pcall(function() return FS:fileExists(f) and jsonReadFile(f) or nil end)
        if okR and type(ev) == 'table' and type(ev.retired) ~= 'table' and type(ev.pack) == 'table' and
          ids.mine(ev.pack.file) then
          ev.retired = { season = sid, date = os.date('!%Y-%m-%dT%H:%M:%SZ') }
          jsonWriteFile(f, ev, true)
        end
      end
    end
  end
  out.seasonId, out.name, out.nameSlug = sid, d.name, nameSlug
  return true
end

-- (one pack looked at: nil when it is unchanged, else what happened; and whether the index changed)
-- (1.7.0: the event file's services read too) a pack last imported by an older reader -- or by an older Earth Rally
-- sharing the user folder -- is imported again, whatever its fingerprint. Kept per pack, and set only by an import
-- that went through.
M.READER = 4      -- (4: the schedule read too, the rally-loop plan)
local function importPack(p, index, force, gone)
  local entry = index.packs[p.name]
  if entry and entry.reader ~= M.READER then force = true end
  -- (the gone pack this one is found to be under a new name: its ids are this pack's to take, and kept if this
  -- import then fails)
  local adopted = nil
  local function adoptOne(match)
    local e = adopt(gone, match)
    if e then adopted = e end
    return e
  end
  local function hasId(e, id)
    for _, x in ipairs(e and e.eventIds or {}) do if x == id then return true end end
    for _, r in ipairs(e and type(e.rounds) == 'table' and e.rounds or {}) do if r.id == id then return true end end
    return false
  end
  -- (an id whose event file is already another pack's, or a loose map's, is taken: a pack gone from the folder
  -- keeps its rallies but leaves the index, so the index alone would let a new pack of the same slug write over
  -- them. The ids this pack's index entry has, and the adopted pack's, are its own whatever their files say.)
  local owners = {}
  local function ownedElsewhere(id)
    if owners[id] == nil then
      local f = importer.EVENTS_DIR .. id .. '.json'
      local okO, ev = pcall(function() return FS:fileExists(f) and jsonReadFile(f) or nil end)
      owners[id] = (okO and type(ev) == 'table') and (type(ev.pack) == 'table' and tostring(ev.pack.file) or true)
        or false
    end
    local o = owners[id]
    if o == false or o == p.name then return false end
    return not (hasId(entry, id) or (adopted and hasId(adopted, id)))
  end
  -- (whether an event file written by this pack name is this pack's: its own, or the adopted pack's old name)
  local function mine(file)
    return file ~= nil and (file == p.name or (adopted ~= nil and file == adopted.packName))
  end
  local ids = { adopt = adoptOne, taken = ownedElsewhere, mine = mine }
  local fp, st = nil, nil
  if p.kind == 'zip' then
    -- (size and time first: hashing a zip of images byte by byte in Lua is what makes a start slow)
    st = statOf(p.path)
    if not force and entry and st and entry.stat == st then return nil end
    local bytes = readBytes(p.path)
    if not bytes then return nil end
    fp = importer._fingerprint(bytes)
    if not force and entry and entry.fingerprint == fp then
      entry.stat = st                                -- (touched, not changed)
      return nil, st ~= nil
    end
  end
  local src, why
  if p.kind == 'zip' then src, why = zipSource(p.path, p.name) else src = folderSource(p.path, p.name) end
  local function fail(w, f)
    -- (told once, until it changes; the ids it had kept for when it is put right: its own, or those of the pack it
    -- was found to be under its old name)
    local keep = entry or {}
    if not (keep.seasonId or keep.eventIds) and adopted then keep = adopted end
    index.packs[p.name] = { reader = M.READER, fingerprint = f or fp or ('failed:' .. w), stat = st, failed = true,
      seasonId = keep.seasonId, eventIds = keep.eventIds, rounds = keep.rounds, nameSlug = keep.nameSlug,
      kind = keep.kind }
    log('W', 'earthRally', 'import ' .. p.name .. ': ' .. w)
    return { file = p.name, ok = false, why = w }
  end
  if not src then return fail(why), true end
  local touched = false
  local ok, res = pcall(function()
    local m, mwhy = M.manifest(src)
    if p.kind == 'folder' then
      if m then
        local named = namedFiles(src, m)
        st = folderStat(src, named)
        if not force and entry and st and entry.stat == st then return 'same' end
        fp = folderFingerprint(src, named)
      else
        fp = 'none:' .. table.concat(src.rootJson(), '|')
      end
      if not force and entry and entry.fingerprint == fp then
        if st and entry.stat ~= st then entry.stat, touched = st, true end
        return 'same'
      end
    end
    if not m then return fail(mwhy, fp) end
    local out = { rallies = {}, warnings = {}, kind = m.kind }
    if m.kind == 'season' then
      local okS, swhy = importSeason(src, m, index, entry, ids, fp, out)
      if not okS then return fail(swhy, fp) end
    else
      if not m.data.map and not (m.kind == 'stage' and type(m.data.line) == 'table') then
        return fail(m.file .. ' names no map', fp)
      end
      local function warn(w) out.warnings[#out.warnings + 1] = w end
      local function taken(c) return importer.idTaken(index, c, nil, p.name) or ownedElsewhere(c) end
      local ev, rep = makeRally(src, m.data, '', { fp = fp, manifest = m.file,
        idFor = function(name)
          -- (a renamed pack with its id in its manifest is the gone pack of the same kind that had that id)
          local own = slugOf(m.data.id)
          if own ~= '' and not (entry and entry.eventIds) then
            adoptOne(function(e) return e.kind == m.kind and hasId(e, own) end)
          end
          local id = ownId(m.data.id, taken, m.kind, warn)
          if id then return id end
          local slug = idOr(name, m.kind)
          local prev = (entry and entry.eventIds) and entry
            or adoptOne(function(e) return e.kind == m.kind and e.nameSlug == slug and e.eventIds ~= nil end)
          local kept = prev and prev.eventIds and prev.eventIds[1]
          if kept and not taken(kept) then return kept end
          return firstFree(slug, taken)
        end }, m.kind)
      if not ev then return fail(tostring(rep), fp) end
      out.rallies[1] = { id = ev.id, name = ev.name, stages = #ev.stages, report = rep }
      out.name, out.nameSlug = ev.name, idOr(ev.name, m.kind)
    end
    return out
  end)
  src.close()
  if not ok then return fail(tostring(res), fp), true end
  if res == 'same' then return nil, touched end
  if res.ok == false then return res, true end

  local ids, stages = {}, 0
  for i, r in ipairs(res.rallies) do
    ids[i], stages = r.id, stages + r.stages
    importer.lastReports[r.id] = { file = p.name, lines = importer.reportLines(r.report) }
    for _, w in ipairs(r.report.warnings) do res.warnings[#res.warnings + 1] = r.name .. ': ' .. w end
  end
  index.packs[p.name] = { reader = M.READER, fingerprint = fp, stat = st, kind = res.kind, seasonId = res.seasonId, eventIds = ids,
                          rounds = res.rounds, nameSlug = res.nameSlug, date = os.date('!%Y-%m-%dT%H:%M:%SZ') }
  log('I', 'earthRally', string.format('imported %s: %s, %d rall%s, %d stages', p.name, tostring(res.name), #ids,
    #ids == 1 and 'y' or 'ies', stages))
  for _, w in ipairs(res.warnings) do log('W', 'earthRally', '  ' .. w) end
  return { file = p.name, ok = true, name = res.name, eventId = ids[1], seasonId = res.seasonId, rallies = #ids,
           stages = stages, warnings = res.warnings }, true
end

-- Every pack in the import folder imported when new or changed (every one with force); packs taken out forgotten,
-- their rallies kept. index: importer's (its .packs kept here). Returns entries in importer.scan's shape, plus
-- rallies, seasonId and warnings; and whether the index changed with nothing to report (a file only touched).
function M.scan(index, force)
  index.packs = index.packs or {}
  local found, seen = M.find(), {}
  for _, p in ipairs(found) do seen[p.name] = true end
  -- (packs gone from the folder leave the index before any id is given, so a pack renamed since the last scan
  -- takes its old ids instead of their "-2")
  local gone, goneNames = {}, {}
  for name, e in pairs(index.packs) do
    if not seen[name] then gone[name], goneNames[#goneNames + 1] = e, name end
  end
  for _, name in ipairs(goneNames) do index.packs[name] = nil end
  table.sort(goneNames)
  local done, changed = {}, #goneNames > 0
  for _, p in ipairs(found) do
    local r, ch = importPack(p, index, force, gone)
    if r then done[#done + 1] = r end
    if ch then changed = true end
  end
  for _, name in ipairs(goneNames) do
    local entry = gone[name]
    if entry.adopted then
      log('I', 'earthRally', name .. ' is gone from the import folder: a pack under another name took its ids')
    elseif not entry.failed then
      done[#done + 1] = { file = name, eventId = entry.eventIds and entry.eventIds[1], removed = true, ok = true,
                          rallies = entry.eventIds and #entry.eventIds or 1 }
      log('I', 'earthRally', name .. ' taken out of the import folder: its rallies are kept')
    end
  end
  return done, changed
end

return M
