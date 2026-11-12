<template>
  <!-- Earth Rally's menu page (docs/mockups-1.2.0/menu.html): a route of its own ("earthRally", index.js), opened by
       Ctrl+Alt+K, the pause menu's Earth Rally tab, or the results card. Four views in one component: Rallies, a
       rally's stages, a stage, Settings. Data and buttons: earthRally_main (store.js). -->
  <div class="er-page">
    <div class="er-topbar">
      <div class="er-back" tabindex="0" @click="back" @keydown.enter="back"><span>‹</span> {{ view === "rallies" ? "Close" : "Back" }}</div>
      <div class="er-title"><span class="er-accent">Earth</span> Rally</div>
      <div class="er-crumbs"><span v-for="c in crumbs" :key="c">{{ c }}</span></div>
      <div class="er-right">
        <BngButton v-if="view !== 'settings'" :accent="ACCENTS.outlined" @click="go('settings')">Settings</BngButton>
      </div>
    </div>

    <div class="er-content">
      <!-- the run or the recce under way -->
      <div v-if="banner" class="er-banner">
        <span>{{ banner }}</span>
        <BngButton v-if="st.run && st.run.busy" :accent="ACCENTS.outlined" @click="action('abort')">Stop the run</BngButton>
        <template v-if="st.recce">
          <BngButton :accent="ACCENTS.main" @click="action('recceSave')">Save recce</BngButton>
          <BngButton :accent="ACCENTS.outlined" @click="action('recceSaveAnyway')">Save anyway</BngButton>
          <BngButton :accent="ACCENTS.outlined" @click="action('recceCancel')">Cancel recce</BngButton>
        </template>
      </div>
      <div v-if="st.earthWhy" class="er-warnline">{{ st.earthWhy }}</div>

      <!-- ===== Rallies ===== -->
      <section v-if="view === 'rallies'" class="er-rallies">
        <div v-for="r in arr(st.rallies)" :key="r.id" class="er-card er-rally-card">
          <div class="er-rc-head">
            <div class="er-rc-name">{{ r.name }}</div>
            <div v-if="r.file" class="er-dim">from {{ r.file }}</div>
          </div>
          <div class="er-stats">
            <div class="er-stat"><div class="er-v">{{ r.stages }}</div><div class="er-l">stages</div></div>
            <div class="er-stat"><div class="er-v">{{ lenNum(r.lengthM) }}</div><div class="er-l">{{ units() }} of stages</div></div>
            <div class="er-stat"><div class="er-v">{{ r.driven }}</div><div class="er-l">driven</div></div>
          </div>
          <div class="er-driven">
            <span class="er-muted">{{ r.driven }} of {{ r.stages }} stages driven</span>
            <div class="er-bar"><i :style="{ width: (r.stages ? 100 * r.driven / r.stages : 0) + '%' }"></i></div>
          </div>
          <div class="er-rc-foot"><BngButton :accent="ACCENTS.main" @click="openRally(r.id)">Open rally</BngButton></div>
        </div>

        <div class="er-card er-add">
          <div class="er-rc-name">+ Add a rally</div>
          <ol>
            <li>Get the rally's map: a <b>.kml</b>, <b>.kmz</b> or <b>.gpx</b> (Google My Maps, or the organisers' map).</li>
            <li>Put it in the import folder. It is imported straight away.</li>
          </ol>
          <div class="er-path">{{ st.importFolder }}</div>
          <div class="er-row">
            <BngButton :accent="ACCENTS.main" @click="action('openFolder')">Open import folder</BngButton>
            <BngButton :accent="ACCENTS.secondary" @click="action('rescan')">Re-scan</BngButton>
          </div>
          <div v-if="st.lastImport" class="er-report">
            <div class="er-report-h">Last import · {{ st.lastImport.at }}</div>
            <div v-for="(l, i) in arr(st.lastImport.lines)" :key="i" :class="l.ok ? 'er-ok' : 'er-warn'">{{ l.ok ? "✓" : "!" }} {{ l.text }}</div>
          </div>
        </div>
      </section>

      <!-- ===== a rally ===== -->
      <section v-else-if="view === 'rally' && rly">
        <div class="er-rally-head">
          <div class="er-rh-name">{{ rly.name }}</div>
          <div class="er-stat"><div class="er-v">{{ rly.stages }}</div><div class="er-l">stages</div></div>
          <div class="er-stat"><div class="er-v">{{ len(rly.lengthM) }}</div><div class="er-l">of stages</div></div>
          <div class="er-stat"><div class="er-v">{{ rly.driven }} / {{ rly.stages }}</div><div class="er-l">driven</div></div>
        </div>
        <div class="er-card er-stages">
          <div class="er-srow er-hdr"><span>Stage</span><span>Name</span><span class="er-r">Length</span><span class="er-st">Status</span><span class="er-r">Best</span><span></span></div>
          <div v-for="s in arr(rly.list)" :key="s.id" class="er-srow er-click" tabindex="0" @click="openStage(rly.id, s.id)" @keydown.enter="openStage(rly.id, s.id)">
            <span class="er-ss">SS{{ s.ss }}</span><span>{{ s.name }}</span><span class="er-r er-mono">{{ len(s.lengthM) }}</span>
            <span class="er-st"><span class="er-pill" :class="pill(s.status).cls">{{ pill(s.status).label }}</span></span>
            <span class="er-r er-mono" :class="{ 'er-none': !s.best }">{{ s.best ? time(s.best) : "–" }}</span><span class="er-go">›</span>
          </div>
        </div>
        <div class="er-muted er-help">
          <b>Ready</b>: notes from the stage's own roads or your recce. <b>Recce recommended</b>: part of the stage has
          no road on the map (no notes there) until you drive its recce. <b>Recce needed</b>: drive its recce first.
        </div>
        <details v-if="arr(rly.report).length" class="er-report er-report-full">
          <summary>Import report</summary>
          <div v-for="(l, i) in arr(rly.report)" :key="i">{{ l }}</div>
        </details>
      </section>

      <!-- ===== a stage ===== -->
      <section v-else-if="view === 'stage' && stg" class="er-stage-page">
        <div>
          <div class="er-stage-ss">SS{{ stg.ss }} · {{ (stg.rally || "").toUpperCase() }}</div>
          <div class="er-stage-name">{{ stg.name }}</div>
          <div class="er-muted">{{ controlsLine }}</div>
          <div class="er-tiles">
            <div class="er-card er-tile"><div class="er-v">{{ lenNum(stg.lengthM) }}<small>{{ units() }}</small></div><div class="er-l">Length</div></div>
            <div class="er-card er-tile"><div class="er-v">{{ dash(stg.corners) }}</div><div class="er-l">Corners</div></div>
            <div class="er-card er-tile"><div class="er-v">{{ dash(stg.junctions) }}</div><div class="er-l">Junctions</div></div>
            <div class="er-card er-tile"><div class="er-v">{{ dash(stg.bridges) }}</div><div class="er-l">{{ stg.bridges === 1 ? "Bridge" : "Bridges" }}</div></div>
          </div>
          <div class="er-card er-line-note"><span class="er-pill" :class="pill(stg.status).cls">{{ pill(stg.status).label }}</span><span>{{ stg.note }}</span></div>
          <div class="er-actions">
            <BngButton :accent="ACCENTS.main" :disabled="!stg.canDrive || busy" @click="action('drive', stg.eventId, stg.id)">Drive stage</BngButton>
            <BngButton :accent="ACCENTS.secondary" :disabled="busy" @click="action('route', stg.eventId, stg.id)">Route to start</BngButton>
            <BngButton :accent="ACCENTS.secondary" :disabled="busy" @click="action('recce', stg.eventId, stg.id)">Recce</BngButton>
          </div>
          <div v-if="busyMsg" class="er-msg">{{ busyMsg }}</div>
          <div class="er-act-help">
            <b>Drive stage</b>: takes you to the {{ stg.atc ? "time control before the start" : "start" }}, then through the stage as in a real rally.<br>
            <b>Route to start</b>: the way there on the GPS, arrows on the road. No teleport.<br>
            <b>Recce</b>: drive the stage once at your own pace; the line you drive gives the notes.
          </div>
        </div>
        <div class="er-card er-runs">
          <h3>Your runs</h3>
          <div v-if="stg.best" class="er-best-box"><span class="er-t">{{ time(stg.best) }}</span><span class="er-badge">BEST</span></div>
          <div v-for="(r, i) in arr(stg.runs)" :key="i" class="er-run">
            <span>{{ when(r.date) }} <span v-if="r.last" class="er-dim">· last</span></span>
            <span class="er-mono">{{ time(r.timeS) }}</span>
            <span :class="r.penaltyS > 0 ? 'er-pen' : 'er-clean'">{{ r.text }}</span>
          </div>
          <div v-if="!arr(stg.runs).length" class="er-muted">No runs yet.</div>
          <div class="er-muted er-small">Times include penalties.</div>
        </div>
      </section>

      <!-- ===== Settings ===== -->
      <section v-else-if="view === 'settings'" class="er-settings-page">
        <div class="er-card"><EarthRallySettings /></div>
        <div class="er-card er-side">
          <h3>Developer</h3>
          <p class="er-muted">The HUD preview plays sample moments of a run through the HUD, without driving.</p>
          <BngButton :accent="ACCENTS.outlined" @click="previewHud">HUD preview</BngButton>
          <p class="er-dim er-small">Earth Rally {{ st.version }}</p>
        </div>
      </section>

      <div v-else class="er-muted">Loading...</div>
    </div>

    <div class="er-infobar">
      <span><span class="er-k">Esc</span>Back to the game</span>
      <span><span class="er-k">Ctrl+Alt+K</span>Open / close Earth Rally</span>
    </div>
  </div>
</template>

<script setup>
import { ref, computed, onMounted, onUnmounted } from "vue"
import { BngButton, ACCENTS } from "@/common/components/base"
import EarthRallySettings from "./EarthRallySettings.vue"
import {
  state, rally, stage, busyMsg, action as luaAction, refreshState, loadRally, loadStage, closeMenu, previewHud,
  arr, units, len, lenNum, time, when, STATUS, RUN_WORDS,
} from "./store.js"

const view = ref("rallies")
const sel = ref({ eventId: null, stageId: null })
const st = computed(() => state.value || {})
const rly = computed(() => (rally.value && !rally.value.missing && rally.value.id === sel.value.eventId) ? rally.value : null)
const stg = computed(() => (stage.value && !stage.value.missing && stage.value.id === sel.value.stageId) ? stage.value : null)
const busy = computed(() => !!(st.value.recce || (st.value.run && st.value.run.busy)))

const crumbs = computed(() => {
  if (view.value === "settings") return ["Settings"]
  const c = ["Rallies"]
  if (view.value === "rally" || view.value === "stage") c.push((rly.value && rly.value.name) || (stg.value && stg.value.rally) || "")
  if (view.value === "stage" && stg.value) c.push(`SS${stg.value.ss} ${stg.value.name}`)
  return c
})

const banner = computed(() => {
  const s = st.value
  if (s.recce) {
    const pct = Math.round((s.recce.share || 0) * 100)
    return s.recce.started ? `Recce of ${s.recce.stageName}: ${pct} % driven` : `Recce of ${s.recce.stageName}: drive to the start of the stage; recording begins there`
  }
  if (s.run && s.run.busy) return `SS${s.run.ss || ""} ${s.run.stageName}: ${RUN_WORDS[s.run.state] || s.run.state}`
  if (s.run && s.run.state === "failed") return `${s.run.stageName}: stopped (${s.run.error || ""})`
  return ""
})

const controlsLine = computed(() => {
  const s = stg.value
  if (!s) return ""
  const parts = []
  if (s.atc) parts.push("Time control before the start")
  if (s.stop) parts.push("stop control after the flying finish")
  return parts.length ? parts.join(" · ") : "Start line and flying finish"
})

function go(v) { view.value = v; busyMsg.value = "" }
const pill = status => STATUS[status] || STATUS.none
const dash = v => (v === null || v === undefined ? "–" : v)
function openRally(id) {
  sel.value = { eventId: id, stageId: null }
  loadRally(id)
  go("rally")
}
function openStage(eventId, stageId) {
  sel.value = { eventId, stageId }
  loadStage(eventId, stageId)
  go("stage")
}
function back() {
  if (view.value === "stage") openRally(sel.value.eventId)
  else if (view.value === "rally" || view.value === "settings") go("rallies")
  else closeMenu()
}
function action(what, eventId, stageId) {
  luaAction(what, eventId, stageId, () => {
    if (view.value === "stage" && sel.value.stageId) loadStage(sel.value.eventId, sel.value.stageId)
    if (view.value === "rally" && sel.value.eventId) loadRally(sel.value.eventId)
  })
}

// the poll: the state every second, the page's own data every two
let timer = null
let tick = 0
function poll() {
  refreshState()
  if (++tick % 2) return
  if (view.value === "rally" && sel.value.eventId) loadRally(sel.value.eventId)
  if (view.value === "stage" && sel.value.stageId) loadStage(sel.value.eventId, sel.value.stageId)
}
onMounted(() => {
  // (opened at a page: the results card's Rally menu, a pause-menu rally)
  refreshState(s => {
    const at = s && s.openAt
    if (at && at.view === "stage" && at.eventId && at.stageId) openStage(at.eventId, at.stageId)
    else if (at && at.view === "rally" && at.eventId) openRally(at.eventId)
    else if (at && at.view === "settings") go("settings")
  })
  timer = setInterval(poll, 1000)
})
onUnmounted(() => { if (timer) clearInterval(timer) })
</script>

<style lang="scss" scoped>
.er-page {
  --er-orange: #f26b1d;
  --er-orange-500: #c75b1e;
  --er-muted: #b8bcc6;
  --er-dim: #8a909a;
  --er-blue: #1f8fff;
  position: absolute; inset: 0; display: flex; flex-direction: column; color: #f0f0f0;
  font-family: "Noto Sans", sans-serif; font-size: 16px;
  background: rgba(10, 12, 16, 0.72);
}
.er-topbar {
  height: 84px; flex-shrink: 0; display: flex; align-items: center; gap: 20px; padding: 0 64px;
  background: linear-gradient(180deg, rgba(0, 0, 0, 0.8), rgba(0, 0, 0, 0.35));
}
.er-back { display: flex; align-items: center; gap: 10px; padding: 8px 16px 8px 10px; border-radius: 0.25rem; background: rgba(0, 0, 0, 0.4); color: var(--er-muted); font-size: 18px; cursor: pointer; }
.er-title { font-size: 30px; font-weight: 700; letter-spacing: 0.06em; text-transform: uppercase; }
.er-accent { color: var(--er-orange); }
.er-crumbs { font-size: 18px; color: var(--er-muted); span + span::before { content: "›"; margin: 0 10px; color: #6f7480; } }
.er-right { margin-left: auto; display: flex; gap: 12px; }
.er-content { flex: 1; padding: 28px 64px 24px; overflow-y: auto; }
.er-infobar { height: 48px; flex-shrink: 0; display: flex; align-items: center; gap: 28px; padding: 0 64px; background: rgba(0, 0, 0, 0.6); color: var(--er-muted); }
.er-k { font-family: "Overpass Mono", monospace; font-size: 13px; padding: 1px 7px; margin-right: 6px; border: 1px solid #6f7480; border-radius: 3px; color: #fff; }

.er-card { background: rgba(0, 0, 0, 0.6); border-radius: 0.5rem; }
.er-muted { color: var(--er-muted); }
.er-dim { color: var(--er-dim); font-size: 15px; }
.er-small { font-size: 14px; margin-top: 12px; }
.er-mono { font-family: "Overpass Mono", monospace; }
.er-row { display: flex; gap: 12px; flex-wrap: wrap; }
.er-banner { display: flex; align-items: center; gap: 12px; margin-bottom: 18px; padding: 12px 18px; border-radius: 0.5rem; background: rgba(31, 143, 255, 0.25); border-left: 4px solid var(--er-blue); font-size: 18px; span { margin-right: auto; } }
.er-warnline { margin-bottom: 14px; color: #ffd36b; }
.er-msg { margin-top: 12px; color: #ffd36b; }
.er-stat .er-v { font-family: "Overpass Mono", monospace; font-size: 32px; font-weight: 700; }
.er-stat .er-l, .er-tile .er-l { font-size: 14px; text-transform: uppercase; letter-spacing: 0.08em; color: var(--er-muted); }

.er-pill { display: inline-flex; align-items: center; gap: 8px; font-size: 15px; font-weight: 600; padding: 3px 12px; border-radius: 999px; white-space: nowrap;
  &::before { content: ""; width: 8px; height: 8px; border-radius: 50%; background: currentColor; }
  &.ready { background: rgba(40, 140, 80, 0.55); color: #d9ffe6; }
  &.recce { background: rgba(190, 140, 30, 0.45); color: #fff1cc; }
  &.none { background: rgba(170, 60, 60, 0.45); color: #ffdede; }
}

.er-rallies { display: grid; grid-template-columns: repeat(auto-fill, minmax(420px, 1fr)); gap: 28px; }
.er-rally-card { display: flex; flex-direction: column; min-height: 380px; border-top: 4px solid var(--er-orange); }
.er-rc-head { padding: 26px 30px 10px; }
.er-rc-name { font-size: 30px; font-weight: 700; line-height: 1.15; }
.er-stats { display: grid; grid-template-columns: repeat(3, 1fr); gap: 12px; padding: 16px 30px; }
.er-driven { padding: 6px 30px 0; }
.er-bar { height: 10px; border-radius: 5px; background: #2a2e38; overflow: hidden; margin-top: 8px; i { display: block; height: 100%; background: var(--er-blue); } }
.er-rc-foot { margin-top: auto; padding: 20px 30px 24px; }
.er-add { border: 3px dashed #5a6070; background: rgba(0, 0, 0, 0.35); padding: 26px 30px; display: flex; flex-direction: column; gap: 14px;
  ol { margin: 0; padding-left: 26px; font-size: 17px; line-height: 1.55; } }
.er-path { font-family: "Overpass Mono", monospace; font-size: 13px; color: var(--er-muted); background: rgba(0, 0, 0, 0.4); padding: 8px 10px; border-radius: 0.25rem; word-break: break-all; }
.er-report { background: rgba(0, 0, 0, 0.4); border-radius: 0.25rem; padding: 12px 14px; font-size: 15px; line-height: 1.5; }
.er-report-h { font-size: 13px; text-transform: uppercase; letter-spacing: 0.08em; color: var(--er-muted); margin-bottom: 4px; }
.er-report-full { margin-top: 18px; summary { cursor: pointer; font-weight: 600; } }
.er-ok { color: #6fd39a; }
.er-warn { color: #ffd36b; }

.er-rally-head { display: flex; align-items: flex-end; gap: 48px; margin-bottom: 22px; }
.er-rh-name { font-size: 40px; font-weight: 700; }
.er-stages { padding: 8px 0; }
.er-srow { display: grid; grid-template-columns: 100px 1fr 130px 260px 150px 30px; align-items: center; height: 58px; padding: 0 28px; font-size: 20px; border-left: 4px solid transparent;
  & + .er-srow { border-top: 1px solid rgba(255, 255, 255, 0.06); }
  &.er-hdr { height: 40px; font-size: 14px; text-transform: uppercase; letter-spacing: 0.08em; color: var(--er-muted); }
  &.er-click { cursor: pointer; }
  &.er-click:hover, &.er-click:focus { background: rgba(199, 91, 30, 0.22); border-left-color: var(--er-orange); }
  .er-ss { font-family: "Overpass Mono", monospace; font-weight: 700; color: var(--er-muted); }
  .er-r { text-align: right; }
  .er-st { padding-left: 30px; }
  .er-none { color: #6f7480; }
  .er-go { color: var(--er-dim); text-align: right; }
}
.er-help { margin-top: 14px; font-size: 15px; }

.er-stage-page { display: grid; grid-template-columns: 1.25fr 1fr; gap: 28px; }
.er-stage-ss { font-family: "Overpass Mono", monospace; font-size: 20px; color: var(--er-orange); font-weight: 700; letter-spacing: 0.05em; }
.er-stage-name { font-size: 52px; font-weight: 700; line-height: 1.1; }
.er-tiles { display: grid; grid-template-columns: repeat(4, 1fr); gap: 16px; margin: 26px 0; }
.er-tile { padding: 18px 20px; .er-v { font-family: "Overpass Mono", monospace; font-size: 40px; font-weight: 700; line-height: 1.1; small { font-size: 18px; margin-left: 4px; color: var(--er-muted); } } }
.er-line-note { display: flex; align-items: center; gap: 14px; padding: 14px 18px; font-size: 17px; }
.er-actions { display: flex; gap: 14px; margin-top: 24px; flex-wrap: wrap; }
.er-act-help { margin-top: 16px; font-size: 15px; line-height: 1.7; color: var(--er-muted); }
.er-runs { padding: 22px 26px; h3 { margin: 0 0 12px; font-size: 20px; } }
.er-best-box { display: flex; align-items: center; gap: 14px; margin-bottom: 12px; .er-t { font: 700 44px "Overpass Mono", monospace; } }
.er-badge { background: rgb(0, 200, 0); color: #002a00; font-weight: 800; padding: 2px 10px; border-radius: 6px; }
.er-run { display: grid; grid-template-columns: 1fr auto 1fr; gap: 14px; padding: 9px 0; border-top: 1px solid rgba(255, 255, 255, 0.07); font-size: 17px;
  .er-pen { color: #ffd36b; text-align: right; } .er-clean { color: #6fd39a; text-align: right; } }

.er-settings-page { display: grid; grid-template-columns: 1.6fr 1fr; gap: 28px; align-items: start; }
.er-side { padding: 22px 26px; h3 { margin: 0 0 8px; } }
</style>
