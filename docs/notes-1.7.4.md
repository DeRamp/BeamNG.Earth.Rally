# 1.7.4 notes: play from the main menu

Branch `feature/main-menu`, build `1.7.3-alpha+mainmenu` (c8c1088). An Earth Rally tile on Play > Rally; BeamNG.Earth
loads when a stage is driven or a rally started; the rally's car picked in the game's vehicle picker
(`docs/mockups-1.7.3+mainmenu/car.html`). Driven by the owner 2026-11-18, started from the main menu.

## Findings (logged, not fixed)

### 1. Drive from the main menu hung on "Loading BeamNG.Earth" until Escape

The owner: "it got stuck on loading into a rally. I pressed escape and it finished loading in ... I waited for a
while."

From `beamng.log` (Drive stage, OTR 2024 Final, SS4 Maryhill Up):

- 54.4 s: the level load starts. `startFreeroamByName` runs the whole load inside our call, so our own log line
  "from the menu: loading BeamNG.Earth" only appears at 58.0 s, after the level is already loaded.
- 58.0 s: `loadWorldThen` puts our page up at once (`showLoading`: `M.openMenu()`), under the game's own loading
  screen, which is still up.
- 60.2 s: the game hides its loading screen. Our page is already the UI state, so `menuOpen` stays true.
- 144.0 s: "Loading BeamNG.Earth done after 83.7 s". This came only after the owner's Escape.

**Diagnosis.** `updateWorldWait` counts the 2 s settle only once `w.shown` is set. It sets `w.shown` only on reopening
the page, which needs `not menuOpen and lastUi == 'play'`. Our page was never closed, so neither condition was ever
true and the wait stalled with the world up. Escape went to `pause` and back to `play`, which closed and reopened
the page, set `w.shown`, and the stage ran 2 s later.

**Fix (for the owner's go):** in `updateWorldWait`, once `inWorld`, also set `w.shown` when the page is already up
and the game's loading screen has gone. Two candidate checks:

- `core_gamestate`'s loading status;
- the "loading screen is unloaded" point.

Keep the reopen on `play` for when the page was closed. Test: the page up throughout (no `play` change), and the
stage runs.

**Fixed** (the owner's go, 2026-11-18): once BeamNG.Earth is in its world and the game's loading screen has gone
(`core_gamestate.loading()` false), the wait counts the page as shown if it is already up. If the game left the UI
on `play`, the page is put back. Test: `test_run`, "the page up the whole time".

### 2. The Rally page tile's picture

The owner wanted it "more obviously Earth Rally". It is now the GitHub social preview (the jump shot with the
EARTH RALLY wordmark), cut to 16:9 at 960x540. Source: `Earth Rally marketing/social/github-social-preview.jpg`.

### 3. Home has to be scrolled

The owner: "When I open up the menu, I have to scroll on that main page on Earth Rally Home."

**Diagnosis.** `.er-hm` (EarthRallyHomeMenu.vue) is `height: 100%; min-height: 640px` of the scrolling content box
(`.er-content`, `overflow-y: auto`). Anything above it adds to that height. From the main menu the new note line
("BeamNG.Earth loads when you drive a stage or start a rally.") sits above it, so the page is taller than the screen
by that line. On a small or scaled screen the 640px floor and the 76px heading add more.

**Fix (for the owner's go):** Home's content becomes a column (`display: flex; flex-direction: column`), and the
grid takes what is left (`flex: 1; min-height: 0`), with no 640px floor. Headings go 76 → 68px and 56 → 50px, and
tile padding gets a little tighter. Files: `EarthRallyHomeMenu.vue`, and `EarthRally.vue` for the Home content class.
Mock-up: `docs/mockups-1.7.3+mainmenu/home.html`.

### 4. Drive rally and Drive stage tiles: in-game pictures with cars

The owner: "can you make these in-game pictures, please? I want to see cars on here. Make it make sense."

**Now:** the two tiles are placeholder SVG drawings (a gradient and a route line).

**Fix (for the owner's go):** two in-game shots of the rally car, shipped in the mod as jpgs and shown with
`object-fit: cover` under the same dark fade:

- Drive rally: rally day. The car past the spectator tape and fencing at Weaver Bend, dust behind it
  (`marketing/social/post-weaver-bend-16x9.jpg`).
- Drive stage: one car on one stage road, the hero shot (`marketing/social/square-01-hero-1x1.jpg`, cropped above
  its wordmark).

Files: `EarthRallyHomeMenu.vue`, plus `ui/modules/apps/earthRally/home-rally.jpg` and `home-stage.jpg`.

### 5. The Rally page tile: the name big, the car on the left

The owner likes the picture, but the words are small and low; the tile shows as a small thumbnail, so small text and
detail are lost. Wanted: the car in the air on the left, the name in big type on the right, and it reads
"earth.rally", in line with BeamNG.drive and BeamNG.Earth.

**Fix (for the owner's go):** a new `ui/modules/apps/earthRally/tile.jpg` (960x540), from the clean jump shot
(`marketing/samples/picture-02-jump-sunrise-1080p.jpg`, no wordmark): the car on the left, the right side darkened,
and the name stacked in two lines, white then orange (`EARTH` / `.RALLY`, Segoe UI Black). Two cases to pick from:
`docs/mockups-1.7.3+mainmenu/tile-a.jpg` (capitals) and `tile-b.jpg` (lower case), with `-thumb.png` at 240x135.
Only the picture changes; the tile's name stays "Earth Rally".
