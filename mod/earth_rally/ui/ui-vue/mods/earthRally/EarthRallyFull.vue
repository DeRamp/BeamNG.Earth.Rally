<template>
  <!-- The full rally's two pages in the menu (1.7.0; mock-ups 1 and 2, approved 2026-11-15, trimmed after the first
       drive, #24):
       kind "start"  the start screen: the car you're in, its class (guessed, any can be picked), Realistic or Casual,
                     cancelled stages as they really ran or all of them, Start (at the rally's start on the map).
       kind "card"   the time card: the running order with your times and stage places, where you are (getting the
                     stages ready, at a service, on a transit, on a stage) with its one button, the Super Rally card
                     after a Realistic recovery, your overall place, and Leave rally / Retire, each with a confirm
                     (#28). Data: earthRally_main.uiRallyStart / uiRallyCard (store.js). -->
  <section class="er-full">
    <!-- ===== start ===== -->
    <template v-if="kind === 'start'">
      <div v-if="!s" class="er-muted">Loading...</div>
      <div v-else-if="!s.canRun" class="er-card er-pad">{{ s.why }}</div>
      <div v-else class="er-two">
        <div class="er-card er-pad">
          <h2>{{ s.name }}</h2>
          <div class="er-muted">{{ s.stages }} stages · {{ s.days }} {{ s.days === 1 ? "day" : "days" }} · {{ s.services }} {{ s.services === 1 ? "service" : "services" }}<template v-if="s.crews"> · real field: {{ s.crews }} National crews</template></div>
          <div class="er-lbl">Car</div>
          <div class="er-box"><span>{{ s.car ? s.car.name : "Get in a car first" }}</span><span v-if="s.car && s.car.drivetrain" class="er-muted">{{ s.car.drivetrain }}</span></div>
          <div class="er-lbl">Class</div>
          <div class="er-seg er-wrap">
            <span v-for="c in arr(s.classes)" :key="c" tabindex="0" bng-nav-item :class="{ on: cls === c }" @click="cls = c" @keydown.enter="cls = c">{{ c }}</span>
          </div>
          <div class="er-muted er-small">{{ cls === s.class ? "Picked from your car's drivetrain." : "Your pick." }}</div>
        </div>
        <div class="er-card er-pad er-col">
          <div class="er-lbl">Mode</div>
          <div class="er-seg">
            <span tabindex="0" bng-nav-item :class="{ on: mode === 'realistic' }" @click="mode = 'realistic'" @keydown.enter="mode = 'realistic'">Realistic</span>
            <span tabindex="0" bng-nav-item :class="{ on: mode === 'casual' }" @click="mode = 'casual'" @keydown.enter="mode = 'casual'">Casual</span>
          </div>
          <div class="er-muted er-small">
            <template v-if="mode === 'realistic'">No restarts. Recovering ends your stage: Super Rally penalty, back in at the next service.</template>
            <template v-else>Recover as often as you like and restart any stage.</template>
          </div>
          <template v-if="arr(s.cancelled).length">
            <div class="er-lbl">Cancelled stages</div>
            <div class="er-seg">
              <span tabindex="0" bng-nav-item :class="{ on: canc === 'real' }" @click="canc = 'real'" @keydown.enter="canc = 'real'">As it really ran</span>
              <span tabindex="0" bng-nav-item :class="{ on: canc === 'all' }" @click="canc = 'all'" @keydown.enter="canc = 'all'">Run them all</span>
            </div>
            <div class="er-muted er-small">{{ arr(s.cancelled).join(", ") }} {{ arr(s.cancelled).length === 1 ? "was" : "were" }} cancelled on the day.</div>
          </template>
          <div class="er-foot">
            <div v-if="s.toRecce" class="er-muted er-small">{{ s.toRecce }} {{ s.toRecce === 1 ? "stage gets its" : "stages get their" }} line first: the auto recce takes you to each.</div>
            <div v-if="arr(s.heldOut).length" class="er-warn er-small">Held out, road missing from the map: {{ arr(s.heldOut).map(h => h.name).join(", ") }}</div>
            <div v-if="s.saved" class="er-warn">This replaces your saved rally (at {{ s.saved.at }}).</div>
            <div v-if="s.inProgress && s.inProgress !== s.id" class="er-warn">Another rally is under way: leave it from its time card first.</div>
            <BngButton v-bng-ui-nav-focus="1" class="er-wide" :accent="ACCENTS.main" :disabled="!s.car" @click="start">Start{{ s.start ? ` · at ${s.start}` : "" }}</BngButton>
          </div>
        </div>
      </div>
    </template>

    <!-- ===== time card ===== -->
    <template v-else>
      <div v-if="!c" class="er-muted">Loading...</div>
      <div v-else-if="c.none" class="er-card er-pad">No rally is under way.</div>
      <div v-else class="er-two er-card-grid">
        <div class="er-card er-pad er-tc">
          <div class="er-tc-head"><h2>{{ c.name }}</h2><span class="er-mode">{{ c.mode === "realistic" ? "Realistic" : "Casual" }} · {{ c.class }}</span></div>
          <div class="er-tc-rows">
            <template v-for="(r, i) in arr(c.rows)" :key="i">
              <div v-if="dayHead(i)" class="er-day">Day {{ r.day }}</div>
              <div class="er-tr" :class="rowCls(r)">
                <span class="er-mono">{{ r.label }}</span>
                <span class="er-clip">{{ r.name || "" }}</span>
                <span class="er-mono er-r">{{ r.kind === "stage" ? (r.timeS != null ? time(r.timeS) : (r.next ? "next" : "")) : "" }}</span>
                <span class="er-mono er-r">{{ r.pos ? `${r.pos} / ${r.of}` : "" }}</span>
              </div>
            </template>
          </div>
          <div v-if="arr(c.heldOut).length" class="er-muted er-small">Held out, road missing from the map: {{ arr(c.heldOut).map(h => h.ss).join(", ") }}</div>
        </div>
        <div class="er-col er-gap">
          <!-- finished -->
          <div v-if="c.done" class="er-card er-pad">
            <h3>{{ c.unclassified ? "RALLY OVER · NOT CLASSIFIED" : "RALLY FINISHED" }}</h3>
            <div class="er-big">{{ longTime(c.totalS) }}</div>
            <div v-if="c.overall && !c.unclassified" class="er-muted">P{{ c.overall.pos }} of {{ c.overall.of }} · {{ c.class }} {{ ord(c.overall.classPos) }} of {{ c.overall.classOf }}</div>
          </div>
          <!-- the Super Rally card, once, at the service rejoined at -->
          <div v-else-if="c.superRally && c.phase === 'stop'" class="er-card er-pad">
            <h3>SUPER RALLY · BACK IN AT {{ (c.superRally.at || "").toUpperCase() }}</h3>
            <div class="er-tr er-hd"><span>Missed</span><span></span><span class="er-r">{{ c.class }} fastest</span><span class="er-r">+</span><span class="er-r">Your time</span></div>
            <div v-for="(m, i) in arr(c.superRally.rows)" :key="i" class="er-tr er-sr">
              <span class="er-mono">{{ m.ss }}</span><span class="er-clip">{{ m.name }}</span>
              <span class="er-mono er-r">{{ time(m.classBestS) }}<small v-if="m.from !== 'class'">*</small></span>
              <span class="er-mono er-r">+{{ Math.round(m.addS / 60) }}:00</span>
              <span class="er-mono er-r">{{ time(m.timeS) }}</span>
            </div>
            <div class="er-row2"><b>Penalty</b><b class="er-mono">{{ time(c.superRally.addS) }}</b></div>
            <div v-if="arr(c.superRally.rows).some(m => m.from !== 'class')" class="er-muted er-small">* no {{ c.class }} crew on that pass: the fastest National time.</div>
            <BngButton v-bng-ui-nav-focus="1" class="er-wide" :accent="ACCENTS.main" @click="goNext">{{ goLabel }}</BngButton>
          </div>
          <!-- where you are and what is next -->
          <div v-else class="er-card er-pad">
            <template v-if="c.phase === 'prep'">
              <h3>GETTING THE STAGES READY</h3>
              <div v-if="c.prep && c.prep.name">Auto recce: {{ c.prep.name }} ({{ c.prep.i }} of {{ c.prep.of }})</div>
            </template>
            <template v-else-if="c.phase === 'moving'">
              <h3>ON THE WAY TO {{ (c.at && c.at.label || "").toUpperCase() }}</h3>
            </template>
            <template v-else-if="c.phase === 'stop'">
              <h3>{{ (c.at.label || "").toUpperCase() }}{{ c.at.name ? ` · ${c.at.name}` : "" }}</h3>
              <div v-if="c.nextStage">Next: {{ c.nextStage.ss }} {{ c.nextStage.name }}<template v-if="c.nextStage.lengthM"> · {{ len(c.nextStage.lengthM) }}</template></div>
            </template>
            <template v-else-if="c.phase === 'transit' || c.phase === 'toStop'">
              <h3>TRANSIT</h3>
              <div v-if="c.transit">To {{ c.transit.name }}<template v-if="c.transit.distM != null"> · {{ len(c.transit.distM) }}</template></div>
              <div class="er-muted er-small">Follow the arrows.</div>
            </template>
            <template v-else-if="c.phase === 'toGo'">
              <h3>NEXT: {{ (c.at && c.at.label || "").toUpperCase() }}</h3>
            </template>
            <template v-else-if="c.phase === 'stage'">
              <h3>{{ c.at ? c.at.label : "" }} UNDER WAY</h3>
              <div v-if="c.at">{{ c.at.name }}</div>
            </template>
            <BngButton v-if="c.phase !== 'prep' && c.phase !== 'moving'" v-bng-ui-nav-focus="1" class="er-wide" :accent="ACCENTS.main" @click="goNext">{{ goLabel }}</BngButton>
          </div>
          <div class="er-card er-pad">
            <h3>OVERALL</h3>
            <template v-if="c.overall">
              <div class="er-row2"><span>Position</span><b>P{{ c.overall.pos }} / {{ c.overall.of }}</b></div>
              <div class="er-row2"><span>{{ c.class }}</span><b>{{ ord(c.overall.classPos) }} / {{ c.overall.classOf }}</b></div>
              <div class="er-row2"><span>Gap to leader</span><span class="er-mono">{{ c.overall.gapS > 0.05 ? "+" + longTime(c.overall.gapS) : "leading" }}</span></div>
            </template>
            <div class="er-row2"><span>Your total</span><span class="er-mono">{{ longTime(c.totalS) }}</span></div>
          </div>
          <!-- leaving: continue later, or retire (#28) -->
          <div class="er-card er-pad">
            <BngButton v-if="c.done" :accent="ACCENTS.outlined" @click="leave">Close the rally</BngButton>
            <template v-else-if="ask === 'leave'">
              <h3>LEAVE THE RALLY?</h3>
              <div>You continue later from {{ c.leave ? c.leave.at : "the last service" }}.</div>
              <div v-if="c.leave && c.leave.superRally" class="er-warn">{{ c.leave.superRally }} is under way: it is scored under Super Rally.</div>
              <div v-if="c.leave && arr(c.leave.redo).length" class="er-warn">{{ arr(c.leave.redo).join(", ") }}: driven again.</div>
              <div class="er-btns">
                <BngButton v-bng-ui-nav-focus="1" :accent="ACCENTS.main" @click="leave">Leave rally</BngButton>
                <BngButton :accent="ACCENTS.outlined" @click="ask = null">Cancel</BngButton>
              </div>
            </template>
            <template v-else-if="ask === 'retire'">
              <h3>RETIRE FROM THE RALLY?</h3>
              <div>Your progress in this rally is deleted.</div>
              <div class="er-btns">
                <BngButton v-bng-ui-nav-focus="1" :accent="ACCENTS.main" @click="retire">Retire</BngButton>
                <BngButton :accent="ACCENTS.outlined" @click="ask = null">Cancel</BngButton>
              </div>
            </template>
            <div v-else class="er-btns">
              <BngButton :accent="ACCENTS.outlined" @click="ask = 'leave'">Leave rally</BngButton>
              <BngButton :accent="ACCENTS.outlined" @click="ask = 'retire'">Retire</BngButton>
            </div>
          </div>
        </div>
      </div>
    </template>
    <div v-if="busyMsg" class="er-msg">{{ busyMsg }}</div>
  </section>
</template>

<script setup>
import { ref, computed, watch } from "vue"
import { BngButton, ACCENTS } from "@/common/components/base"
import { vBngUiNavFocus } from "@/common/directives"
import { rallyStart, rallyCard, rallyAction, busyMsg, arr, len, time, longTime, ord } from "./store.js"

const props = defineProps({ kind: { type: String, default: "card" }, id: { type: String, default: null } })
const emit = defineEmits(["view"])

const s = computed(() => (rallyStart.value && rallyStart.value.id === props.id ? rallyStart.value : null))
const c = computed(() => rallyCard.value)

const mode = ref("realistic")
const canc = ref("real")
const cls = ref("L4WD")
watch(s, (x, was) => { if (x && (!was || was.id !== x.id)) cls.value = x.class || "L4WD" }, { immediate: true })

function start() {
  rallyAction("start", props.id, { mode: mode.value, class: cls.value, cancelled: canc.value }, r => {
    if (r.ok) emit("view", r.view || "timecard")
  })
}
function goNext() { rallyAction("go", c.value && c.value.id, null) }
// the confirm up: null, 'leave' or 'retire' (taken down when the rally moves on)
const ask = ref(null)
watch(() => c.value && c.value.phase, () => { ask.value = null })
function leave() {
  const id = c.value && c.value.id
  rallyAction("quit", id, null, r => { if (r.ok) emit("view", "rally", id) })
}
function retire() {
  const id = c.value && c.value.id
  rallyAction("abandon", id, null, r => { if (r.ok) emit("view", "rally", id) })
}
const goLabel = computed(() => {
  const x = c.value
  if (!x) return "Go"
  const nx = x.nextStage ? `${x.nextStage.ss} ${x.nextStage.name}` : "the next stage"
  switch (x.phase) {
    case "stop": return x.at && x.at.kind === "start" ? `Drive to ${nx}` : `Service out · drive to ${nx}`
    case "toGo": return `Go to ${x.at ? x.at.label : "the next stop"}`
    case "stage": return "Back to the stage"
    default: return "Back to driving"
  }
})
const rowCls = r => ({ next: r.next && r.kind === "stage", svc: r.kind !== "stage", here: r.next && r.kind !== "stage", sr: r.superRally, dim: r.done && r.kind !== "stage" })
const dayHead = i => {
  const rows = arr(c.value && c.value.rows)
  const r = rows[i]
  if (!r || r.kind !== "stage" || !r.day) return false
  for (let j = i - 1; j >= 0; j--) if (rows[j].kind === "stage") return rows[j].day !== r.day
  return true
}
</script>

<style lang="scss" scoped>
.er-full { color: #f0f0f0; }
.er-card { background: rgba(0, 0, 0, 0.6); border-radius: 0.5rem; }
.er-pad { padding: 22px 26px; }
.er-two { display: grid; grid-template-columns: minmax(0, 1fr) minmax(0, 1fr); gap: 24px; align-items: start; }
.er-card-grid { grid-template-columns: minmax(0, 1.6fr) minmax(0, 1fr); }
.er-col { display: flex; flex-direction: column; }
.er-gap { gap: 20px; }
h2 { margin: 0 0 6px; font-size: 30px; }
h3 { margin: 0 0 10px; font-size: 20px; letter-spacing: 0.04em; }
.er-muted { color: #b8bcc6; }
.er-small { font-size: 15px; margin-top: 8px; line-height: 1.5; }
.er-lbl { margin: 18px 0 6px; font-size: 14px; text-transform: uppercase; letter-spacing: 0.08em; color: #b8bcc6; }
.er-box { display: flex; justify-content: space-between; padding: 10px 14px; border: 1px solid #555; border-radius: 0.25rem; background: rgba(255, 255, 255, 0.04); font-size: 18px; }
.er-seg { display: flex; gap: 4px; background: rgba(0, 0, 0, 0.45); border-radius: 0.25rem; padding: 4px;
  span { flex: 1; text-align: center; padding: 8px 14px; border-radius: 3px; font-size: 18px; font-weight: 600; color: #b8bcc6; cursor: pointer; }
  span.on { background: #c75b1e; color: #fff; }
  span:focus { outline: 2px solid #f26b1d; outline-offset: 2px; } }
.er-wrap { flex-wrap: wrap; span { flex: 0 0 auto; } }
.er-foot { margin-top: 24px; }
.er-wide { width: 100%; margin-top: 14px; }
.er-btns { display: flex; gap: 12px; margin-top: 14px; }
.er-warn { color: #ffd36b; margin-bottom: 8px; }
.er-msg { margin-top: 12px; color: #ffd36b; }
.er-mono { font-family: "Overpass Mono", monospace; }
.er-r { text-align: right; }
.er-clip { overflow: hidden; white-space: nowrap; text-overflow: ellipsis; }
.er-tc-head { display: flex; align-items: baseline; gap: 16px; .er-mode { margin-left: auto; color: #b8bcc6; } }
.er-tc-rows { margin-top: 8px; }
.er-day { margin: 14px 0 4px; font-size: 14px; text-transform: uppercase; letter-spacing: 0.1em; color: #f26b1d; font-weight: 700; }
.er-tr { display: grid; grid-template-columns: 110px minmax(0, 1fr) 120px 100px; gap: 10px; padding: 7px 10px; font-size: 18px; border-bottom: 1px solid rgba(255, 255, 255, 0.06); align-items: center;
  &.next { background: #2a6df4; color: #fff; font-weight: 600; border-radius: 3px; }
  &.svc { background: rgba(120, 50, 40, 0.35); }
  &.here { outline: 2px solid #2a6df4; outline-offset: -2px; font-weight: 600; }
  &.sr { color: #ffb38a; }
  &.dim { color: #8a909a; } }
.er-hd { color: #b8bcc6; font-size: 14px; grid-template-columns: 80px minmax(0, 1fr) 110px 70px 110px; }
.er-sr { grid-template-columns: 80px minmax(0, 1fr) 110px 70px 110px; color: #ffb38a; }
.er-row2 { display: flex; justify-content: space-between; padding: 5px 0; font-size: 18px; }
.er-big { font: 700 44px "Overpass Mono", monospace; color: #f26b1d; }
</style>
