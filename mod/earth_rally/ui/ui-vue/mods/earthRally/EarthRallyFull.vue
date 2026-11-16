<template>
  <!-- The full rally's two pages in the menu (1.7.0 MVP; mock-ups 1 and 2, approved 2026-11-15):
       kind "start"  the start screen: the car you're in, its class (guessed, any can be picked), Realistic or Casual,
                     cancelled stages as they really ran or all of them, Start.
       kind "card"   the time card between every stage: the running order with your times and stage places, what
                     is next (or the service you're at, with the Super Rally card after a Realistic recovery), your
                     overall place, Quit. Data: earthRally_main.uiRallyStart / uiRallyCard (store.js). -->
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
          <div class="er-muted er-small">{{ cls === s.class ? "Chosen for your car from its drivetrain." : "Your pick." }} Super Rally and your class place use it.</div>
        </div>
        <div class="er-card er-pad er-col">
          <div class="er-lbl">Mode</div>
          <div class="er-seg">
            <span tabindex="0" bng-nav-item :class="{ on: mode === 'realistic' }" @click="mode = 'realistic'" @keydown.enter="mode = 'realistic'">Realistic</span>
            <span tabindex="0" bng-nav-item :class="{ on: mode === 'casual' }" @click="mode = 'casual'" @keydown.enter="mode = 'casual'">Casual</span>
          </div>
          <div class="er-muted er-small">
            <b>Realistic</b>: no restarts. Recovering ends your stage: Super Rally penalty and back in at the next service.<br>
            <b>Casual</b>: recover onto the stage as often as you like, and restart any stage, with no penalty.
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
            <div v-if="s.saved" class="er-warn">Starting again replaces the rally you have saved here (at {{ s.saved.at }}).</div>
            <div v-if="s.inProgress && s.inProgress !== s.id" class="er-warn">Another rally is under way: quit it from its time card first.</div>
            <div class="er-muted er-small">Saves at each service. Damage stays with you until service. BeamNG's own recovery is off: Backspace is the rally's.</div>
            <BngButton v-bng-ui-nav-focus="1" class="er-wide" :accent="ACCENTS.main" :disabled="!s.car" @click="start">Start{{ s.first ? ` · ${s.first.ss} ${s.first.name}` : "" }}</BngButton>
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
                <span class="er-clip">{{ r.kind === "stage" ? r.name : (r.name || "") }}<template v-if="r.kind !== 'stage'"> · full repair · game saves</template></span>
                <span class="er-mono er-r">{{ r.kind === "stage" ? (r.timeS != null ? time(r.timeS) : (r.next ? "next" : "")) : "" }}</span>
                <span class="er-mono er-r">{{ r.pos ? `${r.pos} / ${r.of}` : "" }}</span>
              </div>
            </template>
          </div>
        </div>
        <div class="er-col er-gap">
          <!-- finished -->
          <div v-if="c.done" class="er-card er-pad">
            <h3>{{ c.unclassified ? "RALLY OVER · NOT CLASSIFIED" : "RALLY FINISHED" }}</h3>
            <div class="er-big">{{ longTime(c.totalS) }}</div>
            <div v-if="c.overall && !c.unclassified" class="er-muted">P{{ c.overall.pos }} of {{ c.overall.of }} · {{ c.class }} {{ ord(c.overall.classPos) }} of {{ c.overall.classOf }}</div>
            <div class="er-muted er-small">{{ c.unclassified ? "A Realistic recovery with no service left to rejoin at." : "Kept on the rally's Results tab." }}</div>
          </div>
          <!-- the Super Rally card, once, at the stop rejoined at -->
          <div v-else-if="c.superRally" class="er-card er-pad">
            <h3>SUPER RALLY · BACK IN AT {{ (c.superRally.at || "").toUpperCase() }}</h3>
            <div class="er-tr er-hd"><span>Missed stage</span><span></span><span class="er-r">{{ c.class }} fastest</span><span class="er-r">+ ARA</span><span class="er-r">Your time</span></div>
            <div v-for="(m, i) in arr(c.superRally.rows)" :key="i" class="er-tr er-sr">
              <span class="er-mono">{{ m.ss }}</span><span class="er-clip">{{ m.name }}</span>
              <span class="er-mono er-r">{{ time(m.classBestS) }}<small v-if="m.from !== 'class'">*</small></span>
              <span class="er-mono er-r">+{{ Math.round(m.addS / 60) }}:00</span>
              <span class="er-mono er-r">{{ time(m.timeS) }}</span>
            </div>
            <div class="er-row2"><b>Penalty on top of the class times</b><b class="er-mono">{{ time(c.superRally.addS) }}</b></div>
            <div class="er-muted er-small">ARA rule RCR 6.3.1: 10 min for the first stage missed, 7 min for each after, added to the fastest time in your class.<template v-if="arr(c.superRally.rows).some(m => m.from !== 'class')"> * no {{ c.class }} crew on that pass: the fastest National time.</template></div>
            <div class="er-muted er-small">The car is fully repaired at service. Game saved.</div>
            <BngButton v-bng-ui-nav-focus="1" class="er-wide" :accent="ACCENTS.main" :disabled="!!c.running" @click="goNext">{{ goLabel }}</BngButton>
          </div>
          <!-- next -->
          <div v-else class="er-card er-pad">
            <template v-if="c.at && c.at.kind !== 'stage'">
              <h3>{{ c.at.label.toUpperCase() }}{{ c.at.name ? ` · ${c.at.name}` : "" }}</h3>
              <div class="er-muted">The car is fully repaired. Game saved.</div>
            </template>
            <h3 v-if="c.nextStage">NEXT: {{ c.nextStage.ss }}</h3>
            <div v-if="c.nextStage">{{ c.nextStage.name }}<template v-if="c.nextStage.lengthM"> · {{ len(c.nextStage.lengthM) }}</template></div>
            <div v-if="c.at && c.at.kind === 'stage' && c.pos > 1" class="er-muted er-small">Damage carried from the last stage: it stays until service.</div>
            <div v-if="c.running" class="er-muted er-small">The stage is under way.</div>
            <BngButton v-bng-ui-nav-focus="1" class="er-wide" :accent="ACCENTS.main" :disabled="!!c.running" @click="goNext">{{ goLabel }}</BngButton>
          </div>
          <div class="er-card er-pad">
            <h3>OVERALL</h3>
            <template v-if="c.overall">
              <div class="er-row2"><span>Position</span><b>P{{ c.overall.pos }} / {{ c.overall.of }}</b></div>
              <div class="er-row2"><span>{{ c.class }}</span><b>{{ ord(c.overall.classPos) }} / {{ c.overall.classOf }}</b></div>
              <div class="er-row2"><span>Gap to leader</span><span class="er-mono">{{ c.overall.gapS > 0.05 ? "+" + longTime(c.overall.gapS) : "leading" }}</span></div>
            </template>
            <div class="er-row2"><span>Your total</span><span class="er-mono">{{ longTime(c.totalS) }}</span></div>
            <div v-if="!c.overall" class="er-muted er-small">{{ c.hasBoard ? "Places come with your first stage." : "This rally has no real results to place you against." }}</div>
            <BngButton :accent="ACCENTS.outlined" @click="quit">{{ c.done ? "Close the rally" : "Quit · resume from the last service" }}</BngButton>
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
function quit() {
  const id = c.value && c.value.id
  rallyAction("quit", id, null, r => { if (r.ok) emit("view", "rally", id) })
}
const goLabel = computed(() => {
  const x = c.value
  if (!x || !x.nextStage) return "Go"
  const out = x.at && x.at.kind !== "stage" ? "Service out · " : "Go to the start · "
  return out + x.nextStage.ss + (x.at && x.at.kind !== "stage" ? " " + x.nextStage.name : "")
})
const rowCls = r => ({ next: r.next && r.kind === "stage", svc: r.kind !== "stage", sr: r.superRally, dim: r.done && r.kind !== "stage" })
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
  &.sr { color: #ffb38a; }
  &.dim { color: #8a909a; } }
.er-hd { color: #b8bcc6; font-size: 14px; grid-template-columns: 80px minmax(0, 1fr) 110px 70px 110px; }
.er-sr { grid-template-columns: 80px minmax(0, 1fr) 110px 70px 110px; color: #ffb38a; }
.er-row2 { display: flex; justify-content: space-between; padding: 5px 0; font-size: 18px; }
.er-big { font: 700 44px "Overpass Mono", monospace; color: #f26b1d; }
</style>
