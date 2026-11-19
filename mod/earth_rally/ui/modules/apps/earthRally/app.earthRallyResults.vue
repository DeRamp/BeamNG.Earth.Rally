<template>
  <!-- Earth Rally's stage-done card (docs/mockups-1.2.0/results.html), an interactive app in the stage layout, shown
       while the stream 'earthRally' says show.results (Lua: hudFrame.lua; open from the stop control until a button,
       driving off, or a timeout: runner.lua). The buttons go to earthRally_main.uiResults; Close shuts the card. -->
  <!-- a controller (1.6.2), as the game's own prompts over driving take one (its mission/activity prompt,
       ActivityStart.vue; the drag-race dial, dragDialControl): the card says the game a popup is up while
       it shows, which is what lets a controller's menu buttons through on the driving screen at all, and a
       no-nav scope of its own takes them -- the first button picked as it opens, the d-pad moves along them, A presses
       the picked one, B closes. (1.7.0 rev 4) The game is paused under every card now, so the stick picks too.
       (2026-11-19) None of that reached the card in 0.40.6 (a HUD app gets no UI nav): the pad and the keys are taken
       in Lua while the card is up (lua earthRally/cardInput.lua), which sends the pick here (ours.card). -->
  <!-- (1.7.0) A pass of a full rally: the card is the rally's (mock-up 3: your stage and class place against the
       real National field, the crews round you; Continue to the time card, Restart in Casual only, Close), and in
       Realistic mode the Recover? question (mock-up 4) comes up in it from the recovery key during the stage, or
       on a transit (#69). (rev 4, #58) "Load the stage?" at a time control's board comes up in it too, the same
       look as Recover?: docs/mockups-1.7.0/rev4.html, screens "prompt" and "recover". -->
  <div v-if="res || ask || load" ref="cardEl" class="er-results" tabindex="0"
    v-bng-scoped-nav="{ scopeId: 'earthRallyResults', type: 'nonav', activateOnMount: true, trapPolicy: 'always',
      bubbleWhitelistEvents: ['menu'] }"
    v-bng-on-ui-nav:ok="() => forward('ok')" v-bng-on-ui-nav:back="() => forward('back')"
    v-bng-on-ui-nav:focus_l="() => forward('prev')" v-bng-on-ui-nav:focus_u="() => forward('prev')"
    v-bng-on-ui-nav:focus_r="() => forward('next')" v-bng-on-ui-nav:focus_d="() => forward('next')"
    v-bng-on-ui-nav:focus_lr="e => stick('x', e)" v-bng-on-ui-nav:focus_ud="e => stick('y', e)">
    <!-- (#59) a question over a paused game: A / D-pad / stick work its two buttons, B is the second one -->
    <template v-if="ask">
      <div class="er-qtop er-ask-top"><div class="er-kick">{{ askKick }}</div><div class="er-name">Recover?</div></div>
      <div class="er-ask"><template v-if="ask.transit && ask.toStop">Recovering takes you to <b>{{ ask.stop }}</b>. No stage is missed.</template><template v-else-if="ask.transit">Recovering ends your transit.<template v-if="ask.stop"> You rejoin at <b>{{ ask.stop }}</b> under Super Rally.</template></template><template v-else>Recovering ends this stage.<template v-if="ask.stop"> You go to <b>{{ ask.stop }}</b> under Super Rally and carry on from there.</template></template><template v-if="!ask.stop && !ask.toStop && ask.last"> This is the last stage: the rally ends unclassified.</template><template v-else-if="!ask.stop && !ask.toStop"> There is no service left to rejoin at: the rally ends unclassified.</template></div>
      <div class="er-buttons">
        <BngButton class="er-main" :class="{ 'er-picked': ring('recover') }" :accent="ACCENTS.main" @click="act('recover')">Recover · Super Rally</BngButton>
        <BngButton :class="{ 'er-picked': ring('keep') }" :accent="ACCENTS.secondary" @click="act('keep')">Keep going</BngButton>
      </div>
      <div class="er-foot er-keys"><span><span class="er-k er-ka">A</span>Select</span><span><span class="er-k er-kb">B</span>Keep going</span><span class="er-paused">Game paused</span></div>
    </template>
    <template v-else-if="load">
      <div class="er-qtop er-ask-top"><div class="er-kick">Time control{{ loadSs ? ` · ${loadSs}` : "" }}</div><div class="er-name">Load the stage?</div></div>
      <div class="er-ask">{{ loadLine }} The game pauses while the stage and the world around you load.</div>
      <div class="er-buttons">
        <BngButton class="er-main" :class="{ 'er-picked': ring('load') }" :accent="ACCENTS.main" @click="act('load')">{{ loadSs ? `Load ${loadSs}` : "Load the stage" }}</BngButton>
        <BngButton :class="{ 'er-picked': ring('notYet') }" :accent="ACCENTS.secondary" @click="act('notYet')">Not yet</BngButton>
      </div>
      <div class="er-foot er-keys"><span><span class="er-k er-ka">A</span>Select</span><span><span class="er-k er-kb">B</span>Not yet</span><span class="er-paused">Game paused</span></div>
    </template>
    <template v-else>
    <div class="er-top">
      <span v-if="fmt.ss(stage)" class="er-ss">{{ fmt.ss(stage) }}</span><span class="er-name">{{ stage.name }}</span><span class="er-done">Stage complete</span>
    </div>
    <div class="er-total">
      <span class="er-t">{{ fmt.time(fin.time) }}</span>
      <template v-if="!rc">
      <span v-if="fin.newBest" class="er-delta er-best">{{ fin.first ? "FIRST TIME" : fmt.delta(fin.delta) + " · NEW BEST" }}</span>
      <span v-else class="er-delta er-slower">{{ fmt.delta(fin.delta) }}</span>
      </template>
    </div>
    <!-- (rally loop) the three quarter splits and the finish, each with its gap to your best (green ahead, amber
         behind, none on a first run): one row across the card, so a rally card with its crews still fits -->
    <div v-if="splits.length" class="er-splits">
      <div v-for="s in splits" :key="s.n" class="er-split" :class="{ 'er-split-fin': s.n === 4 }">
        <span class="er-split-l">{{ s.n === 4 ? "Finish" : `Split ${s.n}` }}</span>
        <span class="er-split-row">
          <span class="er-v">{{ fmt.time(s.timeS) }}</span>
          <span v-if="typeof s.gapS === 'number'" class="er-split-gap" :class="s.gapS < 0 ? 'er-best' : 'er-slower'">{{ fmt.delta(s.gapS) }}</span>
        </span>
      </div>
    </div>
    <!-- a full rally's places against the real National field -->
    <div v-if="rc" class="er-rally">
      <div class="er-rplace">
        <span v-if="rc.stage">Stage <b>P{{ rc.stage.pos }} / {{ rc.stage.of }}</b> · {{ rcClass }} <b>{{ rc.stage.classPos }} / {{ rc.stage.classOf }}</b></span>
        <span v-if="rc.overall" class="er-rov">Overall <b>P{{ rc.overall.pos }}</b> · {{ rcClass }} {{ fmt.ord(rc.overall.classPos) }}</span>
      </div>
      <div v-for="(r, i) in rcRows" :key="i" class="er-rrow" :class="{ me: r.you, gap: r.gap }">
        <template v-if="r.gap"><span>⋯</span></template>
        <template v-else><span>{{ r.pos }}</span><span class="er-rn">{{ r.you ? "YOU" : r.name }}</span><span>{{ r.class }}</span><span class="er-v">{{ fmt.time(r.timeS) }}</span><span class="er-v">{{ r.gapS > 0.05 ? "+" + fmt.time(r.gapS) : "" }}</span></template>
      </div>
    </div>
    <div class="er-lines">
      <div class="er-line"><span>Stage time</span><span class="er-v">{{ fmt.time(fin.stageTime) }}</span></div>
      <div class="er-line er-pen"><span>Penalties</span><span class="er-v">{{ fin.penalty > 0 ? `+${Math.round(fin.penalty)} s` : "none" }}</span></div>
      <div v-for="p in (rc ? [] : penLines)" :key="p.label" class="er-line er-sub" :class="{ 'er-zero': !p.s }">
        <span>{{ p.label }}</span><span class="er-v">{{ p.s ? `+${p.s} s` : "–" }}</span>
      </div>
      <div class="er-line er-sum"><span>Your time</span><span class="er-v">{{ fmt.time(fin.time) }}</span></div>
      <div v-if="!rc && fin.best !== null && fin.best !== undefined" class="er-line er-bestline">
        <span>{{ fin.newBest ? "Best before this run" : "Best" }}</span><span class="er-v">{{ fmt.time(fin.best) }}</span>
      </div>
    </div>
    <div v-if="rc" class="er-buttons">
      <BngButton class="er-main" :class="{ 'er-picked': ring('continue') }" :accent="ACCENTS.main" @click="act('continue')">{{ rc.last ? "Continue · the finish" : "Time card" }}</BngButton>
      <BngButton v-if="rc.canRestart" :class="{ 'er-picked': ring('restart') }" :accent="ACCENTS.secondary" @click="act('restart')">Restart stage</BngButton>
      <BngButton class="er-close" :class="{ 'er-picked': ring('close') }" :accent="ACCENTS.outlined" @click="act('close')">Close</BngButton>
    </div>
    <div v-else class="er-buttons">
      <BngButton v-if="next" class="er-main" :class="{ 'er-picked': ring('next') }" :accent="ACCENTS.main" @click="act('next')">
        Next stage <small>{{ fmt.ss(next) ? fmt.ss(next) + " " : "" }}{{ next.name }} · {{ fmt.len(next.lengthM, units) }}</small>
      </BngButton>
      <BngButton :class="{ 'er-picked': ring('retry') }" :accent="ACCENTS.secondary" @click="act('retry')">Retry</BngButton>
      <BngButton :class="{ 'er-picked': ring('menu') }" :accent="ACCENTS.secondary" @click="act('menu')">Rally menu</BngButton>
      <!-- (1.6.2, #18) just the card gone, back to driving: runner.resultsAction's last case -->
      <BngButton class="er-close" :class="{ 'er-picked': ring('close') }" :accent="ACCENTS.outlined" @click="act('close')">Close</BngButton>
    </div>
    <div class="er-foot">{{ rc ? (rc.next && !rc.last ? (rc.driven ? `Next: ${rc.next}. Close and follow the arrows.` : `Next: ${rc.next}. Time card (Ctrl+Alt+K) to go on.`) : "") : "The game is paused: Close (B) to drive on." }}</div>
    </template>
  </div>
</template>

<script setup>
import { ref, computed, watch, nextTick, onUnmounted } from "vue"
import { useStreams } from "@/services/events"
import { BngButton, ACCENTS } from "@/common/components/base"
import { vBngScopedNav, vBngOnUiNav } from "@/common/directives"
import { reportState, hasReportedPopupState } from "@/services/stateReporter"
import useControls from "@/services/controls"
import * as fmt from "./format.js"

const f = ref(null)
useStreams(["earthRally"], streams => {
  if (streams.earthRally) f.value = streams.earthRally
})

const show = computed(() => (f.value && f.value.show && !Array.isArray(f.value.show) ? f.value.show : {}))
const res = computed(() => (show.value.results && f.value.results && f.value.results.finish) ? f.value.results : null)
const fin = computed(() => (res.value && res.value.finish) || {})
const next = computed(() => res.value && res.value.next)
const stage = computed(() => (f.value && f.value.stage) || {})
const units = computed(() => (f.value && f.value.units) || "km")
// (1.7.0) the full rally's part of the stream (hudFrame: ours.rally; show.recoverAsk)
const rally = computed(() => (f.value && f.value.rally) || null)
const rc = computed(() => (res.value && rally.value && rally.value.card) || null)
const ask = computed(() => (show.value.recoverAsk && rally.value && rally.value.ask) || null)
// (#69) on a transit the question has no stage of its own to name
const askKick = computed(() => {
  const a = ask.value || {}
  const names = [a.ss, a.name].filter(Boolean).join(" ")
  return `${a.transit ? "Transit" : names || "Stage"} · Realistic`
})
// (#58) stopped at a time control's board: rallyRun's loadAsk = { ss, name, km }, up while show.loadAsk
const load = computed(() => (show.value.loadAsk && rally.value && rally.value.loadAsk) || null)
// (the SS as a label "SS2" or a bare number, whichever the stream carries)
const loadSs = computed(() => {
  const l = load.value
  if (!l) return ""
  const v = typeof l.ssLabel === "string" && l.ssLabel ? l.ssLabel : l.ss
  if (typeof v === "number" || (typeof v === "string" && /^\d+$/.test(v))) return `SS${v}`
  return typeof v === "string" ? v : ""
})
// "SS2 Cutter Creek, 14.8 km."
const loadLine = computed(() => {
  const l = load.value || {}
  const km = typeof l.km === "number" ? fmt.len(l.km * 1000, units.value) : (l.km || "")
  const what = [loadSs.value, l.name].filter(Boolean).join(" ")
  const line = [what, km].filter(Boolean).join(", ")
  return line ? line + "." : ""
})
const rcClass = computed(() => {
  const st = rc.value && rc.value.stage
  const row = st && (Array.isArray(st.rows) ? st.rows : Object.values(st.rows || {})).find(r => r.you)
  return (row && row.class) || ""
})
const rcRows = computed(() => {
  const st = rc.value && rc.value.stage
  return st ? (Array.isArray(st.rows) ? st.rows : Object.values(st.rows || {})) : []
})

// (rally loop) finish.splits = [ { n, timeS, gapS } ], n = 4 the finish; absent on a run without splits. A Lua list
// can arrive as [] or as {} with keys: in n order either way.
const splits = computed(() => {
  const v = fin.value.splits
  const l = Array.isArray(v) ? v : (v && typeof v === "object" ? Object.values(v) : [])
  return l.filter(s => s && typeof s.n === "number").sort((a, b) => a.n - b.n)
})

const penLines = computed(() => {
  const p = fin.value.penalties || {}
  return [
    { label: "Jump start", s: p.jumpStart || 0 },
    { label: p.lateMinutes ? `Late at the start (${p.lateMinutes} min)` : "Late at the start", s: p.late || 0 },
    { label: p.resetCount ? `Resets (${p.resetCount} × 10 s)` : "Resets", s: p.resets || 0 },
    { label: "Missed time control", s: p.missedAtc || 0 },
  ]
})

// The controller's pick among the buttons, in their order on the card (Next stage only when there is one).
const order = computed(() => {
  if (ask.value) return ["recover", "keep"]
  if (load.value) return ["load", "notYet"]
  if (rc.value) return rc.value.canRestart ? ["continue", "restart", "close"] : ["continue", "close"]
  return next.value ? ["next", "retry", "menu", "close"] : ["retry", "menu", "close"]
})
// (2026-11-19) The pad and the keys are Lua's while the card is up (lua earthRally/cardInput.lua: in 0.40.6 a HUD
// app gets no UI nav at all -- the apps overlay hosts every app with prevent-uinav, so the game never turns ok / back
// / the d-pad on for it). Lua owns the pick and sends it in the stream (ours.card = { pick, pad }); the card draws
// it. Any nav the game does send the card goes to the same place (src "ui"), where a press is acted on once.
const cardInfo = computed(() => (f.value && f.value.card && typeof f.value.card === "object" ? f.value.card : null))
const picked = computed(() => {
  const p = cardInfo.value && cardInfo.value.pick
  return order.value.includes(p) ? p : order.value[0]
})
// (the pick drawn only with a controller in use, as the game's own focus ring is: a mouse player sees no ring)
const controls = useControls()
const padOn = computed(() => !!(controls && controls.focusIfController) || !!(cardInfo.value && cardInfo.value.pad))
// (#59) a question's pick is always drawn: its buttons are the one selection, mouse or pad
const ring = what => (padOn.value || up.value === "ask" || up.value === "load") && picked.value === what
function luaCall(cmd) {
  if (f.value && f.value.preview) return
  if (window.bngApi && window.bngApi.engineLua) window.bngApi.engineLua(`if earthRally_main then ${cmd} end`)
}
// The UI's own nav forwarded to Lua (src 'ui'; cardInput's SAME_PRESS_S acts on one press once if it also came
// through our map). Kept, though 0.40.6 never sends it: the game hosts HUD apps with no UI nav (its AppHost.vue sets
// bng-no-child-nav), so A reaches the card only through cardInput's map. It stays beside the mouse's clicks (act())
// for a future BeamNG that gives HUD apps UI nav.
function forward(kind) {
  gameLog(`results card got ${kind} from the UI (${up.value}), focus ${describe(document.activeElement)}`)
  luaCall(`earthRally_main.cardPress(${JSON.stringify(kind)}, 'ui')`)
}
function stick(axis, e) {
  const v = Number(e && e.detail && e.detail.value) || 0
  luaCall(`earthRally_main.cardStick(${JSON.stringify(axis)}, ${v}, 'ui')`)
}
// (the card keeps the real focus, so no button of it is clicked by the game's own nav as well)
function focusCard() {
  const el = cardEl.value
  if (!el || (f.value && f.value.preview) || document.activeElement === el) return
  try { el.focus({ preventScroll: true }) } catch (e) { /* (no focus to take: mouse only) */ }
}

// While the card is up the game is told a popup is open (the name has the shape its popup service reports,
// /popup/<type>/<component>/aside): its input bindings turn its menu buttons on for the driving screen then
// (core/input/bindings.lua, onUIStateTriggered). (#62) A modal one while the game is paused under the card -- a
// question's card always, the finish card only while its pause is held (show.cardPaused: with a stop control) --
// since a non-modal popup leaves A to the car's interaction triggers too (btn_a is also triggerAction0;
// core/vehicleTriggers.lua: "modal popups own the controller confirm button"). An "activity" one otherwise: a
// flying-finish card can be up with the car still rolling, and a modal popup there would take the car's buttons.
const popupState = computed(() =>
  `/popup/${(ask.value || load.value || show.value.cardPaused) ? "normal" : "activity"}/EarthRallyResults/aside`)
let reported = false    // (the state reported now, or false)
let listening = false   // (the nav log's window listener, #62: listenNav below)
function setReported(on) {
  const want = on ? popupState.value : false
  if (want === reported) return
  try {
    if (reported) reportState(reported, false)
    if (want) reportState(want, true)
  } catch (e) { /* (an older game: mouse only, as before) */ }
  reported = want
}
// (the finish card's pause comes on a frame after the card, and a question can come up over it: the kind follows)
watch(popupState, () => { if (reported) setReported(true) })
const up = computed(() => (ask.value ? "ask" : load.value ? "load" : res.value ? "res" : null))
watch(up, (r, was) => {
  setReported(!!r && !(f.value && f.value.preview))
  listenNav(!!r && !(f.value && f.value.preview))
  if (r && r !== was) {
    nextTick(focusCard)
    logOpen(r)
  }
}, { immediate: true })
// (#41) The buttons change under the card: a rally's part (continue / restart / close) arrives after the stage's
// (next / retry / ...), so the pick made as it opened is on no button. A new order picks its first button again.
// (by the names, not the array: the stream sends a new frame, and so a new array, many times a second)
watch(() => order.value.join(","), (o, was) => {
  if (up.value && o !== was) {
    nextTick(focusCard)
    gameLog(`results card buttons now ${o.replace(/,/g, " ")}: pick ${picked.value}`)
  }
})

// (#41) The game's log says, as the card opens, whether the popup state was reported (which lets the pad's menu
// buttons through) and whether the card's nav scope took the pad.
const cardEl = ref(null)
function logOpen(r) {
  nextTick(() => setTimeout(() => {
    // (again here: the nonav scope's activation blurs whatever had the focus, a beat after the card mounts)
    focusCard()
    let popup = "?"
    try { popup = String(hasReportedPopupState()) } catch (e) { /* (an older game) */ }
    const el = cardEl.value
    const scope = el ? el.getAttribute("data-bng-scoped-nav-state") || "none" : "no card"
    const line = `results card up (${r}): popup state reported ${reported}, popup open ${popup}, nav scope ${scope}, ` +
      `pick ${picked.value}, buttons ${order.value.join(" ")}, focus ${describe(document.activeElement)}`
    gameLog(line)
  }, 250))
}
// (#62) Every A / B / d-pad press while the card is up, wherever the game sends it (a capture listener on the window
// sees it first): a press the card never got shows here and not in the card's own "got" lines.
const NAV_LOGGED = ["ok", "back", "focus_l", "focus_r", "focus_u", "focus_d"]
function onAnyNav(e) {
  const d = (e && e.detail) || {}
  if (!NAV_LOGGED.includes(d.name) || !d.value) return
  gameLog(`nav ${d.name} sent to ${describe(e.target)} (target scope ${d.targetScope || "none"}), ` +
    `focus ${describe(document.activeElement)}`)
}
function listenNav(on) {
  if (on === listening) return
  listening = on
  if (on) window.addEventListener("ui_nav", onAnyNav, true)
  else window.removeEventListener("ui_nav", onAnyNav, true)
}
// (an element as the log can name it: the card, one of its buttons, or a tag.class in a ui scope)
function describe(el) {
  if (!el) return "none"
  if (el === document.body) return "body"
  const card = cardEl.value
  if (card && el === card) return "the card"
  if (card && card.contains(el)) return "a card button"
  const scope = el.closest ? el.closest("[bng-ui-scope]") : null
  const cls = typeof el.className === "string" && el.className.trim() ? "." + el.className.trim().split(/\s+/)[0] : ""
  return `${String(el.tagName || "?").toLowerCase()}${cls}${scope ? " in scope " + scope.getAttribute("bng-ui-scope") : ""}`
}
function gameLog(line) {
  console.log("earthRally: " + line)
  if (window.bngApi && window.bngApi.engineLua) {
    window.bngApi.engineLua(`log('I', 'earthRally', ${JSON.stringify(line)})`)
  }
}
onUnmounted(() => {
  setReported(false)
  listenNav(false)
})

// (a click: through cardInput, so a click and a key on the same card act once)
function act(what) {
  luaCall(`earthRally_main.cardClick(${JSON.stringify(what)})`)
}
</script>

<style lang="scss" scoped>
.er-results {
  --er-theme: #1f8fff;
  --er-go: rgb(0, 255, 0);
  --er-amber: #ffb000;
  --er-muted: #b8bcc6;
  --er-zero: #6f7480;
  color: #f0f0f0;
  font-family: "Noto Sans", sans-serif;
  background: rgba(0, 0, 0, 0.78);
  border-radius: 0.5rem;
  overflow: hidden;
  box-shadow: 0 10px 50px rgba(0, 0, 0, 0.6);
}
.er-top { padding: 26px 40px 20px; border-top: 6px solid var(--er-theme); display: flex; align-items: baseline; gap: 18px; }
.er-ss { font: 700 22px "Overpass Mono", monospace; color: var(--er-theme); }
.er-name { font-size: 40px; font-weight: 700; }
.er-done { margin-left: auto; font-size: 18px; letter-spacing: 0.12em; text-transform: uppercase; color: var(--er-muted); }
.er-total { padding: 6px 40px 18px; display: flex; align-items: flex-end; gap: 24px; }
.er-t { font: 700 112px/1 "Overpass Mono", monospace; }
.er-delta { font-size: 30px; font-weight: 800; padding: 4px 16px; border-radius: 8px; margin-bottom: 14px; }
.er-best { background: var(--er-go); color: #002a00; }
.er-slower { background: var(--er-amber); color: #1a1000; }
.er-splits { margin: 0 40px 14px; display: grid; grid-template-columns: repeat(4, minmax(0, 1fr)); gap: 0;
  border-top: 1px solid rgba(255, 255, 255, 0.12); padding-top: 8px; }
.er-split { display: flex; flex-direction: column; gap: 3px; padding: 0 10px; min-width: 0;
  border-left: 1px solid rgba(255, 255, 255, 0.07);
  &:first-child { padding-left: 0; border-left: none; }
  .er-split-l { font-size: 14px; letter-spacing: 0.1em; text-transform: uppercase; color: var(--er-muted); }
  .er-split-row { display: flex; align-items: center; gap: 8px; white-space: nowrap; }
  .er-v { font-size: 20px; }
  .er-split-gap { font-size: 15px; font-weight: 800; padding: 1px 7px; border-radius: 5px; }
  &.er-split-fin { .er-split-l { color: #fff; font-weight: 700; } .er-v { font-weight: 700; } } }
.er-lines { margin: 0 40px; border-top: 1px solid rgba(255, 255, 255, 0.12); }
.er-line { display: grid; grid-template-columns: 1fr auto; padding: 9px 0; font-size: 22px; border-bottom: 1px solid rgba(255, 255, 255, 0.07); }
.er-v { font: 600 22px "Overpass Mono", monospace; }
.er-sub { padding-left: 26px; font-size: 19px; color: #dfe3ea; .er-v { font-size: 19px; } }
.er-zero, .er-zero .er-v { color: var(--er-zero); }
.er-pen .er-v { color: #ffd36b; }
.er-sum { font-weight: 700; .er-v { font-size: 26px; font-weight: 700; } }
.er-bestline .er-v { color: var(--er-muted); }
.er-buttons { display: flex; gap: 16px; padding: 24px 40px 12px; }
.er-close { margin-left: auto; }
/* the controller's pick (A presses it) */
.er-picked { outline: 3px solid #fff; outline-offset: 3px; }
.er-results:focus { outline: none; }
.er-main { flex: 1; small { font-weight: 500; opacity: 0.85; margin-left: 8px; } }
.er-foot { padding: 0 40px 22px; font-size: 16px; color: var(--er-muted); }
.er-ask-top { border-top-color: #f26b1d; }
.er-ask { padding: 4px 40px 8px; font-size: 22px; line-height: 1.5; }
/* (rev 4) a question's head: the kicker over the question, as the mock-up's Recover? and Load the stage? */
.er-qtop { padding: 26px 40px 12px; border-top: 6px solid var(--er-theme); }
.er-kick { font-size: 17px; letter-spacing: 0.18em; text-transform: uppercase; font-weight: 700; color: #f26b1d; margin-bottom: 4px; }
.er-keys { display: flex; align-items: center; gap: 26px; padding-top: 8px; }
.er-k { display: inline-flex; align-items: center; justify-content: center; width: 28px; height: 28px; border-radius: 50%;
  font: 700 14px "Noto Sans", sans-serif; color: #111; margin-right: 8px; }
.er-ka { background: #6cc24a; }
.er-kb { background: #e5533d; }
.er-paused { margin-left: auto; font-size: 15px; letter-spacing: 0.12em; text-transform: uppercase; color: #8a909a; }
.er-rally { margin: 0 40px 10px; }
.er-rplace { display: flex; justify-content: space-between; font-size: 20px; padding: 6px 0 8px; .er-rov { color: var(--er-muted); } }
.er-rrow { display: grid; grid-template-columns: 50px minmax(0, 1fr) 80px 120px 110px; gap: 8px; padding: 4px 8px; font-size: 18px;
  border-bottom: 1px solid rgba(255, 255, 255, 0.06);
  &.me { background: #16305e; font-weight: 700; }
  &.gap { color: #6f7480; text-align: center; grid-template-columns: 1fr; }
  .er-rn { overflow: hidden; white-space: nowrap; text-overflow: ellipsis; }
  .er-v { font-size: 18px; text-align: right; } }
</style>
