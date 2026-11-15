-- The in-game importer on hand-made maps: KML (namespaces, CDATA, folders, a stage in pieces, MultiGeometry), GPX,
-- name matching ("SS1 Kuhnle" / "Kuhnle Start", typos reported), and the folder scan against a stand-in file system.
local T = dofile(TESTS .. '/testlib.lua')
function log() end
local imp = require('earthRally/importer')

-- a line north from (lat0, lon0), n points 50 m apart
local function northLine(lat0, lon0, n, from)
  local out = {}
  for i = from or 0, n - 1 do out[#out + 1] = string.format('%.7f,%.7f,0', lon0, lat0 + i * 50 / 111195) end
  return table.concat(out, ' ')
end

local kml = [[<?xml version="1.0" encoding="UTF-8"?>
<kml:kml xmlns:kml="http://www.opengis.net/kml/2.2"><kml:Document><kml:name>Test &amp; Rally 2026</kml:name>
<kml:Folder><kml:name>Stages</kml:name>
<kml:Placemark>]] .. '<kml:name><![CDATA[SS1 Kuhnle]]></kml:name>' .. [[<kml:ExtendedData><kml:Data name="x"><kml:displayName>no</kml:displayName></kml:Data></kml:ExtendedData>
 <kml:MultiGeometry><kml:LineString><kml:coordinates>]] .. northLine(47.0, -123.0, 21, 0) .. [[</kml:coordinates></kml:LineString>
 <kml:LineString><kml:coordinates>]] .. northLine(47.0, -123.0, 41, 20) .. [[</kml:coordinates></kml:LineString></kml:MultiGeometry></kml:Placemark>
<kml:Placemark><kml:name>Dayton V2</kml:name><kml:LineString><kml:coordinates>]] .. northLine(47.1, -123.0, 30) .. [[</kml:coordinates></kml:LineString></kml:Placemark>
</kml:Folder>
<kml:Placemark><kml:name>Kuhnle Start</kml:name><kml:Point><kml:coordinates>-123.0,47.0,0</kml:coordinates></kml:Point></kml:Placemark>
<kml:Placemark><kml:name>Kuhnle FF</kml:name><kml:Point><kml:coordinates>-123.0,]] .. string.format('%.7f', 47.0 + 1950 / 111195) .. [[,0</kml:coordinates></kml:Point></kml:Placemark>
<kml:Placemark><kml:name>Daytn Stop</kml:name><kml:Point><kml:coordinates>-123.0,47.12,0</kml:coordinates></kml:Point></kml:Placemark>
<kml:Placemark><kml:name>Service Park</kml:name><kml:Point><kml:coordinates>-123.01,47.05,0</kml:coordinates></kml:Point></kml:Placemark>
<kml:Placemark><kml:name>Spectator area</kml:name><kml:Polygon><kml:outerBoundaryIs><kml:LinearRing><kml:coordinates>-123,47 -123.001,47 -123,47.001 -123,47</kml:coordinates></kml:LinearRing></kml:outerBoundaryIs></kml:Polygon></kml:Placemark>
</kml:Document></kml:kml>]]

local p = imp.parse(kml, 'kml')
T.check(p.name == 'Test & Rally 2026', 'the document name, entities decoded (' .. tostring(p.name) .. ')')
T.check(#p.lines == 2, 'two lines (' .. #p.lines .. ')')
T.check(p.lines[1].name == 'SS1 Kuhnle' and #p.lines[1].pieces == 2, 'CDATA name, a stage in two pieces')
T.check(#p.points == 4, 'four points; the polygon is not one (' .. #p.points .. ')')

local ev, rep = imp.build(p, 'test', p.name, 'test.kml')
T.check(ev and #ev.stages == 2, 'two stages')
local k = ev.stages[1]
T.check(k.id == 'kuhnle', '"SS1 Kuhnle" is the stage kuhnle (' .. k.id .. ')')
T.check(k.controls.start and k.controls.ff, '"Kuhnle Start" and "Kuhnle FF" are its controls')
T.near(k.lengthM, 2000, 1, 'the pieces joined: 2 km')
T.check(k.gapsM[1] < 1, 'joined end to end, no gap')
T.near(k.controls.ff.distM, 1950, 1, 'the flying finish 1950 m along')
T.check(ev.stages[2].id == 'dayton' and not ev.stages[2].controls.stop, 'Dayton V2 is dayton; "Daytn Stop" not matched')
local un = rep.unmatched[1]
T.check(un and un.name == 'Daytn Stop' and un.suggest == 'Dayton V2', 'the typo reported with a suggestion')
T.check(#ev.points == 4 and ev.source.file == 'test.kml', 'every point kept, the source file named')
local lines = imp.reportLines(rep)
T.check(#lines >= 3 and table.concat(lines, '\n'):find('did you mean Dayton V2') ~= nil, 'the report says it')
T.near(k.radiusM, 1000, 1, 'the enclosing circle of a straight 2 km line: 1 km round')

-- driving direction from the flying finish when there is no start: a line drawn finish-first is turned round
local rev = imp.parse([[<kml><Document><Placemark><name>Hill</name><LineString><coordinates>]] ..
  northLine(47.2, -123.0, 20) .. [[</coordinates></LineString></Placemark>
  <Placemark><name>Hill Flying Finish</name><Point><coordinates>-123.0,47.2,0</coordinates></Point></Placemark>
  </Document></kml>]], 'kml')
local ev2 = imp.build(rev, 'r', 'R', 'r.kml')
T.check(math.abs(ev2.stages[1].line[#ev2.stages[1].line][1] - 47.2) < 1e-6, 'the stage ends at its flying finish')

-- GPX: tracks in segments, a route, waypoints
local gpx = [[<?xml version="1.0"?><gpx version="1.1"><metadata><name>GPX Rally</name></metadata>
<wpt lat="47.3" lon="-123.0"><name>Ridge Start</name></wpt>
<trk><name>Ridge</name><trkseg><trkpt lat="47.3" lon="-123.0"></trkpt><trkpt lat="47.301" lon="-123.0"/></trkseg>
<trkseg><trkpt lat='47.301' lon='-123.0'/><trkpt lat="47.302" lon="-123.0"/></trkseg></trk>
<rte><name>Valley</name><rtept lat="47.4" lon="-123.0"/><rtept lat="47.401" lon="-123.0"/></rte></gpx>]]
local g = imp.parse(gpx, 'gpx')
T.check(g.name == 'GPX Rally' and #g.lines == 2 and #g.points == 1, 'GPX: name, a track and a route, a waypoint')
T.check(g.lines[1].name == 'Ridge' and #g.lines[1].pieces == 2, 'the track in its two segments')
local gev = imp.build(g, 'g', g.name, 'g.gpx')
T.check(gev.stages[1].controls.start ~= nil, 'the waypoint is the start')

-- nothing to make stages from
local none, nrep = imp.build(imp.parse('<kml><Placemark><name>x</name><Point><coordinates>1,2</coordinates></Point></Placemark></kml>', 'kml'), 'n', 'N', 'n.kml')
T.check(none == nil and nrep.warnings[1]:find('no lines'), 'a map with no lines: no rally, and why')

------------------------------------------------------------------------------------------ the folder

local files = {}
local removed = {}
FS = {
  directoryExists = function() return true end, directoryCreate = function() end,
  fileExists = function(_, f) return files[f] ~= nil end,
  removeFile = function(_, f) files[f] = nil removed[#removed + 1] = f end,
  findFiles = function(_, dir, pat)
    local ext = pat:match('^%*%.(.+)$'):gsub('%.', '%%.')
    local out = {}
    for f in pairs(files) do
      if f:sub(1, #dir) == dir and not f:sub(#dir + 1):find('/') and f:match('%.' .. ext .. '$') then out[#out + 1] = f end
    end
    table.sort(out)
    return out
  end,
}
function readFile(f) return type(files[f]) == 'string' and files[f] or nil end
function jsonWriteFile(f, d) files[f] = d return true end
function jsonReadFile(f) return type(files[f]) == 'table' and files[f] or nil end

files['/earthRally/import/Test Rally.kml'] = kml
-- an event from tools/import_kml.py made from the same file before: its id is kept (its recces belong to it)
files['/earthRally/events/oldid.json'] = { format = 1, id = 'oldid', source = { file = 'Test Rally.kml' }, stages = {} }
local r1 = imp.scan()
T.check(#r1 == 1 and r1[1].ok and r1[1].eventId == 'oldid' and r1[1].stages == 2, 'imported, under the old id')
T.check(files['/earthRally/events/oldid.json'].name == 'Test & Rally 2026', 'the event written')
T.check(#imp.scan() == 0, 'unchanged: not imported again')
files['/earthRally/import/Test Rally.kml'] = kml:gsub('Dayton V2', 'Dayton V3')
local r2 = imp.scan()
T.check(#r2 == 1 and r2[1].ok, 'changed: imported again')
files['/earthRally/import/broken.gpx'] = '<gpx></gpx>'
local r3 = imp.scan()
T.check(#r3 == 1 and not r3[1].ok and r3[1].why:find('no lines'), 'a map with no lines: reported, nothing written')
files['/earthRally/import/Test Rally.kml'] = nil
local r4 = imp.scan()
local gone = false
for _, x in ipairs(r4) do if x.removed and x.eventId == 'oldid' then gone = true end end
T.check(gone and files['/earthRally/events/oldid.json'] ~= nil, 'the file taken out: forgotten, its rally kept')
-- an edit that keeps the file's length is seen
files['/earthRally/import/Same.kml'] = kml
imp.scan()
files['/earthRally/import/Same.kml'] = kml:gsub('Kuhnle FF', 'Kuhnle Ff')
local r5 = imp.scan()
T.check(#r5 == 1 and r5[1].ok, 'an edit of the same length: imported again')
T.check(#imp.scan(true) >= 1, 'Re-scan imports every file again')
-- X.kml and X.kmz: two rallies, not one
files['/earthRally/import/Same.kmz'] = 'x'
ZipArchive = function() return { openArchiveName = function() return true end,
  getFileList = function() return { 'doc.kml' } end, readFileToMemory = function() return kml end,
  close = function() end } end
local r6 = imp.scan()
T.check(#r6 == 1 and r6[1].ok and r6[1].eventId == 'same-2', 'a .kmz beside a .kml of the same name: its own rally ('
  .. tostring(r6[1] and r6[1].eventId) .. ')')
-- a KML saved by a browser as X.kml.xml: imported, named without either extension
files['/earthRally/import/2026 SOFR Friday KML.kml.xml'] = kml
local r7 = imp.scan()
T.check(#r7 == 1 and r7[1].ok and r7[1].eventId == '2026-sofr-friday-kml', 'a .kml.xml imported as a KML ('
  .. tostring(r7[1] and (r7[1].eventId or r7[1].why)) .. ')')
T.check(imp._text('Craig&#8217;s') == 'Craig\226\128\153s', 'a numeric entity as UTF-8')

-- The naming rules moving on re-imports every map, because a map already imported is otherwise skipped while its
-- bytes have not changed -- and the three identical "Main Route Book" rallies are already on the author's machine.
-- The ids must survive it, or their recces, matched lines and times stop belonging to them.
do
  local before = {}
  for f, e in pairs(files['/earthRally/importIndex.json'].files or {}) do
    if e.eventId then before[f] = e.eventId end
  end
  T.check(next(before) ~= nil, 'there are maps already imported to re-import')
  T.check(files['/earthRally/importIndex.json'].names == imp.NAME_RULES,
    'the index records which naming rules wrote it')
  T.check(#imp.scan() == 0, 'nothing to do while the rules have not moved')

  files['/earthRally/importIndex.json'].names = imp.NAME_RULES - 1
  local rr = imp.scan()
  T.check(#rr >= 2, 'the rules moved on: every map read again (' .. #rr .. ')')
  local kept = true
  for f, id in pairs(before) do
    if (files['/earthRally/importIndex.json'].files[f] or {}).eventId ~= id then kept = false end
  end
  T.check(kept, 'and every rally kept its id, so its recces and times still belong to it')
  T.check(files['/earthRally/importIndex.json'].names == imp.NAME_RULES, 'the index now says so')
  T.check(#imp.scan() == 0, 'and it is not asked for again on the next start')

  -- ... including when there was nothing in the folder to re-import, which is the only case where the index would
  -- otherwise never be written and the re-import would be asked for on every single start
  for f in pairs(files) do if f:find('/earthRally/import/', 1, true) == 1 then files[f] = nil end end
  imp.scan()                                     -- (the maps gone: forgotten, their rallies kept)
  T.check(#imp.scan() == 0, 'an empty import folder: nothing to do')
  files['/earthRally/importIndex.json'].names = imp.NAME_RULES - 1
  -- (watching the write itself, not the table: this stand-in hands back the stored table, so the scan setting the
  --  field on it would look like a save whether or not one happened)
  local wroteIndex = false
  local realWrite = jsonWriteFile
  jsonWriteFile = function(f, d)
    if f == '/earthRally/importIndex.json' then wroteIndex = true end
    return realWrite(f, d)
  end
  T.check(#imp.scan() == 0, 'the rules moved on with an empty folder: still nothing to do')
  jsonWriteFile = realWrite
  T.check(wroteIndex, 'but the index is written anyway, so the re-import is not asked for on every start')
end

------------------------------------------------------------------------------------------ naming a rally
-- Roadmap item 4. The twelve maps imported on the author's machine, 2026-11-14, are the fixture: three of them
-- came in as "Main Route Book" and two carried ".kmz" in the middle of their name.
do
  local function nm(doc, file) return imp.eventName(doc, file) end

  -- the three that collided: the document says nothing, so the file names tell them apart
  T.check(nm('Main Route Book', '2026 SOFR Thursday KML.kml.xml') == '2026 SOFR Thursday',
    'a generic document name gives way to the file (' .. nm('Main Route Book', '2026 SOFR Thursday KML.kml.xml') .. ')')
  T.check(nm('Main Route Book', '2026 SOFR Friday KML.kml.xml') == '2026 SOFR Friday', '... Friday')
  T.check(nm('(Main Route Book)', '2026 SOFR Saturday KML.kml.xml') == '2026 SOFR Saturday',
    '... and Saturday, whose document name was in brackets')
  T.check(nm('Main Route Book', '2026 SOFR Friday KML.kml.xml') ~= nm('Main Route Book', '2026 SOFR Saturday KML.kml.xml'),
    'so no two of them read the same in the menu')

  -- the two that carried an extension in the organiser's own document name
  T.check(nm('2026 Overmountain - Publish v2.kmz', '2026 Overmountain - Publish v2.kmz') ==
    '2026 Overmountain - Publish v2', 'a document name ending .kmz loses it')
  T.check(nm('V1_Rally_Colorado_2026_Controls_and_Route.kmz', 'V1_Rally_Colorado_2026_Controls_and_Route.kmz') ==
    'V1 Rally Colorado 2026 Controls and Route', 'and underscores read as spaces')

  -- the seven that were already right are left exactly as they were
  for _, c in ipairs({
    { '2026 LSPR Friday', '2026 LSPR Friday.kmz' },
    { '2026 LSPR Saturday', '2026 LSPR Saturday.kmz' },
    { '2026 OFR', '2026 OFR.kmz' },
    { '2026 SnoDrift Rally Maps - Competitors', '2026 SnoDrift Rally Maps - Competitors.kmz' },
    { '2026-100 Acre Wood', '2026-100 Acre Wood.kml' },
    { 'OTR 2024 Final', 'OTR 2024 Final.kml' },
    { 'V4 Olympus Rally 26', 'V4 Olympus Rally 26.kml' },
  }) do
    T.check(nm(c[1], c[2]) == c[1], 'left alone: ' .. c[1] .. ' (' .. nm(c[1], c[2]) .. ')')
  end

  -- no document name at all: the file, tidied
  T.check(nm(nil, 'Olympus_Rally_2026.kml') == 'Olympus Rally 2026', 'no document name: the file name, tidied')
  T.check(nm('', 'doc.kml') == 'doc', 'an empty document name does the same')
  T.check(nm('   ', 'Snow Rally.gpx') == 'Snow Rally', 'and so does a document name of spaces')
  T.check(nm('Untitled map', 'Deep Forest.kmz') == 'Deep Forest', "Google My Maps' own default is generic too")
  T.check(nm('Maps', 'Deep Forest.kmz') == 'Deep Forest', 'so is "Maps"')
  T.check(nm('Main Route Book', nil) == 'Main Route Book',
    'nothing to fall back to: the generic name is still better than no name')
  T.check(nm(nil, nil) == 'Rally', 'and neither leaves something to show')

  -- a rally really called "Route 66" is not generic: only the whole name counts
  T.check(nm('Route 66 Rally', 'x.kml') == 'Route 66 Rally', 'a name that merely contains a generic word is kept')
  T.check(nm('Main Street Stages', 'x.kml') == 'Main Street Stages', '... and so is this one')

  -- cleanName and genericName on their own
  T.check(imp.cleanName('a.kml.xml') == 'a', 'cleanName: both halves of .kml.xml')
  T.check(imp.cleanName('Rally  2026 ') == 'Rally 2026', 'cleanName: doubled spaces and a trailing one')
  T.check(imp.cleanName('Olympus KML') == 'Olympus', 'cleanName: a trailing format word')
  T.check(imp.cleanName('KML') == 'KML', '... unless that is the whole of it')
  T.check(imp.genericName('ROUTE BOOK') and imp.genericName('route-book') and imp.genericName('  Routes '),
    'genericName: case, punctuation and spaces do not matter')
  T.check(not imp.genericName('Dalles Mountain'), 'genericName: a real name is not generic')
end

------------------------------------------------------------------------------------------ 1.5.0: the organisers' points
-- Each point classified radio / medical / spectator / marshal from the pack converter's "#pt-<kinds>" style, else
-- from the organisers' folders, style, name and description; one within 100 m of a stage's line kept on it as marks.
local function marksKml()
  local lat0, lon0 = 47.3, -123.2
  local function at(alongM, eastM)
    return string.format('%.7f,%.7f,0', lon0 + eastM / (111195 * math.cos(math.rad(lat0))), lat0 + alongM / 111195)
  end
  local function pm(name, alongM, eastM, extra)
    return '<Placemark><name>' .. name .. '</name>' .. (extra or '') .. '<Point><coordinates>' .. at(alongM, eastM) ..
      '</coordinates></Point></Placemark>\n'
  end
  return [[<?xml version="1.0" encoding="UTF-8"?>
<kml xmlns="http://www.opengis.net/kml/2.2"><Document><name>Marks Rally</name>
<Style id="icon-police"><IconStyle/></Style>
<Folder><name>SS1 Ridge</name>
<Placemark><name>SS1 Ridge</name><LineString><coordinates>]] .. northLine(lat0, lon0, 41) .. [[</coordinates></LineString></Placemark>
]] .. pm('Start - Ridge', 0, 0) .. pm('Point 3', 400, 6, '<styleUrl>#pt-radio-spectator</styleUrl>')
    .. pm('Caution !!!', 500, 2, '<styleUrl>#pt-caution</styleUrl>')
    .. pm('Radio 9 (from the words, but the style says)', 600, 3, '<styleUrl>#pt-medical</styleUrl>') .. [[
</Folder>
<Folder><name>Organisers</name><Folder><name>Marshals</name>
]] .. pm('2000', 900, -8) .. pm('2010', 950, 150) .. [[
</Folder>
<Folder><name>Points</name>
]] .. pm('Gulf - Radio, Spectator', 1200, -12) .. pm('Fire and Ambulance', 1300, 9) .. pm('R3', 1400, 4)
    .. pm('MP 9', 1500, -3) .. pm('Junction', 1550, 2, '<styleUrl>#icon-police</styleUrl>')
    .. pm('Spectators prohibited', 1600, 5) .. pm('Marshall Road', 1650, 5)
    .. pm('Point A', 1700, 6, '<description><![CDATA[Doctor on site]]></description>') .. [[
</Folder>
<Folder><name>Medical</name>
]] .. pm('County Hospital', 1000, 236) .. [[
</Folder></Folder>
</Document></kml>]]
end

do
  local p = imp.parse(marksKml(), 'kml')
  local byName = {}
  for _, pt in ipairs(p.points) do byName[pt.name] = pt end
  T.check(byName['2000'] and byName['2000'].folders[1] == 'Organisers' and byName['2000'].folders[2] == 'Marshals',
    'readKml: a point keeps its folder path')
  T.check(byName['Point 3'].style == '#pt-radio-spectator' and byName['Point A'].description == 'Doctor on site',
    'readKml: and its style and description')
  T.check(byName['Start - Ridge'].folders[1] == 'SS1 Ridge', 'readKml: a point in a stage\'s folder: that folder')
  local function kinds(name) return table.concat(imp.markKinds(byName[name]), ',') end
  T.check(kinds('Point 3') == 'radio,spectator', 'pack style #pt-radio-spectator: radio and spectator')
  T.check(kinds('Caution !!!') == '', 'pack style #pt-caution: not a dressing point')
  T.check(kinds('Radio 9 (from the words, but the style says)') == 'medical', 'a #pt- style is trusted over the words')
  T.check(kinds('2000') == 'marshal', 'a point named "2000" in a Marshals folder: a marshal')
  T.check(kinds('Gulf - Radio, Spectator') == 'radio,spectator', '"Gulf - Radio, Spectator": both')
  T.check(kinds('Fire and Ambulance') == 'medical', '"Fire and Ambulance": medical')
  T.check(kinds('R3') == 'radio', '"R3": radio')
  T.check(kinds('MP 9') == 'marshal', '"MP 9": a marshal')
  T.check(kinds('Junction') == 'marshal', 'a police style: a marshal')
  T.check(kinds('Spectators prohibited') == '', 'a prohibited spectator area: not a spectator point')
  T.check(kinds('Marshall Road') == '', '"Marshall Road": not a marshal')
  T.check(kinds('Point A') == 'medical', 'a doctor in the description: medical')
  T.check(kinds('County Hospital') == 'medical', 'a hospital in the Medical folder: medical (but far off)')
  T.check(kinds('Start - Ridge') == '', 'a control is not a mark')

  local ev = imp.build(p, 'marks', 'Marks Rally', 'marks.kml')
  local st = ev.stages[1]
  T.check(st.controls.start ~= nil, 'the control rules unchanged: its start still a control')
  local got = {}
  for _, m in ipairs(st.marks or {}) do got[#got + 1] = m.kind .. ':' .. m.name end
  local list = table.concat(got, ' | ')
  local want = 'radio:Point 3 | spectator:Point 3 | medical:Radio 9 (from the words, but the style says) | ' ..
    'marshal:2000 | radio:Gulf - Radio, Spectator | spectator:Gulf - Radio, Spectator | medical:Fire and Ambulance | ' ..
    'radio:R3 | marshal:MP 9 | marshal:Junction | medical:Point A'
  T.check(list == want, 'marks on the stage, one entry per kind, in order along it (' .. list .. ')')
  local hosp, far = false, false
  for _, m in ipairs(st.marks or {}) do
    if m.name == 'County Hospital' then hosp = true end
    if m.name == '2010' then far = true end
  end
  T.check(not hosp and not far, 'a hospital 236 m off and a marshal 150 m off: dropped')
  local m1 = st.marks and st.marks[1]
  T.check(m1 and m1.lat and m1.lon and math.abs(m1.distM - 400) < 2 and math.abs(m1.offLineM - 6) < 1,
    'a mark carries lat, lon, its distance along and off the line')
  local none = imp.build(imp.parse(kml, 'kml'), 'test', 'x', 'x.kml')
  T.check(none.stages[1].marks == nil, 'a stage its map marks nothing on: no marks')
end

-- The rule bump: rallies imported under the rules before (NAME_RULES 2) are read again once, keeping their ids, and
-- gain their marks without the player doing anything.
do
  for f in pairs(files) do if f:find('/earthRally/', 1, true) == 1 then files[f] = nil end end
  files['/earthRally/import/Marks.kml'] = marksKml()
  T.check(#imp.scan() == 1, 'a map with marks imported')
  local id = files['/earthRally/importIndex.json'].files['Marks.kml'].eventId
  -- as 1.4.0 left it: the same bytes, an event without marks, the index of the rules before
  local evPath = '/earthRally/events/' .. id .. '.json'
  for _, s in ipairs(files[evPath].stages) do s.marks = nil end
  files['/earthRally/importIndex.json'].names = 2
  local rr = imp.scan()
  T.check(#rr == 1 and rr[1].ok and rr[1].eventId == id, 'the rules moved on: the map read again')
  T.check(files[evPath].stages[1].marks and #files[evPath].stages[1].marks == 11
    and files['/earthRally/importIndex.json'].files['Marks.kml'].eventId == id,
    'the rules moved on (3): the unchanged map read again, its rally gains its marks under the same id')
  T.check(#imp.scan() == 0, 'and not again')
end

-- events.stageMarks: the counts for the stage page
do
  local events = require('earthRally/events')
  local p = imp.parse(marksKml(), 'kml')
  local ev = imp.build(p, 'marks', 'Marks Rally', 'marks.kml')
  local n = events.stageMarks('marks', ev.stages[1].id, ev.stages[1])
  T.check(n.radio == 3 and n.medical == 3 and n.spectator == 2 and n.marshal == 3,
    string.format('stageMarks: radio %d, medical %d, spectator %d, marshal %d', n.radio, n.medical, n.spectator, n.marshal))
  local z = events.stageMarks('marks', 'nope', { id = 'nope' })
  T.check(z.radio == 0 and z.medical == 0 and z.spectator == 0 and z.marshal == 0, 'stageMarks: none marked, all 0')
end

T.done('test_import')
