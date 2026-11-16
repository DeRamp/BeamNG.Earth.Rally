<template>
  <!-- The loading screen (1.7.0, #49 and #40; docs/mockups-1.7.0/loading.html): over the whole menu page while the
       world loads somewhere (Drive, Go to start, Recce, Retry / Next stage, a rally's move to a stop, the stage at its
       time control). Its data: earthRally_main.uiLoading() (loadScreen.lua), polled here while the page is up. Steps,
       a bar, and last the world round the car against the "World loaded before driving" setting. At a time control
       (kind "atc") the card waits for Continue once the stage and the world are ready. While it is up the menu page
       under it is not drawn (#60, EarthRally.vue): it is a screen of its own, on its own background.
       A presses Continue as soon as it is ready, wherever the focus is (#61): the ok handler is on the screen itself,
       and the game's nav runs the deepest handler in the page's scope when the focused element has none. -->
  <div v-if="L" class="er-load-wrap" v-bng-on-ui-nav:ok="okPress">
    <div class="er-load-top"><span class="er-accent">Earth</span> Rally</div>
    <div class="er-load-mid">
      <!-- the time control card -->
      <div v-if="L.kind === 'atc'" class="er-lcard er-tc">
        <div class="er-l">
          <div class="er-kick">{{ L.kick }}</div>
          <h1>{{ L.title }}</h1>
          <div class="er-sub">{{ L.sub }}</div>
          <!-- (#64) the start time is given when Continue is pressed, so it cannot run out while the card is up -->
          <div class="er-tcrow"><span>Time in</span><b>{{ (L.card && L.card.timeIn) || "–" }}</b></div>
          <div v-if="L.card && L.card.due" class="er-tcrow"><span>Due</span><b>{{ L.card.due }}</b></div>
          <div class="er-tcrow"><span>Start time</span><b :class="{ 'er-sm': !L.ready }">{{ (L.card && L.card.startNote) || "given when you continue" }}</b></div>
          <div class="er-tcrow"><span>Then</span><b class="er-sm">move up to the start line</b></div>
        </div>
        <div class="er-r">
          <h3>The stage</h3>
          <ul class="er-steps">
            <li v-for="(s, i) in arr(L.steps).filter(x => !x.world)" :key="i" :class="s.state"><span class="er-dot">{{ s.state === "done" ? "✓" : "" }}</span>{{ s.text }}</li>
          </ul>
          <div class="er-world">
            <!-- (#63) while the world's origin moves (L.moving), its count means nothing yet: a moving stripe -->
            <div class="er-wt"><b>World</b><span v-if="L.moving">Moving the world...</span><span v-else-if="L.worldReady" class="er-ok">Ready to drive</span><span v-else>{{ L.world || 0 }}%</span></div>
            <div class="er-wbar"><i v-if="L.moving" class="move"></i><i v-else :class="{ full: L.worldReady }" :style="{ width: Math.min(100, L.world || 0) + '%' }"></i><em :style="{ left: L.need + '%' }"></em><u :style="{ left: L.need + '%' }">{{ L.need }}%</u></div>
          </div>
          <BngButton v-if="L.ready" ref="contBtn" v-bng-ui-nav-focus="1" class="er-big" :accent="ACCENTS.main" @click="cont">{{ L.button || "Continue" }}</BngButton>
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
          <!-- (#63) while the world's origin moves (L.moving), its count means nothing yet: a moving stripe -->
          <div class="er-wt"><b>World</b><span v-if="L.moving">Moving the world...</span><span v-else-if="L.worldReady" class="er-ok">Ready to drive</span><span v-else>{{ L.world || 0 }}%</span></div>
          <div class="er-wbar"><i v-if="L.moving" class="move"></i><i v-else :class="{ full: L.worldReady }" :style="{ width: Math.min(100, L.world || 0) + '%' }"></i><em :style="{ left: L.need + '%' }"></em><u :style="{ left: L.need + '%' }">{{ L.need }}%</u></div>
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
import { ref, watch, nextTick, onMounted, onUnmounted } from "vue"
import { BngButton, ACCENTS } from "@/common/components/base"
import { vBngUiNavFocus, vBngOnUiNav } from "@/common/directives"
import { engineLua, arr, refreshState, focusButton } from "./store.js"

// up: true while the screen is up (the page under it stops drawing itself, #60)
const emit = defineEmits(["view", "up"])
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
// (one press, one Continue: the button's click and A can both arrive for the same press)
let sent = false
function cont() {
  if (sent) return
  sent = true
  engineLua("earthRally_main and earthRally_main.uiLoadingContinue()", () => { sent = false; poll() })
}
// A on the screen: Continue once ready, else nothing (nothing under a loading screen is to be pressed)
function okPress() { if (L.value && L.value.kind === "atc" && L.value.ready) cont() }
// (#61) the ready button takes the real focus as it appears, not only on a controller's first page
const contBtn = ref(null)
watch(() => !!(L.value && L.value.ready), r => { if (r) nextTick(() => focusButton(contBtn.value)) })
watch(() => !!L.value, up => { sent = false; emit("up", up) })
onMounted(() => { poll(); timer = setInterval(poll, 250) })
onUnmounted(() => { if (timer) clearInterval(timer) })
</script>

<style lang="scss" scoped>
/* (#60) a background of its own, solid: the game and the menu page never show through */
.er-load-wrap { position: fixed; inset: 0; z-index: 50; display: flex; flex-direction: column; color: #f0f0f0;
  background: radial-gradient(ellipse at 70% 30%, #2a2219 0%, #121418 60%, #0b0c0f 100%); }
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
@keyframes er-slide { from { left: 0; } to { left: 70%; } }
.er-world { margin-top: 26px; padding: 18px 20px 30px; border-radius: 8px; background: rgba(255, 255, 255, 0.05); }
.er-wt { display: flex; justify-content: space-between; font-size: 18px; margin-bottom: 10px; b { font-weight: 600; } span { color: #b8bcc6; } span.er-ok { color: #3ccf7e; } }
.er-wbar { position: relative; height: 14px; border-radius: 7px; background: rgba(255, 255, 255, 0.12);
  i { position: absolute; left: 0; top: 0; bottom: 0; border-radius: 7px; background: #3b8beb; }
  i.full { background: #3ccf7e; }
  i.move { width: 30%; background: repeating-linear-gradient(90deg, #3b8beb 0 14px, #2a6bb8 14px 28px); animation: er-slide 1.6s linear infinite; }
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
