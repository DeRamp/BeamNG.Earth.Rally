-- earthRally/codriver: the game's own co-driver settings (BeamNG.drive 0.40.6 Options > Rally, and the voice it keeps in
-- rallyCodriverVoicepackMRU), shown on our settings page. Read and written in the game's settings, not our file, so a
-- change here shows in the game's Options too (one value, not two that disagree).
--
-- The game's voices come in pairs: one person has a casual pack (compositorStyle 'english/casual') and an enthusiast
-- one (shown here as Professional). A voice on our page is a person and accent; Style picks which of their packs. A
-- person with one pack has the other style greyed out. The pick goes to the front of the game's MRU list, which is
-- what its resolver reads (voicepack.addToMRU). Our notes are built for the voice picked when a run starts
-- (rallyAdapter.speaks), and the game takes a new voice at once, so Voice and Style are locked while a run is under
-- way (main.lua passes `locked`): a casual voice put in mid-run would be silent on the calls only the other can say.
local M = {}

M.VOICEPACK = '/lua/ge/extensions/gameplay/rally/voicepack'
M.TIMING_MIN, M.TIMING_MAX, M.TIMING_STEP = 0, 10, 0.1
M.KEYS = { timing = 'rallyCodriverTiming', audio = 'rallyAudioPacenotes', visual = 'rallyVisualPacenotes' }
M.STYLES = { { value = 'casual', label = 'Casual' }, { value = 'pro', label = 'Professional' } }
M.STYLE_DESC = { casual = 'Simple calls: corner number and direction',
  pro = 'Every call: corner shapes, crests, cautions and more' }

local function vp()
  local ok, m = pcall(require, M.VOICEPACK)
  if ok and type(m) == 'table' and type(m.listInventory) == 'function' and type(m.addToMRU) == 'function' then return m end
  return nil
end

local function gameSettings()
  local s = rawget(_G, 'settings')
  if type(s) == 'table' and type(s.getValue) == 'function' and type(s.setValue) == 'function' then return s end
  return nil
end

-- 'casual' or 'pro' for a pack.
function M.styleOf(entry)
  local st = type(entry) == 'table' and entry.compositorStyle or nil
  if type(st) == 'string' and st:match('casual$') then return 'casual' end
  return 'pro'
end

-- The accent from the pack's dialect key ('ui.options.rally.dialects.en-GB.name' -> 'UK'), or nil.
function M.accentOf(entry)
  local d = type(entry) == 'table' and entry.dialect or nil
  if type(d) ~= 'string' then return nil end
  local region = d:match('%a%a%-(%a%a)')
  if not region then return nil end
  region = region:upper()
  return region == 'GB' and 'UK' or region
end

-- A voice's key: person, accent and language (an add-on in another language is its own voice).
function M.keyOf(entry)
  return tostring(entry.persona) .. '|' .. tostring(M.accentOf(entry) or '') .. '|' .. tostring(entry.language or '')
end

-- One voice per person and accent: { key, label, packs = { casual = entry, pro = entry } }, in the game's order.
function M.voices(entries)
  local out, byKey = {}, {}
  for _, e in ipairs(entries or {}) do
    if type(e) == 'table' and e.persona then
      local accent = M.accentOf(e)
      local key = M.keyOf(e)
      local v = byKey[key]
      if not v then
        v = { key = key, label = accent and (e.persona .. ' (' .. accent .. ')') or e.persona, packs = {} }
        byKey[key] = v
        out[#out + 1] = v
      end
      local style = M.styleOf(e)
      if not v.packs[style] then v.packs[style] = e end
    end
  end
  return out
end

local function inventory(m)
  local ok, list = pcall(m.listInventory, nil, { globalOnly = true })
  return ok and type(list) == 'table' and list or {}
end

-- (an empty MRU list is what a new profile has: the game puts its default voice in it on its first rally load, so
--  it is put there first here too, or the resolver would show its fallback, a casual pack, until then)
local function current(m)
  if type(m.ensureSettingsInitialized) == 'function' then pcall(m.ensureSettingsInitialized, {}) end
  local ok, _, entry = pcall(m.resolveEffectiveEntry, nil, nil, { globalOnly = true, writeSettings = false })
  return ok and type(entry) == 'table' and entry or nil
end

-- The timing kept to the slider's range and step.
function M.clampTiming(v)
  v = tonumber(v)
  if not v or v ~= v then return nil end
  v = math.max(M.TIMING_MIN, math.min(M.TIMING_MAX, v))
  return tonumber(string.format('%.1f', math.floor(v / M.TIMING_STEP + 0.5) * M.TIMING_STEP))
end

-- For the settings page: nil when the game's co-driver is not there (another game version).
function M.uiState(locked)
  local m, s = vp(), gameSettings()
  if not (m and s) then return nil end
  local voices = M.voices(inventory(m))
  local cur = current(m)
  local curKey, curStyle
  if cur then
    curKey = M.keyOf(cur)
    curStyle = M.styleOf(cur)
  end
  local uiVoices, styles = {}, {}
  local has = {}
  for i, v in ipairs(voices) do
    uiVoices[i] = { value = v.key, label = v.label }
    if v.key == curKey then has = v.packs end
  end
  for i, st in ipairs(M.STYLES) do
    styles[i] = { value = st.value, label = st.label, has = has[st.value] ~= nil }
  end
  return {
    locked = locked and true or nil, voices = uiVoices, voice = curKey, styles = styles, style = curStyle,
    styleDesc = curStyle and M.STYLE_DESC[curStyle] or nil,
    timing = M.clampTiming(s.getValue(M.KEYS.timing)) or 3.0,
    timingMin = M.TIMING_MIN, timingMax = M.TIMING_MAX, timingStep = M.TIMING_STEP,
    audio = s.getValue(M.KEYS.audio) ~= false, visual = s.getValue(M.KEYS.visual) ~= false,
  }
end

-- Change one: 'voice' (a voice key; keeps the style if that person has it), 'style' ('casual' | 'pro'), 'timing'
-- (seconds), 'audio' / 'visual' (booleans). Returns { ok, codriver, error }.
function M.set(key, value, locked)
  local m, s = vp(), gameSettings()
  if not (m and s) then return { ok = false, error = 'no co-driver in this game version' } end
  local function fail(why) return { ok = false, error = why, codriver = M.uiState(locked) } end
  if key == 'timing' then
    local v = M.clampTiming(value)
    if not v then return fail('timing: not a number') end
    s.setValue(M.KEYS.timing, v)
  elseif key == 'audio' or key == 'visual' then
    if type(value) ~= 'boolean' then return fail(key .. ': not on or off') end
    s.setValue(M.KEYS[key], value)
  elseif (key == 'voice' or key == 'style') and locked then
    return fail(key .. ': not during a run')
  elseif key == 'voice' or key == 'style' then
    local voices = M.voices(inventory(m))
    local cur = current(m)
    local curStyle = cur and M.styleOf(cur) or 'pro'
    local curKey = cur and M.keyOf(cur) or nil
    local wantKey = key == 'voice' and value or curKey
    local wantStyle = key == 'style' and value or curStyle
    local voice
    for _, v in ipairs(voices) do if v.key == wantKey then voice = v end end
    if not voice then return fail('voice: not installed (' .. tostring(wantKey) .. ')') end
    local pack = voice.packs[wantStyle]
    if not pack then
      if key == 'style' then return fail('style: this voice has no ' .. tostring(wantStyle) .. ' pack') end
      pack = voice.packs.pro or voice.packs.casual      -- a new voice without the style in use: the one it has
    end
    local ok, err = pcall(m.addToMRU, pack)
    if not ok then return fail('voice: ' .. tostring(err)) end
  else
    return fail('unknown co-driver setting ' .. tostring(key))
  end
  return { ok = true, codriver = M.uiState(locked) }
end

return M
