<template>
  <!-- The online leaderboard (prototype): players' own times on this stage, from the online board through the Earth
       Rally Online add-on (main.lua uiOnline, online.lua). Stock (the game's own cars as they come) and Open boards.
       Said in one card, whatever the state: off, no add-on running, no name yet, no line, or the board. -->
  <div class="er-card er-lb er-on">
    <div class="er-top">
      <h3>Online</h3>
      <div v-if="ready" class="er-tabs">
        <span v-for="b in BOARDS" :key="b.id" tabindex="0" bng-nav-item :class="{ on: board === b.id }"
          @click="pick(b.id)" @keydown.enter="pick(b.id)">{{ b.label }}</span>
      </div>
    </div>

    <div v-if="!o" class="er-empty"><b>Loading…</b></div>

    <div v-else-if="!o.status.on" class="er-empty">
      <b>The online board is off</b>
      Compare your times with everyone running Earth Rally. Sent when on: your board name, the stage, the car, the time
      and where the car went.
      <div class="er-row"><BngButton :accent="ACCENTS.main" @click="setSetting('onlineBoard', true)">Turn on</BngButton></div>
    </div>

    <div v-else-if="!o.status.connected" class="er-empty">
      <b>Can't reach the online board</b>
      Start <i>Earth Rally Online</i> on BeamNG.Earth's Add-ons page.
      <div v-if="o.status.error" class="er-why">{{ o.status.error }}</div>
    </div>

    <div v-else-if="!o.status.player || renaming" class="er-name">
      <b>{{ o.status.player ? "A new name" : "Pick a name for the online board" }}</b>
      <span class="er-muted">2 to 24 letters or numbers. Everyone sees it.</span>
      <div class="er-row">
        <input v-model="nameText" class="er-input" type="text" maxlength="24" placeholder="Your name"
          @focus="typing(true)" @blur="typing(false)" @keydown.enter="saveName" @keydown.stop @keyup.stop />
        <BngButton :accent="ACCENTS.main" :disabled="naming || nameText.trim().length < 2" @click="saveName">Save</BngButton>
        <BngButton v-if="o.status.player" :accent="ACCENTS.outlined" @click="renaming = false">Cancel</BngButton>
      </div>
      <div v-if="o.naming && o.naming.error && !naming" class="er-why">{{ o.naming.error }}</div>
    </div>

    <div v-else-if="!o.hasLine" class="er-empty"><b>No line yet</b>Run the auto recce or drive a recce first: the board
      finds this stage by where its line starts and finishes.</div>

    <template v-else>
      <div v-if="lastNote" class="er-note" :class="{ bad: lastBad }">{{ lastNote }}</div>
      <div v-if="data && data.you" class="er-you-line">
        <span class="er-p">{{ ord(data.you.pos) }}<small>of {{ data.of }}</small></span>
        <span>{{ youGap }}</span>
      </div>
      <div v-else-if="data && data.of" class="er-you-line"><span>{{ data.of }} {{ data.of === 1 ? "time" : "times" }} on {{ boardLabel }}. Drive it to be placed.</span></div>

      <div v-if="!data && b.asking" class="er-empty"><b>Loading…</b></div>
      <div v-else-if="!data && b.error" class="er-empty"><b>The board did not answer</b><span class="er-why">{{ b.error }}</span></div>
      <div v-else-if="data && !data.of" class="er-empty"><b>No times yet</b>Be the first on the {{ boardLabel }} board.</div>
      <template v-else-if="data">
        <div class="er-trow er-hdr"><span>Pos</span><span>Driver</span><span>Car</span><span class="er-r">Time</span><span class="er-r">Gap</span></div>
        <template v-for="(r, i) in arr(data.rows)" :key="i">
          <div v-if="r.skipped" class="er-trow er-gap"><span>⋮</span></div>
          <div class="er-trow" :class="{ me: r.you }">
            <span class="er-pos">{{ r.pos }}</span><span class="er-clip">{{ r.name }}</span><span class="er-cls er-clip">{{ r.car }}</span>
            <span class="er-t">{{ time(r.timeMs / 1000) }}</span><span class="er-g">{{ gap(r.gapMs / 1000) }}</span>
          </div>
        </template>
      </template>
      <div class="er-foot">
        <span>As <b>{{ o.status.player.name }}</b> · <span class="er-link" tabindex="0" bng-nav-item @click="startRename" @keydown.enter="startRename">rename</span></span>
        <span>Unverified times<template v-if="o.status.queued"> · {{ o.status.queued }} waiting to send</template></span>
      </div>
    </template>
  </div>
</template>

<script setup>
import { ref, computed, watch, onMounted, onUnmounted } from "vue"
import { BngButton, ACCENTS } from "@/common/components/base"
import { arr, time, gap, ord, setSetting, loadOnline, onlineName, typing } from "./store.js"

const props = defineProps({
  eventId: { type: String, required: true },
  stageId: { type: String, required: true },
})
const BOARDS = [{ id: "stock", label: "Stock" }, { id: "open", label: "Open" }]
const POLL_MS = 2000

const o = ref(null)
const board = ref("stock")
const nameText = ref("")
const naming = ref(false)
const renaming = ref(false)

const b = computed(() => (o.value && o.value.board) || {})
const data = computed(() => b.value.data || null)
const ready = computed(() => o.value && o.value.status.on && o.value.status.connected && o.value.status.player && !renaming.value && o.value.hasLine)
const boardLabel = computed(() => (BOARDS.find(x => x.id === board.value) || BOARDS[0]).label)
const youGap = computed(() => {
  const d = data.value
  if (!d || !d.you) return ""
  const lead = arr(d.rows)[0]
  if (!lead || d.you.pos === 1) return "fastest"
  return `${gap((d.you.timeMs - lead.timeMs) / 1000)} to the fastest`
})
// the last run sent, said once on this stage's board
const lastNote = computed(() => {
  const l = o.value && o.value.last
  if (!l) return ""
  if (l.queued) return "Your last run is waiting to send: the board could not be reached."
  if (!l.ok) return `Your last run was not sent: ${l.error || "no answer"}`
  if (l.status === "flagged") return `Your last run is held for a look (${arr(l.flags).join(", ")}). It shows once it is cleared.`
  const label = l.board === "open" ? "Open" : "Stock"
  return `Your last run: ${ord(l.pos)} of ${l.of} on ${label}${l.stage && l.stage.name ? ` (${l.stage.name})` : ""}.`
})
const lastBad = computed(() => { const l = o.value && o.value.last; return !!l && (!l.ok || l.status === "flagged") })

function refresh(force) {
  loadOnline(props.eventId, props.stageId, board.value, force, r => {
    if (!r) return
    o.value = r
    if (naming.value && r.naming && !r.naming.asking) {
      naming.value = false
      if (r.naming.ok) renaming.value = false
    }
  })
}
function pick(id) { board.value = id; refresh(false) }
function saveName() {
  const n = nameText.value.trim()
  if (n.length < 2 || naming.value) return
  naming.value = true
  onlineName(n, () => refresh(false))
}
function startRename() { nameText.value = (o.value && o.value.status.player && o.value.status.player.name) || ""; renaming.value = true }

let timer = null
onMounted(() => { refresh(true); timer = setInterval(() => refresh(false), POLL_MS) })
onUnmounted(() => { if (timer) clearInterval(timer); typing(false) })
watch(() => [props.eventId, props.stageId], () => { o.value = null; refresh(true) })
</script>

<style lang="scss" scoped>
.er-card { background: rgba(0, 0, 0, 0.6); border-radius: 0.5rem; }
.er-muted { color: var(--er-muted); }
.er-clip { overflow: hidden; white-space: nowrap; text-overflow: ellipsis; }
.er-lb { padding: 20px 0 10px; }
.er-top { display: flex; align-items: center; gap: 16px; padding: 0 26px 12px;
  h3 { margin: 0; font-size: 20px; } }
.er-tabs { margin-left: auto; display: flex; gap: 4px; background: rgba(0, 0, 0, 0.45); border-radius: 0.25rem; padding: 4px;
  span { padding: 5px 16px; border-radius: 3px; font-size: 16px; font-weight: 600; color: var(--er-muted); cursor: pointer; }
  span.on { background: var(--er-orange-500); color: #fff; } }
.er-you-line { display: flex; align-items: baseline; gap: 14px; padding: 0 26px 12px; font-size: 18px; color: var(--er-muted);
  .er-p { font: 700 34px "Overpass Mono", monospace; color: #fff;
    small { font-size: 18px; color: var(--er-muted); font-weight: 400; margin-left: 6px; } } }
.er-note { margin: 0 26px 10px; padding: 10px 14px; border-radius: 0.25rem; background: rgba(31, 143, 255, 0.16); color: #cfe6ff; font-size: 16px;
  &.bad { background: rgba(255, 211, 107, 0.12); color: #ffd36b; } }
.er-empty { padding: 40px 26px 50px; text-align: center; font-size: 18px; color: var(--er-muted); line-height: 1.45;
  b { display: block; color: #fff; font-size: 24px; margin-bottom: 6px; } }
.er-why { display: block; margin-top: 10px; font-size: 15px; color: var(--er-dim); }
.er-row { display: flex; justify-content: center; gap: 10px; margin-top: 16px; }
.er-name { display: flex; flex-direction: column; gap: 6px; padding: 10px 26px 24px; font-size: 17px;
  b { font-size: 22px; } .er-row { justify-content: flex-start; } }
.er-input { flex: 1; min-width: 0; padding: 8px 12px; font-size: 18px; color: #fff; background: rgba(0, 0, 0, 0.5);
  border: 1px solid #5a6070; border-radius: 0.25rem;
  &:focus { outline: 2px solid var(--er-orange); outline-offset: 1px; } }
.er-trow { display: grid; grid-template-columns: 54px minmax(0, 1fr) minmax(0, 0.8fr) 110px 100px; align-items: center; height: 36px; padding: 0 26px; font-size: 17px; border-left: 4px solid transparent; column-gap: 8px;
  & + .er-trow { border-top: 1px solid rgba(255, 255, 255, 0.06); }
  &.er-hdr { height: 30px; font-size: 12px; letter-spacing: 0.08em; text-transform: uppercase; color: var(--er-muted); }
  &.me { background: rgba(199, 91, 30, 0.26); border-left-color: var(--er-orange); font-weight: 700; .er-pos { color: #fff; } }
  &.er-gap { height: 20px; color: #6f7480; font-size: 16px; line-height: 1; }
  .er-r { text-align: right; }
  .er-pos { font-family: "Overpass Mono", monospace; font-weight: 700; color: var(--er-muted); }
  .er-cls { font-size: 14px; font-weight: 600; color: var(--er-muted); }
  .er-t { font-family: "Overpass Mono", monospace; font-weight: 600; text-align: right; }
  .er-g { font-family: "Overpass Mono", monospace; text-align: right; color: var(--er-muted); font-size: 15px; }
}
.er-foot { display: flex; justify-content: space-between; gap: 12px; padding: 12px 26px 2px; font-size: 14px; color: var(--er-dim);
  b { color: var(--er-muted); } }
.er-link { color: var(--er-muted); text-decoration: underline; cursor: pointer; }
.er-link:focus { outline: 2px solid var(--er-orange); outline-offset: 2px; }
</style>
