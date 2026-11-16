# 1.7.0: the full rally, MVP plan

The owner's design is the full-rally GDD, draft 2, with the four approved MVP mock-ups. Both are kept outside git
with the rally data, because they quote real crews and times. This file records what the MVP builds and the choices
made. Test plan and findings: [`notes-1.7.0.md`](notes-1.7.0.md).

## What the MVP is

- **One rally, start to finish.** The stages run in the event file's order. Road sections are skipped.
- **Services and overnights** come from the event file. Each one fully repairs the car and saves the game. Damage
  carries from stage to stage in between.
- **Two modes**, chosen at the start:
  - **Realistic:** no restarts. Recovering ends the stage under Super Rally, and you rejoin at the next service.
  - **Casual:** recover onto the stage line as often as you like, and restart a stage from its result card.
- **BeamNG's own recovery is off** for the whole rally: resets, recover, reload, teleports and the vehicle menus.
  Backspace is the rally's recovery.
- **The game saves only at the start and at each service.** Quit anywhere else and the car comes back repaired at
  the last service. In Realistic, the stage times since then are kept, and a stage you quit during is scored under
  Super Rally: quitting is no free restart.
- **Places come from the real National field:** stage, overall and class. Finished rallies go on the rally's
  Results tab, with the mode marked.
- **No event file means no full rally.**

## Super Rally (ARA RCR 6.3.1)

A missed stage scores the fastest real National time in your class on that pass. Add 10 min for the first stage
missed in the rally, and 7 min for each one after. Every stage from the recovery to the next service or overnight is
missed.

## Where it lives

| File | What |
|---|---|
| `pack.lua` | `itineraryOf` returns the stops as well: `event.rallyStops`. A service is an `SVC_IN` / `SVC_OUT` row, or a row on a `service` entry's control. An overnight is a change of day. A class's copy of the running order adds nothing. `M.READER`: a pack read by an older reader is imported again, once. |
| `rally.lua` | New and pure: the running order, stage done, recover / Super Rally, Casual restart, service, the loop replayed after a quit, the places, the save's shape. |
| `rallyRun.lua` | New: drives the rally through the runner. Action filter, repair, save file `/earthRally/rallies/<id>.json`, time card data, results card buttons, the Recover? question. |
| `runner.lua` | `start(..., { rally, ssLabel, keepDamage })`. `onFinished` / `onRallyReset` callbacks. Rally times stay out of the stage boards. No reset penalty in a rally. The card waits for an answer. `keepDamage` (below). |
| `hudFrame.lua` | `ours.rally` and `show.recoverAsk` in the stream; `run.rallyKey` in the stream key. |
| `main.lua` | `uiRallyStart`, `uiRallyCard`, `uiRallyAction`. Backspace goes to the rally first. Menu actions are refused during a rally. Cleanup on level end and unload. |
| Vue | `EarthRallyFull.vue` (start screen, time card) and the rally bar on the rally page. The results card has the rally version and the Recover? question. |

## The three in-game checks, answered from the game's own source

1. **Blocking the game's recovery:** `core_input_actionFilter.setGroup` + `addAction(0, group, true)`, as
   `career/career.lua` does. `reset_physics` is not in the game's own `vehicleTeleporting` group, so it is listed
   separately.
2. **BeamNG.Earth's teleport repairs the car:** its `placePlayer` calls `spawn.safeTeleport(..., resetVehicle =
   true)`. During a rally's move to the next stage, `runner.keepDamage` wraps `spawn.safeTeleport` so the player's
   car is set down with `resetVehicle = false`. In a rally it stays on for the whole pass (BeamNG.Earth's fall
   guard and floor check can set the car down again after the start), and is unwrapped when the pass ends. The log
   warns if a stage is placed without the wrapper seeing the set-down. A BeamNG.Earth option to keep the car as it is
   on a teleport would be the cleaner fix.
3. **A full repair in place:** the game's own "Repair here" is `spawn.safeTeleport(veh, veh:getPosition(), facing,
   nil, nil, nil, nil, true)` (`core/recoveryPrompt.lua`).

## Choices made (the owner to confirm)

- **Casual recovery is free.** The +10 s stays in single stages.
- **The class guess uses the drivetrain only:** AWD gives L4WD, anything else L2WD. You can pick any class.
- **No crew of your class on a pass:** Super Rally uses the fastest National time. **No field at all:** 60 km/h
  over the pass's km.
- **Recovering with no service left** ends the rally unclassified.
- **Rally stage times do not go on the single-stage boards.**
- **One rally in progress at a time.** The menu refuses other stages, recces and teleports until you quit it.
- **A reset that gets past the block** (the radial menu, quick access) ends the stage in Realistic. In Casual it is
  free, and a radial reset repairs the car.
- **The Recover? question:** answer it with the buttons, or press Backspace again, at least 1 s later and not with
  a menu up. It goes away after 10 s.
- **Resume needs the same car** the rally was started in.
- **The Results tab's best full rally** is the best Realistic one; a Casual one shows only when there is none.
- **Overall places count the notional times**, as the real classification does. Stage places leave them out.
- **No pad default** for the recovery yet. Bind `Earth Rally: back on the road` in Controls.

## Left for after the MVP

Road sections with target times and lateness, shakedown and recce in the loop, a "damage carried" readout, a restart
from the pause menu, weather per stage, split times, ghost cars.
