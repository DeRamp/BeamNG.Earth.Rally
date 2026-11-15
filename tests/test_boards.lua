-- boards.lua: a stage's leaderboard, your rally result and the season standings, on small made-up rallies.
local T = dofile(TESTS .. '/testlib.lua')
local B = require('earthRally/boards')

-- field rows: { seconds, driver, car, class, championship, notional }
local function crew(s, d, champ, notional) return { s, d, '1', 'O4WD', champ or 'national', notional or false } end

local event = {
  id = 'test-r1', name = 'Test Rally',
  stages = {
    { id = 'alpha', name = 'Alpha', lengthM = 10000 },
    { id = 'bravo', name = 'Bravo Road', lengthM = 5000 },
  },
}
local board = {
  format = 1,
  passes = {
    { ss = 'SS1', stage = 'Alpha', run = 1, km = 10.0, cancelled = false, field = {
      crew(300, 'Ann'), crew(310, 'Bob'), crew(320, ' cara '), crew(330, 'Dan', 'regional'), crew(305, 'Ned', nil, true) } },
    { ss = 'SS2', stage = 'bravo', run = 1, km = 5.0, cancelled = false, field = {
      crew(150, 'Ann'), crew(140, 'Bob'), crew(160, 'Cara'), crew(155, 'Dan', 'regional') } },
    { ss = 'SS3', stage = 'Alpha', run = 2, km = 10.0, cancelled = true, field = {} },
    { ss = 'SS4', stage = 'Alpha', run = 3, km = 10.0, cancelled = false, field = {
      crew(295, 'ANN'), crew(300, 'Bob'), crew(300, 'Cara', nil, true), crew(301, 'Dan', 'regional') } },
    { ss = 'SS5', stage = 'Charlie', run = 1, km = 8.0, cancelled = false, field = { crew(200, 'Ann') } },
  },
}

------------------------------------------------------------------------------------------ gapText
T.check(B.gapText(32.14) == '+32.1' and B.gapText(62.3) == '+1:02.3' and B.gapText(0) == '' and B.gapText(nil) == '',
  'gapText: seconds, minutes, nothing for the leader')

------------------------------------------------------------------------------------------ stageBoard
do
  local r = B.stageBoard(nil, 'alpha', { bestS = 300 })
  T.check(r.reason == 'noBoard' and #r.rows == 0 and #r.passes == 0, 'a stage with no board: noBoard, no rows')

  r = B.stageBoard(board, { id = 'zulu', name = 'Zulu' }, { bestS = 300 })
  T.check(r.reason == 'noPasses' and #r.rows == 0, 'a stage the board does not have: noPasses')

  r = B.stageBoard(board, event.stages[1], { bestS = 312, lineM = 10200 })
  T.check(#r.passes == 3 and r.passes[1].ss == 'SS1' and r.passes[2].cancelled == true and r.passes[3].run == 3,
    'pass list for the toggle: by the stage name, cancelled ones included')
  T.check(r.pass == 'SS1' and r.field == 4, 'default pass: the first counted one; notional left out of the field')
  T.check(r.rows[1].name == 'Ann' and r.rows[2].name == 'Bob' and r.rows[3].you and r.rows[4].name == 'cara',
    'you inserted in place; names trimmed')
  T.check(r.rows[5].pos == 5 and r.rows[5].name == 'Dan', 'crews behind you move down a place')
  T.check(r.you.pos == 3 and r.you.of == 5 and r.you.gapS == 12 and r.you.aheadS == 2 and r.reason == nil,
    'your placing: 3rd of 5, +12 to the fastest, +2 to the one ahead')
  T.check(r.rows[1].gapS == 0 and r.rows[2].gapS == 10 and type(r.rows[1].timeS) == 'number', 'times stay numbers')

  r = B.stageBoard(board, { id = 'alpha', name = 'Alpha' }, { bestS = 290, pass = 'SS1' })
  T.check(r.you.pos == 1 and r.rows[1].you and r.rows[2].pos == 2 and r.you.gapS == -10 and r.you.aheadS == nil and
    r.you.leadS == 10 and r.rows[2].gapS == 10, 'you faster than everyone: first, leading by 10')

  r = B.stageBoard(board, event.stages[1], { pass = 'SS3', bestS = 300 })
  T.check(r.reason == 'cancelled' and #r.rows == 0 and r.you == nil and #r.passes == 3, 'a cancelled pass: no board')

  r = B.stageBoard(board, event.stages[1], { pass = 'SS4' })
  T.check(r.reason == 'noTime' and r.you == nil and #r.rows == 3 and r.rows[1].name == 'ANN',
    'no time yet: the field, no placing')
  T.check(r.rows[2].pos == 2 and r.rows[3].pos == 3, 'notional dropped (Cara at 300 notional)')

  r = B.stageBoard(board, event.stages[1], { pass = 'SS4', bestS = 300 })
  T.check(r.rows[2].name == 'Bob' and r.rows[3].you and r.rows[2].pos == 2 and r.rows[3].pos == 2 and r.rows[4].pos == 4
    and r.you.pos == 2 and r.you.aheadS == 0, 'a tie in time: same place, you after the crew you tie')

  r = B.stageBoard(board, event.stages[1], { bestS = 300, lineM = 10600 })
  T.check(r.reason == 'lineMismatch' and r.you == nil and r.field == 4 and #r.rows == 4,
    'line 6% off: field shown, you not placed')
  r = B.stageBoard(board, event.stages[1], { bestS = 300, lineM = 10400 })
  T.check(r.reason == nil and r.you ~= nil, 'line 4% off: placed')

  -- top N: you outside it
  local big = { passes = { { ss = 'SS1', stage = 'alpha', run = 1, km = 10, field = {} } } }
  for i = 1, 30 do big.passes[1].field[i] = crew(100 + i, 'Crew ' .. i) end
  r = B.stageBoard(big, 'alpha', { bestS = 120.5 })
  T.check(#r.rows == 13 and r.rows[10].pos == 10 and r.rows[11].pos == 20 and r.rows[11].skipped and
    r.rows[12].you and r.rows[12].pos == 21 and r.rows[13].pos == 22 and r.rows[13].name == 'Crew 21' and
    not r.rows[12].skipped and not r.rows[13].skipped and r.you.of == 31,
    'you outside the top 10: the top 10, a gap, then the crew ahead, you and the crew behind')
  r = B.stageBoard(big, 'alpha', { bestS = 103.5, top = 5 })
  T.check(#r.rows == 6 and r.rows[4].you and r.rows[4].pos == 4 and r.rows[6].pos == 6 and not r.rows[4].skipped,
    'you inside the top: top crews plus you in place')
  r = B.stageBoard(big, 'alpha', { bestS = 50 })
  T.check(#r.rows == 11 and r.rows[1].you and r.rows[1].pos == 1 and r.rows[11].pos == 11, 'you first: you and ten crews')
  r = B.stageBoard(big, 'alpha', { bestS = 110.5, top = 10 })
  T.check(#r.rows == 12 and r.rows[11].you and r.rows[11].pos == 11 and r.rows[12].pos == 12 and
    not r.rows[11].skipped and not r.rows[12].skipped, '11th: you right after the top, and the crew behind, no gap')
  r = B.stageBoard(big, 'alpha', { bestS = 111.5 })
  T.check(#r.rows == 13 and r.rows[11].pos == 11 and r.rows[12].you and r.rows[13].pos == 13 and
    not r.rows[11].skipped, '12th: the crew ahead is 11th, no gap')
  r = B.stageBoard(big, 'alpha', { bestS = 112.5 })
  T.check(#r.rows == 14 and r.rows[11].pos == 11 and r.rows[12].pos == 12 and r.rows[13].you and
    r.rows[14].pos == 14 and not r.rows[11].skipped, '13th: one crew between the top and the one ahead: shown, no gap')
  r = B.stageBoard(big, 'alpha', { bestS = 113.5 })
  T.check(#r.rows == 13 and r.rows[11].pos == 13 and r.rows[11].skipped and r.rows[12].you and r.rows[12].pos == 14,
    '14th: two crews left out, the gap before the crew ahead')
  r = B.stageBoard(big, 'alpha', { bestS = 200 })
  T.check(#r.rows == 12 and r.rows[11].pos == 30 and r.rows[11].skipped and r.rows[12].you and r.rows[12].pos == 31
    and r.you.pos == 31 and r.you.of == 31, 'last: the crew ahead and you, nobody behind')
  local small = { passes = { { ss = 'SS1', stage = 'alpha', run = 1, km = 10, field = {} } } }
  for i = 1, 4 do small.passes[1].field[i] = crew(100 + i, 'Crew ' .. i) end
  r = B.stageBoard(small, 'alpha', { bestS = 300 })
  T.check(#r.rows == 5 and r.rows[5].you and not r.rows[5].skipped, 'a field smaller than the top: everyone and you')

  local empty = { passes = { { ss = 'SS1', stage = 'alpha', run = 1, km = 10, field = {} } } }
  r = B.stageBoard(empty, 'alpha', { bestS = 300 })
  T.check(r.field == 0 and #r.rows == 1 and r.rows[1].you and r.you.pos == 1 and r.you.of == 1 and r.you.gapS == 0,
    'an empty field: you alone, 1st of 1')
  r = B.stageBoard(empty, 'alpha', {})
  T.check(r.field == 0 and #r.rows == 0 and r.reason == 'noTime', 'an empty field, no time: nothing')
  local dup = { passes = { { ss = 'SS1', stage = 'alpha', km = 10, field = { crew(310, 'Ann'), crew(300, 'ann ') } } } }
  r = B.stageBoard(dup, 'alpha', {})
  T.check(r.field == 1 and r.rows[1].timeS == 300, 'a driver twice in a pass: once, their fastest')
end

------------------------------------------------------------------------------------------ rallyResult
do
  local r = B.rallyResult(event, board, { alpha = 300 })
  T.check(#r.passes == 3 and r.passes[1].ss == 'SS1' and r.passes[3].ss == 'SS4' and #r.cancelled == 1 and
    #r.unmatched == 1 and r.unmatched[1].stage == 'Charlie', 'counted passes: cancelled and unknown stages left out')
  T.check(not r.complete and r.totalS == nil and #r.missing == 1 and r.missing[1] == 'bravo' and r.you == nil,
    'incomplete: which stage is missing')
  -- crews over SS1 + SS2 + SS4, notional included: Ann 300+150+295=745, Bob 310+140+300=750, Cara 320+160+300=780
  -- (notional on SS4 counts), Dan 330+155+301=786; Ned has SS1 only: not ranked
  T.check(#r.ranked == 4 and r.ranked[1].name == 'Ann' and r.ranked[1].totalS == 745 and r.ranked[3].name == 'cara' and
    r.ranked[3].totalS == 780, 'crews ranked on the same passes, notional included')
  local ned = false
  for _, x in ipairs(r.ranked) do if x.name == 'Ned' then ned = true end end
  T.check(not ned, 'a crew with a time on only some passes is not ranked')

  r = B.rallyResult(event, board, { alpha = 299, bravo = 151 })
  -- yours: 299 + 151 + 299 = 749
  T.check(r.complete and r.totalS == 749 and #r.missing == 0, 'complete: your best once per counted pass')
  T.check(r.you.pos == 2 and r.you.of == 5 and r.you.gapS == 4 and r.you.aheadS == 4 and r.ranked[2].you and
    r.ranked[3].pos == 3 and r.ranked[3].name == 'Bob' and r.ranked[2].gapS == 4, 'you placed in the rally: 2nd of 5')

  r = B.rallyResult(event, board, { alpha = 299.9, bravo = 150.2 })   -- 750.0: ties with Bob
  T.check(r.you.pos == 2 and r.ranked[2].name == 'Bob' and r.ranked[3].you and r.ranked[3].pos == 2 and
    r.ranked[4].pos == 4, 'a tie in total: shared place')

  r = B.rallyResult(event, nil, { alpha = 300 })
  T.check(r.noBoard and #r.passes == 2 and not r.complete and #r.ranked == 0 and r.missing[1] == 'bravo',
    'no board, no itinerary: each stage once')
  r = B.rallyResult(event, nil, { alpha = 300, bravo = 100 })
  T.check(r.complete and r.totalS == 400 and r.you.pos == 1 and r.you.of == 1, 'no board: your total, alone')
  local ev2 = { stages = event.stages, itinerary = {
    { ss = 'SS1', stage = 'Alpha', run = 1 }, { ss = 'SS2', stage = 'Alpha', run = 2 },
    { ss = 'SS3', stage = 'Bravo Road', run = 1, cancelled = true } } }
  r = B.rallyResult(ev2, nil, { alpha = 300 })
  T.check(r.complete and r.totalS == 600 and #r.cancelled == 1, 'no board: the itinerary, passes counted twice')

  local mis = { stages = { { id = 'alpha', name = 'Alpha', lengthM = 12000 }, event.stages[2] } }
  r = B.rallyResult(mis, board, { alpha = 300, bravo = 150 })
  T.check(#r.lineMismatch == 1 and r.lineMismatch[1] == 'alpha' and r.complete, 'a stage whose line is off is named')
  T.check(r.counted == 3 and r.comparable == 1 and r.kmTotal == 25 and r.kmCovered == 5 and r.partial and
    r.passes[1].comparable == false and r.passes[2].comparable == true and #r.missing == 0,
    'the result is over the comparable passes: 1 of 3, 5 of 25 km')
  T.check(r.notRanked and r.totalS == 150 and r.you == nil and #r.ranked == 4 and r.ranked[1].name == 'Bob' and
    r.ranked[1].totalS == 140,
    'under 75% of the km: not ranked; your total and the crews\' over the comparable pass only, you not placed')
  for _, x in ipairs(r.ranked) do T.check(not x.you, 'you not in the ranked list') end

  -- four stages, one off: ranked over the other three (the user, 2026-11-14)
  local four = { stages = { { id = 'a', name = 'A', lengthM = 10000 }, { id = 'b', name = 'B', lengthM = 10000 },
    { id = 'c', name = 'C', lengthM = 10000 }, { id = 'd', name = 'D', lengthM = 10000 } } }
  local function fb(dKm)
    return { passes = {
      { ss = 'SS1', stage = 'a', km = 10, field = { crew(100, 'X'), crew(101, 'Y'), crew(99, 'Z') } },
      { ss = 'SS2', stage = 'b', km = 10, field = { crew(100, 'X'), crew(101, 'Y'), crew(99, 'Z') } },
      { ss = 'SS3', stage = 'c', km = 10, field = { crew(100, 'X'), crew(101, 'Y'), crew(99, 'Z') } },
      { ss = 'SS4', stage = 'd', km = dKm, field = { crew(50, 'X'), crew(40, 'Z') } } } }
  end
  local b4 = fb(2)          -- (d's map line is 10 km against a 2 km pass: off)
  r = B.rallyResult(four, b4, { a = 100.5, b = 100.5, c = 100.5 })
  T.check(r.comparable == 3 and r.counted == 4 and r.kmCovered == 30 and r.kmTotal == 32 and r.partial and
    not r.notRanked and r.complete and r.totalS == 301.5 and #r.lineMismatch == 1 and r.lineMismatch[1] == 'd',
    'one stage off, 30 of 32 km: ranked over the other three, d not needed for a complete result')
  T.check(r.you and r.you.pos == 3 and r.you.of == 4 and r.ranked[1].name == 'Z' and r.ranked[3].you and
    r.ranked[4].name == 'Y', 'Y, with no time on the left-out pass, is ranked: crews need only the comparable passes')
  r = B.rallyResult(four, fb(10), { a = 100.5, b = 100.5, c = 100.5 },
    { lineMByStage = { d = 13000 } })
  T.check(r.comparable == 3 and r.kmCovered == 30 and r.kmTotal == 40 and not r.notRanked and r.you ~= nil,
    'measured on the driven line (13 km against 10): off; 30 of 40 km is exactly 75%: ranked')
  r = B.rallyResult(four, fb(10), { a = 100.5, b = 100.5, c = 100.5 },
    { lineMByStage = { c = 13000, d = 13000 } })
  T.check(r.comparable == 2 and r.notRanked and r.you == nil and r.complete and r.totalS == 201,
    'two of four off (50%): not ranked, your total over the two still shown')
  r = B.rallyResult({ stages = { { id = 'a', name = 'A', lengthM = 20000 } } }, fb(10), { a = 100 },
    { lineMByStage = { a = 10100 } })
  T.check(#r.lineMismatch == 0 and r.comparable == 1, "the driven line's length is taken over the map's")
  -- the same line, its start and flying finish 10 km apart: start to FF is what the stage's km measures
  local ff = { stages = { { id = 'alpha', name = 'Alpha', lengthM = 12000,
    controls = { start = { distM = 1000 }, ff = { distM = 11000 } } }, event.stages[2] } }
  T.check(B.stageLengthM(ff.stages[1]) == 10000 and B.stageLengthM(event.stages[1]) == 10000 and
    B.stageLengthM({ lengthM = 5, controls = { start = { distM = 3 } } }) == 5 and B.stageLengthM(nil) == nil,
    'stageLengthM: start to flying finish when both are on the line, else the whole line')
  r = B.rallyResult(ff, board, { alpha = 299, bravo = 151 })
  T.check(#r.lineMismatch == 0 and not r.notRanked and r.you and r.you.pos == 2, 'measured start to FF: ranked')
  local sb = B.stageBoard(board, ff.stages[1], { bestS = 300 })
  T.check(sb.you and sb.reason == nil, 'stageBoard measures start to FF too when no lineM is given')

  local allCx = { passes = { { ss = 'SS1', stage = 'alpha', km = 10, cancelled = true, field = {} } } }
  r = B.rallyResult(event, allCx, { alpha = 300 })
  T.check(not r.complete and #r.passes == 0 and #r.ranked == 0, 'every pass cancelled: nothing to total')

  local tenths = { stages = { { id = 'a', name = 'A' } }, }
  local tb = { passes = {} }
  for i = 1, 10 do tb.passes[i] = { ss = 'SS' .. i, stage = 'a', km = 1, field = { crew(0.1, 'X') } } end
  r = B.rallyResult(tenths, tb, { a = 0.1 })
  T.check(r.ranked[1].pos == 1 and r.ranked[2].pos == 1 and r.totalS == 1, 'sums of tenths tie exactly')
end

------------------------------------------------------------------------------------------ standings
do
  local rules = B.standingsRules({})
  T.check(rules.championship == 'national' and rules.points[1] == 25 and #rules.points == 15 and rules.best == nil,
    'defaults: national, 25..1 over 15 places, every round')
  T.check(B.standingsRules({ standings = { championship = false } }).championship == false and
    B.standingsRules({ standings = { championship = 'all' } }).championship == false, 'all crews: false or "all"')
  local again = B.standingsRules({ standings = B.standingsRules({ standings = { championship = 'all', best = '3',
    points = { 9, 'x', 1 } } }) })
  T.check(again.championship == false and again.best == 3 and #again.points == 1,
    'its own output reads back the same (pack.lua writes the season file with it); points stop at a non-number')

  local ev = { id = 'r', stages = { { id = 's', name = 'S' } } }
  local function one(times)
    local f = {}
    for i, t in ipairs(times) do f[i] = crew(t[1], t[2], t[3]) end
    return { passes = { { ss = 'SS1', stage = 's', km = 1, field = f } } }
  end
  local season = { standings = { points = { 10, 6, 4, 3 } } }
  local rounds = {
    { event = { id = 'r1', name = 'One', stages = ev.stages },
      board = one({ { 100, 'Ann' }, { 101, 'Reg', 'regional' }, { 102, 'Bob' }, { 103, 'Cara' } }),
      bestByStage = { s = 101.5 } },
    { event = { id = 'r2', name = 'Two', stages = ev.stages }, board = nil, bestByStage = { s = 50 } },
    { event = { id = 'r3', name = 'Three', stages = ev.stages },
      board = one({ { 100, 'bob ' }, { 101, 'Ann' }, { 102, 'Cara' } }), bestByStage = {} },
  }
  local st = B.standings(season, rounds)
  -- r1 (national): the crews by their real places, Ann 1 (10), Bob 2 (6), Cara 3 (4), Reg filtered out; you 2nd
  -- among them (6), no crew moved down for it. r2 no board: no points; r3: Bob 1 (10), Ann 2 (6), Cara 3 (4)
  -- Ann 16, Bob 16, Cara 8, you 6
  T.check(#st.rounds == 3 and st.rounds[2].noBoard and st.rounds[1].scored == 4, 'a round with no board: listed')
  T.check(st.rows[1].name == 'Ann' and st.rows[1].points == 16 and st.rows[2].name == 'Bob' and st.rows[2].points == 16
    and st.rows[1].perRound[1].pos == 1 and st.rows[2].perRound[1].pos == 2 and st.rows[2].perRound[1].points == 6,
    'points summed; crews one entry by driver name, trimmed and case folded; you move no crew down')
  -- the crews' points are the same with no result of yours, and with a mismatch
  local function crewPoints(x)
    local t = {}
    for _, r in ipairs(x.rows) do if not r.you then t[#t + 1] = r.name .. '=' .. r.points end end
    table.sort(t)
    return table.concat(t, ',')
  end
  local noYou = {}
  for i, rd in ipairs(rounds) do noYou[i] = { event = rd.event, board = rd.board, bestByStage = {} } end
  local offLine = {}
  for i, rd in ipairs(rounds) do offLine[i] = { event = rd.event, board = rd.board, bestByStage = rd.bestByStage,
    lineMByStage = { s = 5000 } } end
  local sOff = B.standings(season, offLine)
  T.check(crewPoints(B.standings(season, noYou)) == crewPoints(st) and crewPoints(sOff) == crewPoints(st) and
    sOff.you == nil, "crews' points identical with no result of yours and with your line off (" .. crewPoints(st) .. ')')
  T.check(st.you and st.you.points == 6 and st.you.pos == 4 and st.you.perRound[1].pos == 2 and
    st.you.perRound[2].noBoard and st.you.perRound[3].pos == nil, 'your row, per round')
  local reg = false
  for _, r in ipairs(st.rows) do if r.name == 'Reg' then reg = true end end
  T.check(not reg and st.entries == 4, 'other championships do not score')

  -- a round whose map is not the stage as run (2 km of line against a 1 km pass): not ranked, your fastest time
  -- scores nothing there; the crews score as usual, from their real places
  local mis = B.standings(season, { rounds[1], { event = { id = 'm1', name = 'Mis', stages = { { id = 's', name = 'S',
    lengthM = 2000 } } }, board = one({ { 100, 'Ann' }, { 102, 'Bob' } }), bestByStage = { s = 90 } } })
  T.check(mis.rounds[2].notRanked and mis.rounds[2].scored == 2 and mis.rows[1].name == 'Ann' and
    mis.rows[1].points == 20 and mis.you.points == 6, 'a round not ranked: you score nothing in it, the crews do')
  T.check(mis.you.perRound[2].notRanked and mis.you.perRound[2].points == 0 and mis.rows[1].perRound[2].pos == 1 and
    mis.you.perRound[1].pos == 2, 'your cell flags it; the crews keep their places')
  local mis2 = B.standings(season, { { event = { id = 'm1', name = 'Mis', stages = { { id = 's', name = 'S',
    lengthM = 2000 } } }, board = one({ { 100, 'Ann' }, { 102, 'Bob' } }), bestByStage = { s = 90 },
    lineMByStage = { s = 1020 } } })
  T.check(mis2.you and mis2.you.pos == 1 and not mis2.rounds[1].notRanked,
    'the same round measured on the driven line (1.02 km against 1 km): ranked, you score')
  local noB = B.rallyResult({ stages = { { id = 's', name = 'S', lengthM = 12000,
    controls = { start = { distM = 1000 }, ff = { distM = 11000 } } } } }, nil, { s = 90 })
  T.check(#noB.lineMismatch == 0 and not noB.notRanked, 'no board: no mismatch (there is no km to set it against)')
  T.check(st.rows[1].perRound[1].points == 10 and st.rows[1].perRound[3].points == 6 and st.rows[1].wins == 1,
    'per round points and wins')

  local top = B.standings(season, rounds, { top = 2 })
  T.check(#top.rows == 2 and top.you.pos == 4 and not top.rows[2].you, 'your row given when outside the rows shown')

  local all = B.standings({ standings = { championship = 'all', points = { 10, 6, 4, 3 } } }, rounds)
  T.check(all.entries == 5 and all.rounds[1].scored == 5, 'championship all: every crew scores')

  -- best = 1: only each entry's best round counts
  local b1 = B.standings({ standings = { points = { 10, 6, 4, 3 }, best = 1 } }, rounds)
  T.check(b1.rows[1].name == 'Ann' and b1.rows[1].points == 10 and b1.rows[2].name == 'Bob' and
    b1.rows[2].points == 10, 'best = N: only the best N rounds count')
  T.check(b1.rows[1].pos == 1 and b1.rows[2].pos == 1, 'a win and a second each: a full tie, the same place')

  -- a full tie: same points, same finishes
  local tie = {
    { event = { stages = ev.stages }, board = one({ { 100, 'Ann' }, { 101, 'Bob' } }) },
    { event = { stages = ev.stages }, board = one({ { 100, 'Bob' }, { 101, 'Ann' } }) },
  }
  local t = B.standings({}, tie)
  T.check(t.rows[1].points == 45 and t.rows[2].points == 45 and t.rows[1].pos == 1 and t.rows[2].pos == 1,
    'a full tie: same place')
  T.check(t.you == nil, 'no result of yours anywhere: no row of yours')
  -- wins break a points tie: X 25+1 (a win, a 15th) vs Y 13+13 (two 4ths) = 26 each
  local f1 = {}
  f1[1] = crew(100, 'X')
  for i = 2, 3 do f1[i] = crew(100 + i, 'P' .. i) end
  f1[4] = crew(200, 'Y')
  local r2f = {}
  for i = 1, 3 do r2f[#r2f + 1] = crew(100 + i, 'Q' .. i) end
  r2f[#r2f + 1] = crew(110, 'Y')
  for i = 5, 14 do r2f[#r2f + 1] = crew(110 + i, 'R' .. i) end
  r2f[#r2f + 1] = crew(200, 'X')
  local w = B.standings({}, {
    { event = { stages = ev.stages }, board = { passes = { { ss = 'SS1', stage = 's', km = 1, field = f1 } } } },
    { event = { stages = ev.stages }, board = { passes = { { ss = 'SS1', stage = 's', km = 1, field = r2f } } } },
  })
  local px, py
  for _, r in ipairs(w.rows) do if r.name == 'X' then px = r elseif r.name == 'Y' then py = r end end
  T.check(px.points == 26 and py.points == 26 and px.pos < py.pos, 'equal points: more wins first')

  -- a season whose only round does not match the official distance: no points for you, the crews' as usual
  local off = { { event = { id = 'r1', stages = { { id = 's', name = 'S', lengthM = 2000 } } },
    board = one({ { 100, 'Ann' }, { 102, 'Bob' } }), bestByStage = { s = 50 } } }
  local so = B.standings({}, off)
  T.check(so.you == nil and so.rows[1].name == 'Ann' and so.rows[1].points == 25 and so.rounds[1].notRanked,
    'line mismatch: no points for you in that round')
  -- you ahead of crews in a partial ranking: your points from your place there; the crews below are not moved
  local pr = B.rallyResult(ev, one({ { 100, 'Ann' }, { 102, 'Bob' } }), { s = 99 })
  T.check(pr.field[1].name == 'Ann' and pr.field[1].pos == 1 and pr.field[2].pos == 2 and pr.ranked[1].you,
    "rallyResult's field: the crews' real ranking, without you")
  local sp = B.standings({}, { { event = ev, board = one({ { 100, 'Ann' }, { 102, 'Bob' } }), bestByStage = { s = 99 } } })
  local ann, bob
  for _, r in ipairs(sp.rows) do if r.name == 'Ann' then ann = r elseif r.name == 'Bob' then bob = r end end
  T.check(sp.you.perRound[1].pos == 1 and sp.you.points == 25 and ann.points == 25 and ann.perRound[1].pos == 1 and
    bob.points == 20, 'you 1st: 25; Ann still 1st among the crews (25), Bob 2nd (20)')

  -- ranked over part of the rally (a stage off the official distance left out, the rest over 75%): your cell says so
  T.check(sp.you.perRound[1].partial == nil, 'ranked over the whole rally: no partial mark')
  local pev = { stages = { { id = 's', name = 'S', lengthM = 10000 }, { id = 't', name = 'T', lengthM = 1000 } } }
  local pb = { passes = { { ss = 'SS1', stage = 's', km = 10, field = { crew(100, 'Ann'), crew(102, 'Bob') } },
    { ss = 'SS2', stage = 't', km = 1, field = { crew(40, 'Ann'), crew(41, 'Bob') } } } }
  local spp = B.standings({}, { { event = pev, board = pb, bestByStage = { s = 99, t = 60 }, lineMByStage = { t = 2000 } } })
  T.check(spp.you and spp.you.perRound[1].pos == 1 and spp.you.perRound[1].partial == true and
    spp.rows[1].perRound[1].partial == nil, "ranked over the stages that match: your cell marked partial, the crews' not")

  -- topRows: the top N and you, the one home of that list
  local list = {}
  for i = 1, 12 do list[i] = { pos = i, name = 'C' .. i, totalS = 100 + i, gapS = i - 1 } end
  table.insert(list, 12, { pos = 12, name = 'You', totalS = 111.5, gapS = 10.5, you = true })
  local rows = B.topRows(list, 10)
  T.check(#rows == 13 and rows[11].name == 'C11' and rows[12].you and not rows[12].skipped and rows[12].timeS == 111.5
    and rows[13].name == 'C12' and rows[1].timeS == 101, 'topRows: ten crews, then the crew ahead, you and the one behind; totals as timeS')

  local none = B.standings({}, {})
  T.check(#none.rows == 0 and none.you == nil and none.entries == 0, 'a season with no rounds: an empty table')
end

T.done('test_boards.lua')
