<template>
  <!-- Rallies (docs/mockups-rally-files/menu.html, screen 1): one card per thing dropped in. A season is one card
       (its round covers as a mosaic, stages driven, your place in the standings); a rally and a single stage get
       their cover, or a drawn plate. "Add" is one strip at the bottom. Data: menu.lua, M.home (uiState.home). -->
  <section>
    <div class="er-home">
      <div v-for="(s, i) in seasons" :key="'s:' + s.id" v-bng-ui-nav-focus="i === 0 ? 1 : undefined" class="er-card er-hcard er-wide" tabindex="0" bng-nav-item
        @click="emit('season', s.id)" @keydown.enter="emit('season', s.id)">
        <div class="er-mosaic" :style="{ gridTemplateColumns: `repeat(${Math.min(4, arr(s.covers).length) || 1}, 1fr)` }">
          <EarthRallyPic v-for="c in arr(s.covers)" :key="c.round" small :url="c.url || ''" :kind="`ROUND ${c.round}`" :name="shortName(c.name)" />
        </div>
        <div class="er-body">
          <div class="er-kind">Season · {{ s.rallies }} {{ s.rallies === 1 ? "rally" : "rallies" }}</div>
          <div class="er-hname" :title="s.name">{{ s.name }}</div>
          <div class="er-hline">{{ [months(s.dates), `${s.stages} stages`].filter(Boolean).join(" · ") }}</div>
        </div>
        <div class="er-hprog">{{ s.driven }} of {{ s.stages }} stages driven<div class="er-bar"><i :style="{ width: pct(s.driven, s.stages) }"></i></div></div>
        <div class="er-hfoot">
          <BngButton :accent="ACCENTS.main" @click.stop="emit('season', s.id)">Open season</BngButton>
          <div v-if="s.you" class="er-you"><div class="er-v">{{ ord(s.you.pos) }}</div><div class="er-l">in the standings</div></div>
        </div>
      </div>

      <div v-for="(r, i) in rallies" :key="'r:' + r.id" v-bng-ui-nav-focus="(i === 0 && !seasons.length) ? 1 : undefined" class="er-card er-hcard" tabindex="0" bng-nav-item @click="open(r)" @keydown.enter="open(r)">
        <EarthRallyPic class="er-hpic" :url="(r.media && r.media.cover) || ''" :kind="r.kind === 'stage' ? 'STAGE' : 'RALLY'" :name="r.name" :blue="r.kind === 'stage'" />
        <div class="er-body">
          <div class="er-kind" :class="{ blue: r.kind === 'stage' }">{{ r.kind === "stage" ? "Stage" : `Rally · ${r.stages} ${r.stages === 1 ? "stage" : "stages"}` }}</div>
          <div class="er-hname" :title="r.name">{{ r.name }}</div>
          <div class="er-hline">{{ hline(r) }}</div>
        </div>
        <div v-if="r.kind === 'stage'" class="er-hprog">{{ r.best ? `Best ${time(r.best)}` : "Not driven yet" }}</div>
        <div v-else class="er-hprog">{{ r.driven }} of {{ r.stages }} stages driven<div class="er-bar"><i :style="{ width: pct(r.driven, r.stages) }"></i></div></div>
        <div class="er-hfoot"><BngButton :accent="ACCENTS.secondary" @click.stop="open(r)">{{ r.kind === "stage" ? "Open stage" : "Open rally" }}</BngButton></div>
      </div>
    </div>
    <div v-if="!seasons.length && !rallies.length" class="er-muted er-empty">No rallies yet.</div>

    <div class="er-add">
      <div class="er-t">+ Add</div>
      <div class="er-d">
        Drop a map (<b>.kml</b>, <b>.kmz</b>, <b>.gpx</b>) or a rally file (<b>.zip</b> or folder) in the import folder.
        <div class="er-path">{{ st.importFolder }}</div>
        <template v-if="st.lastImport">
          <div class="er-report-h">Last import · {{ st.lastImport.at }}</div>
          <!-- (each line opens its import report: docs/mockups-hand-files/import.html, screen 1) -->
          <div v-for="(l, i) in arr(st.lastImport.lines)" :key="i" class="er-iline" :class="lineClass(l)" :tabindex="l.report ? 0 : -1"
            :bng-nav-item="l.report ? true : undefined" @click="l.report && emit('report', l.file)" @keydown.enter="l.report && emit('report', l.file)">
            <span>{{ l.verdict === "failed" ? "✕" : l.verdict === "problems" || !l.ok ? "!" : "✓" }} {{ l.text }}</span>
            <span v-if="l.report" class="er-go">Report</span>
          </div>
        </template>
      </div>
      <div class="er-btns">
        <BngButton :accent="ACCENTS.secondary" @click="emit('action', 'openFolder')">Open folder</BngButton>
        <BngButton :accent="ACCENTS.outlined" @click="emit('action', 'rescan')">Re-scan</BngButton>
      </div>
    </div>
  </section>
</template>

<script setup>
import { computed } from "vue"
import { BngButton, ACCENTS } from "@/common/components/base"
import { vBngUiNavFocus } from "@/common/directives"   // (the first card takes a controller's focus: EarthRally.vue)
import EarthRallyPic from "./EarthRallyPic.vue"
import { state, arr, len, time, ord, months, days, shortName } from "./store.js"

const emit = defineEmits(["season", "rally", "stage", "action", "report"])
function lineClass(l) {
  if (l.verdict === "failed") return "er-bad"
  if (l.verdict === "problems" || !l.ok) return "er-warn"
  return "er-ok"
}
const st = computed(() => state.value || {})
const seasons = computed(() => arr(st.value.home && st.value.home.seasons))
const rallies = computed(() => arr(st.value.home && st.value.home.rallies))
const pct = (a, b) => (b ? (100 * a) / b : 0) + "%"
function hline(r) {
  if (r.kind === "stage") return len(r.lengthM)
  return [days(r.dates, true), r.place, `${len(r.lengthM)} of stages`].filter(Boolean).join(" · ")
}
function open(r) {
  if (r.kind === "stage") emit("stage", r.id, r.stageId)
  else emit("rally", r.id)
}
</script>

<style lang="scss" scoped>
.er-card { background: rgba(0, 0, 0, 0.6); border-radius: 0.5rem; }
.er-muted { color: var(--er-muted); }
.er-home { display: grid; grid-template-columns: repeat(auto-fill, minmax(400px, 1fr)); gap: 28px; }
.er-hcard { display: flex; flex-direction: column; overflow: hidden; cursor: pointer; min-width: 0; min-height: 560px;
  outline: none;
  &:focus { box-shadow: 0 0 0 3px var(--er-orange); } }   /* (#51: the focus only; the mouse moves it, store.js pointTo) */
.er-wide { grid-column: span 2; }
.er-hpic { height: 300px; flex-shrink: 0; }
.er-mosaic { display: grid; grid-auto-rows: 1fr; gap: 3px; height: 300px; flex-shrink: 0; background: #000; }
.er-body { padding: 20px 26px 0; min-width: 0; }
.er-kind { font-size: 13px; font-weight: 700; letter-spacing: 0.14em; color: var(--er-orange); text-transform: uppercase;
  &.blue { color: #6fb6ff; } }
.er-hname { font-size: 32px; font-weight: 700; line-height: 1.15; margin-top: 4px; white-space: nowrap; overflow: hidden; text-overflow: ellipsis; }
.er-hline { font-size: 18px; color: var(--er-muted); margin-top: 4px; white-space: nowrap; overflow: hidden; text-overflow: ellipsis; }
.er-hprog { padding: 16px 26px 0; font-size: 16px; color: var(--er-muted); }
.er-bar { height: 8px; border-radius: 4px; background: #2a2e38; overflow: hidden; margin-top: 8px; i { display: block; height: 100%; background: var(--er-blue); } }
.er-hfoot { margin-top: auto; padding: 20px 26px 22px; display: flex; align-items: center; gap: 16px; }
.er-you { margin-left: auto; text-align: right;
  .er-v { font-family: "Overpass Mono", monospace; font-size: 26px; font-weight: 700; }
  .er-l { font-size: 13px; letter-spacing: 0.08em; text-transform: uppercase; color: var(--er-muted); } }
.er-empty { margin-top: 8px; font-size: 18px; }
.er-add { margin-top: 28px; display: flex; align-items: flex-start; gap: 22px; padding: 16px 26px; border: 2px dashed #4a505c; border-radius: 0.5rem; background: rgba(0, 0, 0, 0.3);
  .er-t { font-size: 20px; font-weight: 700; white-space: nowrap; }
  .er-d { color: var(--er-muted); font-size: 16px; line-height: 1.45; min-width: 0; }
  .er-btns { margin-left: auto; display: flex; gap: 12px; flex-shrink: 0; }
}
.er-path { font-family: "Overpass Mono", monospace; font-size: 13px; margin: 6px 0; word-break: break-all; }
.er-report-h { font-size: 13px; text-transform: uppercase; letter-spacing: 0.08em; margin-top: 6px; }
.er-ok { color: #6fd39a; }
.er-warn { color: #ffd36b; }
.er-bad { color: #ff7a66; }
.er-iline { display: flex; align-items: baseline; gap: 10px; padding: 3px 6px; border-radius: 3px; outline: none;
  &[tabindex="0"] { cursor: pointer; }
  &:focus { box-shadow: 0 0 0 3px var(--er-orange); } }
.er-go { margin-left: auto; font-size: 14px; color: #ddd; border: 1px solid #6f7480; border-radius: 4px; padding: 1px 10px; flex-shrink: 0; }
</style>
