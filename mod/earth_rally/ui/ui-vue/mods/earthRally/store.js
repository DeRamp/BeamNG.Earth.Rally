// Earth Rally's menu: the state shared by its page (EarthRally.vue, a route of its own) and its pause-menu
// card (EarthRallyTab.vue). Lua side: lua/ge/extensions/earthRally/main.lua
// (uiState, uiSeason, uiRally, uiStage, uiAction, uiSet), as BeamNG.Earth's settings pages talk to its settings.lua.
import { ref } from "vue"

export const state = ref({})          // earthRally_main.uiState(): rallies, settings, the run, the recce, ...
export const season = ref(null)       // earthRally_main.uiSeason(id)
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
export function loadSeason(id) {
  engineLua(`earthRally_main and earthRally_main.uiSeason(${q(id)}) or nil`, r => { if (r) season.value = r })
}
// cb(r): once, with the answer (the page uses it to open a one-stage rally straight on its stage)
export function loadRally(id, cb) {
  engineLua(`earthRally_main and earthRally_main.uiRally(${q(id)}) or nil`, r => {
    if (r) rally.value = r
    if (cb) cb(r)
  })
}
// pass: the leaderboard's pass ("SS4"), or nothing for the one you place best on
export function loadStage(eventId, stageId, pass) {
  engineLua(`earthRally_main and earthRally_main.uiStage(${q(eventId)}, ${q(stageId)}, ${q(pass)}) or nil`, s => { if (s) stage.value = s })
}

// A button: drive / route / recce / autoRecce / autoRecceStop / reset / recceSave / recceSaveAnyway /
// recceCancel / abort / openFolder / rescan
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

// Stats and Report a problem (+stats; main.lua uiStats): what = yes / no / shown / openFolder / report.
// a, b: for report, what the player wrote and whether to save the log. (Cut at 4000 without splitting an emoji.)
const luaText = v => JSON.stringify(String(v || "").replace(/[\u0000-\u0009\u000b-\u001f]/g, " ").slice(0, 4000).replace(/[\ud800-\udbff]$/, ""))
export function statsAction(what, a, b, cb) {
  engineLua(`earthRally_main and earthRally_main.uiStats(${q(what)}, ${luaText(a)}, ${b ? "true" : "false"}) or nil`, r => {
    if (r && r.stats) state.value = Object.assign({}, state.value, { stats: r.stats })
    if (cb) cb(r)
  })
}

// view: the page to open at; none opens where the menu was left (EarthRally.vue's lastPlace)
export function openMenu(view, eventId) {
  engineLua(`if earthRally_main then earthRally_main.openMenu(${q(view)}, ${q(eventId)}) end`)
}

// Where the menu page was left: { view, sel, rallyTab }, kept here because the page itself is unmounted when the
// menu closes (this module lives as long as the UI does; a UI reload starts on Rallies again).
export const lastPlace = { at: null }
export function closeMenu() { engineLua("if earthRally_main then earthRally_main.closeMenu() end") }

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
// A time that can run past the hour (a rally's total): 2:43:50.6, else as time()
export function longTime(s) {
  if (s === null || s === undefined) return "–"
  const t = Math.round(s * 10) / 10
  if (t < 3600) return time(t)
  const h = Math.floor(t / 3600)
  const m = Math.floor((t - h * 3600) / 60)
  const r = t - h * 3600 - m * 60
  return `${h}:${m < 10 ? "0" : ""}${m}:${r < 10 ? "0" : ""}${r.toFixed(1)}`
}
// A gap to the fastest: "+32.1", "+1:02.3"; nothing for the leader (boards.lua's gapText)
export function gap(s) {
  if (s === null || s === undefined || Math.abs(s) < 0.05) return ""
  const sign = s < 0 ? "-" : "+"
  const a = Math.abs(s)
  return sign + (a < 60 ? a.toFixed(1) : longTime(a))
}
// 1st, 2nd, 3rd, 11th, 23rd
export function ord(n) {
  if (n === null || n === undefined) return "–"
  const t = n % 100
  if (t >= 11 && t <= 13) return `${n}th`
  return n + ({ 1: "st", 2: "nd", 3: "rd" }[n % 10] || "th")
}
// Dates as the rally files write them ({ from, to }, "2026-02-06"): read as written, never through Date (a
// time zone would move a day). days(): "6–7 Feb", "30 Jan – 1 Feb" (withYear: "17–19 Apr 2026");
// months(): "Feb – Oct 2026".
const MONTHS = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]
function ymd(s) {
  const m = /^(\d{4})-(\d{2})-(\d{2})/.exec(s || "")
  return m ? { y: +m[1], m: +m[2] - 1, d: +m[3] } : null
}
export function days(dt, withYear) {
  const a = ymd(dt && (dt.from || dt.to))
  const b = ymd(dt && (dt.to || dt.from)) || a
  if (!a) return ""
  const y = withYear ? ` ${b.y}` : ""
  if (a.y === b.y && a.m === b.m) return a.d === b.d ? `${a.d} ${MONTHS[a.m]}${y}` : `${a.d}–${b.d} ${MONTHS[a.m]}${y}`
  if (a.y === b.y) return `${a.d} ${MONTHS[a.m]} – ${b.d} ${MONTHS[b.m]}${y}`
  return `${a.d} ${MONTHS[a.m]} ${a.y} – ${b.d} ${MONTHS[b.m]} ${b.y}`
}
export function months(dt) {
  const a = ymd(dt && (dt.from || dt.to))
  const b = ymd(dt && (dt.to || dt.from)) || a
  if (!a) return ""
  if (a.y === b.y && a.m === b.m) return `${MONTHS[a.m]} ${a.y}`
  if (a.y === b.y) return `${MONTHS[a.m]} – ${MONTHS[b.m]} ${a.y}`
  return `${MONTHS[a.m]} ${a.y} – ${MONTHS[b.m]} ${b.y}`
}
// A rally's name without its year, for the small places (a mosaic tile, "SnoDrift 11th")
export function shortName(n, dropRally) {
  let s = String(n || "").replace(/\s+\d{4}$/, "")
  if (dropRally) s = s.replace(/\s+Rally$/i, "")
  return s
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
// "SS2 · SS4 Wildcat" for the banners: the stage's real SS label from the Lua (menu.ssLabel), or its name alone on
// a stage the rally's itinerary never runs, or from a file with no label. Never an SS number made up here.
export function ssName(x) {
  if (!x) return ""
  return x.ssLabel ? `${x.ssLabel} ${x.stageName || ""}` : `${x.stageName || ""}`
}
export const AUTO_OUTCOME = { partial: "warn", nodata: "flat", failed: "err" }
export const RUN_WORDS = {
  travel: "going to the stage", anchor: "moving the world to the stage", build: "building the stage",
  place: "setting the car down", toAtc: "driving to the time control", toStart: "moving up to the start line",
  waitStart: "on the start line", running: "on the stage", toStop: "on to the stop control",
  finished: "stage done", failed: "stopped",
}
