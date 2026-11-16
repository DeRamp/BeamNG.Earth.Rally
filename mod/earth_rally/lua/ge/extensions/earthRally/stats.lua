-- earthRally/stats: anonymous player stats, opt-in (docs/research-telemetry.md, PRIVACY.md, the mock-up in
-- docs/mockups-telemetry/telemetry.html).
--
--   Asked once, when the rally menu first opens. Nothing is recorded or sent before the answer; closing the menu
--   with the question up counts as No. Only the answer and anything waiting to go are kept, in the user folder's
--   earthRally/telemetry/; every message sent is also written word for word to SENT_FILE, so the player can read
--   exactly what left their PC.
--
--   No install number: each game session gets a new random number, kept in memory only, so two sessions of the same
--   player cannot be linked (the owner's choice, 2026-11-16: "fully anonymous"). The price: installs are not counted,
--   only sessions, and there is nothing to "delete my stats" by.
--
--   Sent over plain HTTP (the game's Lua has no TLS) to the stats Worker (server/), in batches, from a coroutine
--   stepped by update(): the game never waits on the network, except the one name lookup per session, which is
--   only done while the menu page is up (the game is paused there), and not tried again that session if it fails.
--
--   What is sent: the event, the session number, the mod, game and BeamNG.Earth versions, the day (UTC, no time),
--   and per event a few counts (EVENTS). Rallies and stages from a pack are named; a player's own imported maps are
--   sent as 'custom' (a name could be a private place). Never: names, accounts, hardware, other mods, positions,
--   free text, logs. The IP address travels with every request (it must, to reach the server) but is not stored.
local M = {}

-- The stats Worker's address (server/README.md). Empty: stats are asked about and kept, but nothing is sent.
M.ENDPOINT = ''
M.DIR = '/earthRally/telemetry/'
M.STATE_FILE = M.DIR .. 'state.json'
M.QUEUE_FILE = M.DIR .. 'queue.json'
M.SENT_FILE = M.DIR .. 'sent.jsonl'
M.BATCH = 50              -- events per message
M.QUEUE_MAX = 500         -- kept while the server cannot be reached; the oldest go first
M.TIMEOUT_S = 8           -- a send given up after this long
M.RETRY_S = 600           -- and not tried again for this long
M.PRIVACY_URL = 'https://github.com/DeRamp/BeamNG.Earth.Rally/blob/main/PRIVACY.md'

-- event -> the extra fields it may carry (anything else is dropped before it is queued)
M.EVENTS = {
  session_start = {},
  stage_started = { rally = true, stage = true, pass = true, line = true },
  stage_finished = { rally = true, stage = true, pass = true, result = true, time_s = true, resets = true, line = true },
  rally_started = { rally = true, stages_total = true },
  rally_finished = { rally = true, stages_done = true, stages_total = true },
  recce_done = { result = true },
  error = { code = true, module = true },
}

local st = nil              -- { consent = 'ask'|'yes'|'no' }
local queue = nil
local session = nil         -- this game session's random number (memory only)
local modVersion = '?'
local prompted = false      -- the question has been on screen this session
local sessionSent = false
local job, sock = nil, nil  -- the send under way (a coroutine) and its socket
local gen = 0               -- bumped by No: a send started before it is thrown away
local nextTry = 0
local clock = 0
local lastSent = nil        -- the last message sent, as written to SENT_FILE
local dnsCache, dnsFailed = {}, false
local attempts = {}         -- event id -> { done = { stageId = true } }: this session's rally attempt
local wantSend = false

local function lg(level, msg) local f = rawget(_G, 'log') if f then f(level, 'earthRally', 'stats: ' .. msg) end end
local function readJson(p)
  local fs, read = rawget(_G, 'FS'), rawget(_G, 'jsonReadFile')
  if not read or (fs and fs.fileExists and not fs:fileExists(p)) then return nil end
  local ok, d = pcall(read, p)
  return ok and type(d) == 'table' and d or nil
end
local function writeJson(p, t)
  local w = rawget(_G, 'jsonWriteFile')
  if w then pcall(w, p, t, true) end
end
local function encode(t)
  local enc = rawget(_G, 'jsonEncode')
  if enc then return enc(t) end
  error('no jsonEncode')
end

-- A random number for this session: 32 hex digits. Not tied to anything on the PC, never saved.
local seeded = false
function M.newSession()
  if not seeded then
    seeded = true
    local addr = tonumber(tostring({}):match('0x(%x+)') or '0', 16) or 0
    math.randomseed((os.time() + math.floor(os.clock() * 1e6) + addr) % 2147483647)
  end
  local parts = {}
  for i = 1, 32 do parts[i] = string.format('%x', math.random(0, 15)) end
  return table.concat(parts)
end

local function load()
  if st then return end
  local saved = readJson(M.STATE_FILE) or {}
  st = { consent = (saved.consent == 'yes' or saved.consent == 'no') and saved.consent or 'ask' }
  local q = readJson(M.QUEUE_FILE)
  queue = (st.consent == 'yes' and q and type(q.events) == 'table') and q.events or {}
end
local function saveState() writeJson(M.STATE_FILE, { consent = st.consent }) end
local function saveQueue() writeJson(M.QUEUE_FILE, { events = queue }) end

-- Drop the send under way (its socket closed): after No, nothing more may leave.
local function cancelSend()
  if sock then pcall(function() sock:close() end) end
  job, sock = nil, nil
  gen = gen + 1
end

function M.init(version) modVersion = version or '?' load() end
function M.consent() load() return st.consent end

-- The player's answer: true (Yes), false (No). No also drops anything waiting and any send under way.
function M.answer(yes)
  load()
  st.consent = yes and 'yes' or 'no'
  if not yes then queue = {} saveQueue() cancelSend() wantSend = false end
  saveState()
  lg('I', 'the player said ' .. st.consent)
  if yes then M.sessionStart() end
end

-- The menu shows the question (main.uiState asks): remembered, so leaving the menu with it up is a No.
function M.prompting() load() if st.consent == 'ask' then prompted = true end end
function M.menuClosed() if prompted and st and st.consent == 'ask' then M.answer(false) end prompted = false end

local function earthVersion()
  local ok, earth = pcall(require, 'earthRally/earthAdapter')
  if not ok then return nil end
  local okV, a, b = pcall(earth.apiVersion)
  return okV and a and (tostring(a) .. '.' .. tostring(b)) or nil
end

-- Queue one event (only with Yes). fields: the event's own (EVENTS), the rest dropped.
function M.record(name, fields)
  load()
  if st.consent ~= 'yes' then return false end
  local allowed = M.EVENTS[name]
  if not allowed then return false end
  session = session or M.newSession()
  local e = { event = name, session = session, mod = modVersion, game = rawget(_G, 'beamng_version'),
    earth = earthVersion(), day = os.date('!%Y-%m-%d') }
  for k, v in pairs(fields or {}) do
    if allowed[k] then
      if type(v) == 'number' then e[k] = math.floor(v + 0.5)
      elseif type(v) == 'boolean' then e[k] = v
      elseif v ~= nil then e[k] = tostring(v):sub(1, 80) end
    end
  end
  queue[#queue + 1] = e
  while #queue > M.QUEUE_MAX do table.remove(queue, 1) end
  saveQueue()
  return true
end

function M.sessionStart()
  if sessionSent then return end
  if M.record('session_start') then sessionSent = true end
end

-- What a rally and a stage are called in the stats: named when they came from a pack (published files), else
-- 'custom' (a player's own map: its name could be a private place or event).
function M.names(event, stage)
  if type(event) == 'table' and type(event.pack) == 'table' then
    return tostring(event.name or event.id or '?'), stage and tostring(stage.name or stage.id or '?') or nil
  end
  return 'custom', stage and 'custom' or nil
end

------------------------------------------------------------------------------------------ hooks from the runner

-- run: runner's run table. Called when the stage clock starts (GO), so driving to the start and leaving is not a
-- run. Each run reports one start and, after it, one ending.
--   A rally attempt (this session, in memory): starts when the rally's first stage starts, unless an attempt is
--   open with nothing finished yet (restarting stage 1 is the same attempt); finishes once every stage of the rally
--   has been finished in it, in any order. A one-stage rally is only a stage.
function M.stageStarted(run)
  if not (run and run.event and run.stage) or run.statsStarted then return end
  run.statsStarted = true
  local rally, stage = M.names(run.event, run.stage)
  M.record('stage_started', { rally = rally, stage = stage, pass = run.ss, line = run.checks and run.checks.line })
  local stages, id = run.event.stages or {}, run.event.id or rally
  if #stages > 1 and stages[1] and stages[1].id == run.stage.id then
    local a = attempts[id]
    if not (a and next(a.done) == nil) then
      attempts[id] = { done = {} }
      M.record('rally_started', { rally = rally, stages_total = #stages })
    end
  end
end

-- result: 'finished' | 'failed' | 'quit'.
function M.stageEnded(run, result)
  if not (run and run.event and run.stage) or run.statsEnded or not run.statsStarted then return end
  run.statsEnded = true
  local rally, stage = M.names(run.event, run.stage)
  M.record('stage_finished', { rally = rally, stage = stage, pass = run.ss, result = result,
    time_s = result == 'finished' and run.finalTime or nil, resets = run.resets or 0,
    line = run.checks and run.checks.line })
  local stages, id = run.event.stages or {}, run.event.id or rally
  local a = attempts[id]
  if result == 'finished' and a then
    a.done[run.stage.id] = true
    local done = 0
    for _, s in ipairs(stages) do if a.done[s.id] then done = done + 1 end end
    if done == #stages then
      M.record('rally_finished', { rally = rally, stages_done = done, stages_total = #stages })
      attempts[id] = nil
    end
  end
  M.flushSoon()
end

-- code: a short fixed name (never a message: it could carry a path with the player's name in it)
function M.error(code, module) M.record('error', { code = code, module = module }) end

------------------------------------------------------------------------------------------ sending

function M.parseUrl(u)
  local host, port, path = tostring(u or ''):match('^http://([^/:]+):?(%d*)(/?.*)$')
  if not host or host == '' then return nil end
  return host, tonumber(port) or 80, (path ~= '' and path or '/')
end

-- One POST, in a coroutine: yields while waiting. Returns the HTTP status, or nil and why.
function M.post(url, body, now)
  local host, port, path = M.parseUrl(url)
  if not host then return nil, 'no address' end
  local okS, socket = pcall(require, 'socket')
  if not okS then return nil, 'no luasocket' end
  local ip = dnsCache[host]
  if not ip then
    if dnsFailed then return nil, 'name lookup failed earlier' end
    ip = socket.dns.toip(host)
    if not ip then dnsFailed = true return nil, 'name lookup failed' end
    dnsCache[host] = ip
  end
  local t0 = now()
  local c = socket.tcp()
  sock = c
  c:settimeout(0)
  local function late() return now() - t0 > M.TIMEOUT_S end
  local function stop(why) c:close() if sock == c then sock = nil end return nil, why end
  local ok, err = c:connect(ip, port)
  if not ok and err ~= 'timeout' and err ~= 'Operation already in progress' then return stop(err) end
  while not ok do
    local _, w = socket.select(nil, { c }, 0)
    if w and #w > 0 then
      -- writable: connected, or (on some systems) failed. Asking again tells which.
      local ok2, e2 = c:connect(ip, port)
      if ok2 or e2 == 'already connected' then break end
      if e2 ~= 'timeout' and e2 ~= 'Operation already in progress' then return stop(e2) end
    end
    if late() then return stop('connect timed out') end
    coroutine.yield()
  end
  local req = 'POST ' .. path .. ' HTTP/1.0\r\nHost: ' .. host .. '\r\nContent-Type: application/json\r\n' ..
    'User-Agent: EarthRally/' .. modVersion .. '\r\nContent-Length: ' .. #body .. '\r\nConnection: close\r\n\r\n' .. body
  local i = 1
  while i <= #req do
    local n, e, partial = c:send(req, i)
    if n then i = n + 1
    elseif e == 'timeout' then
      i = (partial or (i - 1)) + 1
      if late() then return stop('send timed out') end
      coroutine.yield()
    else return stop(e) end
  end
  local line, got = nil, ''
  while true do
    local s, e, partial = c:receive('*l', got)
    if s then line = s break end
    if e ~= 'timeout' then return stop(e) end
    got = partial or got
    if late() then return stop('no answer') end
    coroutine.yield()
  end
  c:close()
  if sock == c then sock = nil end
  return tonumber(line:match('^HTTP/%d%.%d (%d+)'))
end

local function appendSent(text)
  local okF, f = pcall(io.open, M.SENT_FILE, 'a')
  if okF and f then f:write(text, '\n') f:close() end
  lastSent = text
end

local function base(path)
  return (M.ENDPOINT:gsub('/+$', '')) .. path
end

-- Take these events off the queue by identity (more may have been queued meanwhile, or the oldest pushed out).
local function unqueue(batch)
  local gone = {}
  for _, e in ipairs(batch) do gone[e] = true end
  local kept = {}
  for _, e in ipairs(queue) do if not gone[e] then kept[#kept + 1] = e end end
  queue = kept
  saveQueue()
end

-- The next send: a batch of events. Returns a function(now) -> true (done), false (try later).
local function nextJob()
  if M.ENDPOINT == '' or st.consent ~= 'yes' or #queue == 0 then return nil end
  local batch = {}
  for k = 1, math.min(#queue, M.BATCH) do batch[k] = queue[k] end
  local myGen = gen
  return function(now)
    local code, why = M.post(base('/v1/events'), encode({ events = batch }), now)
    if myGen ~= gen then return true end           -- (No was pressed meanwhile: forget it)
    if code and code >= 200 and code < 300 then
      unqueue(batch)
      for _, e in ipairs(batch) do appendSent(encode(e)) end
      return true
    end
    if code and code >= 400 and code < 500 then
      -- refused (bad, too big, over the cap): sending it again would be refused again
      lg('W', 'the server refused ' .. #batch .. ' events (' .. code .. '); dropped')
      unqueue(batch)
      return false
    end
    lg('I', 'not sent (' .. tostring(code or why) .. '); kept for later')
    return false
  end
end

function M.flushSoon() wantSend = true end

-- Every frame (main.onUpdate). menuUp: the menu page is the screen (the one name lookup is done only then).
function M.update(dt, menuUp)
  clock = clock + (dt or 0)
  if not st then return end
  if job then
    local co = job
    local ok, r = coroutine.resume(co, function() return clock end)
    if job ~= co then return end                    -- (cancelled while it ran)
    if not ok then lg('W', 'send failed: ' .. tostring(r)) cancelSend() nextTry = clock + M.RETRY_S return end
    if coroutine.status(co) == 'dead' then
      job = nil
      if r then wantSend = #queue > 0 else nextTry = clock + M.RETRY_S end
    end
    return
  end
  if not wantSend or clock < nextTry or dnsFailed then return end
  if not next(dnsCache) and not menuUp then return end
  local fn = nextJob()
  if not fn then wantSend = false return end
  job = coroutine.create(function(now) return fn(now) end)
end

------------------------------------------------------------------------------------------ the player's controls

function M.openFolder()
  local plat = rawget(_G, 'Engine') and Engine.Platform
  if plat and plat.exploreFolder then pcall(plat.exploreFolder, M.DIR) return true end
  return false
end

-- For the menu page.
function M.uiState()
  load()
  return { consent = st.consent, server = M.ENDPOINT ~= '', waiting = #queue, last = lastSent, privacyUrl = M.PRIVACY_URL }
end

-- (tests)
function M._reset()
  st, queue, session, prompted, sessionSent, job, sock, lastSent = nil, nil, nil, false, false, nil, nil, nil
  nextTry, clock, wantSend, dnsCache, dnsFailed, attempts = 0, 0, false, {}, false, {}
end
function M._queue() return queue end
function M._state() return st end
function M._session() return session end
function M._job() return job end

return M
