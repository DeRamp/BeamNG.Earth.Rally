# Make a full rally

A **full rally** is a set of stages driven in order: transits between them, service between loops, one total time.
A **loop** is a group of stages driven between two services. Run the same stages again after service and that's
the second loop.

Any map you drop in can be driven stage by stage. To show up under **Drive rally**, it needs three files in one
folder.

```
Fernvale Rally/        a folder in the import folder
├── rally.json         says "this is a rally" and names the other two
├── map.kml            one line per stage
└── event.json         the running order: which stage when, and where service is
```

The import folder: **Drive stage > Open folder**, or
`%LOCALAPPDATA%\BeamNG\BeamNG.drive\current\earthRally\import\`.

## 1. The map

Draw one **line per stage** in [Google My Maps](https://www.google.com/mymaps), in the driving direction, and give
each one a name: `Fernvale South`, `Fernvale North`. A stage you drive twice is drawn **once**.

* Start and flying-finish points are optional; see [[Make your own stage map]].
* Export with **Export to KML/KMZ**: choose the whole map, tick **Export to a .KML file**, and leave **Keep data
  up to date** off. A network-link KML holds no lines.
* Keep the words `service`, `regroup`, `area`, `finish`, `FF` and `flying` out of stage names.

## 2. `rally.json`

```json
{
  "kind": "rally",
  "id": "fernvale-rally",
  "name": "Fernvale Rally",
  "map": "map.kml",
  "event": "event.json"
}
```

Your times are saved against `id`. Once you've set it, don't change it.

## 3. `event.json`: the loops

This is two loops of two stages, with service between:

```json
{
  "locations": [
    { "id": "park", "name": "Fernvale Service Park", "lat": 60.0102, "lon": -10.0451 }
  ],
  "itinerary": [
    { "type": "MTC_OUT", "control": "TC0", "location": "park", "day": 1 },
    { "type": "SS", "control": "SS1", "stage": "Fernvale South", "run": 1, "day": 1 },
    { "type": "SS", "control": "SS2", "stage": "Fernvale North", "run": 1, "day": 1 },
    { "type": "SVC_IN", "control": "A", "location": "park", "day": 1 },
    { "type": "SS", "control": "SS3", "stage": "Fernvale South", "run": 2, "day": 1 },
    { "type": "SS", "control": "SS4", "stage": "Fernvale North", "run": 2, "day": 1 }
  ]
}
```

* **One `SS` row per pass**, top to bottom in running order.
* `type` is `"SS"`, in capitals.
* `control` must be different on every pass: `SS1`, `SS2`, `SS3`... A label used twice is read once, so the second
  loop disappears.
* `stage` is the map line's name, **exactly**, with the same capitals and spaces.
* `run` counts the passes over one stage: `1` the first time, `2` the second.
* **Service**: put an `SVC_IN` (or `SVC_OUT`) row between the loops. Service after the last stage is the finish.
* **More days**: change `day` from `1` to `2` on a pass. An overnight halt goes in before it.
* **Where**: `locations` puts the start and service on the map (`lat` and `lon` are numbers, not text). Without
  them the rally still runs: each transit goes straight to the next stage.
* No comments or trailing commas: JSON that won't read is skipped as a whole.

## 4. Check it in game

1. Drop the folder into the import folder. It's imported at once. If not, press **Re-scan**.
2. Open **Drive stage** and find the rally. Its page should have a **Full rally** bar with **Start the rally**.
3. Open the rally's **Import report** and fix everything it lists.
4. Go back to Home. The rally is now under **Drive rally**.

## It doesn't show up

| What you see | Why | Fix |
|---|---|---|
| The rally isn't on **Drive stage** at all | No manifest was found | Read the **Last import** line under **+ Add**. `rally.json` must be at the top of the folder, and only one manifest per folder. |
| On **Drive stage**, but no **Full rally** bar | The event file wasn't read, or none of its `SS` rows matched a line | Open **Import report**. It says *can't read the event file* (bad JSON or wrong file name) or *no line of that name in the map* (the `stage` names don't match). |
| `rally.json` or `event.json` sit loose in the import folder | Loose JSON files are never read | Put them in a folder with the map. A `.zip` of the folder works too. |
| Only the first loop is there | `control` labels are repeated | Number every pass: `SS1` to `SS8`, not `SS1` to `SS4` twice. |
| Some stages are missing | Their `stage` name doesn't match a line | The **Import report** names each one. Copy the line's name from the map. |
| A map line shows **Not run** | No `SS` row names it | Add a row for it, or leave it out on purpose. |
| A change you made doesn't show | It wasn't imported yet | Press **Re-scan**. |

## A season of rallies

To make a season, put `season.json` at the top instead of `rally.json`, with one round per rally. Each round
takes the same `map` and `event` fields. Real results, rules and pictures are optional extras. The full format
is in [Making stages and rally packs](https://github.com/DeRamp/BeamNG.Earth.Rally/blob/main/docs/making-rally-packs.md).
