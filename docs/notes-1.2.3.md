# Earth Rally 1.2.3: notes from testing 1.2.2

Items the user reported while testing 1.2.2. Both are built (mock-up agreed first:
docs/mockups-1.2.3/hud.html).

1. **The progress meter sat too low.** *Built.* The stage clock, the progress meter and the km readout moved from
   `top: 64px` to the top of the screen, where the 1.2.0 mock-up had them. Three places had to move together: the
   layout file, and the hard-coded `.er-km` and `.er-offroute` in app.earthRallyHud.vue.
   - With it: BeamNG.Earth's place-name strip is switched off for the stage and back afterwards
     (`earthAdapter.setStatusBar`, from the runner's layoutOn / layoutOff, and again when the mod loads in case a run
     was cut short). Its own flag, not the player's setting, which would be saved over.

2. **The grey-out over the stage notes.** *Built: removed.* It was a plain box the size of the pacenote app's whole
   slot (1440x216) while the cards fill about a fifth of it, so most of it dimmed the scenery. The approved 1.2.0
   mock-up never had one. `show.dimNotes` is gone from hudFrame.lua, with the element, its CSS, and the assertions in
   selftest.lua and tests/test_hud.lua.

## Still open from 1.2.2

- The blank start board after a new start minute (roadmap 7): never built.
- The 1.2.1 release notes still name the on-stage display as a known issue. It was the dev install script, not the
  release zip: to correct.

## Found by the self-test (2026-11-13, desktop)

- **The game's AI can drive a BeamNG.Earth stage, but only just.** `ai.driveUsingPath` with a `script` keeps its
  route in a private graph installed by `mapmgr.setCustomMap()`, and BeamNG.Earth's navgraph.lua:535 broadcasts
  `be:queueAllObjectLua('mapmgr.requestMap()')` to every vehicle whenever it streams new roads, which replaces that
  graph. On top of that the game builds the scripted path with a corridor the width of the car itself
  (`arg.script[i].r or obj:getInitialWidth()`, about 2 m). With both against it the car drove in straight lines off
  the stage, and forwards and backwards, never passing 1.7 km of 4.1.
  Giving the path an `r` of 5 m fixed it: a full pass, 23/23 checks, co-driver included (40 notes called).
  But it finished in 8.6 minutes having used 6 rescues, 7 resets and strayed 229 m from the line: it passes, propped
  up, and not the same way twice.
- **Walking the car along the line instead** (teleported frame by frame) is 3.5 minutes, the same every run, and
  passes 22 of 23 — but **the co-driver stays silent** (0 of 32 notes), which the user spotted while watching: the
  game's call timing is speed-scaled and a teleported car has no speed. It also makes BeamNG.Earth stream hard
  (372 frame hitches against the driven run's 0).
  Still to settle: whether a stepped car can be given enough motion for the notes to play.
