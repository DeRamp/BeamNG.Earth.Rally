-- earthRally/online: the online leaderboard (docs/research-online-leaderboards.md). Players' own times only; a rally
-- pack's real results are the offline leaderboard (boards.lua) and never leave this computer.
--
-- The game's Lua cannot reach the internet: its sockets reach only this computer and the LAN, with no HTTPS. So this
-- talks to the companion (online/companion/earth_rally_online.py, run beside the game by BeamNG.Earth's add-ons page)
-- on 127.0.0.1:PORT, one JSON object per line each way, and the companion talks to the board's server. Non-blocking
-- (luasocket, timeout 0): nothing here holds up a frame. Off until the player turns the online board on (settings
-- `onlineBoard`): nothing connects or is sent before that.
--
-- What a run sends (runStart / runSample / runFinish): the stage described by where it is (name, rally, start and
-- flying finish, length: the server finds the same road for players whose lines differ by a few metres), the car,
-- the time and its penalties, and the car's position twice a second (the server's checks, and later ghosts).
local M = {}

M.HOST, M.PORT = '127.0.0.1', 47820
M.RECONNECT_S = 5
M.CONNECT_TIMEOUT_S = 2
M.REQUEST_TIMEOUT_S = 20
M.BOARD_FRESH_S = 30          -- a board is asked for again after this long
M.TRACE_STEP_S = 0.5          -- a trace point every this much stage time
M.TRACE_MAX = 19000           -- (the server takes 20000)
M.VERSION = nil               -- the mod's version, sent with each run (main.lua sets it)

local socket = nil
local sock, state, timer = nil, 'off', 0     -- 'off' | 'disconnected' | 'connecting' | 'connected'
local enabled = false
local inbuf, outbuf = '', ''
local nextId = 0
local pending = {}            -- id -> { cb, op, age }
local hello = nil             -- the companion's hello answer
local boards = {}             -- key -> { at, data, error, asking }
local runs = {}               -- handle -> { token | nil, asking, finished payload, result }
local clock = 0
M.lastError = nil
M.lastResult = nil            -- the last run's answer: { ok, status, pos, of, best, error, queued, stage, board }

local function enc(v) return (rawget(_G, 'jsonEncode') or M._jsonEncode)(v) end
local function dec(s)
  local f = rawget(_G, 'jsonDecode') or M._jsonDecode
  local ok, v = pcall(f, s)
  return ok and v or nil
end
local function logW(msg) local lg = rawget(_G, 'log') if lg then lg('W', 'earthRally', 'online: ' .. msg) end end

------------------------------------------------------------------------------------------ pure parts

-- A stage as the server knows it. lineStart / lineFinish: { lat, lon } where the timing starts and the flying finish
-- is on the line the stage is timed on (events.timedSpan, runner's run.lineStart), lengthM between them.
function M.stageDesc(eventName, stageName, lineStart, lineFinish, lengthM)
  if type(lineStart) ~= 'table' or type(lineFinish) ~= 'table' or type(lengthM) ~= 'number' then return nil end
  if type(lineStart[1]) ~= 'number' or type(lineFinish[1]) ~= 'number' then return nil end
  return { name = tostring(stageName or 'Stage'), rally = eventName and tostring(eventName) or nil,
    start = { lineStart[1], lineStart[2] }, finish = { lineFinish[1], lineFinish[2] },
    lengthM = math.floor(lengthM + 0.5) }
end

-- (a board's cache key: the stage to about 10 m, its length to the metre, and the board)
function M.descKey(desc, board)
  return string.format('%.4f,%.4f,%.4f,%.4f,%d,%s', desc.start[1], desc.start[2], desc.finish[1], desc.finish[2],
    desc.lengthM, tostring(board))
end

-- 'stock' when the car is one of the game's own as it comes (its model and its configuration both the game's
-- official ones), else 'open'. details: core_vehicles.getCurrentVehicleDetails(). A car tuned in the garage and
-- saved is a custom configuration, so it is open. (The game's labels: Source = 'BeamNG - Official' | 'Custom' |
-- 'Mod'; unconfirmed on 0.40.5 until checked in game.)
M.OFFICIAL = 'BeamNG - Official'
function M.boardFor(details)
  if type(details) ~= 'table' then return 'open' end
  local model = type(details.model) == 'table' and details.model or {}
  local cfg = type(details.configs) == 'table' and details.configs or {}
  if model.Source == M.OFFICIAL and cfg.Source == M.OFFICIAL then return 'stock' end
  return 'open'
end

-- The car's name for a board row (as rallyRun.car names it).
function M.carName(details)
  if type(details) ~= 'table' then return nil end
  local cfg = type(details.configs) == 'table' and details.configs or {}
  local model = type(details.model) == 'table' and details.model or {}
  local brand, nm = cfg.Brand or model.Brand, cfg.Name or model.Name
  if not nm then return nil end
  nm = tostring(nm)
  if brand and not nm:find(tostring(brand), 1, true) then nm = tostring(brand) .. ' ' .. nm end
  return nm
end

-- A trace point added when STEP has passed since the last (trace: { {ms, lat, lon}... }); at = stage seconds.
-- force: always (the finish). Returns true when added.
function M.addPoint(trace, at, lat, lon, force)
  if type(lat) ~= 'number' or type(lon) ~= 'number' or type(at) ~= 'number' then return false end
  local ms = math.floor(math.max(0, at) * 1000 + 0.5)
  local last = trace[#trace]
  if last and not force and ms - last[1] < M.TRACE_STEP_S * 1000 then return false end
  if #trace >= M.TRACE_MAX and not force then return false end
  local p = { ms, math.floor(lat * 1e6 + 0.5) / 1e6, math.floor(lon * 1e6 + 0.5) / 1e6 }
  if last and last[1] >= ms then trace[#trace] = { last[1], p[2], p[3] } return true end
  trace[#trace + 1] = p
  return true
end

------------------------------------------------------------------------------------------ the connection

local function closeSock(err)
  if sock then pcall(sock.close, sock) end
  sock, inbuf, outbuf = nil, '', ''
  local was = state
  state, timer = enabled and 'disconnected' or 'off', 0
  hello = nil
  if err then M.lastError = err end
  -- (every request waiting is answered: the companion is gone)
  local waiting = pending
  pending = {}
  for _, p in pairs(waiting) do pcall(p.cb, { ok = false, error = 'the companion stopped', offline = true }) end
  return was
end

local function onConnected()
  state = 'connected'
  M.lastError = nil
  pcall(sock.setoption, sock, 'tcp-nodelay', true)
  M.request('hello', {}, function(r) if r and r.ok then hello = r end end)
end

local function startConnect()
  socket = socket or M._socket or require('socket')
  sock = socket.tcp()
  sock:settimeout(0)
  local ok, err = sock:connect(M.HOST, M.PORT)
  if ok then onConnected()
  elseif err == 'timeout' or err == 'Operation already in progress' then state, timer = 'connecting', 0
  else closeSock('the companion is not running (' .. tostring(err) .. ')') end
end

local function flush()
  if outbuf == '' or not sock then return end
  local last, err, partial = sock:send(outbuf)
  local sent = last or partial or 0
  if sent > 0 then outbuf = outbuf:sub(sent + 1) end
  if not last and err ~= 'timeout' then closeSock('send: ' .. tostring(err)) end
end

local function receive()
  for _ = 1, 64 do
    local data, err, part = sock:receive(65536)
    local got = data or part
    if got and #got > 0 then inbuf = inbuf .. got end
    if err and err ~= 'timeout' then closeSock('the companion stopped (' .. tostring(err) .. ')') return end
    if not data then break end
  end
  while true do
    local nl = inbuf:find('\n', 1, true)
    if not nl then break end
    local line = inbuf:sub(1, nl - 1)
    inbuf = inbuf:sub(nl + 1)
    local msg = dec(line)
    if type(msg) == 'table' and msg.id ~= nil then
      local p = pending[msg.id]
      pending[msg.id] = nil
      if p then
        local ok, e = pcall(p.cb, msg)
        if not ok then logW(p.op .. ': ' .. tostring(e)) end
      end
    end
  end
end

-- Ask the companion: op and its fields; cb(answer) once, always (an answer, or { ok = false, error, offline }).
function M.request(op, fields, cb)
  cb = cb or function() end
  if state ~= 'connected' then
    cb({ ok = false, error = M.lastError or 'the companion is not running', offline = true })
    return false
  end
  nextId = nextId + 1
  local msg = {}
  for k, v in pairs(fields or {}) do msg[k] = v end
  msg.id, msg.op = nextId, op
  pending[nextId] = { cb = cb, op = op, age = 0 }
  outbuf = outbuf .. enc(msg) .. '\n'
  flush()
  return true
end

-- Each frame (main.lua onUpdate).
function M.update(dt)
  dt = dt or 0
  clock = clock + dt
  if not enabled then
    if sock then closeSock() end
    state = 'off'
    return
  end
  if state == 'off' then state, timer = 'disconnected', M.RECONNECT_S end
  if state == 'disconnected' then
    timer = timer + dt
    if timer >= M.RECONNECT_S then timer = 0 startConnect() end
    return
  end
  if state == 'connecting' then
    if sock:getpeername() then onConnected()
    else
      timer = timer + dt
      if timer >= M.CONNECT_TIMEOUT_S then closeSock('the companion is not running') end
      return
    end
  end
  flush()
  if state == 'connected' then receive() end
  for id, p in pairs(pending) do
    p.age = p.age + dt
    if p.age > M.REQUEST_TIMEOUT_S then
      pending[id] = nil
      pcall(p.cb, { ok = false, error = 'no answer from the companion' })
    end
  end
end

function M.enable(on)
  enabled = on == true
  if enabled and state == 'off' then state, timer = 'disconnected', M.RECONNECT_S end
  if not enabled then closeSock() state = 'off' end
end
function M.enabled() return enabled end

-- For the page: { on, connected, player = { name } | nil, server, queued, error }.
function M.status()
  return { on = enabled, connected = state == 'connected' and hello ~= nil, state = state,
    player = hello and hello.player or nil, server = hello and hello.server or nil, queued = hello and hello.queued or 0,
    error = (state ~= 'connected' and enabled) and M.lastError or nil }
end

-- A name for the board (the first time: a new player; after: a new name). cb(answer).
function M.register(name, cb)
  return M.request('register', { name = name }, function(r)
    if r.ok and hello then hello.player = r.player end
    if cb then cb(r) end
  end)
end

------------------------------------------------------------------------------------------ boards

-- A stage's online board, as last heard: { data = the server's answer | nil, error, asking }; asks again when it is
-- older than BOARD_FRESH_S (or force). desc: M.stageDesc; board: 'stock' | 'open'.
function M.board(desc, board, force)
  if not desc then return { error = 'this stage has no line yet' } end
  local key = M.descKey(desc, board)
  local b = boards[key]
  if not b then b = {} boards[key] = b end
  if not b.asking and (force or not b.at or clock - b.at > M.BOARD_FRESH_S) and state == 'connected' and hello then
    b.asking = true
    M.request('board', { stage = desc, board = board, top = 10, n = 2 }, function(r)
      b.asking, b.at = false, clock
      if r.ok then b.data, b.error = r, nil else b.error = r.error end
    end)
  end
  return { data = b.data, error = b.error or ((not b.data and not b.asking) and M.status().error) or nil,
    asking = b.asking or nil }
end

-- (the boards asked for again on the next look: a run was sent)
function M.forgetBoards() boards = {} end

------------------------------------------------------------------------------------------ runs

-- A run's clock started: a token asked for (the server's clock from here to the submission is one of its checks).
-- Returns a handle for runFinish, or nil when the online board is off or the stage has no line.
function M.runStart(desc)
  if not (enabled and desc) then return nil end
  local h = { desc = desc, trace = {}, asking = true }
  runs[h] = true
  M.request('start', { stage = desc }, function(r)
    h.asking = false
    if r.ok then h.token = r.token else h.error = r.error end
    if h.finish then M._send(h) end
  end)
  return h
end

function M.runSample(h, at, lat, lon)
  if h and not h.finish then M.addPoint(h.trace, at, lat, lon) end
end

-- The run is over: { timeS, penaltyS, driveS, car, board, lat, lon (the finish) }. Sent when its token is here.
function M.runFinish(h, fin)
  if not h or h.finish then return end
  M.addPoint(h.trace, fin.driveS, fin.lat, fin.lon, true)
  h.finish = fin
  if not h.asking then M._send(h) end
end

function M._send(h)
  runs[h] = nil
  if not h.token then
    M.lastResult = { ok = false, error = 'not sent: ' .. tostring(h.error or 'no run token') }
    return
  end
  local f = h.finish
  local run = { token = h.token, board = f.board == 'stock' and 'stock' or 'open', car = f.car,
    timeMs = math.floor(f.timeS * 1000 + 0.5), penaltyMs = math.floor((f.penaltyS or 0) * 1000 + 0.5),
    trace = h.trace, modVersion = M.VERSION }
  M.request('submit', { run = run }, function(r)
    M.lastResult = r
    r.board = run.board
    M.forgetBoards()
    if not r.ok and not r.queued then logW('run not taken: ' .. tostring(r.error)) end
  end)
end

-- (tests: everything back to the start)
function M._reset()
  if sock then pcall(sock.close, sock) end
  sock, state, timer, enabled, inbuf, outbuf = nil, 'off', 0, false, '', ''
  pending, hello, boards, runs, clock, nextId = {}, nil, {}, {}, 0, 0
  M.lastError, M.lastResult = nil, nil
end

return M
