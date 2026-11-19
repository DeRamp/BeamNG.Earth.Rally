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
