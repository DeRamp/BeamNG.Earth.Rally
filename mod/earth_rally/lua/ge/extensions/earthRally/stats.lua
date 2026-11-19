-- earthRally/stats: anonymous player stats, opt-in (docs/research-telemetry.md, PRIVACY.md, the mock-up in
-- docs/mockups-telemetry/telemetry.html).
--
--   Asked when the player turns the leaderboard on (#76): its own Yes / No, separate from the leaderboard, which
--   works either way. Nothing is recorded or sent before a Yes; closing the menu with the question up counts as No.
--   Only the answer, the install number (below) and anything waiting to go are kept, in the user folder's
--   earthRally/telemetry/; every message sent is also written word for word to SENT_FILE, so the player can read
--   exactly what left their PC.
--
--   Each game session gets a new random number, never reused, and every event carries it. The leaderboard's player id
--   is never sent with them.
--   The install number (the owner, 2026-11-18: count players): a random number made on Yes and kept in STATE_FILE,
--   sent once per session in its own event, install_seen, with only the versions and the day, in a message of its
--   own: never with the session number or a stage, so the server can count players but not tie one to what they
--   drove (it keeps them in a table apart, server/schema.sql installs). A No deletes
--   it; a later Yes makes a new one.
--
--   Sent through the leaderboard's companion (online.lua, M.transport): the game's Lua cannot reach the internet, so
--   events go to the companion on 127.0.0.1 and it posts them over HTTPS to the stats server (server/). Recorded only
--   while the leaderboard is on; sent in batches; the game never waits on them.
--
--   What is sent: the event, the session number (install_seen: the install number instead), the mod, game and BeamNG.Earth versions, the day (UTC, no time),
--   and per event a few fields (EVENTS): a finished stage's car and class, an error's cleaned text. Rallies and
--   stages are sent by name, a pack's and the player's own imported or home-made ones alike (the owner, 2026-11-18);
--   a car that is not one of the game's own is sent as 'custom'. Never: the player's names, accounts, hardware,
--   other mods, positions, logs. The IP address reaches the server with every request but is not stored.
local M = {}

M.DIR = '/earthRally/telemetry/'
M.STATE_FILE = M.DIR .. 'state.json'
M.QUEUE_FILE = M.DIR .. 'queue.json'
M.SENT_FILE = M.DIR .. 'sent.jsonl'
M.BATCH = 50              -- events per message
M.QUEUE_MAX = 500         -- kept while the server cannot be reached; the oldest go first
M.RETRY_S = 300           -- a send that failed is not tried again for this long
M.WAIT_S = 10             -- the companion not there: looked for again after this long
M.ERRORS_MAX = 30         -- errors recorded per session at most
M.ERROR_REPEAT = 3        -- and each error code at most this often
M.MESSAGE_MAX = 200       -- an error's text, cleaned, cut to this
M.PRIVACY_URL = 'https://github.com/DeRamp/BeamNG.Earth.Rally/blob/main/PRIVACY.md'

-- event -> the extra fields it may carry (anything else is dropped before it is queued)
M.EVENTS = {
  session_start = {},
  stage_started = { rally = true, stage = true, pass = true, line = true },
  stage_finished = { rally = true, stage = true, pass = true, result = true, time_s = true, resets = true, line = true,
    car = true, cls = true },
  rally_started = { rally = true, stages_total = true },
  rally_finished = { rally = true, stages_done = true, stages_total = true },
  recce_done = { result = true },
  error = { code = true, module = true, message = true },
}
-- install_seen: its own event, never through record() (no session number): exactly these fields
M.INSTALL_FIELDS = { event = true, install = true, mod = true, game = true, earth = true, day = true }

local st = nil              -- { consent = 'ask'|'yes'|'no', install = 32 hex (only with yes) }
local queue = nil
local session = nil         -- this game session's random number (never reused)
local modVersion = '?'
local prompted = false      -- the question has been on screen this session
local sessionSent = false
local job = nil            -- true while a batch is with the companion
local gen = 0               -- bumped by No: a send started before it is thrown away
local nextTry = 0
local clock = 0
local lastSent = nil        -- the last message sent, as written to SENT_FILE
local errCount, errSeen = 0, {}   -- this session's errors recorded, and how often each code
local attempts = {}         -- event id -> { done = passes finished }: this session's rally attempt
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

-- A random number for this session (and the install number): 32 hex digits. Not tied to anything on the PC.
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
  if st.consent == 'yes' and type(saved.install) == 'string' and saved.install:match('^%x+$') and #saved.install == 32 then
    st.install = saved.install:lower()
  end
  local q = readJson(M.QUEUE_FILE)
  queue = (st.consent == 'yes' and q and type(q.events) == 'table') and q.events or {}
end
local function saveState() writeJson(M.STATE_FILE, { consent = st.consent, install = st.install }) end
local function saveQueue() writeJson(M.QUEUE_FILE, { events = queue }) end

-- Drop the send under way (its answer ignored): after No, nothing more is taken off the queue or sent.
local function cancelSend()
  job = nil
  gen = gen + 1
end

function M.init(version) modVersion = version or '?' load() end
function M.consent() load() return st.consent end

-- The player's answer: true (Yes), false (No). No also drops anything waiting and any send under way.
function M.answer(yes)
  load()
  st.consent = yes and 'yes' or 'no'
  -- (Yes: the install number kept, or made; No: deleted, so a later Yes makes a new one)
  if yes then st.install = st.install or M.newSession() else st.install = nil end
  -- (No throws the session's start away with the rest: a Yes after it records the start again)
  if not yes then queue = {} saveQueue() cancelSend() wantSend = false sessionSent = false end
  saveState()
  lg('I', 'the player said ' .. st.consent)
  if yes then M.sessionStart() end
end

-- The menu shows the question (main.uiState asks): remembered, so leaving the menu with it up is a No.
function M.prompting() load() if st.consent == 'ask' then prompted = true end end
-- (the question went without an answer -- Leaderboards turned off under it: not a No)
function M.unprompt() prompted = false end
function M.menuClosed() if prompted and st and st.consent == 'ask' then M.answer(false) end prompted = false end

local function earthVersion()
  local ok, earth = pcall(require, 'earthRally/earthAdapter')
  if not ok then return nil end
  local okV, a, b = pcall(earth.apiVersion)
  return okV and a and (tostring(a) .. '.' .. tostring(b)) or nil
end

-- Whether the leaderboard is on (main.lua sets it: online.enabled). Stats go through its companion, so they are
-- recorded only while it is on.
M.active = nil

-- Queue one event (only with Yes, and the leaderboard on). fields: the event's own (EVENTS), the rest dropped.
function M.record(name, fields)
  load()
  if st.consent ~= 'yes' or not (M.active and M.active()) then return false end
  local allowed = M.EVENTS[name]
  if not allowed then return false end
  session = session or M.newSession()
  local e = { event = name, session = session, mod = modVersion, game = rawget(_G, 'beamng_version'),
    earth = earthVersion(), day = os.date('!%Y-%m-%d') }
  for k, v in pairs(fields or {}) do
    if allowed[k] then
      if type(v) == 'number' then e[k] = math.floor(v + 0.5)
      elseif type(v) == 'boolean' then e[k] = v
      elseif v ~= nil then e[k] = tostring(v):sub(1, k == 'message' and M.MESSAGE_MAX or 80) end
    end
  end
  queue[#queue + 1] = e
  while #queue > M.QUEUE_MAX do table.remove(queue, 1) end
  saveQueue()
  return true
end

-- install_seen: the install number on its own, with only the versions and the day (INSTALL_FIELDS).
local function recordInstall()
  if not st.install then st.install = M.newSession() saveState() end
  queue[#queue + 1] = { event = 'install_seen', install = st.install, mod = modVersion, game = rawget(_G, 'beamng_version'),
    earth = earthVersion(), day = os.date('!%Y-%m-%d') }
  while #queue > M.QUEUE_MAX do table.remove(queue, 1) end
  saveQueue()
end

function M.sessionStart()
  if sessionSent then return end
  if M.record('session_start') then sessionSent = true recordInstall() end
end

-- What a rally and a stage are called in the stats: their names, from a pack or the player's own imported or
-- home-made ones alike (until 2026-11-18 a player's own were sent as 'custom'), cut to 80 as record() does.
function M.names(event, stage)
  local function nm(t) return type(t) == 'table' and tostring(t.name or t.id or '?'):sub(1, 80) or '?' end
  return nm(event), stage and nm(stage) or nil
end

------------------------------------------------------------------------------------------ hooks from the runner

-- run: runner's run table. Called when the stage clock starts (GO), so driving to the start and leaving is not a
-- run. Each run reports one start and, after it, one ending.
--   A rally attempt (this session, in memory) follows the rally's running order (run.rallyOrder: the itinerary's
--   counted passes, so a stage driven in two loops is in it twice; else the map's stages). It starts when the first
--   pass's stage starts and no attempt is waiting on that stage (restarting stage 1 is the same attempt); each pass
--   finished in turn moves it on; the last one finishes the rally. A stage out of turn is only a stage. A one-stage
--   rally is only a stage.
local function orderOf(run)
  if type(run.rallyOrder) == 'table' then return run.rallyOrder end
  local out = {}
  for _, s in ipairs(run.event.stages or {}) do out[#out + 1] = s.id end
  return out
end

function M.stageStarted(run)
  if not (run and run.event and run.stage) or run.statsStarted then return end
  run.statsStarted = true
  local rally, stage = M.names(run.event, run.stage)
  M.record('stage_started', { rally = rally, stage = stage, pass = run.ss, line = run.checks and run.checks.line })
  local order, id = orderOf(run), run.event.id or rally
  if #order < 2 then return end
  local a = attempts[id]
  if a and order[a.done + 1] == run.stage.id then return end           -- (the next pass of the attempt under way)
  if order[1] == run.stage.id then
    attempts[id] = { done = 0 }
    M.record('rally_started', { rally = rally, stages_total = #order })
  end
end

-- result: 'finished' | 'failed' | 'quit'.
function M.stageEnded(run, result)
  if not (run and run.event and run.stage) or run.statsEnded or not run.statsStarted then return end
  run.statsEnded = true
  local rally, stage = M.names(run.event, run.stage)
  M.record('stage_finished', { rally = rally, stage = stage, pass = run.ss, result = result,
    time_s = result == 'finished' and run.finalTime or nil, resets = run.resets or 0,
    line = run.checks and run.checks.line,
    -- (the car and its class, as the runner found them at the finish: a car that is not the game's own is 'custom')
    cls = run.carClass, car = run.carClass and (run.carClass == 'stock' and run.carName or 'custom') or nil })
  local order, id = orderOf(run), run.event.id or rally
  local a = attempts[id]
  if result == 'finished' and a and order[a.done + 1] == run.stage.id then
    a.done = a.done + 1
    if a.done >= #order then
      M.record('rally_finished', { rally = rally, stages_done = a.done, stages_total = #order })
      attempts[id] = nil
    end
  end
  M.flushSoon()
end

-- An error: code a short name for it, module the part of the mod, message its text. The text is cleaned first
-- (report.clean: user names in paths, emails, IP addresses, Steam ids out) and cut to MESSAGE_MAX; numbers in the
-- code become #, so the same error is one code. At most ERRORS_MAX a session, each code ERROR_REPEAT times.
function M.cleanMessage(msg)
  if msg == nil then return nil end
  local text = tostring(msg):gsub('[\r\n]+', ' ')
  local okR, report = pcall(require, 'earthRally/report')
  if not (okR and type(report) == 'table' and report.clean) then return nil end
  local user = os.getenv and (os.getenv('USERNAME') or os.getenv('USER')) or nil
  local okC, ls = pcall(report.clean, text, user)
  if not (okC and type(ls) == 'table' and type(ls[1]) == 'string') then return nil end
  return ls[1]:sub(1, M.MESSAGE_MAX)
end

function M.error(code, module, message)
  load()
  if st.consent ~= 'yes' or errCount >= M.ERRORS_MAX or not (M.active and M.active()) then return false end
  code = (M.cleanMessage(tostring(code or 'error')) or 'error'):gsub('%d+', '#'):sub(1, 80)
  local n = (errSeen[code] or 0) + 1
  if n > M.ERROR_REPEAT then return false end
  if not M.record('error', { code = code, module = module, message = M.cleanMessage(message) }) then return false end
  errSeen[code] = n
  errCount = errCount + 1
  M.flushSoon()
  return true
end

-- Every error Earth Rally writes to the game's log (log('E', 'earthRally...', text)) recorded as one, while stats
-- are on: the global log wrapped once, the original always called first. unwatchLog puts it back.
-- (the wrapper keeps its own original: something that wrapped it after us, and later calls it or puts it back,
-- still reaches the game's log; unwatched, it only passes lines on)
local origLog, myLog, inLog, watching = nil, nil, false, false
function M.watchLog()
  watching = true
  if myLog then return end
  local lgf = rawget(_G, 'log')
  if type(lgf) ~= 'function' then return end
  local orig = lgf
  origLog = orig
  myLog = function(level, tag, msg, ...)
    orig(level, tag, msg, ...)
    if watching and level == 'E' and not inLog and type(tag) == 'string' and tag:sub(1, 10) == 'earthRally' and st
      and st.consent == 'yes' then
      inLog = true
      local text = tostring(msg)
      -- (the code: the text up to its first colon, else its first 40 letters: "rally prep", "menu action go")
      local code = text:match('^([^:]+):') or text:sub(1, 40)
      pcall(M.error, code, tag, text)
      inLog = false
    end
  end
  rawset(_G, 'log', myLog)
end
function M.unwatchLog()
  watching = false
  -- (put back only when it is still ours on top; else ours stays under the other one, passing lines on)
  if myLog and rawget(_G, 'log') == myLog then rawset(_G, 'log', origLog) origLog, myLog = nil, nil end
end

------------------------------------------------------------------------------------------ sending

-- How events leave: set by main.lua to the leaderboard companion (online.lua): transport(events, cb) -> false when
-- the companion is not connected; else cb(answer) once, { ok } or { ok = false, status, offline }. The game's own Lua
-- cannot reach the internet (BeamNG's network sandbox, found 2026-11-16), so stats go only through the companion (#76).
M.transport = nil

local function appendSent(text)
  local okF, f = pcall(io.open, M.SENT_FILE, 'a')
  if okF and f then f:write(text, '\n') f:close() end
  lastSent = text
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

local function sendBatch()
  if not M.transport or st.consent ~= 'yes' or #queue == 0 then return false end
  -- (install_seen always goes in a message of its own, never with session events: the oldest waiting event says
  -- which kind this message carries)
  local installs = queue[1].event == 'install_seen'
  local batch = {}
  for _, e in ipairs(queue) do
    if #batch >= M.BATCH then break end
    if (e.event == 'install_seen') == installs then batch[#batch + 1] = e end
  end
  local myGen = gen
  job = true
  local started = M.transport(batch, function(r)
    if myGen ~= gen then return end                -- (No was pressed meanwhile: forget it)
    job = nil
    r = type(r) == 'table' and r or {}
    local code = tonumber(r.status)
    if r.ok then
      unqueue(batch)
      for _, e in ipairs(batch) do appendSent(encode(e)) end
      wantSend = #queue > 0
    elseif code and code >= 400 and code < 500 and code ~= 429 and code ~= 404 then
      -- (404: no stats server at that address yet -- kept, not dropped)
      -- refused (bad, too big, over the cap): sending it again would be refused again
      -- (it did leave the PC, so it goes in the local copy too, marked)
      lg('W', 'the server refused ' .. #batch .. ' events (' .. code .. '); dropped')
      unqueue(batch)
      for _, e in ipairs(batch) do appendSent(encode(e)) end
      appendSent(encode({ note = 'the server refused the ' .. #batch .. ' lines above (' .. code .. ')' }))
      nextTry = clock + M.RETRY_S
    else
      lg('I', 'not sent (' .. tostring(code or r.error) .. '); kept for later')
      nextTry = clock + M.RETRY_S
    end
  end)
  if not started and myGen == gen then job = nil end
  return started
end

function M.flushSoon() wantSend = true end

-- Every frame (main.onUpdate). One batch at a time, when the companion is there.
function M.update(dt)
  clock = clock + (dt or 0)
  if not st or job then return end
  if not wantSend or clock < nextTry then return end
  if #queue == 0 then wantSend = false return end
  if not sendBatch() and not job then nextTry = clock + M.WAIT_S end
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
  return { consent = st.consent, leaderboard = (M.active and M.active()) == true, waiting = #queue, last = lastSent,
    privacyUrl = M.PRIVACY_URL }
end

-- (tests)
function M._reset()
  st, queue, session, prompted, sessionSent, job, lastSent = nil, nil, nil, false, false, nil, nil
  nextTry, clock, wantSend, attempts, errCount, errSeen = 0, 0, false, {}, 0, {}
end
function M._queue() return queue end
function M._state() return st end
function M._session() return session end
function M._install() return st and st.install end
function M._job() return job end

return M
