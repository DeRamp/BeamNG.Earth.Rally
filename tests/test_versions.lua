-- versions.lua: what the startup check says about a machine that has moved on from the one Earth Rally was built
-- on. M.findings is pure and takes everything it judges, so every outcome is driven here rather than only the one
-- this PC happens to be in.
local T = dofile(TESTS .. '/testlib.lua')

local logged = {}
function log(level, _, msg) logged[#logged + 1] = { level = level, msg = tostring(msg) } end

local versions = require('earthRally/versions')

------------------------------------------------------------------------------------------ parse and compare

T.check(versions.parse('0.40.5.0')[2] == 40, 'parse: the minor')
T.check(#versions.parse('0.40.5.0') == 3, 'parse: three numbers, the hotfix part dropped')
T.check(versions.parse('0.41') ~= nil and #versions.parse('0.41') == 2, 'parse: a two-part version')
T.check(versions.parse(nil) == nil and versions.parse('') == nil and versions.parse(42) == nil,
  'parse: nothing out of nothing')
T.check(versions.parse('v0.40.5-hotfix')[1] == 0, 'parse: numbers out of a decorated string')

T.check(versions.compare({ 0, 40, 5 }, { 0, 40, 5 }) == 0, 'compare: the same')
T.check(versions.compare({ 0, 41, 0 }, { 0, 40, 5 }) == 1, 'compare: a newer minor')
T.check(versions.compare({ 0, 40, 4 }, { 0, 40, 5 }) == -1, 'compare: an older patch')
T.check(versions.compare({ 0, 40 }, { 0, 40, 0 }) == 0, 'compare: a missing part counts as zero')
T.check(versions.compare({ 1, 0, 0 }, { 0, 99, 99 }) == 1, 'compare: the major wins')

------------------------------------------------------------------------------------------ the findings

local function find(found, id)
  for _, f in ipairs(found) do if f.id == id then return f end end
end
local function ids(found)
  local out = {}
  for _, f in ipairs(found) do out[#out + 1] = f.id end
  return table.concat(out, ',')
end

-- the machine the mod was built on, with everything present: nothing to say
local GOOD = {
  mod = '1.3.2-alpha',
  game = versions.GAME_BUILT .. '.0',
  rally = { ok = true },
  earth = { major = 1, minor = 9 },
  internals = { { id = 'rebaseTo', what = 'core.rebaseTo', ok = true, why = 'x' } },
  minMinor = 6, knownMinor = 9,
}
-- GOOD with fields changed. NIL removes one: `env({ game = nil })` cannot, because pairs() never sees a nil
-- value, and an override that silently does nothing makes the assertion after it vacuous -- which is exactly what
-- happened to the "BeamNG.Earth not loaded" check below the first time it was written.
local NIL = {}
local function env(over)
  local e = {}
  for k, v in pairs(GOOD) do e[k] = v end
  for k, v in pairs(over or {}) do e[k] = (v ~= NIL) and v or nil end
  return e
end
T.check(env({ game = NIL }).game == nil and env({}).game == GOOD.game, 'the fixture can take a field away')

T.check(#versions.findings(GOOD) == 0, 'the machine it was built on: nothing said (' .. ids(versions.findings(GOOD)) .. ')')

-- 1. the game's rally engine is the gate
do
  local f = versions.findings(env({ rally = { ok = false, why = "this BeamNG.drive's rally engine is not the one Earth Rally knows (0.40.5)" } }))
  local r = find(f, 'rallyEngine')
  T.check(r and r.level == 'error', 'a changed rally engine is an error')
  T.check(r and r.text:find('rally engine is not the one') ~= nil, "the adapter's own words are kept")
  T.check(r and r.text:find('stage cannot be loaded') ~= nil, 'and what it costs is said')
end

-- 2. the game's version is said, never refused
do
  local f = versions.findings(env({ game = '0.41.0.0' }))
  local g = find(f, 'gameVersion')
  T.check(g and g.level == 'warn', 'a newer BeamNG.drive is a warning, not an error')
  T.check(g and g.text:find('0.41.0.0') and g.text:find(versions.GAME_BUILT), 'both versions named')
  T.check(g and g.text:find('newer than') ~= nil, 'and which way round it is')
  T.check(g and g.text:find('still looks the same') ~= nil,
    'a version difference with a working rally engine says so, so it is not chased')
  T.check(find(f, 'rallyEngine') == nil, 'nothing refused for the version alone')

  local older = find(versions.findings(env({ game = '0.39.0.0' })), 'gameVersion')
  T.check(older and older.text:find('older than') ~= nil, 'an older BeamNG.drive reads the other way')

  -- the two together: the version difference stops guessing and points at the engine finding
  local both = versions.findings(env({ game = '0.41.0.0', rally = { ok = false, why = 'changed' } }))
  local bg = find(both, 'gameVersion')
  T.check(bg and bg.text:find('changed with it') ~= nil, 'a version difference that DID break the engine says so')
  T.check(both[1].level == 'error', 'the error comes first (' .. both[1].id .. ')')

  -- the startup pass, before BeamNG.Earth is up: the rally engine has not been looked at (looking would load the
  -- game's rally extension from the main menu), so the version note must not claim anything about it either way
  local early = find(versions.findings(env({ game = '0.41.0.0', rally = NIL })), 'gameVersion')
  T.check(early and early.text:find('still looks the same') == nil and early.text:find('changed with it') == nil,
    'the rally engine not yet looked at: the version note says nothing about it (' .. tostring(early and early.text) .. ')')
  T.check(early and early.text:find('0%.41') ~= nil, '... but still names the version')
  T.check(#versions.findings(env({ rally = NIL })) == 0, 'and a matching version with no engine check says nothing at all')

  local none = find(versions.findings(env({ game = NIL })), 'gameVersion')
  T.check(none and none.level == 'warn' and none.text:find('does not say') ~= nil,
    'a game that does not say its version is a warning of its own')
end

-- 3. BeamNG.Earth's published API
do
  local old = find(versions.findings(env({ earth = { major = 1, minor = 5 } })), 'earthMinor')
  T.check(old and old.level == 'error', 'an API older than the minimum is an error')
  T.check(old and old.text:find('1.5') and old.text:find('1.6') and old.text:find('update BeamNG.Earth'),
    'with both figures and what to do (' .. tostring(old and old.text) .. ')')

  -- the one this check exists to get right: a NEW major must not be called old
  local maj = find(versions.findings(env({ earth = { major = 2, minor = 0 } })), 'earthMajor')
  T.check(maj and maj.level == 'error', 'a different major is an error')
  T.check(maj and maj.text:find('too old') == nil, 'a NEWER major is never called "too old"')
  T.check(maj and maj.text:find('built for 1%.x') ~= nil, 'it says which major Earth Rally is for')
  T.check(find(versions.findings(env({ earth = { major = 2, minor = 0 } })), 'earthMinor') == nil,
    'and the minor is not judged against a major we do not know')

  local new = find(versions.findings(env({ earth = { major = 1, minor = 12 } })), 'earthNewer')
  T.check(new and new.level == 'warn', 'a newer minor is a warning, not an error')
  T.check(new and new.text:find('1.12') and new.text:find('1.9'), 'with both minors')
  T.check(new and new.text:find('Nothing is refused') ~= nil, 'and that nothing is refused')

  T.check(#versions.findings(env({ earth = { major = 1, minor = 6 } })) == 0,
    'the minimum itself is fine, not a warning')

  -- BeamNG.Earth not loaded yet is not a version problem: the startup check must be silent about it
  local pending = versions.findings(env({ earth = NIL, internals = NIL }))
  T.check(#pending == 0, 'BeamNG.Earth not loaded: nothing said about its version (' .. ids(pending) .. ')')
end

-- 4. the internals it has no API for, each by name
do
  local f = versions.findings(env({ internals = {
    { id = 'hudApp', what = 'core.hudApp', ok = false, why = 'its strips stay on screen' },
    { id = 'rebaseTo', what = 'core.rebaseTo', ok = true, why = 'x' },
    { id = 'camshift', what = 'beamngEarth/camshift.RADIUS_MIN', ok = false, why = 'the camera is left behind' },
  } }))
  T.check(#f == 2, 'one finding per missing internal, none for those present (' .. ids(f) .. ')')
  local h = find(f, 'internal:hudApp')
  T.check(h and h.level == 'warn', 'a missing internal is a warning: a stage still runs')
  T.check(h and h.text:find('core%.hudApp') ~= nil, 'named by the name that went missing')
  T.check(h and h.text:find('its strips stay on screen') ~= nil, 'with what stops working')
  T.check(h and h.text:find('version does not mention it') ~= nil,
    'and why no version number would have caught it')
end

------------------------------------------------------------------------------------------ the log line

do
  local s = versions.summary(GOOD)
  T.check(s:find('1%.3%.2%-alpha') and s:find(versions.GAME_BUILT) and s:find('1%.9'),
    'the summary carries all three versions (' .. s .. ')')
  T.check(versions.summary(env({ earth = NIL })):find('not loaded') ~= nil,
    'and says so when BeamNG.Earth is not there')
end

-- check() logs the summary and one line per finding, and is quiet the second time: the check runs again when
-- BeamNG.Earth turns up, and a repeated block of warnings teaches a player to skip the log
do
  versions.reset()
  logged = {}
  local real = versions.env
  versions.env = function(modVersion) return env({ mod = modVersion, rally = { ok = false, why = 'changed' } }) end
  local f = versions.check('1.3.2-alpha')
  T.check(#f == 1 and f[1].level == 'error', 'check() returns what it found')
  T.check(#logged == 2 and logged[1].level == 'I' and logged[2].level == 'E',
    'the summary at I, the error at E (' .. #logged .. ' lines)')
  logged = {}
  versions.check('1.3.2-alpha')
  T.check(#logged == 0, 'the same findings again: nothing logged (' .. #logged .. ')')
  versions.env = function(modVersion) return env({ mod = modVersion }) end
  logged = {}
  versions.check('1.3.2-alpha')
  T.check(#logged == 1, 'findings that changed are logged again (' .. #logged .. ')')
  T.check(#versions.current() == 0 and #versions.notes() == 0, 'and the page is given the new, empty list')
  versions.env = real
end

-- notes() is what the page shows: the texts, errors first
do
  local realEnv = versions.env
  versions.reset()
  versions.env = function() return env({ rally = { ok = false, why = 'the rally engine changed' }, game = '0.41.0.0' }) end
  versions.check('1.3.2-alpha')
  versions.env = realEnv       -- (put back before the block below, which drives the real one)
  local n = versions.notes()
  T.check(#n == 2 and n[1]:find('rally engine') ~= nil and n[2]:find('0%.41') ~= nil,
    'notes(): the error first, the version warning after (' .. #n .. ')')
  T.check(type(n[1]) == 'string' and type(n[2]) == 'string', 'notes(): plain strings for the page')
end

------------------------------------------------------------------------------------------ env: what it asks, when

-- The game caught this one within a second of starting, and it is worth a test of its own: looking at the game's
-- rally engine LOADS `gameplay_rally` (68 ms), so the startup check must not do it at the main menu -- only once
-- the BeamNG.Earth level is loaded. The first cut gated on BeamNG.Earth's API answering, which is true from the
-- main menu on, and `onExtensionLoaded earthRally_main` went from about 2 ms to 70.
do
  local rallyLoads, inWorld = 0, false
  extensions = { load = function(n) if n == 'gameplay_rally' then rallyLoads = rallyLoads + 1 end end }
  beamngEarth_api = {
    version = function() return 1, 9 end,
    inWorld = function() return inWorld end,
    has = function() return false end,
    ready = function() return true end,
  }

  local e1 = versions.env('1.3.2-alpha')
  T.check(e1.rally == nil, 'at the main menu: the rally engine is not looked at')
  T.check(rallyLoads == 0, '... so nothing pulls it in (' .. rallyLoads .. ' load(s))')
  T.check(e1.earth and e1.earth.minor == 9, "but BeamNG.Earth's own version is read there")
  T.check(#versions.findings(e1) > 0, 'and its internals are judged (' .. #versions.findings(e1) .. ' finding(s))')

  inWorld = true
  local e2 = versions.env('1.3.2-alpha')
  T.check(e2.rally ~= nil, 'in the BeamNG.Earth level: the rally engine IS looked at')
  T.check(rallyLoads == 1, '... and that is where it is pulled in (' .. rallyLoads .. ' load(s))')
  T.check(e2.rally.ok == false and tostring(e2.rally.why):find('rally engine') ~= nil,
    "with the adapter's own answer (" .. tostring(e2.rally.why) .. ')')

  beamngEarth_api, extensions = nil, nil
end

T.done('test_versions.lua')
