<template>
  <!-- Earth Rally's HUD (docs/mockups-1.2.0/hud.html): one full-screen, click-through app in the stage layout
       (settings/ui_apps/.../earthRallyStage), drawing what the stream 'earthRally' says is up (Lua:
       earthRally/hudFrame.lua, its `show` table). Placed by hand at the mock-up's places for 1920x1080. The game's
       own rally apps (countdown, stage time, progress bar) sit beside it in the same layout. -->
  <div class="er-hud" v-if="f">
    <!-- pacenote cards dimmed while off route (the stock app's place: top 17.5 %, 75 % wide, 20 % high) -->
    <div v-if="show.dimNotes" class="er-dim-notes"></div>
    <!-- the game dimmed behind the results card -->
    <div v-if="show.results" class="er-dim-all"></div>

    <!-- 1 driving to the stage: the stock dashboard's look, in the countdown's place -->
    <div v-if="show.next" class="er-panel er-next">
      <div class="er-next-clock">
        <div class="er-label">Rally clock</div>
        <div class="er-pink">{{ f.clockText }}</div>
      </div>
      <div class="er-next-what">
        <span class="er-muted">Next</span> SS{{ stage.ss }} {{ stage.name }}
        <span class="er-sub">· {{ fmt.len(stage.lengthM, units) }}</span>
      </div>
      <div class="er-next-to" v-if="f.control === 'atc'">
        <span class="er-badge er-tc">ATC</span>
        <span class="er-big-dist">{{ fmt.dist(f.toControlM, units) }}</span>
        <span class="er-next-text">Stop at the time control (red clock board).<br>You get your start time there.</span>
      </div>
      <div class="er-next-to" v-else>
        <span class="er-next-text">Getting ready: the world loading at the stage{{ f.preview ? " (preview)" : "" }}...</span>
      </div>
    </div>

    <!-- 2 the timecard line under the stock countdown -->
    <div v-if="show.timecard" class="er-panel er-timecard">
      <div v-if="f.atcTime"><div class="er-label">Checked in</div><div class="er-mono">{{ fmt.clock(f.atcTime) }}</div></div>
      <div v-else-if="f.missedAtc"><div class="er-label">Time control</div><div class="er-mono er-warn">missed +60 s</div></div>
      <div v-else><div class="er-label">Start</div><div class="er-mono">on the line</div></div>
      <div><div class="er-label">Your start</div><div class="er-mono er-pink">{{ f.startAt ? fmt.clock(f.startAt) : "when you stop" }}</div></div>
      <div v-if="f.state === 'toStart'" class="er-timecard-hint">On the line, stopped: <span class="er-kbd">Interact (Shift+E)</span> skips the wait</div>
    </div>

    <!-- 3 the big numeral for the last seconds, GO, the jump start -->
    <div v-if="show.bigCount" class="er-bigcount">{{ f.countdown }}</div>
    <div v-else-if="show.go" class="er-bigcount er-go">GO</div>
    <div v-if="show.jump" class="er-jump">JUMP START +10 s<small>You moved before GO. The clock runs from your start time.</small></div>

    <!-- 4 km done beside the stock progress bar; off route in the bar's place -->
    <div v-if="show.km" class="er-km">{{ fmt.lenValue(f.doneM, units) }} <small>/ {{ fmt.len(f.totalM, units) }}</small></div>
    <div v-if="show.offRoute" class="er-offroute">
      <div class="er-arrow">
        <svg width="44" height="44" viewBox="0 0 44 44" :style="{ transform: `rotate(${f.backBearing || 0}deg)` }">
          <path d="M22 4 L36 24 L27 24 L27 40 L17 40 L17 24 L8 24 Z" fill="#ffb000" />
        </svg>
      </div>
      <span class="er-off-w">OFF ROUTE</span>
      <span class="er-off-d">{{ fmt.dist(f.offM, units) }}</span>
      <span class="er-off-s">· {{ wayBack }}</span>
    </div>

    <!-- 5 the flying finish, a few seconds -->
    <div v-if="show.finish && fin" class="er-finish">
      <div class="er-finish-l">SS{{ stage.ss }} {{ stage.name }} · flying finish</div>
      <div class="er-finish-t">{{ fmt.time(fin.time) }}</div>
      <div v-if="fin.newBest" class="er-delta er-best">{{ fin.first ? "FIRST TIME" : fmt.delta(fin.delta) + " · NEW BEST" }}</div>
      <div v-else class="er-delta er-slower">{{ fmt.delta(fin.delta) }}</div>
      <div v-if="fin.penalty > 0" class="er-finish-pen">includes +{{ Math.round(fin.penalty) }} s {{ penWords }}</div>
    </div>

    <div v-if="f.preview && f.previewLabel" class="er-preview">HUD preview: {{ f.previewLabel }}</div>
  </div>
</template>

<script setup>
import { ref, computed } from "vue"
import { useStreams } from "@/services/events"
import * as fmt from "./format.js"

const f = ref(null)
useStreams(["earthRally"], streams => {
  if (streams.earthRally) f.value = streams.earthRally
})

// (an empty Lua table can arrive as [] or {})
const show = computed(() => (f.value && f.value.show && !Array.isArray(f.value.show) ? f.value.show : {}))
const stage = computed(() => (f.value && f.value.stage) || {})
const units = computed(() => (f.value && f.value.units) || "km")
const fin = computed(() => f.value && f.value.finish)

const wayBack = computed(() => {
  const b = f.value && f.value.backBearing
  if (b === null || b === undefined) return "back to the route"
  const a = Math.abs(b)
  if (a > 120) return "turn back"
  if (a < 30) return "the route is ahead"
  return b < 0 ? "the route is to your left" : "the route is to your right"
})

const penWords = computed(() => {
  const p = (fin.value && fin.value.penalties) || {}
  const w = []
  if (p.jumpStart) w.push("jump start")
  if (p.late) w.push("late")
  if (p.resets) w.push(p.resetCount === 1 ? "1 reset" : `${p.resetCount} resets`)
  if (p.missedAtc) w.push("missed time control")
  return w.join(", ")
})
</script>

<style lang="scss" scoped>
.er-hud {
  --er-theme: #1f8fff;
  --er-dash: rgba(66, 70, 81, 0.8);
  --er-pink: rgb(225, 123, 225);
  --er-tc: rgb(43, 136, 194);
  --er-go: rgb(0, 255, 0);
  --er-amber: #ffb000;
  --er-muted: #b8bcc6;
  position: absolute;
  inset: 0;
  pointer-events: none;
  color: #fff;
  font-family: "Noto Sans", sans-serif;
  font-size: 16px;
  overflow: hidden;
}
.er-panel { position: absolute; background: var(--er-dash); border-radius: 0.5rem; }
.er-label { font-size: 12px; text-transform: uppercase; letter-spacing: 0.06em; opacity: 0.85; }
.er-muted { color: var(--er-muted); font-weight: 600; }
.er-pink { color: var(--er-pink); font-family: "Overpass Mono", monospace; font-weight: 700; }
.er-mono { font-family: "Overpass Mono", monospace; font-weight: 700; font-size: 24px; }
.er-warn { color: var(--er-amber); }
.er-badge { display: inline-flex; align-items: center; border-radius: 10px; font-weight: 700; padding: 2px 12px; font-size: 26px; }
.er-tc { background: var(--er-tc); box-shadow: 0 0 10px 0 rgba(43, 136, 194, 0.7); }
.er-kbd { font-family: "Overpass Mono", monospace; font-weight: 700; padding: 1px 8px; border-radius: 4px; background: #fff; color: #111; }

.er-dim-notes { position: absolute; left: 12.5%; width: 75%; top: 17.5%; height: 20%; background: rgba(0, 0, 0, 0.55); border-radius: 0.5rem; }
.er-dim-all { position: absolute; inset: 0; background: rgba(8, 10, 14, 0.55); }

.er-next {
  left: 50%; transform: translateX(-50%); top: 82px; width: 750px; padding: 14px 20px 16px;
  display: grid; grid-template-columns: 170px 1fr; gap: 6px 22px;
  .er-next-clock {
    grid-row: span 2; display: flex; flex-direction: column; align-items: center; justify-content: center;
    border-right: 1px solid rgba(255, 255, 255, 0.15); padding-right: 18px;
    .er-pink { font-size: 32px; text-shadow: 0 0 10px rgba(225, 123, 225, 0.5); }
  }
  .er-next-what { font-size: 30px; font-weight: 700; line-height: 1.2; }
  .er-sub { font-size: 22px; font-weight: 500; color: var(--er-muted); }
  .er-next-to { display: flex; align-items: center; gap: 16px; }
  .er-big-dist { font-family: "Overpass Mono", monospace; font-size: 40px; font-weight: 700; white-space: nowrap; }
  .er-next-text { font-size: 18px; line-height: 1.3; color: #e8e8e8; }
}

.er-timecard {
  left: 50%; transform: translateX(-50%); top: 318px; width: 450px; padding: 10px 16px;
  display: grid; grid-template-columns: 1fr 1fr; gap: 4px;
  .er-timecard-hint { grid-column: span 2; font-size: 15px; color: #ddd; padding-top: 4px; }
}

.er-bigcount {
  position: absolute; left: 0; right: 0; top: 380px; text-align: center;
  font: 800 220px/1 "Noto Sans", sans-serif;
  text-shadow: 0 0 30px rgba(0, 0, 0, 0.6), 0 0 12px rgba(255, 255, 255, 0.5);
  &.er-go { color: var(--er-go); text-shadow: 0 0 30px rgba(0, 255, 0, 0.6); }
}
.er-jump {
  position: absolute; left: 50%; transform: translateX(-50%); top: 640px; width: 600px; padding: 14px; text-align: center;
  background: rgba(160, 0, 0, 0.88); border: 2px solid #ff6666; border-radius: 0.5rem;
  font-size: 40px; font-weight: 800; letter-spacing: 0.04em; box-shadow: 0 0 24px rgba(255, 0, 0, 0.6);
  small { display: block; font-size: 20px; font-weight: 500; letter-spacing: 0; opacity: 0.9; }
}

/* beside the stock progress bar (our layout: left 288, top 64, 780 wide) */
.er-km {
  position: absolute; left: 1068px; top: 64px; height: 68px; padding: 0 16px; background: rgba(0, 0, 0, 0.8);
  display: flex; align-items: center; gap: 8px; font: 700 28px "Overpass Mono", monospace;
  border-left: 1px solid rgba(255, 255, 255, 0.1);
  small { font-size: 17px; color: var(--er-muted); font-weight: 600; }
}
.er-offroute {
  position: absolute; left: 288px; top: 64px; width: 780px; height: 96px; background: rgba(255, 176, 0, 0.95); color: #111;
  display: flex; align-items: center; gap: 22px; padding: 0 26px; box-shadow: 0 0 30px rgba(255, 176, 0, 0.6);
  .er-arrow { width: 70px; height: 70px; border-radius: 50%; background: #111; display: flex; align-items: center; justify-content: center; }
  .er-off-w { font-size: 40px; font-weight: 800; letter-spacing: 0.04em; }
  .er-off-d { font: 700 40px "Overpass Mono", monospace; }
  .er-off-s { font-size: 26px; font-weight: 600; }
}

.er-finish {
  position: absolute; left: 50%; transform: translateX(-50%); top: 210px; width: 800px; padding: 22px 30px 26px;
  text-align: center; background: rgba(0, 0, 0, 0.72); border-radius: 0.5rem; border-top: 6px solid var(--er-theme);
  .er-finish-l { font-size: 20px; letter-spacing: 0.12em; text-transform: uppercase; color: var(--er-muted); }
  .er-finish-t { font: 700 120px/1.05 "Overpass Mono", monospace; }
  .er-finish-pen { margin-top: 12px; font-size: 20px; color: #ffd36b; }
}
.er-delta { display: inline-block; margin-top: 8px; font-size: 34px; font-weight: 800; padding: 4px 18px; border-radius: 8px; }
.er-best { background: var(--er-go); color: #002a00; }
.er-slower { background: rgba(255, 176, 0, 0.95); color: #1a1000; }

.er-preview {
  position: absolute; left: 50%; transform: translateX(-50%); bottom: 90px; padding: 6px 14px; border-radius: 4px;
  background: rgba(255, 250, 150, 0.95); color: #222; font-weight: 600;
}
</style>
