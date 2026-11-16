<template>
  <!-- The loading screen (1.7.0, #49 and #40; docs/mockups-1.7.0/loading.html): over the whole menu page while the
       world loads somewhere (Drive, Go to start, Recce, Retry / Next stage, a rally's move to a stop, the stage at its
       time control). Its data: earthRally_main.uiLoading() (loadScreen.lua), polled here while the page is up. Steps,
       a bar, and last the world round the car against the "World loaded before driving" setting. At a time control
       (kind "atc") the card waits for Continue once the stage and the world are ready. -->
  <div v-if="L" class="er-load-wrap">
    <div class="er-load-top"><span class="er-accent">Earth</span> Rally</div>
    <div class="er-load-mid">
      <!-- the time control card -->
      <div v-if="L.kind === 'atc'" class="er-lcard er-tc">
        <div class="er-l">
          <div class="er-kick">{{ L.kick }}</div>
          <h1>{{ L.title }}</h1>
          <div class="er-sub">{{ L.sub }}</div>
          <div class="er-tcrow"><span>Time in</span><b>{{ (L.card && L.card.timeIn) || "–" }}</b></div>
          <div class="er-tcrow"><span>Start time</span><b class="er-sm">given at the red board</b></div>
          <div class="er-tcrow"><span>Then</span><b class="er-sm">move up to the start line</b></div>
        </div>
        <div class="er-r">
          <h3>The stage</h3>
          <ul class="er-steps">
            <li v-for="(s, i) in arr(L.steps).filter(x => !x.world)" :key="i" :class="s.state"><span class="er-dot">{{ s.state === "done" ? "✓" : "" }}</span>{{ s.text }}</li>
          </ul>
          <div class="er-world">
            <div class="er-wt"><b>World</b><span v-if="L.worldReady" class="er-ok">Ready to drive</span><span v-else>{{ L.world || 0 }}%</span></div>
            <div class="er-wbar"><i :class="{ full: L.worldReady }" :style="{ width: Math.min(100, L.world || 0) + '%' }"></i><em :style="{ left: L.need + '%' }"></em><u :style="{ left: L.need + '%' }">{{ L.need }}%</u></div>
          </div>
          <BngButton v-if="L.ready" v-bng-ui-nav-focus="1" class="er-big" :accent="ACCENTS.main" @click="cont">{{ L.button || "Continue" }}</BngButton>
          <BngButton v-else class="er-big" :accent="ACCENTS.secondary" disabled>Loading the stage...</BngButton>
        </div>
      </div>
      <!-- every other load -->
      <div v-else class="er-lcard er-load">
        <div class="er-kick">{{ L.kick }}</div>
        <h1>{{ L.title }}</h1>
        <div v-if="L.sub" class="er-sub">{{ L.sub }}</div>
        <template v-if="L.bar != null">
          <div class="er-bar"><i :style="{ width: Math.round(100 * L.bar) + '%' }"></i></div>
          <div class="er-barlbl"><span>{{ L.barText }}</span><span>{{ Math.round(100 * L.bar) }}%</span></div>
        </template>
        <ul class="er-steps">
          <li v-for="(s, i) in arr(L.steps)" :key="i" :class="s.state"><span class="er-dot">{{ s.state === "done" ? "✓" : "" }}</span>{{ s.text }}</li>
        </ul>
        <div class="er-world">
          <div class="er-wt"><b>World</b><span v-if="L.worldReady" class="er-ok">Ready to drive</span><span v-else>{{ L.world || 0 }}%</span></div>
          <div class="er-wbar"><i :class="{ full: L.worldReady }" :style="{ width: Math.min(100, L.world || 0) + '%' }"></i><em :style="{ left: L.need + '%' }"></em><u :style="{ left: L.need + '%' }">{{ L.need }}%</u></div>
        </div>
        <div v-if="L.tip" class="er-tip">{{ L.tip }}</div>
      </div>
    </div>
    <div class="er-load-foot">
      <span v-if="L.kind === 'atc' && L.ready"><span class="er-k">A</span>Continue</span>
      <span class="er-paused">Game paused</span>
    </div>
  </div>
</template>

<script setup>
import { ref, onMounted, onUnmounted } from "vue"
import { BngButton, ACCENTS } from "@/common/components/base"
import { vBngUiNavFocus } from "@/common/directives"
import { engineLua, arr, refreshState } from "./store.js"

const emit = defineEmits(["view"])
const L = ref(null)
let timer = null
function poll() {
  engineLua("earthRally_main and earthRally_main.uiLoading and earthRally_main.uiLoading() or nil", r => {
    const was = L.value
    L.value = r && typeof r === "object" && r.title !== undefined ? r : null
    // (done: the page under it shows what follows, the time card in a rally)
    if (was && !L.value) {
      refreshState()
      if (was.thenView) emit("view", was.thenView)
    }
  })
}
function cont() { engineLua("earthRally_main and earthRally_main.uiLoadingContinue()", () => poll()) }
onMounted(() => { poll(); timer = setInterval(poll, 250) })
onUnmounted(() => { if (timer) clearInterval(timer) })
</script>

<style lang="scss" scoped>
.er-load-wrap { position: fixed; inset: 0; z-index: 50; display: flex; flex-direction: column; background: rgba(10, 12, 16, 0.92); color: #f0f0f0; }
.er-load-top { height: 84px; display: flex; align-items: center; padding: 0 64px; font-size: 30px; font-weight: 700; letter-spacing: 0.06em; text-transform: uppercase; background: linear-gradient(180deg, rgba(0, 0, 0, 0.8), rgba(0, 0, 0, 0.35)); }
.er-accent { color: #f26b1d; margin-right: 10px; }
.er-load-mid { flex: 1; display: flex; align-items: center; justify-content: center; padding: 28px 64px; }
.er-load-foot { height: 56px; display: flex; align-items: center; gap: 30px; padding: 0 64px; background: rgba(0, 0, 0, 0.6); color: #b8bcc6; font-size: 17px; }
.er-k { display: inline-flex; align-items: center; justify-content: center; width: 28px; height: 28px; border-radius: 50%; font-weight: 700; font-size: 14px; color: #111; background: #6cc24a; margin-right: 8px; }
.er-paused { margin-left: auto; font-size: 15px; letter-spacing: 0.12em; text-transform: uppercase; color: #8a909a; }
.er-lcard { background: rgba(0, 0, 0, 0.6); border-radius: 10px; }
.er-load { width: 980px; padding: 44px 52px; }
.er-kick { font-size: 17px; letter-spacing: 0.18em; text-transform: uppercase; color: #f26b1d; font-weight: 700; }
h1 { margin: 8px 0 6px; font-size: 52px; line-height: 1.05; text-transform: uppercase; font-weight: 800; }
.er-sub { font-size: 21px; color: #b8bcc6; margin-bottom: 28px; }
.er-bar { height: 12px; border-radius: 6px; background: rgba(255, 255, 255, 0.12); overflow: hidden; margin: 8px 0 10px; i { display: block; height: 100%; background: #f26b1d; border-radius: 6px; } }
.er-barlbl { display: flex; justify-content: space-between; color: #b8bcc6; font-size: 17px; }
.er-steps { margin: 26px 0 0; padding: 0; list-style: none; display: grid; gap: 12px; font-size: 20px;
  li { display: flex; align-items: center; gap: 14px; color: #8a909a; }
  li.done { color: #e8eaee; } li.now { color: #fff; font-weight: 600; } }
.er-dot { width: 26px; height: 26px; border-radius: 50%; border: 2px solid #5a606a; display: inline-flex; align-items: center; justify-content: center; font-size: 15px; flex-shrink: 0; }
.done .er-dot { background: #3ccf7e; border-color: #3ccf7e; color: #062; }
.now .er-dot { border-color: #f26b1d; border-top-color: transparent; animation: er-spin 1s linear infinite; }
@keyframes er-spin { to { transform: rotate(360deg); } }
.er-world { margin-top: 26px; padding: 18px 20px 30px; border-radius: 8px; background: rgba(255, 255, 255, 0.05); }
.er-wt { display: flex; justify-content: space-between; font-size: 18px; margin-bottom: 10px; b { font-weight: 600; } span { color: #b8bcc6; } span.er-ok { color: #3ccf7e; } }
.er-wbar { position: relative; height: 14px; border-radius: 7px; background: rgba(255, 255, 255, 0.12);
  i { position: absolute; left: 0; top: 0; bottom: 0; border-radius: 7px; background: #3b8beb; }
  i.full { background: #3ccf7e; }
  em { position: absolute; top: -6px; bottom: -6px; width: 3px; background: #fff; border-radius: 2px; }
  u { position: absolute; top: 20px; transform: translateX(-50%); text-decoration: none; font-size: 14px; color: #fff; white-space: nowrap; } }
.er-tip { margin-top: 30px; padding-top: 20px; border-top: 1px solid rgba(255, 255, 255, 0.1); color: #b8bcc6; font-size: 17px; }
.er-tc { width: 1080px; display: grid; grid-template-columns: 1fr 1fr; overflow: hidden;
  .er-l { padding: 42px 46px; }
  .er-r { padding: 42px 46px; background: rgba(255, 255, 255, 0.04); display: flex; flex-direction: column; }
  h3 { margin: 0 0 14px; font-size: 18px; letter-spacing: 0.14em; text-transform: uppercase; color: #b8bcc6; font-weight: 600; }
  .er-steps { margin: 0; font-size: 18px; } }
.er-tcrow { display: flex; justify-content: space-between; align-items: baseline; padding: 12px 0; border-bottom: 1px solid rgba(255, 255, 255, 0.08); font-size: 20px;
  span { color: #b8bcc6; } b { font-family: "Overpass Mono", monospace; font-size: 26px; } b.er-sm { font-family: inherit; font-size: 18px; font-weight: 500; } }
.er-big { width: 100%; margin-top: 24px; font-size: 24px; }
</style>
