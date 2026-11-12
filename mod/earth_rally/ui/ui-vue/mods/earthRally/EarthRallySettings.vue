<template>
  <!-- Earth Rally's settings (docs/mockups-1.2.0/menu.html, Settings): a row per setting with its choices as a
       segmented switch. The rows come from Lua (earthRally/settings.lua uiState: labels, descriptions, options), so
       a new setting needs no change here. In the menu page and in the pause menu's Earth Rally tab. -->
  <div class="er-settings">
    <div v-if="card" class="er-set-title">Earth Rally settings</div>
    <div v-for="s in schema" :key="s.id" class="er-set">
      <div class="er-set-text">
        <div class="er-set-n">{{ s.label }}</div>
        <div class="er-set-d">{{ s.desc }}</div>
      </div>
      <div class="er-seg">
        <span
          v-for="o in arr(s.options)"
          :key="String(o.value)"
          tabindex="0"
          :class="{ on: values[s.id] === o.value }"
          @click="setSetting(s.id, o.value)"
          @keydown.enter="setSetting(s.id, o.value)"
        >{{ o.label }}</span>
      </div>
    </div>
    <div v-if="!schema.length" class="er-set-d">Earth Rally is not loaded.</div>
    <div class="er-set-note">
      <b>Time controls</b>: <i>Full</i>, as in a real rally: stop at the time control (the red clock board), get your
      start time, move up to the start line and wait for your minute; driving past the time control costs 60 s.
      <i>Quick start</i>: straight to the start line, the countdown a few seconds after you stop on it. From the next stage.
    </div>
  </div>
</template>

<script setup>
import { computed, onMounted, onUnmounted } from "vue"
import { state, setSetting, arr, startPolling, stopPolling } from "./store.js"

defineProps({
  card: { type: Boolean, default: false },     // in the pause menu (a title of its own)
})

const schema = computed(() => arr(state.value.settings && state.value.settings.schema))
const values = computed(() => (state.value.settings && state.value.settings.settings) || {})

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
  span:hover { background: rgba(255, 255, 255, 0.08); }
  span.on { background: #c75b1e; color: #fff; font-weight: 600; }
}
.er-set-note { margin-top: 1em; font-size: 0.9em; line-height: 1.5; color: #b8bcc6; }
</style>
