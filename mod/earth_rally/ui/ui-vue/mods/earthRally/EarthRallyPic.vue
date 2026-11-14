<template>
  <!-- A rally's picture over a rally plate drawn in CSS (docs/mockups-rally-files/menu.html, "pictures"). The plate
       is always there, so a rally with no picture, or one whose file will not load, still looks deliberate: a
       picture that fails is dropped (@error), never left as a broken image. Where the game's UI can load a file
       from the user folder is not yet checked in game (menu.lua, mediaUrl): until it is, this is what shows.
       contain: a logo (a transparent PNG). The plate is then drawn only when there is no logo to show, or it
       would show through the logo. bare: a backdrop (the rally banner's photo), the drawn ground with no plate. -->
  <div class="er-pic er-plate-bg" :class="{ blue, small }">
    <div v-if="plateShown" class="er-plate" :class="{ blue }">
      <div class="er-pk">{{ kind }}</div>
      <div class="er-pn">{{ name }}</div>
    </div>
    <img v-if="url && !bad" :src="url" :class="contain ? 'er-contain' : 'er-cover'" alt="" @error="bad = true" />
  </div>
</template>

<script setup>
import { ref, computed, watch } from "vue"

const props = defineProps({
  url: { type: String, default: "" },
  kind: { type: String, default: "RALLY" },     // the plate's small line: RALLY, STAGE, ROUND 3
  name: { type: String, default: "" },
  blue: { type: Boolean, default: false },      // a single stage's plate
  small: { type: Boolean, default: false },     // a mosaic tile
  contain: { type: Boolean, default: false },   // a logo
  bare: { type: Boolean, default: false },      // no plate at all
})
const bad = ref(false)
watch(() => props.url, () => { bad.value = false })
const plateShown = computed(() => !props.bare && (!props.contain || !props.url || bad.value))
</script>

<style lang="scss" scoped>
.er-pic { position: relative; overflow: hidden; display: flex; align-items: center; justify-content: center; }
.er-plate-bg {
  background-color: #1b2530;
  background-image: repeating-linear-gradient(135deg, rgba(255, 255, 255, 0.035) 0 2px, transparent 2px 22px),
    radial-gradient(ellipse at 30% 20%, rgba(242, 107, 29, 0.28), transparent 60%), linear-gradient(160deg, #26323d, #12171d);
  &.blue {
    background-image: repeating-linear-gradient(135deg, rgba(255, 255, 255, 0.035) 0 2px, transparent 2px 22px),
      radial-gradient(ellipse at 30% 20%, rgba(31, 143, 255, 0.3), transparent 60%), linear-gradient(160deg, #22303f, #10161c);
  }
}
.er-plate {
  position: relative; padding: 26px 34px 20px; min-width: 62%; max-width: 86%; text-align: center;
  border: 5px solid #f0f0f0; border-radius: 120px 120px 14px 14px / 70px 70px 14px 14px;
  background: rgba(0, 0, 0, 0.35); box-shadow: 0 6px 24px rgba(0, 0, 0, 0.4);
  .er-pk { font-size: 14px; font-weight: 700; letter-spacing: 0.3em; color: #f26b1d; }
  .er-pn { font-size: 30px; font-weight: 800; line-height: 1.1; text-transform: uppercase; letter-spacing: 0.02em; margin-top: 4px;
    overflow-wrap: anywhere; }
  &.blue .er-pk { color: #6fb6ff; }
}
.small .er-plate {
  min-width: 0; padding: 8px 10px; border-width: 3px; border-radius: 40px 40px 6px 6px / 24px 24px 6px 6px;
  .er-pk { font-size: 10px; letter-spacing: 0.2em; }
  .er-pn { font-size: 13px; }
}
img { position: absolute; inset: 0; width: 100%; height: 100%; }
.er-cover { object-fit: cover; }
.er-contain { object-fit: contain; }
</style>
