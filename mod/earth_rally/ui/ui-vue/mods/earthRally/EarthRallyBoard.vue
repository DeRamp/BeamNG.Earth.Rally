<template>
  <!-- A stage's leaderboard (docs/mockups-rally-files/menu.html, screen 4): a toggle between its passes, the real
       top 10 and your row, or one line saying why you are not placed: no time yet, the map's line is not the stage
       as run, or the pass was cancelled. Data: menu.lua, addStageRallyFiles (uiStage's `board`). -->
  <div class="er-card er-lb">
    <div class="er-top">
      <h3>Leaderboard</h3>
      <div v-if="passes.length > 1" class="er-tabs">
        <span v-for="p in passes" :key="p.ss" tabindex="0" :class="{ on: p.ss === b.pass, cx: p.cancelled }"
          @click="emit('pass', p.ss)" @keydown.enter="emit('pass', p.ss)">{{ p.ss }}</span>
      </div>
      <div v-else class="er-one er-mono">{{ b.pass }}</div>
    </div>

    <div v-if="b.reason === 'cancelled'" class="er-empty">
      <b>{{ b.pass }} was cancelled</b>No times on the day.<template v-if="others.length"> See {{ others.join(", ") }}.</template>
    </div>
    <div v-else-if="!b.field" class="er-empty"><b>No times on {{ b.pass }}</b>The results have none for this pass.</div>
    <template v-else>
      <div v-if="b.you" class="er-you-line">
        <span class="er-p">{{ ord(b.you.pos) }}<small>of {{ b.you.of }}</small></span>
        <span>{{ b.you.gapS > 0 ? `${gap(b.you.gapS)} to the fastest` : b.you.leadS ? `fastest by ${gap(b.you.leadS).slice(1)}` : "fastest" }}</span>
      </div>
      <div v-else-if="b.reason === 'noTime'" class="er-you-line"><span>{{ b.field }} times on {{ b.pass }}. Drive it to see where you'd place.</span></div>
      <div v-else-if="b.reason === 'lineMismatch'" class="er-note">Not placed: your line is {{ km(b.lineKm) }}, the stage was {{ km(b.km) }}.</div>

      <div class="er-trow er-hdr"><span>Pos</span><span>Driver</span><span>Class</span><span class="er-r">Time</span><span class="er-r">Gap</span></div>
      <template v-for="(r, i) in arr(b.rows)" :key="i">
        <div v-if="r.skipped" class="er-trow er-gap"><span>⋮</span></div>
        <div class="er-trow" :class="{ me: r.you }">
          <span class="er-pos">{{ r.pos }}</span><span class="er-clip">{{ r.name }}</span><span class="er-cls">{{ r.you ? "" : r.class }}</span>
          <span class="er-t">{{ time(r.timeS) }}</span><span class="er-g">{{ gap(r.gapS) }}</span>
        </div>
      </template>
      <template v-if="!b.you">
        <div v-if="b.field > arr(b.rows).length" class="er-trow er-gap"><span>⋮</span></div>
        <div class="er-trow me er-plain">
          <span class="er-pos">–</span><span>You</span><span></span>
          <span v-if="b.reason === 'lineMismatch' && best" class="er-t">{{ time(best) }}</span><span v-else class="er-t er-dim">no time</span>
          <span class="er-g">{{ b.reason === "lineMismatch" && best ? "not placed" : "" }}</span>
        </div>
      </template>
    </template>
  </div>
</template>

<script setup>
import { computed } from "vue"
import { arr, time, gap, ord, units, MILE_M } from "./store.js"

const props = defineProps({
  b: { type: Object, required: true },   // the stage's board
  best: { type: Number, default: null }, // your best on the stage
})
const emit = defineEmits(["pass"])
const passes = computed(() => arr(props.b.passes))
const others = computed(() => passes.value.filter(p => !p.cancelled && p.ss !== props.b.pass).map(p => p.ss))
const km = k => (k === null || k === undefined ? "–" : units() === "mi" ? `${(k * 1000 / MILE_M).toFixed(1)} mi` : `${Number(k).toFixed(1)} km`)
</script>

<style lang="scss" scoped>
.er-card { background: rgba(0, 0, 0, 0.6); border-radius: 0.5rem; }
.er-mono { font-family: "Overpass Mono", monospace; }
.er-dim { color: var(--er-dim); }
.er-clip { overflow: hidden; white-space: nowrap; text-overflow: ellipsis; }
.er-lb { padding: 20px 0 10px; }
.er-top { display: flex; align-items: center; gap: 16px; padding: 0 26px 12px;
  h3 { margin: 0; font-size: 20px; } }
.er-one { margin-left: auto; color: var(--er-muted); font-size: 16px; }
.er-tabs { margin-left: auto; display: flex; gap: 4px; background: rgba(0, 0, 0, 0.45); border-radius: 0.25rem; padding: 4px;
  span { padding: 5px 16px; border-radius: 3px; font-size: 16px; font-weight: 600; font-family: "Overpass Mono", monospace; color: var(--er-muted); cursor: pointer; }
  span.on { background: var(--er-orange-500); color: #fff; }
  span.cx { text-decoration: line-through; } }
.er-you-line { display: flex; align-items: baseline; gap: 14px; padding: 0 26px 12px; font-size: 18px; color: var(--er-muted);
  .er-p { font: 700 34px "Overpass Mono", monospace; color: #fff;
    small { font-size: 18px; color: var(--er-muted); font-weight: 400; margin-left: 6px; } } }
.er-note { margin: 0 26px 10px; padding: 10px 14px; border-radius: 0.25rem; background: rgba(255, 211, 107, 0.12); color: #ffd36b; font-size: 16px; }
.er-empty { padding: 60px 26px 70px; text-align: center; font-size: 20px; color: var(--er-muted);
  b { display: block; color: #fff; font-size: 24px; margin-bottom: 6px; } }
.er-trow { display: grid; grid-template-columns: 54px minmax(0, 1fr) 80px 110px 100px; align-items: center; height: 36px; padding: 0 26px; font-size: 17px; border-left: 4px solid transparent;
  & + .er-trow { border-top: 1px solid rgba(255, 255, 255, 0.06); }
  &.er-hdr { height: 30px; font-size: 12px; letter-spacing: 0.08em; text-transform: uppercase; color: var(--er-muted); }
  &.me { background: rgba(199, 91, 30, 0.26); border-left-color: var(--er-orange); font-weight: 700; .er-pos { color: #fff; } }
  &.me.er-plain { font-weight: 400; }
  &.er-gap { height: 20px; color: #6f7480; font-size: 16px; line-height: 1; }
  .er-r { text-align: right; }
  .er-pos { font-family: "Overpass Mono", monospace; font-weight: 700; color: var(--er-muted); }
  .er-cls { font-size: 14px; font-weight: 600; color: var(--er-muted); }
  .er-t { font-family: "Overpass Mono", monospace; font-weight: 600; text-align: right; }
  .er-g { font-family: "Overpass Mono", monospace; text-align: right; color: var(--er-muted); font-size: 15px; }
}
</style>
