# Earth Rally: player guide

Everything the [README](../README.md) leaves out. What changed in each version: [CHANGELOG](../CHANGELOG.md).

## The auto recce and BeamNG.Earth

The auto recce works a stage's driving line out from BeamNG.Earth's roads so you never have to drive a recce. It
needs **modding API 1.9**, which is [one pull request waiting on TecnaGamer](https://github.com/TecnaGamer/BeamNG.Earth/pull/1249).
Until an official release has it, install BeamNG.Earth from
**[the DeRamp fork](https://github.com/DeRamp/BeamNG.Earth/releases)**: BeamNG.Earth with that change added, with the same kind of
installer. Report problems with the fork to [Earth Rally's issues](https://github.com/DeRamp/BeamNG.Earth.Rally/issues),
not to the BeamNG.Earth team.

**With a stock BeamNG.Earth nothing breaks.** Earth Rally asks, gets no for an answer, and greys out **Auto
recce** with a note saying why — you drive a recce instead, as you always could. That is the only thing you lose.

## Getting a stage to drive

1. **Add a rally.** In the menu, **Open folder**, and drop in the rally's `.kml`, `.kmz` or `.gpx`. It is
   imported straight away. Each line becomes a stage; named points beside it become its controls.
2. **Give the stage a line**, which is what the pacenotes and the timing follow. Either:
   * **Auto recce** — one button. It works out whether BeamNG.Earth has the map data along the stage, tells you how
     much there is to download and asks first; takes you to the start; then works the line out from the roads
     there. A 4 km stage takes about a second and a half. Say **Not now** and it stops, having downloaded nothing
     and moved nobody.
   * **Recce** — drive the stage once at your own pace. The map line is drawn on the road ahead of you (orange, with
     a green ball at the flying finish) and the mod records the line you actually drove.

   Once a stage has a line, **Auto recce** becomes **Reset**, which removes it so you can make it again. A line you
   *drove* is confirmed first — that one cannot be remade in a second and a half.
3. **Drive stage.** Or **Route to start** to drive there yourself instead of being put there.

Where the map genuinely has no road, the organisers' line is used, no notes are called there, and the stage says a
recce would be better.

## Seasons, rallies and leaderboards

The menu goes **Rallies > a season > a rally > a stage**. A single map you drop in is a rally of its own; a **rally
pack** can carry a whole season. A pack is a folder (or a `.zip` of one) in the import folder, with a `season.json`,
`rally.json` or `stage.json` at its top, and it can bring along:

* **Cover pictures and logos** for the menu.
* **The itinerary**: which stages run when, so a stage run twice shows as one row, *SS2 · SS4*.
* **Real results.** Every stage gets a **leaderboard** of the real crews' times, and you are placed among them:
  the top 10, and below that the crew just ahead of you, you, and the crew just behind. A rally's **Results** tab
  adds your best on each stage up into a rally total and ranks it against the crews who finished.
* **Rules**: penalties for a false start, and for arriving late or early at a control.
* **Season standings**, worked out from each rally's finishing order (25, 20, 16, 13, 11 … points by default).

Times only count on a leaderboard when your line is the real stage. A line more than 5 % off the official
distance, start to flying finish, still keeps your times under **Your runs**, but they are not placed. The format
is written down in [`docs/rally-file.md`](rally-file.md), and everything in it is optional, so a pack with
only maps in it works too.

## A stage, start to finish

* The mod takes you to just before the **arrival time control**, and moves BeamNG.Earth's world origin to the middle
  of the stage so the ground does not shift under you (stages up to ~26 km across).
* Traffic and parked cars are cleared for the stage, and put back after.
* Route arrows lead to each control. In a control's zone the brakes ease in as you reach the board, so you can roll
  up to the boards and tent.
* At the ATC you get your **start time** on the rally clock. Driving past it is a missed control (+60 s). Where
  the map has no ATC you are set down short of the line instead, and nothing starts until you drive up to it and
  stop -- so you can wait for the world to finish loading.
* On the line you are held until GO, launch control on where the car has it, with the start tree, the countdown and
  the co-driver's *30 seconds… good luck… 5-4-3-2-1*. Early? **Shift + E** while stopped on the line skips to 6 s
  before your start. Jumping the start is +10 s; arriving late is +10 s a minute.
* On the stage: the stage clock, the distance done, the pacenote cards, and an **OFF ROUTE** warning with the way
  back if you leave the line. Each reset costs 10 s (a setting).
* The clock stops at the **flying finish**; drive on to the **stop control** for the results card — your time, each
  penalty, your best, and **Next stage**.

**Pacenotes** come from the stage's line, voiced by the game's own co-driver: every corner with its number and
length, *hairpin*, *square*, *tightens* / *opens*, *chicane*, long sweepers, and a *caution* where a corner comes up
faster than it looks. Crests are called where the driver cannot see the road ahead — not wherever the grade changes
— with *down* at the top of a downhill from flat road, and *jump*, *dip*, *up* / *down* from the heights. With an
auto recce, junctions are called too — *at junction*, *past junction*, *keep left / right* — and *over bridge*
where the line has its bridges (the in-game recce cannot see them; `tools/auto_recce.py --bridges-only` adds
BeamNG.Earth's own). A casual co-driver voice hears only what it can say. All of it, and the figures behind it:
[`docs/pacenotes-1.5.0.md`](pacenotes-1.5.0.md).

## A full rally

* **Drive rally** on the home page lists every rally whose pack has an event file. Pick one, choose the mode and
  whether to drive cancelled stages, then **Start**.
* **Realistic**: no restarts; a recovery sends you to the next service under Super Rally (the class's fastest
  time +10 min on the first stage missed, +7 min on each after). **Casual**: free recoveries and restarts.
* The time card lists every control. **Start transit** routes you to the next one; stop at its board to check in.
  At a stage's time control, **Load the stage?** readies the stage behind a loading screen.
* At service and overnight the car is fully repaired and the rally is saved. Damage carries over in between.
* The rally's recovery is **Backspace** or **D-pad right**, and asks **Recover?** first. On a transit to service it
  takes you to service; in a rally with no service, to the next stage's start.
* After the last stage, drive back to service, then **New rally** or **Continue driving**. Your rally goes on the
  rally's **Results** tab.

## Controls

| what | keyboard | controller |
|---|---|---|
| **Open / close the menu** | **Ctrl + Alt + K** (Esc closes) | bind one, or the pause menu's **Rally menu** |
| Skip the wait on the start line | **Shift + E** (Interact) | modifier + **Y** |
| Reset the car (+10 s on a stage) | **R** / **Insert** | the game's own |
| **Back on the road** where you got to, facing on (+10 s) | **Backspace** | bind one |
| **Flip upright** where you are (no penalty) | **Shift + Backspace** | the radial menu |

To rebind: Options > Controls > Bindings, category **Gameplay**, the actions starting **Earth Rally:**.

**Settings** (in the Earth Rally menu): units, the reset penalty, the control-zone brake, where the start
clock's close-up shows.

## The menu will not open

1. Are you in the BeamNG.Earth level? Try **Rally menu** on the pause menu's **Earth Rally** tab.
2. Press **`~`** and type `earthRally_main.toggleMenu()`.
   * **It opens** — the mod is fine, the key is not reaching the game. On some layouts Ctrl + Alt is AltGr, and some
     overlays take Ctrl + Alt + K. Bind another key.
   * **`attempt to index global 'earthRally_main'`** — the mod is not loaded. Main menu > **Mods** and switch Earth
     Rally on. Not listed? The zip must be directly in `…\current\mods\`, still zipped, one copy only. BeamMP
     switches local mods off when you join a server.
3. **It opens with no styling** (plain text, no layout)? This can happen after BeamNG.Earth's map page was opened
   in the same session. Type `reloadUI()` in the console.
4. Still nothing: `beamng.log` in `…\current\` should say `Earth Rally <version> loaded`. Open an issue with the lines
   mentioning `earthRally`.

## Making your own stage map

In [Google My Maps](https://www.google.com/mymaps), draw a line along the stage's roads and add markers named after
it, then Export to KML. The importer reads **lines as stages** and **points as controls**:

| the point's name contains | control |
|---|---|
| `Start`, `SS` | start line |
| `FF`, `Flying`, `Finish` | flying finish — the clock stops here |
| `ATC`, `TC` | arrival time control (optional) |
| `Stop` | stop control (optional) |

For a stage called `Maryhill Up`, points `Maryhill Up Start` and `Maryhill Up FF` match it. Case, years, version
tags and stage numbers are ignored. Without a start point the stage starts at the line's first point, so the
smallest file that works is one line per stage, drawn in the driving direction.

The rally's **Import report** in the menu lists each stage with its length and controls, and anything to fix.

## Developers

`python tests/run_tests.py` runs the offline suite, `python tools/install.py` installs the mod from this folder,
`python tools/package.py <version>` builds the release zip. Design notes and plans are in this folder.
