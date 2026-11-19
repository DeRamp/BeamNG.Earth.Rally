<template>
  <!-- No leaderboard name yet (main.lua namePromptWanted): Leaderboards on, the helper connected, no player. Save is
       the Online card's name box (uiOnlineName); it closes once the name is saved (the player comes back in the
       state), shows the error otherwise. Later hides it until the next menu open. -->
  <div class="er-namep">
    <div class="er-np-card">
      <h1>Pick your leaderboard name</h1>
      <p>Everyone on the leaderboard sees it. 2 to 24 letters or numbers.</p>
      <input ref="box" v-model="nameText" class="er-np-input" type="text" maxlength="24" placeholder="Your name"
        tabindex="0" bng-nav-item
        @focus="typing(true)" @blur="typing(false)" @keydown.enter="save" @keydown.stop @keyup.stop />
      <div v-if="error" class="er-np-why">{{ error }}</div>
      <div class="er-np-btns">
        <BngButton ref="laterBtn" :accent="ACCENTS.outlined" @click="later">Later</BngButton>
        <BngButton :accent="ACCENTS.main" :disabled="asking || nameText.trim().length < 2" @click="save">Save</BngButton>
      </div>
    </div>
  </div>
</template>

<script setup>
import { ref, computed, watch, onMounted, onUnmounted, nextTick } from "vue"
import { BngButton, ACCENTS } from "@/common/components/base"
import { onlineName, namePromptLater, typing, focusButton, refreshState } from "./store.js"

// naming: the last Save's answer from uiState ({ asking } or { ok, error })
const props = defineProps({ naming: Object })
const nameText = ref("")
const saving = ref(false)   // Save pressed here, its answer not in yet
let sent = false            // the name reached the Lua side (a poll's answer from before it is not the answer)
const tried = ref(false)    // Save pressed here at least once (an older answer from the Online card is not shown)
const box = ref(null)
const laterBtn = ref(null)
const asking = computed(() => saving.value || !!(props.naming && props.naming.asking))
const error = computed(() => (tried.value && !saving.value && props.naming && !props.naming.asking && !props.naming.ok && props.naming.error) || "")

function save() {
  const n = nameText.value.trim()
  if (n.length < 2 || asking.value) return
  saving.value = true
  tried.value = true
  sent = false
  onlineName(n, () => { sent = true; refreshState() })
}
// (the answer in: the pop-up goes on ok, as the player comes back in the state; the error shows otherwise)
watch(() => props.naming, nm => {
  if (saving.value && sent && nm && !nm.asking) {
    saving.value = false
    if (nm.ok) typing(false)
  }
})
function later() { typing(false); namePromptLater() }
// (the controller lands on the pop-up, not on the page under it: on Later, as Save waits for a name)
onMounted(() => nextTick(() => focusButton(laterBtn.value)))
onUnmounted(() => typing(false))
</script>

<style lang="scss" scoped>
.er-namep {
  position: fixed; inset: 0; z-index: 50; display: flex; align-items: center; justify-content: center;
  background: rgba(0, 0, 0, 0.62);
}
.er-np-card {
  width: 620px; max-width: 92%; background: #16181c; border-radius: 0.5rem; padding: 34px 40px 30px; color: #f0f0f0;
  box-shadow: 0 10px 40px rgba(0, 0, 0, 0.6);
  h1 { margin: 0 0 12px; font-size: 30px; }
  p { font-size: 17px; line-height: 1.5; color: #d8dbe2; margin: 0 0 16px; }
}
.er-np-input {
  width: 100%; box-sizing: border-box; font-size: 18px; padding: 8px 12px; margin: 0 0 10px; border-radius: 0.25rem;
  border: 1px solid rgba(255, 255, 255, 0.25); background: rgba(255, 255, 255, 0.06); color: #f0f0f0;
}
.er-np-why { color: #ff9a8a; font-size: 15px; margin: 0 0 10px; }
.er-np-btns { display: flex; gap: 14px; justify-content: flex-end; margin-top: 6px; }
</style>
