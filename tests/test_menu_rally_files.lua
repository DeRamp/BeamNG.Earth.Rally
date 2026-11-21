-- menu.lua over the files a rally pack leaves (docs/rally-file.md; the screens: docs/mockups-rally-files/menu.html):
-- the Rallies page's seasons / rallies / stages, a season's rounds and standings, a rally's passes grouped by stage
-- with the better-of-passes Place, its Results and Rules, a stage's leaderboard, and an event file from before rally
-- files coming out unchanged.
local T = dofile(TESTS .. '/testlib.lua')

local files = {}
function jsonWriteFile(path, data) files[path] = data return true end
function jsonReadFile(path) return files[path] end
FS = {
  fileExists = function(_, path) return files[path] ~= nil end,
  findFiles = function(_, dir)
    local out = {}
    for k in pairs(files) do if k:sub(1, #dir) == dir and k:match('%.json$') then out[#out + 1] = k end end
    table.sort(out)
    return out
  end,
}
function log() end

local events = require('earthRally/events')
local menu = require('earthRally/menu')

local line = { { 47.0, -123.0 }, { 47.01, -123.0 } }
local function stage(id, name, km) return { id = id, name = name, lengthM = km * 1000, line = line, controls = {} } end
local function crew(s, d) return { s, d, '1', 'RC2', 'national', false } end
local function run(t) return { finished = true, timeS = t, penaltyS = 0, date = '2026-11-14T10:00:00Z' } end

files['/earthRally/seasons/ts.json'] = { format = 1, id = 'ts', name = 'Test Season', championship = 'Test Champs',
  rounds = { 'ts-r1', 'ts-r2' }, standings = { championship = false, points = { 25, 20, 16, 13, 11 } } }

-- Round 1: Alpha run twice (SS1, SS3), Bravo twice (SS2, and SS4 cancelled on the day)
files['/earthRally/events/ts-r1.json'] = { format = 1, id = 'ts-r1', name = 'First Rally',
  stages = { stage('alpha', 'Alpha', 10), stage('bravo', 'Bravo', 5) },
  season = { id = 'ts', name = 'Test Season', round = 1 },
  dates = { from = '2030-03-01', to = '2030-03-02' }, place = 'Fernvale, ZZ',
  itinerary = {
    { ss = 'SS1', stage = 'alpha', run = 1, km = 10, cancelled = false },
    { ss = 'SS2', stage = 'bravo', run = 1, km = 5, cancelled = false },
    { ss = 'SS3', stage = 'alpha', run = 2, km = 10, cancelled = false },
    { ss = 'SS4', stage = 'bravo', run = 2, km = 5, cancelled = true },
  },
  rules = { falseStartS = { 10, 60, 180 }, lateSPerMin = 10, earlySPerMin = 60, maxLatenessMin = 30 },
  media = { cover = '/earthRally/media/ts-r1/cover.png', logo = '/earthRally/media/ts-r1/logo.png' },
  boards = 'ts-r1.json' }
files['/earthRally/boards/ts-r1.json'] = { format = 1, passes = {
  { ss = 'SS1', stage = 'alpha', run = 1, km = 10, cancelled = false, field = {
    crew(280, 'Ann'), crew(285, 'Bob'), crew(290, 'Cara'), crew(295, 'Dan'), crew(300, 'Eve') } },
  { ss = 'SS2', stage = 'bravo', run = 1, km = 5, cancelled = false, field = {
    crew(150, 'Ann'), crew(130, 'Bob'), crew(160, 'Cara'), crew(170, 'Dan'), crew(180, 'Eve') } },
  { ss = 'SS3', stage = 'alpha', run = 2, km = 10, cancelled = false, field = {
    crew(300, 'Ann'), crew(310, 'Bob'), crew(320, 'Cara'), crew(330, 'Dan') } },
  { ss = 'SS4', stage = 'bravo', run = 2, km = 5, cancelled = true, field = {} },
} }
-- Round 2: one stage, no results
files['/earthRally/events/ts-r2.json'] = { format = 1, id = 'ts-r2', name = 'Second Rally',
  stages = { stage('charlie', 'Charlie', 8) }, season = { id = 'ts', name = 'Test Season', round = 2 },
  media = { cover = '/earthRally/media/ts-r2/cover.jpg' } }
-- A rally from a map on its own, as every event file was before rally files
files['/earthRally/events/old.json'] = { format = 1, id = 'old', name = 'Old Rally', source = { file = 'Old.kml' },
  stages = { stage('o1', 'Oak', 4), stage('o2', 'Elm', 6) } }
-- A single stage
files['/earthRally/events/one.json'] = { format = 1, id = 'one', name = 'Coal Hill', stages = { stage('ch', 'Coal Hill', 4.6) } }
-- A round whose season is not on this computer any more: a rally of its own
files['/earthRally/events/orphan.json'] = { format = 1, id = 'orphan', name = 'Orphan Rally',
  stages = { stage('p1', 'Pine', 3), stage('p2', 'Fir', 3) }, season = { id = 'gone', name = 'Gone', round = 1 } }

files['/earthRally/results/ts-r1__alpha.json'] = { runs = { run(320), run(305) } }
files['/earthRally/results/old__o1.json'] = { runs = { run(200) } }
files['/earthRally/results/one__ch.json'] = { runs = { run(192.7) } }
events.list(true)

------------------------------------------------------------------------------------------ the Rallies page
do
  local h = menu.home()
  T.check(#h.seasons == 1 and h.seasons[1].id == 'ts' and h.seasons[1].rallies == 2 and h.seasons[1].stages == 3 and
    h.seasons[1].driven == 1, 'home: one season card, its rallies, stages and stages driven')
  T.check(#h.seasons[1].covers == 2 and h.seasons[1].covers[1].url == '/earthRally/media/ts-r1/cover.png' and
    h.seasons[1].covers[1].round == 1 and h.seasons[1].covers[2].name == 'Second Rally',
    'home: the mosaic\'s covers, as urls, in round order')
  T.check(h.seasons[1].dates.from == '2030-03-01' and h.seasons[1].you == nil,
    'home: the season\'s dates; no standings place before any rally result')
  local by = {}
  for _, c in ipairs(h.rallies) do by[c.id] = c end
  T.check(#h.rallies == 3 and by.old and by.one and by.orphan and not by['ts-r1'] and not by['ts-r2'],
    'home: the rounds are inside the season card; the rest are cards of their own')
  T.check(by.old.kind == 'rally' and by.old.media == nil and by.old.stages == 2 and by.old.driven == 1 and
    by.old.file == 'Old.kml', 'home: an old rally is a rally card, no picture')
  T.check(by.one.kind == 'stage' and by.one.stageId == 'ch' and by.one.best == 192.7,
    'home: a one-stage rally with no season is a stage card, opening on its stage')
  T.check(by.orphan.kind == 'rally', 'home: a round whose season is gone is a rally of its own')
end

------------------------------------------------------------------------------------------ a rally
do
  local r = menu.rally('ts-r1')
  T.check(r.season and r.season.id == 'ts' and r.season.round == 1 and r.place == 'Fernvale, ZZ' and
    r.dates.to == '2030-03-02' and r.media.logo == '/earthRally/media/ts-r1/logo.png' and r.hasBoard,
    'rally: season crumb, dates, place, pictures, a board')
  T.check(#r.list == 2 and r.list[1].id == 'alpha' and #r.list[1].passes == 2 and r.list[1].passes[1].ss == 'SS1' and
    r.list[1].passes[2].ss == 'SS3' and r.list[2].passes[2].cancelled == true and r.anyCancelled,
    'rally: a stage run twice is one row with both passes, a cancelled pass marked')
  T.check(r.list[1].best == 305 and r.list[1].place and r.list[1].place.pos == 2 and r.list[1].place.of == 5 and
    r.list[1].place.pass == 'SS3', 'rally: Place is the better of the passes (6th on SS1, 2nd on SS3)')
  T.check(r.list[2].place == nil and r.list[2].placeWhy == 'noTime', 'rally: no time on Bravo, no Place')
  T.check(r.results and r.results.complete == false and r.results.stages == 2 and r.results.driven == 1 and
    r.results.chips[1].done and not r.results.chips[2].done and #r.results.rows == 4 and not r.results.rows[1].you,
    'rally: Results waits for Bravo; the real field is there')
  T.check(r.results.chips[1].timeS == r.list[1].best and r.results.chips[1].ss == 'SS1' and r.results.chips[2].timeS == nil,
    'rally: a driven stage chip carries your time and its SS, a stage not driven none (#54)')
  T.check(#r.rules == 4 and r.rules[1].value == '10 / 60 / 180 s' and r.rules[1].inGame and
    r.rules[2].value == '10 s a minute' and r.rules[3].value == '1 min a minute' and r.rules[4].value == 'out' and
    r.rules[4].label:find('30 min'), 'rally: the rules the file has, one short line each')

  -- Bravo driven: the rally result, and the season standings from it
  files['/earthRally/results/ts-r1__bravo.json'] = { runs = { run(140) } }
  events.forget()
  r = menu.rally('ts-r1')
  -- your total: 305 (SS1) + 140 (SS2) + 305 (SS3) = 750; Ann 730, Bob 725, Cara 770, Dan 795 (Eve has no SS3)
  T.check(r.results.complete and r.results.totalS == 750 and r.results.you.pos == 3 and r.results.you.of == 5 and
    r.results.winnerS == 725, 'rally: your total over the counted passes, 3rd of 5')
  T.check(r.results.rows[3].you and r.results.rows[3].timeS == 750 and r.results.rows[4].name == 'Cara' and
    r.results.points == 16, 'rally: you in the results table; 16 points in the season')
  T.check(r.list[2].place and r.list[2].place.pass == 'SS2' and r.list[2].place.pos == 2,
    'rally: Bravo placed on its one counted pass')

  -- the line not the stage that was run: no Place
  local p, why = menu.stagePlace(events.boards('ts-r1'), { id = 'alpha', name = 'Alpha', lengthM = 12000 }, 305)
  T.check(p == nil and why == 'lineMismatch', 'Place: a line 20% off the stage as run is not placed')
end

------------------------------------------------------------------------------------------ a stage
do
  local s = menu.stage('ts-r1', 'alpha', 'start')
  T.check(s.board and s.board.pass == 'SS3' and s.board.you.pos == 2 and #s.board.passes == 2 and s.board.field == 4,
    'stage: the leaderboard opens on the pass you place best on')
  T.check(s.board.rows[2].you and s.board.rows[1].name == 'Ann' and s.board.rows[1].class == 'RC2' and
    s.board.rows[2].class == nil, 'stage: your row slotted in, its class blank')
  T.check(#s.passes == 2 and s.season.id == 'ts' and s.ss == 1 and s.single == nil, 'stage: its passes and season')
  s = menu.stage('ts-r1', 'alpha', 'start', true, 'SS1')
  T.check(s.board.pass == 'SS1' and s.board.you.pos == 6 and s.board.rows[6].you, 'stage: the pass toggle')
  s = menu.stage('ts-r1', 'bravo', 'start', true, 'SS4')
  T.check(s.board.pass == 'SS4' and s.board.reason == 'cancelled' and #s.board.rows == 0, 'stage: a cancelled pass')
  s = menu.stage('ts-r2', 'charlie', 'start')
  T.check(s.board == nil and s.season.round == 2 and s.single == nil, 'stage: no results, no leaderboard')
  s = menu.stage('one', 'ch', 'start')
  T.check(s.single and s.board == nil and s.season == nil and s.best == 192.7, 'stage: a single stage')
  T.check(menu.rally('one').single, 'rally: a single stage says so (the page opens the stage)')
end

------------------------------------------------------------------------------------------ a season
do
  local s = menu.season('ts')
  T.check(s.name == 'Test Season' and s.rallies == 2 and s.finished == 1 and s.dates.from == '2030-03-01' and
    s.next == 'Second Rally', 'season: rounds, finished, dates, the round to finish next')
  T.check(s.rounds[1].round == 1 and s.rounds[1].complete and s.rounds[1].you.pos == 3 and s.rounds[1].points == 16 and
    s.rounds[1].driven == 2 and s.rounds[1].media.cover and s.rounds[2].you == nil and s.rounds[2].stages == 1,
    'season: a finished round shows your place; an unfinished one does not')
  local st = s.standings
  T.check(st.you and st.you.pos == 3 and st.you.points == 16 and st.youShown and st.entries == 5 and
    st.rows[1].name == 'Bob' and st.rows[1].points == 25 and st.rows[1].perRound[1].pos == 1 and
    st.rows[1].perRound[2].noBoard, 'season: standings from boards.standings, you among them')
  T.check(#st.points == 5 and #st.rounds == 2 and st.rounds[2].name == 'Second Rally', 'season: points scale, rounds')
  local h = menu.home()
  T.check(h.seasons[1].you and h.seasons[1].you.pos == 3 and h.seasons[1].you.points == 16 and h.seasons[1].driven == 2,
    'home: the season card shows your standings place')
  T.check(menu.season('nope') == nil, 'season: unknown id, nil')
end

------------------------------------------------------------------------------------------ an old event file
do
  local base = menu.rallyBase('old')
  local r = menu.rally('old')
  local keysBase, keysNew = {}, {}
  for k in pairs(base) do keysBase[#keysBase + 1] = k end
  for k in pairs(r) do keysNew[#keysNew + 1] = k end
  table.sort(keysBase) table.sort(keysNew)
  T.check(table.concat(keysBase, ',') == table.concat(keysNew, ','),
    'old event: the rally page gets no new fields (' .. table.concat(keysNew, ',') .. ')')
  T.check(r.list[1].ss == 1 and r.list[1].name == 'Oak' and r.list[2].ss == 2 and r.list[1].best == 200 and
    r.list[1].place == nil and #r.list[1].passes == 1 and r.list[1].passes[1].ss == 'SS1' and
    r.list[2].passes[1].ss == 'SS2', 'old event: stages in map order as SS1, SS2, no Place')
  local s = menu.stage('old', 'o2', 'start')
  T.check(s.ss == 2 and s.board == nil and s.season == nil and s.single == nil and s.media == nil and
    s.passes[1].ss == 'SS2', 'old event: the stage page as before')
  T.check(menu.rulesLines(nil) == nil and menu.rulesLines({}) == nil, 'no rules: no Rules tab')
  T.check(menu.mediaUrl('/earthRally/media/x/cover.png') == '/earthRally/media/x/cover.png' and menu.mediaUrl('') == nil,
    'mediaUrl: the path as it is (unverified in game)')
end

------------------------------------------------------------------------------------------ not run, not ranked
do
  -- Delta's map line is 10 km against a 7 km pass (a mismatch); Echo matches; Fox is in the map but never run
  files['/earthRally/events/mm.json'] = { format = 1, id = 'mm', name = 'Mismatch Rally',
    stages = { stage('delta', 'Delta', 10), stage('echo', 'Echo', 5), stage('fox', 'Fox', 3) },
    itinerary = { { ss = 'SS1', stage = 'delta', run = 1, km = 7 }, { ss = 'SS2', stage = 'echo', run = 1, km = 5 } },
    media = { cover = '/earthRally/media/mm/cover.png' }, pack = { file = 'MM.zip', fingerprint = '99:00ab12cd34' },
    boards = 'mm.json' }
  files['/earthRally/boards/mm.json'] = { format = 1, passes = {
    { ss = 'SS1', stage = 'delta', run = 1, km = 7, field = { crew(200, 'Ann'), crew(210, 'Bob') } },
    { ss = 'SS2', stage = 'echo', run = 1, km = 5, field = { crew(100, 'Ann'), crew(90, 'Bob'), crew(95, 'Cy') } },
  } }
  files['/earthRally/results/mm__delta.json'] = { runs = { run(150) } }
  files['/earthRally/results/mm__echo.json'] = { runs = { run(80) } }
  events.forget()
  events.list(true)
  local r = menu.rally('mm')
  local fox
  for _, row in ipairs(r.list) do if row.id == 'fox' then fox = row end end
  T.check(fox and fox.notRun and #fox.passes == 0 and r.list[3].id == 'fox', 'a line never run: notRun, no SS, last')
  T.check(menu.ssLabel(menu.findEvent('mm'), 'fox') == nil and menu.ssLabel(menu.findEvent('mm'), 'echo') == 'SS2' and
    menu.ssLabel(menu.findEvent('old'), 'o2') == 'SS2', 'ssLabel: the real SS, map order with no itinerary, nil when not run')
  local s = menu.stage('mm', 'fox', 'start')
  T.check(s.notRun and #s.passes == 0, 'stage page: not run')
  local res = r.results
  T.check(res.complete and res.totalS == 80 and res.notRanked and res.you == nil and res.points == nil and
    res.mismatch and #res.mismatch == 1 and res.mismatch[1] == 'Delta' and res.crews == 3 and res.counted == 2 and
    res.comparable == 1 and res.kmTotal == 12 and res.kmCovered == 5 and res.partial and res.stages == 1 and
    res.chips[1].name == 'Echo',
    'results: Delta does not match the official distance: left out; Echo alone is 5 of 12 km, under 75%: not ranked')
  for _, row in ipairs(res.rows) do T.check(not row.you, 'results: you not among the ranked rows') end
  s = menu.stage('mm', 'delta', 'start')
  T.check(s.board and s.board.reason == 'lineMismatch' and s.board.lineKm == 10 and s.board.km == 7 and
    s.board.lineOf == 'map', 'stage board: the map\'s km and the real km, for the mismatch line')

  -- Delta matched to the roads, 7.0 km start to finish: the driven line is what is measured, and it matches
  files['/earthRally/matched/mm__delta.json'] = { format = 1, points = { { 47.0, -123.0, 0 },
    { 47.0 + 3500 / 111195, -123.0, 0 }, { 47.0 + 7000 / 111195, -123.0, 0 } } }
  events.forget()
  r = menu.rally('mm')
  res = r.results
  T.check(not res.notRanked and not res.partial and res.comparable == 2 and res.totalS == 230 and res.you and
    res.you.pos == 1 and res.you.of == 3 and res.mismatch == nil,
    'measured on the matched line (7.0 km, as run): Delta counts, ranked 1st of 3')
  s = menu.stage('mm', 'delta', 'start')
  T.check(s.board and s.board.reason == nil and s.board.you and s.board.lineOf == 'matched' and
    math.abs(s.board.lineKm - 7) < 0.01, 'stage board: placed, the matched line\'s km')
  local info = events.stageLineInfo('mm', 'delta', menu.findEvent('mm').stages[1])
  T.check(info and info.kind == 'matched' and info.key and info.key:sub(1, 10) == 'matched:3:' and
    math.abs(info.lengthM - 7000) < 5, 'stageLineInfo: the line\'s kind, identity and start-to-finish length')

  -- a time driven on another line: in Your runs, not on the boards; a time with no line recorded: placed
  T.check(info.start and info.finish and math.abs(info.start[1] - 47.0) < 1e-5 and
    math.abs(info.finish[1] - (47.0 + 7000 / 111195)) < 1e-5, "stageLineInfo: the start and the finish on the line")
  local function onLine(t, lineM, a, b) local x = run(t) x.lineKey, x.lineM, x.lineStart, x.lineFinish = 'k', lineM, a, b return x end
  local old = onLine(50, 9000, { 47.0, -123.0 }, { 47.0 + 9000 / 111195, -123.0 })
  local same = onLine(79, 7000, info.start, info.finish)
  local deltaStage = menu.findEvent('mm').stages[1]
  files['/earthRally/results/mm__delta.json'] = { runs = { run(150), old, same } }
  events.forget()
  T.check(events.best('mm', 'delta') == 50 and events.bestPlaceable('mm', 'delta', deltaStage) == 79,
    'best: every time; bestPlaceable: the times on the line the stage runs on now, and those with none recorded')
  -- the same road matched again, every point a metre over (and one more point): its times are still placed
  local kx = 111195 * math.cos(math.rad(47))
  files['/earthRally/matched/mm__delta.json'] = { format = 1, points = { { 47.0, -123.0 + 1 / kx, 0 },
    { 47.0 + 2000 / 111195, -123.0 + 1 / kx, 0 }, { 47.0 + 3500 / 111195, -123.0 + 1 / kx, 0 },
    { 47.0 + 7000 / 111195, -123.0 + 1 / kx, 0 } } }
  events.forget()
  T.check(events.bestPlaceable('mm', 'delta', deltaStage) == 79 and events.stageLineInfo('mm', 'delta', deltaStage).key ~= info.key,
    'the same road matched again a metre over: another key, the same line by tolerance; its times placed')
  -- a recce of another route between the same two ends, 5% longer: not the line those times were driven on
  local east = math.sqrt(3675 ^ 2 - 3500 ^ 2) / kx
  files['/earthRally/recce/mm__delta.json'] = { points = { { 47.0, -123.0, 0 },
    { 47.0 + 3500 / 111195, -123.0 + east, 0 }, { 47.0 + 7000 / 111195, -123.0, 0 } } }
  events.forget()
  local ri = events.stageLineInfo('mm', 'delta', deltaStage)
  T.check(ri.kind == 'recce' and math.abs(ri.lengthM - 7350) < 5 and events.bestPlaceable('mm', 'delta', deltaStage) == 150,
    'a recce of another route, the same ends, 5% longer: the times on the old line not placed (' .. ri.lengthM .. ')')
  T.check(events.onLine(onLine(1, 7350 + 29, info.start, info.finish), ri) and
    not events.onLine(onLine(1, 7350 + 80, info.start, info.finish), ri) and
    not events.onLine(onLine(1, 7350, { 47.0 + 30 / 111195, -123.0 }, info.finish), ri) and
    not events.onLine(onLine(1, 7350, info.start, info.finish), nil) and events.onLine(run(1), nil),
    'onLine: within 1% (30 m at least) and both ends within 25 m; nothing recorded: on any line')
  files['/earthRally/recce/mm__delta.json'] = nil
  -- a run saved and read back (JSON): still placed
  files['/earthRally/results/mm__delta.json'] = { runs = { run(150), old } }
  events.forget()
  events.addResult('mm', 'delta', onLine(78, 7000, info.start, info.finish))
  files['/earthRally/results/mm__delta.json'] = T.jsonDecode(T.jsonEncode(files['/earthRally/results/mm__delta.json']))
  events.forget()
  T.check(events.bestPlaceable('mm', 'delta', deltaStage) == 78, 'a time saved and read back from JSON: placed')
  files['/earthRally/matched/mm__delta.json'] = { format = 1, points = { { 47.0, -123.0, 0 },
    { 47.0 + 3500 / 111195, -123.0, 0 }, { 47.0 + 7000 / 111195, -123.0, 0 } } }
  files['/earthRally/results/mm__delta.json'] = { runs = { run(150), old, same } }
  events.forget()
  s = menu.stage('mm', 'delta', 'start')
  T.check(s.best == 50 and s.board.bestS == 79 and s.board.you.timeS == 79 and s.board.oldLine == nil,
    "stage page: Your runs' BEST is every time; the board places the best on this line")
  T.check(menu.rally('mm').results.totalS == 159, 'rally result: the placeable best (79 + 80)')
  files['/earthRally/results/mm__delta.json'] = { runs = { old } }
  events.forget()
  s = menu.stage('mm', 'delta', 'start')
  T.check(s.best == 50 and s.board.bestS == nil and s.board.you == nil and s.board.reason == 'noTime' and
    s.board.oldLine, 'only times on an earlier line: none placed, and the board says so')
  T.check(menu.rally('mm').results.complete == false, 'and the rally result waits for a time on this line')

  -- (additions A) Your runs' best splits: the fastest run with splits on the line the stage runs on now (a full-rally
  -- pass can be it), and each run's splits on that line with its gaps to them
  local key = events.stageLineInfo('mm', 'delta', deltaStage).key
  local function sp(t, a, b, c, k, d)
    local x = run(t) x.lineKey, x.splits, x.date = k or key, { a, b, c }, d or x.date return x
  end
  files['/earthRally/results/mm__delta.json'] = { runs = {
    sp(79, 20, 40, 60, nil, '2026-11-14T10:00:00Z'),
    sp(70, 15, 30, 50, 'another line'),
    run(85),
    sp(81, 19.5, 41, 62, nil, '2026-11-18T10:00:00Z') } }
  events.forget()
  s = menu.stage('mm', 'delta', 'start')
  local bs = s.bestSplits
  T.check(bs and bs.timeS == 79 and bs.splits[2] == 40 and bs.date == '2026-11-14T10:00:00Z' and bs.rally == nil,
    'best splits: the fastest run with splits on this line, and its date (the faster one on another line not it)')
  local r1, r2, r3, r4 = s.runs[1], s.runs[2], s.runs[3], s.runs[4]
  T.check(r1.timeS == 81 and r1.splits and #r1.splits == 4 and r1.splits[1].gapS == -0.5 and r1.splits[2].gapS == 1
    and r1.splits[3].gapS == 2 and r1.splits[4].timeS == 81 and r1.splits[4].gapS == 2,
    'a run\'s splits and finish, each with its gap signed (ahead negative)')
  T.check(r2.timeS == 85 and r2.splits == nil, 'a run with no splits: none')
  T.check(r3.timeS == 70 and r3.splits == nil, 'a run on another line: no splits')
  T.check(r4.timeS == 79 and r4.splits and r4.splits[1].timeS == 20 and r4.splits[1].gapS == nil
    and r4.splits[4].gapS == nil and r4.bestSplits, 'the best run itself: its splits, no gaps')
  -- (review 2026-11-19) two runs with the same date and time: only the best one itself marked (by its place in runs)
  files['/earthRally/results/mm__delta.json'].runs[5] = sp(79, 21, 41, 61, nil, '2026-11-14T10:00:00Z')
  events.forget()
  s = menu.stage('mm', 'delta', 'start')
  T.check(s.runs[5].bestSplits and not s.runs[1].bestSplits and s.runs[1].splits[1].gapS == 1,
    'the best run marked by identity, not by its date and time: its twin compared with it')
  files['/earthRally/results/mm__delta.json'].runs[5] = nil
  -- a full-rally pass faster on this line: the best splits are its, and the row says so
  files['/earthRally/results/mm__delta.json'].rallyPasses = { { timeS = 78.5, splits = { 18, 39, 59 }, lineKey = key,
    date = '2026-11-16T10:00:00Z' } }
  events.forget()
  s = menu.stage('mm', 'delta', 'start')
  T.check(s.bestSplits and s.bestSplits.rally == true and s.bestSplits.timeS == 78.5
    and s.bestSplits.date == '2026-11-16T10:00:00Z', 'best splits from a full-rally pass: rally = true')
  T.check(s.runs[4].splits[1].gapS == 2 and s.runs[4].splits[4].gapS == 0.5 and not s.runs[4].bestSplits,
    'every run of yours compared with the pass')
  -- a stage with no line: no best splits and no split lines, whatever its runs recorded
  files['/earthRally/results/mm__echo.json'] = { runs = { sp(80, 20, 40, 60, 'some line') } }
  events.forget()
  s = menu.stage('mm', 'echo', 'start')
  T.check(s.bestSplits == nil and s.runs[1].splits == nil, 'no line: no best splits, no split lines')

  -- the HUD's next stage and SS count (runner.lua): the itinerary's running order and counted passes; the map's
  -- order with none, a stage never run skipped
  local it = { id = 'it', stages = { stage('a', 'A', 1), stage('x', 'X', 1), stage('y', 'Y', 1), stage('b', 'B', 1),
    stage('c', 'C', 1), stage('d', 'D', 1) }, itinerary = {
    { ss = 'SS1', stage = 'c' }, { ss = 'SS2', stage = 'a' }, { ss = 'SS3', stage = 'c' },
    { ss = 'SS4', stage = 'd', cancelled = true }, { ss = 'SS5', stage = 'b' } } }
  local function nx(id) local s, i = menu.nextStage(it, id) return s and (s.id .. i) or 'none' end
  T.check(menu.passCount(it) == 4 and nx('c') == 'a1' and nx('a') == 'c5' and nx('d') == 'b4' and nx('b') == 'none',
    "nextStage: the next counted pass in running order after the stage's first (" .. nx('c') .. ' ' .. nx('a') .. ' ' ..
    nx('d') .. ' ' .. nx('b') .. ')')
  T.check(nx('x') == 'b4' and menu.ssLabel(it, 'x') == nil, 'a stage never run: the next in map order that is run')
  local oe = menu.findEvent('old')
  local o2, oi = menu.nextStage(oe, 'o1')
  T.check(menu.passCount(oe) == nil and o2 and o2.id == 'o2' and oi == 2 and menu.nextStage(oe, 'o2') == nil,
    "no itinerary: map order, no pass count (the runner counts the map's stages, as before)")

  -- a round its season no longer lists, retired by the import: not a card on Home
  files['/earthRally/events/retired.json'] = { format = 1, id = 'retired', name = 'Retired Rally',
    stages = { stage('q1', 'Quince', 3) }, season = { id = 'ts', name = 'Test Season', round = 3 },
    retired = { season = 'ts', date = '2026-11-14T00:00:00Z' } }
  events.forget()
  events.list(true)
  local seen = false
  for _, c in ipairs(menu.home().rallies) do if c.id == 'retired' then seen = true end end
  T.check(not seen and menu.rally('retired') ~= nil, 'a retired round: off Home, its page and times still there')
  -- Drive rally (#39): only the rallies with an event file (rallyStops and an itinerary), dated ones first; no rallyRun loaded here, so nothing saved
  files['/earthRally/events/fr.json'] = { format = 1, id = 'fr', name = 'Full Rally', stages = { stage('f1', 'Fig', 4) },
    dates = { from = '2030-05-01', to = '2030-05-02' },
    itinerary = { { ss = 'SS1', stage = 'f1', run = 1, km = 4, cancelled = false } }, rallyStops = {} }
  files['/earthRally/events/fr0.json'] = { format = 1, id = 'fr0', name = 'Undated Rally', stages = { stage('g1', 'Gum', 2) },
    itinerary = { { ss = 'SS1', stage = 'g1', run = 1, km = 2, cancelled = false } }, rallyStops = {} }
  events.forget()
  events.list(true)
  local dv = menu.drive()
  local ids = {}
  for _, c in ipairs(dv.rallies) do ids[#ids + 1] = c.id end
  T.check(table.concat(ids, ',') == 'fr,fr0' and dv.rallies[1].stages == 1 and dv.rallies[1].dates
    and dv.rallies[1].saved == nil and dv.active == nil,
    'drive: only rallies with an event file, dated first (' .. table.concat(ids, ',') .. ')')
  T.check(r.media.cover == '/earthRally/media/mm/cover.png?v=ab12cd34'
    and menu.mediaUrl('/x.png', 'abc') == '/x.png?v=abc', 'media: cache-busted with the pack\'s fingerprint')
end

T.done('test_menu_rally_files')
