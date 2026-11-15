-- earthRally/boards: a stage's leaderboard, your rally result and the season standings (docs/rally-file.md,
-- "Leaderboards and standings"), worked out from the files the mod wrote from a pack. Pure: the caller reads the
-- files and passes the tables in (no file system, no game calls), so all of it tests offline (tests/test_boards.lua).
-- Times stay numbers in seconds; wording and formatting are the page's (gapText below is the one exception).
--
-- What is read (docs/rally-file.md, "What the mod writes"):
--   event   earthRally/events/<rallyId>.json: id, name, stages [{ id, name, lengthM }], itinerary (only when there
--           is no board), season { id, name, round }
--   board   earthRally/boards/<rallyId>.json: passes [{ ss, stage, run, km, cancelled, field = [[seconds, driver,
--           car, class, championship, notional]...] }], fastest first (re-sorted here all the same)
--   season  earthRally/seasons/<seasonId>.json: standings { championship, points, best }
--   bestByStage  { [stageId] = your best seconds } (events.bestPlaceable for each stage: on its line now)
--
-- Readings taken where the spec is open:
--   * A board pass names its stage by `stage`. It is taken to belong to an event stage when it equals the stage's
--     id, or its name (trimmed, case folded), or when the pass carries a `stageId` equal to the id.
--   * A pass whose stage is not in the event (the map has no such line) is left out of everything: you cannot drive
--     it, so "the same passes" for the crews leaves it out too. rallyResult lists it in `unmatched`.
--   * "of N" counts you: 14th of 41 when the field has 40 crews. Equal times share a place (1, 2, 2, 4) and you go
--     after the crews you tie with.
--   * A stage's length is measured on the line you are timed on (the caller passes it: menu.lua measures start to
--     flying finish on the recce or matched line, events.drivenLengthM), else on the map (M.stageLengthM): start to
--     flying finish when the map has both controls (what an official stage km measures), else the whole line. More
--     than 5% off a pass's km is a line mismatch: you are not placed on that pass's board, and the pass is left out
--     of the rally result. The result is over the comparable passes (counted, not a mismatch): your total and every
--     crew's. It is ranked only when those passes cover at least M.RANK_MIN_SHARE of the rally's counted km (the
--     user, 2026-11-14); below that it is shown, `notRanked`, and scores you nothing. The crews' standings points
--     never depend on your lines: they come from their real ranking over every counted pass (M.standings).
--   * A rally with no board still gets your total, over its itinerary's counted passes (or each stage once); only
--     the ranking needs the board. Such a round scores no points in the standings, and is still listed.
--   * The results' overall table is not read (pack.lua does not keep it): a crew is ranked exactly when it has a
--     time on every counted pass, as the spec says.
--   * standings.championship: JSON null cannot be told from missing once decoded, so "all crews" is written as
--     false, "" or "all" (standingsRules gives false); missing is the default "national". Compared case folded.
--     standingsRules is the one place the standings block is read: pack.lua writes the season file with it too.
--   * Tie-breaks on points (wins, then seconds, ...) count every round's finishes, not only the `best` N counted.
local M = {}

M.LINE_MISMATCH = 0.05
M.RANK_MIN_SHARE = 0.75     -- the share of a rally's counted km its comparable passes must cover to rank
M.TOP = 10
M.EPS = 1e-6
M.DEFAULT_STANDINGS = {
  championship = 'national',
  points = { 25, 20, 16, 13, 11, 10, 9, 8, 7, 6, 5, 4, 3, 2, 1 },
  best = nil,
}
M.YOU = 'You'

local function norm(s)
  if type(s) ~= 'string' then return nil end
  return (s:gsub('^%s+', ''):gsub('%s+$', ''):lower())
end
M.crewKey = norm

-- Rounded to the millisecond, so sums of tenths compare equal.
local function ms(x) return math.floor(x * 1000 + 0.5) / 1000 end

-- '+32.1', '+1:02.3'; '' for nil or zero (the leader's row).
function M.gapText(s)
  if type(s) ~= 'number' or math.abs(s) < 0.05 then return '' end
  local sign = s < 0 and '-' or '+'
  s = math.abs(s)
  if s < 60 then return string.format('%s%.1f', sign, s) end
  local m = math.floor(s / 60)
  return string.format('%s%d:%04.1f', sign, m, s - m * 60)
end

------------------------------------------------------------------------------------------ passes

local function stageMatches(pass, stage)
  if type(stage) ~= 'table' then return false end
  if pass.stageId ~= nil and pass.stageId == stage.id then return true end
  if pass.stage == nil then return false end
  if pass.stage == stage.id then return true end
  local a, b = norm(pass.stage), norm(stage.name)
  return a ~= nil and a == b
end

-- The event stage a board pass belongs to, or nil.
function M.stageOf(event, pass)
  for _, s in ipairs((event and event.stages) or {}) do
    if stageMatches(pass, s) then return s end
  end
  return nil
end

-- The map's length of a stage, in metres, to set against a results pass's km: start to flying finish when the
-- stage has both controls on its line (their distM along it), else the whole line (lengthM). nil when neither.
function M.stageLengthM(stage)
  if type(stage) ~= 'table' then return nil end
  local c = type(stage.controls) == 'table' and stage.controls or {}
  local s, f = c.start, c.ff
  if type(s) == 'table' and type(f) == 'table' and type(s.distM) == 'number' and type(f.distM) == 'number' and
    f.distM > s.distM then
    return f.distM - s.distM
  end
  return type(stage.lengthM) == 'number' and stage.lengthM or nil
end

-- Is a stage length (m: on the line you are timed on, or the map's) more than 5% off a pass's km?
function M.isMismatch(lineM, km)
  return type(lineM) == 'number' and type(km) == 'number' and km > 0 and
    math.abs(lineM / 1000 - km) / km > M.LINE_MISMATCH
end

local function passInfo(p)
  return { ss = p.ss, run = p.run, km = p.km, cancelled = p.cancelled == true }
end

-- A pass's field as crew rows: notional left out unless keepNotional, fastest first (equal times in file order),
-- one row per driver (their fastest).
local function fieldOf(pass, keepNotional)
  local rows, seen, sorted = {}, {}, {}
  for i, f in ipairs(pass.field or {}) do
    if type(f[1]) == 'number' and norm(f[2]) and norm(f[2]) ~= '' and (keepNotional or f[6] ~= true) then
      sorted[#sorted + 1] = { f = f, i = i }
    end
  end
  table.sort(sorted, function(a, b)
    if math.abs(a.f[1] - b.f[1]) > M.EPS then return a.f[1] < b.f[1] end
    return a.i < b.i
  end)
  for _, x in ipairs(sorted) do
    local f, key = x.f, norm(x.f[2])
    if not seen[key] then
      seen[key] = true
      rows[#rows + 1] = { key = key, name = (f[2]:gsub('^%s+', ''):gsub('%s+$', '')), car = f[3], class = f[4],
        championship = f[5], notional = f[6] == true, timeS = f[1] }
    end
  end
  return rows
end

-- Places a list of { timeS } rows (sorted) and you (yourS or nil) into one ranked list: equal times share a place,
-- you after the crews you tie with. Returns the list (rows with pos, gapS, you) and your entry.
local function rank(rows, yourS, you)
  local out, mine = {}, nil
  local inserted = yourS == nil
  local function push(r)
    local prev = out[#out]
    if prev and math.abs(prev.timeS - r.timeS) <= M.EPS then r.pos = prev.pos else r.pos = #out + 1 end
    out[#out + 1] = r
  end
  for _, r in ipairs(rows) do
    if not inserted and yourS < r.timeS - M.EPS then
      mine = you
      push(mine)
      inserted = true
    end
    push(r)
  end
  if not inserted then mine = you push(mine) end
  local lead = out[1] and out[1].timeS
  for _, r in ipairs(out) do r.gapS = ms(r.timeS - lead) end
  return out, mine
end

-- Your placing in a ranked list: { pos, of, gapS (to the fastest crew; negative when you beat them all), aheadS (to
-- the crew just ahead; nil when you lead), leadS (to the next crew when you lead), timeS }.
local function placing(out, mine, idx)
  local crews = #out - 1
  local fastestCrew, ahead, behind
  for i, r in ipairs(out) do
    if not r.you then
      fastestCrew = fastestCrew or r
      if i < idx then ahead = r end
      if i > idx and not behind then behind = r end
    end
  end
  return {
    pos = mine.pos, of = crews + 1, timeS = mine.timeS,
    gapS = fastestCrew and ms(mine.timeS - fastestCrew.timeS) or 0,
    aheadS = ahead and ms(mine.timeS - ahead.timeS) or nil,
    leadS = (not ahead and behind) and ms(behind.timeS - mine.timeS) or nil,
  }
end

local function indexOf(list, x)
  for i, r in ipairs(list) do if r == x then return i end end
  return nil
end

-- The menu rows of a ranked list (a stage's, or rallyResult's `ranked`): the first `top` crews, with you at your
-- place among them (so up to top + 1 rows). Placed below them, you come with the crew just ahead of you and the
-- one just behind (the user, 2026-11-14: "show you your total place, and the person directly above/behind you"),
-- and the first row after crews left out is marked skipped = true (the menu draws a gap above it).
-- (Fewer than M.MIN_GAP crews between the top and the one ahead of you are shown rather than skipped: a gap of
-- one would hide no more than the row it takes.)
-- Rows: { pos, name, car, class, timeS, gapS, you, skipped }. The one home of "the top 10 and you".
M.NEAR = 1      -- crews shown either side of you, below the top
M.MIN_GAP = 2   -- the fewest crews a gap may hide; fewer are shown
local function menuRow(r)
  return { pos = r.pos, name = r.name, car = r.car, class = r.class, timeS = r.timeS or r.totalS, gapS = r.gapS,
    you = r.you == true }
end
local function menuRows(out, top)
  out = out or {}
  local rows, crews, at = {}, 0, nil
  for i, r in ipairs(out) do
    if r.you then at = i break end
  end
  -- the top crews, and you when you are among them
  local last = 0
  for i, r in ipairs(out) do
    if r.you then
      if crews >= top then break end
      rows[#rows + 1] = menuRow(r)
    else
      if crews >= top then break end
      crews = crews + 1
      rows[#rows + 1] = menuRow(r)
    end
    last = i
  end
  if not at or at <= last then return rows end
  -- you below the top: the crews around you, joined on to the top when the gap is small
  local from = math.max(at - M.NEAR, last + 1)
  if from - last - 1 < M.MIN_GAP then from = last + 1 end
  local to = math.min(at + M.NEAR, #out)
  for i = from, to do
    local row = menuRow(out[i])
    if i == from and from > last + 1 then row.skipped = true end
    rows[#rows + 1] = row
  end
  return rows
end
function M.topRows(list, top) return menuRows(list, top or M.TOP) end

------------------------------------------------------------------------------------------ a stage's leaderboard

-- board: the rally's board (nil: none). stage: the stage id, or the event's stage table { id, name } (the name lets
-- a pass that names its stage by the line's name be found). opts: { pass = a pass's ss (default the first counted
-- one), bestS = your best time, lineM = the stage's length in metres start to flying finish on the line you are
-- timed on (menu.lua: events.drivenLengthM on the recce or matched line; default M.stageLengthM(stage), the map's),
-- name = your row's name, top = 10 }.
--
-- Returns { passes = [{ ss, run, km, cancelled }], pass = the chosen ss, km, field = crews on it, fastestS,
--   rows = [{ pos, name, car, class, timeS, gapS, you }], you = placing or nil,
--   reason = nil | 'noBoard' | 'noPasses' | 'cancelled' | 'noTime' | 'lineMismatch' }
-- (reason says why you are not placed, or, for the first three, why there is no field at all).
function M.stageBoard(board, stage, opts)
  opts = opts or {}
  local st = type(stage) == 'table' and stage or { id = stage, name = opts.stageName }
  local out = { passes = {}, rows = {}, field = 0 }
  if type(board) ~= 'table' then out.reason = 'noBoard' return out end
  local mine = {}
  for _, p in ipairs(board.passes or {}) do
    if stageMatches(p, st) then
      mine[#mine + 1] = p
      out.passes[#out.passes + 1] = passInfo(p)
    end
  end
  if #mine == 0 then out.reason = 'noPasses' return out end
  local chosen
  if opts.pass ~= nil then
    for _, p in ipairs(mine) do if p.ss == opts.pass then chosen = p break end end
  end
  if not chosen then
    for _, p in ipairs(mine) do if p.cancelled ~= true then chosen = p break end end
  end
  chosen = chosen or mine[1]
  out.pass, out.km, out.run = chosen.ss, chosen.km, chosen.run
  if chosen.cancelled == true then out.reason = 'cancelled' return out end

  local crews = fieldOf(chosen, false)
  out.field = #crews
  out.fastestS = crews[1] and crews[1].timeS or nil
  local yourS = type(opts.bestS) == 'number' and opts.bestS or nil
  local lineM = opts.lineM
  if lineM == nil then lineM = M.stageLengthM(st) end
  if yourS and M.isMismatch(lineM, chosen.km) then
    out.reason = 'lineMismatch'
    yourS = nil
  elseif not yourS then
    out.reason = 'noTime'
  end
  local you = yourS and { you = true, name = opts.name or M.YOU, timeS = yourS } or nil
  local list, me = rank(crews, yourS, you)
  if me then out.you = placing(list, me, indexOf(list, me)) end
  out.rows = menuRows(list, opts.top or M.TOP)
  return out
end

------------------------------------------------------------------------------------------ your rally result

-- The passes that count, each as { ss, run, km, stageId, pass = the board pass }; and the ones left out.
local function countedPasses(event, board)
  local counted, cancelled, unmatched = {}, {}, {}
  if type(board) == 'table' then
    for _, p in ipairs(board.passes or {}) do
      local s = M.stageOf(event, p)
      if not s then unmatched[#unmatched + 1] = { ss = p.ss, stage = p.stage }
      elseif p.cancelled == true then cancelled[#cancelled + 1] = { ss = p.ss, stageId = s.id }
      else counted[#counted + 1] = { ss = p.ss, run = p.run, km = p.km, stageId = s.id, pass = p } end
    end
    return counted, cancelled, unmatched
  end
  -- no board: the itinerary, else each stage once
  local itin = event and event.itinerary
  if type(itin) == 'table' and #itin > 0 then
    for _, it in ipairs(itin) do
      local s = M.stageOf(event, { stage = it.stage, stageId = it.stageId })
      if not s then unmatched[#unmatched + 1] = { ss = it.ss, stage = it.stage }
      elseif it.cancelled == true then cancelled[#cancelled + 1] = { ss = it.ss, stageId = s.id }
      else counted[#counted + 1] = { ss = it.ss, run = it.run, km = it.km, stageId = s.id } end
    end
  else
    for i, s in ipairs((event and event.stages) or {}) do
      counted[#counted + 1] = { ss = i, run = 1, km = s.lengthM and s.lengthM / 1000, stageId = s.id }
    end
  end
  return counted, cancelled, unmatched
end

-- (the crews with a time on every one of these passes, each with its total, fastest first: notional included, as
-- they are the official times)
local function crewTotals(passes)
  local crews = {}
  if #passes == 0 then return crews end
  local acc, order = {}, {}
  for pi, c in ipairs(passes) do
    for _, r in ipairs(fieldOf(c.pass, true)) do
      local a = acc[r.key]
      if not a then
        a = { name = r.name, car = r.car, class = r.class, championship = r.championship, n = 0, totalS = 0,
          first = #order + 1 }
        acc[r.key] = a
        order[#order + 1] = r.key
      end
      if a.lastPass ~= pi then
        a.n, a.totalS, a.lastPass = a.n + 1, a.totalS + r.timeS, pi
        a.championship = a.championship or r.championship
      end
    end
  end
  for _, k in ipairs(order) do
    local a = acc[k]
    if a.n == #passes then
      crews[#crews + 1] = { key = k, name = a.name, car = a.car, class = a.class, championship = a.championship,
        timeS = ms(a.totalS), first = a.first }
    end
  end
  table.sort(crews, function(a, b)
    if math.abs(a.timeS - b.timeS) > M.EPS then return a.timeS < b.timeS end
    return a.first < b.first
  end)
  return crews
end

-- (the length a stage is checked by, start to flying finish: on the recce or matched line, from the caller, else the
-- map's)
local function lengthOf(stage, opts)
  local l = stage and type(opts.lineMByStage) == 'table' and opts.lineMByStage[stage.id] or nil
  if type(l) == 'number' then return l end
  return M.stageLengthM(stage)
end

-- event: the rally (events/<id>.json); board: its board or nil; bestByStage: { [stageId] = seconds }.
-- opts: { name = your row's name, lineMByStage = { [stageId] = metres start to flying finish on the line you are
-- timed on } (a stage not in it is measured on the map) }.
-- Returns { passes = counted [{ ss, run, km, stageId, comparable }], cancelled = [{ ss, stageId }],
--   unmatched = [{ ss, stage }], counted = #passes, comparable = how many of them are not a line mismatch,
--   kmTotal / kmCovered (the counted passes' km, and the comparable ones'), partial = true when some are left out,
--   complete (a time on every comparable pass), totalS (when complete: over the comparable passes),
--   missing = [stageId...] (comparable stages still to drive, in running order),
--   ranked = [{ pos, name, car, class, championship, totalS, gapS, you }] (crews with a time on every comparable
--   pass, and you when complete and ranked), you = placing or nil, noBoard, lineMismatch = [stageId...] (counted
--   stages whose length, on the line you are timed on or else the map's, is more than 5% off the pass's km),
--   notRanked = true when the comparable passes cover less than M.RANK_MIN_SHARE of the counted km: your total
--   stands, but it is not placed and scores you nothing,
--   field = [{ pos, key, name, championship, totalS }] (the crews' real ranking over every counted pass, without
--   you: their standings points come from it) }
function M.rallyResult(event, board, bestByStage, opts)
  opts = opts or {}
  bestByStage = bestByStage or {}
  local counted, cancelled, unmatched = countedPasses(event, board)
  local out = { passes = {}, cancelled = cancelled, unmatched = unmatched, missing = {}, ranked = {},
    lineMismatch = {}, noBoard = type(board) ~= 'table', complete = false }
  local seenMissing, byId, mism = {}, {}, {}
  for _, s in ipairs((event and event.stages) or {}) do byId[s.id] = s end
  -- (only against a board's km: with none there is nothing to rank against, and the map-only fallback's km is
  -- the whole line, which would set a start-to-flying-finish length against itself)
  local comparable, kmTotal, kmCovered = {}, 0, 0
  for _, c in ipairs(counted) do
    local off = false
    if not out.noBoard then
      if mism[c.stageId] == nil then
        mism[c.stageId] = M.isMismatch(lengthOf(byId[c.stageId], opts), c.km)
        if mism[c.stageId] then out.lineMismatch[#out.lineMismatch + 1] = c.stageId end
      end
      off = mism[c.stageId]
    end
    local km = type(c.km) == 'number' and c.km or 0
    kmTotal = kmTotal + km
    if not off then
      comparable[#comparable + 1] = c
      kmCovered = kmCovered + km
    end
    out.passes[#out.passes + 1] = { ss = c.ss, run = c.run, km = c.km, stageId = c.stageId, comparable = not off }
  end
  local total = 0
  for _, c in ipairs(comparable) do
    local b = bestByStage[c.stageId]
    if type(b) == 'number' then total = total + b
    elseif not seenMissing[c.stageId] then
      seenMissing[c.stageId] = true
      out.missing[#out.missing + 1] = c.stageId
    end
  end
  out.counted, out.comparable = #counted, #comparable
  out.kmTotal, out.kmCovered = math.floor(kmTotal * 100 + 0.5) / 100, math.floor(kmCovered * 100 + 0.5) / 100
  out.partial = #comparable < #counted or nil
  out.complete = #comparable > 0 and #out.missing == 0
  if out.complete then out.totalS = ms(total) end
  -- (the share by km; by passes when the passes have no km)
  local share = kmTotal > 0 and kmCovered / kmTotal or (#counted > 0 and #comparable / #counted or 0)
  out.notRanked = (not out.noBoard and #counted > 0 and share < M.RANK_MIN_SHARE - M.EPS) or nil
  -- the crews' totals over the comparable passes (the Results table, with you placed), and over every counted pass
  -- (their real ranking: what their standings points come from, whatever your lines are)
  if not out.noBoard then
    local full = crewTotals(counted)
    for i, r in ipairs(full) do
      local prev = full[i - 1]
      r.pos = (prev and math.abs(prev.timeS - r.timeS) <= M.EPS) and prev.pos or i
    end
    out.field = {}
    for i, r in ipairs(full) do
      out.field[i] = { pos = r.pos, key = r.key, name = r.name, championship = r.championship, totalS = r.timeS }
    end
  end
  local crews = (not out.noBoard) and crewTotals(comparable) or {}
  local ranks = out.complete and not out.notRanked
  local you = ranks and { you = true, key = nil, name = opts.name or M.YOU, timeS = out.totalS } or nil
  local list, me = rank(crews, ranks and out.totalS or nil, you)
  for i, r in ipairs(list) do
    out.ranked[i] = { pos = r.pos, key = r.key, name = r.name, car = r.car, class = r.class,
      championship = r.championship, totalS = r.timeS, gapS = r.gapS, you = r.you == true }
  end
  if me then out.you = placing(list, me, indexOf(list, me)) end
  return out
end

------------------------------------------------------------------------------------------ season standings

-- A standings block as written in a manifest or a season file, made whole: { championship = a name or false (every
-- crew), points, best = N or nil }.
local function standingsRules(season)
  local s = (season and type(season.standings) == 'table' and season.standings) or {}
  local champ = s.championship
  if champ == nil then champ = M.DEFAULT_STANDINGS.championship end
  if champ == false or type(champ) ~= 'string' or champ == '' or norm(champ) == 'all' then champ = false end
  local points = {}
  for i, p in ipairs(type(s.points) == 'table' and s.points or {}) do
    if type(p) ~= 'number' then break end
    points[i] = p
  end
  if #points == 0 then points = M.DEFAULT_STANDINGS.points end
  local best = tonumber(s.best)
  best = best and best >= 1 and math.floor(best) or nil
  return { championship = champ, points = points, best = best }
end
M.standingsRules = standingsRules

-- season: seasons/<id>.json (its standings block); rounds: [{ event, board, bestByStage, lineMByStage }] in season
-- order (lineMByStage as rallyResult's). opts: { name = your row's name, top = rows shown (default all) }.
-- The crews' points in every round come from their real ranking over all its counted passes (rallyResult's field),
-- whatever your lines. Yours come from your place in the comparable-stage ranking (your total against the crews'
-- over the same passes), set beside theirs without moving any crew a place. A round not ranked (its comparable
-- passes under M.RANK_MIN_SHARE of its km) scores you nothing; the crews score in it as usual.
-- Returns { rules = { championship, points, best }, rounds = [{ id, name, noBoard, notRanked, scored = crews
--   placed }], rows = [{ pos, name, points, perRound = [{ pos, points, partial = true | nil (yours, ranked over the
--   comparable passes only) } | { noBoard = true, points = 0 } |
--   { notRanked = true, points = 0 } (yours, in a round not ranked) | { points = 0 }], wins, you }],
--   you = your row (also when it is not in rows; nil only with no rally result anywhere), entries = all rows' count }
function M.standings(season, rounds, opts)
  opts = opts or {}
  local rules = standingsRules(season)
  local out = { rules = rules, rounds = {}, rows = {} }
  local entries, order = {}, {}
  local YOUKEY = {}
  local function entry(key, name, isYou)
    local e = entries[key]
    if not e then
      e = { name = name, you = isYou, perRound = {}, finishes = {}, points = 0 }
      entries[key] = e
      order[#order + 1] = key
    end
    return e
  end
  local nRounds = #(rounds or {})
  for ri, rd in ipairs(rounds or {}) do
    local ev = rd.event or {}
    local info = { id = ev.id, name = ev.name, noBoard = type(rd.board) ~= 'table', scored = 0 }
    out.rounds[ri] = info
    local res = (not info.noBoard) and
      M.rallyResult(ev, rd.board, rd.bestByStage, { name = opts.name, lineMByStage = rd.lineMByStage }) or nil
    info.notRanked = res and res.notRanked or nil
    if res then
      local function inChamp(r) return not rules.championship or norm(r.championship) == norm(rules.championship) end
      -- the crews: their real places over every counted pass (among their championship), never moved by you
      local pos, prev = 0, nil
      for _, r in ipairs(res.field or {}) do
        if inChamp(r) then
          pos = pos + 1
          local p = (prev and math.abs(prev.totalS - r.totalS) <= M.EPS) and prev.place or pos
          prev = { totalS = r.totalS, place = p }
          local e = entry(r.key, r.name, false)
          e.perRound[ri] = { pos = p, points = rules.points[p] or 0 }
          e.finishes[#e.finishes + 1] = p
          info.scored = info.scored + 1
        end
      end
      -- you: your place in the comparable-stage ranking (among the same championship), the crews' points as they are
      if not res.notRanked then
        local p, before = nil, 0
        for _, r in ipairs(res.ranked) do
          if r.you then p = before + 1 break end
          if inChamp(r) then before = before + 1 end
        end
        -- (tied with the crews just ahead: their place)
        if p then
          local mine
          for _, r in ipairs(res.ranked) do if r.you then mine = r end end
          local k = 0
          for _, r in ipairs(res.ranked) do
            if not r.you and inChamp(r) then
              k = k + 1
              if math.abs(r.totalS - mine.totalS) <= M.EPS then p = math.min(p, k) end
            end
          end
          local e = entry(YOUKEY, mine.name, true)
          e.perRound[ri] = { pos = p, points = rules.points[p] or 0, partial = res.partial or nil }
          e.finishes[#e.finishes + 1] = p
          info.scored = info.scored + 1
        end
      end
    end
  end
  for _, k in ipairs(order) do
    local e = entries[k]
    local scores = {}
    for ri = 1, nRounds do
      if out.rounds[ri].noBoard then e.perRound[ri] = { noBoard = true, points = 0 }
      elseif not e.perRound[ri] then
        e.perRound[ri] = { points = 0, notRanked = (e.you and out.rounds[ri].notRanked) or nil }
      else scores[#scores + 1] = e.perRound[ri].points end
    end
    table.sort(scores, function(a, b) return a > b end)
    local total = 0
    for i, s in ipairs(scores) do if not rules.best or i <= rules.best then total = total + s end end
    e.points = total
    e.counts = {}
    for _, p in ipairs(e.finishes) do e.counts[p] = (e.counts[p] or 0) + 1 end
    e.wins = e.counts[1] or 0
  end
  local maxPos = 0
  for _, k in ipairs(order) do for _, p in ipairs(entries[k].finishes) do if p > maxPos then maxPos = p end end end
  local function cmp(a, b)
    if a.points ~= b.points then return a.points > b.points end
    for p = 1, maxPos do
      local x, y = a.counts[p] or 0, b.counts[p] or 0
      if x ~= y then return x > y end
    end
    return nil
  end
  local list = {}
  for i, k in ipairs(order) do list[i] = entries[k] entries[k].first = i end
  table.sort(list, function(a, b)
    local c = cmp(a, b)
    if c ~= nil then return c end
    if a.you ~= b.you then return not a.you end
    return a.first < b.first
  end)
  local top = opts.top or #list
  for i, e in ipairs(list) do
    local prev = list[i - 1]
    e.pos = (prev and cmp(prev, e) == nil) and prev.pos or i
    local row = { pos = e.pos, name = e.name, points = e.points, perRound = e.perRound, wins = e.wins,
      you = e.you == true }
    if i <= top then out.rows[#out.rows + 1] = row end
    if e.you then out.you = row end
  end
  out.entries = #list
  return out
end

return M
