<template>
  <!-- Earth Rally's menu page (docs/mockups-1.2.0/menu.html, redrawn for rally files in
       docs/mockups-rally-files/menu.html): a route of its own ("earthRally", index.js), opened by Ctrl+Alt+K, the
       pause menu's Earth Rally tab, or the results card. Five views: Rallies (EarthRallyHome.vue), a season
       (EarthRallySeason.vue), a rally's stages, a stage, Settings. Rallies > Season > Rally > Stage in the crumbs,
       each one a way back. Data and buttons: earthRally_main (store.js). -->
  <div class="er-page">
    <div class="er-topbar">
      <div class="er-back" tabindex="0" @click="back" @keydown.enter="back"><span>‹</span> {{ view === "rallies" ? "Close" : "Back" }}</div>
      <div class="er-title"><span class="er-accent">Earth</span> Rally</div>
      <div class="er-crumbs"><span v-for="(c, i) in crumbs" :key="i" :class="{ 'er-cgo': c.go }" @click="c.go && c.go()">{{ c.label }}</span></div>
      <div class="er-right">
        <BngButton v-if="view !== 'settings'" :accent="ACCENTS.outlined" @click="go('settings')">Settings</BngButton>
      </div>
    </div>

    <div class="er-content">
      <!-- the run or the recce under way -->
      <div v-if="banner" class="er-banner">
        <span>{{ banner }}</span>
        <BngButton v-if="st.run && st.run.busy" :accent="ACCENTS.outlined" @click="action('abort')">Stop the run</BngButton>
        <!-- No Download / Not now here: the answer lives in the stage's own row and on its page, in the Auto
             recce column, so one press is answered where it was made. The banner still SAYS what is waiting. -->
        <BngButton v-if="auto" :accent="ACCENTS.outlined" @click="action('autoRecceStop')">Stop</BngButton>
        <template v-if="st.recce">
          <BngButton :accent="ACCENTS.main" @click="action('recceSave')">Save recce</BngButton>
          <BngButton :accent="ACCENTS.outlined" @click="action('recceSaveAnyway')">Save anyway</BngButton>
          <BngButton :accent="ACCENTS.outlined" @click="action('recceCancel')">Cancel recce</BngButton>
        </template>
      </div>
      <div v-if="st.earthWhy" class="er-warnline">{{ st.earthWhy }}</div>
      <!-- Something changed under the mod since it was built (versions.lua): the game's version, BeamNG.Earth's
           modding API, or one of the internals it has no API for. Empty in the normal case, so nothing shows. -->
      <div v-for="(n, i) in arr(st.versionNotes)" :key="'vn' + i" class="er-warnline">{{ n }}</div>

      <!-- ===== Rallies ===== -->
      <EarthRallyHome v-if="view === 'rallies'" @season="openSeason" @rally="openRally" @stage="openStage" @action="action" />

      <!-- ===== a season ===== -->
      <EarthRallySeason v-else-if="view === 'season' && ssn" :key="ssn.id" :s="ssn" @rally="openRally" />

      <!-- ===== a rally ===== -->
      <section v-else-if="view === 'rally' && rly">
        <!-- the banner: the rally's photo behind, its logo (or a drawn plate), its round, dates and town -->
        <div class="er-rbanner">
          <EarthRallyPic class="er-rb-photo" bare :url="(rly.media && (rly.media.photo || rly.media.cover)) || ''" />
          <EarthRallyPic class="er-rb-logo" contain :url="(rly.media && rly.media.logo) || ''" :kind="rly.season && rly.season.round ? `ROUND ${rly.season.round}` : 'RALLY'" :name="rly.name" />
          <div class="er-rb-text">
            <div v-if="rly.season" class="er-rb-round">Round {{ rly.season.round }} · {{ rly.season.name }}</div>
            <div class="er-rb-name er-clip" :title="rly.name">{{ rly.name }}</div>
            <div class="er-rb-sub">{{ rallySub }}</div>
          </div>
          <div class="er-rb-stats">
            <div class="er-stat"><div class="er-v">{{ len(rly.lengthM) }}</div><div class="er-l">{{ rly.stages }} stages</div></div>
            <div class="er-stat"><div class="er-v">{{ rly.driven }} / {{ rly.stages }}</div><div class="er-l">driven</div></div>
          </div>
        </div>
        <!-- Results (with real results) and Rules (when the file has any): no tabs at all on a rally with neither -->
        <div v-if="rallyTabs.length > 1 || legend" class="er-under-banner">
          <div v-if="rallyTabs.length > 1" class="er-tabs">
            <span v-for="t in rallyTabs" :key="t.id" tabindex="0" :class="{ on: curTab === t.id }" @click="rallyTab = t.id" @keydown.enter="rallyTab = t.id">{{ t.label }}</span>
          </div>
          <div v-if="legend && curTab === 'stages'" class="er-legend">
            <template v-if="rly.anyCancelled"><s>{{ cancelledSs }}</s> pass cancelled on the day</template><template v-if="rly.anyCancelled && rly.hasBoard"> · </template><template v-if="rly.hasBoard"><b>Place</b>: your best against the real field</template>
          </div>
        </div>
        <EarthRallyResults v-if="curTab === 'results'" :r="rly.results" />
        <div v-else-if="curTab === 'rules'" class="er-card er-rules">
          <div v-for="(l, i) in arr(rly.rules)" :key="i" class="er-rule">
            <span>{{ l.label }}</span><span><span class="er-rv">{{ l.value }}</span><span v-if="l.inGame" class="er-in">IN GAME</span></span>
          </div>
        </div>
        <template v-else>
        <!-- Seven columns: the seventh holds the Auto recce button (docs/mockups-1.3.0/auto-recce-button.html,
             section 3). Its header cell is deliberately empty -- an AUTO RECCE heading over a column blank on most
             rows reads as data, and advertises on every row something half of them cannot do. -->
        <div class="er-card er-stages">
          <div class="er-srow er-hdr" :style="srowCols"><span>Stage</span><span>Name</span><span class="er-r">Length</span><span class="er-st">Status</span><span></span><span class="er-r">Best</span><span v-if="rly.hasBoard" class="er-r">Place</span><span></span></div>
          <div v-for="s in arr(rly.list)" :key="s.id" class="er-srow er-click" :class="{ 'er-running': autoRow(s) }" :style="srowCols" tabindex="0" @click="openStage(rly.id, s.id)" @keydown.enter="rowEnter($event, s)">
            <!-- a stage run twice is one row: SS2 · SS4, a pass cancelled on the day struck out -->
            <span v-if="s.notRun" class="er-ss er-notrun">Not run</span>
            <span v-else class="er-ss"><span v-for="(p, k) in passList(s)" :key="k"><s v-if="p.cancelled">{{ p.ss }}</s><template v-else>{{ p.ss }}</template><template v-if="k < passList(s).length - 1"> · </template></span></span>
            <span class="er-clip">{{ s.name }}</span><span class="er-r er-mono">{{ len(s.lengthM) }}</span>
            <span class="er-st">
              <span v-if="autoRow(s)" class="er-pill working" :style="{ '--er-done': autoPct }">{{ STATUS.working.label }} <span class="er-wn">{{ autoLeg }}</span></span>
              <span v-else class="er-pill" :class="pill(s.status).cls">{{ pill(s.status).label }}</span>
            </span>
            <!-- @click.stop: the whole row opens the stage, so without it the button would do both. The row's
                 Enter is guarded the same way, in rowEnter: Enter on a focused button fires its click AND bubbles. -->
            <span class="er-act">
              <!-- Everything about the auto recce answers in THIS cell (the user, 2026-11-14: "move that to a
                   button in the same collum as autp recce. all indication should be there"). The banner is easy to
                   miss and the question can arrive while the player is looking at the list, so while one waits on
                   an answer the cell holds the answer; the rest of the time it holds Stop. -->
              <template v-if="autoRow(s) && autoAsk">
                <BngButton :accent="ACCENTS.main" @click.stop="action('autoRecceDownload')">Download</BngButton>
                <BngButton :accent="ACCENTS.outlined" @click.stop="action('autoRecceSkip')">Not now</BngButton>
              </template>
              <BngButton v-else-if="autoRow(s)" :accent="ACCENTS.outlined" @click.stop="action('autoRecceStop')">Stop</BngButton>
              <BngButton v-else-if="st.autoOk && s.status === 'none'" :accent="ACCENTS.secondary" :disabled="busy" @click.stop="action('autoRecce', rly.id, s.id)">{{ outcomeFor(s) ? "Try again" : "Auto recce" }}</BngButton>
              <!-- Reset takes the same cell on a stage that HAS a line, so every row has exactly one control and
                   the column reads as one question. Deliberately NOT gated on st.autoOk: it removes files and asks
                   BeamNG.Earth for nothing, so a player on a stock BeamNG.Earth still has their way back from a
                   recce they are unhappy with -- gating it the way Auto recce is gated would lock out exactly the
                   players with no auto recce to fall back on. A driven recce, or any line with times on it (they
                   stop being placed), is confirmed on the stage page, where there is room to say what is lost; the
                   row opens it rather than deleting from under them. -->
              <BngButton v-else-if="s.line === 'matched' && !s.best" :accent="ACCENTS.outlined" :disabled="busy" @click.stop="action('reset', rly.id, s.id)">Reset</BngButton>
              <BngButton v-else-if="s.line" :accent="ACCENTS.outlined" @click.stop="askReset(rly.id, s.id)">Reset</BngButton>
            </span>
            <!-- Old line: it has times, none on the line it runs on now (menu.lua, oldLine): not placed, not driven -->
            <span v-if="s.oldLine" class="er-r er-none" :title="time(s.best)">Old line</span>
            <span v-else class="er-r er-mono" :class="{ 'er-none': !s.best }">{{ s.best ? time(s.best) : "–" }}</span>
            <!-- Place: the better of your placings over the stage's passes, against the real field -->
            <span v-if="rly.hasBoard" class="er-plc"><template v-if="s.place">{{ ord(s.place.pos) }}<small>of {{ s.place.of }}</small></template><span v-else class="er-none">–</span></span>
            <span class="er-go">›</span>
          </div>
        </div>
        <!-- how an auto recce ended, one line per stage: the pill only ever says whether the stage can be driven -->
        <div v-if="arr(rly.autoLines).length" class="er-under">
          <div v-for="l in arr(rly.autoLines)" :key="l.stageId" class="er-outcome" :class="outcomeCls(l.kind)">
            <span v-if="l.ssLabel" class="er-ssx">{{ l.ssLabel }}</span>{{ l.text }}
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
        </template>
      </section>

      <!-- ===== a stage ===== -->
      <section v-else-if="view === 'stage' && stg" class="er-stage-page">
        <div>
          <div class="er-stage-ss">{{ ssLine }}</div>
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
            <template v-if="autoHere && autoAsk">
              <BngButton :accent="ACCENTS.main" @click="action('autoRecceDownload')">Download {{ MB(autoAsk.bytes) }}</BngButton>
              <BngButton :accent="ACCENTS.outlined" @click="action('autoRecceSkip')">Not now</BngButton>
            </template>
            <BngButton v-else-if="autoHere" :accent="ACCENTS.outlined" @click="action('autoRecceStop')">Stop the auto recce</BngButton>
            <BngButton v-else-if="stg.autoCan" :accent="ACCENTS.secondary" :disabled="busy || !st.autoOk" @click="action('autoRecce', stg.eventId, stg.id)">Auto recce</BngButton>
            <!-- menu.lua sets autoCan only on a stage with no line, so on a stage that has one the Auto recce
                 button is already absent and Reset is simply its v-else-if: the row keeps four buttons, never
                 five. A matched line goes at once (1.25 s to make again); a driven recce asks first, because it
                 cost the stage, driven, and cannot be got back. -->
            <BngButton v-else-if="stg.line === 'matched' && !stg.best" :accent="ACCENTS.outlined" :disabled="busy" @click="action('reset', stg.eventId, stg.id)">Reset</BngButton>
            <BngButton v-else-if="stg.line && !confirmReset" :accent="ACCENTS.outlined" @click="confirmRecce = false; confirmReset = true">Reset</BngButton>
            <BngButton :accent="ACCENTS.secondary" :disabled="busy" @click="recce">Recce</BngButton>
          </div>
          <!-- The confirm: for a driven recce, and for a matched line with times on it (they stop being placed).
               A matched line with no times is not confirmed: confirming the cheap case would teach clicking
               through, and the once it mattered that habit would carry. -->
          <div v-if="confirmReset && stg.line" class="er-card er-confirm">
            <div>
              <b>{{ stg.line === "matched" ? "Remove the matched line?" : "Remove the recce you drove?" }}</b><br>
              <!-- It does NOT promise the auto recce will manage one here: whether the map has roads for this
                   stage on this computer is only known by asking for them, and a confirm that guessed would be
                   worse than one that does not say. -->
              <span v-if="stg.line === 'matched'">Afterwards you can run the auto recce again, or drive the recce.</span>
              <span v-else>This cannot be undone. Afterwards you can run the auto recce, or drive the recce again.</span>
              <template v-if="stg.best"><br><span>{{ PLACED_WARN }}</span></template>
            </div>
            <div class="er-confirm-row">
              <BngButton :accent="ACCENTS.outlined" @click="confirmReset = false">Keep it</BngButton>
              <BngButton :accent="ACCENTS.main" :disabled="busy" @click="confirmReset = false; action('reset', stg.eventId, stg.id)">{{ stg.line === "matched" ? "Remove the line" : "Remove the recce" }}</BngButton>
            </div>
          </div>
          <!-- A new recce over a line with times on it: said once before it starts (the new line replaces this one) -->
          <div v-if="confirmRecce && stg.line && stg.best" class="er-card er-confirm">
            <div><b>Drive a new recce?</b><br><span>{{ PLACED_WARN }}</span></div>
            <div class="er-confirm-row">
              <BngButton :accent="ACCENTS.outlined" @click="confirmRecce = false">Not now</BngButton>
              <BngButton :accent="ACCENTS.main" :disabled="busy" @click="confirmRecce = false; action('recce', stg.eventId, stg.id)">Recce</BngButton>
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
        <!-- the Leaderboard card above Your runs (the user, 2026-11-14), which then shows the last two -->
        <div class="er-rcol">
        <EarthRallyBoard v-if="stg.board" :b="stg.board" :best="stg.best" @pass="choosePass" />
        <div class="er-card er-runs">
          <h3>Your runs</h3>
          <div v-if="stg.best" class="er-best-box"><span class="er-t">{{ time(stg.best) }}</span><span class="er-badge">BEST</span></div>
          <div v-for="(r, i) in runsShown" :key="i" class="er-run">
            <span>{{ when(r.date) }} <span v-if="r.last" class="er-dim">· last</span></span>
            <span class="er-mono">{{ time(r.timeS) }}</span>
            <span :class="r.penaltyS > 0 ? 'er-pen' : 'er-clean'">{{ r.text }}</span>
          </div>
          <div v-if="!arr(stg.runs).length" class="er-muted">No runs yet.</div>
          <div class="er-muted er-small">Times include penalties.</div>
        </div>
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
import EarthRallyHome from "./EarthRallyHome.vue"
import EarthRallySeason from "./EarthRallySeason.vue"
import EarthRallyPic from "./EarthRallyPic.vue"
import EarthRallyBoard from "./EarthRallyBoard.vue"
import EarthRallyResults from "./EarthRallyResults.vue"
import {
  state, season, rally, stage, busyMsg, action as luaAction, refreshState, takeOpenAt, loadSeason, loadRally, loadStage,
  closeMenu, previewHud,
  arr, units, len, lenNum, riseNum, riseUnit, time, when, ord, days, ssName, STATUS, AUTO_OUTCOME, RUN_WORDS,
} from "./store.js"

const view = ref("rallies")
// pass: the stage leaderboard's pass the player picked (null: the one they place best on, chosen in Lua)
const sel = ref({ seasonId: null, eventId: null, stageId: null, pass: null })
const st = computed(() => state.value || {})
const ssn = computed(() => (season.value && !season.value.missing && season.value.id === sel.value.seasonId) ? season.value : null)
const rly = computed(() => (rally.value && !rally.value.missing && rally.value.id === sel.value.eventId) ? rally.value : null)
// (the rally as well as the stage: a stage's id is its line's name, and two rallies can both have a "Wildcat")
const stg = computed(() => (stage.value && !stage.value.missing && stage.value.id === sel.value.stageId &&
  stage.value.eventId === sel.value.eventId) ? stage.value : null)
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
  if (a.phase === "asking") return a.ask ? MB(a.ask.bytes) + "?" : "your call"
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

// Rallies > Season > Rally > Stage: { label, go } each, go (a way back) on all but the last
const crumbs = computed(() => {
  if (view.value === "settings") return [{ label: "Settings" }]
  const c = [{ label: "Rallies", go: () => go("rallies") }]
  const seasonCrumb = s => ({ label: s.name, go: () => openSeason(s.id) })
  if (view.value === "season") c.push({ label: (ssn.value && ssn.value.name) || "" })
  if (view.value === "rally" && rly.value) {
    if (rly.value.season) c.push(seasonCrumb(rly.value.season))
    c.push({ label: rly.value.name })
  }
  if (view.value === "stage" && stg.value) {
    const s = stg.value
    if (!s.single) {
      if (s.season) c.push(seasonCrumb(s.season))
      c.push({ label: s.rally, go: () => openRally(s.eventId, false) })
    }
    c.push({ label: s.name })
  }
  return c
})

// ---- a rally's page
// Stages / Results / Rules: Results with real results to show, Rules when the file has any
const rallyTab = ref("stages")
const rallyTabs = computed(() => {
  const r = rly.value
  const t = [{ id: "stages", label: "Stages" }]
  if (r && r.results) t.push({ id: "results", label: "Results" })
  if (r && arr(r.rules).length) t.push({ id: "rules", label: "Rules" })
  return t
})
const curTab = computed(() => (rallyTabs.value.some(t => t.id === rallyTab.value) ? rallyTab.value : "stages"))
const legend = computed(() => !!(rly.value && (rly.value.anyCancelled || rly.value.hasBoard)))
const cancelledSs = computed(() => {
  for (const s of arr(rly.value && rly.value.list)) {
    const p = arr(s.passes).find(x => x.cancelled)
    if (p) return p.ss
  }
  return ""
})
// a row's passes (menu.lua: the itinerary's, or SS1, SS2... in map order with none). A line the itinerary never
// runs has none and says "Not run" (s.notRun): it is never given a made-up SS number.
const passList = s => arr(s && s.passes)
// The columns: the SS cell widens for "SS11 · SS15", and Place comes in with real results. The seventh column
// (Auto recce / Reset) keeps its 210px whatever else changes (see .er-srow).
const srowCols = computed(() => {
  const r = rly.value
  const wide = arr(r && r.list).some(s => arr(s.passes).length > 1)
  return { gridTemplateColumns: `${wide ? 170 : 100}px minmax(0, 1fr) 130px 260px 210px 150px ${r && r.hasBoard ? "130px " : ""}30px` }
})
const rallySub = computed(() => {
  const r = rly.value
  if (!r) return ""
  const parts = [days(r.dates, true), r.place].filter(Boolean)
  if (parts.length) return parts.join(" · ")
  return `From ${r.file || "your map"} · ${r.stages} ${r.stages === 1 ? "stage" : "stages"}`
})

// ---- a stage's page
// "SS2 · SS4 · OLYMPUS RALLY 2026"; "NOT RUN · ..." for a line the itinerary never runs; "STAGE" for a stage on
// its own
const ssLine = computed(() => {
  const s = stg.value
  if (!s) return ""
  if (s.single) return "STAGE"
  const ss = s.notRun ? "NOT RUN" : arr(s.passes).map(p => p.ss).join(" · ")
  return [ss, (s.rally || "").toUpperCase()].filter(Boolean).join(" · ")
})
const runsShown = computed(() => {
  const runs = arr(stg.value && stg.value.runs)
  return stg.value && stg.value.board ? runs.slice(0, 2) : runs
})

const banner = computed(() => {
  const s = st.value
  if (s.auto) {
    const n = `Auto recce of ${ssName(s.auto)}`
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
  if (s.run && s.run.busy) return `${ssName(s.run)}: ${RUN_WORDS[s.run.state] || s.run.state}`
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
function openSeason(id) {
  sel.value = { seasonId: id, eventId: null, stageId: null, pass: null }
  loadSeason(id)
  go("season")
}
// redirect: a rally of one stage and no season opens on its stage (Back from that stage goes to Rallies, so it never
// comes back through here; false from the stage's own crumb all the same)
function openRally(id, redirect = true) {
  if (sel.value.eventId !== id) rallyTab.value = "stages"
  sel.value = { ...sel.value, eventId: id, stageId: null, pass: null }
  loadRally(id, r => {
    if (redirect && r && r.single && r.id === id && view.value === "rally" && sel.value.eventId === id) {
      const first = arr(r.list)[0]
      if (first) openStage(id, first.id)
    }
  })
  go("rally")
}
// Reset's confirm, for a driven recce (the matched case needs none). Held here rather than per stage because
// it must not survive leaving the page: a confirm still up when another stage is opened would sit over a line it
// was never asked about.
const confirmReset = ref(false)
// A new recce over a line that has times on it asks first, as Reset does: those times stop being placed.
const confirmRecce = ref(false)
const PLACED_WARN = "If the new line runs differently, your times here stop counting on the leaderboards (they stay in Your runs)."
function recce() {
  const s = stg.value
  if (s && s.line && s.best) { confirmReset.value = false; confirmRecce.value = true }
  else if (s) action("recce", s.eventId, s.id)
}

function openStage(eventId, stageId) {
  sel.value = { ...sel.value, eventId, stageId, pass: null }
  confirmReset.value = false
  confirmRecce.value = false
  loadStage(eventId, stageId)
  go("stage")
}
// the leaderboard's pass toggle
function choosePass(ss) {
  sel.value = { ...sel.value, pass: ss }
  loadStage(sel.value.eventId, sel.value.stageId, ss)
}

// Reset pressed on a list row whose line was driven, or that has times: open the stage and put the confirm up
// there, rather than deleting from under the player in a row that has no room to say what is lost.
function askReset(eventId, stageId) {
  openStage(eventId, stageId)
  confirmReset.value = true
}
function back() {
  if (view.value === "stage") {
    const single = stg.value ? stg.value.single : (rly.value && rly.value.single)
    if (single) go("rallies")
    else openRally(sel.value.eventId, false)
  } else if (view.value === "rally") {
    const s = rly.value && rly.value.season
    if (s) openSeason(s.id)
    else go("rallies")
  } else if (view.value === "season" || view.value === "settings") go("rallies")
  else closeMenu()
}
function action(what, eventId, stageId) {
  luaAction(what, eventId, stageId, () => {
    if (view.value === "stage" && sel.value.stageId) loadStage(sel.value.eventId, sel.value.stageId, sel.value.pass)
    if (view.value === "rally" && sel.value.eventId) loadRally(sel.value.eventId)
  })
}

// the poll: the state every second, the page's own data every two
let timer = null
let tick = 0
function poll() {
  refreshState()
  if (++tick % 2) return
  if (view.value === "season" && sel.value.seasonId) loadSeason(sel.value.seasonId)
  if (view.value === "rally" && sel.value.eventId) loadRally(sel.value.eventId)
  if (view.value === "stage" && sel.value.stageId) loadStage(sel.value.eventId, sel.value.stageId, sel.value.pass)
}

onMounted(() => {
  // (opened at a page: the results card's Rally menu, a pause-menu rally)
  refreshState()
  takeOpenAt(at => {
    if (at && at.view === "stage" && at.eventId && at.stageId) openStage(at.eventId, at.stageId)
    else if (at && at.view === "rally" && at.eventId) openRally(at.eventId)
    else if (at && at.view === "season" && at.eventId) openSeason(at.eventId)
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
.er-crumbs { font-size: 18px; color: var(--er-muted); white-space: nowrap; overflow: hidden; text-overflow: ellipsis; min-width: 0;
  span + span::before { content: "›"; margin: 0 10px; color: #6f7480; }
  span:last-child { color: #fff; }
  .er-cgo { cursor: pointer; }
  .er-cgo:hover { color: #fff; text-decoration: underline; } }
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

.er-clip { overflow: hidden; white-space: nowrap; text-overflow: ellipsis; }
.er-report { background: rgba(0, 0, 0, 0.4); border-radius: 0.25rem; padding: 12px 14px; font-size: 15px; line-height: 1.5; }
.er-report-full { margin-top: 18px; summary { cursor: pointer; font-weight: 600; } }

/* a rally's banner: its photo behind a dark fade, the logo (or a drawn plate), the name and its numbers */
.er-rbanner { position: relative; height: 196px; border-radius: 0.5rem; overflow: hidden; display: flex; align-items: center; gap: 34px; padding: 0 34px; margin-bottom: 18px;
  > :not(.er-rb-photo) { position: relative; z-index: 1; } }
.er-rbanner .er-rb-photo { position: absolute; inset: 0;
  &::after { content: ""; position: absolute; inset: 0; z-index: 1;
    background: linear-gradient(90deg, rgba(8, 10, 14, 0.92) 0%, rgba(8, 10, 14, 0.78) 45%, rgba(8, 10, 14, 0.25) 100%); } }
.er-rbanner .er-rb-logo { width: 290px; height: 145px; flex-shrink: 0; background: none;
  :deep(.er-plate) { min-width: 100%; padding: 18px 16px 14px; }
  :deep(.er-pn) { font-size: 24px; } }
.er-rb-text { min-width: 0; }
.er-rb-round { font-size: 14px; font-weight: 700; letter-spacing: 0.14em; color: var(--er-orange); text-transform: uppercase; }
.er-rb-name { font-size: 46px; font-weight: 700; line-height: 1.1; }
.er-rb-sub { font-size: 19px; color: #dfe3ea; margin-top: 4px; }
.er-rb-stats { margin-left: auto; display: flex; gap: 36px; flex-shrink: 0;
  .er-stat { text-align: right; }
  .er-v { font-size: 30px; }
  .er-l { font-size: 13px; } }
.er-under-banner { display: flex; align-items: center; gap: 20px; margin-bottom: 14px; }
.er-legend { margin-left: auto; font-size: 15px; color: var(--er-muted); s { color: #6f7480; } }
/* in-page tabs: the game's segmented look */
.er-tabs { display: flex; gap: 4px; background: rgba(0, 0, 0, 0.45); border-radius: 0.25rem; padding: 4px;
  span { padding: 8px 22px; border-radius: 3px; font-size: 18px; font-weight: 600; color: var(--er-muted); cursor: pointer; }
  span.on { background: var(--er-orange-500); color: #fff; } }
.er-rules { max-width: 760px; padding: 12px 0; }
.er-rule { display: grid; grid-template-columns: 1fr auto; padding: 18px 30px; font-size: 22px; align-items: center;
  & + .er-rule { border-top: 1px solid rgba(255, 255, 255, 0.06); }
  .er-rv { font-family: "Overpass Mono", monospace; font-weight: 700; }
  .er-in { font-size: 13px; font-weight: 700; letter-spacing: 0.06em; padding: 2px 8px; margin-left: 12px; border-radius: 3px; background: var(--er-blue); vertical-align: 3px; } }
.er-stages { padding: 8px 0; }
/* Seven tracks: the action column comes out of Name's 1fr, NOT out of Status -- Status already holds the longest
   pill ("Recce recommended", about 177px) with its 30px padding, and below about 215px that pill overruns the
   column. 210px rather than 1.3.0's 160px, because the cell now holds TWO controls while a download waits on an
   answer: at the row's own button size (15px on a 20px line, no min-width, no margin) "Download" is about 92px
   and "Not now" about 83px, which with a 12px gap is 187px. Name goes from about 1066px to 856px at 1920, and the
   longest name in a real rally is about 460px. */
.er-srow { display: grid; grid-template-columns: 100px 1fr 130px 260px 210px 150px 30px; align-items: center; height: 58px; padding: 0 28px; font-size: 20px; border-left: 4px solid transparent;
  & + .er-srow { border-top: 1px solid rgba(255, 255, 255, 0.06); }
  &.er-hdr { height: 40px; font-size: 14px; text-transform: uppercase; letter-spacing: 0.08em; color: var(--er-muted); }
  &.er-click { cursor: pointer; }
  &.er-click:hover, &.er-click:focus { background: rgba(199, 91, 30, 0.22); border-left-color: var(--er-orange); }
  /* The stage being matched, findable while scrolling a long rally: the left border it already has, in blue.
     This has to beat the hover and focus rules above on SPECIFICITY, not on order -- it is three classes plus the
     pseudo-class against their two, so it holds wherever it sits in the file. Written the other way round (same
     specificity, later in the file) the mark would vanish the moment anyone moved this block, or the pointer. */
  &.er-running, &.er-running.er-click:hover, &.er-running.er-click:focus { border-left-color: var(--er-blue); }
  .er-ss { font-family: "Overpass Mono", monospace; font-weight: 700; color: var(--er-muted); white-space: nowrap; font-size: 18px;
    s { color: #6f7480; text-decoration-thickness: 2px; } }
  .er-notrun { font-family: "Noto Sans", sans-serif; font-weight: 600; font-size: 15px; color: #6f7480; }
  .er-plc { font-family: "Overpass Mono", monospace; font-weight: 700; text-align: right;
    small { font-weight: 400; color: var(--er-dim); font-size: 14px; margin-left: 4px; } }
  .er-r { text-align: right; }
  .er-st { padding-left: 30px; }
  .er-none { color: #6f7480; }
  .er-go { color: var(--er-dim); text-align: right; }
  /* The action column. The button is sized by the game's own hooks rather than by overriding its rules: it sets
     font-size / line-height itself ("default value to be overriden with the parent component's styles",
     utility/button.vue:91-92) so those need :deep, while min-width (6em -- more than this cell has) and margin are
     custom properties it reads from whatever contains it. 15px text on a 20px line is a 29px button in a 58px row. */
  .er-act { padding-left: 24px; --bng-button-min-width: 0; --bng-button-margin: 0;
    display: flex; gap: 12px; align-items: center;
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

.er-stage-page { display: grid; grid-template-columns: minmax(0, 1.25fr) minmax(0, 1fr); gap: 28px; align-items: start; }
.er-rcol { display: flex; flex-direction: column; gap: 20px; min-width: 0; }
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
