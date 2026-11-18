-- online.lua: the online board's client, against a fake companion socket (no game, no network).
local T = dofile(TESTS .. '/testlib.lua')
local O = require('earthRally/online')
O._jsonEncode, O._jsonDecode = T.jsonEncode, T.jsonDecode

------------------------------------------------------------------------------------------ pure parts
local d = O.stageDesc('Test Rally', 'Alpha', { 60.1, 25.2 }, { 60.2, 25.3 }, 10012.4)
T.check(d and d.name == 'Alpha' and d.rally == 'Test Rally' and d.start[1] == 60.1 and d.finish[2] == 25.3 and
  d.lengthM == 10012, 'a stage described')
T.check(O.stageDesc('R', 'S', nil, { 1, 2 }, 100) == nil, 'no line: no description')
T.check(O.descKey(d, 'stock') ~= O.descKey(d, 'open'), 'a key per board')

local official = { model = { Source = 'BeamNG - Official', Brand = 'Ibishu', Name = 'Covet' },
  configs = { Source = 'BeamNG - Official', Name = 'Covet Rally' } }
T.check(O.boardFor(official) == 'stock', "the game's own car as it comes: stock")
T.check(O.boardFor({ model = official.model, configs = { Source = 'Custom' } }) == 'open', 'a saved tune: open')
T.check(O.boardFor({ model = { Source = 'Mod' }, configs = { Source = 'Mod' } }) == 'open', 'a mod car: open')
T.check(O.boardFor(nil) == 'open', 'no details: open')
T.check(O.carName(official) == 'Ibishu Covet Rally', 'the car named as rallyRun names it')

local tr = {}
T.check(O.addPoint(tr, 0, 60, 25) and not O.addPoint(tr, 0.2, 60.0001, 25) and O.addPoint(tr, 0.5, 60.0002, 25),
  'a point every half second')
T.check(O.addPoint(tr, 0.7, 60.0003, 25, true) and #tr == 3 and tr[3][1] == 700, 'the finish always')
T.check(O.addPoint(tr, 0.7, 60.0004, 25, true) and #tr == 3 and tr[3][2] == 60.0004, 'the same time: replaced')

------------------------------------------------------------------------------------------ a fake companion
-- The socket hands each request line to `serve`, which returns the answer; answers arrive on the next receive.
local sent, inbox, refused = {}, {}, false
local function serve(req)
  if req.op == 'hello' then return { ok = true, version = 't', server = 'https://board', player = { name = 'Ann' }, queued = 0 } end
  if req.op == 'start' then return { ok = true, token = 'tok1', stageId = 's1' } end
  if req.op == 'submit' then return { ok = true, status = 'ok', pos = 2, of = 5, best = req.run.timeMs } end
  if req.op == 'board' then return { ok = true, of = 1, rows = { { pos = 1, name = 'Ann', timeMs = 300000 } } } end
  if req.op == 'register' then return { ok = true, player = { name = req.name } } end
  return { ok = false, error = 'unknown' }
end
local hold = {}         -- op -> true: its answer is held back until released
local held = {}
local fakeSock = {}
function fakeSock.settimeout() end
function fakeSock.setoption() end
function fakeSock:connect() if refused then return nil, 'connection refused' end return nil, 'timeout' end
function fakeSock:getpeername() return '127.0.0.1' end
function fakeSock:close() end
function fakeSock:send(data)
  for line in data:gmatch('([^\n]*)\n') do
    local req = T.jsonDecode(line)
    sent[#sent + 1] = req
    local a = serve(req)
    a.id = req.id
    if hold[req.op] then held[#held + 1] = a else inbox[#inbox + 1] = T.jsonEncode(a) .. '\n' end
  end
  return #data
end
function fakeSock:receive()
  if #inbox == 0 then return nil, 'timeout', '' end
  -- (at most 40 bytes a call: a line split across receives is put back together)
  local s = table.concat(inbox)
  inbox = {}
  if #s > 40 then inbox[1] = s:sub(41) end
  return nil, 'timeout', s:sub(1, 40)
end
O._socket = { tcp = function() return fakeSock end }

local function frames(n) for _ = 1, n or 3 do O.update(0.1) end end
local function drain() for _ = 1, 400 do O.update(0) if #inbox == 0 then break end end O.update(0) end

------------------------------------------------------------------------------------------ off by default
O._reset()
frames(100)
T.check(#sent == 0 and O.status().on == false, 'off: nothing connects or is sent')
T.check(O.runStart(d) == nil, 'off: no run handle')
local r0
O.request('board', {}, function(r) r0 = r end)
T.check(r0 and r0.ok == false and r0.offline, 'off: a request is answered at once, offline')

------------------------------------------------------------------------------------------ on
O.enable(true)
frames(4)
local st = O.status()
T.check(st.on and st.connected and st.player.name == 'Ann' and st.server == 'https://board', 'on: connected, hello heard')

-- a board: asked once, then cached
local b = O.board(d, 'stock')
T.check(b.asking and not b.data, 'a board asked for')
drain()
b = O.board(d, 'stock')
T.check(b.data and b.data.rows[1].name == 'Ann' and not b.asking, 'a board heard')
local asks = 0
for _, q in ipairs(sent) do if q.op == 'board' then asks = asks + 1 end end
T.check(asks == 1, 'a fresh board is not asked for again')
frames(400)    -- (40 s)
O.board(d, 'stock')
asks = 0
for _, q in ipairs(sent) do if q.op == 'board' then asks = asks + 1 end end
T.check(asks == 2, 'an old one is')

-- a run: token, trace, submission
local h = O.runStart(d)
T.check(h ~= nil, 'a run handle')
drain()
for i = 0, 20 do O.runSample(h, i * 0.25, 60.1 + i * 0.0001, 25.2) end
O.runFinish(h, { timeS = 15.0, penaltyS = 10, driveS = 5.1, car = 'Ibishu Covet', board = 'stock', lat = 60.2, lon = 25.3 })
drain()
local sub
for _, q in ipairs(sent) do if q.op == 'submit' then sub = q.run end end
T.check(sub and sub.token == 'tok1' and sub.board == 'stock' and sub.timeMs == 15000 and sub.penaltyMs == 10000 and
  sub.car == 'Ibishu Covet', 'the run sent with its token')
T.check(sub and #sub.trace == 12 and sub.trace[1][1] == 0 and sub.trace[#sub.trace][1] == 5100 and
  sub.trace[#sub.trace][2] == 60.2, 'the trace: every half second, and the finish')
T.check(O.lastResult and O.lastResult.ok and O.lastResult.pos == 2 and O.lastResult.board == 'stock', 'the answer kept')

-- a run that finishes before its token arrives is sent when it does
hold.start = true
local before = #sent
local h2 = O.runStart(d)
drain()
O.runFinish(h2, { timeS = 20, penaltyS = 0, driveS = 20, board = 'open', lat = 60.2, lon = 25.3 })
drain()
local n = 0
for i = before + 1, #sent do if sent[i].op == 'submit' then n = n + 1 end end
T.check(n == 0, 'not sent before its token')
for _, a in ipairs(held) do inbox[#inbox + 1] = T.jsonEncode(a) .. '\n' end
held, hold.start = {}, nil
drain()
for i = before + 1, #sent do if sent[i].op == 'submit' then n = n + 1 end end
T.check(n == 1 and O.lastResult.board == 'open', 'sent once the token is here')

-- naming
local named
O.register('Annie', function(r) named = r end)
drain()
T.check(named and named.ok and O.status().player.name == 'Annie', 'a new name')

------------------------------------------------------------------------------------------ no companion
O._reset()
refused = true
O.enable(true)
frames(60)
st = O.status()
T.check(st.on and not st.connected and st.error and st.error:find('not running'), 'no companion: said why')
T.check(O.board(d, 'stock').error ~= nil, 'no companion: the board says why')
local h3 = O.runStart(d)
O.runFinish(h3, { timeS = 20, penaltyS = 0, driveS = 20, board = 'stock', lat = 60.2, lon = 25.3 })
T.check(O.lastResult and O.lastResult.ok == false and O.lastResult.error:find('not sent'), 'no companion: the run is not sent, and says so')
O.enable(false)
T.check(O.status().on == false, 'off again')

T.done('test_online')
