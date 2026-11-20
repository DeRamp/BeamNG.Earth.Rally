# Rally loop: test notes (build 1.9.4-alpha+rallyloop, Warden Test Rally)

The owner's first drive, 2026-11-19 (the checklist report). Logged, not fixed: each has the diagnosis, the fix and the
files it touches. Build only when told.

## 1. Time of day and weather never changed (the big one)

Seen: SS1 sunny, not cloudy; SS5 and SS4 (Run them all) sunny; 17:00 at a control and not dark; the Drive stage
Weather row never showed, so Rally day and the picks could not be tried.

Diagnosis: the log says every set worked ("BeamNG.Earth's clock 16:00, weather overcast, 10 C", then rain, clear,
fog, snow in turn), but BeamNG.Earth's own settings (`settings/beamngEarth.json`) have **skyMode and weatherMode both
Manual**. In Manual, BeamNG.Earth stops applying its clock and weather (sky.lua onUpdate and weather.lua's update return
when `mode ~= 'real'`), so the hooks' values sit there unused. The Drive stage row hides itself when the weather is not
live (`earthAdapter.weatherLive`), which is why it never appeared. BeamNG.Earth switches to Manual by itself when
something else changes the time or weather ("Time set to Manual because it was changed"), so a player can be in Manual
without knowing.

Fix: while a rally (or a stage's weather pick) holds the clock or weather, put BeamNG.Earth's sky and weather in Real
with their `setMode('real')` (not saved: it does not touch beamngEarth.json), and put back the mode the player had when
it is given back (kept in our PRESETS entry, like the real weather, so a Lua reload cannot lose it). The Weather row
then shows whenever the hooks are there. Off by the setting "Rally's real time and weather": nothing touched.

Files: `earthAdapter.lua` (setScene / clearScene / weatherLive), `main.lua` (uiStage wxCan), `tests/test_stage_weather.lua`,
a test for the mode kept and given back.

## 2. Traffic On: no traffic on road sections

Seen: no traffic on transits with On; it worked only with traffic turned on from the main menu first.

Diagnosis: On means "leave the world's traffic as it is" (log: "traffic on road sections: the world's own, left as it is
(none running)"). With none running, On gives none.

Fix: On with no traffic running spawns it for the rally (the game's traffic with the player's own amount, as the main
menu's switch does) and takes it away at the end; traffic already running is left as now. Stages still clear it.

Files: `rallyRun.lua` (traffic choice / start / give back), `runner.lua` (the traffic helpers), `tests/test_run.lua`.

## 3. Casual: the car cannot be reset when broken

Diagnosis: the rally blocks BeamNG's reset and recovery actions (`rallyRun.BLOCKED`) in both modes. Casual is meant to
let you carry on.

Fix: in Casual, leave reset_physics and the recover actions open (still block vehicle swap, the parts menu and the fun
actions); Realistic as now.

Files: `rallyRun.lua` (block by mode), `tests/test_run.lua`.

## 4. Started in slow motion, stuck in slow motion

Diagnosis: the rally blocks `slower_motion`, `faster_motion` and `toggle_slow_motion`; started while the game was in
slow motion, the player cannot get out of it.

Fix: set the simulation speed back to normal when the rally starts and when it resumes (the actions stay blocked, so a
rally cannot be driven slowed).

Files: `rallyRun.lua` (start / resume), `tests/test_run.lua`.

## 5. Routed to the wrong side of a time control

Diagnosis (to confirm with the owner: which control): the transit's GPS is aimed at the control's point, and the route
can reach it from beyond the board (the stage side), so the car arrives facing the wrong way and the board check-in or
the stage's approach is off.

Fix: aim the route at a point on the road before the control, back along the stage's approach (the line from the start
back through the ATC), then on to the board.

Files: `rallyRun.lua` (the transit's route target), `runner.lua` (arrivalPoint), a test.

## 6. Settings from the time card goes back to Home

Diagnosis: Back on Settings always goes Home (#39: Drive rally, Drive stage and Settings go back to Home).

Fix: Settings opened from the time card goes back to the time card; from anywhere else, Home as now.

Files: `EarthRally.vue` (back, where Settings was opened from).

## 7. Asked for: the rally's time on a transit

The owner: "Add rally time for transit." The rally clock (the time of day in the rally, e.g. 16:04) leads the road
section's HUD line: `16:04 · due 16:10 · 6:00 left · 1.2 km`. The time card's header already shows the clock, so its
transit banner is unchanged.

Files: `hudFrame.lua` (transitText), `tests/test_hud.lua`.

## 8. Wording: "early · free" reads "on time"

The owner: change "Early - Free" to "On time". The Transit column's word for an early check-in that cost nothing.

Files: `EarthRallyFull.vue` (roadWord).

## Not checked this drive

Skipped on the checklist (most hang on 1): own time and weather back after the rally, the real-world setting Off,
late penalties, no lateness limit, the service out time, the time card's columns, Save and quit then Continue, the
rally's finish and page, cards with the keyboard, Traffic Off, the whole Drive stage Weather row, multiplayer.

## Fixed after review (debugger and contrarian, before drive 2)

- Casual: only the player's reset and recover are open (not "reset all"), and a reset costs the reset penalty, as on
  Drive stage.
- Traffic the rally started is kept in the settings (`rallyTrafficSpawned`), so Save and quit then Continue, or a Lua
  reload, still takes it away at the end. Taken away at once (the game's state otherwise stays "on" a frame, and
  Continue saw it as the world's). Left while it was still spawning: taken away again once it is on.
- Traffic that cannot be started: a short line says so.
- Approach point (5): only where the stage's first 50 m run on the same way as the ATC to the start; round a corner,
  no point, as before.
- Manual weather given back: fog, clouds and wind as the player had them, not the last stage's.
- Settings from the time card: Back still goes to the time card after the menu is closed and opened.

Not acted on:
- The player changing the time mid-rally: the next stop puts BeamNG.Earth back in Real for the rally. Rare; the
  player's mode still comes back at the end.
- A full game Lua reload mid-rally in Manual can give back the rally's hour as the player's time. Edge only.

