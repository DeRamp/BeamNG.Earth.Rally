-- stats (+stats): nothing recorded before Yes, only allowed fields, a new random number each session (never saved),
-- pack names vs 'custom', one start and one end per run, rally attempts, and the non-blocking POST against a stand-in
-- socket: sent events taken off by identity, refused batches dropped, No cancelling a send under way, a failed name
-- lookup not tried again.
local T = dofile(TESTS .. '/testlib.lua')
function log() end
local files = {}
function jsonReadFile(p) return files[p] and T.jsonDecode(files[p]) end
function jsonWriteFile(p, t) files[p] = T.jsonEncode(t) return true end
jsonEncode = T.jsonEncode
FS = { fileExists = function(_, p) return files[p] ~= nil end }
beamng_version = '0.40.5.0'
io.open = function() return nil end      -- (sent.jsonl: not written in the test)

-- a stand-in luasocket: connect in progress for one step, a send that takes two goes, an answer line in two parts
local sent, answer, lookups, closed = {}, 'HTTP/1.1 204 No Content', 0, 0
local hold = false                       -- true: the answer never comes (a send left under way)
package.preload['socket'] = function()
  return {
    dns = { toip = function(h) lookups = lookups + 1 return h == 'stats.example' and '10.0.0.1' or nil end },
    select = function(_, w) return nil, w end,
    tcp = function()
      local c, sends, reads, conns = {}, 0, 0, 0
      function c:settimeout() end
      function c:connect()
        conns = conns + 1
        if conns == 1 then return nil, 'timeout' end
        return nil, 'already connected'
      end
      function c:send(s, i)
        sends = sends + 1
        if sends == 1 then sent[#sent + 1] = s:sub(i, i + 9) return nil, 'timeout', i + 9 end
        sent[#sent] = sent[#sent] .. s:sub(i) return #s
      end
      function c:receive(_, prefix)
        reads = reads + 1
        if hold or reads == 1 then return nil, 'timeout', answer:sub(1, 6) end
        return (prefix or '') .. answer:sub(7)
      end
      function c:close() closed = closed + 1 end
      return c
    end,
  }
end

local stats = require('earthRally/stats')
stats.init('1.6.2-alpha+stats')
local function frames(n) for _ = 1, n or 10 do stats.update(0.1, true) end end

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
T.check(not files[stats.STATE_FILE]:find('install', 1, true), 'no install number saved')
local q = stats._queue()
T.check(#q == 1 and q[1].event == 'session_start', 'Yes: session_start queued')
T.check(q[1].day and q[1].day:match('^%d%d%d%d%-%d%d%-%d%d$') and q[1].mod == '1.6.2-alpha+stats', 'day and mod set')
for k in pairs(q[1]) do
  T.check(({ event = 1, session = 1, mod = 1, game = 1, earth = 1, day = 1 })[k], 'only the common fields: ' .. k)
end
T.check(stats.record('made_up') == false, 'unknown events refused')
stats.record('error', { code = 'x', module = 'main', message = 'C:/Users/Someone/secret' })
T.check(q[#q].message == nil and q[#q].code == 'x', 'unlisted fields dropped')

-- names: a pack's rally is named, a player's own map is 'custom'
local packEv = { id = 'e1', name = 'ARA 2026', pack = { file = 'ara.zip' }, stages = { { id = 's1', name = 'SS1 A' }, { id = 's2', name = 'SS2 B' } } }
local ownEv = { id = 'e2', name = "Bob's farm", stages = { { id = 's1', name = 'Back field' } } }
local r, s = stats.names(packEv, packEv.stages[1])
T.check(r == 'ARA 2026' and s == 'SS1 A', 'pack: named')
r, s = stats.names(ownEv, ownEv.stages[1])
T.check(r == 'custom' and s == 'custom', 'own map: custom')

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
T.check(count('rally_finished') == 1, 'out of order within the attempt: finished')
T.check(stats._session() ~= session, 'a new session: a new number')

-- sending: nothing with no address; with one, a batch goes in a few frames and the queue empties
q = stats._queue()
stats.flushSoon() frames(1)
T.check(#stats._queue() > 0, 'no address: kept')
stats.ENDPOINT = 'http://stats.example/'
stats.flushSoon() frames()
T.check(#stats._queue() == 0, 'sent: queue empty')
T.check(sent[1] and sent[1]:match('^POST /v1/events HTTP/1.0\r\nHost: stats.example') ~= nil, 'POST to /v1/events')
T.check(sent[1] and sent[1]:find('"session":"' .. stats._session() .. '"', 1, true) ~= nil, 'the body carries the events')
T.check(stats.uiState().last ~= nil, 'the last message kept for the page')

-- an event queued while a send is under way is kept (sent ones are taken off by identity, not by count)
hold = true
stats.record('error', { code = 'one' })
stats.flushSoon() frames(2)
T.check(stats._job() ~= nil, 'a send under way')
stats.record('error', { code = 'two' })
local nSent = #sent
hold = false frames(3)
T.check(#stats._queue() == 1 and stats._queue()[1].code == 'two', 'the one queued meanwhile kept')
frames()
T.check(#stats._queue() == 0 and #sent == nSent + 1 and sent[#sent]:find('"code":"two"', 1, true), 'and sent next')

-- a failed answer keeps the events and waits; a refused batch is dropped
answer = 'HTTP/1.1 500 Oops'
stats.record('error', { code = 'three' })
stats.flushSoon() stats.update(stats.RETRY_S + 1, true) frames()
T.check(#stats._queue() == 1, '500: kept for later')
answer = 'HTTP/1.1 400 Bad Request'
stats.update(stats.RETRY_S + 1, true) stats.flushSoon() frames()
T.check(#stats._queue() == 0, '400: dropped, not retried for ever')

-- No while a send is under way: the send is closed and nothing is written as sent
answer = 'HTTP/1.1 204 No Content'
stats.update(stats.RETRY_S + 1, true)
stats.record('error', { code = 'late' })
hold = true
local last, closedBefore = stats.uiState().last, closed
stats.flushSoon() frames(2)
T.check(stats._job() ~= nil, 'under way')
stats.answer(false)
T.check(stats._job() == nil and closed > closedBefore, 'No: the send closed')
hold = false frames()
T.check(#stats._queue() == 0 and stats.uiState().last == last, 'No: nothing more sent or queued')

-- a failed name lookup is not tried again this session (it can stall the game)
fresh()
stats.ENDPOINT = 'http://nowhere.example/'
local before = lookups
stats.flushSoon() frames()
stats.update(stats.RETRY_S + 1, true) stats.flushSoon() frames()
T.check(lookups == before + 1, 'one lookup only')

-- the address
local h, p, path = stats.parseUrl('http://a.b.workers.dev:8080/x')
T.check(h == 'a.b.workers.dev' and p == 8080 and path == '/x', 'url with port')
T.check(stats.parseUrl('https://a.b/') == nil, 'https refused (no TLS in the game)')

T.done('test_stats')
