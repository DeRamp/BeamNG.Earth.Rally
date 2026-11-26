-- The hand-made rally files (textPack.lua, docs/rally-file.md "Hand-made files"): the downloadable templates imported
-- as they ship, then the ways a person gets them wrong, each with the problem the import report gives.
local T = dofile(TESTS .. '/testlib.lua')
function log() end
local imp = require('earthRally/importer')
local pack = require('earthRally/pack')
local R = require('earthRally/textRead')

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

local written = {}           -- path -> text (writeFile: the import reports)
function writeFile(f, s) written[f] = s files[f] = s return true end
local IMP = '/earthRally/import/'
local function find(list, file)
  for _, d in ipairs(list) do if d.file == file then return d end end
end
local ROOT = TESTS .. '/../templates/Earth Rally templates/'
local function template(rel)
  local f = assert(io.open(ROOT .. rel, 'rb'))
  local s = f:read('*a')
  f:close()
  return s
end
local function has(list, needle)
  for _, p in ipairs(list or {}) do
    local t = type(p) == 'table' and ((p.what or '') .. ' ' .. (p.fix or '')) or tostring(p)
    if t:find(needle, 1, true) then return p end
  end
  return nil
end
local function clear(prefix) for k in pairs(files) do if k:sub(1, #prefix) == prefix then files[k] = nil end end end

-- a line north from (lat0, lon0), n points 50 m apart
local function northLine(lat0, lon0, n)
  local out = {}
  for i = 0, n - 1 do out[#out + 1] = string.format('%.7f,%.7f,0', lon0, lat0 + i * 50 / 111195) end
  return table.concat(out, ' ')
end
local function kml(doc, lines)
  local out = { '<?xml version="1.0"?><kml><Document><name>' .. doc .. '</name>' }
  for _, l in ipairs(lines) do
    out[#out + 1] = '<Placemark><name>' .. l[1] .. '</name><LineString><coordinates>' .. northLine(l[2], l[3], l[4])
      .. '</coordinates></LineString></Placemark>'
  end
  out[#out + 1] = '</Document></kml>'
  return table.concat(out, '\n')
end
local forestKml = kml('My map', { { 'Meaford Mills', 60.00, -10.00, 40 }, { 'Kilo Hill', 60.03, -10.05, 30 },
  { 'Long Gap', 60.06, -10.10, 50 } })

------------------------------------------------------------------------------------------ the rally template as it ships
local RA = IMP .. 'My Rally/'
files[RA .. 'rally.txt'] = template('My Rally/rally.txt')
-- (the example rows taken in, as a person keeping them would)
local function examples(s) return (s:gsub('\n# (SS%d)', '\n%1')) end
files[RA .. 'results.csv'] = examples(template('My Rally/results.csv'))
files[RA .. 'weather.csv'] = examples(template('My Rally/weather.csv'))
files[RA .. 'my stages.kml'] = forestKml
local r1 = imp.scan()
local d = find(r1, 'My Rally')
if DEBUG then
  for k, v in pairs(d or {}) do print(k, v) end
  for _, w in ipairs(d and (d.warnings or d.problems) or {}) do print('  W', pack.whyText(w)) end
end
T.check(d and d.ok and d.name == 'My Forest Rally' and d.stages == 3, 'the rally template imports as it ships')
local ev = jsonReadFile('/earthRally/events/my-forest-rally.json')
T.check(ev and #ev.itinerary == 6, 'six passes')
local function pass(ss) for _, p in ipairs(ev.itinerary) do if p.ss == ss then return p end end end
T.check(pass('SS3').stage == 'meaford-mills' and pass('SS3').run == 2, 'a stage listed again is its second run')
T.check(pass('SS1').km == 10.46 and pass('SS6').powerStage == true, 'length and power stage')
T.check(pass('SS5').day == 2 and pass('SS5').date == '2031-02-08', 'Day 2: the next day, dated from Dates')
T.check(ev.dates.from == '2031-02-07' and ev.place == 'Fernvale', 'dates and town')
T.check(ev.rules.falseStartS[3] == 180 and ev.rules.lateSPerMin == 10 and ev.rules.startIntervalMin == 2, 'rules')
local stops = ev.rallyStops or {}
T.check(#stops == 3 and stops[1].kind == 'service' and stops[1].after == 2 and stops[1].place.lat == 60.0102,
  'Service at a place, with its position')
T.check(stops[2].kind == 'overnight' and stops[2].place.name == 'Ridge Hotel', 'the overnight at the next start')
T.check(ev.rallyStart and ev.rallyStart.name == 'Fernvale Park', 'the rally starts at its Start')
T.check(pass('SS1').weather and pass('SS1').weather.code == 3 and pass('SS1').weather.cover.total == 90
  and pass('SS2').weather.code == 61 and pass('SS6').weather.fog == true and pass('SS3').weather == nil, 'weather')
local bd = jsonReadFile('/earthRally/boards/my-forest-rally.json')
T.check(bd and #bd.passes == 3 and #bd.passes[1].field == 3 and #bd.passes[2].field == 2, 'results: DNF left out')
T.check(bd.passes[2].field[2][6] == true and bd.passes[3].cancelled and pass('SS3').cancelled, 'notional; cancelled')
T.check(#d.warnings == 0, 'no problems')
local rep = written[RA .. 'import report.txt']
T.check(rep and rep:find('\r\nIMPORTED\r\n', 1, true) and rep:find('3 crews on 3 stages', 1, true),
  'the import report written in the folder')
-- the examples left as they ship: no made-up crews or weather in the rally
clear(RA)
files[RA .. 'rally.txt'] = template('My Rally/rally.txt')
files[RA .. 'results.csv'] = template('My Rally/results.csv')
files[RA .. 'weather.csv'] = template('My Rally/weather.csv')
files[RA .. 'my stages.kml'] = forestKml
local r0 = find(imp.scan(), 'My Rally')
local e0 = jsonReadFile('/earthRally/events/my-forest-rally.json')
local b0 = jsonReadFile('/earthRally/boards/my-forest-rally.json')
T.check(r0 and r0.ok and #r0.warnings == 0 and e0.itinerary[1].weather == nil and (not b0 or #b0.passes == 0),
  'the template as it ships: imports clean, its example rows not used')
files[RA .. 'results.csv'] = examples(template('My Rally/results.csv'))
files[RA .. 'weather.csv'] = examples(template('My Rally/weather.csv'))
imp.scan()

-- (the template's timed running order: the plain one taken out, the # taken off the timed one)
local function timedRally()
  local s = template('My Rally/rally.txt')
  s = s:gsub('\nRunning order:\n.-\n\n\n', '\n\n\n', 1)
  local head, tail = s:match('^(.*\n)(# Running order:.*)$')
  tail = tail:gsub('\n# ?', '\n'):gsub('^# ?', '')
  return head .. tail
end
files[RA .. 'rally.txt'] = timedRally()
local r2 = imp.scan()
local tev = jsonReadFile('/earthRally/events/my-forest-rally.json')
local tp = {}
for _, p in ipairs(tev.itinerary) do tp[p.ss] = p end
T.check(find(r2, 'My Rally') and find(r2, 'My Rally').ok, 'the timed template imports')
T.check(tev.timing and tev.timing.start.time == '08:00' and tev.timing.timezone == 'Europe/London', 'timed: start')
T.check(tp.SS1.firstCar == '08:23' and tp.SS1.targetMin == 20 and tp.SS1.latenessMin == 10, 'timed: SS1')
T.check(tp.SS3.targetMin == 82 and tp.SS3.outAt == '09:40' and tp.SS3.inType == 'SVC_IN', 'timed: after service')
T.check(tp.SS6.targetMin == 100, 'timed: a control only for Regional not counted')
T.check(tev.timing.earlyFree.MTC_IN and tev.timing.earlyFree.RGC_IN, 'early is free at')
T.check(tev.rallyStops[2].outAt == '08:00' and tev.rallyStops[2].place.name == 'Ridge Hotel', 'timed: the overnight')

------------------------------------------------------------------------------------------ mistakes
local function scanWith(rally, extra)
  clear(RA)
  files[RA .. 'my stages.kml'] = forestKml
  files[RA .. 'rally.txt'] = rally
  for k, v in pairs(extra or {}) do files[RA .. k] = v end
  local r = imp.scan()
  return find(r, 'My Rally'), jsonReadFile('/earthRally/events/my-forest-rally.json')
end
local BASE = 'Rally: My Forest Rally\nMap: my stages.kml\nDates: 7-8 Feb 2031\n'

-- a stage name a slip of the map's
local m1 = scanWith(BASE .. 'Running order:\n  SS1 Meaford Mills\n  SS2  Kilo Hil\n')
local pr = has(m1.warnings, 'no stage called "Kilo Hil"')
T.check(m1.ok and pr and pr.line == 6 and pr.what:find('Read as "Kilo Hill"', 1, true), 'stage typo: read as, line 6')
-- a name that is nothing like a stage: left out, the rest run
local m2, e2 = scanWith(BASE .. 'Running order:\n  SS1 Meaford Mills\n  SS2 Banana Road\n  SS3 Kilo Hill\n')
T.check(m2.ok and has(m2.warnings, 'no stage called "Banana Road"') and #e2.itinerary == 2
  and e2.itinerary[2].ss == 'SS3', 'unknown stage: left out, SS numbers kept')
-- the map named wrongly, one map in the folder
local m3 = scanWith('Rally: X\nMap: stages.kml\n')
T.check(m3.ok and has(m3.warnings, 'used my stages.kml'), 'wrong map name: the one map used')
-- no Map line at all
local m4 = scanWith('Rally: X\n')
T.check(m4.ok and m4.stages == 3, 'no Map line: the one map used')
-- no map in the folder
clear(RA)
files[RA .. 'rally.txt'] = 'Rally: X\nMap: nowhere.kml\n'
local m5 = find(imp.scan(), 'My Rally')
T.check(m5 and not m5.ok and m5.problem.what:find('no nowhere.kml', 1, true) and m5.problem.line == 2,
  'no map: not imported, with the line')
T.check(written[RA .. 'import report.txt']:find('NOT IMPORTED', 1, true), 'a report for a pack that failed')
-- fixed: looked at again
files[RA .. 'my stages.kml'] = forestKml
files[RA .. 'rally.txt'] = 'Rally: X\nMap: my stages.kml\n'
local m6 = find(imp.scan(), 'My Rally')
T.check(m6 and m6.ok, 'a failed pack put right is imported')
T.check(find(imp.scan(), 'My Rally') == nil, 'and not again while unchanged')
-- the report written into the folder does not make it new
files[RA .. 'import report.txt'] = 'changed by hand'
T.check(find(imp.scan(), 'My Rally') == nil, 'the report is not part of the pack')
-- keys every way
local m7, e7 = scanWith('rally = My Forest Rally\nMAP  my stages\nDATE: Feb 7-8, 2031\nTown: "Fernvale"\n'
  .. 'Organiser: Fernvale Motor Club\nDatse: x\n')
T.check(m7.ok and e7.name == 'My Forest Rally' and e7.dates.to == '2031-02-08' and e7.place == 'Fernvale',
  'keys with = and none, map without its extension, quotes')
T.check(has(m7.warnings, 'Not something the game uses') and has(m7.warnings, 'Did you mean "dates"'),
  'an unknown key skipped; a slip of one named')
-- rally.json beside rally.txt
local m8 = scanWith(BASE, { ['rally.json'] = '{"name": "Old"}' })
T.check(m8.ok and m8.warnings[1].what:find('rally.json and rally.txt are both', 1, true), 'the .txt wins, said first')
-- UTF-16 from Notepad, Windows line ends
local function utf16(s)
  local out = { '\255\254' }
  for i = 1, #s do out[#out + 1] = s:sub(i, i) .. '\0' end
  return table.concat(out)
end
local m9, e9 = scanWith(utf16((BASE .. 'Running order:\n  Kilo Hill\n'):gsub('\n', '\r\n')))
T.check(m9.ok and #e9.itinerary == 1 and e9.itinerary[1].stage == 'kilo-hill', 'UTF-16 with CRLF')
-- places: swapped, unknown, an area
local m10, e10 = scanWith(BASE .. 'Place: Park\n  At: -10.0451, 60.0102\n  Area: 1,2; 3,4\nRunning order:\n'
  .. '  Meaford Mills\n  Service at Prak\n  Kilo Hill\n  Regroup at Town Hall\n  Long Gap\n')
T.check(has(m10.warnings, 'looks like longitude first'), 'longitude first, found by the map')
T.check(e10.rallyStops[1].place and math.abs(e10.rallyStops[1].place.lat - 60.0102) < 1e-9, 'and used swapped')
T.check(has(m10.warnings, 'No place called "Prak". Read as "Park"'), 'a place typo')
T.check(has(m10.warnings, '"Town Hall" is not one of your places'), 'a place nobody gave')
local area = has(m10.warnings, 'Service areas are not used yet')
T.check(area and area.level == 'unused', 'an Area: read, not used yet')
-- results from Excel in Europe: semicolons, decimal commas, a broken time, a column per stage
local m11 = scanWith(BASE .. 'Running order:\n  Meaford Mills\n  Kilo Hill\n', {
  ['results.csv'] = 'Car;Driver;SS1;SS2;SS9\n1;A;6:39,4;5:12;\n2;B;5.20.3;DNS;\n' })
local bd11 = jsonReadFile('/earthRally/boards/my-forest-rally.json')
T.check(m11.ok and bd11 and #bd11.passes == 2 and bd11.passes[1].field[1][1] == 399.4, 'wide results with ;')
local bt = has(m11.warnings, '"5.20.3" is not a time')
T.check(bt and bt.line == 3 and bt.file == 'results.csv', 'a broken time: its line')
T.check(has(m11.warnings, 'There is no SS9'), 'a results column for a pass that does not exist')
-- times with no date
local m12 = scanWith('Rally: X\nRunning order:\n  08:00 Start\n  Kilo Hill\n')
T.check(has(m12.warnings, 'no date, so the times are not used'), 'times without a date')
-- a line nobody can read
local m13 = scanWith(BASE .. 'Running order:\n  Kilo Hill\n  have a nice day\n')
T.check(has(m13.warnings, 'neither a stage in the map nor a stop'), 'an unreadable running order line')

-- (handoff review) a time written 8h23 at the front; a stage named like a month; lists that must not end early
local marshKml = kml('M', { { 'Marsh Road', 60.00, -10.00, 30 }, { 'Kilo Hill', 60.03, -10.05, 30 } })
local function scanMap(rally, map)
  clear(RA)
  files[RA .. 'my stages.kml'] = map
  files[RA .. 'rally.txt'] = rally
  return find(imp.scan(), 'My Rally'), jsonReadFile('/earthRally/events/my-forest-rally.json')
end
local h1, he1 = scanMap(BASE .. 'Running order:\n  8h00 Start at Park\n  08h23  SS1 Marsh Road\n  Rally start: Park\n'
  .. '  Marsh Road 20 min\nStart interval 2 min\nStart interval: 3 min\n', marshKml)
T.check(h1.ok and he1.itinerary[1].firstCar == '08:23' and he1.itinerary[1].stage == 'marsh-road',
  '8h23 at the front is a time; Marsh Road is a stage, not March')
T.check(#he1.itinerary == 2 and he1.itinerary[2].run == 2, '"Rally start:" inside the list stays in it')
T.check(he1.rules and he1.rules.startIntervalMin == 2, '"Start interval 2 min" after the list is a setting')
T.check(has(h1.warnings, 'Start interval is set twice'), 'and the second one said')
-- an impossible date: said once, not again and again
local d1 = scanMap('Rally: X\nDates: 30/02/2031\n', forestKml)
T.check(d1 and d1.ok and has(d1.warnings, 'not a day of the year'), 'Dates 30/02: said, the rally imported')
T.check(find(imp.scan(), 'My Rally') == nil, 'and not imported again while unchanged')
-- a position off the Earth: one problem, not a crash
local pz = scanMap(BASE .. 'Place: Park\n  At: N 60.01 W 190.04\n', forestKml)
T.check(pz and pz.ok and has(pz.warnings, 'not a position'), 'a position off the Earth: a problem')
-- results naming a stage the running order calls something else
local rn = scanMap(BASE .. 'Running order:\n  Meaford Mills\n', forestKml)
files[RA .. 'results.csv'] = 'SS,Stage,Driver,Time\nSS1,Mill Road,A,6:00\nSS1,Mill Road,B,6:10\n'
local rn2 = find(imp.scan(), 'My Rally')
local said = 0
for _, w in ipairs(rn2.warnings) do if type(w) == 'table' and w.what:find('"Mill Road" here', 1, true) then said = said + 1 end end
T.check(said == 1, 'results calling SS1 another name: used by its SS, said once')
-- line.csv with no header and a height column
clear(RA)
files[IMP .. 'Hill/stage.txt'] = 'Stage: Hill\nLine: line.csv\n'
files[IMP .. 'Hill/line.csv'] = '60.0,-10.0,100\n60.00045,-10.0001,101\n60.0009,-10.0002,102\n'
local hl = find(imp.scan(), 'Hill')
local hev = hl and hl.eventId and jsonReadFile('/earthRally/events/' .. hl.eventId .. '.json')
T.check(hl and hl.ok and hev and #hev.stages[1].line == 3, 'line.csv with no header: its first point kept')
clear(IMP .. 'Hill/')

local tp = require('earthRally/textPack')
local q1 = tp._pieces('SS1 Kilo Hill 1 hr 30')
local q2 = tp._pieces('ATC 2 hrs')
local q3 = tp._pieces('ATC 1 hour 30 min')
local q4 = tp._pieces('12.50 km Kilo Hill')
T.check(q1.target == 90 and q2.target == 120 and q3.target == 90 and q2.rest == 'ATC', 'hours written every way')
T.check(q4.time == nil and q4.km == 12.5, '12.50 km at the front is a length')
-- a map taken out after it failed: its report goes with it
files[IMP .. 'Broken.kml'] = '<kml><Document></Document></kml>'
imp.scan()
T.check(files[IMP .. 'Broken.kml - import report.txt'] ~= nil, 'a failed map has its report')
files[IMP .. 'Broken.kml'] = nil
imp.scan()
T.check(files[IMP .. 'Broken.kml - import report.txt'] == nil, 'taken out: its report too')

------------------------------------------------------------------------------------------ the stage template
local ST = IMP .. 'My Stage/'
clear(RA)
files[ST .. 'stage.txt'] = template('My Stage/stage.txt'):gsub('\nMap: [^\n]*', ''):gsub('\n# Line:', '\nLine:')
files[ST .. 'line.csv'] = template('My Stage/line.csv')
local s1 = find(imp.scan(), 'My Stage')
T.check(s1 and s1.ok and s1.stages == 1 and s1.name == 'Kilo Hill', 'the stage template with line.csv')
local se = jsonReadFile('/earthRally/events/kilo-hill.json')
T.check(se and #se.stages[1].line >= 4, 'its line')
files[ST .. 'stage.txt'] = template('My Stage/stage.txt')
files[ST .. 'line.csv'] = nil
files[ST .. 'kilo hill.kml'] = kml('X', { { 'Kilo Hill', 60.03, -10.05, 30 } })
local s2 = find(imp.scan(), 'My Stage')
T.check(s2 and s2.ok and s2.stages == 1, 'the stage template with a map')

------------------------------------------------------------------------------------------ the season template
clear(ST)
local SE = IMP .. 'My Season/'
files[SE .. 'season.txt'] = template('My Season/season.txt')
files[SE .. 'My First Round/rally.txt'] = template('My Season/My First Round/rally.txt')
files[SE .. 'My First Round/my stages.kml'] = forestKml
local z1 = find(imp.scan(), 'My Season')
if DEBUG and z1 then for _, w in ipairs(z1.warnings or z1.problems or {}) do print('  W', pack.whyText(w)) end print(z1.why) end
T.check(z1 and z1.ok and z1.rallies == 1 and z1.name == 'My Forest Series 2031', 'the season template imports')
local sz = jsonReadFile('/earthRally/seasons/my-forest-series-2031.json')
T.check(sz and sz.standings.points[1] == 25 and sz.standings.championship == 'National' and #sz.rounds == 1,
  'standings')
local rz = jsonReadFile('/earthRally/events/' .. sz.rounds[1] .. '.json')
T.check(rz and rz.season.round == 1 and #rz.itinerary == 4 and rz.rallyStops[1].kind == 'service', 'its round')
-- no Rounds list: every rally folder, in date order
files[SE .. 'season.txt'] = 'Season: Two\n'
files[SE .. 'Later/rally.txt'] = 'Rally: Later\nDates: 1 Mar 2031\n'
files[SE .. 'Later/my stages.kml'] = forestKml
local z2 = find(imp.scan(), 'My Season')
local s2f = z2 and jsonReadFile('/earthRally/seasons/' .. z2.seasonId .. '.json')
T.check(z2 and z2.ok and z2.rallies == 2 and s2f and jsonReadFile('/earthRally/events/' .. s2f.rounds[2] .. '.json')
  .name == 'Later', 'rounds found by themselves, in date order')
-- a round whose folder is misspelt, and one that is not there
files[SE .. 'season.txt'] = 'Season: Two\nRounds:\n  1  My Frist Round\n  2  Nowhere\n  3 Later\n'
local z3 = find(imp.scan(), 'My Season')
T.check(z3 and z3.ok and z3.rallies == 2 and has(z3.warnings, 'used "My First Round"')
  and has(z3.warnings, 'no folder or map called "Nowhere"'), 'round folders: a slip used, a missing one said')
-- a folder named with a year in front
files[SE .. '2031 Rally Wales/rally.txt'] = 'Rally: Wales\n'
files[SE .. '2031 Rally Wales/my stages.kml'] = forestKml
files[SE .. 'season.txt'] = 'Season: Two\nCount only: Masters\nRounds:\n  2031 Rally Wales\n'
files[SE .. '2031 Rally Wales/results.csv'] = 'SS,Driver,Championship,Time\nSS1,A,National,6:00\n'
local z4 = find(imp.scan(), 'My Season')
T.check(z4 and z4.ok and z4.rallies == 1, 'a round folder with a year in front')
T.check(has(z4.warnings, 'season standings are empty'), 'standings that would be empty: said')
-- every round failing: the reason is a round's, said once
files[SE .. 'season.txt'] = 'Season: Two\nPoints: 10 5\nPoints: 3\nRounds:\n  Nowhere Else\n  1 Gone\n'
local z5 = find(imp.scan(), 'My Season')
T.check(z5 and not z5.ok and not z5.problem.what:find('set twice', 1, true), 'a failed season: not a minor note as its reason ('
  .. tostring(z5 and z5.why) .. ')')

------------------------------------------------------------------------------------------ the templates folder dropped in whole
clear(SE)
local TF = IMP .. 'Earth Rally templates/'
files[TF .. 'READ ME FIRST.txt'] = template('READ ME FIRST.txt')
files[TF .. 'My Rally/rally.txt'] = template('My Rally/rally.txt')
files[TF .. 'My Stage/stage.txt'] = template('My Stage/stage.txt')
local tf = find(imp.scan(), 'Earth Rally templates')
T.check(tf and not tf.ok and tf.problem.what:find('My Rally', 1, true) and tf.problem.fix:find('on its own', 1, true),
  'the whole templates folder: told to put each folder in on its own')

-- broken JSON: where it goes wrong
clear(TF)
local JF = IMP .. 'Old Pack/'
files[JF .. 'rally.json'] = '{\n  "name": "Old",\n  "map": "m.kml",\n  "event": e.json\n}'
local jf = find(imp.scan(), 'Old Pack')
T.check(jf and not jf.ok and jf.problem.line == 4 and jf.problem.what:find('needs "quotes"', 1, true),
  'broken JSON: its line and what is wrong (' .. tostring(jf and jf.why) .. ')')
T.check(select(3, pack._jsonWhere('{"a": 1\n "b": 2}')):find('comma is missing', 1, true), 'a missing comma')
T.check(pack._jsonWhere('{"a": 1,}') and select(3, pack._jsonWhere('{"a": 1,}')):find('comma before }', 1, true),
  'a trailing comma')
T.check(pack._jsonWhere('{"a": 1} ') == nil, 'good JSON: nothing to say')

T.done('test_textpack')
