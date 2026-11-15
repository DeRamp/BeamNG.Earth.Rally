# Notes for 1.5.2

## 1. Run stage skipped the ATC after Auto recce, Go to start or a stopped Recce

*Built, tested in game by the user (2026-11-14: "that all worked!"), released in 1.5.2-alpha.* **Auto recce teleported to the stage start, and Run stage then
skipped the ATC** (the user, 2026-11-14: "when you press auto recce, it teliports you to the stage start, this means
when you press run stage, you unintentinaly skip the ATC. Instead can autorecce teleport you to the ATC?"). The user
then asked for the root cause and the on-road landing as well ("yes, run as recomended").

**Why it happened.**
- Auto recce of a far stage (`GO_IF_FURTHER_M`, 5 km) teleported to `controls.start`, then `runner.faceStage` set
  the car behind the start line. Go to start and Recce do the same.
- `runner.start` only teleports when the car is more than `TRAVEL_IF_FARTHER_M` (300 m) from the ATC, so
  `run.teleported` stayed false.
- `stepPlace` took any car 15-150 m from the ATC (`DRIVEN_THERE_MIN_M` to `NO_SET_DOWN_M`) for "driven there" and
  left it, wherever it was. With an ATC within about 150 m of the start, the car started on the stage and
  `stepToAtc` counted a missed time control.

**The fix.**
- `runner.lua` `stepPlace`: a car **on the stage** (within `START_ZONE_OFF_M`, 8 m, of the run's line anywhere
  along it; the line keeps at most 30 m before the start) is never "driven there". It is set down 40 m before the
  ATC. Read along the road, so hairpins count. Cars parked on approach roads keep their spot.
  - Where the ATC is itself on the line (under 30 m before the start), only from past its zone, so a car parked
    short of the board is kept. Never later than the start zone (12 m before the line), so an ATC just before the
    start cannot leave a car on the line as "driven there".
  - A first cut used straight-line "nearer the start than the ATC". The reviews found it let a car 30 m into a
    stage with an ATC 20 m before it through, and moved players on approach roads. Replaced.
- `main.lua` `goThenMatch`: Auto recce lands at `runner.arrivalPoint` (the ATC when the stage has one, else the
  start), then `runner.faceAtc` sets the car on the road 40 m before the board, facing it.
  - No road found (the road map can still be the last place's after a teleport): the car is left on the raw ATC
    point. Run stage sets it down later, as it is within 15 m.
  - The landing is logged: `auto recce: landed at the ATC: ...`.
- Tests in `tests/test_run.lua`: cars at -4, +30 and +90 m from the start with an ATC 20 m before it are set down
  and not counted missed (they fail without the guard); cars parked short of a close ATC, and between the ATC and a
  far start, are kept; a car on the start line past an ATC on the line is set down;
  `faceAtc` on and off the road map; the auto recce lands at the ATC, and a stage without an ATC still lands at
  the start.

**Left open.**
- A car between the ATC and the start, more than 30 m before the line, is kept. It is not an instant miss and the
  route arrows point back to the ATC, but driving on to the line from there costs the 60 s missed-control penalty.
- A car more than 8 m off the line is not "on the stage". `faceStage`'s 'turned only' fallback leaves a car on the
  organisers' raw start, which can be up to 60 m off the line. That fallback only runs with no stage line, when Run
  stage has no line either (not confirmed).
- A stage that shares its approach road, or loops back past its ATC: a car parked on the shared road 15-150 m from
  the ATC is set down before the board. Harmless, but the player is moved.
- Go to start (developer panel) still lands at the start. Run stage then sets the car down before the ATC.
- An ATC after the start in the data: the set-down lands 40 m into the stage, facing back. A data problem, older
  than this fix.
- An ATC up to `ATC_MAX_FROM_START_M` (1.5 km) off the line may be outside the downloaded corridor. The landing
  could then hit `WORLD_WAIT_S` (120 s) and stop with "taking long to load". Not seen in game.
- `faceAtc` turns towards the organisers' start; `stepPlace` towards the line's start point. They can pick
  different roads at a junction. Harmless: Run stage keeps the car if it is not on the stage.
