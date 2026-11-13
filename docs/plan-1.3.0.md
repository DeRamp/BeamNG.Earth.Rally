# Earth Rally 1.3.0 plan

## Road matching for every player (no Python, no developer tool)

Today a stage runs without a recce only when `tools/match_roads.py` has matched its line to BeamNG.Earth's roads, and
that needs Python and BeamNG.Earth's source. Players who import their own maps get "recce needed" on every stage.

### How

- **Earth Rally Matcher**: a BeamNG.Earth *companion* add-on (docs/ADDONS.md, "Programs beside the game"), made from
  `match_roads.py`: one Python file, installed from BeamNG.Earth's Add-ons page and run by BeamNG.Earth's own Python
  (`BeamNG.Earth --run-addon`), so players need no Python. The packaged app bundles every `server/*.py` module
  (tools/build_app.py), so `mapdata`, `mapcells`, `dem` and `roads` import as they do in the source tree.
- Set to **start with BeamNG.Earth**. It watches `earthRally/events/`; any stage with no file in `earthRally/matched/`
  (or an older one than its event) is matched and written there. A status file (`earthRally/matcher.json`: per stage
  queued / matching / done / failed, with progress) tells the mod what it is doing.
- **In game**, automatic, no button. The stage page shows the matcher's state:

  ```
  Stillwater                     12.4 km
  Line: matching to the roads… (3 of 9 stages)
  ```

  Without the matcher installed, the page says how to install it instead of only "recce needed".
- **Distribution**: a registry entry (kind `companion`, `run: {args: [...]}`, autostart) by pull request to
  BeamNG.Earth's add-on registry, its asset a `.py` in this repo's releases. Until merged: BeamNG.Earth's local list
  (`%LOCALAPPDATA%\beamng-earth\addons\local.json`).

### To find out first

- That a companion run by the packaged app (not the source tree) imports the server's modules.
- The packaged app's download cache folder (the source tree's is `~/.cache/beamng-earth`), so the matcher uses the data
  the player's BeamNG.Earth already downloaded.
- Show the stage-page mock-up to the user before building it.

## Also for later

- Maps that group each stage with its controls in folders (SOFR, and one with points named "ATC 10, 14", "Start",
  "Finish"): read the folders, not only the names.
- Earlier notes: a blank start board after a reschedule, course tape, junction direction signs.
