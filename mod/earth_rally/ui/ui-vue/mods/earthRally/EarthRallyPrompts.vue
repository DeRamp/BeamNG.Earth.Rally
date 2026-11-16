<template>
  <!-- The prompt bar along the bottom of the menu page (1.7.0, #39; docs/mockups-1.7.0/home.html): a controller's
       buttons for the page shown, then the key that opens and closes the menu. A presses what has the focus, B goes
       back (Close on Home), Y opens Results on the Drive rally page (EarthRally.vue's context handler). -->
  <div class="er-prompts">
    <span><span class="er-pad a">A</span>Select</span>
    <span><span class="er-pad b">B</span>{{ top ? "Close" : "Back" }}</span>
    <span v-if="results"><span class="er-pad y">Y</span>Results</span>
    <span class="er-pr-right"><span class="er-k">Ctrl+Alt+K</span>Open / close</span>
  </div>
</template>

<script setup>
defineProps({
  top: { type: Boolean, default: false },       // Home: B closes the menu
  results: { type: Boolean, default: false },   // Drive rally with a rally that has results: Y
})
</script>

<style lang="scss" scoped>
.er-prompts { height: 56px; flex-shrink: 0; display: flex; align-items: center; gap: 30px; padding: 0 64px; background: rgba(0, 0, 0, 0.6);
  color: var(--er-muted); font-size: 17px; }
.er-pad { display: inline-flex; align-items: center; justify-content: center; width: 28px; height: 28px; border-radius: 50%;
  font: 700 14px "Noto Sans", sans-serif; color: #111; margin-right: 8px; vertical-align: middle;
  &.a { background: #6cc24a; } &.b { background: #e5533d; } &.y { background: #f0c419; } }
.er-pr-right { margin-left: auto; }
.er-k { font-family: "Overpass Mono", monospace; font-size: 13px; padding: 1px 7px; margin-right: 6px; border: 1px solid #6f7480; border-radius: 3px; color: #fff; }
</style>
