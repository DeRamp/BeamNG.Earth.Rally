# The rally loop, timed: plan (1.7.3-alpha+rallyloop)

The 1.7.0 items left on the roadmap, as the owner chose on 2026-11-18. Branch `feature/rally-loop`, worktree
`BeamNG.Earth.Rally-rally-loop`, from `main` at 1.7.3-alpha (8489b23). Mock-ups: `docs/mockups-rally-loop/`.
**Nothing is built until the owner OKs this plan and the mock-ups.**

| | Item | Owner's answer |
|---|---|---|
| 1 | Timed road sections | Real schedule: the rally clock follows the itinerary |
| 2 | Early check-in penalty | A setting, **off by default**, in every mode |
| 3 | Weather and time of day per stage | The rally's **real** weather, on its real date: needs a fork change |
| 4 | Split times | (no question asked: see the choices below) |
| - | Shakedown and recce in the loop | **Not now** (stays on the roadmap) |

## 1. Timed road sections

**What the files hold.** Every ARA event file and the Warden test rally carry, per control: `date`, `first_car`
(the first car's due time, e.g. TC1 18:22), `target_min` on time controls, `lateness_min` on stages (the "bogey") and
`timezone` on the event. Today `pack.itineraryOf` drops all of it. The chain is the ARA rule (RCR 5.3.9, 5.4.4):

> due at the next time control = the stage's start time + its lateness time + the road section's target time.

Checked on SnoDrift: SS1 starts 18:25, lateness 11 min, target to TC2 14 min, so TC2 is due 18:50: the file's own
18:50.

**The rally clock** is the itinerary's: the rally starts at the first control's real `first_car` time, on the real
date, in the event's time zone. The game's time of day *is* the rally clock (item 3), so a night stage runs at night.
- Each road section has a due time at its end, worked out as above from **your** start time, not the first car's.
- A service resets you to the schedule: you leave at its scheduled out time (`SVC_OUT`'s `first_car`), so lateness
  never carries past a service. Service and overnight still take no time to sit through: the clock jumps.
- Loading screens and menus pause the clock (they already pause the game).
- A Realistic recovery to service puts the clock at that service's scheduled out time.

**Late and early.**
- Late: the pack's `lateSPerMin` (ARA: 10 s per minute or part of one), at each time control. Added to the rally
  total as a road penalty, shown on the time card.
- Early: only when the new setting **Early check-in penalty** is on (default off). Off: arrive early and the card
  shows your due minute with a countdown, and you check in at it; **Shift + E / Y** skips the wait. On: you may
  still wait at the board for your minute; checking in before it costs `earlySPerMin` (ARA: 1 min per minute).
- The ATC card gets its **Due** row (the Vue card already has the slot, `L.card.due`; nothing fills it today).
- The start time on the line becomes the due time plus the usual minute, as now.

**Rallies with no target times** (single maps, other packs): road sections stay untimed, as now. Nothing breaks.

**Files:** `pack.lua` (carry `date`, `first_car`, `target_min`, `lateness_min`, `timezone`, the SVC/MTC rows' times),
`rally.lua` (`orderOf` items get `due` / `targetMin` / `latenessMin`; a road-penalty sum in the results),
`rallyRun.lua` (the clock, due times, check-in, `uiCard` rows), `runner.lua` (`todNow` reads the rally clock in a
rally), `settings.lua` (one row), `main.lua` / `loadScreen.lua` (`card.due`), the time card and ATC card Vue, the
HUD transit line. Save format 3 (the rally clock and road penalties saved at service; format-2 saves still load,
untimed). Tests: `test_pack`, `test_rally`, `test_run`, `test_settings`.

## 2. Weather and time of day per stage

Each stage gets the sky and the weather of its real date and time, at its own place.

**Time of day / date.** BeamNG.Earth's `real` sky mode always shows *today*. Setting the time ourselves makes it
switch itself to `manual` and save that in its own settings (fork `sky.lua:382-407`), and setting the game's time
alone does not move BeamNG.Earth's sun. So this needs the fork.

**Weather.** BeamNG.Earth's server only fetches Open-Meteo's *current* weather. Open-Meteo has a free, keyless
historical archive (`archive-api.open-meteo.com`, hourly, back to 1940, a few days behind today) with the same fields.

**Fork change (fork.2, modding API 1.10):** one call, `api.setWorldTime(epoch)` / `api.setWorldTime(nil)`:
- the sky shows that moment (date and time) at the player, running on from it in real time, without switching
  the player's sky setting to manual and without saving anything;
- the weather server fetches that hour from the archive for the player's position (same message as now), and goes
  back to live weather on `nil`;
- `has('worldTime')` so Earth Rally can ask.

**Earth Rally:** at the rally start and after each service, `setWorldTime` to the rally clock; on a stage's load, to
the stage's start. `nil` when the rally ends or is left. Without fork.2: Earth Rally leaves the sky and the weather alone (no
reaching into BeamNG.Earth's internals, which would show today's date anyway), with one line on the start screen
saying so.

**Files:** fork `sky.lua`, `weather.lua`, `server/weather.py`, `server/netfetch.py` (the archive host's policy),
`api.lua`, `ADDONS.md`; Earth Rally `earthAdapter.lua`, `rallyRun.lua`. The fork goes out as `1.10.0-beta.fork.2`
**only when the owner says**, as the last one did. Tests: fork's weather server tests; Earth Rally `test_rally`.

## 3. Split times

- Three splits per stage at a quarter, half and three quarters of the timed distance (start to flying finish).
- Compared with **your best run on that stage** (any mode). Real results have no splits, so the leaderboard stays
  finish times only.
- On the stage: as you pass a split, a card under the stage clock for 5 s: *Split 2 · 3:12.4 · -1.8* (green ahead,
  amber behind, nothing to compare on a first run).
- On the finish card: the three splits and the finish, each with its gap.
- Saved with each run (`splits = {s1, s2, s3}`), so the next run has something to beat. Runs saved before this
  have none: the first new run sets them.

**Files:** `runner.lua` (split points, crossing on `run.along`), `events.lua` (save / best splits), `hudFrame.lua`,
the HUD app. Tests: `test_run`, `test_events`.

## Choices I've made (say if any is wrong)

1. **Maximum lateness** (ARA: 30 min in a day, out of the rally): **dropped entirely** (the owner, 2026-11-18). Not
   enforced and not shown; lateness only costs its penalty.
2. **Regroups and refuels** (`RGC_IN`, `REFUEL`): no stop of their own; their times only feed the due times.
3. **The target time is the real one**, though our GPS route can be a little longer or shorter than the real road
   section. If the owner's drives show targets that can't be made, we add a margin.
4. **Early penalty off** also covers the late side of waiting: with it off, sitting at the board until your minute
   is never late.
5. **Splits** are fixed at quarters, not points from the organisers' maps (they have none).
6. **Without fork.2**, a rally still runs and is still timed; the date, the time of day and the weather are the
   player's own, not the rally's.
7. **Skip the wait** (Shift + E / Y at the board, early penalty off) jumps the clock to your minute, as a service
   does, so you check in on time.
8. Rows further ahead on the time card show "–" until their due time is known; services show their fixed out time.
9. "at night" / "at dusk" on the start screen comes from the sun's height at the start, not from the clock.

**The owner's answers (2026-11-18):** choices OK; the maximum lateness dropped entirely; a split or finish slower
than your best is **amber**, as today's finish card (ahead stays green). Go given. Built on `feature/rally-loop`
only: **nothing goes into `main` until the owner has driven it and says release.**

## Order of work

1. Timed road sections (Earth Rally only). 2. Splits. 3. The fork change and fork.2 build (not released).
4. Earth Rally's use of it. Then `/handoff`, the owner drives, findings in `docs/notes-<next>.md`.

## Build: builders and interfaces

Four builders at once. **Touch only your own files.** Need something from another builder's files? It is in the
interfaces below; if not, write it in your report instead of editing their file. Bug-for-bug: no systems beyond this
plan. Comments in the code's own style (why, not what). Made-up names only in tests and comments.

| Builder | Owns | Items |
|---|---|---|
| **Lua** | `mod/earth_rally/lua/**`, `tests/**` | 1 (all logic), 2 (Earth Rally side), 3 (logic) |
| **Menu** | `mod/earth_rally/ui/ui-vue/mods/earthRally/**` | time card, ATC card, settings row (if not generic), start screen |
| **HUD** | `mod/earth_rally/ui/modules/apps/earthRally/**` | transit line colours, split card, finish card splits |
| **Fork** | `..\beamng.earth-fork-release` on a new branch `world-time` (own worktree `..\beamng.earth-world-time`) | 2 (fork side) |

The mock-ups (`docs/mockups-rally-loop/rally-loop.html`, every screen's note) are the look. Where they differ from
this plan, the plan's owner answers win: **no maximum lateness anywhere; slower than your best is amber.**

### Interfaces

1. **Timed flag.** A rally is *timed* when its event has target times. Untimed rallies behave exactly as today and
   every field below is nil for them.
2. **Time card** (`rallyRun.uiCard()`): `clock = { date = 'Fri 6 Feb', time = '18:41' }`; each row may carry
   `due` ('18:50' or nil until known), `timeIn` ('18:51'), `roadPenaltyS` (number, late/early cost at that control),
   `outAt` (a service's fixed out time, '20:53'); `transit` adds `due` ('18:50'), `leftS` (seconds to due, negative
   when late), `late` (whole minutes late, 0 when not); top level `roadPenaltyS` (the total).
3. **ATC card** (`loadScreen.ui().card`, `kind = 'atc'`): `due` ('18:50'), `result = { kind = 'onTime' | 'late' |
   'early', min = n, penaltyS = n }` once checked in; while waiting for your minute (early penalty off, or on and
   not yet checked in): `wait = { leftS = n, due = '18:50' }` and the first step reads "Stopped at the board". The
   skip: `earthRally_main.uiLoadingSkipWait()` (new; jumps the rally clock to the due minute and checks in on time).
   The keyboard Shift+E / controller Y already route to the start-line skip in Lua; the Lua builder makes the same
   key skip the wait while `wait` is up.
4. **HUD transit line** (hudFrame `ours.rally.transit`): `{ label, due, leftS, distM, late, penaltyS }`. The text
   stays Lua-side as today; the HUD app colours it: `leftS < 60` amber, `late > 0` red.
5. **Splits** (hudFrame): `ours.split = { n = 1..3, timeS, gapS }` for 5 s after each split (`gapS` nil on a first
   run; negative = ahead, green; positive = behind, amber). `finish.splits = [ { n, timeS, gapS } ]` (n = 4 is the
   finish) on the finish card. Progress bar quarter ticks: `ours.splitsAt = { 0.25, 0.5, 0.75 }`.
6. **Setting** `earlyPenalty` (bool, default false), label "Early check-in penalty", help "Checking in before your
   minute costs the rally's early penalty. Off: you wait for your minute." In `settings.lua` SCHEMA / ORDER after
   `resetPenalty`. The Menu builder only adds Vue if the settings page is not generic over SCHEMA.
7. **Start screen** (`rallyRun.startInfo()`): `startsAt = { text = 'Fri 6 Feb 2026, 18:00 local', light = 'night'
   | 'dusk' | 'day' | 'dawn' }` (light from the sun's height at the start place), `worldTime = false` when BeamNG.Earth
   lacks the API (the screen then shows the fork note from the mock-up).
8. **Fork API** (modding API 1.10, `has('worldTime')`): `api.setWorldTime(epoch)` sets the sky to that UTC moment at
   the player and runs on in real time, without changing or saving the player's sky / weather mode; the weather
   server fetches that hour from `archive-api.open-meteo.com` (falling back to Open-Meteo's historical-forecast
   API for the last few days) and keeps it while the world time is set; `api.setWorldTime(nil)` goes back to
   whatever the player had. `api.worldTime()` returns the epoch or nil. Earth Rally reaches it through
   `earthAdapter.setWorldTime(epoch)` / `earthAdapter.hasWorldTime()`.

### Done means

Each builder: touched tests pass (`python tests/run_tests.py test_x ...`, never the two e2e; the fork builder runs
the fork's own weather/sky tests); a short report per item: files and functions changed, what it could not do and
why, anything the others must know. Commits on the branch, each builder its own commits; **no merge into `main`,
no push** (the lead pushes). Then the lead runs `/handoff` over the whole diff.

**Added after the review (the owner, 2026-11-18):** a setting **Rally's real date and weather** (`realWorld`, default
on, after Early check-in penalty). Off: Earth Rally never sets BeamNG.Earth's world time (one it set is given back as
the menu closes), and the start screen shows no fork note.

## Additions (2026-11-19)

Two small additions to this build, as the owner picked them. Mock-ups: `docs/mockups-rally-loop/additions.html`.
**Plan and mock-ups only: nothing is built until the owner OKs them.** The owner's rules still apply: no maximum
lateness anywhere; slower than your best is amber; the early penalty is off by default.

### A. Results show it all

**What the player sees.**
- **Results tab, a finished timed rally.** The "Your full rally" strip above the results grows a second line: one
  chip per stage (`SS1 6:48.2`), with the road penalty taken getting to that stage's time control after its time, in
  amber (`+20 s`). A stop where you were late (a service, the finish) gets a chip of its own (`Service A +20 s`). The
  first line adds `incl. road penalties +1:10` after the total; with none, `no road penalties` in green.
- **Stage page.** In Your runs, under the BEST box, a **Best splits** row: 1/4, 1/2, 3/4 and Finish of your fastest
  run with splits on the line the stage runs on now, and where it came from (`your run of 14 Nov` or `a full-rally
  pass, 16 Nov`). Each run in the list with splits on that line gets a second, smaller line: its four times, each
  with its gap to the best splits (ahead green, slower amber, none on the best run itself).
- Untimed rallies, finished rallies saved before this, and runs with no splits look exactly as today.

**The logic.**
- `rally.finished(r)` keeps, per pass, `roadS` (its `r.road[ss].penaltyS`, nil when none), and `stops = { { label,
  inType, min, penaltyS } }` for each stop checked in at a cost (addition B). `roadPenaltyS` is already there.
- `rallyRun.resultsFor(id)` passes the best finished rally's `passes`, `stops` and `roadPenaltyS` through to the page
  (`main.lua`'s `rallyFinished` is already filled from it).
- `menu.stageBase`: `bestSplits = events.bestSplits(e.id, s.id, info.key)`, `info = events.stageLineInfo(...)`; nil
  when the stage has no line. `events.bestSplits` also returns the run's `date`, and `rally = true` for a rally pass.
  Each run in `runs` gets `splits = { { timeS, gapS }... }` (four: s1, s2, s3 and the finish, its `timeS`) only when
  it has three splits and its `lineKey` is the current line's; `gapS` against `bestSplits` (nil on the best run).

**Files / functions.** `rally.lua` (`finished`), `rallyRun.lua` (`resultsFor`), `events.lua` (`bestSplits`: date,
rally), `menu.lua` (`stageBase`: `bestSplits`, `runs[k].splits`), `EarthRally.vue` (the full-rally strip's chips;
Your runs' Best splits and each run's split line).

**Tests.** `test_rally` (finished: `roadS` per pass, `stops`, an untimed rally unchanged); `test_menu_rally_files`
(best splits on the current line only, date and rally flag, gaps signed, no line: none, a run on another line: no
splits).

**Choices I've made.**
1. **Best splits are one run's**, the fastest with splits on the current line: the one the HUD compares with. Not the
   best of each quarter from different runs (that time was never driven).
2. A run on an earlier line shows its time as today but **no splits**: a quarter of another line is another place.
3. The best splits may come from a **full-rally pass**, which is never in Your runs: the row says so.
4. Road penalties go on the **full rally's** strip only: the "Your rally" card beside the real top 10 is built from
   single-stage bests, which have no road sections.
5. A stop gets a chip **only when it cost something**; an on-time or free early check-in adds none.

### B. Time controls complete

**What the event files hold** (the made-up Warden test rally's shape): after a stage, the road section runs to the
next "in" control; each row has `target_min` (from the row before) and `first_car`.
- `SVC_IN` (target 6 after SS1) → `SVC_OUT` (its target is the service's length) → ATC.
- `RGC_IN` (5) → `RGC_OUT` (the regroup's length; "Regroup Out / Service In") → `SVC_OUT` → next day `MTC_OUT`.
- The last stage → `MTC_IN` (6: the finish).
- `time_rules.early_checkin_allowed: ["MTC_IN", "RGC_IN"]`.

Today `itineraryOf` adds every target between two passes into the next pass's `targetMin` and keeps the last out row
(`outAt`, `outTargetMin`); a stop has only its out time (`outT`). Nothing is due at a stop: `arrive()` repairs, saves
and opens the card; `transitDueNow` returns nil while `toStop`; `uiCard` shows `–` on every row whose due is not
known, and no Due / In / Road on stops.

**What the player sees.**
- **Driving to a service, a regroup or the finish:** the HUD's transit line and the time card's banner get the due
  time and the time left, as on the way to an ATC (amber under a minute, red when late).
- **Arriving** (stopped at its board): the time card opens as now; its stop card carries the check-in: Time in, Due,
  Result (`On time` / `2 min late · +20 s` / `3 min early · no penalty`) and Out (the scheduled out time the clock
  jumps to). A regroup or the finish says `early check-in allowed`.
- **The time card:** stop rows get Due / In / Road like stage rows. A row whose due isn't known yet shows its road
  section's target instead of `–`: `target 14 min`, dim. Rows the schedule fixes (after a stop's out time) keep their
  due time, as now.
- Road penalties at stops go into the same total, the overall standing and the finished rally.

**The logic.**
- **`pack.itineraryOf`:** in each stretch after a pass, the first row of type `SVC_IN`, `RGC_IN`, `MTC_IN` or `PF_IN`
  is its check-in, carried on the next pass as `inType` and `inTargetMin` (the targets from the pass up to and
  including that row; a lateness of a pass with no line counted in, as for `targetMin`). The stretch after the last
  pass goes in `timing.finish = { inType, inTargetMin }`. In the stops loop each stop takes `inType` / `inTargetMin`
  from `out[st.after + 1]`, as it takes `outAt` now. `timing.earlyFree = { MTC_IN = true, RGC_IN = true }` from
  `time_rules.early_checkin_allowed` (strings: `rulesOf` reads numbers only, so it is read beside it).
- **`rally.orderOf`:** a stop item gets `inType` and `inTargetMin` (+ `carry` from passes left out before it, as a
  stage's `targetMin` does); the final stop gets `timing.finish`'s. `rally.new` keeps `r.earlyFree`. `holdOut`: a
  stage taken out right before a stop adds its target and lateness to the stop's `inTargetMin`; two stops merged keep
  the first one's in (the one driven into).
- **`rally.dueFor(r, i)`** for a stop: `lastOut + inTargetMin` (to the minute), nil without either. Only the stop
  right after the stage just done has one: a stage's time out is never known in advance.
- **`rally.checkIn(r, item, inT, dueT, earlyPenalty, key)`:** key = the stage's `ss`, or `'stop' .. i` for a stop
  (its place in `r.order`, as `serviced` keys it). Late: `lateSPerMin`, as at an ATC. Early: free when
  `r.earlyFree[item.inType]`, else as at an ATC (the setting). The entry keeps `inType`.
- **`rallyRun`:** `dueAt(i)` answers for the current stop too; `transitDueNow` also runs while driving to a stop
  (`toStop`), labelled with the stop. `arrive(driven)`: driven in (stopped at the board, or near it from the time
  card's button) with a due known, `M.checkIn` before `save()`, so the save at the service holds it; the final stop
  checks in before `finish()`. A teleport (a Realistic recovery, a stop with no place, a move) checks nothing in. No
  wait at a stop: the clock jumps to the out time anyway; with the early penalty on, you wait short of the board, as
  crews wait outside a control.
- **`uiCard`:** stop rows read `R.road['stop' .. i]` for `due` / `timeIn` / `roadPenaltyS` / `roadKind`, else
  `due = dueAt(i)`. A row with no due, not done: `targetMin` (a stage: its `targetMin`, or `outTargetMin` after a
  stop; a stop: `inTargetMin`). At a stop, `at.checkIn = { inType, due, timeIn, kind, min, penaltyS, free, outAt }`.
  The transit block works for `toStop` as for a stage.
- **Save:** still format 3. A rally saved before this goes on as it was: its stops have no `inTargetMin`, so nothing
  is due at them.

**Files / functions.** `pack.lua` (`itineraryOf`, its stops loop), `rally.lua` (`orderOf`, `new`, `holdOut`,
`dueFor`, `checkIn`, `finished`), `rallyRun.lua` (`dueAt`, `transitDueNow`, `arrive`, `goNext`'s near-arrival,
`uiCard`), `EarthRallyFull.vue` (stop rows, `target N min` in a wider Due column, the stop card's check-in, the `toStop`
banner). The HUD
app needs nothing: `hudFrame` already shows whatever `transitDue` gives.

**Tests.** `test_pack` (a made-up itinerary in the Warden shape: the service-in's 6, the regroup-in's 5 before an
overnight, the finish's 6, `earlyFree`; a pass with no line before a stop); `test_rally` (`orderOf` with a cancelled
pass before a stop; `dueFor` for a stop; `checkIn` late at a service, early free at a regroup and at the finish,
early at a service with the setting on and off; `holdOut` before a stop); `test_run` (arriving driven checks in and
saves it; a recovery doesn't; the final service checks in before finishing; `uiCard` stop rows, `targetMin`,
`at.checkIn`).

**Choices I've made.**
1. **One check-in per stop:** the first "in" control after the stage. A regroup right before a service (the Warden
   shape) is checked at the regroup, early free; the service-in after it is not timed again.
2. **A regroup on its own** (no service or overnight next to it) stays inside the road section, as today: no stop on
   the map. Its time is in the next ATC's target, so lateness there costs the same, once, at the ATC.
3. **Early at a service-in** follows the early-penalty setting: off (the default), `3 min early · no penalty`; on,
   1 min a minute. No wait card at a stop: with the penalty on, you wait short of the board.
4. **No check-in without driving in:** a Realistic recovery, a stop with no place on the map, or a teleport leaves the
   row blank, as today.
5. **`target 14 min`** is the road section's target from the control before it; rows whose due the schedule fixes
   keep the due time.
6. **No maximum lateness**, here as everywhere: lateness at a stop only costs its penalty.

### C. Controller on the HUD cards

(The owner, 2026-11-19: "controller support doesn't work on the pop-up menus"; no mock-up, the cards are unchanged.)
While a card is up and showing ("Load the stage?", Recover?, the finish card), a Lua action map takes A / Enter (ok),
B (back), the d-pad / arrows / left stick (move), and the game's own actions on those buttons are filtered out until
they are up again (`cardInput.lua`).
- **Xbox-type pads only.** A PlayStation pad over DirectInput, or a wheel, gets nothing on the cards (the mouse still
  works). The reason: BeamNG 0.40.6 hosts HUD apps with no UI nav (its `AppHost.vue` sets `bng-no-child-nav`), so a
  card cannot use the game's own menu navigation, which knows every device; our map binds the xinput pad and the
  keyboard only.

### D. Traffic on road sections

(The owner, 2026-11-19: "an option that lets you enable traffic or not before you start a rally ... just for during
transits". No mock-up: the owner specified it.) The start screen's Rally settings get **Traffic on road sections:
On / Off**.
- **On:** the world's traffic is left exactly as it is on the road sections and at the stops. BeamNG.Earth spawns
  its own regional traffic and spawns it again as the region changes; the mod never sets up the game's stock traffic
  (the wrong cars, and a hitch). A world started without traffic has none: the start screen then says "This world
  has no traffic. Start BeamNG.Earth with traffic on to have it on road sections."
- **Off:** traffic held at 0 for the whole rally, the player's amount given back when the rally ends or is left. The
  amount is kept in the settings meanwhile, so a Lua reload does not lose it.
- **Each stage** is closed to traffic either way, as before.
- **Default:** the player's last pick; before any, the world's (On when its traffic is running). A save from before
  this leaves the world's traffic alone.

**Known, from the last review:** the card takes the pad whenever it is up, even when the game refused its pause; then
the parking brake, shift up, look back and reset are off while the card is up, and the arrows / left stick move the
card's pick as well as steering. After a walk-mode recce in a rally's prep, a stop with no place on the map is run where
the last recce window left the car (no ARA stop is like that).

## E. Weather and time of day on the official BeamNG.Earth (plan, 2026-11-19, awaiting the owner's go)

The owner, 2026-11-19: "We're trying to officially not use anything with my fork of Earth anymore. I want to just
be using the main fork of Earth from now on." And: the weather is stored in the pack, never fetched as a stage loads.
This replaces item 2's fork API (`api.setWorldTime`, the `world-time` branch of the fork: abandoned, not released).

**How, on the official BeamNG.Earth (checked on 1.10.1-beta).** Two hooks it keeps for BeamMP servers (the server's
clock and weather for everyone, `mpsession.lua:482-483`). Neither switches the player's sky / weather setting to
Manual, saves anything or shows a toast; nil gives back what the player had:
- `beamngEarth_sky.setServerClock({ hours, speed = 1, epoch })`: the local hour shown, run on in real time.
- `beamngEarth_weather.setPreset(name)`: a weather message held, live reports ignored while it is. The messages are a
  plain table, `beamngEarth_weather.PRESETS`, so Earth Rally adds its own entry (`earthRally`) holding the stage's
  stored weather and picks it.
These are not modding API: a BeamNG.Earth update can rename them. `earthAdapter` checks both are there; if either is
missing, one log line, and the rally runs on the player's own sky and weather. In a BeamMP session (a server clock
already set by someone else) Earth Rally leaves them alone.

**The limit:** the clock hook sets the hour, not the date. The sun is where it is *today* at that hour, not on the
rally's day (a February rally driven in November: sunset up to ~40 min off). The weather is the real day's.

**Weather in the pack.** A tool, `tools/pack_weather.py <pack folder>`, run once when a pack is made:
- for each SS row of each event file: the hour of its start (`date` + `first_car`, the event's `timezone`) at the
  stage's start point (the map's line), from Open-Meteo's historical archive (`archive-api.open-meteo.com`, keyless;
  the historical forecast API for the last few days before today);
- writes `weather` on that row, in BeamNG.Earth's own message shape (`code, cover{low,mid,high}, wind{ms,gustMs,
  fromDeg}, visM, rainMmH, snowCmH, slTempC, fog`), worked out the way its server does (`server/weather.py derive`,
  MIT, credited), plus `weather_source` on the event ("Open-Meteo.com, archive, fetched <date>");
- a rally still in the future: nothing written (the tool says so), and in game that rally keeps the player's weather;
- `--force` to fetch again; otherwise rows that have weather are left alone.
Run on the Warden and ARA packs (they stay out of git, as all rally data). `docs/rally-file.md` gets the field.

**In game:**
- `pack.itineraryOf` carries `weather` per pass; the order's stages keep it.
- At each stage's load and at the start / out of each stop: the clock hook to the rally clock's local hour; the weather
  to the next stage's stored weather (the road section before a stage has that stage's weather; service the next).
- Re-set as now on unpause and on drift (the hook's clock runs on wall time, not game time).
- Given back (clock nil, preset nil, our table entry removed) at the end, on leave, on quit, and at load if left set.
- The setting "Rally's real date and weather" becomes **"Rally's real time and weather"** (default on).
- Start screen: the fork note goes. Instead, only when it applies: "This rally has no stored weather: your own weather"
  or "Your BeamNG.Earth can't set the rally's time and weather." (2026-11-19: no source line under the start time either; the UI as minimal as it can be).
- The fork code goes: `earthAdapter.setWorldTime / hasWorldTime / worldTime`, `KNOWN_API_MINOR` back to main's.

**Optional, needs a mock-up first:** each stage's weather in a word on the time card ("SS2 · overcast, 15 °C").

**Files:** new `tools/pack_weather.py` + `tests/test_pack_weather.py` (offline, a made-up archive response); `pack.lua`,
`rally.lua`, `rallyRun.lua` (setWorld → the hooks), `earthAdapter.lua`, `settings.lua`, `EarthRallyFull.vue` (note
text), `docs/rally-file.md`, `docs/plan-rally-loop.md`. Tests: test_pack, test_rally, test_run.

**The owner's go on E (2026-11-19), with the optional time card weather** (mock-up first:
`docs/mockups-rally-loop/weather.html`).

**Built 2026-11-19** (feature/rally-loop): `tools/pack_weather.py`, the field in `docs/rally-file.md`, the Lua side
(`earthAdapter.hasSceneHooks / setScene / clearScene`, PRESETS entry `earthrally`: BeamNG.Earth looks preset names up
lower-cased), the start screen's two notes. The data for the time card's word is there (`rows[i].weather`,
`transit.weather`); its UI waits for the mock-up. Known limit: BeamNG.Earth's `setPreset(nil)` keeps the rally's weather
showing until its next real weather message (it refreshes every 10 min).
The time card's word built 2026-11-19 (`EarthRallyFull.vue`: each stage row, the transit banner's second line).

## F. Earth Rally off in multiplayer (the owner, 2026-11-19)

"Earth Rally should disable when multiplayer is enabled anyway, as this is a very multiplayer unfriendly mod."
- In a BeamMP session (`MPCoreNetwork.isMPSession()`, as BeamNG.Earth's own `beammp.inSession` reads it; checked on
  start, each level start, and about once a second), Earth Rally does nothing: no stage or rally starts, a stage under
  way is stopped and a rally under way is left as Save and quit leaves it (resumable later), the HUD apps show nothing,
  no input map or action filter is pushed, BeamNG.Earth's clock / weather hooks are never touched, and traffic is
  given back.
- The menu opens on one card: "Earth Rally is off in multiplayer" (mock-up with E's). The pause menu's Rally menu
  button opens the same.
- One log line each way ("multiplayer session: Earth Rally off" / "on again").
Files: `main.lua` (a `multiplayer()` check gating start paths and the update), `rallyRun.lua` (leave), `runner.lua`
(stop), `menu.lua`/`uiState` (`multiplayer = true`), the menu Vue (after the mock-up). Tests: test_run.

**Built 2026-11-19** (Lua side): `main.mpCheck` / `main.multiplayer()`, `earthAdapter.inMultiplayer`, `uiState().multiplayer`.
The menu's one card built 2026-11-19 (`EarthRally.vue`: every page, Close or B shuts the menu).
