# What was found testing 1.3.2-dev

Reports from the user driving the build, and what came of each. The same shape as `docs/notes-1.3.0.md`.

---

## 1. A menu UI glitch, on BeamNG.Earth's map page and on the Earth Rally menu (reported 2026-11-14)

> "There seems to be a Menu UI glitch both for earths maps and our rally menu / might not be us, could be a beam
> issue"

**Not diagnosed yet — what the glitch looks like is not yet known, and that is what tells the two candidates below
apart.** No code changed. What the log and the two repositories say so far:

### What the log says, and it is one-sided

`beamng.log`, the session started 2026-11-14 12:32. **246 `ResizeObserver loop completed with undelivered
notifications` errors**, every one on the route `index.html#/beamng-earth-map` — BeamNG.Earth's map page — and not
one on Earth Rally's route (`grep -i "CEF.*earthRally"` over the whole log: nothing). `ResizeObserver` appears in
exactly one file across both repositories, BeamNG.Earth's `mod/beamng_earth/ui/ui-vue/mods/beamngEarth/EarthMap.vue`;
Earth Rally does not use it anywhere.

Paired against every page the UI router went to, which is what settles it:

| time | page opened | errors |
|---|---|---|
| 101.15 s | Earth Rally menu | none |
| 261.90 s | BeamNG.Earth map | **begin at 262.00 s**, on mount (`routeCommit -> mountReady`, then the error) |
| 265.70 s | BeamNG.Earth map | carry on; the burst runs to 269.5 s, 170 errors |
| 277.98 s | Earth Rally menu | none |
| 283.41 s | BeamNG.Earth map | **76 more**, 283.4 s to 284.5 s |
| 297.81 s | Earth Rally menu | none |
| 365.43 s | Earth Rally menu | none |

So the map page throws **every** time it is opened, from the first frame it mounts, and it settles after about
seven seconds before firing again on the next mount. The user's "the Menus and maps worked at first though" is the
first four minutes of the session, in which the map had not been opened yet — there was no clean map visit to lose.
The log ran on to 456 s with no further errors.

A `ResizeObserver` loop is a feedback loop: an observed element's size changes, the handler changes a size, the
observer fires again. Chromium logs the warning and drops a frame of notifications, which on screen is flicker or
a box that jitters between two sizes. 246 of them in 22 seconds is not a stray warning.

### The second candidate: a mod writing to the game's own app frame

BeamNG.Earth's status-bar app, `mod/beamng_earth/ui/modules/apps/BeamNGEarthStatus/app.js`, on the first HUD
payload it receives:

```js
var host = el && el.closest ? el.closest('.ui-app-host') : null
if (host) { host.style.overflow = 'visible'; unclipped = true }
```

`.ui-app-host` is **the game's** frame for a UI app, not the mod's own element. The app reaches out of itself and
sets an inline `overflow: visible` on it, once, and **never puts it back** — the flag `unclipped` makes sure it is
done once, and nothing restores it when the row shrinks to one line again. So for the rest of the session that
app's cell does not clip, and anything the status bar draws beyond its 64 px frame lands on whatever is next to
it.

This arrived upstream two days before the report, in `959e1022` (2026-11-12, "Status bar: a long loading (or
location) row wraps onto more lines... the app's frame (.ui-app-host, the layout's 64 px) no longer clips the grown
box"), and it **is in the branch on this machine** (`addon-api-road-graph`, which carries dev). The commit's own
message says it was checked at three UI scales and four UI resolutions — for the status bar itself. What it cannot
have checked is what the unclipped cell does to its neighbours, which in the stage layout are Earth Rally's HUD
apps.

**Scope, stated carefully so this is not overclaimed:** `closest('.ui-app-host')` walks up from the status bar's
own element, so it unclips **that app's** frame and not every app's. This is not a global style change. It still
means one app's box can now overlap its neighbours, and the effect outlives the long row that caused it.

### What has been ruled out

* **Not a stale UI cache.** `temp/html/cef_150` was written at 12:33, this session, after the install.
* **Not a stale installed copy.** The installed `EarthRally.vue` is byte-identical to the repository's and both
  carry the 11:52 edit; `tools/selftest.py --check-install` passes on all five checks.
* **Not an Earth Rally UI error.** Our route logged nothing at all, and the one thing 1.3.2 added to that page is a
  `v-for` over `st.versionNotes` through `arr()`, which returns `[]` for the empty Lua table and so renders nothing
  — and on this machine the version check found nothing to say, so the list is empty.

### What it actually looks like (screenshot, 2026-11-14)

Neither of the two candidates above. **The Earth Rally menu renders with its own stylesheet missing.** The DOM and
the data are intact and correct — the rally cards are all there, and they carry the 1.3.2 names ("2026 LSPR
Friday", "2026 OFR") — but every rule from the page's own `<style scoped lang="scss">` is gone: no panel, no grid,
no background. The content collapses into a narrow unstyled column in the top left, lines overlapping each other,
with the game world visible straight through where the page's background should be.

The decisive detail in that picture: **the game's own components keep their styling.** The Settings button and the
orange "Open rally" buttons are `BngButton`s and they still look right. So this is not "CSS failed to load" — it
is *our page's own style element*, and only that, missing.

The user, asked whether it happens on its own: **"Only after visiting Earth's map."**

### The leading explanation, stated as a hypothesis and not as a finding

Both mods register their routes through `window.bngRoutes` and the game's `ui_router_routeManager`, and both load
their page with a dynamic `import()` of a `.vue` file. BeamNG's mod-UI loader unloads and reloads mod UI at
runtime — **this is not a guess; BeamNG.Earth's own `index.js` is built around it**, with a lifecycle queue, an
owner symbol, a 30-second timeout and a retry, under the comment *"The mod loader may overlap async load/unload
calls, including calls from different evaluated copies."* Earth Rally's `index.js` has no such machinery; it
registers on load and unregisters on unload, and that is all.

A Vue SFC's scoped style is injected into the document when its **module is first evaluated**, once. A dynamic
`import()` of a module already in the registry does not evaluate it again. So if our route is torn down and the
style element goes with it, and our page is then mounted again from the cached module, the component renders and
the style never comes back — no error, nothing in the log, which is exactly what is seen: 0 CEF errors on our
route across four visits.

That explains every observation: it works the first time, it breaks only after another mod's route churn, the
game's own components are unaffected (their modules live in the core bundle and are never unloaded), and nothing
anywhere throws.

**What this does not do is name the code that removes the style element.** Searched and ruled out: Earth Rally's
UI never touches the document outside its own component (`grep` for `document.head|querySelector|remove()|
innerHTML|styleSheets` over `mod/earth_rally/ui`: no hits). BeamNG.Earth's does in several places, but each one
removes something it created itself (`earthServers.js` keeps a reference to its own `<style>` and removes that;
`map3dLabels.js` clears its own labels), and neither mod removes style elements wholesale. So on the evidence it
is most likely the game's own teardown, which is what the user suspected first.

### What is needed next

**Both experiments came back clean (the user, 2026-11-14: "both 1 and 2 look fine").** BeamNG.Earth's settings
page is styled; Earth Rally's pause-menu tab is styled. With the user's original report — that the glitch is on
"earths maps and our rally menu" — that completes a two-by-two across two independent mods, and the split falls on
the **mechanism**, not on the mod:

| page | how its component is loaded | result |
|---|---|---|
| BeamNG.Earth's world map (route `beamngEarthMap`) | the mod's own `import("./EarthMap.vue")` | **loses its styles** |
| Earth Rally's menu (route `earthRally`) | the mod's own `import("./EarthRally.vue")` | **loses its styles** |
| BeamNG.Earth's settings (pause tab) | `componentName: ".../EarthSettingsPage.vue"`, the game loads it | fine |
| Earth Rally's rallies (pause tab) | `componentName: ".../EarthRallyTab.vue"`, the game loads it | fine |

Both mods do both things, and in both mods it is the route that breaks and the pause tab that survives. **So this
is BeamNG's own mod-UI behaviour, reached by any mod that registers a full-screen route** — which is the
documented way to have one (the game's `ui/ui-vue/mods/README.md`, "Standalone routes", shows exactly this shape:
the component imported by the mod and passed as `component:`). It is not Earth Rally's doing and not
BeamNG.Earth's. The user said so in the first message — "might not be us, could be a beam issue" — and the
evidence agrees.

There is no documented string-path form for a route's component, so the shape that survives is not available to a
route without changing how the page is loaded.

### What the diagnostic found: not removal, and then not reproducing at all

A probe went into `EarthRally.vue` (`styleCheck`, on every mount) and `index.js` (on load and unload), and the
first reading came back from the bad state — the menu opened straight after BeamNG.Earth's map:

```
49.87  Transition started: beamngEarthMap
54.53  Transition started: earthRally
54.58  style check -- ours in head 1 of 233, css scope none,
                      page attrs [data-v-bng-gjdi3l data-v-bng-1]
```

**`ours in head 1`: the style element had not been removed.** The leading explanation above — our `<style>` taken
out of the document and never re-injected from a cached module — is **wrong**, and the fifteen-line clone fix it
implied would have done nothing. Worth keeping that in view: it was a tidy explanation that fitted every
observation, and it was still wrong.

(`css scope none` in that line was a defect in the probe, not a finding: the regex looked for `[data-v-` followed
by hex, and this build's scope ids are `data-v-bng-gjdi3l` — letters past `f`, a `bng-` prefix and a hyphen. It
was widened, and the probe was changed to ask the browser whether the rules **apply** — `getComputedStyle` of
`.er-page` against the `position: absolute; display: flex` its own first rule sets — rather than to infer it.)

After `reloadUI()`, **it would not reproduce**. Three menu opens, two of them immediately after a map visit:

```
183.13  earthRally   -> applied true,  css scopes [data-v-bng-gjdi50], page attrs [data-v-bng-gjdi50 data-v-bng-1]
185.21  beamngEarthMap
187.74  earthRally   -> applied true,  same ids, matching
188.79  beamngEarthMap
190.74  earthRally   -> applied true,  same ids, matching
```

The user: *"it all worked btw... no more bug"*.

**Nothing was fixed.** The probe only reads the document and prints a line; no behaviour changed between the
broken session and the clean one, beyond a `reloadUI()` and a rebuilt page module. So this is **intermittent and
state-dependent**, not "opening the map breaks it" — which is what the first session's evidence looked like, and
that reading now has to be let go of too. The two sessions differ in how the UI came up: the broken one was the
UI as the game started it, the clean one was the UI after an explicit reload.

**Left in place deliberately:** the probe stays for now, because an intermittent fault that is understood the
moment it next happens is worth one log line when the menu opens. It should come out before 1.3.2 is released. If
it fires again, the line distinguishes the two readings on its own:

* `applied false` with the scopes differing → the mounted page is a different compilation from the stylesheet in
  the document, which is where the two id formats (`data-v-bng-gjdi3l`, a hash, and `data-v-bng-1`, a counter)
  were pointing.
* `applied false` with `ours in head 0` → removal after all, and the clone fix comes back.
* `applied true` while the page still looks bare → the rules land and something else is wrong; start again.

### The reading that still holds

Independent of the mechanism, the two-by-two stands: **both mods' full-screen routes break, both mods' pause tabs
survive**, and that is BeamNG's own mod-route behaviour reached by the documented way of registering a route. The
user said so first.

### The earlier plan, kept for the record

What is inferred, not observed: that our page's `<style>` element has been **removed from the document**. That is
the obvious reading of the screenshot, but a second reading fits it equally well — the style element is still
there and the component's elements have lost the `data-v-…` attribute its rules are scoped to, so nothing matches.
The two want different fixes, and five lines tell them apart:

```js
// in onLoad, after the import
const ours = [...document.head.querySelectorAll("style")].filter(s => s.textContent.includes(".er-"))
console.log("Earth Rally: style elements in head:", ours.length)
```

Run it on a first load and again after Earth's map has been opened. **Count drops to 0** — the element is being
removed, and the fix below works. **Count stays 1** — it is a scope-id mismatch, and the fix below would do
nothing, so stop and think again.

### The fix, if it is removal

Keep the stylesheet ourselves rather than depending on one surviving a teardown we do not control. On first load,
find our style element and keep a clone; on every later load, re-append the clone if it is gone. About fifteen
lines in `index.js`, no CSS rewritten, no change to how the page looks — so no mock-up — and it does not care what
removed the element or why.

The heavier alternative, moving every rule out of `<style scoped>` into a stylesheet the mod owns and injects, is
only worth it if the clone trick fails. `scoped` does real work: its rules only match our own elements, so moving
them out means making every selector specific enough to stand alone.

### Experiments 1 and 2 as they were put (kept for the record)

1. **With the menu already unstyled, open BeamNG.Earth's own settings page.** If that is unstyled too, the loss is
   not about Earth Rally at all and every mod route mounted after the map page has it. If Earth's page is fine and
   only ours is broken, something is specific to our registration and that is ours to fix.
2. **With the menu already unstyled, open the pause menu's Earth Rally tab.** Those are separate components
   (`EarthRallyTab.vue`, `EarthRallySide.vue`) loaded by the game by name rather than by our `import()`. If the tab
   still looks right while the full page does not, the loss is per-module and the hypothesis above holds; if both
   are bare, the whole of our UI mod was reloaded.

### The fix that does not depend on the answer

Whatever is removing it, Earth Rally can stop depending on a style element surviving a teardown it does not
control: move the page's rules out of `<style scoped>` and into a stylesheet the mod owns, injected in `onLoad`
and removed in `onUnload` — the pattern BeamNG.Earth already uses in `earthServers.js`, which keeps a reference to
its own `<style>` and removes exactly that one. Then our page's styling is re-established every time our UI mod
loads, cached module or not, and it cannot be taken away by anyone else's route.

That is a change to how the menu is built rather than to how it looks, so it needs no mock-up — but it is not a
one-liner either (the scoped attribute does real work: `scoped` rules only match our own elements, so moving them
out means every selector has to be made specific enough on its own), and it should not be started until the user
says so.

If instead experiment 1 shows Earth's own pages breaking too, it is **upstream or in BeamNG itself**, and the note
to carry is that it is a UI-loader behaviour BeamNG.Earth already works around in its own `index.js` and Earth
Rally does not.
