# The Earth Rally file (format 1)

What a player drops into `<BeamNG user folder>/current/earthRally/import/` to get a season, a rally or a stage, and
what the mod makes of it. Drafted 2026-11-14 on branch `rally-files`, with the ARA Nationals 2026 pack (not in git:
organisers' material) as the worked example. Version number decided at merge (the user).

## What can be dropped in

| Dropped in | Becomes |
|---|---|
| A `.kml` / `.kmz` / `.gpx` on its own (as today) | one rally, named from the map; stages from its lines |
| A **pack**: a folder, or a `.zip` of one, with a manifest at its root | a season, a rally or a stage, with whatever else the manifest names |

The manifest is the one JSON file at the pack's root whose `kind` is `season`, `rally` or `stage`. A root file named
`season.json` / `rally.json` / `stage.json` with no `kind` is taken as that kind (so the ARA pack's `season.json`
works as it is). More than one manifest at the root is refused, naming them. Everything a manifest names is a path
relative to the folder the manifest is in, with `/` or `\`; a path that climbs out of the pack is not read.

The pack's root is the folder (or the zip) itself, or the one folder inside it when nothing else is beside that
folder: `X/X/season.json`, as Windows' Extract All or a zipped folder makes it, works. A Mac's `__MACOSX/` and any
entry whose name starts with `.` (`.DS_Store`) are ignored when looking for that folder, in a zip and in a folder.
A `.kmz` inside a `.zip` is refused (put the `.kml` in the pack instead).

Any field may be missing unless marked **required**. Unknown fields are ignored. A `format` greater than this reader
knows is refused with a message naming both numbers (a round's own rally manifest too: that round is left out).

## Season (`kind: "season"`)

```jsonc
{
  "format": 1, "kind": "season",
  "id": "ara-nationals-2026",            // optional: else a slug of name. Kept stable: it keys your times (Ids)
  "name": "ARA Nationals 2026",          // required
  "championship": "American Rally Association National Championship 2026",   // shown under the name
  "rounds": [                            // required, in running order
    { "round": 1,                        // its number (default: its place in the list); a number listed twice: the second left out
      "id": "snodrift-2026",             // optional (Ids)
      "name": "SnoDrift Rally 2026", "dates": { "from": "2026-02-06", "to": "2026-02-07" },
      "map": "01 SnoDrift Rally 2026.kml",           // required: the stage lines
      "event": "events/01 SnoDrift Rally 2026.json", // the itinerary (Event file)
      "results": "results/01 SnoDrift Rally 2026.json",
      "cover": "covers/01 ... - cover.png", "logo": "...", "photo": "...",
      "rules": { ... } },                // this round's, over the season's
    { "round": 2, "rally": "round2/rally.json" }   // or a rally manifest of its own (Rally)
  ],
  "standings": {                         // season standings; this block is optional, with these defaults
    "championship": "national",          // only crews whose results rows have this championship score (false, "" or "all": everyone; compared case folded)
    "points": [25, 20, 16, 13, 11, 10, 9, 8, 7, 6, 5, 4, 3, 2, 1],  // by finishing position in each rally; read up to the first non-number
    "best": null                         // count only the best N rounds (null: all)
  },
  "rules": { ... }                       // Rules: for every round unless the round or its rally manifest overrides it
}
```

The default points scale is ours (the user, 2026-11-14: "build your own standings table based on the included
events ... just use finishing data"): 15 places deep because these fields are 42 to 97 cars, and the power stage is
ignored for now.

## Rally (`kind: "rally"`, or one round of a season)

The same fields as a season's round: `id`, `name`, `dates`, `map` (**required**), `event`, `results`, `cover`, `logo`,
`photo`, `rules`. A round that names a `rally` manifest has that file read in its place, its paths relative to that
file's folder; the round's `id`, `name` and `dates` fill what the manifest leaves out, and the round's `rules` sit
between the season's and the manifest's. With no `name`, the map's name is used. `dates` falls back to the event
file's `event.dates`.

### Event file (`event`)

Only these fields are read; everything else in it (the ARA files carry schedule, service, free-text time rules and
penalties) is ignored. Rules are **not** read from it: they come from the manifests only (Rules).

```jsonc
{ "event": { "dates": { "from": "...", "to": "..." },     // when the manifest has no dates
             "hq": { "town": "Fernvale", "state": "ZZ" } }, // "Fernvale, ZZ", one line under the rally's name
  "itinerary": [
    { "type": "SS",          // only SS rows are read
      "control": "SS3",      // the pass's label; a control listed again (one row per class) is read once
      "stage": "Meaford-Mills",  // the map line's name, exactly
      "run": 2,              // which time over this stage (default 1)
      "ss_km": 10.46,        // the pass's length, when the results do not give one
      "day": 1, "power_stage": false } ] }
```

The itinerary is the running order. A row whose `stage` names no line in the map is an import warning and is left
out. With no event file (or no SS row that matches), the stages run once each in map order, SS1, SS2..., each its
line's length. A map line the itinerary never runs is a stage with no passes: the menu shows it as "Not run", with
no SS number.

### Results file (`results`)

Only these fields are read; anything else (`status`, an `overall` table, positions, co-drivers, penalties) is
ignored. A crew's rally total is worked out from its stage times (Leaderboards), never read.

```jsonc
{ "stages": [
    { "control": "SS1",       // which itinerary pass this is; else matched by stage + run
      "stage": "Meaford-Mills",   // the map line's name, exactly
      "run": 1, "km": 10.46,  // km: else the itinerary's ss_km
      "cancelled": false,
      "times": [ { "seconds": 399.4,      // a row with no seconds is left out
                   "driver": "...", "car": "199", "class": "L4WD", "championship": "national",
                   "notional": false } ] } ] }   // notional: a time given, not driven (Leaderboards)
```

A results stage whose `stage` names no line in the map is an import warning and is left out. With no `results`,
there are no leaderboards.

**Names join exactly.** An itinerary or results `stage` is matched to a map line by its exact name. (The boards file
the mod writes names each pass by the stage's id; when reading one, a pass also matches a stage whose name equals it
trimmed and case folded.)

## Stage (`kind: "stage"`)

A rally of one stage: `id`, `name`, `map` or `line`, `event`, `results` (that stage's passes), `cover`, `logo`,
`photo`, `rules`. A `map` should hold one line: more is an import warning, and the first is used.

Instead of a map, a stage can be given as points:

```jsonc
{ "format": 1, "kind": "stage", "name": "Kilo Hill",
  "line": [[60.0, -10.0, 100], [60.00045, -10.0, 101], ...],  // [lat, lon, alt?] in driving order; overrides map. alt is not used yet
  "controls": { "atc": { "lat": ..., "lon": ... }, "start": { ... }, "ff": { ... }, "stop": { ... } } }   // each optional
```

The line is imported exactly as a map's line would be, with each control matched onto it as a map's named points
are. Fewer than two points, or a point that is not `[lat, lon]`, is refused.

## Rules

Numbers the game can use, not text. Every field optional; a missing one is not shown. Read from the manifests only:
the season's, then the round's, then the rally (or stage) manifest's, each later one overriding a field at a time.

```jsonc
"rules": {
  "falseStartS": [10, 60, 180],     // 1st, 2nd, 3rd offence
  "lateSPerMin": 10,                // late at a time control, per minute or part
  "earlySPerMin": 60,               // early at a time control
  "maxLatenessMin": 30,             // per leg (ARA: per day), before retirement
  "startIntervalMin": 2
}
```

The Rules tab shows at most these five, one short line each (all five: the user, 2026-11-14). The ARA pack
carries the four its events state, at season level. The game does not apply them yet: its jump start is a
fixed 10 s (`runner.JUMP_START_PENALTY_S`), and the tab marks a rule "in game" only where the two agree.

## Ids

Ids key the player's times (`results/<rallyId>__<stageId>.json`), so an organiser's edit to a pack must not move
them.

- **Season**: its manifest's `id` (slugged); else the id this pack had at its last import; else the id of a pack
  gone from the folder in the same scan with a season of the same name (a renamed zip or folder takes its old ids);
  else a slug of its name.
- **Round**: its own `id`; else the id recorded for that round at the last import, found by its map's path inside
  the pack (case folded: a `map.kml` in every round's folder does not hand the ids out by position; two rounds on one
  map are told apart by their names), then by its name; else `<seasonId>-<slug of its name>` (`<seasonId>-round`
  when the name slugs to nothing), never an id this season gave another round before.
- **Rally or stage pack**: its `id`; else the one this pack (or a renamed one, as for a season) had; else a slug of
  its name.
- An id another import already has is an import warning, and the next free one (`x-2`, `x-3`...) is used. So is an
  id whose rally is still on this computer from another pack (one taken out of the folder keeps its rallies) or from
  a loose map. A pack that fails to import keeps the ids it had, for when it is put right: a renamed pack, the ids it
  took from its old name.
- **Stage ids** inside a rally are slugs of the line name, as for a loose map.

## What the mod writes from a pack (internal, not part of the format)

- `earthRally/events/<rallyId>.json`: as today (format 1), plus `season` `{ id, name, round }` when it came from a
  season, `dates`, `place`, `itinerary` `[{ ss, stage, run, km, cancelled, day, powerStage }]`, `rules`, `media`
  `{ cover, logo, photo }`, `boards` (a boards file name, or missing), and `pack` `{ file, fingerprint }`. A round
  its season no longer lists (taken out, or its id changed) is kept with `retired` `{ season, date }`: not shown on
  the Rallies page, its times kept; put back under its id, it is written afresh.
- `earthRally/seasons/<seasonId>.json`: `{ format: 1, id, name, championship, rounds: [rallyId...], standings }`.
  When a season's id changes, the file under the old id is removed.
- `earthRally/results/<rallyId>__<stageId>.json`: each finished run also records the line it was driven on:
  `line` (`recce` / `matched`), `lineKey` (that line in short: kind, point count, first, middle and last points)
  and `lineM` (start to flying finish on it, as timed). Times saved before that have none.
- `earthRally/boards/<rallyId>.json`: the results, trimmed: `{ format: 1, fingerprint, passes: [{ ss, stage, run,
  km, cancelled, field: [[seconds, driver, car, class, championship, notional]...] }] }`, fastest first. Removed
  when the pack no longer names results.
- Images: copied to `earthRally/media/<rallyId>/<cover|logo|photo>.<ext>`; a re-import first removes the ones the
  last import copied. The menu loads them with `?v=` and the pack's fingerprint, so a changed picture is not taken
  from the page's cache. Whether the menu can load from there is still to be checked in game (`menu.mediaUrl`).
- A pack is imported again only when it changed: its size and modification time first, then (when those moved, or
  the game gives none) its bytes. For a folder, that is the manifest and every file it names. `__MACOSX`, dot files,
  `Thumbs.db` and `desktop.ini` (any case) are not part of a pack.

## Leaderboards and standings (what is computed, and the rules for it)

- **A stage's leaderboard** is one pass's field: every crew with a time on it, `notional` ones left out, fastest
  first. Your best time on that stage is placed into it ("14th of 40, +32.1 s to the fastest"). A cancelled pass has
  no leaderboard.
- **On the rally page**, a stage run twice shows once, and its Place is the better of your placings on its passes
  (the user, 2026-11-14). The leaderboard on the stage page has a toggle between passes.
- **The stage you drive against the stage as run** (the user, 2026-11-14): a stage's length is measured on the line
  you are timed on, start to flying finish: the recce or the matched line, whichever the stage runs on (a control
  more than 200 m off that line is taken as its end; start and finish less than 100 m apart along it, the whole
  line). With no such line, the map's: start to flying finish when both controls are on it, else the whole line.
  More than 5% off a pass's `km` is a line mismatch: that pass's field is shown but you are not placed in it ("Your
  line is 12.0 km start to finish; the official distance is 10.5 km").
- **Which of your times count**: each time records the line it was driven on. Only your best on the line the stage
  runs on now is placed on leaderboards and counted in rally results; a time driven on another line (a recce driven
  again, a stage matched again, a reset) still shows in your runs and their best. A time saved before times recorded
  their line is taken as driven on the current one.
- **Your rally result** is over the comparable passes: the counted ones (not cancelled) whose stage is not a line
  mismatch. When you have a time on every stage with a comparable pass, your total is the sum of your best time on
  each, once per comparable pass. A real crew's total is the sum of its times over the same passes (notional
  included: they are the official times); a crew missing any of them is not ranked. The result is **ranked** when
  the comparable passes cover at least 75% of the rally's counted km ("Ranked over 14 of 16 stages (271 of 279
  km)." when some are left out, naming the ones that don't match the official distance). Below that it is shown but
  **not ranked**: no place, and no points for you ("Not ranked: only 6 of 20 stages match the
  stages as run (a recce may fix this).").
- **Season standings**: the real crews' standings never depend on your map or your lines. In every round with
  results, each crew (only those of `standings.championship`) gets `points[position]` by its real ranking over all
  the counted passes (the full rally, notional included), whether or not you are ranked. You get
  `points[position]` by your place in the comparable-stage ranking (your total against the crews' totals over the
  same comparable passes, among that championship's crews), set beside theirs without moving any crew: the crews
  below you do not drop a place for points. In a round that is not ranked (under 75% of its km) you score nothing
  ("NR") and the crews score as usual. Crews are one entry across rounds by driver name (trimmed, case folded). Ties
  on points: more wins, then more second places, and so on. A round with no results scores nothing, and is still
  listed.
