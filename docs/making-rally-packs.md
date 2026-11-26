# Making stages and rally packs

How to make files Earth Rally can import: a single stage, a whole rally, or a season of rallies with itineraries,
real results, rules and pictures. This guide is for organisers, modders and anyone sharing stages. The full
format, with every edge case, is in [`rally-file.md`](rally-file.md).

**Start with the templates:** download
[`Earth Rally templates.zip`](https://github.com/DeRamp/BeamNG.Earth.Rally/raw/main/templates/Earth%20Rally%20templates.zip),
copy the folder you want, fill it in with Notepad and Excel, and drop it in the import folder. Every file explains
itself. Read [Hand-made files](#hand-made-files-start-here) below.

Everything goes in the import folder: **Open folder** on the menu's **Drive stage** page, or
`%LOCALAPPDATA%\BeamNG\BeamNG.drive\current\earthRally\import\`. The mod imports new and changed files when it
loads and whenever the folder changes. **Re-scan** imports everything again.

The examples below are fictional and illustrative: each shows one file, and together they don't make a working
pack.

**Not yet in the alpha:**

* Packs in a `.zip` are untested in game. Use a folder until they are.
* Pictures may not show in the menu yet; a drawn plate stands in.
* Rules are shown on the **Rules** tab, not applied. The false start is a fixed 10 s.

## Contents

1. [What you can make](#what-you-can-make)
2. [Hand-made files (start here)](#hand-made-files-start-here)
3. [The stage map](#the-stage-map)
4. [JSON packs: laying out a pack](#laying-out-a-pack)
5. [Stage pack: `stage.json`](#stage-pack-stagejson)
6. [Rally pack: `rally.json`](#rally-pack-rallyjson)
7. [Season pack: `season.json`](#season-pack-seasonjson)
8. [The event file: itinerary, service and overnight](#the-event-file-itinerary-service-and-overnight)
9. [The results file: leaderboards](#the-results-file-leaderboards)
10. [Rules](#rules)
11. [Pictures](#pictures)
12. [Checking and updating a pack](#checking-and-updating-a-pack)
13. [Sharing](#sharing)

## What you can make

| You drop in | You get |
|---|---|
| A `.kml`, `.kmz` or `.gpx` map | One rally. Each line in it is a stage, run once each in map order. |
| A **stage pack**: a folder or `.zip` with `stage.txt` (or `stage.json`) | One stage, with its own name, picture and results. |
| A **rally pack**: a folder or `.zip` with `rally.txt` (or `rally.json`) | One rally with a running order, real results, rules and pictures. |
| A **season pack**: a folder or `.zip` with `season.txt` (or `season.json`) | Several rallies in order, with season standings. |

Every pack starts from a stage map, so make that first. The `.txt` files are for people making packs by hand; the
`.json` ones are for tools, and keep working as before. When a folder has both, the `.txt` is read.

## Hand-made files (start here)

Plain text and spreadsheets, no JSON. The game takes whatever it can make sense of, and **every import writes an
`import report.txt`** in the pack's folder (beside a `.zip` or a loose map: `<name> - import report.txt`) saying
what it found, what it left out and how to fix it, with the file and line. The same report opens in game from the
**Drive stage** page's **Last import** lines.

| File | What it is |
|---|---|
| `rally.txt` | The rally: name, map, dates, town, pictures, places, running order, rules |
| `season.txt` | A season: rounds (one folder per rally, each with its `rally.txt`), points, rules |
| `stage.txt` | One stage: a map, or `line.csv` with its controls |
| `results.csv` | Real crews' times: one row per crew per stage, or a column per stage |
| `weather.csv` | Each stage's weather in words (`overcast`, `light rain`); `tools/pack_weather.py` can fill it |
| `line.csv` | A stage drawn as points, for a stage with no map |

Only `Rally:` (or `Season:`, `Stage:`) and the map are needed. Leave out what you don't have.

**Forgiving by design:**

* `Rally: X` and `rally = X` are the same. Capitals, spacing, `#` notes and quotes don't matter. After the
  running order, give each setting its colon (`Late: 10`).
* Notepad's encodings, Word's curly quotes and Excel's `;` files all read.
* Positions can be pasted from Google Maps, typed as `60.0102, -10.0451`, or in degrees and minutes. Longitude
  first is spotted and swapped.
* Times read as `6:39.4`, `399.4` or `0:06:39.4`; dates as `7 Feb 2031`, `2031-02-07` or `7-8 Feb 2031`.
* A name that is a slip of a stage, place, file or setting is read as the one it nearly matches, and the report
  says so.

### The running order

One line per stage or stop in `rally.txt`, under `Running order:`:

```
Running order:
  Day 1
  Start at Fernvale Park
  SS1  Meaford Mills      10.46 km
  SS2  Kilo Hill
  Service at Fernvale Park
  SS3  Meaford Mills
  Day 2
  Start at Ridge Hotel
  SS4  Long Gap           power stage
  Finish at Fernvale Park
```

* A **stage** is named as its line is in the map. Listed again, it is its next run. The `SS` number is optional.
* A **stop** is `Start`, `Service`, `Regroup`, `Refuel` or `Finish`, then `at` and a place. Each place is a
  `Place:` block with `At:` and its position, so services and overnights land in the right spot.
* `Day 2` (with a date if you like) starts the next day: the night between is an overnight.
* **Timed road sections** go on the same lines: a time at the front (`08:23`, the first car), minutes at the end
  (`20 min`, the time allowed from the line before), `late 10 min` on a stage, `ATC` lines, timed stops in pairs
  (`Service in` / `Service out`, `MTC in` / `MTC out`, `Regroup in` / `Regroup out`, `Parc ferme in` /
  `Parc ferme out`), and `only Regional` for a control only some classes pass. The rally template ends with a
  full example.

## The stage map

### Drawing it

Any road on BeamNG.Earth can be a stage. [Google My Maps](https://www.google.com/mymaps) is the easiest tool;
anything that writes KML or GPX works.

1. Draw a **line** along the stage's roads, **in the driving direction**, from before the start to past the flying
   finish. Name it after the stage: `Maryhill Up`.
2. Add **points** for its controls, named after the stage (below).
3. Repeat for each stage. One file holds the whole rally.
4. **Export to KML** (a `.kmz` is fine too).

What the importer reads:

* **Lines** become stages. In KML that is every `Placemark` with a `LineString`, in any folder. In GPX, every
  `trk` and `rte`.
* A line in several pieces (a `MultiGeometry`, or several `trkseg`) is joined into one, in driving order.
* **Points** (`Point` in KML, `wpt` in GPX) become controls or organisers' points. Others are ignored.
* The **rally's name** is the document's name, unless that is a generic one ("Untitled map", "Main Route Book",
  "Layer"...). Then the file name is used.
* The stage's id comes from its line's name. Keep line names unique and stable: times are saved against them.

### Naming the controls

A point is a control when its name has a control word in it, and is matched to the stage whose name is the rest.

| The point's name contains | Control |
|---|---|
| `Start`, `SS` | start line |
| `FF`, `Flying`, `Finish` | flying finish: the clock stops here |
| `ATC`, `TC` | arrival time control (optional) |
| `Stop` | stop control (optional) |

* For `Maryhill Up`: `Maryhill Up Start`, `SS Maryhill Up`, `Maryhill Up FF` and `ATC Maryhill Up` all match.
* Case, any 2- or 4-digit number (`2026`, `26`, `12`), version tags (`v2`), stage numbers (`SS3`) and the words
  `control`, `end`, `in` and `out` are ignored when matching. So `Forest 12` and `Forest 34` look the same: name
  stages so they differ by more than a number.
* A stage number is not a control word: `SS3 Maryhill Up` alone is not a start.
* A shortened name works when only one stage starts that way: `Maryhill FF` matches `Maryhill Up`, unless there is
  also a `Maryhill Down`. `Reverse` is never dropped: `Maryhill FF` won't match `Maryhill Reverse`.
* A point with `service`, `regroup`, `MTC`, `parc`, `spectator`, `jump`, `traffic`, `area`, `VC`, `barricade`,
  `maybe`, `prohibited` or `expose` in its name is never a control.
* **Stage names** go through the same rules, so keep those words, and `flying` or `FF`, out of them. A stage called
  `Quarry Area` or `Service Road` can never get a control.
* **No start point:** the stage starts at the line's first point (of its longest piece, if drawn in pieces).
  **No flying finish:** it ends at the line's end.
  So the smallest map that works is one line per stage.
* With a flying finish but no start, a line drawn backwards is turned round.
* A start or flying finish more than 100 m from its line is flagged in the Import report.

### Marking the organisers' points

Radio, medical, spectator and marshal points are put out on the stage by the stage dressing. A point counts when it
is within 100 m of a stage's line.

The surest way is the point's KML style: `<styleUrl>#pt-radio</styleUrl>`. The kinds are `radio`, `medical`,
`spectator` and `marshal`, and they combine: `#pt-radio-spectator` is both. A tagged point is exactly those kinds,
whatever its name says.

Untagged points are read from their words:

| Kind | Read from |
|---|---|
| Radio | `radio` in the folder, style or name, or a name like `R3`, `Radio 3` |
| Medical | `medical`, `ambulance`, `MIV`, `doctor` in the folder, style or name |
| Spectator | `spectator` in the folder, style, name or description, unless it also says `prohibited`, `closed`, `parking`, `car park`, `toilets`, `no spectators` and the like |
| Marshal | `marshal` in the folder, style or name, a name like `MP 9`, or a style with `police` in it |

An untagged control is never one of these: `Start Radio` stays the start. A tagged point is a mark even when its
name makes it a control too.

### The smallest example

```xml
<?xml version="1.0" encoding="UTF-8"?>
<kml xmlns="http://www.opengis.net/kml/2.2">
<Document>
  <name>Fernvale Rally</name>
  <Placemark>
    <name>Fernvale South</name>
    <LineString><coordinates>
      -10.0000,60.0000 -10.0010,60.0004 -10.0021,60.0011 -10.0030,60.0020
    </coordinates></LineString>
  </Placemark>
  <Placemark><name>Fernvale South Start</name><Point><coordinates>-10.0001,60.0001</coordinates></Point></Placemark>
  <Placemark><name>Fernvale South FF</name><Point><coordinates>-10.0029,60.0019</coordinates></Point></Placemark>
  <Placemark>
    <name>R1</name><styleUrl>#pt-radio</styleUrl>
    <Point><coordinates>-10.0015,60.0007</coordinates></Point>
  </Placemark>
</Document>
</kml>
```

KML coordinates are `longitude,latitude[,altitude]`. That file on its own is already a rally of one stage.

## Laying out a pack

A pack is a **folder**, or a **`.zip` of one**, with one manifest at its top: `season.json`, `rally.json` or
`stage.json`. Everything else is optional and named by the manifest. A typical season:

```
Fernvale Series 2030/
├── season.json                    the manifest: rounds, standings, rules
├── maps/
│   ├── Fernvale Rally.kml         stage lines and controls, one map per rally
│   └── Quarry Rally.kml
├── events/
│   └── Fernvale Rally.json        itinerary, service, overnight
├── results/
│   └── Fernvale Rally.json        real crews' stage times
├── covers/
│   ├── Fernvale cover.jpg
│   └── Fernvale logo.png
└── round2/                        a round can have a rally manifest of its own
    ├── rally.json
    └── map.kml
```

The folder names are up to you: only the manifest's paths matter.

* **Paths** are relative to the file that names them, with `/` or `\`. A path that climbs out of the pack
  (`../other.kml`) is not read.
* **One manifest** at the top. Two is refused, naming both. A manifest can also be any `.json` with
  `"kind": "season"`, `"rally"` or `"stage"`.
* **A zip** can hold the pack's files directly, or one folder holding them (as Windows' **Send to > Compressed
  folder** makes it).
* **Not part of a pack:** `__MACOSX`, dot files (`.DS_Store`), `Thumbs.db` and `desktop.ini`.
* **No `.kmz` inside a `.zip`.** Put the `.kml` in the pack instead. A `.kmz` in a folder pack is fine.
* **JSON** must be valid: no comments, no trailing commas. The examples below follow that. When it isn't, the
  import report gives the line and column.
* Unknown fields are ignored. Every field is optional unless marked **required**.
* Each manifest may carry `"format": 1`. A higher number than the mod knows is refused, so leave it at `1`.

## Stage pack: `stage.json`

One stage with its own name, results and pictures.

```json
{
  "format": 1,
  "kind": "stage",
  "id": "kilo-hill",
  "name": "Kilo Hill",
  "map": "Kilo Hill.kml",
  "results": "results.json",
  "cover": "cover.jpg"
}
```

The map should hold one line; with more, the first is used and the Import report says so.

Instead of a map, a stage can be given as points. `line` is `[lat, lon]` pairs in driving order (note: latitude
first, the other way round from KML). `controls` are each optional:

```json
{
  "format": 1,
  "kind": "stage",
  "name": "Kilo Hill",
  "line": [[60.0000, -10.0000], [60.0004, -10.0010], [60.0011, -10.0021], [60.0020, -10.0030]],
  "controls": {
    "atc":   { "lat": 59.9998, "lon": -9.9998 },
    "start": { "lat": 60.0001, "lon": -10.0001 },
    "ff":    { "lat": 60.0019, "lon": -10.0029 },
    "stop":  { "lat": 60.0020, "lon": -10.0030 }
  }
}
```

A third number in a point (altitude) is accepted and not used yet. Fewer than two points is refused.

## Rally pack: `rally.json`

```json
{
  "format": 1,
  "kind": "rally",
  "id": "fernvale-2030",
  "name": "Fernvale Rally 2030",
  "dates": { "from": "2030-03-01", "to": "2030-03-02" },
  "map": "Fernvale Rally.kml",
  "event": "event.json",
  "results": "results.json",
  "cover": "cover.jpg",
  "logo": "logo.png",
  "photo": "photo.jpg",
  "rules": { "lateSPerMin": 10, "earlySPerMin": 60 }
}
```

| Field | What it does |
|---|---|
| `map` | **Required.** The stage lines: `.kml`, `.kmz` or `.gpx`. |
| `id` | Keys the players' saved times. Set it once and never change it. Without it, one is made from the name. |
| `name` | Shown in the menu. Without it, the map's name. |
| `dates` | `from` and `to`, `YYYY-MM-DD`. Without it, the event file's. |
| `event` | The itinerary: running order, passes, service and overnight. Needed for **Drive rally**. |
| `results` | The real crews' times: leaderboards and rally results. |
| `cover`, `logo`, `photo` | Pictures for the menu. |
| `rules` | Penalties and timings (see [Rules](#rules)). |

Without an event file the stages run once each, in map order, as SS1, SS2..., each its line's length.

## Season pack: `season.json`

```json
{
  "format": 1,
  "kind": "season",
  "id": "fernvale-series-2030",
  "name": "Fernvale Series 2030",
  "championship": "Fernvale Regional Rally Championship",
  "rounds": [
    {
      "round": 1,
      "id": "fernvale-2030",
      "name": "Fernvale Rally 2030",
      "dates": { "from": "2030-03-01", "to": "2030-03-02" },
      "map": "maps/Fernvale Rally.kml",
      "event": "events/Fernvale Rally.json",
      "results": "results/Fernvale Rally.json",
      "cover": "covers/Fernvale cover.jpg",
      "logo": "covers/Fernvale logo.png",
      "rules": { "startIntervalMin": 3 }
    },
    { "round": 2, "rally": "round2/rally.json" }
  ],
  "standings": {
    "championship": "national",
    "points": [25, 20, 16, 13, 11, 10, 9, 8, 7, 6, 5, 4, 3, 2, 1],
    "best": null
  },
  "rules": { "falseStartS": [10, 60, 180], "lateSPerMin": 10 }
}
```

* `name` and `rounds` are **required**. Rounds are listed in running order.
* A round takes the same fields as a `rally.json`, or a `rally` path to a rally manifest of its own. That manifest's
  paths are relative to its own folder; the round's `id`, `name` and `dates` fill any it leaves out.
* `round` is the round's number; without it, its place in the list. A number used twice: the second is left out.
* `standings` (optional, these are the defaults):
  * `championship`: only crews whose results rows carry this championship score points. `false`, `""` or `"all"`:
    every crew.
  * `points`: points for 1st, 2nd, 3rd... in each rally.
  * `best`: count only each crew's best N rounds; `null` counts all.
* `rules` set here apply to every round. A round's own `rules`, then its rally manifest's, override them one field
  at a time.

## The event file: itinerary, service and overnight

The event file is the rally's itinerary: which stage runs when, how long each pass is, and where service and the
overnight halt are. With one, the rally shows real SS numbers, a stage run twice shows as one row (*SS2 · SS5*),
and the rally can be driven whole with **Drive rally**.

```json
{
  "event": {
    "name": "Fernvale Rally 2030",
    "dates": { "from": "2030-03-01", "to": "2030-03-02" },
    "hq": { "town": "Fernvale", "state": "ZZ" }
  },
  "locations": [
    { "id": "park", "name": "Fernvale Park Service Area, Fernvale", "lat": 60.0102, "lon": -10.0451 },
    { "id": "hall", "name": "Fernvale Hall", "lat": 60.0120, "lon": -10.0402 }
  ],
  "service": [
    { "type": "service", "control": "2A-2B", "location": "park" }
  ],
  "itinerary": [
    { "type": "MTC_OUT", "control": "TC0", "location": "hall", "day": 1 },
    { "type": "SS", "control": "SS1", "stage": "Fernvale South", "run": 1, "ss_km": 3.0, "day": 1 },
    { "type": "SS", "control": "SS2", "stage": "Fernvale North", "run": 1, "ss_km": 1.95, "day": 1 },
    { "type": "SVC_IN", "control": "2A", "location": "park", "day": 1 },
    { "type": "SVC_OUT", "control": "2B", "location": "park", "day": 1 },
    { "type": "SS", "control": "SS3", "stage": "Fernvale South", "run": 2, "ss_km": 3.0, "day": 1 },
    { "type": "MTC_IN", "control": "TC3", "location": "hall", "day": 1 },
    { "type": "MTC_OUT", "control": "TC4", "location": "hall", "day": 2 },
    { "type": "SS", "control": "SS4", "stage": "Fernvale North", "run": 2, "ss_km": 1.95, "day": 2,
      "power_stage": true }
  ]
}
```

### The itinerary

`itinerary` is the running order, one row per control, top to bottom.

`SS` rows are the stages:

| Field | What it does |
|---|---|
| `type` | `"SS"`. |
| `control` | **Required.** The pass's label: `SS1`, `SS2`... A control listed again (one row per class) is read once. Without it, the row is not a pass. |
| `stage` | **Required.** The map line's name, **exactly** as in the map. A name with no line is left out and reported. |
| `run` | Which time over this stage: `1`, `2`... Default `1`. |
| `ss_km` | The pass's official length, when the results file gives none. With results, players more than 5% off it on their line aren't placed on its leaderboard. |
| `day` | The day number. A change of day between two passes is an overnight halt. |
| `power_stage` | `true` for the power stage. |

A map line the itinerary never runs shows in the menu as **Not run**.

### Service, overnight and the rally's start

For **Drive rally**, other rows say where the stops are. Only the rows between passes matter:

* **Service** after a pass: a `SVC_IN` or `SVC_OUT` row, or a row whose `control` is one of a `service` entry's.
  An entry counts only with `"type": "service"`. Its `control` can name several, split by `-` or spaces (`"2A-2B"`), for events that write service as a
  pair of controls or as refuel zones (`"RZ1"`).
* **Overnight** after a pass: the next pass has a different `day`.
* Services are labelled **Service A**, **Service B**...
* **Where a stop is**: a row's `location`, or its service entry's, names an entry in `locations`, which gives
  `name`, and `lat` and `lon` as numbers (not strings). The service entry's place wins, then `SVC_OUT`, `SVC_IN`,
  the day's start (`MTC_OUT`, `PE_OUT`), its end (`MTC_IN`), `PE_IN`, then any other.
* **The overnight** is at that day's last service park. Only a day with no located service uses the overnight's own
  place, preferring the next morning's start.
* **The finish**: after the last stage the rally ends at a **Final service** at the last day's service park (its
  last located service). A stop listed after the last pass is not used. A rally with no located service ends at
  its last stage.
* **The rally's start** is the place of a located row before the first pass, else the first stop with a place.
* A place's name is shortened for the time card: `"Fernvale Park Service Area (Saturday), Fernvale"` shows as
  *Fernvale Park Service Area*.

Other row types (`TC`, `RG_IN` and the rest) are fine to include: they only count as places. Rules are
not read from the event file, only from the manifests.

**Drive rally** lists a rally, or a season's round, when it has an event file with at least one `SS` row that
matches a map line. Without locations, the rally still runs: each transit goes to the next stage's time control
when that is within 1.5 km of the start, else to the start.

## The results file: leaderboards

Real stage times, one entry per pass. Each stage gets a leaderboard, the rally gets results, and a season gets
standings.

```json
{
  "stages": [
    {
      "control": "SS1",
      "stage": "Fernvale South",
      "run": 1,
      "km": 3.0,
      "cancelled": false,
      "times": [
        { "seconds": 181.5, "driver": "Ada Brook", "car": "7", "class": "L4WD", "championship": "national" },
        { "seconds": 175.2, "driver": "Cy Dale", "car": "3", "class": "O2WD", "championship": "regional" },
        { "seconds": 190.0, "driver": "Ed Finch", "car": "9", "class": "L4WD", "championship": "national",
          "notional": true }
      ]
    },
    { "control": "SS3", "stage": "Fernvale South", "run": 2, "km": 3.0, "cancelled": true, "times": [] }
  ]
}
```

| Field | What it does |
|---|---|
| `control` | Which itinerary pass this is. Without it, matched by `stage` and `run`. |
| `stage` | **Required.** The map line's name, exactly. |
| `run`, `km` | As in the itinerary. `km` falls back to the itinerary's `ss_km`. |
| `cancelled` | `true`: no leaderboard, and the pass isn't counted in rally totals. |
| `times[].seconds` | **Required** for a row to count. Rows without it are left out. |
| `times[].driver` | The crew's name. Season standings join crews across rounds by it, ignoring case. |
| `times[].car`, `class` | Shown on the leaderboard. |
| `times[].championship` | Which crews score season points (see `standings.championship`). |
| `times[].notional` | `true` for a time given, not driven: left off the stage leaderboard, counted in totals. |

Rally totals and positions are worked out from the stage times. An `overall` table, positions or penalties in the
file are ignored. A crew missing a time on any counted pass isn't ranked.

## Rules

Numbers, shown on the rally's **Rules** tab. Every field is optional.

```json
"rules": {
  "falseStartS": [10, 60, 180],
  "lateSPerMin": 10,
  "earlySPerMin": 60,
  "maxLatenessMin": 30,
  "startIntervalMin": 2
}
```

| Field | Meaning |
|---|---|
| `falseStartS` | Seconds for a 1st, 2nd and 3rd false start. |
| `lateSPerMin` | Seconds per minute (or part) late at a time control. |
| `earlySPerMin` | Seconds per minute (or part) early at a time control. |
| `maxLatenessMin` | Minutes late allowed in a day before retirement. |
| `startIntervalMin` | Minutes between cars. |

Set them in a season, a round or a rally manifest; the most specific wins, field by field.

## Pictures

`cover`, `logo` and `photo` are image paths: `.jpg` and `.png` are safest. They are copied into the player's
folder, so the pack can be moved after import. A missing picture is reported and skipped.

## Checking and updating a pack

1. Drop the pack into the import folder, then open the `import report.txt` the game writes in it (beside a `.zip`
   or a loose map: `<name> - import report.txt`), or press **Report** on the **Drive stage** page's last-import line.
2. The report says whether it imported, lists each problem with its file, line and what to do, and shows what the
   game found: the stages against the map's lines, the running order with services and days, whether it is timed,
   the results, weather, pictures and rules.
3. A pack that can't be used at all says why: no map, two manifests, a `format` too high, a `.kmz` in a `.zip`,
   or a `.json` with its line and column.
4. Edit the pack where it is. The mod imports it again when its files change, and writes a new report. Editing the
   report itself does nothing.

To keep players' times when you update a pack:

* **Give every season, round and rally an `id`** and never change it. Times are saved against the rally's id and
  the stage's line name.
* **Don't rename lines** in the map. A renamed line is a new stage, with no times.
* A pack without ids that is renamed keeps its old ones when its name (the season's, for a season) stays the same
  and the old file leaves the folder at the same time.
* Moving a line's start or finish changes the stage. Players' old times stay in their runs, but only times on the
  stage's current line are placed on leaderboards.

## Sharing

Route books, photos and results belong to the organisers and name real crews. Ask the event before sharing a pack
built from them, and never commit one to this repository.
