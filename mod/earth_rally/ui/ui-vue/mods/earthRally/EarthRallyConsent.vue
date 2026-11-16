<template>
  <!-- The stats question (+stats; docs/mockups-telemetry/telemetry.html, #consent): over the menu page the first
       time it opens, once. Nothing is sent before the answer; leaving the menu with it up counts as No (main.lua).
       The two buttons look the same on purpose: No must be as easy as Yes. Nothing is pre-selected. -->
  <div class="er-consent">
    <div class="er-cs-card">
      <h1>Help improve Earth Rally?</h1>
      <p>Earth Rally can send a few anonymous counts, like which stages you run and whether you finish them. It shows
        which stages people drive and what needs fixing.</p>
      <div class="er-cs-cols">
        <div class="er-cs-col yes"><h2>What it sends</h2><ul>
          <li>Mod and game version</li>
          <li>Stages and rallies started and finished</li>
          <li>Stage time, resets, retirements</li>
          <li>A random number, new every session</li></ul></div>
        <div class="er-cs-col no"><h2>Never sent</h2><ul>
          <li>Your name, Steam or BeamNG account</li>
          <li>Your location, or your IP address (never stored)</li>
          <li>Your other mods or your PC</li>
          <li>Logs, unless you send a report</li></ul></div>
      </div>
      <p class="er-cs-small">Change your mind any time in <b>Settings › Privacy</b>. Full details, from DeRamp:
        github.com/DeRamp/BeamNG.Earth.Rally/PRIVACY.md</p>
      <div class="er-cs-btns">
        <BngButton :accent="ACCENTS.outlined" @click="answer('no')">No thanks</BngButton>
        <BngButton :accent="ACCENTS.outlined" @click="answer('yes')">Yes, send stats</BngButton>
      </div>
    </div>
  </div>
</template>

<script setup>
import { onMounted } from "vue"
import { BngButton, ACCENTS } from "@/common/components/base"
import { statsAction } from "./store.js"

function answer(what) { statsAction(what) }
onMounted(() => statsAction("shown"))
</script>

<style lang="scss" scoped>
.er-consent {
  position: fixed; inset: 0; z-index: 50; display: flex; align-items: center; justify-content: center;
  background: rgba(0, 0, 0, 0.62);
}
.er-cs-card {
  width: 860px; max-width: 92%; background: #16181c; border-radius: 0.5rem; padding: 34px 40px 30px; color: #f0f0f0;
  box-shadow: 0 10px 40px rgba(0, 0, 0, 0.6);
  h1 { margin: 0 0 12px; font-size: 30px; }
  p { font-size: 17px; line-height: 1.5; color: #d8dbe2; margin: 0 0 18px; }
}
.er-cs-cols { display: grid; grid-template-columns: 1fr 1fr; gap: 16px; margin-bottom: 16px; }
.er-cs-col {
  background: rgba(255, 255, 255, 0.04); border-radius: 0.35rem; padding: 14px 18px;
  h2 { margin: 0 0 6px; font-size: 16px; }
  ul { margin: 0; padding-left: 20px; line-height: 1.7; color: #d8dbe2; font-size: 15.5px; }
  &.yes h2 { color: #7fc77f; }
  &.no h2 { color: #e59a7a; }
}
.er-cs-small { font-size: 14px !important; color: #b8bcc6 !important; }
.er-cs-btns { display: flex; gap: 14px; justify-content: flex-end; }
</style>
