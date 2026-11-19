<template>
  <!-- The Leaderboards helper did not answer when the menu opened (#77; main.lua helperPromptWanted): how to add it.
       Got it hides it until the next menu open; with the box ticked, until another version of the mod. -->
  <div class="er-helper">
    <div class="er-hp-card">
      <h1>Add Earth Rally Leaderboards</h1>
      <p>Leaderboards compare your stage times with other players. They need a small helper add-on beside the game.</p>
      <ol>
        <li>In BeamNG.Earth, open <b>Add-ons › Add from GitHub</b>.</li>
        <li>Paste <code>DeRamp/earth-rally-leaderboards</code>.</li>
        <li>Press <b>Install</b>, then <b>Start</b>.</li>
        <li>Tick <b>Start with BeamNG.Earth</b>.</li>
      </ol>
      <p class="er-hp-small">Then turn on <b>Settings › Leaderboards</b> here.</p>
      <div class="er-hp-btns">
        <label class="er-hp-check"><input type="checkbox" v-model="dontShow" /> Don't show this again</label>
        <BngButton :accent="ACCENTS.outlined" @click="close">Got it</BngButton>
      </div>
    </div>
  </div>
</template>

<script setup>
import { ref } from "vue"
import { BngButton, ACCENTS } from "@/common/components/base"
import { helperPromptClose } from "./store.js"

const dontShow = ref(false)
function close() { helperPromptClose(dontShow.value) }
</script>

<style lang="scss" scoped>
.er-helper {
  position: fixed; inset: 0; z-index: 50; display: flex; align-items: center; justify-content: center;
  background: rgba(0, 0, 0, 0.62);
}
.er-hp-card {
  width: 720px; max-width: 92%; background: #16181c; border-radius: 0.5rem; padding: 34px 40px 30px; color: #f0f0f0;
  box-shadow: 0 10px 40px rgba(0, 0, 0, 0.6);
  h1 { margin: 0 0 12px; font-size: 30px; }
  p { font-size: 17px; line-height: 1.5; color: #d8dbe2; margin: 0 0 16px; }
  ol { margin: 0 0 16px; padding-left: 24px; font-size: 17px; line-height: 1.8; color: #d8dbe2; }
  code { background: rgba(255, 255, 255, 0.08); border-radius: 0.25rem; padding: 1px 6px; color: #f0f0f0; }
}
.er-hp-small { font-size: 14px !important; color: #b8bcc6 !important; }
.er-hp-btns { display: flex; gap: 14px; align-items: center; justify-content: space-between; }
.er-hp-check { display: flex; gap: 8px; align-items: center; font-size: 16px; color: #d8dbe2; cursor: pointer; }
</style>
