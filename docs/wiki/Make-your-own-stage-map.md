# Make your own stage map

Any road on BeamNG.Earth can be a stage. Draw it in [Google My Maps](https://www.google.com/mymaps):

1. Draw a **line** along the stage's roads, in the driving direction. Name it, for example `Maryhill Up`.
2. Add **points** named after it for the controls (table below).
3. **Export to KML** and drop the file in the import folder (**Open folder** on the Rallies page).
4. Open the rally's **Import report** to check each stage's length and controls.

| The point's name contains | Control |
|---|---|
| `Start`, `SS` | start line |
| `FF`, `Flying`, `Finish` | flying finish: the clock stops here |
| `ATC`, `TC` | arrival time control (optional) |
| `Stop` | stop control (optional) |

* For `Maryhill Up`, points `Maryhill Up Start` and `Maryhill Up FF` match it.
* Case, years, version tags and stage numbers are ignored.
* No start point? The stage starts at the line's first point. The smallest file that works is one line per stage.
* Several lines in one file make a rally of several stages.

Radio, medical, marshal and spectator points can be marked too; see [[Stage dressing]].
