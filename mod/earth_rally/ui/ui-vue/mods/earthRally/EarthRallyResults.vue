<template>
  <!-- A rally's Results tab (docs/mockups-rally-files/menu.html, screen 3): until every stage has a time, what is
       left to drive beside the real top 10; then your total against them. Data: menu.lua, addRallyFiles
       (uiRally's `results`). -->
  <div class="er-res-wrap">
    <div v-if="!r.complete" class="er-card er-todo">
      <div class="er-head">Drive all {{ r.stages }} stages to get a rally result</div>
      <div class="er-bar"><i :style="{ width: (r.stages ? (100 * r.driven) / r.stages : 0) + '%' }"></i></div>
      <div class="er-muted er-of"><span class="er-mono er-w">{{ r.driven }}</span> of {{ r.stages }} driven</div>
      <div class="er-chips">
        <span v-for="(c, i) in arr(r.chips)" :key="i" class="er-chip" :class="{ done: c.done }">{{ c.done ? "✓ " : "" }}{{ c.name }}</span>
      </div>
    </div>
    <div v-else class="er-card er-todo">
      <h3>Your rally</h3>
      <div class="er-big">{{ ord(r.you && r.you.pos) }}<small>of {{ r.you && r.you.of }}</small></div>
      <div class="er-total">{{ longTime(r.totalS) }}</div>
      <div v-if="r.you && r.you.gapS > 0" class="er-muted er-of">{{ gap(r.you.gapS) }} to the winner</div>
      <div v-else-if="r.you" class="er-muted er-of">Ahead of the winner</div>
      <div v-if="r.points !== undefined && r.points !== null" class="er-pts"><b>+{{ r.points }} points</b> <span class="er-muted">in the season</span></div>
      <div class="er-foot-note">Your best on each stage, once for every pass run.</div>
    </div>

    <div class="er-card er-table">
      <div :class="{ 'er-ghosted': !r.complete }">
        <div class="er-trow er-hdr"><span>Pos</span><span>Driver</span><span>Class</span><span class="er-r">Total</span><span class="er-r">Gap</span></div>
        <template v-for="(row, i) in arr(r.rows)" :key="i">
          <div v-if="row.skipped" class="er-trow er-gap"><span>⋮</span></div>
          <div class="er-trow" :class="{ me: row.you }">
            <span class="er-pos">{{ row.pos }}</span><span class="er-clip">{{ row.name }}</span><span class="er-cls">{{ row.you ? "" : row.class }}</span>
            <span class="er-t">{{ longTime(row.timeS) }}</span><span class="er-g">{{ gap(row.gapS) }}</span>
          </div>
        </template>
        <div v-if="!arr(r.rows).length" class="er-muted er-none">No crew in the results ran every stage.</div>
      </div>
      <div v-if="!r.complete" class="er-over"><div class="er-msg">The real top {{ Math.min(arr(r.rows).length, 10) || 10 }} is waiting<div>Your total goes in here once every stage has a time.</div></div></div>
    </div>
  </div>
</template>

<script setup>
import { arr, ord, gap, longTime } from "./store.js"

defineProps({ r: { type: Object, required: true } })   // the rally's results
</script>

<style lang="scss" scoped>
.er-card { background: rgba(0, 0, 0, 0.6); border-radius: 0.5rem; }
.er-muted { color: var(--er-muted); }
.er-mono { font-family: "Overpass Mono", monospace; }
.er-clip { overflow: hidden; white-space: nowrap; text-overflow: ellipsis; }
.er-res-wrap { display: grid; grid-template-columns: 440px minmax(0, 1fr); gap: 28px; align-items: start; }
.er-todo { padding: 30px 32px;
  h3 { margin: 0 0 10px; font-size: 14px; letter-spacing: 0.1em; text-transform: uppercase; color: var(--er-muted); font-weight: 600; } }
.er-head { font-size: 28px; font-weight: 700; line-height: 1.25; }
.er-bar { height: 12px; border-radius: 6px; margin: 22px 0 10px; background: #2a2e38; overflow: hidden; i { display: block; height: 100%; background: var(--er-blue); } }
.er-of { font-size: 18px; .er-w { color: #fff; } }
.er-chips { display: flex; flex-wrap: wrap; gap: 10px; margin-top: 22px; }
.er-chip { font-size: 16px; padding: 5px 12px; border-radius: 999px; background: rgba(255, 255, 255, 0.07); color: var(--er-muted);
  &.done { background: rgba(40, 140, 80, 0.4); color: #d9ffe6; } }
.er-big { font: 700 52px "Overpass Mono", monospace; line-height: 1.05;
  small { font-size: 22px; color: var(--er-muted); margin-left: 6px; font-weight: 600; } }
.er-total { font: 700 30px "Overpass Mono", monospace; margin-top: 14px; }
.er-pts { margin-top: 22px; font-size: 20px; b { color: var(--er-orange); } }
.er-foot-note { margin-top: 14px; font-size: 15px; color: var(--er-muted); }
.er-table { position: relative; padding: 6px 0; }
.er-ghosted { opacity: 0.4; filter: saturate(0.4); }
.er-over { position: absolute; inset: 0; display: flex; align-items: center; justify-content: center; }
.er-msg { background: rgba(10, 12, 16, 0.92); border: 1px solid #3a3f48; border-radius: 0.5rem; padding: 22px 30px; font-size: 22px; font-weight: 600; text-align: center;
  div { font-size: 16px; font-weight: 400; color: var(--er-muted); margin-top: 6px; } }
.er-none { padding: 16px 26px; }
.er-trow { display: grid; grid-template-columns: 76px minmax(0, 1fr) 110px 170px 140px; align-items: center; height: 48px; padding: 0 26px; font-size: 19px; border-left: 4px solid transparent;
  & + .er-trow { border-top: 1px solid rgba(255, 255, 255, 0.06); }
  &.er-hdr { height: 38px; font-size: 13px; letter-spacing: 0.08em; text-transform: uppercase; color: var(--er-muted); }
  &.me { background: rgba(199, 91, 30, 0.26); border-left-color: var(--er-orange); font-weight: 700; .er-pos { color: #fff; } }
  &.er-gap { height: 26px; color: #6f7480; font-size: 18px; line-height: 1; }
  .er-r { text-align: right; }
  .er-pos { font-family: "Overpass Mono", monospace; font-weight: 700; color: var(--er-muted); }
  .er-cls { font-size: 14px; font-weight: 600; color: var(--er-muted); }
  .er-t { font-family: "Overpass Mono", monospace; font-weight: 600; text-align: right; }
  .er-g { font-family: "Overpass Mono", monospace; text-align: right; color: var(--er-muted); font-size: 17px; }
}
</style>
