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
works as it is). Everything a manifest names is a path relative to the pack root, with `/` or `\`.

Any field may be missing unless marked **required**. Unknown fields are kept and ignored. A `format` greater than
this reader knows is refused with a message naming both numbers.

## Season (`kind: "season"`)

```jsonc
{
  "format": 1, "kind": "season",
  "id": "ara-nationals-2026",            // optional: else a slug of name. Kept stable: it keys your times.
  "name": "ARA Nationals 2026",          // required
  "championship": "American Rally Association National Championship 2026",
  "rounds": [                            // required, in running order
    { "round": 1, "name": "SnoDrift Rally 2026", "dates": { "from": "2026-02-06", "to": "2026-02-07" },
      "map": "01 SnoDrift Rally 2026.kml",           // required: the stage lines
      "event": "events/01 SnoDrift Rally 2026.json", // itinerary + rules (events/SCHEMA.md in the ARA pack)
      "results": "results/01 SnoDrift Rally 2026.json",
      "cover": "covers/01 ... - cover.png", "logo": "...", "photo": "..." }
    // or { "round": 2, "rally": "round2/rally.json" }  -- a rally manifest of its own
  ],
  "standings": {                         // season standings; this block is optional, with these defaults
    "championship": "national",          // only crews whose results row has this championship score (false or "all": everyone)
    "points": [25, 20, 16, 13, 11, 10, 9, 8, 7, 6, 5, 4, 3, 2, 1],  // by finishing position in each rally
    "best": null                         // count only the best N rounds (null: all)
  },
  "rules": { ... }                       // see Rules: applies to every round unless the round overrides it
}
```

The default points scale is ours (the user, 2026-11-14: "build your own standings table based on the included
events ... just use finishing data"): 15 places deep because these fields are 42 to 97 cars, and the power stage is
ignored for now.

## Rally (`kind: "rally"`, or one round of a season)

The same fields as a season's round, plus `rules`. `map` is required. `event` is an event file as in the ARA pack's
`events/SCHEMA.md`; the mod reads only:

- `itinerary[]` rows with `type: "SS"` (one row per control: when a pass is listed once per class, the first row
  is kept): `control` (SS1...), `stage` (exact line name in the map), `run`, `ss_km`,
  `power_stage`, `day`: the running order, and which pass is which.
- `event.dates`, `event.hq.town` / `.state` (one line under the rally's name).
- `rules` if present (below); the free-text `time_rules` / `penalties` are not read.

`results` is a results file as in the ARA pack:

```jsonc
{ "format": 1, "event": "...", "status": "final",
  "stages": [ { "control": "SS1", "stage": "Meaford-Mills", "run": 1, "km": 10.46, "cancelled": false,
                "times": [ { "pos": 1, "car": "199", "driver": "...", "codriver": "...", "vehicle": "...",
                             "class": "L4WD", "championship": "national", "seconds": 399.4, "penalty_s": 0,
                             "notional": false } ] } ],
  "overall": [ { "pos": 1, "car": "35", "driver": "...", "class": "NA4WD", "championship": "national",
                 "seconds": 7111.1, "result": "classified" } ] }   // "result" may be missing: then classified
```

An `overall` row with no time is left out; rows with a time are classified unless `result` says otherwise.
With no `event`, the stages run in map order as SS1, SS2... With no `results`, there are no leaderboards.

## Stage (`kind: "stage"`)

`{ "format": 1, "kind": "stage", "name": ..., "map": "x.kml", "results": ..., "cover": ... }`: a rally of one
stage. `map` holds one line (more is an import warning, and the first is used). `results` may list that stage's
passes.

## Rules

Numbers the game can use, not text. Every field optional; a missing one is not shown.

```jsonc
"rules": {
  "falseStartS": [10, 60, 180],     // 1st, 2nd, 3rd offence
  "lateSPerMin": 10,                // late at a time control, per minute or part
  "earlySPerMin": 60,               // early at a time control
  "maxLatenessMin": 30,             // per leg (ARA: per day), before retirement
  "startIntervalMin": 2
}
```

The Rules card shows at most these five, one short line each (all five: the user, 2026-11-14). The ARA pack
carries the four its events state, at season level. Today's game uses only `falseStartS[1]`, as the
jump-start penalty; the rest are for the full-rally mode (roadmap: itineraries, late / early penalties).

## Kept for later versions (reserved, read by nothing yet)

So the file does not need a format 2 for them. On a stage (in a map's place, or beside it): `line` (lat / lon / alt
points, for a stage made in game), `heights`, `notes` (pacenotes), `controls` (ATC / start / FF / stop as points).
On a rally: `roadSections` (target times between controls), `service`, `weather`, `timeOfDay`. On a season:
`powerStagePoints`.

## What the mod writes from a pack (internal, not part of the format)

- `earthRally/events/<rallyId>.json`: as today (format 1), plus `season` `{ id, name, round }` when it came from a
  season, `dates`, `place`, `itinerary` `[{ ss, stage, run, km, cancelled }]`, `rules`, `media` `{ cover, logo,
  photo }` (paths the menu can load), `boards` (a boards file name or nil), and `pack` `{ file, fingerprint }`.
- `earthRally/seasons/<seasonId>.json`: `{ format: 1, id, name, championship, rounds: [rallyId...], standings }`.
- `earthRally/boards/<rallyId>.json`: the results, trimmed: `{ format: 1, fingerprint, passes: [{ ss, stage, run,
  km, cancelled, field: [[seconds, driver, car, class, championship, notional]...] }], overall: [[seconds, driver,
  car, class, championship, classified]...] }`. Fastest first.
- Images: copied to a place the menu can load (where is settled by an in-game check: see the plan).

**Stage ids** inside a pack-made rally are slugs of the line name exactly as today, so a later re-import keeps them;
the rally id is `<seasonId>-r<round>` for a round, the manifest's `id` or a slug of its name otherwise.

## Leaderboards and standings (what is computed, and the rules for it)

- **A stage's leaderboard** is one pass's field: every crew with a time on it, `notional` ones left out, fastest
  first. Your best time on that stage is placed into it ("14th of 40, +32.1 s to the fastest"). A cancelled pass has
  no leaderboard.
- **On the rally page**, a stage run twice shows once, and its Place is the better of your placings on its passes
  (the user, 2026-11-14). The leaderboard on the stage page has a toggle between passes.
- **No placing when the line is not the stage that was run**: if the map line's length differs from the results'
  `km` by more than 5%, the field is shown but you are not placed in it ("This map's line is not the stage as run").
- **Your rally result**: when you have a time on every stage that has a counted pass (not cancelled), your total
  is the sum of your best time on each stage, once per counted pass. A real crew's total is the sum of its times
  over the same passes (notional included: they are the official times); a crew missing any of them is not ranked.
- **Season standings**: in each round, the ranked crews (only those of `standings.championship`) and you if your
  rally result exists get `points[position]`. Crews are one entry across rounds by driver name (trimmed, case
  folded). Ties on points: more wins, then more second places, and so on.
