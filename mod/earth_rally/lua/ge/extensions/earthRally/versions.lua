-- earthRally/versions: what Earth Rally was built against, and whether this machine still matches it. Checked at
-- startup and once more when BeamNG.Earth turns up (it may load after us), said in the log and on the Rallies page.
--
-- Roadmap item 23, and the reason it is first in 1.3.2: this mod reaches into two projects that move on their own
-- release schedules, and when one of them changes under it the symptom a player meets is a stage that behaves
-- oddly, not a message. One clear line naming the version that changed is worth more than any amount of guessing,
-- and it costs nothing to carry.
--
-- Three surfaces, each checked differently because each fails differently:
--
--   BeamNG.drive        a version string, and the rally engine's own shape. The STRING is a warning and the SHAPE
--                       is the gate. A mod built on 0.40.5 usually survives 0.40.6, so a different version is
--                       said once and nothing is refused; a rally engine that no longer looks like the one
--                       stageWriter writes for IS refused, because then a stage loads wrongly rather than not at
--                       all, and a wrong driveline means wrong pacenotes called at speed.
--   BeamNG.Earth's API  a major and a minor it publishes (api.version). Older than MIN_API_MINOR is refused with
--                       the figures; a different MAJOR is refused as a different API, not as an old one; NEWER
--                       than the newest minor we know is said and not refused, because the project has only ever
--                       added calls.
--   its internals       the handful of things BeamNG.Earth has no API for (earthAdapter, "internals (no API
--                       yet)"). They are not in the versioned surface at all, so a rename need not bump any
--                       number: the name going missing is the only signal there is. Each is named with what stops
--                       working, because "Earth Rally is broken" is not something a player can act on.
--
-- M.findings is pure and takes everything it judges, so the whole table of outcomes is tested offline
-- (tests/test_versions.lua) rather than only on the one machine that happens to be in front of us.
local M = {}

local logTag = 'earthRally'

-- The BeamNG.drive this was built and driven on. Bump it when the mod has actually been run on a new one.
M.GAME_BUILT = '0.40.5'

------------------------------------------------------------------------------------------ pure

-- '0.40.5.0' -> { 0, 40, 5 }: the first three numbers, which is as far as BeamNG's own version means anything to
-- us (the fourth moves with hotfixes that have never touched the Lua we use).
function M.parse(s)
  if type(s) ~= 'string' then return nil end
  local out = {}
  for n in s:gmatch('%d+') do
    out[#out + 1] = tonumber(n)
    if #out == 3 then break end
  end
  if #out == 0 then return nil end
  return out
end

-- -1, 0 or 1 comparing two parsed versions (a missing part counts as 0).
function M.compare(a, b)
  for i = 1, 3 do
    local x, y = a[i] or 0, b[i] or 0
    if x < y then return -1 elseif x > y then return 1 end
  end
  return 0
end

-- Everything judged, in one go: a list of { level = 'error' | 'warn', id, text }, worst first within each kind.
--
-- env = {
--   game      = the game's version string, or nil when it does not say
--   rally     = { ok = bool, why = string }      the game's rally engine (rallyAdapter.check)
--   earth     = { major, minor } or nil          nil: BeamNG.Earth not loaded, so nothing is said about it yet
--   internals = { { id, what, ok, why } ... } or nil
--   minMinor, knownMinor = BeamNG.Earth's API minors Earth Rally needs and knows
-- }
--
-- An 'error' is something a stage will not survive; a 'warn' is something to know before reporting a bug. Nothing
-- here stops the mod loading: the mod refusing to run is the one outcome that is always worse than the mod
-- running with a warning on its front page, because a player with a warning can still drive and can still say
-- what it said.
function M.findings(env)
  local out = {}
  local function add(level, id, text) out[#out + 1] = { level = level, id = id, text = text } end

  -- 1. the game's rally engine: the gate, and the only one of these that is about behaviour rather than a number
  local rally = env.rally
  if rally and rally.ok == false then
    add('error', 'rallyEngine', (rally.why or "this BeamNG.drive's rally engine is not the one Earth Rally knows")
      .. '. The co-driver and the stage line come from it, so a stage cannot be loaded.')
  end

  -- 2. the game's version: said, never refused
  local built = M.parse(M.GAME_BUILT)
  local here = M.parse(env.game)
  if not here then
    add('warn', 'gameVersion', string.format(
      'This BeamNG.drive does not say which version it is; Earth Rally was built on %s.', M.GAME_BUILT))
  elseif M.compare(here, built) ~= 0 then
    local which = M.compare(here, built) > 0 and 'newer than' or 'older than'
    -- what the rally engine says about it, where it has been looked at: a version difference that broke nothing
    -- is worth knowing and not worth chasing, and saying so is the difference between a note and a worry
    local tail = ''
    if rally and rally.ok == false then tail = ' Its rally engine has changed with it (above).'
    elseif rally then tail = ' Its rally engine still looks the same, so this is worth knowing rather than fixing.'
    end
    add('warn', 'gameVersion', string.format('This is BeamNG.drive %s, %s the %s Earth Rally was built and driven on.%s',
      env.game, which, M.GAME_BUILT, tail))
  end

  -- 3. BeamNG.Earth's published API
  local e = env.earth
  local minMinor = env.minMinor or 6
  local knownMinor = env.knownMinor or minMinor
  if e then
    local major, minor = e.major, e.minor
    if major ~= 1 then
      add('error', 'earthMajor', string.format(
        "This BeamNG.Earth's modding API is %s.%s. Earth Rally is built for 1.x, and a new major means calls it "
        .. 'uses have changed or gone: it needs an Earth Rally built for %s.',
        tostring(major), tostring(minor), tostring(major)))
    elseif (minor or 0) < minMinor then
      add('error', 'earthMinor', string.format(
        "This BeamNG.Earth's modding API is 1.%s. Earth Rally needs 1.%d or newer: update BeamNG.Earth.",
        tostring(minor), minMinor))
    elseif (minor or 0) > knownMinor then
      add('warn', 'earthNewer', string.format(
        "This BeamNG.Earth's modding API is 1.%s, newer than the 1.%d Earth Rally was built on. Nothing is "
        .. 'refused -- it has only ever added calls -- but new ones are not used yet.',
        tostring(minor), knownMinor))
    end
  end

  -- 4. its internals, each by name
  for _, it in ipairs(env.internals or {}) do
    if it.ok == false then
      add('warn', 'internal:' .. tostring(it.id), string.format(
        'This BeamNG.Earth no longer has %s, which Earth Rally uses: %s. It is not part of the modding API, so '
        .. 'its version does not mention it.', tostring(it.what), tostring(it.why)))
    end
  end

  -- 5. Earth Rally loaded twice: an old earth_rally-*.zip dragged into mods/ and the Add-ons page's copy (1.8.0)
  local twice = M.copiesNote(env.modZips)
  if twice then add('error', 'twoCopies', twice) end

  table.sort(out, function(a, b)
    if (a.level == 'error') ~= (b.level == 'error') then return a.level == 'error' end
    return false      -- (a stable sort is not promised, so only the two kinds are ordered)
  end)
  return out
end

-- The one-line summary that goes in the log on every start, whatever the findings are: the three versions, so a
-- log a player sends in says what they were running without anyone having to ask.
function M.summary(env)
  local e = env.earth
  return string.format('versions: Earth Rally %s on BeamNG.drive %s (built for %s), BeamNG.Earth API %s',
    tostring(env.mod), tostring(env.game or '?'), M.GAME_BUILT,
    e and string.format('%s.%s', tostring(e.major), tostring(e.minor)) or 'not loaded')
end

------------------------------------------------------------------------------------------ two copies of the mod

-- The file BeamNG.Earth's Add-ons page installs Earth Rally as (its id for DeRamp/BeamNG.Earth.Rally, .zip).
M.ADDON_ZIP = 'beamng-earth-rally.zip'
M.MODS_DIR = '%LOCALAPPDATA%\\BeamNG\\BeamNG.drive\\current\\mods\\'

-- Whether a mod zip's file name is an Earth Rally copy: the release zips (earth_rally-1.7.3-alpha.zip, renamed
-- ones like earth_rally (1).zip) and the Add-ons page's.
function M.isEarthRallyZip(name)
  local n = tostring(name or ''):lower()
  if not n:match('%.zip$') then return false end
  return n == M.ADDON_ZIP or n:match('^earth[_%- ]?rally') ~= nil
end

-- The player's message when more than one Earth Rally zip is loaded, or nil. zips: their file names. The Add-ons
-- page's copy is the one to keep (it updates itself); without it, the player keeps one of their choice.
function M.copiesNote(zips)
  local ours = {}
  for _, z in ipairs(zips or {}) do if M.isEarthRallyZip(z) then ours[#ours + 1] = z end end
  if #ours < 2 then return nil end
  table.sort(ours)
  local others, addon = {}, false
  for _, z in ipairs(ours) do
    if z:lower() == M.ADDON_ZIP then addon = true else others[#others + 1] = z end
  end
  if addon then
    return string.format('Earth Rally is installed twice. Close the game, delete %s from %s and start again. '
      .. "BeamNG.Earth's Add-ons page keeps %s up to date.", table.concat(others, ', '), M.MODS_DIR, M.ADDON_ZIP)
  end
  return string.format('Earth Rally is installed %d times (%s). Close the game, keep one, delete the others from '
    .. '%s and start again.', #ours, table.concat(ours, ', '), M.MODS_DIR)
end

-- The file names of the active mod zips Earth Rally could be in, from the game's mod manager (an inactive mod is not
-- loaded, so it is not a second copy). {} when the mod manager cannot say.
-- An unpacked copy (a developer's mods/unpacked/ folder) is not a zip and is not counted: accepted, players do not have one.
function M.modZips()
  local out = {}
  local mm = rawget(_G, 'core_modmanager')
  if not (mm and mm.getMods) then return out end
  local ok, mods = pcall(mm.getMods)
  if not ok or type(mods) ~= 'table' then return out end
  for _, m in pairs(mods) do
    local full = type(m) == 'table' and tostring(m.fullpath or '') or ''
    if m.active ~= false and full:lower():match('%.zip$') then
      local name = full:match('([^/\\]+)$')
      if name and M.isEarthRallyZip(name) then out[#out + 1] = name end
    end
  end
  table.sort(out)
  return out
end

------------------------------------------------------------------------------------------ the live machine

local earth = require('earthRally/earthAdapter')
local rallyA = require('earthRally/rallyAdapter')

-- What this machine is, gathered for M.findings. `modVersion` is passed in rather than required, so this module
-- does not depend on main.lua (which requires it).
function M.env(modVersion)
  local major, minor = earth.apiVersion()
  -- The game's rally engine is only looked at once the BeamNG.Earth LEVEL is loaded. Not squeamishness:
  -- rallyAdapter.check() LOADS `gameplay_rally` if it is not loaded, and doing that at the main menu pulls the
  -- game's rally engine in before there is a level for it, every start, for a check whose answer is wanted before
  -- a stage rather than before the menu.
  --
  -- The first cut of this gated on BeamNG.Earth's API answering at all, which is wrong and the game said so
  -- within a second of starting: the API is there from the main menu on, so the check still loaded the engine and
  -- `onExtensionLoaded earthRally_main` went from about 2 ms to 70, which BeamNG itself flags as
  -- "quite slow and should be optimized". `earth.inWorld()` is the question that was meant.
  local rally = nil
  if earth.inWorld() then
    local rok, rwhy = rallyA.check()
    rally = { ok = rok and true or false, why = rwhy }
  end
  return {
    mod = modVersion,
    game = rawget(_G, 'beamng_version'),
    rally = rally,
    earth = major and { major = major, minor = minor } or nil,
    internals = earth.internals(),
    modZips = M.modZips(),
    minMinor = earth.MIN_API_MINOR,
    knownMinor = earth.KNOWN_API_MINOR,
  }
end

local said = nil          -- the findings as they were last logged (so a re-check is quiet unless it changed)
local current = {}

-- Check and log. Called at startup and again when BeamNG.Earth appears; quiet when nothing has changed since the
-- last time, because the second call is the normal case and a repeated block of warnings in the log is noise that
-- teaches a player to skip the log.
function M.check(modVersion)
  local env = M.env(modVersion)
  local found = M.findings(env)
  current = found
  local key = M.summary(env)
  for _, f in ipairs(found) do key = key .. '|' .. f.id end
  if key == said then return found end
  said = key
  log('I', logTag, M.summary(env))
  for _, f in ipairs(found) do
    log(f.level == 'error' and 'E' or 'W', logTag, f.text)
  end
  return found
end

-- The findings as they stand, for the page and the developer panel.
function M.current() return current end

-- Only what a player should see on the Rallies page: the texts, errors first. Empty when all is well, which is
-- the normal case and shows nothing.
function M.notes()
  local out = {}
  for _, f in ipairs(current) do out[#out + 1] = f.text end
  return out
end

function M.reset() said, current = nil, {} end

return M
