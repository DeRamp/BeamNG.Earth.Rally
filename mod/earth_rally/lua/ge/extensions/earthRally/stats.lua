-- earthRally/stats: anonymous player stats, opt-in (docs/research-telemetry.md, PRIVACY.md, the mock-up in
-- docs/mockups-telemetry/telemetry.html).
--
--   Asked once, when the rally menu first opens. Nothing is recorded or sent before the answer; closing the menu
--   with the question up counts as No. The answer, a random install number (made only on Yes) and anything waiting
--   to go are kept in the user folder's earthRally/telemetry/; every message sent is also written word for word to
--   SENT_FILE, so the player can read exactly what left their PC.
--
--   Sent over plain HTTP (the game's Lua has no TLS) to the stats Worker (server/), in batches, from a coroutine
--   stepped by update(): the game never waits on the network, except the one name lookup per session, which is
--   only done while the menu page is up (the game is paused there).
--
--   What is sent: the event, the install number, the mod, game and BeamNG.Earth versions, the day (UTC, no time),
--   and per event a few counts (EVENTS). Rallies and stages from a pack are named; a player's own imported maps are
--   sent as 'custom' (a name could be a private place). Never: names, accounts, IP (the server does not keep it),
--   hardware, other mods, positions, free text, logs.
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
  stage_started = { rally = true, stage = true, pass = true, pacenotes = true, line = true },
  stage_finished = { rally = true, stage = true, pass = true, result = true, time_s = true, resets = true,
                     pacenotes = true, line = true },
  rally_started = { rally = true, stages_total = true },
  rally_finished = { rally = true, stages_done = true, stages_total = true },
  recce_done = { result = true },
  error = { code = true, module = true },
}

local st = nil              -- { consent = 'ask'|'yes'|'no', install, deletes = { install... } }
local queue = nil
local modVersion = '?'
local prompted = false      -- the question has been on screen this session
local sessionSent = false
local job, jobT = nil, 0    -- the send under way (a coroutine) and how long it has run
local nextTry = 0
local clock = 0
local lastSent = nil        -- the last message sent, as written to SENT_FILE
local dnsCache = {}

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

-- A random install number: 32 hex digits. Not tied to anything on the PC; replaced by "Delete my stats".
function M.newInstall()
  local parts = {}
  local mix = math.floor((os.clock() * 1e6) % 65536) + os.time() % 65536 + tonumber(tostring({}):match('0x(%x+)') or '0', 16) % 65536
  for i = 1, 32 do parts[i] = string.format('%x', (math.random(0, 15) + mix + i * 7) % 16) mix = math.floor(mix / 3) + math.random(0, 9999) end
  return table.concat(parts)
end

local function load()
  if st then return end
  st = readJson(M.STATE_FILE) or {}
  if st.consent ~= 'yes' and st.consent ~= 'no' then st.consent = 'ask' end
  if st.consent == 'yes' and type(st.install) ~= 'string' then st.install = M.newInstall() end
  if type(st.deletes) ~= 'table' then st.deletes = {} end
  local q = readJson(M.QUEUE_FILE)
  queue = (q and type(q.events) == 'table') and q.events or {}
end
local function saveState() writeJson(M.STATE_FILE, { consent = st.consent, install = st.install, deletes = st.deletes }) end
local function saveQueue() writeJson(M.QUEUE_FILE, { events = queue }) end

function M.init(version) modVersion = version or '?' load() end
function M.consent() load() return st.consent end

-- The player's answer: true (Yes), false (No).
function M.answer(yes)
  load()
  st.consent = yes and 'yes' or 'no'
  if yes and not st.install then st.install = M.newInstall() end
  if not yes then queue = {} saveQueue() end
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
  local e = { event = name, install = st.install, mod = modVersion, game = rawget(_G, 'beamng_version'),
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

-- run: runner's run table. Each run reports one start and one ending.
function M.stageStarted(run, pacenotes)
  if not (run and run.event and run.stage) or run.statsStarted then return end
  run.statsStarted = true
  local rally, stage = M.names(run.event, run.stage)
  M.record('stage_started', { rally = rally, stage = stage, pass = run.ss, pacenotes = pacenotes, line = run.checks and run.checks.line })
  local stages = run.event.stages or {}
  if #stages > 1 and stages[1] and stages[1].id == run.stage.id then
    M.record('rally_started', { rally = rally, stages_total = #stages })
  end
end

-- result: 'finished' | 'failed' | 'quit'. best(eventId, stageId): a time on that stage, for "rally finished".
function M.stageEnded(run, result, best)
  if not (run and run.event and run.stage) or run.statsEnded or not run.statsStarted then return end
  run.statsEnded = true
  local rally, stage = M.names(run.event, run.stage)
  M.record('stage_finished', { rally = rally, stage = stage, pass = run.ss, result = result,
    time_s = result == 'finished' and run.finalTime or nil, resets = run.resets or 0,
    line = run.checks and run.checks.line })
  local stages = run.event.stages or {}
  if result == 'finished' and #stages > 1 and stages[#stages].id == run.stage.id and best then
    local done = 0
    for _, s in ipairs(stages) do if best(run.event.id, s.id) then done = done + 1 end end
    if done == #stages then M.record('rally_finished', { rally = rally, stages_done = done, stages_total = #stages }) end
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
    ip = socket.dns.toip(host)
    if not ip then return nil, 'name lookup failed' end
    dnsCache[host] = ip
  end
  local t0 = now()
  local c = socket.tcp()
  c:settimeout(0)
  local ok, err = c:connect(ip, port)
  local function late() return now() - t0 > M.TIMEOUT_S end
  if not ok and err ~= 'timeout' and err ~= 'Operation already in progress' then c:close() return nil, err end
  while not ok do
    local _, w = socket.select(nil, { c }, 0)
    if w and #w > 0 then break end
    if late() then c:close() return nil, 'connect timed out' end
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
      if late() then c:close() return nil, 'send timed out' end
      coroutine.yield()
    else c:close() return nil, e end
  end
  local line, got = nil, ''
  while true do
    local s, e, partial = c:receive('*l', got)
    if s then line = s break end
    if e ~= 'timeout' then c:close() return nil, e end
    got = partial or got
    if late() then c:close() return nil, 'no answer' end
    coroutine.yield()
  end
  c:close()
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

-- The next send: a waiting delete first, then a batch of events.
local function nextJob()
  if M.ENDPOINT == '' then return nil end
  if #st.deletes > 0 then
    local id = st.deletes[1]
    return function(now)
      local code = M.post(base('/v1/delete'), encode({ install = id }), now)
      if code and code >= 200 and code < 300 then table.remove(st.deletes, 1) saveState() return true end
      return false
    end
  end
  if st.consent ~= 'yes' or #queue == 0 then return nil end
  local n = math.min(#queue, M.BATCH)
  local batch = {}
  for k = 1, n do batch[k] = queue[k] end
  return function(now)
    local body = encode({ events = batch })
    local code, why = M.post(base('/v1/events'), body, now)
    if code and code >= 200 and code < 300 then
      for _ = 1, n do table.remove(queue, 1) end
      saveQueue()
      for _, e in ipairs(batch) do appendSent(encode(e)) end
      return true
    end
    lg('I', 'not sent (' .. tostring(code or why) .. '); kept for later')
    return false
  end
end

local wantSend = false
function M.flushSoon() wantSend = true end

-- Every frame (main.onUpdate). menuUp: the menu page is the screen (the one name lookup is done only then).
function M.update(dt, menuUp)
  clock = clock + (dt or 0)
  if not st then return end
  if job then
    jobT = jobT + (dt or 0)
    local ok, r = coroutine.resume(job, function() return clock end)
    if not ok then lg('W', 'send failed: ' .. tostring(r)) job = nil nextTry = clock + M.RETRY_S return end
    if coroutine.status(job) == 'dead' then
      job = nil
      if r then wantSend = (#queue > 0 or #st.deletes > 0) else nextTry = clock + M.RETRY_S end
    end
    return
  end
  if not wantSend or clock < nextTry then return end
  if not next(dnsCache) and not menuUp then return end
  local fn = nextJob()
  if not fn then wantSend = false return end
  job, jobT = coroutine.create(function(now) return fn(now) end), 0
end

------------------------------------------------------------------------------------------ the player's controls

-- Settings > Privacy: on / off (the same as answering again).
function M.set(on) M.answer(on and true or false) end

-- Delete my stats: the server asked to remove this install's rows, what is waiting and the local copy dropped,
-- and a new install number if stats stay on.
function M.deleteMine()
  load()
  if st.install then st.deletes[#st.deletes + 1] = st.install end
  st.install = (st.consent == 'yes') and M.newInstall() or nil
  queue = {}
  saveQueue()
  saveState()
  pcall(os.remove, M.SENT_FILE)
  local fs = rawget(_G, 'FS')
  if fs and fs.removeFile then pcall(function() fs:removeFile(M.SENT_FILE) end) end
  lastSent = nil
  sessionSent = false
  M.flushSoon()
  lg('I', 'stats deleted; a new install number')
end

function M.openFolder()
  local plat = rawget(_G, 'Engine') and Engine.Platform
  if plat and plat.exploreFolder then pcall(plat.exploreFolder, M.DIR) return true end
  return false
end

-- For the menu page.
function M.uiState()
  load()
  return { consent = st.consent, server = M.ENDPOINT ~= '', waiting = #queue, last = lastSent,
    install = st.install and (st.install:sub(1, 4) .. '…' .. st.install:sub(-4)) or nil, privacyUrl = M.PRIVACY_URL }
end

-- (tests)
function M._reset() st, queue, prompted, sessionSent, job, lastSent, nextTry, clock, wantSend = nil, nil, false, false, nil, nil, 0, 0, false dnsCache = {} end
function M._queue() return queue end
function M._state() return st end

return M
