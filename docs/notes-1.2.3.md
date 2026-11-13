# Earth Rally 1.2.3: notes from testing 1.2.2

Items the user reports while testing 1.2.2, to build into 1.2.3. Logged only: no changes until the user says so.
UI items get a mock-up before any code.

1. **The progress meter sits too low.** It should be closer to the top of the screen.
   - With it: while a stage is running, the upper part of BeamNG.Earth's own UI should be turned off temporarily, so
     the two do not stack up. Back as it was when the stage ends.

2. **The grey-out for the stage notes is just a big rectangle.** It reads as a block of flat grey rather than as the
   notes being dimmed. The user's suggestion: get rid of it. (It is `show.dimNotes`, set while off route —
   hudFrame.lua sets the flag, the Vue side draws it.)

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
