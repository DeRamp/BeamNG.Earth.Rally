<template>
  <!-- The pause menu's Earth Rally tab: one button into the menu page (EarthRally.vue), which opens where it was
       left. index.js registers it. -->
  <div class="er-tab">
    <div class="er-tab-title">Earth Rally</div>
    <BngButton :accent="ACCENTS.main" class="er-tab-go" @click="openMenu()">Rally menu</BngButton>
    <div class="er-tab-sub">Ctrl+Alt+K opens it while you drive.</div>
  </div>
</template>

<script setup>
import { BngButton, ACCENTS } from "@/common/components/base"
import { openMenu } from "./store.js"
</script>

<style lang="scss" scoped>
.er-tab { display: flex; flex-direction: column; align-items: flex-start; gap: 0.75em; padding: 0.5em 0.75em 1em; color: #f0f0f0; }
.er-tab-title { font-size: 1.4em; font-weight: 700; }
.er-tab-go { font-size: 1.15em; }
.er-tab-sub { font-size: 0.9em; color: #b8bcc6; }
</style>
