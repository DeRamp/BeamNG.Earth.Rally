-- Packs (docs/rally-file.md) on a small made-up season against a stand-in file system: a season of two rounds (one
-- with an event file and results, one map only), a rally in a .zip, a stage, and the ways a pack can be wrong. Then,
-- only where it is on this computer, the real ARA Nationals 2026 pack (organisers' material: never in git).
local T = dofile(TESTS .. '/testlib.lua')
function log() end
local imp = require('earthRally/importer')
local pack = require('earthRally/pack')

-- a line north from (lat0, lon0), n points 50 m apart
local function northLine(lat0, lon0, n)
  local out = {}
  for i = 0, n - 1 do out[#out + 1] = string.format('%.7f,%.7f,0', lon0, lat0 + i * 50 / 111195) end
  return table.concat(out, ' ')
end

-- a KML: lines = { { name, lat, lon, n }... }
local function kml(doc, lines)
  local out = { '<?xml version="1.0"?><kml><Document><name>' .. doc .. '</name>' }
  for _, l in ipairs(lines) do
    out[#out + 1] = '<Placemark><name>' .. l[1] .. '</name><LineString><coordinates>' .. northLine(l[2], l[3], l[4])
      .. '</coordinates></LineString></Placemark>'
    out[#out + 1] = string.format('<Placemark><name>Start - %s</name><Point><coordinates>%.7f,%.7f,0</coordinates>'
      .. '</Point></Placemark>', l[1], l[3], l[2])
  end
  out[#out + 1] = '</Document></kml>'
  return table.concat(out, '\n')
end

------------------------------------------------------------------------------------------ the stand-in game

local files = {}             -- path -> text (what is read) or table (what jsonWriteFile wrote)
local zips = {}              -- path -> { entry name -> text }
local copied = {}            -- dest -> source
local mtimes = {}            -- path -> modification time (FS:stat); 1 when not set
local hashed = 0             -- how many times a zip's bytes were read (the cost FS:stat spares)
local J = T.jsonEncode

FS = {
  -- (a folder is what some file is inside of)
  directoryExists = function(_, d)
    local pre = d:gsub('/+$', '') .. '/'
    for f in pairs(files) do if f:sub(1, #pre) == pre then return true end end
    return false
  end,
  directoryCreate = function() end,
  fileExists = function(_, f) return files[f] ~= nil end,
  removeFile = function(_, f) files[f] = nil end,
  stat = function(_, f)
    if type(files[f]) ~= 'string' then return nil end
    return { filetype = 'file', filesize = #files[f], modtime = mtimes[f] or 1, createtime = 1 }
  end,
  copyFile = function(_, a, b)
    if files[a] == nil then return false end
    files[b], copied[b] = files[a], a
    return true
  end,
  -- (every depth, whatever is asked: the importer must not take a map inside a pack for a loose one)
  findFiles = function(_, dir, pat)
    local ext = pat == '*' and '' or pat:match('^%*%.(.+)$'):gsub('%.', '%%.')
    local out = {}
    for f in pairs(files) do
      if f:sub(1, #dir) == dir and (ext == '' or f:lower():match('%.' .. ext:lower() .. '$')) then out[#out + 1] = f end
    end
    table.sort(out)
    return out
  end,
  -- (folders AND files, as the game's may: pack.find must keep only the folders)
  directoryList = function(_, dir)
    local seen, out = {}, {}
    for f in pairs(files) do
      local sub = f:sub(1, #dir) == dir and f:sub(#dir + 1):match('^([^/]+)')
      if sub and not seen[sub] then seen[sub] = true out[#out + 1] = dir .. sub end
    end
    table.sort(out)
    return out
  end,
}
function readFile(f)
  if f:lower():match('%.zip$') then hashed = hashed + 1 end
  return type(files[f]) == 'string' and files[f] or nil
end
function jsonWriteFile(f, d) files[f] = d return true end
function jsonReadFile(f)
  if type(files[f]) == 'table' then return files[f] end
  return type(files[f]) == 'string' and T.jsonDecode(files[f]) or nil
end
jsonDecode = T.jsonDecode
ZipArchive = function()
  local z
  return {
    openArchiveName = function(_, p) z = zips[p] return z ~= nil end,
    getFileList = function()
      local out = {}
      for n in pairs(z) do out[#out + 1] = n end
      table.sort(out)
      return out
    end,
    readFileToMemory = function(_, n) return z[n] end,
    extractFile = function(_, n, dest)
      if not z[n] then return false end
      files[dest], copied[dest] = z[n], 'zip:' .. n
      return true
    end,
    close = function() end,
  }
end

local IMP = '/earthRally/import/'
local function find(list, file)
  for _, d in ipairs(list) do if d.file == file then return d end end
end

------------------------------------------------------------------------------------------ a season of two rounds

local fernKml = kml('Fernvale Rally 2030', {
  { 'Fernvale North', 51.00, -1.00, 40 }, { 'Fernvale South', 51.05, -1.00, 60 }, { 'Old Mill', 51.10, -1.00, 20 } })
local quarryKml = kml('Quarry Hill Rally', { { 'Quarry Hill', 52.00, -2.00, 30 }, { 'Quarry Loop', 52.05, -2.00, 25 } })
local S = IMP .. 'Test Series/'
files[S .. 'season.json'] = J({
  format = 1, name = 'Test Series 2030', championship = 'The Test Championship',
  rules = { falseStartS = { 10, 60, 180 }, startIntervalMin = 2, note = 'ignored' },
  standings = { points = { 10, 6, 4 } },
  someFutureField = { kept = true },
  rounds = {
    { round = 1, name = 'Fernvale Rally', dates = { from = '2030-03-01', to = '2030-03-02' },
      map = 'maps\\Fernvale.kml', event = 'events/fernvale.json', results = './results/fernvale.json',
      cover = 'covers/fern cover.PNG', photo = 'covers/missing.jpg', rules = { startIntervalMin = 3 } },
    { round = 2, map = 'Quarry.kml' },
  },
})
files[S .. 'maps/Fernvale.kml'] = fernKml
files[S .. 'Quarry.kml'] = quarryKml
files[S .. 'covers/fern cover.PNG'] = 'PNGBYTES'
files[S .. 'notes.json'] = J({ hello = 'not a manifest' })
files[S .. 'events/fernvale.json'] = J({
  format = 1,
  event = { name = 'Fernvale Rally 2030', hq = { name = 'The Hall', town = 'Fernvale', state = 'ZZ' } },
  rules = { lateSPerMin = 10 },
  itinerary = {
    { control = 'TC0', type = 'MTC_OUT' },
    { control = 'SS1', type = 'SS', stage = 'Fernvale South', run = 1, ss_km = 3.0, day = 1, classes = { 'national' } },
    { control = 'SS2', type = 'SS', stage = 'Fernvale North', run = 1, ss_km = 1.95, day = 1 },
    { control = 'SS3', type = 'SS', stage = 'Fernvale South', run = 2, ss_km = 3.0, day = 2, power_stage = true },
    { control = 'SS3', type = 'SS', stage = 'Fernvale South', run = 2, ss_km = 3.0, day = 2, classes = { 'regional' } },
  },
})
local fernResults = {
  format = 1, event = 'Fernvale Rally 2030', status = 'final',
  stages = {
    { control = 'SS1', stage = 'Fernvale South', run = 1, km = 3.0, cancelled = false, times = {
      { car = '7', driver = 'Ada Brook', class = 'A', championship = 'national', seconds = 181.5 },
      { car = '3', driver = 'Cy Dale', class = 'B', championship = 'regional', seconds = 175.2 },
      { car = '9', driver = 'Ed Finch', class = 'A', championship = 'national', seconds = 190.0, notional = true },
      { car = '11', driver = 'Gil Hart', class = 'A', championship = 'national' },     -- (no time)
    } },
    { control = 'SS2', stage = 'Fernvale North', run = 1, km = 1.95, times = {
      { car = '3', driver = 'Cy Dale', class = 'B', championship = 'regional', seconds = 120.0 },
      { car = '7', driver = 'Ada Brook', class = 'A', championship = 'national', seconds = 118.4 },
    } },
    { control = 'SS3', stage = 'Fernvale South', run = 2, km = 3.0, cancelled = true, times = {} },
    { control = 'SS4', stage = 'Ghost Road', run = 1, km = 5.0, times = {
      { car = '7', driver = 'Ada Brook', seconds = 300.0 } } },
  },
  overall = {
    { pos = 2, car = '3', driver = 'Cy Dale', class = 'B', championship = 'regional', seconds = 295.2 },
    { car = '9', driver = 'Ed Finch', class = 'A', championship = 'national', seconds = 200.0, result = 'DNF' },
    { pos = 1, car = '7', driver = 'Ada Brook', class = 'A', championship = 'national', seconds = 299.9,
      result = 'classified' },
    { car = '11', driver = 'Gil Hart', class = 'A', championship = 'national' },
  },
}
files[S .. 'results/fernvale.json'] = J(fernResults)

local r1 = imp.scan()
local d = find(r1, 'Test Series')
T.check(d and d.ok and d.rallies == 2 and d.stages == 5, 'the season imported: 2 rallies, 5 stages ('
  .. tostring(d and (d.why or d.stages)) .. ')')
T.check(#r1 == 1, 'the pack and nothing else: its maps are not loose rallies as well (' .. #r1 .. ')')
T.check(not files['/earthRally/events/fernvale.json'] and not files['/earthRally/events/quarry.json'],
  'no loose rally made from a map inside the pack')

local season = files['/earthRally/seasons/test-series-2030.json']
T.check(season and season.id == 'test-series-2030' and season.name == 'Test Series 2030' and
  season.championship == 'The Test Championship', 'the season file, its id a slug of the name')
T.check(season and #season.rounds == 2 and season.rounds[1] == 'test-series-2030-fernvale-rally' and
  season.rounds[2] == 'test-series-2030-quarry-hill-rally', 'rounds in order, ids <season>-<slug of the round name> (round 2 named from its map)')
T.check(season and season.standings.championship == 'national' and season.standings.points[1] == 10 and
  #season.standings.points == 3 and season.standings.best == nil, 'standings: its points, the default championship')

local e1 = files['/earthRally/events/test-series-2030-fernvale-rally.json']
T.check(e1 and e1.format == 1 and e1.name == 'Fernvale Rally' and e1.id == 'test-series-2030-fernvale-rally', 'round 1 written')
-- the stages exactly as a bare import of the same map gives them
local bare = imp.build(imp.parse(fernKml, 'kml'), 'x', 'x', 'x.kml')
local same = e1 and #e1.stages == #bare.stages
for i, s in ipairs(bare.stages) do
  local o = e1 and e1.stages[i]
  if not (o and o.id == s.id and o.lengthM == s.lengthM and #o.line == #s.line) then same = false end
end
T.check(same, 'its stages are what a bare KML import gives')
T.check(e1 and e1.season.id == 'test-series-2030' and e1.season.round == 1 and e1.season.name == 'Test Series 2030',
  'the season named on the rally')
T.check(e1 and e1.dates.from == '2030-03-01' and e1.place == 'Fernvale, ZZ', 'dates from the manifest, place from hq')
local it = e1 and e1.itinerary or {}
T.check(#it == 3 and it[1].ss == 'SS1' and it[1].stage == 'fernvale-south' and it[2].stage == 'fernvale-north' and
  it[3].run == 2, 'the itinerary in running order, one row per control (' .. #it .. ')')
T.check(it[3] and it[3].cancelled == true and it[1].cancelled == false and it[1].km == 3.0,
  'a pass cancelled in the results is cancelled in the itinerary')
T.check(it[3] and it[3].powerStage == true and it[3].day == 2, 'power stage and day kept')
T.check(e1 and e1.rules.falseStartS[2] == 60 and e1.rules.startIntervalMin == 3 and e1.rules.lateSPerMin == nil and
  e1.rules.note == nil, "rules: the season's, the round's over them; the event file's not read; numbers only")
T.check(e1 and e1.media.cover == '/earthRally/media/test-series-2030-fernvale-rally/cover.png' and
  files['/earthRally/media/test-series-2030-fernvale-rally/cover.png'] == 'PNGBYTES' and e1.media.photo == nil,
  'the cover copied to the media folder, lower-case extension; a missing photo not recorded')
T.check(e1 and e1.boards == 'test-series-2030-fernvale-rally.json' and e1.pack.file == 'Test Series' and
  e1.pack.fingerprint ~= nil, 'boards and pack named')

local b = files['/earthRally/boards/test-series-2030-fernvale-rally.json']
T.check(b and b.format == 1 and #b.passes == 3, 'boards: three passes (the one with no line left out)')
local p1 = b and b.passes[1]
T.check(p1 and p1.ss == 'SS1' and p1.stage == 'fernvale-south' and p1.run == 1 and p1.km == 3.0 and not p1.cancelled,
  'a pass joined to its stage id')
T.check(p1 and #p1.field == 3 and p1.field[1][1] == 175.2 and p1.field[1][2] == 'Cy Dale' and p1.field[1][3] == '3'
  and p1.field[3][6] == true and p1.field[1][6] == false, 'its field fastest first, notional flagged, no-time row out')
T.check(b and b.passes[3].cancelled == true and #b.passes[3].field == 0, 'a cancelled pass')
T.check(b and b.overall == nil, 'no overall table in the boards: nothing reads it')
local oldMill = false
for _, s in ipairs(e1 and e1.stages or {}) do if s.id == 'old-mill' then oldMill = true end end
local runOld = false
for _, ps in ipairs(b and b.passes or {}) do if ps.stage == 'old-mill' then runOld = true end end
T.check(oldMill and not runOld, 'a line never run is a stage with no passes')

local warned = false
for _, w in ipairs(d and d.warnings or {}) do if w:find('Ghost Road', 1, true) then warned = true end end
T.check(warned, 'a results stage with no line: a warning')
local rep = table.concat((imp.lastReports['test-series-2030-fernvale-rally'] or {}).lines or {}, '\n')
T.check(rep:find('results SS4 "Ghost Road": no line of that name in the map', 1, true) ~= nil,
  'and in the import report, in its usual shape')
T.check(rep:find("can't find the photo image", 1, true) ~= nil, 'the missing image reported too')

local e2 = files['/earthRally/events/test-series-2030-quarry-hill-rally.json']
T.check(e2 and e2.name == 'Quarry Hill Rally' and e2.season.round == 2, 'round 2: named from its map')
T.check(e2 and #e2.itinerary == 2 and e2.itinerary[1].ss == 'SS1' and e2.itinerary[1].stage == 'quarry-hill' and
  e2.itinerary[2].stage == 'quarry-loop', 'no event file: the map in order')
T.check(e2 and e2.boards == nil and e2.media == nil and files['/earthRally/boards/test-series-2030-quarry-hill-rally.json'] == nil,
  'no results: no boards')
T.check(e2 and e2.rules.falseStartS[1] == 10 and e2.rules.lateSPerMin == nil, "the season's rules on every round")

T.check(#imp.scan() == 0, 'unchanged: not imported again')
fernResults.stages[1].times[1].seconds = 170.0
files[S .. 'results/fernvale.json'] = J(fernResults)
local r2 = imp.scan()
T.check(#r2 == 1 and r2[1].ok and files['/earthRally/boards/test-series-2030-fernvale-rally.json'].passes[1].field[1][1] == 170.0,
  'a file the manifest names changed: imported again')
local sj = T.jsonDecode(files[S .. 'season.json'])
sj.name = 'Test Series 2030 (final)'
files[S .. 'season.json'] = J(sj)
imp.scan()
T.check(files['/earthRally/seasons/test-series-2030.json'].name == 'Test Series 2030 (final)' and
  files['/earthRally/events/test-series-2030-fernvale-rally.json'].season.name == 'Test Series 2030 (final)',
  'renamed: the season keeps its id, so its rounds keep theirs')
T.check(files['/earthRally/importIndex.json'].packs['Test Series'].seasonId == 'test-series-2030', 'kept in the index')

------------------------------------------------------------------------------------------ a rally in a zip, a stage

zips[IMP .. 'Brindle.zip'] = {
  ['Brindle Rally/'] = '',
  ['Brindle Rally/rally.json'] = J({ format = 1, name = 'Brindle Rally', map = 'brindle.kml', logo = 'art\\logo.jpg',
    results = 'times.json' }),
  ['Brindle Rally/brindle.kml'] = kml('Brindle', { { 'Brindle Pass', 53.0, -3.0, 30 } }),
  ['Brindle Rally/art/logo.jpg'] = 'JPGBYTES',
  ['Brindle Rally/times.json'] = J({ stages = { { control = 'SS1', stage = 'Brindle Pass', run = 1, times = {
    { car = '1', driver = 'Ida Jones', seconds = 99.5 } } } } }),
}
files[IMP .. 'Brindle.zip'] = 'zip bytes v1'
files[IMP .. 'One Stage/manifest.json'] = J({ format = 1, kind = 'stage', name = 'Lone Ridge', map = 'ridge.gpx',
  results = 'ridge-times.json' })
files[IMP .. 'One Stage/ridge.gpx'] = [[<gpx><trk><name>Lone Ridge Up</name><trkseg><trkpt lat="54.0" lon="-4.0"/>
  <trkpt lat="54.01" lon="-4.0"/></trkseg></trk><trk><name>Lone Ridge Down</name><trkseg><trkpt lat="54.0" lon="-4.1"/>
  <trkpt lat="54.01" lon="-4.1"/></trkseg></trk></gpx>]]
files[IMP .. 'One Stage/ridge-times.json'] = J({ stages = {
  { control = 'SS1', stage = 'Lone Ridge Up', run = 1, km = 1.1, times = { { driver = 'Kit Lane', seconds = 61 } } },
  { control = 'SS2', stage = 'Lone Ridge Up', run = 2, km = 1.1, times = { { driver = 'Kit Lane', seconds = 59 } } },
} })
local r3 = imp.scan()
local z = find(r3, 'Brindle.zip')
T.check(z and z.ok and z.eventId == 'brindle-rally' and z.rallies == 1, 'a rally zip (its manifest in its one top '
  .. 'folder, named rally.json with no kind) imported as brindle-rally (' .. tostring(z and (z.why or z.eventId)) .. ')')
local be = files['/earthRally/events/brindle-rally.json']
T.check(be and be.season == nil and be.media.logo == '/earthRally/media/brindle-rally/logo.jpg' and
  copied['/earthRally/media/brindle-rally/logo.jpg'] == 'zip:Brindle Rally/art/logo.jpg',
  'its logo extracted from the zip')
T.check(be and be.boards == 'brindle-rally.json' and files['/earthRally/boards/brindle-rally.json'].passes[1].stage ==
  'brindle-pass', 'its boards')
local st = find(r3, 'One Stage')
T.check(st and st.ok and st.stages == 1 and st.eventId == 'lone-ridge', 'a stage pack: one stage')
T.check(table.concat(st and st.warnings or {}, ' '):find('2 lines', 1, true) ~= nil, 'two lines: a warning')
local sb = files['/earthRally/boards/lone-ridge.json']
T.check(sb and #sb.passes == 2 and sb.passes[2].run == 2, "its results' two passes")
T.check(#imp.scan() == 0, 'a zip unchanged: not imported again')
hashed = 0
T.check(#imp.scan() == 0 and hashed == 0, 'a zip whose size and time are unchanged: not even read (' .. hashed .. ')')
mtimes[IMP .. 'Brindle.zip'] = 5
T.check(#imp.scan() == 0 and hashed == 1, 'touched (new time, same bytes): read once, not imported')
hashed = 0
T.check(#imp.scan() == 0 and hashed == 0, 'and its new time remembered')
files[IMP .. 'Brindle.zip'] = 'zip bytes v2'          -- (the same size: the time says it changed)
mtimes[IMP .. 'Brindle.zip'] = 6
local r4 = imp.scan()
T.check(#r4 == 1 and r4[1].eventId == 'brindle-rally', 'its bytes changed: imported again, the same id')

------------------------------------------------------------------------------------------ packs that are wrong

files[IMP .. 'Future/season.json'] = J({ format = 2, name = 'Later', rounds = { { map = 'x.kml' } } })
files[IMP .. 'No Name/season.json'] = J({ format = 1, rounds = { { map = 'x.kml' } } })
files[IMP .. 'No Map/rally.json'] = J({ format = 1, name = 'Mapless' })
files[IMP .. 'Gone Map/rally.json'] = J({ format = 1, name = 'Lost', map = 'nowhere.kml' })
files[IMP .. 'Two/rally.json'] = J({ format = 1, map = 'a.kml' })
files[IMP .. 'Two/stage.json'] = J({ format = 1, map = 'a.kml' })
files[IMP .. 'Stuff/readme.txt'] = 'hello'
files[IMP .. 'Half/season.json'] = J({ format = 1, name = 'Half Season', rounds = {
  { round = 1, map = 'h.kml' }, { round = 2, name = 'No map here' } } })
files[IMP .. 'Half/h.kml'] = kml('Half One', { { 'Hollow', 55.0, -5.0, 20 } })
local r5 = imp.scan()
local function why(f) local x = find(r5, f) return x and not x.ok and x.why or '' end
T.check(why('Future'):find('format 2', 1, true) and why('Future'):find('format 1', 1, true),
  'format 2 refused, naming both numbers (' .. why('Future') .. ')')
T.check(why('No Name'):find('no name', 1, true), 'a season with no name refused')
T.check(why('No Map'):find('no map', 1, true), 'a rally with no map refused')
T.check(why('Gone Map'):find("can't find nowhere.kml", 1, true), 'a map that is not there')
T.check(why('Two'):find('more than one manifest', 1, true), 'two manifests refused')
T.check(why('Stuff'):find('not a rally pack', 1, true), 'a folder with no manifest reported')
local h = find(r5, 'Half')
T.check(h and h.ok and h.rallies == 1 and table.concat(h.warnings, ' '):find('round 2', 1, true),
  'a round with no map: left out with a warning, the rest imported')
T.check(#imp.scan() == 0, 'each told once, until it changes')

------------------------------------------------------------------------------------------ loose maps, packs gone

files[IMP .. 'Loose.kml'] = kml('Loose Rally', { { 'Loose Lane', 56.0, -6.0, 20 } })
local r6 = imp.scan()
T.check(#r6 == 1 and r6[1].ok and r6[1].eventId == 'loose' and r6[1].rallies == nil, 'a loose map: as it always was')
for f in pairs(files) do if f:find(IMP .. 'Test Series/', 1, true) == 1 then files[f] = nil end end
local r7 = imp.scan()
T.check(#r7 == 1 and r7[1].removed and r7[1].rallies == 2 and files['/earthRally/events/test-series-2030-fernvale-rally.json'],
  'a pack taken out: forgotten, its rallies kept')

-- the readers
local evs = require('earthRally/events')
evs.forget()
-- (#50) the pack taken out: its rallies off the list, their files kept; the loose map's and Brindle's still there
do
  local ids = {}
  for _, e in ipairs(evs.list(true)) do ids[e.id] = true end
  T.check(not ids['test-series-2030-fernvale-rally'] and files['/earthRally/events/test-series-2030-fernvale-rally.json'],
    'a pack taken out: its rallies not listed, their files kept')
  T.check(ids['loose'] and ids['brindle-rally'], 'the rallies whose files are in the folder: listed')
end
T.check(evs.season('test-series-2030') and evs.season('test-series-2030').rounds[2] == 'test-series-2030-quarry-hill-rally',
  'events.season')
T.check(#evs.seasons() == 2 and evs.seasons()[1].name == 'Half Season', 'events.seasons, by name')
T.check(evs.boards('brindle-rally') and evs.boards('brindle-rally').passes[1].field[1][2] == 'Ida Jones' and
  evs.boards('test-series-2030-quarry-hill-rally') == nil, 'events.boards')
T.check(pack._norm('a\\b/./c/../d.kml') == 'a/b/d.kml' and pack._norm('../x') == nil, 'paths: \\, . and ..')

------------------------------------------------------------------------------------------ the folder listing

do
  local kinds = {}
  for _, p in ipairs(pack.find()) do kinds[p.name] = p.kind end
  T.check(kinds['Brindle.zip'] == 'zip' and kinds['Loose.kml'] == nil and kinds['One Stage'] == 'folder',
    'find: the listing gives files too; only folders are folders, a .zip stays a zip')
end

------------------------------------------------------------------------------------------ ids that survive edits

local function warnings(list, file)
  local x = find(list, file)
  return table.concat(x and x.warnings or {}, ' | ')
end

do
  local P = IMP .. 'Edits/'
  local function season(rounds, id)
    files[P .. 'season.json'] = J({ format = 1, name = 'Edit Cup', id = id, rounds = rounds })
  end
  for _, m in ipairs({ 'a', 'b', 'c', 'j1', 'j2', 'j3' }) do
    files[P .. m .. '.kml'] = kml(m:upper() .. ' Rally', { { m:upper() .. ' One', 57.0, -7.0, 20 } })
  end
  season({ { round = 1, name = 'Alpha', map = 'a.kml' }, { round = 2, name = 'Bravo', map = 'b.kml' } })
  imp.scan()
  local sea = files['/earthRally/seasons/edit-cup.json']
  T.check(sea and sea.rounds[1] == 'edit-cup-alpha' and sea.rounds[2] == 'edit-cup-bravo',
    'round ids: <season>-<slug of the round name>')
  -- reordered, Bravo renamed (its map the same), Charlie put in front
  season({ { round = 1, name = 'Charlie', map = 'c.kml' }, { round = 2, name = 'Bravo Renamed', map = 'b.kml' },
           { round = 3, name = 'Alpha', map = 'a.kml' } })
  imp.scan()
  sea = files['/earthRally/seasons/edit-cup.json']
  T.check(sea.rounds[1] == 'edit-cup-charlie' and sea.rounds[2] == 'edit-cup-bravo' and sea.rounds[3] == 'edit-cup-alpha',
    'rounds reordered, one renamed, one added: every id stays with its rally (' .. table.concat(sea.rounds, ', ') .. ')')
  -- a map renamed, the round's name the same
  files[P .. 'a2.kml'] = files[P .. 'a.kml']
  season({ { round = 1, name = 'Charlie', map = 'c.kml' }, { round = 2, name = 'Bravo Renamed', map = 'b.kml' },
           { round = 3, name = 'Alpha', map = 'a2.kml' } })
  imp.scan()
  sea = files['/earthRally/seasons/edit-cup.json']
  T.check(sea.rounds[3] == 'edit-cup-alpha', 'a round whose map file was renamed: found by its name')

  -- two rounds of one name; the first taken out: the second keeps its id; a third of that name is a new rally
  season({ { round = 1, name = 'Juliet', map = 'j1.kml' }, { round = 2, name = 'Juliet', map = 'j2.kml' } })
  imp.scan()
  sea = files['/earthRally/seasons/edit-cup.json']
  T.check(sea.rounds[1] == 'edit-cup-juliet' and sea.rounds[2] == 'edit-cup-juliet-2', 'two rounds of one name')
  season({ { round = 1, name = 'Juliet', map = 'j2.kml' } })
  imp.scan()
  sea = files['/earthRally/seasons/edit-cup.json']
  T.check(sea.rounds[1] == 'edit-cup-juliet-2', 'the first taken out: the second keeps its id, not the first one\'s')
  season({ { round = 1, name = 'Juliet', map = 'j2.kml' }, { round = 2, name = 'Juliet', map = 'j3.kml' } })
  imp.scan()
  sea = files['/earthRally/seasons/edit-cup.json']
  T.check(sea.rounds[2] ~= 'edit-cup-juliet' and sea.rounds[2] ~= 'edit-cup-juliet-2',
    'an id is never given to a different rally of the season, even after its own round went (' ..
    tostring(sea.rounds[2]) .. ')')

  -- a broken edit keeps the ids for when it is put right
  files[P .. 'season.json'] = J({ format = 1, name = 'Edit Cup', rounds = {} })
  local rb = imp.scan()
  T.check(find(rb, 'Edits') and not find(rb, 'Edits').ok, 'a season with no rounds: refused')
  local ie = files['/earthRally/importIndex.json'].packs['Edits']
  T.check(ie.failed and ie.seasonId == 'edit-cup' and ie.eventIds and ie.eventIds[1] == 'edit-cup-juliet-2' and
    ie.rounds and #ie.rounds > 0, 'a failed import keeps the season id, rally ids and rounds it had')
  season({ { round = 1, name = 'Alpha', map = 'a2.kml' } })
  imp.scan()
  sea = files['/earthRally/seasons/edit-cup.json']
  T.check(sea and sea.id == 'edit-cup' and sea.rounds[1] == 'edit-cup-alpha', 'put right: the same ids again')

  -- the folder renamed (no id in its manifest): the season and its rounds keep their ids, nothing "taken out"
  local moved = {}
  for f, v in pairs(files) do if f:sub(1, #P) == P then moved[f] = v end end
  for f, v in pairs(moved) do files[f] = nil files[IMP .. 'Edit Cup 2' .. f:sub(#P)] = v end
  local rr = imp.scan()
  local rn = find(rr, 'Edit Cup 2')
  T.check(rn and rn.ok and rn.seasonId == 'edit-cup' and files['/earthRally/seasons/edit-cup.json'].rounds[1] ==
    'edit-cup-alpha' and files['/earthRally/seasons/edit-cup-2.json'] == nil,
    'a renamed folder adopts its old season id, not edit-cup-2 (' .. tostring(rn and (rn.seasonId or rn.why)) .. ')')
  T.check(find(rr, 'Edits') == nil, 'and the old name is not reported as taken out')

  -- ids fixed in the manifest go through the same check
  files[IMP .. 'Clash/rally.json'] = J({ format = 1, id = 'brindle-rally', name = 'Clash Rally', map = 'c.kml' })
  files[IMP .. 'Clash/c.kml'] = kml('Clash', { { 'Clash Lane', 58.5, -8.0, 20 } })
  files[IMP .. 'Bangs/rally.json'] = J({ format = 1, id = '!!!', name = 'Bang Rally', map = 'b.kml' })
  files[IMP .. 'Bangs/b.kml'] = kml('Bang', { { 'Bang Lane', 58.6, -8.0, 20 } })
  local rc = imp.scan()
  local c = find(rc, 'Clash')
  T.check(c and c.ok and c.eventId == 'brindle-rally-2' and warnings(rc, 'Clash'):find('brindle-rally', 1, true),
    'a manifest id another import has: a warning and a free one (' .. tostring(c and c.eventId) .. ')')
  T.check(files['/earthRally/events/brindle-rally.json'].name == 'Brindle Rally', 'the other rally not overwritten')
  T.check(find(rc, 'Bangs') and find(rc, 'Bangs').eventId == 'bang-rally', 'an id of "!!!": the name\'s slug')
end

------------------------------------------------------------------------------------------ nested folders, Mac zips

do
  files[IMP .. 'Nested/Nested/season.json'] = J({ format = 1, name = 'Nested Cup', rounds = {
    { round = 1, name = 'Deep', map = 'deep.kml' } } })
  files[IMP .. 'Nested/Nested/deep.kml'] = kml('Deep', { { 'Deep Lane', 59.0, -9.0, 20 } })
  files[IMP .. 'Nested/.DS_Store'] = 'x'
  files[IMP .. 'Nested/__MACOSX/Nested/._season.json'] = 'x'
  zips[IMP .. 'Mac.zip'] = {
    ['Mac Rally/rally.json'] = J({ format = 1, name = 'Mac Rally', map = 'mac.kml' }),
    ['Mac Rally/mac.kml'] = kml('Mac', { { 'Mac Lane', 59.5, -9.0, 20 } }),
    ['__MACOSX/Mac Rally/._rally.json'] = 'x', ['.DS_Store'] = 'x',
  }
  files[IMP .. 'Mac.zip'] = 'mac zip'
  local rn = imp.scan()
  local n = find(rn, 'Nested')
  T.check(n and n.ok and n.seasonId == 'nested-cup', 'a folder holding one folder (Extract All): its pack read (' ..
    tostring(n and (n.why or n.seasonId)) .. ')')
  local mz = find(rn, 'Mac.zip')
  T.check(mz and mz.ok and mz.eventId == 'mac-rally', 'a zip with __MACOSX/ and .DS_Store: its one folder found (' ..
    tostring(mz and (mz.why or mz.eventId)) .. ')')
end

------------------------------------------------------------------------------------------ a stage as points

do
  local line = {}
  for i = 0, 20 do line[#line + 1] = { 60.0 + i * 50 / 111195, -10.0, 100 + i } end
  files[IMP .. 'Kilo/stage.json'] = J({ format = 1, kind = 'stage', name = 'Kilo Hill', line = line,
    controls = { start = { lat = 60.0 + 50 / 111195, lon = -10.0 }, ff = { lat = 60.0 + 950 / 111195, lon = -10.0 } } })
  local rk = imp.scan()
  local k = find(rk, 'Kilo')
  local ke = files['/earthRally/events/kilo-hill.json']
  local ks = ke and ke.stages[1]
  T.check(k and k.ok and ks and ks.name == 'Kilo Hill' and #ks.line == 21, 'a stage given as a line, no map (' ..
    tostring(k and (k.why or k.eventId)) .. ')')
  T.check(ks and ks.controls.start and ks.controls.ff and math.abs(ks.controls.ff.distM - ks.controls.start.distM - 900) < 2
    and math.abs(require('earthRally/boards').stageLengthM(ks) - 900) < 2,
    'its controls on the line: start to flying finish 900 m')
end

------------------------------------------------------------------------------------------ images replaced

do
  local zb = zips[IMP .. 'Brindle.zip']
  zb['Brindle Rally/rally.json'] = J({ format = 1, name = 'Brindle Rally', map = 'brindle.kml', logo = 'art/logo.png',
    results = 'times.json' })
  zb['Brindle Rally/art/logo.png'] = 'PNG LOGO'
  files[IMP .. 'Brindle.zip'] = 'zip bytes v3'
  mtimes[IMP .. 'Brindle.zip'] = 7
  imp.scan()
  local be = files['/earthRally/events/brindle-rally.json']
  T.check(be.media.logo == '/earthRally/media/brindle-rally/logo.png' and
    files['/earthRally/media/brindle-rally/logo.png'] == 'PNG LOGO' and files['/earthRally/media/brindle-rally/logo.jpg'] == nil,
    'a .jpg logo replaced by a .png: the old one removed')
end

------------------------------------------------------------------------------------------ review round 2

local function ix() return files['/earthRally/importIndex.json'].packs end

-- round ids by the map's path inside the pack (a map.kml in every round's folder), the name's slug the tie-break
do
  local P = IMP .. 'Paths/'
  local function season(rounds) files[P .. 'season.json'] = J({ format = 1, name = 'Path Cup', rounds = rounds }) end
  files[P .. 'r1/map.kml'] = kml('North', { { 'North One', 61.0, -11.0, 20 } })
  files[P .. 'r2/map.kml'] = kml('South', { { 'South One', 61.1, -11.0, 20 } })
  files[P .. 'shared.kml'] = kml('Shared', { { 'Shared One', 61.2, -11.0, 20 } })
  season({ { round = 1, name = 'North', map = 'r1/map.kml' }, { round = 2, name = 'South', map = 'r2/map.kml' },
           { round = 3, name = 'Day One', map = 'shared.kml' }, { round = 4, name = 'Day Two', map = 'shared.kml' } })
  imp.scan()
  local sea = files['/earthRally/seasons/path-cup.json']
  T.check(sea and sea.rounds[1] == 'path-cup-north' and sea.rounds[2] == 'path-cup-south' and
    sea.rounds[3] == 'path-cup-day-one' and sea.rounds[4] == 'path-cup-day-two', 'paths: four rounds')
  T.check(ix()['Paths'].rounds[1].map == 'r1/map.kml', 'a round recorded by its map\'s path in the pack, lower case')
  -- reordered and both folder rounds renamed: each id stays with its map, not its position
  season({ { round = 1, name = 'Day Two', map = 'shared.kml' }, { round = 2, name = 'Southern', map = 'r2/map.kml' },
           { round = 3, name = 'Northern', map = 'r1/map.kml' }, { round = 4, name = 'Day One', map = 'shared.kml' } })
  imp.scan()
  sea = files['/earthRally/seasons/path-cup.json']
  T.check(sea.rounds[2] == 'path-cup-south' and sea.rounds[3] == 'path-cup-north',
    'two rounds both on a map.kml, reordered and renamed: each keeps its id by its path (' ..
    table.concat(sea.rounds, ', ') .. ')')
  T.check(sea.rounds[1] == 'path-cup-day-two' and sea.rounds[4] == 'path-cup-day-one',
    'two rounds on one map, reordered: the name\'s slug tells them apart')
  -- an index from before paths were recorded (bare file names): matched by file name where it is unique
  for _, r in ipairs(ix()['Paths'].rounds) do if r.id == 'path-cup-north' then r.map = 'one.kml' end end
  files[P .. 'r1/one.kml'] = files[P .. 'r1/map.kml']
  season({ { round = 1, name = 'Day Two', map = 'shared.kml' }, { round = 2, name = 'Southern', map = 'r2/map.kml' },
           { round = 3, name = 'Northern Again', map = 'r1/one.kml' }, { round = 4, name = 'Day One', map = 'shared.kml' } })
  imp.scan()
  T.check(files['/earthRally/seasons/path-cup.json'].rounds[3] == 'path-cup-north',
    'an old index\'s bare file name still finds its round')
end

-- a folder pack where the game gives no file stat: its bytes decide, so an edit is imported
do
  local P = IMP .. 'No Stat/'
  local stat = FS.stat
  FS.stat = function() return nil end
  files[P .. 'rally.json'] = J({ format = 1, name = 'No Stat Rally', map = 'm.kml' })
  files[P .. 'm.kml'] = kml('NS', { { 'Nostat Lane', 62.0, -12.0, 20 } })
  local r = imp.scan()
  T.check(find(r, 'No Stat') and find(r, 'No Stat').ok, 'no stat: imported')
  T.check(ix()['No Stat'].stat == nil, 'no stat: none recorded (not "missing" for every file)')
  T.check(find(imp.scan(), 'No Stat') == nil, 'no stat, unchanged: not imported again')
  files[P .. 'm.kml'] = kml('NS', { { 'Nostat Lane', 62.0, -12.0, 30 } })
  r = imp.scan()
  T.check(find(r, 'No Stat') and find(r, 'No Stat').ok and #files['/earthRally/events/no-stat-rally.json'].stages[1].line > 20,
    'no stat, the map edited: imported again')
  FS.stat = stat
end

-- a season given an id: the old season file goes; its rounds no longer listed are retired, not loose rallies
do
  local P = IMP .. 'Id Change/'
  files[P .. 'a.kml'] = kml('IA', { { 'Ia Lane', 63.0, -13.0, 20 } })
  files[P .. 'b.kml'] = kml('IB', { { 'Ib Lane', 63.1, -13.0, 20 } })
  files[P .. 'season.json'] = J({ format = 1, name = 'Idc Cup', rounds = {
    { round = 1, name = 'Alpha', map = 'a.kml' }, { round = 2, name = 'Bravo', map = 'b.kml' } } })
  imp.scan()
  T.check(files['/earthRally/seasons/idc-cup.json'] and files['/earthRally/events/idc-cup-alpha.json'], 'idc: imported')
  files[P .. 'season.json'] = J({ format = 1, id = 'idc-2030', name = 'Idc Cup', rounds = {
    { round = 1, id = 'idc-a', name = 'Alpha', map = 'a.kml' } } })
  local r = imp.scan()
  T.check(find(r, 'Id Change') and find(r, 'Id Change').seasonId == 'idc-2030' and
    files['/earthRally/seasons/idc-2030.json'] and files['/earthRally/seasons/idc-cup.json'] == nil,
    'the season\'s id changed: the old season file removed')
  local oa, ob = files['/earthRally/events/idc-cup-alpha.json'], files['/earthRally/events/idc-cup-bravo.json']
  T.check(oa and oa.retired and oa.retired.season == 'idc-2030' and ob and ob.retired and
    files['/earthRally/events/idc-a.json'].retired == nil, 'the rallies it no longer lists: kept, retired')
  -- Bravo back under its old id: written afresh, no longer retired
  files[P .. 'season.json'] = J({ format = 1, id = 'idc-2030', name = 'Idc Cup', rounds = {
    { round = 1, id = 'idc-a', name = 'Alpha', map = 'a.kml' }, { round = 2, id = 'idc-cup-bravo', name = 'Bravo', map = 'b.kml' } } })
  imp.scan()
  T.check(files['/earthRally/events/idc-cup-bravo.json'].retired == nil and
    files['/earthRally/events/idc-cup-bravo.json'].season.id == 'idc-2030', 'a retired round put back: not retired')
end

-- a renamed pack whose import then fails keeps the ids it took from its old name
do
  local P = IMP .. 'Ren A/'
  files[P .. 'season.json'] = J({ format = 1, name = 'Ren Cup', rounds = { { round = 1, name = 'Rone', map = 'r.kml' } } })
  files[P .. 'r.kml'] = kml('Ren', { { 'Ren Lane', 64.0, -14.0, 20 } })
  imp.scan()
  T.check(ix()['Ren A'] and ix()['Ren A'].seasonId == 'ren-cup', 'ren: imported')
  for f, v in pairs(files) do
    if f:sub(1, #P) == P then files[f] = nil if f:match('season%.json$') then files[IMP .. 'Ren B/season.json'] = v end end
  end
  local r = imp.scan()                     -- (Ren B: the same season, its map left behind: no round can be read)
  T.check(find(r, 'Ren B') and not find(r, 'Ren B').ok and find(r, 'Ren A') == nil, 'renamed and broken: refused')
  local e = ix()['Ren B']
  T.check(e and e.failed and e.seasonId == 'ren-cup' and e.eventIds and e.eventIds[1] == 'ren-cup-rone',
    'the failed import keeps the ids it adopted (' .. tostring(e and e.seasonId) .. ')')
  files[IMP .. 'Ren B/r.kml'] = kml('Ren', { { 'Ren Lane', 64.0, -14.0, 20 } })
  r = imp.scan()
  T.check(find(r, 'Ren B') and find(r, 'Ren B').seasonId == 'ren-cup' and
    files['/earthRally/seasons/ren-cup.json'].rounds[1] == 'ren-cup-rone', 'put right: the same ids')
end

-- a pack gone, its rallies kept; in the same scan a pack of another kind with the same slug: not written over
do
  files[IMP .. 'Kind A/rally.json'] = J({ format = 1, name = 'Same Name', map = 'k.kml' })
  files[IMP .. 'Kind A/k.kml'] = kml('KA', { { 'Ka Lane', 65.0, -15.0, 20 } })
  imp.scan()
  T.check(files['/earthRally/events/same-name.json'] and files['/earthRally/events/same-name.json'].pack.file == 'Kind A',
    'kind a: imported')
  files[IMP .. 'Kind A/rally.json'], files[IMP .. 'Kind A/k.kml'] = nil, nil
  files[IMP .. 'Kind B/stage.json'] = J({ format = 1, name = 'Same Name', map = 'k.kml' })
  files[IMP .. 'Kind B/k.kml'] = kml('KB', { { 'Kb Lane', 65.5, -15.0, 20 } })
  local r = imp.scan()
  local kb = find(r, 'Kind B')
  T.check(kb and kb.ok and kb.eventId == 'same-name-2' and files['/earthRally/events/same-name.json'].pack.file == 'Kind A',
    'the kept rally is not overwritten: the new pack is same-name-2 (' .. tostring(kb and (kb.eventId or kb.why)) .. ')')
end

-- review round 3: a round that could not be read this time is retired (it is not in the season now, whatever id it
-- was given); an event file another pack has written under a round's old id is never marked
do
  local P = IMP .. 'Retire/'
  files[P .. 'a.kml'] = kml('RA', { { 'Ra Lane', 67.0, -17.0, 20 } })
  files[P .. 'b.kml'] = kml('RB', { { 'Rb Lane', 67.1, -17.0, 20 } })
  files[P .. 'c.kml'] = kml('RC', { { 'Rc Lane', 67.2, -17.0, 20 } })
  files[P .. 'season.json'] = J({ format = 1, name = 'Ret Cup', rounds = {
    { round = 1, name = 'Alpha', map = 'a.kml' }, { round = 2, name = 'Bravo', map = 'b.kml' },
    { round = 3, name = 'Charlie', map = 'c.kml' } } })
  imp.scan()
  T.check(files['/earthRally/events/ret-cup-bravo.json'] and files['/earthRally/events/ret-cup-charlie.json'],
    'retire: imported')
  -- Bravo's map now has no line (its id is given, its rally cannot be made); Charlie taken out, and its event file
  -- meanwhile written by another pack
  files[P .. 'b.kml'] = kml('RB', {})
  files['/earthRally/events/ret-cup-charlie.json'].pack = { file = 'Other Pack' }
  files[P .. 'season.json'] = J({ format = 1, name = 'Ret Cup', rounds = {
    { round = 1, name = 'Alpha', map = 'a.kml' }, { round = 2, name = 'Bravo', map = 'b.kml' } } })
  imp.scan()
  local sea = files['/earthRally/seasons/ret-cup.json']
  local b, c = files['/earthRally/events/ret-cup-bravo.json'], files['/earthRally/events/ret-cup-charlie.json']
  T.check(sea and #sea.rounds == 1 and b and type(b.retired) == 'table',
    'a round given its id but not made this time: not in the season, retired')
  T.check(c and c.retired == nil, "an event file another pack wrote under an old round's id: not marked retired")
  T.check(files['/earthRally/events/ret-cup-alpha.json'].retired == nil, 'a round still in the season: not retired')
  -- Bravo put right: written afresh, not retired
  files[P .. 'b.kml'] = kml('RB', { { 'Rb Lane', 67.1, -17.0, 20 } })
  imp.scan()
  T.check(files['/earthRally/events/ret-cup-bravo.json'].retired == nil, 'put right: no longer retired')
end

-- Windows' Thumbs.db and desktop.ini are not part of a pack
do
  T.check(pack._ignored('Thumbs.db') and pack._ignored('THUMBS.DB') and pack._ignored('Desktop.ini') and
    pack._ignored('__MACOSX') and pack._ignored('.DS_Store') and not pack._ignored('season.json'), 'ignored names')
  files[IMP .. 'Thumby/Thumby/rally.json'] = J({ format = 1, name = 'Thumb Rally', map = 't.kml' })
  files[IMP .. 'Thumby/Thumby/t.kml'] = kml('T', { { 'Thumb Lane', 66.0, -16.0, 20 } })
  files[IMP .. 'Thumby/Thumbs.db'] = 'x'
  files[IMP .. 'Thumby/desktop.ini'] = 'x'
  local r = imp.scan()
  T.check(find(r, 'Thumby') and find(r, 'Thumby').ok, 'a folder holding one folder and Thumbs.db: its pack read')
end

------------------------------------------------------------------------------------------ 1.5.0: the organisers' points
-- A pack's maps go through the same reader: the converter's "#pt-<kinds>" points, in each stage's Folder, become
-- the stage's marks in the written event.
do
  local lat0, lon0 = 67.0, -17.0
  local function pt(name, style, alongM, eastM)
    return string.format('<Placemark><name>%s</name><styleUrl>%s</styleUrl><Point><coordinates>%.7f,%.7f,0'
      .. '</coordinates></Point></Placemark>', name, style,
      lon0 + eastM / (111195 * math.cos(math.rad(lat0))), lat0 + alongM / 111195)
  end
  files[IMP .. 'Marked/rally.json'] = J({ format = 1, name = 'Marked Rally', map = 'm.kml' })
  files[IMP .. 'Marked/m.kml'] = '<?xml version="1.0"?><kml><Document><name>Marked</name><Folder><name>SS1 Fjord</name>'
    .. '<Placemark><name>SS1 Fjord</name><LineString><coordinates>' .. northLine(lat0, lon0, 30)
    .. '</coordinates></LineString></Placemark>'
    .. pt('Radio 1', '#pt-radio', 300, 5) .. pt('Hairpin', '#pt-spectator-marshal', 800, -10)
    .. pt('Caution', '#pt-caution', 900, 0) .. '</Folder></Document></kml>'
  local r = imp.scan()
  local d = find(r, 'Marked')
  local ev = d and d.ok and files['/earthRally/events/marked-rally.json']
  local got = {}
  for _, m in ipairs(ev and ev.stages[1].marks or {}) do got[#got + 1] = m.kind .. ':' .. m.name end
  T.check(table.concat(got, ' | ') == 'radio:Radio 1 | spectator:Hairpin | marshal:Hairpin',
    'a pack\'s map: its #pt- points the stage\'s marks (' .. table.concat(got, ' | ') .. ')')
end

------------------------------------------------------------------------------------------ the real ARA pack

local ARA = 'C:/Users/Station/Documents/Claude/Rally Files/ARA Nationals 2026'
local probe = io.open(ARA .. '/season.json', 'rb')
if not probe then
  print('test_pack: the ARA Nationals 2026 pack is not on this computer; its test skipped')
else
  probe:close()
  -- (the pack's folder read from disk; everything written kept in memory)
  local root = IMP .. 'ARA Nationals 2026/'
  local function disk(f)
    if f:sub(1, #root) ~= root then return nil end
    local h = io.open(ARA .. '/' .. f:sub(#root + 1), 'rb')
    if not h then return nil end
    local s = h:read('*a')
    h:close()
    return s
  end
  files, zips = { ['/earthRally/importIndex.json'] = { format = 1, files = {}, names = imp.NAME_RULES } }, {}
  local mem = files
  readFile = function(f) return type(mem[f]) == 'string' and mem[f] or disk(f) end
  FS.fileExists = function(_, f) return mem[f] ~= nil or disk(f) ~= nil end
  FS.copyFile = function(_, a, b) mem[b] = '(copy of ' .. a .. ')' return disk(a) ~= nil end
  FS.directoryList = function(_, dir) return dir == IMP and { IMP .. 'ARA Nationals 2026' } or {} end
  FS.directoryExists = function(_, d) return d == IMP .. 'ARA Nationals 2026' end
  FS.stat = function() return nil end
  FS.findFiles = function(_, dir, pat)
    if dir == root and pat == '*.json' then return { root .. 'season.json' } end
    local out = {}
    for f in pairs(mem) do if f:sub(1, #dir) == dir and f:match('%.json$') and pat == '*.json' then out[#out + 1] = f end end
    return out
  end
  jsonReadFile = function(f) return type(mem[f]) == 'table' and mem[f] or nil end

  local ra = imp.scan()
  local a = ra[1]
  T.check(#ra == 1 and a.ok and a.rallies == 8, 'ARA: 8 rallies (' .. tostring(a and (a.why or a.rallies)) .. ')')
  local unjoined = {}
  for _, w in ipairs(a and a.warnings or {}) do if w:find('results', 1, true) then unjoined[#unjoined + 1] = w end end
  T.check(#unjoined == 0, 'ARA: every results stage joined to a line (' .. table.concat(unjoined, '; ') .. ')')
  local araSeason = mem['/earthRally/seasons/ara-nationals-2026.json']
  local rounds = araSeason and araSeason.rounds or {}
  local B = require('earthRally/boards')
  local sorted, passes, overLine, overFF, allLine, unranked = true, 0, 0, 0, 0, {}
  for r = 1, 8 do
    local ev = mem['/earthRally/events/' .. tostring(rounds[r]) .. '.json']
    local bd = mem['/earthRally/boards/' .. tostring(rounds[r]) .. '.json']
    for _, ps in ipairs(bd and bd.passes or {}) do
      passes = passes + 1
      for i = 2, #ps.field do if ps.field[i][1] < ps.field[i - 1][1] then sorted = false end end
      local st = ev and B.stageOf(ev, ps)
      if st and B.isMismatch(st.lengthM, ps.km) then allLine = allLine + 1 end
      if not ps.cancelled and st then
        if B.isMismatch(st.lengthM, ps.km) then overLine = overLine + 1 end
        if B.isMismatch(B.stageLengthM(st), ps.km) then overFF = overFF + 1 end
      end
    end
    if not bd then sorted = false end
    -- (each rally under the 75% rule, on the map's lines: how many of its counted passes are comparable, their km)
    if ev and bd then
      local bests = {}
      for _, s in ipairs(ev.stages) do bests[s.id] = 100 end
      local res = B.rallyResult(ev, bd, bests)
      unranked[#unranked + 1] = string.format('%s %s %d/%d passes %.0f/%.0f km', ev.name,
        res.notRanked and 'NOT RANKED' or 'ranked', res.comparable, res.counted, res.kmCovered, res.kmTotal)
      if res.notRanked and (res.you or #res.lineMismatch == 0) then sorted = false end
      if not res.notRanked and not res.you then sorted = false end
    end
  end
  T.check(sorted and passes == 125, 'ARA: every pass\'s field fastest first (' .. passes .. ' passes)')
  -- (what the 5% rule makes of the real season: printed, not checked, as it is the organisers' maps that decide)
  print(string.format('test_pack: ARA passes over 5%% off: %d of 125 on the whole line (%d of the counted ones); '
    .. '%d counted ones start to flying finish. Rallies: %s', allLine, overLine, overFF,
    table.concat(unranked, '; ')))
  local oj = mem['/earthRally/events/ara26-ojibwe-forests.json']
  local ob = mem['/earthRally/boards/ara26-ojibwe-forests.json']
  local run = {}
  for _, ps in ipairs(ob and ob.passes or {}) do run[ps.stage] = true end
  local unrun = {}
  for _, s in ipairs(oj and oj.stages or {}) do if not run[s.id] then unrun[#unrun + 1] = s.name end end
  table.sort(unrun)
  T.check(#unrun == 2 and unrun[1] == 'Perkins' and unrun[2] == 'Tulaby Lake',
    "ARA: Ojibwe's two lines never run, Perkins and Tulaby Lake (" .. table.concat(unrun, ', ') .. ')')
  T.check(oj and oj.place == 'Bemidji, MN' and #oj.itinerary == 16 and oj.itinerary[3].cancelled == true and
    oj.media.cover == '/earthRally/media/ara26-ojibwe-forests/cover.png',
    'ARA: Ojibwe\'s place, itinerary, cover')
  T.check(#rounds == 8 and rounds[8] == 'ara26-lake-superior', 'ARA: the season, its ids from the manifest')
  -- (1.7.0) each rally's full-rally running order, as rally.lua makes it from the imported event: printed for the
  -- owner to read against the itinerary (the developer check the plan asks for), checked only for what every round
  -- has -- a service, a stage after it
  local R = require('earthRally/rally')
  local allRun = true
  local placesMissing = {}     -- (1.7.0, service on the map: '@' in the print is a stop with its place)
  for r = 1, 8 do
    local ev = mem['/earthRally/events/' .. tostring(rounds[r]) .. '.json']
    local rr = ev and R.new(ev, { cancelled = 'all' })
    local parts, svc = {}, 0
    for _, it in ipairs(rr and rr.order or {}) do
      if it.kind == 'stage' then parts[#parts + 1] = it.ss .. (it.cancelledReal and '(x)' or '')
      else
        parts[#parts + 1] = '[' .. it.label .. (it.place and '@' or '') .. ']'
        if it.kind == 'service' then svc = svc + 1 end
        if not it.place then placesMissing[#placesMissing + 1] = (ev and ev.name or '?') .. ' ' .. it.label end
      end
    end
    if not (rr and svc > 0) then allRun = false end
    print(string.format('test_pack: full rally %s: %s', ev and ev.name or tostring(rounds[r]), table.concat(parts, ' ')))
  end
  T.check(allRun, 'ARA: every round runs as a full rally, with at least one service')
  -- (the rally-loop plan) every round is timed, and driven exactly to the schedule -- each stage started at its first
  -- car's printed start, through its lateness time -- every due time at a time control falls in the few minutes
  -- before that stage's printed start (the time control's own minute; ARA: 3 min before the start)
  local wt = require('earthRally/worldTime')
  local timedAll, dues, off = true, 0, {}
  for r = 1, 8 do
    local ev = mem['/earthRally/events/' .. tostring(rounds[r]) .. '.json']
    local rr = ev and R.new(ev, { cancelled = 'all' })
    if not (rr and rr.timed) then timedAll = false
    else
      for i, it in ipairs(rr.order) do
        if it.kind == 'stage' then
          local st = wt.parse(it.date, it.firstCar)
          local due = R.dueFor(rr, i)
          if due and st then
            dues = dues + 1
            if not (st - due >= 0 and st - due <= 5 * 60) then
              off[#off + 1] = string.format('%s %s (%+d min)', ev.name, it.ss, (st - due) / 60)
            end
          end
          rr.lastOut = R.timeOut(it, st, nil)
        end
      end
    end
  end
  T.check(timedAll, 'ARA: every round is timed')
  print(string.format('test_pack: ARA due times worked out on the schedule: %d; off it: %s', dues,
    #off > 0 and table.concat(off, '; ') or 'none'))
  T.check(dues > 100, 'ARA: due times worked out (' .. dues .. ')')
  print('test_pack: stops with no place on the map: ' .. (#placesMissing > 0 and table.concat(placesMissing, '; ') or 'none'))
  T.check(#placesMissing == 0, 'ARA: every start, service and overnight has its place on the map')
end

------------------------------------------------------------------------------------------ the schedule (review fixes)
do
  local warns = {}
  local function w(m) warns[#warns + 1] = m end
  local ev = { event = { timezone = 'Australia/Perth' }, itinerary = {
    { control = 'SVC A OUT', type = 'SVC_OUT', date = '2030-03-01', first_car = '10:00' },
    { control = 'TC1', type = 'TC', target_min = 10 },
    { control = 'SS1', type = 'SS', stage = 'Ghost Road', run = 1, lateness_min = 5, day = 1 },
    -- (a regional crew's own control: not ours; and one naming National among others: ours)
    { control = 'TC1R', type = 'TC', target_min = 99, classes = { 'Regional' } },
    { control = 'TC2', type = 'TC', target_min = 20, classes = { 'ARC National 2WD', 'Regional' } },
    { control = 'SS2', type = 'SS', stage = 'Fernvale South', run = 1, lateness_min = 6, day = 1 },
  } }
  local out = pack._itineraryOf(ev, {}, { ['Fernvale South'] = 'fern_s' }, w)
  T.check(#out == 1 and out[1].ss == 'SS2', 'schedule: the pass with a line kept')
  -- (E) SS1 has no line: its lateness goes on to SS2's road section, from the service's out time too
  T.check(out[1].targetMin == 35, 'schedule: no-line pass lateness in targetMin (' .. tostring(out[1].targetMin) .. ')')
  T.check(out[1].outTargetMin == 35, 'schedule: no-line pass lateness in outTargetMin ('
    .. tostring(out[1].outTargetMin) .. ')')
  T.check(out[1].outAt == '10:00', 'schedule: the service out time carried')
  -- (S) the class filter: substring, any case; a warning for the dropped row only
  local dropped = 0
  for _, m in ipairs(warns) do if m:find('TC1R', 1, true) then dropped = dropped + 1 end end
  T.check(dropped == 1, 'class filter: one warning for the regional-only row')
  local kept = true
  for _, m in ipairs(warns) do if m:find('TC2', 1, true) then kept = false end end
  T.check(kept, "class filter: 'ARC National 2WD' kept, no warning")
end

T.done('test_pack')
