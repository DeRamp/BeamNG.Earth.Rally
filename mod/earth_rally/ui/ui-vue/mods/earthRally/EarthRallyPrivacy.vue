<template>
  <!-- Settings › Privacy (+stats; docs/mockups-telemetry/telemetry.html, #settings and #reportweb): the stats switch,
       the local copy of what was sent, and Report a problem (a GitHub issue in the browser). -->
  <div class="er-privacy">
    <div class="er-pv-title">Privacy</div>
    <div class="er-pv-row">
      <div class="er-pv-t"><b>Send anonymous stats</b><span>Stages and rallies run and finished. A new random number each session, so nothing links back to you.</span></div>
      <div class="er-seg">
        <span tabindex="0" bng-nav-item :class="{ on: s.consent === 'yes' }" @click="statsAction('yes')" @keydown.enter="statsAction('yes')">On</span>
        <span tabindex="0" bng-nav-item :class="{ on: s.consent !== 'yes' }" @click="statsAction('no')" @keydown.enter="statsAction('no')">Off</span>
      </div>
    </div>
    <div class="er-pv-row">
      <div class="er-pv-t"><b>See what was sent</b><span>Every message is also saved on your PC, word for word
        (earthRally/telemetry/sent.jsonl).</span></div>
      <BngButton :accent="ACCENTS.outlined" @click="statsAction('openFolder')">Open folder</BngButton>
    </div>
    <div class="er-pv-row">
      <div class="er-pv-t"><b>Report a problem</b><span>Opens a bug report on GitHub. You choose whether to add your log.</span></div>
      <BngButton :accent="ACCENTS.outlined" @click="reportOpen = true">Report</BngButton>
    </div>
    <div v-if="s.consent === 'yes' && !s.server" class="er-pv-note">Stats are kept on your PC for now: this build has no
      stats server set yet.</div>
    <div v-else-if="s.waiting" class="er-pv-note">{{ s.waiting }} waiting to be sent.</div>
    <template v-if="s.last">
      <div class="er-pv-label">Last message sent</div>
      <pre class="er-pv-code">{{ s.last }}</pre>
    </template>

    <!-- Report a problem -->
    <div v-if="reportOpen" class="er-pv-dim">
      <div class="er-pv-card">
        <h1>Report a problem</h1>
        <div class="er-pv-label">What happened?</div>
        <textarea v-model="text" rows="5" placeholder="The co-driver stopped calling notes halfway through SS3…"></textarea>
        <label class="er-pv-check"><input type="checkbox" v-model="withLog"> Save my game log for the report
          (personal details removed)</label>
        <p class="er-pv-small">Your browser opens a new issue on <b>github.com/DeRamp/BeamNG.Earth.Rally</b> with this
          filled in. The log is saved to earthRally/reports/ and its folder opens: drag the file into the issue.
          Needs a free GitHub account.</p>
        <div class="er-pv-btns">
          <BngButton :accent="ACCENTS.outlined" @click="reportOpen = false">Cancel</BngButton>
          <BngButton :accent="ACCENTS.main" @click="send">Open GitHub</BngButton>
        </div>
      </div>
    </div>
    <div v-if="msg" class="er-pv-note">{{ msg }}</div>
  </div>
</template>

<script setup>
import { ref, computed } from "vue"
import { BngButton, ACCENTS } from "@/common/components/base"
import { state, statsAction } from "./store.js"

const s = computed(() => state.value.stats || {})
const reportOpen = ref(false)
const text = ref("")
const withLog = ref(true)
const msg = ref("")
function send() {
  statsAction("report", text.value, withLog.value, r => {
    msg.value = (r && r.message) || ""
    if (r && r.ok) { reportOpen.value = false; text.value = "" }
  })
}
</script>

<style lang="scss" scoped>
.er-privacy { padding: 0.5em 0.75em; color: #f0f0f0; }
.er-pv-title { font-size: 1.4em; font-weight: 700; padding-bottom: 0.4em; }
.er-pv-row {
  display: flex; align-items: center; justify-content: space-between; gap: 1.2em; padding: 0.7em 0.5em;
  border-bottom: 1px solid rgba(255, 255, 255, 0.07);
}
.er-pv-t { display: flex; flex-direction: column; b { font-size: 1.1em; font-weight: 600; } span { font-size: 0.9em; color: #b8bcc6; margin-top: 2px; } }
.er-seg {
  display: flex; flex-shrink: 0; border-radius: 0.25rem; overflow: hidden; box-shadow: inset 0 0 0 1px #5a6070;
  span { padding: 0.45em 0.9em; cursor: pointer; color: #b8bcc6; }
  span:hover { background: rgba(255, 255, 255, 0.08); }
  span.on { background: #c75b1e; color: #fff; font-weight: 600; }
}
.er-pv-note { margin-top: 0.8em; font-size: 0.9em; color: #b8bcc6; }
.er-pv-label { margin-top: 1.1em; font-size: 0.85em; color: #b8bcc6; text-transform: uppercase; letter-spacing: 0.05em; }
.er-pv-code {
  margin: 0.4em 0 0; padding: 0.7em 0.8em; background: rgba(0, 0, 0, 0.45); border-radius: 0.25rem; font-size: 0.8em;
  white-space: pre-wrap; word-break: break-all; color: #d8dbe2; max-height: 9em; overflow: auto;
}
.er-pv-dim { position: fixed; inset: 0; z-index: 60; background: rgba(0, 0, 0, 0.62); display: flex; align-items: center; justify-content: center; }
.er-pv-card {
  width: 900px; max-width: 92%; background: #16181c; border-radius: 0.5rem; padding: 30px 36px; color: #f0f0f0;
  h1 { margin: 0 0 6px; font-size: 28px; }
  textarea { width: 100%; box-sizing: border-box; margin-top: 6px; padding: 10px; font: inherit; font-size: 16px; color: #f0f0f0;
    background: rgba(0, 0, 0, 0.5); border: 1px solid #5a6070; border-radius: 0.25rem; resize: vertical; }
}
.er-pv-check { display: flex; gap: 10px; align-items: center; margin-top: 14px; font-size: 16px; }
.er-pv-small { font-size: 14px; color: #b8bcc6; line-height: 1.5; }
.er-pv-btns { display: flex; gap: 14px; justify-content: flex-end; margin-top: 10px; }
</style>
