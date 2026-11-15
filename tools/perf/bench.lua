-- Earth Rally performance bench (docs/perf-plan-1.6.1.md). A developer tool: loaded into a running game through the
-- MCP server's run_lua by tools/perf/run_bench.py. It changes no mod file: the runner's internals it needs are read
-- from the upvalues of its public functions, so it measures the build the player has (the release zip) as it is.
--
--   erBench.run(suite)   suite = { name, steps = { {op = ...}, ... } } (JSON string or table). Runs the steps inside the
--                        game, one per frame at most, and writes:
--                          /earthRally/bench/<suite>/<label>.json   one per capture
--                          /earthRally/bench/progress.json          every 0.25 s: step, phase, label, done
--   erBench.stop(why)    stops the suite and puts every switch back
--
-- Steps (op): abort | start {event, stage} | spot {alongM} | state {name} | settle {timeout} | set {switch, value} |
--   capture {label, warm, seconds, profile} | arrival {label, seconds, dress} | wait {seconds} | note {text}
-- Switches: streams (Hz) | layout ('stage'|'plain') | notes (true|false) | props ('shown'|'hidden') |
--   startClock ('loaded'|'unloaded') | traffic ('on'|'off') | dress (objects per update) | fpsCap (0 = off)
if erBench and erBench.stop then pcall(erBench.stop, 'reloaded') end
local B = {}
erBench = B

local DIR = '/earthRally/bench/'
local runner = require('earthRally/runner')
local props = require('earthRally/props')
local earth = require('earthRally/earthAdapter')
local rallyA = require('earthRally/rallyAdapter')
local geo = require('earthRally/geo')

local wall = hptimer()
local function ms() return wall:stop() end
local function r2(x) return x and math.floor(x * 100 + 0.5) / 100 or nil end

------------------------------------------------------------------------------------------ the runner's internals
local function upv(f, name)
  if type(f) ~= 'function' then return nil end
  local i = 1
  while true do
    local n, v = debug.getupvalue(f, i)
    if not n then return nil end
    if n == name then return v end
    i = i + 1
  end
end
local I = {
  setState = upv(runner.wrapUp, 'setState'),
  zoneRelease = upv(runner.wrapUp, 'zoneRelease'),
  tidy = upv(runner.abort, 'tidy'),
}
I.trafficOn = upv(I.tidy, 'trafficOn')
I.systems = upv(I.trafficOn, 'systems')
B.internals = {}
for k, v in pairs(I) do B.internals[k] = v ~= nil end

------------------------------------------------------------------------------------------ hook timers
-- Each Earth Rally function below is wrapped while a suite runs: time per call (max and total per capture). The mod
-- calls them through their module tables, so the wrap sees every call; put back on stop.
local HOOKS = {
  { 'runner', runner, 'update' }, { 'runner', runner, 'placeClockView' }, { 'runner', runner, 'uiFrame' },
  { 'props', props, 'update' }, { 'earth', earth, 'update' }, { 'rallyA', rallyA, 'status' },
}
local hookStats, wrapped = {}, {}
local function wrapHooks()
  for _, h in ipairs(HOOKS) do
    local name, mod, fn = h[1] .. '.' .. h[3], h[2], h[3]
    local orig = mod[fn]
    if type(orig) == 'function' and not wrapped[name] then
      wrapped[name] = { mod = mod, fn = fn, orig = orig }
      mod[fn] = function(...)
        local t = ms()
        local a, b, c, d = orig(...)
        local dt = ms() - t
        local s = hookStats[name]
        if s then
          s.calls, s.total = s.calls + 1, s.total + dt
          if dt > s.max then s.max = dt end
          s.frame = s.frame + dt
        end
        return a, b, c, d
      end
    end
  end
end
local function unwrapHooks()
  for name, w in pairs(wrapped) do w.mod[w.fn] = w.orig end
  wrapped = {}
end
local function resetHookStats()
  hookStats = {}
  for name in pairs(wrapped) do hookStats[name] = { calls = 0, total = 0, max = 0, frame = 0 } end
end

------------------------------------------------------------------------------------------ counts (not during a capture)
local function staticCount()
  local ok, objs = pcall(scenetree.findClassObjects, 'TSStatic')
  return ok and objs and #objs or -1
end
local function nodeCount()
  local ok, n = pcall(function()
    local c = 0
    for _ in pairs(map.getMap().nodes) do c = c + 1 end
    return c
  end)
  return ok and n or -1
end
local function propCount()
  local g = scenetree.findObject(props.GROUP)
  if not g then return 0 end
  local ok, n = pcall(function() return g:size() end)
  return ok and n or -1
end

------------------------------------------------------------------------------------------ state of the run
local function run() return runner.current() end
local function runState() local r = run() return r and r.state or 'none' end

local SW = {}           -- the switches as set now
local swOrig = {}       -- what to put back
local function setPropsHidden(h)
  local g = scenetree.findObject(props.GROUP)
  if not g then return end
  pcall(function()
    for i = 0, g:size() - 1 do
      local o = g:at(i)
      if o and o.setHidden then o:setHidden(h) end
    end
  end)
end

local function setSwitch(name, value)
  if name == 'streams' then
    swOrig.streams = swOrig.streams or earthRally_main.STREAM_HZ
    earthRally_main.STREAM_HZ = value
  elseif name == 'layout' then
    local gs = rawget(_G, 'core_gamestate')
    if not (gs and gs.setGameState) then return false, 'no core_gamestate' end
    swOrig.layoutHold = swOrig.layoutHold or runner.LAYOUT_HOLD_S
    if value == 'plain' then
      runner.LAYOUT_HOLD_S = 1e9
      local r = run()
      pcall(gs.setGameState, nil, (r and r.oldLayout ~= runner.STAGE_LAYOUT and r.oldLayout) or 'beamngEarth')
    else
      runner.LAYOUT_HOLD_S = swOrig.layoutHold
      pcall(gs.setGameState, nil, runner.STAGE_LAYOUT)
    end
  elseif name == 'notes' then
    rallyA.notesOn(value and true or false)
  elseif name == 'props' then
    setPropsHidden(value == 'hidden')
  elseif name == 'startClock' then
    if value == 'unloaded' then pcall(extensions.unload, runner.CLOCK_EXT)
    else pcall(extensions.load, runner.CLOCK_EXT) end
  elseif name == 'traffic' then
    if not I.systems then return false, 'no traffic systems' end
    swOrig.traffic = swOrig.traffic or {}
    for sname, s in pairs(I.systems()) do
      local ok, cur = pcall(s.get)
      if value == 'off' then
        if ok and cur and cur ~= 0 then swOrig.traffic[sname] = cur pcall(s.set, 0) end
      elseif swOrig.traffic[sname] then
        pcall(s.set, swOrig.traffic[sname])
      end
    end
  elseif name == 'dress' then
    swOrig.dress = swOrig.dress or props.DRESS_OBJS_PER_UPDATE
    props.DRESS_OBJS_PER_UPDATE = value
  elseif name == 'fpsCap' then
    swOrig.fpsCap = swOrig.fpsCap or { settings.getValue('FPSLimiterEnabled'), settings.getValue('FPSLimiter') }
    if value and value > 0 then settings.setValue('FPSLimiter', value) settings.setValue('FPSLimiterEnabled', true)
    else settings.setValue('FPSLimiterEnabled', false) end
  else
    return false, 'unknown switch ' .. tostring(name)
  end
  SW[name] = value
  return true
end

local function restoreSwitches()
  if swOrig.streams then earthRally_main.STREAM_HZ = swOrig.streams end
  if swOrig.layoutHold then runner.LAYOUT_HOLD_S = swOrig.layoutHold end
  if swOrig.dress then props.DRESS_OBJS_PER_UPDATE = swOrig.dress end
  if swOrig.traffic and I.systems then
    for sname, s in pairs(I.systems()) do if swOrig.traffic[sname] then pcall(s.set, swOrig.traffic[sname]) end end
  end
  if swOrig.fpsCap then
    pcall(settings.setValue, 'FPSLimiter', swOrig.fpsCap[2])
    pcall(settings.setValue, 'FPSLimiterEnabled', swOrig.fpsCap[1])
  end
  if SW.props == 'hidden' then setPropsHidden(false) end
  swOrig, SW = {}, {}
end

------------------------------------------------------------------------------------------ the frame recorder
local W = nil            -- the capture under way
local lastT = nil
local metrics = {}
local function frame(dt)
  local w = W
  if not w then return end
  local el = (ms() - w.t0) / 1000
  if el < w.warm then return end
  local i = #w.ft + 1
  -- (hook timers and garbage counted from the first recorded frame, not from the warm-up)
  local gc = collectgarbage('count')
  if i == 1 then
    for _, s in pairs(hookStats) do s.calls, s.total, s.max = 0, 0, 0 end
    w.gcPrev, w.gcKB = gc, 0
  elseif gc > w.gcPrev then
    w.gcKB = w.gcKB + (gc - w.gcPrev)       -- (garbage made this frame; a collection drops the count, not counted)
  end
  w.gcPrev = gc
  w.ft[i] = r2(dt)
  if Engine.Debug and Engine.Debug.getLastPerformanceMetrics then
    for k in pairs(metrics) do metrics[k] = nil end
    Engine.Debug.getLastPerformanceMetrics(metrics)
    local spike = dt > 33.3
    local keep = spike and { frame = i, ms = r2(dt) } or nil
    for c, raw in pairs(metrics) do
      local v = tonumber(raw)
      if v and not c:match('^phys') and not c:match('^virt') then
        local s = w.cat[c]
        if not s then s = { sum = 0, max = 0 } w.cat[c] = s end
        s.sum = s.sum + v
        if v > s.max then s.max = v end
        if keep and v >= 1 then keep[c] = r2(v) end
      end
    end
    if keep then
      local hk = {}
      for name, s in pairs(hookStats) do if s.frame >= 0.5 then hk[name] = r2(s.frame) end end
      keep.hooks = hk
      if #w.spikes < 300 then w.spikes[#w.spikes + 1] = keep end
    end
  end
  for _, s in pairs(hookStats) do s.frame = 0 end
  if el >= w.warm + w.seconds then B._endCapture('time') end
end

local function pct(s, p) return #s > 0 and s[math.max(1, math.min(#s, math.ceil(#s * p)))] or nil end

local prof = nil
local function profStart(w)
  local ok, p = pcall(require, 'jit.profile')
  if not ok then return end
  prof = p
  w.luaLines, w.luaFiles, w.samples = {}, {}, 0
  p.start('li1', function(thread, samples)
    local cw = W
    if not cw or not cw.luaLines then return end
    cw.samples = cw.samples + samples
    local top = p.dumpstack(thread, 'pl', 1)
    cw.luaLines[top] = (cw.luaLines[top] or 0) + samples
    local file = top:match('^(.-):%d+') or top
    cw.luaFiles[file] = (cw.luaFiles[file] or 0) + samples
  end)
end
local function profStop() if prof then pcall(prof.stop) prof = nil end end
local function topN(t, n, total)
  local a = {}
  for k, v in pairs(t or {}) do a[#a + 1] = { k, v } end
  table.sort(a, function(x, y) return x[2] > y[2] end)
  local out = {}
  for i = 1, math.min(n, #a) do out[i] = { what = a[i][1], samples = a[i][2], share = r2(100 * a[i][2] / math.max(1, total)) } end
  return out
end

------------------------------------------------------------------------------------------ the suite
local S = nil            -- { cfg, co, step, phase, label, captures, log, done }
local progressT = 0

local function note(text)
  if S then S.log[#S.log + 1] = string.format('%.1f %s', (ms() - S.t0) / 1000, text) end
  log('I', 'erBench', text)
end

local function writeProgress(force)
  if not S then return end
  local t = ms()
  if not force and t - progressT < 250 then return end
  progressT = t
  local w = W
  pcall(jsonWriteFile, DIR .. 'progress.json', {
    suite = S.cfg.name, step = S.step, of = #S.cfg.steps, op = S.op, phase = S.phase, label = w and w.label or nil,
    capturing = w ~= nil and (ms() - w.t0) / 1000 >= w.warm or false, state = runState(), done = S.done or false,
    why = S.why, captures = S.captures, t = r2((t - S.t0) / 1000), err = S.err,
  }, false)
end

local function waitFrames(cond, timeoutS, what)
  local t0 = ms()
  while true do
    local ok, v = pcall(cond)
    if ok and v then return true end
    if (ms() - t0) / 1000 > timeoutS then error('timed out (' .. timeoutS .. ' s) waiting for ' .. what, 0) end
    coroutine.yield()
  end
end

function B._endCapture(why)
  local w = W
  if not w then return end
  W = nil
  profStop()
  local s = {}
  for i, v in ipairs(w.ft) do s[i] = v end
  table.sort(s)
  local n, sum, o33, o50 = #s, 0, 0, 0
  for _, v in ipairs(s) do sum = sum + v if v > 33.3 then o33 = o33 + 1 end if v > 50 then o50 = o50 + 1 end end
  local cats = {}
  for c, v in pairs(w.cat) do
    local mean = v.sum / math.max(1, n)
    if mean >= 0.02 or v.max >= 1 then cats[c] = { mean = r2(mean), max = r2(v.max) } end
  end
  local hooks = {}
  for name, h in pairs(hookStats) do
    hooks[name] = { calls = h.calls, meanMs = r2(h.total / math.max(1, h.calls)), maxMs = r2(h.max),
      perFrameMs = r2(h.total / math.max(1, n)) }
  end
  local r = run()
  local res = {
    format = 1, suite = S and S.cfg.name, label = w.label, meta = w.meta, why = why,
    startedAt = w.startedAt, quality = settings.getValue('GraphicOverallQuality'),
    frames = n, seconds = r2(sum / 1000), mean = n > 0 and r2(sum / n) or nil,
    p50 = r2(pct(s, 0.5)), p95 = r2(pct(s, 0.95)), p99 = r2(pct(s, 0.99)), max = r2(s[n]),
    over33 = o33, over50 = o50, engine = cats, hooks = hooks, spikes = w.spikes,
    gcKBs = r2((w.gcKB or 0) / math.max(0.001, sum / 1000)),
    counts = w.counts, state = runState(), along = r and r.along and math.floor(r.along) or nil,
    switches = deepcopy and deepcopy(SW) or SW,
    lua = w.samples and { samples = w.samples, files = topN(w.luaFiles, 20, w.samples),
      lines = topN(w.luaLines, 30, w.samples) } or nil,
    ft = w.ft,
  }
  pcall(jsonWriteFile, DIR .. (S and S.cfg.name or 'adhoc') .. '/' .. w.label .. '.json', res, false)
  if S then S.captures = S.captures + 1 end
  note(string.format('capture %s: %d frames, p50 %.2f p99 %.2f over50 %d', w.label, n, res.p50 or -1, res.p99 or -1, o50))
end

local function capture(step, meta)
  resetHookStats()
  W = { label = step.label, meta = meta, t0 = ms(), warm = step.warm or 5, seconds = step.seconds or 20, ft = {},
    cat = {}, spikes = {}, gc0 = collectgarbage('count'), startedAt = os.date('!%Y-%m-%dT%H:%M:%SZ'),
    counts = { statics = staticCount(), nodes = nodeCount(), props = propCount() } }
  if step.profile then profStart(W) end
  local optick = step.optick and Engine.Profiler and Engine.Profiler.startCapture
  local optickOn = false
  while W do
    -- (props hidden stays hidden: a site spawned during the capture is hidden too)
    if SW.props == 'hidden' then setPropsHidden(true) end
    if optick and not optickOn and (ms() - W.t0) / 1000 >= W.warm then
      pcall(Engine.Profiler.startCapture)
      optickOn = true
    end
    coroutine.yield()
  end
  if optickOn then
    pcall(Engine.Profiler.stopCapture)
    FS:directoryCreate('optick', true)
    local path = (FS:getUserPath() .. 'optick/' .. step.label .. '.opt'):gsub('\\', '/')
    local ok = pcall(Engine.Profiler.saveCapture, path)
    note('optick ' .. (ok and ('saved: ' .. path) or 'save failed'))
  end
end

-- The car set down on the stage line `alongM` past the start, facing along it, by a plain teleport (no BeamNG.Earth
-- teleport, so the world's origin stays where the run anchored it). Waits for ground under the point first.
local function placeAt(alongM)
  local r = run()
  if not (r and r.line and r.cum and r.startM) then error('no run line to place on', 0) end
  local s = r.startM + alongM
  local veh = getPlayerVehicle(0)
  if not veh then error('no player vehicle', 0) end
  local function target()
    local p = geo.pointAt(r.line, r.cum, s)
    local q = geo.pointAt(r.line, r.cum, s + 8)
    if not p.z then p.z = veh:getPosition().z end
    return p, q
  end
  -- (held at the line's own height, from the map's elevation data, until the ground there has streamed in: the
  -- world loads around the car, so the car has to be there first, and re-placed each frame it cannot fall)
  local hitZ
  waitFrames(function()
    local p, q = target()
    local d = castRayStatic(vec3(p.x, p.y, p.z + 15), vec3(0, 0, -1), 40)
    if d and d < 40 then hitZ = p.z + 15 - d return true end
    runner.placeCar(veh, vec3(p.x, p.y, p.z + 1.5), vec3(q.x - p.x, q.y - p.y, 0))
    return false
  end, 90, 'ground at ' .. alongM .. ' m')
  local p, q = target()
  runner.placeCar(veh, vec3(p.x, p.y, hitZ + 0.3), vec3(q.x - p.x, q.y - p.y, 0))
  r.prevAlong, r.along = s, s
  pcall(rallyA.resync)
  note(string.format('placed at %d m (line %.0f m), ground z %.1f', alongM, s, hitZ))
end

local function setState(name)
  local r = run()
  if name == 'none' then pcall(runner.abort, true) return end
  if not r then error('no run for state ' .. name, 0) end
  if name == 'running' then
    if r.state ~= 'running' then
      r.startAt = runner.clock()
      pcall(I.zoneRelease)
      rallyA.notesOn(true)
      r.clock = 0
      I.setState('running')
    end
  elseif name == 'waitStart' then
    r.startAt = (runner.clock() or 0) + 3600
    r.prevLeft = 3600
    r.staged = nil
    I.setState('waitStart')
  elseif name == 'finished' then
    r.finalTime = nil
    runner.wrapUp()
  else
    error('unknown state ' .. name, 0)
  end
  note('state ' .. name .. ' (now ' .. runState() .. ')')
end

-- The world settled: BeamNG.Earth loading nothing, the TSStatic count still for 5 s, and the median frame time of the
-- last 5 s within 5 % of the 5 s before it. Frame times are kept here (a short ring), not recorded.
local function settle(step)
  local t0, timeout = ms(), step.timeout or 120
  local ft, lastT2, lastCount, sameSince = {}, ms(), nil, ms()
  local nextCheck = ms()
  while true do
    local t = ms()
    ft[#ft + 1] = t - lastT2
    lastT2 = t
    if #ft > 2000 then table.remove(ft, 1) end
    if t >= nextCheck then
      nextCheck = t + 1000
      local c = staticCount()
      if c ~= lastCount then lastCount, sameSince = c, t end
      local loading = earth.loading()
      local el = (t - t0) / 1000
      if not loading and (t - sameSince) >= 5000 and el >= 10 then
        -- medians of the frames in the last 5 s and the 5 s before
        local a, b, acc = {}, {}, 0
        for i = #ft, 1, -1 do
          acc = acc + ft[i]
          if acc <= 5000 then a[#a + 1] = ft[i] elseif acc <= 10000 then b[#b + 1] = ft[i] else break end
        end
        table.sort(a) table.sort(b)
        local ma, mb = pct(a, 0.5), pct(b, 0.5)
        if ma and mb and math.abs(ma - mb) <= 0.05 * mb then
          note(string.format('settled in %.0f s (statics %d, median %.2f ms)', el, c, ma))
          return true, el
        end
      end
      if el > timeout then
        note(string.format('did not settle in %d s (loading %s, statics %d)', timeout, tostring(loading), c))
        return false, el
      end
    end
    coroutine.yield()
  end
end

local function check(step)
  -- the state the capture is for, before it starts: a wrong state stops the suite
  local want = step.state
  local r = run()
  local st = runState()
  if want and st ~= want then error('state is ' .. st .. ', not ' .. want, 0) end
  if want == 'running' or want == 'waitStart' then
    if step.alongM and r and r.along and math.abs((r.along - r.startM) - step.alongM) > 50 then
      error(string.format('car %.0f m along, not %d', r.along - r.startM, step.alongM), 0)
    end
  end
end

local OPS = {}
function OPS.note(st) note(st.text) end
function OPS.wait(st) local t0 = ms() waitFrames(function() return (ms() - t0) / 1000 >= st.seconds end, st.seconds + 5, 'wait') end
function OPS.abort() pcall(runner.abort, true) restoreSwitches() waitFrames(function() return runState() == 'none' or runState() == 'idle' or runState() == 'finished' end, 20, 'abort') end
function OPS.start(st)
  pcall(runner.abort, true)
  local res = earthRally_main.uiAction('drive', st.event, st.stage)
  if not (res and res.ok) then error('could not start: ' .. tostring(res and res.message), 0) end
  note('run started: ' .. st.event .. ' / ' .. st.stage)
  waitFrames(function()
    local s = runState()
    if s == 'failed' then error('run failed in setup: ' .. tostring(run().error), 0) end
    return s == 'toAtc' or s == 'toStart' or s == 'waitStart'
  end, st.timeout or 240, 'setup (toAtc/toStart)')
  waitFrames(function() return earth.ready() end, 60, 'BeamNG.Earth ready')
  note('setup done: ' .. runState())
end
function OPS.spot(st) placeAt(st.alongM) S.spot = st.alongM end
function OPS.state(st) setState(st.name) S.stateName = st.name end
function OPS.settle(st)
  local ok, el = settle(st)
  S.settled = ok
  S.settleS = el
  if not ok and st.required ~= false then S.skipUntilSpot = true end
end
function OPS.set(st)
  local ok, why = setSwitch(st.switch, st.value)
  if ok == false then error('switch ' .. st.switch .. ': ' .. tostring(why), 0) end
  note('set ' .. st.switch .. ' = ' .. tostring(st.value))
end
function OPS.capture(st)
  if S.skipUntilSpot then note('skipped ' .. st.label .. ' (spot did not settle)') return end
  check(st)
  capture(st, { test = st.test, spot = S.spot, state = runState(), switch = st.switch, value = st.value,
    pair = st.pair, settleS = S.settleS })
end
-- Arriving at a spot: the 10 s after the car is set down, while that stretch's dressing is put down. Recorded from the
-- moment of placing (no warm-up), so the spawn burst is in it.
function OPS.arrival(st)
  if st.dress then setSwitch('dress', st.dress) end
  resetHookStats()
  W = { label = st.label, t0 = ms(), warm = 0, seconds = 1e9, ft = {}, cat = {}, spikes = {},
    gc0 = collectgarbage('count'), startedAt = os.date('!%Y-%m-%dT%H:%M:%SZ'), counts = {},
    meta = { test = st.test, spot = st.alongM, state = runState(), switch = 'dress', value = st.dress, pair = st.pair } }
  placeAt(st.alongM)
  S.spot = st.alongM
  local t0 = ms()
  while W and (ms() - t0) / 1000 < (st.seconds or 10) do coroutine.yield() end
  W.counts = { statics = staticCount(), nodes = nodeCount(), props = propCount() }
  B._endCapture('arrival')
end

-- The road graph the game has now (map.getMap()), for the offline timings (T6): nodes with position, radius and links.
function OPS.dump(st)
  local out, n = { nodes = {} }, 0
  for id, nd in pairs(map.getMap().nodes) do
    local links = {}
    for to in pairs(nd.links or {}) do links[#links + 1] = to end
    out.nodes[id] = { nd.pos.x, nd.pos.y, nd.pos.z, nd.radius, links }
    n = n + 1
  end
  out.count = n
  pcall(jsonWriteFile, DIR .. S.cfg.name .. '/' .. st.label .. '.json', out, false)
  note('road graph dumped: ' .. n .. ' nodes')
end

local function body()
  for i, st in ipairs(S.cfg.steps) do
    S.step, S.op, S.phase = i, st.op, st.label or st.name or st.switch or st.op
    if st.op == 'spot' then S.skipUntilSpot = false end
    local f = OPS[st.op]
    if not f then error('unknown op ' .. tostring(st.op), 0) end
    f(st)
    writeProgress(true)
  end
end

------------------------------------------------------------------------------------------ the extension
local E = {}
function E.onUpdate()
  local t = ms()
  if lastT then frame(t - lastT) end
  lastT = t
  if S and S.co and not S.done then
    local ok, err = coroutine.resume(S.co)
    if not ok then
      S.err = tostring(err)
      note('ERROR: ' .. S.err)
      B.stop('error')
    elseif coroutine.status(S.co) == 'dead' then
      B.stop('finished')
    end
  end
  writeProgress(false)
end
pcall(extensions.unload, 'erBenchExt')
package.loaded['erBenchExt'] = E
extensions.load('erBenchExt')

function B.run(cfg)
  if type(cfg) == 'string' then cfg = jsonDecode(cfg) end
  if S and not S.done then return 'a suite is running' end
  for k, v in pairs(I) do if v == nil then return 'missing runner internal: ' .. k end end
  wrapHooks()
  S = { cfg = cfg, t0 = ms(), step = 0, captures = 0, log = {} }
  S.co = coroutine.create(body)
  FS:directoryCreate(DIR .. cfg.name, true)
  writeProgress(true)
  return 'running ' .. cfg.name .. ' (' .. #cfg.steps .. ' steps)'
end

function B.stop(why)
  if W then B._endCapture('stopped') end
  profStop()
  restoreSwitches()
  unwrapHooks()
  if S then
    S.done, S.why = true, why
    pcall(jsonWriteFile, DIR .. S.cfg.name .. '/suite-log.json', { why = why, err = S.err, log = S.log }, false)
    writeProgress(true)
  end
  return 'stopped: ' .. tostring(why)
end

local missing = {}
for k, v in pairs(I) do if v == nil then missing[#missing + 1] = k end end
return #missing == 0 and 'erBench loaded' or ('erBench loaded, MISSING internals: ' .. table.concat(missing, ','))
