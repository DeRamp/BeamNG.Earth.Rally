<template>
  <!-- The pause menu's Earth Rally tab, its second card: how to get going, and the full menu page. -->
  <div class="er-side">
    <div class="er-side-title">Real-world rally stages</div>
    <p>Pick a rally and a stage, then <b>Drive stage</b>: the time control, your start minute, the stage with the
      game's co-driver, the flying finish and the stop control, as in a real rally.</p>
    <p><b>Ctrl+Alt+K</b> opens Earth Rally while you drive.</p>
    <BngButton :accent="ACCENTS.main" @click="openMenu('rallies')">Open Earth Rally</BngButton>
    <div class="er-side-v">Earth Rally {{ version }}</div>
  </div>
</template>

<script setup>
import { computed } from "vue"
import { BngButton, ACCENTS } from "@/common/components/base"
import { state, openMenu } from "./store.js"

const version = computed(() => (state.value && state.value.version) || "")
</script>

<style lang="scss" scoped>
.er-side { display: flex; flex-direction: column; gap: 0.5em; padding: 0.5em 0.75em 1em; color: #f0f0f0; height: 100%;
  p { margin: 0; line-height: 1.45; color: #dfe3ea; } }
.er-side-title { font-size: 1.2em; font-weight: 700; }
.er-side-v { margin-top: auto; font-size: 0.85em; color: #8a909a; }
</style>
