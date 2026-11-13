# Earth Rally 1.2.4: notes from testing 1.2.3

Items the user reports while testing 1.2.3, to build into 1.2.4. Logged only: no changes until the user says so.
UI items get a mock-up before any code.

1. **The rally block belongs in the top left corner.** The card shown before a stage (the rally clock, the stage, the
   ATC and its distance: `.er-next` in app.earthRallyHud.vue) is centred at `top: 82px`. It should sit in the top
   left corner, hard against the edge, as the stage clock and progress meter now do.
   - Mocked up and agreed in principle: docs/mockups-1.2.3/hud.html, the "Before the stage" moment.

2. **BeamNG.Earth's banner lands across the rally information.** Its warning line ("Server OK - some internet data
   sources not answering: basemap.nationalmap.gov unreachable") is centred at `top: 36px`, over the rally apps.
   Not to be hidden: it says the stage may be running on incomplete map data, which is worth knowing mid-rally.
   Move it directly under the rally block in the top left (`beamngEarthBanner` in earthRallyStage.uilayout.json).
   - In the same mock-up, with a toggle for it.

3. **The yellow warning boards before the ATC stand off to the right of the road, not either side of it**
   (Maryhill Up). Each site's props are set out from the road's middle and half width
   (`props.lua`, `placeAlong` / `spawn`), and where the road map has no road there the site falls back to a straight
   line from the organisers' point, which can be metres off the road. The run's own log said exactly that:
   `props: atc put down (8 objects, 0 placed by the road map, no road on the map there: straight from the control)`.
   So the likely fix is at the ATC site, not in the board spacing: find the road for it the way the start and finish
   do (they follow the stage line, which is on the road), rather than from the control's own point.

4. **The "checked in / your start time" card is in the way of the skip-the-wait prompt** (right bumper + Y on a pad).
   `.er-timecard` is centred at `top: 318px`; the game's own prompt for Interact lands under or behind it. Either
   move the card or leave that strip of screen free while the prompt is up.

## Carried over, still open

- The blank start board after a new start minute (roadmap 7): never built.
- The 1.2.1 release notes still name the on-stage display as a known issue. It was the dev install script, not the
  release zip: to correct.
