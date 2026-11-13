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

T.done('test_import')
