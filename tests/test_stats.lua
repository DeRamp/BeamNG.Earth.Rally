-- stats (#76): nothing recorded before Yes or with the leaderboard off, only allowed fields, a new random number
-- each session (never saved), an install number (saved, sent alone in install_seen, deleted by No), rallies and stages by name (own ones too), one start and one end per run, rally attempts; sent through a
-- stand-in companion: sent events taken off by identity, refused batches dropped, No dropping a send under way;
-- errors cleaned and capped, the game's log watched and given back.
local T = dofile(TESTS .. '/testlib.lua')
function log() end
local files = {}
function jsonReadFile(p) return files[p] and T.jsonDecode(files[p]) end
function jsonWriteFile(p, t) files[p] = T.jsonEncode(t) return true end
jsonEncode = T.jsonEncode
FS = { fileExists = function(_, p) return files[p] ~= nil end }
beamng_version = '0.40.5.0'
io.open = function() return nil end      -- (sent.jsonl: not written in the test)

-- a stand-in companion (online.sendStats): answers held until reply(), or refused when not connected
local sent, pending, connected = {}, {}, true
local function transport(events, cb)
  if not connected then return false end
  sent[#sent + 1] = events
  pending[#pending + 1] = cb
  return true
end
local function reply(r) local cb = table.remove(pending, 1) if cb then cb(r) end end
local active = true

local stats = require('earthRally/stats')
stats.active = function() return active end
stats.transport = transport
stats.init('1.6.2-alpha+stats')
local function frames(n) for _ = 1, n or 10 do stats.update(0.1) end end

T.check(stats.consent() == 'ask', 'asks first')
T.check(stats.record('session_start') == false, 'nothing recorded before the answer')
T.check(#stats._queue() == 0, 'queue empty before the answer')

-- leaving the menu without the question shown is not an answer; with it shown, it is a No
stats.menuClosed()
T.check(stats.consent() == 'ask', 'not shown: still asking')
stats.prompting() stats.menuClosed()
T.check(stats.consent() == 'no', 'shown and left: No')
T.check(stats.record('session_start') == false, 'No: nothing recorded')

stats.answer(true)
local session = stats._session()
T.check(type(session) == 'string' and #session == 32 and session:match('^%x+$'), 'a 32-hex session number')
T.check(not files[stats.STATE_FILE]:find(session, 1, true), 'the session number is not saved')
local install = stats._install()
T.check(type(install) == 'string' and #install == 32 and install:match('^%x+$') and install ~= session, 'a 32-hex install number')
T.check(files[stats.STATE_FILE]:find(install, 1, true) ~= nil, 'the install number saved')
local q = stats._queue()
T.check(#q == 2 and q[1].event == 'session_start' and q[2].event == 'install_seen', 'Yes: session_start and install_seen queued')
T.check(q[1].day and q[1].day:match('^%d%d%d%d%-%d%d%-%d%d$') and q[1].mod == '1.6.2-alpha+stats', 'day and mod set')
for k in pairs(q[1]) do
  T.check(({ event = 1, session = 1, mod = 1, game = 1, earth = 1, day = 1 })[k], 'only the common fields: ' .. k)
end
T.check(q[2].install == install and q[2].session == nil and q[2].day == q[1].day, 'install_seen: the install number, no session')
for k in pairs(q[2]) do T.check(stats.INSTALL_FIELDS[k], 'install_seen: only its fields: ' .. k) end
T.check(stats.record('install_seen') == false, 'install_seen never through record (no session number on it)')
stats.sessionStart()
T.check(#q == 2, 'install_seen once a session')
T.check(stats.record('made_up') == false, 'unknown events refused')
stats.record('error', { code = 'x', module = 'main', message = 'C:/Users/Someone/secret' })
T.check(q[#q].code == 'x' and q[#q].message ~= nil, 'an error keeps its text')
stats.record('stage_started', { stage = 'x', message = 'no' })
T.check(q[#q].message == nil, 'unlisted fields dropped')

-- names: a pack's rally and a player's own imported or home-made one are both sent by name, cut to 80
local packEv = { id = 'e1', name = 'ARA 2026', pack = { file = 'ara.zip' }, stages = { { id = 's1', name = 'SS1 A' }, { id = 's2', name = 'SS2 B' } } }
local ownEv = { id = 'e2', name = "Bob's farm", stages = { { id = 's1', name = 'Back field' } } }
local r, s = stats.names(packEv, packEv.stages[1])
T.check(r == 'ARA 2026' and s == 'SS1 A', 'pack: named')
r, s = stats.names(ownEv, ownEv.stages[1])
T.check(r == "Bob's farm" and s == 'Back field', 'own map: named, not custom')
r, s = stats.names({ id = 'e3', stages = {} }, { id = 'ss9' })
T.check(r == 'e3' and s == 'ss9', 'no name: its id')
r, s = stats.names({ name = string.rep('x', 120) }, nil)
T.check(#r == 80 and s == nil, 'a long name cut to 80, no stage: nil')

-- one start and one end per run; no end without a start
local function count(ev) local n = 0 for _, e in ipairs(stats._queue()) do if e.event == ev then n = n + 1 end end return n end
local function runOf(i, extra)
  local t = { event = packEv, stage = packEv.stages[i], ss = i }
  for k, v in pairs(extra or {}) do t[k] = v end
  return t
end
local n0 = #q
local run = runOf(1, { resets = 2, checks = { line = 'recce' } })
stats.stageStarted(run) stats.stageStarted(run)
T.check(#q == n0 + 2 and q[n0 + 1].event == 'stage_started' and q[n0 + 2].event == 'rally_started', 'start + rally start, once')
run.finalTime = 412.4
stats.stageEnded(run, 'finished') stats.stageEnded(run, 'quit')
T.check(#q == n0 + 3 and q[n0 + 3].result == 'finished' and q[n0 + 3].time_s == 412 and q[n0 + 3].resets == 2, 'one end, whole seconds')
stats.stageEnded(runOf(2), 'quit')
T.check(#q == n0 + 3, 'no end without a start (left before GO)')
for _, e in ipairs(q) do
  if e.event ~= 'install_seen' then T.check(e.install == nil, 'no install number on ' .. e.event) end
end

-- the install number: kept across sessions (init again), deleted by No, a new one after a later Yes
stats._reset() stats.init('x')
T.check(stats._install() == install, 'the install number read back on a later session')
stats.sessionStart()
local seen = stats._queue()[#stats._queue()]
T.check(seen.event == 'install_seen' and seen.install == install, 'a later session: the same install number sent')
stats.answer(false)
T.check(stats._install() == nil and not files[stats.STATE_FILE]:find(install, 1, true), 'No: the install number deleted')
stats._reset() stats.init('x')
T.check(stats._install() == nil, 'No: nothing read back')
stats.answer(true)
T.check(stats._install() and stats._install() ~= install, 'Yes after No: a new install number')
-- (a saved No with an install number left in the file: not read back)
files[stats.STATE_FILE] = T.jsonEncode({ consent = 'no', install = install })
stats._reset() stats.init('x')
T.check(stats._install() == nil, 'a No on file: its install number ignored')

-- rally attempts: restarting stage 1 before finishing it is the same attempt; every stage finished in the attempt
-- (any order) finishes the rally, once
local fresh = function() stats._reset() files = {} stats.init('x') stats.answer(true) end
fresh()
local a = runOf(1) stats.stageStarted(a) stats.stageEnded(a, 'quit')
a = runOf(1) stats.stageStarted(a)
T.check(count('rally_started') == 1, 'stage 1 restarted: one rally start')
a.finalTime = 300 stats.stageEnded(a, 'finished')
local b = runOf(2, { finalTime = 200 }) stats.stageStarted(b) stats.stageEnded(b, 'finished')
T.check(count('rally_finished') == 1, 'every stage finished: rally finished')
b = runOf(2, { finalTime = 190 }) stats.stageStarted(b) stats.stageEnded(b, 'finished')
T.check(count('rally_finished') == 1, 'a stage run again after: no second finish')
a = runOf(1, { finalTime = 300 }) stats.stageStarted(a)
T.check(count('rally_started') == 2, 'stage 1 again after a finish: a new attempt')
stats.stageEnded(a, 'finished')
T.check(count('rally_finished') == 1, 'only stage 1 in the new attempt: not finished')
fresh()
b = runOf(2, { finalTime = 200 }) stats.stageStarted(b) stats.stageEnded(b, 'finished')
a = runOf(1, { finalTime = 300 }) stats.stageStarted(a) stats.stageEnded(a, 'finished')
T.check(count('rally_finished') == 0, 'stage 2 before the attempt started: not counted')
b = runOf(2, { finalTime = 200 }) stats.stageStarted(b) stats.stageEnded(b, 'finished')
T.check(count('rally_finished') == 1, 'stage 1 then 2 in the attempt: finished')
-- a rally run in two loops (the itinerary's running order, A B A B): one start and one finish, out of four passes
fresh()
local loop = { 's1', 's2', 's1', 's2' }
for _, sid in ipairs(loop) do
  local x = runOf(sid == 's1' and 1 or 2, { finalTime = 100, rallyOrder = loop })
  stats.stageStarted(x) stats.stageEnded(x, 'finished')
end
T.check(count('rally_started') == 1 and count('rally_finished') == 1, 'two loops: one rally')
local fin = nil
for _, e in ipairs(stats._queue()) do if e.event == 'rally_finished' then fin = e end end
T.check(fin.stages_total == 4 and fin.stages_done == 4, 'counted in passes')
T.check(stats._session() ~= session, 'a new session: a new number')

-- sending: nothing with no companion; with one, a batch goes and the queue empties once it is taken
stats._reset() files = {} stats.init('x') stats.answer(true)
sent, pending = {}, {}
connected = false
stats.flushSoon() frames(1)
T.check(#stats._queue() > 0 and #sent == 0, 'no companion: kept')
connected = true
stats.update(stats.WAIT_S + 1)
T.check(#sent == 1 and stats._job() ~= nil, 'sent to the companion')
T.check(sent[1][1].session == stats._session(), 'the batch carries the events')
for _, e in ipairs(sent[1]) do T.check(e.event ~= 'install_seen', 'install_seen never in a message with session events') end
stats.record('error', { code = 'two' })
reply({ ok = true })
local q2 = stats._queue()
T.check(#q2 == 2 and q2[1].event == 'install_seen' and q2[2].code == 'two', 'taken off by identity: the one queued meanwhile kept')
T.check(stats.uiState().last ~= nil, 'the last message kept for the page')
frames(1)
T.check(#sent[2] == 1 and sent[2][1].event == 'install_seen', 'install_seen sent in a message of its own')
reply({ ok = true })
frames(1)
T.check(#sent[3] == 1 and sent[3][1].code == 'two', 'then the session events, without it')
reply({ ok = true })
T.check(#stats._queue() == 0, 'and sent next')

-- a failed answer keeps the events and waits; a refused batch is dropped
stats.record('error', { code = 'three' })
stats.flushSoon() frames(1) reply({ ok = false, status = 500 })
T.check(#stats._queue() == 1, '500: kept for later')
stats.flushSoon() frames(1)
T.check(#pending == 0, 'and not sent again at once')
stats.update(stats.RETRY_S + 1) reply({ ok = false, status = 400 })
T.check(#stats._queue() == 0, '400: dropped, not retried for ever')
T.check(stats.uiState().last:find('refused', 1, true) ~= nil, '400: what left still goes in the local copy, marked')

-- No while a send is under way: its answer is ignored and nothing is written as sent
stats.update(stats.RETRY_S + 1)
stats.record('error', { code = 'late' })
local last = stats.uiState().last
stats.flushSoon() frames(1)
T.check(stats._job() ~= nil, 'under way')
stats.answer(false)
T.check(stats._job() == nil, 'No: the send dropped')
reply({ ok = true })
T.check(#stats._queue() == 0 and stats.uiState().last == last, 'No: nothing more sent or queued')

-- No then Yes: the session's start recorded again (No threw it away)
stats._reset() files = {} stats.init('x') stats.answer(true) stats.answer(false) stats.answer(true)
T.check(#stats._queue() == 2 and stats._queue()[1].event == 'session_start' and stats._queue()[2].event == 'install_seen',
  'No then Yes: session_start and install_seen again')

-- the leaderboard off: nothing recorded
stats.answer(true)
active = false
T.check(stats.record('session_start') == false, 'leaderboard off: nothing recorded')
active = true

-- errors: text cleaned, numbers out of the code, each code a few times only, the log watched
stats._reset() files = {} stats.init('x') stats.answer(true)
local n0 = #stats._queue()
for _ = 1, 5 do stats.error('bad thing 12', 'main', [[C:\Users\Someone\x.lua:3: boom]]) end
local errs = {}
for _, e in ipairs(stats._queue()) do if e.event == 'error' then errs[#errs + 1] = e end end
T.check(#errs == stats.ERROR_REPEAT, 'one code: at most ERROR_REPEAT times')
T.check(errs[1].code == 'bad thing #', 'numbers out of the code')
T.check(errs[1].message and not errs[1].message:find('Someone', 1, true), 'the user name cleaned out: ' .. tostring(errs[1].message))
local logged = {}
log = function(l, tag, m) logged[#logged + 1] = m end
stats.watchLog()
log('E', 'earthRally', 'rally prep: oops')
log('W', 'earthRally', 'just a warning')
log('E', 'other', 'not ours')
T.check(#logged == 3, 'the game still logs everything')
local last2 = stats._queue()[#stats._queue()]
T.check(last2.event == 'error' and last2.code == 'rally prep' and last2.module == 'earthRally', "Earth Rally's errors recorded")
local count2 = #stats._queue()
stats.unwatchLog()
log('E', 'earthRally', 'after: not recorded')
T.check(#stats._queue() == count2, 'unwatched: the log given back')

-- terms (the owner, 2026-11-19): a Yes under older terms is asked again; a No stays; a Yes under the current terms kept
stats._reset() files = {}
files[stats.STATE_FILE] = T.jsonEncode({ consent = 'yes' })
files[stats.QUEUE_FILE] = T.jsonEncode({ events = { { event = 'stage_started' } } })
stats.init('x')
T.check(stats.consent() == 'ask', 'an old Yes (no terms): asked again')
T.check(T.jsonDecode(files[stats.STATE_FILE]).consent == 'ask', 'an old Yes: ask saved')
T.check(#stats._queue() == 0 and #T.jsonDecode(files[stats.QUEUE_FILE]).events == 0, 'an old Yes: its waiting events dropped')
local sentBefore = #sent
stats.sessionStart()
local re = runOf(1, { finalTime = 100 }) stats.stageStarted(re) stats.stageEnded(re, 'finished')
log('E', 'earthRally', 're-asking: not recorded')
frames(30)
T.check(#stats._queue() == 0 and #sent == sentBefore, 're-asking: nothing queued or sent')
T.check(stats._install() == nil and not files[stats.STATE_FILE]:find('install', 1, true), 're-asking: no install number')
stats.answer(true)
local saved = T.jsonDecode(files[stats.STATE_FILE])
T.check(saved.consent == 'yes' and saved.terms == stats.TERMS and stats._install() ~= nil, 'Yes again: the current terms saved')
stats._reset() stats.init('x')
T.check(stats.consent() == 'yes', 'a Yes under the current terms: kept')
files[stats.STATE_FILE] = T.jsonEncode({ consent = 'yes', terms = 1 })
stats._reset() stats.init('x')
T.check(stats.consent() == 'ask', 'a Yes under terms 1: asked again')
files[stats.STATE_FILE] = T.jsonEncode({ consent = 'no' })
stats._reset() stats.init('x')
T.check(stats.consent() == 'no', 'an old No: stays No')
stats.answer(false)
T.check(T.jsonDecode(files[stats.STATE_FILE]).terms == stats.TERMS, 'No: the current terms saved')

T.done('test_stats')
