<template>
  <!-- Earth Rally's settings (docs/mockups-1.2.0/menu.html, Settings): a row per setting with its choices as a
       segmented switch. The rows come from Lua (earthRally/settings.lua uiState: labels, descriptions, options), so
       a new setting needs no change here. In the menu page and in the pause menu's Earth Rally tab.
       Co-driver (docs/mockups-codriver/settings.html): the game's own co-driver settings (earthRally/codriver.lua),
       in a second column; not there on a game version without them. -->
  <!-- (#51: the mouse moves the one selection here too, in the pause menu's card as on the menu page) -->
  <div class="er-settings" @mousemove="pointTo">
    <div v-if="card" class="er-set-title">Earth Rally settings</div>
    <div class="er-set-cols">
      <div>
        <div v-if="cd" class="er-set-grp">Rally</div>
        <div v-for="s in schema" :key="s.id" class="er-set">
          <div class="er-set-text">
            <div class="er-set-n">{{ s.label }}</div>
            <div class="er-set-d">{{ s.desc }}</div>
          </div>
          <div class="er-seg">
            <span
              v-for="o in arr(s.options)"
              :key="String(o.value)"
              tabindex="0" bng-nav-item
              :class="{ on: values[s.id] === o.value }"
              @click="setSetting(s.id, o.value)"
              @keydown.enter="setSetting(s.id, o.value)"
            >{{ o.label }}</span>
          </div>
        </div>
        <div v-if="!schema.length" class="er-set-d">Earth Rally is not loaded.</div>
      </div>
      <div v-if="cd">
        <div class="er-set-grp">Co-driver</div>
        <div v-if="arr(cd.voices).length" class="er-set">
          <div class="er-set-text">
            <div class="er-set-n">Voice</div>
            <div class="er-set-d">{{ cd.locked ? "Change it between runs" : "Who reads your notes" }}</div>
          </div>
          <!-- a drop-down, not buttons: players can add many voices -->
          <select
            class="er-drop" bng-nav-item :disabled="cd.locked"
            :value="cd.voice"
            @change="setCodriver('voice', $event.target.value)"
          >
            <option v-for="o in arr(cd.voices)" :key="o.value" :value="o.value">{{ o.label }}</option>
          </select>
        </div>
        <div v-if="cd.style" class="er-set">
          <div class="er-set-text">
            <div class="er-set-n">Style</div>
            <div class="er-set-d">{{ cd.locked ? "Change it between runs" : cd.styleDesc }}</div>
          </div>
          <div class="er-seg" :class="{ locked: cd.locked }">
            <span
              v-for="o in arr(cd.styles)" :key="o.value"
              :tabindex="o.has && !cd.locked ? 0 : -1" :bng-nav-item="o.has && !cd.locked ? '' : null"
              :class="{ on: cd.style === o.value, off: !o.has }"
              @click="o.has && !cd.locked && setCodriver('style', o.value)"
              @keydown.enter="o.has && !cd.locked && setCodriver('style', o.value)"
            >{{ o.label }}</span>
          </div>
        </div>
        <div class="er-set">
          <div class="er-set-text">
            <div class="er-set-n">Call timing</div>
            <div class="er-set-d">How far ahead each call ends before you reach it</div>
          </div>
          <div class="er-slide">
            <input
              type="range" bng-nav-item
              :min="cd.timingMin" :max="cd.timingMax" :step="cd.timingStep"
              :value="timing"
              @input="timing = Number($event.target.value)"
              @change="setTiming(Number($event.target.value))"
            >
            <b>{{ Number(timing).toFixed(1) }} s</b>
          </div>
        </div>
        <div class="er-set">
          <div class="er-set-text">
            <div class="er-set-n">Spoken calls</div>
            <div class="er-set-d">Hear the co-driver</div>
          </div>
          <div class="er-seg">
            <span
              v-for="o in onOff" :key="String(o.value)"
              tabindex="0" bng-nav-item
              :class="{ on: cd.audio === o.value }"
              @click="setCodriver('audio', o.value)"
              @keydown.enter="setCodriver('audio', o.value)"
            >{{ o.label }}</span>
          </div>
        </div>
        <div class="er-set">
          <div class="er-set-text">
            <div class="er-set-n">Calls on screen</div>
            <div class="er-set-d">The pacenote symbols at the top of the screen</div>
          </div>
          <div class="er-seg">
            <span
              v-for="o in onOff" :key="String(o.value)"
              tabindex="0" bng-nav-item
              :class="{ on: cd.visual === o.value }"
              @click="setCodriver('visual', o.value)"
              @keydown.enter="setCodriver('visual', o.value)"
            >{{ o.label }}</span>
          </div>
        </div>
      </div>
    </div>
  </div>
</template>

<script setup>
import { computed, ref, watch, onMounted, onUnmounted } from "vue"
import { state, setSetting, setCodriver, arr, startPolling, stopPolling, pointTo } from "./store.js"

defineProps({
  card: { type: Boolean, default: false },     // in the pause menu (a title of its own)
})

const schema = computed(() => arr(state.value.settings && state.value.settings.schema))
const values = computed(() => (state.value.settings && state.value.settings.settings) || {})
const cd = computed(() => state.value.codriver || null)
const onOff = [{ value: true, label: "On" }, { value: false, label: "Off" }]
// the slider's number while it is dragged; the game's value again whenever that changes
const timing = ref(3)
watch(() => cd.value && cd.value.timing, v => { if (typeof v === "number") timing.value = v }, { immediate: true })
// (a save that failed or got no answer: the slider goes back to the game's value)
function setTiming(v) {
  setCodriver("timing", v, () => { if (cd.value && typeof cd.value.timing === "number") timing.value = cd.value.timing })
}

onMounted(startPolling)
onUnmounted(stopPolling)
</script>

<style lang="scss" scoped>
.er-settings { display: flex; flex-direction: column; gap: 2px; padding: 0.5em 0.75em; color: #f0f0f0; }
.er-set-title { font-size: 1.4em; font-weight: 700; padding-bottom: 0.4em; }
.er-set {
  display: flex; align-items: center; justify-content: space-between; gap: 1.5em; padding: 0.7em 0.5em;
  border-bottom: 1px solid rgba(255, 255, 255, 0.07);
}
.er-set-n { font-size: 1.15em; font-weight: 600; }
.er-set-d { font-size: 0.9em; color: #b8bcc6; margin-top: 2px; }
.er-seg {
  display: flex; flex-shrink: 0; border-radius: 0.25rem; overflow: hidden; box-shadow: inset 0 0 0 1px #5a6070;
  span { padding: 0.45em 0.9em; cursor: pointer; color: #b8bcc6; white-space: nowrap; }
  span:focus { background: rgba(255, 255, 255, 0.08); }   /* (#51: the focus only; the mouse moves it, pointTo) */
  span.on { background: #c75b1e; color: #fff; font-weight: 600; }
}
.er-set-cols { display: grid; grid-template-columns: repeat(auto-fit, minmax(32em, 1fr)); gap: 0 3em; align-items: start; }
.er-set-grp { font-size: 0.85em; text-transform: uppercase; letter-spacing: 0.08em; color: #9aa3ad; padding: 0.3em 0.5em; }
.er-seg span.off { color: #5d626c; cursor: default; }
.er-drop {
  flex-shrink: 0; min-width: 14em; font: inherit; color: #fff; background: #23272e; cursor: pointer;
  border: 0; border-radius: 0.25rem; box-shadow: inset 0 0 0 1px #5a6070; padding: 0.45em 0.9em;
  &:focus { outline: 1px solid rgba(255, 255, 255, 0.4); }
  &:disabled { opacity: 0.45; cursor: default; }
  option { background: #23272e; color: #fff; }
}
.er-seg.locked { opacity: 0.45; span { cursor: default; } }
.er-slide {
  display: flex; align-items: center; gap: 0.8em; flex-shrink: 0;
  input { width: 12em; accent-color: #c75b1e; cursor: pointer; }
  input:focus { outline: 1px solid rgba(255, 255, 255, 0.4); }
  b { min-width: 3.6em; text-align: right; font-weight: 700; }
}
</style>
