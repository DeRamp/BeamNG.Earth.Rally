# Hand-made rally files (plan)

Drafted with the owner, 2026-11-25; built 2026-11-26 as `1.10.0-alpha+handfiles` (numbered at merge). Not yet
driven in game.

A second way to write rally packs, for people making them by hand: plain text (`.txt`) and spreadsheets (`.csv`), no
JSON. It covers everything the JSON packs do (`docs/rally-file.md`). It forgives the mistakes people make, and every
import writes a report saying what it found and why anything was left out. The JSON packs keep working unchanged.

Owner's decisions (2026-11-25/26): plain text and CSV, no JSON; seasons and real results included; everything the
game supports, schedule and time controls included; the game writes an import report; when a folder has both a
`.txt` and a `.json` manifest, the text one wins and the report says so; **one** running order, in `rally.txt`, as
simple as possible, with the timed parts optional on the same lines (no `schedule.csv`); weather by hand as words;
a template people download and fill in; the in-game report opened from the Last import lines.

## The files

Templates, every line explained in the file itself: [`templates/Earth Rally templates/`](../templates/Earth%20Rally%20templates/),
downloadable as `templates/Earth Rally templates.zip` (`tools/make_templates.py` builds it).

| File | What it is | Needed |
|---|---|---|
| `season.txt` | A season: name, rounds in order, standings, rules | for a season |
| `rally.txt` | A rally: name, map, dates, town, pictures, places, running order (timed or not), rules | for a rally |
| `stage.txt` | One stage: name, map or `line.csv`, controls, pictures, rules | for a stage |
| `results.csv` | Real crews' times, one row per crew per stage, or one column per stage | no |
| `weather.csv` | Each stage's weather (`tools/pack_weather.py` fills it, or by hand) | no |
| `line.csv` | A stage's line as points, for a stage with no map | no |
| the map | `.kml` / `.kmz` / `.gpx`, as today: lines, control points, `#pt-` organisers' points | yes |

A rally folder needs only `rally.txt` and the map. `results.csv` and `weather.csv` are picked up by
name when `rally.txt` doesn't name them. A season is a folder with `season.txt` and one folder per round; with no
`Rounds:` list, every rally folder in it is a round, in date order.

## Everything the game reads today, and where it goes

| Today (JSON) | Hand-made |
|---|---|
| season `id`, `name`, `championship` | `season.txt`: `ID`, `Season`, `Championship` |
| season `rounds[]`: `round`, `rally` manifest, or inline round | `Rounds:` list (number, folder or map); each round's own `rally.txt` |
| season `standings`: `championship`, `points`, `best` | `Count only`, `Points`, `Best rounds` |
| `rules` (season, round, rally, stage; each overrides the one before) | `False start`, `Late`, `Early`, `Max lateness`, `Start interval`, in any of the `.txt` files, same order of overriding |
| rally `id`, `name`, `dates`, `map`, `cover`, `logo`, `photo` | `rally.txt`: `ID`, `Rally`, `Dates`, `Map`, `Cover`, `Logo`, `Photo` |
| event `hq` (town, state) | `Town` |
| event `timezone` | `Time zone` |
| event `time_rules.early_checkin_allowed` | `Early is free at` |
| event `locations[]` (id, name, lat, lon) | `Place:` blocks with `At:` |
| event `service[]` (controls served by a place) | `Service at <place>`, or `Service in` / `Service out` lines, in the running order |
| itinerary SS rows: `control`, `stage`, `run`, `ss_km`, `day`, `power_stage` | running order lines (`SS1  Meaford Mills  10.46 km  power stage`, `Day 2`); run counted from repeats |
| itinerary stops: `SVC_IN/OUT`, `MTC_IN/OUT`, `RGC_IN/OUT`, `PE_OUT`, `PF_IN`, `ATC`, `REFUEL` | running order lines in words (`Service in`, `MTC out`, `Regroup in`, `Parc ferme out`, `ATC`, `Refuel`); `Start`, `Finish` |
| schedule: `date`, `first_car`, `target_min`, `lateness_min`, `classes` | on the same lines: `Day 2  8 Feb 2031`, `08:23` in front, `20 min`, `late 10 min`, `only Regional` |
| SS row `weather` (code, cover, wind, temps, rain, snow, fog, visibility...) | `weather.csv`, one row per SS; `Sky` in words or a WMO code |
| `weather_source` | written by `tools/pack_weather.py` as a `#` line in `weather.csv` |
| results `stages[]`: `control`, `stage`, `run`, `km`, `cancelled` | `results.csv` `SS`, `Stage`, `Km`; `cancelled` in the Time column |
| results `times[]`: `seconds`, `driver`, `car`, `class`, `championship`, `notional` | `results.csv` `Time` (`6:39.4` or seconds, `N` for notional), `Driver`, `Car`, `Class`, `Championship` |
| stage `line` points `[lat, lon, alt]` | `line.csv` |
| stage `controls` (atc, start, ff, stop) | `stage.txt`: `ATC`, `Start`, `Finish`, `Stop` |
| `format`, `kind` | not needed: the file's name says the kind; no version number to get wrong |

## How forgiving it is

The reader takes whatever it can make sense of, and says what it did. A file is refused only when nothing usable is
left (no name and no map, say), and always with the reason.

- **Text**: any capitals and spacing; `Key: value`, `Key = value` or `Key  value`; `#` and `//` notes, also after a
  value; tabs; Windows, Mac or Unix line ends; UTF-8 with or without a BOM, UTF-16 (Notepad's "Unicode"), Windows-1252;
  curly quotes and long dashes from Word; a value in quotes.
- **Keys**: common other words for each (`Name` / `Title` for `Rally`; `Stages` / `Itinerary` for `Running order`;
  `Location` / `Position` / `GPS` for `At`). An unknown key is listed in the report as skipped, never an error. A key
  that is close to a known one gets "did you mean".
- **Files**: named with any capitals, with or without the extension Windows hides (`rally.txt.txt`, `Rally.TXT`),
  `rally.csv` or `results.xlsx` saved by mistake named in the report. A file named that is missing: "did you mean"
  the nearest file in the folder. `.json` beside `.txt`: the text one is read, and the report says so.
- **CSV**: `,` or `;` or tab (Excel in Europe saves `;`), columns in any order and with any of their common names,
  extra columns skipped, blank rows and Excel's trailing commas skipped, `#` notes allowed.
- **Positions**: `60.0102, -10.0451`, `60.0102 -10.0451`, `60°00'36.7"N 10°02'42.4"W`, `N 60.0102 W 10.0451`, a
  Google Maps link. Longitude first is spotted when it can't be latitude (over 90) or the place is far from the map,
  swapped, and reported.
- **Times and dates**: `6:39.4`, `399.4`, `0:06:39.4`, `6'39.4"`, `6m39.4s`, a decimal comma; `08:23`, `8.23`,
  `8h23`, `8:23 am`; `2031-02-07`, `7 Feb 2031`, `Feb 7 2031`, `7/2/2031` (day and month told apart where the other
  can't be a month; otherwise read as day first and reported). Durations `30`, `30 min`, `0:30`, `1h`.
- **Names** (stages, places, files, round folders, settings): matched ignoring capitals, spaces, punctuation and
  accents, and an `SS3` in front. One that is a slip of a single name (a letter or two out, two swapped, or cut
  short) is read as that name and the report says so on its line; a longer name is never taken for a shorter one
  ("Kilo Hill North" is not "Kilo Hill"). Anything further off is left out, with "did you mean" when one is near.
  (Changed in review, 2026-11-26: guessing with the report saying so, rather than leaving every slip out, is what
  "very accepting of errors" asked for.)

## The import report

Written each time a pack or map is read: `import report.txt` inside a folder pack; `<name> - import report.txt`
beside a zip or a loose map. The importer never reads report files. JSON packs and loose maps get one too, and broken
JSON gets its line and column instead of today's "not a rally pack".

Sections, in order: the verdict (**Imported**, **Imported with N problems**, **Not imported**: what to do),
**Problems** (numbered: file, line, the line as written, what's wrong, what was done, how to fix), **What the game
found** (the rally, its stages against the map's lines, the running order with services and days, timing, results,
weather, rules), **Read but not used yet**. Sample: [`mockups-hand-files/import report.txt`](mockups-hand-files/import%20report.txt).

In game: the Rallies page's "Last import" lines open the same report on an **Import report** page. Mock-up:
[`mockups-hand-files/import.html`](mockups-hand-files/import.html).

## Service areas later

A `Place:` is a block, so a later `Area:` (corner positions, or a polygon in the map) is one more line under it.
Until the game uses areas, an `Area:` line is reported under "Read but not used yet" and the place's `At:` is used.

## How it's built

- `textRead.lua`: the forgiving pieces (encodings, keys, names, CSV, positions, times, dates).
- `textPack.lua`: `season.txt` / `rally.txt` / `stage.txt` and the CSVs as the tables the JSON files give
  `pack.lua` (a manifest, and the event and results files as virtual files), with every problem as
  `{ file, line, text, what, fix, level }`. Everything after reading (`makeRally`, ids, boards, the full rally,
  timing, weather) is the JSON packs' own code.
- `pack.lua`: the `.txt` manifest first, a `.json` beside it named; problems carried as tables; broken JSON with
  its line and column; a failed hand-made pack fingerprinted by all its files, so a fix is picked up; rally folders
  one level in named. `importer.lua`: loose maps report too.
- `importReport.lua`: the report as data and as `import report.txt`; `main.lua` keeps it on each Last import line;
  `EarthRallyImportReport.vue` shows it (the mock-up's screens 2 and 3).
- `tools/pack_weather.py`: a hand-made pack gets `weather.csv`, from its running order as textPack.lua reads it
  (through lupa).
- Tests: `test_textread` (every way a value can be written), `test_textpack` (the templates as they ship, the timed
  running order, the mistakes, the season and stage templates, broken JSON), `test_pack_weather` (weather.csv, and
  read back), `test_templates` (the zip is the folder's).

## Not done

- Service areas: `Area:` is read and said "not used yet" (the owner, 2026-11-25: may come later).
- Not driven in game yet: the report page and the report files are checked offline only.
- Reports are written beside every loose map and zip on each import, as the owner asked; one whose file is taken
  out is deleted with it. If the folder gets cluttered, write them only for imports with problems.
