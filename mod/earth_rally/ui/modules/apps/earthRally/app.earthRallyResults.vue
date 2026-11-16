<template>
  <!-- Earth Rally's stage-done card (docs/mockups-1.2.0/results.html), an interactive app in the stage layout, shown
       while the stream 'earthRally' says show.results (Lua: hudFrame.lua; open from the stop control until a button,
       driving off, or a timeout: runner.lua). The buttons go to earthRally_main.uiResults; Close shuts the card. -->
  <!-- a controller (1.6.2), as the game's own prompts over driving take one (its mission/activity prompt,
       ActivityStart.vue; the drag-race dial, dragDialControl): the card says the game an activity popup is up while
       it shows, which is what lets a controller's menu buttons through on the driving screen at all, and a
       no-nav scope of its own takes them -- the first button picked as it opens, the d-pad moves along them, A presses
       the picked one, B closes. The sticks and triggers stay the car's: drive off and the card closes as before. -->
  <!-- (1.7.0) A pass of a full rally: the card is the rally's (mock-up 3: your stage and class place against the
       real National field, the crews round you; Continue to the time card, Restart in Casual only, Close), and in
       Realistic mode the Recover? question (mock-up 4) comes up in it from the recovery key during the stage. -->
  <div v-if="res || ask" class="er-results" tabindex="0"
    v-bng-scoped-nav="{ scopeId: 'earthRallyResults', type: 'nonav', activateOnMount: true, trapPolicy: 'always',
      bubbleWhitelistEvents: ['menu'] }"
    v-bng-on-ui-nav:ok="pressPicked" v-bng-on-ui-nav:back="() => act(ask ? 'keep' : 'close')"
    v-bng-on-ui-nav:focus_l="() => pick(-1)" v-bng-on-ui-nav:focus_u="() => pick(-1)"
    v-bng-on-ui-nav:focus_r="() => pick(1)" v-bng-on-ui-nav:focus_d="() => pick(1)">
    <template v-if="ask">
      <div class="er-top er-ask-top"><span class="er-name">Recover?</span><span class="er-done">{{ ask.ss }} {{ ask.name }} · Realistic</span></div>
      <div class="er-ask">Recovering ends this stage. <template v-if="ask.stop">You go to <b>{{ ask.stop }}</b> under Super Rally and carry on from there.</template><template v-else>There is no service left to rejoin at: the rally ends unclassified.</template></div>
      <div class="er-buttons">
        <BngButton class="er-main" :class="{ 'er-picked': ring('recover') }" :accent="ACCENTS.main" @click="act('recover')">Recover · Super Rally</BngButton>
        <BngButton :class="{ 'er-picked': ring('keep') }" :accent="ACCENTS.secondary" @click="act('keep')">Keep going</BngButton>
      </div>
      <div class="er-foot">Press the recovery key (Backspace) again to recover. Drive on and the question goes after 10 s.</div>
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
      <BngButton class="er-main" :class="{ 'er-picked': ring('continue') }" :accent="ACCENTS.main" @click="act('continue')">{{ rc.last ? "Continue · the finish" : "Continue · time card" }}</BngButton>
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
    <div class="er-foot">{{ rc ? "Close leaves the card so you can look at the car; Ctrl+Alt+K opens the time card." : "Or just drive off: the card closes." }}</div>
    </template>
  </div>
</template>

<script setup>
import { ref, computed, watch, onUnmounted } from "vue"
import { useStreams } from "@/services/events"
import { BngButton, ACCENTS } from "@/common/components/base"
import { vBngScopedNav, vBngOnUiNav } from "@/common/directives"
import { reportState } from "@/services/stateReporter"
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
const rcClass = computed(() => {
  const st = rc.value && rc.value.stage
  const row = st && (Array.isArray(st.rows) ? st.rows : Object.values(st.rows || {})).find(r => r.you)
  return (row && row.class) || ""
})
const rcRows = computed(() => {
  const st = rc.value && rc.value.stage
  return st ? (Array.isArray(st.rows) ? st.rows : Object.values(st.rows || {})) : []
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
  if (rc.value) return rc.value.canRestart ? ["continue", "restart", "close"] : ["continue", "close"]
  return next.value ? ["next", "retry", "menu", "close"] : ["retry", "menu", "close"]
})
const picked = ref(null)
// (the pick drawn only with a controller in use, as the game's own focus ring is: a mouse player sees no ring)
const controls = useControls()
const padOn = computed(() => !!(controls && controls.focusIfController))
const ring = what => padOn.value && picked.value === what
function pick(d) {
  const o = order.value
  const i = o.indexOf(picked.value)
  picked.value = o[Math.max(0, Math.min(o.length - 1, (i < 0 ? 0 : i + d)))]
}
function pressPicked() { if (picked.value) act(picked.value) }

// While the card is up the game is told an activity popup is open (the name has the shape its popup service
// reports, /popup/<type>/<component>/aside): its input bindings turn its menu buttons on for the driving screen then,
// and a non-modal ("activity") one leaves the car's own controls alone (core/input/bindings.lua, onUIStateTriggered).
const POPUP_STATE = "/popup/activity/EarthRallyResults/aside"
let reported = false
function setReported(on) {
  if (on === reported) return
  reported = on
  try { reportState(POPUP_STATE, on) } catch (e) { /* (an older game: mouse only, as before) */ }
}
const up = computed(() => (ask.value ? "ask" : res.value ? "res" : null))
watch(up, (r, was) => {
  if (r && r !== was) picked.value = order.value[0]
  if (!r) picked.value = null
  setReported(!!r && !(f.value && f.value.preview))
}, { immediate: true })
onUnmounted(() => setReported(false))

function act(what) {
  if (f.value && f.value.preview) return
  if (window.bngApi && window.bngApi.engineLua) {
    window.bngApi.engineLua(`if earthRally_main then earthRally_main.uiResults(${JSON.stringify(what)}) end`)
  }
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
.er-rally { margin: 0 40px 10px; }
.er-rplace { display: flex; justify-content: space-between; font-size: 20px; padding: 6px 0 8px; .er-rov { color: var(--er-muted); } }
.er-rrow { display: grid; grid-template-columns: 50px minmax(0, 1fr) 80px 120px 110px; gap: 8px; padding: 4px 8px; font-size: 18px;
  border-bottom: 1px solid rgba(255, 255, 255, 0.06);
  &.me { background: #16305e; font-weight: 700; }
  &.gap { color: #6f7480; text-align: center; grid-template-columns: 1fr; }
  .er-rn { overflow: hidden; white-space: nowrap; text-overflow: ellipsis; }
  .er-v { font-size: 18px; text-align: right; } }
</style>
