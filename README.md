# Earth Rally

Drive real rally stages on the real roads of [BeamNG.Earth](https://github.com/TecnaGamer/BeamNG.Earth), timed,
with BeamNG.drive's own co-driver calling pacenotes worked out from the road.

**v1.5.2-alpha · BeamNG.drive 0.40.5 · BeamNG.Earth modding API 1.6+ · auto recce: [DeRamp fork](https://github.com/DeRamp/BeamNG.Earth/releases)**
[Download](https://github.com/DeRamp/BeamNG.Earth.Rally/releases) · [Changelog](CHANGELOG.md) ·
[Player guide](docs/guide.md) · [Report a bug](https://github.com/DeRamp/BeamNG.Earth.Rally/issues)

## What it does

* Turns a rally's published map (`.kml`, `.kmz`, `.gpx`) into timed stages with their controls.
* **Auto recce** works out each stage's line from the roads, or drive a recce yourself.
* Time controls, a start tree and countdown, penalties, a flying finish and a results card.
* Pacenotes from the road: corners, hairpins, crests, jumps, junctions, cautions.
* **Rally packs** carry a whole season: itinerary, real results, rules and pictures.
* Leaderboards against the real crews, rally totals and season standings.

## Install

1. Install BeamNG.Earth from [the DeRamp fork](https://github.com/DeRamp/BeamNG.Earth/releases), with its installer, as you
   would the official one.
2. Download `earth_rally-<version>.zip` from [Releases](https://github.com/DeRamp/BeamNG.Earth.Rally/releases).
3. Put it, still zipped, in `%LOCALAPPDATA%\BeamNG\BeamNG.drive\current\mods\`.
4. In game: **Freeroam > BeamNG.Earth**, then **Ctrl + Alt + K** for the menu.

The fork adds the modding API the **Auto recce** needs, until an official release has it. Official BeamNG.Earth
1.6+ also works; you drive a recce instead. Report fork problems here, not to the BeamNG.Earth team.
Details: [player guide](docs/guide.md#the-auto-recce-and-beamngearth).

## Updating

* Delete the old Earth Rally zip first. Two copies both load.
* Your rallies, lines and times are kept. They live in `…\current\earthRally\`, not in the zip.

## Quick start

1. In the menu, **Open import folder** and drop in a rally's map.
2. Pick a stage and press **Auto recce**, or **Recce** to drive it once.
3. **Drive stage**.

## Known issues

* Auto recce is hidden on a stock BeamNG.Earth (needs API 1.9).
* Where the map has no road, the organisers' line is used and no notes are called there.
* A rally pack imported from a `.zip` is untested in game. Folders work.
* Very broad hilltops are not called as crests.

## Reporting bugs

[Open an issue](https://github.com/DeRamp/BeamNG.Earth.Rally/issues) with:

* Earth Rally, BeamNG.drive and BeamNG.Earth versions.
* What you did and what happened.
* The lines mentioning `earthRally` from `%LOCALAPPDATA%\BeamNG\BeamNG.drive\current\beamng.log`.

Menu will not open? See [the player guide](docs/guide.md#the-menu-will-not-open).

## Docs

* [Player guide](docs/guide.md): stages, controls, leaderboards, making your own map
* [Pacenotes](docs/pacenotes-1.5.0.md): every call and the figures behind it
* [Rally pack format](docs/rally-file.md)
* [Roadmap](docs/roadmap.md)
* [Developer docs](docs/): tests, tools and design notes
* [Writing standard](docs/writing-standard.md): README, changelog and releases

## License

MIT, see [LICENSE](LICENSE). BeamNG.Earth and BeamNG.drive belong to their authors.

Your imported rallies stay in your user folder, not in this repository. Route books, photos and results belong to
the organisers and name real crews: don't commit them, and ask the event before sharing a pack.
