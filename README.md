# Earth Rally

Drive real rallies on the real roads. Drop in a rally's map — the one its organisers published — and Earth Rally
turns it into timed stages on [BeamNG.Earth](https://github.com/TecnaGamer/BeamNG.Earth), with time controls, a
start tree, penalties, and BeamNG.drive's own co-driver calling pacenotes worked out from the road itself.

**Status: alpha (1.3.1).** It works and it is being played, but things move.

## What you need

* **BeamNG.drive 0.40.5**
* **BeamNG.Earth**, modding API 1.6 or newer
* **A BeamNG.Earth that can hand out its road graph**, if you want the auto recce — see below

> ### The auto recce needs a BeamNG.Earth that does not exist yet
>
> The auto recce works a stage's driving line out from BeamNG.Earth's roads so you never have to drive a recce. It
> needs **modding API 1.9**, which is [one pull request waiting on TecnaGamer](https://github.com/TecnaGamer/BeamNG.Earth/pull/1249).
> Until that is merged, the only BeamNG.Earth that can answer is the fork it lives on:
> **`github.com/DeRamp/BeamNG.Earth`, branch `addon-api-road-graph`**.
>
> **With a stock BeamNG.Earth nothing breaks.** Earth Rally asks, gets no for an answer, and simply shows no auto
> recce — you drive a recce instead, as you always could. That is the only thing you lose.

## Install

Download `earth_rally-<version>.zip` from [Releases](https://github.com/DeRamp/BeamNG.Earth.Rally/releases) and put
it — still zipped — in `%LOCALAPPDATA%\BeamNG\BeamNG.drive\current\mods\`. Updating? Delete the old zip first; two
copies will both load.

In game: **Freeroam > BeamNG.Earth**, then **Ctrl + Alt + K** for the Earth Rally menu (or the pause menu's **Earth
Rally** tab).

## Getting a stage to drive

1. **Add a rally.** In the menu, **Open import folder**, and drop in the rally's `.kml`, `.kmz` or `.gpx`. It is
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

## A stage, start to finish

* The mod takes you to just before the **arrival time control**, and moves BeamNG.Earth's world origin to the middle
  of the stage so the ground does not shift under you (stages up to ~26 km across).
* Traffic and parked cars are cleared for the stage, and put back after.
* Route arrows lead to each control. In a control's zone the brakes ease in as you reach the board, so you can roll
  up to the boards and tent.
* At the ATC you get your **start time** on the rally clock. Driving past it is a missed control (+60 s).
* On the line you are held until GO, launch control on where the car has it, with the start tree, the countdown and
  the co-driver's *30 seconds… good luck… 5-4-3-2-1*. Early? **Shift + E** while stopped on the line skips to 6 s
  before your start. Jumping the start is +10 s; arriving late is +10 s a minute.
* On the stage: the stage clock, the distance done, the pacenote cards, and an **OFF ROUTE** warning with the way
  back if you leave the line. Each reset costs 10 s (a setting).
* The clock stops at the **flying finish**; drive on to the **stop control** for the results card — your time, each
  penalty, your best, and **Next stage**.

**Pacenotes** come from the stage's line: corners, their severity and the distance calls, voiced by the game's own
co-driver. With an auto recce, junctions are called too — *at junction*, *past junction*, *keep left / right*.

## Controls

| what | keyboard | controller |
|---|---|---|
| **Open / close the menu** | **Ctrl + Alt + K** (Esc closes) | bind one, or use the pause menu's tab |
| Skip the wait on the start line | **Shift + E** (Interact) | modifier + **Y** |
| Reset the car (+10 s on a stage) | **R** / **Insert** | the game's own |
| **Back on the road** where you got to, facing on (+10 s) | **Backspace** | bind one |
| **Flip upright** where you are (no penalty) | **Shift + Backspace** | the radial menu |

To rebind: Options > Controls > Bindings, category **Gameplay**, the actions starting **Earth Rally:**.

**Settings** (menu, or the pause-menu tab): units, full time controls or a quick start on the line, the reset
penalty, the control-zone brake, where the start clock's close-up shows.

## The menu will not open

1. Are you in the BeamNG.Earth level? Try the pause menu's **Earth Rally** tab.
2. Press **`~`** and type `earthRally_main.toggleMenu()`.
   * **It opens** — the mod is fine, the key is not reaching the game. On some layouts Ctrl + Alt is AltGr, and some
     overlays take Ctrl + Alt + K. Bind another key.
   * **`attempt to index global 'earthRally_main'`** — the mod is not loaded. Main menu > **Mods** and switch Earth
     Rally on. Not listed? The zip must be directly in `…\current\mods\`, still zipped, one copy only. BeamMP
     switches local mods off when you join a server.
3. Still nothing: `beamng.log` in `…\current\` should say `Earth Rally 1.3.1 loaded`. Open an issue with the lines
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

## Your rallies are yours

The maps you import and everything made from them — stages, recces, times — live in your BeamNG.drive user folder
(`…\current\earthRally\`), not in this repository. Organisers' route books belong to the organisers: don't commit
them or pass them on.

## More

* What is coming: [`docs/roadmap.md`](docs/roadmap.md)
* This version: [`docs/release-1.3.1.md`](docs/release-1.3.1.md)
* Building, testing and the design notes: [`docs/`](docs/) — `python tests/run_tests.py` runs the suite,
  `python tools/install.py` installs from this folder.

## License

MIT — see [LICENSE](LICENSE). BeamNG.Earth and BeamNG.drive are their authors'; their licences are their own.
