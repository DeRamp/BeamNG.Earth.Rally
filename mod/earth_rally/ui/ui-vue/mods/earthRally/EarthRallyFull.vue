<template>
  <!-- The full rally's two pages in the menu (1.7.0; mock-ups 1 and 2, approved 2026-11-15, trimmed after the first
       drive, #24):
       kind "start"  the start screen: the car you're in, its class (guessed, any can be picked), Realistic or Casual,
                     cancelled stages as they really ran or all of them, Start (at the rally's start on the map).
       kind "card"   the time card: the running order with your times and stage places, where you are (getting the
                     stages ready, at a service, on a transit, on a stage) with its one button, the Super Rally card
                     after a Realistic recovery, your overall place, and Save and quit / Retire, each with a confirm
                     (#28); once finished, the result and New rally / Continue driving (#71).
       Each page's main button is a big one at the lower right (docs/mockups-1.7.0/rev4.html, #56 #57).
       Data: earthRally_main.uiRallyStart / uiRallyCard (store.js).
       (rally loop, docs/mockups-rally-loop) A timed rally (its event has target times; the card carries a clock)
       adds the rally clock, each control's Due / In / Road, a service's out time, the transit's due time and time
       left, and the road penalties; the start screen says when the rally really starts. Untimed: as before. -->
  <section class="er-full">
    <!-- ===== start ===== -->
    <template v-if="kind === 'start'">
      <div v-if="!s" class="er-muted">Loading...</div>
      <div v-else-if="!s.canRun" class="er-card er-pad">{{ s.why }}</div>
      <template v-else>
      <div class="er-two">
        <div class="er-card er-pad">
          <h2>{{ s.name }}</h2>
          <div class="er-muted">{{ s.stages }} stages · {{ s.days }} {{ s.days === 1 ? "day" : "days" }} · {{ s.services }} {{ s.services === 1 ? "service" : "services" }}<template v-if="s.crews"> · real field: {{ s.crews }} National crews</template></div>
          <div v-if="s.startsAt && s.startsAt.text" class="er-when"><span class="er-sky" :class="s.startsAt.light || 'day'"></span><span>Starts {{ s.startsAt.text }}{{ LIGHT_WORDS[s.startsAt.light] || "" }}</span></div>
          <div class="er-lbl">Car</div>
          <div class="er-box"><span>{{ s.car ? s.car.name : (s.canPick ? "Choose a car" : "Get in a car first") }}</span><span v-if="s.car && s.car.drivetrain" class="er-muted">{{ s.car.drivetrain }}{{ s.car.last ? " · your last car" : "" }}</span></div>
          <!-- (at the main menu: the game's own vehicle picker, then back here) -->
          <div v-if="s.canPick" class="er-box er-pickcar" tabindex="0" bng-nav-item @click="pickCar(props.id, 'start')" @keydown.enter="pickCar(props.id, 'start')"><span>Choose {{ s.car ? "another" : "a" }} car…</span><span class="er-muted">›</span></div>
          <div class="er-lbl">Class</div>
          <div class="er-seg er-wrap">
            <span v-for="c in arr(s.classes)" :key="c" tabindex="0" bng-nav-item :class="{ on: cls === c }" @click="cls = c" @keydown.enter="cls = c">{{ c }}</span>
          </div>
          <div class="er-muted er-small">{{ cls === s.class ? "Picked from your car's drivetrain." : "Your pick." }}</div>
        </div>
        <div class="er-card er-pad er-col">
          <h3 class="er-sec">Rally settings</h3>
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
          <!-- (the owner, 2026-11-19) traffic on the road sections between stages, as in a real rally; each stage is
               cleared of it either way (rallyRun trafficStart). On leaves the world's own traffic as it is: a world
               started without traffic has none, and says so. Picked first: the last pick, else the world's -->
          <div class="er-lbl">Traffic on road sections</div>
          <div class="er-seg">
            <span tabindex="0" bng-nav-item :class="{ on: traffic === 'on' }" @click="traffic = 'on'" @keydown.enter="traffic = 'on'">On</span>
            <span tabindex="0" bng-nav-item :class="{ on: traffic === 'off' }" @click="traffic = 'off'" @keydown.enter="traffic = 'off'">Off</span>
          </div>
          <div class="er-muted er-small">{{ traffic === "on" ? "Traffic on the roads between stages. Each stage is closed to it." : "No traffic for the whole rally." }}</div>
          <div v-if="traffic === 'on' && s.traffic && s.traffic.world === false" class="er-warn er-small">This world has no traffic. Start BeamNG.Earth with traffic on to have it on road sections.</div>
          <div class="er-foot">
            <div v-if="s.toRecce" class="er-muted er-small">{{ s.toRecce }} {{ s.toRecce === 1 ? "stage gets its" : "stages get their" }} line first: the auto recce takes you to each.</div>
            <div v-if="arr(s.heldOut).length" class="er-warn er-small">Held out: {{ arr(s.heldOut).map(h => h.why ? `${h.name} (${h.why})` : h.name).join(", ") }}</div>
          </div>
        </div>
      </div>
      <!-- (#56) Start out of the settings: the big way in at the lower right, selected as the page opens, its
           warnings just above it -->
      <div class="er-corner">
        <div v-if="s.weather === 'none'" class="er-warn er-nofork">This rally has no stored weather: your own weather</div>
        <div v-else-if="s.weather === 'noHooks'" class="er-warn er-nofork">Your BeamNG.Earth can't set the rally's time and weather.</div>
        <div v-if="s.saved" class="er-warn">This replaces your saved rally (at {{ s.saved.at }}).</div>
        <div v-if="s.inProgress && s.inProgress !== s.id" class="er-warn">Another rally is under way: leave it from its time card first.</div>
        <BngButton ref="startBtn" v-bng-ui-nav-focus="1" class="er-huge" :accent="ACCENTS.main" :disabled="!s.car" @click="start">
          <span class="er-hb">Start the rally<small v-if="!s.car">{{ s.canPick ? "choose a car first" : "get in a car first" }}</small><small v-else-if="s.canPick">loads BeamNG.Earth with this car</small><small v-else-if="s.start">first car away {{ s.start }}</small></span>
        </BngButton>
      </div>
      </template>
    </template>

    <!-- ===== time card ===== -->
    <template v-else>
      <div v-if="!c" class="er-muted">Loading...</div>
      <div v-else-if="c.none" class="er-card er-pad">No rally is under way.<div v-if="state.message" class="er-muted">{{ state.message }}</div></div>
      <!-- (#71) finished: the result, Full results, and the two ways on, New rally selected -->
      <template v-else-if="c.done">
        <div class="er-card er-fin">
          <div class="er-kick">{{ c.name }}{{ !c.unclassified && arr(c.rows).some(r => r.final) ? " · checked in at the final service" : "" }}</div>
          <h2>{{ c.unclassified ? "Rally over · not classified" : "Rally finished" }}</h2>
          <div class="er-fin-t">{{ longTime(c.totalS) }}</div>
          <div v-if="c.overall && !c.unclassified" class="er-muted er-fin-p">P{{ c.overall.pos }} of {{ c.overall.of }} · {{ c.class }} {{ ord(c.overall.classPos) }} of {{ c.overall.classOf }}<template v-if="c.points != null"> · +{{ c.points }} points in the season</template></div>
          <BngButton v-if="c.overall" class="er-fin-res" :accent="ACCENTS.outlined" @click="emit('view', 'results', c.id)">Full results</BngButton>
        </div>
        <div class="er-corner er-corner-row">
          <BngButton class="er-huge er-huge-2" :accent="ACCENTS.outlined" :disabled="ending" @click="endRally('endDrive')">
            <span class="er-hb">Continue driving<small>free roam in BeamNG.Earth</small></span>
          </BngButton>
          <BngButton ref="newBtn" v-bng-ui-nav-focus="1" class="er-huge er-huge-2" :accent="ACCENTS.main" :disabled="ending" @click="endRally('endNew')">
            <span class="er-hb">New rally<small>back to Home</small></span>
          </BngButton>
        </div>
      </template>
      <template v-else>
      <div class="er-two er-card-grid">
        <div class="er-card er-pad er-tc">
          <div class="er-tc-head"><h2>{{ c.name }}</h2><span v-if="timed" class="er-clock">{{ [c.clock.date, c.clock.time].filter(Boolean).join(" · ") }}</span><span class="er-mode">{{ c.mode === "realistic" ? "Realistic" : "Casual" }} · {{ c.class }}</span></div>
          <div class="er-tc-rows" :class="{ 'er-t2': timed }">
            <div v-if="timed" class="er-tr er-thd"><span></span><span></span><span class="er-r">Due</span><span class="er-r">In</span><span class="er-r">Road</span><span class="er-r">Stage</span><span class="er-r">Pos</span></div>
            <template v-for="(r, i) in arr(c.rows)" :key="i">
              <div v-if="dayHead(i)" class="er-day">Day {{ r.day }}</div>
              <div class="er-tr" :class="rowCls(r)">
                <span class="er-mono">{{ r.label }}</span>
                <!-- (plan E) a stage's stored weather in a word beside its name: dim once driven, none when not stored
                     (docs/mockups-rally-loop/weather.html, a) -->
                <span v-if="r.weather" class="er-sn"><span class="er-clip">{{ r.name || "" }}</span><span class="er-wx" :class="{ done: r.done }"><svg viewBox="0 0 24 24" v-html="wxIcon(r.weather)"></svg>{{ wxText(r.weather) }}</span></span>
                <span v-else-if="timed" class="er-clip er-nm">{{ r.name || "" }}<small v-if="stopNote(r)">{{ stopNote(r) }}</small></span>
                <span v-else class="er-clip">{{ r.name || "" }}</span>
                <template v-if="timed">
                  <!-- (additions B) a row whose due isn't known yet: its road section's target, dim -->
                  <span v-if="!r.due && r.targetMin != null && !r.done" class="er-r"><span class="er-tgt">target {{ r.targetMin }} min</span></span>
                  <span v-else class="er-mono er-r" :class="{ 'er-dimc': !r.due }">{{ r.due || (r.done ? "" : "–") }}</span>
                  <span class="er-mono er-r">{{ r.timeIn || "" }}</span>
                  <span class="er-r" :class="road(r).cls">{{ road(r).text }}</span>
                </template>
                <span class="er-mono er-r">{{ r.kind === "stage" ? (r.timeS != null ? time(r.timeS) : (r.next ? "next" : "")) : "" }}</span>
                <span class="er-mono er-r">{{ r.pos ? `${r.pos} / ${r.of}` : "" }}</span>
              </div>
            </template>
          </div>
          <div v-if="timed && c.roadPenaltyS != null" class="er-tsum"><span>Road penalties <b :class="{ 'er-late': c.roadPenaltyS > 0 }">{{ c.roadPenaltyS > 0 ? pen(c.roadPenaltyS) : "none" }}</b></span></div>
          <div v-if="arr(c.heldOut).length" class="er-muted er-small">Held out: {{ arr(c.heldOut).map(h => h.why ? `${h.ss} (${h.why})` : h.ss).join(", ") }}</div>
        </div>
        <div class="er-col er-gap">
          <!-- the Super Rally card, once, at the service rejoined at -->
          <div v-if="c.superRally && c.phase === 'stop'" class="er-card er-pad">
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
          </div>
          <!-- where you are and what is next -->
          <div v-else class="er-card er-pad">
            <template v-if="c.phase === 'prep'">
              <!-- (#34) the auto recce of each stage still to come with no line, followed -->
              <h3>GETTING THE STAGES READY</h3>
              <div class="er-muted er-small" v-if="c.prep">The auto recce matches each stage to the roads<template v-if="c.prep.of">. Stage {{ Math.max(1, c.prep.i) }} of {{ c.prep.of }}</template>. Then: to the start.</div>
              <div v-for="(p, i) in arr(c.prep && c.prep.stages)" :key="i" class="er-pr" :class="p.state">
                <span class="er-mono">{{ p.ss || "" }}</span>
                <span class="er-clip">{{ p.name }}<small>{{ prepDetail(p) }}</small></span>
                <span class="er-r">{{ { done: "✓ Ready", failed: "No line", now: prepPct(p), wait: "Waiting" }[p.state] }}</span>
                <div v-if="p.state === 'now'" class="er-pbar" :class="{ live: prepLive() }"><i :style="{ width: (prepBar() || 0) + '%' }"></i></div>
              </div>
              <!-- (1.7.2) one Stop for all of them: the owner pressed Stop once a stage before. The stages left are held out,
                   as a Stop on each did; Save and quit stays the way to leave the rally -->
              <div class="er-prstop"><BngButton :accent="ACCENTS.outlined" @click="stopPrep">{{ prepStopLabel() }}</BngButton></div>
            </template>
            <template v-else-if="c.phase === 'moving'">
              <h3>ON THE WAY TO {{ (c.at && c.at.label || "").toUpperCase() }}</h3>
            </template>
            <template v-else-if="c.phase === 'stop'">
              <h3>{{ (c.at.label || "").toUpperCase() }}{{ c.at.name ? ` · ${c.at.name}` : "" }}</h3>
              <!-- (additions B) driven in and checked in at its "in" control: time in, due, the result, the out time
                   the clock jumps to -->
              <div v-if="c.at.checkIn" class="er-cibox">
                <div class="er-cikind">{{ IN_WORDS[c.at.checkIn.inType] || "Check-in" }}<span v-if="c.at.checkIn.free">early check-in allowed</span></div>
                <div class="er-tcrow"><span>Time in</span><b>{{ c.at.checkIn.timeIn }}</b></div>
                <div class="er-tcrow"><span>Due</span><b>{{ c.at.checkIn.due }}</b></div>
                <div class="er-tcrow"><span>Result</span><b :class="ciResult(c.at.checkIn).cls">{{ ciResult(c.at.checkIn).text }}</b></div>
                <div v-if="c.at.checkIn.outAt" class="er-tcrow"><span>Out</span><b>{{ c.at.checkIn.outAt }}</b></div>
              </div>
              <div v-if="c.nextStage" :class="{ 'er-cinext': c.at.checkIn }">Next: {{ c.nextStage.ss }} {{ c.nextStage.name }}<template v-if="c.nextStage.lengthM"> · {{ len(c.nextStage.lengthM) }}</template><template v-if="nextDue"> · due {{ nextDue }}</template></div>
            </template>
            <template v-else-if="c.phase === 'transit' || c.phase === 'toStop'">
              <h3>TRANSIT</h3>
              <!-- timed: the due time and the time left (the rally clock stands still while the menu is open, so it
                   does not count here), red once late -->
              <div v-if="c.transit && c.transit.due" class="er-banner" :class="{ late: c.transit.late > 0 }">
                <span>To {{ c.transit.name }}</span><i>·</i><span>due <span class="er-mono">{{ c.transit.due }}</span></span>
                <template v-if="c.transit.late > 0"><i>·</i><span>{{ c.transit.late }} min late<template v-if="c.transit.penaltyS > 0"> · {{ pen(c.transit.penaltyS) }}</template></span></template>
                <template v-else-if="c.transit.leftS != null"><i>·</i><span class="er-mono">{{ mmss(c.transit.leftS) }}</span><span>left</span></template>
                <template v-if="c.transit.distM != null"><i>·</i><span class="er-mono">{{ len(c.transit.distM) }}</span></template>
                <!-- (plan E) the next stage's stored weather, its own line -->
                <span v-if="c.transit.weather" class="er-bwx"><svg viewBox="0 0 24 24" v-html="wxIcon(c.transit.weather)"></svg>{{ wxText(c.transit.weather) }}</span>
              </div>
              <div v-else-if="c.transit">To {{ c.transit.name }}<template v-if="c.transit.distM != null"> · {{ len(c.transit.distM) }}</template>
                <span v-if="c.transit.weather" class="er-bwx"><svg viewBox="0 0 24 24" v-html="wxIcon(c.transit.weather)"></svg>{{ wxText(c.transit.weather) }}</span></div>
              <div class="er-muted er-small">Follow the arrows.<template v-if="c.transit && c.transit.due"> Late costs a road penalty for each minute.</template></div>
            </template>
            <template v-else-if="c.phase === 'toGo'">
              <h3>NEXT: {{ (c.at && c.at.label || "").toUpperCase() }}</h3>
            </template>
            <template v-else-if="c.phase === 'stage'">
              <h3>{{ c.at ? c.at.label : "" }} UNDER WAY</h3>
              <div v-if="c.at">{{ c.at.name }}</div>
            </template>
          </div>
          <div class="er-card er-pad">
            <h3>OVERALL</h3>
            <template v-if="c.overall">
              <div class="er-row2"><span>Position</span><b>P{{ c.overall.pos }} / {{ c.overall.of }}</b></div>
              <div class="er-row2"><span>{{ c.class }}</span><b>{{ ord(c.overall.classPos) }} / {{ c.overall.classOf }}</b></div>
              <div class="er-row2"><span>Gap to leader</span><span class="er-mono">{{ c.overall.gapS > 0.05 ? "+" + longTime(c.overall.gapS) : "leading" }}</span></div>
            </template>
            <div v-if="timed && c.roadPenaltyS > 0" class="er-row2"><span>Road penalties</span><span class="er-mono er-late">{{ pen(c.roadPenaltyS) }}</span></div>
            <div class="er-row2"><span>Your total</span><span class="er-mono">{{ longTime(c.totalS) }}</span></div>
          </div>
          <!-- leaving: continue later, or retire (#28) -->
          <div class="er-card er-pad">
            <template v-if="ask === 'leave'">
              <h3>SAVE AND QUIT?</h3>
              <div>You continue later from {{ c.leave ? c.leave.at : "the last service" }}.</div>
              <div v-if="c.leave && c.leave.superRally" class="er-warn">{{ c.leave.superRally }} is under way: it is scored under Super Rally.</div>
              <div v-if="c.leave && arr(c.leave.redo).length" class="er-warn">{{ arr(c.leave.redo).join(", ") }}: driven again.</div>
              <div class="er-btns">
                <BngButton v-bng-ui-nav-focus="1" :accent="ACCENTS.main" @click="leave">Save and quit</BngButton>
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
              <BngButton :accent="ACCENTS.outlined" @click="ask = 'leave'">Save and quit</BngButton>
              <BngButton :accent="ACCENTS.outlined" @click="ask = 'retire'">Retire</BngButton>
            </div>
          </div>
        </div>
      </div>
      <!-- (#57) the card's one way on, the start screen's big button at the lower right, selected as it comes up -->
      <div v-if="c.phase !== 'prep' && c.phase !== 'moving'" class="er-corner">
        <BngButton ref="goBtn" v-bng-ui-nav-focus="1" class="er-huge" :accent="ACCENTS.main" @click="goNext">
          <span class="er-hb">{{ goLabel.t }}<small v-if="goLabel.s">{{ goLabel.s }}</small></span>
        </BngButton>
      </div>
      </template>
    </template>
    <div v-if="busyMsg" class="er-msg">{{ busyMsg }}</div>
  </section>
</template>

<script setup>
import { ref, computed, watch, nextTick } from "vue"
import { BngButton, ACCENTS } from "@/common/components/base"
import { vBngUiNavFocus } from "@/common/directives"
import { pickCar, units, state, action, mmss, rallyStart, rallyCard, rallyAction, busyMsg, closeMenu, focusButton, arr, len, time, longTime, ord, wxText, wxIcon } from "./store.js"

const props = defineProps({ kind: { type: String, default: "card" }, id: { type: String, default: null } })
const emit = defineEmits(["view"])

// "at night": the start's light (rallyRun.startInfo startsAt.light, from the sun's height at the start)
const LIGHT_WORDS = { night: ", at night", dusk: ", at dusk", dawn: ", at dawn", day: ", in daylight" }
const s = computed(() => (rallyStart.value && rallyStart.value.id === props.id ? rallyStart.value : null))
const c = computed(() => rallyCard.value)
// a timed rally: its card carries the rally clock (nil on an untimed one, whose card stays as it was)
const timed = computed(() => !!(c.value && c.value.clock && typeof c.value.clock === "object"))
// a road penalty: "+20 s", "+2:10"
function pen(v) {
  const t = Math.round(v || 0)
  return t < 60 ? `+${t} s` : `+${mmss(t)}`
}
// A control's Road column: nothing until checked in there, "on time", or the cost in amber, late or early as Lua
// checked it in (r.roadKind: "HH:MM" strings cannot tell over midnight)
function road(r) {
  // (additions B: early at a stop at no cost -- the event allows it there, or the early penalty is off)
  if (!(r.roadPenaltyS > 0) && r.roadKind === "early") return { text: "early · free", cls: "er-dimc" }
  if (!(r.roadPenaltyS > 0)) return { text: r.timeIn ? "on time" : "", cls: "er-dimc" }
  return { text: `${pen(r.roadPenaltyS)} ${r.roadKind === "early" ? "early" : "late"}`, cls: "er-late" }
}
// (additions B) The control a stop is checked in at (rally.lua's inType), in words
const IN_WORDS = { SVC_IN: "Service in", RGC_IN: "Regroup in", MTC_IN: "MTC in", PF_IN: "Parc fermé in" }
// A stop row's small line: where it is checked in, and its out time ("service in · out 20:05"); the final service's
// MTC in is the finish
function stopNote(r) {
  if (r.kind === "stage") return ""
  const parts = []
  if (r.final && r.inType === "MTC_IN") parts.push("finish (MTC in)")
  else if (IN_WORDS[r.inType]) parts.push(IN_WORDS[r.inType].toLowerCase())
  if (r.outAt) parts.push(`out ${r.outAt}`)
  return parts.join(" · ")
}
// The stop card's Result: "On time", "2 min late · +20 s", "3 min early · no penalty"
function ciResult(ci) {
  if (ci.kind === "late") return { text: `${ci.min} min late · ${pen(ci.penaltyS)}`, cls: "er-late" }
  if (ci.kind === "early") {
    if (ci.penaltyS > 0) return { text: `${ci.min} min early · ${pen(ci.penaltyS)}`, cls: "er-late" }
    return { text: `${ci.min} min early · no penalty`, cls: "er-ok" }
  }
  return { text: "On time", cls: "er-ok" }
}
// The next stage's due time where the schedule fixes it (out of a stop), for the stop card's Next line
const nextDue = computed(() => {
  const x = c.value
  const row = x && x.nextIndex ? arr(x.rows)[x.nextIndex - 1] : null
  return row && row.due ? row.due : ""
})

const mode = ref("realistic")
const canc = ref("real")
const traffic = ref("off")
const cls = ref("L4WD")
watch(s, (x, was) => {
  if (x && (!was || was.id !== x.id)) {
    cls.value = x.class || "L4WD"
    traffic.value = x.traffic && x.traffic.pick === "on" ? "on" : "off"
  }
}, { immediate: true })

function start() {
  rallyAction("start", props.id, { mode: mode.value, class: cls.value, cancelled: canc.value, traffic: traffic.value }, r => {
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
// (#71) a finished rally closed: New rally opens Home, Continue driving closes the menu (free roam)
const ending = ref(false)
function endRally(what) {
  const id = c.value && c.value.id
  ending.value = true
  rallyAction(what, id, null, r => {
    ending.value = false
    if (!r.ok) return
    if (what === "endDrive") closeMenu()
    else emit("view", "home")
  })
}
// The main button's words, { t, s }: its big line and the small one under it. (#57: "Start transit · to SS4 Name"
// at the start and out of a service alike, the owner's call)
const goLabel = computed(() => {
  const x = c.value
  if (!x) return { t: "Go" }
  const nx = x.nextStage ? `${x.nextStage.ss} ${x.nextStage.name}` : "the next stage"
  switch (x.phase) {
    case "stop": return { t: "Start transit", s: `to ${nx}` }
    case "toGo": return { t: `Go to ${x.at ? x.at.label : "the next stop"}` }
    // (#44: says what you go back to)
    case "stage": return { t: "Back to the stage", s: x.at ? `${x.at.label} ${x.at.name || ""}`.trim() : "" }
    case "transit":
    case "toStop": return { t: "Back to the transit", s: x.transit && x.transit.name ? `to ${x.transit.name}` : "" }
    default: return { t: "Back to driving" }
  }
})
// The main button takes the real focus as the page opens and as the rally moves on (it comes up after the card's
// data, so v-bng-ui-nav-focus alone misses it): Start, the time card's way on, New rally (#56, #57, #71)
const startBtn = ref(null)
const goBtn = ref(null)
const newBtn = ref(null)
watch(() => !!(s.value && s.value.canRun), ok => { if (ok) nextTick(() => focusButton(startBtn.value)) }, { immediate: true })
watch(() => (c.value && !c.value.none ? `${c.value.id}:${c.value.phase}:${!!c.value.done}` : null), k => {
  if (k && props.kind === "card") nextTick(() => focusButton(c.value && c.value.done ? newBtn.value : goBtn.value))
}, { immediate: true })
// (#34) the stage in progress: what its auto recce is doing
const AUTO_WORDS = { going: "Going to the stage", asking: "Pricing the map data", planning: "Checking the map data",
  downloading: "Downloading the map", matching: "Matching the roads" }
function prepAuto() { return c.value && c.value.prep && c.value.prep.auto }
function prepBar() {
  const a = prepAuto()
  if (!a) return null
  if (a.windows) return Math.round(100 * (a.done || 0) / a.windows)
  if (a.phase === "downloading" && a.area && a.area.total) return Math.round(100 * (a.area.done || 0) / a.area.total)
  return null
}
function prepPct(p) { const b = prepBar(); return b == null ? "Working" : `${b}%` }
function prepDetail(p) {
  if (p.state === "failed") return "Not matched: held out if it has no line"
  if (p.state !== "now") return p.km ? `${p.km} km` : ""
  const a = prepAuto()
  if (!a) return "Starting"
  let t = AUTO_WORDS[a.phase] || "Working"
  if (a.windows) t += ` · window ${Math.min((a.done || 0) + 1, a.windows)} of ${a.windows}`
  else if (a.phase === "downloading" && a.area && a.area.total) t += ` · ${a.area.done || 0} of ${a.area.total}`
  // (1.7.2) the download's time, and a word when its count sits still: the items differ a lot in size
  if (a.phase === "downloading") {
    t += ` · ${mmss(a.waitedS)}`
    if ((a.quietS || 0) >= 15 && a.area && a.area.total && (a.area.done || 0) < a.area.total) t += " · still going, a big piece"
  }
  return t
}
// the stripes: working with no count moving to show for it
function prepLive() { const a = prepAuto(); return !a || (a.phase !== "matching" && a.phase !== "asking") }
// (1.7.2) Stop: no more auto recces. The prep ends as after the last one -- a stage with no line held out -- and the
// rally goes on (main.lua autoRecceStop), so the card stays; with no stage left to drive the rally ended, so its page
function stopPrep() {
  const id = c.value && c.value.id
  action("autoRecceStop", null, null, r => { if (r && r.rallyEnded) emit("view", "rally", id) })
}
function prepStopLabel() {
  const p = c.value && c.value.prep
  const left = p ? p.of - Math.max(1, p.i) + 1 : 0
  return left > 1 ? `Stop all ${left}` : "Stop"
}
// (plan E) a stage's weather (rallyRun.weatherWord: { text, tempC, icon, night }): "overcast · 15 °C", "clear night · −2 °C"
const rowCls = r => ({ next: r.next && r.kind === "stage", svc: r.kind !== "stage", here: r.next && r.kind !== "stage", sr: r.superRally, dim: r.done && r.kind !== "stage" })
// A day's header over its first row of any kind that carries a day (#57: the start carries the first stage's, so
// Day 1 heads the list above Start). Rows with no day (an older rally's start) take none and break no day.
const dayHead = i => {
  const rows = arr(c.value && c.value.rows)
  const r = rows[i]
  if (!r || !r.day) return false
  for (let j = i - 1; j >= 0; j--) if (rows[j].day) return rows[j].day !== r.day
  return true
}
</script>

<style lang="scss" scoped>
/* (room at the bottom so the page scrolls clear of the big button in the corner) */
.er-full { color: #f0f0f0; padding-bottom: 150px; }
/* The main button at the lower right (#56, #57, #71; the mock-up's .cornerbtn): fixed above the prompt bar (56px),
   so a long time card scrolls under it, never takes it away. The game's button made big as Home's is: its margin
   and min-width through the hooks it reads, its own size rules beaten on specificity (.er-full first). */
.er-corner { position: fixed; right: 64px; bottom: 90px; z-index: 5; display: flex; flex-direction: column; align-items: flex-end; gap: 12px;
  .er-warn { margin: 0; font-size: 17px; text-shadow: 0 1px 3px #000; } }
.er-corner-row { flex-direction: row; align-items: flex-end; gap: 20px; }
.er-full .er-huge { --bng-button-margin: 0; --bng-button-min-width: 520px; font-size: 30px; line-height: 36px; font-weight: 800; letter-spacing: 0.04em;
  text-transform: uppercase; padding: 20px 56px; }
.er-full .er-huge-2 { --bng-button-min-width: 420px; }
.er-hb { display: flex; flex-direction: column; align-items: center;
  small { font-size: 17px; line-height: 22px; font-weight: 500; text-transform: none; letter-spacing: 0; opacity: 0.85; margin-top: 2px; } }
.er-sec { margin: 0 0 4px; font-size: 18px; letter-spacing: 0.16em; text-transform: uppercase; color: #f26b1d; font-weight: 700; }
.er-kick { font-size: 17px; letter-spacing: 0.18em; text-transform: uppercase; color: #f26b1d; font-weight: 700; }
.er-fin { width: 900px; max-width: 100%; margin: 40px auto 0; padding: 48px; text-align: center;
  h2 { font-size: 60px; margin: 10px 0 0; text-transform: uppercase; line-height: 1.1; } }
.er-fin-t { font: 700 56px "Overpass Mono", monospace; margin: 18px 0 6px; }
.er-fin-p { font-size: 22px; }
.er-fin .er-fin-res { margin-top: 22px; }
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
.er-pickcar { margin-top: 8px; cursor: pointer; }
.er-box { display: flex; justify-content: space-between; padding: 10px 14px; border: 1px solid #555; border-radius: 0.25rem; background: rgba(255, 255, 255, 0.04); font-size: 18px; }
.er-seg { display: flex; gap: 4px; background: rgba(0, 0, 0, 0.45); border-radius: 0.25rem; padding: 4px;
  span { flex: 1; text-align: center; padding: 8px 14px; border-radius: 3px; font-size: 18px; font-weight: 600; color: #b8bcc6; cursor: pointer; }
  span.on { background: #c75b1e; color: #fff; }
  span:focus { outline: 2px solid #f26b1d; outline-offset: 2px; } }
.er-wrap { flex-wrap: wrap; span { flex: 0 0 auto; } }
.er-foot { margin-top: 24px; }
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
.er-pr { display: grid; grid-template-columns: 70px minmax(0, 1fr) 110px; gap: 12px; align-items: center; padding: 10px 12px; margin-top: 6px; border-radius: 4px; font-size: 18px;
  small { display: block; color: #8a909a; font-size: 14px; }
  &.done { background: rgba(60, 207, 126, 0.08); .er-r { color: #3ccf7e; } }
  &.now { background: rgba(242, 107, 29, 0.14); outline: 2px solid rgba(242, 107, 29, 0.6); }
  &.wait { color: #8a909a; }
  &.failed { background: rgba(255, 211, 107, 0.07); .er-r { color: #ffd36b; } } }
.er-pbar { grid-column: 1 / -1; height: 8px; border-radius: 4px; background: rgba(255, 255, 255, 0.12); overflow: hidden;
  i { display: block; height: 100%; background: #f26b1d; transition: width 0.6s ease; }
  /* (1.7.2) stripes while it works, so a count that sits still never reads as stuck */
  &.live { background: repeating-linear-gradient(-45deg, rgba(242, 107, 29, 0.28) 0 8px, rgba(242, 107, 29, 0.1) 8px 16px);
    background-size: 22.6px 100%; animation: er-prun 1s linear infinite; } }
@keyframes er-prun { to { background-position: 22.6px 0; } }
.er-prstop { margin-top: 14px; }
/* (rally loop) the timed time card: the clock, Due / In / Road, the transit's due banner, the penalties */
.er-clock { font: 700 22px "Overpass Mono", monospace; color: rgb(225, 123, 225); text-shadow: 0 0 10px rgba(225, 123, 225, 0.4); }
.er-t2 .er-tr { grid-template-columns: 96px minmax(0, 1fr) 112px 74px 130px 100px 84px; }
/* (additions B) a road section's target where the due isn't known; the stop card's check-in */
.er-tgt { font-size: 15px; color: #8a909a; white-space: nowrap; }
.er-tr.next .er-tgt { color: #dfe6ff; }
.er-ok { color: #3ccf7e; }
.er-cibox { margin-top: 10px; padding: 6px 16px 4px; border-radius: 8px; background: rgba(255, 255, 255, 0.05); }
.er-cikind { font-size: 15px; letter-spacing: 0.12em; text-transform: uppercase; color: #f26b1d; font-weight: 700; margin: 4px 0 6px;
  span { color: #b8bcc6; letter-spacing: 0.04em; text-transform: none; font-weight: 500; margin-left: 8px; } }
.er-tcrow { display: flex; justify-content: space-between; align-items: baseline; gap: 16px; padding: 9px 0; border-bottom: 1px solid rgba(255, 255, 255, 0.08); font-size: 18px;
  span { color: #b8bcc6; white-space: nowrap; } b { font-family: "Overpass Mono", monospace; font-size: 22px; text-align: right; }
  &:last-child { border-bottom: 0; } }
.er-cinext { margin-top: 14px; font-size: 18px; }
.er-thd { color: #b8bcc6; font-size: 13px; text-transform: uppercase; letter-spacing: 0.08em; border-bottom-color: rgba(255, 255, 255, 0.14); padding-top: 4px; padding-bottom: 4px; }
.er-nm small { display: block; font-size: 14px; font-weight: 600; color: #8a909a; }
.er-dimc { color: #8a909a; }
.er-late { color: #ffd36b; }
.er-tr.next .er-late, .er-tr.next .er-dimc, .er-tr.next .er-nm small { color: #fff; }
.er-tsum { display: flex; gap: 28px; margin-top: 12px; padding: 0 10px; font-size: 16px; color: #b8bcc6;
  b { font-family: "Overpass Mono", monospace; color: #fff; font-weight: 700; } b.er-late { color: #ffd36b; } }
.er-banner { display: flex; flex-wrap: wrap; align-items: baseline; gap: 4px 12px; padding: 12px 16px; border-radius: 6px; background: rgba(42, 109, 244, 0.18);
  box-shadow: inset 4px 0 0 #2a6df4; font-size: 21px; font-weight: 600;
  .er-mono { font-weight: 700; } i { font-style: normal; color: #6f7480; }
  &.late { background: rgba(229, 83, 61, 0.16); box-shadow: inset 4px 0 0 #e5533d; color: #ff8a78; } }
.er-when { display: flex; align-items: center; gap: 14px; margin-top: 18px; padding: 14px 18px; border-radius: 6px; background: rgba(40, 50, 90, 0.45); box-shadow: inset 4px 0 0 #7c8cff; font-size: 21px; font-weight: 600; }
.er-sky { width: 26px; height: 26px; border-radius: 50%; flex: none;
  &.night { box-shadow: inset -8px -3px 0 0 #e8e4c8; transform: rotate(-20deg); }
  &.dusk, &.dawn { background: linear-gradient(180deg, #ffb46b 50%, transparent 50%); }
  &.day { background: #ffd36b; } }
.er-corner .er-nofork { max-width: 620px; text-align: right; line-height: 1.45; }
/* (plan E) a stage's weather beside its name, and the transit banner's line for the next stage */
.er-sn { display: flex; align-items: center; gap: 14px; min-width: 0; }
.er-wx { margin-left: auto; display: inline-flex; align-items: center; gap: 6px; flex: none; font-size: 15px; font-weight: 500; color: #b8bcc6; white-space: nowrap;
  svg { width: 19px; height: 19px; flex: none; }
  &.done { color: #8a909a; } }
.er-tr.next .er-wx { color: #fff; }
.er-bwx { display: flex; align-items: center; gap: 8px; flex-basis: 100%; font-weight: 500; color: #dfe6ff;
  svg { width: 22px; height: 22px; flex: none; } }
.er-row2 { display: flex; justify-content: space-between; padding: 5px 0; font-size: 18px; }
</style>
