// Earth Rally's menu: the state shared by its page (EarthRally.vue, a route of its own) and its pause-menu cards
// (EarthRallyTab.vue, EarthRallySettings.vue, EarthRallySide.vue). Lua side: lua/ge/extensions/earthRally/main.lua
// (uiState, uiRally, uiStage, uiAction, uiSet), as BeamNG.Earth's settings pages talk to its settings.lua.
import { ref } from "vue"

export const state = ref({})          // earthRally_main.uiState(): rallies, settings, the run, the recce, ...
export const rally = ref(null)        // earthRally_main.uiRally(id)
export const stage = ref(null)        // earthRally_main.uiStage(eventId, stageId)
export const busyMsg = ref("")        // the last button's answer

export function engineLua(script, cb) {
  if (!window.bngApi || !window.bngApi.engineLua) return
  window.bngApi.engineLua(script, cb)
}
const q = v => JSON.stringify(v === undefined || v === null ? null : v).replace(/^null$/, "nil")
const luaValue = v => (typeof v === "boolean" || typeof v === "number") ? String(v) : JSON.stringify(String(v))

// (an empty Lua table can arrive as {} or [])
export function arr(x) {
  if (Array.isArray(x)) return x
  if (x && typeof x === "object") return Object.values(x)
  return []
}

export function refreshState(cb) {
  engineLua("earthRally_main and earthRally_main.uiState() or nil", s => {
    if (s) state.value = s
    if (cb) cb(s)
  })
}
export function takeOpenAt(cb) {
  engineLua("earthRally_main and earthRally_main.uiOpenAt() or nil", at => cb(at))
}
export function loadRally(id) {
  engineLua(`earthRally_main and earthRally_main.uiRally(${q(id)}) or nil`, r => { if (r) rally.value = r })
}
export function loadStage(eventId, stageId) {
  engineLua(`earthRally_main and earthRally_main.uiStage(${q(eventId)}, ${q(stageId)}) or nil`, s => { if (s) stage.value = s })
}

// A button: drive / route / recce / autoRecce / autoRecceStop / recceSave / recceSaveAnyway / recceCancel /
// abort / openFolder / rescan
export function action(what, eventId, stageId, cb) {
  busyMsg.value = ""
  engineLua(`earthRally_main and earthRally_main.uiAction(${q(what)}, ${q(eventId)}, ${q(stageId)}) or nil`, r => {
    busyMsg.value = (r && r.message) || ""
    refreshState()
    if (cb) cb(r)
  })
}

export function setSetting(key, value) {
  engineLua(`earthRally_main and earthRally_main.uiSet(${q(key)}, ${luaValue(value)}) or nil`, r => {
    if (r && r.settings && state.value.settings) state.value.settings.settings = r.settings
  })
}

export function openMenu(view, eventId) {
  engineLua(`if earthRally_main then earthRally_main.openMenu(${q(view || "rallies")}, ${q(eventId)}) end`)
}
export function closeMenu() { engineLua("if earthRally_main then earthRally_main.closeMenu() end") }
export function previewHud() { engineLua("if earthRally_main then earthRally_main.previewHud() end") }

// The poll while a page or card is open (a count: started / stopped by each)
let users = 0
let timer = null
export function startPolling() {
  if (users++ === 0) {
    refreshState()
    timer = setInterval(refreshState, 1000)
  }
}
export function stopPolling() {
  if (--users <= 0) {
    users = 0
    if (timer) clearInterval(timer)
    timer = null
  }
}

// ---- words and numbers (lengths in metres, times in seconds from Lua)
export const MILE_M = 1609.344
export function units() { return (state.value.settings && state.value.settings.settings && state.value.settings.settings.units) || "km" }
export function len(m) {
  if (m === null || m === undefined) return "–"
  return units() === "mi" ? `${(m / MILE_M).toFixed(1)} mi` : `${(m / 1000).toFixed(1)} km`
}
export function lenNum(m) { return ((m || 0) / (units() === "mi" ? MILE_M : 1000)).toFixed(1) }

// A height gained or lost over a stage (the Gain and Loss tiles), from the one distance setting units() already
// answers: metres in metric, feet in imperial, at the same 3.28084 the HUD's own format.js dist() uses -- no
// second setting and no second way of deciding.
//
// Rounded to the nearest 10 m, or the nearest 50 ft -- about the size of the figure's own uncertainty, and
// deliberately not dist()'s nearest 10 ft, which is three times finer than the metric step and would print a
// stage with nothing to climb as 0 m in metric and 10 ft in imperial. The two settings now agree about which
// stages are flat. The dash is "the line carries no heights"; no line at all is a dash on all three tiles.
export const FEET_PER_M = 3.28084
export function riseUnit() { return units() === "mi" ? "ft" : "m" }
export function riseNum(m) {
  if (m === null || m === undefined) return "–"
  return units() === "mi" ? String(Math.round(m * FEET_PER_M / 50) * 50) : String(Math.round(m / 10) * 10)
}
export function time(s) {
  if (s === null || s === undefined) return "–"
  const t = Math.round(s * 10) / 10
  const m = Math.floor(t / 60)
  const r = t - m * 60
  return `${m}:${r < 10 ? "0" : ""}${r.toFixed(1)}`
}
export function when(iso) {
  if (!iso) return ""
  const d = new Date(iso)
  if (isNaN(d.getTime())) return iso
  const now = new Date()
  const hm = d.toLocaleTimeString([], { hour: "2-digit", minute: "2-digit" })
  if (d.toDateString() === now.toDateString()) return `Today, ${hm}`
  const y = new Date(now.getTime() - 86400000)
  if (d.toDateString() === y.toDateString()) return `Yesterday, ${hm}`
  return `${d.toLocaleDateString([], { day: "numeric", month: "short" })}, ${hm}`
}
export const STATUS = {
  ready: { label: "Ready", cls: "ready" },
  recce: { label: "Recce recommended", cls: "recce" },
  none: { label: "Recce needed", cls: "none" },
  // The fourth state, while an auto recce runs: the pill itself is the progress (the page has no room for a second
  // line in a 58px row), so it carries the window count and fills to it. It answers the same question the other
  // three do -- can I drive this stage? -- and an ending puts the pill back to one of them, never to a fifth.
  working: { label: "Auto recce", cls: "working" },
}
// How an auto recce ended (autoRecce.lua's M.PARTIAL / M.NODATA / M.FAILED) -> the colour of the line under the
// card. No map data anywhere is grey on purpose: it is a normal outcome for ground never driven, not a failure,
// and the only red line on the page is the one where something actually went wrong.
export const AUTO_OUTCOME = { partial: "warn", nodata: "flat", failed: "err" }
export const RUN_WORDS = {
  travel: "going to the stage", anchor: "moving the world to the stage", build: "building the stage",
  place: "setting the car down", toAtc: "driving to the time control", toStart: "moving up to the start line",
  waitStart: "on the start line", running: "on the stage", toStop: "on to the stop control",
  finished: "stage done", failed: "stopped",
}
