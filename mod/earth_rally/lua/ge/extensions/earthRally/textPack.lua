-- earthRally/textPack: the hand-made rally files (docs/rally-file.md, "Hand-made files"): season.txt, rally.txt and
-- stage.txt with results.csv, weather.csv and line.csv beside them, turned into the same tables the JSON files give
-- pack.lua (a manifest, an event file, a results file), so everything after that is the JSON packs' own code.
--
-- It takes whatever it can make sense of and says what it did: each thing worth telling is a problem
--   { file, line, text (the line as written), what, fix, level = 'problem' | 'unused' }
-- and a file is refused only when nothing usable is left. Pure Lua: the pack is reached through `src` (pack.lua's
-- folder or zip source, with list()) and `ctx.parseMap(rel)`.
local R = require('earthRally/textRead')

local M = {}

M.KINDS = { 'season', 'rally', 'stage' }
M.MAP_EXT = { kml = true, kmz = true, gpx = true }
M.PICTURE_EXT = { png = true, jpg = true, jpeg = true }
M.FAR_KM = 300            -- a place this far from the map's stages is not where it was meant to be
M.REPORT_NAME = 'import report.txt'

------------------------------------------------------------------------------------------ the keys

local function keys(t)
  local out = {}
  for k, list in pairs(t) do
    out[k] = { label = list[1] }      -- (how a key is named to a person: its first name, never the code's)
    for i, a in ipairs(list) do out[k][i] = R.fold(a) end
  end
  return out
end

local RULE_KEYS = {
  falseStartS = { 'false start', 'false starts', 'jump start', 'false start penalty' },
  lateSPerMin = { 'late', 'late penalty', 'late check in', 'late at a time control' },
  earlySPerMin = { 'early', 'early penalty', 'early check in', 'early at a time control' },
  earlyFree = { 'early is free at', 'early free at', 'early allowed at', 'early check in allowed at', 'early ok at' },
  maxLatenessMin = { 'max lateness', 'maximum lateness', 'max late', 'lateness limit' },
  startIntervalMin = { 'start interval', 'interval', 'start gap', 'starting interval' },
}
local function with(t)
  local out = {}
  for k, v in pairs(RULE_KEYS) do out[k] = v end
  for k, v in pairs(t) do out[k] = v end
  return keys(out)
end

local PICTURES = { cover = { 'cover', 'cover picture', 'cover image', 'card' }, logo = { 'logo' },
  photo = { 'photo', 'banner', 'picture', 'image', 'header' } }

M.RALLY_KEYS = with({
  name = { 'rally', 'name', 'title', 'rally name', 'event name' },
  map = { 'map', 'maps', 'map file', 'stage map', 'kml', 'gpx', 'kmz' },
  dates = { 'dates', 'date', 'when' },
  town = { 'town', 'city', 'hq', 'headquarters', 'venue' },
  timezone = { 'time zone', 'timezone', 'tz', 'zone' },
  id = { 'id', 'rally id' },
  cover = PICTURES.cover, logo = PICTURES.logo, photo = PICTURES.photo,
  results = { 'results', 'result', 'results file' },
  weather = { 'weather', 'weather file' },
  place = { 'place', 'location' },
  at = { 'at', 'position', 'pos', 'gps', 'coords', 'coordinates', 'lat lon', 'lat long', 'latlng' },
  area = { 'area', 'service area', 'bounds', 'bounding box', 'box', 'polygon' },
  order = { 'running order', 'order', 'itinerary', 'schedule', 'route', 'stage order', 'run order', 'stages' },
})
M.SEASON_KEYS = with({
  name = { 'season', 'name', 'title', 'season name' },
  championship = { 'championship', 'series', 'subtitle' },
  id = { 'id', 'season id' },
  rounds = { 'rounds', 'rallies', 'events', 'calendar' },
  points = { 'points', 'points scale', 'scoring' },
  best = { 'best rounds', 'best', 'count best', 'best of' },
  countOnly = { 'count only', 'standings for', 'only count', 'championship class' },
})
M.STAGE_KEYS = with({
  name = { 'stage', 'name', 'title', 'stage name' },
  map = { 'map', 'map file', 'kml', 'gpx', 'kmz' },
  line = { 'line', 'points', 'line file', 'track' },
  id = { 'id', 'stage id' },
  cover = PICTURES.cover, logo = PICTURES.logo, photo = PICTURES.photo,
  results = { 'results', 'result', 'results file' },
  atc = { 'atc', 'arrival control', 'time control', 'tc' },
  start = { 'start', 'start line', 'start control' },
  ff = { 'finish', 'flying finish', 'ff', 'end' },
  stop = { 'stop', 'stop control', 'stop line' },
})
local LISTS = { order = true, rounds = true }

------------------------------------------------------------------------------------------ problems

local KIND_OF      -- (kindOf, below: settings() asks it whether a "Key:" in a list is a stop)

local function problem(out, file, ln, what, fix, level)
  local text = ln and ln.raw and ln.raw:gsub('%s+#.*$', ''):gsub('%s+//.*$', '') or nil
  out[#out + 1] = { file = file, line = ln and ln.n or nil, text = text, what = what, fix = fix,
    level = level or 'problem' }
end

------------------------------------------------------------------------------------------ files in the pack

local function dirOf(rel) return rel:match('^(.*)/[^/]*$') or '' end
local function baseName(rel) return rel:match('([^/]+)$') or rel end
local function extOf(rel) return (rel:match('%.([%w]+)$') or ''):lower() end
local function join(base, rel) return base ~= '' and (base .. '/' .. rel) or rel end
-- (a name with the extension Windows hides typed again, "rally.txt.txt", and any case: its plain stem)
local function stemOf(name) return (name:lower():gsub('%.txt$', ''):gsub('%.txt$', '')) end
local function isReport(rel)
  local b = baseName(rel):lower()
  return b:find('import report', 1, true) ~= nil
end

-- (the files directly in folder `base` of the pack)
local function filesIn(all, base)
  local out = {}
  for _, rel in ipairs(all) do if dirOf(rel) == base then out[#out + 1] = rel end end
  return out
end

-- (the sub-folders directly in folder `base`)
local function foldersIn(all, base)
  local seen, out = {}, {}
  local pre = base ~= '' and (base .. '/') or ''
  for _, rel in ipairs(all) do
    if rel:sub(1, #pre) == pre then
      local sub = rel:sub(#pre + 1):match('^([^/]+)/')
      if sub and not seen[sub] and sub:sub(1, 1) ~= '.' and sub:lower() ~= '__macosx' then
        seen[sub] = true
        out[#out + 1] = sub
      end
    end
  end
  table.sort(out)
  return out
end

-- A file named in a .txt, found in folder `base`: as written, in any case, with or without its extension, or the one
-- it is a slip of. `exts`: the kinds it may be (nil: any). Returns its path and, when it is not the name written, a
-- note saying what was used; or nil and why.
local function findFile(all, base, written, exts)
  written = R.unquote(written):gsub('\\', '/')
  local want = (base ~= '' and (base .. '/') or '') .. written
  local wl = want:lower()
  local here = filesIn(all, dirOf(want))
  local function okExt(rel) return not exts or exts[extOf(rel)] end
  for _, rel in ipairs(here) do if rel == want then return rel end end
  for _, rel in ipairs(here) do if rel:lower() == wl and okExt(rel) then return rel end end
  for _, rel in ipairs(here) do
    -- (the extension left off, or typed twice)
    local s = baseName(rel):lower()
    local w = baseName(wl)
    if okExt(rel) and (s:gsub('%.[^.]+$', '') == w or s == w .. '.' .. extOf(rel) or s .. '.txt' == w
      or s:gsub('%.[^.]+$', ''):gsub('%.[^.]+$', '') == w:gsub('%.[^.]+$', '')) then
      return rel, string.format('used %s', baseName(rel))
    end
  end
  local names = {}
  for _, rel in ipairs(here) do if okExt(rel) then names[#names + 1] = baseName(rel) end end
  local hit = R.closest(baseName(written), names)
  if hit then return join(dirOf(want), hit), string.format('used %s, the nearest name in the folder', hit) end
  return nil, string.format('there is no %s in the folder', baseName(written))
end

-- (the files of a kind in folder `base`: 'map' -> its maps)
local function ofKind(all, base, exts)
  local out = {}
  for _, rel in ipairs(filesIn(all, base)) do if exts[extOf(rel)] and not isReport(rel) then out[#out + 1] = rel end end
  return out
end

------------------------------------------------------------------------------------------ the manifest

-- The text manifest at the pack's root, when there is one: { kind, file }. A file named season / rally / stage .txt
-- (any case, "rally.txt.txt"), else any other .txt at the root whose first setting is "Season:", "Rally:" or "Stage:".
-- Second answer: the others found, when more than one is there (the pack is then refused, naming them).
function M.find(all)
  local named, others = {}, {}
  for _, rel in ipairs(filesIn(all, '')) do
    if extOf(rel) == 'txt' and not isReport(rel) then
      local stem = stemOf(baseName(rel))
      local kind = nil
      for _, k in ipairs(M.KINDS) do if stem == k then kind = k end end
      if kind then named[#named + 1] = { kind = kind, file = rel }
      else others[#others + 1] = rel end
    end
  end
  return named, others
end

-- (the first setting of a text, for a manifest not named season / rally / stage.txt)
function M.firstKey(text)
  for _, ln in ipairs(R.lines(text)) do
    if ln.text ~= '' then
      for _, kind in ipairs(M.KINDS) do
        local k = R.fold(ln.text:match('^([^:=]+)[:=]') or '')
        if k == kind then return kind end
      end
      return nil
    end
  end
  return nil
end

------------------------------------------------------------------------------------------ reading a .txt

-- A .txt's settings: { key -> { value, ln } } (the first of each, and later ones noted), the lists ("Running order:",
-- "Rounds:") as their lines, the places, and what was skipped.
local function settings(text, file, keyset, probs)
  local out, lists, places = {}, {}, {}
  local inList, place = nil, nil
  for _, ln in ipairs(R.lines(text)) do
    if ln.text ~= '' then
      local k, v, written = nil, nil, nil
      -- (inside a list, only a "Key:" with a colon ends it: a stage may be called "Map Hill")
      if inList then
        local head = ln.text:match('^([^:=]-)%s*[:=]')
        -- (only "Key:" for a whole known key, and not a stop: "Service park: X" and "Rally start: X" stay in it)
        if head and not head:find('^%d') and R.exactKey(ln.text, keyset) and select(2, KIND_OF(head)) ~= '' then
          k, v, written = R.keyValue(ln.text, keyset)
          if not k then k, v = nil, nil end
        end
        -- (no colon: a setting of two words or more, "False start 10", ends it too; one word, "Late", needs its
        -- colon after a list, as a stage may be called "Late Hill")
        if not k and not head then
          local k2, v2, w2 = R.keyValue(ln.text, keyset)
          if k2 and w2 and w2:find('%s') and not LISTS[k2] and k2 ~= 'place' and select(2, KIND_OF(w2)) ~= '' then
            k, v, written = k2, v2, w2
          end
        end
        if not k then
          lists[inList][#lists[inList] + 1] = ln
          goto continue
        end
      else
        k, v, written = R.keyValue(ln.text, keyset)
      end
      if k and LISTS[k] then
        inList, place = k, nil
        lists[k] = lists[k] or {}
        if v ~= '' then lists[k][#lists[k] + 1] = { n = ln.n, raw = ln.raw, text = v } end
      elseif k == 'place' then
        inList = nil
        place = { name = v, ln = ln }
        -- ("Place: Fernvale Park, 60.0102, -10.0451" or "... at 60.0102, -10.0451")
        local name, pos = v:match('^(.-)%s+at%s+(.+)$')
        if not name then name, pos = v:match('^([^,]-%a[^,]-),%s*(.+)$') end
        if name and pos and R.position(pos) then place.name, place.atText, place.atLn = R.trim(name), pos, ln end
        places[#places + 1] = place
      elseif k == 'at' or k == 'area' then
        inList = nil
        if not place then
          problem(probs, file, ln, string.format('"%s" is not under a Place.', written),
            'Put it on the line after "Place: <name>".')
        elseif k == 'at' then place.atText, place.atLn = v, ln
        else place.area, place.areaLn = v, ln end
      elseif k then
        inList = nil
        if out[k] then
          problem(probs, file, ln, string.format('%s is set twice: the first one, on line %d, is used.', written,
            out[k].ln.n), 'Delete one of them.')
        else
          out[k] = { value = R.unquote(v), ln = ln, written = written }
        end
      else
        inList = nil
        local near = v and R.closestKey(v, keyset)
        if near then
          local nice = keyset[near].label or near
          problem(probs, file, ln, string.format('"%s" is not a setting the game knows. Did you mean "%s"?', v, nice),
            'Fix the spelling. Until then this line is skipped.')
        else
          problem(probs, file, ln, v and 'Not something the game uses: skipped.'
            or "The game can't tell what this line is: skipped.", nil, 'unused')
        end
      end
    end
    ::continue::
  end
  return out, lists, places
end

-- The rules a .txt gives, as rulesOf takes them (numbers only); and the "early is free at" stops as row types.
local STOP_WORDS     -- (filled below: the running order's words for each kind of row)
local function rulesFrom(s, file, probs)
  local rules, any = {}, false
  local function num(k)
    local e = s[k]
    if not e then return end
    local ns = R.numbers(e.value)
    if #ns == 0 then
      problem(probs, file, e.ln, string.format('"%s" has no number in it.', e.value), 'Write it as a number: 10')
    else
      rules[k], any = ns[1], true
    end
  end
  num('lateSPerMin') num('earlySPerMin') num('maxLatenessMin') num('startIntervalMin')
  if s.falseStartS then
    local ns = R.numbers(s.falseStartS.value)
    if #ns == 0 then
      problem(probs, file, s.falseStartS.ln, string.format('"%s" has no number in it.', s.falseStartS.value),
        'Write the penalties in seconds: 10, 60, 180')
    else
      rules.falseStartS, any = ns, true
    end
  end
  local free = nil
  if s.earlyFree then
    free = {}
    for part in (s.earlyFree.value .. ','):gmatch('([^,;/]+)[,;/]') do
      local t = STOP_WORDS(R.trim(part))
      if t then free[#free + 1] = t
      elseif R.trim(part) ~= '' then
        problem(probs, file, s.earlyFree.ln, string.format('"%s" is not a kind of stop.', R.trim(part)),
          'Use MTC in, Regroup in, Service in or Parc ferme in.')
      end
    end
  end
  return any and rules or nil, free
end

------------------------------------------------------------------------------------------ the running order

-- (each kind of row and the words people use for it, longest first so "service in" is not taken for "service")
local KINDS = {
  { 'SVC_IN', { 'service in', 'svc in', 'into service', 'service arrival' } },
  { 'SVC_OUT', { 'service out', 'svc out', 'out of service', 'service departure', 'leave service' } },
  { 'RGC_IN', { 'regroup in', 'regroup arrival', 'regroup' } },
  { 'RGC_OUT', { 'regroup out', 'regroup departure' } },
  { 'MTC_IN', { 'mtc in', 'overnight in', 'overnight', 'finish', 'rally finish', 'end of day', 'end' } },
  { 'MTC_OUT', { 'mtc out', 'overnight out', 'start', 'rally start', 'restart', 'leave', 'depart' } },
  { 'PF_IN', { 'parc ferme in', 'parc ferme', 'pf in' } },
  { 'PE_OUT', { 'parc ferme out', 'pf out' } },
  { 'REFUEL', { 'refuel', 'refuelling', 'refueling', 'refuel zone', 'fuel' } },
  { 'SVC_IN', { 'service', 'svc', 'service park' } },
  { 'ATC', { 'atc', 'tc', 'time control', 'arrival control', 'arrival time control' } },
}
local KIND_WORDS = {}
for _, k in ipairs(KINDS) do
  for _, w in ipairs(k[2]) do KIND_WORDS[#KIND_WORDS + 1] = { type = k[1], words = w } end
end
table.sort(KIND_WORDS, function(a, b) return #a.words > #b.words end)

-- (the kind of row a phrase starts with, and the rest: "Service in at Fernvale Park" -> SVC_IN, "Fernvale Park")
local function kindOf(text)
  local t = text:gsub('\195\169', 'e'):gsub('\195\137', 'E'):gsub('\195\168', 'e'):gsub('%s+', ' ')
  local lower = t:lower()
  for _, kw in ipairs(KIND_WORDS) do
    local w = kw.words
    if lower:sub(1, #w) == w and (#lower == #w or lower:sub(#w + 1, #w + 1):match('[%s:,%-@]')) then
      local rest = R.trim(t:sub(#w + 1)):gsub('^[:,%-@]%s*', ''):gsub('^[Aa][Tt]%s+', '')
      return kw.type, R.trim(rest)
    end
  end
  return nil
end
STOP_WORDS = function(s)
  local t, rest = kindOf(s)
  if t and rest == '' and t ~= 'ATC' then return t end
  return nil
end
M._kindOf = kindOf
KIND_OF = kindOf

-- (a running order line's own pieces, taken off it: the time at its front, its control code, its length, lateness,
-- minutes, power stage and "only" classes; what is left is the stage or the stop)
local function pieces(text)
  local p = {}
  -- the time at the front, first: "8h23" is a time there, not 8 hours 23
  do
    local a, rest = R.trim(text):match('^(%S+)%s*(.*)$')
    if a and a:find('%d') and (a:find('[:%.hH]') or a:lower():find('[ap]m$')) then
      local c = R.clock(a)
      local b, rest2 = rest:match('^(%S+)%s*(.*)$')
      if not c and b and b:lower():match('^[ap]%.?m%.?$') then c, rest = R.clock(a .. ' ' .. b), rest2 end
      if c then p.time, text = c, rest end
    end
  end
  local t = ' ' .. text .. ' '
  local only = t:match('%s[Oo][Nn][Ll][Yy]%s+(.-)%s*$')
  if only then
    p.classes = {}
    for c in (only:gsub('%s+and%s+', ',') .. ','):gmatch('([^,/&]+)[,/&]') do
      if R.trim(c) ~= '' then p.classes[#p.classes + 1] = R.trim(c) end
    end
    t = t:gsub('%s[Oo][Nn][Ll][Yy]%s+.-%s*$', ' ')
  end
  local ps = t:find('%s[Pp][Oo][Ww][Ee][Rr]%s*[Ss][Tt][Aa][Gg][Ee]%s')
  if ps then p.power = true t = t:gsub('%s[Pp][Oo][Ww][Ee][Rr]%s*[Ss][Tt][Aa][Gg][Ee]%s', ' ') end
  if t:find('%s[Cc][Aa][Nn][Cc][Ee][Ll]+[Ee][Dd]%s') then
    p.cancelled = true
    t = t:gsub('%s[Cc][Aa][Nn][Cc][Ee][Ll]+[Ee][Dd]%s', ' ')
  end
  local late = t:match('%s[Ll][Aa][Tt][Ee]%a*%s*:?%s*(%d+[%.,]?%d*%s*[%a]*)%s')
  if late then
    p.late = R.minutes((late:gsub('%s*[Mm]%a*$', '')))
    t = t:gsub('%s[Ll][Aa][Tt][Ee]%a*%s*:?%s*%d+[%.,]?%d*%s*[%a]*%s', ' ', 1)
  end
  local km = t:match('%s(%d+[%.,]?%d*)%s*[Kk][Mm]%s')
  if km then p.km = R.number(km) t = t:gsub('%s%d+[%.,]?%d*%s*[Kk][Mm]%s', ' ', 1) end
  -- (minutes: "20 min", "1 h 30", "1h30 min", "+20")
  -- ("1 h 30", "1h30 min": an h straight after the hours, so "Route 7 Hill 2" is a name)
  local h, m = t:match('%s(%d+)%s*[Hh]%s*(%d%d?)%s*[Mm]?[Ii]?[Nn]?%a*%s')
  if h then
    p.target = tonumber(h) * 60 + tonumber(m)
    t = t:gsub('%s%d+%s*[Hh]%s*%d%d?%s*[Mm]?[Ii]?[Nn]?%a*%s', ' ', 1)
  else
    local mins = t:match('%s%+?(%d+[%.,]?%d*)%s*[Mm][Ii][Nn]%a*%s') or t:match('%s%+(%d+)%s')
    if mins then
      p.target = R.number(mins)
      t = t:gsub('%s%+?%d+[%.,]?%d*%s*[Mm][Ii][Nn]%a*%s', ' ', 1):gsub('%s%+%d+%s', ' ', 1)
    else
      local hrs = t:match('%s(%d+[%.,]?%d*)%s*[Hh]%s') or t:match('%s(%d+[%.,]?%d*)%s*[Hh][Oo][Uu][Rr][Ss]?%s')
      if hrs then
        p.target = R.number(hrs) * 60
        t = t:gsub('%s%d+[%.,]?%d*%s*[Hh]%s', ' ', 1):gsub('%s%d+[%.,]?%d*%s*[Hh][Oo][Uu][Rr][Ss]?%s', ' ', 1)
      end
    end
  end
  t = R.trim(t)
  -- the control code: TC1, TC2A, SS12, RZ1 ("SS 3" too)
  local code, rest3 = t:match('^(%a%a?%a?%a?%d+%a?)[%s:%.%-]+(.*)$')
  if not code then code = t:match('^(%a%a?%a?%a?%d+%a?)$') rest3 = '' end
  if not code then
    local ss, n, rest4 = t:match('^([Ss][Ss])%s+(%d+)[%s:%.%-]+(.*)$')
    if ss then code, rest3 = 'SS' .. n, rest4 end
  end
  p.full = t
  if code and not code:lower():match('^day') then
    p.code, t = code:upper(), R.trim(rest3)
  end
  p.rest = t:gsub('^[%-:,%.]%s*', '')
  return p
end
M._pieces = pieces

-- The running order's lines as an event file's itinerary and locations. stages: the map's line names. places: the
-- Place blocks. dates: the rally's { from, to } or nil.
local function runningOrder(list, file, stageNames, places, dates, probs)
  local rows, locs, locById = {}, {}, {}
  local foldStage = {}
  for _, name in ipairs(stageNames) do
    local f = R.fold(name)
    if foldStage[f] == nil then foldStage[f] = name end
  end
  for _, pl in ipairs(places) do
    local id = R.fold(pl.name)
    if id ~= '' and not locById[id] then
      local l = { id = id, name = pl.name, lat = pl.lat, lon = pl.lon }
      locs[#locs + 1], locById[id] = l, l
    end
  end
  local placeNames = {}
  for _, l in ipairs(locs) do placeNames[#placeNames + 1] = l.name end

  local day, date, dayGiven = 1, dates and dates.from or nil, false
  local runs, ssCount, passes, warnedDate = {}, 0, {}, false
  local function placeId(text, ln)
    local t = R.trim(text)
    if t == '' then return nil end
    local id = R.fold(t)
    if locById[id] then return id end
    local hit = R.closest(t, placeNames)
    if hit then
      problem(probs, file, ln, string.format('No place called "%s". Read as "%s".', t, hit),
        'If that\'s right, fix the spelling to stop this message.')
      return R.fold(hit)
    end
    local l = { id = id, name = t }
    locs[#locs + 1], locById[id] = l, l
    placeNames[#placeNames + 1] = t
    problem(probs, file, ln, string.format('"%s" is not one of your places, so the game doesn\'t know where it is.', t),
      string.format('Add "Place: %s" with its position (At: lat, lon).', t))
    return id
  end
  local function stageMatch(text)
    local f = R.fold(text)
    if foldStage[f] then return foldStage[f] end
    -- ("SS3 - Kilo Hill", "Stage 3: Kilo Hill", "Special stage Kilo Hill")
    local t2 = text:gsub('^[Ss]pecial%s+[Ss]tage%s*', ''):gsub('^[Ss][Tt][Aa][Gg][Ee]%s*%d*[%s:%.%-]*', '')
      :gsub('^[Ss][Ss]%s*%d*[%s:%.%-]*', '')
    if foldStage[R.fold(t2)] then return foldStage[R.fold(t2)] end
    return nil, t2
  end
  local function addRow(row, p, ln)
    row.day, row.date = day, date
    if p.time then
      row.first_car = p.time
      if not date and not warnedDate then
        warnedDate = true
        problem(probs, file, ln, 'This line has a time, but the rally has no date, so the times are not used.',
          'Add "Dates: 7 Feb 2031" (or "Day 1  7 Feb 2031" in the running order).')
      end
    end
    if p.classes then row.classes = p.classes end
    rows[#rows + 1] = row
  end

  for _, ln in ipairs(list) do
    local text = ln.text
    -- a new day: "Day 2", "Day 2 - 8 Feb 2031", or a date on its own
    local dn, drest = text:match('^[Dd][Aa][Yy]%s*(%d+)%s*[:%-,%.]?%s*(.-)%s*$')
    -- (a stage first: "Mayfield 2" is a stage, not a day)
    local isStage = foldStage[R.fold(text)] or stageMatch(text)
    if isStage then dn = nil end
    local whole = not dn and not isStage and text:find('%d') and R.date(text, dates and dates.from:sub(1, 4))
    if dn or whole then
      local was = day
      day = dn and tonumber(dn) or (dayGiven and day + 1 or (#rows > 0 and day + 1 or 1))
      dayGiven = true
      local d = whole
      if dn and drest ~= '' then
        local why, either
        d, why, either = R.date(drest, dates and dates.from:sub(1, 4))
        if not d then problem(probs, file, ln, (why or 'not a date') .. '.', 'Write the day as: Day 2  8 Feb 2031')
        elseif either then
          problem(probs, file, ln, string.format('"%s" could be day/month or month/day: read as %s.', drest, d),
            'Write the month as a word (8 Feb 2031) to stop this message.')
        end
      end
      if not d and dates and dates.from then d = R.addDays(dates.from, day - 1) end
      date = d or date
      if dn and day <= was and #rows > 0 then
        problem(probs, file, ln, string.format('Day %d comes after day %d.', day, was), 'Check the day numbers.')
      end
    else
      local p = pieces(text)
      local rest = p.rest
      local stage, stripped = nil, nil
      -- (a stage named as in the map first, whole: "A1 Road" is a stage, not control A1)
      stage = p.code and foldStage[R.fold(p.full)] or nil
      if stage then p.code = nil end
      if not stage and not (p.code and not p.code:match('^SS')) then stage, stripped = stageMatch(rest) end
      local kind, placeText = nil, nil
      if not stage then kind, placeText = kindOf(rest) end
      if not stage and not kind and p.code then
        kind, placeText = kindOf(p.full)
        if kind then p.code = nil end
      end
      if not stage and not kind and p.code and not p.code:match('^SS') and rest == '' then kind = 'ATC' end
      if not stage and not kind then
        -- a stage by a name it is a slip of
        local want = stripped ~= nil and stripped or rest
        local hit = want ~= '' and R.closest(want, stageNames)
        if hit then
          problem(probs, file, ln, string.format('There is no stage called "%s" in the map. Read as "%s".', want, hit),
            'If that\'s right, fix the spelling to stop this message.')
          stage = hit
        elseif (p.code and p.code:match('^SS')) or rest:lower():match('^stage') or rest:lower():match('^ss') then
          problem(probs, file, ln, string.format('There is no stage called "%s" in the map.', want),
            'Name it as its line is named in the map. Until then it is left out of the rally.')
          -- (its number still counted: SS5 stays SS5 after a stage left out)
          ssCount = p.code and tonumber(p.code:match('%d+')) or ssCount + 1
        elseif want ~= '' then
          problem(probs, file, ln, string.format('"%s" is neither a stage in the map nor a stop.', want),
            'A stage is named as in the map; a stop starts with Start, Service, Regroup, Refuel, Finish or ATC.')
        end
      end
      if stage then
        local n = p.code and tonumber(p.code:match('^SS(%d+)')) or nil
        ssCount = n or (ssCount + 1)
        local control = 'SS' .. ssCount
        if passes[control] then
          problem(probs, file, ln, string.format('%s is listed twice: the second one is left out.', control),
            'Give each stage its own SS number, or leave the numbers out.')
        else
          passes[control] = true
          runs[stage] = (runs[stage] or 0) + 1
          -- (minutes on a stage line: the time to get there, as an ATC line before it would say)
          if p.target then
            addRow({ type = 'ATC', target_min = p.target }, { classes = nil }, ln)
          end
          local row = { type = 'SS', control = control, stage = stage, run = runs[stage], ss_km = p.km,
            lateness_min = p.late, power_stage = p.power or nil }
          if p.cancelled then
            problem(probs, file, ln, '"cancelled" in the running order is not used.',
              'A stage is cancelled in results.csv: write "cancelled" in its Time.', 'unused')
          end
          addRow(row, p, ln)
        end
      elseif kind then
        local row = { type = kind, control = p.code, target_min = p.target }
        if placeText and placeText ~= '' then
          row.location = placeId(placeText, ln)
        end
        if p.km or p.late or p.power then
          problem(probs, file, ln, 'A length, lateness or "power stage" is only for a stage: not used here.', nil,
            'unused')
        end
        addRow(row, p, ln)
      end
    end
  end
  return rows, locs
end

------------------------------------------------------------------------------------------ places

local function readPlaces(places, file, probs, centre)
  for _, pl in ipairs(places) do
    if pl.name == '' then
      problem(probs, file, pl.ln, 'This place has no name.', 'Write it as: Place: Fernvale Park')
    end
    if pl.atText then
      local lat, lon, note = R.position(pl.atText)
      if not lat then
        problem(probs, file, pl.atLn, lon .. '.', 'Until then the game doesn\'t know where ' .. pl.name .. ' is.')
      else
        if note == 'swapped' then
          problem(probs, file, pl.atLn, string.format('Longitude first: read as %.6f, %.6f (%s).', lat, lon, pl.name),
            'Swap the two numbers in the file to stop this message.')
        elseif centre then
          -- (both numbers could be latitudes: the far one from the stages is the wrong way round)
          local function km(a, b) return math.sqrt(((a - centre[1]) * 111) ^ 2 + ((b - centre[2]) * 111 *
            math.cos(math.rad(centre[1]))) ^ 2) end
          if km(lat, lon) > M.FAR_KM and math.abs(lon) <= 90 and km(lon, lat) < M.FAR_KM then
            problem(probs, file, pl.atLn, string.format('This looks like longitude first. Read as %.4f, %.4f (%s).',
              lon, lat, pl.name), 'If that\'s right, swap them in the file to stop this message.')
            lat, lon = lon, lat
          elseif km(lat, lon) > M.FAR_KM then
            problem(probs, file, pl.atLn, string.format('%s is %.0f km from the stages.', pl.name, km(lat, lon)),
              'Check its position.')
          end
        end
        pl.lat, pl.lon = lat, lon
      end
    elseif pl.name ~= '' then
      problem(probs, file, pl.ln, string.format('%s has no position.', pl.name),
        'Add a line under it: At: 60.0102, -10.0451 (paste it from Google Maps).')
    end
    if pl.area then
      problem(probs, file, pl.areaLn, string.format('Service areas are not used yet: %s\'s "At" is used.', pl.name),
        nil, 'unused')
    end
  end
end

------------------------------------------------------------------------------------------ CSV files

local RESULT_COLS = {
  ss = { 'ss', 'ssno', 'ssnumber', 'control', 'stageno', 'stagenumber', 'specialstage' },
  stage = { 'stage', 'stagename', 'ssname' },
  run = { 'run', 'pass', 'loop' },
  km = { 'km', 'distance', 'length', 'sskm', 'stagekm' },
  car = { 'car', 'carno', 'carnumber', 'no', 'number', 'num', 'entry', 'entryno', 'startno', 'startnumber', 'bib' },
  driver = { 'driver', 'crew', 'drivername', 'name', 'competitor', 'pilot', 'entrant' },
  class = { 'class', 'cat', 'category', 'group' },
  championship = { 'championship', 'series', 'champ', 'cup', 'championships' },
  time = { 'time', 'stagetime', 'sstime', 'result', 'seconds' },
  notional = { 'notional', 'given' },
  cancelled = { 'cancelled', 'canceled' },
}
local NO_TIME = { dnf = true, dns = true, dsq = true, ret = true, retired = true, nt = true, notime = true,
  ['-'] = true, ['--'] = true, ['---'] = true, x = true, dq = true, exc = true, excluded = true, otl = true,
  na = true, ['n/a'] = true, missing = true }
local function yes(s) local f = R.fold(s) return f == 'yes' or f == 'y' or f == 'true' or f == '1' or f == 'x' end

-- results.csv as a results file: { stages = { { control, stage, run, km, cancelled, times = {...} }... } }.
-- passes: the rally's { control -> { stage, run, km } } (its running order, or its map's stages in order).
local function readResults(text, file, passes, stageNames, probs)
  local header, rows = R.csv(text)
  if not header then
    problem(probs, file, nil, string.format('%s is empty.', baseName(file)), 'Fill it in, or delete it.')
    return nil
  end
  local col = {}
  for k, aliases in pairs(RESULT_COLS) do col[k] = R.column(header, aliases) end
  for i, c in ipairs(header.cells) do if R.trim(c) == '#' and not col.car then col.car = i end end
  local byKey, order = {}, {}
  local said, curLn = {}, nil
  local function NOTE(what, fix) problem(probs, file, curLn, what, fix) end
  local function stageFor(ssText, stageText, runText, ln)
    curLn = ln
    local control = nil
    if ssText and ssText ~= '' then
      local n = ssText:match('(%d+)')
      control = n and ('SS' .. tonumber(n)) or nil
    end
    local pass = control and passes[control]
    local name, guessed = nil, false
    if stageText and stageText ~= '' then
      for _, s in ipairs(stageNames) do if R.fold(s) == R.fold(stageText) then name = s end end
      if not name then
        local hit = R.closest(stageText, stageNames)
        if hit then name, guessed = hit, true end
      end
      if not name and not pass then
        return nil, string.format('There is no stage called "%s" in the map.', stageText)
      end
    end
    if pass then
      if name and name ~= pass.stage then
        return nil, string.format('%s is %s in the running order, not %s.', control, pass.stage, stageText)
      end
      -- (said once a pass: a name that matches no line, or only nearly, beside an SS that does)
      if stageText and stageText ~= '' and (not name or guessed) and not said[control] then
        said[control] = true
        NOTE(string.format('%s is "%s" here and %s in the running order: %s used.', control, stageText, pass.stage,
          control), 'If they are the same stage, write it as in the running order to stop this message.')
      end
      return { control = control, stage = pass.stage, run = pass.run, km = pass.km }
    end
    if guessed then
      NOTE(string.format('No stage called "%s". Read as "%s".', stageText, name),
        'If that\'s right, fix the spelling to stop this message.')
    end
    if name then
      local run = R.number(runText or '') or 1
      for c, ps in pairs(passes) do
        if ps.stage == name and ps.run == run then return { control = c, stage = name, run = run, km = ps.km } end
      end
      return { control = control, stage = name, run = run }
    end
    if control then return nil, string.format('There is no %s in the running order.', control) end
    return nil, 'This row says neither which SS nor which stage it is.'
  end
  local function key(st) return (st.control or '') .. '|' .. st.stage .. '|' .. st.run end
  local function entry(st)
    local k = key(st)
    if not byKey[k] then
      byKey[k] = { control = st.control, stage = st.stage, run = st.run, km = st.km, cancelled = false, times = {},
        crews = {} }
      order[#order + 1] = k
    end
    return byKey[k]
  end
  local function addTime(e, cell, r, rowLn)
    local t = R.trim(cell)
    if t == '' then return end
    if R.fold(t) == 'cancelled' or R.fold(t) == 'canceled' then e.cancelled = true return end
    if NO_TIME[t:lower()] or NO_TIME[R.fold(t)] then return end
    local s, notional = R.stageTime(t)
    if not s then
      problem(probs, file, rowLn, notional .. '.', 'This crew is left out of ' .. (e.control or e.stage) ..
        "'s leaderboard.")
      return
    end
    local driver = col.driver and r.cells[col.driver] or ''
    local car = col.car and r.cells[col.car] or ''
    local who = R.fold(driver) .. '#' .. R.fold(car)
    if who ~= '#' and e.crews[who] then
      problem(probs, file, rowLn, string.format('%s has two times on %s: the first is used.',
        driver ~= '' and driver or ('Car ' .. car), e.control or e.stage), 'Delete one of them.')
      return
    end
    e.crews[who] = true
    if col.notional and yes(r.cells[col.notional] or '') then notional = true end
    e.times[#e.times + 1] = { seconds = s, driver = driver, car = car,
      class = col.class and r.cells[col.class] or nil, championship = col.championship and r.cells[col.championship]
      or nil, notional = notional or nil }
  end

  if col.time then
    if not (col.ss or col.stage) then
      problem(probs, file, { n = header.n, raw = header.raw }, 'There is no SS or Stage column.',
        'Add a column headed SS (SS1, SS2...) or Stage (the stage\'s name).')
      return nil
    end
    for _, r in ipairs(rows) do
      local ln = { n = r.n, raw = r.raw }
      local st, why = stageFor(col.ss and r.cells[col.ss], col.stage and r.cells[col.stage], col.run and
        r.cells[col.run], ln)
      if not st then
        problem(probs, file, ln, why, 'This row is left out.')
      else
        local e = entry(st)
        if col.km and not e.km then e.km = R.number(r.cells[col.km] or '') end
        if col.cancelled and yes(r.cells[col.cancelled] or '') then e.cancelled = true end
        addTime(e, r.cells[col.time] or '', r, ln)
      end
    end
  else
    -- one row per crew, a column per stage (SS1, SS2... or the stages' names)
    local stageCols = {}
    for i, c in ipairs(header.cells) do
      local n = c:match('^%s*[Ss][Ss]%s*(%d+)%s*$')
      local st = nil
      if n then
        local why
        st, why = stageFor('SS' .. n, nil, nil)
        if not st then problem(probs, file, { n = header.n, raw = header.raw }, why, 'That column is left out.') end
      else
        for _, s in ipairs(stageNames) do if R.fold(s) == R.fold(c) then st = stageFor(nil, s, nil) end end
      end
      if st then stageCols[#stageCols + 1] = { i = i, st = st } end
    end
    if #stageCols == 0 then
      problem(probs, file, { n = header.n, raw = header.raw }, 'There is no Time column, and no column per stage.',
        'Head the times column "Time", or head one column per stage SS1, SS2...')
      return nil
    end
    for _, r in ipairs(rows) do
      for _, sc in ipairs(stageCols) do addTime(entry(sc.st), r.cells[sc.i] or '', r, { n = r.n, raw = r.raw }) end
    end
  end
  local out = { stages = {} }
  for _, k in ipairs(order) do
    local e = byKey[k]
    e.crews = nil
    out.stages[#out.stages + 1] = e
  end
  return out
end

-- (weather in words: the WMO code, the cloud, and rain or snow in an hour)
local SKY = {
  { { 'clear', 'sunny', 'fine', 'clear sky' }, 0, 0 },
  { { 'mainly clear', 'mostly clear', 'mostly sunny' }, 1, 20 },
  { { 'partly cloudy', 'partly sunny', 'some cloud', 'broken cloud' }, 2, 50 },
  { { 'cloudy', 'mostly cloudy' }, 3, 85 },
  { { 'overcast', 'grey', 'gray', 'dull' }, 3, 100 },
  { { 'fog', 'foggy', 'mist', 'misty', 'freezing fog' }, 45, 100, fog = true },
  { { 'drizzle', 'light drizzle', 'damp' }, 53, 100, rain = 0.3 },
  { { 'light rain', 'showers', 'light showers', 'rain showers' }, 61, 95, rain = 0.8 },
  { { 'rain', 'raining', 'wet', 'moderate rain' }, 63, 100, rain = 2.5 },
  { { 'heavy rain', 'downpour', 'heavy showers', 'storm' }, 65, 100, rain = 8 },
  { { 'light snow', 'snow showers', 'sleet' }, 71, 100, snow = 0.2 },
  { { 'snow', 'snowing', 'moderate snow' }, 73, 100, snow = 0.6 },
  { { 'heavy snow', 'blizzard' }, 75, 100, snow = 1.5 },
  { { 'thunder', 'thunderstorm', 'thunderstorms', 'lightning' }, 95, 100, rain = 6, thunder = true },
}
local SKY_BY = {}
local SKY_NAMES = {}
for _, s in ipairs(SKY) do
  for _, w in ipairs(s[1]) do SKY_BY[R.fold(w)] = s SKY_NAMES[#SKY_NAMES + 1] = w end
end
local WX_COLS = {
  ss = { 'ss', 'ssno', 'control', 'stageno' }, stage = { 'stage', 'stagename' },
  sky = { 'sky', 'weather', 'conditions' }, cloud = { 'cloud', 'cloudpercent', 'clouds',
  'cloudcover', 'cover' }, wind = { 'wind', 'windms', 'windspeed', 'windspeedms' }, gust = { 'gust', 'gustms',
  'gusts' }, from = { 'windfrom', 'winddirection', 'from', 'direction', 'winddeg' }, temp = { 'temp', 'tempc',
  'temperature', 'temperaturec', 'airtemp' }, rain = { 'rain', 'rainmmh', 'rainmm', 'precipitation' },
  snow = { 'snow', 'snowcmh', 'snowcm' }, fog = { 'fog' }, vis = { 'visibility', 'visibilitym', 'vis', 'vism' },
  thunder = { 'thunder' },
  -- (what tools/pack_weather.py writes beside them, from the real weather: all optional)
  wmo = { 'code', 'wmo', 'wmocode', 'weathercode' }, isDay = { 'daylight', 'isday' },
  low = { 'lowcloud', 'lowcloudpercent' }, mid = { 'midcloud', 'midcloudpercent' },
  high = { 'highcloud', 'highcloudpercent' }, slTemp = { 'sealeveltempc', 'sltempc', 'sealeveltemp' },
  dew = { 'dewc', 'dewpoint', 'dewpointc' }, baseM = { 'cloudbasem', 'cloudbase' },
  baseAglM = { 'cloudbaseaboveground', 'cloudbaseabovegroundm' }, elevM = { 'elevationm', 'elevation' },
  pressure = { 'pressurehpa', 'pressure' },
}

-- weather.csv as { control -> weather } (BeamNG.Earth's weather message, as tools/pack_weather.py stores it).
local function readWeather(text, file, passes, stageNames, probs)
  local header, rows = R.csv(text)
  if not header then return {} end
  local col = {}
  for k, aliases in pairs(WX_COLS) do col[k] = R.column(header, aliases) end
  if not (col.ss or col.stage) or not (col.sky or col.wmo) then
    problem(probs, file, { n = header.n, raw = header.raw }, 'weather.csv needs an SS column and a Sky column.',
      'See the notes at the top of the template.')
    return {}
  end
  local out = {}
  for _, r in ipairs(rows) do
    local ln = { n = r.n, raw = r.raw }
    local function cell(k) return col[k] and R.trim(r.cells[col[k]] or '') or '' end
    local controls = {}
    local ssText = cell('ss')
    if ssText ~= '' then
      local n = ssText:match('(%d+)')
      if n and passes['SS' .. tonumber(n)] then controls[1] = 'SS' .. tonumber(n)
      else problem(probs, file, ln, string.format('There is no %s in the running order.', ssText),
        'This row is left out.') end
    elseif cell('stage') ~= '' then
      local name = nil
      for _, s in ipairs(stageNames) do if R.fold(s) == R.fold(cell('stage')) then name = s end end
      if not name then
        name = R.closest(cell('stage'), stageNames)
        if name then problem(probs, file, ln, string.format('No stage called "%s". Read as "%s".', cell('stage'), name),
          'If that\'s right, fix the spelling to stop this message.') end
      end
      for c, ps in pairs(passes) do if ps.stage == name then controls[#controls + 1] = c end end
      if #controls == 0 then
        problem(probs, file, ln, string.format('There is no stage called "%s".', cell('stage')), 'This row is left out.')
      end
    end
    if #controls > 0 then
      local skyText = cell('sky')
      local code, s = tonumber(cell('wmo')) or tonumber(skyText), SKY_BY[R.fold(skyText)]
      if not code and not s then
        local hit = R.closest(skyText, SKY_NAMES)
        s = hit and SKY_BY[R.fold(hit)] or nil
        problem(probs, file, ln, string.format('"%s" is not a kind of weather the game knows%s.', skyText,
          hit and ('. Read as "' .. hit .. '"') or ''), hit and 'Fix the spelling to stop this message.'
          or 'Use one of the words in the notes at the top of weather.csv. This row is left out.')
      end
      if code or s then
        code = code or s[2]
        local cover = R.number(cell('cloud')) or (s and s[3]) or (code >= 3 and 100 or code * 25)
        local temp = R.number(cell('temp'))
        local snowy = (code >= 71 and code <= 77) or code == 85 or code == 86
        local w = {
          code = code, cover = { total = cover, low = cover, mid = cover, high = cover },
          wind = { ms = R.number(cell('wind')) or 2, gustMs = R.number(cell('gust')) or (R.number(cell('wind')) or 2) * 2,
            fromDeg = R.number(cell('from')) or 0 },
          slTempC = temp or (snowy and -2 or 12), tempC = temp or (snowy and -2 or 12),
          rainMmH = R.number(cell('rain')) or (s and s.rain) or 0,
          snowCmH = R.number(cell('snow')) or (s and s.snow) or 0,
          fog = (col.fog and cell('fog') ~= '') and yes(cell('fog')) or (s and s.fog) or false,
          thunder = (col.thunder and cell('thunder') ~= '') and yes(cell('thunder')) or (s and s.thunder) or code >= 95,
          visM = R.number(cell('vis')),
        }
        if w.fog and not w.visM then w.visM = 400 end
        -- (the real weather's own: cloud layers, daylight, cloud base, dew point, height, pressure)
        local low, mid, high = R.number(cell('low')), R.number(cell('mid')), R.number(cell('high'))
        if low then w.cover.low = low end
        if mid then w.cover.mid = mid end
        if high then w.cover.high = high end
        if R.number(cell('slTemp')) then w.slTempC = R.number(cell('slTemp')) end
        if cell('isDay') ~= '' then w.isDay = yes(cell('isDay')) end
        w.dewC, w.baseM, w.baseAglM = R.number(cell('dew')), R.number(cell('baseM')), R.number(cell('baseAglM'))
        w.elevM, w.pressureHpa = R.number(cell('elevM')), R.number(cell('pressure'))
        for _, c in ipairs(controls) do out[c] = w end
      end
    end
  end
  return out
end

-- line.csv as [[lat, lon, alt?]...]
local function readLine(text, file, probs)
  local header, rows = R.csv(text)
  if not header then return nil, 'line.csv is empty' end
  local cLat = R.column(header, { 'lat', 'latitude', 'y' })
  local cLon = R.column(header, { 'lon', 'lng', 'long', 'longitude', 'x' })
  local cAlt = R.column(header, { 'height', 'heightm', 'alt', 'altitude', 'elevation', 'ele', 'z' })
  local pts = {}
  -- (no header: the first row is a point too)
  if not (cLat and cLon) and R.position(#header.cells >= 2 and (header.cells[1] .. ', ' .. header.cells[2])
    or header.cells[1]) then table.insert(rows, 1, header) end
  for _, r in ipairs(rows) do
    local lat, lon, note
    if cLat and cLon then lat, lon = R.number(r.cells[cLat] or ''), R.number(r.cells[cLon] or '')
    else
      local two = #r.cells >= 2 and (r.cells[1] .. ', ' .. r.cells[2]) or r.cells[1]
      lat, lon, note = R.position(two)
    end
    if lat and lon then
      pts[#pts + 1] = { lat, lon, cAlt and R.number(r.cells[cAlt] or '') or nil }
    else
      problem(probs, file, { n = r.n, raw = r.raw }, 'Not a point: left out.', 'Write it as: 60.00045, -10.0001')
    end
  end
  if #pts < 2 then return nil, 'line.csv has fewer than two points' end
  return pts
end

------------------------------------------------------------------------------------------ one rally

-- (the map's stage names, and the middle of its lines)
local function mapInfo(parsed)
  local names, sLat, sLon, n = {}, 0, 0, 0
  for i, l in ipairs(parsed.lines) do
    names[i] = l.name
    for _, pc in ipairs(l.pieces) do
      for _, p in ipairs(pc) do sLat, sLon, n = sLat + p[1], sLon + p[2], n + 1 end
    end
  end
  return names, n > 0 and { sLat / n, sLon / n } or nil
end

-- A rally.txt as a rally's spec (map, name, dates, pictures, rules, event and results by their virtual paths), its
-- virtual files added to `virtual`. base: its folder in the pack. Returns spec, or nil and why.
local function readRally(ctx, rel, base, probs, virtual)
  local all = ctx.all
  local text = ctx.readText(rel)
  if not text then return nil, "can't read " .. rel end
  local s, lists, places = settings(text, rel, M.RALLY_KEYS, probs)
  local spec = {}
  spec.name = s.name and s.name.value ~= '' and s.name.value or nil
  if not spec.name then
    problem(probs, rel, nil, 'The rally has no name: the map\'s name is used.', 'Add a line: Rally: My Forest Rally')
  end
  spec.id = s.id and s.id.value ~= '' and s.id.value or nil
  -- the map
  local mapRel, why
  if s.map then
    local note
    mapRel, note = findFile(all, base, s.map.value, M.MAP_EXT)
    if mapRel and note then
      problem(probs, rel, s.map.ln, string.format('There is no %s in the folder: %s.', s.map.value, note),
        'If that\'s right, fix the name to stop this message.')
    elseif not mapRel then
      local maps = ofKind(all, base, M.MAP_EXT)
      if #maps == 1 then
        mapRel = maps[1]
        problem(probs, rel, s.map.ln, string.format('There is no %s in the folder: used %s, the only map there.',
          s.map.value, baseName(maps[1])), 'Fix the name to stop this message.')
      else
        return nil, { file = rel, line = s.map.ln.n, text = s.map.ln.raw, what = string.format(
          'There is no %s in the folder.', baseName(s.map.value)), fix = #maps > 1 and ('The maps there are: ' ..
          table.concat((function() local t = {} for i, m in ipairs(maps) do t[i] = baseName(m) end return t end)(),
          ', ') .. '.') or 'Put the map in the folder beside ' .. baseName(rel) .. '.' }
      end
    end
  else
    local maps = ofKind(all, base, M.MAP_EXT)
    if #maps == 1 then mapRel = maps[1]
    elseif #maps == 0 then
      return nil, { file = rel, what = 'There is no map in the folder.',
        fix = 'Put your stage map (.kml, .kmz or .gpx) beside ' .. baseName(rel) .. ', and add "Map: <its name>".' }
    else
      local names = {}
      for i, m in ipairs(maps) do names[i] = baseName(m) end
      return nil, { file = rel, what = 'There are several maps in the folder, and no "Map:" line to say which.',
        fix = 'Add a line: Map: ' .. names[1] .. '  (the maps there: ' .. table.concat(names, ', ') .. ')' }
    end
  end
  spec.map = mapRel
  local parsed, pwhy = ctx.parseMap(mapRel)
  if not parsed then return nil, { file = mapRel, what = tostring(pwhy), fix = 'Save the map again from your map tool.' } end
  local stageNames, centre = mapInfo(parsed)
  if #stageNames == 0 then
    return nil, { file = mapRel, what = 'The map has no lines in it: nothing to make stages from.',
      fix = 'Draw each stage as a line (a path), not as points.' }
  end
  -- dates
  if s.dates then
    local d, dwhy, either = R.dates(s.dates.value)
    if d then
      spec.dates = d
      if either then
        problem(probs, rel, s.dates.ln, string.format('"%s" could be day/month or month/day: read as %s.',
          s.dates.value, d.from), 'Write the month as a word (7 Feb 2031) to stop this message.')
      end
    else
      problem(probs, rel, s.dates.ln, (dwhy or 'not a date') .. '.',
        'Write it as 7-8 Feb 2031, or 2031-02-07 to 2031-02-08.')
    end
  end
  -- pictures, results, weather
  for _, k in ipairs({ 'cover', 'logo', 'photo' }) do
    if s[k] and s[k].value ~= '' then
      local f, note = findFile(all, base, s[k].value, M.PICTURE_EXT)
      if f and note then
        problem(probs, rel, s[k].ln, string.format('There is no %s: %s.', s[k].value, note),
          'If that\'s right, fix the name to stop this message.')
      elseif not f then
        problem(probs, rel, s[k].ln, string.format('There is no picture %s in the folder.', s[k].value),
          'Put it in the folder (.png or .jpg), or delete this line.')
      end
      spec[k] = f
    end
  end
  readPlaces(places, rel, probs, centre)
  local rules, free = rulesFrom(s, rel, probs)
  spec.rules = rules
  -- the running order
  local ev = { event = {}, locations = nil, itinerary = {} }
  if s.town and s.town.value ~= '' then ev.event.hq = { town = s.town.value } end
  if s.timezone and s.timezone.value ~= '' then ev.event.timezone = s.timezone.value end
  if spec.dates then ev.event.dates = spec.dates end
  if free and #free > 0 then ev.time_rules = { early_checkin_allowed = free } end
  local passes = {}
  if lists.order and #lists.order > 0 then
    ev.itinerary, ev.locations = runningOrder(lists.order, rel, stageNames, places, spec.dates, probs)
    for _, row in ipairs(ev.itinerary) do
      if row.type == 'SS' then passes[row.control] = { stage = row.stage, run = row.run, km = row.ss_km } end
    end
    local any = false
    for _ in pairs(passes) do any = true break end
    if not any then
      problem(probs, rel, lists.order[1], 'No stage in the running order matches a line in the map: the stages run in map order.',
        'Name each stage as its line is named in the map.')
      ev.itinerary = {}
      for i, name in ipairs(stageNames) do passes['SS' .. i] = { stage = name, run = 1 } end
    end
  else
    -- (no running order: the map's lines in order, as pack.lua runs them)
    for i, name in ipairs(stageNames) do passes['SS' .. i] = { stage = name, run = 1 } end
    if #places > 0 then
      local locs = {}
      for _, pl in ipairs(places) do locs[#locs + 1] = { id = R.fold(pl.name), name = pl.name, lat = pl.lat, lon = pl.lon } end
      ev.locations = locs
      problem(probs, rel, places[1].ln, 'There is no running order, so the places are not used.',
        'Add "Running order:" with the stages and stops in order.', 'unused')
    end
  end
  -- weather
  local wxRel = nil
  if s.weather and s.weather.value ~= '' then
    local note
    wxRel, note = findFile(all, base, s.weather.value, { csv = true, txt = true })
    if not wxRel then problem(probs, rel, s.weather.ln, string.format('There is no %s in the folder.', s.weather.value),
      'Put it in the folder, or delete this line.')
    elseif note then problem(probs, rel, s.weather.ln, string.format('There is no %s: %s.', s.weather.value, note),
      'If that\'s right, fix the name to stop this message.') end
  else
    wxRel = findFile(all, base, 'weather.csv', { csv = true })
    if wxRel and baseName(wxRel):lower() ~= 'weather.csv' then wxRel = nil end
  end
  spec.weatherFile = wxRel      -- (tools/pack_weather.py writes there)
  if wxRel then
    local wx = readWeather(ctx.readText(wxRel) or '', wxRel, passes, stageNames, probs)
    local any = false
    for _, row in ipairs(ev.itinerary) do
      if row.type == 'SS' and wx[row.control] then row.weather, any = wx[row.control], true end
    end
    if not any and next(wx) and #ev.itinerary == 0 then
      problem(probs, wxRel, nil, 'Weather needs a running order in rally.txt: not used.',
        'Add "Running order:" to rally.txt.', 'unused')
    end
  end
  if next(ev.event) == nil then ev.event = nil end
  local evPath = rel .. '#event'
  virtual[evPath] = ev
  spec.event = evPath
  -- results
  local resRel = nil
  if s.results and s.results.value ~= '' then
    local note
    resRel, note = findFile(all, base, s.results.value, { csv = true, txt = true })
    if not resRel then problem(probs, rel, s.results.ln, string.format('There is no %s in the folder.',
      s.results.value), 'Put it in the folder, or delete this line.')
    elseif note then problem(probs, rel, s.results.ln, string.format('There is no %s: %s.', s.results.value, note),
      'If that\'s right, fix the name to stop this message.') end
  else
    resRel = findFile(all, base, 'results.csv', { csv = true })
    if resRel and baseName(resRel):lower() ~= 'results.csv' then resRel = nil end
  end
  if resRel then
    local res = readResults(ctx.readText(resRel) or '', resRel, passes, stageNames, probs)
    if res then
      virtual[resRel .. '#results'] = res
      spec.results = resRel .. '#results'
    end
  end
  return spec
end

------------------------------------------------------------------------------------------ the three kinds

local function readStage(ctx, rel, probs, virtual)
  local all = ctx.all
  local text = ctx.readText(rel)
  local s = settings(text or '', rel, M.STAGE_KEYS, probs)
  local spec = { name = s.name and s.name.value ~= '' and s.name.value or nil, id = s.id and s.id.value or nil }
  if s.line and s.line.value ~= '' then
    local f, note = findFile(all, '', s.line.value, nil)
    if f and M.MAP_EXT[extOf(f)] then
      spec.map = f
    elseif f then
      if note then problem(probs, rel, s.line.ln, string.format('There is no %s: %s.', s.line.value, note),
        'If that\'s right, fix the name to stop this message.') end
      local pts, why = readLine(ctx.readText(f) or '', f, probs)
      if not pts then return nil, { file = f, what = why .. '.', fix = 'One point per row: lat, lon.' } end
      spec.line = pts
    else
      return nil, { file = rel, line = s.line.ln.n, text = s.line.ln.raw, what = note .. '.',
        fix = 'Put line.csv in the folder.' }
    end
  end
  if not spec.line and not spec.map then
    -- (the map the same way a rally finds it: named, or the only one in the folder)
    local maps = ofKind(all, '', M.MAP_EXT)
    if s.map then
      local f, note = findFile(all, '', s.map.value, M.MAP_EXT)
      if not f and #maps == 1 then f, note = maps[1], 'used ' .. baseName(maps[1]) .. ', the only map there' end
      if not f then return nil, { file = rel, line = s.map.ln.n, text = s.map.ln.raw,
        what = string.format('There is no %s in the folder.', s.map.value), fix = 'Put the map beside stage.txt.' } end
      if note then problem(probs, rel, s.map.ln, string.format('There is no %s: %s.', s.map.value, note),
        'If that\'s right, fix the name to stop this message.') end
      spec.map = f
    elseif #maps == 1 then spec.map = maps[1]
    elseif #maps == 0 then
      local csvs = findFile(all, '', 'line.csv', { csv = true })
      if csvs then
        local pts, why = readLine(ctx.readText(csvs) or '', csvs, probs)
        if not pts then return nil, { file = csvs, what = why .. '.', fix = 'One point per row: lat, lon.' } end
        spec.line = pts
      else
        return nil, { file = rel, what = 'There is no map or line.csv in the folder.',
          fix = 'Put the stage\'s map beside stage.txt, and add "Map: <its name>".' }
      end
    else
      return nil, { file = rel, what = 'There are several maps in the folder, and no "Map:" line to say which.',
        fix = 'Add a line: Map: <the map\'s name>' }
    end
  end
  if not spec.name and spec.line then
    problem(probs, rel, nil, 'The stage has no name.', 'Add a line: Stage: Kilo Hill')
  end
  spec.controls = {}
  for _, role in ipairs({ 'atc', 'start', 'ff', 'stop' }) do
    if s[role] and s[role].value ~= '' then
      local lat, lon, note = R.position(s[role].value)
      if lat then
        spec.controls[role] = { lat = lat, lon = lon }
        if note == 'swapped' then problem(probs, rel, s[role].ln, string.format('Longitude first: read as %.6f, %.6f.',
          lat, lon), 'Swap the two numbers to stop this message.') end
      else
        problem(probs, rel, s[role].ln, lon .. '.', 'This control is left out.')
      end
    end
  end
  if next(spec.controls) and spec.map then
    problem(probs, rel, nil, 'Controls in stage.txt are only used with line.csv: the map\'s own control points are used.',
      nil, 'unused')
  end
  for _, k in ipairs({ 'cover', 'logo', 'photo' }) do
    if s[k] and s[k].value ~= '' then
      local f, note = findFile(all, '', s[k].value, M.PICTURE_EXT)
      if not f then problem(probs, rel, s[k].ln, string.format('There is no picture %s in the folder.', s[k].value),
        'Put it in the folder (.png or .jpg), or delete this line.')
      elseif note then problem(probs, rel, s[k].ln, string.format('There is no %s: %s.', s[k].value, note),
        'If that\'s right, fix the name to stop this message.') end
      spec[k] = f
    end
  end
  spec.rules = rulesFrom(s, rel, probs)
  -- results: every row is this stage's
  local resRel = s.results and findFile(all, '', s.results.value, { csv = true }) or nil
  if s.results and not resRel then
    problem(probs, rel, s.results.ln, string.format('There is no %s in the folder.', s.results.value),
      'Put it in the folder, or delete this line.')
  end
  if not s.results then
    resRel = findFile(all, '', 'results.csv', { csv = true })
    if resRel and baseName(resRel):lower() ~= 'results.csv' then resRel = nil end
  end
  if resRel then
    local stageName = spec.name or 'Stage'
    if spec.map then
      local parsed = ctx.parseMap(spec.map)
      if parsed and parsed.lines[1] then stageName = parsed.lines[1].name end
    end
    local res = readResults(ctx.readText(resRel) or '', resRel, { SS1 = { stage = stageName, run = 1 } },
      { stageName }, probs)
    if res then
      for _, st in ipairs(res.stages) do st.stage, st.control = stageName, 'SS1' end
      virtual[resRel .. '#results'] = res
      spec.results = resRel .. '#results'
    end
  end
  return spec
end

-- (a season's rounds: the Rounds list, else every folder with a rally in it, in date order)
local function readSeason(ctx, rel, probs, virtual)
  local all = ctx.all
  local text = ctx.readText(rel)
  local s, lists = settings(text or '', rel, M.SEASON_KEYS, probs)
  local data = { name = s.name and s.name.value ~= '' and s.name.value or nil,
    championship = s.championship and s.championship.value or nil, id = s.id and s.id.value or nil, rounds = {} }
  if not data.name then
    return nil, { file = rel, what = 'The season has no name.', fix = 'Add a line: Season: My Forest Series 2031' }
  end
  -- standings
  local st = {}
  if s.points then
    local ns = R.numbers(s.points.value)
    if #ns == 0 then problem(probs, rel, s.points.ln, 'No numbers in the points.', 'Write them as: 25 20 16 13 11')
    else st.points = ns end
  end
  if s.best then
    local f = R.fold(s.best.value)
    if f ~= 'all' and f ~= '' then
      local n = R.numbers(s.best.value)[1]
      if n then st.best = n
      else problem(probs, rel, s.best.ln, string.format('"%s" is not a number.', s.best.value), 'Write all, or a number.') end
    end
  end
  if s.countOnly then
    local f = R.fold(s.countOnly.value)
    st.championship = (f == 'all' or f == 'everyone' or f == '') and false or s.countOnly.value
  end
  if next(st) ~= nil then data.standings = st end
  data.rules = rulesFrom(s, rel, probs)

  -- the rounds
  local folders = foldersIn(all, '')
  local function rallyIn(folder)
    for _, f in ipairs(filesIn(all, folder)) do
      if extOf(f) == 'txt' and stemOf(baseName(f)) == 'rally' then return f end
    end
    for _, f in ipairs(filesIn(all, folder)) do
      if extOf(f) == 'txt' and not isReport(f) and M.firstKey(ctx.readText(f) or '') == 'rally' then return f end
    end
    return nil
  end
  local wanted = {}
  if lists.rounds and #lists.rounds > 0 then
    local used = {}
    for i, ln in ipairs(lists.rounds) do
      local n, target = ln.text:match('^[Rr]ound%s*(%d+)[%s:%.%-)]+(.+)$')
      if not n then n, target = ln.text:match('^(%d+)[%s:%.%-)]+(.+)$') end
      if not n then target = ln.text end
      -- (a folder named with a number in front, "2031 Rally Wales", is that folder: the whole line first)
      for _, f in ipairs(folders) do
        if R.fold(f) == R.fold(ln.text) then n, target = nil, ln.text end
      end
      target = R.unquote(R.trim(target or ''))
      local round = tonumber(n) or i
      if used[round] then
        problem(probs, rel, ln, string.format('Round %d is listed twice: the second is left out.', round),
          'Give each round its own number.')
      else
        used[round] = true
        local folder = nil
        for _, f in ipairs(folders) do if f:lower() == target:lower() or R.fold(f) == R.fold(target) then folder = f end end
        if not folder then
          local hit = R.closest(target, folders)
          if hit then
            problem(probs, rel, ln, string.format('There is no folder "%s": used "%s".', target, hit),
              'If that\'s right, fix the name to stop this message.')
            folder = hit
          end
        end
        if folder then
          wanted[#wanted + 1] = { round = round, folder = folder, ln = ln }
        else
          local f = findFile(all, '', target, M.MAP_EXT)
          if f and M.MAP_EXT[extOf(f)] then
            wanted[#wanted + 1] = { round = round, map = f, ln = ln }
          else
            problem(probs, rel, ln, string.format('There is no folder or map called "%s" in the season\'s folder.',
              target), 'Name the round\'s folder exactly. Until then this round is left out.')
          end
        end
      end
    end
  else
    for _, f in ipairs(folders) do
      if rallyIn(f) then wanted[#wanted + 1] = { folder = f } end
    end
    if #wanted == 0 then
      return nil, { file = rel, what = 'The season has no rounds: no "Rounds:" list, and no rally folders in it.',
        fix = 'Put one folder per rally in the season\'s folder, each with its rally.txt and map.' }
    end
  end

  for _, w in ipairs(wanted) do
    local spec, why
    if w.map then
      spec = { map = w.map }
    else
      local rrel = rallyIn(w.folder)
      if rrel then
        spec, why = readRally(ctx, rrel, w.folder, probs, virtual)
      else
        local maps = ofKind(all, w.folder, M.MAP_EXT)
        if #maps == 1 then
          spec = { map = maps[1] }
          problem(probs, w.folder, nil, string.format('%s has no rally.txt: its map is used on its own.', w.folder),
            'Add a rally.txt (see the My Rally template).', 'unused')
        else
          why = { file = w.folder, what = string.format('There is no rally.txt in %s.', w.folder),
            fix = 'Put a rally.txt and the rally\'s map in it.' }
        end
      end
    end
    local r = { round = w.round, why = nil }
    if spec then for k, v in pairs(spec) do r[k] = v end
    else r.why = why end
    w.r = r
    data.rounds[#data.rounds + 1] = w
  end
  -- (no list: in date order, then by name)
  if not (lists.rounds and #lists.rounds > 0) then
    table.sort(data.rounds, function(a, b)
      local da = a.r.dates and a.r.dates.from or '9999'
      local db = b.r.dates and b.r.dates.from or '9999'
      if da ~= db then return da < db end
      return (a.folder or a.map) < (b.folder or b.map)
    end)
  end
  local rounds = {}
  for i, w in ipairs(data.rounds) do
    w.r.round = w.r.round or i
    rounds[i] = w.r
  end
  data.rounds = rounds
  -- (standings that would come out empty: no crew in the results is in the championship that scores)
  local want = st.championship
  if want == nil then want = 'national' end
  if want then
    local any, seen = false, false
    for _, r in ipairs(rounds) do
      local res = r.results and virtual[r.results]
      for _, stg in ipairs(res and res.stages or {}) do
        for _, t in ipairs(stg.times or {}) do
          seen = true
          if R.fold(t.championship or '') == R.fold(want) then any = true end
        end
      end
    end
    if seen and not any then
      problem(probs, rel, s.countOnly and s.countOnly.ln or nil, string.format(
        'No crew in the results is in the "%s" championship, so the season standings are empty.', want),
        'Write "Count only: all", or give results.csv a Championship column.')
    end
  end
  return data
end

------------------------------------------------------------------------------------------ the pack

-- The pack's manifest from its text files, as pack.lua's M.manifest gives a JSON one:
--   { kind, file, data, virtual = { path -> table }, problems = {...}, named = { the files it was made from } }
-- or nil when the pack has no text manifest; or nil, false, why (a problem) when it has one that can't be used.
-- ctx: { all = every file in the pack, readText(rel) -> text, parseMap(rel) -> parsed or nil, why }
function M.read(ctx)
  local all = {}
  for _, rel in ipairs(ctx.all) do if not isReport(rel) then all[#all + 1] = rel end end
  ctx.all = all
  local named, others = M.find(all)
  if #named == 0 and not ctx.jsonManifest then
    for _, rel in ipairs(others) do
      local k = M.firstKey(ctx.readText(rel) or '')
      if k then named[#named + 1] = { kind = k, file = rel } end
    end
  end
  if #named == 0 then return nil end
  if #named > 1 then
    local names = {}
    for i, f in ipairs(named) do names[i] = f.file end
    return nil, false, { what = 'More than one rally file at the top of the folder: ' .. table.concat(names, ', ') .. '.',
      fix = 'Keep one: season.txt, rally.txt or stage.txt.' }
  end
  local m = { kind = named[1].kind, file = named[1].file, virtual = {}, problems = {}, text = true }
  local data, why
  if m.kind == 'season' then data, why = readSeason(ctx, m.file, m.problems, m.virtual)
  elseif m.kind == 'rally' then data, why = readRally(ctx, m.file, '', m.problems, m.virtual)
  else data, why = readStage(ctx, m.file, m.problems, m.virtual) end
  if not data then
    if type(why) ~= 'table' then why = { file = m.file, what = tostring(why) } end
    return nil, false, why, m.problems
  end
  m.data = data
  -- (what it was made from: every text, table and map in the pack, and the pictures it names)
  local named2 = {}
  for _, rel in ipairs(all) do
    local e = extOf(rel)
    if e == 'txt' or e == 'csv' or M.MAP_EXT[e] or e == 'json' then named2[#named2 + 1] = rel end
  end
  local picList = {}
  local function pics(t)
    for _, k in ipairs({ 'cover', 'logo', 'photo' }) do
      if type(t[k]) == 'string' then named2[#named2 + 1] = t[k] picList[#picList + 1] = t[k] end
    end
  end
  if m.kind == 'season' then for _, r in ipairs(data.rounds) do pics(r) end else pics(data) end
  m.named, m.pics = named2, picList
  return m
end

-- The ID line of a pack's hand-made manifest, without reading anything else (pack.lua tells two copies of a pack
-- apart by it); nil when the pack has no text manifest, false when it has one with no ID.
function M.idOf(ctx)
  local all = {}
  for _, rel in ipairs(ctx.all) do if not isReport(rel) then all[#all + 1] = rel end end
  local named = M.find(all)
  if #named ~= 1 then return nil end
  local keyset = named[1].kind == 'season' and M.SEASON_KEYS or named[1].kind == 'rally' and M.RALLY_KEYS
    or M.STAGE_KEYS
  local s = settings(ctx.readText(named[1].file) or '', named[1].file, keyset, {})
  return s.id and s.id.value ~= '' and s.id.value or false
end

M._settings, M._runningOrder, M._readResults, M._readWeather, M._findFile = settings, runningOrder, readResults,
  readWeather, findFile

return M
