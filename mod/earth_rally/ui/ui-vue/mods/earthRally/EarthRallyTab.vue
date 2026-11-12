<template>
  <!-- The pause menu's Earth Rally tab, its Rallies page: the run or recce under way, each rally with its progress
       and a way into the full menu page (EarthRally.vue). index.js registers it. -->
  <div class="er-tab">
    <div class="er-tab-title">Earth Rally</div>
    <div v-if="line" class="er-tab-run">{{ line }}</div>
    <div v-for="r in arr(st.rallies)" :key="r.id" class="er-tab-rally" tabindex="0" @click="openMenu('rally', r.id)" @keydown.enter="openMenu('rally', r.id)">
      <div class="er-tab-name">{{ r.name }}</div>
      <div class="er-tab-sub">{{ r.stages }} stages · {{ len(r.lengthM) }} · {{ r.driven }} driven</div>
    </div>
    <div v-if="!arr(st.rallies).length" class="er-tab-sub">No rallies yet: put a rally's map (.kml, .kmz, .gpx) in the import folder.</div>
    <div class="er-tab-buttons">
      <BngButton :accent="ACCENTS.main" @click="openMenu('rallies')">Open Earth Rally</BngButton>
      <BngButton :accent="ACCENTS.outlined" @click="action('openFolder')">Open import folder</BngButton>
    </div>
  </div>
</template>

<script setup>
import { computed, onMounted, onUnmounted } from "vue"
import { BngButton, ACCENTS } from "@/common/components/base"
import { state, arr, len, action, openMenu, startPolling, stopPolling, RUN_WORDS } from "./store.js"

const st = computed(() => state.value || {})
const line = computed(() => {
  const s = st.value
  if (s.recce) return `Recce of ${s.recce.stageName}: ${Math.round((s.recce.share || 0) * 100)} %`
  if (s.run && s.run.busy) return `SS${s.run.ss || ""} ${s.run.stageName}: ${RUN_WORDS[s.run.state] || s.run.state}`
  return ""
})

onMounted(startPolling)
onUnmounted(stopPolling)
</script>

<style lang="scss" scoped>
.er-tab { display: flex; flex-direction: column; gap: 0.5em; padding: 0.5em 0.75em 1em; color: #f0f0f0; }
.er-tab-title { font-size: 1.4em; font-weight: 700; }
.er-tab-run { padding: 0.5em 0.75em; border-left: 4px solid #1f8fff; background: rgba(31, 143, 255, 0.2); border-radius: 0.25rem; }
.er-tab-rally { padding: 0.6em 0.75em; border-radius: 0.25rem; background: rgba(0, 0, 0, 0.35); cursor: pointer; border-left: 4px solid #f26b1d;
  &:hover, &:focus { background: rgba(199, 91, 30, 0.25); } }
.er-tab-name { font-size: 1.15em; font-weight: 600; }
.er-tab-sub { font-size: 0.9em; color: #b8bcc6; }
.er-tab-buttons { display: flex; gap: 0.5em; flex-wrap: wrap; margin-top: 0.5em; }
</style>
