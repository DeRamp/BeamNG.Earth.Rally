-- codriver: the game's co-driver settings on our settings page -- voices grouped by person and accent, Casual /
-- Professional picking the person's pack, the timing slider's range, spoken and on-screen calls.
local T = dofile(TESTS .. '/testlib.lua')
function log() end

-- the game's settings and voice packs, as 0.40.6 ships them (Clover is hidden by the game: enableAnimalCodrivers)
local store = { rallyCodriverTiming = 3.0, rallyAudioPacenotes = true, rallyVisualPacenotes = true }
settings = { getValue = function(k) return store[k] end, setValue = function(k, v) store[k] = v end }
local function pack(dir, persona, dialect, style)
  return { id = 'global:' .. dir, scope = 'global', dirname = dir, language = 'en', persona = persona,
    dialect = 'ui.options.rally.dialects.' .. dialect .. '.name', compositorStyle = 'english/' .. style }
end
local packs = {
  pack('ak_e', 'Alex Kihurani', 'en-US', 'enthusiast'), pack('ak_c', 'Alex Kihurani', 'en-US', 'casual'),
  pack('dw_e', 'dirtwheel', 'en-US', 'enthusiast'), pack('dw_c', 'dirtwheel', 'en-US', 'casual'),
  pack('rh_e', 'HighDef', 'en-GB', 'enthusiast'), pack('rh_c', 'HighDef', 'en-GB', 'casual'),
  { id = 'global:mine', scope = 'global', dirname = 'mine', language = 'en', persona = 'Yen', compositorStyle = 'english/casual' },
}
local mru = {}
package.loaded['/lua/ge/extensions/gameplay/rally/voicepack'] = {
  listInventory = function() return packs end,
  resolveEffectiveEntry = function()
    for _, p in ipairs(packs) do if p.id == mru[1] then return p.dirname, p end end
  end,
  addToMRU = function(e) table.insert(mru, 1, e.id) end,
  -- the game's default voice into an empty list; its resolver falls back to a casual pack without it
  ensureSettingsInitialized = function() if #mru == 0 then mru[1] = 'global:ak_e' end end,
}

local cd = require('earthRally/codriver')

local ui = cd.uiState()
T.check(#ui.voices == 4, 'one voice per person and accent (4, not 7 packs)')
T.check(ui.voices[1].label == 'Alex Kihurani (US)' and ui.voices[3].label == 'HighDef (UK)', 'accent shown, GB as UK')
T.check(ui.voices[4].label == 'Yen', 'no dialect: the name alone')
T.check(ui.voice == 'Alex Kihurani|US|en' and ui.style == 'pro', "a new profile: the game's default voice shown (Professional)")
T.check(ui.styles[1].has and ui.styles[2].has, 'Alex has both styles')
T.check(ui.timing == 3.0 and ui.timingMin == 0 and ui.timingMax == 10 and ui.timingStep == 0.1, 'timing 0 to 10 s in 0.1')

T.check(cd.set('style', 'casual').ok and mru[1] == 'global:ak_c', 'Casual picks the same person\'s casual pack')
T.check(cd.set('voice', 'HighDef|UK|en').ok and mru[1] == 'global:rh_c', 'a new voice keeps the style in use')
T.check(cd.set('style', 'pro').ok and mru[1] == 'global:rh_e', 'Professional: the enthusiast pack')
local r = cd.set('voice', 'Yen||en')
T.check(r.ok and mru[1] == 'global:mine', 'a voice without the style in use: the pack it has')
T.check(not r.codriver.styles[2].has and r.codriver.style == 'casual', 'Professional greyed out for a casual-only voice')
T.check(not cd.set('style', 'pro').ok and mru[1] == 'global:mine', 'a style the voice has no pack for is refused')
T.check(not cd.set('voice', 'Nobody||en').ok, 'a voice not installed is refused')

T.check(cd.set('timing', 4.26).ok and store.rallyCodriverTiming == 4.3, 'timing kept to 0.1 s')
cd.set('timing', 12); T.check(store.rallyCodriverTiming == 10, 'timing at most 10 s')
cd.set('timing', -1); T.check(store.rallyCodriverTiming == 0, 'timing at least 0 s')
T.check(not cd.set('timing', 'x').ok and store.rallyCodriverTiming == 0, 'timing: not a number refused')
T.check(cd.set('audio', false).ok and store.rallyAudioPacenotes == false, 'spoken calls off')
T.check(cd.set('visual', false).ok and cd.uiState().visual == false, 'calls on screen off')
T.check(not cd.set('audio', 'no').ok and store.rallyAudioPacenotes == false, 'on/off must be a boolean')
T.check(not cd.set('countdown', '3d').ok, 'settings that are not the co-driver\'s are refused')

-- during a run: voice and style locked (the run's notes were built for the voice it started with), the rest not
local was = mru[1]
local lr = cd.set('voice', 'Alex Kihurani|US|en', true)
T.check(not lr.ok and mru[1] == was and lr.codriver.locked, 'voice locked during a run')
T.check(not cd.set('style', 'casual', true).ok and mru[1] == was, 'style locked during a run')
T.check(cd.set('timing', 2.5, true).ok and store.rallyCodriverTiming == 2.5, 'timing still changes during a run')
T.check(cd.uiState().locked == nil, 'not locked between runs')

-- another game version, no co-driver: nothing shown
package.loaded['/lua/ge/extensions/gameplay/rally/voicepack'] = false
T.check(cd.uiState() == nil and not cd.set('timing', 3).ok, 'no co-driver: no column, set refused')

T.done('test_codriver')
