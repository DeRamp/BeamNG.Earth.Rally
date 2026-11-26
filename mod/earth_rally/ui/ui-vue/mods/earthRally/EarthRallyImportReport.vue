<template>
  <!-- Import report (docs/mockups-hand-files/import.html, screens 2 and 3): one import's verdict, its problems (file,
       line, the line as written, what is wrong, what to do) and what the game found. The same report is written as
       "import report.txt" beside the file (importReport.lua). Data: the Last import line it was opened from
       (main.lua scanImports, uiState.lastImport.lines[i].report). -->
  <section class="er-rep">
    <div v-if="!rep" class="er-muted er-none">Nothing to show: import something first.</div>
    <template v-else>
      <div class="er-rep-main">
        <div class="er-card er-verdict" :class="rep.verdict">
          <div class="er-vh">{{ rep.headline }}</div>
          <div class="er-vs">{{ rep.sub }}</div>
        </div>
        <template v-if="arr(rep.problems).length">
          <div class="er-lbl">Problems</div>
          <div class="er-card er-probs">
            <div v-for="p in arr(rep.problems)" :key="p.n" class="er-prob">
              <span class="er-n" :class="{ bad: rep.verdict === 'failed' }">{{ p.n }}</span>
              <span v-if="p.where" class="er-where">{{ p.where }}</span>
              <div v-if="p.text" class="er-as">{{ p.text }}</div>
              <div class="er-what">{{ p.what }}</div>
              <div v-if="p.fix" class="er-fix">{{ p.fix }}</div>
            </div>
          </div>
        </template>
        <template v-if="arr(rep.unused).length">
          <div class="er-lbl">Read but not used</div>
          <div class="er-card er-probs">
            <div v-for="(p, i) in arr(rep.unused)" :key="'u' + i" class="er-prob">
              <span v-if="p.where" class="er-where">{{ p.where }}</span>
              <div v-if="p.text" class="er-as">{{ p.text }}</div>
              <div class="er-what er-muted">{{ p.what }}</div>
            </div>
          </div>
        </template>
      </div>
      <div class="er-rep-side">
        <template v-for="(f, i) in arr(rep.found)" :key="'f' + i">
          <div class="er-lbl">{{ arr(rep.found).length > 1 ? f.title : "What the game found" }}</div>
          <div class="er-card er-found">
            <div v-for="r in arr(f.rows)" :key="r.label" class="er-row">
              <div class="er-k">{{ r.label }}</div>
              <div class="er-v">{{ r.value }}</div>
            </div>
          </div>
        </template>
        <div class="er-btns">
          <BngButton :accent="ACCENTS.secondary" @click="emit('action', 'openFolder')">Open folder</BngButton>
          <BngButton :accent="ACCENTS.outlined" @click="emit('action', 'rescan')">Re-scan</BngButton>
        </div>
      </div>
    </template>
  </section>
</template>

<script setup>
import { computed } from "vue"
import { BngButton, ACCENTS } from "@/common/components/base"
import { state, arr } from "./store.js"

const props = defineProps({ file: { type: String, default: "" } })
const emit = defineEmits(["action"])
// (the report of the import of `file` in the last scan; none when a later scan no longer has it)
const rep = computed(() => {
  const li = state.value && state.value.lastImport
  const lines = arr(li && li.lines)
  const hit = lines.find(l => l.report && l.file === props.file)
  return hit ? hit.report : null
})
</script>

<style lang="scss" scoped>
.er-card { background: rgba(0, 0, 0, 0.6); border-radius: 0.5rem; }
.er-muted { color: var(--er-muted); }
.er-none { font-size: 18px; }
.er-rep { display: grid; grid-template-columns: minmax(0, 1fr) 620px; gap: 28px; align-items: start; }
.er-lbl { font-size: 15px; letter-spacing: 0.14em; text-transform: uppercase; color: #8a909a; font-weight: 600; margin: 22px 0 12px; }
.er-rep-side .er-lbl:first-child { margin-top: 0; }
.er-verdict { padding: 22px 28px; border-left: 6px solid #ffd36b;
  &.ok { border-color: #6fd39a; } &.failed { border-color: #e5533d; }
  .er-vh { font-size: 26px; font-weight: 700; }
  .er-vs { color: var(--er-muted); font-size: 18px; margin-top: 6px; } }
.er-prob { padding: 16px 22px; border-bottom: 1px solid #2a2e35;
  &:last-child { border-bottom: 0; } }
.er-n { display: inline-block; width: 26px; height: 26px; border-radius: 50%; background: #ffd36b; color: #111; font-weight: 700;
  text-align: center; line-height: 26px; margin-right: 10px; font-size: 14px;
  &.bad { background: #e5533d; color: #fff; } }
.er-where { font-size: 14px; color: #8a909a; letter-spacing: 0.04em; }
.er-as { font-family: "Overpass Mono", monospace; font-size: 15px; color: #ddd; background: rgba(255, 255, 255, 0.06); padding: 3px 8px;
  border-radius: 3px; display: inline-block; margin: 6px 0; white-space: pre-wrap; word-break: break-word; }
.er-what { font-size: 18px; margin-top: 4px; }
.er-fix { color: var(--er-muted); font-size: 16px; margin-top: 4px; }
.er-found { padding: 18px 24px; font-size: 16px; }
.er-row { display: flex; gap: 16px; padding: 5px 0; }
.er-k { width: 130px; flex-shrink: 0; color: #8a909a; }
.er-v { white-space: pre-line; min-width: 0; word-break: break-word; }
.er-btns { display: flex; gap: 12px; margin-top: 18px; }
</style>
