# 1.6.1 notes: seen during the 1.6.0 screenshot session

Logged, not fixed (the owner is bug testing; the owner decides which go in before the 1.6.0 launch). Found on 2026-11-14 while
driving 1.6.0 through BeamNG's in-game MCP server for the marketing screenshots: Weaver Bend (Overmountain), Maryhill
Up (OTR 2024), Valley of the Gods Eastbound (Colorado).

## 1. A season listed twice after its pack gained an `id`

**Seen:** Rallies showed **ARA Nationals 2026** twice (one "0 of 64 driven", one "5 of 64"). With the second season
file moved aside, its eight rallies showed as loose rallies on Rallies.

**Diagnosis (likely):** `seasons/ara-nationals-2026-2.json` and `events/ara26-*-2.json` are left from an import
before the pack's `season.json` had `"id"`. The importer index (`importIndex.json`) only knows the new ids, so the
old files are orphans and nothing removes them. Any player whose pack changes its ids would see the same.

**Fix to consider:** on import, remove (or move to `events-old/`) season and event files that no index entry owns,
after keeping their times by line key. Check against the owner's data first: the `-2` files carry real driven times.

## 2. Stale message after Auto recce finishes

**Seen:** after **Auto recce** on Valley of the Gods Eastbound finished ("Recce recommended", 85 corners), the line
under the buttons still read "Auto recce of Valley of the Gods Eastbound: checking what map data is missing."

**Diagnosis:** the menu's `message` is set when the press starts and not replaced when the sequence ends.

## 3. Weaver Bend: the line past the flying finish leaves the road

**Seen:** following the stage line from the flying finish toward the stop control took the car onto grass, with
BeamNG's "Please make a U-turn" and the stop control 154 m off. Seen with the script AI on the line, not a driver.

**To check:** whether the matched line after the FF follows the road on this stage, or only the map line does.

## 4. BeamNG's footer draws over the menu's key hints

**Seen:** on every menu page, BeamNG's own bottom bar (version, Navigate / OK / Back) covers the menu's
"Esc Back to the game · Ctrl+Alt+K Open / close Earth Rally" row. Cosmetic; visible in every menu screenshot.

## 5. BeamNG.Earth's server notice in the rally block

**Seen:** on the way to the ATC the rally block carried BeamNG.Earth's "Server OK, some internet data sources not
answering: basemap.nationalmap.gov unreachable ..." for the whole transit, three lines tall. Not ours, but it is in
our block; consider a one-line cut.
