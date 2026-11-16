<template>
  <!-- Drive rally (1.7.0, #39; docs/mockups-1.7.0/home.html, moment pick): a card for every rally that can run as a
       full rally (an event file), a tag on one saved, under way or finished, and the picked one's panel with one big
       button: Continue for a saved rally, Time card for the one under way, else Start the rally (the start screen).
       A controller: moving onto a card picks it, A on a card presses the big button, Y opens its Results.
       A mouse: a click picks, a double click (or the big button) goes. Data: menu.lua M.drive (store.js loadDrive),
       the panel's numbers from uiRallyStart (rallyRun.startInfo), asked for as a card is picked. -->
  <section class="er-pk">
    <div class="er-pk-cards">
      <div v-for="(r, i) in list" :key="r.id" class="er-pk-rc" :class="{ on: r.id === selId }" tabindex="0" bng-nav-item
        v-bng-ui-nav-focus="r.id === firstId ? 1 : undefined"
        @focus="choose(r.id)" @click="e => (e.detail > 0 ? choose(r.id) : go(r))" @dblclick="go(r)" @keydown.enter.self="go(r)">
        <svg class="er-pk-art" viewBox="0 0 400 300" preserveAspectRatio="xMidYMid slice">
          <rect width="400" height="300" :fill="ART[i % ART.length].bg"/>
          <path :d="ART[i % ART.length].road" stroke="#e8d6b0" stroke-width="5" fill="none" opacity=".85"/>
        </svg>
        <img v-if="cover(r) && !bad[r.id]" class="er-pk-img" :src="cover(r)" alt="" @error="bad[r.id] = true" />
        <div class="er-pk-shade"></div>
        <div v-if="tag(r)" class="er-pk-tag" :class="tag(r).cls">{{ tag(r).text }}</div>
        <h3 :title="r.name">{{ r.name }}</h3>
        <div class="er-pk-m">{{ meta(r) }}</div>
      </div>
      <div v-if="drive && !list.length" class="er-card er-pk-none">
        No rally here can run as a full rally yet: that needs a rally file with its event file (the itinerary and the
        time controls). Every stage is still under <b>Drive stage</b>.
      </div>
      <div v-else-if="!drive" class="er-muted">Loading...</div>
    </div>

    <div v-if="cur" class="er-card er-pk-detail">
      <h2 :title="cur.name">{{ cur.name }}</h2>
      <div class="er-pk-sub">{{ subLine }}</div>
      <div class="er-pk-facts">
        <div><b>{{ info ? info.stages : cur.stages }}</b><span>stages</span></div>
        <div><b>{{ lenNum(cur.lengthM) }}</b><span>{{ units() }} of stages</span></div>
        <div><b>{{ info ? info.days : "–" }}</b><span>{{ info && info.days === 1 ? "day" : "days" }}</span></div>
      </div>
      <div class="er-pk-lines">
        <div v-if="info">{{ info.services }} {{ info.services === 1 ? "service" : "services" }}<template v-if="info.start"> · starts at {{ info.start }}</template></div>
        <div v-if="cur.saved"><b>Saved</b> at {{ cur.saved.at }} · {{ MODE[cur.saved.mode] || cur.saved.mode }} · {{ cur.saved.class }} · {{ cur.saved.done }} {{ cur.saved.done === 1 ? "stage" : "stages" }} done</div>
        <div v-if="cur.finished"><b>Best</b> {{ longTime(cur.finished.totalS) }}<template v-if="cur.finished.pos"> · P{{ cur.finished.pos }} of {{ cur.finished.of }}</template><template v-if="cur.finished.unclassified"> · not classified</template> · {{ MODE[cur.finished.mode] || cur.finished.mode }}</div>
        <div v-if="info && info.toRecce" class="er-muted">{{ info.toRecce }} {{ info.toRecce === 1 ? "stage gets its" : "stages get their" }} line first: the auto recce takes you to each.</div>
        <div v-if="info && arr(info.heldOut).length" class="er-pk-warn">Held out, road missing from the map: {{ arr(info.heldOut).map(h => h.name).join(", ") }}</div>
        <div v-if="other" class="er-pk-warn">{{ other.name }} is under way: leave it from its time card first.</div>
      </div>
      <EarthRallyPic class="er-pk-pic" :url="(cur.media && (cur.media.photo || cur.media.cover)) || ''"
        :kind="cur.season && cur.season.round ? `ROUND ${cur.season.round}` : 'RALLY'" :name="cur.name" />
      <BngButton class="er-pk-big" :accent="ACCENTS.main" :disabled="busy && !isActive(cur)" @click="go(cur)">{{ mainLabel(cur) }}</BngButton>
      <div v-if="cur.saved || cur.board" class="er-pk-subbtns">
        <BngButton v-if="cur.saved && !isActive(cur)" :accent="ACCENTS.outlined" :disabled="busy" @click="emit('start', cur.id)">Start again</BngButton>
        <BngButton v-if="cur.board" :accent="ACCENTS.outlined" @click="emit('results', cur.id)">Results</BngButton>
      </div>
      <div v-if="cur.saved && !isActive(cur)" class="er-pk-note">Start again goes to the start screen (car, class, mode) and replaces the save.</div>
    </div>
  </section>
</template>

<script setup>
import { ref, computed, watch } from "vue"
import { BngButton, ACCENTS } from "@/common/components/base"
import { vBngUiNavFocus } from "@/common/directives"
import EarthRallyPic from "./EarthRallyPic.vue"
import { state, drive, rallyStart, loadRallyStart, arr, lenNum, units, longTime, ord, days } from "./store.js"

defineProps({ busy: { type: Boolean, default: false } })
const emit = defineEmits(["start", "continue", "card", "results"])

const MODE = { realistic: "Realistic", casual: "Casual" }
// drawn art for a card with no cover of its own (the mock-up's): four grounds, four roads, in turn
const ART = [
  { bg: "#4f6f6a", road: "M20 250 C90 200 140 230 200 170 S320 120 390 140" },
  { bg: "#8a6a45", road: "M30 230 C100 160 170 220 240 150 S330 90 380 110" },
  { bg: "#3f6a45", road: "M20 200 C110 250 160 150 230 190 S340 230 390 160" },
  { bg: "#5a6f86", road: "M40 240 L140 240 L140 150 L300 150 L300 80" },
]
const list = computed(() => arr(drive.value && drive.value.rallies))
const active = computed(() => (state.value && state.value.rallyActive) || null)
const isActive = r => !!(r && active.value && active.value.id === r.id)
const bad = ref({})
const cover = r => (r.media && (r.media.cover || r.media.photo)) || ""

// the picked rally: the one under way, else the last saved, else the first
const selId = ref(null)
const firstId = computed(() => {
  const l = list.value
  if (!l.length) return null
  const a = active.value && l.find(r => r.id === active.value.id)
  if (a) return a.id
  let best = null
  for (const r of l) if (r.saved && (!best || String(r.saved.savedAt || "") > String(best.saved.savedAt || ""))) best = r
  return (best || l[0]).id
})
const cur = computed(() => list.value.find(r => r.id === selId.value) || list.value.find(r => r.id === firstId.value) || null)
watch(() => cur.value && cur.value.id, id => { if (id) loadRallyStart(id) }, { immediate: true })
function choose(id) { selId.value = id }
const info = computed(() => (rallyStart.value && cur.value && rallyStart.value.id === cur.value.id && !rallyStart.value.missing) ? rallyStart.value : null)
const other = computed(() => (active.value && cur.value && !isActive(cur.value) && !active.value.done) ? active.value : null)

function tag(r) {
  if (isActive(r)) return { text: active.value.done ? "Finished · time card" : "Under way", cls: "" }
  if (r.saved) return { text: `Saved · ${r.saved.at}`, cls: "" }
  if (r.finished) return { text: r.finished.pos ? `Finished · ${ord(r.finished.pos)}` : "Finished", cls: "done" }
  return null
}
function meta(r) {
  const head = r.season && r.season.round ? `Round ${r.season.round}` : null
  return [head, `${r.stages} ${r.stages === 1 ? "stage" : "stages"}`, days(r.dates, true)].filter(Boolean).join(" · ")
}
const subLine = computed(() => {
  const r = cur.value
  if (!r) return ""
  const parts = []
  if (r.season) parts.push(r.season.round ? `Round ${r.season.round} of ${r.season.name}` : r.season.name)
  else if (r.place) parts.push(r.place)
  if (info.value && info.value.crews) parts.push(`real field: ${info.value.crews} National crews`)
  return parts.join(" · ")
})
function mainLabel(r) {
  if (isActive(r)) return "Time card"
  if (r.saved) return `Continue · ${r.saved.at}`
  return "Start the rally"
}
// the big button (and A on a card): the time card, Continue, or the start screen
function go(r) {
  if (!r) return
  selId.value = r.id
  if (isActive(r)) emit("card")
  else if (r.saved) emit("continue", r.id)
  else emit("start", r.id)
}
// Y (EarthRally.vue passes the controller's context button here): the picked rally's Results
function results() { if (cur.value && cur.value.board) emit("results", cur.value.id) }
const hasResults = computed(() => !!(cur.value && cur.value.board))
defineExpose({ results, hasResults })
</script>

<style lang="scss" scoped>
.er-card { background: rgba(0, 0, 0, 0.6); border-radius: 0.5rem; }
.er-muted { color: var(--er-muted); }
.er-pk { display: grid; grid-template-columns: minmax(0, 1fr) 640px; gap: 28px; height: 100%; min-height: 640px; }
.er-pk-cards { display: grid; grid-template-columns: repeat(3, minmax(0, 1fr)); gap: 20px; align-content: start; overflow-y: auto; padding: 4px; margin: -4px; }
.er-pk-rc { position: relative; height: 300px; border-radius: 10px; overflow: hidden; display: flex; flex-direction: column; justify-content: flex-end;
  padding: 18px 20px; cursor: pointer; min-width: 0;
  &.on, &:hover, &:focus { outline: 4px solid var(--er-orange); outline-offset: -4px; }
  > :not(.er-pk-art):not(.er-pk-img):not(.er-pk-shade):not(.er-pk-tag) { position: relative; }
  h3 { margin: 0; font-size: 26px; text-transform: uppercase; letter-spacing: 0.02em; white-space: nowrap; overflow: hidden; text-overflow: ellipsis; }
}
.er-pk-art, .er-pk-img, .er-pk-shade { position: absolute; inset: 0; width: 100%; height: 100%; }
.er-pk-img { object-fit: cover; }
.er-pk-shade { background: linear-gradient(180deg, rgba(0, 0, 0, 0) 30%, rgba(0, 0, 0, 0.9)); }
.er-pk-m { color: #d6d9df; font-size: 15px; margin-top: 4px; white-space: nowrap; overflow: hidden; text-overflow: ellipsis; }
.er-pk-tag { position: absolute; top: 14px; left: 14px; font-size: 13px; font-weight: 700; padding: 4px 10px; border-radius: 3px;
  background: var(--er-orange-500); color: #fff; text-transform: uppercase; letter-spacing: 0.08em;
  &.done { background: rgba(60, 207, 126, 0.85); color: #062; } }
.er-pk-none { grid-column: 1 / -1; padding: 22px 26px; font-size: 18px; line-height: 1.5; color: var(--er-muted); b { color: #fff; } }
.er-pk-detail { padding: 30px 34px; display: flex; flex-direction: column; min-height: 0; overflow: hidden;
  h2 { margin: 0; font-size: 40px; line-height: 1.1; text-transform: uppercase; white-space: nowrap; overflow: hidden; text-overflow: ellipsis; } }
.er-pk-sub { color: var(--er-muted); font-size: 18px; margin: 6px 0 20px; }
.er-pk-facts { display: grid; grid-template-columns: repeat(3, 1fr); gap: 12px; margin-bottom: 18px;
  div { background: rgba(255, 255, 255, 0.06); border-radius: 6px; padding: 12px 14px; }
  b { display: block; font: 700 30px "Overpass Mono", monospace; }
  span { color: var(--er-muted); font-size: 14px; text-transform: uppercase; letter-spacing: 0.08em; } }
.er-pk-lines { font-size: 16px; color: var(--er-muted); line-height: 1.7; margin-bottom: 16px; b { color: #fff; font-weight: 600; } }
.er-pk-warn { color: #ffd36b; }
.er-pk-pic { flex: 1; min-height: 120px; border-radius: 6px; margin-bottom: 22px; }
.er-pk-detail .er-pk-big { --bng-button-margin: 0; width: 100%; font-size: 26px; line-height: 32px; padding: 14px 40px; letter-spacing: 0.04em; }
.er-pk-subbtns { display: flex; gap: 12px; margin-top: 12px; --bng-button-margin: 0;
  > * { flex: 1; } }
.er-pk-note { color: var(--er-muted); font-size: 15px; margin-top: 10px; text-align: center; }
</style>
