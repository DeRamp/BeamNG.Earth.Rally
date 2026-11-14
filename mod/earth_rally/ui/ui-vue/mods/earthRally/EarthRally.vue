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
        <!-- The question goes in the banner, not on the stage page, because the auto recce can be started from a
             stage ROW and the player may well be looking at the rally list when it comes back. The banner is on
             every page, so the one place the answer can always be given is here. Stop is still beside it: saying
             no to the download is not the same as abandoning the auto recce. -->
        <template v-if="autoAsk">
          <BngButton :accent="ACCENTS.main" @click="action('autoRecceDownload')">Download {{ MB(autoAsk.bytes) }}</BngButton>
          <BngButton :accent="ACCENTS.outlined" @click="action('autoRecceSkip')">Not now</BngButton>
        </template>
        <BngButton v-if="auto" :accent="ACCENTS.outlined" @click="action('autoRecceStop')">Stop</BngButton>
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
            <div class="er-rc-name er-clip" :title="r.name">{{ r.name }}</div>
            <div v-if="r.file" class="er-dim er-clip" :title="r.file">from {{ r.file }}</div>
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
          <div class="er-rh-name er-clip" :title="rly.name" style="min-width: 0; flex: 0 1 auto">{{ rly.name }}</div>
          <div class="er-stat"><div class="er-v">{{ rly.stages }}</div><div class="er-l">stages</div></div>
          <div class="er-stat"><div class="er-v">{{ len(rly.lengthM) }}</div><div class="er-l">of stages</div></div>
          <div class="er-stat"><div class="er-v">{{ rly.driven }} / {{ rly.stages }}</div><div class="er-l">driven</div></div>
        </div>
        <!-- Seven columns: the seventh holds the Auto recce button (docs/mockups-1.3.0/auto-recce-button.html,
             section 3). Its header cell is deliberately empty -- an AUTO RECCE heading over a column blank on most
             rows reads as data, and advertises on every row something half of them cannot do. -->
        <div class="er-card er-stages">
          <div class="er-srow er-hdr"><span>Stage</span><span>Name</span><span class="er-r">Length</span><span class="er-st">Status</span><span></span><span class="er-r">Best</span><span></span></div>
          <div v-for="s in arr(rly.list)" :key="s.id" class="er-srow er-click" :class="{ 'er-running': autoRow(s) }" tabindex="0" @click="openStage(rly.id, s.id)" @keydown.enter="rowEnter($event, s)">
            <span class="er-ss">SS{{ s.ss }}</span><span>{{ s.name }}</span><span class="er-r er-mono">{{ len(s.lengthM) }}</span>
            <span class="er-st">
              <span v-if="autoRow(s)" class="er-pill working" :style="{ '--er-done': autoPct }">{{ STATUS.working.label }} <span class="er-wn">{{ autoLeg }}</span></span>
              <span v-else class="er-pill" :class="pill(s.status).cls">{{ pill(s.status).label }}</span>
            </span>
            <!-- @click.stop: the whole row opens the stage, so without it the button would do both. The row's
                 Enter is guarded the same way, in rowEnter: Enter on a focused button fires its click AND bubbles. -->
            <span class="er-act">
              <BngButton v-if="autoRow(s)" :accent="ACCENTS.outlined" @click.stop="action('autoRecceStop')">Stop</BngButton>
              <BngButton v-else-if="st.autoOk && s.status === 'none'" :accent="ACCENTS.secondary" :disabled="busy" @click.stop="action('autoRecce', rly.id, s.id)">{{ outcomeFor(s) ? "Try again" : "Auto recce" }}</BngButton>
              <!-- Reset takes the same cell on a stage that HAS a line, so every row has exactly one control and
                   the column reads as one question. Deliberately NOT gated on st.autoOk: it removes files and asks
                   BeamNG.Earth for nothing, so a player on a stock BeamNG.Earth still has their way back from a
                   recce they are unhappy with -- gating it the way Auto recce is gated would lock out exactly the
                   players with no auto recce to fall back on. A driven recce is confirmed on the stage page, where
                   there is room to say what is lost; the row opens it rather than deleting from under them. -->
              <BngButton v-else-if="s.line === 'matched'" :accent="ACCENTS.outlined" :disabled="busy" @click.stop="action('reset', rly.id, s.id)">Reset</BngButton>
              <BngButton v-else-if="s.line" :accent="ACCENTS.outlined" @click.stop="askReset(rly.id, s.id)">Reset</BngButton>
            </span>
            <span class="er-r er-mono" :class="{ 'er-none': !s.best }">{{ s.best ? time(s.best) : "–" }}</span><span class="er-go">›</span>
          </div>
        </div>
        <!-- how an auto recce ended, one line per stage: the pill only ever says whether the stage can be driven -->
        <div v-if="arr(rly.autoLines).length" class="er-under">
          <div v-for="l in arr(rly.autoLines)" :key="l.stageId" class="er-outcome" :class="outcomeCls(l.kind)">
            <span class="er-ssx">SS{{ l.ss }}</span>{{ l.text }}
          </div>
        </div>
        <div class="er-muted er-help">
          <b>Ready</b>: notes from the stage's own roads or your recce. <b>Recce recommended</b>: part of the stage has
          no road on the map (no notes there) until you drive its recce. <b>Recce needed</b>:
          {{ st.autoOk ? "run the auto recce, or drive its recce." : "drive its recce." }}
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
            <!-- Gain and Loss, from the stage's own line (menu.lua, events.lineFigures): the height it climbs and
                 the height it gives back, each counted once a move has gone 2 m from the last one counted. They
                 took the places of Junctions and Bridges, so the grid is the same four tracks it always was. -->
            <div class="er-card er-tile"><div class="er-v">{{ riseNum(stg.gainM) }}<small>{{ riseUnit() }}</small></div><div class="er-l">Gain</div></div>
            <div class="er-card er-tile"><div class="er-v">{{ riseNum(stg.lossM) }}<small>{{ riseUnit() }}</small></div><div class="er-l">Loss</div></div>
          </div>
          <div v-if="autoHere" class="er-card er-line-note">
            <span class="er-pill working" :style="{ '--er-done': autoPct }">{{ STATUS.working.label }} <span class="er-wn">{{ autoLeg }}</span></span>
            <span v-if="auto.phase === 'going'">Going to the start of the stage and waiting for the world to load. A road graph can only be asked for near where you are.</span>
            <span v-else-if="auto.phase === 'planning'">Working out what map data is missing along the stage.</span>
            <span v-else-if="auto.phase === 'downloading'">Downloading the map data along the stage. It is gated so it cannot slow the world down, and it carries on if you leave this page.<template v-if="auto.area && auto.area.msg"> {{ auto.area.msg }}</template></span>
            <span v-else>Matching the line to the map's roads, {{ auto.stepM }} m at a time. No map data is downloaded. You can leave this page.</span>
          </div>
          <div v-else class="er-card er-line-note"><span class="er-pill" :class="pill(stg.status).cls">{{ pill(stg.status).label }}</span><span>{{ stg.note }}</span></div>
          <!-- Auto recce is the fourth button, before Recce, so the two recce buttons sit together and the cheap
               one comes first. While one runs it is replaced in place by its Stop, not joined by a fifth button. -->
          <div class="er-actions">
            <BngButton :accent="ACCENTS.main" :disabled="!stg.canDrive || busy" @click="action('drive', stg.eventId, stg.id)">Drive stage</BngButton>
            <BngButton :accent="ACCENTS.secondary" :disabled="busy" @click="action('route', stg.eventId, stg.id)">Route to start</BngButton>
            <BngButton v-if="autoHere" :accent="ACCENTS.outlined" @click="action('autoRecceStop')">Stop the auto recce</BngButton>
            <BngButton v-else-if="stg.autoCan" :accent="ACCENTS.secondary" :disabled="busy || !st.autoOk" @click="action('autoRecce', stg.eventId, stg.id)">Auto recce</BngButton>
            <!-- menu.lua sets autoCan only on a stage with no line, so on a stage that has one the Auto recce
                 button is already absent and Reset is simply its v-else-if: the row keeps four buttons, never
                 five. A matched line goes at once (1.25 s to make again); a driven recce asks first, because it
                 cost the stage, driven, and cannot be got back. -->
            <BngButton v-else-if="stg.line === 'matched'" :accent="ACCENTS.outlined" :disabled="busy" @click="action('reset', stg.eventId, stg.id)">Reset</BngButton>
            <BngButton v-else-if="stg.line && !confirmReset" :accent="ACCENTS.outlined" @click="confirmReset = true">Reset</BngButton>
            <BngButton :accent="ACCENTS.secondary" :disabled="busy" @click="action('recce', stg.eventId, stg.id)">Recce</BngButton>
          </div>
          <!-- The confirm, for a driven recce only. Confirming the cheap case as well would be worse than not
               confirming at all: it teaches clicking through, and the once it mattered that habit would carry. -->
          <div v-if="confirmReset && stg.line && stg.line !== 'matched'" class="er-card er-confirm">
            <div>
              <b>Remove the recce you drove?</b><br>
              <!-- It does NOT promise the auto recce will manage one here: whether the map has roads for this
                   stage on this computer is only known by asking for them, and a confirm that guessed would be
                   worse than one that does not say. -->
              <span>This cannot be undone. Afterwards you can run the auto recce, or drive the recce again.</span>
            </div>
            <div class="er-confirm-row">
              <BngButton :accent="ACCENTS.outlined" @click="confirmReset = false">Keep it</BngButton>
              <BngButton :accent="ACCENTS.main" :disabled="busy" @click="confirmReset = false; action('reset', stg.eventId, stg.id)">Remove the recce</BngButton>
            </div>
          </div>
          <!-- beside the row, never a tooltip: a disabled BngButton takes no pointer events and can never show one -->
          <div v-if="stg.autoWhy" class="er-msg">{{ stg.autoWhy }}</div>
          <div v-if="stg.autoLine" class="er-outcome" :class="outcomeCls(stg.autoLine.kind)">{{ stg.autoLine.text }}</div>
          <div v-if="busyMsg" class="er-msg">{{ busyMsg }}</div>
          <div class="er-act-help">
            <b>Drive stage</b>: takes you to the {{ stg.atc ? "time control before the start" : "start" }}, then through the stage as in a real rally.<br>
            <b>Route to start</b>: the way there on the GPS, arrows on the road. No teleport.<br>
            <template v-if="stg.autoCan"><b>Auto recce</b>: {{ !st.autoOk
              ? "works the line out from the map's roads. Not available with this BeamNG.Earth."
              : st.autoCanFetch
                ? "takes you to the start, then works the line out from the map's roads. Where the map data is missing it tells you how much there is to download and asks first."
                : "works the line out from the map's roads. Reads only the map data already on your disk; downloads nothing." }}<br></template>
            <template v-if="stg.line"><b>Reset</b>: removes this stage's line, so you can make it again -- with the auto recce or by driving a recce. Your times are kept.<br></template>
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
  state, rally, stage, busyMsg, action as luaAction, refreshState, takeOpenAt, loadRally, loadStage, closeMenu, previewHud,
  arr, units, len, lenNum, riseNum, riseUnit, time, when, STATUS, AUTO_OUTCOME, RUN_WORDS,
} from "./store.js"

const view = ref("rallies")
const sel = ref({ eventId: null, stageId: null })
const st = computed(() => state.value || {})
const rly = computed(() => (rally.value && !rally.value.missing && rally.value.id === sel.value.eventId) ? rally.value : null)
const stg = computed(() => (stage.value && !stage.value.missing && stage.value.id === sel.value.stageId) ? stage.value : null)
// An auto recce holds the page as a recce does: the Lua does one window at a time, so every other action is
// greyed while one runs (the running row's own Stop is not disabled, and is the way out).
const busy = computed(() => !!(st.value.recce || st.value.auto || (st.value.run && st.value.run.busy)))

// the auto recce running, if any: which row it is, how far through, and the window it is on. progress().done
// counts the windows finished, while the pill and the banner name the one in flight -- so it is never "0 / 19".
const auto = computed(() => st.value.auto || null)
const autoWindow = computed(() => {
  const a = auto.value
  return a ? Math.min((a.done || 0) + 1, a.windows || 1) : 0
})
const autoPct = computed(() => {
  const a = auto.value
  if (a && a.phase === "downloading" && a.area && a.area.total) {
    return `${Math.round((100 * (a.area.done || 0)) / a.area.total)}%`
  }
  // the legs with nothing to count: a filled pill would claim progress it does not have, an empty one would read
  // as stuck, so they sit at a tenth -- enough to look alive, not enough to be read as a measurement
  if (a && a.phase && a.phase !== "matching") return "10%"
  return a && a.windows ? `${Math.round((100 * autoWindow.value) / a.windows)}%` : "0%"
})
const MB = b => `${((b || 0) / 1e6).toFixed(b && b < 1e7 ? 1 : 0)} MB`
// One press is one thing, so every leg answers in the same place: the pill's own tail. Matching keeps its window
// count, which is the only leg with a real measurement in it.
const autoLeg = computed(() => {
  const a = auto.value
  if (!a) return ""
  if (a.phase === "going") return "going there"
  if (a.phase === "planning") return "checking"
  if (a.phase === "asking") return "your call"
  if (a.phase === "downloading") return a.area && a.area.total ? `${a.area.done || 0} / ${a.area.total}` : "starting"
  return `${autoWindow.value} / ${a.windows || 1}`
})
// What is waiting on the player, or null. `bytes` is the only figure shown: BeamNG.Earth's own documentation says
// not to show `seconds` (a serial model with no bandwidth in it -- it said 132 s for a download that took 43) and
// `km2` is the corridor's geometry, far smaller than the ground actually fetched.
const autoAsk = computed(() => (auto.value && auto.value.phase === "asking" && auto.value.ask) || null)
const autoRow = s => !!(auto.value && rly.value && auto.value.eventId === rly.value.id && auto.value.stageId === s.id)
const autoHere = computed(() => !!(auto.value && stg.value &&
  auto.value.eventId === stg.value.eventId && auto.value.stageId === stg.value.id))
const outcomeFor = s => arr(rly.value && rly.value.autoLines).find(l => l.stageId === s.id) || null
const outcomeCls = kind => AUTO_OUTCOME[kind] || "flat"
// Enter on the row opens the stage -- but only when the row itself has the focus. Enter on a button inside it
// already fires that button's own click, and the keydown bubbles up here as well, so without this the Stop button
// would stop the auto recce and open the stage in the one keypress (the keyboard twin of needing @click.stop).
function rowEnter(e, s) { if (e.target === e.currentTarget) openStage(rly.value.id, s.id) }

const crumbs = computed(() => {
  if (view.value === "settings") return ["Settings"]
  const c = ["Rallies"]
  if (view.value === "rally" || view.value === "stage") c.push((rly.value && rly.value.name) || (stg.value && stg.value.rally) || "")
  if (view.value === "stage" && stg.value) c.push(`SS${stg.value.ss} ${stg.value.name}`)
  return c
})

const banner = computed(() => {
  const s = st.value
  if (s.auto) {
    const n = `Auto recce of SS${s.auto.ss} ${s.auto.stageName}`
    if (s.auto.phase === "going") return `${n}: going to the start, waiting for the world to load`
    if (s.auto.phase === "planning") return `${n}: checking what map data is missing`
    if (s.auto.phase === "asking") return `${n}: ${MB(s.auto.ask && s.auto.ask.bytes)} of map data to download -- your call`
    if (s.auto.phase === "downloading") {
      const a = s.auto.area
      return `${n}: downloading the map data${a && a.total ? `, ${a.done || 0} of ${a.total} items` : ""}`
    }
    // "no map data is downloaded" is not padding: someone watching a progress bar assumes it is downloading, and
    // the matching leg reads only what is already on this computer -- which is still true, and is why this
    // sentence belongs to the matching leg alone now rather than to the whole button.
    return `${n}: window ${autoWindow.value} of ${s.auto.windows}, no map data is downloaded`
  }
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
// Reset's confirm, for a driven recce (the matched case needs none). Held here rather than per stage because
// it must not survive leaving the page: a confirm still up when another stage is opened would sit over a line it
// was never asked about.
const confirmReset = ref(false)

function openStage(eventId, stageId) {
  sel.value = { eventId, stageId }
  confirmReset.value = false
  loadStage(eventId, stageId)
  go("stage")
}

// Reset pressed on a list row whose line was driven: open the stage and put the confirm up there, rather than
// deleting from under the player in a row that has no room to say what is lost.
function askReset(eventId, stageId) {
  openStage(eventId, stageId)
  confirmReset.value = true
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
  refreshState()
  takeOpenAt(at => {
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
  /* the auto recce running: the pill IS the progress bar. Its background is a two-stop gradient whose hard edge
     sits at --er-done, set per row from the window count, so it fills left to right as the windows come in. A 58px
     row has no second line for a bar of its own, and a bar across the row would read as a selection. */
  &.working {
    color: #cfe8ff;
    background: linear-gradient(to right, rgba(31, 143, 255, 0.62) var(--er-done, 0%), rgba(31, 143, 255, 0.22) var(--er-done, 0%));
    .er-wn { font-family: "Overpass Mono", monospace; font-weight: 700; margin-left: -2px; }
    &::before { animation: er-pulse 1.2s ease-in-out infinite; }
  }
}
@keyframes er-pulse { 0%, 100% { opacity: 1; } 50% { opacity: 0.3; } }

.er-rallies { display: grid; grid-template-columns: repeat(auto-fill, minmax(420px, 1fr)); gap: 28px; }
.er-rally-card { display: flex; flex-direction: column; min-height: 380px; border-top: 4px solid var(--er-orange); }
.er-rc-head { padding: 26px 30px 10px; }
.er-rally-card, .er-rc-head { min-width: 0; }   /* (a grid item: a long name must not widen the card) */
.er-clip { overflow: hidden; white-space: nowrap; text-overflow: ellipsis; }
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
/* Seven tracks: the 160px action column comes out of Name's 1fr, NOT out of Status -- Status already holds the
   longest pill ("Recce recommended", about 177px) with its 30px padding, and below about 215px that pill overruns
   the column. Name goes from about 1066px to 906px at 1920, and the longest name in a real rally is about 460px. */
.er-srow { display: grid; grid-template-columns: 100px 1fr 130px 260px 160px 150px 30px; align-items: center; height: 58px; padding: 0 28px; font-size: 20px; border-left: 4px solid transparent;
  & + .er-srow { border-top: 1px solid rgba(255, 255, 255, 0.06); }
  &.er-hdr { height: 40px; font-size: 14px; text-transform: uppercase; letter-spacing: 0.08em; color: var(--er-muted); }
  &.er-click { cursor: pointer; }
  &.er-click:hover, &.er-click:focus { background: rgba(199, 91, 30, 0.22); border-left-color: var(--er-orange); }
  /* The stage being matched, findable while scrolling a long rally: the left border it already has, in blue.
     This has to beat the hover and focus rules above on SPECIFICITY, not on order -- it is three classes plus the
     pseudo-class against their two, so it holds wherever it sits in the file. Written the other way round (same
     specificity, later in the file) the mark would vanish the moment anyone moved this block, or the pointer. */
  &.er-running, &.er-running.er-click:hover, &.er-running.er-click:focus { border-left-color: var(--er-blue); }
  .er-ss { font-family: "Overpass Mono", monospace; font-weight: 700; color: var(--er-muted); }
  .er-r { text-align: right; }
  .er-st { padding-left: 30px; }
  .er-none { color: #6f7480; }
  .er-go { color: var(--er-dim); text-align: right; }
  /* The action column. The button is sized by the game's own hooks rather than by overriding its rules: it sets
     font-size / line-height itself ("default value to be overriden with the parent component's styles",
     utility/button.vue:91-92) so those need :deep, while min-width (6em -- more than this cell has) and margin are
     custom properties it reads from whatever contains it. 15px text on a 20px line is a 29px button in a 58px row. */
  .er-act { padding-left: 24px; --bng-button-min-width: 0; --bng-button-margin: 0;
    :deep(.bng-button) { font-size: 15px; line-height: 20px; } }
}
.er-help { margin-top: 14px; font-size: 15px; }
/* how an auto recce ended, under the card, aligned with the rows above it */
.er-under { padding: 0 28px; }
.er-outcome { margin-top: 14px; font-size: 15px; line-height: 1.5;
  &.warn { color: #ffd36b; }
  &.flat { color: var(--er-muted); }
  &.err { color: #ff8a8a; }
  .er-ssx { font-family: "Overpass Mono", monospace; font-weight: 700; margin-right: 6px; }
}

.er-stage-page { display: grid; grid-template-columns: 1.25fr 1fr; gap: 28px; }
.er-stage-ss { font-family: "Overpass Mono", monospace; font-size: 20px; color: var(--er-orange); font-weight: 700; letter-spacing: 0.05em; }
.er-stage-name { font-size: 52px; font-weight: 700; line-height: 1.1; }
.er-tiles { display: grid; grid-template-columns: repeat(4, 1fr); gap: 16px; margin: 26px 0; }
.er-tile { padding: 18px 20px; .er-v { font-family: "Overpass Mono", monospace; font-size: 40px; font-weight: 700; line-height: 1.1; small { font-size: 18px; margin-left: 4px; color: var(--er-muted); } } }
.er-line-note { display: flex; align-items: center; gap: 14px; padding: 14px 18px; font-size: 17px; }
.er-actions { display: flex; gap: 14px; margin-top: 24px; flex-wrap: wrap; }
.er-act-help { margin-top: 16px; font-size: 15px; line-height: 1.7; color: var(--er-muted); }
/* Reset's confirm. Orange rather than red: the game has no destructive-red anywhere else, and one red card in a
   menu that has none would read as an error rather than a question. */
.er-confirm { display: flex; align-items: center; justify-content: space-between; gap: 20px; flex-wrap: wrap;
  margin-top: 14px; padding: 16px 20px; font-size: 16px; line-height: 1.5;
  box-shadow: inset 0 0 0 1px var(--er-orange-500);
  b { font-size: 17px; }
  span { color: var(--er-muted); }
}
.er-confirm-row { display: flex; gap: 12px; flex-shrink: 0; }
.er-runs { padding: 22px 26px; h3 { margin: 0 0 12px; font-size: 20px; } }
.er-best-box { display: flex; align-items: center; gap: 14px; margin-bottom: 12px; .er-t { font: 700 44px "Overpass Mono", monospace; } }
.er-badge { background: rgb(0, 200, 0); color: #002a00; font-weight: 800; padding: 2px 10px; border-radius: 6px; }
.er-run { display: grid; grid-template-columns: 1fr auto 1fr; gap: 14px; padding: 9px 0; border-top: 1px solid rgba(255, 255, 255, 0.07); font-size: 17px;
  .er-pen { color: #ffd36b; text-align: right; } .er-clean { color: #6fd39a; text-align: right; } }

.er-settings-page { display: grid; grid-template-columns: 1.6fr 1fr; gap: 28px; align-items: start; }
.er-side { padding: 22px 26px; h3 { margin: 0 0 8px; } }
</style>
