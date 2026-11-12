-- earthRally/settings: the player's Earth Rally settings, as BeamNG.Earth keeps its own (beamngEarth/settings.lua): a
-- schema of defaults (1.1.0's behaviour, so a missing or broken file changes nothing), saved with jsonWriteFile in the
-- user folder's settings/ (FILE), read with jsonReadFile. The menu page (Vue) gets uiState() and calls set(), which
-- validates, saves and answers with every value. Not the game's own options list (settings.getValue).
local M = {}

M.FILE = '/settings/earthRally.json'
M.VERSION = 1

-- id -> { values (the allowed ones, the first is not special), default, label, desc, options = { {value, label}... } }
M.SCHEMA = {
  units = { default = 'km', label = 'Units', desc = 'Stage lengths and distances on the HUD',
    options = { { 'km', 'km' }, { 'mi', 'miles' } } },
  timeControls = { default = 'full', label = 'Time controls',
    desc = 'Check in at the time control and wait for your start time, or start on the line',
    options = { { 'full', 'Full' }, { 'quick', 'Quick start on the line' } } },
  resetPenalty = { default = true, label = 'Reset penalty',
    desc = '+10 s for each car reset during the timed stage', options = { { true, 'On' }, { false, 'Off' } } },
  zoneBrake = { default = true, label = 'Control-zone brake',
    desc = "The brakes ease on in a control's zone, so you stop at its board", options = { { true, 'On' }, { false, 'Off' } } },
  clockView = { default = 'right', label = 'Start clock view',
    desc = 'Where the close-up of the start clock shows during the countdown',
    options = { { 'right', 'Right' }, { 'top', 'Top' }, { 'off', 'Off' } } },
  devPanel = { default = false, label = 'Developer panel',
    desc = "The old Earth Rally window with each run's checks", options = { { true, 'On' }, { false, 'Off' } } },
}
M.ORDER = { 'units', 'timeControls', 'resetPenalty', 'zoneBrake', 'clockView', 'devPanel' }

local values = nil
local listeners = {}

local function defaults()
  local d = {}
  for k, s in pairs(M.SCHEMA) do d[k] = s.default end
  return d
end

-- A value for key, or nil and why.
function M.validate(key, v)
  local s = M.SCHEMA[key]
  if not s then return nil, 'unknown setting ' .. tostring(key) end
  for _, o in ipairs(s.options) do
    if o[1] == v then return v end
  end
  return nil, tostring(key) .. ': not one of its values (' .. tostring(v) .. ')'
end

-- Read the file: every valid known value taken, the rest left at its default. Returns the values and the warnings.
function M.load(path)
  values = defaults()
  local warnings = {}
  local read = rawget(_G, 'jsonReadFile')
  local fs = rawget(_G, 'FS')
  local ok, data = false, nil
  if read and (not (fs and fs.fileExists) or fs:fileExists(path or M.FILE)) then ok, data = pcall(read, path or M.FILE) end
  if ok and type(data) == 'table' then
    for k, v in pairs(data) do
      if k ~= 'version' then
        local val, err = M.validate(k, v)
        if val ~= nil then values[k] = val else warnings[#warnings + 1] = err end
      end
    end
  elseif ok and data ~= nil then
    warnings[#warnings + 1] = 'the settings file is not an object'
  elseif not ok and data ~= nil then
    warnings[#warnings + 1] = 'the settings file is unreadable: ' .. tostring(data)
  end
  local lg = rawget(_G, 'log')
  for _, w in ipairs(warnings) do if lg then lg('W', 'earthRally', 'settings: ' .. w) end end
  return values, warnings
end

function M.save(path)
  local write = rawget(_G, 'jsonWriteFile')
  if not (write and values) then return false end
  local out = { version = M.VERSION }
  for k, v in pairs(values) do out[k] = v end
  local ok, err = pcall(write, path or M.FILE, out, true)
  return ok and err ~= false
end

-- (read the file the first time any value is asked for)
local function vals()
  if not values then M.load() end
  return values
end

function M.get(key) return vals()[key] end

function M.all()
  local out = {}
  for k, v in pairs(vals()) do out[k] = v end
  return out
end

-- Change one: validated, saved, the listeners told. Returns { ok, settings, error }.
function M.set(key, v)
  local val, err = M.validate(key, v)
  if val == nil then return { ok = false, error = err, settings = M.all() } end
  local old = vals()[key]
  values[key] = val
  M.save()
  if old ~= val then
    for _, fn in pairs(listeners) do pcall(fn, key, val, old) end
  end
  return { ok = true, settings = M.all() }
end

-- fn(key, value, old) on each change (main.lua: the developer panel).
function M.onChange(name, fn) listeners[name] = fn end

-- Back to the defaults (tests; the file is not written).
function M.reset() values = defaults() end

-- For the menu page: the values and the schema in its order (labels, descriptions, options as { value, label }).
function M.uiState()
  local schema = {}
  for _, k in ipairs(M.ORDER) do
    local s = M.SCHEMA[k]
    local opts = {}
    for i, o in ipairs(s.options) do opts[i] = { value = o[1], label = o[2] } end
    schema[#schema + 1] = { id = k, label = s.label, desc = s.desc, default = s.default, options = opts }
  end
  return { settings = M.all(), schema = schema }
end

return M
