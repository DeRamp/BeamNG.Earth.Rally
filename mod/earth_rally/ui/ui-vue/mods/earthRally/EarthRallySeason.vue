<template>
  <!-- A season (docs/mockups-rally-files/menu.html, screen 2): its rounds as cover cards, your place on a round you
       have finished, and a Standings tab (top 10 and you, points per round). Data: menu.lua, M.season (uiSeason). -->
  <section>
    <div class="er-shead">
      <div class="er-shead-n">
        <div class="er-name">{{ s.name }}</div>
        <div class="er-sub">{{ [`${s.rallies} ${s.rallies === 1 ? "rally" : "rallies"}`, months(s.dates)].filter(Boolean).join(" · ") }}</div>
      </div>
      <div class="er-stat" style="margin-left: 40px"><div class="er-v">{{ s.finished }} / {{ s.rallies }}</div><div class="er-l">rallies finished</div></div>
      <div v-if="you" class="er-stat"><div class="er-v">{{ ord(you.pos) }}</div><div class="er-l">standings</div></div>
      <div class="er-tabs">
        <span v-for="t in TABS" :key="t.id" tabindex="0" bng-nav-item :class="{ on: tab === t.id }" @click="tab = t.id" @keydown.enter="tab = t.id">{{ t.label }}</span>
      </div>
    </div>

    <div v-if="tab === 'rounds'" class="er-rounds">
      <div v-for="(r, i) in arr(s.rounds)" :key="r.id" v-bng-ui-nav-focus="i === 0 ? 1 : undefined" class="er-card er-rcard" :class="{ done: r.stages && r.driven === r.stages }"
        tabindex="0" bng-nav-item @click="emit('rally', r.id)" @keydown.enter="emit('rally', r.id)">
        <div class="er-rpic">
          <EarthRallyPic class="er-rpic-in" :url="(r.media && r.media.cover) || ''" :kind="`ROUND ${r.round}`" :name="shortName(r.name)" />
          <span class="er-rn">R{{ r.round }}</span>
          <span v-if="r.complete && r.you" class="er-res">{{ ord(r.you.pos) }}</span>
          <span v-else-if="r.notRanked" class="er-res er-nr">Not ranked</span>
        </div>
        <div class="er-body">
          <div class="er-nm" :title="r.name">{{ r.name }}</div>
          <div class="er-dt">{{ [days(r.dates), r.place].filter(Boolean).join(" · ") || " " }}</div>
          <div class="er-pr"><span><span class="er-mono er-w">{{ r.driven }}</span> / {{ r.stages }} stages</span><div class="er-bar"><i :style="{ width: pct(r.driven, r.stages) }"></i></div></div>
        </div>
      </div>
    </div>

    <div v-else class="er-stand-wrap">
      <div class="er-card er-table">
        <div class="er-trow er-hdr" :style="cols"><span>Pos</span><span>Driver</span><span v-for="r in rounds" :key="r.round" class="er-c" :class="{ 'er-cnr': r.notRanked }">R{{ r.round }}</span><span class="er-r">Points</span></div>
        <template v-for="(row, i) in rows" :key="i">
          <div class="er-trow" :class="{ me: row.you }" :style="cols">
            <span class="er-pos">{{ row.pos }}</span><span class="er-clip">{{ row.name }}</span>
            <span v-for="(p, k) in arr(row.perRound)" :key="k" class="er-rp" :class="{ w: p.pos === 1 && !p.partial, x: !p.pos }">{{ cell(p) }}</span>
            <span class="er-pts">{{ row.points }}</span>
          </div>
        </template>
        <template v-if="you && !st.youShown">
          <div class="er-trow er-gap" :style="cols"><span>⋮</span></div>
          <div class="er-trow me" :style="cols">
            <span class="er-pos">{{ you.pos }}</span><span>{{ you.name }}</span>
            <span v-for="(p, k) in arr(you.perRound)" :key="k" class="er-rp" :class="{ w: p.pos === 1 && !p.partial, x: !p.pos }">{{ cell(p) }}</span>
            <span class="er-pts">{{ you.points }}</span>
          </div>
        </template>
        <div v-if="!rows.length" class="er-muted er-none">No results in this season's files yet.</div>
      </div>
      <div>
        <div class="er-card er-side">
          <h3>You</h3>
          <template v-if="you">
            <div class="er-big">{{ ord(you.pos) }}<small>{{ you.points }} pts</small></div>
            <div v-if="placed.length" class="er-foot-note">{{ placed.join(" · ") }}</div>
          </template>
          <div v-else class="er-foot-note">No rally result yet: drive every stage of a rally.</div>
          <div v-if="s.next" class="er-foot-note">Finish {{ s.next }} to score{{ you ? " again" : "" }}.</div>
        </div>
        <div v-if="pointsLine" class="er-foot-note er-pad">{{ pointsLine }}</div>
        <div v-if="nrLine" class="er-foot-note er-pad">{{ nrLine }}</div>
        <div v-if="anyPartial" class="er-foot-note er-pad">* your place over the stages that match; crews' points are from the full rally.</div>
      </div>
    </div>
  </section>
</template>

<script setup>
import { ref, computed, watch } from "vue"
import EarthRallyPic from "./EarthRallyPic.vue"
import { vBngUiNavFocus } from "@/common/directives"   // (the first round takes a controller's focus: EarthRally.vue)
import { arr, ord, days, months, shortName, lastPlace } from "./store.js"

const props = defineProps({ s: { type: Object, required: true } })   // menu.season
const emit = defineEmits(["rally"])
const TABS = [{ id: "rounds", label: "Rallies" }, { id: "standings", label: "Standings" }]
// (kept per season across the menu closing, as the rest of where the menu was left: store.js lastPlace)
const tab = ref((lastPlace.seasonTab && lastPlace.seasonTab.id === props.s.id && lastPlace.seasonTab.tab) || "rounds")
watch(tab, t => { lastPlace.seasonTab = { id: props.s.id, tab: t } })

const st = computed(() => props.s.standings || {})
const you = computed(() => st.value.you || null)
const rows = computed(() => arr(st.value.rows))
const rounds = computed(() => arr(st.value.rounds))
const cols = computed(() => ({ gridTemplateColumns: `70px minmax(0, 1fr) repeat(${rounds.value.length}, 52px) 90px` }))
// a round's cell: its points ("25*" for yours from a ranking over part of the rally), "–" when not placed, "NR" for
// yours in a round not ranked
const cell = p => (p.pos ? (p.partial ? `${p.points}*` : p.points) : p.notRanked ? "NR" : "–")
const anyPartial = computed(() => !!(you.value && arr(you.value.perRound).some(p => p.pos && p.partial)))
// "R4 is not ranked: too few of its stages match the official distance, so you can't score there."
const nrLine = computed(() => {
  const nr = rounds.value.filter(r => r.notRanked).map(r => `R${r.round}`)
  if (!nr.length) return ""
  const one = nr.length === 1
  return `${nr.join(", ")} ${one ? "is" : "are"} not ranked: too few of ${one ? "its" : "their"} stages match the official distance, so you can't score there.`
})
const pct = (a, b) => (b ? (100 * a) / b : 0) + "%"
// "SnoDrift 11th · 100 Acre Wood 9th": the rounds you were placed in
const placed = computed(() => arr(props.s.rounds).filter(r => r.complete && r.you).map(r => `${shortName(r.name, true)} ${ord(r.you.pos)}`))
// "Points for the top 15 in each rally: 25, 20, 16, 13, 11 … 1."
const pointsLine = computed(() => {
  const p = arr(st.value.points)
  if (!p.length) return ""
  const shown = p.length > 6 ? `${p.slice(0, 5).join(", ")} … ${p[p.length - 1]}` : p.join(", ")
  const best = st.value.best ? ` Your best ${st.value.best} rallies count.` : ""
  return `Points for the top ${p.length} in each rally: ${shown}.${best}`
})
</script>

<style lang="scss" scoped>
.er-card { background: rgba(0, 0, 0, 0.6); border-radius: 0.5rem; }
.er-muted { color: var(--er-muted); }
.er-mono { font-family: "Overpass Mono", monospace; }
.er-clip { overflow: hidden; white-space: nowrap; text-overflow: ellipsis; }
.er-shead { display: flex; align-items: flex-end; gap: 28px; margin-bottom: 20px; }
.er-shead-n { min-width: 0; }
.er-name { font-size: 40px; font-weight: 700; line-height: 1.1; }
.er-sub { font-size: 18px; color: var(--er-muted); margin-top: 4px; }
.er-stat { text-align: right; flex-shrink: 0;
  .er-v { font-family: "Overpass Mono", monospace; font-size: 30px; font-weight: 700; }
  .er-l { font-size: 13px; letter-spacing: 0.08em; text-transform: uppercase; color: var(--er-muted); } }
.er-tabs { margin-left: auto; margin-bottom: 4px; display: flex; gap: 4px; background: rgba(0, 0, 0, 0.45); border-radius: 0.25rem; padding: 4px; flex-shrink: 0;
  span { padding: 8px 22px; border-radius: 3px; font-size: 18px; font-weight: 600; color: var(--er-muted); cursor: pointer; }
  span.on { background: var(--er-orange-500); color: #fff; } }

.er-rounds { display: grid; grid-template-columns: repeat(4, minmax(0, 1fr)); gap: 22px; }
.er-rcard { overflow: hidden; cursor: pointer; display: flex; flex-direction: column;
  &:hover, &:focus { box-shadow: 0 0 0 3px var(--er-orange); outline: none; }
  &.done .er-bar i { background: #6fd39a; } }
.er-rpic { position: relative; height: 214px; }
.er-rpic-in { position: absolute; inset: 0; }
.er-rn { position: absolute; top: 12px; left: 12px; z-index: 2; font: 700 15px "Overpass Mono", monospace; background: rgba(0, 0, 0, 0.72); padding: 3px 10px; border-radius: 0.25rem; }
.er-res { position: absolute; top: 12px; right: 12px; z-index: 2; font-size: 15px; font-weight: 700; padding: 3px 10px; border-radius: 0.25rem; background: var(--er-orange-500);
  &.er-nr { background: rgba(0, 0, 0, 0.72); color: #ffd36b; } }
.er-body { padding: 14px 18px 16px; min-width: 0; }
.er-nm { font-size: 21px; font-weight: 700; white-space: nowrap; overflow: hidden; text-overflow: ellipsis; }
.er-dt { font-size: 15px; color: var(--er-muted); margin-top: 2px; }
.er-pr { display: flex; align-items: center; gap: 12px; margin-top: 12px; font-size: 15px; color: var(--er-muted);
  .er-bar { flex: 1; } .er-w { color: #fff; } }
.er-bar { height: 8px; border-radius: 4px; background: #2a2e38; overflow: hidden; i { display: block; height: 100%; background: var(--er-blue); } }

.er-stand-wrap { display: grid; grid-template-columns: minmax(0, 1fr) 380px; gap: 28px; align-items: start; }
.er-table { padding: 6px 0; }
.er-trow { display: grid; align-items: center; height: 48px; padding: 0 26px; font-size: 19px; border-left: 4px solid transparent;
  & + .er-trow { border-top: 1px solid rgba(255, 255, 255, 0.06); }
  &.er-hdr { height: 38px; font-size: 13px; letter-spacing: 0.08em; text-transform: uppercase; color: var(--er-muted); }
  &.me { background: rgba(199, 91, 30, 0.26); border-left-color: var(--er-orange); font-weight: 700; .er-pos { color: #fff; } }
  &.er-gap { height: 26px; color: #6f7480; font-size: 18px; line-height: 1; }
  .er-r { text-align: right; } .er-c { text-align: center; } .er-cnr { color: #6f7480; }
  .er-pos { font-family: "Overpass Mono", monospace; font-weight: 700; color: var(--er-muted); }
  .er-pts { font-family: "Overpass Mono", monospace; font-weight: 700; font-size: 21px; text-align: right; }
  .er-rp { font-family: "Overpass Mono", monospace; font-size: 15px; text-align: center; color: var(--er-muted);
    &.w { color: #ffcf4a; font-weight: 700; } &.x { color: #4a505c; } }
}
.er-none { padding: 16px 26px; }
.er-side { padding: 24px 26px;
  h3 { margin: 0 0 10px; font-size: 14px; letter-spacing: 0.1em; text-transform: uppercase; color: var(--er-muted); font-weight: 600; } }
.er-big { font: 700 52px "Overpass Mono", monospace; line-height: 1.05;
  small { font-size: 22px; color: var(--er-muted); margin-left: 6px; font-weight: 600; } }
.er-foot-note { margin-top: 14px; font-size: 15px; color: var(--er-muted); }
.er-pad { margin-top: 18px; padding: 0 4px; }
</style>
