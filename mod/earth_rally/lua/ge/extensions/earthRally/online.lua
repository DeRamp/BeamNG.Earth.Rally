-- earthRally/online: the online leaderboard (docs/research-online-leaderboards.md). Players' own times only; a rally
-- pack's real results are the offline leaderboard (boards.lua) and never leave this computer.
--
-- The game's Lua cannot reach the internet: its sockets reach only this computer and the LAN, with no HTTPS. So this
-- talks to the companion (online/companion/earth_rally_online.py, run beside the game by BeamNG.Earth's add-ons page)
-- on 127.0.0.1:PORT, one JSON object per line each way, and the companion talks to the board's server. Non-blocking
-- (luasocket, timeout 0): nothing here holds up a frame. Off until the player turns the online board on (settings
-- `onlineBoard`): nothing connects or is sent before that.
--
-- What a run sends (runStart / runSample / runReset / runFinish): the stage described by where it is (name, rally,
-- start and flying finish, length: the server finds the same road for players whose lines differ by a few metres),
-- the car, the time and its penalties, the car's position twice a second, when it was reset or recovered, and how far
-- the game's clock fell behind real time (slow motion) -- the server's checks, and later ghosts.
local M = {}

M.HOST, M.PORT = '127.0.0.1', 47820
M.RECONNECT_S = 5
M.CONNECT_TIMEOUT_S = 2
M.REQUEST_TIMEOUT_S = 20
M.BOARD_FRESH_S = 10          -- a board is asked for again after this long (and on every new look: #73)
M.HELLO_EVERY_S = 10          -- the companion's state (its queue) asked for again this often
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
local clock = 0
local helloAt = 0
local unsent = {}             -- finished runs the companion was not there to take: sent when it is back
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

-- (a stage's key here: its ends to about 10 m and its length to the metre; with the board, a board's cache key)
function M.stageKey(desc)
  return string.format('%.4f,%.4f,%.4f,%.4f,%d', desc.start[1], desc.start[2], desc.finish[1], desc.finish[2],
    desc.lengthM)
end
function M.descKey(desc, board) return M.stageKey(desc) .. ',' .. tostring(board) end

-- The car's class (the owner, 2026-11-18, #75): 'stock' when it is one of the game's own presets, untouched; 'open'
-- for any other car. Returns the class and why, for the log. details: core_vehicles.getCurrentVehicleDetails().
--   A preset: the car's configuration is a .pc file (parts changed in the garage and not saved make it a table, not a
--   file: open). The game's own: the game labels the model and the configuration 'BeamNG - Official' (else 'Custom'
--   for the player's saved configurations, or a mod's name). The labels come from where each file was loaded, by
--   comparing paths as they are written; when they do not say official, the configuration file's own place is
--   checked again here with the paths' case and slashes evened out (originOf(path) -> the file's mount or archive
--   path; FS:getFileOriginInfo in the game), so a preset loaded from the game's own content is stock either way.
M.OFFICIAL = 'BeamNG - Official'
local function normPath(p) return (tostring(p or ''):gsub('\\', '/'):gsub('/+', '/'):lower()) end
function M.gameOrigin(path, originOf, gamePath)
  local fs = rawget(_G, 'FS')
  originOf = originOf or (fs and function(q)
    local ok, o = pcall(function() return fs:getFileOriginInfo(q) end)
    return ok and type(o) == 'table' and (o.mountPath or o.archivePath) or nil
  end)
  if not gamePath and fs then
    local ok, g = pcall(function() return fs:getGamePath() end)
    gamePath = ok and type(g) == 'string' and g or nil
  end
  if not (originOf and gamePath and gamePath ~= '') then return false end
  local o = originOf(path)
  if not o then return false end
  local g = normPath(gamePath)
  if g:sub(-1) ~= '/' then g = g .. '/' end
  return normPath(o):sub(1, #g) == g
end
function M.boardFor(details, originOf, gamePath)
  if type(details) ~= 'table' then return 'open', 'no car' end
  local model = type(details.model) == 'table' and details.model or {}
  local cfg = type(details.configs) == 'table' and details.configs or {}
  local cur = type(details.current) == 'table' and details.current or {}
  local pc = cur.pc_file
  if type(pc) ~= 'string' or not pc:lower():match('%.pc$') then return 'open', 'not a saved preset' end
  -- (the player's own default car, settings/default.pc: the game gives it the model's labels, but it is theirs)
  if details.userDefault or pc:lower():find('settings/', 1, true) then return 'open', "the player's default car: " .. pc end
  local labels = 'model ' .. tostring(model.Source) .. ', config ' .. tostring(cfg.Source) .. ', ' .. pc
  if model.Source == M.OFFICIAL and cfg.Source == M.OFFICIAL then return 'stock', labels end
  -- (a configuration from a mod or the player's own is never the game's: only a missing or official model label,
  -- and a config labelled official or not at all, are checked by the file's place)
  local okModel = model.Source == nil or model.Source == M.OFFICIAL
  local okCfg = cfg.Source == nil or cfg.Source == M.OFFICIAL or cfg.Source == model.Source
  if okModel and okCfg and M.gameOrigin(pc, originOf, gamePath) then return 'stock', labels .. " (from the game's files)" end
  return 'open', labels
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

local function askHello()
  helloAt = clock
  M.request('hello', {}, function(r) if r and r.ok then hello = r end end)
end

local function onConnected()
  state = 'connected'
  M.lastError = nil
  pcall(sock.setoption, sock, 'tcp-nodelay', true)
  askHello()
  local again = unsent
  unsent = {}
  for _, x in ipairs(again) do M._submit(x.run, x.key, true) end
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
  if state == 'connected' and clock - helloAt >= M.HELLO_EVERY_S then askHello() end
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
  -- (asked while an answer is on its way: asked again once it is here, so a new look never shows an older list)
  if force and b.asking then b.again = true end
  if not b.asking and (force or not b.at or clock - b.at > M.BOARD_FRESH_S) and state == 'connected' and hello then
    b.asking, b.again = true, false
    M.request('board', { stage = desc, board = board, top = 10, n = 2 }, function(r)
      b.asking, b.at = false, clock
      if r.ok then b.data, b.error = r, nil else b.error = r.error end
      if b.again then b.at = nil end
    end)
  end
  return { data = b.data, error = b.error or ((not b.data and not b.asking) and M.status().error) or nil,
    asking = b.asking or nil }
end

-- (the boards asked for again on the next look: a run was sent, or the menu opened. What was shown stays until the
-- new answer is in, so the list does not blink out)
function M.forgetBoards() for _, b in pairs(boards) do b.at = nil end end

-- Stats (#76): the player's events, to the companion, which passes them to the stats server. false when the
-- companion is not connected (nothing asked); else cb(answer) once.
function M.sendStats(events, cb)
  if state ~= 'connected' or not hello then return false end
  return M.request('stats', { events = events }, cb)
end

------------------------------------------------------------------------------------------ runs

-- A run begins: a token asked for (the server's clock from here to the submission must be at least the stage
-- time, so it is asked for at the run's start, well before GO: a slow answer then costs nothing). Returns a handle
-- for runSample / runReset / runFinish, or nil when the online board is off or the stage has no line.
function M.runStart(desc)
  if not (enabled and desc) then return nil end
  local h = { desc = desc, trace = {}, resets = {}, slowS = 0, asking = true }
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

-- The car was reset or recovered at stage time `at` (s): its jump in the trace is that, not a teleport.
function M.runReset(h, at)
  if h and not h.finish and type(at) == 'number' and #h.resets < 500 then
    h.resets[#h.resets + 1] = math.floor(math.max(0, at) * 1000 + 0.5)
  end
end

-- A frame of the timed stage: the game's clock behind real time (slow motion; a paused game, dtSim 0, is not).
function M.runFrame(h, dtReal, dtSim)
  if h and not h.finish and (dtSim or 0) > 0 and (dtReal or 0) > 0 and dtSim < dtReal * 0.9 then
    h.slowS = h.slowS + (dtReal - dtSim)
  end
end

-- The run is over: { timeS, penaltyS, driveS, car, board, lat, lon (the finish) }. Sent when its token is here.
function M.runFinish(h, fin)
  if not h or h.finish then return end
  M.addPoint(h.trace, fin.driveS, fin.lat, fin.lon, true)
  h.finish = fin
  if not h.asking then M._send(h) end
end

function M._send(h)
  local key = M.stageKey(h.desc)
  if not h.token then
    M.lastResult = { ok = false, error = 'not sent: ' .. tostring(h.error or 'no run token'), stageKey = key }
    return
  end
  local f = h.finish
  local run = { token = h.token, board = f.board == 'stock' and 'stock' or 'open', car = f.car,
    timeMs = math.floor(f.timeS * 1000 + 0.5), penaltyMs = math.floor((f.penaltyS or 0) * 1000 + 0.5),
    trace = h.trace, resets = h.resets, slowMs = math.floor(h.slowS * 1000 + 0.5), modVersion = M.VERSION }
  M._submit(run, key)
end

-- (a run whose token is valid for a day: the companion gone for a moment -- restarted mid-stage -- keeps it here
-- until it is back)
function M._submit(run, key, resent)
  M.request('submit', { run = run }, function(r)
    -- (sent again: the first went through after all, only its answer was lost)
    if resent and not r.ok and r.status == 409 then r = { ok = true, status = 'ok', error = nil, resentTaken = true } end
    if r.offline and not r.queued and #unsent < 20 then
      unsent[#unsent + 1] = { run = run, key = key }
      r = { ok = false, queued = true, error = r.error }
    end
    M.lastResult = r
    r.board, r.stageKey = run.board, key
    M.forgetBoards()
    if not r.ok and not r.queued then logW('run not taken: ' .. tostring(r.error)) end
  end)
end

-- (tests: everything back to the start)
function M._reset()
  if sock then pcall(sock.close, sock) end
  sock, state, timer, enabled, inbuf, outbuf = nil, 'off', 0, false, '', ''
  pending, hello, boards, clock, nextId, helloAt, unsent = {}, nil, {}, 0, 0, 0, {}
  M.lastError, M.lastResult = nil, nil
end

return M
