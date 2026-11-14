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
local J = T.jsonEncode

FS = {
  directoryExists = function() return true end, directoryCreate = function() end,
  fileExists = function(_, f) return files[f] ~= nil end,
  removeFile = function(_, f) files[f] = nil end,
  copyFile = function(_, a, b)
    if files[a] == nil then return false end
    files[b], copied[b] = files[a], a
    return true
  end,
  -- (every depth, whatever is asked: the importer must not take a map inside a pack for a loose one)
  findFiles = function(_, dir, pat)
    local ext = pat:match('^%*%.(.+)$'):gsub('%.', '%%.')
    local out = {}
    for f in pairs(files) do
      if f:sub(1, #dir) == dir and f:lower():match('%.' .. ext:lower() .. '$') then out[#out + 1] = f end
    end
    table.sort(out)
    return out
  end,
  directoryList = function(_, dir)
    local seen, out = {}, {}
    for f in pairs(files) do
      local sub = f:sub(1, #dir) == dir and f:sub(#dir + 1):match('^([^/]+)/')
      if sub and not seen[sub] then seen[sub] = true out[#out + 1] = dir .. sub end
    end
    table.sort(out)
    return out
  end,
}
function readFile(f) return type(files[f]) == 'string' and files[f] or nil end
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
      cover = 'covers/fern cover.PNG', photo = 'covers/missing.jpg' },
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
T.check(season and #season.rounds == 2 and season.rounds[1] == 'test-series-2030-r1' and
  season.rounds[2] == 'test-series-2030-r2', 'rounds in order, ids <season>-r<round>')
T.check(season and season.standings.championship == 'national' and season.standings.points[1] == 10 and
  #season.standings.points == 3 and season.standings.best == nil, 'standings: its points, the default championship')

local e1 = files['/earthRally/events/test-series-2030-r1.json']
T.check(e1 and e1.format == 1 and e1.name == 'Fernvale Rally' and e1.id == 'test-series-2030-r1', 'round 1 written')
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
T.check(e1 and e1.rules.falseStartS[2] == 60 and e1.rules.startIntervalMin == 2 and e1.rules.lateSPerMin == 10 and
  e1.rules.note == nil, "rules: the season's and the event file's numbers, nothing else")
T.check(e1 and e1.media.cover == '/earthRally/media/test-series-2030-r1/cover.png' and
  files['/earthRally/media/test-series-2030-r1/cover.png'] == 'PNGBYTES' and e1.media.photo == nil,
  'the cover copied to the media folder, lower-case extension; a missing photo not recorded')
T.check(e1 and e1.boards == 'test-series-2030-r1.json' and e1.pack.file == 'Test Series' and
  e1.pack.fingerprint ~= nil, 'boards and pack named')

local b = files['/earthRally/boards/test-series-2030-r1.json']
T.check(b and b.format == 1 and #b.passes == 3, 'boards: three passes (the one with no line left out)')
local p1 = b and b.passes[1]
T.check(p1 and p1.ss == 'SS1' and p1.stage == 'fernvale-south' and p1.run == 1 and p1.km == 3.0 and not p1.cancelled,
  'a pass joined to its stage id')
T.check(p1 and #p1.field == 3 and p1.field[1][1] == 175.2 and p1.field[1][2] == 'Cy Dale' and p1.field[1][3] == '3'
  and p1.field[3][6] == true and p1.field[1][6] == false, 'its field fastest first, notional flagged, no-time row out')
T.check(b and b.passes[3].cancelled == true and #b.passes[3].field == 0, 'a cancelled pass')
T.check(b and #b.overall == 3 and b.overall[1][2] == 'Cy Dale' and b.overall[2][2] == 'Ada Brook' and
  b.overall[3][2] == 'Ed Finch' and b.overall[3][6] == false and b.overall[1][6] == true,
  'overall: classified fastest first, then the rest; "result" missing reads as classified')
local oldMill = false
for _, s in ipairs(e1 and e1.stages or {}) do if s.id == 'old-mill' then oldMill = true end end
local runOld = false
for _, ps in ipairs(b and b.passes or {}) do if ps.stage == 'old-mill' then runOld = true end end
T.check(oldMill and not runOld, 'a line never run is a stage with no passes')

local warned = false
for _, w in ipairs(d and d.warnings or {}) do if w:find('Ghost Road', 1, true) then warned = true end end
T.check(warned, 'a results stage with no line: a warning')
local rep = table.concat((imp.lastReports['test-series-2030-r1'] or {}).lines or {}, '\n')
T.check(rep:find('results SS4 "Ghost Road": no line of that name in the map', 1, true) ~= nil,
  'and in the import report, in its usual shape')
T.check(rep:find("can't find the photo image", 1, true) ~= nil, 'the missing image reported too')

local e2 = files['/earthRally/events/test-series-2030-r2.json']
T.check(e2 and e2.name == 'Quarry Hill Rally' and e2.season.round == 2, 'round 2: named from its map')
T.check(e2 and #e2.itinerary == 2 and e2.itinerary[1].ss == 'SS1' and e2.itinerary[1].stage == 'quarry-hill' and
  e2.itinerary[2].stage == 'quarry-loop', 'no event file: the map in order')
T.check(e2 and e2.boards == nil and e2.media == nil and files['/earthRally/boards/test-series-2030-r2.json'] == nil,
  'no results: no boards')
T.check(e2 and e2.rules.falseStartS[1] == 10 and e2.rules.lateSPerMin == nil, "the season's rules on every round")

T.check(#imp.scan() == 0, 'unchanged: not imported again')
fernResults.stages[1].times[1].seconds = 170.0
files[S .. 'results/fernvale.json'] = J(fernResults)
local r2 = imp.scan()
T.check(#r2 == 1 and r2[1].ok and files['/earthRally/boards/test-series-2030-r1.json'].passes[1].field[1][1] == 170.0,
  'a file the manifest names changed: imported again')
local sj = T.jsonDecode(files[S .. 'season.json'])
sj.name = 'Test Series 2030 (final)'
files[S .. 'season.json'] = J(sj)
imp.scan()
T.check(files['/earthRally/seasons/test-series-2030.json'].name == 'Test Series 2030 (final)' and
  files['/earthRally/events/test-series-2030-r1.json'].season.name == 'Test Series 2030 (final)',
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
files[IMP .. 'Brindle.zip'] = 'zip bytes v2'
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
T.check(#r7 == 1 and r7[1].removed and r7[1].rallies == 2 and files['/earthRally/events/test-series-2030-r1.json'],
  'a pack taken out: forgotten, its rallies kept')

-- the readers
local evs = require('earthRally/events')
evs.forget()
T.check(evs.season('test-series-2030') and evs.season('test-series-2030').rounds[2] == 'test-series-2030-r2',
  'events.season')
T.check(#evs.seasons() == 2 and evs.seasons()[1].name == 'Half Season', 'events.seasons, by name')
T.check(evs.boards('brindle-rally') and evs.boards('brindle-rally').passes[1].field[1][2] == 'Ida Jones' and
  evs.boards('test-series-2030-r2') == nil, 'events.boards')
T.check(pack._norm('a\\b/./c/../d.kml') == 'a/b/d.kml' and pack._norm('../x') == nil, 'paths: \\, . and ..')

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
  local sorted, passes = true, 0
  for r = 1, 8 do
    local bd = mem['/earthRally/boards/ara-nationals-2026-r' .. r .. '.json']
    for _, ps in ipairs(bd and bd.passes or {}) do
      passes = passes + 1
      for i = 2, #ps.field do if ps.field[i][1] < ps.field[i - 1][1] then sorted = false end end
    end
    if not bd then sorted = false end
  end
  T.check(sorted and passes == 125, 'ARA: every pass\'s field fastest first (' .. passes .. ' passes)')
  local oj = mem['/earthRally/events/ara-nationals-2026-r6.json']
  local ob = mem['/earthRally/boards/ara-nationals-2026-r6.json']
  local run = {}
  for _, ps in ipairs(ob and ob.passes or {}) do run[ps.stage] = true end
  local unrun = {}
  for _, s in ipairs(oj and oj.stages or {}) do if not run[s.id] then unrun[#unrun + 1] = s.name end end
  table.sort(unrun)
  T.check(#unrun == 2 and unrun[1] == 'Perkins' and unrun[2] == 'Tulaby Lake',
    "ARA: Ojibwe's two lines never run, Perkins and Tulaby Lake (" .. table.concat(unrun, ', ') .. ')')
  T.check(oj and oj.place == 'Bemidji, MN' and #oj.itinerary == 16 and oj.itinerary[3].cancelled == true and
    oj.media.cover == '/earthRally/media/ara-nationals-2026-r6/cover.png', 'ARA: Ojibwe\'s place, itinerary, cover')
  T.check(mem['/earthRally/seasons/ara-nationals-2026.json'].rounds[8] == 'ara-nationals-2026-r8', 'ARA: the season')
end

T.done('test_pack')
