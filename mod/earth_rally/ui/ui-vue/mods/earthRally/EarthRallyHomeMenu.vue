<template>
  <!-- Home (1.7.0, #39; docs/mockups-1.7.0/home.html, moments home and homeSaved): where the menu opens. Drive rally
       is the big tile (a whole rally: the Drive rally page, EarthRallyPick.vue), Drive stage the smaller one (the
       Rallies list, EarthRallyHome.vue, as it was), Settings under them. A rally saved, or under way, puts a Continue
       strip in the Drive rally tile that goes straight back into it, and takes a controller's first focus.
       Data: menu.lua M.drive (store.js loadDrive, asked for by EarthRally.vue as Home opens) and uiState.rallyActive. -->
  <section class="er-hm">
    <div class="er-hm-tile er-hm-big" tabindex="0" bng-nav-item v-bng-ui-nav-focus="cont ? undefined : 1"
      @click="emit('pick')" @keydown.enter.self="emit('pick')">
      <svg class="er-hm-art" viewBox="0 0 1100 800" preserveAspectRatio="xMidYMid slice">
        <defs>
          <linearGradient id="er-hm-g1" x1="0" y1="0" x2="1" y2="1"><stop offset="0" stop-color="#3f6b86"/><stop offset=".5" stop-color="#6f8a5a"/><stop offset="1" stop-color="#2f3a28"/></linearGradient>
          <linearGradient id="er-hm-g2" x1="0" y1="0" x2="1" y2="1"><stop offset="0" stop-color="#8a6a45"/><stop offset=".6" stop-color="#b98c55"/><stop offset="1" stop-color="#4a3624"/></linearGradient>
        </defs>
        <rect width="1100" height="800" fill="url(#er-hm-g1)"/>
        <path d="M0 380 C200 330 330 420 520 360 S860 280 1100 330 L1100 800 L0 800Z" fill="#2c3a24" opacity=".85"/>
        <path d="M80 330 C240 240 300 280 420 200 S640 110 760 160 S960 240 1060 110" stroke="#e8d6b0" stroke-width="10" fill="none" stroke-linecap="round" opacity=".75"/>
        <path d="M80 330 C240 240 300 280 420 200 S640 110 760 160 S960 240 1060 110" stroke="#f26b1d" stroke-width="3" stroke-dasharray="14 12" fill="none" opacity=".9"/>
        <circle cx="420" cy="200" r="12" fill="#fff"/><circle cx="760" cy="160" r="12" fill="#fff"/>
      </svg>
      <div class="er-hm-shade"></div>
      <div class="er-hm-kicker">A whole rally</div>
      <h2>Drive rally</h2>
      <p>Every stage in order, start to finish. Drive the transits, service between loops, and see your time against the real field.</p>
      <ul><li>Time card</li><li>Transits &amp; service</li><li>Damage carries over</li><li>Realistic or Casual</li></ul>
      <!-- a rally under way (its time card) or saved (Continue): one press of A picks it back up -->
      <div v-if="cont" class="er-hm-cont" @click.stop>
        <div class="er-hm-ctext">
          <div class="er-hm-ct">{{ cont.active ? (cont.done ? "Finished" : "Under way") : "Continue" }}</div>
          <div class="er-hm-cn">{{ cont.name }}</div>
          <div class="er-hm-cw">{{ cont.where }}</div>
        </div>
        <BngButton v-bng-ui-nav-focus="1" class="er-hm-bigbtn" :accent="ACCENTS.main" :disabled="busy"
          @click.stop="cont.active ? emit('card') : emit('continue', cont.id)">{{ cont.active ? "Time card" : "Continue" }}</BngButton>
      </div>
      <div v-else><BngButton class="er-hm-bigbtn" :accent="ACCENTS.main" @click.stop="emit('pick')">Choose a rally</BngButton></div>
    </div>

    <div class="er-hm-side">
      <div class="er-hm-tile er-hm-small" tabindex="0" bng-nav-item @click="emit('stages')" @keydown.enter.self="emit('stages')">
        <svg class="er-hm-art" viewBox="0 0 700 600" preserveAspectRatio="xMidYMid slice">
          <rect width="700" height="600" fill="url(#er-hm-g2)"/>
          <path d="M60 300 C180 200 260 250 340 160 S520 60 650 80" stroke="#f3e2c0" stroke-width="9" fill="none" stroke-linecap="round" opacity=".8"/>
          <rect x="50" y="288" width="22" height="22" fill="#fff"/><path d="M640 68 l14 0 l0 24 l-14 0z" fill="#111"/>
        </svg>
        <div class="er-hm-shade"></div>
        <div class="er-hm-kicker">One stage</div>
        <h2>Drive stage</h2>
        <p>Pick any stage of any rally. Practise it, recce it, beat your best time.</p>
        <div><BngButton class="er-hm-midbtn" :accent="ACCENTS.outlined" @click.stop="emit('stages')">Choose a stage</BngButton></div>
      </div>
      <div class="er-card er-hm-mini" tabindex="0" bng-nav-item @click="emit('settings')" @keydown.enter.self="emit('settings')">
        <div class="er-hm-ic">⚙</div>
        <div>Settings<small>Units, co-driver, pacenotes, HUD</small></div>
      </div>
    </div>
  </section>
</template>

<script setup>
import { computed } from "vue"
import { BngButton, ACCENTS } from "@/common/components/base"
import { vBngUiNavFocus } from "@/common/directives"
import { state, drive, arr } from "./store.js"

defineProps({ busy: { type: Boolean, default: false } })
const emit = defineEmits(["pick", "stages", "settings", "continue", "card"])

const MODE = { realistic: "Realistic", casual: "Casual" }
// What the strip says, or null: the rally under way (uiState, live), else the last one saved (by savedAt)
const cont = computed(() => {
  const a = state.value && state.value.rallyActive
  if (a) return { active: true, done: a.done, id: a.id, name: a.name, where: a.done ? "Its results are on the time card." : "Back to its time card." }
  let best = null
  for (const r of arr(drive.value && drive.value.rallies)) {
    if (r.saved && (!best || String(r.saved.savedAt || "") > String(best.saved.savedAt || ""))) best = r
  }
  if (!best) return null
  const s = best.saved
  const where = [MODE[s.mode] || s.mode, s.class, s.at ? `at ${s.at}` : null, s.next && s.next !== s.at ? `${s.next} next` : null,
    `${s.done || 0} ${s.done === 1 ? "stage" : "stages"} done`].filter(Boolean).join(" · ")
  return { id: best.id, name: best.name, where }
})
</script>

<style lang="scss" scoped>
.er-card { background: rgba(0, 0, 0, 0.6); border-radius: 0.5rem; }
.er-hm { display: grid; grid-template-columns: 1.55fr 1fr; gap: 28px; height: 100%; min-height: 640px; }
.er-hm-tile { position: relative; border-radius: 10px; overflow: hidden; display: flex; flex-direction: column; justify-content: flex-end;
  padding: 40px 44px; cursor: pointer; min-width: 0;
  &:hover, &:focus { outline: 4px solid var(--er-orange); outline-offset: 0; }
  > :not(.er-hm-art):not(.er-hm-shade) { position: relative; }
  h2 { margin: 6px 0 10px; font-size: 76px; line-height: 1; letter-spacing: 0.02em; text-transform: uppercase; font-weight: 800; }
  p { margin: 0 0 22px; font-size: 21px; color: #dfe2e8; max-width: 760px; line-height: 1.4; }
  ul { margin: 0 0 26px; padding: 0; list-style: none; display: flex; flex-wrap: wrap; gap: 10px; }
  li { font-size: 16px; padding: 6px 12px; border-radius: 4px; background: rgba(255, 255, 255, 0.12); color: #eee; }
}
.er-hm-small h2 { font-size: 56px; }
.er-hm-art { position: absolute; inset: 0; width: 100%; height: 100%; }
.er-hm-shade { position: absolute; inset: 0; background: linear-gradient(180deg, rgba(0, 0, 0, 0) 25%, rgba(0, 0, 0, 0.85) 100%); }
.er-hm-kicker { font-size: 18px; letter-spacing: 0.18em; text-transform: uppercase; color: var(--er-orange); font-weight: 700; }
/* the game's button, made the mock-up's big one: its own size rules beaten on specificity (.er-hm first), its margin
   and min-width through the hooks it reads (EarthRally.vue's .er-act does the same) */
.er-hm .er-hm-bigbtn { --bng-button-margin: 0; font-size: 26px; line-height: 32px; padding: 14px 40px; letter-spacing: 0.04em; }
.er-hm .er-hm-midbtn { --bng-button-margin: 0; font-size: 20px; line-height: 26px; padding: 10px 30px; }
.er-hm-cont { display: flex; align-items: center; gap: 22px; padding: 18px 22px; border-radius: 8px; background: rgba(0, 0, 0, 0.55);
  border-left: 4px solid var(--er-orange); cursor: default;
  .er-hm-ctext { min-width: 0; margin-right: auto; }
  .er-hm-ct { font-size: 15px; color: var(--er-muted); text-transform: uppercase; letter-spacing: 0.1em; }
  .er-hm-cn { font-size: 24px; font-weight: 700; white-space: nowrap; overflow: hidden; text-overflow: ellipsis; }
  .er-hm-cw { color: var(--er-muted); font-size: 17px; }
}
.er-hm-side { display: grid; grid-template-rows: 1fr auto; gap: 28px; min-width: 0; }
.er-hm-mini { display: flex; align-items: center; gap: 18px; padding: 22px 26px; font-size: 20px; cursor: pointer;
  &:hover, &:focus { outline: 4px solid var(--er-orange); outline-offset: 0; }
  small { display: block; color: var(--er-muted); font-size: 15px; }
}
.er-hm-ic { width: 46px; height: 46px; border-radius: 50%; border: 2px solid #6f7480; display: flex; align-items: center; justify-content: center;
  font-size: 22px; color: var(--er-muted); flex-shrink: 0; }
</style>
