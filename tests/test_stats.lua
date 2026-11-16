-- stats (+stats): nothing recorded before Yes, only allowed fields, pack names vs 'custom', one start and one end per
-- run, rally finished only with every stage done, delete, and the non-blocking POST against a stand-in socket.
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
local sent, answer = {}, 'HTTP/1.1 204 No Content'
package.preload['socket'] = function()
  return {
    dns = { toip = function(h) return h == 'stats.example' and '10.0.0.1' or nil end },
    select = function(_, w) return nil, w end,
    tcp = function()
      local c, sends, reads = {}, 0, 0
      function c:settimeout() end
      function c:connect() return nil, 'timeout' end
      function c:send(s, i)
        sends = sends + 1
        if sends == 1 then sent[#sent + 1] = s:sub(i, i + 9) return nil, 'timeout', i + 9 end
        sent[#sent] = sent[#sent] .. s:sub(i) return #s
      end
      function c:receive(_, prefix)
        reads = reads + 1
        if reads == 1 then return nil, 'timeout', answer:sub(1, 6) end
        return (prefix or '') .. answer:sub(7)
      end
      function c:close() end
      return c
    end,
  }
end

local stats = require('earthRally/stats')
stats.init('1.6.2-alpha+stats')

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
local install = stats._state().install
T.check(type(install) == 'string' and #install == 32 and install:match('^%x+$'), 'a 32-hex install number')
local q = stats._queue()
T.check(#q == 1 and q[1].event == 'session_start', 'Yes: session_start queued')
T.check(q[1].day and q[1].day:match('^%d%d%d%d%-%d%d%-%d%d$') and q[1].mod == '1.6.2-alpha+stats', 'day and mod set')
for k in pairs(q[1]) do
  T.check(({ event = 1, install = 1, mod = 1, game = 1, earth = 1, day = 1 })[k], 'only the common fields: ' .. k)
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

-- one start and one end per run; rally started on stage 1; rally finished once every stage has a time
local n0 = #q
local run = { event = packEv, stage = packEv.stages[1], ss = 1, resets = 2, checks = { line = 'recce' } }
stats.stageStarted(run) stats.stageStarted(run)
T.check(#q == n0 + 2 and q[n0 + 1].event == 'stage_started' and q[n0 + 2].event == 'rally_started', 'start + rally start, once')
run.finalTime = 412.4
local times = { s1 = 400 }
local best = function(_, sid) return times[sid] end
stats.stageEnded(run, 'finished', best) stats.stageEnded(run, 'quit', best)
T.check(#q == n0 + 3 and q[n0 + 3].result == 'finished' and q[n0 + 3].time_s == 412 and q[n0 + 3].resets == 2, 'one end, whole seconds')
local run2 = { event = packEv, stage = packEv.stages[2], ss = 2, finalTime = 300 }
stats.stageStarted(run2)
times.s2 = 300
stats.stageEnded(run2, 'finished', best)
T.check(q[#q].event == 'rally_finished' and q[#q].stages_done == 2, 'rally finished with every stage done')
local run3 = { event = packEv, stage = packEv.stages[2], ss = 2 }
stats.stageEnded(run3, 'quit', best)
T.check(q[#q].event == 'rally_finished', 'no end without a start')

-- sending: nothing with no address; with one, a batch goes in a few frames and the queue empties
stats.flushSoon()
stats.update(0.1, true)
T.check(#stats._queue() > 0, 'no address: kept')
stats.ENDPOINT = 'http://stats.example/'
stats.flushSoon()
for _ = 1, 10 do stats.update(0.1, true) end
T.check(#stats._queue() == 0, 'sent: queue empty')
T.check(sent[1] and sent[1]:match('^POST /v1/events HTTP/1.0\r\nHost: stats.example') ~= nil, 'POST to /v1/events')
T.check(sent[1] and sent[1]:find('"install":"' .. install .. '"', 1, true) ~= nil, 'the body carries the events')
T.check(stats.uiState().last ~= nil, 'the last message kept for the page')

-- a failed answer keeps the events and waits
answer = 'HTTP/1.1 500 Oops'
stats.record('session_start')
stats.flushSoon()
for _ = 1, 10 do stats.update(0.1, true) end
T.check(#stats._queue() == 1, '500: kept for later')

-- delete: a delete for the old number, a new number, queue cleared, sent even with stats off
stats.deleteMine()
T.check(stats._state().install ~= install and #stats._state().deletes == 1 and #stats._queue() == 0, 'deleted, new number')
stats.answer(false)
answer = 'HTTP/1.1 200 OK'
stats.update(stats.RETRY_S + 1, true)
for _ = 1, 10 do stats.update(0.1, true) end
T.check(#stats._state().deletes == 0, 'delete sent even with stats off')
T.check(sent[#sent]:match('^POST /v1/delete') and sent[#sent]:find(install, 1, true), 'delete names the old number')

-- the address
local h, p, path = stats.parseUrl('http://a.b.workers.dev:8080/x')
T.check(h == 'a.b.workers.dev' and p == 8080 and path == '/x', 'url with port')
T.check(stats.parseUrl('https://a.b/') == nil, 'https refused (no TLS in the game)')

T.done('test_stats')
